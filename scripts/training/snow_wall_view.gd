extends Node2D
## Visual-only wall overlay. Never owns a collider, timer, cold meter or damage callback.
var field:Node2D
var visual_walls:Array[Rect2] = []

func _ready() -> void:
	name = "EnvironmentSnowWalls"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _draw() -> void:
	if not is_instance_valid(field): return
	var snow:Texture2D = field.SNOW
	var cell_size:float = field.CELL
	var native_scale:Vector2 = snow.get_size()/cell_size
	for cell:Vector2i in field.environment_patches:
		var record:Dictionary = field.environment_patches[cell]
		if not bool(record.decorative): continue
		var offset:Vector2 = field._development_environment_offsets.get(cell,Vector2.ZERO)
		for piece:Dictionary in projected_pieces(cell,record):
			var rect:Rect2 = piece.rect
			var corner:Vector2 = piece.corner
			# Crop the original native tile; never stretch a thin wall into a full snow tile.
			draw_texture_rect_region(snow,Rect2(rect.position+offset,rect.size),Rect2((rect.position-corner)*native_scale,rect.size*native_scale))

func projected_pieces(cell:Vector2i,record:Dictionary) -> Array[Dictionary]:
	var result:Array[Dictionary] = []
	var size:Vector2 = Vector2.ONE*field.CELL
	for original:Rect2 in record.rects:
		var center:Vector2 = field.point_at(cell)
		if visual_walls.is_empty():
			result.append({"rect":original,"corner":center-size*0.5})
			continue
		# Background style is a LOCAL visual preference. Project the same replicated
		# wall snow onto this peer's actual wall surface, never changing its ground cells.
		var nearest:Rect2
		var best:float = INF
		var anchor:Vector2 = original.get_center()
		for wall:Rect2 in visual_walls:
			var distance:float = anchor.distance_squared_to(anchor.clamp(wall.position,wall.end))
			if distance<best:
				nearest = wall
				best = distance
		if best>pow(field.CELL*2.0,2): continue
		if nearest.size.x>=nearest.size.y: center.y = nearest.get_center().y
		else: center.x = nearest.get_center().x
		var rectangle:Rect2 = Rect2(center-size*0.5,size).intersection(nearest)
		if rectangle.has_area(): result.append({"rect":rectangle,"corner":center-size*0.5})
	return result
