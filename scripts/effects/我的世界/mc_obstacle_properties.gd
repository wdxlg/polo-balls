extends Node
## 公共障碍物属性：StaticBody2D / TileMapLayer 默认可破坏；可挂同名子节点调参。
## 地图安全边界仍强制保护；单格 TileData 可用同名自定义数据覆写前两项。
@export var destructible:bool = true
@export_range(0.1,100.0,0.1) var blast_step:float = 34.0
@export var crack_thresholds:PackedFloat32Array = PackedFloat32Array([34.0,67.0])

static func _cell_value(node:Node,cell:Variant,key:String) -> Variant:
	if not node is TileMapLayer or not cell is Vector2i: return null
	var layer:TileMapLayer = node as TileMapLayer
	var tile:TileData = layer.get_cell_tile_data(cell)
	if tile == null or layer.tile_set == null: return null
	for i:int in range(layer.tile_set.get_custom_data_layers_count()):
		if str(layer.tile_set.get_custom_data_layer_name(i)) == key:
			return tile.get_custom_data(key)
	return null

static func _config(node:Node) -> Node:
	return node.get_node_or_null("MCObstacleProperties") if is_instance_valid(node) else null

static func can_break(node:Node,cell:Variant = null) -> bool:
	if not is_instance_valid(node): return false
	var value:Variant = _cell_value(node,cell,"mc_obstacle_destructible")
	if value is bool: return value
	if node.has_meta("mc_obstacle_destructible"): return bool(node.get_meta("mc_obstacle_destructible"))
	var config:Node = _config(node)
	return bool(config.get("destructible")) if config != null else true

static func progress_per_blast(node:Node,cell:Variant = null) -> float:
	var value:Variant = _cell_value(node,cell,"mc_obstacle_blast_step")
	if not value is float and not value is int:
		value = node.get_meta("mc_obstacle_blast_step") if node.has_meta("mc_obstacle_blast_step") else null
	if not value is float and not value is int:
		var config:Node = _config(node)
		value = config.get("blast_step") if config != null else 34.0
	return clampf(float(value),0.1,100.0)

static func thresholds(node:Node) -> PackedFloat32Array:
	var config:Node = _config(node)
	return config.get("crack_thresholds") if config != null else PackedFloat32Array([34.0,67.0])

static func crack_index(node:Node,progress:float) -> int:
	var stages:PackedFloat32Array = thresholds(node)
	var result:int = -1
	for i:int in range(stages.size()):
		if progress >= clampf(stages[i],0.0,100.0): result = i
	return result
