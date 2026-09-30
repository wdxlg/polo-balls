extends Node2D

# ============================================================
# 手动训练控制器
# - 鼠标位置就是一个不可见的“训练攻击者”。
# - 可选鼠标碰撞伤害。
# - 右键从鼠标位置发动当前选择的攻击：有角色时朝最近角色，无角色时按自由瞄准方向。
# - 普通投射物直接复用 res://scenes/shooter 下的真实 PackedScene。
# - 拳击手拳头不是独立场景，因此在这里提供一个与原拳击手近似的固定距离拳击。
# ============================================================

const MOUSE_PROXY_SCENE:PackedScene = preload("res://scenes/ball.tscn")
const WALL_HIT_BURST_SCRIPT = preload("res://scripts/effects/wall_hit_burst.gd")
const CURRENT_BLOOD_SCRIPT = preload("res://scripts/effects/若叶睦_击杀血液.gd")
const MANUAL_TEAM:String = "__MANUAL_TRAINING__"
const BOXER_FIST_TEXTURE_PATH:String = "res://Images/characters/人物/拳击手/拳头.png"
const BLOOD_RENDER_Z:int = -2 # V189：相对 World 最终约 z=-4，与地图表面层对齐，绝不盖住人物/普通投射物
const BLOOD_DROP_SFX = [
	preload("res://audio/sfx/combat/血滴1.mp3"),
	preload("res://audio/sfx/combat/血滴2.mp3"),
	preload("res://audio/sfx/combat/血滴3.mp3"),
	preload("res://audio/sfx/combat/血滴4.mp3"),
]

@export_category("鼠标碰撞伤害")
@export_range(4.0,80.0,1.0) var collision_radius:float = 18.0
@export_range(0.0,500.0,1.0) var collision_damage:float = 20.0
@export_range(0.02,1.0,0.01) var collision_damage_interval:float = 0.18

@export_category("拳击手拳头")
@export_range(8.0,120.0,1.0) var boxer_fist_reach:float = 45.0
@export_range(4.0,60.0,1.0) var boxer_fist_half_width:float = 20.0
@export_range(0.01,0.30,0.01) var boxer_fist_hit_delay:float = 0.065
@export_range(0.0,500.0,1.0) var boxer_fist_damage:float = 20.0
@export_range(0.02,0.5,0.01) var boxer_fist_visual_duration:float = 0.14

@export_category("血液测试")
@export_range(120.0,1600.0,10.0) var blood_forward_speed:float = 650.0
@export_range(0.0,1200.0,10.0) var blood_forward_deceleration:float = 480.0
@export_range(0.15,0.80,0.01) var blood_min_forward_speed_ratio:float = 0.40
@export_range(40.0,520.0,10.0) var blood_upward_speed:float = 230.0
@export_range(80.0,1200.0,10.0) var blood_gravity:float = 540.0
@export_range(0.0,0.40,0.01) var blood_height_scale_bonus:float = 0.18
@export_range(2.0,18.0,0.5) var blood_projectile_size:float = 6.0
@export_range(0.0,0.60,0.01) var blood_midflight_drop_chance:float = 0.28
@export_range(0.05,0.60,0.01) var blood_midflight_drop_min_time:float = 0.14
@export_range(0.05,0.80,0.01) var blood_midflight_drop_max_time:float = 0.34
@export_range(0.0,0.40,0.01) var blood_motion_stretch_bonus:float = 0.22
@export_range(6.0,40.0,0.5) var blood_projectile_trail_length:float = 18.0
@export_range(4.0,48.0,0.5) var blood_ground_splat_radius:float = 17.0
@export_range(4.0,48.0,0.5) var blood_wall_splat_width:float = 25.0
@export_range(1.0,18.0,0.5) var blood_wall_splat_depth:float = 8.0
@export_range(0.0,16.0,0.5) var blood_wall_surface_inset:float = 1.5
@export_range(1.0,60.0,1.0) var blood_decal_lifetime:float = 24.0

@export_category("调试")
@export var draw_cursor_indicator:bool = true
@export_range(2.0,24.0,0.5) var cursor_indicator_radius:float = 6.0
@export_range(8.0,48.0,1.0) var aim_arrow_length:float = 22.0
@export_range(1.0,30.0,0.5) var aim_smoothing:float = 14.0
@export_range(0.1,8.0,0.1) var free_aim_mouse_threshold:float = 0.8

var _mouse_proxy:ball = null
var _collision_cooldowns:Dictionary = {}
var _active_fist_threats:Array[Dictionary] = []
var _active_blood_projectiles:Array[Dictionary] = []
var _last_manual_enabled:bool = false
var _attack_repeat_cooldown:float = 0.0
var _smoothed_aim_direction:Vector2 = Vector2.RIGHT
var _fallback_aim_direction:Vector2 = Vector2.RIGHT
var _last_mouse_position:Vector2 = Vector2.ZERO
var _aim_initialized:bool = false
var _last_visual_ticks_msec:int = 0

# 鼠标碰撞伤害开启时，鼠标本身也按 collision_radius 当作一个圆形碰撞体。
# 这里不真正把隐藏代理体打开物理碰撞，而是用 shape query 检测墙面，
# 避免鼠标被墙卡住，同时仍能得到准确的墙面接触点和法线来播放白线。
var _mouse_wall_probe_initialized:bool = false
var _last_mouse_wall_probe_position:Vector2 = Vector2.ZERO
var _last_mouse_wall_probe_ticks_msec:int = 0
var _mouse_wall_contact_id:int = 0
var _last_mouse_wall_burst_ticks_msec:int = 0
var _last_mouse_wall_burst_position:Vector2 = Vector2.ZERO
var _has_last_mouse_wall_burst_position:bool = false


func _ready() -> void:
	add_to_group("ManualTrainingController")
	add_to_group("ManualTrainingThreatProvider")
	z_index = 500
	_last_mouse_position = get_global_mouse_position()
	global_position = _last_mouse_position
	_last_visual_ticks_msec = Time.get_ticks_msec()
	_reset_mouse_wall_probe(global_position)
	queue_redraw()


func _process(_delta:float) -> void:
	if not _manual_enabled():
		return

	# 瞄准平滑使用真实时间，不受训练 10x/32x 的 Engine.time_scale 影响。
	var now_ticks:int = Time.get_ticks_msec()
	var visual_delta:float = 1.0 / 60.0
	if _last_visual_ticks_msec > 0:
		visual_delta = clampf(float(now_ticks - _last_visual_ticks_msec) / 1000.0,0.0,0.05)
	_last_visual_ticks_msec = now_ticks

	# 直接从当前 CanvasItem 获取世界鼠标坐标，避免 Camera2D 缩放/平移后
	# 使用屏幕坐标造成准星和实际发射点错位。
	var mouse_position:Vector2 = get_global_mouse_position()
	var mouse_motion:Vector2 = mouse_position - _last_mouse_position
	_last_mouse_position = mouse_position
	global_position = mouse_position

	var target:ball = _nearest_character(mouse_position)
	var desired:Vector2 = Vector2.ZERO
	if target != null and is_instance_valid(target):
		desired = target.global_position - mouse_position
	elif mouse_motion.length() >= free_aim_mouse_threshold:
		# 空场景没有目标时，用最近的鼠标移动方向作为自由瞄准方向。
		# 鼠标停下后保留最后方向，因此仍然能持续发射。
		_fallback_aim_direction = mouse_motion.normalized()
		desired = _fallback_aim_direction
	else:
		desired = _fallback_aim_direction

	if desired.length_squared() > 0.000001:
		desired = desired.normalized()
		if not _aim_initialized:
			_smoothed_aim_direction = desired
			_aim_initialized = true
		else:
			var weight:float = 1.0 - exp(-maxf(aim_smoothing,0.01) * visual_delta)
			var angle_value:float = lerp_angle(_smoothed_aim_direction.angle(),desired.angle(),clampf(weight,0.0,1.0))
			_smoothed_aim_direction = Vector2.RIGHT.rotated(angle_value)

	queue_redraw()


func _exit_tree() -> void:
	_destroy_mouse_proxy()
	_clear_active_blood_projectiles()
	_active_fist_threats.clear()


func _physics_process(delta:float) -> void:
	var enabled:bool = _manual_enabled()
	if enabled != _last_manual_enabled:
		_last_manual_enabled = enabled
		queue_redraw()
		if enabled:
			_last_mouse_position = get_global_mouse_position()
			global_position = _last_mouse_position
			_last_visual_ticks_msec = Time.get_ticks_msec()
			_aim_initialized = false
			_reset_mouse_wall_probe(global_position)
		else:
			_active_fist_threats.clear()
			_clear_active_blood_projectiles()
			_collision_cooldowns.clear()
			_attack_repeat_cooldown = 0.0
			_reset_mouse_wall_probe(global_position)

	if not enabled:
		visible = false
		return

	visible = true
	# _process() 负责每个渲染帧更新准星与平滑瞄准；物理帧只处理碰撞/发射。
	# 第一次物理帧早于 _process 时，仍用当前全局鼠标位置兜底。
	if not _aim_initialized:
		global_position = get_global_mouse_position()
	_ensure_mouse_proxy()
	if _mouse_proxy != null and is_instance_valid(_mouse_proxy):
		_mouse_proxy.global_position = global_position

	_tick_collision_cooldowns(delta)
	_tick_fist_threats(delta)
	_tick_blood_projectiles(delta)
	_process_held_attack(delta)

	var mouse_collision_enabled:bool = bool(Game.Game_Settings.get("Manual_Collision_Damage", false)) and Game.mouse_in_map
	if mouse_collision_enabled:
		_process_mouse_wall_contact_feedback(delta)
		_process_cursor_collision_damage()
	else:
		# 关闭鼠标碰撞伤害或离开地图后清掉接触状态。
		# 这样下一次重新开启/重新进入地图并压在墙上时，会正常产生一次撞墙白线。
		_reset_mouse_wall_probe(global_position)


func _draw() -> void:
	if not draw_cursor_indicator or not _manual_enabled():
		return
	var radius:float = maxf(cursor_indicator_radius,2.0)
	var cursor_color:= Color(1.0,0.42,0.32,0.92)
	draw_circle(Vector2.ZERO,radius,Color(1.0,0.25,0.20,0.07),true)
	draw_circle(Vector2.ZERO,radius,cursor_color,false,1.0)
	var arm:float = radius + 2.5
	draw_line(Vector2(-arm,0.0),Vector2(-radius * 0.45,0.0),cursor_color,1.0)
	draw_line(Vector2(radius * 0.45,0.0),Vector2(arm,0.0),cursor_color,1.0)
	draw_line(Vector2(0.0,-arm),Vector2(0.0,-radius * 0.45),cursor_color,1.0)
	draw_line(Vector2(0.0,radius * 0.45),Vector2(0.0,arm),cursor_color,1.0)

	# 瞄准箭头显示“下一发实际使用的方向”。
	var aim_dir:Vector2 = _smoothed_aim_direction
	if aim_dir.length_squared() <= 0.000001:
		aim_dir = Vector2.RIGHT
	aim_dir = aim_dir.normalized()
	var arrow_start:Vector2 = aim_dir * (radius + 4.0)
	var arrow_end:Vector2 = aim_dir * (radius + 4.0 + maxf(aim_arrow_length,8.0))
	var arrow_color:= Color(1.0,0.86,0.45,0.92)
	draw_line(arrow_start,arrow_end,arrow_color,1.35,true)
	var side:Vector2 = Vector2(-aim_dir.y,aim_dir.x)
	var head_len:float = 5.5
	var head_half:float = 3.2
	var arrow_head:= PackedVector2Array([
		arrow_end,
		arrow_end - aim_dir * head_len + side * head_half,
		arrow_end - aim_dir * head_len - side * head_half,
	])
	draw_colored_polygon(arrow_head,arrow_color)


func _process_held_attack(delta:float) -> void:
	if not Game.mouse_in_map or not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		# 松开后下一次点击立即开火，而不是继续等上一轮冷却。
		_attack_repeat_cooldown = 0.0
		return

	_attack_repeat_cooldown -= delta
	if _attack_repeat_cooldown > 0.0:
		return

	request_attack(get_global_mouse_position())
	_attack_repeat_cooldown = maxf(Game.get_manual_training_attack_interval(), 0.02)


func request_attack(origin:Vector2) -> void:
	if not _manual_enabled() or not Game.mouse_in_map:
		return

	var target:ball = _nearest_character(origin)
	var fire_direction:Vector2 = _smoothed_aim_direction
	if target != null and is_instance_valid(target):
		var toward_target:Vector2 = target.global_position - origin
		if toward_target.length_squared() > 0.000001:
			# 箭头已经平滑朝目标旋转；真正发射也使用箭头方向，确保视觉与弹道一致。
			fire_direction = _smoothed_aim_direction
	if fire_direction.length_squared() <= 0.000001:
		fire_direction = _fallback_aim_direction
	if fire_direction.length_squared() <= 0.000001:
		fire_direction = Vector2.RIGHT
	fire_direction = fire_direction.normalized()

	var attack_id:String = Game.get_manual_training_attack()
	var selected:Dictionary = _find_attack_entry(attack_id)
	if selected.is_empty():
		return

	var kind:String = str(selected.get("kind", "scene"))
	if kind == "boxer_fist":
		_fire_boxer_fist(origin,target,fire_direction)
		return
	if kind == "blood":
		_fire_blood(origin,fire_direction)
		return

	var path:String = str(selected.get("path", ""))
	if not path.is_empty():
		_spawn_attack_scene(path,origin,target,fire_direction)


func get_active_manual_melee_threats(_receiver:ball = null) -> Array[Dictionary]:
	var result:Array[Dictionary] = []
	for info:Dictionary in _active_fist_threats:
		result.append(info.duplicate(true))
	return result


func _manual_enabled() -> bool:
	# 手动训练现在是 World 的独立工具，不再要求同时开启“训练模式”。
	return bool(Game.Game_Settings.get("Manual_Training",false))


func _nearest_character(origin:Vector2) -> ball:
	var best:ball = null
	var best_distance_sq:float = INF
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var candidate:ball = node as ball
		if candidate == _mouse_proxy:
			continue
		if candidate.Type != ball.Ball_Type.Ball or candidate.health <= 0:
			continue
		var distance_sq:float = origin.distance_squared_to(candidate.global_position)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best = candidate
	return best


func _tick_collision_cooldowns(delta:float) -> void:
	var to_remove:Array[int] = []
	for raw_id:Variant in _collision_cooldowns.keys():
		var id:int = int(raw_id)
		var remaining:float = float(_collision_cooldowns[raw_id]) - delta
		if remaining <= 0.0:
			to_remove.append(id)
		else:
			_collision_cooldowns[raw_id] = remaining
	for id:int in to_remove:
		_collision_cooldowns.erase(id)


func _process_cursor_collision_damage() -> void:
	if collision_damage <= 0.0:
		return
	var radius_sq:float = collision_radius * collision_radius
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if target == _mouse_proxy or target.Type != ball.Ball_Type.Ball or target.health <= 0:
			continue
		if global_position.distance_squared_to(target.global_position) > radius_sq:
			continue
		var target_id:int = target.get_instance_id()
		if _collision_cooldowns.has(target_id):
			continue
		_collision_cooldowns[target_id] = maxf(collision_damage_interval, 0.02)
		target.receive_spatial_damage(
			collision_damage,
			{"shape":"circle","center":global_position,"radius":maxf(collision_radius,1.0),"source":self},
			false
		)


func _process_mouse_wall_contact_feedback(fallback_delta:float) -> void:
	var current_position:Vector2 = global_position
	var now_ticks:int = Time.get_ticks_msec()
	if not _mouse_wall_probe_initialized:
		_reset_mouse_wall_probe(current_position)

	var previous_position:Vector2 = _last_mouse_wall_probe_position
	var motion:Vector2 = current_position - previous_position
	var real_delta:float = maxf(fallback_delta, 0.0001)
	if _last_mouse_wall_probe_ticks_msec > 0:
		var elapsed_msec:int = now_ticks - _last_mouse_wall_probe_ticks_msec
		if elapsed_msec > 0:
			real_delta = clampf(float(elapsed_msec) / 1000.0, 0.001, 0.10)
	var mouse_speed:float = motion.length() / real_delta

	# 先检查当前圆形鼠标碰撞体是否正压在墙上；如果一帧移动很远又越过了墙，
	# 再做一次 swept-circle cast，避免快速甩鼠标时穿过薄墙却没有白线。
	var contact:Dictionary = _find_mouse_wall_overlap(current_position)
	var persistent_contact:bool = not contact.is_empty()
	if contact.is_empty() and motion.length_squared() > 0.000001:
		contact = _sweep_mouse_circle_for_wall(previous_position, motion)

	if contact.is_empty():
		_mouse_wall_contact_id = 0
		_last_mouse_wall_probe_position = current_position
		_last_mouse_wall_probe_ticks_msec = now_ticks
		return

	var collider_id:int = int(contact.get("collider_id", 0))
	var impact_position:Vector2 = contact.get("point", current_position)
	var normal:Vector2 = contact.get("normal", Vector2.ZERO)
	if normal.length_squared() <= 0.000001:
		normal = -motion.normalized() if motion.length_squared() > 0.000001 else Vector2.RIGHT
	normal = normal.normalized()

	var entering_new_wall:bool = collider_id <= 0 or collider_id != _mouse_wall_contact_id
	var repeat_interval_ready:bool = now_ticks - _last_mouse_wall_burst_ticks_msec >= 80
	var repeat_distance:float = maxf(collision_radius * 0.70, 7.0)
	var moved_far_enough:bool = (
		not _has_last_mouse_wall_burst_position
		or impact_position.distance_to(_last_mouse_wall_burst_position) >= repeat_distance
	)
	var moving_into_wall:bool = (
		motion.length_squared() > 0.000001
		and motion.normalized().dot(normal) < -0.08
	)

	# 第一次碰到墙必定播一次；持续沿墙推动时只有移动了足够距离且满足短冷却才补播，
	# 避免鼠标停在墙里时每个 physics frame 都刷满屏白线。
	if entering_new_wall or (persistent_contact and repeat_interval_ready and moved_far_enough and moving_into_wall):
		var impact_speed:float = mouse_speed
		if entering_new_wall:
			# 鼠标原地开启碰撞伤害、此时本来就在墙上，也应该能看到一组轻量反馈。
			impact_speed = maxf(impact_speed, 90.0)
		var incoming_direction:Vector2 = motion.normalized() if motion.length_squared() > 0.000001 else -normal
		_spawn_mouse_wall_burst(impact_position, normal, impact_speed, now_ticks, incoming_direction)

	_mouse_wall_contact_id = collider_id if persistent_contact else 0
	_last_mouse_wall_probe_position = current_position
	_last_mouse_wall_probe_ticks_msec = now_ticks


func _find_mouse_wall_overlap(position:Vector2) -> Dictionary:
	var state:PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var shape:= CircleShape2D.new()
	shape.radius = maxf(collision_radius, 1.0)
	var exclusions:Array[RID] = _mouse_wall_query_exclusions()
	return _get_wall_rest_info(state, shape, position, exclusions)


func _sweep_mouse_circle_for_wall(from_position:Vector2, motion:Vector2) -> Dictionary:
	var state:PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var shape:= CircleShape2D.new()
	shape.radius = maxf(collision_radius, 1.0)
	var exclusions:Array[RID] = _mouse_wall_query_exclusions()

	# cast_motion 会告诉圆形在这段位移里最远能安全走到哪里。
	# 如果最先撞到的是某个非墙实体，就把它临时排除后继续找真正的墙。
	for _attempt:int in range(8):
		var query:= PhysicsShapeQueryParameters2D.new()
		query.shape = shape
		query.transform = Transform2D(0.0, from_position)
		query.motion = motion
		query.collide_with_bodies = true
		query.collide_with_areas = false
		query.collision_mask = 0xFFFFFFFF
		query.margin = 0.08
		query.exclude = exclusions

		var fractions:PackedFloat32Array = state.cast_motion(query)
		if fractions.size() < 2 or fractions[0] >= 0.999999:
			return {}

		var safe_fraction:float = clampf(float(fractions[0]), 0.0, 1.0)
		# get_rest_info 只检测“当前重叠”，不会读取 query.motion。
		# 因此从安全位置往碰撞方向推进约 0.75px，让圆形轻微进入接触面后再取 point/normal。
		var probe_step_fraction:float = minf(0.02, maxf(0.75 / maxf(motion.length(), 0.001), 0.0005))
		var probe_fraction:float = clampf(safe_fraction + probe_step_fraction, 0.0, 1.0)
		var probe_position:Vector2 = from_position + motion * probe_fraction
		var rest:Dictionary = _get_nearest_rest_info(state, shape, probe_position, exclusions)
		if rest.is_empty():
			return {}

		var collider:Object = _object_from_collider_id(int(rest.get("collider_id", 0)))
		if _is_wall_like_object(collider):
			return rest

		var rid:RID = rest.get("rid", RID())
		if not rid.is_valid():
			return {}
		exclusions.append(rid)

	return {}


func _get_wall_rest_info(
	state:PhysicsDirectSpaceState2D,
	shape:Shape2D,
	position:Vector2,
	exclusions:Array[RID]
) -> Dictionary:
	# get_rest_info 只返回最近的一个重叠体。为了不让其它非墙静态物件挡住查询，
	# 最多迭代排除 8 个非墙碰撞体，再寻找真正的墙面。
	for _attempt:int in range(8):
		var rest:Dictionary = _get_nearest_rest_info(state, shape, position, exclusions)
		if rest.is_empty():
			return {}
		var collider:Object = _object_from_collider_id(int(rest.get("collider_id", 0)))
		if _is_wall_like_object(collider):
			return rest
		var rid:RID = rest.get("rid", RID())
		if not rid.is_valid():
			return {}
		exclusions.append(rid)
	return {}


func _get_nearest_rest_info(
	state:PhysicsDirectSpaceState2D,
	shape:Shape2D,
	position:Vector2,
	exclusions:Array[RID]
) -> Dictionary:
	var query:= PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, position)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = 0xFFFFFFFF
	query.margin = 0.08
	query.exclude = exclusions
	return state.get_rest_info(query)


func _mouse_wall_query_exclusions() -> Array[RID]:
	# 鼠标碰撞伤害和角色接触伤害已经在 _process_cursor_collision_damage() 单独处理；
	# 墙面查询排除所有 ball，避免人物/投射物抢走墙面的 rest_info。
	var result:Array[RID] = []
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if node is CollisionObject2D and is_instance_valid(node):
			var rid:RID = (node as CollisionObject2D).get_rid()
			if rid.is_valid():
				result.append(rid)
	return result


func _object_from_collider_id(collider_id:int) -> Object:
	if collider_id <= 0 or not is_instance_id_valid(collider_id):
		return null
	return instance_from_id(collider_id)


func _is_wall_like_object(collider:Object) -> bool:
	if collider == null:
		return false
	if collider is ball:
		return false
	if collider is TileMapLayer or collider is StaticBody2D or collider is AnimatableBody2D:
		return true
	if collider.has_meta("wall_hit_surface"):
		return bool(collider.get_meta("wall_hit_surface"))
	return false


func _spawn_mouse_wall_burst(
	impact_position:Vector2,
	surface_normal:Vector2,
	impact_speed:float,
	now_ticks:int,
	incoming_direction:Vector2
) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var normal:Vector2 = surface_normal.normalized() if surface_normal.length_squared() > 0.000001 else Vector2.RIGHT
	# 圆形鼠标碰撞体沿任意墙面切线的横截面都是直径。直接交给与角色撞墙相同的
	# WallHitBurst，数量/长度/扩散继续由现有的“速度 + 碰撞尺寸”规则统一决定。
	var impact_width:float = clampf(maxf(collision_radius, 1.0) * 2.0, 2.0, 96.0)
	var seed:int = Game.battle_rng_seed_or("scripts/training/manual_training_controller.gd:wall_hit_seed",int(get_instance_id()) ^ int(now_ticks * 1103515245))
	WALL_HIT_BURST_SCRIPT.spawn(
		world,
		impact_position,
		normal,
		maxf(impact_speed, 1.0),
		impact_width,
		seed,
		incoming_direction
	)
	_last_mouse_wall_burst_ticks_msec = now_ticks
	_last_mouse_wall_burst_position = impact_position
	_has_last_mouse_wall_burst_position = true


func _reset_mouse_wall_probe(position:Vector2) -> void:
	_mouse_wall_probe_initialized = true
	_last_mouse_wall_probe_position = position
	_last_mouse_wall_probe_ticks_msec = Time.get_ticks_msec()
	_mouse_wall_contact_id = 0
	_has_last_mouse_wall_burst_position = false


func _find_attack_entry(attack_id:String) -> Dictionary:
	for entry:Dictionary in Game.get_manual_attack_catalog():
		if str(entry.get("id", "")) == attack_id:
			return entry
	return {}


func _spawn_attack_scene(path:String,origin:Vector2,target:ball,fire_direction:Vector2) -> void:
	var resource:PackedScene = ResourceLoader.load(path) as PackedScene
	if resource == null:
		push_warning("手动训练：无法加载攻击场景 " + path)
		return

	_ensure_mouse_proxy()
	if _mouse_proxy == null or not is_instance_valid(_mouse_proxy):
		return

	var attack:Node = resource.instantiate()
	if not attack is Node2D:
		attack.free()
		return

	var direction_value:Vector2 = fire_direction
	if direction_value.length_squared() <= 0.000001:
		direction_value = Vector2.RIGHT
	direction_value = direction_value.normalized()
	var has_target:bool = target != null and is_instance_valid(target) and target.health > 0
	var aim_position:Vector2 = target.global_position if has_target else origin + direction_value * 320.0

	# 尽量在 _ready() 之前写入身份/方向，保证真实投射物初始化时就能读到主人和阵营。
	if attack is ball:
		var projectile_ball:ball = attack as ball
		projectile_ball.Master = _mouse_proxy
		projectile_ball.Master_name = str(_mouse_proxy.name)
		projectile_ball.Team = MANUAL_TEAM
		projectile_ball.direction = direction_value
		projectile_ball.Target_Enemy = target if has_target else null
		projectile_ball.Nearest_Enemy = target if has_target else null
	else:
		_set_property_if_exists(attack,"Master",_mouse_proxy)
		_set_property_if_exists(attack,"Master_name",str(_mouse_proxy.name))
		_set_property_if_exists(attack,"Team",MANUAL_TEAM)
		_set_property_if_exists(attack,"direction",direction_value)
		_set_property_if_exists(attack,"Target_Enemy",target if has_target else null)
		_set_property_if_exists(attack,"Nearest_Enemy",target if has_target else null)
		_set_property_if_exists(attack,"target_position",aim_position)

	# 炸弹客炸弹默认是地雷。有目标时沿用“附着最近目标”；空场景则保留地雷语义，
	# 这样不会因为没有 attached_target_name 报错。
	if _has_property(attack,"is_ground") and _has_property(attack,"attached_target_name"):
		if has_target:
			attack.set("is_ground",false)
			attack.set("attached_target_name",str(target.name))
		else:
			attack.set("is_ground",true)

	var world:Node = get_tree().current_scene
	if world == null:
		attack.free()
		return

	world.add_child(attack,true)
	(attack as Node2D).global_position = origin
	attack.add_to_group("ManualTrainingProjectile")
	attack.add_to_group("BattleTransient")
	attack.set_meta("manual_training_projectile",true)
	attack.set_meta("manual_training_radius",_estimate_attack_radius(attack))
	attack.set_meta("manual_training_target_id",target.get_instance_id() if has_target else -1)
	attack.set_meta("manual_training_aim_direction",direction_value)

	# 部分自定义投射物在 _ready 后才建立目标字段，再补一次常见目标属性。
	_set_property_if_exists(attack,"Target_Enemy",target if has_target else null)
	_set_property_if_exists(attack,"Nearest_Enemy",target if has_target else null)
	_set_property_if_exists(attack,"target_position",aim_position)
	_apply_manual_bullet_rotation(attack,path,direction_value)


func _apply_manual_bullet_rotation(attack:Node,path:String,direction_value:Vector2) -> void:
	# 手动训练会复用真实 shooter 场景，但过去只写 direction，没有把真正的枪械子弹根节点转向。
	# 只处理“子弹”，不碰飞刀、酒瓶、扳手、卡牌等其它投射物。
	var file_name:String = path.get_file()
	if file_name not in ["子弹.tscn","军火商_子弹.tscn","猎人_霰弹.tscn"]:
		return
	if not attack is Node2D:
		return
	var dir:Vector2 = direction_value.normalized() if direction_value.length_squared() > 0.000001 else Vector2.RIGHT
	if attack is ball:
		var projectile_ball:ball = attack as ball
		(attack as Node2D).global_rotation = projectile_ball.Default_Rotation + dir.angle()
	else:
		(attack as Node2D).global_rotation = dir.angle()


func _estimate_attack_radius(attack:Node) -> float:
	if attack is ball:
		var projectile:ball = attack as ball
		if projectile.collision_shape_2d != null and projectile.collision_shape_2d.shape != null:
			var shape:Shape2D = projectile.collision_shape_2d.shape
			if shape is CircleShape2D:
				return maxf((shape as CircleShape2D).radius, 4.0)
			if shape is RectangleShape2D:
				return maxf((shape as RectangleShape2D).size.length() * 0.25, 4.0)
	if attack is CollisionObject2D:
		for child:Node in attack.get_children():
			if child is CollisionShape2D and (child as CollisionShape2D).shape != null:
				var shape:Shape2D = (child as CollisionShape2D).shape
				if shape is CircleShape2D:
					return maxf((shape as CircleShape2D).radius, 4.0)
	return 8.0


func _fire_boxer_fist(origin:Vector2,target:ball,fire_direction:Vector2) -> void:
	var attack_dir:Vector2 = fire_direction
	if attack_dir.length_squared() <= 0.000001:
		attack_dir = Vector2.RIGHT
	attack_dir = attack_dir.normalized()

	var threat:Dictionary = {
		"source": self,
		"source_key": "MANUAL_FIST:%d" % Time.get_ticks_usec(),
		"origin": origin,
		"axis": attack_dir,
		"reach": maxf(boxer_fist_reach,8.0),
		"radius": maxf(boxer_fist_half_width,4.0),
		"active_from": maxf(boxer_fist_hit_delay,0.01),
		"active_until": maxf(boxer_fist_hit_delay + 0.10,0.11),
		"time_to_impact": maxf(boxer_fist_hit_delay,0.01),
		"remaining": maxf(boxer_fist_hit_delay + 0.12,0.13),
	}
	_active_fist_threats.append(threat)
	_spawn_boxer_fist_visual(origin,attack_dir)

	# 没有角色时仍然播放/发出拳头；只有存在有效目标时才安排伤害结算。
	if target == null or not is_instance_valid(target):
		return
	var target_id:int = target.get_instance_id()
	var timer:SceneTreeTimer = get_tree().create_timer(maxf(boxer_fist_hit_delay,0.01),false,true)
	timer.timeout.connect(_resolve_boxer_fist_hit.bind(target_id,origin,attack_dir),CONNECT_ONE_SHOT)


func _resolve_boxer_fist_hit(target_id:int, origin:Vector2, attack_dir:Vector2) -> void:
	if not is_instance_id_valid(target_id):
		return
	var object:Object = instance_from_id(target_id)
	if not object is ball:
		return
	var target:ball = object as ball
	if target.health <= 0 or target.Type != ball.Ball_Type.Ball:
		return

	var to_target:Vector2 = target.global_position - origin
	var forward:float = to_target.dot(attack_dir)
	var lateral:float = absf(to_target.cross(attack_dir))
	if forward < -7.0 or forward > boxer_fist_reach:
		return
	if lateral > boxer_fist_half_width:
		return

	if boxer_fist_damage > 0.0:
		target.receive_spatial_damage(
			boxer_fist_damage,
			{
				"shape":"capsule",
				"from":origin - attack_dir * 7.0,
				"to":origin + attack_dir * boxer_fist_reach,
				"half_width":maxf(boxer_fist_half_width,1.0),
				"source":self,
			},
			false
		)


func _spawn_boxer_fist_visual(origin:Vector2, attack_dir:Vector2) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return

	var texture:Texture2D = null
	if ResourceLoader.exists(BOXER_FIST_TEXTURE_PATH):
		texture = ResourceLoader.load(BOXER_FIST_TEXTURE_PATH) as Texture2D

	if texture != null:
		var fist := Sprite2D.new()
		fist.texture = texture
		fist.centered = true
		fist.z_index = 60
		world.add_child(fist)
		fist.add_to_group("BattleTransient")
		var size:Vector2 = texture.get_size()
		var reach:float = maxf(boxer_fist_reach, 8.0)
		fist.global_position = origin + attack_dir * reach * 0.5
		fist.global_rotation = attack_dir.angle()
		fist.scale = Vector2(reach / maxf(size.x, 1.0), maxf(boxer_fist_half_width * 1.4, 8.0) / maxf(size.y, 1.0))
		var tween:Tween = fist.create_tween()
		tween.set_parallel(true)
		tween.tween_property(fist, "modulate:a", 0.0, maxf(boxer_fist_visual_duration, 0.02))
		tween.tween_property(fist, "scale:x", fist.scale.x * 1.12, maxf(boxer_fist_visual_duration, 0.02))
		tween.finished.connect(fist.queue_free)
		return

	var line := Line2D.new()
	line.width = 6.0
	line.default_color = Color(1.0, 0.85, 0.72, 0.95)
	line.points = PackedVector2Array([Vector2.ZERO, attack_dir * boxer_fist_reach])
	line.global_position = origin
	line.z_index = 60
	world.add_child(line)
	line.add_to_group("BattleTransient")
	var tween:Tween = line.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, maxf(boxer_fist_visual_duration, 0.02))
	tween.finished.connect(line.queue_free)


func _tick_fist_threats(delta:float) -> void:
	for index:int in range(_active_fist_threats.size() - 1, -1, -1):
		var info:Dictionary = _active_fist_threats[index]
		var remaining:float = float(info.get("remaining", 0.0)) - delta
		if remaining <= 0.0:
			_active_fist_threats.remove_at(index)
			continue
		info["remaining"] = remaining
		info["active_from"] = maxf(float(info.get("active_from", 0.0)) - delta, 0.0)
		info["active_until"] = maxf(float(info.get("active_until", 0.0)) - delta, 0.0)
		info["time_to_impact"] = maxf(float(info.get("time_to_impact", 0.0)) - delta, 0.0)
		_active_fist_threats[index] = info


# ============================================================
# V181：修正 V180 的 -48 过低绘制层导致血液被世界背景/地形完全盖住的问题；血液改为绝对 Z=-1，
# 保持在人物/普通子弹下方，同时回到世界背景上方可见层。像素阶梯从约 2px 粗块细化到 1px 级。
# 飞行血不再保持固定缩放：随速度/飞行相位轻微沿运动方向拉长（绝不压扁横向厚度），并有小幅整体脉动；
# 一部分血滴会在飞行途中提前转入下坠，落地生成小型像素血迹。V177 的真实接触时机继续保留。
# V177 手动训练：血液运动/命中时机/血迹二次重做
# - 碰撞检测改为“血滴当前屏幕位置 -> 下一屏幕位置”，不再用地面投影提前撞墙。
# - 射线使用血滴前端而不是中心；命中时把血滴中心放到“前端刚好接触表面”的位置，并保留一个物理帧再转成墙血。
# - 飞行血沿真实屏幕速度方向旋转，主体改为前圆后尖的液滴，拖尾只保留少量分裂小滴。
# - 地面血迹使用多血池融合 + 定向拖抹 + 大小差异卫星滴；墙血以真实碰撞点为表面基准，只轻微压入墙内，
#   再叠加贴面飞溅、凝血凸块和沿世界重力方向的流挂，避免“贴纸”或“堆在墙前”。
# ============================================================
func _fire_blood(origin:Vector2, fire_direction:Vector2) -> void:
	var world:Node = get_tree().current_scene
	if world == null: return
	var attack_dir:Vector2 = fire_direction.normalized() if fire_direction.length_squared() > 0.000001 else Vector2.RIGHT
	# 每次随机抽取真实发射器的攻击状态，而不是训练专用的另一套血弹。
	var state:int = randi_range(0,3)
	var context:Dictionary = {"direction":attack_dir}
	var label:String = ""
	match state:
		0:
			label = "小范围穿刺"
			context.merge({"kind":"pierce","speed":randf_range(200.0,340.0),"life_scale":randf_range(0.30,0.42),"cone_scale":0.75,"count":randi_range(6,10)})
		1:
			label = "高速穿刺"
			context.merge({"kind":"pierce","speed":randf_range(550.0,1000.0),"count":randi_range(12,18)})
		2:
			label = "斩击甩血"
			context.merge({"kind":"slash","cone_scale":randf_range(1.0,1.35),"count":randi_range(10,16)})
		_:
			label = "大范围碰撞"
			context.merge({"kind":"crush","cone_scale":randf_range(1.7,2.0),"speed_scale":randf_range(1.3,1.6),"life_scale":1.3,"count":randi_range(16,22)})
	var effect:Node2D = CURRENT_BLOOD_SCRIPT.new()
	world.add_child(effect)
	effect.name = "ManualTrainingCurrentBlood"
	effect.set_meta("blood_preview_state",state)
	effect.set_meta("blood_preview_label",label)
	effect.call("configure",origin,attack_dir,2,int(randi()),7,10.0,randf_range(220.0,300.0),context)


func _tick_blood_projectiles(delta:float) -> void:
	if _active_blood_projectiles.is_empty():
		return
	var step:float = maxf(delta,0.0)
	for index:int in range(_active_blood_projectiles.size() - 1, -1, -1):
		var info:Dictionary = _active_blood_projectiles[index]
		var visual:Node2D = info.get("node") as Node2D
		if visual == null or not is_instance_valid(visual):
			_active_blood_projectiles.remove_at(index)
			continue

		# 已经真实接触障碍物：让飞行血在碰撞点停留至少一个物理帧，再生成贴面血迹。
		var pending_hit:Dictionary = info.get("pending_hit",{})
		if not pending_hit.is_empty():
			var hold:float = float(info.get("impact_hold",0.0)) - step
			if hold <= 0.0:
				_spawn_wall_blood_decal(
					pending_hit.get("position",visual.global_position),
					pending_hit.get("normal",Vector2.LEFT),
					pending_hit.get("collider"),
					info.get("direction",Vector2.RIGHT)
				)
				visual.queue_free()
				_active_blood_projectiles.remove_at(index)
				continue
			info["impact_hold"] = hold
			_active_blood_projectiles[index] = info
			continue

		var previous_ground:Vector2 = info.get("ground_position",visual.global_position)
		var previous_height:float = maxf(float(info.get("height",0.0)),0.0)
		var previous_screen:Vector2 = previous_ground + Vector2(0.0,-previous_height)
		var direction_value:Vector2 = info.get("direction",Vector2.RIGHT)
		if direction_value.length_squared() <= 0.000001:
			direction_value = Vector2.RIGHT
		direction_value = direction_value.normalized()
		# V180：水平速度先快后慢。先用本帧当前速度推进，再向最低速度衰减，
		# 避免一出生就被减速吃掉“爆发感”。
		var forward_speed:float = maxf(float(info.get("forward_speed",blood_forward_speed)),1.0)
		var min_forward_speed:float = maxf(float(info.get("min_forward_speed",forward_speed * 0.40)),1.0)
		var forward_deceleration:float = maxf(float(info.get("forward_deceleration",blood_forward_deceleration)),0.0)
		var age:float = float(info.get("age",0.0)) + step
		info["age"] = age
		var current_vertical_speed:float = float(info.get("vertical_speed",blood_upward_speed))
		var early_drop_after:float = float(info.get("early_drop_after",-1.0))
		if not bool(info.get("early_drop_triggered",false)) and early_drop_after >= 0.0 and age >= early_drop_after:
			info["early_drop_triggered"] = true
			current_vertical_speed = minf(current_vertical_speed,-float(info.get("early_drop_speed",185.0)))
			forward_speed *= clampf(float(info.get("early_drop_forward_ratio",0.68)),0.45,0.90)
			min_forward_speed = minf(min_forward_speed,forward_speed)
			info["min_forward_speed"] = min_forward_speed
		var next_ground:Vector2 = previous_ground + direction_value * forward_speed * step
		var gravity_value:float = maxf(blood_gravity,1.0)
		var next_height:float = previous_height + current_vertical_speed * step - 0.5 * gravity_value * step * step
		var vertical_speed:float = current_vertical_speed - gravity_value * step
		if next_height < 0.0:
			next_height = 0.0
		var next_screen:Vector2 = next_ground + Vector2(0.0,-next_height)

		# V180：height 除了屏幕抬升，还会让血滴在高处小幅等比放大。碰撞前端也同步放大，
		# 因此墙面接触仍按“视觉前端真正碰到”的时机判断。
		var base_scale:Vector2 = info.get("base_scale",visual.scale)
		var peak_reference:float = maxf(float(info.get("height_peak_reference",1.0)),1.0)
		var height_ratio:float = clampf(next_height / peak_reference,0.0,1.25)
		var height_scale_factor:float = 1.0 + clampf(blood_height_scale_bonus,0.0,0.40) * height_ratio
		var launch_speed:float = maxf(float(info.get("launch_forward_speed",forward_speed)),1.0)
		var speed_ratio:float = clampf(forward_speed / launch_speed,0.0,1.0)
		var phase:float = float(info.get("motion_phase",0.0))
		var flutter:float = 0.5 + 0.5 * sin(age * 18.0 + phase)
		var stretch_strength:float = clampf(float(info.get("motion_stretch_strength",0.12)),0.0,0.40)
		var motion_stretch:float = 1.0 + stretch_strength * (0.45 + 0.55 * speed_ratio) * (0.62 + 0.38 * flutter)
		var size_pulse:float = 1.0 + 0.035 * (0.5 + 0.5 * sin(age * 13.0 + phase * 0.73))
		visual.scale = Vector2(base_scale.x * height_scale_factor * motion_stretch,base_scale.y * height_scale_factor * size_pulse)

		# 关键：检测的是血滴真实屏幕轨迹，而且用“前端”扫过障碍物。这样不会因为 ground_position
		# 的投影先穿过墙，就在血滴视觉还没到墙时提前消失。
		var movement:Vector2 = next_screen - previous_screen
		var velocity_dir:Vector2 = movement.normalized() if movement.length_squared() > 0.000001 else direction_value
		var front_offset:float = maxf(float(info.get("front_offset_base",0.0)) * height_scale_factor * motion_stretch,0.0)
		var ray_from:Vector2 = previous_screen + velocity_dir * front_offset
		var ray_to:Vector2 = next_screen + velocity_dir * front_offset
		var wall_hit:Dictionary = _blood_wall_raycast(ray_from,ray_to)
		if not wall_hit.is_empty():
			var impact_position:Vector2 = wall_hit.get("position",ray_to)
			var _normal:Vector2 = wall_hit.get("normal",-velocity_dir)
			# 把血滴中心退回 front_offset，使前端正好接触碰撞面。
			visual.global_position = impact_position - velocity_dir * front_offset
			visual.global_rotation = velocity_dir.angle()
			info["pending_hit"] = wall_hit
			info["impact_hold"] = maxf(step,1.0 / 120.0)
			_active_blood_projectiles[index] = info
			continue

		info["ground_position"] = next_ground
		info["vertical_speed"] = vertical_speed
		info["height"] = next_height
		var slowed_forward_speed:float = move_toward(forward_speed,min_forward_speed,forward_deceleration * step)
		info["forward_speed"] = slowed_forward_speed
		visual.global_position = next_screen

		# 液滴头部沿实际屏幕速度方向，包括上抛/下落分量。
		var visual_velocity:Vector2 = direction_value * forward_speed + Vector2(0.0,-vertical_speed)
		if visual_velocity.length_squared() > 0.000001:
			visual.global_rotation = visual_velocity.angle()

		if next_height <= 0.0 and vertical_speed < 0.0:
			if bool(info.get("early_drop_triggered",false)):
				_spawn_pixel_ground_drop(next_ground,direction_value)
			else:
				_spawn_ground_blood_decal(next_ground,direction_value)
			visual.queue_free()
			_active_blood_projectiles.remove_at(index)
			continue

		_active_blood_projectiles[index] = info


func _clear_active_blood_projectiles() -> void:
	for info:Dictionary in _active_blood_projectiles:
		var visual:Node = info.get("node") as Node
		if visual != null and is_instance_valid(visual):
			visual.queue_free()
	_active_blood_projectiles.clear()


func _blood_wall_raycast(from_position:Vector2,to_position:Vector2) -> Dictionary:
	if from_position.distance_squared_to(to_position) <= 0.000001:
		return {}
	var state:PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var exclusions:Array[RID] = _mouse_wall_query_exclusions()
	for _attempt:int in range(8):
		var query:= PhysicsRayQueryParameters2D.create(from_position,to_position)
		query.collide_with_bodies = true
		query.collide_with_areas = false
		query.collision_mask = 0xFFFFFFFF
		query.exclude = exclusions
		var hit:Dictionary = state.intersect_ray(query)
		if hit.is_empty():
			return {}
		var collider:Object = hit.get("collider")
		if _is_wall_like_object(collider):
			return hit
		var rid:RID = hit.get("rid",RID())
		if not rid.is_valid():
			return {}
		exclusions.append(rid)
	return {}


func _spawn_pixel_ground_drop(position:Vector2,incoming_direction:Vector2) -> void:
	_play_manual_blood_drop_sfx(position,-15.0)
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var holder:=Node2D.new()
	holder.name = "ManualTrainingBloodPixelDrop"
	holder.z_as_relative = true
	holder.z_index = BLOOD_RENDER_Z
	world.add_child(holder)
	holder.add_to_group("BattleTransient")
	holder.global_position = position
	var direction_value:Vector2 = incoming_direction.normalized() if incoming_direction.length_squared() > 0.000001 else Vector2.RIGHT
	holder.global_rotation = direction_value.angle() + randf_range(-0.18,0.18)
	var unit:float = randf_range(0.75,1.15)
	for i:int in range(randi_range(4,7)):
		var pixel:=Polygon2D.new()
		var half:float = randf_range(0.55,1.25) * unit
		pixel.polygon = _blood_pixel_square_polygon(half)
		pixel.color = Color(0.48 + randf_range(-0.05,0.12),0.003,0.010,randf_range(0.70,0.96))
		var back:float = randf_range(-5.0,2.0) * unit
		var side:float = randf_range(-3.0,3.0) * unit
		pixel.position = Vector2(back,side)
		if i == 0:
			pixel.scale = Vector2(randf_range(1.4,2.2),randf_range(1.0,1.35))
		holder.add_child(pixel)
	_schedule_blood_decal_fade(holder)


func _spawn_ground_blood_decal(position:Vector2,incoming_direction:Vector2) -> void:
	_play_manual_blood_drop_sfx(position,-14.0)
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var holder:= Node2D.new()
	holder.name = "ManualTrainingBloodGroundDecal"
	holder.z_as_relative = true
	holder.z_index = BLOOD_RENDER_Z
	world.add_child(holder)
	holder.add_to_group("BattleTransient")
	holder.global_position = position
	var direction_value:Vector2 = incoming_direction.normalized() if incoming_direction.length_squared() > 0.000001 else Vector2.RIGHT
	holder.global_rotation = direction_value.angle() + randf_range(-0.11,0.11)

	var radius:float = maxf(blood_ground_splat_radius,4.0) * randf_range(0.76,1.28)
	# 底层扩散边，形状更扁、更透明。
	var soak:= Polygon2D.new()
	soak.polygon = _blood_splat_polygon(radius * randf_range(1.12,1.35),radius * randf_range(0.34,0.62),randi_range(19,28),0.42)
	soak.color = Color(0.13,0.0,0.002,0.46)
	soak.rotation = randf_range(-0.28,0.28)
	holder.add_child(soak)

	# 主血池不是一整块模板：用 2~4 个不同大小/位置的池融合成非对称轮廓。
	var lobe_count:int = randi_range(2,4)
	for i:int in range(lobe_count):
		var pool:= Polygon2D.new()
		var lobe_scale:float = 1.0 if i == 0 else randf_range(0.34,0.72)
		var rx:float = radius * lobe_scale * randf_range(0.82,1.12)
		var ry:float = radius * lobe_scale * randf_range(0.36,0.68)
		pool.polygon = _blood_splat_polygon(rx,ry,randi_range(14,24),randf_range(0.22,0.50))
		pool.color = Color(0.40 + randf_range(-0.035,0.08),0.002,0.008,randf_range(0.82,0.95))
		pool.position = Vector2(randf_range(-radius * 0.34,radius * 0.34),randf_range(-radius * 0.24,radius * 0.24))
		pool.rotation = randf_range(-0.55,0.55)
		holder.add_child(pool)

	# 入射方向反向留下拖抹：一条主拖痕 + 若干断裂的小拖痕。
	var main_streak:= Polygon2D.new()
	main_streak.polygon = _blood_streak_polygon(radius * randf_range(0.85,1.75),radius * randf_range(0.09,0.18))
	main_streak.color = Color(0.45,0.003,0.009,0.82)
	main_streak.position = Vector2(-radius * randf_range(0.52,0.92),randf_range(-radius * 0.18,radius * 0.18))
	main_streak.rotation = randf_range(-0.20,0.20)
	holder.add_child(main_streak)
	for i:int in range(randi_range(1,3)):
		var streak:= Polygon2D.new()
		streak.polygon = _blood_streak_polygon(radius * randf_range(0.25,0.72),radius * randf_range(0.05,0.13))
		streak.color = Color(0.50,0.004,0.010,randf_range(0.58,0.82))
		streak.position = Vector2(-radius * randf_range(0.75,1.55),randf_range(-radius * 0.55,radius * 0.55))
		streak.rotation = randf_range(-0.42,0.42)
		holder.add_child(streak)

	# 卫星血滴分为近圈大滴和远圈小滴，避免所有点的尺度/距离都近似。
	var satellite_count:int = randi_range(8,15)
	for i:int in range(satellite_count):
		var near_ring:bool = i < 4
		var angle_value:float = randf_range(-PI,PI)
		var distance_value:float = radius * (randf_range(0.55,1.15) if near_ring else randf_range(1.10,2.65))
		var drop:= Polygon2D.new()
		var r:float = radius * (randf_range(0.10,0.23) if near_ring else randf_range(0.035,0.11))
		if randf() < 0.32:
			drop.polygon = _blood_teardrop_polygon(r * randf_range(1.8,3.4),r * randf_range(0.75,1.20))
			drop.rotation = angle_value
		else:
			drop.polygon = _blood_irregular_ellipse(r,r * randf_range(0.62,1.12),randi_range(7,11))
		drop.color = Color(0.42 + randf_range(-0.04,0.11),0.003,0.010,randf_range(0.58,0.92))
		drop.position = Vector2.from_angle(angle_value) * distance_value
		holder.add_child(drop)
	_schedule_blood_decal_fade(holder)


func _spawn_wall_blood_decal(position:Vector2,surface_normal:Vector2,collider:Object,incoming_direction:Vector2 = Vector2.ZERO) -> void:
	_play_manual_blood_drop_sfx(position,-14.5)
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var normal:Vector2 = surface_normal.normalized() if surface_normal.length_squared() > 0.000001 else Vector2.LEFT
	var tangent:Vector2 = Vector2(normal.y,-normal.x)
	var holder:= Node2D.new()
	holder.name = "ManualTrainingBloodWallDecal"

	var parent_node:Node = world
	var mapped_to_obstacle:bool = collider is CanvasItem and is_instance_valid(collider)
	if mapped_to_obstacle:
		parent_node = collider as Node
		# V187：训练墙血也只覆盖它实际映射到的障碍物；其它训练血全部使用 World relative z=-2。
		# 相对 Z=0 继承障碍物最终 Z，并作为其子 CanvasItem 画在父项表面。
		holder.z_as_relative = true
		holder.z_index = 0
		holder.show_behind_parent = false
	else:
		# 无有效障碍父级时，保持 World relative z=-2 的自由血液底层。
		holder.z_as_relative = true
		holder.z_index = BLOOD_RENDER_Z
	parent_node.add_child(holder)
	holder.add_to_group("BattleTransient")

	var half_width:float = maxf(blood_wall_splat_width,4.0) * 0.5 * randf_range(0.82,1.24)
	var depth:float = maxf(blood_wall_splat_depth,1.0)
	# 主贴面只轻微压进碰撞面。V176 的较大 inset 会让中心离真实接触点过远；V177 默认只压 1.5px。
	var inset:float = maxf(blood_wall_surface_inset,0.0)
	holder.global_position = position - normal * inset
	holder.global_rotation = tangent.angle()

	# 贴面主血斑以 y≈0 为中心，绝大部分视觉真正跨在碰撞边界上，而不是整体悬在墙外。
	var soak:= Polygon2D.new()
	soak.polygon = _blood_splat_polygon(half_width * randf_range(1.05,1.32),maxf(depth * randf_range(0.28,0.46),1.1),randi_range(18,27),0.46)
	soak.color = Color(0.14,0.0,0.002,0.62)
	soak.position = Vector2(randf_range(-half_width * 0.08,half_width * 0.08),-depth * 0.08)
	holder.add_child(soak)

	var stain:= Polygon2D.new()
	stain.polygon = _blood_splat_polygon(half_width,maxf(depth * randf_range(0.32,0.55),1.2),randi_range(16,24),0.38)
	stain.color = Color(0.44 + randf_range(-0.04,0.07),0.003,0.010,0.93)
	stain.position = Vector2(randf_range(-half_width * 0.10,half_width * 0.10),0.0)
	stain.rotation = randf_range(-0.22,0.22)
	holder.add_child(stain)

	# 撞击方向沿墙切线产生不规则放射飞溅。
	var tangent_motion:float = 0.0
	if incoming_direction.length_squared() > 0.000001:
		tangent_motion = incoming_direction.normalized().dot(tangent)
	for i:int in range(randi_range(3,6)):
		var spray:= Polygon2D.new()
		var len:float = half_width * randf_range(0.35,1.10)
		var wid:float = maxf(depth * randf_range(0.07,0.18),0.65)
		spray.polygon = _blood_streak_polygon(len,wid)
		spray.color = Color(0.48 + randf_range(-0.05,0.08),0.003,0.011,randf_range(0.58,0.86))
		var side_bias:float = signf(tangent_motion) if absf(tangent_motion) > 0.12 else (1.0 if randf() > 0.5 else -1.0)
		spray.position = Vector2(side_bias * randf_range(half_width * 0.22,half_width * 0.92),randf_range(-depth * 0.22,depth * 0.08))
		spray.rotation = randf_range(-0.48,0.48)
		holder.add_child(spray)

	# 凝血体积：暗底仍贴墙，主体和高光只向外法线 (+local Y) 少量凸起。
	var clot_shadow:= Polygon2D.new()
	clot_shadow.polygon = _blood_irregular_ellipse(half_width * randf_range(0.28,0.46),depth * randf_range(0.22,0.38),12)
	clot_shadow.color = Color(0.18,0.0,0.004,0.82)
	clot_shadow.position = Vector2(randf_range(-half_width * 0.24,half_width * 0.24),depth * 0.02)
	holder.add_child(clot_shadow)
	var clot:= Polygon2D.new()
	clot.polygon = _blood_splat_polygon(half_width * randf_range(0.22,0.40),depth * randf_range(0.26,0.48),randi_range(10,15),0.20)
	clot.color = Color(0.57,0.006,0.014,0.98)
	clot.position = clot_shadow.position + Vector2(randf_range(-1.2,1.2),depth * randf_range(0.18,0.32))
	holder.add_child(clot)
	var highlight:= Polygon2D.new()
	highlight.polygon = _blood_ellipse_polygon(half_width * randf_range(0.08,0.16),maxf(depth * 0.10,0.75),9)
	highlight.color = Color(0.92,0.14,0.17,0.66)
	highlight.position = clot.position + Vector2(-half_width * 0.07,depth * 0.18)
	holder.add_child(highlight)

	# 世界重力方向上的流挂。将 world DOWN 转到 holder 局部坐标，墙无论朝哪边，血都“往屏幕下方流”。
	var local_down:Vector2 = holder.global_transform.basis_xform_inv(Vector2.DOWN).normalized()
	for i:int in range(randi_range(1,3)):
		var drip:= Polygon2D.new()
		var drip_len:float = half_width * randf_range(0.35,0.85)
		var drip_w:float = maxf(depth * randf_range(0.08,0.16),0.65)
		drip.polygon = _blood_teardrop_polygon(drip_len,drip_w * 2.0)
		drip.color = Color(0.42 + randf_range(-0.03,0.07),0.003,0.010,randf_range(0.66,0.88))
		drip.position = Vector2(randf_range(-half_width * 0.55,half_width * 0.55),0.0) + local_down * randf_range(depth * 0.15,depth * 0.48)
		drip.rotation = local_down.angle()
		holder.add_child(drip)

	# 少量表面外血珠强化厚度，但不把主体整体顶出墙外。
	for i:int in range(randi_range(2,5)):
		var bead:= Polygon2D.new()
		var r:float = randf_range(maxf(depth * 0.12,0.9),maxf(depth * 0.28,1.5))
		bead.polygon = _blood_irregular_ellipse(r,r * randf_range(0.72,1.10),8)
		bead.color = Color(0.58 + randf_range(-0.04,0.08),0.006,0.014,randf_range(0.76,0.95))
		bead.position = Vector2(randf_range(-half_width * 0.72,half_width * 0.72),depth * randf_range(0.08,0.30))
		holder.add_child(bead)

	_schedule_blood_decal_fade(holder)


func _schedule_blood_decal_fade(holder:Node2D) -> void:
	if holder == null or not is_instance_valid(holder):
		return
	var lifetime:float = maxf(blood_decal_lifetime,1.0)
	var tween:Tween = holder.create_tween()
	tween.tween_interval(lifetime)
	tween.tween_property(holder,"modulate:a",0.0,1.4)
	tween.finished.connect(holder.queue_free,CONNECT_ONE_SHOT)


func _play_manual_blood_drop_sfx(position_value:Vector2,volume_db:float) -> void:
	if BLOOD_DROP_SFX.is_empty() or not is_inside_tree():
		return
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var stream_value:Variant = BLOOD_DROP_SFX[randi_range(0,BLOOD_DROP_SFX.size() - 1)]
	if not stream_value is AudioStream:
		return
	var player:=AudioStreamPlayer2D.new()
	player.name = "ManualBloodDropSFX"
	player.stream = stream_value as AudioStream
	player.global_position = position_value
	player.volume_db = volume_db
	player.pitch_scale = randf_range(0.92,1.08)
	player.max_distance = 950.0
	player.attenuation = 0.85
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	world.add_child(player)
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _blood_pixel_square_polygon(radius:float) -> PackedVector2Array:
	var r:float = maxf(roundf(radius * 2.0) * 0.5,0.5)
	return PackedVector2Array([Vector2(-r,-r),Vector2(r,-r),Vector2(r,r),Vector2(-r,r)])


func _blood_pixel_drop_polygon(length_value:float,width_value:float,variant:int = 0) -> PackedVector2Array:
	var length:float = maxf(length_value,4.0)
	var width:float = maxf(width_value,3.0)
	var px:float = 1.0
	var points:Array[Vector2] = []
	match posmod(variant,4):
		0:
			points = [Vector2(-0.56,-0.10),Vector2(-0.38,-0.10),Vector2(-0.38,-0.28),Vector2(-0.10,-0.28),Vector2(-0.10,-0.50),Vector2(0.22,-0.50),Vector2(0.22,-0.34),Vector2(0.42,-0.34),Vector2(0.42,-0.17),Vector2(0.58,-0.17),Vector2(0.58,0.17),Vector2(0.42,0.17),Vector2(0.42,0.34),Vector2(0.22,0.34),Vector2(0.22,0.50),Vector2(-0.10,0.50),Vector2(-0.10,0.28),Vector2(-0.38,0.28),Vector2(-0.38,0.10),Vector2(-0.56,0.10)]
		1:
			points = [Vector2(-0.62,-0.08),Vector2(-0.42,-0.08),Vector2(-0.42,-0.24),Vector2(-0.18,-0.24),Vector2(-0.18,-0.46),Vector2(0.16,-0.46),Vector2(0.16,-0.36),Vector2(0.40,-0.36),Vector2(0.40,-0.18),Vector2(0.56,-0.18),Vector2(0.56,0.18),Vector2(0.34,0.18),Vector2(0.34,0.38),Vector2(0.04,0.38),Vector2(0.04,0.50),Vector2(-0.24,0.50),Vector2(-0.24,0.26),Vector2(-0.46,0.26),Vector2(-0.46,0.10),Vector2(-0.62,0.10)]
		2:
			points = [Vector2(-0.50,-0.12),Vector2(-0.34,-0.12),Vector2(-0.34,-0.34),Vector2(-0.04,-0.34),Vector2(-0.04,-0.50),Vector2(0.30,-0.50),Vector2(0.30,-0.34),Vector2(0.48,-0.34),Vector2(0.48,-0.16),Vector2(0.62,-0.16),Vector2(0.62,0.16),Vector2(0.48,0.16),Vector2(0.48,0.34),Vector2(0.24,0.34),Vector2(0.24,0.46),Vector2(-0.10,0.46),Vector2(-0.10,0.30),Vector2(-0.34,0.30),Vector2(-0.34,0.12),Vector2(-0.50,0.12)]
		_:
			points = [Vector2(-0.58,-0.06),Vector2(-0.40,-0.06),Vector2(-0.40,-0.22),Vector2(-0.20,-0.22),Vector2(-0.20,-0.40),Vector2(0.10,-0.40),Vector2(0.10,-0.52),Vector2(0.34,-0.52),Vector2(0.34,-0.32),Vector2(0.52,-0.32),Vector2(0.52,-0.14),Vector2(0.62,-0.14),Vector2(0.62,0.14),Vector2(0.48,0.14),Vector2(0.48,0.30),Vector2(0.28,0.30),Vector2(0.28,0.44),Vector2(-0.04,0.44),Vector2(-0.04,0.34),Vector2(-0.28,0.34),Vector2(-0.28,0.18),Vector2(-0.48,0.18),Vector2(-0.48,0.06),Vector2(-0.58,0.06)]
	var result:=PackedVector2Array()
	for p:Vector2 in points:
		var raw:=Vector2(p.x * length,p.y * width)
		result.append(Vector2(roundf(raw.x / px) * px,roundf(raw.y / px) * px))
	return result


func _blood_teardrop_polygon(length_value:float,width_value:float) -> PackedVector2Array:
	var length:float = maxf(length_value,3.0)
	var width:float = maxf(width_value,2.0)
	# +X 为液滴头部；前端圆，后端收成尖尾。加入轻微随机使连续发射不完全复制。
	return PackedVector2Array([
		Vector2(-length * randf_range(0.62,0.76),randf_range(-width * 0.08,width * 0.08)),
		Vector2(-length * 0.28,-width * randf_range(0.24,0.34)),
		Vector2(length * 0.08,-width * randf_range(0.47,0.55)),
		Vector2(length * 0.35,-width * randf_range(0.34,0.43)),
		Vector2(length * 0.52,-width * randf_range(0.12,0.20)),
		Vector2(length * randf_range(0.55,0.62),0.0),
		Vector2(length * 0.50,width * randf_range(0.13,0.21)),
		Vector2(length * 0.32,width * randf_range(0.34,0.44)),
		Vector2(length * 0.05,width * randf_range(0.46,0.56)),
		Vector2(-length * 0.30,width * randf_range(0.23,0.35)),
	])


func _blood_streak_polygon(length_value:float,width_value:float) -> PackedVector2Array:
	var length:float = maxf(length_value,2.0)
	var width:float = maxf(width_value,0.8)
	return PackedVector2Array([
		Vector2(-length * 0.62,randf_range(-width * 0.08,width * 0.08)),
		Vector2(-length * 0.16,-width * randf_range(0.42,0.58)),
		Vector2(length * 0.42,-width * randf_range(0.22,0.38)),
		Vector2(length * 0.60,0.0),
		Vector2(length * 0.34,width * randf_range(0.20,0.36)),
		Vector2(-length * 0.14,width * randf_range(0.40,0.56)),
	])


func _blood_ellipse_polygon(radius_x:float,radius_y:float,point_count:int = 12) -> PackedVector2Array:
	var points:= PackedVector2Array()
	var count:int = maxi(point_count,6)
	for i:int in range(count):
		var angle_value:float = TAU * float(i) / float(count)
		points.append(Vector2(cos(angle_value) * radius_x,sin(angle_value) * radius_y))
	return points


func _blood_irregular_ellipse(radius_x:float,radius_y:float,point_count:int = 12) -> PackedVector2Array:
	var points:= PackedVector2Array()
	var count:int = maxi(point_count,6)
	for i:int in range(count):
		var angle_value:float = TAU * float(i) / float(count)
		var jitter:float = randf_range(0.68,1.28)
		points.append(Vector2(cos(angle_value) * radius_x * jitter,sin(angle_value) * radius_y * jitter))
	return points


func _blood_splat_polygon(radius_x:float,radius_y:float,point_count:int = 18,spike_strength:float = 0.30) -> PackedVector2Array:
	var points:= PackedVector2Array()
	var count:int = maxi(point_count,8)
	var spike:float = clampf(spike_strength,0.0,0.9)
	for i:int in range(count):
		var angle_value:float = TAU * float(i) / float(count)
		var wobble:float = randf_range(0.68,1.28)
		if randf() < 0.24:
			wobble += randf_range(spike * 0.30,spike)
		var x:float = cos(angle_value) * radius_x * wobble
		var y:float = sin(angle_value) * radius_y * randf_range(0.72,1.24)
		points.append(Vector2(x,y))
	return points

func _ensure_mouse_proxy() -> void:
	if _mouse_proxy != null and is_instance_valid(_mouse_proxy):
		return
	var world:Node = get_tree().current_scene
	if world == null:
		return

	var proxy:ball = MOUSE_PROXY_SCENE.instantiate() as ball
	if proxy == null:
		return
	proxy.name = "ManualTrainingMouseSource"
	proxy.Type = ball.Ball_Type.Shooter
	proxy.Team = MANUAL_TEAM
	proxy.Max_health = 1
	proxy.Damage = 0
	proxy.Speed = 0.0
	proxy.Has_Collision_Damage = false
	proxy.Can_Attack = false
	proxy.Can_Skill = false
	proxy.direction = Vector2.ZERO
	world.add_child(proxy, true)
	proxy.global_position = global_position
	proxy.visible = false
	_disable_proxy_collisions(proxy)
	proxy.process_mode = Node.PROCESS_MODE_DISABLED
	_mouse_proxy = proxy


func _disable_proxy_collisions(root:Node) -> void:
	if root is CollisionObject2D:
		var collision_object:CollisionObject2D = root as CollisionObject2D
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0
	if root is Area2D:
		(root as Area2D).monitoring = false
		(root as Area2D).monitorable = false
	for child:Node in root.get_children():
		if child is CollisionShape2D:
			(child as CollisionShape2D).disabled = true
		_disable_proxy_collisions(child)


func _destroy_mouse_proxy() -> void:
	if _mouse_proxy != null and is_instance_valid(_mouse_proxy):
		_mouse_proxy.queue_free()
	_mouse_proxy = null


func _has_property(object:Object, property_name:String) -> bool:
	# V431 性能：按脚本缓存属性名集合（classes/property_index.gd），不再逐次 get_property_list()。
	return PROPERTY_INDEX.has_property(object,property_name)


const PROPERTY_INDEX = preload("res://classes/property_index.gd")


func _set_property_if_exists(object:Object, property_name:String, value:Variant) -> void:
	if _has_property(object, property_name):
		object.set(property_name, value)
