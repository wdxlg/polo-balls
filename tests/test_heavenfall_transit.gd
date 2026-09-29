extends "res://tests/test_heavenfall_actor_refraction.gd"
# Complete action on the real World, original Camera2D, and default window.
var bow: Node2D
var victim: Node2D
var rift: Node2D
var center: Vector2
var movie: Image
var movie_index: int = 0
var frame_size: Vector2i
var render: bool = false


func sample_frame() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func record_frame() -> void:
	if not render or OS.get_cmdline_user_args().has("--no-filmstrip"): return
	var image: Image = await sample_frame()
	if root.use_hdr_2d and RenderingServer.get_current_rendering_method() != "gl_compatibility":
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				image.set_pixel(x, y, image.get_pixel(x, y).linear_to_srgb())
	image.convert(Image.FORMAT_RGBA8)
	if movie == null:
		frame_size = image.get_size()
		movie = Image.create(frame_size.x * 8, frame_size.y * 9, false, Image.FORMAT_RGBA8)
	if movie_index < 72:
		movie.blit_rect(image, Rect2i(Vector2i.ZERO, frame_size), Vector2i(movie_index % 8, movie_index / 8) * frame_size)
		movie_index += 1


func tick_action(delta: float) -> void:
	bow._advance_rift_transit(delta)
	if is_instance_valid(rift) and not rift.is_queued_for_deletion():
		rift.set_process(false)
		rift._process(delta)
	for ring: Node in get_nodes_in_group("HeavenfallArrivalRing"):
		ring.set_process(false)
		ring._process(delta)


func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Camera_Move = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0, true)
	create_timer(160.0, true, false, true).timeout.connect(func(): finish(2))
	render = DisplayServer.get_name() != "headless"
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world, CONNECT_ONE_SHOT)
	root.add_child(world)
	world.control.hide()
	await create_timer(0.5).timeout
	center = world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	# Normal map-centering / toolbar controls, not a replacement preview camera.
	world.mouse_offset = Vector2.ZERO
	world.toolbar_zoom_multiplier = 1.0
	world.camera_2d.position_smoothing_enabled = false
	world.process_always(0.0)
	world.camera_2d.global_position = center
	world.camera_2d.reset_smoothing()
	world.camera_2d.force_update_scroll()
	bow = spawn("res://scenes/characters/我的世界/天堂陨落长弓.tscn", center + Vector2(-48, 16))
	victim = spawn("res://scenes/characters/我的世界/羊.tscn", center + Vector2(36, 28), "Team1")
	for actor: Node in [bow, victim]:
		actor.state_machine.set_physics_process(false)
		actor.set_physics_process(false)
	await create_timer(0.25).timeout
	bow.set_process(false)
	victim.set_process(false)
	bow.facing = Vector2.RIGHT
	bow.drawing = 0.0
	bow.visual_mob()
	victim.visual_mob()
	bow.rng.seed = 317
	bow.spawn_heaven_rift(center + Vector2(10, 16), Vector2.RIGHT)
	rift = _rifts().back()
	rift.set_process(false)
	rift._age = rift.opening_time
	rift._sync_visual()
	await physics_frame
	var landing: Vector2 = rift.landing
	var start: Vector2 = bow.global_position
	print("TRANSIT_RING_RANGE: landing=", landing, " victim=", victim.global_position, " distance=", landing.distance_to(victim.global_position), " radius=", bow.rift_blast_radius)
	var hp: float = bow.health
	var enemy_hp: float = victim.health
	var material: Material = bow.image.material
	var image_transform: Transform2D = bow.image.transform
	var graphics_color: Color = bow.graphics.modulate
	var collision_radius: float = bow.collision_shape_2d.shape.radius
	for i in range(6): await record_frame()
	check(not bow.receive_positional_damage(40, start, false, victim), "incoming hit is dodged, not applied before the animation")
	check(bow.health == hp and bow.is_rift_transiting(), "one transit starts with unchanged health")
	var transit: Node2D = bow._rift_transit
	transit.set_process(false)
	check(bow.global_position == start and victim.health == enemy_hp, "no immediate teleport or premature area damage")
	check(rift.is_reserved() and not rift.is_open() and not rift._closed, "reservation disables reuse without beginning closure")
	var held_width: float = rift._closure_factor()
	var time0: float = transit.elapsed
	var rift_time0: float = rift._age
	game.now_stop_state = true
	tick_action(0.2)
	check(transit.elapsed == time0 and rift._age == rift_time0, "pause freezes transit and reserved aperture")
	game.now_stop_state = false
	bow.direction = Vector2.RIGHT
	bow.Repel = Vector2(100, 100)
	bow.move(100.0, 0.1)
	bow.stand(0.1)
	check(bow.global_position == start, "launch visual does not move the body or inherit repel")
	bow._cool = 0.0
	bow.step_mob(0.1)
	check(bow.drawing == 0.0 and _bolts().is_empty(), "the stretched body cannot draw or shoot during transit")
	bow.take_damage(50)
	check(bow.health == hp and bow._rift_transit == transit, "repeated contacts reuse the same dodge, not another charge")
	# Sixty-Hz action frames, captured at the original physical render scale.
	for i in range(1, 19):
		tick_action(1.0 / 60.0)
		if i == 3:
			check(transit.pose_scale.x <= 0.15 and transit.pose_scale.y >= 2.7, "body becomes vertically thin and long before the ascent")
			check(float(transit.white_material.get_shader_parameter("whitening")) == 1.0, "the narrow launch body is pure white")
			check(bow.global_position == start, "the logical body remains inside the arena during launch")
			if render:
				var white_frame: Image = await sample_frame()
				var projected: Rect2 = (root.get_stretch_transform() * transit.sprite.get_global_transform_with_canvas()) * transit.sprite.get_rect()
				var bounds: Rect2i = Rect2i(projected.position.floor(), projected.size.ceil()).intersection(Rect2i(Vector2i.ZERO, white_frame.get_size()))
				var white_count: int = 0
				for y in range(bounds.position.y, bounds.end.y):
					for x in range(bounds.position.x, bounds.end.x):
						if white(white_frame.get_pixel(x,y)) > 0.90: white_count += 1
				check(white_count > 20, "GPU renders the white stretched body, not only transform metadata")
		if i == 7:
			var bounds: Rect2 = (root.get_stretch_transform() * transit.sprite.get_global_transform_with_canvas()) * transit.sprite.get_rect()
			check(bounds.end.y < 0.0 and not transit.crossed, "the entire body leaves the real screen before reappearing")
		if i == 8:
			check(transit.crossed and transit.last_exit_bounds.end.y < 0.0, "crossing is recorded only beyond the viewport top")
			check(bow.global_position.is_equal_approx(landing), "body moves once to the independently validated safe landing")
			check(bool(transit.white_material.get_shader_parameter("clip_opening")), "emergence is clipped to the rift mouth rather than popping in")
			check(victim.health < enemy_hp and rift.is_reserved(), "arrival attacks immediately while the white body is still emerging")
			check(get_nodes_in_group("HeavenfallArrivalRing").size() == 1 and bow.is_rift_transiting(), "wave starts on arrival, not after elastic recovery")
		if i == 12:
			check(transit.pose_scale.x > 1.0 and transit.pose_scale.y < 1.0, "restoration has a real elastic overshoot, not linear scaling")
			check(is_equal_approx(rift._closure_factor(), held_width), "reserved opening keeps its width while the universe still animates")
		await record_frame()
	check(not bow.is_rift_transiting() and bow.TRANSIT.TOTAL_TIME <= 0.29, "entire transit now takes about 0.28 seconds instead of 0.55")
	check(victim.health <= enemy_hp - 2.0, "arrival tick deals its fixed 2 damage, and later ticks follow")
	check(bow.graphics.modulate == graphics_color and bow.image.material == material and bow.image.transform == image_transform, "original visibility, material and exact sprite transform are restored")
	check(bow.collision_shape_2d.shape.radius == collision_radius, "visual stretching never changes the collision shape")
	check(rift._closed and not rift.is_reserved(), "rift only begins fast closure after the circle attack")
	var rings: Array[Node] = get_nodes_in_group("HeavenfallArrivalRing")
	check(rings.size() == 1, "exactly one arrival circle is created")
	check(is_equal_approx(bow.rift_blast_radius, 38.0), "circle is reduced again to 0.8x of the previous 47.5")
	var ring: Node2D = rings[0]
	check(is_equal_approx(ring._radius, 38.0), "the drawn range matches the smaller attack radius")
	check(ring.tick_count == 5 and is_equal_approx(ring.tick_interval, 0.09), "arrival circle keeps dealing damage on five ticks")
	check(ring.ticks_done() >= 3, "the circle continues ticking while it expands instead of firing once")
	check(ring.get_script().get_base_script().resource_path.ends_with("重锤落地冲击.gd"), "circle reuses the actual mace effect implementation")
	check(ring._blocks.is_empty() and is_equal_approx(ring.ring_end_scale, 1.58), "mace expansion stays unchanged, without unrelated ground debris")
	check(ring._ring_palette[0] == Color("14534f") and ring._ring_palette[1] == Color("83dbd6") and ring._ring_palette[2] == Color("c8c8c8"), "ring uses the bow's dark teal, cyan and silver")
	check(ring._fill.z_index < world.z_index and ring._fill_material.get_shader_parameter("cosmic_atlas") == rift.COSMIC_ATLAS, "native cosmic disk is behind actors and uses the original atlas")
	var knock: Node = null
	for child: Node in victim.get_children():
		if child.get_script() != null and child.get_script().resource_path.ends_with("knockback_effect.gd"): knock = child
	check(knock != null and knock.distance <= 3.01 and knock.speed <= 120.01, "each tick only nudges with a 3-unit outward knockback")
	var hp_after: float = victim.health
	bow._apply_rift_dodge(start, landing, rift.rift_id, rift._points[0])
	check(not bow.is_rift_transiting() and victim.health == hp_after and get_nodes_in_group("HeavenfallArrivalRing").size() == 1, "duplicate reliable transit event cannot repeat the attack")
	if render:
		# Actual white sheep body is unchanged by the opaque disk. Hide only the
		# circle's own fill, not actors; keep ring/streaks identical in both frames.
		# Damage feedback is a separate real-time tween; freeze the identical
		# actor/particles in both renders rather than mislabel flash decay as occlusion.
		# World camera framing tweens continue despite set_process(false). A/B
		# captures must hold the very same actual camera matrix, not compare two
		# shifted views (the initial comparison was translated by -2,-3 pixels).
		var frozen_canvas: Transform2D = root.canvas_transform
		var camera_enabled: bool = world.camera_2d.enabled
		world.camera_2d.enabled = false
		root.canvas_transform = frozen_canvas
		var previous_mode: int = world.process_mode
		world.process_mode = Node.PROCESS_MODE_DISABLED
		if victim.hit_white_tween != null: victim.hit_white_tween.pause()
		victim.hit_white_method(0.0)
		await process_frame
		print("RING_DEPTH: world=",world.z_index," fill=",ring._fill.z_index," actor=",victim.z_index," graphics=",victim.graphics.z_index)
		ring._fill.hide()
		var without_fill: Image = await sample_frame()
		ring._fill.show()
		var with_fill: Image = await sample_frame()
		check(root.canvas_transform == frozen_canvas, "compositing A/B holds the identical actual-camera transform")
		var body_rect: Rect2 = (root.get_stretch_transform() * victim.image.get_global_transform_with_canvas()) * victim.image.get_rect()
		var area: Rect2i = Rect2i(body_rect.position.floor(), body_rect.size.ceil()).intersection(Rect2i(Vector2i.ZERO, with_fill.get_size()))
		export_image(without_fill.duplicate(), "heavenfall_ring_without.png")
		export_image(with_fill.duplicate(), "heavenfall_ring_with.png")
		print("RING_ACTOR_DEBUG: area=",area," rect=",victim.image.get_rect()," modulate=",victim.image.modulate," self=",victim.image.self_modulate," gmod=",victim.graphics.modulate," transform=",victim.image.global_transform)
		var actor_pixels: Vector2i = actor_core_delta(without_fill, with_fill, area)
		check(actor_pixels.x > 15 and actor_pixels.y == 0, "star-filled attack circle does not cover the actual sheep body")
		check(delta_count_all(without_fill, with_fill) > 1000, "GPU circle really contains a visible cosmic fill")
		export_image(with_fill.duplicate(), "heavenfall_arrival_ring.png")
		print("TRANSIT_ACTOR_PIXELS: checked=",actor_pixels.x," covered=",actor_pixels.y)
		world.process_mode = previous_mode
		world.camera_2d.enabled = camera_enabled
		world.camera_2d.force_update_scroll()
	for i in range(28):
		tick_action(1.0 / 60.0)
		await record_frame()
	check(not is_instance_valid(rift) or rift.is_queued_for_deletion(), "spent rift is removed after its 0.24-second geometric closure")
	var landed: float = enemy_hp - victim.health
	check(landed > 0.0 and landed <= 10.0 and is_zero_approx(fmod(landed, 2.0)), "the circle only ever deals its fixed 2-per-tick damage, no stray extra hit")
	var settled: float = victim.health
	for i in range(10):
		tick_action(1.0 / 60.0)
	check(victim.health == settled, "after its five ticks the circle stops dealing damage")
	print("TRANSIT_TICK_DAMAGE: landed=", landed, " hp_after=", hp_after, " settled=", settled)
	if movie != null:
		check(movie.save_png("user://heavenfall_transit_frames.png") == OK, "real default-view animation frames saved")
		print("TRANSIT_FRAMES: count=",movie_index," size=",frame_size)
	# Cleanup interruption and ownership: no ghost, hidden body or reserved leak.
	for node: Node in get_nodes_in_group("HeavenfallArrivalRing"): node.queue_free()
	bow._rift_cool = 0.0
	bow._rift_grace = 0.0
	bow.global_position = start
	bow.spawn_heaven_rift(center + Vector2(-5, -20), Vector2.UP)
	var interrupted: Node2D = _rifts().back()
	interrupted.set_process(false)
	interrupted._age = interrupted.opening_time
	check(bow._try_rift_dodge(), "another available charge starts after cooldown reset")
	bow._advance_rift_transit(0.08)
	bow._cancel_rift_transit()
	check(not bow.is_rift_transiting() and bow.graphics.modulate == graphics_color and interrupted._closed, "interruption restores the body and releases the reserved opening")
	# Reserved near-expiry cracks stay open for the action, then time out safely
	# if their owner never completes the transit.
	bow.spawn_heaven_rift(center, Vector2.RIGHT)
	var expiring: Node2D = _rifts().back()
	expiring.set_process(false)
	expiring._age = expiring._life - 0.01
	check(expiring.reserve_transit(), "a valid nearly-expired opening can be reserved once")
	var near_width: float = expiring._closure_factor()
	expiring._process(0.7)
	check(expiring.is_reserved() and not expiring.is_queued_for_deletion() and is_equal_approx(expiring._closure_factor(), near_width), "normal expiry cannot shut on an emerging body")
	expiring._process(1.4)
	check(expiring._closed and not expiring.is_reserved(), "orphaned reservation has a bounded cleanup timeout")
	# Clients replay the animation/ring but never apply server damage.
	await process_frame
	var client_bow: Node2D = spawn("res://scenes/characters/我的世界/天堂陨落长弓.tscn", start)
	client_bow.state_machine.set_physics_process(false)
	client_bow.set_process(false)
	client_bow.set_multiplayer_authority(2)
	var before_client: float = victim.health
	client_bow._apply_rift_dodge(start, landing)
	client_bow._advance_rift_transit(client_bow.TRANSIT.TOTAL_TIME + 0.01)
	check(victim.health == before_client and not client_bow.is_rift_transiting(), "non-authority visual replay cannot deal a second area hit")
	client_bow.queue_free()
	await process_frame
	# Death while launching restores visuals and does not leave an arrival attack.
	var before_death: float = victim.health
	var death_rift: Node2D = _mature_rift_fixture(bow, landing)
	bow._apply_rift_dodge(start, landing, death_rift.rift_id, landing)
	bow.health = 0
	bow._advance_rift_transit(1.0)
	check(not bow.is_rift_transiting() and bow.graphics.modulate == graphics_color and victim.health == before_death, "death cancels transit with no ghost or posthumous attack")
	bow.health = hp
	await test_exit_views(start, landing)
	root.size = Vector2i(540, 960)
	bow.global_position = start
	bow._rift_cool = 0.0
	bow._rift_grace = 0.0
	bow.spawn_heaven_rift(center, Vector2.UP)
	var blocked_rift: Node2D = _rifts().back()
	blocked_rift.set_process(false)
	blocked_rift._age = blocked_rift.opening_time
	check(bow._try_rift_dodge(), "destination is clear when the departure is selected")
	var wall: StaticBody2D = _mk_wall(blocked_rift.landing)
	(wall.get_child(0).shape as RectangleShape2D).size = Vector2(130, 130)
	await physics_frame
	bow._advance_rift_transit(bow.TRANSIT.EXIT_AT + 0.01)
	check(not bow.is_rift_transiting() and bow.global_position == start and blocked_rift._closed, "newly blocked destination aborts safely without an arrival attack")
	wall.queue_free()
	await process_frame
	# Previous camera/arrival cases leave real ticking rings alive for 0.46s.
	# Isolate the single-tick displacement fixture from their delayed extra hits.
	print("TRANSIT_CLEAR_OLD_RINGS: ", get_nodes_in_group("HeavenfallArrivalRing").size())
	for old_ring: Node in get_nodes_in_group("HeavenfallArrivalRing"):
		old_ring.queue_free()
	await process_frame
	var dummy: Node2D = _mk_enemy(center + Vector2(35, -25))
	dummy.Speed = 0.0
	dummy.default_properties.Speed = 0.0
	dummy.Can_Attack = false
	dummy.Can_Skill = false
	dummy.direction = Vector2.ZERO
	dummy.state_machine.set_physics_process(true)
	await physics_frame
	var dummy_start: Vector2 = dummy.global_position
	# 世界自己会刷出单位挤动假人；先挪开，只量这一跳的位移。
	for other: Node in get_nodes_in_group("Ball"):
		if other == bow or other == victim or other == dummy:
			continue
		(other as Node2D).global_position = Vector2(-3000, -3000)
	await physics_frame
	dummy_start = dummy.global_position
	bow._rift_blast_damage(dummy_start + Vector2(-20, 0))
	# Real state-machine physics, not manual move_and_slide from a render coroutine.
	await create_timer(0.2).timeout
	var distance: float = dummy.global_position.distance_to(dummy_start)
	# The shared controller adds an 85-ms decelerating control-recovery stage after
	# the nominal 3-unit nudge, so assert a tiny displacement, not an exact endpoint.
	check(distance > 0.5 and distance <= 12.0, "a single tick only nudges the enemy a little way outward")
	print("TRANSIT_KNOCKBACK_DISTANCE: ", distance)
	dummy.queue_free()
	var mace: Node2D = load("res://scripts/effects/我的世界/重锤落地冲击.gd").new()
	check(mace._ring_palette == PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]) and mace._ring_color(1, 0.4) == Color(1,1,1,0.4), "original mace retains its exact white palette and alpha")
	mace.free()
	print("HEAVENFALL TRANSIT RESULT: %d/%d passed" % [checks-failures, checks])
	finish(0 if failures == 0 else 1)


func delta_count_all(a: Image, b: Image) -> int:
	var n: int = 0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			if colour_delta(a.get_pixel(x,y), b.get_pixel(x,y)) > 0.01: n += 1
	return n


func test_exit_views(start: Vector2, landing: Vector2) -> void:
	var original_size: Vector2i = root.size
	for sample: Dictionary in [{"name":"ordinary_pan", "size":original_size,"zoom":0.7,"pan":Vector2(-20,15)}, {"name":"zoom_in", "size":original_size,"zoom":1.4,"pan":Vector2(25,-10)}, {"name":"resized", "size":Vector2i(720,1280),"zoom":1.0,"pan":Vector2.ZERO}, {"name":"letterbox", "size":Vector2i(960,640),"zoom":0.65,"pan":Vector2.ZERO}]:
		root.size = sample["size"]
		world.mouse_offset = sample["pan"]
		world.toolbar_zoom_multiplier = sample["zoom"]
		world.process_always(0.0)
		world.camera_2d.force_update_scroll()
		await process_frame
		bow.global_position = start
		var view_rift: Node2D = _mature_rift_fixture(bow, landing)
		bow._apply_rift_dodge(start, landing, view_rift.rift_id, landing)
		var travel: Node2D = bow._rift_transit
		travel.set_process(false)
		bow._advance_rift_transit(travel.EXIT_AT + 0.002)
		check(travel.last_exit_bounds.end.y < -20.0, sample["name"] + ": whole body exits the actual viewport under camera/window transforms")
		bow._cancel_rift_transit()

