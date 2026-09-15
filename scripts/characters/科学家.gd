extends ball

const PROJECTILE_SCENE := preload("res://scenes/shooter/科学家弹丸.tscn")
const PORTAL_SCRIPT := preload("res://scripts/characters/科学家_传送门.gd")
const ORANGE_PORTAL_TEXTURE:Texture2D = preload("res://Images/characters/人物/科学家/橙色传送.png")
const BLUE_PORTAL_TEXTURE:Texture2D = preload("res://Images/characters/人物/科学家/蓝色传送.png")

@export_category("反弹弹丸")
@export_range(10.0,1500.0,10.0) var projectile_speed:float = 470.0
@export_range(0.1,30.0,0.1) var projectile_lifetime:float = 2.6
@export_range(0.0,10.0,0.1) var portal_extra_lifetime:float = 0.0
@export_range(0.1,60.0,0.1) var projectile_max_lifetime:float = 8.0
@export_range(0.0,300.0,1.0) var projectile_spawn_offset:float = 32.0
@export var shoot_audio:String = "Mp7单发"

@export_category("传送门")
@export_range(0.2,30.0,0.1) var portal_interval:float = 4.0
@export_range(8.0,300.0,1.0) var portal_length:float = 38.0
@export_range(2.0,60.0,1.0) var portal_thickness:float = 5.0
@export_range(4.0,100.0,1.0) var portal_exit_offset:float = 16.0
@export_range(0.05,2.0,0.01) var portal_lock_seconds:float = 0.22
@export var orange_portal_color:Color = Color(1.0,0.42,0.05,0.92)
@export var blue_portal_color:Color = Color(0.1,0.48,1.0,0.92)
@export var portal_audio:String = "Blue"

var _orange_portal:Area2D = null
var _blue_portal:Area2D = null
var _next_portal_is_orange:bool = true
var _portal_loop_running:bool = false
var _portal_map_name:String = ""
var _last_controlled_portal_msec:int = -1000000000


func _ready() -> void:
	# 门由自己的循环放置，不走基础 Skill 状态；攻击条件在 get_next_state 里额外要求“场上已有门”。
	Can_Skill = false
	super._ready()
	if is_multiplayer_authority():
		call_deferred("_portal_loop")


func get_next_state(state:State) -> int:
	if not is_multiplayer_authority():
		return -1

	if health <= 0 and Type != Ball_Type.Creature:
		if state != State.Die:
			return State.Die
		return -1

	if dizziness:
		return -1

	# V129：直接控制时统一交回 ball 的“只响应玩家鼠标、不自动起手”状态逻辑。
	# 本角色仍可在玩家点击后执行自己的 Attack()/Skill()，这里只阻止自定义 AI 冷却分支抢先出招。
	if is_player_controlled():
		return super.get_next_state(state)

	# 科学家自定义攻击条件没有经过父类 get_next_state，因此这里显式接入统一开战闸门。
	if not is_combat_runtime_active():
		return super.get_next_state(state)

	if Attacking and state != State.Attack:
		return State.Attack

	# 科学家只有场上至少存在一个自己的传送门时才允许攻击。
	if (
		Can_Attack
		and not Attacking
		and state_machine.last_state_dis.Attack >= Attack_Cooling
		and _nearest_portal() != null
	):
		return State.Attack

	match state:
		State.Move:
			if Speed <= 0:
				return State.Stand
		State.Stand:
			if Speed > 0:
				return State.Move
		State.Attack:
			if not Attacking:
				return State.Stand
		State.Hurt:
			if hurting_timer.is_stopped():
				return State.Stand
	return -1


func Attack() -> void:
	super()
	if state_machine.current_state == State.Die or not is_multiplayer_authority():
		return

	# AI 核心规则仍是向最近传送门射；直接控制时则完全交给鼠标方向，且不要求场上已有传送门。
	var portal:Area2D = _nearest_portal()
	if portal == null and not has_player_control_aim():
		Attacking = false
		return

	var dir:Vector2 = player_control_aim_direction(direction) if has_player_control_aim() else (portal.global_position - global_position)
	if dir.length_squared() <= 0.000001:
		dir = direction if direction.length_squared() > 0.000001 else Vector2.RIGHT
	dir = dir.normalized()

	var projectile:ball = PROJECTILE_SCENE.instantiate()
	projectile.Master = self
	projectile.Master_name = name
	projectile.Team = Team
	projectile.Target_Enemy = null if has_player_control_aim() else Nearest_Enemy
	projectile.Damage = Damage
	projectile.Speed = projectile_speed
	projectile.direction = dir
	projectile.global_position = global_position + dir * projectile_spawn_offset
	projectile.global_rotation = projectile.Default_Rotation + dir.angle()
	projectile.set("lifetime",projectile_lifetime)
	projectile.set("portal_extra_lifetime",portal_extra_lifetime)
	projectile.set("max_total_lifetime",projectile_max_lifetime)
	projectile.name = Game.return_random_name(projectile)
	get_tree().current_scene.add_child(projectile,true)

	if shoot_audio != "":
		Audios.play_sfx.rpc(shoot_audio,{},true,true)

	Attacking = true
	await get_tree().create_timer(0.08).timeout
	if is_instance_valid(self):
		Attacking = false


func controlled_skill_action() -> void:
	# V131：直接控制时右键手动放/移动下一扇门；自动 portal loop 暂停。
	if not is_player_controlled() or not is_multiplayer_authority():
		return
	if health <= 0 or state_machine.current_state == State.Die or dizziness or is_damage_output_disabled():
		return
	if not has_player_control_aim():
		return
	var now_msec:int = Time.get_ticks_msec()
	var cooldown_msec:int = int(round(maxf(portal_interval,0.0) * 1000.0))
	if now_msec - _last_controlled_portal_msec < cooldown_msec:
		return
	_last_controlled_portal_msec = now_msec
	_place_or_move_next_portal(player_control_aim_position)


func _portal_loop() -> void:
	if _portal_loop_running:
		return
	_portal_loop_running = true

	# 第一扇门仍然是“开战立即放置”，但布阵/暂停阶段不会提前生成。
	while is_instance_valid(self) and is_inside_tree() and health > 0 and not is_combat_runtime_active():
		await get_tree().process_frame
	if not is_instance_valid(self) or not is_inside_tree() or health <= 0:
		_portal_loop_running = false
		return
	if not is_player_controlled():
		_place_or_move_next_portal()

	while is_instance_valid(self) and is_inside_tree() and health > 0:
		if not (await wait_for_combat_time(maxf(portal_interval,0.2))):
			break
		if not is_instance_valid(self) or not is_inside_tree() or health <= 0:
			break
		if is_combat_runtime_active() and not is_player_controlled():
			_place_or_move_next_portal()

	_portal_loop_running = false


func _place_or_move_next_portal(forced_world_point:Variant = null) -> void:
	if not is_combat_runtime_active():
		return
	var info:Dictionary = _get_current_map_info()
	if info.is_empty():
		return

	var current_map_name:String = str(info["name"])
	if _portal_map_name != "" and _portal_map_name != current_map_name:
		_cleanup_portals()
		_next_portal_is_orange = true
	_portal_map_name = current_map_name

	var rect:Rect2 = info["rect"]
	var other:Area2D = _blue_portal if _next_portal_is_orange else _orange_portal
	var placement:Dictionary
	if forced_world_point is Vector2:
		placement = _wall_placement_near_point(rect,forced_world_point)
	else:
		placement = _roll_wall_placement(rect,other)
	if placement.is_empty():
		return

	var placing_orange:bool = _next_portal_is_orange
	_apply_portal_placement_local(placing_orange,placement,false)
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		_rpc_apply_portal_placement.rpc(placing_orange,placement)

	# 顺序 O -> B -> O -> B，已有两个后自然就是每次移动“更早的那一个”。
	_next_portal_is_orange = not _next_portal_is_orange

	if portal_audio != "":
		Audios.play_sfx.rpc(portal_audio,{},true)


func _create_portal(is_orange:bool,visual_only:bool) -> Area2D:
	var portal:Area2D = PORTAL_SCRIPT.new()
	portal.name = "ScientistPortalOrange" if is_orange else "ScientistPortalBlue"
	var color:Color = orange_portal_color if is_orange else blue_portal_color
	var texture:Texture2D = ORANGE_PORTAL_TEXTURE if is_orange else BLUE_PORTAL_TEXTURE
	# script.new() 门不会被 MultiplayerSpawner 自动复制；各端用确定性名字创建。
	portal.set("visual_only",visual_only)
	portal.set("portal_color",color)
	portal.set("portal_texture",texture)
	get_tree().current_scene.add_child(portal,true)
	return portal


func _apply_portal_placement_local(is_orange:bool,placement:Dictionary,visual_only:bool) -> void:
	var portal:Area2D = _orange_portal if is_orange else _blue_portal
	if portal == null or not is_instance_valid(portal):
		portal = _create_portal(is_orange,visual_only)
		if is_orange:
			_orange_portal = portal
		else:
			_blue_portal = portal
	var color:Color = orange_portal_color if is_orange else blue_portal_color
	_configure_portal(portal,placement,color)
	_pair_portals()


@rpc("authority","call_remote","reliable")
func _rpc_apply_portal_placement(is_orange:bool,placement:Dictionary) -> void:
	_apply_portal_placement_local(is_orange,placement,true)


func _configure_portal(portal:Area2D,placement:Dictionary,color:Color) -> void:
	portal.call(
		"configure_portal",
		placement["position"],
		placement["normal"],
		float(placement.get("length",portal_length)),
		portal_thickness,
		color,
		portal_exit_offset,
		portal_lock_seconds
	)
	portal.set_meta(&"scientist_wall_side",int(placement.get("side",-1)))


func _pair_portals() -> void:
	if _orange_portal == null or _blue_portal == null:
		return
	if not is_instance_valid(_orange_portal) or not is_instance_valid(_blue_portal):
		return
	_orange_portal.set("paired_portal",_blue_portal)
	_blue_portal.set("paired_portal",_orange_portal)


func _nearest_portal() -> Area2D:
	var nearest:Area2D = null
	var nearest_distance_sq:float = INF
	for portal in [_orange_portal,_blue_portal]:
		if portal == null or not is_instance_valid(portal):
			continue
		var distance_sq:float = global_position.distance_squared_to(portal.global_position)
		if distance_sq < nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest = portal
	return nearest


func _get_current_map_info() -> Dictionary:
	var world = get_tree().current_scene
	if world == null or not world.has_method("return_map_world_rect"):
		return {}
	var map_name:String = str(world.now_choose_map)
	if not world.map_group.has(map_name):
		return {}
	var map_node = world.map_group[map_name]
	if not map_node is TileMapLayer:
		return {}
	var rect:Rect2 = world.return_map_world_rect(map_node)
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return {}
	return {"name":map_name,"rect":rect}


func _wall_placement_near_point(rect:Rect2,world_point:Vector2) -> Dictionary:
	# 玩家把鼠标指向地图内任意位置；门吸附到距离鼠标最近的地图墙面，
	# 沿墙方向则尽量保持鼠标对应的位置。
	var distances:PackedFloat32Array = PackedFloat32Array([
		absf(world_point.x - rect.position.x),
		absf(world_point.x - rect.end.x),
		absf(world_point.y - rect.position.y),
		absf(world_point.y - rect.end.y),
	])
	var side:int = 0
	var best:float = distances[0]
	for index:int in range(1,4):
		if distances[index] < best:
			best = distances[index]
			side = index
	var horizontal:bool = side >= 2
	var wall_span:float = rect.size.x if horizontal else rect.size.y
	var max_wall_length:float = maxf(wall_span - 12.0,8.0)
	var usable_length:float = clampf(portal_length,8.0,max_wall_length)
	var half_length:float = usable_length * 0.5
	var inset:float = portal_thickness * 0.5 + 1.0
	var pos:Vector2
	var normal:Vector2
	if side == 0:
		pos = Vector2(rect.position.x + inset,clampf(world_point.y,rect.position.y + half_length,rect.end.y - half_length))
		normal = Vector2.RIGHT
	elif side == 1:
		pos = Vector2(rect.end.x - inset,clampf(world_point.y,rect.position.y + half_length,rect.end.y - half_length))
		normal = Vector2.LEFT
	elif side == 2:
		pos = Vector2(clampf(world_point.x,rect.position.x + half_length,rect.end.x - half_length),rect.position.y + inset)
		normal = Vector2.DOWN
	else:
		pos = Vector2(clampf(world_point.x,rect.position.x + half_length,rect.end.x - half_length),rect.end.y - inset)
		normal = Vector2.UP
	return {
		"position":pos,
		"normal":normal,
		"length":usable_length,
		"side":side,
	}


func _roll_wall_placement(rect:Rect2,other:Area2D) -> Dictionary:
	# 四面墙完全等价地进入候选池。旧版“挑离另一扇门最远的位置”会天然
	# 偏爱对侧墙，在长方形地图上看起来几乎总是左右墙。这里改为：
	# 1. 四面墙各生成相同数量候选；
	# 2. 只过滤与另一扇门过近的点；
	# 3. 从剩余候选随机选择。
	var candidates:Array[Dictionary] = []
	var fractions:Array[float] = [0.16,0.33,0.5,0.67,0.84]

	for side in range(4):
		var horizontal:bool = side >= 2
		var wall_span:float = rect.size.x if horizontal else rect.size.y
		var max_wall_length:float = maxf(wall_span - 12.0,8.0)
		var usable_length:float = clampf(portal_length,8.0,max_wall_length)
		var half_length:float = usable_length * 0.5
		var inset:float = portal_thickness * 0.5 + 1.0

		for fraction in fractions:
			var pos:Vector2
			var normal:Vector2
			if side == 0: # 左墙
				pos = Vector2(rect.position.x + inset,clampf(rect.position.y + rect.size.y * fraction,rect.position.y + half_length,rect.end.y - half_length))
				normal = Vector2.RIGHT
			elif side == 1: # 右墙
				pos = Vector2(rect.end.x - inset,clampf(rect.position.y + rect.size.y * fraction,rect.position.y + half_length,rect.end.y - half_length))
				normal = Vector2.LEFT
			elif side == 2: # 上墙
				pos = Vector2(clampf(rect.position.x + rect.size.x * fraction,rect.position.x + half_length,rect.end.x - half_length),rect.position.y + inset)
				normal = Vector2.DOWN
			else: # 下墙
				pos = Vector2(clampf(rect.position.x + rect.size.x * fraction,rect.position.x + half_length,rect.end.x - half_length),rect.end.y - inset)
				normal = Vector2.UP

			candidates.append({
				"position":pos,
				"normal":normal,
				"length":usable_length,
				"side":side
			})

	if candidates.is_empty():
		return {}

	if other != null and is_instance_valid(other):
		var min_separation:float = maxf(portal_length * 1.25,28.0)
		var filtered:Array[Dictionary] = []
		for candidate in candidates:
			var candidate_position:Vector2 = candidate["position"]
			if candidate_position.distance_to(other.global_position) >= min_separation:
				filtered.append(candidate)
		if not filtered.is_empty():
			candidates = filtered

	return candidates.pick_random()


func _rand_inside(low:float,high:float,margin:float) -> float:
	var a:float = low + margin
	var b:float = high - margin
	if a >= b:
		return (low + high) * 0.5
	return randf_range(a,b)


func _cleanup_portals() -> void:
	if _orange_portal != null and is_instance_valid(_orange_portal):
		_orange_portal.queue_free()
	if _blue_portal != null and is_instance_valid(_blue_portal):
		_blue_portal.queue_free()
	_orange_portal = null
	_blue_portal = null


func _exit_tree() -> void:
	_cleanup_portals()


func Die() -> void:
	super()
	_cleanup_portals()
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(self):
		Game.free_node(self)
