extends SceneTree
var failures:int = 0
var checks:int = 0
func _initialize() -> void:
	call_deferred("_run")
func norm(value:Variant,scene_root:Node) -> Variant:
	if value is Node:
		return str(scene_root.get_path_to(value))
	if value is RandomNumberGenerator:
		return "independently initialized native RNG"
	if value is Shape2D:
		var data:Dictionary = {"class":value.get_class()}
		for info:Dictionary in value.get_property_list():
			if (int(info.usage) & PROPERTY_USAGE_STORAGE) != 0 and info.name not in ["resource_name","resource_path","resource_local_to_scene","script"]:
				data[info.name] = value.get(info.name)
		return data
	if value is Resource:
		return value.get_class()+"|"+value.resource_path
	if value is Callable or value is Signal:
		return str(typeof(value))
	if value is Array:
		var a:Array = []
		for item:Variant in value:
			a.append(norm(item,scene_root))
		return a
	if value is Dictionary:
		var d:Dictionary = {}
		for key:Variant in value:
			d[key] = norm(value[key],scene_root)
		return d
	return value
func compare(a:Node,b:Node,ar:Node,br:Node,stage:String) -> void:
	for info:Dictionary in a.get_property_list():
		var key:String = str(info.name)
		if (int(info.usage) & (PROPERTY_USAGE_STORAGE|PROPERTY_USAGE_SCRIPT_VARIABLE)) == 0:
			continue
		if key in ["_external_directional_gravity_hop_rng"]:
			continue
		checks += 1
		if key == "_visual_facing_last_image_id":
			# IDs must differ between independent instances, but each must point
			# to its own Image (not the other instance or the packing prototype).
			if stage == "after_ready" and (a.get(key) != a.image.get_instance_id() or b.get(key) != b.image.get_instance_id()):
				failures += 1
			continue
		if norm(a.get(key),ar) != norm(b.get(key),br):
			failures += 1
			if failures <= 12:
				print("SCENE_DIFFERENCE ",stage," ",ar.get_path_to(a),":",key," ",norm(a.get(key),ar)," != ",norm(b.get(key),br))
	checks += 3
	if a.scene_file_path != b.scene_file_path or norm(a.owner,ar) != norm(b.owner,br) or a.get_child_count() != b.get_child_count():
		failures += 1
		print("SCENE_TOPOLOGY_DIFFERENCE ",ar.get_path_to(a))
	for i:int in range(mini(a.get_child_count(),b.get_child_count())):
		compare(a.get_child(i),b.get_child(i),ar,br,stage)
func _run() -> void:
	var cache:Script = load("res://classes/runtime_knife_scene.gd")
	var source:PackedScene = load("res://scenes/shooter/knife.tscn")
	var world:Node2D = Node2D.new()
	root.add_child(world)
	current_scene = world
	seed(9224)
	var expected_random:int = randi()
	seed(9224)
	cache.prepare(world,source)
	checks += 1
	if randi() != expected_random:
		failures += 1
		print("SCENE_GLOBAL_RNG_CHANGED")
	var a:Node = source.instantiate()
	# V430: the runtime scene deliberately drops projectile-irrelevant nodes.
	# Apply the same strip to the reference instance so everything else must match.
	var strip_sync:bool = cache.should_strip_synchronizer(world)
	checks += 1
	if cache.strip_projectile_nodes(a,strip_sync) != (8 if strip_sync else 7):
		failures += 1
		print("SCENE_STRIP_COUNT_UNEXPECTED")
	var b:Node = cache.instantiate(world,source)
	checks += 1
	for stripped:StringName in cache.PROJECTILE_STRIP_NODES:
		if b.get_node_or_null(NodePath(stripped)) != null:
			failures += 1
			print("SCENE_STRIP_NODE_PRESENT ",stripped)
	compare(a,b,a,b,"before_ready")
	a.process_mode = Node.PROCESS_MODE_DISABLED
	b.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(a)
	world.add_child(b)
	# Parent sibling naming is intentionally unique; compare all other state.
	b.name = a.name + "_paired"
	compare(a,b,a,b,"after_ready")
	var c:Node = source.instantiate()
	cache.strip_projectile_nodes(c,strip_sync)
	var d:Node = cache.instantiate(world,source)
	checks += 1
	if a.get_instance_id() == b.get_instance_id() or b.get_instance_id() == d.get_instance_id():
		failures += 1
	for path:String in ["CollisionShape2D","hitbox/CollisionShape2D","hurtbox/CollisionShape2D"]:
		checks += 1
		var original_shared:bool = a.get_node(path).shape == c.get_node(path).shape
		var cached_shared:bool = b.get_node(path).shape == d.get_node(path).shape
		if original_shared != cached_shared:
			failures += 1
			print("SCENE_RESOURCE_ALIAS_DIFFERENCE ",path)
	c.free()
	d.free()
	var previous:PackedScene = cache.prepare(world,source).packed
	source.emit_changed()
	checks += 1
	if world.has_meta(cache.CACHE_KEY):
		failures += 1
	checks += 1
	if cache.prepare(world,source).packed == previous:
		failures += 1
	var start:int = Time.get_ticks_usec()
	for i:int in range(300):
		var n:Node = source.instantiate()
		n.free()
	var original_us:int = Time.get_ticks_usec()-start
	start = Time.get_ticks_usec()
	for i:int in range(300):
		var n:Node = cache.instantiate(world,source)
		n.free()
	var optimized_us:int = Time.get_ticks_usec()-start
	print("SCENE_CACHE_TEST ",JSON.stringify({"checks":checks,"failures":failures,"original_300_us":original_us,"optimized_300_us":optimized_us}))
	current_scene = null
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
