extends Node
## One authority-owned controller per body; overlapping surfaces never multiply thrust.
## A surface supplies surface_acceleration_at(world_point). Motion uses the shared
## ball velocity channel, NOT teleports, Speed buffs or knockback/control ownership.
const NODE_NAME:StringName = &"SurfaceAcceleration"
var target_ref:WeakRef
var surfaces:Dictionary = {} # instance ID -> weak surface reference
var momentum:Vector2 = Vector2.ZERO
var previous_position:Vector2
var release_deceleration:float = 600.0
var _preserve_reflected_sample:bool = false
var _reflected_distance:float = 0.0
var _reflected_heading:Vector2 = Vector2.ZERO

static func touch(target:ball,surface:Node2D) -> Node:
	if not is_instance_valid(target) or not target.is_multiplayer_authority() or target.health <= 0: return null
	if target.Type not in [ball.Ball_Type.Ball,ball.Ball_Type.Creature]: return null
	var effect:Node = target.get_node_or_null(NodePath(NODE_NAME))
	if effect != null and effect.is_queued_for_deletion():
		target.remove_child(effect)
		effect = null
	if effect == null:
		effect = load("res://scripts/effects/surface_acceleration.gd").new()
		effect.name = NODE_NAME
		effect.target_ref = weakref(target)
		effect.previous_position = target.global_position
		effect.process_physics_priority = -50
		target.add_child(effect)
	effect.surfaces[surface.get_instance_id()] = weakref(surface)
	return effect

func _physics_process(delta:float) -> void:
	var target:Variant = target_ref.get_ref() if target_ref != null else null
	if not is_instance_valid(target) or target.health <= 0 or not target.is_multiplayer_authority():
		_clear()
		queue_free()
		return
	if not target.is_combat_runtime_active():
		previous_position = target.global_position
		return
	if delta <= 0.0: return
	var acceleration:float = 0.0
	var ratio:float = 0.0
	for id:int in surfaces.keys():
		var surface:Variant = (surfaces[id] as WeakRef).get_ref()
		if not is_instance_valid(surface) or surface.is_queued_for_deletion():
			surfaces.erase(id)
			continue
		var info:Dictionary = surface.surface_acceleration_at(target.global_position)
		if info.is_empty():
			surfaces.erase(id)
			continue
		acceleration = maxf(acceleration,float(info.get("acceleration",0.0)))
		ratio = maxf(ratio,float(info.get("max_bonus_ratio",0.0)))
		release_deceleration = maxf(float(info.get("release_deceleration",600.0)),1.0)
	var traveled:Vector2 = target.global_position-previous_position
	previous_position = target.global_position
	var base_speed:float = maxf(target.Speed,0.0)*(target.CHARACTER_BASE_MOVE_SPEED_MULTIPLIER if target.Type == ball.Ball_Type.Ball else 1.0)
	# A real pre-reflection leg must not disappear when reflect_momentum resets
	# the sampling origin. Otherwise frequent real bounces freeze acceleration.
	var moving:bool = _is_real_motion(target,traveled,delta) or _reflected_distance > 0.001
	var heading:Vector2 = traveled.normalized()
	if _preserve_reflected_sample and not _reflected_heading.is_zero_approx(): heading = _reflected_heading
	if acceleration > 0.0 and moving:
		var limit:float = base_speed*ratio
		if target.has_method("get_surface_acceleration_speed_limit"):
			limit = maxf(float(target.get_surface_acceleration_speed_limit(limit)),0.0)
		momentum = heading*minf(momentum.length()+acceleration*delta,limit)
	elif acceleration > 0.0:
		if not _preserve_reflected_sample: momentum = Vector2.ZERO
	else:
		momentum = momentum.move_toward(Vector2.ZERO,release_deceleration*delta)
	_preserve_reflected_sample = false
	_reflected_distance = 0.0
	_reflected_heading = Vector2.ZERO
	target.surface_motion_velocity = momentum
	if surfaces.is_empty() and momentum.is_zero_approx(): queue_free()

func _is_real_motion(target:ball,traveled:Vector2,delta:float) -> bool:
	var base_speed:float = maxf(target.Speed,0.0)*(target.CHARACTER_BASE_MOVE_SPEED_MULTIPLIER if target.Type == ball.Ball_Type.Ball else 1.0)
	# Compare against already existing/requested physical speed, not only the
	# configured base stat. Still reject discontinuous spawn/teleport jumps.
	var expected_speed:float = maxf(base_speed,maxf(momentum.length(),target._last_requested_velocity.length()))
	return traveled.length() > 0.001 and traveled.length() < maxf(12.0,expected_speed*maxf(delta,0.0)*5.0)

func steer_momentum(heading:Vector2,include_release:bool = false) -> void:
	var target:Variant = target_ref.get_ref() if target_ref != null else null
	if not is_instance_valid(target) or target.health <= 0 or not target.is_multiplayer_authority() or not target.is_combat_runtime_active(): return
	if heading.is_zero_approx() or (surfaces.is_empty() and not include_release): return
	# Only redirect existing momentum. Input alone cannot create or bank thrust.
	momentum = heading.normalized()*momentum.length()
	if _preserve_reflected_sample: _reflected_heading = heading.normalized()
	target.surface_motion_velocity = momentum

func reflect_momentum(normal:Vector2) -> void:
	var target:Variant = target_ref.get_ref() if target_ref != null else null
	if not is_instance_valid(target) or not target.is_multiplayer_authority() or not target.is_combat_runtime_active(): return
	if normal.is_zero_approx(): return
	var traveled:Vector2 = target.global_position-previous_position
	if _is_real_motion(target,traveled,target.get_physics_process_delta_time()): _reflected_distance += traveled.length()
	var incoming:Vector2 = momentum.normalized() if not momentum.is_zero_approx() else _reflected_heading
	if incoming.is_zero_approx(): incoming = target._last_requested_velocity.normalized()
	_reflected_heading = incoming.bounce(normal.normalized()) if incoming.dot(normal) < 0.0 else incoming
	if momentum.dot(normal) < 0.0: momentum = momentum.bounce(normal.normalized())
	target.surface_motion_velocity = momentum
	# Do not re-integrate the pre-impact displacement into the old inward direction.
	previous_position = target.global_position
	# Keep any real traveled leg plus its outgoing heading. A reflection with
	# no movement only gets the existing one-sample grace, never acceleration.
	_preserve_reflected_sample = true

func _clear() -> void:
	var target:Variant = target_ref.get_ref() if target_ref != null else null
	if is_instance_valid(target): target.surface_motion_velocity = Vector2.ZERO
	momentum = Vector2.ZERO
	_reflected_distance = 0.0
	_reflected_heading = Vector2.ZERO
	_preserve_reflected_sample = false

func _exit_tree() -> void:
	_clear()
