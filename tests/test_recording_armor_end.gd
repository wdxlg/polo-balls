extends SceneTree
var checks:int = 0
var failures:int = 0
func _initialize() -> void: call_deferred("run")
func check(ok:bool,text:String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ",text)
func run() -> void:
	var game:Node = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	var stopped:bool = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Development_Mode = false
	game.now_stop_state = true
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.set_physics_process(false)
	world.set_process(false)
	world.create_char("Team0","烈焰人",Vector2(-30,0))
	world.create_char("Team1","木剑",Vector2(30,0))
	await process_frame
	for actor:Node in world._battle_units_cache: actor.process_mode = Node.PROCESS_MODE_DISABLED
	world._update_manual_victory_bell()
	check(not world._victory_bell_played,"fresh ordinary fight does not end")
	for actor:Node in world._battle_units_cache:
		if actor.Team=="Team1": actor.health=0
	world._update_manual_victory_bell()
	check(world._victory_bell_played,"real World settlement raises the previous fight's bell")
	world.create_char("Team1","不死盔甲架",Vector2(30,0))
	await process_frame
	for actor:Node in world._battle_units_cache: actor.process_mode = Node.PROCESS_MODE_DISABLED
	world.refresh_versus_text()
	var recorder:Node = world.control._battle_record_controls.recorder
	var naming:Script = load("res://scripts/ui/battle_record_naming.gd")
	recorder._match_snapshot = naming.snapshot(world,false)
	check(world._collect_alive_victory_sides().size()==2 and world._victory_bell_played,"reproduce an ongoing armor fight with a naturally retained old bell")
	check(not recorder._match_over_now() and not recorder._sim_match_over(),"both recorder paths reject the stale terminal signal")
	check(naming.title(recorder._match_snapshot,"zh")=="烈焰人" and naming.title(recorder._match_snapshot,"en")=="Blaze","real actor selection excludes old setup foes and the dummy")
	for simulated:bool in [false,true]:
		recorder._tail_seconds = 1.5
		recorder._sim_tail_left = -1.0
		recorder._sim_finished = false
		recorder._stale_match_over = false
		for frame:int in 480:
			if simulated: recorder._update_sim_progress(1.0/60.0)
			else: recorder._update_match_end_tail(1.0/60.0)
		check(not recorder._sim_finished and recorder.get_tail_left()<0,"ongoing armor fight records beyond eight seconds: "+str(simulated))
		recorder._sim_tail_left = 0.01
		recorder._sim_finished = true
		recorder._stale_match_over = true
		if simulated: recorder._update_sim_progress(0.1)
		else: recorder._update_match_end_tail(0.1)
		check(recorder.get_tail_left()<0 and not recorder._sim_finished and not recorder._stale_match_over,"re-entering contested armor battle cancels a previously armed tail: "+str(simulated))
	# Explicit timed or queue completion remains authoritative, including survivors.
	game.Game_Settings.Training_Mode = true
	game.Game_Settings.Training_Mode_Type = "timed"
	world._timed_finished = true
	check(recorder._match_over_now(),"a real timed expiry still ends the recording with survivors")
	world._timed_finished = false
	game.Game_Settings.Training_Mode_Type = "rotation"
	world._rotation_finished = true
	check(recorder._match_over_now(),"an exhausted rotation queue remains a real finish")
	world._rotation_finished = false
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	world._armor_stand_test_hud_active = false
	check(recorder._match_over_now(),"ordinary recorder semantics do not change")
	world._armor_stand_test_hud_active = true
	# Do not clear or synthesize the global bell; disappearance of the opposing
	# primary contender makes the existing World result valid for this fight.
	for actor:Node in world._battle_units_cache:
		if actor.Team=="Team0": actor.health=0
	check(world._collect_alive_victory_sides().size()==1 and recorder._match_over_now(),"actual loss of the opposing role permits automatic finish")
	for simulated:bool in [false,true]:
		recorder._sim_tail_left = -1.0
		recorder._sim_finished = false
		recorder._stale_match_over = false
		if simulated: recorder._update_sim_progress(1.0/60.0)
		else: recorder._update_match_end_tail(1.0/60.0)
		check(is_equal_approx(recorder.get_tail_left(),1.5) and not recorder._sim_finished,"actual end starts the complete configured tail: "+str(simulated))
		if simulated: recorder._update_sim_progress(0.5)
		else: recorder._update_match_end_tail(0.5)
		check(is_equal_approx(recorder.get_tail_left(),1.0),"tail uses supplied game time: "+str(simulated))
		if simulated: recorder._update_sim_progress(1.0)
		else: recorder._update_match_end_tail(1.0)
		check(recorder._sim_finished,"actual end plus tail automatically stops: "+str(simulated))
	await create_timer(0.5,true,false,true).timeout
	world.queue_free()
	await process_frame
	game.Game_Settings = saved
	game.now_stop_state = stopped
	print("ARMOR_RECORD_END checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
