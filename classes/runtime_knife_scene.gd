extends RefCounted
## Bake away scene inheritance once, but create NEW objects for every throw.
## No projectile pooling: ObjectIDs, physics objects, awaits and destruction stay fresh.
const CACHE_KEY = &"_runtime_flat_knife_scene"
const PATH = "res://scenes/shooter/knife.tscn"
static func prepare(world:Node,source:PackedScene) -> Dictionary:
	if world == null or source == null or source.resource_path != PATH:
		return {}
	if world.has_meta(CACHE_KEY):
		var cached:Dictionary = world.get_meta(CACHE_KEY)
		if cached.get("source") == source:
			return cached
	var prototype:Node = source.instantiate()
	if prototype == null:
		return {}
	var records:Array = []
	_flatten(prototype,prototype,records)
	var packed:PackedScene = PackedScene.new()
	var error:int = packed.pack(prototype)
	prototype.free()
	if error != OK:
		return {}
	var entry:Dictionary = {"source":source,"packed":packed,"records":records}
	world.set_meta(CACHE_KEY,entry)
	# Rebuild after an in-place PackedScene reload/edit. A Node-bound callable
	# disconnects automatically when this world dies; no global cache survives it.
	source.changed.connect(world.remove_meta.bind(CACHE_KEY),CONNECT_ONE_SHOT)
	return entry
static func instantiate(world:Node,source:PackedScene) -> Node:
	var entry:Dictionary = prepare(world,source)
	if entry.is_empty():
		return source.instantiate()
	var node:Node = (entry.packed as PackedScene).instantiate()
	for record:Dictionary in entry.records:
		var child:Node = node.get_node(record.path)
		if record.has("owner"):
			child.owner = node.get_node(record.owner) if record.owner != null else null
		if record.has("scene_path"):
			child.scene_file_path = record.scene_path
	return node
static func _flatten(node:Node,scene_root:Node,records:Array) -> void:
	var record:Dictionary = {"path":scene_root.get_path_to(node)}
	if not node.scene_file_path.is_empty():
		record.scene_path = node.scene_file_path
		node.scene_file_path = ""
	if node != scene_root and node.owner != scene_root:
		record.owner = scene_root.get_path_to(node.owner) if node.owner != null else null
	if record.size() > 1:
		records.append(record)
	if node != scene_root:
		node.owner = scene_root
	for child:Node in node.get_children():
		_flatten(child,scene_root,records)
