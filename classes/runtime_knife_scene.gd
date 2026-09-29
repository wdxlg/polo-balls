extends RefCounted
## Bake away scene inheritance once, but create NEW objects for every throw.
## No projectile pooling: ObjectIDs, physics objects, awaits and destruction stay fresh.
const CACHE_KEY = &"_runtime_flat_knife_scene"
const PATH = "res://scenes/shooter/knife.tscn"
## V430 性能：投射物不需要这些继承自 ball.tscn 的子节点（血条 UI、动画播放器、
## 状态图标、回血/受伤计时器、自动适配器、同步器）。它们对小刀的外观与伤害没有任何
## 影响，但每把刀都要为它们付出 instantiate / _ready / free 成本（23 节点 -> 10 节点）。
## MultiplayerSynchronizer 仅在没有联机 peer 时剥离，联机对局保持原样。
const PROJECTILE_STRIP_NODES:Array[StringName] = [
	&"Health_Bar",&"AnimationPlayer",&"Status_Image",
	&"Health_Restore_Timer",&"Hurting_Timer",&"CharacterAutoFit",
	&"Graphics/AnimatedSprite2D",
]
static func should_strip_synchronizer(world:Node) -> bool:
	# Game 启动时总会装一个 OfflineMultiplayerPeer，因此 has_multiplayer_peer() 恒为 true；
	# 只有真实网络 peer（ENet 等）存在时才保留同步器。
	if not world.is_inside_tree():
		return true
	var peer:MultiplayerPeer = world.multiplayer.multiplayer_peer
	return peer == null or peer is OfflineMultiplayerPeer
static func strip_projectile_nodes(prototype:Node,strip_synchronizer:bool) -> int:
	var removed:int = 0
	var names:Array[StringName] = PROJECTILE_STRIP_NODES.duplicate()
	if strip_synchronizer:
		names.append(&"MultiplayerSynchronizer")
	for node_name:StringName in names:
		var child:Node = prototype.get_node_or_null(NodePath(node_name))
		if child == null:
			continue
		child.get_parent().remove_child(child)
		child.free()
		removed += 1
	return removed
static func prepare(world:Node,source:PackedScene) -> Dictionary:
	if world == null or source == null or source.resource_path != PATH:
		return {}
	var strip_synchronizer:bool = should_strip_synchronizer(world)
	if world.has_meta(CACHE_KEY):
		var cached:Dictionary = world.get_meta(CACHE_KEY)
		if cached.get("source") == source and bool(cached.get("strip_synchronizer")) == strip_synchronizer:
			return cached
	var prototype:Node = source.instantiate()
	if prototype == null:
		return {}
	strip_projectile_nodes(prototype,strip_synchronizer)
	var records:Array = []
	_flatten(prototype,prototype,records)
	var packed:PackedScene = PackedScene.new()
	var error:int = packed.pack(prototype)
	prototype.free()
	if error != OK:
		return {}
	var entry:Dictionary = {"source":source,"packed":packed,"records":records,"strip_synchronizer":strip_synchronizer}
	world.set_meta(CACHE_KEY,entry)
	# Rebuild after an in-place PackedScene reload/edit. A Node-bound callable
	# disconnects automatically when this world dies; no global cache survives it.
	var rebuild:Callable = world.remove_meta.bind(CACHE_KEY)
	if not source.changed.is_connected(rebuild):
		source.changed.connect(rebuild,CONNECT_ONE_SHOT)
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
