extends Node2D
const NORMAL_TEXTURE = preload("res://Images/characters/我的世界/wither/poppy.png")
const WITHER_TEXTURE = preload("res://Images/characters/我的世界/wither/wither_rose.png")
const EFFECT_TEXTURE = preload("res://Images/characters/我的世界/wither/effect_0.png")
const ROSE_DIAMETER:float = 20.0
const TOUCH_RADIUS:float = 11.0
const ROSE_DAMAGE:float = 4.0
var source_ref:WeakRef
var age:float = 0.0
var life:float = 12.0
var withered:bool = false
var consumed:bool = false
func configure(source:ball) -> void:
	source_ref = weakref(source)
	add_to_group("WitherFlower")
	add_to_group("AI_Hazard")
func become_wither() -> void:
	if withered or consumed or is_queued_for_deletion(): return
	withered = true
	add_to_group("WitherRose")
	queue_redraw()
func _physics_process(delta:float) -> void:
	if consumed: return
	var source:ball = source_ref.get_ref() as ball if source_ref != null else null
	if source == null or source.health <= 0: queue_free(); return
	if not source.is_combat_runtime_active(): return
	age += delta
	if age >= life: queue_free(); return
	if age < 0.5 or not source.is_multiplayer_authority(): return
	for node:Node in SubmissionCharacterTools.targeting_candidates(source):
		if node is ball and source.mc_enemy(node) and ball.body_point(node,global_position).distance_to(global_position) <= TOUCH_RADIUS+(node as ball).get_crowd_separation_radius_world():
			# Either flower is a single-use trap. Only an explosion-converted
			# Wither rose adds the Wither status to its four-point contact hit.
			consumed = true
			source.impact(node as ball,ROSE_DAMAGE,global_position)
			if withered: source.apply_wither(node as ball)
			remove_from_group("AI_Hazard")
			remove_from_group("WitherFlower")
			remove_from_group("WitherRose")
			queue_free()
			break
func _process(_delta:float) -> void: queue_redraw()
func _draw() -> void:
	if consumed: return
	var scale_factor:float = minf(age/0.5,1.0)
	var texture:Texture2D = WITHER_TEXTURE if withered else NORMAL_TEXTURE
	draw_texture_rect(texture,Rect2(-ROSE_DIAMETER*scale_factor*0.5,-ROSE_DIAMETER*scale_factor*0.5,ROSE_DIAMETER*scale_factor,ROSE_DIAMETER*scale_factor),false)
	if withered:
		draw_texture_rect(EFFECT_TEXTURE,Rect2(-13,-13,26,26),false,Color(0.23,0.17,0.29,0.22))
func get_ai_hazard_info() -> Dictionary:
	var source:ball = source_ref.get_ref() as ball if source_ref != null else null
	if consumed or age < 0.5 or source == null or source.health <= 0: return {}
	return {"shape":"circle","position":global_position,"radius":TOUCH_RADIUS,"damage":ROSE_DAMAGE,"danger_duration":0.1,"source":source,"kind":"wither_rose" if withered else "ordinary_rose"}
