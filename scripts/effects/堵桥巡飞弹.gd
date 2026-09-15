extends Node2D

const SUBMISSION_TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const SMALL_BOMB_SCRIPT:Script = preload("res://scripts/effects/堵桥巡飞弹小炸弹.gd")
const MISSILE_TEXTURE:Texture2D = preload("res://Images/characters/三角洲/乌鲁鲁/巡飞弹.png")

var owner_ref:WeakRef = null
var target_ref:WeakRef = null
var last_target_position:Vector2 = Vector2.ZERO
var current_direction:Vector2 = Vector2.UP
var rise_duration:float = 0.38
var rise_speed:float = 330.0
var cruise_speed:float = 560.0
var turn_speed_rad:float = deg_to_rad(150.0)
var lifetime:float = 5.2
var hit_radius:float = 11.0
var impact_radius:float = 78.0
var impact_damage_multiplier:float = 8.0
var elapsed:float = 0.0
var config:Dictionary = {}
var _finished:bool = false
var _exploding:bool = false
var _explosion_elapsed:float = 0.0
var _trail_world:Array[Vector2] = []
var _sprite:Sprite2D = null


func setup(owner_ball:ball,target_ball:ball,start_position:Vector2,config_value:Dictionary = {}) -> void:
	owner_ref = weakref(owner_ball)
	target_ref = weakref(target_ball)
	global_position = start_position
	_trail_world.clear()
	_trail_world.append(start_position)
	if target_ball != null and is_instance_valid(target_ball):
		last_target_position = target_ball.global_position
	current_direction = Vector2.UP
	config = config_value.duplicate(true)
	rise_duration = maxf(float(config.get("rise_duration",rise_duration)),0.05)
	rise_speed = maxf(float(config.get("rise_speed",rise_speed)),40.0)
	cruise_speed = maxf(float(config.get("cruise_speed",cruise_speed)),80.0)
	turn_speed_rad = deg_to_rad(maxf(float(config.get("turn_speed_deg",rad_to_deg(turn_speed_rad))),10.0))
	lifetime = maxf(float(config.get("lifetime",lifetime)),0.5)
	hit_radius = maxf(float(config.get("hit_radius",hit_radius)),3.0)
	impact_radius = maxf(float(config.get("impact_radius",impact_radius)),10.0)
	impact_damage_multiplier = maxf(float(config.get("impact_damage_multiplier",impact_damage_multiplier)),0.0)


func _ready() -> void:
	# World 的地图外视觉遮罩位于 z=90。巡飞弹需要先上升到地图外再俯冲，
	# 因此设为 top_level 并放在遮罩之上、血条/地图黑边之下，避免出界阶段被盖住。
	set_as_top_level(true)
	z_as_relative = false
	z_index = 98
	add_to_group("BattleTransient")
	if _trail_world.is_empty():
		_trail_world.append(global_position)
	_build_visual()
	queue_redraw()


func _physics_process(delta:float) -> void:
	if _finished:
		return
	var source:ball = _owner()
	if source == null or not is_instance_valid(source):
		queue_free()
		return
	if not source.is_combat_runtime_active():
		return

	if _exploding:
		_explosion_elapsed += delta
		if _sprite != null and is_instance_valid(_sprite):
			_sprite.visible = false
		queue_redraw()
		if _explosion_elapsed >= 0.26:
			queue_free()
		return

	elapsed += delta
	if elapsed >= lifetime:
		_impact(source,global_position)
		return

	var target:ball = _target()
	if target != null and is_instance_valid(target):
		last_target_position = target.global_position

	var speed:float = rise_speed
	if elapsed <= rise_duration:
		current_direction = Vector2.UP
	else:
		speed = cruise_speed
		var to_target:Vector2 = last_target_position - global_position
		if to_target.length_squared() > 0.000001:
			var desired_angle:float = to_target.angle()
			var current_angle:float = current_direction.angle()
			var diff:float = wrapf(desired_angle - current_angle,-PI,PI)
			# 靠近目标时允许更积极地修正航向，避免低转向率掠过目标后绕很久。
			var distance_to_target:float = to_target.length()
			var near_turn_boost:float = lerpf(2.35,1.0,clampf((distance_to_target - 42.0) / 100.0,0.0,1.0))
			var max_turn:float = turn_speed_rad * near_turn_boost * delta
			current_angle += clampf(diff,-max_turn,max_turn)
			current_direction = Vector2.RIGHT.rotated(current_angle)

	var previous:Vector2 = global_position
	var next_position:Vector2 = previous + current_direction * speed * delta
	# V106：所有端都按角色世界坐标做几何扫掠；伤害仍只由 authority 在 _impact() 内结算。
	# 不再依赖 Hurtbox/Body 当前是否 monitorable、collision_layer 是否临时变化。
	var hit_target:ball = _sweep_enemy(source,previous,next_position)
	if hit_target != null:
		global_position = _closest_point_on_segment(hit_target.global_position,previous,next_position)
		_impact(source,global_position)
		return
	global_position = next_position
	# 巡飞弹原图机头朝右，直接用飞行方向旋转。
	rotation = current_direction.angle()
	if source.has_method("update_uluru_missile_flight_audio_position"):
		source.call("update_uluru_missile_flight_audio_position",global_position)


	_trail_world.append(global_position)
	if _trail_world.size() > 18:
		_trail_world.pop_front()
	queue_redraw()


func _build_visual() -> void:
	if MISSILE_TEXTURE == null:
		return
	_sprite = Sprite2D.new()
	_sprite.name = "乌鲁鲁巡飞弹图像"
	_sprite.texture = MISSILE_TEXTURE
	var longest:float = maxf(MISSILE_TEXTURE.get_width(),MISSILE_TEXTURE.get_height())
	# V106：上一版 58px 明显偏大；压到 34px，仍能看清轮廓但不会接近人物体积。
	_sprite.scale = Vector2.ONE * (34.0 / maxf(longest,1.0))
	add_child(_sprite)
	rotation = current_direction.angle()


func _sweep_enemy(source:ball,from_pos:Vector2,to_pos:Vector2) -> ball:
	# 用“线段到角色中心 + 角色实际 Hurtbox 尺寸”的扫掠判定。
	# 这比 direct_space_state.intersect_shape() 更适合本项目：部分角色技能会暂时关闭
	# Hurtbox 的 monitoring / collision_layer，但巡飞弹仍应在视觉接触时正常近炸。
	var motion:Vector2 = to_pos - from_pos
	var motion_sq:float = motion.length_squared()
	var best:ball = null
	var best_t:float = INF
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var candidate:ball = raw as ball
		if not SUBMISSION_TOOLS.is_enemy(source,candidate):
			continue

		var t:float = 0.0
		if motion_sq > 0.000001:
			t = clampf((candidate.global_position - from_pos).dot(motion) / motion_sq,0.0,1.0)
		var closest:Vector2 = from_pos + motion * t
		var trigger_radius:float = hit_radius + _candidate_body_radius(candidate)
		if closest.distance_squared_to(candidate.global_position) <= trigger_radius * trigger_radius:
			if t < best_t:
				best_t = t
				best = candidate
	return best


func _candidate_body_radius(candidate:ball) -> float:
	# CharacterAutoFit 会改 Hurtbox 大小，因此尽量读取当前真实 CollisionShape2D；
	# 读不到时退回到项目普通角色约 16px 的世界半径。
	if candidate != null and is_instance_valid(candidate) and candidate.self_hurtbox != null and is_instance_valid(candidate.self_hurtbox):
		var shape_node:CollisionShape2D = candidate.self_hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if shape_node != null and shape_node.shape != null:
			var sx:float = shape_node.global_transform.x.length()
			var sy:float = shape_node.global_transform.y.length()
			var shape:Shape2D = shape_node.shape
			if shape is RectangleShape2D:
				var rect:RectangleShape2D = shape as RectangleShape2D
				return clampf(maxf(rect.size.x * sx,rect.size.y * sy) * 0.5,10.0,30.0)
			if shape is CircleShape2D:
				var circle:CircleShape2D = shape as CircleShape2D
				return clampf(circle.radius * maxf(sx,sy),10.0,30.0)
			if shape is CapsuleShape2D:
				var capsule:CapsuleShape2D = shape as CapsuleShape2D
				return clampf(maxf(capsule.radius * 2.0 * sx,capsule.height * sy) * 0.5,10.0,30.0)
	return 16.0


func _closest_point_on_segment(point:Vector2,a:Vector2,b:Vector2) -> Vector2:
	var ab:Vector2 = b - a
	var len_sq:float = ab.length_squared()
	if len_sq <= 0.000001:
		return a
	var t:float = clampf((point - a).dot(ab) / len_sq,0.0,1.0)
	return a + ab * t


func _collider_ball(collider:Variant) -> ball:
	if collider is ball:
		return collider as ball
	if collider is Node:
		var node:Node = collider as Node
		var cursor:Node = node
		for _i:int in range(5):
			if cursor is ball:
				return cursor as ball
			cursor = cursor.get_parent()
			if cursor == null:
				break
		if node.owner is ball:
			return node.owner as ball
	return null


func _impact(source:ball,position_value:Vector2) -> void:
	if _exploding or _finished:
		return
	_exploding = true
	_explosion_elapsed = 0.0
	global_position = position_value
	if _sprite != null and is_instance_valid(_sprite):
		_sprite.visible = false
	if source.is_multiplayer_authority():
		var damage:float = source.attack_damage(impact_damage_multiplier)
		for target:ball in SUBMISSION_TOOLS.enemies_in_radius(source,position_value,impact_radius):
			target.receive_positional_damage(damage,position_value,false,source)

	# V108：主巡飞弹也使用真实爆炸帧动画，不再依赖程序化圆圈反馈。
	# 视觉在每个客户端的本地巡飞弹上生成；声音由authority RPC统一同步，避免重复播放。
	var explosion_variant:int = clampi(int(config.get("missile_explosion_variant",1)),1,3)
	if source.has_method("spawn_uluru_explosion_visual"):
		source.call(
			"spawn_uluru_explosion_visual",
			position_value,
			maxf(impact_radius * 2.15,96.0),
			explosion_variant
		)
	_spawn_four_bombs(source,position_value)
	if source.is_multiplayer_authority() and source.has_method("play_uluru_missile_impact_feedback"):
		source.call("play_uluru_missile_impact_feedback",position_value)
	if source.has_method("_bridge_on_loiter_missile_finished"):
		source.call_deferred("_bridge_on_loiter_missile_finished")
	queue_redraw()


func _spawn_four_bombs(source:ball,position_value:Vector2) -> void:
	if get_tree().current_scene == null:
		return
	var offset:float = randf_range(0.0,TAU)
	for i:int in range(4):
		var bomb:Node2D = SMALL_BOMB_SCRIPT.new() as Node2D
		if bomb == null:
			continue
		bomb.name = "堵桥巡飞弹小炸弹_%d_%d" % [Time.get_ticks_usec(),i]
		get_tree().current_scene.add_child(bomb,true)
		var dir:Vector2 = Vector2.RIGHT.rotated(offset + TAU * float(i) / 4.0)
		var bomb_config:Dictionary = config.duplicate(true)
		bomb_config["bomb_fuse"] = maxf(float(config.get("bomb_fuse",0.9)) + float(i) * 0.08,0.15)
		var variants_value:Variant = config.get("bomb_mc_explosion_variants",[])
		if variants_value is Array:
			var variants:Array = variants_value
			if i < variants.size():
				bomb_config["mc_explosion_variant"] = clampi(int(variants[i]),1,3)
			else:
				bomb_config["mc_explosion_variant"] = randi_range(1,3)
		else:
			bomb_config["mc_explosion_variant"] = randi_range(1,3)
		bomb.call("setup",source,position_value,dir,bomb_config)


func _target() -> ball:
	if target_ref == null:
		return null
	var raw:Variant = target_ref.get_ref()
	if raw is ball and is_instance_valid(raw) and (raw as ball).health > 0:
		return raw as ball
	return null


func _owner() -> ball:
	if owner_ref == null:
		return null
	var raw:Variant = owner_ref.get_ref()
	if raw is ball and is_instance_valid(raw):
		return raw as ball
	return null


func _exit_tree() -> void:
	var source:ball = _owner()
	if source != null and is_instance_valid(source) and source.is_multiplayer_authority() and source.has_method("_bridge_on_loiter_missile_finished"):
		source.call_deferred("_bridge_on_loiter_missile_finished")


func _draw() -> void:
	# 巡飞弹自身只负责真实路径拖尾。爆炸由V108新增的MC帧动画表现，不再额外画圆圈。
	if _trail_world.size() >= 2 and not _exploding:
		var pts:=PackedVector2Array()
		for p:Vector2 in _trail_world:
			# _trail_world 记录世界坐标，_draw() 使用局部坐标，必须完整逆变换。
			pts.append(to_local(p))
		draw_polyline(pts,Color(0.98,0.58,0.18,0.48),2.2,true)
