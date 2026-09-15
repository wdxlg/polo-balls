extends Node2D
# 纯视觉重复贴图：5个Sprite覆盖任意大小地图，不创建格子节点或碰撞体。
const GRASS:Texture2D = preload("res://Images/effects/我的世界/草方块背景/grass_block_top.png")
const LOG:Texture2D = preload("res://Images/effects/我的世界/草方块背景/oak_log_top.png")
var parts:Array[Sprite2D] = []
var interior_rect:Rect2
var visual_rect:Rect2
var cell_size:Vector2
func configure(rect:Rect2,cell:Vector2,enabled:bool) -> void:
	visible = enabled
	if not enabled: return
	interior_rect = rect
	cell_size = cell
	visual_rect = Rect2(rect.position-cell,rect.size+cell*2.0)
	if parts.is_empty():
		for i:int in range(5):
			var sprite := Sprite2D.new()
			sprite.name = "GrassInterior" if i == 0 else "LogBorder%d" % i
			sprite.centered = false
			sprite.region_enabled = true
			sprite.region_filter_clip_enabled = false
			sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.texture = GRASS if i == 0 else LOG
			# 原版草顶是灰度纹理，按原版平原草色着色；木顶直接用原图。
			sprite.modulate = Color("91bd59") if i == 0 else Color.WHITE
			add_child(sprite)
			parts.append(sprite)
	var rects:Array[Rect2] = [rect,
		Rect2(visual_rect.position,Vector2(visual_rect.size.x,cell.y)),
		Rect2(Vector2(visual_rect.position.x,rect.end.y),Vector2(visual_rect.size.x,cell.y)),
		Rect2(Vector2(visual_rect.position.x,rect.position.y),Vector2(cell.x,rect.size.y)),
		Rect2(Vector2(rect.end.x,rect.position.y),Vector2(cell.x,rect.size.y))]
	for i:int in range(5):
		parts[i].position = rects[i].position
		parts[i].scale = cell/Vector2(16,16)
		parts[i].region_rect = Rect2(Vector2.ZERO,rects[i].size/cell*16.0)
