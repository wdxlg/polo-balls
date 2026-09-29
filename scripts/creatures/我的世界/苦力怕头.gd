extends ball
const U=preload("res://scripts/characters/我的世界/new5/utils.gd")

const HEAD_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/苦力怕/苦力怕头.png")
const EXPLOSION_EFFECT_SCENE:PackedScene = preload("res://scenes/effects/我的世界/MC爆炸.tscn")
const DEATH_SMOKE_FRAMES:SpriteFrames = preload("res://scenes/effects/我的世界/蠹虫死亡烟雾.tres")
const FUSE_SOUND:AudioStream = preload("res://audio/characters/我的世界/苦力怕/爆炸准备.ogg")
const DEATH_SOUND:AudioStream = preload("res://audio/characters/我的世界/苦力怕/死亡.ogg")

const DEATH_POSE_DURATION:float = 0.62
const EXPLOSION_VISUAL_HOLD:float = 1.02

# V114：二阶段苦力怕头沿用本体的新引信条视觉，保持前后阶段一致。
const FUSE_BAR_RECT:Rect2 = Rect2(-65.0,52.0,130.0,17.0)
const FUSE_BAR_OUTER_PAD:float = 4.0
const FUSE_BAR_BORDER_WIDTH:float = 2.5
const FUSE_BAR_OUTER_COLOR:Color = Color(0.02,0.02,0.025,0.92)
const FUSE_BAR_BACKGROUND_COLOR:Color = Color(0.12,0.12,0.14,1.0)
const FUSE_BAR_BORDER_COLOR:Color = Color(0.78,0.82,0.88,0.86)
const FUSE_BAR_START_COLOR:Color = Color(1.0,1.0,1.0,1.0)
const FUSE_BAR_END_COLOR:Color = Color(1.0,0.08,0.04,1.0)

@export_category("苦力怕头 / 视觉")
# V85：苦力怕本体场景的正常碰撞宽度为 78；头的独立贴图按同一局部宽度适配，
# 不再依赖源图片分辨率或旧的固定 0.18 scale。根 ball.tscn 自带 0.2 scale，
# 因此 78 局部单位会和本体正常状态的头部量级保持一致。
@export_range(16.0,160.0,1.0) var normal_head_local_size:float = 78.0

@export_category("苦力怕头 / 引信")
@export_range(16.0,180.0,1.0) var fuse_start_radius:float = 50.0
@export_range(20.0,220.0,1.0) var fuse_cancel_radius:float = 50.0
@export_range(0.6,5.0,0.05) var fuse_duration:float = 2.80
@export_range(0.0,2.0,0.05) var fuse_decay_delay:float = 0.55
@export_range(0.05,3.0,0.05) var fuse_decay_acceleration:float = 0.55
@export_range(0.10,4.0,0.05) var fuse_decay_max_speed:float = 1.60
@export_range(0.05,1.0,0.01) var fuse_final_speed_ratio:float = 0.24
@export_range(1.0,1.8,0.01) var fuse_final_scale:float = 1.18 # V90：延长引信后能明显看到这段轻微放大

@export_category("苦力怕头 / 爆炸")
@export_range(10.0,240.0,1.0) var explosion_damage:float = 58.0
@export_range(20.0,220.0,1.0) var explosion_radius:float = 40.0
@export_range(0.0,200.0,1.0) var knockback_distance:float = 54.0
@export_range(50.0,1200.0,10.0) var knockback_speed:float = 520.0

@export_category("苦力怕头 / 爆炸飞行")
# V84：沿用 V83 “无重力弹球”的速度曲线；当速度降到本角色正常世界移动速度时切回原 AI。
@export_range(20.0,1200.0,10.0) var launch_speed_min:float = 260.0
@export_range(20.0,1200.0,10.0) var launch_speed_max:float = 420.0
@export_range(0.05,3.0,0.05) var launch_acceleration_duration:float = 0.65
@export_range(0.0,1600.0,10.0) var launch_acceleration_strength:float = 300.0
@export_range(0.0,1200.0,10.0) var launch_deceleration_start:float = 80.0
@export_range(0.0,1600.0,10.0) var launch_deceleration_growth:float = 260.0
@export_range(0.05,1.0,0.01) var launch_bounce_retention:float = 0.78
@export_range(0.0,1.0,0.01) var launch_collision_tangent_friction:float = 0.08
@export_range(0.0,500.0,1.0) var launch_collision_damage:float = 70.0
@export_range(20.0,1200.0,10.0) var launch_collision_damage_reference_speed:float = 420.0
@export_range(0.02,1.0,0.01) var launch_hit_cooldown:float = 0.18
@export_range(1,8,1) var launch_max_collisions_per_tick:int = 4
@export_range(0.0,20.0,0.1) var launch_spin_speed_min:float = 5.0
@export_range(0.0,30.0,0.1) var launch_spin_speed_max:float = 9.0
@export_range(1.0,3.0,0.05) var charged_launch_force_multiplier:float = 1.65
@export_range(0.1,2.0,0.05) var launch_rotation_recover_duration:float = 0.85

@onready var fuse_audio:AudioStreamPlayer2D = $FuseAudio
@onready var death_audio:AudioStreamPlayer2D = $DeathAudio
@onready var fuse_progress:ProgressBar = $FuseProgress
@onready var fuse_white_overlay:Sprite2D = $Graphics/FuseWhiteOverlay

var _rng := RandomNumberGenerator.new()
var _fusing:bool = false
var _fuse_advancing:bool = false
var _fuse_elapsed:float = 0.0
var _fuse_decay_elapsed:float = 0.0
var _fuse_visual_clock:float = 0.0
var _current_fuse_duration:float = 2.8
var _fuse_target_id:int = 0
var _exploded:bool = false
var _death_sequence_started:bool = false
var _graphics_base_position:Vector2 = Vector2.ZERO
var _graphics_base_scale:Vector2 = Vector2.ONE
var _foot_anchor_parent:Vector2 = Vector2.ZERO
var _foot_anchor_child:Vector2 = Vector2.ZERO

var _launch_active:bool = false
var _launch_age:float = 0.0
var _launch_spin_speed:float = 0.0
var _launch_last_hit_msec_by_target:Dictionary = {}
var _launch_original_collision_mask:int = 0
var _launch_force_multiplier:float = 1.0
var _post_launch_normal_move:bool = false
var _rotation_recovery_active:bool = false
var _rotation_recovery_elapsed:float = 0.0
var _rotation_recovery_from:float = 0.0


func _ready() -> void:
	manual_controllable_subentity = true
	Has_Collision_Damage = false
	Can_Attack = false
	Can_Skill = false
	Health_Restore = 0
	dir_left = false # 头颅素材原生朝右；向左移动时才翻转。
	if image is Sprite2D:
		var sprite := image as Sprite2D
		sprite.texture = HEAD_TEXTURE
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# V85：以正常苦力怕本体 78 局部宽度为基准自动缩放独立头贴图。
		# 使用贴图最大边做适配，避免素材分辨率变化后头又突然变大。
		var texture_size:Vector2 = HEAD_TEXTURE.get_size()
		var max_dimension:float = maxf(maxf(texture_size.x,texture_size.y),1.0)
		var head_scale:float = maxf(normal_head_local_size,1.0) / max_dimension
		sprite.scale = Vector2.ONE * head_scale
		# V86：独立全白覆盖层跟随头贴图的真实尺寸/偏移，不再只依赖公共受击 Shader。
		if fuse_white_overlay != null:
			fuse_white_overlay.texture = HEAD_TEXTURE
			fuse_white_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			fuse_white_overlay.position = sprite.position
			fuse_white_overlay.scale = sprite.scale
			fuse_white_overlay.offset = sprite.offset
			fuse_white_overlay.centered = sprite.centered
			fuse_white_overlay.set_instance_shader_parameter("power",0.0)
			fuse_white_overlay.hide()
	super._ready()
	# 原 ProgressBar 只保留数值，不再显示默认 UI；视觉由 _draw() 绘制。
	if fuse_progress != null:
		fuse_progress.hide()
	_rng.seed = Game.battle_rng_seed_or("scripts/creatures/我的世界/苦力怕头.gd:_rng.seed",maxi(abs(int(Time.get_ticks_usec()) ^ int(get_instance_id())),1))
	_capture_visual_base()


func tick_physics(state:State,delta:float) -> void:
	if _exploded or _death_sequence_started:
		return

	# 爆炸飞行期间完全接管根 CharacterBody2D 的运动，暂停普通移动、索敌与引信。
	# authority 负责真实物理/伤害；远端只显示 MultiplayerSynchronizer 同步的位置与 Graphics 旋转。
	if _launch_active:
		if is_multiplayer_authority() and health > 0 and is_combat_runtime_active():
			_tick_explosion_launch(delta)
		return

	# V87：V86 只在飞行结束瞬间写了一次 velocity，后续仍依赖传入 state。
	# 某些生成/状态切换时序会让 state 留在 Stand，于是下一帧 super.tick_physics()
	# 立刻执行 stand() 把速度清零。飞行结束后的头明确进入“正常移动已恢复”模式：
	# 只要仍可移动且未眩晕，就强制走公共 ball.move()；碰撞、Buff、击退等仍全部走公共链。
	var effective_state:State = state
	if _post_launch_normal_move and Speed > 0.0 and not dizziness:
		# V88：飞行结束后就是普通移动阶段。若方向被其它公共逻辑清空，
		# 在允许角色移动时立刻补一个方向，避免二阶段头再次永久停住。
		if direction.length_squared() <= 0.000001 and Game.Game_Settings.Ball_Can_Move and not is_player_controlled():
			direction = Vector2.RIGHT.rotated(_rng.randf_range(0.0,TAU))
		effective_state = State.Move
	super.tick_physics(effective_state,delta)
	_tick_rotation_recovery(delta)
	if _fusing:
		_advance_fuse_progress(delta)
	_update_fuse_visual()
	if not is_multiplayer_authority() or health <= 0 or not is_combat_runtime_active():
		return
	# V92：头和正常苦力怕使用同一套“靠近才累计、离开后延迟回退”的引信逻辑。
	# 不再是敌人只要进过一次范围，就无条件倒计时到爆炸。
	_update_fuse_logic(delta)


func begin_explosion_launch(initial_direction:Vector2 = Vector2.ZERO,charged_launch:bool = false) -> void:
	if not is_multiplayer_authority() or _exploded or _death_sequence_started:
		return
	var launch_direction:Vector2 = initial_direction
	if launch_direction.length_squared() <= 0.000001:
		launch_direction = Vector2.RIGHT.rotated(_rng.randf_range(0.0,TAU))
	else:
		launch_direction = launch_direction.normalized()

	var low:float = minf(launch_speed_min,launch_speed_max)
	var high:float = maxf(launch_speed_min,launch_speed_max)
	_launch_force_multiplier = maxf(charged_launch_force_multiplier,1.0) if charged_launch else 1.0
	var initial_speed:float = _rng.randf_range(maxf(low,1.0),maxf(high,1.0)) * _launch_force_multiplier
	velocity = launch_direction * initial_speed
	direction = launch_direction
	Repel = Vector2.ZERO
	_launch_original_collision_mask = collision_mask
	# 飞行期必须同时撞地图层 1 和角色层 2；结束后恢复进入飞行前的原 mask。
	set_collision_mask_value(1,true)
	set_collision_mask_value(2,true)
	_launch_active = true
	_launch_age = 0.0
	_launch_last_hit_msec_by_target.clear()
	_post_launch_normal_move = false
	_rotation_recovery_active = false
	_rotation_recovery_elapsed = 0.0
	var spin_abs:float = _rng.randf_range(
		minf(launch_spin_speed_min,launch_spin_speed_max),
		maxf(launch_spin_speed_min,launch_spin_speed_max)
	)
	_launch_spin_speed = spin_abs * (-1.0 if _rng.randf() < 0.5 else 1.0)


func _tick_explosion_launch(delta:float) -> void:
	if delta <= 0.0:
		return
	_launch_age += delta

	# 与 V83 无重力弹球一致：先短暂加速，然后减速，并且减速度随时间持续增大。
	var speed:float = velocity.length()
	if speed > 0.0001:
		var travel_direction:Vector2 = velocity / speed
		if _launch_age <= maxf(launch_acceleration_duration,0.0):
			speed += maxf(launch_acceleration_strength,0.0) * _launch_force_multiplier * delta
		else:
			var decel_time:float = _launch_age - maxf(launch_acceleration_duration,0.0)
			var current_deceleration:float = (
				maxf(launch_deceleration_start,0.0)
				+ maxf(launch_deceleration_growth,0.0) * decel_time
			)
			speed = maxf(speed - current_deceleration * delta,0.0)
		velocity = travel_direction * speed

	var remaining_motion:Vector2 = velocity * delta
	var collision_limit:int = clampi(launch_max_collisions_per_tick,1,8)
	for _i:int in range(collision_limit):
		if remaining_motion.length_squared() <= 0.000001:
			break
		var collision:KinematicCollision2D = move_and_collide(remaining_motion)
		if collision == null:
			break

		var collider:Variant = collision.get_collider()
		if collider is ball:
			_try_launch_collision_damage(collider as ball,collision.get_position())

		var normal:Vector2 = collision.get_normal()
		if normal.length_squared() <= 0.000001:
			break
		normal = normal.normalized()
		if velocity.dot(normal) < 0.0:
			velocity = velocity.bounce(normal) * clampf(launch_bounce_retention,0.0,1.0)
			var normal_component:Vector2 = normal * velocity.dot(normal)
			var tangent_component:Vector2 = velocity - normal_component
			velocity = normal_component + tangent_component * (
				1.0 - clampf(launch_collision_tangent_friction,0.0,1.0)
			)
		remaining_motion = collision.get_remainder().bounce(normal) * clampf(launch_bounce_retention,0.0,1.0)

	if graphics != null and is_instance_valid(graphics):
		graphics.rotation += _launch_spin_speed * delta

	if velocity.length_squared() > 0.000001:
		direction = velocity.normalized()

	# V86：不等到静止。一旦下降到这个头的正常世界移动速度，
	# 就无缝结束“被爆炸炸飞”的弹球阶段，并从下一物理帧重新交还给原移动/索敌 AI。
	if (
		_launch_age > maxf(launch_acceleration_duration,0.0)
		and velocity.length() <= _normal_world_move_speed()
	):
		_finish_explosion_launch()


func _normal_world_move_speed() -> float:
	var normal_speed:float = maxf(Speed,0.0)
	if Type == Ball_Type.Ball:
		normal_speed *= CHARACTER_BASE_MOVE_SPEED_MULTIPLIER
	return normal_speed


func _finish_explosion_launch() -> void:
	if not _launch_active:
		return
	var resume_direction:Vector2 = velocity.normalized() if velocity.length_squared() > 0.000001 else direction
	if resume_direction.length_squared() <= 0.000001:
		resume_direction = Vector2.RIGHT.rotated(_rng.randf_range(0.0,TAU))
	var normal_speed:float = _normal_world_move_speed()
	_launch_active = false
	_launch_age = 0.0
	_launch_spin_speed = 0.0
	_launch_force_multiplier = 1.0
	_launch_last_hit_msec_by_target.clear()
	Repel = Vector2.ZERO
	direction = resume_direction.normalized()
	# 交回普通移动时直接落在正常速度，并显式标记后续持续走 Move，
	# 不再只依赖这一次 velocity 写入。
	velocity = direction * normal_speed
	_post_launch_normal_move = true
	collision_mask = _launch_original_collision_mask
	if state_machine != null and state_machine.current_state != State.Die:
		state_machine.current_state = State.Move
	_start_rotation_recovery()


func _start_rotation_recovery() -> void:
	if graphics == null or not is_instance_valid(graphics):
		_rotation_recovery_active = false
		return
	# V87：不用 Tween。Tween 在生成/同步/状态切换时可能被其它视觉写入打断，
	# 改为由本脚本每个物理帧明确写 Graphics.rotation，直到真正回到 0。
	graphics.rotation = wrapf(graphics.rotation,-PI,PI)
	_rotation_recovery_from = graphics.rotation
	_rotation_recovery_elapsed = 0.0
	_rotation_recovery_active = absf(_rotation_recovery_from) > 0.0005
	if not _rotation_recovery_active:
		graphics.rotation = 0.0


func _tick_rotation_recovery(delta:float) -> void:
	if not _rotation_recovery_active or not is_multiplayer_authority():
		return
	if graphics == null or not is_instance_valid(graphics):
		_rotation_recovery_active = false
		return
	var duration:float = maxf(launch_rotation_recover_duration,0.05)
	_rotation_recovery_elapsed += maxf(delta,0.0)
	var t:float = clampf(_rotation_recovery_elapsed / duration,0.0,1.0)
	# 二次 ease-out：刚切回正常移动时仍保留明显倾斜，随后平滑回正。
	var eased:float = 1.0 - (1.0 - t) * (1.0 - t)
	graphics.rotation = lerp_angle(_rotation_recovery_from,0.0,eased)
	if t >= 1.0:
		graphics.rotation = 0.0
		_rotation_recovery_active = false


func _try_launch_collision_damage(target:ball,impact_position:Vector2) -> void:
	# V85：只有“被本体爆炸炸飞”的阶段才允许碰撞伤害。静止后二阶段头没有接触伤害。
	if not _launch_active:
		return
	if target == null or not is_instance_valid(target) or not _is_enemy(target):
		return
	var target_id:int = target.get_instance_id()
	var now_msec:int = Time.get_ticks_msec()
	var cooldown_msec:int = maxi(int(round(maxf(launch_hit_cooldown,0.0) * 1000.0)),1)
	if _launch_last_hit_msec_by_target.has(target_id):
		if now_msec - int(_launch_last_hit_msec_by_target[target_id]) < cooldown_msec:
			return
	_launch_last_hit_msec_by_target[target_id] = now_msec

	# 以撞击前的真实速度线性缩放伤害：默认 420 px/s = 70 基础伤害。
	# 因为本函数在反弹前调用，所以这里读取到的是实际撞上目标时的入射速度。
	var impact_speed:float = maxf(velocity.length(),0.0)
	var reference_speed:float = maxf(launch_collision_damage_reference_speed,1.0)
	var speed_ratio:float = impact_speed / reference_speed
	var raw_damage:float = maxf(launch_collision_damage,0.0) * speed_ratio
	var damage_value:float = effective_outgoing_damage(raw_damage)
	if damage_value <= 0.0:
		return
	target.receive_spatial_damage(
		damage_value,
		{"point":impact_position,"source":self},
		false,
		false
	)


func move(speed:float,delta:float) -> void:
	# V88：完成炸飞后必须真正恢复“自己的正常移动速度”。
	# V87 仍在引信期间把速度一路压到 fuse_final_speed_ratio=0.24，
	# 188 * 0.6 * 0.24 ≈ 27 px/s，视觉上几乎等于再次停住。
	# 二阶段头现在引信只负责计时/闪白/爆炸，不再修改正常移动速度。
	if _post_launch_normal_move:
		super.move(speed,delta)
		return
	var ratio:float = 1.0
	if _fusing:
		var progress:float = clampf(_fuse_elapsed / maxf(_current_fuse_duration,0.05),0.0,1.0)
		ratio = lerpf(1.0,fuse_final_speed_ratio,progress)
	super.move(speed * ratio,delta)


func stand(delta:float) -> void:
	super.stand(delta)


func _update_fuse_logic(_delta:float) -> void:
	var nearest:ball = null if is_player_controlled() else _nearest_enemy()
	if not _fusing:
		if nearest != null and global_position.distance_to(ball.body_point(nearest,global_position)) <= fuse_start_radius:
			_begin_fuse(nearest)
		return

	var tracked:ball = _resolve_fuse_target()
	var active_target:ball = null
	if tracked != null and global_position.distance_to(ball.body_point(tracked,global_position)) <= fuse_cancel_radius:
		active_target = tracked
	elif nearest != null and global_position.distance_to(ball.body_point(nearest,global_position)) <= fuse_cancel_radius:
		active_target = nearest

	if active_target != null:
		_set_fuse_advancing(true,active_target.get_instance_id())
	else:
		_set_fuse_advancing(false,0)

	if _fuse_elapsed >= _current_fuse_duration:
		_explode()
	elif not _fuse_advancing and _fuse_elapsed <= 0.0:
		_cancel_fuse()

func controlled_attack_action() -> void:
	if not is_player_controlled() or not is_multiplayer_authority() or _launch_active or _fusing or _exploded or _death_sequence_started or not has_player_control_aim(): return
	if not is_combat_runtime_active() or is_damage_output_disabled(): return
	var point:Vector2=player_control_aim_world_position()
	var chosen:ball=null
	var nearest:float=INF
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not (raw is ball) or not _is_enemy(raw as ball): continue
		var distance:float=ball.body_point(raw,point).distance_to(point)
		if distance<=U.radius(raw)+6.0 and distance<nearest:
			chosen=raw as ball
			nearest=distance
	if chosen!=null and global_position.distance_to(ball.body_point(chosen,global_position))<=fuse_start_radius:
		_begin_fuse(chosen)


func _begin_fuse(target:ball) -> void:
	if _fusing or _exploded or target == null:
		return
	var duration:float = maxf(fuse_duration,0.1)
	var target_id:int = target.get_instance_id()
	if multiplayer.has_multiplayer_peer():
		_rpc_begin_fuse.rpc(duration,target_id)
	else:
		_rpc_begin_fuse(duration,target_id)


@rpc("authority","call_local","reliable")
func _rpc_begin_fuse(duration:float,target_id:int) -> void:
	_fusing = true
	_fuse_advancing = true
	_fuse_elapsed = 0.0
	_fuse_decay_elapsed = 0.0
	_fuse_visual_clock = 0.0
	_current_fuse_duration = maxf(duration,0.1)
	_fuse_target_id = target_id
	_play_fuse_audio_from_progress()
	if fuse_progress != null:
		fuse_progress.value = 0.0
		fuse_progress.hide()
	queue_redraw()
	if fuse_white_overlay != null and is_instance_valid(fuse_white_overlay):
		fuse_white_overlay.show()
		fuse_white_overlay.set_instance_shader_parameter("power",0.0)


func _advance_fuse_progress(delta:float) -> void:
	_fuse_visual_clock += maxf(delta,0.0)
	if _fuse_advancing:
		_fuse_decay_elapsed = 0.0
		_fuse_elapsed = minf(_fuse_elapsed + maxf(delta,0.0),_current_fuse_duration)
		return

	_fuse_decay_elapsed += maxf(delta,0.0)
	var decay_time:float = _fuse_decay_elapsed - maxf(fuse_decay_delay,0.0)
	if decay_time <= 0.0:
		return
	var decay_speed:float = minf(
		decay_time * maxf(fuse_decay_acceleration,0.01),
		maxf(fuse_decay_max_speed,0.01)
	)
	_fuse_elapsed = maxf(_fuse_elapsed - decay_speed * maxf(delta,0.0),0.0)


func _set_fuse_advancing(value:bool,target_id:int) -> void:
	if not is_multiplayer_authority() or not _fusing:
		return
	var safe_target_id:int = target_id if value else 0
	if _fuse_advancing == value and (_fuse_target_id == safe_target_id or not value):
		return
	if multiplayer.has_multiplayer_peer():
		_rpc_set_fuse_advancing.rpc(value,safe_target_id)
	else:
		_rpc_set_fuse_advancing(value,safe_target_id)


@rpc("authority","call_local","reliable")
func _rpc_set_fuse_advancing(value:bool,target_id:int) -> void:
	if not _fusing:
		return
	var was_advancing:bool = _fuse_advancing
	_fuse_advancing = value
	_fuse_target_id = target_id if value else 0
	if value:
		_fuse_decay_elapsed = 0.0
		if not was_advancing:
			_play_fuse_audio_from_progress()
	elif fuse_audio != null:
		fuse_audio.stop()


func _play_fuse_audio_from_progress() -> void:
	if fuse_audio == null or FUSE_SOUND == null:
		return
	fuse_audio.stop()
	fuse_audio.stream = FUSE_SOUND
	fuse_audio.volume_db = -5.0
	fuse_audio.pitch_scale = clampf(FUSE_SOUND.get_length() / maxf(_current_fuse_duration,0.1),0.65,1.15)
	var sound_length:float = maxf(FUSE_SOUND.get_length(),0.0)
	var progress:float = clampf(_fuse_elapsed / maxf(_current_fuse_duration,0.05),0.0,0.98)
	fuse_audio.play(progress * sound_length)


func _cancel_fuse() -> void:
	if not _fusing:
		return
	if multiplayer.has_multiplayer_peer():
		_rpc_cancel_fuse.rpc()
	else:
		_rpc_cancel_fuse()


@rpc("authority","call_local","reliable")
func _rpc_cancel_fuse() -> void:
	_fusing = false
	_fuse_advancing = false
	_fuse_elapsed = 0.0
	_fuse_decay_elapsed = 0.0
	_fuse_visual_clock = 0.0
	_fuse_target_id = 0
	if fuse_audio != null:
		fuse_audio.stop()
	_reset_fuse_visual()


func _resolve_fuse_target() -> ball:
	if _fuse_target_id <= 0 or not is_instance_id_valid(_fuse_target_id):
		return null
	var candidate:Variant = instance_from_id(_fuse_target_id)
	if candidate is ball and is_instance_valid(candidate):
		var target:ball = candidate as ball
		if _is_enemy(target):
			return target
	return null


func _update_fuse_visual() -> void:
	if not _fusing or image == null or graphics == null:
		return
	var progress:float = clampf(_fuse_elapsed / maxf(_current_fuse_duration,0.05),0.0,1.0)
	if fuse_progress != null:
		fuse_progress.value = progress
	var flash_power:float = 0.0
	# 和正常苦力怕一致：只有范围内仍有敌人、进度正在累计时才闪白；
	# 离开范围进入“停留 + 回退”时保留当前体型/进度，但停止闪白。
	if _fuse_advancing:
		var frequency:float = lerpf(4.0,12.0,progress)
		var pulse:float = (sin(_fuse_visual_clock * TAU * frequency) + 1.0) * 0.5
		flash_power = clampf(0.12 + pulse * lerpf(0.48,0.82,progress),0.0,1.0)
	# V90：使用独立全白覆盖层直接覆盖整张非透明头贴图。场景 Shader 直接输出纯白 RGB，
	# 不再把白色结果乘回原纹理颜色；底图的受击 power 在引信期固定为 0。
	image.set_instance_shader_parameter("power",0.0)
	if fuse_white_overlay != null and is_instance_valid(fuse_white_overlay):
		# 底图的左右朝向由公共 Shader 完成；覆盖层用原生 flip_h 跟随同一个最终朝向。
		fuse_white_overlay.show()
		fuse_white_overlay.flip_h = is_character_visual_flipped_h()
		fuse_white_overlay.set_instance_shader_parameter("power",flash_power)
	var target_scale:Vector2 = _graphics_base_scale * lerpf(1.0,fuse_final_scale,progress)
	var transformed_anchor := Vector2(
		_foot_anchor_child.x * target_scale.x,
		_foot_anchor_child.y * target_scale.y
	)
	graphics.scale = target_scale
	graphics.position = _foot_anchor_parent - transformed_anchor
	queue_redraw()


func _draw() -> void:
	if not _fusing or _exploded or _death_sequence_started:
		return
	_draw_fuse_progress_bar()


func _draw_fuse_progress_bar() -> void:
	var ratio:float = clampf(_fuse_elapsed / maxf(_current_fuse_duration,0.05),0.0,1.0)
	var pad_vec:= Vector2(FUSE_BAR_OUTER_PAD,FUSE_BAR_OUTER_PAD)
	draw_rect(
		Rect2(FUSE_BAR_RECT.position - pad_vec,FUSE_BAR_RECT.size + pad_vec * 2.0),
		FUSE_BAR_OUTER_COLOR,
		true
	)
	draw_rect(FUSE_BAR_RECT,FUSE_BAR_BACKGROUND_COLOR,true)
	if ratio > 0.0:
		var fill_color:Color = FUSE_BAR_START_COLOR.lerp(FUSE_BAR_END_COLOR,ratio)
		draw_rect(
			Rect2(FUSE_BAR_RECT.position,Vector2(FUSE_BAR_RECT.size.x * ratio,FUSE_BAR_RECT.size.y)),
			fill_color,
			true
		)
	draw_rect(FUSE_BAR_RECT,FUSE_BAR_BORDER_COLOR,false,FUSE_BAR_BORDER_WIDTH)


func _reset_fuse_visual() -> void:
	if image != null and is_instance_valid(image):
		image.set_instance_shader_parameter("power",0.0)
	if fuse_white_overlay != null and is_instance_valid(fuse_white_overlay):
		fuse_white_overlay.set_instance_shader_parameter("power",0.0)
		fuse_white_overlay.hide()
	if graphics != null and is_instance_valid(graphics):
		graphics.position = _graphics_base_position
		graphics.scale = _graphics_base_scale
	if fuse_progress != null and is_instance_valid(fuse_progress):
		fuse_progress.value = 0.0
		fuse_progress.hide()
	queue_redraw()


func _capture_visual_base() -> void:
	if graphics == null:
		return
	_graphics_base_position = graphics.position
	_graphics_base_scale = graphics.scale
	var bottom_y:float = 92.0
	if image is Sprite2D:
		var sprite := image as Sprite2D
		if sprite.texture != null:
			bottom_y = sprite.position.y + (float(sprite.texture.get_height()) * 0.5 + sprite.offset.y) * sprite.scale.y
	_foot_anchor_child = Vector2(0.0,bottom_y)
	_foot_anchor_parent = _graphics_base_position + Vector2(0.0,bottom_y * _graphics_base_scale.y)


func _explode() -> void:
	if _exploded or not is_multiplayer_authority():
		return
	_exploded = true
	var point:Vector2 = global_position
	set_meta(&"ignore_combat_targeting",true)
	set_collision_layer(0)
	set_collision_mask(0)
	if self_hurtbox != null:
		self_hurtbox.set_deferred(&"monitorable",false)
		self_hurtbox.set_deferred(&"monitoring",false)
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var target:ball = raw as ball
		if not _is_enemy(target):
			continue
		if ball.body_point(target,point).distance_to(point) > explosion_radius:
			continue
		var accepted:bool = target.receive_spatial_damage(
			effective_outgoing_damage(explosion_damage),
			{"shape":"circle","center":point,"radius":explosion_radius,"source":self},
			false,
			false
		)
		if not accepted:
			continue
		var push:Vector2 = ball.body_point(target,point) - point
		if push.length_squared() <= 0.000001:
			push = Vector2.RIGHT.rotated(_rng.randf_range(0.0,TAU))
		target.apply_knockback(push.normalized(),knockback_distance,knockback_speed,0.0,0.0,{"source":self,"max_wall_bounces":0,"stop_on_character":true})

	var variant:int = _rng.randi_range(1,3)
	if multiplayer.has_multiplayer_peer():
		_rpc_explosion_visual.rpc(point,variant,explosion_radius * 2.0)
	else:
		_rpc_explosion_visual(point,variant,explosion_radius * 2.0)
	await get_tree().create_timer(EXPLOSION_VISUAL_HOLD).timeout
	if is_instance_valid(self) and is_multiplayer_authority():
		Game.free_node(self)


@rpc("authority","call_local","reliable")
func _rpc_explosion_visual(point:Vector2,_variant:int,diameter:float) -> void:
	_exploded = true
	_fusing = false
	_fuse_advancing = false
	_fuse_target_id = 0
	if fuse_audio != null:
		fuse_audio.stop()
	if image != null:
		image.set_instance_shader_parameter("power",0.0)
	if fuse_white_overlay != null and is_instance_valid(fuse_white_overlay):
		fuse_white_overlay.set_instance_shader_parameter("power",0.0)
		fuse_white_overlay.hide()
	if graphics != null:
		graphics.hide()
	if health_bar != null:
		health_bar.hide()
	if fuse_progress != null:
		fuse_progress.hide()
	queue_redraw()
	var effect:Node2D = EXPLOSION_EFFECT_SCENE.instantiate() as Node2D
	if effect == null:
		return
	effect.set("radius",maxf(diameter*0.5,8.0))
	effect.set("volume_db",-7.0)
	# 和本体一样：这是 RPC 本地视觉，避开 World 根节点的 MultiplayerSpawner。
	effect.name = "CreeperHeadExplosionVisual"
	effect.top_level = true
	effect.position = point
	load("res://scripts/effects/我的世界/mc_explosion.gd").runtime_container(self).add_child(effect,true)
	effect.global_position = point


func _nearest_enemy() -> ball:
	var nearest:ball = null
	var nearest_distance_sq:float = INF
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var candidate:ball = raw as ball
		if not _is_enemy(candidate):
			continue
		var d:float = global_position.distance_squared_to(ball.body_point(candidate,global_position))
		if d < nearest_distance_sq:
			nearest_distance_sq = d
			nearest = candidate
	return nearest


func _is_enemy(target:ball) -> bool:
	if target == null or not is_instance_valid(target) or target == self:
		return false
	if target.Type != Ball_Type.Ball or target.health <= 0 or not target.is_combat_targetable():
		return false
	if not Game.Game_Settings.Have_Team_Damage and not Team.is_empty() and not target.Team.is_empty() and Team == target.Team:
		return false
	return true


func _has_death_animation() -> bool:
	return true


func Die() -> void:
	if _death_sequence_started or _exploded:
		return
	_death_sequence_started = true
	var victory_key:String = str(get_meta(&"battle_continuation_victory_side_key",get_meta(&"victory_side_key",""))).strip_edges()
	var presentation_key:String = str(get_meta(&"battle_continuation_presentation_side_key","")).strip_edges()
	if not victory_key.is_empty():
		set_meta(&"battle_death_bridge_active",true)
		set_meta(&"battle_death_bridge_victory_side_key",victory_key)
		set_meta(&"battle_death_bridge_presentation_side_key",presentation_key)
		set_meta(&"battle_death_bridge_display_name","苦力怕")
	super.Die()
	var pos:Vector2 = global_position
	if multiplayer.has_multiplayer_peer():
		_rpc_death_visual.rpc(pos)
	else:
		_rpc_death_visual(pos)
	await get_tree().create_timer(DEATH_POSE_DURATION).timeout
	if is_instance_valid(self) and is_multiplayer_authority():
		Game.free_node(self)


@rpc("authority","call_local","reliable")
func _rpc_death_visual(pos:Vector2) -> void:
	_fusing = false
	_fuse_advancing = false
	_fuse_target_id = 0
	if fuse_white_overlay != null and is_instance_valid(fuse_white_overlay):
		fuse_white_overlay.set_instance_shader_parameter("power",0.0)
	if fuse_audio != null:
		fuse_audio.stop()
	if death_audio != null:
		death_audio.stream = DEATH_SOUND
		death_audio.volume_db = -2.0
		death_audio.play()
	if health_bar != null:
		health_bar.hide()
	if fuse_progress != null:
		fuse_progress.hide()
	queue_redraw()
	if graphics != null:
		var sign_value:float = -1.0 if direction.x >= 0.0 else 1.0
		var tween:Tween = graphics.create_tween().set_parallel(true)
		tween.tween_property(graphics,"modulate",Color(1.0,0.20,0.20,1.0),0.08)
		tween.tween_property(graphics,"rotation",graphics.rotation + sign_value * PI * 0.5,DEATH_POSE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_spawn_smoke(pos)


func _spawn_smoke(pos:Vector2) -> void:
	var parent:Node = get_tree().current_scene
	if parent == null:
		return
	var smoke := AnimatedSprite2D.new()
	smoke.name = "苦力怕头死亡烟雾"
	smoke.sprite_frames = DEATH_SMOKE_FRAMES
	smoke.animation = &"死亡烟雾"
	smoke.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	smoke.z_as_relative = false
	smoke.z_index = 8
	smoke.scale = Vector2.ONE * 0.38
	smoke.visible = false
	parent.add_child(smoke)
	smoke.global_position = pos
	smoke.animation_finished.connect(Callable(smoke,"queue_free"),CONNECT_ONE_SHOT)
	var delayed:Tween = smoke.create_tween()
	delayed.tween_interval(DEATH_POSE_DURATION)
	delayed.tween_callback(Callable(smoke,"show"))
	delayed.tween_callback(Callable(smoke,"play").bind(&"死亡烟雾"))
