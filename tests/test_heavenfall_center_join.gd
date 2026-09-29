extends "res://tests/test_heavenfall_rift_visual.gd"
# Assert that the central aperture has actual area and that every major throat
# connects to it in the GPU alpha mask, not just in the centerline point list.

func component(image: Image, center: Vector2i) -> PackedByteArray:
	var size: Vector2i = image.get_size()
	var seen := PackedByteArray()
	seen.resize(size.x * size.y)
	var queue := PackedInt32Array()
	var start: int = center.y * size.x + center.x
	if image.get_pixelv(center).a <= 0.10:
		return seen
	seen[start] = 1
	queue.append(start)
	var head: int = 0
	while head < queue.size():
		var value: int = queue[head]
		head += 1
		var x: int = value % size.x
		var y: int = value / size.x
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx: int = x + dx
				var ny: int = y + dy
				if nx < 0 or ny < 0 or nx >= size.x or ny >= size.y:
					continue
				var index: int = ny * size.x + nx
				if seen[index] != 0 or image.get_pixel(nx, ny).a <= 0.10:
					continue
				seen[index] = 1
				queue.append(index)
	return seen

func touches_component(seen: PackedByteArray, pixel: Vector2i, size: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var p: Vector2i = pixel + Vector2i(dx, dy)
			if p.x >= 0 and p.y >= 0 and p.x < size.x and p.y < size.y and seen[p.y * size.x + p.x] != 0:
				return true
	return false

func run() -> void:
	create_timer(45.0, true, false, true).timeout.connect(func(): quit(2))
	root.get_node("Game").now_stop_state = false
	rift_script = load("res://scripts/characters/我的世界/new6/heavenfall_rift.gd")
	var bow_script: Script = load("res://scripts/characters/我的世界/new6/heavenfall_longbow.gd")
	if not rift_script.can_instantiate() or not bow_script.can_instantiate():
		check(false, "connected fracture scripts compile")
		quit(1)
		return
	var generator = bow_script.new()
	generator.rng.seed = 317
	var path: PackedVector2Array = generator._build_rift_path(Vector2.ZERO, Vector2.RIGHT)
	var branches: Array = generator._grow_rift_branches(path)
	generator.free()
	var viewport: SubViewport = make_viewport(Vector2i(320, 320), true)
	var layer := CanvasLayer.new()
	layer.offset = Vector2(160, 160)
	layer.scale = Vector2(3, 3)
	viewport.add_child(layer)
	var rift = rift_script.new()
	layer.add_child(rift)
	rift.configure(null, 1, path, branches, Vector2.ZERO, 6.0)
	rift.set_process(false)
	rift._age = rift.OPEN_TIME
	rift._sync_visual()
	check(rift._has_center_join, "battle fractures use a common connecting opening")
	var roots: Array[Vector2] = []
	var throats_ok: bool = true
	var hub_found: bool = false
	for crack: Dictionary in rift._cached_cracks:
		var samples: Array = crack["samples"]
		if int(crack["id"]) == rift.CENTER_ID:
			hub_found = samples.size() >= 3 and float(crack["width"]) > rift.MAIN_W0
			continue
		var points: PackedVector2Array = crack["points"]
		if points[0].distance_to(Vector2.ZERO) > 0.01:
			continue
		throats_ok = throats_ok and float(samples[0]["w"]) > 0.25 and (samples[0]["p"] as Vector2).is_equal_approx(Vector2.ZERO)
		for sample: Dictionary in samples:
			if (sample["p"] as Vector2).length() >= 5.0:
				roots.append(sample["p"])
				break
	check(hub_found, "central opening is a finite irregular piece, not an empty shared point")
	check(throats_ok and roots.size() >= 4, "major roots have real width and remain exactly attached to the center")
	if DisplayServer.get_name() != "headless":
		for closure: float in [1.0, 0.45]:
			rift._rift_material.set_shader_parameter("closure", closure)
			var image: Image = await read_frame(viewport)
			var seen: PackedByteArray = component(image, Vector2i(160, 160))
			var center_pixels: int = 0
			for y in range(156, 165):
				for x in range(156, 165):
					if image.get_pixel(x, y).a > 0.7:
						center_pixels += 1
			var connected: int = 0
			for point: Vector2 in roots:
				if touches_component(seen, Vector2i((point * 3.0 + Vector2(160,160)).round()), image.get_size()):
					connected += 1
			check(center_pixels >= (24 if closure > 0.5 else 10), "central GPU aperture has visible area during open/closing")
			check(connected == roots.size(), "all major throats belong to the center's connected GPU component")
			print("CENTER_JOIN: closure=%.2f central_pixels=%d connected=%d/%d" % [closure, center_pixels, connected, roots.size()])
	viewport.queue_free()
	await process_frame
	print("HEAVENFALL CENTER JOIN RESULT: %d/%d passed" % [checks-failures, checks])
	quit(0 if failures == 0 else 1)
