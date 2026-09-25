extends SceneTree
## One Godot process, two independent SceneMultiplayer ENet peers and an
## actual MultiplayerSpawner/Synchronizer instance of the character scene.
const SCENE_PATH:String = "res://scenes/characters/我的世界/天堂陨落长弓.tscn"
var checks:int = 0
var failures:int = 0
var done:bool = false
var game:Node
var saved:Dictionary
var saved_stop:bool
var world:Node
var host_root:Node2D
var guest_root:Node2D
var host_api:SceneMultiplayer
var guest_api:SceneMultiplayer
var host_peer:ENetMultiplayerPeer
var guest_peer:ENetMultiplayerPeer

func _initialize() -> void: call_deferred("run")

func check(condition:bool,label:String) -> void:
	checks += 1
	if not condition: failures += 1
	print("PASS: " if condition else "FAIL: ",label)

func until(condition:Callable,seconds:float = 4.0) -> bool:
	var deadline:int = Time.get_ticks_msec()+int(seconds*1000.0)
	while Time.get_ticks_msec()<deadline and not done:
		if condition.call(): return true
		await process_frame
	return false

func rings() -> Array[Node]: return get_nodes_in_group("HeavenfallShotRing")

func freeze_rings() -> void:
	for ring:Node in rings(): ring.set_process(false)

func spawner(parent:Node2D) -> void:
	var spawn:=MultiplayerSpawner.new()
	spawn.name = "BowSpawner"
	spawn.spawn_path = NodePath("..")
	spawn.add_spawnable_scene(SCENE_PATH)
	parent.add_child(spawn)

func run() -> void:
	create_timer(35.0,true,false,true).timeout.connect(func(): print("MUZZLE_NETWORK_TIMEOUT"); finish(2))
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.set_process(false)
	world.set_physics_process(false)
	host_root = Node2D.new()
	host_root.name = "MuzzleNetHost"
	guest_root = Node2D.new()
	guest_root.name = "MuzzleNetGuest"
	world.add_child(host_root)
	world.add_child(guest_root)
	host_api = SceneMultiplayer.new()
	guest_api = SceneMultiplayer.new()
	set_multiplayer(host_api,host_root.get_path())
	set_multiplayer(guest_api,guest_root.get_path())
	host_peer = ENetMultiplayerPeer.new()
	host_peer.set_bind_ip("127.0.0.1")
	var err:Error = host_peer.create_server(0,1)
	check(err == OK,"local authoritative peer starts")
	if err != OK: finish(1); return
	host_api.multiplayer_peer = host_peer
	guest_peer = ENetMultiplayerPeer.new()
	err = guest_peer.create_client("127.0.0.1",host_peer.get_host().get_local_port())
	check(err == OK,"independent client connects")
	if err != OK: finish(1); return
	guest_api.multiplayer_peer = guest_peer
	spawner(host_root)
	spawner(guest_root)
	var joined:bool = await until(func(): return host_api.get_peers().size() == 1 and guest_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED)
	check(joined,"loopback ENet handshake completes")
	if not joined: finish(1); return
	var center:Vector2 = Vector2(120,180)
	var host_unit:Node2D = load(SCENE_PATH).instantiate()
	host_unit.name = "NetworkHeavenfallBow"
	host_unit.position = center
	host_unit.Can_Attack = false
	host_unit.Can_Skill = false
	host_root.add_child(host_unit)
	host_unit.state_machine.set_physics_process(false)
	host_unit.set_physics_process(false)
	var spawned:bool = await until(func(): return guest_root.has_node("NetworkHeavenfallBow"))
	check(spawned,"real MultiplayerSpawner creates the longbow replica")
	if not spawned: finish(1); return
	var guest_unit:Node2D = guest_root.get_node("NetworkHeavenfallBow")
	guest_unit.state_machine.set_physics_process(false)
	guest_unit.set_physics_process(false)
	check(host_unit.is_multiplayer_authority() and not guest_unit.is_multiplayer_authority(),"only host owns the firing actor")
	check(rings().is_empty(),"initial visual synchronization does not replay historical muzzle rings")
	guest_unit._fire()
	check(rings().is_empty(),"non-authority direct fire cannot originate a shot ring")
	host_unit.facing = Vector2(0.6,0.8)
	var launch_direction:Vector2 = host_unit.facing
	var expected:Vector2 = host_unit.global_position+host_unit.facing*host_unit.muzzle_offset
	host_unit._fire()
	freeze_rings()
	# Freeze real projectiles; this test isolates muzzle synchronization, not hits.
	for child:Node in world.get_children():
		if child.get_script() != null and str(child.get_script().resource_path).ends_with("heavenfall_bolt.gd"):
			child.set_physics_process(false)
	check(rings().size() == 1,"authority produces one local ring before network polling")
	host_unit.global_position += Vector2(160,40)
	guest_unit.global_position += Vector2(-80,60)
	host_unit.facing = Vector2.LEFT
	guest_unit.facing = Vector2.UP
	var received:bool = await until(func(): freeze_rings(); return rings().size() == 2)
	check(received,"reliable visual RPC reaches the independent ENet peer exactly once")
	var same_point:bool = received
	var same_direction:bool = received
	var same_palette:bool = received
	var harmless:bool = received
	for ring:Node2D in rings():
		same_point = same_point and ring.global_position.is_equal_approx(expected)
		same_direction = same_direction and ring.ring_axis.is_equal_approx(launch_direction) and is_equal_approx(ring.ring_depth_ratio,0.35)
		same_palette = same_palette and ring.ring_palette == PackedColorArray(host_unit.SHOT_RING_PALETTE)
		harmless = harmless and not ring.is_in_group("AI_Hazard") and ring._blocks.is_empty() and ring.get_child_count() == 0
	check(same_point,"both peers use transmitted launch coordinates, not shifted actor positions")
	check(same_direction,"both peers use launch-plane normal from RPC, never their shifted live facing")
	check(same_palette,"both peers use identical teal/cyan/silver palette")
	check(harmless,"neither peer creates damage, hitbox, hazard, rubble or sound with the ring")
	var state:Dictionary = host_unit.visual_state()
	guest_unit.accept_visual(state)
	state.shot += 1
	guest_unit.accept_visual(state)
	guest_unit.accept_visual(state)
	await create_timer(0.12).timeout
	freeze_rings()
	check(rings().size() == 2,"subsequent replicated recoil state never duplicates the RPC ring")
	game.now_stop_state = true
	var ages:Array[float] = []
	for ring:Node in rings(): ages.append(ring._elapsed); ring._process(0.2)
	var frozen:bool = true
	for i:int in rings().size(): frozen = frozen and is_equal_approx(rings()[i]._elapsed,ages[i])
	check(frozen,"both visual lifetimes freeze during battle pause")
	game.now_stop_state = false
	for ring:Node in rings(): ring._process(0.5)
	await process_frame
	check(rings().is_empty(),"both replicated rings self-clean after their lifetime")
	finish(0 if failures == 0 else 1)

func finish(code:int) -> void:
	if done: return
	# Despawn the networked actor while both APIs are still active. Detaching the
	# peers before destroying its two synchronizers produces engine-level reset
	# errors even when replication and damage have passed every assertion.
	if is_instance_valid(host_root) and host_root.has_node("NetworkHeavenfallBow"):
		host_root.get_node("NetworkHeavenfallBow").queue_free()
		var deadline:int = Time.get_ticks_msec()+1800
		while is_instance_valid(guest_root) and guest_root.has_node("NetworkHeavenfallBow") and Time.get_ticks_msec() < deadline:
			await process_frame
		await process_frame
		if code == 0:
			check(not guest_root.has_node("NetworkHeavenfallBow"),"authoritative despawn removes the replica before the network is torn down")
	done = true
	print("HEAVENFALL_MUZZLE_NETWORK: %d checks / %d failures" % [checks,failures])
	if code == 0 and failures > 0: code = 1
	if host_api != null: host_api.multiplayer_peer = null
	if guest_api != null: guest_api.multiplayer_peer = null
	if host_peer != null: host_peer.close()
	if guest_peer != null: guest_peer.close()
	if is_instance_valid(host_root): set_multiplayer(null,host_root.get_path())
	if is_instance_valid(guest_root): set_multiplayer(null,guest_root.get_path())
	if is_instance_valid(world): world.queue_free()
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	# Flush queued audio and replicated nodes before engine resource-cache teardown.
	await process_frame
	await process_frame
	quit(code)
