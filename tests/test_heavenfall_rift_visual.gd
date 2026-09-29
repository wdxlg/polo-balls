extends SceneTree
# Geometry/lifecycle regression in headless mode; additionally checks the real
# GPU aperture by changing only cosmic_time when a rendering device is available.
var rift_script: Script
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS: " if ok else "FAIL: ") + message)


func run() -> void:
	create_timer(45.0, true, false, true).timeout.connect(func(): quit(2))
	var game: Node = root.get_node("Game")
	# --script is parsed before autoload names exist: load game scripts at runtime.
	rift_script = load("res://scripts/characters/我的世界/new6/heavenfall_rift.gd")
	if rift_script == null or not rift_script.can_instantiate():
		check(false, "rift runtime script compiles")
		quit(1)
		return
	var saved_stop: bool = game.now_stop_state
	game.now_stop_state = false
	AudioServer.set_bus_mute(0, true)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var rift = rift_script.new()
	world.add_child(rift)
	var points := PackedVector2Array([Vector2(30, 60), Vector2(181.25, 60)])
	var branches: Array = [PackedVector2Array([Vector2(60, 60), Vector2(85, 30)]), PackedVector2Array([Vector2(160, 60), Vector2(180, 80)])]
	rift.configure(null, 17, points, branches, Vector2(100, 60), 6.0)
	rift.set_process(false)
	rift._age = rift.OPEN_TIME
	rift._sync_visual()
	var samples: Array = rift._crack_samples(points, 0, rift.MAIN_W0, 1.0)
	check(samples.size() > 2, "rift samples the complete path")
	check(is_equal_approx(rift.MAIN_W0, 4.0), "fractures are thin, not broad triangular wedges")
	check(is_equal_approx(float(samples.back()["s"]), 1.0), "non-divisible path length still includes the exact endpoint")
	check(is_zero_approx(float(samples.back()["w"])), "tail has exactly zero width, not a rounded minimum-width cap")
	check((samples.back()["p"] as Vector2).is_equal_approx(points[1]), "tip stays at the requested endpoint")
	var peak_width: float = 0.0
	var peak_s: float = 0.0
	var bounded_jag: bool = true
	var finite: bool = true
	for i in range(samples.size()):
		var sm: Dictionary = samples[i]
		if float(sm["w"]) > peak_width:
			peak_width = float(sm["w"])
			peak_s = float(sm["s"])
		if (sm["p"] as Vector2).distance_to(sm["ps"]) > float(sm["w"]) * 0.091 + 0.00001:
			bounded_jag = false
		finite = finite and (sm["p"] as Vector2).is_finite() and (sm["n"] as Vector2).is_finite()
	check(is_zero_approx(float(samples[0]["w"])) and peak_s > 0.05 and peak_s < 0.75 and peak_width > 1.0, "fractures have pointed roots and tips with an irregular opening between them")
	check(bounded_jag, "edge irregularity shrinks with the aperture, including the tip")
	check(finite, "all sample positions and normals are finite")
	var narrow: Array = rift._crack_samples(points, 0, rift.MAIN_W0, 0.2)
	var shut: Array = rift._crack_samples(points, 0, rift.MAIN_W0, 0.0)
	var scales: bool = true
	var zero: bool = true
	for i in range(samples.size()):
		scales = scales and is_equal_approx(float(narrow[i]["w"]), float(samples[i]["w"]) * 0.2)
		zero = zero and is_zero_approx(float(shut[i]["w"]))
	check(scales, "closing scales the complete width profile")
	check(zero, "fully closed geometry has no leftover fixed-width star strip")
	check(rift._branch_width(branches[1]) < rift._branch_width(branches[0]), "fine branches remain proportionate to their attachment")
	var branch_samples: Array = rift._crack_samples(branches[0], 1, rift._branch_width(branches[0]), 1.0)
	check(is_zero_approx(float(branch_samples.back()["w"])), "branch ends also converge to sharp points")
	check(rift._crack_samples(PackedVector2Array(), 0, 14.0, 1.0).is_empty(), "empty paths are safe")
	check(rift._crack_samples(PackedVector2Array([Vector2.ONE, Vector2.ONE]), 0, 14.0, 1.0).is_empty(), "zero-length paths are safe")
	var reflected: Array = rift._crack_samples(PackedVector2Array([Vector2(10, 10), Vector2(80, 10), Vector2(80, 10), Vector2(20, 10)]), 0, 14.0, 1.0)
	finite = true
	for sm: Dictionary in reflected:
		finite = finite and (sm["p"] as Vector2).is_finite() and (sm["n"] as Vector2).is_finite()
	check(finite and is_zero_approx(float(reflected.back()["w"])), "reflection and duplicate vertices keep valid pointed geometry")
	check(rift._surface.mesh.get_surface_count() == 1, "all cracks share one cached triangle mesh")
	var mesh_arrays: Array = rift._surface.mesh.surface_get_arrays(0)
	var valid_indices: bool = true
	for index: int in mesh_arrays[Mesh.ARRAY_INDEX]:
		valid_indices = valid_indices and index >= 0 and index < mesh_arrays[Mesh.ARRAY_VERTEX].size()
	check(valid_indices, "ribbon triangle indices stay in bounds")
	var atlas: Image = rift.COSMIC_ATLAS.get_image()
	check(atlas.get_size() == Vector2i(160, 128), "native cosmic atlas has the documented layout")
	# Source-byte comparison is test-only; runtime always uses the imported texture.
	var raw_atlas := Image.new()
	var decode_error: Error = raw_atlas.load_png_from_buffer(FileAccess.get_file_as_bytes("res://Images/characters/我的世界/new6/av_cosmic_atlas.png"))
	atlas.convert(Image.FORMAT_RGBA8)
	raw_atlas.convert(Image.FORMAT_RGBA8)
	check(decode_error == OK and atlas.get_data() == raw_atlas.get_data(), "Godot import preserves native star texels and raw frame IDs exactly")
	var periods: Array[int] = [10, 23, 31, 47, 37, 39, 6, 8, 84, 6]
	var original_timing: bool = true
	for i in range(10):
		original_timing = original_timing and roundi(atlas.get_pixel(159, 112 + i).r * 255.0) == periods[i]
	check(original_timing, "all ten original mcmeta animation periods are retained")
	check(rift.get_child_count() == 4 and rift._exterior_surface.mesh == rift._surface.mesh, "exterior continuation reuses the same cached geometry, no external star emitters")
	check(rift._surface.z_index < 0 and rift._space_copy.z_index > 90 and rift._space_warp.z_index > rift._space_copy.z_index, "stars stay behind actors; refraction samples the completed, map-clipped scene")
	check(rift._space_copy.copy_mode == BackBufferCopy.COPY_MODE_RECT and rift._space_copy.rect.get_area() < 50000.0, "refraction copies only a bounded local rectangle")
	var mesh_id: int = rift._surface.mesh.get_instance_id()
	rift._process(0.2)
	check(rift._surface.mesh.get_instance_id() == mesh_id, "animation updates uniforms without rebuilding mesh geometry")
	game.now_stop_state = true
	var paused_age: float = rift._age
	rift._process(0.5)
	check(is_equal_approx(rift._age, paused_age), "game stop pauses both closure and cosmic animation")
	game.now_stop_state = false
	rift._age = 3.0
	rift._sync_visual()
	check(is_equal_approx(float(rift._rift_material.get_shader_parameter("closure")), 0.5), "GPU receives smooth geometry-only closure")
	check(is_equal_approx(rift.remaining(), 3.0), "visual rewrite preserves lifetime reporting")
	check(rift.is_open(), "rift remains usable before expiry")
	var previous_close: float = 1.0
	var smooth_monotone: bool = true
	for frame in range(61):
		rift._age = float(frame) * 0.1
		var close: float = rift._closure_factor()
		smooth_monotone = smooth_monotone and close <= previous_close + 0.00001 and previous_close - close < 0.026
		previous_close = close
	check(smooth_monotone and is_zero_approx(previous_close), "closing is continuous and monotone with no final width jump")
	rift._age = 3.0
	rift._sync_visual()
	rift.consume()
	check(not rift.is_open(), "consuming a rift still disables its dodge immediately")
	check(not rift.is_queued_for_deletion() and is_equal_approx(rift._closure_factor(), 0.5), "consumed rift begins closing at its current width without a pop")
	rift._process(rift.CONSUME_CLOSE_TIME * 0.5)
	check(is_equal_approx(rift._closure_factor(), 0.25), "consumed rift smoothly closes instead of disappearing")
	rift._process(rift.CONSUME_CLOSE_TIME * 0.5)
	check(rift.is_queued_for_deletion(), "consumed rift is freed only after reaching zero width")
	var expiring = rift_script.new()
	world.add_child(expiring)
	expiring.configure(null, 19, points, [], points[0], 0.5)
	expiring._process(0.6)
	check(not expiring.is_open(), "expired rifts close normally")
	await process_frame
	if DisplayServer.get_name() == "headless":
		print("SKIP: GPU aperture/capture checks require a rendering window")
	else:
		await check_gpu_aperture()
		await check_refraction_and_constancy()
		# Real-world captures live in test_heavenfall_actor_refraction.gd.
	game.now_stop_state = saved_stop
	current_scene = null
	world.queue_free()
	await process_frame
	print("HEAVENFALL RIFT VISUAL RESULT: %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)


func read_frame(viewport: SubViewport) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func make_viewport(size: Vector2i, transparent: bool) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.transparent_bg = transparent
	viewport.use_hdr_2d = bool(ProjectSettings.get_setting("rendering/viewport/hdr_2d", false))
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	return viewport


func check_gpu_aperture() -> void:
	var viewport: SubViewport = make_viewport(Vector2i(640, 200), true)
	var rift = rift_script.new()
	viewport.add_child(rift)
	var path := PackedVector2Array([Vector2(60, 100), Vector2(580, 100)])
	rift.configure(null, 23, path, [], Vector2(320, 100), 6.0)
	rift.set_process(false)
	rift._age = rift.OPEN_TIME
	rift._sync_visual()
	check(not rift._space_warp.visible and rift._space_copy.copy_mode == BackBufferCopy.COPY_MODE_DISABLED, "transparent previews cannot gain an opaque refraction rectangle")
	var samples: Array = rift._crack_samples(path, 0, rift.MAIN_W0, 1.0)
	for close_amount: float in [1.0, 0.4]:
		rift._rift_material.set_shader_parameter("closure", close_amount)
		rift._warp_material.set_shader_parameter("closure", close_amount)
		rift._rift_material.set_shader_parameter("cosmic_time", 0.0)
		var first: Image = await read_frame(viewport)
		# Change only the universe, NOT rim time, geometry, or opacity.
		rift._rift_material.set_shader_parameter("cosmic_time", 12.0)
		var second: Image = await read_frame(viewport)
		var inside_changes: int = 0
		var leaked_changes: int = 0
		var outside_alpha: int = 0
		var lit_pixels: int = 0
		var halo_bound: float = ceil(rift.MAIN_W0 * 0.5 * close_amount * rift.HALO_SCALE + 2.0)
		for y in range(200):
			for x in range(640):
				var before: Color = first.get_pixel(x, y)
				var after: Color = second.get_pixel(x, y)
				if before.a > 0.01:
					lit_pixels += 1
				if (absf(float(y) + 0.5 - 100.0) > halo_bound or x < 59 or x > 580) and maxf(before.a, after.a) > 0.01:
					outside_alpha += 1
				if before.is_equal_approx(after):
					continue
				var px: float = float(x) + 0.5
				if px < 60.0 or px > 580.0:
					leaked_changes += 1
					continue
				var si: int = mini(int((px - 60.0) / 5.0), samples.size() - 2)
				var a: Dictionary = samples[si]
				var b: Dictionary = samples[si + 1]
				var f: float = clampf((px - (a["p"] as Vector2).x) / maxf((b["p"] as Vector2).x - (a["p"] as Vector2).x, 0.001), 0.0, 1.0)
				var center: Vector2 = (a["p"] as Vector2).lerp(b["p"], f)
				var hw: float = lerpf(float(a["w"]), float(b["w"]), f) * 0.5 * close_amount
				# One raster pixel of tolerance for pixel-snap/coverage differences.
				if absf(float(y) + 0.5 - center.y) > hw + 1.0:
					leaked_changes += 1
				else:
					inside_changes += 1
		var stage: String = "open" if close_amount > 0.5 else "closing"
		check(lit_pixels > 40, stage + ": GPU actually renders the rift shader")
		check(inside_changes > 10, stage + ": native cosmic field animates inside the aperture")
		check(leaked_changes == 0, stage + ": cosmic animation never changes pixels outside the crack")
		check(outside_alpha == 0, stage + ": no stars or fixed-width glow survive outside the tapered mesh")
		print("GPU MASK %s: inside_changes=%d leaked_changes=%d outside_alpha=%d" % [stage, inside_changes, leaked_changes, outside_alpha])
	viewport.queue_free()
	await process_frame


func add_caption(parent: Node, text: String, at: Vector2, font_size: int, colour: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	parent.add_child(label)


func add_grid(parent: Node, size: Vector2i) -> Sprite2D:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in range(0, size.y, 12):
		for x in range(0, size.x, 12):
			var col := Color("17252f") if (x / 12 + y / 12) % 2 == 0 else Color("263b46")
			image.fill_rect(Rect2i(x, y, mini(12, size.x - x), mini(12, size.y - y)), col)
			image.fill_rect(Rect2i(x, y, 1, mini(12, size.y - y)), Color("536d78"))
			image.fill_rect(Rect2i(x, y, mini(12, size.x - x), 1), Color("536d78"))
	var grid := Sprite2D.new()
	grid.texture = ImageTexture.create_from_image(image)
	grid.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	grid.centered = false
	grid.z_index = -8
	parent.add_child(grid)
	return grid


func sample_x(samples: Array, x: float) -> Dictionary:
	for i in range(samples.size() - 1):
		var a: Dictionary = samples[i]
		var b: Dictionary = samples[i + 1]
		if x <= (b["p"] as Vector2).x:
			var f: float = clampf((x - (a["p"] as Vector2).x) / maxf((b["p"] as Vector2).x - (a["p"] as Vector2).x, 0.001), 0.0, 1.0)
			return {"p": (a["p"] as Vector2).lerp(b["p"], f), "w": lerpf(float(a["w"]), float(b["w"]), f)}
	return samples.back()


func colour_delta(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))


func check_refraction_and_constancy() -> void:
	var viewport: SubViewport = make_viewport(Vector2i(640, 320), false)
	var grid: Sprite2D = add_grid(viewport, Vector2i(256, 128))
	grid.position = Vector2(-20, -10)
	var camera := Camera2D.new()
	viewport.add_child(camera)
	camera.position = Vector2(120, 50)
	camera.zoom = Vector2(3, 3)
	camera.make_current()
	await process_frame
	var rift = rift_script.new()
	viewport.add_child(rift)
	var points := PackedVector2Array([Vector2(30, 50), Vector2(210, 50)])
	rift.configure(null, 47, points, [], Vector2(120, 50), 6.0)
	rift.set_process(false)
	rift._age = rift.OPEN_TIME
	rift._sync_visual()
	rift._rift_material.set_shader_parameter("cosmic_time", 0.0) # Compare the same universe before/after closure.
	rift._warp_material.set_shader_parameter("warp_strength", 0.0)
	var calm: Image = await read_frame(viewport)
	rift._warp_material.set_shader_parameter("warp_strength", rift.WARP_STRENGTH)
	var refracted: Image = await read_frame(viewport)
	var samples: Array = rift._crack_samples(points, 0, rift.MAIN_W0, 1.0)
	var inverse_canvas: Transform2D = rift.get_global_transform_with_canvas().affine_inverse()
	var outside_changes: int = 0
	var far_changes: int = 0
	var interior_changes: int = 0
	for x in range(640):
		for y in range(320):
			if colour_delta(calm.get_pixel(x, y), refracted.get_pixel(x, y)) < 0.002:
				continue
			var p: Vector2 = inverse_canvas * Vector2(float(x)+0.5, float(y)+0.5)
			var sm: Dictionary = sample_x(samples, p.x)
			var hw: float = float(sm["w"]) * 0.5
			var distance: float = absf(p.y - (sm["p"] as Vector2).y)
			if p.x < 29.0 or p.x > 211.0 or absf(p.y - 50.0) > 14.0:
				far_changes += 1
			if p.x >= 30.0 and p.x < 210.0 and distance > hw + 0.5:
				outside_changes += 1
			if p.x >= 40.0 and p.x < 180.0 and distance < hw - 0.6:
				interior_changes += 1
	check(outside_changes > 100, "GPU refraction visibly displaces scene pixels outside the openings")
	check(far_changes == 0, "refraction is local, not a fullscreen effect")
	check(interior_changes == 0, "guarded scene sampling cannot distort or smear the inner universe")
	rift._rift_material.set_shader_parameter("cosmic_time", 12.0)
	var evolved: Image = await read_frame(viewport)
	var star_changes: int = 0
	var star_leaks: int = 0
	for x in range(640):
		for y in range(320):
			if colour_delta(refracted.get_pixel(x, y), evolved.get_pixel(x, y)) < 0.0001:
				continue
			var p: Vector2 = inverse_canvas * Vector2(float(x)+0.5, float(y)+0.5)
			var sm: Dictionary = sample_x(samples, p.x)
			if p.x < 30.0 or p.x > 210.0 or absf(p.y - (sm["p"] as Vector2).y) > float(sm["w"]) * 0.5 + 0.4:
				star_leaks += 1
			else:
				star_changes += 1
	check(star_changes > 30, "opaque scene really contains the animated native starfield")
	check(star_leaks == 0, "active refraction cannot pull star pixels outside their aperture")
	print("GPU OPAQUE STARS: inside_changes=%d leaked_changes=%d" % [star_changes, star_leaks])
	rift._rift_material.set_shader_parameter("cosmic_time", 0.0)
	rift._rift_material.set_shader_parameter("closure", 0.65)
	rift._warp_material.set_shader_parameter("closure", 0.65)
	var closing: Image = await read_frame(viewport)
	var stable_pixels: int = 0
	var changed_core: int = 0
	var max_delta: float = 0.0
	for x in range(640):
		for y in range(145, 175):
			var p: Vector2 = inverse_canvas * Vector2(float(x)+0.5, float(y)+0.5)
			if p.x < 40.0 or p.x > 180.0:
				continue
			var sm: Dictionary = sample_x(samples, p.x)
			var hw: float = float(sm["w"]) * 0.5 * 0.65
			var inner: float = hw - minf(0.85, hw * 0.28) - 0.35
			if absf(p.y - (sm["p"] as Vector2).y) >= inner:
				continue
			stable_pixels += 1
			var delta: float = colour_delta(refracted.get_pixel(x, y), closing.get_pixel(x, y))
			max_delta = maxf(max_delta, delta)
			if delta > 0.003:
				changed_core += 1
	check(stable_pixels > 30, "camera-magnified closure comparison includes opaque starfield pixels")
	check(changed_core == 0, "closing changes aperture coverage only, never star colour, scale or opacity")
	print("GPU REFRACTION: outside_changes=%d far_changes=%d interior_changes=%d" % [outside_changes, far_changes, interior_changes])
	print("GPU CLOSURE: checked_pixels=%d changed_core=%d max_delta=%.6f" % [stable_pixels, changed_core, max_delta])
	viewport.queue_free()
	await process_frame
