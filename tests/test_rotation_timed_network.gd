extends SceneTree
class Wire extends Node:
	var flags:Dictionary={}
	@rpc("any_peer","call_remote","reliable")
	func mark(key:String) -> void: flags[key]=true
var world:Node
var game:Node
var api:SceneMultiplayer
var peer:ENetMultiplayerPeer
var wire:Wire
var base:Node
var checks:int=0
var failures:int=0
var server:bool=false
func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("ROUND_NET_FAIL "+label)
	else:print("PASS "+label)
func until(f:Callable,seconds:float=8.0) -> bool:
	var end:int=Time.get_ticks_msec()+int(seconds*1000.0)
	while Time.get_ticks_msec()<end:
		if f.call():return true
		await process_frame
	return false
func ack(key:String) -> void: wire.mark.rpc(key)
func flag(key:String) -> bool:return wire.flags.has(key)
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
	await process_frame
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.free()
	world._mc_prewarmer=null;world.set_process(false);world.set_physics_process(false)
	world.control.hide();world.control.team.hide()
	world.now_choose_map="Map10x10";world.refresh_map_presentation()
	peer=ENetMultiplayerPeer.new()
	check((peer.create_server(port,1) if server else peer.create_client("127.0.0.1",port))==OK,"real separate-process ENet endpoint")
	api.multiplayer_peer=peer
	check(await until(func():return api.get_peers().size()==1),"peer connected")
	if server:await host_case()
	else:await guest_case()
	await create_timer(0.25,true,false,true).timeout
	api.multiplayer_peer=OfflineMultiplayerPeer.new();peer.close()
	world.queue_free();await process_frame
	var door:Node=root.get_node_or_null("DarkOakDoorTransition")
	if door!=null:door.queue_free()
	set_multiplayer(null,NodePath("/root/World"));api=null;peer=null
	await process_frame
	print("ROUND_NETWORK_RESULT role=%s checks=%d failures=%d"%["server" if server else "client",checks,failures])
	quit(0 if failures==0 else 1)
func host_case() -> void:
	check(await until(func():return flag("ready")),"remote world ready")
	world._timed_running=true;world._timed_time_left=5.0;world._timed_damage_by_setup={1:10.0,2:8.0}
	world._sync_timed_match(0.0,true)
	check(await until(func():return flag("clock")),"client verified countdown and score")
	world._receive_timed_match.rpc(world._timed_sync_sequence,999.0,{1:999.0},false,true,false,99)
	ack("stale_sent");check(await until(func():return flag("stale")),"client rejected duplicate snapshot")
	world._timed_damage_by_setup={1:50.0,2:50.0};world._timed_time_left=0.0;world._finish_timed_training()
	check(await until(func():return flag("overtime")),"overtime received without local verdict")
	world._timed_damage_by_setup[2]=51.0;world._finish_timed_training()
	check(await until(func():return flag("winner")),"final verdict reached client")
	world.reset();await process_frame;await process_frame
	game.Game_Settings.Training_Mode_Type="rotation";game.Game_Settings.Rotation_Match_Type="duel";game.Game_Settings.Training_Wheel_Battle=false
	world.control.team.show();world._battle_setup_next_id=1
	for side:String in ["left","right"]:
		for i:int in range(2):
			world._enqueue_rotation_character("",side+str(i),world._rotation_spawn_position(side),side,"res://scenes/ball.tscn")
	world.control.hide();world.control.team.hide();world._update_special_training_modes(0)
	for unit:Node in get_nodes_in_group("Ball"):unit.process_mode=Node.PROCESS_MODE_DISABLED
	ack("rotation");check(await until(func():return flag("rotation_ready")),"client switched mode before round")
	var loser:Node=world._find_character_by_setup_id_any(int(world._rotation_active_setup.right));loser.health=0;loser.queue_free()
	check(await until(func():return world._rotation_load_ready),"server real loader completes")
	check(await until(func():return not world._rotation_transitioning),"server finishes real doors")
	check(await until(func():return flag("rotation_done")),"client independently completed synchronized visual transition")
	world._rotation_remote_progress.rpc(world._rotation_ui_token-1,0.0,false)
	ack("old_progress");check(await until(func():return flag("progress_checked")),"old progress cannot reopen or regress client")
	ack("finish")
func guest_case() -> void:
	ack("ready")
	check(await until(func():return world._timed_received_sequence>0),"real world receives authority snapshot")
	check(is_equal_approx(world._timed_time_left,5.0) and world._timed_damage_by_setup[1]==10.0,"countdown and actual score copied")
	world._update_special_training_modes(20)
	check(is_equal_approx(world._timed_time_left,5.0) and not world._timed_finished,"client cannot advance clock or judge timeout")
	world.duel_top_hud._update_clock(0)
	check(world.duel_top_hud.clock_text()=="00:05","remote upper HUD uses authority countdown")
	ack("clock");await until(func():return flag("stale_sent"));await process_frame
	check(world._timed_winner_setup!=99 and world._timed_time_left==5.0,"duplicate/old sequence cannot rewrite final state")
	ack("stale")
	check(await until(func():return world._timed_overtime),"remote receives overtime")
	world._finish_timed_training();world.on_timed_health_loss(null,100)
	check(not world._timed_finished and world._timed_damage_by_setup[1]==50,"client cannot settle or add points")
	ack("overtime")
	check(await until(func():return world._timed_finished and world._timed_winner_setup==1),"winner is authority-selected")
	check(world._timed_damage_by_setup[2]==51 and not paused and not game.now_stop_state,"final score frozen without client pause")
	ack("winner");await until(func():return flag("rotation"))
	world.reset();await process_frame;await process_frame
	game.Game_Settings.Training_Mode_Type="rotation";game.Game_Settings.Rotation_Match_Type="duel";game.Game_Settings.Training_Wheel_Battle=false
	world.control.hide();world.control.team.hide();ack("rotation_ready")
	check(await until(func():return world.duel_top_hud.round_result_locked),"network round outcome displays before doors")
	check(world._rotation_rosters.left.size()==2 and int(world._rotation_next_index.left)==1,"outcome RPC carries exact old roster snapshot")
	check(world.duel_top_hud.winner_index==0 and world.duel_top_hud.sides[0].raw_name=="left0","correct prior winner shown, not upcoming actor")
	check(await until(func():return is_instance_valid(world._rotation_door) and world._rotation_door.phase==world._rotation_door.Phase.COVERED),"remote doors really reach full coverage")
	check(await until(func():return world._rotation_load_ready),"remote waits for server ready without spawning contenders")
	check(world._rotation_ui_progress==1.0,"real progress reaches completion remotely")
	check(await until(func():return world._rotation_combat_released),"remote display releases at half-open")
	check(world._rotation_door.progress<=0.5,"remote does not reveal active fight before opening midpoint")
	check(await until(func():return not world._rotation_transitioning),"remote transition terminates")
	ack("rotation_done");await until(func():return flag("old_progress"));await process_frame
	check(world._rotation_ui_progress==1 and not is_instance_valid(world._rotation_door),"stale token cannot regress progress or restart doors")
	ack("progress_checked");await until(func():return flag("finish"))
