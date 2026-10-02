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
var _initialized:bool = false
var _advance_frame:int = -1
var _compose_frame:int = -1
var _direct_frame:int = -1
var _correction_frame:int = -1
var _correction_used:float = 0.0
var _last_position:Vector2
static var _pair_frame:int = -1
static var _pairs:Dictionary = {}
static var _overlaps:Dictionary = {}

func _ready() -> void:
	process_physics_priority = 1000
	_last_position = actor.global_position
func live() -> bool:
	return is_instance_valid(actor) and actor.is_inside_tree() and actor.is_multiplayer_authority() and actor.health > 0 and actor.is_combat_runtime_active() and not get_tree().paused
func inverse_mass() -> float:
	if bool(actor.get_meta("body_motion_immovable",false)): return 0.0
	if actor.has_method("is_knockback_displacement_immune") and actor.is_knockback_displacement_immune(): return 0.0
	return 1.0
func physical_body() -> bool:
	return actor.collision_shape_2d != null and actor.collision_shape_2d.shape != null and not actor.collision_shape_2d.disabled and (actor.collision_layer & 2)!=0 and (actor.collision_mask & 2)!=0
func externally_driven() -> bool:
	return actor.has_meta("map_rescue_animating") or actor.has_meta("airborne_height") or bool(actor.get_meta("mc_ignore_character_body_collision",false))
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
	if not live(): return Vector2.ZERO
	advance(delta)
	if not _initialized:
		motor = desired
		_initialized = true
	elif actor.dizziness:
		motor = Vector2.ZERO
	else:
		var acceleration:float = maxf(maxf(desired.length(),actor.Speed*0.6),40.0)*16.0
		motor = motor.move_toward(desired,acceleration*maxf(delta,0.0))
	_compose_frame = Engine.get_physics_frames()
	current_velocity = motor+other+impulse_velocity()
	return current_velocity
func compose_direct(value:Vector2,delta:float) -> Vector2:
	if not live(): return Vector2.ZERO
	advance(delta)
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
	if other.has_method("get_body_motion"):
		resolve_pair(other,normal)
		return
	if actor._is_external_gravity_quiet_support_collision(collision): return
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
	if EXCLUSIONS.are_excluded(actor,other) or actor.get_collision_exceptions().has(other): return
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
func _safe_shift(unit:Node,offset:Vector2,partner:Node) -> Vector2:
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
	query.collision_mask = 3
	var ignored:Array[RID] = [unit.get_rid(),partner.get_rid()]
	for exception:PhysicsBody2D in unit.get_collision_exceptions():
		if is_instance_valid(exception): ignored.append(exception.get_rid())
	query.exclude = ignored
	var space:PhysicsDirectSpaceState2D = unit.get_world_2d().direct_space_state
	var cast:PackedFloat32Array = space.cast_motion(query)
	var move:Vector2 = offset*(cast[0] if not cast.is_empty() else 0.0)
	query.motion = Vector2.ZERO
	query.collision_mask = 1
	query.transform.origin += move
	if not space.intersect_shape(query,1).is_empty(): return Vector2.ZERO
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
	query.exclude = [actor.get_rid()]
	_begin_frame()
	for hit:Dictionary in actor.get_world_2d().direct_space_state.intersect_shape(query,24):
		var other:Node = hit.collider as Node
		if not is_instance_valid(other) or not other.has_method("get_body_motion") or not other.is_multiplayer_authority(): continue
		if EXCLUSIONS.are_excluded(actor,other) or actor.get_collision_exceptions().has(other): continue
		var b:Node = other.get_body_motion()
		if b == null or not b.live() or not b.physical_body() or b.externally_driven(): continue
		var key:String = _pair_key(actor,other)
		if _overlaps.has(key): continue
		_overlaps[key] = true
		var points:PackedVector2Array = cs.shape.collide_and_get_contacts(cs.global_transform,other.collision_shape_2d.shape,other.collision_shape_2d.global_transform)
		var correction:Vector2 = Vector2.ZERO
		for i:int in range(0,points.size()-1,2):
			var offset:Vector2 = points[i+1]-points[i]
			if offset.length_squared()>correction.length_squared(): correction = offset
		if correction.length()<=POSITION_SLOP: continue
		correction = correction.limit_length(MAX_CORRECTION)
		var normal:Vector2 = correction.normalized()
		resolve_pair(other,normal)
		var ia:float = inverse_mass()
		var ib:float = b.inverse_mass()
		if ia+ib<=0.0: continue
		var first:Vector2 = _safe_shift(actor,correction*ia/(ia+ib),other) if ia>0.0 else Vector2.ZERO
		var second:Vector2 = _safe_shift(other,-(correction-first),actor) if ib>0.0 else Vector2.ZERO
		if ia>0.0: _safe_shift(actor,correction-first+second,other)
func _physics_process(delta:float) -> void:
	if not live() or externally_driven(): return
	advance(delta)
	# Explicit skill movement remains owned by that skill; ordinary forces still compose.
	if _compose_frame != Engine.get_physics_frames() and impulse_velocity().length_squared()>0.01:
		var incoming:Vector2 = actor.velocity+impulse_velocity()
		var contact:KinematicCollision2D = actor.move_and_collide(impulse_velocity()*delta)
		current_velocity = incoming
		if contact != null: resolve_contact(contact)
	separate_overlaps()
	_last_position = actor.global_position
