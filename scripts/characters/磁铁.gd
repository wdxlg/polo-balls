extends ball
const PROJECTILE_API = preload("res://classes/projectile_interactions.gd")

const ELECTRIC_BALL_SCENE:PackedScene = preload("res://scenes/shooter/磁铁_电球.tscn")
const PROPERTY_INDEX = preload("res://classes/property_index.gd")

@export_category("磁铁 - 外观")
@export var attraction_texture:Texture2D
@export var repulsion_texture:Texture2D

@export_category("磁极")
@export_range(1.0,10.0,0.1) var polarity_interval:float = 3.4
@export_range(80.0,500.0,5.0) var influence_radius:float = 230.0
@export_range(20.0,180.0,1.0) var orbit_radius:float = 62.0
@export_range(20.0,220.0,1.0) var orbit_capture_radius:float = 88.0
@export_range(0.2,8.0,0.1) var orbit_speed:float = 2.8
# 保留旧 Inspector 字段兼容；新版吸引态会在影响半径内直接捕获，不再靠缓慢转向。
@export_range(0.1,20.0,0.1) var projectile_turn_strength:float = 8.5
@export_range(1.0,5.0,0.05) var release_speed_multiplier:float = 1.25
@export_range(0.0,4000.0,25.0) var repulsion_acceleration:float = 300.0
@export_range(200.0,3000.0,25.0) var repulsion_speed_cap:float = 520.0
@export var polarity_audio:String = "Blue"

@export_category("永久电球")
@export_range(80.0,900.0,10.0) var electric_ball_speed:float = 360.0
@export_range(10.0,120.0,1.0) var electric_ball_spawn_distance:float = 42.0

var _pulling:bool = true
var _polarity_left:float = 0.0
var _orbit_clock:float = 0.0
var _orbiting_projectiles:Dictionary = {}
var _electric_ball:ball = null


func _ready() -> void:
	Has_Collision_Damage = false
	# 磁铁自己不进行普通射击。输出来自永久电球与磁场控制。
	Can_Attack = false
	Can_Skill = false
	super._ready()
	_polarity_left = maxf(polarity_interval,1.0)
	_set_character_texture(attraction_texture)
	_update_side_status()
	if is_multiplayer_authority():
		call_deferred("_ensure_electric_ball")


func has_collision_damage() -> bool:
	return false


func Attack() -> void:
	# 明确禁止旧版本的“没储弹就生成普通子弹 / 有储弹就发射”逻辑。
	Attacking = false


func tick_physics(state:State,delta:float) -> void:
	_orbit_clock += delta
	if is_multiplayer_authority() and state != State.Die and health > 0:
		_update_polarity(delta)
		_update_orbiting_projectiles(delta)
		_apply_magnetic_field(delta)
		_ensure_electric_ball()
	super.tick_physics(state,delta)


func _update_polarity(delta:float) -> void:
	_polarity_left -= delta
	if _polarity_left > 0.0:
		return
	_polarity_left = maxf(polarity_interval,1.0)
	_pulling = not _pulling
	_set_character_texture(attraction_texture if _pulling else repulsion_texture)

	# 由吸引切换成排斥时，把真正被吸住并环绕的投射物全部释放出去。
	if not _pulling:
		_release_all_orbiting_projectiles()

	_update_side_status()
	if polarity_audio != "":
		Audios.play_sfx.rpc(polarity_audio,{},true)


func _set_character_texture(texture:Texture2D) -> void:
	if image is Sprite2D and texture != null:
		(image as Sprite2D).texture = texture


func _apply_magnetic_field(delta:float) -> void:
	var candidates:Dictionary = {}
	for node:Node in PROJECTILE_API.candidates(get_tree()):
		candidates[node.get_instance_id()] = node

	for key:Variant in candidates:
		var projectile:Node = candidates[key]
		if projectile == null or not is_instance_valid(projectile) or projectile == self:
			continue
		# V431 性能：先做最便宜的“是不是 Node2D / 在不在影响半径内”过滤，再做分组与属性判定。
		# 这些判定都没有副作用，顺序调整不改变结果；地图上绝大多数节点都在半径之外。
		if not projectile is Node2D:
			continue
		var projectile_2d:Node2D = projectile as Node2D
		var center_to_projectile:Vector2 = projectile_2d.global_position - global_position
		var distance:float = center_to_projectile.length()
		if distance > influence_radius:
			continue
		var projectile_id:int = projectile.get_instance_id()
		if _orbiting_projectiles.has(projectile_id):
			continue
		if projectile.has_meta("_magnet_orbit_owner") and int(projectile.get_meta("_magnet_orbit_owner",0)) != get_instance_id():
			continue
		if not _is_magnetic_projectile(projectile):
			continue

		if _pulling:
			# 吸引态：进入影响范围就直接吸入轨道。这样高速射线弹、普通 ball 弹、
			# 自己的永久电球都不会因为一帧飞得太远而错过捕获。
			_start_projectile_orbit(projectile)
		else:
			# 排斥态：未被储存的飞行投射物也会立即被向外加速推开。
			_push_projectile_outward(projectile,center_to_projectile,delta)


func _push_projectile_outward(projectile:Node,center_to_projectile:Vector2,delta:float) -> void:
	var outward:Vector2 = center_to_projectile.normalized()
	if outward.length_squared() <= 0.000001:
		outward = Vector2.RIGHT.rotated(_orbit_clock)
	_set_projectile_direction(projectile,outward)
	var current_speed:float = _projectile_speed(projectile)
	var boosted_speed:float = minf(
		maxf(current_speed,80.0) + maxf(repulsion_acceleration,0.0) * delta,
		maxf(repulsion_speed_cap,200.0)
	)
	_set_projectile_speed(projectile,boosted_speed)


func _start_projectile_orbit(projectile:Node) -> void:
	if projectile == null or not is_instance_valid(projectile) or not projectile is Node2D:
		return
	var projectile_id:int = projectile.get_instance_id()
	if _orbiting_projectiles.has(projectile_id):
		return

	var projectile_2d:Node2D = projectile as Node2D
	var radial:Vector2 = projectile_2d.global_position - global_position
	if radial.length_squared() <= 0.000001:
		# 多颗弹同时吸进来时给一个稳定但不同的起始角，避免全部叠在同一点。
		radial = Vector2.from_angle(fmod(float(projectile_id) * 0.61803398875,TAU))
	var angle:float = radial.angle()
	var current_dir:Vector2 = _projectile_direction(projectile)
	var tangent:Vector2 = Vector2(-radial.normalized().y,radial.normalized().x)
	var spin_sign:float = 1.0
	if current_dir.length_squared() > 0.000001 and current_dir.dot(tangent) < 0.0:
		spin_sign = -1.0

	# 关键修复：Area2D 射线弹通常自己在 _physics_process() 中移动，
	# 只停 ball 的 state_machine 并不能让它们真正停下来。
	# 因此同时暂停投射物根节点自身的 physics_process，并在释放时原样恢复。
	var root_was_processing:bool = projectile.is_physics_processing()
	projectile.set_physics_process(false)

	var state_machine_node:Node = projectile.get_node_or_null("state_machine")
	var state_machine_was_processing:bool = false
	if state_machine_node != null:
		state_machine_was_processing = state_machine_node.is_physics_processing()
		state_machine_node.set_physics_process(false)

	var hit_area:Area2D = projectile.get_node_or_null("hitbox") as Area2D
	var hit_was_monitoring:bool = false
	if hit_area != null:
		hit_was_monitoring = hit_area.monitoring
		hit_area.set_deferred("monitoring",false)

	# 部分 Area2D 投射物本身就是攻击 Area。储存时也关闭其 monitoring，
	# 防止围着磁铁转的时候继续按原阵营造成伤害。
	var root_area:Area2D = null
	if projectile is Area2D:
		root_area = projectile as Area2D
	var root_area_was_monitoring:bool = false
	if root_area != null:
		root_area_was_monitoring = root_area.monitoring
		root_area.set_deferred("monitoring",false)

	var original_speed:float = _projectile_speed(projectile)
	projectile.set_meta("_magnet_orbit_owner",get_instance_id())
	# 只保存 ObjectID，不在 Dictionary 里长期保存 Node 引用。
	# 投射物可能在磁场环绕期间被其它逻辑 queue_free/free；保存对象引用后再 `as Node`
	# 会触发 “Trying to cast a freed object”。ObjectID 可以在使用前先验证。
	_orbiting_projectiles[projectile_id] = {
		"projectile_id": projectile_id,
		"angle": angle,
		"spin_sign": spin_sign,
		"root_processing": root_was_processing,
		"state_machine_id": state_machine_node.get_instance_id() if state_machine_node != null else 0,
		"state_processing": state_machine_was_processing,
		"hit_area_id": hit_area.get_instance_id() if hit_area != null else 0,
		"hit_monitoring": hit_was_monitoring,
		"root_area_id": root_area.get_instance_id() if root_area != null else 0,
		"root_area_monitoring": root_area_was_monitoring,
		"original_speed": original_speed,
	}

	# 无限吸取：Dictionary 不设容量上限；每一颗真实投射物都保留并独立排布。
	var count:int = maxi(_orbiting_projectiles.size(),1)
	var desired_radius:float = maxf(orbit_radius,4.0) + floorf(float(count - 1) / 10.0) * 10.0
	projectile_2d.global_position = global_position + Vector2.from_angle(angle) * desired_radius
	_set_projectile_direction(projectile,Vector2.from_angle(angle + spin_sign * PI * 0.5))
	_set_projectile_speed(projectile,0.0)


func _update_orbiting_projectiles(delta:float) -> void:
	if _orbiting_projectiles.is_empty():
		return

	var stale_ids:Array[int] = []
	var slot:int = 0
	for projectile_id:Variant in _orbiting_projectiles:
		var info:Dictionary = _orbiting_projectiles[projectile_id]
		var projectile:Node = _node_from_instance_id(int(projectile_id))
		if projectile == null or not projectile is Node2D:
			stale_ids.append(int(projectile_id))
			continue

		var spin_sign:float = float(info.get("spin_sign",1.0))
		var angle:float = float(info.get("angle",0.0)) + orbit_speed * spin_sign * delta
		info["angle"] = angle
		_orbiting_projectiles[projectile_id] = info

		# 每 10 颗向外增加一圈，数量无上限时也不会全部挤在同一条圆周上。
		var ring:int = int(slot / 10)
		var radius:float = maxf(orbit_radius,4.0) + float(ring) * 10.0
		var projectile_2d:Node2D = projectile as Node2D
		projectile_2d.global_position = global_position + Vector2.from_angle(angle) * radius
		var tangent_dir:Vector2 = Vector2.from_angle(angle + spin_sign * PI * 0.5)
		_set_projectile_direction(projectile,tangent_dir)
		slot += 1

	for stale_id:int in stale_ids:
		_orbiting_projectiles.erase(stale_id)


func _release_all_orbiting_projectiles(accelerate:bool = true) -> void:
	if _orbiting_projectiles.is_empty():
		return

	var ids:Array = _orbiting_projectiles.keys()
	for projectile_id:Variant in ids:
		var info:Dictionary = _orbiting_projectiles.get(projectile_id,{})
		_release_orbiting_projectile(info,accelerate)
	_orbiting_projectiles.clear()


func _release_orbiting_projectile(info:Dictionary,accelerate:bool = true) -> void:
	var projectile_id:int = int(info.get("projectile_id",0))
	var projectile:Node = _node_from_instance_id(projectile_id)
	if projectile == null or not projectile is Node2D:
		return

	var projectile_2d:Node2D = projectile as Node2D
	var outward:Vector2 = projectile_2d.global_position - global_position
	if outward.length_squared() <= 0.000001:
		outward = Vector2.RIGHT.rotated(_orbit_clock)
	outward = outward.normalized()

	# 切换排斥的一刻，从轨道外缘把所有储存投射物高速推出。
	projectile_2d.global_position = global_position + outward * (maxf(orbit_radius,4.0) + 18.0)
	_set_projectile_direction(projectile,outward)
	var original_speed:float = float(info.get("original_speed",_projectile_speed(projectile)))
	var launch_speed:float = original_speed
	if accelerate:
		launch_speed = minf(
			maxf(original_speed,160.0) * maxf(release_speed_multiplier,1.0),
			maxf(repulsion_speed_cap,200.0)
		)
	_set_projectile_speed(projectile,launch_speed)
	if projectile.has_meta("_magnet_orbit_owner") and int(projectile.get_meta("_magnet_orbit_owner",0)) == get_instance_id():
		projectile.remove_meta("_magnet_orbit_owner")

	var root_area_node:Node = _node_from_instance_id(int(info.get("root_area_id",0)))
	if root_area_node is Area2D:
		(root_area_node as Area2D).set_deferred("monitoring",bool(info.get("root_area_monitoring",true)))

	var hit_area_node:Node = _node_from_instance_id(int(info.get("hit_area_id",0)))
	if hit_area_node is Area2D:
		(hit_area_node as Area2D).set_deferred("monitoring",bool(info.get("hit_monitoring",true)))

	var state_machine_node:Node = _node_from_instance_id(int(info.get("state_machine_id",0)))
	if state_machine_node != null:
		state_machine_node.set_physics_process(bool(info.get("state_processing",true)))
	projectile.set_physics_process(bool(info.get("root_processing",true)))


func _node_from_instance_id(instance_id_value:int) -> Node:
	# Godot 节点并非 RefCounted；环绕期间它随时可能被其它投射物逻辑释放。
	# 先验证 ObjectID，再取回对象，避免对已经 freed 的 Variant 做类型转换。
	if instance_id_value <= 0 or not is_instance_id_valid(instance_id_value):
		return null
	var object:Object = instance_from_id(instance_id_value)
	if object is Node:
		return object as Node
	return null


func _is_magnetic_projectile(projectile:Node) -> bool:
	return projectile != self and PROJECTILE_API.supports(projectile,"redirect")

func _has_direction_property(projectile:Node) -> bool:
	return PROJECTILE_API.supports(projectile,"redirect")

func _has_speed_property(projectile:Node) -> bool:
	return PROJECTILE_API.supports(projectile,"redirect")

func _projectile_direction(projectile:Node) -> Vector2:
	return PROJECTILE_API.direction_of(projectile)

func _set_projectile_direction(projectile:Node,new_direction:Vector2) -> void:
	PROJECTILE_API.set_direction(projectile,new_direction)

func _projectile_speed(projectile:Node) -> float:
	return PROJECTILE_API.speed_of(projectile)

func _set_projectile_speed(projectile:Node,new_speed:float) -> void:
	PROJECTILE_API.set_speed(projectile,new_speed)

func _object_has_property(object:Object,property_name:String) -> bool:
	# V431 性能：按脚本缓存属性名集合，不再每次 get_property_list()。
	return PROPERTY_INDEX.has_property(object,property_name)


func _ensure_electric_ball() -> void:
	if not is_multiplayer_authority():
		return
	if state_machine != null and state_machine.current_state == State.Die:
		return
	if health <= 0:
		return
	if _electric_ball != null and is_instance_valid(_electric_ball):
		return
	if ELECTRIC_BALL_SCENE == null:
		return

	var world:Node = get_tree().current_scene
	if world == null:
		return
	var new_ball:ball = ELECTRIC_BALL_SCENE.instantiate() as ball
	if new_ball == null:
		return

	var seed_angle:float = (float(Game.battle_rng_seed_or("scripts/characters/磁铁.gd:electric_spawn_angle",int(get_instance_id()))) / 2147483647.0) * TAU
	var spawn_dir:Vector2 = Vector2.from_angle(seed_angle)
	new_ball.Master = self
	new_ball.Master_name = name
	new_ball.Team = Team
	new_ball.Damage = Damage
	new_ball.Speed = maxf(electric_ball_speed,80.0)
	new_ball.direction = spawn_dir
	new_ball.global_position = global_position + spawn_dir * maxf(electric_ball_spawn_distance,16.0)
	new_ball.name = Game.return_random_name(new_ball)
	world.add_child(new_ball,true)
	_electric_ball = new_ball


func _update_side_status() -> void:
	# 磁铁不在角色右侧显示磁极/储弹信息；同时清掉旧版本可能残留的永久条目。
	if not has_method("side_status_remove_permanent"):
		return
	call("side_status_remove_permanent","right","magnet_mode")
	call("side_status_remove_permanent","right","magnet_ammo")


func _cleanup_owned_electric_ball() -> void:
	if _electric_ball != null and is_instance_valid(_electric_ball):
		Game.free_node(_electric_ball)
	_electric_ball = null


func _exit_tree() -> void:
	# 被场景卸载时只恢复投射物原状态，不额外触发“排斥加速”。
	_release_all_orbiting_projectiles(false)
	if is_multiplayer_authority():
		_cleanup_owned_electric_ball()


func Die() -> void:
	if is_multiplayer_authority():
		_release_all_orbiting_projectiles(false)
		_cleanup_owned_electric_ball()
	super()
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(self):
		Game.free_node(self)
