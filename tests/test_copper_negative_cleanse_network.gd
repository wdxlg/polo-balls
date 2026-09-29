extends "res://tests/test_copper_negative_cleanse.gd"
## Independent SceneMultiplayer + World2D roots over real loopback ENet.
class Arena extends Node2D:
	func _current_map_node() -> Node: return self
	func return_map_world_rect(_map:Node) -> Rect2: return Rect2(-320,-240,640,480)
	func is_combat_runtime_active() -> bool: return true
var host_scope:Node2D
var guest_scope:Node2D
var host_api:SceneMultiplayer
var guest_api:SceneMultiplayer
var host_peer:ENetMultiplayerPeer
var guest_peer:ENetMultiplayerPeer

func until(condition:Callable) -> bool:
	var deadline:int = Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline and not finishing:
		if condition.call(): return true
		await process_frame
	return false

func scope(label:String) -> Node2D:
	var view:=SubViewport.new(); view.name = label; view.size = Vector2i(512,384); view.world_2d = World2D.new()
	world.add_child(view)
	var arena:Node2D = Arena.new(); arena.name = "Arena"; view.add_child(arena)
	return arena

func actor(parent:Node2D) -> Node2D:
	var unit:Node2D = load(COPPER_PATH).instantiate()
	unit.name = "Copper"; unit.Team = "Team0"; parent.add_child(unit)
	unit.state_machine.set_physics_process(false); unit.set_physics_process(false); unit.set_process(false)
	return unit

func finish(code:int) -> void:
	if finishing: return
	finishing = true
	game.now_stop_state = true
	if not await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self): code = 1
	for arena:Node in [host_scope,guest_scope]:
		if is_instance_valid(arena):
			for child:Node in arena.get_children(): child.queue_free()
	await process_frame
	await process_frame
	if is_instance_valid(host_scope): set_multiplayer(null,host_scope.get_path())
	if is_instance_valid(guest_scope): set_multiplayer(null,guest_scope.get_path())
	if host_peer!=null: host_peer.close()
	if guest_peer!=null: guest_peer.close()
	if host_api!=null: host_api.multiplayer_peer = null
	if guest_api!=null: guest_api.multiplayer_peer = null
	host_api = null; guest_api = null; host_peer = null; guest_peer = null
	current_scene = null; world.queue_free()
	await process_frame
	game.Game_Settings = saved; game.now_stop_state = saved_stop
	_stop_audio(root)
	await create_timer(0.15,true,false,true).timeout
	print("COPPER_CLEANSE_NETWORK_RESULT checks=",checks," failures=",failures)
	quit(code)

func run() -> void:
	EFFECTS = load("res://scripts/effects/我的世界/mc_status_effects.gd")
	COLD = load("res://scripts/characters/我的世界/snow_golem/cold.gd")
	CLEANSE = load("res://classes/status_cleansing.gd")
	game = root.get_node("Game"); saved = game.Game_Settings.duplicate(true); saved_stop = game.now_stop_state
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	world = Node2D.new(); root.add_child(world); current_scene = world
	create_timer(65,true,false,true).timeout.connect(func():finish(2))
	host_scope = scope("Host"); guest_scope = scope("Guest")
	host_api = SceneMultiplayer.new(); guest_api = SceneMultiplayer.new()
	set_multiplayer(host_api,host_scope.get_path()); set_multiplayer(guest_api,guest_scope.get_path())
	host_peer = ENetMultiplayerPeer.new(); host_peer.set_bind_ip("127.0.0.1")
	check(host_peer.create_server(0,1)==OK,"ephemeral ENet authority listening")
	host_api.multiplayer_peer = host_peer
	guest_peer = ENetMultiplayerPeer.new()
	check(guest_peer.create_client("127.0.0.1",host_peer.get_host().get_local_port())==OK,"independent ENet client connects")
	guest_api.multiplayer_peer = guest_peer
	check(await until(func():return host_api.get_peers().size()==1 and guest_peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED),"real handshake completed")
	var host:Node2D = actor(host_scope)
	var guest:Node2D = actor(guest_scope)
	await physics_frame
	check(host.is_multiplayer_authority() and not guest.is_multiplayer_authority() and host.get_world_2d()!=guest.get_world_2d(),"authority and replica have separate physics scopes")
	for unit:Node2D in [host,guest]:
		EFFECTS.apply_effect(unit,"poison",2,30.0,unit)
		EFFECTS.apply_effect(unit,"strength",2,30.0,unit)
		COLD.ensure(unit).accept_state(80.0,0.0)
		freeze_statuses(unit)
	check(guest.cleanse_negative_effects()==0 and EFFECTS.current(guest,"poison")!=null,"client cannot independently purify")
	var good:Node = EFFECTS.current(guest,"strength")
	var bolt:Node = natural(host)
	check(await until(func():return is_instance_valid(guest._cleanse_effect)),"natural warning uses production lightning RPC on both peers")
	guest._cleanse_effect.set_process(false)
	check(EFFECTS.current(guest,"poison")!=null,"receiving the natural warning does not cleanse early")
	bolt._process(host.lightning_warning+0.01)
	check(await until(func():return guest._negative_cleanse_revision==1 and EFFECTS.current(guest,"poison")==null and not guest.has_node("MCSnowCold")),"actual impact reliably clears negative potion and cold on replica")
	check(EFFECTS.current(host,"poison")==null and not host.has_node("MCSnowCold"),"same negative state cleared on authority")
	check(EFFECTS.current(guest,"strength")==good and EFFECTS.current(host,"strength")!=null,"positive source identities survive on both peers")
	EFFECTS.apply_effect(guest,"poison",1,20.0,guest); freeze_statuses(guest)
	var new_poison:Node = EFFECTS.current(guest,"poison")
	host._receive_negative_cleanse.rpc(1)
	for i:int in range(6): await process_frame
	check(EFFECTS.current(guest,"poison")==new_poison,"duplicate/reordered cleanse revision cannot erase later effects")
	host._summon_lightning(host.global_position,false)
	for i:int in range(6): await process_frame
	for attack:Node in bolts(host):
		if attack!=bolt: attack.set_process(false); attack._process(host.hit_lightning_warning+0.01)
	for i:int in range(6): await process_frame
	check(guest._negative_cleanse_revision==1 and EFFECTS.current(guest,"poison")==new_poison,"attack lightning produces no cleanse packet")
	EFFECTS.apply_effect(host,"weakness",1,20.0,host); freeze_statuses(host)
	host.cleanse_negative_effects()
	check(await until(func():return guest._negative_cleanse_revision==2 and EFFECTS.current(guest,"poison")==null),"a later genuine cleanse has a new monotonic revision")
	finish(0 if failures==0 else 1)
