extends "res://tests/test_heavenfall_actor_refraction.gd"
# Actual-world birth, actual floor-pixel chips, and one fast arrival sequence.
var bow: Node2D
var rift: Node2D
var debris: Node2D
var render: bool = false
var film: Image
var frame_size: Vector2i
var frame_index: int = 0


func frame() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func changed_stats(before: Image, after: Image, center_pixel: Vector2) -> Vector2:
	var count: int = 0
	var farthest: float = 0.0
	for y in range(before.get_height()):
		for x in range(before.get_width()):
			if colour_delta(before.get_pixel(x,y), after.get_pixel(x,y)) > 0.025:
				count += 1
				farthest = maxf(farthest, Vector2(x,y).distance_to(center_pixel))
	return Vector2(count, farthest)


func record() -> void:
	if not render: return
	var image: Image = await frame()
	if root.use_hdr_2d and RenderingServer.get_current_rendering_method() != "gl_compatibility":
		for y in range(image.get_height()):
			for x in range(image.get_width()): image.set_pixel(x,y,image.get_pixel(x,y).linear_to_srgb())
	image.convert(Image.FORMAT_RGBA8)
	if film == null:
		frame_size = image.get_size()
		film = Image.create(frame_size.x * 8, frame_size.y * 8, false, Image.FORMAT_RGBA8)
	if frame_index < 64:
		film.blit_rect(image, Rect2i(Vector2i.ZERO,frame_size), Vector2i(frame_index % 8, frame_index / 8) * frame_size)
		frame_index += 1


func step_scene(delta: float) -> void:
	bow._advance_rift_transit(delta)
	if is_instance_valid(rift) and not rift.is_queued_for_deletion():
		rift.set_process(false)
		rift._process(delta)
	if is_instance_valid(debris) and not debris.is_queued_for_deletion(): debris._process(delta)
	for ring: Node in get_nodes_in_group("HeavenfallArrivalRing"):
		ring.set_process(false)
		ring._process(delta)


func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Camera_Move = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(160.0,true,false,true).timeout.connect(func(): finish(2))
	render = DisplayServer.get_name() != "headless"
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world, CONNECT_ONE_SHOT)
	root.add_child(world)
	world.control.hide()
	await create_timer(0.55).timeout
	var center: Vector2 = world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	world.mouse_offset = Vector2.ZERO
	world.toolbar_zoom_multiplier = 1.0
	world.camera_2d.position_smoothing_enabled = false
	world.process_always(0.0)
	world.camera_2d.global_position = center
	world.camera_2d.force_update_scroll()
	bow = spawn("res://scenes/characters/我的世界/天堂陨落长弓.tscn", center + Vector2(-50,10))
	var victim: Node2D = spawn("res://scenes/characters/我的世界/羊.tscn", center + Vector2(35,28), "Team1")
	for actor: Node in [bow,victim]:
		actor.state_machine.set_physics_process(false)
		actor.set_physics_process(false)
	await create_timer(0.25).timeout
	bow.set_process(false)
	victim.set_process(false)
	bow.facing = Vector2.RIGHT
	bow.visual_mob()
	victim.visual_mob()
	# Freeze the real camera pose for A/B and frame capture. No replacement
	# camera, magnified viewport or disabled project stretch is used.
	var actual_canvas: Transform2D = root.canvas_transform
	world.camera_2d.enabled = false
	root.canvas_transform = actual_canvas
	bow.rng.seed = 317
	bow.spawn_heaven_rift(center, Vector2.RIGHT)
	rift = _rifts().back()
	rift.set_process(false)
	debris = rift._birth_debris.get_ref() if rift._birth_debris != null else null
	if is_instance_valid(debris): debris.set_process(false)
	check(is_zero_approx(rift._opening_factor()), "new fracture starts closed at the central origin")
	var quarter: float
	var half: float
	rift._age = rift.OPEN_TIME * 0.25
	quarter = rift._opening_factor()
	rift._age = rift.OPEN_TIME * 0.5
	half = rift._opening_factor()
	check(quarter > 0.30 and quarter < 0.40 and half > 0.58 and half < 0.68, "large crack tears gradually instead of opening almost fully in the first frames")
	check(is_equal_approx(rift.opening_time, 0.5), "main impact crack takes half a second to open")
	rift._age = 0.15
	check(rift._opening_factor() < 0.45, "old full-open time now shows less than half the crack")
	for progress: float in [0.1, 0.3, 0.6, 0.9, 1.0]:
		rift._age = rift.opening_age_for_progress(progress)
		check(absf(rift._opening_factor() - progress) < 0.0001, "debris inverse clock matches the slower opening front")
	var rain_crack: Node2D = load("res://scripts/characters/我的世界/new6/heavenfall_rain_rift.gd").new()
	world.add_child(rain_crack)
	rain_crack.configure_impact(center, 901, 10.0)
	rain_crack.set_process(false)
	rain_crack._age = 0.075
	check(is_equal_approx(rain_crack.opening_time, 0.15) and is_equal_approx(rain_crack._opening_factor(), 0.875), "small rain crack retains its original 0.15-second cubic opening")
	rain_crack.queue_free()
	var branches_wait: bool = true
	var fine_count: int = 0
	for crack: Dictionary in rift._cached_cracks:
		var path: PackedVector2Array = crack["points"]
		if int(crack["id"]) != rift.CENTER_ID and path[0].distance_to(center) > 0.01:
			fine_count += 1
			if float(crack["samples"][0]["growth_distance"]) <= 1.0: branches_wait = false
	check(fine_count > 0 and branches_wait, "secondary branches inherit their parent's distance instead of appearing as detached cuts")
	rift._age = 0.0
	rift._sync_visual()
	if render:
		# Finish one real floor readback without letting the rift/debris clock run.
		await frame()
		await frame()
		check(is_instance_valid(debris) and not debris._sampling and debris._blocks.size() >= 6 and debris._blocks.size() <= 9, "birth emits only six to nine real-floor chips")
		await check_birth_shader(center, true)
		await check_birth_shader(center, false)
		var exact: bool = true
		var low: bool = true
		var sample_image: Image = debris._snapshot.get("image")
		for block: Dictionary in debris._blocks:
			exact = exact and (block["color"] as Color).is_equal_approx(sample_image.get_pixelv(block["sample_pixel"]))
			var peak: Dictionary = debris.particle_pose(block, float(block["delay"]) + float(block["flight"]) * 0.5)
			low = low and float(peak["height"]) >= 3.0 and float(peak["height"]) <= 6.0 and float(block["size"]) <= 2.3
		check(exact, "each chip uses the captured pixel at its own crack location")
		check(low, "small chips follow low 3-to-6-unit parabolas, not the mace's high arc")
		var debris_time: float = debris._elapsed
		game.now_stop_state = true
		debris._process(0.2)
		check(debris._elapsed == debris_time, "battle pause also freezes the new debris")
		game.now_stop_state = false
		rift._space_warp.show()
		rift._space_copy.copy_mode = BackBufferCopy.COPY_MODE_RECT
		debris.show()
	# Rewind only the deterministic fixture clock, then capture the actual birth
	# followed by the faster teleport and half-size immediate arrival wave.
	rift._age = 0.0
	rift._sync_visual()
	if is_instance_valid(debris): debris._elapsed = 0.0
	for i in range(6): await record()
	for i in range(31):
		step_scene(1.0/60.0)
		await record()
	var hp: float = victim.health
	check(bow._try_rift_dodge(), "formed connected rift is available to the fast transit")
	for i in range(18):
		step_scene(1.0/60.0)
		if i == 7:
			check(bow.is_rift_transiting() and victim.health < hp and get_nodes_in_group("HeavenfallArrivalRing").size() == 1, "wave and damage start at arrival while white emergence is still underway")
		await record()
	for i in range(24):
		step_scene(1.0/60.0)
		await record()
	check(not bow.is_rift_transiting(), "faster transit restores the normal bow")
	if film != null:
		check(film.save_png("user://heavenfall_refined_frames.png") == OK, "default-view birth/debris/fast-arrival filmstrip saved")
		print("REFINED_FRAMES: count=",frame_index," size=",frame_size)
	# Death/consume during birth must stop extending the tips, not keep tearing
	# outward while the mouth is already closing.
	var script: Script = load("res://scripts/characters/我的世界/new6/heavenfall_rift.gd")
	var aborted: Node2D = script.new()
	world.add_child(aborted)
	aborted.configure(null, 803, PackedVector2Array([center,center+Vector2(30,0)]), [], center, 6.0)
	aborted.set_process(false)
	aborted._age = 0.04
	var before_close: float = aborted._opening_factor()
	aborted.consume()
	aborted._process(0.08)
	check(is_equal_approx(aborted._opening_factor(), before_close), "early closure freezes the growing front instead of extending it")
	aborted.queue_free()
	if render: await check_distinct_floor_captures(center)
	await check_half_range(center)
	print("HEAVENFALL BIRTH RESULT: %d/%d passed" % [checks-failures,checks])
	finish(0 if failures == 0 else 1)


func check_birth_shader(center: Vector2, hdr: bool) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320,320)
	viewport.transparent_bg = true
	viewport.use_hdr_2d = hdr
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var layer := CanvasLayer.new()
	layer.scale = Vector2(3,3)
	layer.offset = Vector2(160,160) - center * 3.0
	viewport.add_child(layer)
	var test_rift: Node2D = rift.get_script().new()
	layer.add_child(test_rift)
	test_rift.configure(null, rift.rift_id, rift._points, rift._branches, rift.landing, 6.0)
	test_rift.set_process(false)
	var stats: Array[Vector2] = []
	var mesh_id: int = test_rift._surface.mesh.get_instance_id()
	for age: float in [0.0,0.10,0.25,0.40,0.50]:
		test_rift._age = age
		test_rift._sync_visual()
		test_rift._rift_material.set_shader_parameter("cosmic_time", 0.0)
		test_rift._rift_material.set_shader_parameter("closure", 1.0)
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = viewport.get_texture().get_image()
		var count: int = 0
		var radius: float = 0.0
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				if image.get_pixel(x,y).a > 0.10:
					count += 1
					radius = maxf(radius, Vector2(x,y).distance_to(Vector2(160,160)))
		stats.append(Vector2(count,radius))
		print("BIRTH_GPU: hdr=",hdr," age=",age," pixels=",count," radius_px=",radius)
	check(stats[0].x == 0 and stats[1].x > 0 and stats[1].x < stats[2].x and stats[2].x < stats[4].x, "GPU birth " + str(hdr) + ": actual alpha coverage grows from nothing")
	check(stats[1].y < stats[4].y * 0.60 and stats[2].y > stats[1].y, "GPU birth " + str(hdr) + ": early tips stay near the center in linear path-distance order")
	check(stats[3].x >= stats[4].x * 0.85, "GPU birth " + str(hdr) + ": final tenth of a second settles the extended tips")
	check(test_rift._surface.mesh.get_instance_id() == mesh_id, "GPU birth " + str(hdr) + ": cached geometry and star coordinates are not scaled")
	viewport.queue_free()
	await process_frame


func check_distinct_floor_captures(center: Vector2) -> void:
	# Paint two real floor-layer regions, then crack both IN THE SAME FRAME.
	# This exposes shared-snapshot rectangle/race bugs without colour-name lookup.
	var colors: Array[Color] = [Color("be4422"),Color("224dc0")]
	var effects: Array[Node2D] = []
	var floors: Array[Node2D] = []
	var tears: Array[Node2D] = []
	for i in range(2):
		var point: Vector2 = center + Vector2(-43 if i == 0 else 43,0)
		var floor: Polygon2D = Polygon2D.new()
		floor.polygon = PackedVector2Array([Vector2(-43,-43),Vector2(43,-43),Vector2(43,43),Vector2(-43,43)])
		floor.color = colors[i]
		floor.z_as_relative = false
		floor.z_index = -5
		world.add_child(floor)
		floor.global_position = point
		floors.append(floor)
		bow.rng.seed = 621 + i
		bow.spawn_heaven_rift(point,Vector2.RIGHT)
		var tear: Node2D = _rifts().back()
		tear.set_process(false)
		tears.append(tear)
		var effect: Node2D = tear._birth_debris.get_ref()
		effect.set_process(false)
		effects.append(effect)
	for i in range(5): await frame()
	for i in range(effects.size()):
		var effect: Node2D = effects[i]
		var actual: bool = effect._blocks.size() >= 6
		for block: Dictionary in effect._blocks:
			var c: Color = block["color"]
			actual = actual and colour_delta(c,colors[i]) < 0.015
		check(actual, "same-frame floor capture " + str(i) + " uses its own rendered background, not the other rift's colour")
		check((effect._snapshot["rect"] as Rect2).encloses(effect._capture_rect), "snapshot bounds enclose all requested chip positions")
	var stopped: Node2D = effects[0]
	stopped.stop_emitting(0.0)
	var no_late: bool = true
	for block: Dictionary in stopped._blocks:
		no_late = no_late and stopped.particle_pose(block, float(block["delay"]) + 0.02).is_empty()
	check(no_late, "interrupted birth never emits chips from unreached parts of a crack")
	var sampler: Node = world.get_node("GroundSurfaceSampler")
	var first: Dictionary = await sampler.capture(effects[1]._capture_rect)
	var again: Dictionary = await sampler.capture(effects[1]._capture_rect)
	check(first.get("image") == again.get("image"), "identical same-frame floor requests still share one readback")
	for node: Node in effects + tears + floors: node.queue_free()
	await process_frame


func check_half_range(center: Vector2) -> void:
	var inside: Node2D = _mk_enemy(center+Vector2(30,-15))
	var outside: Node2D = _mk_enemy(center+Vector2(85,-15))
	await physics_frame
	var inner_hp: float = inside.health
	var outer_hp: float = outside.health
	bow._rift_blast_damage(center+Vector2(0,-15))
	check(inside.health < inner_hp and outside.health == outer_hp, "half-sized circle also halves gameplay reach, not just its picture")
	inside.queue_free()
	outside.queue_free()
