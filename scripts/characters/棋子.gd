extends StaticBody2D

# 棋子仍然是角色地形，但只放在角色所在的物理层（2）。
# 项目里的投射物使用墙体层1进行实体碰撞，因此不会被棋子挡住。

var board_controller:Node = null
var stone_owner:ball = null
var cell:Vector2i = Vector2i.ZERO
var color_slot:int = 0
var stone_radius:float = 5.0
var touch_damage_multiplier:float = 1.0
var chain_bonus_damage_multiplier:float = 0.75
var fall_height:float = 115.0
var fall_duration:float = 0.28
var stone_lifetime:float = 14.0
var chain_count:int = 1

var _terrain_shape:CollisionShape2D = null
var _sensor:Area2D = null
var _sensor_shape:CollisionShape2D = null
var _visual_root:Node2D = null
var _outer_visual:Polygon2D = null
var _inner_visual:Polygon2D = null
var _life_timer:Timer = null
var _landed:bool = false
var _expiring:bool = false
var _last_touch_msec_by_target:Dictionary = {}

# body_entered/area_entered 只负责“刚接触时”的即时伤害。
# 角色被多颗棋子夹住后可能一直保持接触、不会再次触发 entered 信号，
# 所以落地棋子会周期检查仍在伤害区里的角色，持续结算接触伤害。
const TOUCH_REPEAT_INTERVAL_MSEC:int = 420
const TOUCH_SCAN_INTERVAL:float = 0.12
var _touch_scan_left:float = 0.0


func _ready() -> void:
	add_to_group("AI_Hazard")
	# layer2：角色默认 mask 包含2；投射物通常只撞 layer1 墙体。
	# V276：远端棋子仅做视觉镜像，真实实体阻挡/伤害都由服务器 authority 负责。
	collision_layer = 2 if is_multiplayer_authority() else 0
	collision_mask = 0
	z_as_relative = false
	z_index = 35
	set_meta("wall_hit_use_raw_contact",true)
	set_meta("wall_hit_visual_width",maxf(stone_radius,2.0))
	_build_nodes()
	_start_fall_animation()


func _physics_process(delta:float) -> void:
	if not _landed or _expiring:
		return
	_touch_scan_left -= delta
	if _touch_scan_left > 0.0:
		return
	_touch_scan_left = TOUCH_SCAN_INTERVAL
	_poll_touching_targets()


func _poll_touching_targets() -> void:
	if _sensor == null or not is_instance_valid(_sensor) or not _sensor.monitoring:
		return

	# CharacterBody2D 本体在 layer 2；正常角色的 Hurtbox Area2D 也在 layer 2。
	# 两边都检查可以覆盖“实体碰撞刚好把本体停在 Area 边缘”的情况。
	var seen:Dictionary = {}
	for body:Node2D in _sensor.get_overlapping_bodies():
		if not body is ball:
			continue
		var target:ball = body as ball
		if not is_instance_valid(target):
			continue
		var target_id:int = target.get_instance_id()
		if seen.has(target_id):
			continue
		seen[target_id] = true
		_try_touch(target)

	for area:Area2D in _sensor.get_overlapping_areas():
		var target:ball = _find_ball_from_area(area)
		if target == null or not is_instance_valid(target):
			continue
		var target_id:int = target.get_instance_id()
		if seen.has(target_id):
			continue
		seen[target_id] = true
		_try_touch(target)


func configure(
	controller:Node,
	owner_ball:ball,
	cell_value:Vector2i,
	slot_value:int,
	radius_value:float,
	base_damage_multiplier_value:float,
	bonus_damage_multiplier_value:float,
	fall_height_value:float = 115.0,
	fall_duration_value:float = 0.28,
	lifetime_value:float = 14.0
) -> void:
	board_controller = controller
	stone_owner = owner_ball
	cell = cell_value
	color_slot = slot_value
	stone_radius = maxf(radius_value,2.0)
	touch_damage_multiplier = maxf(base_damage_multiplier_value,0.0)
	chain_bonus_damage_multiplier = maxf(bonus_damage_multiplier_value,0.0)
	fall_height = maxf(fall_height_value,0.0)
	fall_duration = maxf(fall_duration_value,0.05)
	stone_lifetime = maxf(lifetime_value,0.5)
	# 棋子是有限尺寸的圆形实体，不应该沿用“无限墙面”的白线覆盖宽度。
	# 人物撞到棋子时让墙面撞击反馈从 Godot 报告的真实接触点产生，
	# 并把白线起点的切向覆盖限制在棋子半径附近，避免从棋子轮廓外冒出来。
	set_meta("wall_hit_use_raw_contact",true)
	set_meta("wall_hit_visual_width",maxf(stone_radius,2.0))
	if is_inside_tree():
		_build_nodes()
		_refresh_visual()


func _build_nodes() -> void:
	if not is_inside_tree():
		return
	if _terrain_shape == null or not is_instance_valid(_terrain_shape):
		_terrain_shape = CollisionShape2D.new()
		add_child(_terrain_shape)
	var terrain_circle := CircleShape2D.new()
	terrain_circle.radius = stone_radius
	_terrain_shape.shape = terrain_circle
	_terrain_shape.disabled = not _landed or _expiring

	if _sensor == null or not is_instance_valid(_sensor):
		_sensor = Area2D.new()
		_sensor.collision_layer = 0
		_sensor.collision_mask = 0
		_sensor.set_collision_mask_value(2,true)
		_sensor.monitoring = false
		_sensor.monitorable = false
		_sensor.body_entered.connect(_on_body_entered)
		_sensor.area_entered.connect(_on_area_entered)
		add_child(_sensor)
	if _sensor_shape == null or not is_instance_valid(_sensor_shape):
		_sensor_shape = CollisionShape2D.new()
		_sensor.add_child(_sensor_shape)
	var sensor_circle := CircleShape2D.new()
	sensor_circle.radius = stone_radius + 1.2
	_sensor_shape.shape = sensor_circle
	_sensor_shape.disabled = not _landed or _expiring

	if _visual_root == null or not is_instance_valid(_visual_root):
		_visual_root = Node2D.new()
		_visual_root.z_index = 35
		add_child(_visual_root)
	if _outer_visual == null or not is_instance_valid(_outer_visual):
		_outer_visual = Polygon2D.new()
		_outer_visual.z_index = 0
		_visual_root.add_child(_outer_visual)
	if _inner_visual == null or not is_instance_valid(_inner_visual):
		_inner_visual = Polygon2D.new()
		_inner_visual.z_index = 1
		_visual_root.add_child(_inner_visual)

	if _life_timer == null or not is_instance_valid(_life_timer):
		_life_timer = Timer.new()
		_life_timer.one_shot = true
		_life_timer.timeout.connect(_on_lifetime_timeout)
		add_child(_life_timer)
	_refresh_visual()
	_refresh_threat_debug_meta()


func _refresh_visual() -> void:
	if _visual_root == null or not is_instance_valid(_visual_root):
		return
	if color_slot == 0:
		# 黑棋按要求不描边。
		_outer_visual.visible = false
		_inner_visual.polygon = _make_circle_polygon(stone_radius)
		# 连得越多只做轻微亮度/尺寸变化，不额外加描边。
		var light:float = 0.035 + 0.028 * float(clampi(chain_count,1,5) - 1)
		_inner_visual.color = Color(light,light,light + 0.01,1.0)
	else:
		_outer_visual.visible = true
		_outer_visual.polygon = _make_circle_polygon(stone_radius + 0.7)
		_outer_visual.color = Color(0.05,0.05,0.055,0.92)
		_inner_visual.polygon = _make_circle_polygon(stone_radius)
		var shade:float = 0.97 - 0.035 * float(clampi(chain_count,1,5) - 1)
		_inner_visual.color = Color(shade,shade,shade,1.0)
	if _landed and not _expiring:
		var chain_scale:float = 1.0 + 0.045 * float(clampi(chain_count,1,5) - 1)
		_visual_root.scale = Vector2.ONE * chain_scale


func _make_circle_polygon(radius_value:float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(24):
		points.append(Vector2.from_angle(TAU * float(i) / 24.0) * radius_value)
	return points


func _start_fall_animation() -> void:
	_landed = false
	_expiring = false
	if _terrain_shape != null:
		_terrain_shape.disabled = true
	if _sensor_shape != null:
		_sensor_shape.disabled = true
	if _sensor != null:
		_sensor.monitoring = false
	if _visual_root == null:
		return
	_visual_root.position = Vector2(0.0,-fall_height)
	_visual_root.scale = Vector2.ONE

	var tween:Tween = create_tween()
	# EASE_OUT：先快后慢，落地前明显减速。
	tween.tween_property(_visual_root,"position:y",0.0,fall_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_land)
	tween.tween_property(_visual_root,"scale",Vector2(1.13,0.87),0.045)
	tween.tween_callback(_refresh_visual)


func _land() -> void:
	if _expiring:
		return
	_landed = true
	var gameplay_authority:bool = not multiplayer.has_multiplayer_peer() or is_multiplayer_authority()
	if _terrain_shape != null and is_instance_valid(_terrain_shape):
		_terrain_shape.set_deferred("disabled",not gameplay_authority)
	if _sensor_shape != null and is_instance_valid(_sensor_shape):
		_sensor_shape.set_deferred("disabled",not gameplay_authority)
	if _sensor != null and is_instance_valid(_sensor):
		_sensor.set_deferred("monitoring",gameplay_authority)
	_touch_scan_left = 0.0
	if gameplay_authority:
		# monitoring 是 deferred 开启的，下一物理步再读取重叠列表。
		call_deferred("_poll_touching_targets")
	refresh_lifetime()
	_refresh_visual()
	_refresh_threat_debug_meta()
	if board_controller != null and is_instance_valid(board_controller) and board_controller.has_method("on_stone_landed"):
		board_controller.call_deferred("on_stone_landed",self)


func _current_touch_damage() -> float:
	return stone_owner.attack_damage(touch_damage_multiplier + chain_bonus_damage_multiplier * float(maxi(chain_count - 1,0))) if stone_owner != null and is_instance_valid(stone_owner) else 0.0


func _refresh_threat_debug_meta() -> void:
	if _sensor != null and is_instance_valid(_sensor):
		# 调试层用这个标准 meta 直接把“真实伤害传感 Area”画成白->红。
		# StaticBody2D 本体没有这个 meta，因此仍显示为绿色实体碰撞区域。
		_sensor.set_meta(
			"threat_debug_damage",
			_current_touch_damage() if _landed and not _expiring else 0.0
		)


# 高级 AI 可选接口：棋子既是实体阻挡，也会持续造成接触伤害。
func get_ai_hazard_info(receiver:ball) -> Dictionary:
	if not _landed or _expiring:
		return {}
	if receiver == null or not is_instance_valid(receiver):
		return {}
	return {
		"shape":"circle",
		"position":global_position,
		"velocity":Vector2.ZERO,
		"radius":maxf(stone_radius + 2.0,4.0),
		"kind":"chess_piece",
		"blocking":true,
		"damage":_current_touch_damage(),
		"source":self,
	}


func is_landed_stone() -> bool:
	return _landed and not _expiring


func set_chain_state(value:int,refresh_time:bool = false) -> void:
	chain_count = clampi(value,1,5)
	_refresh_visual()
	_refresh_threat_debug_meta()
	if refresh_time:
		refresh_lifetime()


func refresh_lifetime() -> void:
	if _expiring or not _landed:
		return
	if _life_timer != null and is_instance_valid(_life_timer):
		_life_timer.start(maxf(stone_lifetime,0.5))


func _on_lifetime_timeout() -> void:
	if _expiring:
		return
	if board_controller != null and is_instance_valid(board_controller) and board_controller.has_method("on_stone_expired"):
		board_controller.call("on_stone_expired",self)
	else:
		play_disappear()


func play_disappear() -> void:
	if _expiring:
		return
	_expiring = true
	_refresh_threat_debug_meta()
	if _life_timer != null:
		_life_timer.stop()
	if _terrain_shape != null:
		_terrain_shape.set_deferred("disabled",true)
	if _sensor_shape != null:
		_sensor_shape.set_deferred("disabled",true)
	if _sensor != null:
		_sensor.set_deferred("monitoring",false)
	if _visual_root == null or not is_instance_valid(_visual_root):
		queue_free()
		return
	var tween:Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_visual_root,"modulate:a",0.0,0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_visual_root,"scale",_visual_root.scale * 0.35,0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)


func _on_body_entered(body:Node) -> void:
	if body is ball:
		_try_touch(body as ball)


func _on_area_entered(area:Area2D) -> void:
	var target:ball = _find_ball_from_area(area)
	if target != null:
		_try_touch(target)


func _find_ball_from_area(area:Area2D) -> ball:
	if area == null:
		return null
	if area.owner is ball:
		return area.owner as ball
	var cursor:Node = area
	while cursor != null:
		if cursor is ball:
			return cursor as ball
		cursor = cursor.get_parent()
	return null


func _try_touch(target:ball) -> void:
	if not _landed or _expiring:
		return
	if board_controller == null or not is_instance_valid(board_controller):
		return
	if target == null or not is_instance_valid(target):
		return
	var target_id:int = target.get_instance_id()
	var now_msec:int = Time.get_ticks_msec()
	if _last_touch_msec_by_target.has(target_id):
		if now_msec - int(_last_touch_msec_by_target[target_id]) < TOUCH_REPEAT_INTERVAL_MSEC:
			return
	_last_touch_msec_by_target[target_id] = now_msec
	if _last_touch_msec_by_target.size() > 128:
		_cleanup_old_touch_records(now_msec)
	if board_controller.has_method("on_stone_touched"):
		board_controller.call("on_stone_touched",self,target)


func _cleanup_old_touch_records(now_msec:int) -> void:
	var remove_ids:Array[int] = []
	for target_id in _last_touch_msec_by_target:
		if now_msec - int(_last_touch_msec_by_target[target_id]) > 3000:
			remove_ids.append(int(target_id))
	for target_id:int in remove_ids:
		_last_touch_msec_by_target.erase(target_id)
