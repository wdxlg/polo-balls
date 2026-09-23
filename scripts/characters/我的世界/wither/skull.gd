extends Node2D
const HEAD = preload("res://Images/characters/我的世界/wither/wither_skull.png")
const SKULL_DIAMETER:float = 10.0
const HIT_RADIUS:float = 5.0
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
		source.call("_show_explosion",center,64.0)
		source.call("_emit_sound","explode",center)
		if source.multiplayer.has_multiplayer_peer(): source.call("_sync_skull_explosion",center)
		exploded = true
		remove_from_group("AI_Hazard")
		queue_free()
		return
	if not exploded: global_position = end
func _draw() -> void:
	if exploded: return
	draw_texture_rect(HEAD,Rect2(-SKULL_DIAMETER*0.5,-SKULL_DIAMETER*0.5,SKULL_DIAMETER,SKULL_DIAMETER),false)
func get_ai_hazard_info() -> Dictionary:
	var source:ball = _source()
	if exploded or source == null: return {}
	return {"shape":"circle","position":global_position,"velocity":heading*speed,"radius":HIT_RADIUS,"damage":75.0,"source":source,"danger_duration":0.1,"kind":"wither_skull"}
