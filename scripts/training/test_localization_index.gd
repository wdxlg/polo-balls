extends SceneTree
var game:Node
var failures:int = 0
var checks:int = 0
func _initialize() -> void:
	call_deferred("run")
func check(value:bool,message:String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func collect(node:Node,result:Array[Node]) -> void:
	if node is Control:
		result.append(node)
	for child:Node in node.get_children():
		collect(child,result)
func verify(scene:Node,stage:String) -> void:
	var expected:Array[Node] = []
	collect(scene,expected)
	var actual:Array[Node] = []
	for node:Node in get_nodes_in_group(game.RUNTIME_LOCALIZATION_GROUP):
		if node == scene or scene.is_ancestor_of(node):
			actual.append(node)
	check(expected == actual,"Index mismatch: " + stage)
func run() -> void:
	game = root.get_node("Game")
	var scene:Node = Node.new()
	root.add_child(scene)
	current_scene = scene
	var label:Label = Label.new()
	label.text = "Attack"
	label.tooltip_text = "Health"
	scene.add_child(label)
	game._ensure_runtime_localization_index()
	verify(scene,"initial")
	var container:Node = Node.new()
	scene.add_child(container)
	var dynamic_label:Label = Label.new()
	dynamic_label.text = "Speed"
	container.add_child(dynamic_label)
	var hidden:Label = Label.new()
	scene.add_child(hidden,false,Node.INTERNAL_MODE_BACK)
	var hidden_child:Label = Label.new()
	hidden.add_child(hidden_child)
	verify(scene,"dynamic and internal descendants")
	container.reparent(hidden)
	verify(scene,"move into internal subtree")
	container.reparent(scene)
	verify(scene,"move out of internal subtree")
	scene.remove_child(container)
	verify(scene,"detached")
	scene.add_child(container)
	verify(scene,"reattached")
	game.current_locale = "zh"
	game._refresh_runtime_localized_texts()
	var text:String = label.text
	var tooltip:String = label.tooltip_text
	game._localize_runtime_control_tree(scene,{})
	check(text == label.text and tooltip == label.tooltip_text,"Translation differs")
	label.text = "Health"
	game._refresh_runtime_localized_texts()
	check(label.text == game.translate_ui_text("Health"),"Dynamic text not refreshed")
	dynamic_label.free()
	verify(scene,"freed")
	for i:int in range(3000):
		scene.add_child(Node2D.new())
	for i:int in range(200):
		var l:Label = Label.new()
		l.text = "Health"
		scene.add_child(l)
	var start:int = Time.get_ticks_usec()
	for i:int in range(20):
		game._localize_runtime_control_tree(scene,{})
	var old_us:int = Time.get_ticks_usec()-start
	start = Time.get_ticks_usec()
	for i:int in range(20):
		game._refresh_runtime_localized_texts()
	var indexed_us:int = Time.get_ticks_usec()-start
	print("LOCALIZATION_INDEX_TEST ",JSON.stringify({"checks":checks,"failures":failures,"old_us":old_us,"indexed_us":indexed_us}))
	current_scene = null
	scene.free()
	quit(0 if failures == 0 else 1)
