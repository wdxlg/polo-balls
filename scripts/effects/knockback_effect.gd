extends Node
# ========================================================
# 通用击退效果 V10.1
#
# 目标：
# - 一个角色同时只由一个 KnockbackEffect 驱动，避免多个效果争抢 Repel。
# - distance 决定实际击退路径距离；speed 决定主要冲击速度。
# - 末段按“剩余距离”连续刹车，并限制下一帧最大位移，避免过冲后瞬停。
# - 新击退命中正在击退的角色时，短时间平滑重定向，不再创建第二个控制器。
# - 撞墙反弹只损失速度，不再出现“先突然慢、随后又重新加速”的假反弹。
# - 正常击退结束后，可短暂平滑接回角色自己的移动速度。
# ========================================================

var target:ball = null
var source:Node = null

var direction:Vector2 = Vector2.RIGHT
var distance:float = 100.0
var speed:float = 700.0

# 0 = 撞墙停止；0.5 = 以当前速度的一半反弹；1 = 完全反弹；>1 = 更强反弹。
var wall_bounce_strength:float = 0.0
var max_wall_bounces:int = 1

# 撞到其他 ball 的处理。
var stop_on_character:bool = true
var character_bounce_strength:float = 0.0

# 击退过程中是否锁住角色自己的移动输入/AI。
var lock_control_during_knockback:bool = true

# 眩晕。
var stun_duration:float = 0.0
# true：只有真的撞墙/撞人时才追加眩晕。
# false：正常滑完距离也会眩晕。
var stun_only_on_collision:bool = false

# 撞墙/撞人时，受到击退的目标自己承受的碰撞伤害。
var collision_damage:float = 0.0
var collision_damage_ignore_block:bool = false

# 兼容旧调用：整段速度线性衰减。
var use_speed_falloff:bool = false
@export_range(0.0,1.0,0.01) var end_speed_ratio:float = 0.35

# 通用平滑手感。
var smooth_motion:bool = true
# 最后多少比例的路程进入连续刹车区。
@export_range(0.05,0.8,0.01) var smooth_end_ratio:float = 0.32
# 兼容旧参数。V10.1 默认允许真正减到接近 0；如果某技能显式设值，仍会保留最低比例。
@export_range(0.0,0.5,0.01) var smooth_end_speed_ratio:float = 0.0
# 新击退覆盖旧击退时，方向切换的平滑时间。
@export_range(0.0,0.2,0.005) var redirect_blend_time:float = 0.055
# 正常击退结束后，接回角色自主移动速度的过渡时间。
@export_range(0.0,0.25,0.005) var control_recovery_time:float = 0.085
# 小于该剩余距离就认为击退完成，避免无限逼近终点。
@export_range(0.1,4.0,0.1) var finish_distance_epsilon:float = 0.65
# 很短但速度很高的击退至少保持这段时间，避免只闪 2~4 个物理帧。
@export_range(0.0,0.3,0.005) var minimum_motion_time:float = 0.10

# 旧版反弹恢复参数保留，以免旧场景/代码写入时报错；V10.1 不再使用“反弹后重新加速”。
var bounce_recovery_time:float = 0.0
var bounce_start_speed_ratio:float = 1.0

# 防止极端同步/碰撞情况下效果永远不结束。
var timeout_extra:float = 1.0

var _current_direction:Vector2 = Vector2.RIGHT
var _target_direction:Vector2 = Vector2.RIGHT
var _redirect_from_angle:float = 0.0
var _redirect_to_angle:float = 0.0
var _redirect_elapsed:float = 999.0
var _redirect_duration:float = 0.0

var _current_speed:float = 0.0
var _bounce_speed_scale:float = 1.0
var _remaining_distance:float = 0.0
var _segment_distance:float = 0.0
var _travelled_distance:float = 0.0
var _elapsed:float = 0.0
var _last_position:Vector2 = Vector2.ZERO
var _last_physics_delta:float = 1.0 / 60.0
var _wall_bounces:int = 0
var _had_collision:bool = false

# 0=击退，1=眩晕，2=正常移动恢复过渡。
var _stage:int = 0
var _stun_elapsed:float = 0.0
var _recovery_elapsed:float = 0.0
var _recovery_from_velocity:Vector2 = Vector2.ZERO
var _recovery_to_velocity:Vector2 = Vector2.ZERO

var _lock_acquired:bool = false
var _stun_visual_acquired:bool = false
var _finished:bool = false

const CONTROL_LOCK_META:StringName = &"generic_motion_lock_count"
const CONTROL_BASELINE_META:StringName = &"generic_motion_lock_baseline"


func _ready() -> void:
	if target == null and get_parent() is ball:
		target = get_parent() as ball

	if not _target_is_usable():
		queue_free()
		return

	# 角色先执行 move_and_slide()；击退控制器随后读取本帧碰撞并准备下一帧速度。
	process_physics_priority = target.process_physics_priority + 100

	var initial_direction:Vector2 = _safe_direction(direction)
	_current_direction = initial_direction
	_target_direction = initial_direction
	_redirect_from_angle = initial_direction.angle()
	_redirect_to_angle = initial_direction.angle()
	_redirect_elapsed = 999.0
	_redirect_duration = 0.0

	_bounce_speed_scale = 1.0
	_current_speed = maxf(speed,0.0)
	_segment_distance = maxf(distance,0.0)
	_remaining_distance = _segment_distance
	_travelled_distance = 0.0
	_last_position = target.global_position

	if distance <= 0.0:
		if stun_duration > 0.0:
			_acquire_control_lock()
			_acquire_stun_visual()
			_stage = 1
			target.Repel = Vector2.ZERO
		else:
			_finish(false)
		return

	if lock_control_during_knockback:
		_acquire_control_lock()

	_write_repel(_last_physics_delta)


# ball.apply_knockback() 在已经存在击退控制器时调用这里。
# 新命中覆盖旧的“距离/碰撞参数”，但不会再生成另一个节点争抢 Repel。
func replace_with_hit(
	new_direction:Vector2,
	new_distance:float,
	new_speed:float,
	new_wall_bounce_strength:float,
	new_stun_duration:float,
	options:Dictionary = {}
) -> void:
	if _finished or not _target_is_usable():
		return

	var sanitized_distance:float = maxf(new_distance,0.0)
	var sanitized_stun:float = maxf(new_stun_duration,0.0)

	# 纯眩晕：不需要打断当前击退，只把需要的眩晕时长合并进去。
	if sanitized_distance <= 0.0:
		if sanitized_stun <= 0.0:
			return
		if _stage == 1:
			var old_remaining_stun:float = maxf(stun_duration - _stun_elapsed,0.0)
			stun_duration = maxf(old_remaining_stun,sanitized_stun)
			_stun_elapsed = 0.0
		else:
			stun_duration = maxf(stun_duration,sanitized_stun)
		return

	var old_dir:Vector2 = _current_direction
	var desired_dir:Vector2 = _safe_direction(new_direction)
	var blend_time:float = clampf(float(options.get("redirect_blend_time",redirect_blend_time)),0.0,0.2)
	# 完全反向时缩短转向时间，避免视觉上画出过大的半圆弧。
	if old_dir.dot(desired_dir) < -0.35:
		blend_time *= 0.55

	_target_direction = desired_dir
	_redirect_from_angle = old_dir.angle()
	_redirect_to_angle = desired_dir.angle()
	_redirect_elapsed = 0.0
	_redirect_duration = blend_time
	if blend_time <= 0.0001:
		_current_direction = desired_dir

	source = options.get("source",null)
	distance = sanitized_distance
	speed = maxf(new_speed,0.0)
	wall_bounce_strength = maxf(new_wall_bounce_strength,0.0)
	max_wall_bounces = maxi(int(options.get("max_wall_bounces",1)),0)
	stop_on_character = bool(options.get("stop_on_character",true))
	character_bounce_strength = maxf(float(options.get("character_bounce_strength",0.0)),0.0)
	lock_control_during_knockback = bool(options.get("lock_control",true))
	# 已经承诺的眩晕不因为后一个“无眩晕击退”被抹掉。
	stun_duration = maxf(stun_duration,sanitized_stun)
	stun_only_on_collision = bool(options.get("stun_only_on_collision",false))
	collision_damage = maxf(float(options.get("collision_damage",0.0)),0.0)
	collision_damage_ignore_block = bool(options.get("collision_damage_ignore_block",false))
	use_speed_falloff = bool(options.get("use_speed_falloff",false))
	end_speed_ratio = clampf(float(options.get("end_speed_ratio",0.35)),0.0,1.0)
	smooth_motion = bool(options.get("smooth_motion",true))
	smooth_end_ratio = clampf(float(options.get("smooth_end_ratio",0.32)),0.05,0.8)
	smooth_end_speed_ratio = clampf(float(options.get("smooth_end_speed_ratio",0.0)),0.0,0.5)
	redirect_blend_time = blend_time
	control_recovery_time = clampf(float(options.get("control_recovery_time",0.085)),0.0,0.25)
	finish_distance_epsilon = clampf(float(options.get("finish_distance_epsilon",0.65)),0.1,4.0)
	minimum_motion_time = clampf(float(options.get("minimum_motion_time",0.10)),0.0,0.3)
	timeout_extra = maxf(float(options.get("timeout_extra",1.0)),0.25)

	# 新击退从“现在的位置”重新计算路径；旧剩余距离不和新距离相加，避免多人围攻时击飞无限叠长。
	_segment_distance = sanitized_distance
	_remaining_distance = sanitized_distance
	_travelled_distance = 0.0
	_elapsed = 0.0
	_last_position = target.global_position
	_wall_bounces = 0
	_had_collision = false
	_bounce_speed_scale = 1.0
	_stage = 0
	_stun_elapsed = 0.0
	_recovery_elapsed = 0.0
	_release_stun_visual()

	# 新的冲击应该立刻有力量，但不把旧速度和新速度直接相加，防止多人同帧命中速度爆炸。
	_current_speed = maxf(
		minf(_current_speed,maxf(speed,0.0) * 1.10),
		maxf(speed,0.0) * 0.82
	)

	if lock_control_during_knockback:
		_acquire_control_lock()
	else:
		_release_control_lock()

	_write_repel(_last_physics_delta)


func is_active_effect() -> bool:
	return not _finished


func _physics_process(delta:float) -> void:
	if _finished:
		return
	if not _target_is_usable():
		_finish(false)
		return

	_last_physics_delta = maxf(delta,0.000001)

	if _stage == 1:
		_process_stun(delta)
		return
	if _stage == 2:
		_process_control_recovery(delta)
		return

	_elapsed += delta

	var displacement:Vector2 = target.global_position - _last_position
	_last_position = target.global_position

	# 只把“沿击退方向真正走出去的距离”计入击退路程。
	# 以前使用位置变化的总长度，角色沿墙滑动/被其他位移横向推动时也会消耗击退距离，容易突然结束。
	var forward_travel:float = maxf(displacement.dot(_current_direction),0.0)
	_travelled_distance += forward_travel
	_remaining_distance = maxf(_remaining_distance - forward_travel,0.0)

	# 本帧 move_and_slide() 的碰撞在角色移动完成后统一读取。
	if _handle_collisions():
		return

	if _remaining_distance <= maxf(finish_distance_epsilon,0.1):
		_finish_knockback(false)
		return

	# 安全超时：按较保守的平均速度估算；额外给反弹留余量。
	var expected_time:float = maxf(_segment_distance,0.0) / maxf(maxf(speed,1.0) * 0.42,1.0)
	var bounce_allowance:float = float(_wall_bounces) * 0.50
	if _elapsed >= expected_time + maxf(timeout_extra,0.25) + bounce_allowance:
		_finish_knockback(false)
		return

	_update_redirect(delta)
	_update_current_speed()
	_write_repel(delta)


func _handle_collisions() -> bool:
	var count:int = target.get_slide_collision_count()
	if count <= 0:
		return false

	# 只处理真正挡在击退前方的碰撞。
	for index:int in range(count):
		var collision:KinematicCollision2D = target.get_slide_collision(index)
		if collision == null:
			continue

		var normal:Vector2 = collision.get_normal()
		if normal.length_squared() <= 0.0001:
			continue
		if _current_direction.dot(normal) >= -0.02:
			continue

		var collider = collision.get_collider()
		var impact_position:Vector2 = collision.get_position()
		if collider is ball:
			return _handle_character_collision(normal,impact_position)
		return _handle_wall_collision(normal,impact_position)

	return false


func _handle_wall_collision(normal:Vector2,impact_position:Vector2) -> bool:
	_had_collision = true
	_apply_collision_damage(impact_position)
	if target != null and target.has_method("notify_bounce_feedback"):
		target.notify_bounce_feedback(_current_direction,maxf(_current_speed,80.0),null)

	var bounce_ratio:float = maxf(wall_bounce_strength,0.0)
	if bounce_ratio <= 0.0 or _wall_bounces >= maxi(max_wall_bounces,0):
		_finish_knockback(true)
		return true

	_wall_bounces += 1
	_current_direction = _current_direction.bounce(normal).normalized()
	_target_direction = _current_direction
	_redirect_elapsed = 999.0
	_redirect_duration = 0.0
	_bounce_speed_scale *= bounce_ratio

	# V10.1：反弹后只损失速度，不再“先降到 38% 再重新加速”。
	# 这更符合碰撞后的动量感，也消除了墙边的二次加速突兀感。
	_current_speed = minf(_current_speed,maxf(speed,0.0) * _bounce_speed_scale)
	if _current_speed <= 8.0:
		_finish_knockback(true)
		return true

	_write_repel(_last_physics_delta)
	return false


func _handle_character_collision(normal:Vector2,impact_position:Vector2) -> bool:
	_had_collision = true
	_apply_collision_damage(impact_position)
	if target != null and target.has_method("notify_bounce_feedback"):
		target.notify_bounce_feedback(_current_direction,maxf(_current_speed,80.0),null)

	if stop_on_character or character_bounce_strength <= 0.0:
		_finish_knockback(true)
		return true

	_current_direction = _current_direction.bounce(normal).normalized()
	_target_direction = _current_direction
	_redirect_elapsed = 999.0
	_redirect_duration = 0.0
	_bounce_speed_scale *= maxf(character_bounce_strength,0.0)
	_current_speed = minf(_current_speed,maxf(speed,0.0) * _bounce_speed_scale)
	if _current_speed <= 8.0:
		_finish_knockback(true)
		return true

	_write_repel(_last_physics_delta)
	return false


func _update_redirect(delta:float) -> void:
	if _redirect_duration <= 0.0001 or _redirect_elapsed >= _redirect_duration:
		_current_direction = _target_direction
		return

	_redirect_elapsed += delta
	var t:float = clampf(_redirect_elapsed / _redirect_duration,0.0,1.0)
	# smoothstep：起点/终点角速度都归零，避免方向切换有折角。
	var smooth_t:float = t * t * (3.0 - 2.0 * t)
	var angle:float = lerp_angle(_redirect_from_angle,_redirect_to_angle,smooth_t)
	_current_direction = Vector2.RIGHT.rotated(angle)
	if t >= 1.0:
		_current_direction = _target_direction


func _update_current_speed() -> void:
	var cruise_speed:float = maxf(speed,0.0) * maxf(_bounce_speed_scale,0.0)
	# 短距离高速度如果只持续两三帧，再好的减速曲线也看起来像瞬移。
	# 给这种小击退一个很短的最小时长上限；长距离击退仍完全尊重 speed。
	if minimum_motion_time > 0.0001 and _segment_distance > 0.0:
		cruise_speed = minf(cruise_speed,_segment_distance / minimum_motion_time)
	if cruise_speed <= 0.0:
		_current_speed = 0.0
		return

	var progress:float = 1.0 - clampf(
		_remaining_distance / maxf(_segment_distance,1.0),
		0.0,
		1.0
	)
	var speed_multiplier:float = 1.0

	if use_speed_falloff:
		speed_multiplier *= lerpf(
			1.0,
			clampf(end_speed_ratio,0.0,1.0),
			progress
		)

	if smooth_motion:
		var brake_distance:float = maxf(
			_segment_distance * clampf(smooth_end_ratio,0.05,0.8),
			4.0
		)
		if _remaining_distance < brake_distance:
			var brake_ratio:float = clampf(_remaining_distance / brake_distance,0.0,1.0)
			# sqrt(remaining) 对应“近似恒定减速度”的速度-距离关系，
			# 比直接 smoothstep 到 0 更不容易在末端拖成慢动作。
			var physical_brake_ratio:float = sqrt(brake_ratio)
			speed_multiplier *= maxf(
				physical_brake_ratio,
				clampf(smooth_end_speed_ratio,0.0,0.5)
			)

	_current_speed = cruise_speed * maxf(speed_multiplier,0.0)


func _write_repel(delta:float) -> void:
	if not _target_is_usable():
		return

	var write_speed:float = maxf(_current_speed,0.0)
	if _stage == 0 and _remaining_distance > 0.0:
		# 限制下一物理帧最多走完剩余距离，不允许最后一帧高速过冲几十像素再瞬间停住。
		var max_speed_for_remaining:float = _remaining_distance / maxf(delta,0.000001)
		write_speed = minf(write_speed,max_speed_for_remaining)

	target.Repel = _current_direction * write_speed


func _apply_collision_damage(impact_position:Vector2) -> void:
	if collision_damage <= 0.0 or not _target_is_usable():
		return

	target.receive_positional_damage(collision_damage,impact_position,collision_damage_ignore_block,self)


func _finish_knockback(from_collision:bool) -> void:
	if target != null and is_instance_valid(target):
		target.Repel = Vector2.ZERO

	var should_stun:bool = (
		stun_duration > 0.0
		and (
			not stun_only_on_collision
			or from_collision
			or _had_collision
		)
	)

	if should_stun:
		_acquire_control_lock()
		_acquire_stun_visual()
		_stage = 1
		_stun_elapsed = 0.0
		return

	# 只有“正常走完击退距离”才做接回自主移动的短过渡。
	# 撞墙/撞角色停下时立即交还控制，避免恢复阶段把角色继续推向碰撞面。
	if (
		not from_collision
		and lock_control_during_knockback
		and _lock_acquired
		and control_recovery_time > 0.0
		and _target_is_usable()
	):
		_stage = 2
		_recovery_elapsed = 0.0
		_recovery_from_velocity = _current_direction * maxf(_current_speed,0.0)
		_recovery_to_velocity = target.direction * maxf(target.Speed,0.0)
		# 立刻把第一帧恢复速度留给下一次 stand()，避免阶段切换时空一帧。
		target.Repel = _recovery_from_velocity
		return

	_finish(false)


func _process_stun(delta:float) -> void:
	target.Repel = Vector2.ZERO
	_stun_elapsed += delta
	if _stun_elapsed >= maxf(stun_duration,0.0):
		_finish(false)


func _process_control_recovery(delta:float) -> void:
	if not _target_is_usable():
		_finish(false)
		return

	var duration:float = maxf(control_recovery_time,0.0001)
	_recovery_elapsed += delta
	var t:float = clampf(_recovery_elapsed / duration,0.0,1.0)
	var smooth_t:float = t * t * (3.0 - 2.0 * t)

	# 目标移动方向可能在恢复期间被 AI 更新，跟随最新值可以避免恢复结束后一帧突然转向。
	_recovery_to_velocity = target.direction * maxf(target.Speed,0.0)
	var recovery_velocity:Vector2 = _recovery_from_velocity.lerp(_recovery_to_velocity,smooth_t)
	target.Repel = recovery_velocity

	if t >= 1.0:
		_finish(false)


func _safe_direction(value:Vector2) -> Vector2:
	if value.length_squared() <= 0.0001:
		if target != null and is_instance_valid(target) and target.direction.length_squared() > 0.0001:
			return target.direction.normalized()
		return Vector2.RIGHT
	return value.normalized()


func _target_is_usable() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.health <= 0:
		return false
	if target.state_machine and target.state_machine.current_state == ball.State.Die:
		return false
	return true


func _acquire_control_lock() -> void:
	if _lock_acquired or target == null or not is_instance_valid(target):
		return

	var old_count:int = int(target.get_meta(CONTROL_LOCK_META,0))
	if old_count <= 0:
		target.set_meta(CONTROL_BASELINE_META,target.dizziness)

	target.set_meta(CONTROL_LOCK_META,old_count + 1)
	target.dizziness = true
	_lock_acquired = true


func _acquire_stun_visual() -> void:
	if _stun_visual_acquired or target == null or not is_instance_valid(target):
		return

	if target.has_method("begin_stun_visual"):
		target.begin_stun_visual()
		_stun_visual_acquired = true


func _release_stun_visual() -> void:
	if not _stun_visual_acquired:
		return
	_stun_visual_acquired = false

	if target == null or not is_instance_valid(target):
		return

	if target.has_method("end_stun_visual"):
		target.end_stun_visual()


func _release_control_lock() -> void:
	if not _lock_acquired:
		return
	_lock_acquired = false

	if target == null or not is_instance_valid(target):
		return

	var old_count:int = int(target.get_meta(CONTROL_LOCK_META,0))
	var new_count:int = maxi(old_count - 1,0)

	if new_count > 0:
		target.set_meta(CONTROL_LOCK_META,new_count)
		return

	var baseline:bool = bool(target.get_meta(CONTROL_BASELINE_META,false))
	target.dizziness = baseline
	target.remove_meta(CONTROL_LOCK_META)
	target.remove_meta(CONTROL_BASELINE_META)


func _finish(from_exit:bool) -> void:
	if _finished:
		return
	_finished = true

	_release_stun_visual()
	_release_control_lock()
	if target != null and is_instance_valid(target):
		target.Repel = Vector2.ZERO

	if not from_exit:
		queue_free()


func _exit_tree() -> void:
	_finish(true)
