extends Node2D

# V147：把蠹虫石砖背景拆成小块 CanvasItem。
# Godot 会缓存每个 CanvasItem 的 _draw() 命令，只有 queue_redraw() 的块才会重建。
# 因此石砖裂开/碎裂时只重画附近 8x8 左右的格子，不再让整张 50x50 地图
# 因为一个格子的状态变化而重新提交数千次 draw_texture_rect()。

const STATE_INTACT:int = 0
const STATE_CRACKED:int = 1
const STATE_BROKEN:int = 2

var _field:Node2D = null
var _coords:Array[Vector2i] = []
var _rects:Array[Rect2] = []
var _intact_texture:Texture2D = null
var _cracked_texture:Texture2D = null


func setup(
	field:Node2D,
	map_layer:TileMapLayer,
	chunk_rect:Rect2i,
	intact_texture:Texture2D,
	cracked_texture:Texture2D
) -> void:
	_field = field
	_intact_texture = intact_texture
	_cracked_texture = cracked_texture
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	if (
		_field == null
		or not is_instance_valid(_field)
		or map_layer == null
		or not is_instance_valid(map_layer)
		or map_layer.tile_set == null
	):
		return

	var tile_size:Vector2 = Vector2(map_layer.tile_set.tile_size)
	for y:int in range(chunk_rect.position.y,chunk_rect.end.y):
		for x:int in range(chunk_rect.position.x,chunk_rect.end.x):
			var coord:=Vector2i(x,y)
			var world_position:Vector2 = map_layer.to_global(map_layer.map_to_local(coord))
			var center:Vector2 = _field.to_local(world_position)
			_coords.append(coord)
			_rects.append(Rect2(center - tile_size * 0.5,tile_size))

	queue_redraw()


func _draw() -> void:
	if _field == null or not is_instance_valid(_field):
		return
	var states_value:Variant = _field.get("_tile_states")
	if not (states_value is Dictionary):
		return
	var states:Dictionary = states_value as Dictionary

	# _coords 与 _rects 在 setup() 时一次性算好。状态改变时这里只做 Dictionary 查询
	# 和少量 draw_texture_rect()，不再重复 map_to_local/to_global/to_local 坐标链。
	for index:int in range(_coords.size()):
		var coord:Vector2i = _coords[index]
		var state:int = int(states.get(coord,STATE_INTACT))
		if state == STATE_BROKEN:
			continue
		var texture:Texture2D = _cracked_texture if state == STATE_CRACKED else _intact_texture
		if texture != null:
			draw_texture_rect(texture,_rects[index],false,Color.WHITE,false)
