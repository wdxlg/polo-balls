extends "res://tests/test_battle_recording.gd"
func wall_wait(seconds:float) -> void:
	var until:int = int(Time.call("get_wall_ticks_usec")) + int(seconds*1e6)
	while int(Time.call("get_wall_ticks_usec")) < until: await RenderingServer.frame_post_draw
func run() -> void:
	game = root.get_node("Game")
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Mode = false
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.free()
	controls=world.control._battle_record_controls;recorder=controls.recorder
	recorder.preferences=recorder.PreferencesScript.new("user://test_offline_lifecycle.cfg")
	recorder.preferences.directory="user://recordings/offline_lifecycle"
	world.control.team.hide()
	world.create_char("Team0","牛",Vector2(-80,0))
	world.create_char("Team1","木剑",Vector2(80,0))
	await wall_wait(.3)
	check(recorder.start_simulated(),"offline lifecycle session starts")
	while recorder._frame_index<12:await RenderingServer.frame_post_draw
	var window_mode:int=DisplayServer.window_get_mode()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	var min_begin:int=recorder._frame_index
	await wall_wait(.5)
	check(recorder._frame_index>min_begin,"offscreen capture keeps advancing while the player window is minimized")
	DisplayServer.window_set_mode(window_mode)
	game.stop_game(false)
	await wall_wait(.1)
	var before:int=recorder._frame_index
	var samples:int=recorder._audio.samples_written
	var tick:int=Time.get_ticks_usec()
	await wall_wait(.3)
	check(recorder._frame_index==before and recorder._audio.samples_written==samples,"offline pause advances neither video nor PCM")
	check(Time.get_ticks_usec()==tick,"tick-based abilities freeze with offline pause")
	game.continue_game()
	await wall_wait(1.2)
	check(recorder._frame_index>before,"offline capture continues after the pause/countdown")
	var original_fps:int=recorder._offline._saved.max_fps
	var original_vsync:int=recorder._offline._saved.vsync
	# The scene is deliberately removed in mid-recording, not through normal mux completion.
	game.stop_game(false)
	world.queue_free()
	await process_frame
	await process_frame
	check(Engine.call("get_recording_fixed_fps")==-1 and not AudioServer.call("is_offline_audio"),"scene exit restores native clock and hardware audio")
	check(Engine.max_fps==original_fps and DisplayServer.window_get_vsync_mode()==original_vsync,"scene exit restores rendering limits")
	check(not paused,"scene exit restores original pause policy")
	check(not game.stop_background.visible and not game.stop_text.visible,"scene exit while paused restores prior pause UI visibility")
	print("OFFLINE_LIFECYCLE: %d checks / %d failures" % [checks,failures])
	quit(1 if failures else 0)
