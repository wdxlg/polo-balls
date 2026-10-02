extends Node

# 小丑专用持续吸引效果：现在只负责黑洞。
# 通用击退/滑行/撞墙反弹已经移动到：
# res://scripts/effects/knockback_effect.gd
# 并由 ball.apply_knockback() 给所有角色复用。

const FORCE = preload("res://scripts/effects/knockback_effect.gd")
var target:ball = null
var target_point:Vector2 = Vector2.ZERO
var pull_radius:float = 260.0
var motion_speed:float = 1120.0
var pull_edge_ratio:float = 0.42
var duration:float = 1.0

var _elapsed:float = 0.0
var _finished:bool = false


func _ready() -> void:
	if target == null and get_parent() is ball:
		target = get_parent() as ball

	if not _target_is_usable():
		queue_free()
		return

	# 比目标角色晚执行，每帧在 ball 清 Repel 后重新补回吸力。
	process_physics_priority = target.process_physics_priority + 100


func _physics_process(delta:float) -> void:
	if _finished:
		return
	if not _target_is_usable():
		_finish(false)
		return

	if not target.is_multiplayer_authority() or not target.is_combat_runtime_active(): return
	_elapsed += delta
	if _elapsed >= maxf(duration,0.01):
		_finish(false)
		return

	var to_center:Vector2 = target_point - target.global_position
	var distance_to_center:float = to_center.length()
	if distance_to_center <= 1.0 or distance_to_center > maxf(pull_radius,1.0):
		FORCE.release_pull(target,self)
		return

	var normalized_distance:float = clampf(
		distance_to_center / maxf(pull_radius,1.0),
		0.0,
		1.0
	)
	var center_factor:float = 1.0 - normalized_distance
	var strength_factor:float = lerpf(
		clampf(pull_edge_ratio,0.0,1.0),
		1.30,
		center_factor
	)

	FORCE.set_pull(target,self,(
		to_center.normalized()
		* maxf(motion_speed,0.0)
		* strength_factor
	))


func _target_is_usable() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.Type != ball.Ball_Type.Ball:
		return false
	if target.health <= 0:
		return false
	if target.state_machine and target.state_machine.current_state == ball.State.Die:
		return false
	return true


func _finish(from_exit:bool) -> void:
	if _finished:
		return
	_finished = true
	FORCE.release_pull(target,self)
	if not from_exit:
		queue_free()


func _exit_tree() -> void:
	_finish(true)
