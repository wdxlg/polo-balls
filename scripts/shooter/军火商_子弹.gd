extends Area2D

const LOCAL_SFX = preload("res://scripts/audio/local_positional_sfx.gd")
const WALL_HIT_BURST_SCRIPT = preload("res://scripts/effects/wall_hit_burst.gd")
const PROJECTILE_IMAGE_DIR:String = "res://Images/characters/人物/军火商/弹药"
const BULLET_IMPACT_PERSON:int = 1
const BULLET_IMPACT_HARD:int = 2

# 军火商通用弹丸。枪本体无碰撞；命中由本弹丸每物理帧做 ray query。
# projectile_kind: 0 普通子弹 / 1 火箭弹

@export var Master_name:String = ""
@export var Team:String = ""
@export var projectile_kind:int = 0
@export var damage_amount:float = 10.0
@export var speed:float = 500.0
@export var acceleration:float = 0.0
@export var max_speed:float = 500.0
@export var direction:Vector2 = Vector2.RIGHT
@export var lifetime:float = 5.0
@export var knockback_distance:float = 0.0
@export var knockback_speed:float = 0.0
@export var explosion_radius:float = 0.0
@export var visual_size:float = 5.0

# V80：同一颗军火商通用子弹支持少数角色按实例打开额外规则。
# 默认值全部保持旧军火商行为；伪军只在生成自己的子弹时设置这些参数。
@export var force_friendly_fire:bool = false
@export var friendly_damage_amount:float = -1.0
@export var protected_target_path:String = ""
@export var friendly_root_path:String = ""
@export var max_travel_distance:float = 0.0

var _life_left:float = 0.0
var _exploded:bool = false
var _trail_points:PackedVector2Array = PackedVector2Array()
var _travelled_distance:float = 0.0

@onready var _sprite:Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var _body_visual:Polygon2D = get_node_or_null("BodyVisual") as Polygon2D
@onready var _trail:Line2D = get_node_or_null("Trail") as Line2D


func _ready() -> void:
	add_to_group("AllayExtendedProjectile")
	add_to_group("BattleTransient")
	add_to_group("ArmsDealerProjectile")
	_life_left = maxf(lifetime,0.1)
	if direction.length_squared() <= 0.000001:
		direction = Vector2.RIGHT
	direction = direction.normalized()
	_setup_visual()


func _setup_visual() -> void:
	var texture:Texture2D = _load_projectile_texture()
	if _sprite != null and texture != null:
		_sprite.texture = texture
		# 素材基准统一为本地 +X：火箭弹原图朝左，因此固定水平翻转。
		# 飞向左侧时根节点会旋转约 180°，再用 flip_v 抵消上下倒置。
		_sprite.flip_h = projectile_kind == 1
		_sprite.flip_v = direction.x < 0.0
		var size:Vector2 = texture.get_size()
		var max_dim:float = maxf(size.x,size.y)
		if max_dim > 0.0:
			_sprite.scale = Vector2.ONE * (_projectile_visual_dimension() / max_dim)
		_sprite.visible = true
		if _body_visual != null:
			_body_visual.visible = false
	elif _body_visual != null:
		# 图片丢失时仍保留旧几何图形作为保险，不会出现隐形子弹。
		_body_visual.visible = true
		var radius:float = maxf(visual_size,1.0)
		if projectile_kind == 1:
			_body_visual.polygon = _circle_points(radius,14)
			_body_visual.color = Color(1.0,0.43,0.10,1.0)
		else:
			_body_visual.polygon = PackedVector2Array([
				Vector2(radius * 1.55,0.0),
				Vector2(-radius * 0.75,-radius * 0.55),
				Vector2(-radius * 0.75,radius * 0.55)
			])
			_body_visual.color = Color(1.0,0.92,0.54,1.0)
	if _trail != null:
		_trail.width = maxf(visual_size * (0.50 if projectile_kind == 1 else 0.28),1.0)
		_trail.default_color = Color(1.0,0.58,0.18,0.78) if projectile_kind == 1 else Color(1.0,0.92,0.55,0.48)


func _load_projectile_texture() -> Texture2D:
	var file_name:String = "火箭筒弹.png" if projectile_kind == 1 else "步枪子弹.png"
	var path:String = PROJECTILE_IMAGE_DIR.path_join(file_name)
	# V432 性能：贴图按路径跨实例缓存，不再每颗子弹 ResourceLoader.load()。
	var cached:Variant = _projectile_texture_cache.get(path)
	if cached is Texture2D:
		return cached as Texture2D
	if not ResourceLoader.exists(path):
		return null
	var resource:Resource = ResourceLoader.load(path)
	var texture:Texture2D = resource as Texture2D if resource is Texture2D else null
	if texture != null:
		_projectile_texture_cache[path] = texture
	return texture

static var _projectile_texture_cache:Dictionary = {}


func _projectile_visual_dimension() -> float:
	# visual_size 仍然决定碰撞反馈和不同枪型的相对大小；
	# 图片只把它映射为可读的最大显示尺寸。
	if projectile_kind == 1:
		return clampf(maxf(visual_size,1.0) * 3.4,18.0,38.0)
	return clampf(maxf(visual_size,1.0) * 3.2,10.0,24.0)


func _physics_process(delta:float) -> void:
	_update_trail_visual()
	if not is_multiplayer_authority() or _exploded:
		return

	var master:ball = _resolve_master()
	if master == null or not is_instance_valid(master) or master.health <= 0:
		Game.free_node(self)
		return

	_life_left -= delta
	if _life_left <= 0.0:
		if projectile_kind == 1:
			_explode(global_position)
		else:
			Game.free_node(self)
		return

	if acceleration != 0.0:
		speed = move_toward(speed,maxf(max_speed,0.0),absf(acceleration) * delta)

	var start:Vector2 = global_position
	var step_distance:float = maxf(speed,0.0) * delta
	if max_travel_distance > 0.0:
		var remaining:float = maxf(max_travel_distance - _travelled_distance,0.0)
		if remaining <= 0.001:
			Game.free_node(self)
			return
		step_distance = minf(step_distance,remaining)
	var finish:Vector2 = start + direction * step_distance
	if get_tree().has_group("MinecraftAllay") and load("res://scripts/characters/我的世界/allay/capture.gd").sweep(self,start,finish): return
	var hit:Dictionary = _raycast_motion(start,finish)
	if hit.is_empty():
		global_position = finish
		_travelled_distance += step_distance
		if max_travel_distance > 0.0 and _travelled_distance >= max_travel_distance - 0.001:
			Game.free_node(self)
		return

	global_position = hit.get("position",finish)
	_travelled_distance += start.distance_to(global_position)
	var collider = hit.get("collider",null)
	var hit_normal:Vector2 = hit.get("normal",-direction)
	if hit_normal.length_squared() <= 0.000001:
		hit_normal = -direction
	# 非角色实体就是墙/地图地形：无论普通弹还是火箭，都先让墙面出现白色受击线条。
	if not collider is ball:
		_show_wall_hit_burst_everywhere(
			global_position,
			hit_normal,
			maxf(speed,1.0),
			_wall_impact_cross_section(),
			direction
		)
		# 只有“真正的枪械子弹”使用用户提供的子弹撞墙音；火箭属于投射物，不套用。
		if projectile_kind == 0:
			_play_bullet_impact_sfx("子弹打墙",1.0)
	if projectile_kind == 1:
		_explode(global_position)
		return

	if collider is ball:
		var target:ball = collider as ball
		if _can_damage_target(target):
			var impact_result:int = _apply_direct_hit(target)
			if impact_result == BULLET_IMPACT_HARD:
				_play_bullet_impact_sfx("子弹打墙",1.0)
			elif impact_result == BULLET_IMPACT_PERSON:
				_play_bullet_impact_sfx("子弹打人",0.0)
	Game.free_node(self)


func _raycast_motion(start:Vector2,finish:Vector2) -> Dictionary:
	# 只在射线真的先撞到自己/友军时才追加排除项，避免加特林每颗子弹每帧遍历全部角色。
	var exclude:Array[RID] = []
	var master:ball = _resolve_master()
	if master != null and is_instance_valid(master):
		exclude.append(master.get_rid())

	for _pass:int in range(8):
		var query:PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(start,finish,3,exclude)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.hit_from_inside = true
		var hit:Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return {}
		var collider = hit.get("collider",null)
		if _should_pass_through(collider):
			if collider is CollisionObject2D:
				exclude.append((collider as CollisionObject2D).get_rid())
				continue
		return hit
	return {}


func _should_pass_through(collider:Variant) -> bool:
	if not collider is ball:
		return false
	var target:ball = collider as ball
	var master:ball = _resolve_master()
	if master != null and target == master:
		return true
	if _is_protected_target(target):
		return true
	# 友伤强制开启时同阵营也属于真实攻击，所以仍允许 Sans 正常消耗一次闪避。
	if not force_friendly_fire and Team != "" and target.Team != "" and target.Team == Team:
		return true
	# V179：闪避成功后本颗子弹继续原射线路径；不播放撞人/撞墙声，也不被删除。
	if target.has_method("try_full_projectile_dodge") and bool(target.call("try_full_projectile_dodge",self)):
		return true
	return false


func _apply_direct_hit(target:ball) -> int:
	var hit_damage:float = _damage_for_target(target)
	if target.has_method("try_block_projectile_hit") and bool(target.call("try_block_projectile_hit",self,global_position,hit_damage)):
		return BULLET_IMPACT_HARD
	var before_health:float = float(target.health)
	var before_block:float = float(target.block)
	if hit_damage > 0.0:
		target.receive_positional_damage(hit_damage,global_position,false,self)
	var health_loss:float = maxf(before_health - float(target.health),0.0)
	var block_loss:float = maxf(before_block - float(target.block),0.0)
	if health_loss > 0.0:
		var hit_seed:int = Game.battle_rng_seed_or("scripts/shooter/军火商_子弹.gd:hit_seed",int(Time.get_ticks_usec()) ^ int(get_instance_id()) ^ int(target.get_instance_id()))
		target.notify_hit_burst_feedback(
			global_position,
			hit_damage,
			health_loss,
			block_loss,
			_wall_impact_cross_section(),
			hit_seed,
			direction
		)
	if knockback_distance > 0.0:
		var push:Vector2 = direction
		if push.length_squared() <= 0.000001:
			push = target.global_position - global_position
		if push.length_squared() > 0.000001:
			target.apply_knockback(
				push.normalized(), knockback_distance, maxf(knockback_speed,50.0),
				0.30, 0.0,
				{"source":_resolve_master(),"max_wall_bounces":1,"stop_on_character":true}
			)

	# 有 block 消耗（即使同时破盾掉血）都优先使用“被防御/硬表面”声音。
	if block_loss > 0.0 or health_loss <= 0.0:
		return BULLET_IMPACT_HARD
	return BULLET_IMPACT_PERSON


func _explode(position_value:Vector2) -> void:
	if _exploded:
		return
	_exploded = true
	_show_explosion_everywhere(position_value,maxf(explosion_radius,1.0))
	_play_explosion_sfx()

	var radius:float = maxf(explosion_radius,1.0)
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if not _can_damage_target(target):
			continue
		var distance:float = position_value.distance_to(target.global_position)
		if distance > radius:
			continue
		var falloff:float = lerpf(1.0,0.72,clampf(distance / radius,0.0,1.0))
		var dealt:float = damage_amount * falloff
		if target.has_method("try_block_projectile_hit") and bool(target.call("try_block_projectile_hit",self,position_value,dealt)):
			continue
		if dealt > 0.0:
			target.receive_spatial_damage(
				dealt,
				{"shape":"circle","center":position_value,"radius":radius,"source":self},
				false
			)
		if knockback_distance > 0.0:
			var push:Vector2 = target.global_position - position_value
			if push.length_squared() <= 0.000001:
				push = Vector2.RIGHT.rotated(randf_range(0.0,TAU))
			target.apply_knockback(
				push.normalized(),knockback_distance,maxf(knockback_speed,50.0),
				0.34,0.0,
				{"source":_resolve_master(),"max_wall_bounces":1,"stop_on_character":true}
			)
	Game.free_node(self)


func _wall_impact_cross_section() -> float:
	# 军火商弹丸使用 raycast，没有实体碰撞 Shape；用实际绘制尺寸近似撞击横截面。
	# 普通子弹是细三角，火箭是圆形，所以火箭的覆盖自然更宽。
	if projectile_kind == 1:
		return clampf(maxf(visual_size,1.0) * 2.0,2.0,32.0)
	return clampf(maxf(visual_size,1.0) * 1.10,2.0,14.0)


func _show_wall_hit_burst_everywhere(
	impact_position:Vector2,
	surface_normal:Vector2,
	impact_power:float,
	impact_width:float,
	incoming_direction:Vector2
) -> void:
	var seed:int = randi()
	var incoming:Vector2 = incoming_direction.normalized() if incoming_direction.length_squared() > 0.000001 else -surface_normal.normalized()
	if multiplayer.has_multiplayer_peer():
		_rpc_show_wall_hit_burst.rpc(impact_position,surface_normal,impact_power,impact_width,seed,incoming)
	else:
		_rpc_show_wall_hit_burst(impact_position,surface_normal,impact_power,impact_width,seed,incoming)


@rpc("authority","call_local","reliable")
func _rpc_show_wall_hit_burst(
	impact_position:Vector2,
	surface_normal:Vector2,
	impact_power:float,
	impact_width:float,
	seed:int,
	incoming_direction:Vector2
) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return
	WALL_HIT_BURST_SCRIPT.spawn(
		world,
		impact_position,
		surface_normal,
		impact_power,
		impact_width,
		seed,
		incoming_direction
	)


func _play_explosion_sfx() -> void:
	var params:Dictionary = {
		"volume": -2.0,
		"pitch": 1.0,
	}
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc("火箭筒爆炸",params,false,true)
	else:
		Audios.play_sfx("火箭筒爆炸",params,false,true)


func _play_bullet_impact_sfx(sfx_name:String,volume_offset:float = 0.0) -> void:
	var params:Dictionary = {
		"volume": volume_offset,
		"pitch": randf_range(0.96,1.05),
	}
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc(sfx_name,params,false,true)
	else:
		Audios.play_sfx(sfx_name,params,false,true)


func _play_local_sfx_everywhere(key:String,position_value:Vector2,volume_db:float,pitch:float,max_distance:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_local_sfx.rpc(key,position_value,volume_db,pitch,max_distance)
	else:
		_rpc_play_local_sfx(key,position_value,volume_db,pitch,max_distance)


@rpc("authority","call_local","unreliable")
func _rpc_play_local_sfx(key:String,position_value:Vector2,volume_db:float,pitch:float,max_distance:float) -> void:
	LOCAL_SFX.play(self,key,position_value,volume_db,pitch,max_distance)


func _can_damage_target(target:ball) -> bool:
	if target == null or not is_instance_valid(target) or target.health <= 0:
		return false
	if force_friendly_fire:
		if target.Type != ball.Ball_Type.Ball and target.Type != ball.Ball_Type.Creature:
			return false
	else:
		if not target.is_combat_targetable():
			return false
	var master:ball = _resolve_master()
	if master != null and target == master:
		return false
	if _is_protected_target(target):
		return false
	if not force_friendly_fire and Team != "" and target.Team != "" and target.Team == Team:
		return false
	return true


func _damage_for_target(target:ball) -> float:
	if force_friendly_fire and _is_forced_friendly_target(target) and friendly_damage_amount >= 0.0:
		return friendly_damage_amount
	return damage_amount


func _is_protected_target(target:ball) -> bool:
	var protected:ball = _resolve_ball_path(protected_target_path)
	return protected != null and target == protected


func _is_forced_friendly_target(target:ball) -> bool:
	if target == null:
		return false
	if Team != "" and target.Team != "" and target.Team == Team:
		return true
	var root:ball = _resolve_ball_path(friendly_root_path)
	if root == null:
		return false
	if target == root:
		return true
	var current:ball = target
	var visited:Dictionary = {}
	for _i:int in range(10):
		if current == null or not is_instance_valid(current):
			break
		var id:int = current.get_instance_id()
		if visited.has(id):
			break
		visited[id] = true
		if current.Master == null or not is_instance_valid(current.Master):
			break
		if current.Master == root:
			return true
		current = current.Master
	return false


func _resolve_ball_path(path_value:String) -> ball:
	if path_value.is_empty():
		return null
	var world:Node = get_tree().current_scene
	if world == null:
		return null
	var resolved:Node = world.get_node_or_null(NodePath(path_value))
	if resolved is ball:
		return resolved as ball
	return null


func _resolve_master() -> ball:
	if Master_name.is_empty():
		return null
	var world:Node = get_tree().current_scene
	if world == null:
		return null
	var resolved:Node = world.get_node_or_null(NodePath(Master_name))
	if resolved is ball:
		return resolved as ball
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if node is ball and str(node.name) == Master_name:
			return node as ball
	return null


func _show_explosion_everywhere(position_value:Vector2,radius:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_show_explosion.rpc(position_value,radius)
	else:
		_rpc_show_explosion(position_value,radius)


@rpc("authority","call_local","reliable")
func _rpc_show_explosion(position_value:Vector2,radius:float) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var ring := Line2D.new()
	ring.closed = true
	ring.width = 5.0
	ring.default_color = Color(1.0,0.43,0.08,0.96)
	ring.z_index = 35
	var points := PackedVector2Array()
	for i:int in range(36):
		var a:float = TAU * float(i) / 36.0
		points.append(Vector2(cos(a),sin(a)) * radius)
	ring.points = points
	ring.global_position = position_value
	ring.scale = Vector2(0.15,0.15)
	world.add_child(ring)
	ring.add_to_group("BattleTransient")
	var tween:Tween = ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring,"scale",Vector2.ONE,0.20)
	tween.tween_property(ring,"modulate",Color(1,1,1,0),0.30)
	tween.finished.connect(ring.queue_free)


func _update_trail_visual() -> void:
	if _trail == null:
		return
	var tail_length:float = 26.0 if projectile_kind == 1 else 13.0
	_trail.points = PackedVector2Array([Vector2.ZERO,Vector2(-tail_length,0.0)])


func _circle_points(radius:float,segments:int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i:int in range(maxi(segments,3)):
		var a:float = TAU * float(i) / float(maxi(segments,3))
		points.append(Vector2(cos(a),sin(a)) * radius)
	return points
