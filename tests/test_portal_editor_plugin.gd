extends SceneTree
var failures:int = 0
var checks:int = 0
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var script:GDScript = load("res://addons/portal_map_editor/portal_tiles.gd")
	check(script != null and script.can_instantiate() and script.is_tool(),"portal tile script compiles as editor tool")
	check(script.get_instance_base_type() == "TileMapLayer","portal editing uses real native TileMapLayer")
	var cfg:ConfigFile = ConfigFile.new()
	cfg.load("res://project.godot")
	check(not cfg.get_value("editor_plugins","enabled",PackedStringArray()).has("res://addons/portal_map_editor/plugin.cfg"),"old input/overlay plugin disabled")
	var source:String = FileAccess.get_file_as_string("res://addons/portal_map_editor/portal_tiles.gd")
	check(not source.contains("func _process") and not source.contains("queue_redraw"),"paint layers have no per-frame synchronization or redraw loop")
	var legacy:String = FileAccess.get_file_as_string("res://addons/portal_map_editor/portal_gate_node.gd")
	check(not legacy.contains("func _process"),"legacy markers cannot keep polling after script reload")
	var brush:TileSet = load("res://addons/portal_map_editor/portal_brush.tres")
	check(brush != null and brush.get_source_count() == 1 and brush.tile_size == Vector2i(16,16) and brush.get_source(0).get_tiles_count() == 2,"native TileMap atlas contains blue and red brushes")
	var custom:Array[String] = []
	for property:Dictionary in script.get_script_property_list():
		if int(property.usage) & PROPERTY_USAGE_EDITOR and str(property.name) not in ["script"]:
			custom.append(str(property.name))
	check(custom.size() == 2 and custom.has("pass_mode") and custom.has("direct_connection"),"only pass mode and direct connection are exposed as portal settings")
	print("EDITOR_PLUGIN checks=",checks," failures=",failures)
	quit(1 if failures else 0)
