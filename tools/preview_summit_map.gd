extends SceneTree
## Open the real battle scene with this local visual theme; don't rewrite saved settings.
func _initialize() -> void: open_map.call_deferred()
func open_map() -> void:
	var game:Node = root.get_node("Game")
	game.Game_Settings.Map_Background = "summit"
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	DisplayServer.window_set_title("山巅 · 古竞技场 | Godot 实机预览")
	print("SUMMIT_LIVE_READY style=",world.map_background_style()," original_controls=true")
