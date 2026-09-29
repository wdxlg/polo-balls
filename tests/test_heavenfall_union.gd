extends "res://tests/test_heavenfall_center_join.gd"
# GPU regressions for *interior* connectivity, not merely touching alpha masks.
var film: Image
var frame_number: int = 0
const TILE := Vector2i(384, 384)

func rectangle_mesh(horizontal: bool, close: float = 1.0) -> ArrayMesh:
	var axis := Vector2.RIGHT if horizontal else Vector2.DOWN
	var normal := Vector2(-axis.y, axis.x)
	var vertices := PackedVector2Array()
	var offsets := PackedVector2Array()
	var colors := PackedColorArray()
	for point: Vector2 in [Vector2(64, 64) - axis * 48.0, Vector2(64, 64) + axis * 48.0]:
		for sign_value: float in [-1.0, 1.0]:
			var offset: Vector2 = normal * 7.0 * 1.45 * sign_value * close
			vertices.append(point + offset)
			offsets.append(offset)
			colors.append(Color((sign_value + 1.0) * 0.5, 0, 1, 1))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = offsets
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 2, 1, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func fixture(parent: Node, horizontal: bool) -> Node2D:
	var rift = rift_script.new()
	parent.add_child(rift)
	rift.configure(null, 123, PackedVector2Array([Vector2(16,64), Vector2(112,64)]), [], Vector2(64,64), 6.0)
	rift.set_process(false)
	rift._age = rift.OPEN_TIME
	rift._sync_visual()
	rift._surface.mesh = rectangle_mesh(horizontal)
	rift._rift_material.set_shader_parameter("closure", 1.0)
	rift._rift_material.set_shader_parameter("opening_progress", 1.0)
	rift._rift_material.set_shader_parameter("cosmic_time", 0.0)
	return rift

func freeze_clock(viewport: Viewport) -> void:
	for node: Node in get_nodes_in_group("HeavenfallUnionCoordinator"):
		if node.get_parent() == viewport:
			node.set_process(false)
			node.set("_clock", 0.0)

func capture(viewport: SubViewport) -> Image:
	var image: Image = await read_frame(viewport)
	var copy: Image = image.duplicate()
	copy.convert(Image.FORMAT_RGBA8)
	film.blit_rect(copy, Rect2i(Vector2i.ZERO, TILE), Vector2i(frame_number % 4, frame_number / 4) * TILE)
	frame_number += 1
	return image

func run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(2))
	root.get_node("Game").now_stop_state = false
	AudioServer.set_bus_mute(0, true)
	rift_script = load("res://scripts/characters/我的世界/new6/heavenfall_rift.gd")
	var rain_script: Script = load("res://scripts/characters/我的世界/new6/heavenfall_rain_rift.gd")
	var arrow_script: Script = load("res://scripts/characters/我的世界/new6/heavenfall_arrow.gd")
	check(rain_script.can_instantiate() and arrow_script.can_instantiate(), "rain and real arrow scripts compile")
	film = Image.create(TILE.x * 4, TILE.y * 3, false, Image.FORMAT_RGBA8)
	film.fill(Color(0.055,0.065,0.08,1))
	for hdr: bool in [false, true]:
		var viewport: SubViewport = make_viewport(TILE, true)
		viewport.use_hdr_2d = hdr
		var layer := CanvasLayer.new()
		layer.scale = Vector2(3,3)
		viewport.add_child(layer)
		var horizontal: Node2D = fixture(layer, true)
		var vertical: Node2D = fixture(layer, false)
		freeze_clock(viewport)
		if DisplayServer.get_name() != "headless":
			for close: float in [1.0, 0.55]:
				horizontal.get("_rift_material").set_shader_parameter("closure", close)
				vertical.get("_rift_material").set_shader_parameter("closure", close)
				horizontal.visible = false
				var reference: Image = await read_frame(viewport)
				horizontal.visible = true
				var crossed: Image = await capture(viewport)
				var seam_errors: int = 0
				for y in range(159,226):
					for x in range(189,195):
						if colour_delta(reference.get_pixel(x,y), crossed.get_pixel(x,y)) > 0.025:
							seam_errors += 1
				check(seam_errors == 0, "HDR=%s closure=%.2f: no horizontal rim cuts across vertical cavity (%d bad pixels)" % [hdr, close, seam_errors])
				layer.move_child(horizontal, layer.get_child_count()-1)
				var reversed: Image = await read_frame(viewport)
				var order_errors: int = 0
				for y in range(174,211):
					for x in range(174,211):
						if colour_delta(crossed.get_pixel(x,y), reversed.get_pixel(x,y)) > 0.025: order_errors += 1
				check(order_errors == 0, "crossing does not depend on which rectangle is drawn on top (%d bad pixels)" % order_errors)
				layer.move_child(horizontal, 0)
		# Rain coverage and every primary spoke must connect to the impact itself.
		horizontal.queue_free()
		vertical.queue_free()
		await process_frame
		var rain = rain_script.new()
		layer.add_child(rain)
		rain.configure_impact(Vector2(64,64), 713, 10.0)
		rain.set_process(false)
		freeze_clock(viewport)
		check(rain._has_center_join and rain._branches.size() >= 6, "rain has a central aperture, 5-6 radial arms and secondary forks")
		check(rain._owner_ref == null and not rain.is_in_group("HeavenfallPierceTear"), "rain cannot grant another dodge and no longer uses a directional pierce slit")
		var primary: Array[Vector2] = []
		for crack: Dictionary in rain._cached_cracks:
			if int(crack["id"]) == rain.CENTER_ID: continue
			var path: PackedVector2Array = crack["points"]
			if path[0].distance_to(Vector2(64,64)) < 0.01: primary.append(path[1])
		check(primary.size() >= 5, "all primary rain arms begin at the actual impact point")
		if DisplayServer.get_name() != "headless":
			for age: float in [0.025, 0.15, 0.38]:
				rain._age = age
				rain._sync_visual()
				var image: Image = await capture(viewport)
				var seen: PackedByteArray = component(image, Vector2i(192,192))
				var joined: int = 0
				for point: Vector2 in primary:
					if touches_component(seen, Vector2i((point * 3.0).round()), TILE): joined += 1
				check(joined == primary.size(), "rain grows/closes as one connected web at age %.3f (%d/%d arms)" % [age, joined, primary.size()])
			rain._age = 0.0
			rain._sync_visual()
			var unborn: Image = await read_frame(viewport)
			check(unborn.get_pixel(192,192).a < 0.01, "no pre-existing full web before center-out opening")
		# Pausing and cleanup remain governed by the existing rift lifecycle.
		root.get_node("Game").now_stop_state = true
		var old_age: float = rain._age
		rain._process(0.1)
		check(is_equal_approx(rain._age, old_age), "rain aperture freezes with battle pause")
		root.get_node("Game").now_stop_state = false
		rain._process(1.0)
		check(rain.is_queued_for_deletion(), "rain closes and is removed without leaking")
		viewport.queue_free()
		await process_frame
	if DisplayServer.get_name() != "headless":
		check(film.save_png("user://heavenfall_union_regression.png") == OK, "crossing and rain GPU filmstrip saved")
	print("HEAVENFALL UNION RESULT: %d/%d passed" % [checks-failures, checks])
	quit(0 if failures == 0 else 1)
