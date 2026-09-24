extends Node
var target:ball
var source:Node2D
var duration:float=0.65
var elapsed:float=0.0
var acquired:bool=false
var saved_layer:int=0
var saved_mask:int=0
var saved_escape:Variant=null
var had_escape:bool=false
var capture_point:Vector2
func _ready() -> void:
	if not is_instance_valid(target) or not is_instance_valid(source) or not target.can_receive_negative_effects() or not target.can_receive_control_from(source):
		queue_free()
		return
	process_physics_priority=maxi(target.process_physics_priority,source.process_physics_priority)+150
	var count:int=int(target.get_meta("generic_motion_lock_count",0))
	if count==0: target.set_meta("generic_motion_lock_baseline",target.dizziness)
	target.set_meta("generic_motion_lock_count",count+1)
	target.set_meta("mc_sticky_hold",get_instance_id())
	saved_layer=target.collision_layer
	saved_mask=target.collision_mask
	capture_point=target.global_position
	had_escape=target.has_meta("submission_allow_map_escape")
	saved_escape=target.get_meta("submission_allow_map_escape",false)
	target.set_meta("submission_allow_map_escape",true)
	# Body collision only. Hurt areas remain enabled so attacks can still hit.
	target.collision_layer=0
	target.collision_mask=0
	target.dizziness=true
	target.begin_stun_visual()
	acquired=true
func _physics_process(delta:float) -> void:
	if not acquired or not is_instance_valid(target) or not is_instance_valid(source) or target.health<=0 or source.health<=0:
		queue_free()
		return
	# 活塞在黏附期间上船时也要解除，避免“船跟随活塞、活塞跟随座位”的循环位移。
	if not target.can_receive_control_from(source):
		queue_free()
		return
	if not target.is_combat_runtime_active(): return
	elapsed+=delta
	if elapsed>=duration:
		queue_free()
		return
	target.collision_layer=0
	target.collision_mask=0
	target.Repel=Vector2.ZERO
	target.velocity=Vector2.ZERO
	target.global_position=source.sticky_anchor(target)
func clear_at(point:Vector2) -> bool:
	var shape:CollisionShape2D=target.get_node_or_null("CollisionShape2D")
	if shape==null or shape.shape==null: return true
	var query:=PhysicsShapeQueryParameters2D.new()
	query.shape=shape.shape
	query.transform=shape.global_transform
	query.transform.origin+=point-target.global_position
	query.collision_mask=saved_mask
	query.exclude=[target.get_rid()]
	query.collide_with_areas=false
	return target.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty()
func safe_release() -> void:
	if clear_at(target.global_position): return
	var origin:Vector2=target.global_position
	for radius:float in [8.0,16.0,24.0,40.0,64.0,96.0]:
		for index:int in range(16):
			var point:Vector2=origin+Vector2.RIGHT.rotated(float(index)*TAU/16)*radius
			if clear_at(point): target.global_position=point; return
	if clear_at(capture_point): target.global_position=capture_point
func _exit_tree() -> void:
	if not acquired or not is_instance_valid(target): return
	acquired=false
	target.end_stun_visual()
	if int(target.get_meta("mc_sticky_hold",0))==get_instance_id():
		target.remove_meta("mc_sticky_hold")
		if target.health>0:
			safe_release()
			target.collision_layer=saved_layer
			target.collision_mask=saved_mask
		if had_escape: target.set_meta("submission_allow_map_escape",saved_escape)
		else: target.remove_meta("submission_allow_map_escape")
	var count:int=maxi(0,int(target.get_meta("generic_motion_lock_count",1))-1)
	if count>0: target.set_meta("generic_motion_lock_count",count)
	else:
		target.dizziness=bool(target.get_meta("generic_motion_lock_baseline",false))
		target.remove_meta("generic_motion_lock_count")
		target.remove_meta("generic_motion_lock_baseline")
