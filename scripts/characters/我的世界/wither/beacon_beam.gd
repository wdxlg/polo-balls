extends Node2D
## Vanilla beam texture with a shared gameplay envelope; glow is cosmetic, core is damage.
const TEXTURE = preload("res://Images/characters/我的世界/wither/beacon_beam.png")
const SHADER = preload("res://shaders/mc_beacon_beam.gdshader")
var length:float=0.0
var phase:float=0.0
var warning:bool=false
var core_width:float=0.0
var alpha:float=0.0
var beam_material:ShaderMaterial
func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	beam_material=ShaderMaterial.new()
	beam_material.shader=SHADER
	material=beam_material
func update_beam(distance:float,simulation_time:float,width:float,opacity:float,preparing:bool,firing:bool) -> void:
	length=distance
	phase=simulation_time
	warning=preparing
	core_width=width
	alpha=opacity
	visible=(preparing or firing) and length>0.001 and core_width>0.0001 and alpha>0.0001
	beam_material.set_shader_parameter("scroll",fposmod(simulation_time*0.2,1.0))
	beam_material.set_shader_parameter("tiles",maxf(length/16.0,0.001))
	queue_redraw()
func _draw() -> void:
	if length<=0.001 or core_width<=0.0001: return
	# Several faint falloff bands give a thin charge ray a readable glow.
	# Halo does not inflict damage; the bright textured rectangle is the real beam.
	for i:int in range(3,0,-1):
		var glow_width:float=core_width+float(i)*(0.75 if warning else 0.65)
		draw_texture_rect(TEXTURE,Rect2(-glow_width*0.5,-length,glow_width,length),false,Color(0.85,1.12,1.2,alpha*0.055))
	draw_texture_rect(TEXTURE,Rect2(-core_width*0.5,-length,core_width,length),false,Color(1.1,1.15,1.2,alpha))
