extends "res://tests/test_battle_recording.gd"
class Witness:
	extends Node2D
	var elapsed:float = 0.0
	var enabled:bool = false
	var delay_ms:int = 0
	var steps:Array = []
	var tick_origin:int = 0
	var tick_elapsed:float = 0.0
	var deadline_fired:float = -1.0
	var beacon:AudioStreamPlayer
	var was_white:bool = false
	var marker:ColorRect
	var camera:Camera2D
	func _physics_process(delta:float) -> void:
		if not enabled: return
		if delay_ms > 0: OS.delay_msec(delay_ms)
		elapsed += delta
		tick_elapsed = (Time.get_ticks_usec()-tick_origin)/1e6
		if deadline_fired < 0.0 and tick_elapsed >= 1.1: deadline_fired = elapsed
		steps.append(delta)
		marker.position = camera.get_screen_center_position() - marker.size * 0.5
		var white:bool = elapsed >= 0.5 and fmod(elapsed,0.5) < 0.1
		marker.color = Color.WHITE if white else Color(0.2,0.4,0.6)
		if white and not was_white: beacon.play()
		elif not white and was_white: beacon.stop()
		was_white = white

func wall_wait(seconds:float) -> void:
	var until:int = int(Time.call("get_wall_ticks_usec")) + int(seconds * 1e6)
	while int(Time.call("get_wall_ticks_usec")) < until: await RenderingServer.frame_post_draw

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
	recorder.preferences = recorder.PreferencesScript.new("user://test_recording_offline.cfg")
	recorder.preferences.directory = "user://recordings/offline_test"
	world.control.team.hide()
	root.size = Vector2i(540,960)
	await wall_wait(1.0)
	check(Engine.has_method("set_recording_fixed_fps") and AudioServer.has_method("render_offline_audio"), "native offline interfaces are present")
	if failures: quit(1); return
	var actors:Array = []
	for side:int in range(2):
		var actor:Node = load("res://scenes/ball.tscn").instantiate()
		actor.name = "CurrentActor%d" % side
		world.add_child(actor, true)
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		actor.position = Vector2(-300 if side == 0 else 300,0)
		actor.health = 100037 + side
		actor.collision_layer = 0
		actor.collision_mask = 0
		actor.set_meta("continuation_witness",8765+side)
		actors.append(actor)
	var witness := Witness.new()
	world.add_child(witness)
	witness.camera = world.camera_2d
	witness.marker = ColorRect.new()
	witness.marker.size = Vector2(36,36)
	witness.marker.color = Color(0.2,0.4,0.6)
	witness.marker.z_index = 900
	world.add_child(witness.marker)
	var projectile := RigidBody2D.new()
	projectile.name = "CurrentProjectile"
	projectile.gravity_scale = 0.0
	projectile.can_sleep = false
	projectile.linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	projectile.angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	projectile.linear_damp = 0.0
	projectile.angular_damp = 0.0
	projectile.collision_layer = 0
	projectile.collision_mask = 0
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = 1.0
	projectile.add_child(shape)
	world.add_child(projectile)
	var timer := Timer.new()
	timer.one_shot = true
	timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	witness.add_child(timer)
	var fired:Array = []
	timer.timeout.connect(func(): fired.append(witness.elapsed))
	var tone:AudioStreamPlayer = make_tone(440,&"GameplayRecord")
	var ui_tone:AudioStreamPlayer = make_tone(1760,&"UI")
	witness.beacon = make_tone(880,&"GameplayRecord")
	witness.beacon.stop()
	await wall_wait(0.3)
	var results:Array = []
	for delay:int in [0,40]:
		witness.enabled = false
		witness.elapsed = 0.0
		witness.was_white = false
		witness.beacon.stop()
		witness.steps.clear()
		witness.deadline_fired = -1.0
		witness.delay_ms = delay
		witness.marker.color = Color(0.2,0.4,0.6)
		projectile.position = Vector2(73.25,45.0)
		PhysicsServer2D.body_set_state(projectile.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.375,Vector2(73.25,45.0)))
		projectile.linear_velocity = Vector2(42,-3)
		projectile.rotation = 0.375
		projectile.angular_velocity = 0.31
		# Let native rigid-body transform synchronization finish before choosing the click instant.
		await wall_wait(0.08)
		timer.start(1.37)
		fired.clear()
		world._victory_bell_played = false
		var ids:Array = [actors[0].get_instance_id(),actors[1].get_instance_id(),projectile.get_instance_id()]
		var health:Array = [actors[0].health,actors[1].health]
		var p:Vector2 = projectile.position
		var v:Vector2 = projectile.linear_velocity
		var remaining:float = timer.time_left
		var fps:int = Engine.max_fps
		var vsync:int = DisplayServer.window_get_vsync_mode()
		var scale:float = Engine.time_scale
		# There is deliberately NO remembered setup to restart from.
		world._battle_setup.clear()
		world._last_battle_setup.clear()
		check(not world.has_rematch_setup(), "fixture has current live objects but no rematch setup")
		witness.tick_origin = Time.get_ticks_usec()
		check(recorder.start_simulated(), "offline starts directly from a running current scene")
		if not recorder.is_recording(): print(recorder.get_last_error()); quit(1); return
		check(ids == [actors[0].get_instance_id(),actors[1].get_instance_id(),projectile.get_instance_id()], "no actor/projectile is replaced")
		check(health == [actors[0].health,actors[1].health] and projectile.position == p and projectile.linear_velocity == v, "health, position and in-flight velocity remain exactly as clicked")
		check(is_equal_approx(timer.time_left,remaining) and timer.get_parent()==witness, "partly elapsed native cooldown is not restarted")
		check(is_equal_approx(Engine.time_scale,scale), "default-speed offline simulation does not introduce quarter-speed slowdown")
		check(bool(AudioServer.call("is_offline_audio")), "hardware audio clock is frozen for sample-accurate offline mixing")
		var old_window_mode:int = DisplayServer.window_get_mode()
		if delay > 0: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
		witness.enabled = true
		var begin:int = int(Time.call("get_wall_ticks_usec"))
		var deadline:int = begin + 45000000
		while recorder.is_recording() and recorder._frame_index < 121 and int(Time.call("get_wall_ticks_usec")) < deadline:
			await RenderingServer.frame_post_draw
		var elapsed:float = witness.elapsed
		var duration:float = recorder._game_time
		check(recorder._frame_index == 121, "one encoded frame per offline time step, with no frame skips")
		check(absf(elapsed - (duration-1.0/60)) < .035, "fixed physics progress matches video length independently of wall time")
		var max_error:float = 0.0
		for delta:float in witness.steps: max_error = maxf(max_error,absf(delta-1.0/60))
		check(max_error < 0.000001, "every physics step stays 1/60 even with artificial CPU delay")
		check(fired.size()==1 and absf(fired[0]-1.37)<.035, "existing native timer fires after its REMAINING time")
		check(absf(witness.tick_elapsed-elapsed)<.035 and absf(witness.deadline_fired-1.1)<.035, "tick-based cooldowns follow offline game time, not CPU or encoding wait")
		print("TRAJECTORY=",projectile.position," expected=",p+v*elapsed," velocity=",projectile.linear_velocity)
		check(projectile.position.distance_to(p+v*elapsed)<3.0, "existing rigid body continues its prior trajectory")
		var stats:Dictionary = {"delay_ms":delay,"minimized":delay>0,"wall":float(int(Time.call("get_wall_ticks_usec"))-begin)/1e6,"physics":elapsed,"video":duration,"frames":recorder._frame_index,"max_step_error":max_error,"timer_fired":fired.duplicate(),"audio_samples":recorder._audio.samples_written,"sample_rate":recorder._audio.sample_rate,"codec":recorder._video_codec,"tick_elapsed":witness.tick_elapsed,"tick_deadline_fired":witness.deadline_fired}
		witness.enabled = false
		DisplayServer.window_set_mode(old_window_mode)
		var alive_at_stop:Array = actors.map(func(a): return is_instance_valid(a) and not a.is_queued_for_deletion())
		recorder.stop()
		await wait_idle()
		check(Engine.call("get_recording_fixed_fps")==-1 and not AudioServer.call("is_offline_audio"), "native clocks restored after cancellation")
		check(Engine.max_fps==fps and DisplayServer.window_get_vsync_mode()==vsync and is_equal_approx(Engine.time_scale,scale), "FPS, VSync and game-speed settings restored")
		check(alive_at_stop == actors.map(func(a): return is_instance_valid(a) and not a.is_queued_for_deletion()), "saving does not erase surviving actors or resurrect actors that died during simulation")
		check(paused and game.now_stop_state and not recorder._overlay_backdrop.visible, "calculated current state is paused, not reset or allowed to run ahead during encoding")
		check(recorder.last_outputs.size()==2 and recorder.get_last_error().is_empty(), "both language videos finish successfully")
		stats.outputs = recorder.last_outputs.duplicate()
		results.append(stats)
	check(results[1].wall > results[1].video*2, "deliberately slow computation does not create a longer/slower video")
	# Actual named characters, damaged and repositioned mid-match: not merely generic fixtures.
	world._victory_bell_played = false
	world.create_char("Team0","牛",Vector2(-80,0))
	world.create_char("Team1","木剑",Vector2(80,0))
	await process_frame
	var cow:Node = world._find_character_by_setup_id_any(int(world._battle_setup[-2].id))
	var sword:Node = world._find_character_by_setup_id_any(int(world._battle_setup[-1].id))
	cow.health = 37.0
	cow.position = Vector2(-63.25,17.5)
	cow.velocity = Vector2(21,-5)
	var real_id:int = cow.get_instance_id()
	var real_position:Vector2 = cow.position
	var real_velocity:Vector2 = cow.velocity
	game.set_speed(12.0,false) # User selected 3x: normalize only the export clock.
	check(recorder.start_simulated(),"actual damaged cow versus wooden sword starts from present state")
	check(is_instance_valid(cow) and cow.get_instance_id()==real_id and cow.health==37.0 and cow.position==real_position and cow.velocity==real_velocity, "real character HP/position/velocity/object identity are not reset to the stored lineup")
	check(is_equal_approx(game.get_base_game_time_scale(),1.0),"offline output normalizes a user-selected 3x base speed")
	while recorder._frame_index < 30 and recorder.is_recording(): await RenderingServer.frame_post_draw
	recorder.stop()
	await wait_idle()
	check(recorder.last_outputs.size()==2 and recorder.get_last_error().is_empty(),"actual character continuation exports both language files")
	check(is_equal_approx(game.get_base_game_time_scale(),3.0),"user-selected speed is restored after offline export")
	game.set_speed(10.0,false)
	var f := FileAccess.open("user://recordings/offline_test/manifest.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures,"runs":results},"\t"))
	f.close()
	print("OFFLINE_METRICS=",JSON.stringify(results))
	witness.beacon.queue_free()
	tone.queue_free()
	ui_tone.queue_free()
	world.queue_free()
	await process_frame
	await process_frame
	game.Game_Settings = saved
	print("RECORDING_OFFLINE: %d checks / %d failures" % [checks,failures])
	quit(1 if failures else 0)
