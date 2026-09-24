extends Node2D
## Reusable texture fragmentation: pieces launch, spin and fall out of the map.
## Character death is one caller; any visible Sprite2D/Polygon2D/tile can use it.
## block_fragments.gd is a DIFFERENT optional effect whose pieces land and fade.
@export var gravity:float=600.0
@export var launch_up_min:float=130.0
@export var launch_up_max:float=250.0
@export var horizontal_speed:float=150.0
@export var spin_speed:float=7.0
var pieces:Array[Dictionary]=[]
var arena:Rect2
var age:float=0.0
var _rng:=RandomNumberGenerator.new()
static func spawn(context:Node2D,options:Dictionary={}) -> Node2D:
	## Character convenience entry: include the current image and named equipment.
	var effect:Node2D=_start(context,options)
	var sprites:Array[Sprite2D]=[]
	if context.image is Sprite2D: sprites.append(context.image)
	var names:Array[String]=[]
	var name_set:Dictionary=preload("res://classes/property_index.gd").names(context)
	for property_name:Variant in name_set.keys(): names.append(str(property_name))
	for key:String in ["head","rod","shaft","sword","hook_sprite"]:
		if key in names:
			var value:Variant=context.get(key)
			if value is Sprite2D and value not in sprites and value.is_visible_in_tree(): sprites.append(value)
	for sprite:Sprite2D in sprites:
		effect.cut(sprite,context.is_character_visual_flipped_h() if sprite==context.image else sprite.flip_h)
	return effect

static func _start(context:Node2D,options:Dictionary) -> Node2D:
	var effect:Node2D=load("res://scripts/effects/我的世界/item_fragments.gd").new()
	for key:String in ["gravity","launch_up_min","launch_up_max","horizontal_speed","spin_speed"]:
		if options.has(key): effect.set(key,options[key])
	var world:Node=context.get_tree().current_scene
	var container:Node2D=preload("res://scripts/effects/我的世界/mc_explosion.gd").runtime_container(context)
	container.add_child(effect)
	if world != null and world.has_method("_current_map_node") and world.call("_current_map_node") != null:
		effect.arena=world.return_map_world_rect(world.call("_current_map_node"))
	if effect.arena.size==Vector2.ZERO: effect.arena=Rect2(context.global_position-Vector2(400,400),Vector2(800,800))
	return effect

static func spawn_visual(context:Node2D,options:Dictionary={},tile_info:Dictionary={}) -> Node2D:
	## Works on any visual node; no `image` property or character API required.
	var effect:Node2D=_start(context,options)
	if context is TileMapLayer and tile_info.has("cell"):
		var layer:TileMapLayer=context as TileMapLayer
		var cell:Vector2i=tile_info.cell
		if layer.tile_set != null and layer.get_cell_source_id(cell)>=0:
			var source:TileSetSource=layer.tile_set.get_source(layer.get_cell_source_id(cell))
			if source is TileSetAtlasSource:
				var texture:=AtlasTexture.new()
				texture.atlas=source.texture
				texture.region=source.get_tile_texture_region(layer.get_cell_atlas_coords(cell))
				var sample:=Sprite2D.new()
				sample.texture=texture
				layer.add_child(sample)
				sample.position=layer.map_to_local(cell)
				effect.cut(sample,false)
				sample.free()
	else: effect.cut_visual_tree(context)
	if effect.pieces.is_empty(): effect.queue_free()
	return effect

static func spawn_texture(context:Node2D,texture:Texture2D,point:Vector2,scale_factor:float=1.0,options:Dictionary={}) -> Node2D:
	## A texture-only source, e.g. a virtual tile, is sampled without leaving a node.
	var sample:=Sprite2D.new()
	sample.texture=texture
	context.add_child(sample)
	sample.global_position=point
	sample.global_scale=Vector2.ONE*scale_factor
	var effect:Node2D=spawn_visual(sample,options)
	sample.free()
	return effect

static func spawn_obstacle(context:Node2D,tile_info:Dictionary={},options:Dictionary={}) -> Node2D:
	## Backward-compatible original call used by Ghast/Wither obstacles.
	return spawn_visual(context,options,tile_info)
func _ready() -> void:
	add_to_group("BattleTransient")
	add_to_group("MCItemFragments")
	_rng.randomize()
func cut(source:Sprite2D,flipped:bool) -> void:
	if source.texture==null: return
	# V432 性能：碎片切割区域只取决于纹理本身；按纹理缓存，避免每次死亡都 GPU->CPU 回读。
	var regions:Array=_cut_regions(source.texture)
	for region:Rect2i in regions:
		var texture:=AtlasTexture.new()
		texture.atlas=source.texture
		texture.region=Rect2(region)
		texture.filter_clip=true
		var sprite:=Sprite2D.new()
		sprite.texture=texture
		sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.flip_h=flipped
		sprite.flip_v=source.flip_v
		sprite.z_as_relative=false
		sprite.z_index=104 # pass the map's visual border/mask as cosmetic debris
		add_child(sprite)
		var offset:Vector2=Vector2(region.position)+Vector2(region.size)*0.5-source.texture.get_size()*0.5
		if flipped: offset.x=-offset.x
		if source.flip_v: offset.y=-offset.y
		offset+=source.offset
		sprite.global_transform=source.global_transform
		sprite.global_position=source.to_global(offset)
		var radius:float=(Vector2(region.size)*sprite.global_scale.abs()).length()*0.5
		pieces.append({"sprite":sprite,"velocity":Vector2(_rng.randf_range(-horizontal_speed,horizontal_speed),-_rng.randf_range(launch_up_min,launch_up_max)),"spin":_rng.randf_range(-spin_speed,spin_speed),"radius":radius,"done":false})
static var _cut_region_cache:Dictionary={}
static func _cut_regions(texture:Texture2D) -> Array:
	var key:int=texture.get_instance_id()
	var cached:Variant=_cut_region_cache.get(key)
	if cached is Array: return cached
	var result:Array=[]
	var image:Image=texture.get_image()
	if image!=null and not image.is_empty():
		var used:Rect2i=image.get_used_rect()
		var cell:Vector2i=Vector2i(ceilf(used.size.x/4.0),ceilf(used.size.y/4.0))
		for row:int in range(4):
			for column:int in range(4):
				var region:Rect2i=Rect2i(used.position+cell*Vector2i(column,row),cell).intersection(used)
				if region.size.x<=0 or region.size.y<=0 or image.get_region(region).get_used_rect().size==Vector2i.ZERO: continue
				result.append(region)
	_cut_region_cache[key]=result
	return result
func _process(delta:float) -> void:
	advance(delta)
func advance(delta:float) -> void:
	age+=maxf(delta,0)
	var alive:bool=false
	for piece:Dictionary in pieces:
		if piece.done: continue
		var sprite:Node2D=piece.sprite
		sprite.global_position+=piece.velocity*delta+Vector2(0,0.5*gravity*delta*delta)
		piece.velocity.y+=gravity*delta
		sprite.rotation+=piece.spin*delta
		if (piece.velocity.y>0 and not arena.grow(piece.radius).has_point(sprite.global_position)) or age>20:
			piece.done=true
			sprite.hide()
		else: alive=true
	if not alive: queue_free()

func cut_visual_tree(node:Node) -> void:
	if str(node.name).begins_with("MCBlockCracks"): return
	if node is Sprite2D and node.is_visible_in_tree(): cut(node,node.flip_h)
	elif node is Polygon2D and node.is_visible_in_tree(): cut_polygon(node)
	for child:Node in node.get_children(): cut_visual_tree(child)

func cut_polygon(source:Polygon2D) -> void:
	if source.polygon.size()<3: return
	var bounds:=Rect2(source.polygon[0],Vector2.ZERO)
	for point:Vector2 in source.polygon: bounds=bounds.expand(point)
	for row:int in range(4):
		for column:int in range(4):
			var rect:=Rect2(bounds.position+bounds.size*Vector2(column,row)/4.0,bounds.size/4.0)
			var clip:=PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
			for poly:PackedVector2Array in Geometry2D.intersect_polygons(source.polygon,clip):
				var fragment:=Polygon2D.new()
				fragment.polygon=poly
				fragment.color=source.color
				fragment.z_as_relative=false
				fragment.z_index=104
				add_child(fragment)
				fragment.global_transform=source.global_transform
				var center:Vector2=rect.get_center()
				fragment.position+=fragment.transform.basis_xform(center)
				var points:PackedVector2Array=fragment.polygon
				for i:int in range(points.size()): points[i]-=center
				fragment.polygon=points
				pieces.append({"sprite":fragment,"velocity":Vector2(_rng.randf_range(-horizontal_speed,horizontal_speed),-_rng.randf_range(launch_up_min,launch_up_max)),"spin":_rng.randf_range(-spin_speed,spin_speed),"radius":rect.size.length()*0.5,"done":false})
