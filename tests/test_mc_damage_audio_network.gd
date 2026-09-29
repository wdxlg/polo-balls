extends "res://tests/test_mc_snow_golem_burst_network.gd"
## Real ENet, authoritative variants, replay rejection and peer-local World2D.
func hit_players(parent:Node) -> Array[Node]:
	var result:Array[Node]=[]
	for node:Node in get_nodes_in_group("MCNativeSFX"):
		if parent.is_ancestor_of(node) and node.get_meta("mc_unified_hit",false): result.append(node)
	return result

func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	saved_stop=game.now_stop_state
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	world=Node2D.new()
	root.add_child(world)
	current_scene=world
	evidence=OS.get_environment("MC_AUDIO_EVIDENCE_DIR")
	if evidence.is_empty(): evidence="user://mc_damage_audio_network"
	DirAccess.make_dir_recursive_absolute(evidence)
	create_timer(50,true,false,true).timeout.connect(func():finish(2))
	host_scope=scope("DamageHost")
	guest_scope=scope("DamageGuest")
	host_api=SceneMultiplayer.new()
	guest_api=SceneMultiplayer.new()
	set_multiplayer(host_api,host_scope.get_path())
	set_multiplayer(guest_api,guest_scope.get_path())
	host_peer=ENetMultiplayerPeer.new()
	host_peer.set_bind_ip("127.0.0.1")
	check(host_peer.create_server(0,1)==OK,"real damage audio ENet server")
	host_api.multiplayer_peer=host_peer
	guest_peer=ENetMultiplayerPeer.new()
	check(guest_peer.create_client("127.0.0.1",host_peer.get_host().get_local_port())==OK,"independent ENet client")
	guest_api.multiplayer_peer=guest_peer
	check(await until(func(): return host_api.get_peers().size()==1 and guest_peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED),"real transport handshake")
	var target:Node2D=opponent(host_scope)
	var replica:Node2D=opponent(guest_scope)
	await process_frame
	for amount:float in [49,50,51,100]:
		var previous:int=replica.mc_damage_audio_count
		target.request_mc_damage_audio(amount,target.global_position)
		check(await until(func(): return replica.mc_damage_audio_count==previous+1),"one real RPC delivery "+str(amount))
		check(target.mc_damage_audio_last==replica.mc_damage_audio_last,"actual/gain/event/variant/serial identical on both peers")
		check(replica.mc_damage_audio_last.event==("entity.player.attack.crit" if amount>50 else "entity.player.hurt"),"client strict 50 boundary")
	check(await until(func():return not hit_players(host_scope).is_empty() and not hit_players(guest_scope).is_empty()),"both peers created real native players")
	check(await until(func():
		var hosts:Array[Node]=hit_players(host_scope)
		var guests:Array[Node]=hit_players(guest_scope)
		return not hosts.is_empty() and not guests.is_empty() and hosts.back().get_meta("mc_damage_serial",0)==target._mc_damage_audio_serial and guests.back().get_meta("mc_damage_serial",0)==target._mc_damage_audio_serial),"queued playback reaches the same latest serial on both peers")
	var a:AudioStreamPlayer2D=hit_players(host_scope).back()
	var b:AudioStreamPlayer2D=hit_players(guest_scope).back()
	check(a.get_world_2d()!=b.get_world_2d() and a.get_parent()==host_scope and b.get_parent()==guest_scope,"audio routed to each peer World2D")
	print("NETWORK_CUES ",a.stream.resource_path," ",b.stream.resource_path," ",a.volume_db," ",b.volume_db," bus=",b.bus)
	check(a.stream==b.stream and a.volume_db==b.volume_db and b.bus==&"GameplayRecord","stream variant gain and recording bus preserved")
	var count:int=replica.mc_damage_audio_count
	target._receive_mc_damage_audio.rpc(target._mc_damage_audio_serial,100,target.global_position,0)
	for i:int in range(5): await process_frame
	check(replica.mc_damage_audio_count==count,"duplicate reliable serial not replayed")
	replica.request_mc_damage_audio(51,replica.global_position)
	check(replica.mc_damage_audio_count==count,"client cannot invent authoritative cues")
	# Each same-frame hit has a new serial; no global/event audio debounce.
	for i:int in range(20): target.request_mc_damage_audio(51,target.global_position)
	check(await until(func():return replica.mc_damage_audio_count==count+20),"20 real same-frame packets are 20 client settlements")
	game.now_stop_state=true
	count=target.mc_damage_audio_count
	target.request_mc_damage_audio(51,target.global_position)
	check(target.mc_damage_audio_count==count,"paused battle does not send new cues")
	game.now_stop_state=false
	print("MC_DAMAGE_NETWORK_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
