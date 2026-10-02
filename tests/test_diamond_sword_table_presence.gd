extends "res://tests/test_rotation_frames_challenge.gd"
## The smithing table only exists while a diamond sword is on the field:
## rotation rounds that have not entered must not leave it in the map centre.

const SWORD_SCENE:String = "res://scenes/characters/我的世界/钻石剑.tscn"

func live_tables() -> int:
	var count:int = 0
	for node:Node in get_tree_nodes(&"MinecraftSmithingTable"):
		if is_instance_valid(node) and not node.is_queued_for_deletion(): count += 1
	return count

func get_tree_nodes(group:StringName) -> Array[Node]:
	return get_nodes_in_group(group)

func wait_frames(frames:int = 6) -> void:
	for _i:int in range(frames): await process_frame

func run() -> void:
	create_timer(60.0,true,false,true).timeout.connect(func(): quit(2))
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	var temp_settings:String = OS.get_temp_dir().path_join("diamond_sword_table_settings.cfg")
	# Game saves settings again on exit, so the redirect stays until quit.
	game._settings_storage_path = temp_settings
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Boss_Intro = false
	game.Game_Settings.Local_Hitstop = false
	game.Game_Settings.Map_Background = "blue"
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world._mc_prewarmer = null
	await process_frame
	game.Game_Settings.Training_Mode_Type = "rotation"
	game.Game_Settings.Rotation_Match_Type = "normal"
	game.Game_Settings.Training_Wheel_Battle = false
	game.Game_Settings.Rotation_Multi_Characters = true
	game.Game_Settings.Rotation_Blue_Count = 1
	game.Game_Settings.Rotation_Red_Count = 1
	world.control.team.show()
	world._battle_setup_next_id = 1
	world._enqueue_rotation_character("","钻石剑",world._rotation_spawn_position("left"),"left",SWORD_SCENE,1)
	world._enqueue_rotation_character("","Red0",world._rotation_spawn_position("right"),"right","res://scenes/ball.tscn",1)
	world._enqueue_rotation_character("","Blue1",world._rotation_spawn_position("left"),"left","res://scenes/ball.tscn",2)
	world._enqueue_rotation_character("","Red1",world._rotation_spawn_position("right"),"right","res://scenes/ball.tscn",2)
	await wait_frames()
	world._rotation_preview_round = 1
	world._refresh_rotation_formation_preview()
	await wait_frames()
	check(live_tables() == 1,"previewing the sword round shows one table")
	world._rotation_preview_round = 2
	world._refresh_rotation_formation_preview()
	await wait_frames()
	check(live_tables() == 0,"previewing a round without the sword removes the table")
	world._rotation_preview_round = 1
	world._refresh_rotation_formation_preview()
	await wait_frames()
	check(live_tables() == 1,"table returns with the sword preview")
	# Remove the sword round entirely: nothing of it may linger.
	for record:Dictionary in world._rotation_rosters["left"].duplicate():
		if String(record.char) == "钻石剑": world.delete_rotation_queue_setup_id(int(record.id),"left")
	world._refresh_rotation_formation_preview()
	await wait_frames()
	check(live_tables() == 0,"deleted sword leaves no table")
	world.control.hide()
	world.control.team.hide()
	world.reset()
	await process_frame
	world.queue_free()
	await process_frame
	game.Game_Settings = saved
	if FileAccess.file_exists(temp_settings): DirAccess.remove_absolute(temp_settings)
	print("DIAMOND_TABLE_PRESENCE checks=%d failures=%d" % [checks,failures])
	quit(1 if failures > 0 else 0)
