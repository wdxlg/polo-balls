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
	# Ignore spawn/teleport deltas; a stopped or wall-blocked body cannot bank thrust.
	var moving:bool = traveled.length() > 0.001 and traveled.length() < maxf(12.0,base_speed*delta*5.0)
	if acceleration > 0.0 and moving:
		momentum = traveled.normalized()*minf(momentum.length()+acceleration*delta,base_speed*ratio)
	elif acceleration > 0.0:
		momentum = Vector2.ZERO
	else:
		momentum = momentum.move_toward(Vector2.ZERO,release_deceleration*delta)
	target.surface_motion_velocity = momentum
	if surfaces.is_empty() and momentum.is_zero_approx(): queue_free()

func _clear() -> void:
	var target:Variant = target_ref.get_ref() if target_ref != null else null
	if is_instance_valid(target): target.surface_motion_velocity = Vector2.ZERO
	momentum = Vector2.ZERO

func _exit_tree() -> void:
	_clear()
