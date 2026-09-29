extends "res://tests/test_rotation_frames_challenge.gd"
var frame_notes:Array=[]
func until(f:Callable,seconds:float=6.0) -> bool:
	var end:int=Time.get_ticks_usec()+int(seconds*1000000.0)
	while Time.get_ticks_usec()<end:
		if f.call():return true
		await process_frame
	return false
func capture(key:String) -> void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	image.save_png("user://round_flow_"+key+".png")
func timed_actor(id:int,team:String,path:String="res://scenes/ball.tscn") -> Node:
	var center:Vector2=world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	var actor:Node=world._spawn_character_from_setup({"id":id,"char":path.get_file().get_basename(),"scene_path":path,"team":team,"x":center.x+(-60 if id==1 else 60),"y":center.y})
	actor.Can_Attack=false;actor.Can_Skill=false;actor.Health_Restore=0
	actor.state_machine.set_physics_process(false)
	return actor
func run() -> void:
	create_timer(90,true,false,true).timeout.connect(func():print("ROUND_FLOW_TIMEOUT");quit(2))
	game=root.get_node("Game");saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false;game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Development_Mode=false;game.Game_Settings.Map_Background="blue"
	game.now_stop_state=false;AudioServer.set_bus_mute(0,true)
	root.size=Vector2i(540,960)
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT);root.add_child(world)
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.free()
	world._mc_prewarmer=null
	await process_frame
	world.now_choose_map="Map10x10";world.refresh_map_presentation()
	world.set_process(false);world.set_physics_process(false)
	for mode:String in ["challenge","duel"]:
		await setup(mode,2,2)
		var winner:Node=current("left");var original_id:int=winner.get_instance_id();winner.health=23
		var loser:Node=current("right");loser.health=0;loser.queue_free()
		check(await until(func():return world.duel_top_hud.round_result_locked),mode+": round verdict shows native achievement before cleanup")
		check(is_instance_valid(winner) and winner.health==23 and not is_instance_valid(world._rotation_door),mode+": previous winner retained before closing")
		check(world.is_combat_runtime_active(),mode+": previous fight remains active during result and closing")
		await capture(mode+"_result")
		check(await until(func():return is_instance_valid(world._rotation_door) and world._rotation_door.phase==world._rotation_door.Phase.CLOSING),mode+": shared real 3D doors close")
		check(is_instance_valid(winner) and int(world._rotation_next_index.right)==1,mode+": no next actor loaded before door coverage")
		var door:CanvasLayer=world._rotation_door
		check(await until(func():return door.phase==door.Phase.COVERED and door.loading_slide>0.3),mode+": experience progress rises only while covered")
		check(door.loading_rect().position.y<door.get_viewport().get_visible_rect().size.y,mode+": loading bar is visibly inside bottom edge")
		await capture(mode+"_loading")
		check(await until(func():return world._rotation_load_ready),mode+": real loading stages reach ready")
		if mode=="wheel":await capture("wheel_full")
		check(not world.is_combat_runtime_active() and door.phase==door.Phase.COVERED,mode+": actors remain gated after load until doors half open")
		check(is_instance_valid(world._rotation_toast_mirror) and world._rotation_toast_mirror.get_parent()==door.shield,mode+": achievement is above the closed doors, not hidden behind them")
		if mode=="wheel":
			await until(func():return world.duel_top_hud.round_exit>0.25)
			await capture("wheel_exiting")
		check(await until(func():return door.phase==door.Phase.OPENING),mode+": doors open after both overlays exit")
		check(door.loading_slide==0.0 and world.duel_top_hud.round_exit>=0.99,mode+": progress exits down and achievement exits up before opening")
		check(await until(func():return world._rotation_combat_released),mode+": half-open callback releases battle")
		check(door.progress<=0.5 and world.is_combat_runtime_active(),mode+": formal start occurs at opening midpoint, not fully open")
		if mode=="wheel":await capture("wheel_half")
		check(await until(func():return not world._rotation_transitioning),mode+": transition completes without stuck gate")
		if mode=="duel":check(current("left").get_instance_id()!=original_id and current("left").health==current("left").Max_health,"duel retires winner only behind doors")
		else:check(current("left").get_instance_id()==original_id and current("left").health==23,mode+": survivor keeps real identity and damage")
		fighters()
	# True totem lethal hit in each rotation rule must not cross portrait / begin transition.
	for mode:String in ["wheel","challenge","duel"]:
		world.reset();await process_frame;await process_frame
		game.Game_Settings.Training_Mode_Type="rotation";game.Game_Settings.Rotation_Match_Type=mode
		world._battle_setup_next_id=1;world.control.team.show()
		world._enqueue_rotation_character("","唤魔者",world._rotation_spawn_position("left"),"left","res://scenes/characters/我的世界/唤魔者.tscn")
		world._enqueue_rotation_character("","Dummy",world._rotation_spawn_position("right"),"right","res://scenes/ball.tscn")
		world.control.hide();world.control.team.hide();world._update_special_training_modes(0)
		fighters();var evoker:Node=current("left");var enemy:Node=current("right")
		evoker.receive_spatial_raw_health_damage(1000.0,{"point":evoker.global_position,"shape":"all","source":enemy})
		world._scan_rotation_family_extinctions()
		check(evoker.health==50 and evoker._totem_used and world._battle_family_alive(1),mode+": actual lethal hit consumes totem and remains a live family")
		check(int(world._rotation_active_setup.left)==1 and world._rotation_pending_dead_sides.is_empty() and not world._rotation_results.has(1),mode+": totem does not remove roster slot or mark loss")
		# Inject an obsolete death notification: delayed adjudication must revalidate live health.
		world._rotation_pending_dead_sides.assign(["left"]);world._rotation_resolve_pending_deaths()
		await until(func():return not world._rotation_transitioning)
		check(not world._rotation_transitioning and not world._victory_bell_played and int(world._rotation_active_setup.left)==1,mode+": stale pending death is cancelled after totem save")
	# Cancel/reset while door closed cannot load the next round into a new setup.
	await setup("duel",2,2)
	current("right").health=0;current("right").queue_free()
	check(await until(func():return is_instance_valid(world._rotation_door) and world._rotation_door.phase==world._rotation_door.Phase.COVERED),"cancellation fixture reaches covered phase")
	var cancelled:CanvasLayer=world._rotation_door
	world.reset();await create_timer(0.8,true,false,true).timeout
	check(not cancelled.is_busy() and not world._rotation_transitioning and get_nodes_in_group("Ball").is_empty(),"reset cancels door coroutine, stale loader and old actors")
	# Timed HUD uses score and one top countdown; a totem cannot veto rule defeat.
	game.Game_Settings.Training_Mode_Type="timed";world.control.hide();world.control.team.hide()
	world._timed_running=true;world._timed_time_left=10
	var blue:Node=timed_actor(1,"Team0")
	var red:Node=timed_actor(2,"Team1","res://scenes/characters/我的世界/唤魔者.tscn")
	blue.Damage_reduction=0.35
	world._timed_damage_by_setup={1:123.0,2:23.0}
	world.refresh_versus_text();world.duel_top_hud._refresh_pair();world.duel_top_hud._refresh_values();world.duel_top_hud._update_clock(0);world.duel_top_hud._process(0)
	check(world.duel_top_hud.timed_mode and world.duel_top_hud.sides.size()==2,"timed duel keeps existing top HUD")
	var left:Dictionary=world.duel_top_hud.sides[0]
	check(left.damage==123.0 and is_equal_approx(left.reduction,0.35),"top HUD reads real accumulated damage and retains armor")
	check("123" in world.duel_top_hud.side_value_text(left) and not "/" in world.duel_top_hud.side_value_text(left),"life text replaced with dealt-damage value")
	world._update_special_training_modes(1.0);world.duel_top_hud._update_clock(0)
	check(world.duel_top_hud.clock_text()=="00:09" and not world.timed_training_label.visible,"one upper countdown replaces lower map timer")
	await capture("timed_damage")
	world._timed_damage_by_setup={1:50.0,2:50.0};world._timed_time_left=0;world._finish_timed_training()
	world.duel_top_hud._update_clock(0)
	check(world._timed_overtime and not world._timed_finished and world.is_combat_runtime_active(),"tied timeout enters active overtime instead of pausing or killing")
	check(world.duel_top_hud.clock_text() in ["加赛","OT"] and red.health>0,"upper countdown announces overtime and retains tied fighters")
	world._on_timed_training_damage_resolved(blue,red,1.0);world._update_special_training_modes(0.016)
	check(world._timed_finished and world._timed_winner_setup==1 and not world._timed_overtime,"first score lead in overtime settles once")
	check(red.health==0 and not red._totem_used and red.state_machine.current_state==2,"timed loser dies directly without triggering totem")
	check(not game.now_stop_state and not paused and world.is_combat_runtime_active(),"time-up does not pause the winner or the world")
	check(blue.process_mode!=Node.PROCESS_MODE_DISABLED,"winner is not disabled on verdict")
	var score:float=world._timed_damage_by_setup[1]
	world._on_timed_training_damage_resolved(blue,red,9.0)
	check(world._timed_damage_by_setup[1]==score,"final score cannot keep accumulating after verdict")
	var pos:Vector2=blue.global_position
	blue.Speed=80;blue.direction=Vector2.RIGHT;blue.state_machine.set_physics_process(true)
	await create_timer(0.2,true,false,true).timeout
	check(is_instance_valid(blue) and blue.global_position.distance_to(pos)>0.1,"winner continues real physics movement after countdown ends")
	world.reset();await process_frame;await process_frame
	game.Game_Settings=saved;world.queue_free();await process_frame
	if is_instance_valid(cancelled):cancelled.queue_free()
	print("ROUND_FLOW_RESULT checks=%d failures=%d renderer=%s"%[checks,failures,DisplayServer.get_name()])
	quit(0 if failures==0 else 1)
