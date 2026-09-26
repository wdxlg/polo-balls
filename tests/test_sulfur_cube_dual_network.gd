extends "res://tests/test_sulfur_cube_redesign_network.gd"
## Reuse the existing real ENet/spawner helpers and teardown, adding two-slot contracts.
func empty_frames_visible(unit:Node) -> bool:
	for slot:Node2D in unit._block_frames.get_children():
		var icon:Sprite2D = slot.get_node("BlockIcon") as Sprite2D
		if not slot.is_visible_in_tree() or not slot.get_node("Frame").visible or icon.visible or icon.texture != null: return false
	return unit._block_frames.get_child_count() == 2
func run() -> void:
	create_timer(65.0,true,false,true).timeout.connect(func(): print("SULFUR_DUAL_NETWORK_TIMEOUT"); finish(2))
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
	host_root.name = "SulfurDualHost"
	guest_root = Node2D.new()
	guest_root.name = "SulfurDualGuest"
	world.add_child(host_root)
	world.add_child(guest_root)
	host_api = SceneMultiplayer.new()
	guest_api = SceneMultiplayer.new()
	set_multiplayer(host_api,host_root.get_path())
	set_multiplayer(guest_api,guest_root.get_path())
	host_peer = ENetMultiplayerPeer.new()
	host_peer.set_bind_ip("127.0.0.1")
	var err:Error = host_peer.create_server(0,1)
	check(err == OK,"dual-slot local authoritative peer starts")
	if err != OK: finish(1); return
	host_api.multiplayer_peer = host_peer
	guest_peer = ENetMultiplayerPeer.new()
	err = guest_peer.create_client("127.0.0.1",host_peer.get_host().get_local_port())
	check(err == OK,"dual-slot independent guest connects")
	if err != OK: finish(1); return
	guest_api.multiplayer_peer = guest_peer
	spawner(host_root)
	spawner(guest_root)
	check(await until(func(): return host_api.get_peers().size() == 1 and guest_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED),"dual-slot real ENet handshake completes")
	var center:Vector2 = world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	var host_unit:Node2D = load(SCENE_PATH).instantiate()
	host_unit.name = "NetworkSulfurCube"
	host_unit.Team = "Team0"
	host_unit.position = center
	host_unit.first_block_delay = 99.0
	host_root.add_child(host_unit,true)
	host_unit.state_machine.set_physics_process(false)
	host_unit.set_physics_process(false)
	check(await until(func(): return guest_root.has_node("NetworkSulfurCube")),"dual-slot scene is created by the real MultiplayerSpawner")
	if not guest_root.has_node("NetworkSulfurCube"): finish(1); return
	var guest_unit:Node2D = guest_root.get_node("NetworkSulfurCube")
	guest_unit.state_machine.set_physics_process(false)
	guest_unit.set_physics_process(false)
	check(guest_unit.block_slots.is_empty() and empty_frames_visible(guest_unit),"guest initially sees BOTH empty frames before receiving any block")
	host_unit.acquire_block(CUBE.Block.ICE)
	check(await until(func(): return guest_unit.block_slots == PackedInt32Array([CUBE.Block.ICE])),"one-slot snapshot replicates atomically")
	check(guest_unit._block_frames.get_child(0).get_node("BlockIcon").visible and guest_unit._block_frames.get_child(1).is_visible_in_tree() and not guest_unit._block_frames.get_child(1).get_node("BlockIcon").visible,"guest fills LEFT first without hiding the RIGHT empty frame")
	host_unit.acquire_block(CUBE.Block.MAGMA)
	check(await until(func(): return guest_unit.block_slots == host_unit.block_slots and guest_unit.block_slots.size() == 2),"both traits replicate together, not as racing previous/latest fields")
	check(guest_unit.has_block(CUBE.Block.ICE) and guest_unit.get_fire_effect_ratio() == 0.0 and guest_unit._native_model.block_mode == CUBE.Block.MAGMA,"guest retains old ice capability and sees only newer magma inside")
	check(guest_unit._block_frames.get_child(0).get_meta("block_mode") == CUBE.Block.ICE and guest_unit._block_frames.get_child(1).get_meta("block_mode") == CUBE.Block.MAGMA,"guest shows the same left/right original-material icon order")
	var snapshot:PackedInt32Array = guest_unit.block_slots.duplicate()
	check(not guest_unit.acquire_block(CUBE.Block.IRON) and guest_unit.block_slots == snapshot and host_unit.block_slots == snapshot,"non-authoritative acquisition cannot change either peer's inventory")
	host_unit.acquire_block(CUBE.Block.HONEY)
	check(await until(func(): return guest_unit.block_slots == PackedInt32Array([CUBE.Block.MAGMA,CUBE.Block.HONEY])),"FIFO shift and eviction reach the remote renderer")
	check(not guest_unit.has_block(CUBE.Block.ICE) and guest_unit._native_model.block_mode == CUBE.Block.HONEY,"guest loses only evicted ice and keeps latest-only inner mesh")

	# Sticky contact remains when honey moves to the older slot, clears on eviction.
	var host_victim:Node2D = load("res://scenes/ball.tscn").instantiate()
	host_victim.name = "DualHoneyVictim"
	host_victim.Team = "Team1"
	host_root.add_child(host_victim)
	host_victim.state_machine.set_physics_process(false)
	host_victim.set_physics_process(false)
	host_victim.global_position = center+Vector2(5,0)
	var guest_victim:Node2D = load("res://scenes/ball.tscn").instantiate()
	guest_victim.name = "DualHoneyVictim"
	guest_victim.Team = "Team1"
	guest_root.add_child(guest_victim)
	guest_victim.state_machine.set_physics_process(false)
	guest_victim.set_physics_process(false)
	guest_victim.global_position = center+Vector2(600,0)
	host_unit._pull_touching_enemies(0.1)
	check(await until(func(): return guest_unit.get_collision_exceptions().has(guest_victim)),"guest receives matching target collision lease")
	host_unit.acquire_block(CUBE.Block.IRON)
	check(await until(func(): return guest_unit.block_slots == PackedInt32Array([CUBE.Block.HONEY,CUBE.Block.IRON]) and guest_unit.get_collision_exceptions().has(guest_victim)),"moving honey left does not clear its replicated pair lease")
	host_unit.acquire_block(CUBE.Block.ICE)
	check(await until(func(): return not guest_unit.has_block(CUBE.Block.HONEY) and not guest_unit.get_collision_exceptions().has(guest_victim)),"eviction clears the remote honey collision lease")
	host_victim.queue_free()
	guest_victim.queue_free()

	# Retained crystalline geometry stays outside the latest, different internal block.
	host_unit.set_block(CUBE.Block.AMETHYST)
	host_unit.acquire_block(CUBE.Block.IRON)
	check(await until(func(): return guest_unit.block_slots == host_unit.block_slots and guest_unit.crystal_layout == host_unit.crystal_layout and guest_unit._native_model.crystals_ready()),"two-slot amethyst + iron replicates random crystal layout and independent growth")
	check(guest_unit._native_model.block_mode == CUBE.Block.IRON and guest_unit._native_model.crystal_layer.visible,"guest shows iron inside while retained amethyst protrusions remain visible")
	check(guest_unit.player_control_action_ids().size() == 4,"remote manual action inventory retains slam/change/volley/surge")
	var before_layout:PackedVector3Array = guest_unit.crystal_layout.duplicate()
	guest_unit._roll_crystal_layout()
	guest_unit.controlled_crystal_volley()
	check(guest_unit.crystal_layout == before_layout and not guest_unit.crystals_out,"guest cannot reroll or fire retained crystal gameplay")
	var late_host:Node2D = load(SCENE_PATH).instantiate()
	late_host.name = "TwoBlockLateSpawn"
	late_host.Team = "Team0"
	late_host.position = center+Vector2(100,0)
	late_host.block_slots = PackedInt32Array([CUBE.Block.IRON,CUBE.Block.AMETHYST])
	late_host.crystal_layout = host_unit.crystal_layout.duplicate()
	host_root.add_child(late_host)
	late_host.state_machine.set_physics_process(false)
	late_host.set_physics_process(false)
	check(await until(func(): return guest_root.has_node("TwoBlockLateSpawn") and guest_root.get_node("TwoBlockLateSpawn").block_slots == late_host.block_slots),"spawn snapshot carries both already-acquired blocks")
	var late_guest:Node = guest_root.get_node_or_null("TwoBlockLateSpawn")
	check(is_instance_valid(late_guest) and late_guest._block_frames.get_child(0).visible and late_guest._block_frames.get_child(1).visible and late_guest._native_model.block_mode == CUBE.Block.AMETHYST,"late-spawn replica builds both frames and newest-only body")
	check(late_host.is_external_directional_gravity_locomotion_enabled(),"authority initializes retained iron gravity even from a pre-populated spawn snapshot")
	late_host.queue_free()
	check(await until(func(): return not guest_root.has_node("TwoBlockLateSpawn")),"late-spawned dual inventory despawns without orphan UI")
	host_unit.acquire_block(CUBE.Block.ICE)
	check(await until(func(): return guest_unit.block_slots == host_unit.block_slots and not guest_unit._native_model.crystal_layer.visible),"amethyst eviction removes the remote external crystal layer")

	# TNT consumes once without deleting its companion, and the exception is replicated.
	host_unit.set_block(CUBE.Block.TNT)
	host_unit.acquire_block(CUBE.Block.IRON)
	host_unit.fuse_left = 0.8
	check(await until(func(): return guest_unit.block_slots == PackedInt32Array([CUBE.Block.TNT,CUBE.Block.IRON]) and absf(guest_unit.fuse_left-0.8) < 0.1),"older TNT fuse and newer iron state synchronize together")
	check(await until(func(): return is_instance_valid(guest_unit._charge_circle)),"old retained TNT still has a real guest charge display")
	var before_hp:float = host_unit.health
	guest_unit._detonate()
	check(host_unit.health == before_hp and guest_unit.has_block(CUBE.Block.TNT),"guest cannot explode or consume the authoritative TNT")
	host_unit.fuse_left = 0.0
	host_unit._detonate()
	check(before_hp-host_unit.health == 30.0,"host explosion happens once and respects its other block's iron mitigation")
	check(await until(func(): return guest_unit.block_slots == host_unit.block_slots and not guest_unit.has_block(CUBE.Block.TNT) and guest_unit.fuse_left == 0.0),"consumed TNT disappears on both peers while the companion is kept")
	check(guest_unit.block_slots.size() == 2 and guest_unit.block_slots[0] == CUBE.Block.IRON and guest_unit._native_model.block_mode == guest_unit.block_slots[1],"guest keeps iron left and displays replacement right/inside")
	check(not is_instance_valid(guest_unit._charge_circle),"guest has no stale charge disk after TNT consumption")
	check(await until(func(): return get_nodes_in_group("MCExplosion").size() == 2),"one explosion effect per peer, not one per slot or a re-primed old TNT")
	host_unit.set_block(CUBE.Block.EMPTY)
	check(await until(func(): return guest_unit.block_slots.is_empty()),"empty inventory snapshot reaches the guest")
	check(empty_frames_visible(host_unit) and empty_frames_visible(guest_unit),"both peers clear stale icons but keep BOTH empty frame backgrounds")
	print("SULFUR_DUAL_NETWORK: scoped two-peer checks completed")
	finish(0 if failures == 0 else 1)
