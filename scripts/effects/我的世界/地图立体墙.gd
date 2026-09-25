extends Node2D
# 地图边界的纯视觉 2.5D 外壳。数据直接复用 World 已扣除门洞的地面暴露边；
# 墙顶仍使用现有各主题的一格原版方块贴图，只有蓝色地图需要补画墙顶。
# 本节点不生成碰撞体，也不改变地图的可行走范围。

const OUTWARD_NORMALS:Array[Vector2] = [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]

var wall_edges:Array[Dictionary] = []
var cell_size:Vector2 = Vector2(16.0,16.0)
var light_source:Vector2 = Vector2(1.0,-1.0).normalized()
var face_offset:Vector2 = Vector2(-6.5,6.5)
var tiled:bool = false
var wall_texture:Texture2D
var wall_tint:Color = Color.WHITE


func configure_edges(edges:Array[Dictionary],cell:Vector2,theme:Dictionary,source_direction:Vector2,height_cells:float) -> void:
	wall_edges = edges.duplicate(true)
	cell_size = cell.max(Vector2(0.01,0.01))
	light_source = source_direction.normalized() if source_direction.length_squared() > 0.0001 else Vector2(1.0,-1.0).normalized()
	face_offset = -light_source * minf(cell_size.x,cell_size.y) * clampf(height_cells,0.1,1.5)
	tiled = bool(theme.get("tiled",false))
	wall_texture = theme.get("wall",null) as Texture2D if tiled else null
	wall_tint = theme.get("wall_modulate",Color.WHITE) as Color
	top_level = true
	global_position = Vector2.ZERO
	z_as_relative = false
	# 在地图外遮罩(90)之后、原黑色边线和门扇(100)之前绘制；墙面自然挡住靠墙人物。
	z_index = 99
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	queue_redraw()


func _draw() -> void:
	if wall_edges.is_empty(): return
	# 先画全部墙顶，再画墙身，最后用一条薄的内缘统一封口，避免转角出现裂缝。
	if not tiled:
		for edge:Dictionary in wall_edges: _draw_blue_top(edge)
	for edge:Dictionary in wall_edges: _draw_wall_face(edge)
	for edge:Dictionary in wall_edges: _draw_inner_lip(edge)


func _endpoints(edge:Dictionary) -> PackedVector2Array:
	return PackedVector2Array([MapTileGeometry.point(edge,float(edge.a)),MapTileGeometry.point(edge,float(edge.b))])


func _draw_blue_top(edge:Dictionary) -> void:
	var ends:PackedVector2Array = _endpoints(edge)
	var outward:Vector2 = OUTWARD_NORMALS[int(edge.side)]
	var width:float = minf(cell_size.x,cell_size.y) * 0.72
	var light:float = clampf(0.79+outward.dot(light_source)*0.19,0.60,0.98)
	var cap:Color = Color(0.075,0.31,0.50) * light
	cap.a = 1.0
	draw_colored_polygon(PackedVector2Array([ends[0],ends[1],ends[1]+outward*width,ends[0]+outward*width]),cap)
	var glint:Color = Color(0.34,0.75,0.97,0.47 if outward.dot(light_source)>0.0 else 0.18)
	draw_line(ends[0]+outward*(width-1.0),ends[1]+outward*(width-1.0),glint,1.0,true)


func _draw_wall_face(edge:Dictionary) -> void:
	var ends:PackedVector2Array = _endpoints(edge)
	var points:PackedVector2Array = PackedVector2Array([ends[0],ends[1],ends[1]+face_offset,ends[0]+face_offset])
	var outward:Vector2 = OUTWARD_NORMALS[int(edge.side)]
	# 光来自右上：面向地图、背离光源的北墙和东墙有较深的侧面。
	var lit:float = clampf(0.70-outward.dot(light_source)*0.21,0.48,0.88)
	if tiled and wall_texture != null:
		var top_color:Color = Color(lit,lit,lit,1.0) * wall_tint
		var base_color:Color = Color(lit*0.58,lit*0.58,lit*0.58,1.0) * wall_tint
		var length_cell:float = cell_size.y if int(edge.side)<2 else cell_size.x
		var u0:float = float(edge.a)/length_cell*float(wall_texture.get_width())
		var u1:float = float(edge.b)/length_cell*float(wall_texture.get_width())
		var uv:PackedVector2Array = PackedVector2Array([Vector2(u0,0),Vector2(u1,0),Vector2(u1,wall_texture.get_height()),Vector2(u0,wall_texture.get_height())])
		draw_polygon(points,PackedColorArray([top_color,top_color,base_color,base_color]),uv,wall_texture)
	else:
		var top:Color = Color(0.11,0.40,0.62).darkened(1.0-lit)
		var base:Color = Color(0.025,0.105,0.20).darkened(1.0-lit)
		draw_polygon(points,PackedColorArray([top,top,base,base]))
	var lower:Color = Color(0.0,0.0,0.0,0.40)
	draw_line(ends[0]+face_offset,ends[1]+face_offset,lower,1.0,true)


func _draw_inner_lip(edge:Dictionary) -> void:
	var ends:PackedVector2Array = _endpoints(edge)
	var outward:Vector2 = OUTWARD_NORMALS[int(edge.side)]
	var rim:Color = Color(0.02,0.035,0.055,0.80 if tiled else 0.45)
	draw_line(ends[0],ends[1],rim,1.2,true)
	if tiled:
		# 墙顶仍露出原材质，只在靠光的一侧补很窄的高光；不盖住原像素纹理。
		var strength:float = 0.17 if outward.dot(light_source)>0.0 else 0.06
		draw_line(ends[0]+outward*1.4,ends[1]+outward*1.4,Color(1,1,1,strength),0.9,true)
