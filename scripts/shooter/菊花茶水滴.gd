extends ball

@export_category("菊花茶水滴 - 抛物线")
@export_range(0.1,4.0,0.01) var minimum_flight_time:float = 0.30
@export_range(0.1,4.0,0.01) var maximum_flight_time:float = 1.80
@export_range(0.0,2400.0,1.0) var projectile_gravity:float = 1050.0
@export_range(0.2,8.0,0.05) var max_lifetime:float = 2.6
@export_range(0.0,2000.0,1.0) var fall_delete_distance:float = 260.0

@export_category("菊花茶水滴 - 细线视觉")
@export_range(8.0,160.0,1.0) var line_length:float = 32.0
@export_range(0.5,20.0,0.1) var line_width:float = 2.8
@export_range(0.0,0.35,0.01) var line_length_variation:float = 0.08
@export_range(0.0,0.35,0.01) var line_width_variation:float = 0.10
@export_range(40.0,1200.0,10.0) var distance_length_full_travel:float = 420.0
@export_range(1.0,1.25,0.01) var distance_length_max_scale:float = 1.07
@export var line_color:Color = Color(0.08,1.0,0.28,1.0)
@export var line_glow_color:Color = Color(0.30,1.0,0.48,0.32)

var ballistic_velocity:Vector2 = Vector2.ZERO
var _launch_origin:Vector2 = Vector2.ZERO
var _life_left:float = 0.0
var _visual_base_length:float = 32.0
var _visual_width:float = 2.8
var _visual_current_length:float = 32.0
var _visual_travel_distance:float = 0.0
var _visual_last_world_position:Vector2 = Vector2.ZERO
var _visual_last_redraw_length:float = 32.0


func _ready() -> void:
	Can_Attack = false
	Can_Skill = false
	Health_Restore = 0
	Has_Collision_Damage = true
	Collide_Audio = ""
	# 水滴自己在真实生命伤害确认后播放标准 balls_hit1；先关掉 base 的“伤害结算前”通用 Hit_Audio。
	Hit_Audio = ""
	super._ready()
	# V263：水滴只是攻击载体，不是可受击战斗目标。
	# base ball 对 Shooter 会给 Hurtbox 补碰撞层；这里在 super 后明确关闭其可监测性和层，
	# 让菊花茶水滴之间不会互相命中/抵消，也不会把彼此当受伤对象生成伤害跳字。
	if self_hurtbox != null:
		self_hurtbox.monitorable = false
		self_hurtbox.collision_layer = 0
	add_to_group("BattleTransient")
	add_to_group("ChrysanthemumTeaDroplet")
	_launch_origin = global_position
	_life_left = maxf(max_lifetime,0.2)
	# 每颗水滴出生时只做“小幅”长短/粗细差异，不让弹幕像复制粘贴。
	_visual_base_length = maxf(line_length,12.0) * randf_range(
		1.0 - clampf(line_length_variation,0.0,0.35),
		1.0 + clampf(line_length_variation,0.0,0.35)
	)
	_visual_width = maxf(line_width,1.0) * randf_range(
		1.0 - clampf(line_width_variation,0.0,0.35),
		1.0 + clampf(line_width_variation,0.0,0.35)
	)
	_visual_current_length = _visual_base_length
	_visual_last_redraw_length = _visual_current_length
	if ballistic_velocity.length_squared() <= 0.000001:
		var fallback:Vector2 = direction.normalized() if direction.length_squared() > 0.000001 else Vector2.RIGHT
		ballistic_velocity = fallback * maxf(Speed,60.0)
	_visual_travel_distance = 0.0
	_visual_last_world_position = global_position
	queue_redraw()
	_refresh_motion_visual(0.0,true)


func configure_parabolic_launch(
	start:Vector2,
	target:Vector2,
	fallback_direction:Vector2,
	target_velocity:Vector2 = Vector2.ZERO,
	launch_speed_hint:float = 520.0,
	gravity_strength:float = 720.0,
	prediction:float = 0.16,
	lifetime:float = 2.6,
	arc_time_scale:float = 1.0,
	vertical_aim_max_angle_deg:float = 26.0,
	vertical_aim_full_offset:float = 140.0
) -> void:
	global_position = start
	_launch_origin = start
	projectile_gravity = maxf(gravity_strength,0.0)
	max_lifetime = maxf(lifetime,0.2)
	_life_left = maxf(max_lifetime,0.2)

	var aim_direction:Vector2 = fallback_direction.normalized() if fallback_direction.length_squared() > 0.000001 else Vector2.RIGHT
	var speed_hint:float = maxf(launch_speed_hint,60.0)
	var flight_min:float = maxf(minf(minimum_flight_time,maximum_flight_time),0.10)
	var flight_max:float = maxf(maxf(minimum_flight_time,maximum_flight_time),flight_min)

	# V284：不再解一个“精确命中 target.xy”的抛体终点。
	# 只锁定敌人的 X：水平飞行时间只按 X 距离计算，Y 差只改变初始发射角。
	# 这样同 Y 时就是朝敌人位置的标准抛物线；敌人在上/下时只会让起射方向上抬/下压，
	# 且偏角由 vertical_aim_max_angle_deg 严格限制，不会无限追踪敌人的 Y。
	var raw_delta_x:float = target.x - start.x
	var initial_horizontal_distance:float = absf(raw_delta_x)
	var initial_flight_time:float = clampf(initial_horizontal_distance / speed_hint,flight_min,flight_max)
	initial_flight_time = clampf(initial_flight_time * clampf(arc_time_scale,0.60,1.70),flight_min,flight_max)

	# 只预判 X；Y 绝不做位置锁定。
	var predicted_target_x:float = target.x + target_velocity.x * initial_flight_time * clampf(prediction,0.0,1.0)
	var delta_x:float = predicted_target_x - start.x
	var horizontal_distance:float = absf(delta_x)
	var flight_time:float = clampf(horizontal_distance / speed_hint,flight_min,flight_max)
	flight_time = clampf(flight_time * clampf(arc_time_scale,0.60,1.70),flight_min,flight_max)

	var gravity_strength_safe:float = maxf(projectile_gravity,0.0)
	var vx:float = delta_x / maxf(flight_time,0.001)
	# “同 Y”按菊花茶人物本体中心，而不是按头顶出生点判断。
	# 因此两个人物中心同高时，基础抛物线会在目标 X 处落到敌人的同高位置。
	var vertical_reference_y:float = start.y
	if Master != null and is_instance_valid(Master) and Master is Node2D:
		vertical_reference_y = (Master as Node2D).global_position.y
	var base_arc_vy:float = (
		vertical_reference_y - start.y - 0.5 * gravity_strength_safe * flight_time * flight_time
	) / maxf(flight_time,0.001)

	var vertical_delta:float = target.y - vertical_reference_y
	var vertical_ratio:float = clampf(
		vertical_delta / maxf(vertical_aim_full_offset,20.0),
		-1.0,
		1.0
	)
	var max_angle_rad:float = deg_to_rad(clampf(vertical_aim_max_angle_deg,0.0,45.0))
	var angle_bias:float = vertical_ratio * max_angle_rad
	# 目标在上方：保留原高弧线并继续叠加“向上”有限偏角，所以会比同 Y 更明显上抬。
	# 目标在下方：随着 Y 差增大逐步削弱原本向上的基础弧线，再加入“向下”有限偏角，
	# 因而足够低的目标会真正向下起射。方向修正本身始终受 vertical_aim_max_angle_deg 限制。
	var angle_reference_speed:float = maxf(absf(vx),speed_hint * 0.55)
	var directional_vy:float = tan(angle_bias) * angle_reference_speed
	var vy:float = base_arc_vy + directional_vy
	if vertical_ratio > 0.0:
		vy = base_arc_vy * (1.0 - vertical_ratio) + directional_vy

	ballistic_velocity = Vector2(vx,vy)
	if ballistic_velocity.length_squared() <= 0.000001:
		ballistic_velocity = aim_direction * speed_hint

	direction = ballistic_velocity.normalized()
	Speed = maxf(ballistic_velocity.length(),1.0)
	_visual_travel_distance = 0.0
	_visual_last_world_position = global_position
	_refresh_motion_visual(0.0,true)

func tick_physics(state:State,delta:float) -> void:
	if is_multiplayer_authority() and state != State.Die and health > 0:
		ballistic_velocity += Vector2.DOWN * maxf(projectile_gravity,0.0) * maxf(delta,0.0)
		if ballistic_velocity.length_squared() > 0.000001:
			direction = ballistic_velocity.normalized()
			Speed = maxf(ballistic_velocity.length(),1.0)
		_life_left = maxf(_life_left - maxf(delta,0.0),0.0)
		if _life_left <= 0.0 or global_position.y > _launch_origin.y + maxf(fall_delete_distance,0.0):
			state_machine.current_state = State.Die
			return

	# 公共 ball.tick_physics() 会在这里把菊花茶重力场的外力速度继续叠加进 Repel，
	# 所以自己的水滴同样会被自己主人的重力技能弯折。
	super.tick_physics(state,delta)
	# V285：线长不再跟“速度大小”绑定。每个物理帧累计实际走过的世界距离，
	# 飞得越远只做很轻微的拉长；被重力加速/减速不会突然改变线长。
	if _visual_last_world_position == Vector2.ZERO:
		_visual_last_world_position = global_position
	else:
		_visual_travel_distance += global_position.distance_to(_visual_last_world_position)
		_visual_last_world_position = global_position
	_refresh_motion_visual(delta,false)


func _refresh_motion_visual(_delta:float = 0.0,force_redraw:bool = false) -> void:
	var visual_velocity:Vector2 = velocity if velocity.length_squared() > 0.000001 else ballistic_velocity
	if visual_velocity.length_squared() <= 0.000001:
		return
	# 线条沿本地 Y 轴绘制；CapsuleShape2D 也是 Y 轴长条，因此一起对准真实飞行方向。
	rotation = visual_velocity.angle() - PI * 0.5

	# V285：长度只随“累计运动距离”缓慢增加，不再跟瞬时速度比值变化。
	# 走满 distance_length_full_travel 后也最多只增大到约 1.07 倍，避免再次变成长绿条。
	var travel_ratio:float = clampf(
		_visual_travel_distance / maxf(distance_length_full_travel,1.0),
		0.0,
		1.0
	)
	var target_scale:float = lerpf(1.0,maxf(distance_length_max_scale,1.0),travel_ratio)
	_visual_current_length = maxf(_visual_base_length * target_scale,6.0)
	if force_redraw or absf(_visual_current_length - _visual_last_redraw_length) >= 0.10:
		_visual_last_redraw_length = _visual_current_length
		queue_redraw()

func _draw() -> void:
	var half_length:float = maxf(_visual_current_length,8.0) * 0.5
	var line_start:Vector2 = Vector2(0.0,-half_length)
	var line_end:Vector2 = Vector2(0.0,half_length)
	# 只用 Godot 代码画线，不生成/引用任何额外“水滴图片”。
	draw_line(line_start,line_end,line_glow_color,maxf(_visual_width * 2.0,0.8),true)
	draw_line(line_start,line_end,line_color,maxf(_visual_width,1.0),true)


func _on_hitbox_on_hit(hurt:hurtbox) -> void:
	if not is_multiplayer_authority():
		return
	var target:ball = _hurtbox_target_ball(hurt)
	var before_health:float = float(target.health) if target != null and is_instance_valid(target) else 0.0
	super._on_hitbox_on_hit(hurt)
	# 高频水滴只在“这次命中真的造成生命损失”后播放标准碰撞伤害音。
	# create_new_audio=true 允许连续命中自然叠加，不会每发都把上一声硬截断。
	if target != null and is_instance_valid(target) and float(target.health) < before_health:
		Audios.play_sfx.rpc("balls_hit1",{},true,true)
	state_machine.current_state = State.Die


func when_collide(_speed:float,_collision:KinematicCollision2D) -> void:
	if not is_multiplayer_authority():
		return
	state_machine.current_state = State.Die


func Die() -> void:
	if not is_multiplayer_authority():
		return
	visible = false
	await get_tree().create_timer(0.04).timeout
	if is_instance_valid(self):
		Game.free_node(self)
