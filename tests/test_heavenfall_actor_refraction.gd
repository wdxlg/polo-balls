extends "res://tests/test_mc_new6_load.gd"
# Real battle-world rendering: actual actor, map clipping, camera and terrain.
# The foreground actor must never be replaced by background or opaque stars.

func rendered_frame() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func export_image(image: Image, name: String) -> void:
	if root.use_hdr_2d and RenderingServer.get_current_rendering_method() != "gl_compatibility":
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				image.set_pixel(x, y, image.get_pixel(x, y).linear_to_srgb())
	image.convert(Image.FORMAT_RGBA8)
	check(image.save_png("user://" + name) == OK, "actual battle-world capture saved")
	print("ACTOR_CAPTURE: ", ProjectSettings.globalize_path("user://" + name))

func colour_delta(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r-b.r), absf(a.g-b.g)), absf(a.b-b.b))

func diff_pixels(a: Image, b: Image, rect: Rect2i) -> int:
	var n: int = 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if colour_delta(a.get_pixel(x,y), b.get_pixel(x,y)) > 0.01:
				n += 1
	return n

func white(c: Color) -> float:
	return minf(minf(c.r, c.g), c.b)

func actor_core_delta(before: Image, after: Image, area: Rect2i) -> Vector2i:
	var result := Vector2i.ZERO
	for y in range(area.position.y+3, area.end.y-3):
		for x in range(area.position.x+3, area.end.x-3):
			if white(before.get_pixel(x,y)) < 0.55:
				continue
			if minf(minf(white(before.get_pixel(x-3,y)), white(before.get_pixel(x+3,y))), minf(white(before.get_pixel(x,y-3)), white(before.get_pixel(x,y+3)))) < 0.50:
				continue
			result.x += 1
			if colour_delta(before.get_pixel(x,y), after.get_pixel(x,y)) > 0.01:
				result.y += 1
	return result

func actor_mass(image: Image, area: Rect2i) -> int:
	var mass: int = 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if white(image.get_pixel(x,y)) > 0.35:
				mass += 1
	return mass

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0, true)
	create_timer(90.0, true, false, true).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world, CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var arena: Rect2 = world.return_map_world_rect(world.map_group["Map50x50"])
	var center: Vector2 = arena.get_center()
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.position = center
	camera.zoom = Vector2(3, 3)
	camera.make_current()
	var bow: Node2D = spawn("res://scenes/characters/我的世界/天堂陨落长弓.tscn", center + Vector2(-85, 0))
	var sheep: Node2D = spawn("res://scenes/characters/我的世界/羊.tscn", center)
	bow.state_machine.set_physics_process(false)
	sheep.state_machine.set_physics_process(false)
	bow.set_physics_process(false)
	sheep.set_physics_process(false)
	await physics_frame
	await process_frame
	await create_timer(0.25).timeout
	world.set_process(false)
	world.set_physics_process(false)
	bow.set_process(false)
	sheep.set_process(false)
	game.now_stop_state = true
	var baseline: Image = await rendered_frame()
	var size: Vector2i = baseline.get_size()
	var body := Rect2i(Vector2i(size.x/2-50, size.y/2-45), Vector2i(100, 110))
	var roi := Rect2i(Vector2i(size.x/2-180, size.y/2-140), Vector2i(360, 280))
	bow.rng.seed = 317
	bow.spawn_heaven_rift(center, Vector2.RIGHT)
	var rift: Node2D = _rifts()[0]
	rift.set_process(false)
	rift._age = 0.7 # Inspect mature refraction after the short birth/debris phase.
	rift._sync_visual()
	rift._surface.visible = false
	rift._warp_material.set_shader_parameter("warp_strength", 0.0)
	var identity: Image = await rendered_frame()
	check(diff_pixels(baseline, identity, roi) == 0, "zero-strength refraction cannot hide real actor pixels")
	rift._surface.visible = true
	var with_opening: Image = await rendered_frame()
	var core: Vector2i = actor_core_delta(baseline, with_opening, body)
	check(core.x > 50 and core.y == 0, "opaque starfield is behind the real actor, not cutting through its body")
	rift._warp_material.set_shader_parameter("warp_strength", rift.WARP_STRENGTH)
	var bent: Image = await rendered_frame()
	var mass_before: int = actor_mass(baseline, body)
	var mass_after: int = actor_mass(bent, body)
	check(diff_pixels(with_opening, bent, roi) > 100, "active refraction visibly bends the real completed scene")
	check(mass_before > 150 and mass_after > int(float(mass_before) * 0.75), "refraction preserves the actor rather than replacing it with grass/background")
	var ui_ink: int = 0
	var ui_changed: int = 0
	for y in range(size.y/2-110, size.y/2-75):
		for x in range(size.x/2-45, size.x/2+45):
			var c: Color = with_opening.get_pixel(x,y)
			if white(c) > 0.6 or maxf(maxf(c.r,c.g),c.b) < 0.001:
				ui_ink += 1
				if colour_delta(c, bent.get_pixel(x,y)) > 0.01:
					ui_changed += 1
	check(ui_ink > 20 and ui_changed == 0, "health-bar/UI ink is unchanged; nearby world background may bend")
	print("ACTOR_PIXELS: core_checked=%d core_hidden=%d visible_before=%d visible_after=%d" % [core.x, core.y, mass_before, mass_after])
	# Capture the naked fracture, the real actor crossing it, and smooth closing.
	sheep.graphics.hide()
	if sheep.health_bar != null: sheep.health_bar.hide()
	var bare: Image = await rendered_frame()
	sheep.graphics.show()
	if sheep.health_bar != null: sheep.health_bar.show()
	rift._age = 3.0
	rift._sync_visual()
	rift._rift_material.set_shader_parameter("cosmic_time", 0.0)
	rift._exterior_material.set_shader_parameter("cosmic_time", 0.0)
	var closing: Image = await rendered_frame()
	var comparison := Image.create(1080, 280, false, baseline.get_format())
	comparison.blit_rect(bare, roi, Vector2i.ZERO)
	comparison.blit_rect(bent, roi, Vector2i(360, 0))
	comparison.blit_rect(closing, roi, Vector2i(720, 0))
	export_image(comparison, "heavenfall_fractures_actual.png")
	# Check actual map-edge rendering: the crack continues past the boundary,
	# but an out-of-bounds actor must NOT be restored by a late backbuffer copy.
	rift.queue_free()
	await process_frame
	var edge: Vector2 = Vector2(arena.end.x-1.0, center.y)
	camera.position = edge
	sheep.global_position = edge + Vector2(18, 0)
	if sheep.health_bar != null: sheep.health_bar.hide()
	await physics_frame
	await process_frame
	var edge_baseline: Image = await rendered_frame()
	bow.rng.seed = 81
	bow.spawn_heaven_rift(edge, Vector2.RIGHT)
	rift = _rifts()[0]
	rift.set_process(false)
	rift._age = 0.7 # The boundary comparison is of an opened fracture, not its empty birth frame.
	rift._sync_visual()
	rift._surface.visible = false
	rift._warp_material.set_shader_parameter("warp_strength", 0.0)
	var edge_identity: Image = await rendered_frame()
	print("EDGE_IDENTITY_CHANGED=", diff_pixels(edge_baseline, edge_identity, roi), " actor_position=", sheep.global_position)
	check(diff_pixels(edge_baseline, edge_identity, roi) == 0, "refraction cannot resurrect map-clipped character pixels")
	rift._surface.visible = true
	var edge_opening: Image = await rendered_frame()
	check(rift._exterior_surface.visible, "out-of-map fracture continuation is enabled without disabling map clipping")
	var exterior := Rect2i(Vector2i(size.x/2+8, size.y/2-100), Vector2i(150, 200))
	check(diff_pixels(edge_baseline, edge_opening, exterior) > 10, "fracture remains visible across the actual map boundary")
	print("HEAVENFALL ACTOR RESULT: %d/%d passed" % [checks-failures, checks])
	finish(0 if failures == 0 else 1)
