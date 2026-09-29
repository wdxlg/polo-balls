extends "res://tests/test_rotation_timed_flow.gd"
var door_results:Array=[]
var half_callbacks:int=0
func run() -> void:
	create_timer(80,true,false,true).timeout.connect(func():print("ROUND_BOUNDARY_TIMEOUT");quit(2))
	game=root.get_node("Game");saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false;game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Development_Mode=false;game.Game_Settings.Map_Background="blue"
	game.now_stop_state=false;AudioServer.set_bus_mute(0,true);root.size=Vector2i(540,960)
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT);root.add_child(world)
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.free()
	world._mc_prewarmer=null;await process_frame
	world.now_choose_map="Map10x10";world.refresh_map_presentation();world.set_process(false);world.set_physics_process(false)
	for mode:String in ["challenge","duel"]:
		await setup(mode,1,1)
		var loser:Node=current("right");loser.health=0;loser.queue_free()
		check(await until(func():return world.duel_top_hud.round_result_locked),mode+": final battle still has outcome achievement")
		check(await until(func():return world._rotation_load_ready),mode+": exhausted queue still completes covered final transition")
		check(await until(func():return not world._rotation_transitioning),mode+": exhausted queue never stalls on next resource")
		check(int(world._rotation_next_index.right)==1,mode+": no phantom next contender")
		if mode=="wheel":check(is_instance_valid(current("left")),"wheel final survivor remains intact")
		elif mode=="challenge":check(world._rotation_finished,"challenge marks complete after last blue challenger")
	# Missing upcoming resource must not erase the old winner or falsely reach 100%.
	await setup("challenge",2,2)
	var survivor:Node=current("left");survivor.health=23
	world._rotation_rosters.right[1].scene_path="res://tests/__missing_rotation_fixture__.tscn"
	var dead:Node=current("right");dead.health=0;dead.queue_free()
	check(await until(func():return world._rotation_finished and not world._rotation_transitioning),"failed load terminates into formation controls")
	check(not world._rotation_load_ready and world._rotation_ui_progress<1,"failure never reports ready or completed progress")
	check(is_instance_valid(survivor) and survivor.health==23 and int(world._rotation_next_index.right)==1,"invalid next resource leaves prior winner and queue untouched")
	check(not world.is_combat_runtime_active() and not is_instance_valid(world._rotation_door),"failed load releases input shield without starting combat")
	var visible_error:bool=false
	for n:Node in world.get_children():
		if n is AcceptDialog:visible_error=visible_error or n.visible;n.queue_free()
	check(visible_error,"player receives visible load failure, not silent hang")
	world.reset();await process_frame;await process_frame
	game.Game_Settings.Training_Mode_Type="timed";world.control.hide();world.control.team.hide()
	world._timed_running=true;world._timed_time_left=10
	var blue:Node=timed_actor(1,"Team0");var red:Node=timed_actor(2,"Team1");var third:Node=timed_actor(3,"Team2")
	world._timed_damage_by_setup={1:5.0,2:5.0,3:2.0}
	world.refresh_versus_text();world.duel_top_hud._refresh_pair();world.duel_top_hud._update_clock(0);world.duel_top_hud._process(0)
	check(world.duel_top_hud.sides.size()!=2 and world.duel_top_hud.visible and world.duel_top_hud.clock_text()=="00:10","three-player timed match retains same HUD central clock")
	await capture("timed_three")
	game.now_stop_state=true;world._update_special_training_modes(3)
	check(world._timed_time_left==10,"stop-state pause freezes countdown")
	game.now_stop_state=false;paused=true;world._update_special_training_modes(3)
	check(world._timed_time_left==10,"SceneTree pause freezes countdown")
	paused=false;Engine.time_scale=0;world._update_special_training_modes(3)
	check(world._timed_time_left==10,"zero gameplay speed freezes countdown")
	Engine.time_scale=1;world._update_special_training_modes(1)
	check(world._timed_time_left==9,"countdown resumes once with actual game delta")
	world._timed_time_left=0;world._finish_timed_training()
	check(world._timed_overtime and red.health>0 and third.health>0,"highest-score tie does not kill lower scores prematurely")
	world._on_timed_training_damage_resolved(blue,red,1)
	check(world._timed_finished and world._timed_winner_setup==1,"first actual damage lead settles inside same damage callback")
	check(red.health==0 and third.health==0 and blue.health>0,"multiplayer-count verdict kills every losing setup, keeps winner")
	world.reset();await process_frame;await process_frame
	var door:CanvasLayer=load("res://scripts/ui/dark_oak_transition.gd").ensure(self)
	door.finished.connect(func(completed:bool):door_results.append(completed))
	door.opening_half.connect(func():door.cancel(),CONNECT_ONE_SHOT)
	check(door.play(Callable(),func():half_callbacks+=1),"shared door accepts midpoint signal cancellation test")
	await until(func():return not door.is_busy())
	check(door_results==[false] and half_callbacks==0,"cancel from midpoint signal prevents callback and duplicate success")
	door_results.clear()
	check(door.play(Callable(),func():half_callbacks+=1;door.cancel()),"shared door accepts midpoint callback cancellation test")
	await until(func():return not door.is_busy())
	check(door_results==[false] and half_callbacks==1,"cancel from midpoint callback emits exactly one cancelled finish")
	await setup("duel",2,2)
	dead=current("right");dead.health=0;dead.queue_free()
	check(await until(func():return is_instance_valid(world._rotation_door) and world._rotation_door.phase==door.Phase.COVERED),"world exit tested during real covered load")
	world.queue_free();await process_frame;await process_frame
	check(not door.is_busy() and not door.visible,"World exit cancels root-owned doors and releases overlay")
	game.Game_Settings=saved;door.queue_free();await process_frame
	print("ROUND_BOUNDARY_RESULT checks=%d failures=%d renderer=%s"%[checks,failures,DisplayServer.get_name()])
	quit(0 if failures==0 else 1)
