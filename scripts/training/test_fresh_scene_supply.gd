extends SceneTree
var failures:int = 0
var supply:RefCounted
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
		if key in ["_external_directional_gravity_hop_rng","_visual_facing_last_image_id"]:
			continue
		checks += 1
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
	var cache:Script = load("res://classes/fresh_scene_supply.gd")
	var source:PackedScene = load("res://scenes/shooter/knife.tscn")
	var world:Node2D = Node2D.new()
	root.add_child(world)
	current_scene = world
	seed(9224)
	var expected_random:int = randi()
	seed(9224)
	supply = cache.new()
	supply.start(source,128)
	var deadline:int = Time.get_ticks_msec()+5000
	while supply.count()<128 and Time.get_ticks_msec()<deadline:
		await process_frame
	checks += 1
	if randi() != expected_random:
		failures += 1
		print("SCENE_GLOBAL_RNG_CHANGED")
	var a:Node = source.instantiate()
	var b:Node = supply.take()
	compare(a,b,a,b,"before_ready")
	a.process_mode = Node.PROCESS_MODE_DISABLED
	b.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(a)
	world.add_child(b)
	# Parent sibling naming is intentionally unique; compare all other state.
	b.name = a.name + "_paired"
	compare(a,b,a,b,"after_ready")
	var start:int = Time.get_ticks_usec()
	for i:int in range(100):
		var n:Node = source.instantiate()
		n.free()
	var original_us:int = Time.get_ticks_usec()-start
	while supply.count()<128:
		await process_frame
	start = Time.get_ticks_usec()
	for i:int in range(100):
		var n:Node = supply.take()
		n.free()
	var optimized_us:int = Time.get_ticks_usec()-start
	print("FRESH_SUPPLY_TEST ",JSON.stringify({"checks":checks,"failures":failures,"original_100_us":original_us,"optimized_100_us":optimized_us}))
	supply.close()
	current_scene = null
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
