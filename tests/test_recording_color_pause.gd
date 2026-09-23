extends "res://tests/test_battle_recording.gd"

func esc() -> void:
	for down:bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.physical_keycode = KEY_ESCAPE
		event.pressed = down
		root.push_input(event, true)

func color_error(capture:Image, reference:Image) -> Dictionary:
	var total:float = 0.0
	var worst:float = 0.0
	var count:int = 0
	for y:int in range(2, 20):
		for x:int in range(1, 12):
			var uv := Vector2(float(x) / 12.0, float(y) / 20.0)
			var expected:Color = reference.get_pixelv(Vector2i(uv * Vector2(reference.get_size())))
			if recorder._viewport_uses_hdr(root): expected = expected.linear_to_srgb()
			var actual:Color = capture.get_pixelv(Vector2i(uv * Vector2(capture.get_size())))
			var error:float = maxf(absf(actual.r - expected.r), maxf(absf(actual.g - expected.g), absf(actual.b - expected.b)))
			total += error
			worst = maxf(worst, error)
			count += 1
	return {"mean":total / count, "max":worst, "samples":count}

func panel(color:Color, offset:Vector2, size:Vector2) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.position = world.camera_2d.get_screen_center_position() + offset - size * 0.5
	rect.size = size
	rect.z_index = 900
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(rect)
	return rect

func run() -> void:
	create_timer(100.0, true, false, true).timeout.connect(func(): print("COLOR_PAUSE_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Map_Background = "blue"
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world, CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	root.size = Vector2i(540, 960)
	await settle(1.0)
	world.control.hide()
	world.control.team.hide()
	controls = world.control._battle_record_controls
	recorder = controls.recorder
	var config:String = "user://test_color_pause.cfg"
	DirAccess.remove_absolute(config)
	recorder.preferences = recorder.PreferencesScript.new(config)
	recorder.preferences.directory = "user://recordings/color_pause_test"
	game.Game_Settings.Creating = false
	check(not paused and not game.now_stop_state, "test starts in active battle")
	var chart:ColorRect = panel(Color(0.15, 0.55, 0.25), Vector2.ZERO, Vector2(24, 24))
	var alpha:ColorRect = panel(Color(0.8, 0.2, 0.1, 0.45), Vector2(0, -45), Vector2(36, 25))
	var dark:ColorRect = panel(Color(0.008, 0.018, 0.03), Vector2(0, 45), Vector2(36, 25))
	var tone:AudioStreamPlayer = make_tone(440.0, &"GameplayRecord")
	var wall_start:int = Time.get_ticks_msec()
	check(recorder.start_live(), "LIVE starts with isolated recording settings")
	await settle(0.8)
	await RenderingServer.frame_post_draw
	var capture:Image = recorder._grab_image()
	var reference:Image = root.get_texture().get_image()
	var reference_frame:int = recorder._frame_index - 1
	var metrics:Dictionary = color_error(capture, reference)
	print("COLOR_MATCH=", JSON.stringify(metrics))
	check(metrics.mean < 0.01 and metrics.max < 0.035, "198 same-frame battle samples match game HDR image (top toolbar excluded)")
	check(recorder._sim_viewport.use_hdr_2d == recorder._viewport_uses_hdr(root), "linear-light rendering matches main viewport")
	check(recorder._capture_viewport == recorder._resolve_viewport and capture.get_format() == Image.FORMAT_RGBA8, "GPU sRGB resolve precedes 8-bit quantization")
	var alpha_point:Vector2 = recorder._sim_viewport.canvas_transform * (alpha.position + alpha.size * 0.5)
	var root_alpha:Vector2i = Vector2i(alpha_point * Vector2(reference.get_size()) / Vector2(capture.get_size()))
	var expected_alpha:Color = reference.get_pixelv(root_alpha).linear_to_srgb()
	var actual_alpha:Color = capture.get_pixelv(Vector2i(alpha_point))
	check(Vector3(expected_alpha.r, expected_alpha.g, expected_alpha.b).distance_to(Vector3(actual_alpha.r, actual_alpha.g, actual_alpha.b)) < 0.015, "translucent effect blending matches game, not an SDR approximation")
	var dark_point:Vector2i = Vector2i(recorder._sim_viewport.canvas_transform * (dark.position + dark.size * 0.5))
	var dark_color:Color = capture.get_pixelv(dark_point)
	check(absf(dark_color.r - dark.color.r) < 0.004 and absf(dark_color.g - dark.color.g) < 0.004, "dark tones survive without quantize-then-gamma loss")
	capture.save_png("user://recordings/color_pause_test/capture.png")
	# Toggling the real vignette must alter the recording too.
	game.vignette.hide()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var no_vignette:Image = recorder._grab_image()
	var corner:Vector2i = Vector2i(Vector2(capture.get_size()) * Vector2(0.06, 0.06))
	check(no_vignette.get_pixelv(corner).g > capture.get_pixelv(corner).g + 0.04, "permanent vignette is included in recording")
	game.vignette.show()
	await settle(0.2)
	var before:int = recorder._frame_index
	var samples_before:int = recorder._audio.samples_written
	var time_before:float = recorder._game_time
	esc()
	check(paused and game.now_stop_state and game.stop_background.visible, "real Escape key enters actual pause UI")
	chart.color = Color.RED
	await settle(0.7)
	check(recorder._frame_index == before, "no frame enters video from the first Esc boundary")
	check(recorder._audio.samples_written == samples_before, "no audio enters video during Esc pause")
	check(is_equal_approx(recorder._game_time, time_before), "paused waiting adds no video duration")
	# Force a diagnostic render while paused: even then Stop_Ui must not leak.
	var saved_pause_color:Color = game.stop_background.color
	game.stop_background.color = Color.MAGENTA
	recorder._prepare_next_capture()
	await RenderingServer.frame_post_draw
	var paused_image:Image = recorder._grab_image()
	var ui_pixel:Color = paused_image.get_pixelv(Vector2i(540, 500))
	check(not (ui_pixel.r > 0.8 and ui_pixel.b > 0.8 and ui_pixel.g < 0.2), "pause CanvasLayer excluded even from forced diagnostic capture")
	check(is_equal_approx(float(recorder._capture_vignette.get_instance_shader_parameter("SCALE")), game.vignette_start), "pause darkening animation never enters capture vignette")
	game.stop_background.color = saved_pause_color
	chart.color = Color.CYAN
	esc()
	check(paused and not game.now_stop_state and game.stop_text.visible, "real Escape begins the actual resume countdown")
	for i:int in range(3):
		await settle(0.2)
		check(recorder._frame_index == before and recorder._audio.samples_written == samples_before, "countdown segment %d adds neither frames nor audio" % i)
	await settle(0.7)
	check(not paused and not game.stop_text.visible and recorder._frame_index > before, "capture resumes only after countdown finishes")
	# Two Esc events within one render must still discard the boundary interval.
	game.Game_Settings.Creating = true
	before = recorder._frame_index
	samples_before = recorder._audio.samples_written
	esc()
	esc()
	check(not paused and recorder._pause_boundary, "rapid pause/resume is latched even between draws")
	await RenderingServer.frame_post_draw
	check(recorder._frame_index == before and recorder._audio.samples_written == samples_before, "rapid Esc boundary cannot record a stale frame or audio block")
	game.Game_Settings.Creating = false
	await settle(0.4)
	recorder.recording_finished.connect(func(path:String, frames:int): outputs.append({"path":ProjectSettings.globalize_path(path), "frames":frames}))
	recorder.stop()
	await wait_idle()
	check(outputs.size() == 1 and outputs[0].frames > 0, "valid MP4 saved after repeated Esc transitions")
	var result:Dictionary = {"output":outputs[0], "color":metrics, "reference_frame":reference_frame, "wall_seconds":float(Time.get_ticks_msec() - wall_start) / 1000.0, "game_time":recorder._game_time, "checks":checks, "failures":failures}
	var manifest := FileAccess.open("user://recordings/color_pause_test/manifest.json", FileAccess.WRITE)
	manifest.store_string(JSON.stringify(result, "\t"))
	manifest.close()
	tone.queue_free()
	world.queue_free()
	await process_frame
	await process_frame
	game.Game_Settings = saved
	print("COLOR_PAUSE: %d checks / %d failures" % [checks, failures])
	quit(1 if failures else 0)
