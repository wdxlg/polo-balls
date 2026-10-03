extends Node
## Shared actor momentum and exact-body depenetration. Presentation never drives physics.
const EXCLUSIONS = preload("res://classes/body_collision_exclusions.gd")
const RESTITUTION:float = 0.85
const CONTACT_DRAG:float = 7.0
const POSITION_SLOP:float = 0.03
const MAX_CORRECTION:float = 3.0
var actor:CharacterBody2D
var motor:Vector2 = Vector2.ZERO
var current_velocity:Vector2 = Vector2.ZERO
var impulses:Dictionary = {}
var contact_frame:int = -1
var contacts:Array[Dictionary] = []
var _initialized:bool = false
var _advance_frame:int = -1
var _compose_frame:int = -1
var _direct_frame:int = -1
var _was_direct:bool = false
var _correction_frame:int = -1
var _correction_used:float = 0.0
var _drive:Vector2 = Vector2.ZERO
var _drive_delta:float = 0.0
var _drive_origin:Vector2
var _pressure_frame:int = -1
var _last_position:Vector2
static var _motion_frame:int = -1
static var _pair_frame:int = -1
static var _pairs:Dictionary = {}
static var _overlaps:Dictionary = {}

func _ready() -> void:
	process_physics_priority = 1000
	_last_position = actor.global_position
func live() -> bool:
	return is_instance_valid(actor) and not actor.is_queued_for_deletion() and actor.is_inside_tree() and actor.is_multiplayer_authority() and actor.health > 0 and actor.is_combat_runtime_active() and not get_tree().paused
func inverse_mass() -> float:
	if bool(actor.get_meta("body_motion_immovable",false)): return 0.0
	if actor.has_method("is_knockback_displacement_immune") and actor.is_knockback_displacement_immune(): return 0.0
	return 1.0
func physical_body() -> bool:
	return actor.collision_shape_2d != null and actor.collision_shape_2d.shape != null and not actor.collision_shape_2d.disabled and (actor.collision_layer & 2)!=0 and (actor.collision_mask & 2)!=0
func held() -> bool:
	return actor.is_transport_mounted() or actor.has_meta("mc_sticky_hold") or (actor.dizziness and actor.collision_layer==0 and actor.collision_mask==0)
func reset_motion() -> void:
	_drive = Vector2.ZERO
	impulses.clear()
	motor = Vector2.ZERO
	current_velocity = Vector2.ZERO
	_initialized = false
	_was_direct = false
func transform_motion(map_vector:Callable) -> void:
	_drive = Vector2.ZERO
	motor = map_vector.call(motor)
	current_velocity = map_vector.call(current_velocity)
	for entry:Dictionary in impulses.values(): entry.velocity = map_vector.call(entry.velocity)
func externally_driven() -> bool:
	return held() or actor.has_meta("map_rescue_animating") or actor.has_meta("airborne_height") or bool(actor.get_meta("mc_ignore_character_body_collision",false))
static func _begin_frame() -> void:
	var frame:int = Engine.get_physics_frames()
	if _pair_frame != frame:
		_pair_frame = frame
		_pairs.clear()
		_overlaps.clear()
static func _pair_key(a:Node,b:Node) -> String:
	return "%s:%s" % [mini(a.get_instance_id(),b.get_instance_id()),maxi(a.get_instance_id(),b.get_instance_id())]
func advance(delta:float) -> void:
	var frame:int = Engine.get_physics_frames()
	if _advance_frame == frame: return
	_advance_frame = frame
	for key:Variant in impulses.keys():
		var entry:Dictionary = impulses[key]
		if int(entry.frame)<frame: entry.velocity *= exp(-float(entry.drag)*maxf(delta,0.0))
		if Vector2(entry.velocity).length_squared()<0.01: impulses.erase(key)
func add_impulse(key:int,value:Vector2,drag:float=CONTACT_DRAG,wall_bounce:float=RESTITUTION) -> void:
	if not live() or inverse_mass()<=0.0 or not value.is_finite(): return
	var previous:Vector2 = impulses[key].velocity if impulses.has(key) else Vector2.ZERO
	impulses[key] = {"velocity":previous+value,"drag":maxf(drag,0.1),"frame":Engine.get_physics_frames(),"wall_bounce":maxf(wall_bounce,0.0)}
	current_velocity += value
func remove_impulse(key:int) -> void:
	if impulses.has(key):
		current_velocity -= Vector2(impulses[key].velocity)
		impulses.erase(key)
func impulse_velocity() -> Vector2:
	var result:Vector2 = Vector2.ZERO
	for entry:Dictionary in impulses.values(): result += Vector2(entry.velocity)
	return result.limit_length(12000.0)
func compose(desired:Vector2,other:Vector2,delta:float) -> Vector2:
	if not desired.is_zero_approx() or not other.is_zero_approx() or not impulses.is_empty(): _motion_frame = Engine.get_physics_frames()
	_drive_origin = actor.global_position
	_drive = desired*actor.motion_speed_factor()
	_drive_delta = maxf(delta,0.0)
	if not live(): return Vector2.ZERO
	advance(delta)
	if held():
		motor = Vector2.ZERO
		current_velocity = Vector2.ZERO
		return Vector2.ZERO
	if not _initialized or _was_direct:
		_was_direct = false
		motor = desired
		_initialized = true
	elif actor.dizziness:
		motor = Vector2.ZERO
	elif desired.is_zero_approx() or impulses.is_empty():
		motor = desired
	else:
		var acceleration:float = maxf(maxf(desired.length(),actor.Speed*0.6),40.0)*16.0
		motor = motor.move_toward(desired,acceleration*maxf(delta,0.0))
	_compose_frame = Engine.get_physics_frames()
	current_velocity = motor+other+impulse_velocity()
	return current_velocity
func compose_direct(value:Vector2,delta:float) -> Vector2:
	if not value.is_zero_approx() or not impulses.is_empty(): _motion_frame = Engine.get_physics_frames()
	_drive = Vector2.ZERO
	if not live(): return Vector2.ZERO
	advance(delta)
	if held():
		motor = Vector2.ZERO
		current_velocity = Vector2.ZERO
		return Vector2.ZERO
	_was_direct = true
	_direct_frame = Engine.get_physics_frames()
	_compose_frame = _direct_frame
	_initialized = true
	motor = value
	current_velocity = value+impulse_velocity()
	return current_velocity
func resolve_slide(incoming:Vector2) -> void:
	if not live() or externally_driven(): return
	current_velocity = incoming
	for i:int in range(actor.get_slide_collision_count()):
		resolve_contact(actor.get_slide_collision(i))
	actor.velocity = current_velocity
func resolve_contact(collision:KinematicCollision2D) -> void:
	if collision == null: return
	var other:Object = collision.get_collider()
	var normal:Vector2 = collision.get_normal().normalized()
	if not is_instance_valid(other) or normal.is_zero_approx(): return
	if contact_frame != Engine.get_physics_frames():
		contact_frame = Engine.get_physics_frames()
		contacts.clear()
	if contacts.size()<32:
		contacts.append({"collider":weakref(other),"normal":normal,"point":collision.get_position(),"incoming":current_velocity})
	if other.has_method("get_body_motion"):
		resolve_pair(other,normal)
		return
	if actor._is_external_gravity_quiet_support_collision(collision) and collision.get_normal().dot(normal)>0.99: return
	# Native directional-gravity locomotion owns landing/ceiling cancellation and its hop.
	# Reflecting that same integrated gravity again would manufacture a second launch.
	if actor.is_external_directional_gravity_locomotion_enabled():
		var gravity_axis:float = actor.get_external_directional_gravity_velocity().dot(normal)
		if gravity_axis<0.0: current_velocity -= gravity_axis*normal
	var approach:float = current_velocity.dot(normal)
	if approach < -0.1:
		# Transform owned momentum in place, so ending one effect cannot expose an opposite
		# cancellation impulse. Per-effect wall bounce never scales the tangent.
		var before:Vector2 = impulse_velocity()
		for entry:Dictionary in impulses.values():
			var value:Vector2 = entry.velocity
			entry.velocity = value-(1.0+float(entry.wall_bounce))*value.dot(normal)*normal
		var change:Vector2 = impulse_velocity()-before
		var non_impulse:Vector2 = current_velocity-before
		current_velocity += change
		add_impulse(0,-(1.0+RESTITUTION)*non_impulse.dot(normal)*normal)
		reflect_motor(normal)
func reflect_motor(normal:Vector2) -> void:
	if actor.is_player_controlled() or actor.direction.dot(normal)>=0.0: return
	actor.direction = actor.direction.bounce(normal).normalized()
	if _direct_frame == Engine.get_physics_frames(): return
	var change:Vector2 = motor.bounce(normal)-motor if motor.dot(normal)<0.0 else Vector2.ZERO
	motor += change
	current_velocity += change
	add_impulse(0,-change)
func resolve_pair(other:Node,normal:Vector2) -> void:
	if not other.is_multiplayer_authority() or other.get_world_2d()!=actor.get_world_2d(): return
	if EXCLUSIONS.are_excluded(actor,other): return
	var b:Node = other.get_body_motion()
	if b == null or not b.live() or not b.physical_body() or b.externally_driven() or not physical_body(): return
	_begin_frame()
	var key:String = _pair_key(actor,other)
	if _pairs.has(key): return
	var relative:float = (current_velocity-b.current_velocity).dot(normal)
	if relative >= -0.1: return
	_pairs[key] = true
	var ia:float = inverse_mass()
	var ib:float = b.inverse_mass()
	if ia+ib<=0.0: return
	var impulse:Vector2 = -(1.0+RESTITUTION)*relative/(ia+ib)*normal
	add_impulse(0,impulse*ia)
	b.add_impulse(0,-impulse*ib)
	other.velocity = b.current_velocity
	reflect_motor(normal)
	b.reflect_motor(-normal)
func _press_contacts() -> void:
	# Apply continuing manual pressure after normal movement, not once per mob impact.
	# Predict from input rather than resultant velocity: opposed forces may reduce
	# the latter to zero while the player is still actively trying to make space.
	var frame:int = Engine.get_physics_frames()
	if not live() or _pressure_frame==frame or _compose_frame!=frame or not actor.is_player_controlled() or actor.dizziness or inverse_mass()<=0.0 or _drive.is_zero_approx() or _direct_frame==frame or externally_driven(): return
	_pressure_frame = frame
	var intended:Vector2 = _drive*_drive_delta
	var actual:Vector2 = actor.global_position-_drive_origin
	var axis:Vector2 = intended.normalized()
	var step:Vector2 = axis*minf(MAX_CORRECTION,intended.length()+maxf(0.0,-actual.dot(axis)))
	var cs:CollisionShape2D = actor.collision_shape_2d
	var bounds:Rect2 = cs.global_transform*cs.shape.get_rect()
	var swept:Rect2 = bounds.merge(Rect2(bounds.position+step,bounds.size)).grow(POSITION_SLOP)
	var first:Node
	var push:Vector2 = Vector2.ZERO
	var best:float = 0.0
	# A native recovery contact may be behind the player when other actors moved
	# first. Select the opposed surface from current swept geometry, not that contact.
	for other:Node in get_tree().get_nodes_in_group("Ball"):
		if other==actor or not _pressure_movable(other) or other.get_world_2d()!=actor.get_world_2d() or EXCLUSIONS.are_excluded(actor,other): continue
		var other_cs:CollisionShape2D = other.collision_shape_2d
		if not swept.intersects(other_cs.global_transform*other_cs.shape.get_rect()): continue
		var points:PackedVector2Array = cs.shape.collide_with_motion_and_get_contacts(cs.global_transform,step,other_cs.shape,other_cs.global_transform,Vector2.ZERO)
		for i:int in range(0,points.size()-1,2):
			var normal:Vector2 = (points[i+1]-points[i]).normalized()
			var motor_distance:float = maxf(0.0,-intended.dot(normal))
			if motor_distance<=0.0001: continue
			var distance:float = minf(MAX_CORRECTION,maxf(0.0,motor_distance+actual.dot(normal)))
			if distance>best:
				best=distance;first=other;push=-normal*distance
	if first!=null and best>0.0001: _press_group(first,push)

func _pressure_movable(unit:Object) -> bool:
	if not is_instance_valid(unit) or not unit is CharacterBody2D or not unit.has_method("get_body_motion"): return false
	var motion:Node = unit.get_body_motion()
	return motion != null and motion.live() and motion.physical_body() and not motion.externally_driven() and motion.inverse_mass()>0.0

func _pressure_budget(motion:Node) -> float:
	if motion._correction_frame != Engine.get_physics_frames():
		motion._correction_frame = Engine.get_physics_frames()
		motion._correction_used = 0.0
	return maxf(MAX_CORRECTION-motion._correction_used,0.0)

func _press_group(first:Object,offset:Vector2) -> void:
	if not _pressure_movable(first): return
	var bodies:Array[CharacterBody2D] = [actor,first]
	var exclusions:Array[RID] = [actor.get_rid(),first.get_rid()]
	var candidates:Array[Node] = get_tree().get_nodes_in_group("Ball")
	var index:int = 0
	while index<bodies.size():
		var unit:CharacterBody2D = bodies[index]
		offset = offset.limit_length(_pressure_budget(unit.get_body_motion()))
		if offset.length_squared()<0.000001: return
		var params:=PhysicsTestMotionParameters2D.new()
		params.from = unit.global_transform
		params.motion = offset
		params.margin = 0.001
		params.exclude_bodies = exclusions
		var hit:=PhysicsTestMotionResult2D.new()
		if PhysicsServer2D.body_test_motion(unit.get_rid(),params,hit):
			var blocker:Object = hit.get_collider()
			if _pressure_movable(blocker) and not bodies.has(blocker) and bodies.size()<64:
				bodies.append(blocker)
				exclusions.append(blocker.get_rid())
				continue
			# Terrain, an immovable body or the bounded search horizon limits the
			# entire contact chain. Exclusions exist only in this predictive query.
			offset *= clampf(hit.get_collision_safe_fraction(),0.0,1.0)
		# Kinematic server poses can lag nodes moved earlier in this same tick.
		# Validate swept shapes at their actual current poses before committing a chain.
		var cs:CollisionShape2D = unit.collision_shape_2d
		var bounds:Rect2 = cs.global_transform*cs.shape.get_rect()
		var swept:Rect2 = bounds.merge(Rect2(bounds.position+offset,bounds.size)).grow(POSITION_SLOP)
		for other:Node in candidates:
			if bodies.has(other) or not is_instance_valid(other) or not other.has_method("get_body_motion") or other.get_world_2d()!=unit.get_world_2d(): continue
			var other_motion:Node = other.get_body_motion()
			if other_motion==null or not other_motion.physical_body() or EXCLUSIONS.are_excluded(unit,other): continue
			var other_cs:CollisionShape2D = other.collision_shape_2d
			if not swept.intersects(other_cs.global_transform*other_cs.shape.get_rect()): continue
			if not cs.shape.collide_with_motion(cs.global_transform,offset,other_cs.shape,other_cs.global_transform,Vector2.ZERO): continue
			if not _pressure_movable(other) or bodies.size()>=64: return
			bodies.append(other)
			exclusions.append(other.get_rid())
		index += 1
	if offset.length_squared()<0.000001: return
	# Terrain is checked against the actual collision shape as well, without relying
	# on native recovery displacement or a temporary spawn-safety wall exception.
	for unit:CharacterBody2D in bodies:
		var cs:CollisionShape2D = unit.collision_shape_2d
		var query:=PhysicsShapeQueryParameters2D.new()
		query.shape=cs.shape;query.transform=cs.global_transform
		query.motion=offset;query.collision_mask=1;query.exclude=exclusions
		var space:PhysicsDirectSpaceState2D=unit.get_world_2d().direct_space_state
		var travel:PackedFloat32Array=space.cast_motion(query)
		offset *= travel[0] if not travel.is_empty() else 0.0
		query.motion=Vector2.ZERO;query.transform.origin+=offset
		if not space.intersect_shape(query,1).is_empty(): return
	if offset.length_squared()<0.000001: return
	# Commit together: sequential native moves see neighbors' old physics poses
	# and can deadlock the very chain that has just been proven free to translate.
	_motion_frame = Engine.get_physics_frames()
	for unit:CharacterBody2D in bodies:
		unit.global_position += offset
		unit.get_body_motion()._correction_used += offset.length()
func _safe_shift(unit:Node,offset:Vector2,_partner:Node) -> Vector2:
	if offset.length_squared()<0.000001: return Vector2.ZERO
	var owner_motion:Node = unit.get_body_motion()
	if owner_motion._correction_frame != Engine.get_physics_frames():
		owner_motion._correction_frame = Engine.get_physics_frames()
		owner_motion._correction_used = 0.0
	offset = offset.limit_length(maxf(MAX_CORRECTION-owner_motion._correction_used,0.0))
	var cs:CollisionShape2D = unit.collision_shape_2d
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = cs.shape
	query.transform = cs.global_transform
	query.motion = offset
	# Neighbor contacts are solved iteratively with the shared displacement budget.
	# Treating every touching neighbor as terrain deadlocks a packed but escapable cluster.
	query.collision_mask = 1
	query.exclude = [unit.get_rid()]
	var space:PhysicsDirectSpaceState2D = unit.get_world_2d().direct_space_state
	var cast:PackedFloat32Array = space.cast_motion(query)
	var move:Vector2 = offset*(cast[0] if not cast.is_empty() else 0.0)
	query.motion = Vector2.ZERO
	query.collision_mask = 1
	query.transform.origin += move
	if not space.intersect_shape(query,1).is_empty(): return Vector2.ZERO
	if not move.is_zero_approx(): _motion_frame = Engine.get_physics_frames()
	unit.global_position += move
	owner_motion._correction_used += move.length()
	return move
func separate_overlaps() -> void:
	if not physical_body() or externally_driven(): return
	var cs:CollisionShape2D = actor.collision_shape_2d
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = cs.shape
	query.transform = cs.global_transform
	query.collision_mask = 2
	# Motor steps and corrective shifts can leave same-tick physics poses behind nodes.
	# Resting crowds keep the narrow query instead of repeatedly testing near misses.
	query.margin = MAX_CORRECTION if _motion_frame==Engine.get_physics_frames() else 0.0
	query.exclude = [actor.get_rid()]
	_begin_frame()
	for hit:Dictionary in actor.get_world_2d().direct_space_state.intersect_shape(query,24):
		var other:Node = hit.collider as Node
		if not is_instance_valid(other) or not other.has_method("get_body_motion") or not other.is_multiplayer_authority(): continue
		if EXCLUSIONS.are_excluded(actor,other): continue
		var b:Node = other.get_body_motion()
		if b == null or not b.live() or not b.physical_body() or b.externally_driven(): continue
		var key:String = _pair_key(actor,other)
		# Both owners may refine a contact after neighbors move; impact impulses
		# remain once per pair, and all corrections share the same body budget.
		var refinements:int = 2 if _motion_frame==Engine.get_physics_frames() else 1
		if int(_overlaps.get(key,0))>=refinements: continue
		_overlaps[key] = int(_overlaps.get(key,0))+1
		var points:PackedVector2Array = cs.shape.collide_and_get_contacts(cs.global_transform,other.collision_shape_2d.shape,other.collision_shape_2d.global_transform)
		var correction:Vector2 = Vector2.ZERO
		for i:int in range(0,points.size()-1,2):
			var offset:Vector2 = points[i+1]-points[i]
			if offset.length_squared()>correction.length_squared(): correction = offset
		if correction.length()<=POSITION_SLOP: continue
		correction = correction.normalized()*minf((correction.length()+POSITION_SLOP)*1.1,MAX_CORRECTION)
		var normal:Vector2 = correction.normalized()
		resolve_pair(other,normal)
		var ia:float = inverse_mass()
		var ib:float = b.inverse_mass()
		if ia+ib<=0.0: continue
		var first:Vector2 = _safe_shift(actor,correction*ia/(ia+ib),other) if ia>0.0 else Vector2.ZERO
		var second:Vector2 = _safe_shift(other,-(correction-first),actor) if ib>0.0 else Vector2.ZERO
		if ia>0.0: _safe_shift(actor,correction-first+second,other)
	_press_contacts()
func _physics_process(delta:float) -> void:
	if not live(): return
	advance(delta)
	if externally_driven(): return
	# Explicit skill movement remains owned by that skill; ordinary forces still compose.
	if _compose_frame != Engine.get_physics_frames() and impulse_velocity().length_squared()>0.01:
		_motion_frame = Engine.get_physics_frames()
		var incoming:Vector2 = actor.velocity+impulse_velocity()
		var contact:KinematicCollision2D = actor.move_and_collide(impulse_velocity()*delta)
		current_velocity = incoming
		if contact != null: resolve_contact(contact)
	separate_overlaps()
	_last_position = actor.global_position
