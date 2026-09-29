extends SceneTree
var checks:int = 0
var failures:int = 0
var world:Node
var game:Node
var controls:Node
var recorder:Node
var button:Button
var outputs:Array = []
func _initialize() -> void: call_deferred("run")
func check(ok:bool, label:String) -> void:
	checks += 1
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
func settle(seconds:float = 0.1) -> void:
	await create_timer(seconds, true, false, true).timeout
func click(which:int) -> void:
	var point:Vector2 = button.get_global_transform_with_canvas() * (button.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for down:bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = which
		event.pressed = down
		root.push_input(event, true)
		await process_frame
func wait_idle() -> void:
	var end:int = Time.get_ticks_msec() + 30000
	while recorder.is_busy() and Time.get_ticks_msec() < end: await settle()
	check(not recorder.is_busy(), "encoder finishes without stuck state")
	controls.result_dialog.hide()
func run() -> void:
	create_timer(100.0, true, false, true).timeout.connect(func(): print("RECORD_TEST_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Boss_Intro = false
	game.Game_Settings.Map_Background = "blue"
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world, CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	await settle(0.8)
	world.control.ui_parallax_enabled = false
	world.control.visible = true
	world.control.settings_bar.visible = true
	controls = world.control._battle_record_controls
	recorder = controls.recorder
	# Never read/write the user's persisted choice during automated capture tests.
	DirAccess.remove_absolute("user://test_battle_recording.cfg")
	recorder.preferences = recorder.PreferencesScript.new("user://test_battle_recording.cfg")
	recorder.preferences.directory = "user://recordings/battle_recording_regression"
	button = controls.button
	check(is_instance_valid(recorder), "recorder instantiated by actual UI scene")
	check(button.is_connected("button_up", world.control._on_record_button_up), "left signal wired")
	check(button.is_connected("gui_input", world.control._on_record_button_gui_input), "right signal wired")
	check(button.button_mask == MOUSE_BUTTON_MASK_LEFT, "right button never triggers left toggle")
	check(button.process_mode == Node.PROCESS_MODE_ALWAYS, "record button responds while paused")
	check(button.tooltip_text.contains("user://recordings"), "output location visible in tooltip")
	world.reset()
	await settle()
	# Exercise the scene signal even in headless mode (no rendered hit testing).
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	button.gui_input.emit(right)
	check(recorder.is_idle(), "empty current world does not enter offline recording")
	check(controls.result_dialog.visible and not controls.last_message.is_empty(), "invalid SIM shows actionable message")
	controls.result_dialog.hide()
	if DisplayServer.get_name() == "headless":
		button.button_up.emit()
		check(recorder.is_idle() and recorder.get_last_error().contains("无渲染"), "headless rejected with reason")
		controls.result_dialog.hide()
	else:
		root.size = Vector2i(540, 960)
		# Keep the actual project logical viewport (1080x1920), only the window is small.
		await settle(0.5)
		world.control.apply_portrait_layout()
		recorder.recording_finished.connect(func(path:String, frames:int):
			outputs.append({"path":ProjectSettings.globalize_path(path), "outputs":recorder.last_outputs.duplicate(), "frames":frames, "fps":recorder._output_fps, "audio_samples":recorder._audio.samples_written, "audio_peak":recorder._audio.peak, "game_time":recorder._game_time, "tail":recorder._sim_tail_left, "scale":Engine.time_scale}))
		var audio_bus:int = AudioServer.get_bus_index(&"GameplayRecord")
		var effects_before:int = AudioServer.get_bus_effect_count(audio_bus)
		var game_tone:AudioStreamPlayer = make_tone(440.0, &"GameplayRecord")
		var ui_tone:AudioStreamPlayer = make_tone(1760.0, &"UI")
		var marker := ColorRect.new()
		marker.color = Color.MAGENTA
		marker.position = Vector2(40, 120)
		marker.size = Vector2(180, 180)
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		world.control.get_parent().add_child(marker)
		var chart := ColorRect.new()
		chart.color = Color(0.2, 0.4, 0.6)
		chart.position = world.camera_2d.get_screen_center_position() - Vector2(10, 10)
		chart.size = Vector2(20, 20)
		chart.z_index = 900
		chart.mouse_filter = Control.MOUSE_FILTER_IGNORE
		world.add_child(chart)
		await click(MOUSE_BUTTON_LEFT)
		check(recorder.get_mode() == 1, "actual left mouse starts LIVE")
		check(button.modulate.g < 0.5, "active button turns red")
		await settle(1.0)
		check(recorder._capture_size == Vector2i(1080, 1920), "native Full HD render despite half-size window")
		check(recorder._sim_viewport.use_hdr_2d == recorder._viewport_uses_hdr(root), "capture matches game HDR rendering")
		var capture:Image = recorder._grab_image()
		var main_image:Image = root.get_texture().get_image()
		var main_point:Vector2 = root.get_final_transform() * (marker.get_global_transform_with_canvas() * (marker.size * 0.5))
		var output_point:Vector2 = main_point * Vector2(capture.get_size()) / Vector2(main_image.get_size())
		var ui_pixel:Color = main_image.get_pixelv(Vector2i(main_point))
		var output_pixel:Color = capture.get_pixelv(Vector2i(output_point))
		check(ui_pixel.r > 0.8 and ui_pixel.b > 0.8 and ui_pixel.g < 0.2, "UI witness really exists in player window")
		check(not (output_pixel.r > 0.8 and output_pixel.b > 0.8 and output_pixel.g < 0.2), "toolbar canvas and UI witness excluded from recording")
		var chart_point:Vector2 = recorder._sim_viewport.canvas_transform * (chart.global_position + chart.size * 0.5)
		check(chart_point.distance_to(Vector2(540, 960)) < 5.0, "camera framing stays centered at native output resolution")
		var color:Color = capture.get_pixelv(Vector2i(chart_point))
		check(absf(color.r - 0.2) < 0.03 and absf(color.g - 0.4) < 0.03 and absf(color.b - 0.6) < 0.03, "known sRGB chart preserves color without double gamma")
		capture.save_png("user://recordings/test_clean_fullhd.png")
		main_image.save_png("user://recordings/test_player_with_ui.png")
		var beacon:AudioStreamPlayer = make_tone(880.0, &"GameplayRecord")
		chart.color = Color.WHITE
		await settle(0.25)
		chart.color = Color(0.2, 0.4, 0.6)
		beacon.stop()
		await settle(0.2)
		game.stop_game()
		await settle(0.2)
		var before:int = recorder._frame_index
		var samples_before:int = recorder._audio.samples_written
		await settle(0.7)
		check(recorder._frame_index == before, "paused time is omitted from LIVE output")
		check(recorder._audio.samples_written == samples_before, "paused audio is omitted with video")
		game.continue_game()
		await settle(0.3)
		beacon.play()
		chart.color = Color.WHITE
		await settle(0.25)
		chart.color = Color(0.2, 0.4, 0.6)
		beacon.stop()
		await settle(0.2)
		check(recorder._frame_index > before, "recording resumes after Esc pause")
		game.stop_game()
		await settle(0.1)
		await click(MOUSE_BUTTON_LEFT)
		beacon.queue_free()
		check(recorder.get_mode() == 0, "actual left mouse stops LIVE while paused")
		await wait_idle()
		game.continue_game()
		check(AudioServer.get_bus_effect_count(audio_bus) == effects_before, "audio tap removed after LIVE")
		marker.queue_free()
		chart.queue_free()
		check(outputs[0].audio_peak > 0.01, "LIVE captured non-silent game sound")
		check(outputs.size() == 1 and not outputs[0].path.is_empty() and outputs[0].frames > 0, "LIVE wrote video frames")
		check(not button.disabled and button.modulate == Color.WHITE, "idle button restored after save")
		await settle(0.3)
		check(controls.output_path.text == ProjectSettings.globalize_path(controls.last_output), "saved path is not corrupted by runtime translation")
		# A real World with lightweight fighter fixtures, not a mocked recorder.
		game.Game_Settings.Training_Mode_Type = "rotation"
		game.Game_Settings.Rotation_Match_Type = "challenge"
		world.control.team.show()
		for side:String in ["left", "right"]:
			world._enqueue_rotation_character("", side, world._rotation_spawn_position(side), side, "res://scenes/ball.tscn")
		world.control.team.hide()
		world._update_special_training_modes(0.0)
		check(not world._rotation_rosters.left.is_empty(), "SIM fixture has a currently active queue battle")
		var bus:int = AudioServer.get_bus_index(&"GameplayRecord")
		var was_muted:bool = AudioServer.is_bus_mute(bus)
		var original_scale:float = Engine.time_scale
		await click(MOUSE_BUTTON_RIGHT)
		check(recorder.get_mode() == 2, "actual right mouse starts SIM only")
		await settle(1.2)
		check(recorder._frame_index > 0 and is_instance_valid(recorder._sim_viewport), "SIM captures offscreen frames")
		check(recorder._overlay_backdrop.visible, "SIM overlay visible to player")
		var image:Image = recorder._grab_image()
		check(image != null and not image.is_empty(), "SIM image readable")
		if image != null: image.save_png("user://recordings/test_sim_capture.png")
		check(not recorder._sim_match_over(), "queue in progress is not prematurely finished")
		recorder._overlay_abort.pressed.emit()
		await wait_idle()
		check(is_equal_approx(Engine.time_scale, original_scale), "abort restores time scale")
		check(AudioServer.is_bus_mute(bus) == was_muted, "abort restores audio mute state")
		check(not recorder._overlay_backdrop.visible and recorder._sim_viewport == null and recorder._resolve_viewport == null, "abort clears overlay and capture viewport")
		check(outputs.size() == 2 and not outputs[1].path.is_empty(), "SIM abort saves playable portion")
		await click(MOUSE_BUTTON_RIGHT)
		check(recorder.get_mode() == 2, "SIM can continue from its stopped current state after abort")
		await settle(0.4)
		world._rotation_finished = true
		await wait_idle()
		check(outputs.size() == 3 and not outputs[2].path.is_empty(), "SIM auto-finishes after series completion")
		check(is_equal_approx(Engine.time_scale, original_scale), "auto finish restores time scale")
		check(not button.disabled, "record button reusable after automatic finish")
		check(AudioServer.get_bus_effect_count(audio_bus) == effects_before, "audio tap removed after SIM and restart")
		check(outputs[1].audio_peak > 0.01 and outputs[2].audio_peak > 0.01, "SIM records non-silent game sound")
		game_tone.queue_free()
		ui_tone.queue_free()
		var manifest := FileAccess.open("user://recordings/test_recording_manifest.json", FileAccess.WRITE)
		manifest.store_string(JSON.stringify(outputs, "\t"))
		manifest.close()
		print("MANIFEST=", ProjectSettings.globalize_path("user://recordings/test_recording_manifest.json"))
	world.queue_free()
	await process_frame
	await process_frame
	game.Game_Settings = saved
	print("BATTLE_RECORDING: %d checks / %d failures" % [checks, failures])
	quit(1 if failures else 0)

func make_tone(frequency:float, bus:StringName) -> AudioStreamPlayer:
	var bytes := PackedByteArray()
	var rate:int = 48000
	bytes.resize(rate * 2)
	for i:int in range(rate):
		bytes.encode_s16(i * 2, int(sin(TAU * frequency * i / rate) * 6500.0))
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = rate
	sound.data = bytes
	sound.loop_mode = AudioStreamWAV.LOOP_FORWARD
	sound.loop_end = rate
	var player := AudioStreamPlayer.new()
	player.stream = sound
	player.bus = bus
	root.add_child(player)
	player.play()
	return player
