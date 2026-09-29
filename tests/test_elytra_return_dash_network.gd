extends "res://tests/test_elytra_return_dash.gd"
## Two real ENet APIs, distinct World2Ds, authoritative dash and late-join pose/state.
var host_root:Node2D
var guest_root:Node2D
var host_api:SceneMultiplayer
var guest_api:SceneMultiplayer
var host_peer:ENetMultiplayerPeer
var guest_peer:ENetMultiplayerPeer

func until(condition:Callable,seconds:float = 5.0) -> bool:
	var deadline:int = Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline and not done:
		if condition.call(): return true
		await process_frame
	return false

func scope(label:String) -> Node2D:
	var view:=SubViewport.new()
	view.name = label+"View"
	view.size = Vector2i(512,384)
	view.world_2d = World2D.new()
	root.add_child(view)
	var node:Node2D = FlightArena.new()
	node.name = "Arena"
	view.add_child(node)
	return node

func net_actor(parent:Node2D,role:String,label:String,point:Vector2) -> Node2D:
	var node:Node2D = load("res://scenes/characters/我的世界/"+role+".tscn").instantiate()
	node.name = label
	node.Team = "Team0"
	parent.add_child(node)
	node.state_machine.set_physics_process(false)
	node.set_physics_process(false)
	node.set_process(false)
	prime(node,point,Vector2.RIGHT*240)
	return node

func net_victim(parent:Node2D,label:String,point:Vector2) -> Node2D:
	var previous:Node2D = arena
	arena = parent
	var node:Node2D = victim(point)
	node.name = label
	arena = previous
	return node

func finish() -> void:
	if done: return
	game.now_stop_state = true
	for parent:Node2D in [host_root,guest_root]:
		if not is_instance_valid(parent): continue
		for child:Node in parent.get_children(): child.queue_free()
	await process_frame
	await process_frame
	if is_instance_valid(host_root): set_multiplayer(null,host_root.get_path())
	if is_instance_valid(guest_root): set_multiplayer(null,guest_root.get_path())
	if host_peer!=null: host_peer.close()
	if guest_peer!=null: guest_peer.close()
	if is_instance_valid(host_root): host_root.get_parent().queue_free()
	if is_instance_valid(guest_root): guest_root.get_parent().queue_free()
	print("ELYTRA_DASH_NETWORK_RESULT checks=",checks," failures=",failures)
	await super.finish()

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	evidence = OS.get_environment("ELYTRA_EVIDENCE_DIR")
	if evidence.is_empty(): evidence = "user://elytra_dash_network"
	DirAccess.make_dir_recursive_absolute(evidence)
	create_timer(70,true,false,true).timeout.connect(func():push_error("ELYTRA_ENET_TIMEOUT"); failures+=1; finish())
	host_root = scope("Host")
	guest_root = scope("Guest")
	host_api = SceneMultiplayer.new()
	guest_api = SceneMultiplayer.new()
	set_multiplayer(host_api,host_root.get_path())
	set_multiplayer(guest_api,guest_root.get_path())
	host_peer = ENetMultiplayerPeer.new()
	host_peer.set_bind_ip("127.0.0.1")
	check(host_peer.create_server(0,1)==OK,"real ENet authority listens on an ephemeral local port")
	host_api.multiplayer_peer = host_peer
	guest_peer = ENetMultiplayerPeer.new()
	check(guest_peer.create_client("127.0.0.1",host_peer.get_host().get_local_port())==OK,"guest creates a separate real transport")
	guest_api.multiplayer_peer = guest_peer
	var hosts:Array[Node2D] = []
	var guests:Array[Node2D] = []
	var victims:Array[Node2D] = []
	var guest_victims:Array[Node2D] = []
	for i:int in range(2):
		var role:String = "鞘翅长矛" if i==0 else "鞘翅重锤长矛"
		var y:float = -60.0 if i==0 else 70.0
		var source:Node2D = net_actor(host_root,role,"Flyer"+str(i),Vector2(-140,y))
		var remote:Node2D = net_actor(guest_root,role,"Flyer"+str(i),Vector2(-140,y))
		var target:Node2D = net_victim(host_root,"Victim"+str(i),Vector2(20,y))
		var remote_target:Node2D = net_victim(guest_root,"Victim"+str(i),Vector2(20,y))
		source._pvp_target = target
		remote._pvp_target = remote_target
		hosts.append(source)
		guests.append(remote)
		victims.append(target)
		guest_victims.append(remote_target)
		# State is already in progress before the first replicated pose is accepted.
		check(source.try_pierce_dash(target),role+": authority starts the aligned dash")
		source._step_glide(0.08)
	check(await until(func():return host_api.get_peers().size()==1 and guest_peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED),"independent scene APIs complete the real ENet handshake")
	for i:int in range(2):
		var source:Node2D = hosts[i]
		var remote:Node2D = guests[i]
		var target:Node2D = victims[i]
		var remote_target:Node2D = guest_victims[i]
		check(source.is_multiplayer_authority() and not remote.is_multiplayer_authority(),"only server owns flyer "+str(i))
		check(source.get_world_2d()!=remote.get_world_2d() and not source._is_enemy(remote_target),"different replicas cannot become each other's target "+str(i))
		check(await until(func():return remote._pierce_dashing and remote._glide_velocity.is_equal_approx(source._glide_velocity) and is_equal_approx(remote._pierce_dash_left,source._pierce_dash_left)),"initial/late state includes live dash phase, speed and remaining time "+str(i))
		check(remote.get_node("MultiplayerSynchronizer").replication_config.has_property(NodePath(".:global_position")),"extending flight replication preserves original base position sync "+str(i))
		var old_hp:int = target.health
		var old_remote_hp:int = remote_target.health
		var position_before:Vector2 = remote.global_position
		check(not remote.try_pierce_dash(remote_target) and not remote._apply_spear_contact(remote_target,remote_target.global_position,Vector2.RIGHT,560,true),"guest cannot independently award dash speed or damage "+str(i))
		remote._step_glide(0.2)
		check(remote.global_position==position_before and remote_target.health==old_remote_hp,"guest integrator produces no extra local move/hit "+str(i))
		var incoming:float = source._glide_velocity.length()
		source._step_glide(0.17)
		check(target.health<old_hp and source._glide_velocity.length()>incoming+100,"authoritative real swept hit grants additional propulsion "+str(i))
		check(not source._airborne,"combo has not bounced before the actual pass clears "+str(i))
		check(await until(func():return remote._glide_velocity.is_equal_approx(source._glide_velocity)),"hit-enhanced speed reaches the other peer without replaying its hit "+str(i))
		check(await until(func():return remote.global_position.distance_to(source.global_position)<0.1),"real dash movement reaches the remote pose "+str(i))
		for frame:int in range(45):
			if not source._pierce_dashing: break
			source._step_glide(1.0/60.0)
		check(await until(func():return not remote._pierce_dashing and remote._airborne==source._airborne and remote._chain_level==source._chain_level),"dash completion and deferred combo phase synchronize "+str(i))
		if i==1: check(source._airborne and source._chain_level==1,"network combo starts one post-pass mace chain")
		else: check(not source._airborne,"network pure spear stays a non-mace flyer")
		old_remote_hp = remote_target.health
		remote._step_glide(1.0)
		check(remote_target.health==old_remote_hp,"remote completed dash cannot generate another hit "+str(i))
	await finish()
