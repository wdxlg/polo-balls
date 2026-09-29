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
	var parameters:VBoxContainer = world.control.settings_category_boxes.parameters
	var recording_panel:VBoxContainer = world.control.settings_category_boxes.recording
	check(chooser != null and chooser.get_parent().get_parent() == parameters, "framing option lives in Settings > Parameters")
	var background_row:Node = parameters.get_node_or_null("MapBackgroundRow")
	var framing_row:Node = chooser.get_parent() if chooser != null else null
	var framing_hint:Node = parameters.get_node_or_null("CompositionFeedback")
	check(background_row != null and framing_row != null and framing_row.get_index() == background_row.get_index() + 1 and framing_hint != null and framing_hint.get_index() == framing_row.get_index() + 1, "framing selector and hint sit immediately below background settings")
	check(recording_panel.find_child("RecordingComposition", true, false) == null, "recording-only settings have no framing selector")
	if chooser != null:
		chooser.select(1)
		chooser.item_selected.emit(1)
		check(recorder.get_composition() == recorder.preferences.FOLLOW, "settings switch saves selection")
		check(recorder.PreferencesScript.new("user://composition_visual_smoke.cfg").get_composition() == recorder.preferences.FOLLOW, "selection survives reload")
		await settle(0.3)
		check(recorder.is_idle() and recorder._player_composition_mode == recorder.preferences.FOLLOW and recorder._player_camera == world.camera_2d, "selected framing changes the real player camera even when not recording")
	var dest:String = "user://recordings/composition_visual_smoke"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest))
	check(recorder.set_composition(recorder.preferences.FULL), "select full map without recording")
	await settle(0.3)
	var full_zoom:float = world.camera_2d.zoom.x
	check(recorder.set_composition(recorder.preferences.FOLLOW), "select combat tracking without recording")
	await settle(0.4)
	# The rotation duel can take a moment to spawn or close the initial distance.
	# Wait for an actual framing change instead of testing a transient empty map.
	var zoom_deadline:int = Time.get_ticks_msec() + 4000
	while world.camera_2d.zoom.x <= full_zoom + 0.1 and Time.get_ticks_msec() < zoom_deadline:
		await settle(0.1)
	check(recorder.is_idle() and world.camera_2d.zoom.x > full_zoom + 0.1, "gameplay framing visibly zooms toward combat before recording")
	for value:int in [recorder.preferences.FULL, recorder.preferences.FOLLOW, recorder.preferences.FOLLOW_OVERVIEW]:
		check(recorder.set_composition(value), "save composition %d" % value)
		await settle(0.15)
		check(recorder._player_composition_mode == value, "player camera follows chosen layout %d before recording" % value)
		check(is_instance_valid(recorder._player_overview_layer) == (value == recorder.preferences.FOLLOW_OVERVIEW), "player inset follows overview setting %d" % value)
		if value == recorder.preferences.FOLLOW_OVERVIEW:
			check(recorder._player_overview_layer.visible and recorder._player_overview_viewport.world_2d == root.world_2d, "full-map inset is rendered on actual game window")
		var player_before:Image = root.get_texture().get_image()
		check(player_before != null and player_before.save_png(dest.path_join(["full", "follow", "follow_overview"][value] + "_game.png")) == OK, "non-recording player frame available for layout %d" % value)
		check(recorder.start_live(), "start layout %d" % value)
		await settle(3.0 if OS.has_environment("POLO_COMPOSITION_VIDEO") else 1.1)
		if chooser != null: check(chooser.disabled, "settings locked during capture")
		# A moving battle camera may pan, zoom or switch target between the video
		# tick and this assertion. Compare the exact player transform sampled at
		# capture time, not the later main-window transform.
		var at_capture:Transform2D = recorder._last_player_capture_transform
		var zh_transform:Transform2D = recorder._sim_viewport.canvas_transform
		var en_transform:Transform2D = recorder._secondary._sim_viewport.canvas_transform
		check(recorder._last_player_capture_frame >= Engine.get_process_frames() - 8 and zh_transform.origin.distance_to(at_capture.origin) < 0.01 and zh_transform.x.distance_to(at_capture.x) < 0.001, "ZH video uses that same player camera frame without double zoom")
		check(en_transform.origin.distance_to(at_capture.origin) < 0.01 and en_transform.x.distance_to(at_capture.x) < 0.001, "EN video mirrors the same player camera frame")
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
	# Right-click SIM must use the same live framing on each newly calculated
	# battle frame as left-click LIVE (not an additional recorder-only zoom).
	world.reset()
	await settle(0.1)
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	world._enqueue_rotation_character("我的世界", "钻石剑", world._rotation_spawn_position("left"), "left", "res://scenes/characters/我的世界/钻石剑.tscn")
	world._enqueue_rotation_character("我的世界", "木剑", world._rotation_spawn_position("right"), "right", "res://scenes/characters/我的世界/木剑.tscn")
	world._update_special_training_modes(0.0)
	check(recorder.set_composition(recorder.preferences.FOLLOW), "select tracking for fixed-clock SIM")
	await settle(0.15)
	var offline_started:bool = recorder.start_simulated()
	check(offline_started, "start current-scene offline tracking")
	if offline_started:
		await settle(0.3)
		check(recorder._frame_index >= 3 and recorder._player_composition_mode == recorder.preferences.FOLLOW, "offline battle advances with the player camera")
		var sim_view:Transform2D = recorder._sim_viewport.canvas_transform
		var at_sim_capture:Transform2D = recorder._last_player_capture_transform
		check(sim_view.origin.distance_to(at_sim_capture.origin) < 0.01 and sim_view.x.distance_to(at_sim_capture.x) < 0.001, "right-click video reuses actual game framing without double zoom")
		recorder.stop()
		await wait_idle()
	world.queue_free()
	await process_frame
	game.Game_Settings = saved
	print("COMPOSITION_VISUAL: %d checks / %d failures" % [checks, failures])
	quit(1 if failures else 0)
