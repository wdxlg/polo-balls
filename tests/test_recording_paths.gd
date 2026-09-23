extends "res://tests/test_battle_recording.gd"
func run() -> void:
	create_timer(100.0, true, false, true).timeout.connect(func(): quit(2))
	game = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Boss_Intro = false
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world, CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	await settle(0.8)
	world.control.ui_parallax_enabled = false
	world.control.show()
	world.control.settings_bar.show()
	controls = world.control._battle_record_controls
	recorder = controls.recorder
	button = controls.button
	var prefs_script = load("res://scripts/ui/battle_record_preferences.gd")
	var config_path:String = "user://test_recording_paths_%d.cfg" % Time.get_ticks_usec()
	recorder.preferences = prefs_script.new(config_path)
	var panel:Node = world.control.settings_category_boxes.recording.get_node("RecordingSettings")
	check(panel.recorder == recorder, "settings tab uses actual recorder")
	check(world.control.settings_tab_buttons.recording.text == "录制", "recording settings tab labeled")
	check(panel.folder_dialog.file_mode == FileDialog.FILE_MODE_OPEN_DIR and panel.folder_dialog.use_native_dialog, "native folder selector configured")
	var custom:String = ProjectSettings.globalize_path("user://录制路径测试 中文 空格/%d" % Time.get_ticks_usec())
	panel.folder_dialog.dir_selected.emit(custom)
	check(recorder.get_output_directory() == custom, "folder picker selection saves Unicode path")
	check(DirAccess.dir_exists_absolute(custom), "folder created and write probe succeeds")
	check(FileAccess.file_exists(config_path), "preference saved to disk")
	var reloaded:RefCounted = prefs_script.new(config_path)
	check(reloaded.get_directory() == custom, "new instance reloads saved directory")
	check(panel.path_edit.text == custom, "path shown unmodified in LineEdit")
	var blocker:String = custom.path_join("not_a_directory.txt")
	var handle := FileAccess.open(blocker, FileAccess.WRITE)
	handle.store_string("fixture")
	handle.close()
	panel.path_edit.text = blocker
	panel.save_button.pressed.emit()
	check(recorder.get_output_directory() == custom, "invalid file-as-directory leaves old path intact")
	check(panel.feedback.text.contains("文件"), "invalid path reports specific problem")
	panel.path_edit.text = "relative/folder"
	panel.save_button.pressed.emit()
	check(recorder.get_output_directory() == custom and panel.feedback.text.contains("完整"), "relative path refused")
	panel.path_edit.text = custom
	panel.save_button.pressed.emit()
	if DisplayServer.get_name() != "headless":
		# Reproduce user's entry route: team open + Esc paused -> toolbar left click.
		world.control.game_setting.hide()
		world.control.team.show()
		game.stop_game(false)
		await settle(0.2)
		await click(MOUSE_BUTTON_LEFT)
		check(not world.control.team.visible, "LIVE start closes placement panel")
		check(not game.now_stop_state, "LIVE start resumes explicit Esc pause")
		await settle(1.8)
		check(recorder._frame_index > 0, "real toolbar path now produces frames instead of empty MP4")
		check(recorder._out_path.begins_with(custom + "/"), "session writes to selected directory")
		check(not recorder.set_output_directory(custom.path_join("other")), "cannot change active session directory")
		check(recorder.get_output_directory() == custom, "active session destination stable")
		await click(MOUSE_BUTTON_LEFT)
		await wait_idle()
		check(controls.last_output.begins_with(custom + "/") and controls.last_output.ends_with(".mp4"), "custom Unicode directory receives final MP4")
		check(FileAccess.file_exists(controls.last_output), "saved custom MP4 exists")
		var manifest := FileAccess.open("user://test_recording_paths_manifest.json", FileAccess.WRITE)
		manifest.store_string(JSON.stringify({"path":controls.last_output,"frames":recorder._frame_index}))
		manifest.close()
		# A user pausing AFTER start still skips all frames; don't fake an encoder fault.
		check(recorder.start_live(), "direct recorder can wait for gameplay")
		game.stop_game(false)
		await settle(0.5)
		controls.refresh()
		check(button.text == "待录", "zero-frame wait has explicit amber state")
		recorder.stop()
		await wait_idle()
		check(recorder.get_last_error().contains("没有录到有效画面") and recorder.get_last_error().contains("暂停"), "zero-frame cancellation identifies pause, not encoder or permission")
		check(not FileAccess.file_exists(recorder._video_path) and not FileAccess.file_exists(recorder._audio_path), "zero-frame session cleans only its empty temporary files")
		game.continue_game()
		await settle(1.0)
		world.control.game_setting.show()
		world.control._show_settings_category("recording")
		panel.path_edit.text = custom
		await settle(0.3)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://test_recording_settings.png")
	panel.reset_button.pressed.emit()
	check(recorder.get_output_directory() == ProjectSettings.globalize_path("user://recordings"), "reset default saved correctly")
	check(prefs_script.new(config_path).get_directory() == recorder.get_output_directory(), "default survives reload")
	DirAccess.remove_absolute(config_path)
	world.queue_free()
	await process_frame
	await process_frame
	game.Game_Settings = saved
	print("RECORDING_PATHS: %d checks / %d failures" % [checks, failures])
	quit(1 if failures else 0)
