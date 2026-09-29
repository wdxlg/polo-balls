extends "res://tests/test_heavenfall_rift_visual.gd"
# A zero-strength warp must reproduce the exact background under all transforms;
# partial backbuffer regions must not leave black wedges when zoomed or panned.

func pixels_changed(a: Image, b: Image) -> int:
	var count: int = 0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			if colour_delta(a.get_pixel(x, y), b.get_pixel(x, y)) > 0.003:
				count += 1
	return count

func run() -> void:
	create_timer(45.0, true, false, true).timeout.connect(func(): quit(2))
	if DisplayServer.get_name() == "headless":
		print("SKIP: refraction transform regression requires a GPU viewport")
		quit()
		return
	root.get_node("Game").now_stop_state = false
	rift_script = load("res://scripts/characters/我的世界/new6/heavenfall_rift.gd")
	var viewport: SubViewport = make_viewport(Vector2i(320, 192), false)
	add_grid(viewport, viewport.size)
	var plain: Image = await read_frame(viewport)
	var layer := CanvasLayer.new()
	layer.offset = Vector2(70, 96)
	layer.scale = Vector2(2, 2)
	viewport.add_child(layer)
	var rift = rift_script.new()
	layer.add_child(rift)
	rift.configure(null, 7, PackedVector2Array([Vector2.ZERO, Vector2(90, 0)]), [], Vector2(45, 0), 6.0)
	rift.set_process(false)
	rift._age = rift.OPEN_TIME
	rift._sync_visual()
	rift._surface.visible = false
	rift._warp_material.set_shader_parameter("warp_strength", 0.0)
	var rendered: Image = await read_frame(viewport)
	check(pixels_changed(plain, rendered) == 0, "scaled/translated CanvasLayer retains background without black wedges")
	layer.offset = Vector2(40, 84)
	layer.scale = Vector2(2.5, 2.5)
	rendered = await read_frame(viewport)
	check(pixels_changed(plain, rendered) == 0, "copy bounds follow live CanvasLayer pan and zoom")
	rift.rotation = 0.15
	rift.position = Vector2(3, 4)
	rendered = await read_frame(viewport)
	check(pixels_changed(plain, rendered) == 0, "copy bounds include the rift node transform without double-applying it")
	layer.queue_free()
	await process_frame
	# Test the real battle path: a Camera2D, not a preview CanvasLayer.
	var camera := Camera2D.new()
	viewport.add_child(camera)
	camera.position = Vector2(80, 48)
	camera.zoom = Vector2(2, 2)
	camera.make_current()
	await process_frame
	plain = await read_frame(viewport)
	rift = rift_script.new()
	viewport.add_child(rift)
	rift.configure(null, 9, PackedVector2Array([Vector2(30, 48), Vector2(120, 48)]), [], Vector2(75, 48), 6.0)
	rift.set_process(false)
	rift._age = rift.OPEN_TIME
	rift._sync_visual()
	rift._surface.visible = false
	rift._warp_material.set_shader_parameter("warp_strength", 0.0)
	rendered = await read_frame(viewport)
	check(pixels_changed(plain, rendered) == 0, "Camera2D zoom uses a correctly transformed local backbuffer region")
	rift._space_warp.visible = false
	camera.position += Vector2(8, 3)
	camera.zoom = Vector2(1.8, 1.8)
	await process_frame
	plain = await read_frame(viewport)
	rift._space_warp.visible = true
	rendered = await read_frame(viewport)
	check(pixels_changed(plain, rendered) == 0, "camera motion cannot expose uncopied pixels")
	viewport.queue_free()
	await process_frame
	print("HEAVENFALL WARP TRANSFORM RESULT: %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
