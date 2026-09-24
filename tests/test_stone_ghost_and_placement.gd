extends "res://scripts/training/test_mc_new5.gd"
## Regression for World.create_ghost_ball: placeable Stone is StaticBody2D, not ball.
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(30.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.5).timeout
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	await clear_units()
	world.now_choose_char = "石头"
	var ghost:Node2D = world.create_ghost_ball()
	check(ghost != null and not ghost is CollisionObject2D,"Stone ghost is a harmless Node2D preview")
	if is_instance_valid(ghost):
		check(ghost.get_node_or_null("PreviewImage") is Sprite2D,"Stone ghost retains the real stone picture")
		ghost.queue_free()
	await process_frame
	game.create_ball_in_server("Team0","石头",center)
	await physics_frame
	var placed:StaticBody2D = null
	for node:Node in get_nodes_in_group("PlaceableObstacle"):
		if node.get_parent() == world and node is StaticBody2D and not node.is_queued_for_deletion():
			placed = node as StaticBody2D
			break
	check(placed != null,"placing Stone through the actual RPC facade creates static terrain")
	if placed != null:
		var entry:Dictionary = world._battle_setup.back()
		check(entry.get("kind","") == "obstacle" and entry.get("team","not-empty") == "","terrain stays neutral in saved layout")
		check(world._configured_manual_victory_side_count() == 0,"Stone never arms a victory side")
		var setup_id:int = int(placed.get_meta("battle_setup_id"))
		game._delete_char_at_authority(center)
		check(placed.is_queued_for_deletion() and world._find_battle_setup_entry(setup_id).is_empty(),"real right-click path deletes terrain and its layout entry")
	print("STONE_GHOST_RESULT checks=",checks," failures=",failures)
	finish(0 if failures == 0 else 1)
