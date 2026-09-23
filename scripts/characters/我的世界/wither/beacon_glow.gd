extends Node2D
## Additive beam bloom and source-core light. Purely cosmetic; no hazard/physics.
const EMITTER=preload("res://scripts/characters/我的世界/wither/beacon_emitter.gd")
const GLOW_SHADER=preload("res://shaders/mc_beacon_glow.gdshader")
var on_core:bool=false
var width:float=0.0
var length:float=0.0
var strength:float=0.0
var body_width:float=0.0
func _ready() -> void:
	if on_core:
		var mat:=CanvasItemMaterial.new()
		mat.blend_mode=CanvasItemMaterial.BLEND_MODE_ADD
		mat.light_mode=CanvasItemMaterial.LIGHT_MODE_UNSHADED
		material=mat
	else:
		var mat:=ShaderMaterial.new()
		mat.shader=GLOW_SHADER
		material=mat
	visible=false
func update_glow(new_width:float,new_length:float,opacity:float,new_body_width:float=0.0) -> void:
	width=new_width
	length=new_length
	strength=opacity
	body_width=new_body_width
	visible=strength>0.0001 and width>0.0001
	if not on_core:
		material.set_shader_parameter("width",width)
		material.set_shader_parameter("length",length)
		material.set_shader_parameter("source_y",-width*EMITTER.PLANE_RATIO*.5)
		material.set_shader_parameter("strength",strength)
	queue_redraw()
func _draw() -> void:
	if not visible: return
	if not on_core:
		draw_rect(Rect2(-width*2.2,-length,width*4.4,length+width),Color.WHITE)
		return
	# Light only the actual inner model faces. No glow-painted glass or base.
	var top:PackedVector2Array=EMITTER.core_top(body_width)
	draw_colored_polygon(top,Color(.32,.8,1.0,strength*.43))
	for i:int in [1,2]:
		var a:Vector2=top[i]
		var b:Vector2=top[(i+1)%4]
		var vertical:Vector2=EMITTER.project(Vector3(8,3,8),body_width)-EMITTER.core_center(body_width)
		draw_colored_polygon(PackedVector2Array([a,b,b+vertical,a+vertical]),Color(.1,.48,.72,strength*.32))
