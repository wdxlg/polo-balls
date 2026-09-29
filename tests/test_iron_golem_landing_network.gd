extends "res://tests/test_iron_golem_pair.gd"
func run() -> void:
	create_timer(60.0).timeout.connect(func(): push_error("GOLEM_NETWORK_TIMEOUT"); quit(2))
	var args:PackedStringArray = OS.get_cmdline_user_args()
	# Manual two-process probe, not a single-script regression. Known unverified
	# client RPC delivery is documented in MC_IRON_GOLEM.md; do not count as pass.
	if args.size()<2:
		print("SKIP GOLEM_NETWORK: requires server/client and matching port")
		quit(0)
		return
	var server:bool = args.has("server")
	var port:int = int(args[1])
	game = root.get_node("Game")
	game.now_stop_state = false
	game.Game_Settings.Have_Team_Damage = false
	AudioServer.set_bus_mute(0,true)
	var peer := ENetMultiplayerPeer.new()
	var error:Error = peer.create_server(port,1) if server else peer.create_client("127.0.0.1",port)
	check(error==OK,"ENet peer created")
	root.get_multiplayer().multiplayer_peer = peer
	if server: print("GOLEM_NET_LISTENING")
	else: await root.get_multiplayer().connected_to_server
	arena = Node2D.new()
	arena.name = "NetworkArena"
	root.add_child(arena)
	current_scene = arena
	arena.process_mode = Node.PROCESS_MODE_INHERIT
	var g:Node2D = golem(Vector2(-200,0))
	g.name = "NetworkGolem"
	var victim:Node2D = enemy(Vector2.ZERO)
	victim.name = "NetworkVictim"
	var nearby:Node2D = enemy(Vector2(25,0))
	nearby.name = "NetworkNeighbor"
	for unit:Node in get_nodes_in_group("Ball"):
		if unit.has_method("apply_knockback"):
			unit.Can_Attack = false
			unit.Can_Skill = false
			unit.Speed = 0
			unit.set_process(false)
			unit.set_physics_process(false)
			unit.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	if server:
		while not FileAccess.file_exists("user://golem_peer_ready_"+str(port)): await physics_frame
		await create_timer(0.2).timeout
		check(g.launch_target(victim,121.0,390.0,Vector2.UP)!=null,"server started authoritative flight")
	else:
		var ready_file:FileAccess = FileAccess.open("user://golem_peer_ready_"+str(port),FileAccess.WRITE)
		ready_file.store_string("ready")
		ready_file.close()
		# Server may still be loading native assets. Do not disconnect before launch.
		while victim.get_node_or_null("KnockbackEffect_GolemAirborne")==null: await physics_frame
	var highest:float = 0.0
	var flight_seen:bool = false
	var landed_seen:bool = false
	var authoritative_hits:int = 0
	var visuals:Dictionary = {}
	for frame:int in range(260):
		await physics_frame
		root.get_multiplayer().poll()
		var effect:Node = victim.get_node_or_null("KnockbackEffect_GolemAirborne")
		if effect!=null and not effect._finished:
			flight_seen = true
			effect.set_physics_process(false)
			effect.advance(1.0/60.0)
			highest = maxf(highest,effect.height)
			landed_seen = landed_seen or effect.landed
			authoritative_hits = maxi(authoritative_hits,effect.landing_hits)
		for impact:Node in get_nodes_in_group("GolemLandingImpact"): visuals[impact.get_instance_id()] = true
	check(flight_seen and highest>110,"RPC-created flight animates on this peer")
	check(landed_seen and visuals.size()==1,"one authoritative landing visual appears on this peer")
	check(authoritative_hits==1 if server else authoritative_hits==0,"only server settles the landing damage")
	if server: check(nearby.health<10000,"server applied splash damage")
	check(not victim.has_meta("golem_air_height"),"network flight cleans its height state")
	print("GOLEM_NETWORK_RESULT role=",("server" if server else "client")," checks=",checks," failures=",failures)
	# Let the other peer finish before teardown to avoid unrelated synchronizer errors.
	await create_timer(0.3).timeout
	if server: DirAccess.remove_absolute(ProjectSettings.globalize_path("user://golem_peer_ready_"+str(port)))
	root.get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	peer.close()
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
