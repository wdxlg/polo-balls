extends "res://tests/test_elytra_return_dash_network.gd"
func net_actor(parent:Node2D,_role:String,label:String,point:Vector2) -> Node2D:
	var node:Node2D = load("res://scenes/characters/我的世界/卫道士.tscn").instantiate()
	node.name = label
	node.Team = "Team0"
	parent.add_child(node)
	node.global_position = point
	node.state_machine.set_physics_process(false)
	node.set_physics_process(false)
	node.set_process(false)
	return node
func finish() -> void:
	print("VINDICATOR_NETWORK_RESULT checks=",checks," failures=",failures)
	await super.finish()
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Development_Mode = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	arena = FlightArena.new()
	root.add_child(arena)
	current_scene = arena
	create_timer(45,true,false,true).timeout.connect(func():push_error("VINDICATOR_ENET_TIMEOUT"); failures+=1; finish())
	host_root = scope("Host")
	guest_root = scope("Guest")
	host_api = SceneMultiplayer.new()
	guest_api = SceneMultiplayer.new()
	set_multiplayer(host_api,host_root.get_path())
	set_multiplayer(guest_api,guest_root.get_path())
	host_peer = ENetMultiplayerPeer.new()
	host_peer.set_bind_ip("127.0.0.1")
	check(host_peer.create_server(0,1)==OK,"host listens on an ephemeral ENet port")
	host_api.multiplayer_peer = host_peer
	guest_peer = ENetMultiplayerPeer.new()
	check(guest_peer.create_client("127.0.0.1",host_peer.get_host().get_local_port())==OK,"guest opens a real independent connection")
	guest_api.multiplayer_peer = guest_peer
	var source:Node2D = net_actor(host_root,"","Axe",Vector2.ZERO)
	var remote:Node2D = net_actor(guest_root,"","Axe",Vector2.ZERO)
	var target:Node2D = net_victim(host_root,"Victim",Vector2(180,0))
	var replica:Node2D = net_victim(guest_root,"Victim",Vector2(180,0))
	source.set_player_control_peer(1)
	source.set_player_control_aim_position(Vector2(180,0))
	source.attack_wait = 0.0
	check(source._begin_charge(false),"authority begins charging before handshake completes")
	source.charge_elapsed = source.full_charge_seconds*0.75
	source._update_pose()
	check(await until(func():return host_api.get_peers().size()==1 and guest_peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED),"both scene APIs complete the transport handshake")
	for warm:int in 8: await process_frame
	check(source.is_multiplayer_authority() and not remote.is_multiplayer_authority(),"only host owns attack simulation")
	check(not source.mc_enemy(replica) and source.get_world_2d()!=remote.get_world_2d(),"replica worlds cannot become combat targets")
	source._sync_visual(true)
	check(await until(func():return remote.phase==source.Phase.CHARGE and is_equal_approx(remote.charge_ratio(),0.75)),"late initial state includes actual charge and raised pose")
	check(remote.blade_center().distance_to(source.blade_center())<0.1,"replicated pose reproduces exact axe geometry")
	var before_charge:float = remote.charge_elapsed
	var before_position:Vector2 = remote.global_position
	remote._advance_dash(0.5)
	remote._advance_swing(0.5)
	check(remote.charge_elapsed==before_charge and remote.global_position==before_position,"guest cannot run dash or swing simulation")
	var last_height:float = remote.blade_center().y
	var previous_shaft:Vector2 = Vector2.UP
	for ratio:float in [0.8,0.9,0.95]:
		source.charge_elapsed = source.full_charge_seconds*ratio
		source._update_pose()
		source._sync_visual(true)
		check(await until(func():return is_equal_approx(remote.charge_ratio(),ratio)),"late charge progression reaches replica: "+str(ratio))
		var shaft:Vector2 = remote._axe.to_global(remote.AXE_GRIP+Vector2(6,-6)+remote._axe.offset)-remote._axe.to_global(remote.AXE_GRIP+remote._axe.offset)
		check(remote.blade_center().y<last_height and absf(previous_shaft.angle_to(shaft.normalized()))>0.01 and is_equal_approx(remote._axe.rotation,remote.AXE_HOLD_ANGLE) and remote.blade_center().distance_to(source.blade_center())<0.1,"replica raises and rotates the fixed-grip axe after 75%: "+str(ratio))
		last_height = remote.blade_center().y
		previous_shaft = shaft.normalized()
	source._release_swing()
	check(await until(func():return remote.phase==source.Phase.SWING and is_equal_approx(remote.released_charge,0.95)),"release phase and locked charge cross the wire")
	var before:int = target.health
	var remote_before:int = replica.health
	check(not remote.deal_axe_hit(replica,replica.global_position) and replica.health==remote_before,"guest cannot award local damage")
	check(source.deal_axe_hit(target,target.global_position) and target.health<before,"only authority settles charged melee damage")
	check(await until(func():return replica.health_bar.get_node("TextureRect/Label").text==target.health_bar.get_node("TextureRect/Label").text and absf(replica.health_bar.health_bar.value-float(target.health)/float(target.Max_health))<0.000001 and target.health_bar.label.text==str(target.health)),"settled health display reaches the replica without replaying damage")
	check(replica.health==remote_before,"replica keeps gameplay health host-owned, as required by base replication")
	source.cancel_attack()
	source.attack_wait = 0.0
	source.rush_wait = 0.0
	source.set_player_control_aim_position(Vector2(700,0))
	check(source._begin_charge(true),"host begins separate rush windup")
	source.charge_elapsed = source.full_charge_seconds*0.1
	source._update_pose()
	source._sync_visual(true)
	check(await until(func():return remote.phase==source.Phase.DASH and is_equal_approx(remote.charge_ratio(),0.1)),"early rush pose reaches replica with actual low charge")
	check(remote._arm.to_global(remote.HAND-remote.SHOULDER).y<remote._arm.global_position.y-4 and remote.blade_center().distance_to(source.blade_center())<0.1,"guest sees high rush preparation without granting full damage")
	var held:Vector2 = source.blade_center()
	source._release_swing()
	check(await until(func():return remote.phase==source.Phase.SWING and remote.released_rush),"rush release mode crosses ENet")
	check(remote.blade_center().distance_to(held)<0.1,"guest starts the rush chop at the exact raised hand position")
	for progress:float in [0.2,0.6,0.9]:
		source.phase_elapsed = source.swing_seconds*progress
		source._update_pose()
		source._sync_visual(true)
		check(await until(func():return is_equal_approx(remote.phase_elapsed,source.phase_elapsed)),"fast chop clock reaches replica: "+str(progress))
		check(remote.blade_center().distance_to(source.blade_center())<0.1,"fast chop geometry matches the host: "+str(progress))
	var guest_position:Vector2 = remote.global_position
	var guest_health:int = replica.health
	var guest_clock:float = remote.phase_elapsed
	remote.tick_physics(load("res://classes/ball.gd").State.Move,0.01)
	check(remote.phase_elapsed>guest_clock and remote.phase==source.Phase.SWING,"guest visually advances the fast chop between RPC packets")
	check(remote.global_position==guest_position and replica.health==guest_health and remote.get_debug_attack_regions().is_empty(),"visual interpolation never simulates movement or awards damage")
	source.phase = source.Phase.DASH
	source.charge_elapsed = 0.16
	source._sync_visual(true)
	check(await until(func():return remote.phase==source.Phase.DASH and is_equal_approx(remote.charge_elapsed,0.16)),"rush visual clock is reanchored by host state")
	remote.tick_physics(load("res://classes/ball.gd").State.Move,0.01)
	check(is_equal_approx(remote.charge_elapsed,0.17) and remote.global_position==guest_position,"guest keeps lifting through gaps without simulating dash movement")
	var stun:Node = source.apply_stun(1.0,target)
	source.tick_physics(load("res://classes/ball.gd").State.Move,0.01)
	check(await until(func():return remote.phase==source.Phase.IDLE),"hard-control cancellation is reliably replicated")
	stun.free()
	await finish()
