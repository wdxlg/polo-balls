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
	var buttons:Array = []
	for child in panel.get_children():
		if child is HBoxContainer:
			for inner in child.get_children():
				if inner is Button: buttons.append(inner.text)
	check(buttons == ["打开", "设置"], "recording panel keeps exactly the open and set buttons: " + str(buttons))
	check(panel.tail_spin != null and is_equal_approx(panel.tail_spin.value, 5.0) and is_equal_approx(recorder.get_tail_seconds(), 5.0), "post-match tail defaults to 5 seconds")
	panel.tail_spin.value = 2.5
	check(is_equal_approx(recorder.get_tail_seconds(), 2.5) and is_equal_approx(prefs_script.new(config_path).get_tail_seconds(), 2.5), "tail seconds saved and reloaded from disk")
	panel.tail_spin.value = -3.0
	check(is_equal_approx(recorder.get_tail_seconds(), 0.0) and is_equal_approx(panel.tail_spin.value, 0.0), "negative tail clamps to zero")
	panel.tail_spin.value = 5.0
	var custom:String = ProjectSettings.globalize_path("user://录制路径测试 中文 空格/%d" % Time.get_ticks_usec())
	panel.folder_dialog.dir_selected.emit(custom)
	check(recorder.get_output_directory() == custom, "folder picker selection saves Unicode path")
	check(DirAccess.dir_exists_absolute(custom), "folder created and write probe succeeds")
	check(FileAccess.file_exists(config_path), "preference saved to disk")
	var reloaded:RefCounted = prefs_script.new(config_path)
	check(reloaded.get_directory() == custom, "new instance reloads saved directory")
	check(is_equal_approx(reloaded.get_tail_seconds(), 5.0), "saving the directory keeps the tail setting in the same file")
	check(panel.path_edit.text == custom, "path shown unmodified in LineEdit")
	var blocker:String = custom.path_join("not_a_directory.txt")
	var handle := FileAccess.open(blocker, FileAccess.WRITE)
	handle.store_string("fixture")
	handle.close()
	panel.path_edit.text = blocker
	panel.path_edit.text_submitted.emit(blocker)
	check(recorder.get_output_directory() == custom, "invalid file-as-directory leaves old path intact")
	check(panel.feedback.text.contains("文件"), "invalid path reports specific problem")
	panel.path_edit.text = "relative/folder"
	panel.path_edit.text_submitted.emit("relative/folder")
	check(recorder.get_output_directory() == custom and panel.feedback.text.contains("完整"), "relative path refused")
	panel.path_edit.text = custom
	panel.path_edit.text_submitted.emit(custom)
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
		check(not recorder.set_tail_seconds(9.0) and is_equal_approx(recorder.get_tail_seconds(), 5.0), "cannot change tail seconds during an active session")
		check(recorder.get_tail_left() < 0.0, "undecided match has no tail countdown")
		# Real match end: World's victory bell rings -> LIVE keeps recording tail seconds of game time, then stops by itself.
		recorder.preferences.tail_seconds = 1.0
		recorder._tail_seconds = 1.0
		var frames_at_bell:int = recorder._frame_index
		world._victory_bell_played = true
		await settle(0.3)
		check(recorder.is_recording() and recorder.get_tail_left() >= 0.0 and recorder.get_tail_left() < 1.0, "victory bell starts the post-match countdown while still recording")
		var auto_end:int = Time.get_ticks_msec() + 6000
		while recorder.is_recording() and Time.get_ticks_msec() < auto_end: await settle(0.05)
		check(not recorder.is_recording(), "LIVE stops on its own after the configured tail")
		var tail_frames:int = recorder._frame_index - frames_at_bell
		check(tail_frames >= 48 and tail_frames <= 90, "tail recorded about one second of frames after the bell: %d" % tail_frames)
		world._victory_bell_played = false
		recorder.preferences.tail_seconds = 5.0
		await wait_idle()
		check(recorder.get_mode() == 0 and not recorder.is_busy(), "automatic stop finalizes without another toolbar click")
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
	panel.path_edit.text = prefs_script.DEFAULT_DIRECTORY
	panel.path_edit.text_submitted.emit(panel.path_edit.text)
	check(recorder.get_output_directory() == ProjectSettings.globalize_path("user://recordings"), "reset default saved correctly")
	check(prefs_script.new(config_path).get_directory() == recorder.get_output_directory(), "default survives reload")
	DirAccess.remove_absolute(config_path)
	world.queue_free()
	await process_frame
	await process_frame
	game.Game_Settings = saved
	print("RECORDING_PATHS: %d checks / %d failures" % [checks, failures])
	quit(1 if failures else 0)
