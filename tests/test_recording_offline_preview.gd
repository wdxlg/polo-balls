extends "res://tests/test_battle_recording.gd"
## GPU test: the right-click window shows sampled battle frames without drawing
## another World, changing the two video sources, or updating once per video frame.

func _wait_wall(seconds:float) -> void:
	var until:int = int(Time.call("get_wall_ticks_usec")) + int(seconds * 1000000.0)
	while int(Time.call("get_wall_ticks_usec")) < until:
		await RenderingServer.frame_post_draw

func _small_image(source:Viewport) -> Image:
	var image:Image = source.get_texture().get_image()
	if image == null or image.is_empty(): return null
	if image.get_format() != Image.FORMAT_RGBA8: image.convert(Image.FORMAT_RGBA8)
	image.resize(360, 640, Image.INTERPOLATE_BILINEAR)
	return image

func _swatch_pixels(image:Image) -> int:
	if image == null: return 0
	var hits:int = 0
	for y:int in range(110, 172, 8):
		for x:int in range(70, 136, 8):
			var c:Color = image.get_pixel(x, y)
			if c.r > 0.35 and c.b > 0.35 and c.g < 0.25: hits += 1
	return hits

func run() -> void:
	game = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Map_Background = "blue"
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world, CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	controls = world.control._battle_record_controls
	recorder = controls.recorder
	recorder.preferences = recorder.PreferencesScript.new("user://test_recording_offline_preview.cfg")
	recorder.preferences.directory = "user://recordings/offline_preview_test"
	world.control.team.hide()
	root.size = Vector2i(540, 960)
	for side:int in range(2):
		var actor:Node = load("res://scenes/ball.tscn").instantiate()
		actor.name = "PreviewBall%d" % side
		world.add_child(actor, true)
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		actor.position = Vector2(-300 if side == 0 else 300, 0)
		actor.collision_layer = 0
		actor.collision_mask = 0
	await _wait_wall(0.3)
	var original_mask:int = root.canvas_cull_mask
	check(recorder.start_simulated(), "right-click recording starts from the current battle")
	if not recorder.is_recording():
		print(recorder.get_last_error())
		quit(1)
		return
	var preview:SubViewport = recorder._offline._preview_viewport
	check(is_instance_valid(preview) and preview.size == Vector2i(360, 640), "small preview cache is installed in the player window")
	check(preview.world_2d != root.world_2d and preview.world_2d != recorder._sim_viewport.world_2d, "preview blits a texture instead of rendering a third battlefield")
	check(root.canvas_cull_mask == recorder.CAPTURE_MASK_BIT, "player viewport still culls expensive battlefield rendering")
	check(recorder._offline._preview_image.texture == preview.get_texture(), "visible progress panel samples the cached frame")
	var swatch := ColorRect.new()
	swatch.color = Color.MAGENTA
	swatch.position = Vector2(180, 300)
	swatch.size = Vector2(240, 240)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	recorder._sim_viewport.get_node("RecordingComposition").add_child(swatch)
	var deadline:int = int(Time.call("get_wall_ticks_usec")) + 4000000
	while recorder.is_recording() and (recorder._offline._preview_updates < 2 or recorder._frame_index < 32) and int(Time.call("get_wall_ticks_usec")) < deadline:
		await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw # The last UPDATE_ONCE must be presented.
	var frame_count:int = recorder._frame_index
	var refresh_count:int = recorder._offline._preview_updates
	check(refresh_count >= 2 and frame_count >= 32, "preview receives multiple distinct battle frames")
	check(refresh_count * 5 < frame_count, "preview is wall-clock-limited, not one GPU copy per encoded frame")
	var source:Image = _small_image(recorder._capture_viewport)
	var cache:Image = _small_image(preview)
	var player:Image = _small_image(root)
	check(_swatch_pixels(source) > 15, "the test witness is present in the recorded battle frame")
	check(_swatch_pixels(cache) > 15, "cached preview contains the already-rendered battle frame")
	check(_swatch_pixels(player) > 15, "actual GPU player window shows the battle through the progress overlay, not black")
	var output_dir:String = "user://recordings/offline_preview_test"
	check(player != null and player.save_png(output_dir.path_join("player_preview.png")) == OK, "save player-window visual evidence")
	check(source != null and source.save_png(output_dir.path_join("recorded_source.png")) == OK, "save video-source comparison image")
	var window_mode:int = DisplayServer.window_get_mode()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	var frame_before:int = recorder._frame_index
	var updates_before:int = recorder._offline._preview_updates
	await _wait_wall(0.65)
	check(recorder._frame_index > frame_before and recorder._offline._preview_updates == updates_before, "minimizing skips preview copies but keeps encoding frames")
	DisplayServer.window_set_mode(window_mode)
	await _wait_wall(0.65)
	check(recorder._offline._preview_updates > updates_before, "restoring window resumes occasional picture updates")
	recorder.stop()
	await wait_idle()
	check(root.canvas_cull_mask == original_mask and not recorder._overlay_backdrop.visible, "recording exit restores the ordinary battle window")
	check(not is_instance_valid(preview), "preview cache and signal are cleaned up after recording")
	check(recorder.last_outputs.size() == 2 and recorder.get_last_error().is_empty(), "Chinese and English videos still finish")
	world.queue_free()
	await process_frame
	await process_frame
	game.Game_Settings = saved
	print("OFFLINE_PREVIEW: %d checks / %d failures" % [checks, failures])
	quit(1 if failures else 0)
