extends Node
## Additive, freely steerable impulses. Distance is a free-space reference, not owed travel.
## Legacy tuning fields remain load-compatible; only explicit stun acquires a control lock.

var target:ball = null
var source:Node = null

var direction:Vector2 = Vector2.RIGHT
var distance:float = 100.0
var speed:float = 700.0

var wall_bounce_strength:float = 0.0
var max_wall_bounces:int = 1

var stop_on_character:bool = true
var character_bounce_strength:float = 0.0

var lock_control_during_knockback:bool = false

var stun_duration:float = 0.0
var stun_only_on_collision:bool = false

var collision_damage:float = 0.0
var collision_damage_wall_only:bool = false
var collision_damage_ignore_block:bool = false

var use_speed_falloff:bool = false
@export_range(0.0,1.0,0.01) var end_speed_ratio:float = 0.35

var smooth_motion:bool = true
@export_range(0.05,0.8,0.01) var smooth_end_ratio:float = 0.32
@export_range(0.0,0.5,0.01) var smooth_end_speed_ratio:float = 0.0
@export_range(0.0,0.2,0.005) var redirect_blend_time:float = 0.055
@export_range(0.0,0.25,0.005) var control_recovery_time:float = 0.085
@export_range(0.1,4.0,0.1) var finish_distance_epsilon:float = 0.65
@export_range(0.0,0.3,0.005) var minimum_motion_time:float = 0.10

var bounce_recovery_time:float = 0.0
var bounce_start_speed_ratio:float = 1.0

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


var _motion:Node
var _motion_done:bool = false
var _drag:float = 1.0
var _lifetime:float = 0.0
var _contacts:Dictionary = {}

func _ready() -> void:
	if target == null and get_parent() is ball: target = get_parent() as ball
	if not _target_is_usable() or not target.is_multiplayer_authority():
		_finished = true
		queue_free()
		return
	if not is_instance_valid(source): source = null
	if not target.can_receive_control_from(source):
		_finished = true
		queue_free()
		return
	if respect_target_displacement_immunity(): return
	process_physics_priority = target.process_physics_priority+100
	_motion = target.get_body_motion()
	if _motion == null:
		_finish(false)
		return
	_current_direction = _safe_direction(direction)
	var reference_time:float = maxf(distance/maxf(speed,0.1),maxf(minimum_motion_time,1.0/60.0))
	_current_speed = minf(maxf(speed,0.0),maxf(distance,0.0)/reference_time)
	_drag = 1.0/maxf(reference_time,0.0001)
	_lifetime = minf(maxf(log(maxf(_current_speed,0.11)/0.1)/_drag,0.05),6.0)
	_last_position = target.global_position
	_motion_done = distance<=0.0 or _current_speed<=0.0
	if not _motion_done:
		_motion.add_impulse(get_instance_id(),_current_direction*_current_speed,_drag,wall_bounce_strength)
	if stun_duration>0.0 and not stun_only_on_collision: _start_stun()
	if _motion_done and _stage!=1: _finish(false)

# Compatibility for direct legacy callers; ordinary hits never replace another vector.
func replace_with_hit(new_direction:Vector2,new_distance:float,new_speed:float,new_wall_bounce_strength:float,new_stun_duration:float,options:Dictionary={}) -> void:
	if _target_is_usable():
		options = options.duplicate()
		options["replace_existing"] = false
		target.apply_knockback(new_direction,new_distance,new_speed,new_wall_bounce_strength,new_stun_duration,options)

func is_soft_control_lock_active() -> bool:
	return false
func is_active_effect() -> bool:
	return not _finished
func _physics_process(delta:float) -> void:
	if _finished: return
	if not is_instance_valid(source): source = null
	if not _target_is_usable() or not target.is_multiplayer_authority() or not target.can_receive_control_from(source):
		_finish(false)
		return
	if not target.is_combat_runtime_active() or get_tree().paused: return
	if respect_target_displacement_immunity(): return
	_elapsed += maxf(delta,0.0)
	if not _motion_done:
		var value:Vector2 = _motion.impulses[get_instance_id()].velocity if _motion.impulses.has(get_instance_id()) else Vector2.ZERO
		_current_speed = value.length()
		if not value.is_zero_approx(): _current_direction = value.normalized()
		_handle_collisions()
		if not _finished and (_elapsed>=_lifetime or not _motion.impulses.has(get_instance_id())):
			_finish_knockback(false)
	if _stage == 1 and not _finished: _process_stun(delta)

func _handle_collisions() -> bool:
	if _motion._compose_frame!=Engine.get_physics_frames(): return false
	for index:int in range(target.get_slide_collision_count()):
		var contact:KinematicCollision2D=target.get_slide_collision(index)
		if contact == null: continue
		var collider:Object=contact.get_collider()
		if not is_instance_valid(collider): continue
		var key:int=collider.get_instance_id()
		if _contacts.has(key): continue
		# The body solver has already reflected momentum. Use the requested incoming direction.
		if target._last_requested_velocity.dot(contact.get_normal())>=-0.1: continue
		_contacts[key]=true
		_current_speed=maxf(_current_speed,minf(speed,target._last_requested_velocity.length()))
		if collider is ball: _handle_character_collision(contact.get_normal(),contact.get_position())
		else: _handle_wall_collision(contact.get_normal(),contact.get_position())
		if _finished: return true
	return false
func _handle_wall_collision(_normal:Vector2,impact_position:Vector2) -> bool:
	_had_collision=true
	_wall_bounces+=1
	_apply_collision_damage(impact_position)
	if stun_duration>0.0: _start_stun()
	if not _motion.impulses.has(get_instance_id()) or Vector2(_motion.impulses[get_instance_id()].velocity).length_squared()<0.01:
		_finish_knockback(true)
	return _finished
func _handle_character_collision(_normal:Vector2,impact_position:Vector2) -> bool:
	_had_collision=true
	if not collision_damage_wall_only: _apply_collision_damage(impact_position)
	if stun_duration>0.0: _start_stun()
	return false
func _start_stun() -> void:
	_stage=1
	_stun_elapsed=0.0
	_acquire_control_lock()
	_acquire_stun_visual()
func _finish_knockback(from_collision:bool) -> void:
	if from_collision and stun_duration>0.0 and _stage!=1: _start_stun()
	_motion_done=true
	if is_instance_valid(_motion): _motion.remove_impulse(get_instance_id())
	if _stage!=1: _finish(false)
func _process_stun(delta:float) -> void:
	_stun_elapsed+=maxf(delta,0.0)
	if _stun_elapsed>=stun_duration:
		_release_stun_visual()
		_release_control_lock()
		_stage=0
		if _motion_done: _finish(false)

func respect_target_displacement_immunity() -> bool:
	if _finished or _stage == 1 or distance <= 0.0 or not _target_is_usable(): return false
	if not target.has_method("is_knockback_displacement_immune") or not bool(target.call("is_knockback_displacement_immune")): return false
	var keep_stun:bool = stun_duration > 0.0 and (not stun_only_on_collision or _had_collision)
	var stun_source:Node = source if is_instance_valid(source) else null
	_finish(false)
	if keep_stun: target.apply_stun(stun_duration,stun_source)
	return true

func _apply_collision_damage(impact_position:Vector2) -> void:
	if collision_damage <= 0.0 or not _target_is_usable():
		return

	target.receive_positional_damage(collision_damage,impact_position,collision_damage_ignore_block,self)


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
	if is_instance_valid(_motion): _motion.remove_impulse(get_instance_id())

	if not from_exit:
		queue_free()


func _exit_tree() -> void:
	_finish(true)


# Non-exclusive, refreshed pull leases: unlike finite-distance knockback these
# must coexist with voluntary movement and an already active knockback controller.
# Contributions never accumulate in Repel and never acquire a control lock.
const PULL_META:StringName = &"shared_motion_pull_leases"

static func set_pull(unit:ball,caster:Node,pull:Vector2) -> bool:
	if not is_instance_valid(unit) or unit.is_queued_for_deletion() or unit.health <= 0 or not unit.is_multiplayer_authority(): return false
	if not is_instance_valid(caster) or caster.is_queued_for_deletion() or not caster.is_inside_tree(): return false
	if caster is ball and (caster.health <= 0 or not caster.is_multiplayer_authority() or caster.is_damage_output_disabled()): return false
	if not unit.is_combat_runtime_active() or not unit.can_receive_control_from(caster): return false
	if unit.has_method("is_knockback_displacement_immune") and bool(unit.call("is_knockback_displacement_immune")): return false
	if not pull.is_finite(): return false
	var leases:Dictionary = unit.get_meta(PULL_META,{})
	leases[caster.get_instance_id()] = {"caster":weakref(caster),"velocity":pull,"frame":Engine.get_physics_frames()}
	unit.set_meta(PULL_META,leases)
	return true

static func release_pull(unit:ball,caster:Node) -> void:
	if not is_instance_valid(unit) or not unit.has_meta(PULL_META) or not is_instance_valid(caster): return
	var leases:Dictionary = unit.get_meta(PULL_META)
	leases.erase(caster.get_instance_id())
	if leases.is_empty(): unit.remove_meta(PULL_META)

static func pull_velocity(unit:ball) -> Vector2:
	if not unit.has_meta(PULL_META) or not unit.is_multiplayer_authority() or unit.health <= 0 or not unit.is_combat_runtime_active(): return Vector2.ZERO
	var leases:Dictionary = unit.get_meta(PULL_META)
	var result:Vector2 = Vector2.ZERO
	var immune:bool = unit.has_method("is_knockback_displacement_immune") and bool(unit.call("is_knockback_displacement_immune"))
	for id:int in leases.keys():
		var entry:Dictionary = leases[id]
		var caster:Variant = (entry.caster as WeakRef).get_ref()
		# The owner refreshes every physics step; stale/deleted owners cannot
		# leave a permanent force behind. Two frames cover caller update order.
		var stale:bool = Engine.get_physics_frames()-int(entry.frame) > 2
		if not is_instance_valid(caster) or stale or immune:
			leases.erase(id)
			continue
		if caster.is_queued_for_deletion() or not caster.is_inside_tree() or not unit.can_receive_control_from(caster):
			leases.erase(id)
			continue
		if caster is ball and (caster.health <= 0 or not caster.is_multiplayer_authority() or not caster.is_combat_runtime_active() or caster.is_damage_output_disabled()):
			leases.erase(id)
			continue
		result += entry.velocity
	if leases.is_empty(): unit.remove_meta(PULL_META)
	return result

func get_status_effect_polarity() -> int:
	# Self-powered recoil/dashes are not negative statuses; hostile displacement
	# and source-less/hostile stuns are. Descendant airborne effects share this.
	return 0 if source==target and stun_duration<=0.0 else -1

func cleanse_status_effect() -> void:
	_finish(false) # Virtual dispatch retains specialized airborne cleanup.
