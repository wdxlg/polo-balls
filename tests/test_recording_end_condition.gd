extends SceneTree
## Verify the recorder does not infer a finished match from a transient side count
## or from elapsed game time. The real World remains authoritative for the bell.
var failures:int = 0
func _initialize() -> void: run.call_deferred()
func check(ok:bool, message:String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1
func run() -> void:
	var game:Node = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Boss_Intro = false
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world, CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	await create_timer(0.3, true, false, true).timeout
	var recorder:Node = world.control._battle_record_controls.recorder
	world.create_char("Team0", "蠹虫", Vector2(-80, 0))
	world.create_char("Team1", "鞘翅长矛", Vector2(80, 0))
	await process_frame
	print("RECORD_END_CASE initial bell=", world._victory_bell_played, " sides=", world._collect_alive_victory_sides())
	check(not world._victory_bell_played and not recorder._sim_match_over(), "fresh match is not over")
	recorder._game_time = 301.0
	recorder._tail_seconds = 1.5
	recorder._sim_tail_left = -1.0
	recorder._sim_finished = false
	recorder._update_sim_progress(1.0 / 60.0)
	check(recorder._sim_tail_left < 0.0 and not recorder._sim_finished, "300 seconds alone never starts tail or stops SIM")
	recorder._game_time = 0.0
	var frames:int = 0
	while frames < 180 and not world._victory_bell_played:
		await physics_frame
		frames += 1
		if frames % 30 == 0:
			print("RECORD_END_CASE frame=", frames, " bell=", world._victory_bell_played, " sides=", world._collect_alive_victory_sides(), " recorder_over=", recorder._match_over_now())
	print("RECORD_END_CASE final frame=", frames, " bell=", world._victory_bell_played, " sides=", world._collect_alive_victory_sides())
	# This particular fight may last more than three seconds. Its actual end is
	# checked below in both GPU recordings; here isolate the countdown contract.
	if not world._victory_bell_played:
		check(not recorder._match_over_now() and recorder._sim_tail_left < 0.0, "a still-running fight does not start tail")
		world._victory_bell_played = true
	recorder._update_sim_progress(1.0 / 60.0)
	check(is_equal_approx(recorder._sim_tail_left, 1.5) and not recorder._sim_finished, "world bell starts configured SIM tail, not immediate stop")
	recorder._update_sim_progress(0.5)
	check(is_equal_approx(recorder._sim_tail_left, 1.0) and not recorder._sim_finished, "tail counts game time only")
	recorder._update_sim_progress(1.0)
	check(recorder._sim_finished, "SIM ends after full configured tail")
	if DisplayServer.get_name() != "headless":
		world.reset()
		await process_frame
		game.continue_game()
		world.control.team.hide()
		world.create_char("Team0", "蠹虫", Vector2(-80, 0))
		world.create_char("Team1", "鞘翅长矛", Vector2(80, 0))
		var prefs = recorder.PreferencesScript.new("user://test_recording_end_condition.cfg")
		prefs.directory = "user://recordings/record_end_test"
		prefs.tail_seconds = 1.5
		recorder.preferences = prefs
		check(recorder.start_simulated(), "real matchup starts offline recording")
		var frames_at_bell:int = -1
		var deadline:int = Time.get_wall_ticks_msec() + 90000
		while recorder.is_recording() and Time.get_wall_ticks_msec() < deadline:
			await RenderingServer.frame_post_draw
			if world._victory_bell_played and frames_at_bell < 0:
				frames_at_bell = recorder._frame_index
		check(not recorder.is_recording() and frames_at_bell > 0, "SIM reaches actual match end before stopping")
		check(recorder._frame_index - frames_at_bell >= 88, "SIM records configured 1.5-second tail: %d frames" % (recorder._frame_index - frames_at_bell))
		while recorder.is_busy() and Time.get_wall_ticks_msec() < deadline:
			await process_frame
		check(not recorder.is_busy() and recorder.last_outputs.size() == 2, "SIM saves both completed movies")
		world.reset()
		await process_frame
		game.continue_game()
		world.control.team.hide()
		world.create_char("Team0", "蠹虫", Vector2(-80, 0))
		world.create_char("Team1", "鞘翅长矛", Vector2(80, 0))
		check(recorder.start_live(), "real matchup starts LIVE recording")
		frames_at_bell = -1
		deadline = Time.get_wall_ticks_msec() + 90000
		while recorder.is_recording() and Time.get_wall_ticks_msec() < deadline:
			await RenderingServer.frame_post_draw
			if world._victory_bell_played and frames_at_bell < 0:
				frames_at_bell = recorder._frame_index
		check(not recorder.is_recording() and frames_at_bell > 0, "LIVE reaches actual match end before stopping: " + recorder.get_last_error())
		check(recorder._frame_index - frames_at_bell >= 85, "LIVE records configured 1.5-second tail: %d frames" % (recorder._frame_index - frames_at_bell))
		while recorder.is_busy() and Time.get_wall_ticks_msec() < deadline:
			await process_frame
		check(not recorder.is_busy() and recorder.last_outputs.size() == 2, "LIVE saves both completed movies")
	world.queue_free()
	await process_frame
	game.Game_Settings = saved
	print("RECORD_END_CONDITION: %d failures" % failures)
	quit(1 if failures else 0)
