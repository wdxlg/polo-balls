extends "res://tests/test_diamond_spear_live.gd"
## Actual GPU frame audit at 30 Hz physics / up to 144 Hz rendering.
func run() -> void:
	var center:Vector2 = await setup()
	Engine.physics_ticks_per_second = 30
	Engine.max_fps = 144
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	create_timer(30.0).timeout.connect(func(): finish(2))
	for i:int in range(12): await RenderingServer.frame_post_draw
	var a:Node2D = spawn(center+Vector2(-100,-70))
	var ea:Node2D = victim(a.global_position+Vector2(25,0))
	ea.collision_layer = 0
	a.state_machine.set_physics_process(false)
	a._momentum = 420.0
	a._attack_wait = 0.0
	a._sweep_wait = 10.0
	a._blink_wait = 10.0
	var b:Node2D = spawn(center+Vector2(-100,70))
	var eb:Node2D = victim(b.global_position+Vector2(0,16))
	eb.collision_layer = 0
	b.state_machine.set_physics_process(false)
	b._sweep_wait = 0.0
	b._blink_wait = 10.0
	b.Can_Attack = false
	await physics_frame
	await physics_frame
	# Warm the actual actors/materials, not just the empty world.
	for i:int in range(16): await RenderingServer.frame_post_draw
	# Warm attack-only effects/audio/materials too. A short sweep can otherwise
	# finish while the first-use shader/resource work stalls the sampling window.
	a.Attack()
	b._begin_sweep(eb)
	for i:int in range(36):
		if a._action!=a.Action.IDLE: a._tick_action(1.0/60.0)
		if b._action!=b.Action.IDLE: b._tick_action(1.0/60.0)
		a._apply_pose()
		b._apply_pose()
		await RenderingServer.frame_post_draw
	a._cancel_action()
	b._cancel_action()
	b.direction = Vector2.RIGHT
	b._facing = Vector2.RIGHT
	b._apply_pose()
	a._attack_wait = 0.0
	b._sweep_wait = 0.0
	await process_frame
	a.Attack()
	# Warmup ghosts may still be awaiting deferred deletion this frame. Audit
	# an actual newly spawned attack, never a stale warmup array entry.
	var ghost:Node2D
	for candidate:Variant in a._visual_nodes:
		if is_instance_valid(candidate) and not candidate.is_queued_for_deletion() and candidate.attack_echo and is_zero_approx(candidate.elapsed):
			ghost = candidate
			break
	check(is_instance_valid(ghost),"GPU fixture has a fresh attacking echo")
	check(b._begin_sweep(eb),"GPU fixture starts real moving sweep")
	a.state_machine.set_physics_process(true)
	b.state_machine.set_physics_process(true)
	var same_tick:int = 0
	var interpolated:int = 0
	var echo_subframes:int = 0
	var echo_changes:int = 0
	var last_physics:int = -1
	var last_pose:Transform2D
	var last_echo:float = 0.0
	var maximum_scale:float = 1.0
	var fraction_min:float = 1.0
	var fraction_max:float = 0.0
	var physics_start:int = Engine.get_physics_frames()
	var frames:int = 0
	var intermediate_fractions:int = 0
	var pose_mismatches:int = 0
	for i:int in range(90):
		await RenderingServer.frame_post_draw
		frames += 1
		var physics:int = Engine.get_physics_frames()
		var alpha:float = Engine.get_physics_interpolation_fraction()
		fraction_min = minf(fraction_min,alpha)
		fraction_max = maxf(fraction_max,alpha)
		maximum_scale = maxf(maximum_scale,b.image.scale.x/b._image_rest_scale.x)
		if b._action==b.Action.SWEEP:
			if alpha>0.001 and alpha<0.999: intermediate_fractions += 1
			var expected_angle:float = lerp_angle(b._render_from_angle,b._render_to_angle,alpha)+b.NATIVE_ROTATION_OFFSET
			if absf(wrapf(b.image.global_rotation-expected_angle,-PI,PI))>0.001: pose_mismatches += 1
			print("RENDER_SAMPLE alpha=",alpha," angle=",rad_to_deg(b.image.global_rotation-b.NATIVE_ROTATION_OFFSET)," from=",rad_to_deg(b._render_from_angle)," to=",rad_to_deg(b._render_to_angle)," clock=",b._render_clock," processing=",b.is_processing())
		# Before the first physics step both snapshots are identical; holding the
		# initial pose there is correct, not a failed interpolation frame.
		if physics==last_physics and b._action==b.Action.SWEEP and b._render_from_center.distance_to(b._render_to_center)>0.00001:
			same_tick += 1
			if not b.image.global_transform.is_equal_approx(last_pose): interpolated += 1
		if is_instance_valid(ghost) and ghost.elapsed>0.0 and ghost.elapsed<ghost.stroke_duration:
			if physics==last_physics:
				echo_subframes += 1
				if absf(ghost.sprite.position.x-last_echo)>0.00001: echo_changes += 1
			last_echo = ghost.sprite.position.x
		last_pose = b.image.global_transform
		last_physics = physics
	var physics_count:int = Engine.get_physics_frames()-physics_start
	check(frames>physics_count,"GPU rendered more frames than physics updates")
	check(intermediate_fractions>0 and pose_mismatches==0,"GPU draws genuine fractional angles rather than alternating whole physics poses")
	check(same_tick>0 and interpolated==same_tick,"sweep changes on every sampled render frame between physics ticks")
	check(echo_subframes>0 and echo_changes>0,"attacking echo visibly animates between physics ticks")
	check(fraction_max-fraction_min>0.3,"render interpolation fraction actually advances with project settings")
	check(maximum_scale>1.9 and maximum_scale<=2.0001,"actual rendered sweep reaches its enlarged midpoint without scale overshoot")
	print("RENDER_METRICS frames=",frames," physics=",physics_count," sweep_subframes=",same_tick," sweep_changes=",interpolated," echo_subframes=",echo_subframes," echo_changes=",echo_changes," peak=",maximum_scale," fraction_range=",fraction_min,"..",fraction_max)
	finish(0 if failures==0 else 1)
