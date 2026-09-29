extends "res://tests/test_mc_snow_golem_burst_network.gd"
## Real ENet snapshots with independent melt clocks, signed fade progress and rate changes.
var host_field:Node2D
var guest_field:Node2D

func neutral(parent:Node2D) -> Node2D:
	var node:Node2D = load("res://scripts/training/battle_conditions.gd").new(parent)
	parent.add_child(node)
	node.set_physics_process(false)
	return node

func replace_guest_field(remote:Node2D,provider:Node2D) -> Node2D:
	if is_instance_valid(remote._field): remote._field.free()
	var field:Node2D = load("res://scripts/characters/我的世界/snow_golem/snow_field.gd").ensure(remote,guest_scope)
	field.set_physics_process(false)
	field.environment_source = provider
	remote._field = field
	provider.field = field
	return field

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Environment = "none"
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	evidence = OS.get_environment("SNOW_MELT_EVIDENCE_DIR")
	if evidence.is_empty(): evidence = "user://snow_melt_network"
	DirAccess.make_dir_recursive_absolute(evidence)
	create_timer(75,true,false,true).timeout.connect(func():finish(2))
	host_scope = scope("MeltHost")
	guest_scope = scope("MeltGuest")
	host_api = SceneMultiplayer.new()
	guest_api = SceneMultiplayer.new()
	set_multiplayer(host_api,host_scope.get_path())
	set_multiplayer(guest_api,guest_scope.get_path())
	host_peer = ENetMultiplayerPeer.new()
	host_peer.set_bind_ip("127.0.0.1")
	check(host_peer.create_server(0,1)==OK,"melting authority starts a real ENet listener")
	host_api.multiplayer_peer = host_peer
	guest_peer = ENetMultiplayerPeer.new()
	check(guest_peer.create_client("127.0.0.1",host_peer.get_host().get_local_port())==OK,"melting guest creates an independent ENet transport")
	guest_api.multiplayer_peer = guest_peer
	check(await until(func():return host_api.get_peers().size()==1 and guest_peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED),"melting peer roots complete their handshake")
	var source:Node2D = golem(host_scope)
	var remote:Node2D = golem(guest_scope)
	var host_source:Node2D = neutral(host_scope)
	var guest_source:Node2D = neutral(guest_scope)
	host_field = source._field
	guest_field = remote._field
	host_source.field = host_field
	guest_source.field = guest_field
	host_field.environment_source = host_source
	guest_field.environment_source = guest_source
	await physics_frame
	await process_frame
	check(host_field!=guest_field and host_field.get_world_2d()!=guest_field.get_world_2d(),"replicas keep separate physics and terrain managers")
	game.Game_Settings.Environment = "snow"
	host_field._refresh_melt_rate()
	check(await until(func():return is_equal_approx(guest_field._melt_rate,0.5)),"half-speed weather rate is authoritative and reliably synchronized")
	host_field._melt_clock = 300.0
	host_field._clock = 500.0
	host_field.full_snow_lifetime = 2.0
	host_field.snow_fade_duration = 0.4
	var cell:Vector2i = host_field.snow_cell_at(Vector2.ZERO)
	check(host_field.deposit(source,cell,false),"authority places a real one-block trail")
	var ground:Dictionary = {"cell":Vector2i(3,0),"tile":Rect2(48,0,16,16),"rects":[Rect2(48,0,16,16)],"decorative":false}
	var wall:Dictionary = {"cell":Vector2i(0,-3),"tile":Rect2(-8,-56,16,16),"rects":[Rect2(-8,-49,16,2)],"decorative":true}
	host_field.add_environment_patch(host_source,ground)
	host_field.add_environment_patch(host_source,wall)
	host_field._send_changes()
	check(await until(func():return guest_field.patches.size()==1 and guest_field.environment_patches.size()==2),"trail plus floor/wall records actually cross ENet")
	check(guest_field.patches[cell].tile==host_field.patches[cell].tile and guest_field.patches[cell].tile.size==Vector2(16,16),"replicated trails use the same actual block geometry")
	check(not guest_field.deposit(remote,cell,false) and not guest_field.add_environment_patch(guest_source,ground),"guest cannot manufacture new damaging snow")
	host_field.advance(3.4)
	check(is_equal_approx(host_field._clock,503.4) and is_equal_approx(host_field._melt_clock,301.7),"combat clock is not halved with melt clock")
	guest_field = replace_guest_field(remote,guest_source)
	check(await until(func():return guest_field.patches.size()==1 and guest_field.environment_patches.size()==2),"a recreated client requests the current aged layers")
	check(is_equal_approx(guest_field._melt_rate,0.5) and absf((guest_field.patches[cell].expires_at-guest_field._melt_clock)-0.3)<0.01,"late trail snapshot transfers remaining melt time, not host absolute age")
	check(absf((guest_field.environment_patches[ground.cell].expires_at-guest_field._melt_clock)-0.3)<0.01,"environment snapshot no longer restarts permanent/fresh snow on late join")
	host_field.advance(0.8) # Enter fade: 0.1 of 0.4 melt seconds has elapsed.
	guest_field = replace_guest_field(remote,guest_source)
	check(await until(func():return guest_field.patches.size()==1 and guest_field.environment_patches.size()==2),"late join during fade still receives all surviving geometry")
	check(is_equal_approx(guest_field.snow_alpha(guest_field.patches[cell]),0.75),"late normal trail arrives at its real partial opacity")
	check(is_equal_approx(guest_field.snow_alpha(guest_field.environment_patches[wall.cell]),0.75),"late decorative wall snow arrives at the same partial opacity")
	check(guest_field.get_debug_hazard_info().is_empty(),"replicated fading snow is visual-only, not a stale hazard")
	var before:float = guest_field._melt_clock
	game.now_stop_state = true
	guest_field.advance(5.0)
	check(guest_field._melt_clock==before,"guest visual fade freezes during global battle pause")
	game.now_stop_state = false
	game.Game_Settings.Environment = "none"
	host_field._refresh_melt_rate()
	check(await until(func():return is_equal_approx(guest_field._melt_rate,1.0)),"weather-off restores normal melt rate without deleting the existing state")
	check(guest_field.environment_patches.size()==2,"rate change itself preserves already accumulated floor and wall snow")
	guest_field.advance(0.31)
	check(guest_field.patches.is_empty() and guest_field.environment_patches.is_empty(),"client removes fully faded layers locally without performing damage")
	host_field.advance(0.31)
	host_field._send_changes()
	check(await until(func():return guest_field.patches.is_empty() and guest_field.environment_patches.is_empty()),"authority removal confirms expiry without resurrecting a faded tile")
	check(host_field.patches.is_empty() and host_field.environment_patches.is_empty(),"authority also releases both expired sparse layers")
	guest_field._melt_rate = -1.0 # A fixture sentinel for a reliable channel flush barrier.
	host_field._melt_rate_state.rpc(host_field._melt_rate)
	check(await until(func():return guest_field._melt_rate==host_field._melt_rate),"reliable rate barrier confirms expiry packets arrived before peer teardown")
	print("SNOW_SHARED_MELT_NETWORK checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
