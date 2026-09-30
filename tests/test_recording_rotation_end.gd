extends "res://tests/test_mc_bat.gd"
var recorder:Node

func wall_msec() -> int:
	return int(Time.call("get_wall_ticks_msec")) if Time.has_method("get_wall_ticks_msec") else Time.get_ticks_msec()

func freeze_fighters() -> void:
	for unit:Node in get_nodes_in_group("Ball"):
		unit.process_mode = Node.PROCESS_MODE_DISABLED

func tick(simulated:bool,delta:float) -> void:
	if simulated: recorder._update_sim_progress(delta)
	else: recorder._update_match_end_tail(delta)

func reset_tail(seconds:float = 0.5) -> void:
	recorder._tail_seconds = seconds
	recorder._sim_tail_left = -1.0
	recorder._sim_finished = false
	recorder._stale_match_over = false

func setup(match_type:String) -> void:
	world.reset()
	await process_frame
	await process_frame
	game.Game_Settings.Training_Mode_Type = "rotation"
	game.Game_Settings.Rotation_Match_Type = match_type
	game.Game_Settings.Training_Wheel_Battle = match_type == "wheel"
	game.Game_Settings.Rotation_Multi_Characters = false
	game.Game_Settings.Rotation_Blue_Count = 1
	game.Game_Settings.Rotation_Red_Count = 1
	world.control.team.show()
	world._battle_setup_next_id = 1
	for side:String in ["left","right"]:
		for i:int in 2:
			world._enqueue_rotation_character("","木剑" if side=="left" else "钻石剑",world._rotation_spawn_position(side),side,"res://scenes/ball.tscn",i+1)
	world.control.hide()
	world.control.team.hide()
	world._update_special_training_modes(0.0)
	freeze_fighters()
	await process_frame
	check(world._rotation_started,"actual queue starts: "+match_type)

func defeat(side:String) -> void:
	var actor:Node = world._find_character_by_setup_id_any(int(world._rotation_active_setup[side]))
	check(is_instance_valid(actor),"actual contender exists: "+side)
	if is_instance_valid(actor):
		actor.health = 0
		actor.queue_free()

func settle() -> void:
	await create_timer(0.4).timeout
	var deadline:int = wall_msec()+15000
	while world._rotation_transitioning and wall_msec()<deadline:
		await process_frame
		freeze_fighters()
	await process_frame
	freeze_fighters()
	check(not world._rotation_transitioning,"real result/door/replacement sequence completes")

func assert_ongoing(label:String) -> void:
	check(not recorder._match_over_now() and not recorder._sim_match_over(),label+": round bell is not a series finish")
	for simulated:bool in [false,true]:
		reset_tail()
		for i:int in 8: tick(simulated,1.0)
		check(recorder.get_tail_left()<0.0 and not recorder._sim_finished,label+": continues beyond the tail duration "+str(simulated))
		recorder._sim_tail_left=0.01
		recorder._sim_finished=true
		recorder._stale_match_over=true
		tick(simulated,1.0)
		check(recorder.get_tail_left()<0.0 and not recorder._sim_finished and not recorder._stale_match_over,label+": cancels stale tail on resumed queue "+str(simulated))
	reset_tail()

func contract_cases() -> void:
	for match_type:String in ["duel","wheel","challenge"]:
		await setup(match_type)
		assert_ongoing(match_type+" opening")
		defeat("left" if match_type=="challenge" else "right")
		await create_timer(0.4).timeout
		if match_type!="wheel": check(world._victory_bell_played and world._rotation_transitioning,"reproduces first-round bell during "+match_type+" transition")
		assert_ongoing(match_type+" first-round interval")
		await settle()
		assert_ongoing(match_type+" next round")
		if match_type=="challenge":
			defeat("right")
			await settle()
			assert_ongoing("challenge still has a red opponent")
		defeat("right")
		await settle()
		check(recorder._match_over_now() and recorder._sim_match_over(),match_type+": exhausting the real queue is terminal")
		for simulated:bool in [false,true]:
			for seconds:float in [0.0,0.5,600.0]:
				reset_tail(seconds)
				tick(simulated,0.0)
				check(is_equal_approx(recorder.get_tail_left(),seconds),match_type+": full configured tail begins only at series end "+str(seconds)+" / "+str(simulated))
				tick(simulated,seconds*0.5)
				tick(simulated,seconds*0.5)
				check(recorder._sim_finished,match_type+": stops after the full tail "+str(seconds)+" / "+str(simulated))
	# Legacy modes retain their World bell contract; a queue draw needs no bell.
	game.Game_Settings.Training_Mode_Type="manual"
	world._victory_bell_played=false
	check(not recorder._match_over_now(),"ordinary match without verdict keeps recording")
	world._victory_bell_played=true
	check(recorder._match_over_now(),"ordinary match verdict still stops recording")
	game.Game_Settings.Training_Mode_Type="timed"
	world._timed_finished=true
	check(recorder._match_over_now(),"timed verdict still stops recording")
	game.Game_Settings.Training_Mode_Type="boss"
	game.Game_Settings.Training_Boss_Wheel_Battle=true
	world._rotation_finished=false
	world._rotation_started=true
	world._rotation_rosters={"left":[{"id":1}],"right":[{"id":2}]}
	world._rotation_next_index={"left":0,"right":0}
	assert_ongoing("boss wheel waiting for its next fighters")
	world._rotation_next_index={"left":1,"right":1}
	world._victory_bell_played=false
	check(recorder._match_over_now(),"exhausted queue draw finishes even without a winner bell")

func speed_guard_cases() -> void:
	game.Game_Settings.Training_Mode_Type="rotation"
	world._rotation_transitioning=true
	world._rotation_door=CanvasLayer.new()
	recorder._speed_warmup=0.0
	recorder._speed_real=0.0
	recorder._speed_physics_start=0.0
	recorder._physics_clock=0.0
	check(recorder._live_speed_is_healthy(2.0) and recorder._speed_real==0.0,"door loading resets the speed window without stopping capture")
	world._rotation_door.free()
	world._rotation_door=null
	world._rotation_combat_blocked=true
	check(recorder._live_speed_is_healthy(2.0),"covered scene loading is not sustained combat slowdown")
	world._rotation_combat_blocked=false
	check(not recorder._live_speed_is_healthy(2.0),"an old-round result alone does not bypass overload protection")
	world._rotation_transitioning=false
	recorder._physics_clock=2.0
	check(recorder._live_speed_is_healthy(2.0),"normal combat speed resumes a clean measurement window")
	recorder._physics_clock=3.0
	check(not recorder._live_speed_is_healthy(2.0),"genuine half-speed combat still fails the unchanged speed threshold")
	check(recorder.MAX_FRAMES_PER_DRAW==120 and recorder.WriterScript.MAX_BYTES==256*1024*1024 and recorder.WriterScript.MAX_FRAMES==120,"render-stall and encoder backpressure limits are unchanged")

func gpu_case(folder:String,match_type:String,simulated:bool) -> void:
	await setup(match_type)
	var prefs:RefCounted=recorder.PreferencesScript.new(folder.path_join("prefs.cfg"))
	prefs.directory=folder
	prefs.tail_seconds=0.5
	recorder.preferences=prefs
	var started:bool=recorder.start_simulated() if simulated else recorder.start_live()
	check(started,"start real dual-language encoder: "+recorder.get_last_error())
	if not started: return
	var deadline:int=wall_msec()+120000
	while recorder.is_recording() and recorder._frame_index<12 and wall_msec()<deadline: await process_frame
	var sequence:Array=["left","right","right"] if match_type=="challenge" else ["right","right"]
	var terminal_frame:int=-1
	for index:int in sequence.size():
		check(recorder.is_recording(),"recording reaches round "+str(index+1))
		if not recorder.is_recording(): break
		defeat(sequence[index])
		if index<sequence.size()-1:
			await settle()
			var hold_until:float=recorder._game_time+1.0
			while recorder.is_recording() and recorder._game_time<hold_until and wall_msec()<deadline:
				await process_frame
				freeze_fighters()
			check(recorder.is_recording() and recorder.get_tail_left()<0.0,"encoded the transition and next fight beyond the old stop deadline")
		else:
			while recorder.is_recording() and wall_msec()<deadline:
				await process_frame
				freeze_fighters()
				if recorder._match_over_now() and terminal_frame<0: terminal_frame=recorder._frame_index
	check(not recorder.is_recording() and terminal_frame>=0,"automatic stop follows the complete series, not the first round")
	if recorder.is_recording(): recorder.stop()
	while recorder.is_busy() and wall_msec()<deadline: await process_frame
	check(not recorder.is_busy() and recorder.last_outputs.size()==2,"both language movies finish and mux")
	check(recorder.last_outputs.get("zh","")!=recorder.last_outputs.get("en",""),"localized output paths are distinct")
	check(terminal_frame>=0 and recorder._frame_index-terminal_frame>=28,"final series result retains the configured 30-frame tail")
	check(recorder.get_last_error().is_empty(),"no recording error: "+recorder.get_last_error())
	print("ROTATION_MOVIES ",JSON.stringify({"match_type":match_type,"simulated":simulated,"frames":recorder._frame_index,"terminal_frame":terminal_frame,"outputs":recorder.last_outputs}))

func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	saved_stop=game.now_stop_state
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Development_Mode=false
	game.Game_Settings.Training_Boss_Intro=false
	game.Game_Settings.Map_Background="blue"
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	await process_frame
	recorder=world.control._battle_record_controls.recorder
	var args:PackedStringArray=OS.get_cmdline_user_args()
	if DisplayServer.get_name()!="headless" and args.size()==3:
		await gpu_case(args[0],args[1],args[2]=="sim")
	else:
		await contract_cases()
		speed_guard_cases()
	print("ROTATION_RECORDING RESULT: %d/%d passed" % [checks-failures,checks])
	finish(0 if failures==0 else 1)
