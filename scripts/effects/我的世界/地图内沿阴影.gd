extends Node2D
# 单次距离场合成：四角不叠黑，门洞端点按距离柔和收尾。
const SHADER:Shader = preload("res://scripts/effects/我的世界/地图内沿阴影.gdshader")
var surface:Polygon2D

func configure(rect:Rect2,spread:Vector2,wall_spans:Array) -> void:
	top_level = true
	global_position = rect.position
	z_as_relative = false
	z_index = -4
	if not is_instance_valid(surface):
		surface = Polygon2D.new()
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		surface.material = mat
		add_child(surface)
	var segments:Array[Color] = []
	for side:int in range(4):
		for span:Vector2 in wall_spans[side]:
			if span.y <= span.x: continue
			if side < 2:
				var x:float = 0.0 if side == 0 else rect.size.x
				segments.append(Color(x,span.x-rect.position.y,x,span.y-rect.position.y))
			else:
				var y:float = 0.0 if side == 2 else rect.size.y
				segments.append(Color(span.x-rect.position.x,y,span.y-rect.position.x,y))
	surface.visible = not segments.is_empty() and rect.size.x > 0.0 and rect.size.y > 0.0
	if not surface.visible: return
	# 浮点纹理携带任意数量的墙段，不依赖UV像素单位，也不限制门洞数。
	var data:Image = Image.create(segments.size(),1,false,Image.FORMAT_RGBAF)
	for i:int in range(segments.size()): data.set_pixel(i,0,segments[i])
	surface.polygon = PackedVector2Array([Vector2.ZERO,Vector2(rect.size.x,0),rect.size,Vector2(0,rect.size.y)])
	surface.material.set_shader_parameter("segments",ImageTexture.create_from_image(data))
	surface.material.set_shader_parameter("segment_count",segments.size())
	surface.material.set_shader_parameter("footprint_size",rect.size)
	surface.material.set_shader_parameter("spread_size",spread.max(Vector2(0.01,0.01)))
	# 保持旧矩形接口的四向柔和内沿，兼容已有纯视觉采样夹具。
	surface.material.set_shader_parameter("directional_enabled",false)
	surface.material.set_shader_parameter("opacity",0.36)

func configure_regions(regions:Array[Rect2],spread:Vector2,edges:Array[Dictionary],cast_vector:Vector2 = Vector2(-24.0,24.0)) -> void:
	top_level = true
	global_position = Vector2.ZERO
	z_as_relative = false
	z_index = -4
	if not is_instance_valid(surface):
		surface = Polygon2D.new()
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		surface.material = mat
		add_child(surface)
	surface.visible = not regions.is_empty() and not edges.is_empty()
	if not surface.visible: return
	var vertices:PackedVector2Array = PackedVector2Array()
	var polygons:Array[PackedInt32Array] = []
	for rect:Rect2 in regions:
		var k:int = vertices.size()
		vertices.append_array(PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]))
		polygons.append(PackedInt32Array([k,k+1,k+2,k+3]))
	surface.polygon = vertices
	surface.polygons = polygons
	var image:Image = Image.create(edges.size(),1,false,Image.FORMAT_RGBAF)
	for i:int in range(edges.size()):
		var edge:Dictionary = edges[i]
		var a:Vector2 = MapTileGeometry.point(edge,edge.a)
		var b:Vector2 = MapTileGeometry.point(edge,edge.b)
		image.set_pixel(i,0,Color(a.x,a.y,b.x,b.y))
	surface.material.set_shader_parameter("segments",ImageTexture.create_from_image(image))
	surface.material.set_shader_parameter("segment_count",edges.size())
	surface.material.set_shader_parameter("spread_size",spread.max(Vector2(0.01,0.01)))
	surface.material.set_shader_parameter("directional_enabled",true)
	surface.material.set_shader_parameter("shadow_vector",cast_vector)
	surface.material.set_shader_parameter("opacity",0.44)
