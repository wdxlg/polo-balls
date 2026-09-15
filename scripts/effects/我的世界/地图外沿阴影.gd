extends Node2D
const SHADER:Shader = preload("res://scripts/effects/我的世界/地图外沿阴影.gdshader")
var footprint:Rect2
var spread:Vector2
var surface:Polygon2D
func configure(rect:Rect2,margin:Vector2,alpha:float = 0.36) -> void:
	footprint = rect
	spread = margin.max(Vector2(0.01,0.01))
	top_level = true
	global_position = rect.position
	z_as_relative = false
	# 背景与石砖为-5，地图外网格为-4；阴影在网格之后，且只画未覆盖的外圈。
	z_index = -4
	if not is_instance_valid(surface):
		surface = Polygon2D.new()
		surface.name = "SoftOutsideShadow"
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		surface.material = mat
		add_child(surface)
	surface.polygon = PackedVector2Array([-spread,Vector2(rect.size.x+spread.x,-spread.y),rect.size+spread,Vector2(-spread.x,rect.size.y+spread.y)])
	surface.material.set_shader_parameter("footprint_size",rect.size)
	surface.material.set_shader_parameter("spread_size",spread)
	surface.material.set_shader_parameter("opacity",alpha)
