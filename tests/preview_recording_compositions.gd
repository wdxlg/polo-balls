extends "res://tests/test_battle_recording.gd"
## Rendered end-to-end comparison; runs all three saved UI compositions on one duel.
func run() -> void:
	create_timer(110.0, true, false, true).timeout.connect(func(): quit(2))
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
	root.size = Vector2i(540, 960)
	world.control.ui_parallax_enabled = false
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
	# Do not modify the player's real settings; this is a throwaway config file.
	recorder.preferences = recorder.PreferencesScript.new("user://composition_visual_smoke.cfg")
	var chooser:OptionButton = world.control.find_child("RecordingComposition", true, false) as OptionButton
	check(chooser != null and chooser.item_count == 3, "settings offers all three compositions")
	if chooser != null:
		chooser.select(1)
		chooser.item_selected.emit(1)
		check(recorder.get_composition() == recorder.preferences.FOLLOW, "settings switch saves selection")
		check(recorder.PreferencesScript.new("user://composition_visual_smoke.cfg").get_composition() == recorder.preferences.FOLLOW, "selection survives reload")
	var dest:String = "user://recordings/composition_visual_smoke"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest))
	for value:int in [recorder.preferences.FULL, recorder.preferences.FOLLOW, recorder.preferences.FOLLOW_OVERVIEW]:
		check(recorder.set_composition(value), "save composition %d" % value)
		check(recorder.start_live(), "start layout %d" % value)
		await settle(3.0 if OS.has_environment("POLO_COMPOSITION_VIDEO") else 1.1)
		if chooser != null: check(chooser.disabled, "settings locked during capture")
		var zh:Image = recorder._capture_viewport.get_texture().get_image()
		var en:Image = recorder._secondary._capture_viewport.get_texture().get_image()
		var label:String = ["full", "follow", "follow_overview"][value]
		var save_zh:String = dest.path_join(label + "_zh.png")
		var save_en:String = dest.path_join(label + "_en.png")
		check(zh != null and zh.get_size() == Vector2i(1080, 1920) and zh.save_png(save_zh) == OK, "ZH frame " + label)
		check(en != null and en.get_size() == Vector2i(1080, 1920) and en.save_png(save_en) == OK, "EN frame " + label)
		recorder.stop()
		await wait_idle()
		if chooser != null:
			await process_frame
			check(not chooser.disabled, "settings unlocked after capture")
		print("LAYOUT_PREVIEW=",ProjectSettings.globalize_path(save_zh))
		await settle(0.2)
	world.queue_free()
	await process_frame
	game.Game_Settings = saved
	print("COMPOSITION_VISUAL: %d checks / %d failures" % [checks, failures])
	quit(1 if failures else 0)
