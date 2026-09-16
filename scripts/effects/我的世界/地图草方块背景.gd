extends Node2D
# 纯视觉重复贴图：内部草地 + 一圈木墙，用少量 Sprite 覆盖任意大小地图。
# 木墙按 wall_spans 拆分（每边若干段），传送门缺口处就不画墙，缺口真的“空”出来。
# wall_spans 为空时沿用老行为：四条边各画整条墙。
const GRASS:Texture2D = preload("res://Images/effects/我的世界/草方块背景/grass_block_top.png")
const LOG:Texture2D = preload("res://Images/effects/我的世界/草方块背景/oak_log_top.png")
const TEXTURE_CELL:Vector2 = Vector2(16,16)

var parts:Array[Sprite2D] = []      # parts[0] 是内部草地，其余是木墙段
var interior_rect:Rect2
var visual_rect:Rect2
var cell_size:Vector2


func configure(rect:Rect2,cell:Vector2,enabled:bool,wall_spans:Array = []) -> void:
	visible = enabled
	if not enabled:
		return
	interior_rect = rect
	cell_size = cell
	visual_rect = Rect2(rect.position-cell,rect.size+cell*2.0)
	_ensure_part(0,GRASS,Color("91bd59"))
	_apply_part(parts[0],rect)
	var spans:Array = wall_spans if not wall_spans.is_empty() else _full_wall_spans()
	var wanted:Array[Rect2] = []
	for side:int in range(4):
		for span:Vector2 in spans[side]:
			if span.y - span.x <= 0.01:
				continue
			wanted.append(_wall_rect(side,span.x,span.y))
	# 同一段墙复用同一个 Sprite：地图反复刷新时不会一直新建节点。
	var used:Array[bool] = []
	used.resize(parts.size())
	used.fill(false)
	if not used.is_empty():
		used[0] = true
	for wall_rect:Rect2 in wanted:
		var index:int = -1
		for i:int in range(1,parts.size()):
			if used[i] or not parts[i].has_meta(&"wall_rect"):
				continue
			if (parts[i].get_meta(&"wall_rect") as Rect2).is_equal_approx(wall_rect):
				index = i
				break
		if index < 0:
			# 没有尺寸完全一致的旧墙段时复用第一个空闲段：切换地图大小时节点不会越积越多。
			for i:int in range(1,parts.size()):
				if not used[i]:
					index = i
					break
		if index < 0:
			index = parts.size()
			_ensure_part(index,LOG,Color.WHITE)
		if used.size() < parts.size():
			used.resize(parts.size())
		used[index] = true
		parts[index].set_meta(&"wall_rect",wall_rect)
		_apply_part(parts[index],wall_rect)
	for i:int in range(1,parts.size()):
		parts[i].visible = used[i]


func visible_wall_rects() -> Array[Rect2]:
	# 当前真正显示出来的木墙段（世界坐标）：被传送门缺口减掉的墙不会出现在这里。
	var result:Array[Rect2] = []
	for i:int in range(parts.size()):
		if parts[i].visible and parts[i].get_meta("is_wall",i > 0):
			result.append(parts[i].get_meta(&"wall_rect",Rect2()) as Rect2)
	return result


func _ensure_part(index:int,texture:Texture2D,modulate_color:Color) -> void:
	while parts.size() <= index:
		var sprite := Sprite2D.new()
		sprite.name = "GrassInterior" if parts.is_empty() else "LogBorder%d" % (parts.size()+1)
		sprite.centered = false
		sprite.region_enabled = true
		sprite.region_filter_clip_enabled = false
		sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.texture = texture
		# 原版草顶是灰度纹理，按原版平原草色着色；木顶直接用原图。
		sprite.modulate = modulate_color
		add_child(sprite)
		parts.append(sprite)


func _apply_part(sprite:Sprite2D,area:Rect2) -> void:
	sprite.position = area.position
	sprite.scale = cell_size / TEXTURE_CELL
	sprite.region_rect = Rect2(Vector2.ZERO,area.size/cell_size*TEXTURE_CELL)


func _full_wall_spans() -> Array:
	return [
		[Vector2(interior_rect.position.y,interior_rect.end.y)],
		[Vector2(interior_rect.position.y,interior_rect.end.y)],
		[Vector2(visual_rect.position.x,visual_rect.end.x)],
		[Vector2(visual_rect.position.x,visual_rect.end.x)],
	]


# 某一边某一截墙的世界矩形：0 左 1 右 2 上 3 下。
func _wall_rect(side:int,axis_a:float,axis_b:float) -> Rect2:
	match side:
		0:
			return Rect2(visual_rect.position.x,axis_a,cell_size.x,axis_b-axis_a)
		1:
			return Rect2(interior_rect.end.x,axis_a,cell_size.x,axis_b-axis_a)
		2:
			return Rect2(axis_a,visual_rect.position.y,axis_b-axis_a,cell_size.y)
		_:
			return Rect2(axis_a,interior_rect.end.y,axis_b-axis_a,cell_size.y)


func configure_regions(ground:Array[Rect2],walls:Array[Rect2],cell:Vector2,enabled:bool) -> void:
	visible = enabled
	if not enabled: return
	cell_size = cell
	var areas:Array[Rect2] = ground.duplicate()
	areas.append_array(walls)
	for i:int in range(areas.size()):
		var grass:bool = i < ground.size()
		_ensure_part(i,GRASS if grass else LOG,Color.WHITE)
		parts[i].texture = GRASS if grass else LOG
		parts[i].modulate = Color("91bd59") if grass else Color.WHITE
		parts[i].set_meta("is_wall",not grass)
		parts[i].set_meta("wall_rect",areas[i] if not grass else Rect2())
		parts[i].visible = true
		_apply_part(parts[i],areas[i])
	for i:int in range(areas.size(),parts.size()): parts[i].visible = false
