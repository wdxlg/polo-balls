extends "res://tests/test_rotation_timed_network.gd"
func prepare() -> void:
	game.Game_Settings.Training_Mode_Type="rotation";game.Game_Settings.Rotation_Match_Type="duel";game.Game_Settings.Training_Wheel_Battle=false
	world._rotation_started=true;world.control.hide();world.control.team.hide()
func actors() -> Array:
	var result:Array=[]
	for actor:Node in world._battle_units_cache:
		if is_instance_valid(actor) and not actor.is_queued_for_deletion() and actor.Team=="RescueTest":result.append(actor)
	return result
func host_case() -> void:
	prepare();check(await until(func():return flag("ready")),"recovery client ready")
	var rect:Rect2=world.return_map_world_rect(world.map_group[world.now_choose_map])
	var actor:Node=world._spawn_character_from_setup({"id":7000,"char":"ball","scene_path":"res://scenes/ball.tscn","team":"RescueTest","x":rect.position.x-8,"y":rect.get_center().y})
	actor.Can_Attack=false;actor.Can_Skill=false;actor.Speed=0;actor.state_machine.set_physics_process(false)
	actor.collision_shape_2d.position=Vector2(-180,0)
	ack("placed");check(await until(func():return flag("guard_checked")),"client confirms no autonomous correction")
	actor.state_machine.set_physics_process(true);actor.direction=Vector2.LEFT;actor.Speed=200
	world._process_map_squeeze_protection([actor])
	check(actor.has_meta("map_rescue_animating"),"authority begins ordinary non-wheel correction")
	check(await until(func():return not actor.has_meta("map_rescue_animating")),"authority completes the correction")
	actor.Speed=0
	check(actor.global_position.x>=rect.position.x+55,"offset body is fully clear of the left wall")
	ack("done");check(await until(func():return flag("verified")),"client observes final authority position")
	ack("finish");await create_timer(3.5,true,false,true).timeout
func guest_case() -> void:
	prepare();ack("ready");await until(func():return flag("placed"))
	check(await until(func():return actors().size()==1),"actual actor arrives through the existing multiplayer spawner")
	var actor:Node=actors()[0]
	var rect:Rect2=world.return_map_world_rect(world.map_group[world.now_choose_map])
	world._process_map_squeeze_protection([actor]);world._animate_ball_back_inside_map(actor,rect.get_center())
	check(not actor.has_meta("map_rescue_animating"),"client cannot start a competing pullback on replicated actor")
	ack("guard_checked");await until(func():return flag("done"))
	check(await until(func():return actor.global_position.x>=rect.position.x+54),"ordinary recovery movement replicates to the client")
	check(not actor.has_meta("map_rescue_animating") and not actor.has_meta("map_rescue_state_physics"),"client has no leftover local correction lock")
	ack("verified");await until(func():return flag("finish"));await create_timer(3.5,true,false,true).timeout

func run() -> void:
	create_timer(80,true,false,true).timeout.connect(func():print("ROUND_NET_TIMEOUT");quit(2))
	var args:PackedStringArray=OS.get_cmdline_user_args();server=args.has("--server")
	var port:int=43429
	for a:String in args:
		if a.begins_with("--port="):port=a.trim_prefix("--port=").to_int()
	game=root.get_node("Game");game.Game_Settings.Training_Mode=false;game.Game_Settings.Development_Mode=false
	game.Game_Settings.Training_Mode_Type="timed";game.Game_Settings.Map_Background="blue"
	game.now_stop_state=false;AudioServer.set_bus_mute(0,true)
	api=SceneMultiplayer.new();set_multiplayer(api,NodePath("/root/World"))
	world=load("res://scenes/world.tscn").instantiate();world.name="World"
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT);root.add_child(world)
	wire=Wire.new();wire.name="Wire";world.add_child(wire)
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.free()
	world._mc_prewarmer=null;world.set_process(false);world.set_physics_process(false)
	await process_frame
	world.control.hide();world.control.team.hide()
	world.now_choose_map="Map10x10";world.refresh_map_presentation()
	peer=ENetMultiplayerPeer.new()
	check((peer.create_server(port,1) if server else peer.create_client("127.0.0.1",port))==OK,"real separate-process ENet endpoint")
	api.multiplayer_peer=peer
	check(await until(func():return api.get_peers().size()==1),"peer connected")
	if server:await host_case()
	else:await guest_case()
	await create_timer(0.25,true,false,true).timeout
	# Despawn while the scoped API is still live; disconnecting first makes node teardown query an inactive peer.
	if server:await create_timer(0.2,true,false,true).timeout
	world.queue_free();await process_frame;await process_frame
	api.multiplayer_peer=OfflineMultiplayerPeer.new();peer.close()
	var door:Node=root.get_node_or_null("DarkOakDoorTransition")
	if door!=null:door.queue_free()
	set_multiplayer(null,NodePath("/root/World"));api=null;peer=null
	await process_frame
	print("ROUND_NETWORK_RESULT role=%s checks=%d failures=%d"%["server" if server else "client",checks,failures])
	quit(0 if failures==0 else 1)
