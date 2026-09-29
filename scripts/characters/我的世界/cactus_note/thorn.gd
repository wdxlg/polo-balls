extends "res://scripts/effects/我的世界/骷髅箭.gd"
var fixed_retaliation_damage:bool = false
var flight_left:float = 2.0
var stuck:bool = false
var decorative_left:float = 3.0
func _ready() -> void:
	super._ready()
	remove_from_group("MinecraftSkeletonArrow")
	add_to_group("MCCactusThorn")
func _physics_process(delta:float) -> void:
	if Game.now_stop_state or get_tree().paused: return
	if stuck:
		decorative_left -= delta
		if decorative_left <= 0: queue_free()
		return
	if not _configured: return
	flight_left -= delta
	if flight_left <= 0:
		queue_free()
		return
	var start:Vector2 = global_position
	var finish:Vector2 = start+_direction*_speed*delta
	var hit:Dictionary = _raycast_motion(start,finish)
	if hit.is_empty():
		global_position = finish
		return
	global_position = hit.get("position",finish)
	var collider:Variant = hit.get("collider")
	if _is_blaze_rod(collider):
		queue_free()
		return
	var target:ball = _resolve_ball_from_collider(collider)
	if target != null and _can_damage_target(target):
		_capture_embed_anchor(target)
		if is_multiplayer_authority(): _apply_damage(target,_direct_damage)
		var anchor:Node2D = _resolve_embed_parent(target)
		if is_instance_valid(anchor):
			call_deferred("attach_visual",anchor.get_instance_id(),_embed_local_pose)
	else:
		if collider is Node2D:
			call_deferred("attach_visual",collider.get_instance_id(),collider.global_transform.affine_inverse()*global_transform)
	stuck = true
	_mode = ArrowMode.STUCK_TERRAIN
	_configured = false
	# No pickup sensor, wound controller, execution threshold or damage-over-time.
	_sensor_shape.set_deferred("disabled",true)
func attach_visual(id:int,pose:Transform2D) -> void:
	var anchor:Object = instance_from_id(id)
	if not is_instance_valid(anchor) or not anchor is Node2D or not anchor.is_inside_tree(): return
	reparent(anchor,false)
	transform = pose

func _apply_damage(target:ball,amount:float) -> void:
	if not fixed_retaliation_damage:
		super._apply_damage(target,amount)
		return
	# Fixed outgoing 5, independent of cactus Damage/ordinary-shot multipliers.
	if is_instance_valid(target) and target.receive_positional_damage(5.0,global_position,false,_source_ball()):
		pass # Victim-owned feedback also covers fixed retaliation damage.
