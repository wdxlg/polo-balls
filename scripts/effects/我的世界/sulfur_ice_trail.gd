extends Node2D
## One actual terrain cell of Sulfur Cube's temporary blue-ice trail.
const ICE:Texture2D = preload("res://Images/characters/我的世界/sulfur_cube/source/blue_ice.png")
const FRAGMENTS:Script = preload("res://scripts/effects/我的世界/block_fragments.gd")
const CRACKS:Array[Texture2D] = [
	preload("res://Images/characters/我的世界/snow_golem/ice_crack_0.png"),
	preload("res://Images/characters/我的世界/snow_golem/ice_crack_1.png"),
	preload("res://Images/characters/我的世界/snow_golem/ice_crack_2.png"),
	preload("res://Images/characters/我的世界/snow_golem/ice_crack_3.png"),
	preload("res://Images/characters/我的世界/snow_golem/ice_crack_4.png"),
	preload("res://Images/characters/我的世界/snow_golem/ice_crack_5.png"),
	preload("res://Images/characters/我的世界/snow_golem/ice_crack_6.png"),
	preload("res://Images/characters/我的世界/snow_golem/ice_crack_7.png"),
	preload("res://Images/characters/我的世界/snow_golem/ice_crack_8.png"),
	preload("res://Images/characters/我的世界/snow_golem/ice_crack_9.png")]
const LIFETIME:float = 4.0
const CRACK_START:float = 2.0
const BOOST_REFRESH:float = 0.18
var cell_rect:Rect2
var source_ref:WeakRef
var age:float = 0.0
var _texture:Sprite2D
var _crack:Sprite2D
var _scan:float = 0.0

static func cell_at(context:Node2D,point:Vector2) -> Rect2:
	var world:Node = context.get_tree().current_scene
	if is_instance_valid(world):
		var maps:Variant = world.get("map_group")
		if maps is Dictionary:
			var map_node:Variant = maps.get(str(world.get("now_choose_map")))
			if map_node is Node:
				var layer:TileMapLayer = _find_layer(map_node)
				if layer != null and layer.tile_set != null:
					var cell:Vector2i = layer.local_to_map(layer.to_local(point))
					var center:Vector2 = layer.to_global(layer.map_to_local(cell))
					var tile:Vector2 = Vector2(layer.tile_set.tile_size)
					var size:Vector2 = Vector2(layer.global_transform.x.length()*tile.x,layer.global_transform.y.length()*tile.y)
					return Rect2(center-size*0.5,size)
	var center:Vector2 = (point/24.0).round()*24.0
	return Rect2(center-Vector2.ONE*12.0,Vector2.ONE*24.0)

static func _find_layer(node:Node) -> TileMapLayer:
	if node is TileMapLayer and (node as TileMapLayer).tile_set != null: return node as TileMapLayer
	for child:Node in node.get_children():
		var found:TileMapLayer = _find_layer(child)
		if found != null: return found
	return null

func setup(owner:ball,rect:Rect2) -> void:
	source_ref = weakref(owner)
	cell_rect = rect
	global_position = rect.get_center()
	_texture = Sprite2D.new()
	_texture.name = "NativeBlueIce"
	_texture.texture = ICE
	_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_texture.scale = rect.size/ICE.get_size()
	add_child(_texture)
	_crack = Sprite2D.new()
	_crack.name = "NativeBlockCracks"
	_crack.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_crack.scale = rect.size/Vector2(16.0,16.0)
	_crack.hide()
	add_child(_crack)
	z_as_relative = false
	z_index = 4
	add_to_group("BattleTransient")
	add_to_group("MCSulfurIceTrail")

func _physics_process(delta:float) -> void:
	if not is_instance_valid(_texture): return
	var owner:Variant = source_ref.get_ref() if source_ref != null else null
	if not is_instance_valid(owner) or owner.health <= 0 or not owner.is_combat_runtime_active():
		if not is_instance_valid(owner) or owner.health <= 0: _break_tile()
		return
	age += delta
	if age >= LIFETIME:
		_break_tile()
		return
	if age >= CRACK_START:
		var index:int = clampi(int((age-CRACK_START)/(LIFETIME-CRACK_START)*10.0),0,9)
		_crack.texture = CRACKS[index]
		_crack.show()
	_scan -= delta
	if _scan > 0.0 or not owner.is_multiplayer_authority(): return
	_scan = 0.07
	for raw:Variant in get_tree().get_nodes_in_group("Ball"):
		if not is_instance_valid(raw) or not raw is ball: continue
		var target:ball = raw as ball
		if target.health <= 0 or not cell_rect.has_point(target.global_position): continue
		# A speed multiplier preserves each unit's OWN movement direction. It never
		# teleports or forces motion while the unit stands still; expires off ice.
		var buff := Buff.new(2,BOOST_REFRESH,Buff.Buff_types.Speed,1.65,Buff.Algorithms.mul)
		var scene:Node = get_tree().current_scene
		if is_instance_valid(scene) and scene.has_method("new_buff"):
			scene.new_buff(target,owner,"硫方怪冰径加速",buff)
		else:
			var source_id:int = owner.get_instance_id()
			if not target.Buff_Dic.has(source_id): target.Buff_Dic[source_id] = {}
			target.Buff_Dic[source_id]["硫方怪冰径加速"] = buff

func _break_tile() -> void:
	if is_queued_for_deletion(): return
	if is_inside_tree():
		FRAGMENTS.spawn_texture(self,ICE,global_position,cell_rect.size.x/maxf(ICE.get_width(),1.0),{"max_pieces":9,"scatter_radius":cell_rect.size.x})
	queue_free()
