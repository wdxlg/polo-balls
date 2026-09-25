extends SceneTree
## One Godot process, two independent SceneMultiplayer ENet peers and an
## actual MultiplayerSpawner/Synchronizer instance of the character scene.
const SCENE_PATH:String = "res://scenes/characters/我的世界/硫方怪.tscn"
var CUBE
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

func sulfur_sound_count(event:String) -> int:
	var count:int = 0
	for node:Node in get_nodes_in_group("MCNativeSFX"):
		if str(node.get_meta("mc_sulfur_event","")) == event: count += 1
	return count

func spawner(parent:Node2D) -> void:
	var spawn:=MultiplayerSpawner.new()
	spawn.name = "SulfurCharacterSpawner"
	spawn.spawn_path = NodePath("..")
	spawn.add_spawnable_scene(SCENE_PATH)
	parent.add_child(spawn)

func run() -> void:
	create_timer(35.0,true,false,true).timeout.connect(func(): print("SULFUR_NETWORK_TIMEOUT"); finish(2))
	game = root.get_node("Game")
	CUBE = load("res://scripts/characters/我的世界/硫方怪.gd")
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
	host_root.name = "SulfurNetHost"
	guest_root = Node2D.new()
	guest_root.name = "SulfurNetGuest"
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
	var center:Vector2 = world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	var host_unit:Node2D = load(SCENE_PATH).instantiate()
	host_unit.name = "NetworkSulfurCube"
	host_unit.Team = "Team0"
	host_unit.position = center
	host_root.add_child(host_unit,true)
	host_unit.state_machine.set_physics_process(false)
	host_unit.set_physics_process(false)
	var appeared:bool = await until(func(): return guest_root.has_node("NetworkSulfurCube"))
	check(appeared,"Spawner creates a real guest-side sulfur scene")
	if not appeared: finish(1); return
	var guest_unit:Node2D = guest_root.get_node("NetworkSulfurCube")
	guest_unit.state_machine.set_physics_process(false)
	guest_unit.set_physics_process(false)
	check(host_unit.is_multiplayer_authority() and not guest_unit.is_multiplayer_authority(),"only host owns gameplay")
	host_unit.set_block(CUBE.Block.ICE)
	var inserted:bool = await until(func(): return guest_unit.block_mode == CUBE.Block.ICE and guest_unit._native_model.block_mode == CUBE.Block.ICE and guest_unit.image.texture == guest_unit._model_viewport.get_texture())
	check(inserted,"network changes the guest's six-sided blue-ice block inside its own live 3D viewport")
	check(host_unit._model_viewport != guest_unit._model_viewport and host_unit.image.texture != guest_unit.image.texture,"host and guest own independent renderers, not one shared or synchronized flat image")
	guest_unit.Skill()
	guest_unit.set_block(CUBE.Block.IRON)
	check(guest_unit.block_mode == CUBE.Block.ICE and host_unit.block_mode == CUBE.Block.ICE,"guest cannot initiate another block state")
	host_unit._leave_ice(center,center+Vector2(25,0))
	check(await until(func(): return get_nodes_in_group("MCSulfurIceTrail").size() >= 4,2.0),"host ice cells replicate visible tiles to the guest")
	host_unit._hop_timer = -0.01
	host_unit._previous_motion_position = host_unit.global_position
	host_unit.global_position += Vector2(0.7,0)
	host_unit.tick_physics(0,0.05)
	check(await until(func(): return sulfur_sound_count("jump") >= 2,2.0),"real host displacement plays one original jump sound on both ENet peers")
	host_unit.set_block(CUBE.Block.IRON)
	host_unit._start_single_slam()
	check(await until(func(): return guest_unit.block_mode == CUBE.Block.IRON and guest_unit._slam_time >= 0.0,2.0),"single iron slam enters on host and replicates to guest")
	host_unit._slam_time = 0.5
	check(await until(func(): return guest_unit._slam_time >= 0.38 and guest_unit.get_ai_attack_threats(null).size() == 1,2.0),"guest renders only the actual iron underside threat during descent")
	host_unit.set_block(CUBE.Block.AMETHYST)
	var crystals_visible:bool = await until(func(): return guest_unit.block_mode == CUBE.Block.AMETHYST and guest_unit._native_model.crystal_layer.visible,2.0)
	if not crystals_visible: print("CRYSTAL_NET_STATE host=",host_unit.block_mode," guest=",guest_unit.block_mode," model=",guest_unit._native_model.block_mode," visible=",guest_unit._native_model.crystal_layer.visible," out=",guest_unit.crystals_out)
	check(crystals_visible,"guest displays independently rendered original-texture 3D crystals")
	var guest_tips_ready:bool = await until(func(): return guest_unit._native_model._swap_left <= 0.0 and guest_unit.get_ai_attack_threats(null).size() == 4,2.0)
	var guest_tips_aligned:bool = guest_tips_ready
	if guest_tips_ready:
		var guest_tips:Array[Vector2] = guest_unit._crystal_tip_points()
		var guest_threats:Array = guest_unit.get_ai_attack_threats(null)
		for i:int in range(4): guest_tips_aligned = guest_tips_aligned and guest_tips[i].distance_to(guest_threats[i].position) < 0.5
	check(guest_tips_aligned,"guest tip-only danger regions follow its own 3D protrusions, including after block insertion")
	host_unit._fire_all_crystals()
	var frozen_shards:Array[Node] = []
	var volley_replicated:bool = await until(func():
		for node:Node in get_nodes_in_group("AI_Hazard"):
			if node.get_script() == host_unit.SHARD:
				node.set_physics_process(false)
				if not frozen_shards.has(node): frozen_shards.append(node)
		return frozen_shards.size() == 8,2.0)
	check(volley_replicated,"amethyst RPC creates four shared-model projectiles on each independent ENet peer")
	var host_shapes:Array[Transform3D] = []
	var guest_shapes:Array[Transform3D] = []
	for shard:Node in frozen_shards:
		if shard.source_ref.get_ref() == host_unit: host_shapes.append(shard.crystal.global_transform)
		elif shard.source_ref.get_ref() == guest_unit: guest_shapes.append(shard.crystal.global_transform)
	var same_shapes:bool = host_shapes.size() == 4 and guest_shapes.size() == 4
	if same_shapes:
		for i:int in range(4): same_shapes = same_shapes and host_shapes[i].is_equal_approx(guest_shapes[i])
	check(same_shapes,"guest shard keeps the authoritative launch-frame crystal pose, not a different item icon")
	for shard:Node in frozen_shards: shard.queue_free()
	host_unit.crystals_out = true
	check(await until(func(): return guest_unit.crystals_out and not guest_unit._native_model.crystal_layer.visible,2.0),"amethyst volley removes guest crystal hit regions and 3D geometry")
	host_unit.set_block(CUBE.Block.TNT)
	var primed:bool = await until(func(): return guest_unit.block_mode == CUBE.Block.TNT and absf(guest_unit.fuse_left-CUBE.TNT_FUSE_SECONDS) < 0.12)
	check(primed and guest_unit._native_model.block_mode == CUBE.Block.TNT,"network replicates the guest's internal 3D TNT block and fuse seconds")
	check(await until(func(): return sulfur_sound_count("fuse") >= 2,2.0),"native Minecraft fuse sample plays on host and guest via RPC")
	host_unit.fuse_left = 1.4
	check(await until(func(): return absf(guest_unit.fuse_left-1.4) < 0.12),"ongoing countdown synchronizes to guest")
	check(await until(func(): return is_instance_valid(guest_unit._charge_circle) and absf(guest_unit._charge_circle.progress-(1.0-1.4/CUBE.TNT_FUSE_SECONDS)) < 0.05),"guest charge disk uses the replicated fuse rather than an independent timer")
	var target:Node2D = load("res://scenes/ball.tscn").instantiate()
	target.Team = "Team1"
	world.add_child(target,true)
	target.global_position = center+Vector2(26,0)
	target.Max_health = 2000
	target.default_properties.Max_health = 2000
	target.health = 2000
	target.state_machine.set_physics_process(false)
	target.set_physics_process(false)
	await physics_frame
	var before:float = target.health
	guest_unit._detonate()
	check(target.health == before and guest_unit.block_mode == CUBE.Block.TNT,"guest cannot produce blast damage or alter authoritative TNT")
	var self_before:float = host_unit.health
	host_unit.fuse_left = 0.0
	host_unit._detonate()
	check(target.health < before and target.health >= before-CUBE.TNT_DAMAGE-1.0,"host applies blast damage exactly once")
	check(host_unit.health < self_before,"TNT damages its host caster once")
	var ejected:bool = await until(func(): return guest_unit.block_mode == host_unit.block_mode and guest_unit.block_mode != CUBE.Block.TNT and guest_unit.block_mode != CUBE.Block.EMPTY and guest_unit.fuse_left == 0.0)
	check(ejected,"random post-blast block and fuse reset reach the guest")
	check(not is_instance_valid(guest_unit._charge_circle),"guest removes the charge indicator on the replicated post-blast block")
	check(await until(func(): return sulfur_sound_count("explosion") >= 2,2.0),"native Minecraft explosion sample plays on both ENet peers")
	check(await until(func(): return sulfur_sound_count("entity.player.attack.crit") >= 2,2.0),"actual-damage critical plays its original Minecraft sample on both peers")
	var fx_count:int = 0
	for transient:Node in get_nodes_in_group("MCExplosion"):
		if transient.is_inside_tree(): fx_count += 1
	check(fx_count == 2,"authority and replica each render the shared blast once, without duplicate damage")
	finish(0 if failures == 0 else 1)

func finish(code:int) -> void:
	if done: return
	# Despawn the networked actor while both APIs are still active. Detaching the
	# peers before destroying its two synchronizers produces engine-level reset
	# errors even when replication and damage have passed every assertion.
	if is_instance_valid(host_root) and host_root.has_node("NetworkSulfurCube"):
		host_root.get_node("NetworkSulfurCube").queue_free()
		var deadline:int = Time.get_ticks_msec()+1800
		while is_instance_valid(guest_root) and guest_root.has_node("NetworkSulfurCube") and Time.get_ticks_msec() < deadline:
			await process_frame
		await process_frame
		if code == 0:
			check(not guest_root.has_node("NetworkSulfurCube"),"authoritative despawn removes the replica before the network is torn down")
	done = true
	print("MC_SULFUR_NETWORK: %d checks / %d failures" % [checks,failures])
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
