extends "res://scripts/characters/我的世界/重锤.gd"

const ROCKET_TRAIL:Script = preload("res://scripts/effects/我的世界/elytra_firework_trail.gd")
var _firework_trail:Node2D

@export_category("鞘翅 / 滑翔与烟花")
@export var glide_gravity:float = 135.0
@export var glide_drag:float = 0.12
@export var glide_turn_rate:float = 10.0
@export var firework_interval:float = 1.1
@export var firework_duration:float = 0.38
@export var firework_acceleration:float = 1150.0
@export var smash_gravity:float = 900.0
enum FlightMode { GLIDE, CLIMB, DIVE, REBOUND }
@export var launch_speed:float = 280.0
@export var maximum_flight_speed:float = 900.0
@export var dive_setup_height:float = 85.0
enum FlightTactic { INTERCEPT, LOFT, FLANK, EXTEND }
var _flight_tactic:FlightTactic = FlightTactic.INTERCEPT
var _tactical_aim:Vector2 = Vector2.RIGHT
var _boost_direction:Vector2 = Vector2.RIGHT
var _tactic_hold:float = 0.0
var _tactic_side:float = 1.0
var _flight_mode:FlightMode = FlightMode.GLIDE
var _mode_elapsed:float = 0.0
var _wing_spread:float = 0.52
var _wing_bank:float = 0.0
var _previous_heading:float = 0.0
var _pvp_target:ball
var _glide_velocity:Vector2 = Vector2.ZERO
var _rocket_cooldown:float = 0.8
var _rocket_remaining:float = 0.0
var _launch_y:float = 0.0
var _patrol_rect:Rect2 = Rect2()
var _patrol_rect_refresh:float = 0.0
var _patrol_recovering:bool = false
var _patrol_clockwise:float = 1.0
var _patrol_initialized:bool = false
var _rebound_side:float = 1.0
var _rebound_diving:bool = false
var _rebound_origin:Vector2 = Vector2.ZERO
var _rocket_visual:Sprite2D
var _rocket_display_left:float = 0.0
var _launch_audio:AudioStreamPlayer2D
var _glide_audio:AudioStreamPlayer2D

func _ready() -> void:
	# 世界层救回与三秒出界淘汰必须同时豁免，单关碰撞层不够。
	set_meta(&"submission_allow_map_escape",true)
	Max_health = 200
	super._ready()
	# 仅取消身体阻挡；Hurtbox 仍正常接收攻击，绝非无敌。
	collision_mask = 0
	collision_layer = 0
	_glide_velocity = Vector2(1.0,-0.3).normalized() * launch_speed
	graphics.z_index = 101
	health_bar.z_index = 102
	_rocket_visual = graphics.get_node_or_null("Firework") as Sprite2D
	_launch_audio = get_node("FireworkAudio") as AudioStreamPlayer2D
	_glide_audio = get_node("GlideAudio") as AudioStreamPlayer2D
	$CollisionShape2D.set_deferred("disabled",true)
	visual_scale_gain_per_world_height = 0.0
	swing_peak_scale_multiplier = 1.0
	_layout_equipment()

func tick_physics(state:State,delta:float) -> void:
	# 其他系统（大规模战斗/门/击退）可能恢复身体碰撞，持续保持飞行契约。
	collision_mask = 0
	collision_layer = 0
	super.tick_physics(state,delta)
	if is_combat_runtime_active():
		_rocket_display_left = maxf(_rocket_display_left - delta,0.0)
	_update_flight_media()
	if is_combat_runtime_active():
		_update_wing_animation(delta)

func _update_flight_media() -> void:
	var active:bool = health > 0 and is_combat_runtime_active()
	if _rocket_visual != null:
		_rocket_visual.visible = active and _rocket_display_left > 0.0
		# 固定在角色右下侧，不随速度旋转到身体左上角。
		var body_size:float = WEAPON_VISUAL_SIZE.visible_long_edge((image as Sprite2D).texture) * _air_visual_base_scale.x
		_rocket_visual.position = Vector2(body_size * 0.62,body_size * 0.55).rotated(-graphics.rotation)
		_rocket_visual.rotation = -graphics.rotation
	if _glide_audio != null:
		_glide_audio.stream_paused = not active
		if active and not _glide_audio.playing:
			_glide_audio.play()
	if _launch_audio != null:
		_launch_audio.stream_paused = not active
	if not active and health <= 0:
		_glide_audio.stop()
		_launch_audio.stop()

@rpc("authority","call_local","reliable")
func _show_firework() -> void:
	_rocket_display_left = maxf(firework_duration,0.5)
	if not is_instance_valid(_firework_trail) or _firework_trail.is_queued_for_deletion():
		_firework_trail = ROCKET_TRAIL.new()
		get_tree().current_scene.add_child(_firework_trail)
	_firework_trail.begin(self,1.0)
	if _launch_audio != null:
		_launch_audio.play()
	_update_flight_media()

func _is_character_ground_shadow_owner() -> bool:
	return false

func move(_speed:float,delta:float) -> void:
	if _airborne or health <= 0 or not is_combat_runtime_active():
		return
	_step_glide(delta)

func stand(delta:float) -> void:
	move(Speed,delta)

func _nearest_flight_enemy() -> ball:
	var nearest:ball = null
	var distance:float = INF
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if node is ball and _is_enemy(node as ball):
			var d:float = global_position.distance_squared_to((node as ball).global_position)
			if d < distance:
				distance = d
				nearest = node as ball
	return nearest

func _flight_target() -> ball:
	if not is_instance_valid(_pvp_target) or not _is_enemy(_pvp_target):
		_pvp_target = _nearest_flight_enemy()
	return _pvp_target

func _patrol_aim(delta:float) -> Vector2:
	_patrol_rect_refresh -= delta
	var scene:Node = get_tree().current_scene
	if _patrol_rect_refresh <= 0.0:
		_patrol_rect_refresh = 0.5
		_patrol_rect = Rect2()
		if scene != null and scene.has_method("current_map_island_rects"):
			var rects:Array = scene.call("current_map_island_rects")
			for raw:Variant in rects:
				var rect:Rect2 = raw
				if rect.size.x > 0.0 and rect.size.y > 0.0:
					_patrol_rect = rect if _patrol_rect.size == Vector2.ZERO else _patrol_rect.merge(rect)
	if _patrol_rect.size == Vector2.ZERO:
		return _glide_velocity.normalized()
	_flight_mode = FlightMode.GLIDE
	var center:Vector2 = _patrol_rect.get_center()+Vector2(0,-_patrol_rect.size.y*0.12)
	var radii:Vector2 = Vector2(maxf(_patrol_rect.size.x*0.55,100.0),maxf(_patrol_rect.size.y*0.52,80.0))
	var relative:Vector2 = (global_position-center)/radii
	var angle:float = relative.angle()
	var tangent:Vector2 = Vector2(-sin(angle)*radii.x,cos(angle)*radii.y).normalized()
	if not _patrol_initialized:
		_patrol_clockwise = 1.0 if tangent.dot(_glide_velocity) >= 0.0 else -1.0
		_patrol_initialized = true
	tangent *= _patrol_clockwise
	# 前瞻低高度/快速下坠；恢复到中心线上方再退出，避免阈值附近反复点火。
	var low_line:float = _patrol_rect.end.y-maxf(_patrol_rect.size.y*0.12,35.0)
	if global_position.y+maxf(_glide_velocity.y,0.0)*0.4 > low_line:
		_patrol_recovering = true
	elif global_position.y < center.y:
		_patrol_recovering = false
	# 低高度只决定何时点火，不覆盖巡航方向；旧版强行左上拉升会切掉右半圈。
	# 椭圆切向速度 + 径向误差纠正。避免高速侧前瞻角变大、反复切弯导致偏心。
	var radial:Vector2 = Vector2(relative.x/radii.x,relative.y/radii.y).normalized()
	var error:float = relative.length()-1.0
	var correction:float = clampf(error*3.5,-1.5,1.5)
	return (tangent-radial*correction).normalized()

func _choose_flight_tactic(target:ball,delta:float) -> Vector2:
	if target == null:
		if is_player_controlled():
			return player_control_direction.normalized() if player_control_direction.length_squared() > 0.001 else _glide_velocity.normalized()
		return _patrol_aim(delta)
	_patrol_recovering = false
	var offset:Vector2 = target.global_position-global_position
	var distance:float = offset.length()
	var speed:float = maxf(_glide_velocity.length(),1.0)
	var prediction:float = clampf(distance/speed,0.04,0.4)
	var predicted:Vector2 = target.global_position+target.velocity*prediction
	var alignment:float = _glide_velocity.normalized().dot(offset.normalized())
	_tactic_hold -= delta
	if _tactic_hold <= 0.0:
		# 依据几何、敌人走位和自身动量选招，既非随机乱转，也非固定招式循环。
		var movement_x:float = target.velocity.x if absf(target.velocity.x) > 20.0 else _glide_velocity.x
		_tactic_side = signf(movement_x) if absf(movement_x) > 1.0 else (1.0 if offset.x >= 0.0 else -1.0)
		if (_glide_velocity.y > 60.0 and offset.y > -25.0 and distance < 150.0) or (offset.y > 38.0 and (alignment > -0.55 or distance > 180.0)):
			_flight_tactic = FlightTactic.INTERCEPT
		elif distance < 150.0 and alignment < -0.25 and speed > 220.0:
			_flight_tactic = FlightTactic.EXTEND
		elif offset.y < -35.0 or distance < 85.0:
			_flight_tactic = FlightTactic.LOFT
		elif absf(target.velocity.x) > 35.0 and absf(offset.x) > 90.0 and offset.y < 55.0:
			_flight_tactic = FlightTactic.FLANK
		else:
			_flight_tactic = FlightTactic.INTERCEPT
		# 决策有短暂保持，转身角度大时多给一点时间，避免左右抖动。
		_tactic_hold = clampf(0.16+(1.0-alignment)*0.10,0.16,0.36)
	var aim:Vector2
	match _flight_tactic:
		FlightTactic.LOFT:
			# 缺少落差时斜向拉升，横向取敌人走位或当前惯性；从不锁死正上。
			var horizontal:float = clampf((predicted.x-global_position.x)*0.6,-140.0,140.0)
			if absf(horizontal) < 55.0: horizontal = _tactic_side*75.0
			aim = Vector2(horizontal,-maxf(90.0,-offset.y+55.0))
			_flight_mode = FlightMode.CLIMB
		FlightTactic.FLANK:
			aim = predicted+Vector2(_tactic_side*65.0,-70.0)-global_position
			_flight_mode = FlightMode.GLIDE
		FlightTactic.EXTEND:
			aim = Vector2(_tactic_side*130.0,-90.0)
			_flight_mode = FlightMode.GLIDE
		_:
			# 有落差直接冲敌人；远距离同高则掠向其上方，边追边取得攻击角度。
			aim = predicted-global_position
			var committed_pass:bool = _glide_velocity.y > 60.0 and offset.y > -25.0 and distance < 150.0
			if offset.y < 38.0 and not committed_pass: aim.y -= minf(distance*0.25,65.0)
			_flight_mode = FlightMode.DIVE if offset.y > 20.0 or committed_pass else FlightMode.GLIDE
	return aim.normalized() if aim.length_squared() > 0.001 else _glide_velocity.normalized()

func _wants_tactical_firework(target:ball,aim:Vector2) -> bool:
	if _rocket_cooldown > 0.0 or _rocket_remaining > 0.0 or Attacking or dizziness:
		return false
	var speed:float = _glide_velocity.length()
	if target == null:
		if not is_player_controlled() and _patrol_rect.size != Vector2.ZERO:
			# 低空等路线转入爬升段再加速，避免下行段点火把自己推出轨道。
			return aim.y < -0.10 and (_patrol_recovering or speed < 250.0)
		return speed < launch_speed*0.75 and aim.length_squared() > 0.001
	var offset:Vector2 = target.global_position-global_position
	var distance:float = offset.length()
	# 已有高速命中线就不浪费烟花；需要追击、抬高、脱离或补速时才用。
	if _flight_mode == FlightMode.DIVE and distance < 70.0 and speed > 260.0:
		return false
	if _flight_tactic in [FlightTactic.LOFT,FlightTactic.EXTEND]:
		return speed < 580.0 or offset.y < 25.0
	return speed < 310.0 or (distance > 200.0 and speed < 620.0) or (_flight_mode == FlightMode.DIVE and distance > 90.0 and speed < 500.0)

func _step_glide(delta:float) -> void:
	_rocket_cooldown -= delta
	_mode_elapsed += delta
	var target:ball = null if is_player_controlled() else _flight_target()
	var aim:Vector2 = _choose_flight_tactic(target,delta) if not dizziness else _glide_velocity.normalized()
	_tactical_aim = aim
	if _wants_tactical_firework(target,aim):
		_use_firework(aim)
	_glide_velocity *= exp(-glide_drag*delta)
	_glide_velocity.y += glide_gravity*delta
	if aim.length_squared() > 0.001 and not dizziness:
		# 按角速度限制转弯，保留高速掠过的惯性，不瞬间180度折返。
		var turn_rate:float = 5.5 if _flight_mode == FlightMode.DIVE else 3.8
		if target != null and _flight_tactic == FlightTactic.INTERCEPT:
			# 高速近身时缩小转弯半径，不靠刹车，也不让目标永远落在转弯圆内。
			var range_to_target:float = global_position.distance_to(target.global_position)
			turn_rate = maxf(turn_rate,clampf(_glide_velocity.length()/maxf(range_to_target*0.65,65.0),3.8,9.0))
		if target == null and not is_player_controlled() and _patrol_rect.size != Vector2.ZERO:
			var orbit_radius:float = maxf(minf(_patrol_rect.size.x*0.55,_patrol_rect.size.y*0.52),80.0)
			turn_rate = clampf(_glide_velocity.length()/orbit_radius*2.2,3.8,9.0)
		var heading:float = rotate_toward(_glide_velocity.angle(),aim.angle(),turn_rate*delta)
		_glide_velocity = Vector2.from_angle(heading)*_glide_velocity.length()
	if _rocket_remaining > 0.0:
		var burn:float = minf(delta,_rocket_remaining)
		_rocket_remaining = maxf(_rocket_remaining-delta,0.0)
		# 烟花沿当前选定的飞行/瞄准方向推进，允许向敌人冲刺和斜向调整。
		_boost_direction = Vector2.from_angle(rotate_toward(_boost_direction.angle(),aim.angle(),3.0*delta))
		_glide_velocity += _boost_direction*firework_acceleration*burn
	# 只给无敌巡航增加超速阻力，防止烟花把转弯半径推到地图之外；战斗速度不受影响。
	if target == null and not is_player_controlled() and _patrol_rect.size != Vector2.ZERO and _glide_velocity.length() > 380.0:
		var cruise_speed:float = lerpf(_glide_velocity.length(),380.0,1.0-exp(-3.0*delta))
		_glide_velocity = _glide_velocity.normalized()*cruise_speed
	_glide_velocity = _glide_velocity.limit_length(maximum_flight_speed)
	velocity = _glide_velocity+Repel
	var start:Vector2 = global_position
	var finish:Vector2 = start+velocity*delta
	if velocity.y > 35.0 and _flight_mode == FlightMode.DIVE and not Attacking and not dizziness and not is_damage_output_disabled():
		var steps:int = maxi(1,int(ceil(start.distance_to(finish)/4.0)))
		for i:int in range(1,steps+1):
			global_position = start.lerp(finish,float(i)/float(steps))
			if _try_dive_smash():
				_face_flight_direction()
				return
	global_position = finish
	_face_flight_direction()

func _try_dive_smash() -> bool:
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if node is ball and _is_enemy(node as ball) and _target_overlaps_damage_circle(node as ball,global_position,base_landing_radius):
			_airborne = true
			Attacking = true
			_chain_level = 1
			_chain_damage_multiplier = base_landing_damage_multiplier
			_flight_height = maxf(dive_setup_height,base_flight_height)
			_finish_landing()
			return true
	return false

func _use_firework(boost_direction:Vector2 = Vector2.ZERO) -> void:
	var requested:Vector2 = boost_direction
	if requested.length_squared() < 0.001:
		requested = _choose_flight_tactic(null if is_player_controlled() else _flight_target(),0.0)
	if requested.length_squared() < 0.001: requested = Vector2.RIGHT
	_boost_direction = requested.normalized()
	if multiplayer.has_multiplayer_peer():
		_show_firework.rpc()
	else:
		_show_firework()
	# 这是最短再次使用间隔，不是定时触发器；到点也必须满足战术需求。
	_rocket_cooldown = maxf(firework_interval,0.1)
	_rocket_remaining = maxf(firework_duration,0.01)
	# 不把已有动量强制改成正上，也不在烟花刚点燃时瞬移式转头。

func _begin_flight(level:int) -> void:
	var incoming:Vector2 = _glide_velocity
	var target:ball = _flight_target()
	# 静止目标也不能每击都垂直弹跳：沿入射惯性掠到侧上方，下一击换角度。
	if target != null and absf(target.velocity.x) > 25.0:
		_rebound_side = signf(target.velocity.x)
	elif absf(incoming.x) > 70.0:
		_rebound_side = signf(incoming.x)
	else:
		_rebound_side = -_rebound_side
	super._begin_flight(level)
	_flight_mode = FlightMode.REBOUND
	_mode_elapsed = 0.0
	_launch_y = global_position.y
	_rebound_origin = global_position
	_rebound_diving = false
	_rocket_remaining = 0.0
	# 不重置烟花冷却：连击空中也允许按需补位，不能每跳都把冷却重新锁满。
	var lift:float = sqrt(2.0*maxf(smash_gravity,1.0)*maxf(_flight_height,1.0))
	var lateral:float = incoming.x*0.8 + _rebound_side*clampf(lift*0.38,100.0,210.0)
	_glide_velocity = Vector2(clampf(lateral,-maximum_flight_speed*0.65,maximum_flight_speed*0.65),-lift*0.90)
	velocity = _glide_velocity
	_face_flight_direction()

func _end_missed_rebound() -> void:
	_airborne = false
	Attacking = false
	_chain_level = 1
	_chain_damage_multiplier = 0.0
	_recover_from_landing_pose()

func _update_flight(delta:float) -> void:
	if not is_combat_runtime_active():
		return
	_rocket_cooldown -= delta
	if is_damage_output_disabled():
		_end_missed_rebound()
		return
	var target:ball = _flight_target()
	# 子步内同时更新转向、重力和攻击，真实轨迹可斜升、侧移、回转再砸。
	var steps:int = maxi(1,int(ceil((_glide_velocity.length()*delta+smash_gravity*delta*delta)/4.0)))
	var dt:float = delta/float(steps)
	for i:int in range(steps):
		_flight_elapsed += dt
		var aim:Vector2 = _glide_velocity.normalized()
		var distance:float = 0.0
		if is_player_controlled() and player_control_direction.length_squared() > 0.001:
			aim = player_control_direction.normalized()
			_rebound_diving = aim.y > 0.1
		elif target != null and is_instance_valid(target):
			distance = global_position.distance_to(target.global_position)
			var prediction:float = clampf(distance/maxf(_glide_velocity.length(),100.0),0.05,0.35)
			var predicted:Vector2 = target.global_position+target.velocity*prediction
			var clearance:float = target.global_position.y-global_position.y
			if _flight_elapsed > 0.16 and (clearance > minf(_flight_height*0.65,125.0) or _flight_elapsed > 0.55):
				_rebound_diving = true
			if _rebound_diving:
				aim = (predicted-global_position).normalized()
			else:
				var lateral_gap:float = clampf(_flight_height*0.85,60.0,140.0)
				var flank:Vector2 = predicted+Vector2(_rebound_side*lateral_gap,-maxf(_flight_height,75.0))
				aim = (flank-global_position).normalized()
			# 目标闪开、横向距离大或失速时，允许在本轮连击内用烟花修正。
			if _rocket_cooldown <= 0.0 and _rocket_remaining <= 0.0 and not dizziness and _flight_elapsed > 0.20 and (distance > 155.0 or _glide_velocity.length() < 180.0):
				_use_firework(aim)
		_glide_velocity *= exp(-glide_drag*dt)
		_glide_velocity.y += smash_gravity*0.40*dt
		if aim.length_squared() > 0.001 and not dizziness:
			var turn:float = clampf(_glide_velocity.length()/maxf(distance*0.55,45.0),5.5,10.0) if _rebound_diving else 3.2
			var heading:float = rotate_toward(_glide_velocity.angle(),aim.angle(),turn*dt)
			_glide_velocity = Vector2.from_angle(heading)*_glide_velocity.length()
		if _rocket_remaining > 0.0:
			var burn:float = minf(dt,_rocket_remaining)
			_rocket_remaining = maxf(_rocket_remaining-dt,0.0)
			_boost_direction = Vector2.from_angle(rotate_toward(_boost_direction.angle(),aim.angle(),3.0*dt))
			_glide_velocity += _boost_direction*firework_acceleration*burn
		_glide_velocity = _glide_velocity.limit_length(maximum_flight_speed)
		velocity = _glide_velocity
		global_position += velocity*dt
		if _glide_velocity.y > 35.0:
			var radius:float = base_landing_radius+landing_radius_gain*float(_chain_level-1)
			for node:Node in get_tree().get_nodes_in_group("Ball"):
				if node is ball and _is_enemy(node as ball) and _target_overlaps_damage_circle(node as ball,global_position,radius):
					_finish_landing()
					_face_flight_direction()
					return
		# 不再将起跳Y坐标当成地板。可继续追到更低位置，只在本轮确实失去机会后结束。
		if _flight_elapsed > 2.8 or (target == null and _flight_elapsed > 1.1):
			_end_missed_rebound()
			break
	_face_flight_direction()

func _ground_impact_center() -> Vector2:
	return global_position

func _sync_air_visual_followers() -> void:
	# 根节点已经真实起跳，禁止父类再给图片/血条添加假高度。
	if graphics != null:
		graphics.position = _visual_base_position
	if health_bar != null:
		health_bar.position = _health_bar_base_position
	if _rocket_visual != null:
		_rocket_visual.visible = _rocket_display_left > 0.0 and health > 0

func _layout_equipment() -> void:
	# 根节点缩放是 0.2，旧版16px附件再次缩小后仅3px且藏在锤子下。
	# 用锤子实际可见像素作为基准，在同一坐标系内布局。
	var body_size:float = WEAPON_VISUAL_SIZE.visible_long_edge((image as Sprite2D).texture) * image.scale.x
	var wings:Node2D = graphics.get_node_or_null("Elytra") as Node2D
	if wings != null:
		wings.show_behind_parent = false
		wings.z_index = 2
		wings.scale = Vector2.ONE * body_size / 34.0
		wings.rotation = 0.0
	if _rocket_visual != null:
		_rocket_visual.scale = Vector2.ONE * body_size * 0.55 / 16.0
		_rocket_visual.z_index = 3

func _face_flight_direction() -> void:
	if graphics == null:
		return
	if velocity.length_squared() > 0.001:
		direction = velocity.normalized()
		graphics.rotation = velocity.angle() + PI * 0.5
	# Graphics只负责飞行朝向，Image只负责重锤动作，两层自然叠加。
	if _airborne:
		image.rotation = deg_to_rad(base_spin_speed_degrees + _flight_height * spin_speed_per_height) * _flight_elapsed
		image.scale = _air_visual_base_scale
	elif not Attacking:
		image.rotation = 0.0
		image.scale = _air_visual_base_scale
	_layout_equipment()

func _perform_opening_swing(attack_dir:Vector2) -> int:
	# 父类写Image局部旋转；先将世界攻击方向转换到当前飞行朝向的局部空间。
	return await super._perform_opening_swing(attack_dir.rotated(-graphics.global_rotation))

func _opening_swing_head_position(attack_dir:Vector2,local_angle:float,scale_multiplier:float = 1.0) -> Vector2:
	var world_angle:float = graphics.global_rotation + attack_dir.angle() + local_angle
	return global_position + Vector2.from_angle(world_angle) * swing_hammer_head_reach * scale_multiplier

func _swing_scale_multiplier(_t:float) -> float:
	return 1.0

func _recover_from_landing_pose() -> void:
	_flight_mode = FlightMode.GLIDE
	_tactic_hold = 0.0
	_face_flight_direction()

func get_projectile_embed_local_transform(world_pose:Transform2D) -> Transform2D:
	return image.global_transform.affine_inverse() * world_pose

func _update_wing_animation(delta:float) -> void:
	var wings:Node2D = graphics.get_node_or_null("Elytra") as Node2D
	if wings == null:
		return
	# Mojang animation.elytra.gliding：俯冲越陡，ratio越小，翼角从90度收至15度。
	# 原版为3D骨骼，这里将Z翼角和转弯倾斜映射到2D附件，不做鸟类扑翼。
	var motion:Vector2 = velocity.normalized()
	var ratio:float = 1.0 - pow(maxf(motion.y,0.0),1.5)
	var spread:float = deg_to_rad(lerpf(15.0,90.0,ratio))
	var heading:float = velocity.angle() if velocity.length_squared() > 0.01 else _previous_heading
	var turn:float = clampf(angle_difference(_previous_heading,heading)/maxf(delta,0.001),-3.0,3.0)
	_previous_heading = heading
	var blend:float = 1.0-exp(-12.0*delta)
	_wing_spread = lerpf(_wing_spread,spread,blend)
	_wing_bank = lerpf(_wing_bank,turn*0.08,blend)
	var left:Sprite2D = wings.get_node("Left") as Sprite2D
	var right:Sprite2D = wings.get_node("Right") as Sprite2D
	left.rotation = _wing_spread + _wing_bank
	right.rotation = -_wing_spread + _wing_bank
	left.position = Vector2(-lerpf(6.0,13.0,ratio),6.0)
	right.position = Vector2(lerpf(6.0,13.0,ratio),6.0)
	left.scale = Vector2(1.6,lerpf(1.45,1.75,ratio))
	right.scale = Vector2(1.6,lerpf(1.45,1.75,ratio))
