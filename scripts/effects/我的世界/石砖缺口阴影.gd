extends Node2D
const SHADER:Shader = preload("res://scripts/effects/我的世界/石砖缺口阴影.gdshader")
var mask_image:Image
var mask_texture:ImageTexture
var surface:Polygon2D
var grid_rect:Rect2i
func configure(rect:Rect2,used:Rect2i) -> void:
	grid_rect = used
	top_level = true
	global_position = rect.position
	z_as_relative = false
	z_index = -5 # 背景后、同层石砖渲染块前；不盖住血液、人物或震动中的砖。
	mask_image = Image.create(used.size.x,used.size.y,false,Image.FORMAT_R8)
	mask_image.fill(Color.WHITE)
	mask_texture = ImageTexture.create_from_image(mask_image)
	surface = Polygon2D.new()
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("occupancy",mask_texture)
	mat.set_shader_parameter("grid_size",Vector2(used.size))
	mat.set_shader_parameter("footprint_size",rect.size)
	surface.material = mat
	surface.polygon = PackedVector2Array([Vector2.ZERO,Vector2(rect.size.x,0),rect.size,Vector2(0,rect.size.y)])
	# 无基础纹理的Polygon2D需要显式提供归一化UV。
	surface.uv = PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN])
	add_child(surface)
func update_states(states:Dictionary) -> void:
	mask_image.fill(Color.WHITE)
	for key:Variant in states:
		if int(states[key]) == 2 and grid_rect.has_point(key):
			var p:Vector2i = key-grid_rect.position
			mask_image.set_pixel(p.x,p.y,Color.BLACK)
	mask_texture.update(mask_image)
