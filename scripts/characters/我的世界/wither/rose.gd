extends Node2D
const ROSE_TEXTURE = preload("res://Images/characters/我的世界/wither/wither_rose.png")
const EFFECT_TEXTURE = preload("res://Images/characters/我的世界/wither/effect_0.png")
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
	var scale_factor:float = minf(age/0.5,1.0)
	draw_texture_rect(ROSE_TEXTURE,Rect2(-21*scale_factor,-21*scale_factor,42*scale_factor,42*scale_factor),false)
	draw_texture_rect(EFFECT_TEXTURE,Rect2(-23,-23,46,46),false,Color(0.23,0.17,0.29,0.22))
func get_ai_hazard_info() -> Dictionary:
	var source:Variant = source_ref.get_ref() if source_ref != null else null
	if age < 0.5 or not is_instance_valid(source) or source.health <= 0: return {}
	return {"shape":"circle","position":global_position,"radius":23.0,"damage":4.0,"danger_duration":3.0,"source":source,"kind":"wither_rose"}
