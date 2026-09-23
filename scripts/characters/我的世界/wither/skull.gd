extends Node2D
## Sweep the path each physics frame, explode on the first target or solid wall.
var source_ref:WeakRef
var heading:Vector2 = Vector2.RIGHT
var speed:float = 260.0
var life:float = 4.0
var exploded:bool = false
func configure(source:ball,direction:Vector2) -> void:
	source_ref = weakref(source)
	heading = direction.normalized()
	rotation = heading.angle()
	add_to_group("AI_Hazard")
func _source() -> ball:
	var node:Variant = source_ref.get_ref() if source_ref != null else null
	return node as ball if is_instance_valid(node) and node is ball and node.health > 0 else null
func _physics_process(delta:float) -> void:
	if exploded: return # Impact is resolved exactly once; keep only the short visual.
	var source:ball = _source()
	if source == null: queue_free(); return
	if not source.is_multiplayer_authority() or not source.is_combat_runtime_active(): return
	life -= delta
	if life <= 0: queue_free(); return
	var start:Vector2 = global_position
	var end:Vector2 = start+heading*speed*delta
	var excluded:Array[RID] = [source.get_rid()]
	for n:int in range(12):
		var query:=PhysicsRayQueryParameters2D.create(start,end,3,excluded)
		var hit:Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
		if hit.is_empty(): break
		var collider:Variant = hit.get("collider")
		if collider is ball and not source.call("mc_enemy",collider):
			excluded.append((collider as ball).get_rid())
			continue
		var direct:ball = collider as ball if collider is ball else null
		var center:Vector2 = Vector2(hit.position)-heading*3.0
		source.call("_blast",center,64.0,45.0,direct,true)
		global_position = center
		exploded = true
		remove_from_group("AI_Hazard")
		queue_redraw()
		get_tree().create_timer(0.16).timeout.connect(queue_free)
		return
	if not exploded: global_position = end
func _draw() -> void:
	if exploded:
		draw_circle(Vector2.ZERO,64.0,Color(0.14,0.11,0.18,0.32))
		draw_arc(Vector2.ZERO,64.0,0,TAU,28,Color(0.62,0.43,0.73,0.9),3.0)
		return
	draw_circle(Vector2.ZERO,15.0,Color("313238"))
	draw_rect(Rect2(-9,-4,5,5),Color.BLACK)
	draw_rect(Rect2(4,-4,5,5),Color.BLACK)
	draw_rect(Rect2(-5,6,10,3),Color("161518"))
	draw_circle(Vector2(-23,0),7.0,Color(0.14,0.09,0.19,0.55))
func get_ai_hazard_info() -> Dictionary:
	var source:ball = _source()
	if exploded or source == null: return {}
	return {"shape":"circle","position":global_position,"velocity":heading*speed,"radius":15.0,"damage":75.0,"source":source,"danger_duration":0.1,"kind":"wither_skull"}
