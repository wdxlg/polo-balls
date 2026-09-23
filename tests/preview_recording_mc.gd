extends "res://tests/test_battle_recording.gd"
## Real character/audio smoke, separate from deterministic tone tests.
func run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(2))
	game = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode_Type = "rotation"
	game.Game_Settings.Rotation_Match_Type = "duel"
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Boss_Intro = false
	game.Game_Settings.Map_Background = "blue"
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world, CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	await settle(0.8)
	world.reset()
	await settle()
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	world.control.team.show()
	world._enqueue_rotation_character("我的世界", "钻石剑", world._rotation_spawn_position("left"), "left", "res://scenes/characters/我的世界/钻石剑.tscn")
	world._enqueue_rotation_character("我的世界", "木剑", world._rotation_spawn_position("right"), "right", "res://scenes/characters/我的世界/木剑.tscn")
	world.control.team.hide()
	world.control.show()
	world.control.settings_bar.show()
	world._update_special_training_modes(0.0)
	controls = world.control._battle_record_controls
	recorder = controls.recorder
	check(recorder.start_live(), "real MC match starts clean recording")
	await settle(8.0)
	var peak:float = recorder._audio.peak
	recorder.stop()
	await wait_idle()
	check(peak > 0.0001, "real MC battle produces gameplay audio without injected tones")
	check(not controls.last_output.is_empty(), "real match MP4 saved")
	var f := FileAccess.open("user://recordings/test_mc_recording_manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"path":ProjectSettings.globalize_path(controls.last_output),"peak":peak,"frames":recorder._frame_index}))
	f.close()
	print("MC_RECORDING_PATH=",ProjectSettings.globalize_path(controls.last_output))
	world.queue_free()
	await process_frame
	await process_frame
	game.Game_Settings = saved
	print("MC_RECORDING: %d checks / %d failures" % [checks, failures])
	quit(1 if failures else 0)
