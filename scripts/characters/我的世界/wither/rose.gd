extends Node2D
var source_ref:WeakRef
var age:float = 0.0
var life:float = 12.0
func configure(source:ball) -> void:
	source_ref = weakref(source)
	add_to_group("WitherRose")
	add_to_group("AI_Hazard")
func _physics_process(delta:float) -> void:
	var source:Variant = source_ref.get_ref() if source_ref != null else null
	if not is_instance_valid(source) or source.health <= 0: queue_free(); return
	if not source.is_combat_runtime_active(): return
	age += delta
	if age >= life: queue_free(); return
	if age < 0.5 or not source.is_multiplayer_authority(): return
	for node:Node in SubmissionCharacterTools.targeting_candidates(source):
		if node is ball and source.mc_enemy(node) and node.global_position.distance_to(global_position) <= 23.0+(node as ball).get_crowd_separation_radius_world():
			source.apply_wither(node as ball)
func _process(_delta:float) -> void: queue_redraw()
func _draw() -> void:
	draw_circle(Vector2.ZERO,23.0,Color(0.31,0.10,0.31,0.16))
	var scale_factor:float = minf(age/0.5,1.0)
	draw_line(Vector2(0,10)*scale_factor,Vector2(0,-9)*scale_factor,Color("424a37"),4.0)
	for i:int in range(5):
		var p:Vector2 = Vector2(0,-10)+Vector2.RIGHT.rotated(float(i)*TAU/5.0)*9.0
		draw_circle(p*scale_factor,6.0*scale_factor,Color("462331"))
	draw_circle(Vector2(0,-10)*scale_factor,4.0*scale_factor,Color("17191b"))
func get_ai_hazard_info() -> Dictionary:
	var source:Variant = source_ref.get_ref() if source_ref != null else null
	if age < 0.5 or not is_instance_valid(source) or source.health <= 0: return {}
	return {"shape":"circle","position":global_position,"radius":23.0,"damage":4.0,"danger_duration":3.0,"source":source,"kind":"wither_rose"}
