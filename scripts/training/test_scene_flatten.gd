extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var original:PackedScene = load("res://scenes/shooter/knife.tscn")
	var proto:Node = original.instantiate()
	flatten_nodes(proto,proto)
	var flat:PackedScene = PackedScene.new()
	var err:int = flat.pack(proto)
	print("FLAT_PACK error=",err," original_nodes=",original.get_state().get_node_count()," flat_nodes=",flat.get_state().get_node_count())
	proto.free()
	ResourceSaver.save(flat,"res://scenes/shooter/knife_flat_probe.tscn")
	for scene:PackedScene in [original,flat]:
		var nodes:Array[Node] = []
		var started:int = Time.get_ticks_usec()
		for i:int in range(400):
			nodes.append(scene.instantiate())
		var instantiate_ms:float = float(Time.get_ticks_usec()-started)/1000.0
		started = Time.get_ticks_usec()
		for node:Node in nodes:
			node.free()
		print("FLAT_TIMING original=",scene==original," instantiate_400_ms=",instantiate_ms," free_400_ms=",float(Time.get_ticks_usec()-started)/1000.0)
	quit()

func flatten_nodes(node:Node,scene_root:Node) -> void:
	node.scene_file_path = ""
	if node != scene_root:
		node.owner = scene_root
	for child:Node in node.get_children():
		flatten_nodes(child,scene_root)
