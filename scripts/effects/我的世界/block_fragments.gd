extends Node2D
## Shared Minecraft BLOCK destruction: real block pixels arc outward, land, rest, then fade.
## Not the item-character death effect (item_fragments.gd), whose shards leave the map.
const ITEM = preload("res://scripts/effects/我的世界/item_fragments.gd")
const EXPLOSION = preload("res://scripts/effects/我的世界/mc_explosion.gd")
@export var scatter_radius:float = 22.0
@export var arc_height_min:float = 18.0
@export var arc_height_max:float = 42.0
@export var flight_min:float = 0.38
@export var flight_max:float = 0.72
@export var ground_hold:float = 0.20
@export var fade_time:float = 0.30
@export var max_pieces:int = 16
@export var spin_speed:float = 4.0
@export var z_layer:int = 104
var pieces:Array[Dictionary] = []
var age:float = 0.0
var _duration:float = 0.0
var _rng := RandomNumberGenerator.new()

static func spawn_obstacle(context:Node2D,tile_info:Dictionary = {},options:Dictionary = {}) -> Node2D:
	var effect:Node2D = load("res://scripts/effects/我的世界/block_fragments.gd").new()
	effect._configure(options)
	EXPLOSION.runtime_container(context).add_child(effect)
	effect.global_position = context.global_position
	if context is TileMapLayer and tile_info.has("cell"):
		var layer:TileMapLayer = context as TileMapLayer
		var cell:Vector2i = tile_info.cell
		if layer.tile_set != null and layer.get_cell_source_id(cell) >= 0:
			var source:TileSetSource = layer.tile_set.get_source(layer.get_cell_source_id(cell))
			if source is TileSetAtlasSource:
				var atlas:TileSetAtlasSource = source as TileSetAtlasSource
				var texture := AtlasTexture.new()
				texture.atlas = atlas.texture
				texture.region = atlas.get_tile_texture_region(layer.get_cell_atlas_coords(cell))
				texture.filter_clip = true
				var sample := Sprite2D.new()
				sample.texture = texture
				layer.add_child(sample)
				sample.position = layer.map_to_local(cell)
				effect.cut_sprite(sample,false)
				sample.free()
	else:
		effect.cut_obstacle_tree(context)
	if effect.pieces.is_empty(): effect.queue_free()
	return effect

static func spawn_texture(context:Node2D,texture:Texture2D,point:Vector2,scale_factor:float = 1.0,options:Dictionary = {}) -> Node2D:
	## For drawn/virtual blocks with no Sprite2D, e.g. a broken moss tile.
	var sample := Sprite2D.new()
	sample.texture = texture
	context.add_child(sample)
	sample.global_position = point
	sample.global_scale = Vector2.ONE*scale_factor
	var effect:Node2D = spawn_obstacle(sample,{},options)
	sample.free()
	return effect

func _configure(options:Dictionary) -> void:
	for key:String in ["scatter_radius","arc_height_min","arc_height_max","flight_min","flight_max","ground_hold","fade_time","max_pieces","spin_speed","z_layer"]:
		if options.has(key): set(key,options[key])

func _ready() -> void:
	add_to_group("BattleTransient")
	add_to_group("MCBlockFragments")
	top_level = true
	global_position = Vector2.ZERO
	global_scale = Vector2.ONE
	_rng.randomize()

func cut_obstacle_tree(node:Node) -> void:
	if str(node.name).begins_with("MCBlockCracks") or pieces.size() >= max_pieces: return
	if node is Sprite2D and node.is_visible_in_tree(): cut_sprite(node,node.flip_h)
	elif node is Polygon2D and node.is_visible_in_tree(): cut_polygon(node)
	for child:Node in node.get_children(): cut_obstacle_tree(child)

func cut_sprite(source:Sprite2D,flipped:bool) -> void:
	if source.texture == null: return
	# Share only the alpha-aware pixel-region cutter; movement/lifetime are independent.
	for region:Rect2i in ITEM._cut_regions(source.texture):
		if pieces.size() >= max_pieces: break
		var texture := AtlasTexture.new()
		texture.atlas = source.texture
		texture.region = Rect2(region)
		texture.filter_clip = true
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.flip_h = flipped
		sprite.flip_v = source.flip_v
		sprite.modulate = source.modulate
		add_child(sprite)
		var offset:Vector2 = Vector2(region.position)+Vector2(region.size)*0.5-source.texture.get_size()*0.5+source.offset
		if flipped: offset.x = -offset.x
		if source.flip_v: offset.y = -offset.y
		sprite.global_transform = source.global_transform
		sprite.global_position = source.to_global(offset)
		_add_piece(sprite,source.global_position)

func cut_polygon(source:Polygon2D) -> void:
	if source.polygon.size() < 3: return
	var bounds := Rect2(source.polygon[0],Vector2.ZERO)
	for point:Vector2 in source.polygon: bounds = bounds.expand(point)
	for row:int in range(4):
		for column:int in range(4):
			if pieces.size() >= max_pieces: return
			var rect := Rect2(bounds.position+bounds.size*Vector2(column,row)/4.0,bounds.size/4.0)
			var clip := PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
			for poly:PackedVector2Array in Geometry2D.intersect_polygons(source.polygon,clip):
				if pieces.size() >= max_pieces: return
				var center:Vector2 = rect.get_center()
				var fragment := Polygon2D.new()
				var points:PackedVector2Array = poly.duplicate()
				for i:int in range(points.size()): points[i] -= center
				fragment.polygon = points
				fragment.color = source.color
				fragment.modulate = source.modulate
				add_child(fragment)
				fragment.global_transform = source.global_transform
				fragment.global_position = source.to_global(center)
				_add_piece(fragment,source.global_position)

func _add_piece(shard:Node2D,origin:Vector2) -> void:
	shard.z_as_relative = false
	shard.z_index = z_layer
	var start:Vector2 = shard.global_position
	var landing:Vector2 = origin+Vector2(_rng.randf_range(-scatter_radius,scatter_radius),_rng.randf_range(-scatter_radius*0.45,scatter_radius*0.45))
	var flight:float = _rng.randf_range(maxf(flight_min,0.01),maxf(maxf(flight_max,flight_min),0.01))
	var height:float = _rng.randf_range(maxf(0.0,arc_height_min),maxf(maxf(arc_height_min,arc_height_max),0.0))
	var spin:float = _rng.randf_range(-spin_speed,spin_speed)
	pieces.append({"sprite":shard,"start":start,"landing":landing,"height":height,"flight":flight,"spin":spin,"rotation":shard.rotation,"alpha":shard.modulate.a,"landed":false})
	_duration = maxf(_duration,flight+maxf(ground_hold,0.0)+maxf(fade_time,0.01))

func _process(delta:float) -> void:
	var game:Node = get_node_or_null("/root/Game")
	if get_tree().paused or (game != null and bool(game.get("now_stop_state"))): return
	advance(delta)

func advance(delta:float) -> void:
	age += maxf(delta,0.0)
	for piece:Dictionary in pieces:
		var shard:Node2D = piece.sprite
		var flight:float = float(piece.flight)
		var t:float = clampf(age/flight,0.0,1.0)
		shard.global_position = piece.start.lerp(piece.landing,t)-Vector2(0.0,4.0*float(piece.height)*t*(1.0-t))
		shard.rotation = float(piece.rotation)+float(piece.spin)*minf(age,flight)
		piece.landed = age >= flight
		var fade:float = clampf((age-flight-maxf(ground_hold,0.0))/maxf(fade_time,0.01),0.0,1.0)
		var tint:Color = shard.modulate
		tint.a = float(piece.alpha)*(1.0-fade)
		shard.modulate = tint
	if age >= _duration: queue_free()
