extends Node2D
const SHADER:Shader = preload("res://scripts/effects/我的世界/地图外沿阴影.gdshader")
var footprint:Rect2
var footprints:Array[Rect2] = []
var spread:Vector2
var surface:Polygon2D
var cutouts:Array[Rect2] = []
var island_cutouts:Array = []

func configure(rect:Rect2,margin:Vector2,alpha:float = 0.36,cuts:Array[Rect2] = []) -> void:
	configure_union([rect],margin,[cuts],alpha)

func configure_union(rects:Array[Rect2],margin:Vector2,cuts_by_island:Array,alpha:float = 0.36) -> void:
	footprints = rects.duplicate()
	island_cutouts = cuts_by_island.duplicate(true)
	cutouts.clear()
	if rects.is_empty():
		visible = false
		return
	visible = true
	footprint = rects[0]
	for rect:Rect2 in rects: footprint = footprint.merge(rect)
	spread = margin.max(Vector2(0.01,0.01))
	top_level = true
	global_position = footprint.position
	z_as_relative = false
	z_index = -4
	if not is_instance_valid(surface):
		surface = Polygon2D.new()
		surface.name = "SoftOutsideShadow"
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		surface.material = mat
		add_child(surface)
	var shape_data:Image = Image.create(rects.size(),2,false,Image.FORMAT_RGBAF)
	for i:int in range(rects.size()):
		var rect:Rect2 = rects[i]
		var cuts:Array = cuts_by_island[i] if i < cuts_by_island.size() else []
		shape_data.set_pixel(i,0,Color(rect.position.x-footprint.position.x,rect.position.y-footprint.position.y,rect.size.x,rect.size.y))
		shape_data.set_pixel(i,1,Color(cutouts.size(),cuts.size(),0,0))
		for cut:Rect2 in cuts: cutouts.append(cut)
	var data:Image = Image.create(maxi(cutouts.size(),1),1,false,Image.FORMAT_RGBAF)
	for i:int in range(cutouts.size()):
		var cut:Rect2 = cutouts[i]
		data.set_pixel(i,0,Color(cut.position.x-footprint.position.x,cut.position.y-footprint.position.y,cut.size.x,cut.size.y))
	var size:Vector2 = footprint.size
	surface.polygon = PackedVector2Array([-spread,Vector2(size.x+spread.x,-spread.y),size+spread,Vector2(-spread.x,size.y+spread.y)])
	surface.material.set_shader_parameter("spread_size",spread)
	surface.material.set_shader_parameter("opacity",alpha)
	surface.material.set_shader_parameter("islands",ImageTexture.create_from_image(shape_data))
	surface.material.set_shader_parameter("island_count",rects.size())
	surface.material.set_shader_parameter("cutouts",ImageTexture.create_from_image(data))
	surface.material.set_shader_parameter("cutout_count",cutouts.size())

static func _box_distance(point:Vector2,rect:Rect2,scale:Vector2) -> float:
	var q:Vector2 = (point-rect.get_center()).abs()/scale-rect.size/scale*0.5
	return q.max(Vector2.ZERO).length()+minf(maxf(q.x,q.y),0.0)

func distance_to_union(point:Vector2) -> float:
	# 与着色器相同的 CPU 参考，用于连接处回归；不在逐帧渲染中执行。
	var distance:float = INF
	for i:int in range(footprints.size()):
		var d:float = _box_distance(point,footprints[i],spread)
		if i < island_cutouts.size():
			for cut:Rect2 in island_cutouts[i]: d = maxf(d,-_box_distance(point,cut,spread))
		distance = minf(distance,d)
	return distance
