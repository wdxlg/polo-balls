extends Node2D
## Original Java beacon texture: vertically repeating white core and faint outer shell.
## The parent supplies simulation time; no wall-clock/TIME animation during pauses.
const TEXTURE = preload("res://Images/characters/我的世界/wither/beacon_beam.png")
const SHADER = preload("res://shaders/mc_beacon_beam.gdshader")
var length:float = 0.0
var phase:float = 0.0
var warning:bool = false
var beam_material:ShaderMaterial
func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	beam_material = ShaderMaterial.new()
	beam_material.shader = SHADER
	material = beam_material
func update_beam(distance:float,simulation_time:float,preparing:bool,firing:bool) -> void:
	length = distance
	phase = simulation_time
	warning = preparing
	visible = (preparing or firing) and length > 0.001
	beam_material.set_shader_parameter("scroll",fposmod(simulation_time*0.2,1.0))
	beam_material.set_shader_parameter("tiles",maxf(length/16.0,0.001))
	queue_redraw()
func _draw() -> void:
	if length <= 0.001: return
	# Project a rotating square core into the 2D arena, without rotating the ray.
	var core_width:float = 7.0*(absf(cos(phase*0.75))+absf(sin(phase*0.75)))
	draw_texture_rect(TEXTURE,Rect2(-7.0,-length,14.0,length),false,Color(1,1,1,0.07 if warning else 0.18))
	draw_texture_rect(TEXTURE,Rect2(-core_width*0.5,-length,core_width,length),false,Color(1,1,1,0.25 if warning else 1.0))
