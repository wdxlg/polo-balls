extends "res://tests/test_rotation_frames_challenge.gd"
## Rotation hides XX VS XX (screen title and matchup panels); the top HUD shows the clock only.

func run() -> void:
	create_timer(60.0,true,false,true).timeout.connect(func(): quit(2))
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	var saved_storage:String = game._settings_storage_path
	var temp_settings:String = OS.get_temp_dir().path_join("rotation_time_only_hud_settings.cfg")
	game._settings_storage_path = temp_settings
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Boss_Intro = false
	game.Game_Settings.Local_Hitstop = false
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
	game.Game_Settings.Rotation_Multi_Characters = false
	game.Game_Settings.Rotation_Blue_Count = 1
	game.Game_Settings.Rotation_Red_Count = 1
	world.control.team.show()
	world._battle_setup_next_id = 1
	# One unit per side is the case that used to open the 1v1 matchup panels.
	for side:String in ["left","right"]:
		world._enqueue_rotation_character("",("Blue" if side=="left" else "Red")+"0",world._rotation_spawn_position(side),side,"res://scenes/ball.tscn")
	world.control.hide()
	world.control.team.hide()
	world._update_special_training_modes(0.0)
	await create_timer(2.0).timeout
	var huds:Array = []
	for n:Node in world.find_children("*","",true,false):
		if n.get_script() != null and str(n.get_script().resource_path).ends_with("duel_top_hud.gd") and not n.is_mirror():
			huds.append(n)
	check(huds.size() == 1,"one top hud")
	check(not world.versus_label.visible,"screen XX VS XX hidden")
	check(String(world.versus_label.text).is_empty(),"versus text empty")
	if huds.size() == 1:
		var hud:Node = huds[0]
		check(hud.visible,"top hud visible for the clock")
		check(hud.sides.is_empty(),"no matchup sides")
		check(not hud._matchup_panels_visible(),"matchup panels hidden")
		check(hud._center_panel_wanted(),"centre clock panel wanted")
		check(is_equal_approx((hud._panel_rects()[1] as Rect2).size.y,hud.TIME_ONLY_PANEL_HEIGHT),"time-only centre height")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_temp_dir().path_join("rotation_time_only_hud.png"))
	world.reset()
	await process_frame
	world.queue_free()
	await process_frame
	game.Game_Settings = saved
	game._settings_storage_path = saved_storage
	if FileAccess.file_exists(temp_settings): DirAccess.remove_absolute(temp_settings)
	print("ROTATION_TIME_ONLY_HUD checks=%d failures=%d" % [checks,failures])
	quit(1 if failures > 0 else 0)
