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
	check(recorder.is_idle(), "empty SIM setup does not enter recording")
	check(controls.result_dialog.visible and not controls.last_message.is_empty(), "invalid SIM shows actionable message")
	controls.result_dialog.hide()
	if DisplayServer.get_name() == "headless":
		button.button_up.emit()
		check(recorder.is_idle() and recorder.get_last_error().contains("无渲染"), "headless rejected with reason")
		controls.result_dialog.hide()
	else:
		root.size = Vector2i(540, 960)
		root.content_scale_size = Vector2i(540, 960)
		await settle(0.5)
		world.control.apply_portrait_layout()
		recorder.recording_finished.connect(func(path:String, frames:int):
			outputs.append({"path":ProjectSettings.globalize_path(path), "frames":frames, "fps":recorder._output_fps}))
		await click(MOUSE_BUTTON_LEFT)
		check(recorder.get_mode() == 1, "actual left mouse starts LIVE")
		check(button.modulate.g < 0.5, "active button turns red")
		await settle(1.0)
		paused = true
		var before:int = recorder._frame_index
		await settle(0.3)
		check(recorder._frame_index > before, "LIVE capture continues while paused")
		await click(MOUSE_BUTTON_LEFT)
		check(recorder.get_mode() == 0, "actual left mouse stops LIVE while paused")
		await wait_idle()
		paused = false
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
		check(world.has_rematch_setup(), "SIM fixture has actual rematch setup")
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
		check(not recorder._overlay_backdrop.visible and recorder._sim_viewport == null, "abort clears overlay and capture viewport")
		check(outputs.size() == 2 and not outputs[1].path.is_empty(), "SIM abort saves playable portion")
		await click(MOUSE_BUTTON_RIGHT)
		check(recorder.get_mode() == 2, "SIM can restart after abort")
		await settle(0.4)
		world._rotation_finished = true
		await wait_idle()
		check(outputs.size() == 3 and not outputs[2].path.is_empty(), "SIM auto-finishes after series completion")
		check(is_equal_approx(Engine.time_scale, original_scale), "auto finish restores time scale")
		check(not button.disabled, "record button reusable after automatic finish")
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
