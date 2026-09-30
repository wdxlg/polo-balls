extends "res://scripts/effects/knockback_effect.gd"
## Physical lift for any ball: real body + collider sweep, authority movement, shared control lock.
## Caller RPCs the same launch to all peers; only the authoritative instance moves the body.
## Override _on_landing(point) for role-specific sounds/damage; use landed_at for other effects.
signal landed_at(point:Vector2,apex_height:float)
@export var height_meta_key:StringName = &"airborne_height"
var height:float = 0.0
var peak_height:float = 0.0
var flight_elapsed:float = 0.0
var flight_duration:float = 0.0
var landed:bool = false
var landing_position:Vector2 = Vector2.ZERO
var landing_hits:int = 0
var _start_height:float = 0.0
var _initial_speed:float = 0.0
var _gravity:float = 1.0
var horizontal_speed:float = 0.0
var _vertical_speed:float = 0.0
var _ground_y:float = 0.0
var _contact_landed:bool = false
var _map_regions:Array[Rect2] = []

static func launch(victim:ball,caster:Node,apex:float,up_speed:float,stun:float,side_speed:float = 0.0,options:Dictionary = {}) -> Node:
	if not is_instance_valid(victim) or victim.health<=0 or not victim.can_receive_control_from(caster): return null
	var script:Script = options.get("effect_script",load("res://scripts/effects/physical_airborne_effect.gd"))
	var effect_name:String = str(options.get("name","KnockbackEffect_Airborne"))
	var effect:Node = victim.get_node_or_null(effect_name)
	if effect != null and (effect.get_script()!=script or effect._finished):
		effect.name = "RetiredAirborne_" + str(effect.get_instance_id())
		effect = null
	var fresh:bool = effect==null
	if fresh: effect = script.new()
	effect.name = effect_name
	effect.target = victim
	effect.source = caster
	effect.horizontal_speed = side_speed
	var properties:Dictionary = options.get("properties",{})
	for key:Variant in properties: effect.set(str(key),properties[key])
	if is_instance_valid(caster): effect.set_multiplayer_authority(caster.get_multiplayer_authority())
	if fresh:
		effect.distance = apex
		effect.speed = up_speed
		effect.stun_duration = stun
		victim.add_child(effect)
	else: effect.relaunch(apex,up_speed,stun)
	return effect

func _ready() -> void:
	if not _target_is_usable() or not target.can_receive_control_from(source):
		_finish(false)
		return
	if respect_target_displacement_immunity(): return
	process_physics_priority = target.process_physics_priority+110
	_ground_y = target.global_position.y
	add_to_group("GenericAirborne")
	if is_multiplayer_authority(): _acquire_control_lock()
	relaunch(distance,speed,stun_duration)

func relaunch(apex:float,up_speed:float,stun:float) -> void:
	# Re-hit merges into the existing flight without a ground snap or stacked AOE.
	distance = maxf(apex,1.0)
	speed = maxf(up_speed,1.0)
	stun_duration = maxf(stun_duration,stun)
	if landed:
		peak_height = 0.0
		_ground_y = target.global_position.y
	height = maxf(_ground_y-target.global_position.y,0.0)
	_contact_landed = false
	_start_height = height
	_gravity = speed*speed/(2.0*distance)
	_initial_speed = sqrt(2.0*_gravity*maxf(distance-_start_height,0.0))
	flight_duration = (_initial_speed+sqrt(_initial_speed*_initial_speed+2.0*_gravity*_start_height))/_gravity
	flight_elapsed = 0.0
	_vertical_speed = -_initial_speed
	landed = false
	_stun_elapsed = 0.0
	_release_stun_visual()
	if is_multiplayer_authority(): _acquire_control_lock()
	_apply_height()

func _physics_process(delta:float) -> void:
	advance(delta)

func advance(delta:float) -> void:
	if _finished: return
	if not _target_is_usable():
		_finish(false)
		return
	if not target.is_combat_runtime_active(): return
	if is_instance_valid(source) and not target.can_receive_control_from(source):
		_finish(false)
		return
	if landed:
		_stun_elapsed += maxf(delta,0.0)
		if _stun_elapsed>=stun_duration: _finish(false)
		return
	# Replicas receive the real root transform via the existing ball synchronizer.
	# They must not independently move a second collision body or lift Graphics.
	if not is_multiplayer_authority():
		height = maxf(_ground_y-target.global_position.y,0.0)
		_apply_height()
		return
	_refresh_map_regions()
	var remaining:float = target.motion_scaled_delta(delta)
	while remaining>0.000001 and not landed:
		# Small swept steps include thin obstacles and the real trajectory's apex.
		var dt:float = minf(remaining,minf(1.0/240.0,1.0/maxf(absf(_vertical_speed)+absf(horizontal_speed),1.0)))
		if _vertical_speed<0.0: dt = minf(dt,maxf(-_vertical_speed/_gravity,0.000001))
		_step_body(dt)
		remaining -= dt
	_apply_height()

func _refresh_map_regions() -> void:
	_map_regions.clear()
	var world:Node = get_tree().current_scene
	if world==null: return
	if world.has_method("current_map_island_rects"):
		for rect:Rect2 in world.current_map_island_rects():
			if rect.has_area(): _map_regions.append(rect)
	if not _map_regions.is_empty(): return
	if world.has_method("_current_map_node") and world.has_method("return_map_world_rect"):
		var map_node:Node = world._current_map_node()
		if map_node!=null:
			var rect:Rect2 = world.return_map_world_rect(map_node)
			if rect.has_area(): _map_regions.append(rect)

func body_rect() -> Rect2:
	var shape:CollisionShape2D = target.collision_shape_2d
	if is_instance_valid(shape) and shape.shape!=null:
		return shape.global_transform*shape.shape.get_rect()
	return Rect2(target.global_position-Vector2.ONE,Vector2.ONE*2.0)

func _rect_in_map(rect:Rect2) -> bool:
	if _map_regions.is_empty(): return true
	# Subtract the union, not each region separately: adjacent floor tiles/islands
	# with shared edges must not produce artificial internal walls.
	var uncovered:Array[Rect2] = [rect]
	for region:Rect2 in _map_regions:
		var next:Array[Rect2] = []
		for piece:Rect2 in uncovered:
			var overlap:Rect2 = piece.intersection(region)
			if not overlap.has_area():
				next.append(piece)
				continue
			for part:Rect2 in [
				Rect2(piece.position,Vector2(piece.size.x,overlap.position.y-piece.position.y)),
				Rect2(Vector2(piece.position.x,overlap.end.y),Vector2(piece.size.x,piece.end.y-overlap.end.y)),
				Rect2(Vector2(piece.position.x,overlap.position.y),Vector2(overlap.position.x-piece.position.x,overlap.size.y)),
				Rect2(Vector2(overlap.end.x,overlap.position.y),Vector2(piece.end.x-overlap.end.x,overlap.size.y))]:
				if part.size.x>0.0001 and part.size.y>0.0001: next.append(part)
		uncovered = next
		if uncovered.is_empty(): return true
	return false

func _fits_motion(motion:Vector2) -> bool:
	var rect:Rect2 = body_rect()
	return _rect_in_map(rect.merge(Rect2(rect.position+motion,rect.size)))

func _step_body(dt:float) -> void:
	var descending:bool = _vertical_speed>=0.0
	var motion := Vector2(horizontal_speed*dt,_vertical_speed*dt+0.5*_gravity*dt*dt)
	_vertical_speed += _gravity*dt
	flight_elapsed += dt
	var reaches_ground:bool = descending and target.global_position.y+motion.y>=_ground_y
	if reaches_ground: motion.y = maxf(_ground_y-target.global_position.y,0.0)
	var map_block_x:bool = false
	var map_block_y:bool = false
	var wanted_motion:Vector2 = motion
	if not _fits_motion(motion):
		map_block_x = not _fits_motion(Vector2(motion.x,0.0))
		map_block_y = not _fits_motion(Vector2(0.0,motion.y))
		if not map_block_x and not map_block_y:
			map_block_x = absf(motion.x)>0.00001
			map_block_y = absf(motion.y)>0.00001
		var low:float = 0.0
		var high:float = 1.0
		for iteration:int in range(16):
			var fraction:float = (low+high)*0.5
			if _fits_motion(motion*fraction): low = fraction
			else: high = fraction
		motion *= low
	var collision:KinematicCollision2D = null
	if not motion.is_zero_approx(): collision = target.move_and_collide(motion,false,0.001)
	# Height is measured from actual position AFTER collision, never nominal arc.
	height = maxf(_ground_y-target.global_position.y,0.0)
	peak_height = maxf(peak_height,height)
	if map_block_x: horizontal_speed = 0.0
	if map_block_y:
		if descending: _contact_landed = true
		else: _vertical_speed = maxf(_vertical_speed,0.0)
	if collision!=null:
		var normal:Vector2 = collision.get_normal()
		if absf(normal.x)>0.25: horizontal_speed = 0.0
		if motion.y<0.0 and normal.y>0.25: _vertical_speed = maxf(_vertical_speed,0.0)
		if descending and motion.y>=0.0 and normal.y< -0.25: _contact_landed = true
	if reaches_ground and target.global_position.y>=_ground_y-0.01: _contact_landed = true
	_report_forced_collision(collision,wanted_motion,map_block_x,map_block_y)
	target.velocity = Vector2(horizontal_speed,_vertical_speed)
	_apply_height()
	if _contact_landed: land()

# Optional target hook (e.g. the spider weaves silk on any obstacle contact even
# while airborne). Map-rect clamping stops short of the wall without a physics
# collision, so probe the blocked axis test-only to find the real surface.
func _report_forced_collision(collision:KinematicCollision2D,wanted:Vector2,block_x:bool,block_y:bool) -> void:
	if not target.has_method(&"on_forced_motion_collision"): return
	if collision==null and (block_x or block_y):
		var probe := Vector2(signf(wanted.x)*4.0 if block_x else 0.0,signf(wanted.y)*4.0 if block_y else 0.0)
		if not probe.is_zero_approx(): collision = target.move_and_collide(probe,true,0.001)
	if collision!=null: target.call(&"on_forced_motion_collision",collision)

func _apply_height() -> void:
	# No Graphics, health bar or shadow offset: all three follow the actual body.
	if is_instance_valid(target) and not _finished: target.set_meta(height_meta_key,height)

func ground_center() -> Vector2:
	var ring:Dictionary = target.get_character_ground_shadow_ring_data(0.0)
	return ring.get("center",target.global_position)

func land() -> void:
	if landed or _finished or not is_multiplayer_authority() or not _target_is_usable() or not target.is_combat_runtime_active(): return
	if not _contact_landed: return
	landed = true
	height = 0.0
	_apply_height()
	landing_position = ground_center()
	landed_at.emit(landing_position,peak_height)
	_on_landing(landing_position)
	if _target_is_usable(): _acquire_stun_visual()
	else: _finish(false)

func _on_landing(_point:Vector2) -> void:
	pass

func _finish(from_exit:bool) -> void:
	if _finished: return
	_finished = true
	height = 0.0
	if is_instance_valid(target): target.remove_meta(height_meta_key)
	_release_stun_visual()
	_release_control_lock()
	# An independent planar knockback may still own Repel.
	if not from_exit: queue_free()
