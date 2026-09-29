extends "res://tests/test_elytra_return_dash_network.gd"
## Retain existing real ENet dash checks, then exercise the stable Wither visual RPC.
var checked_skulls:bool = false

func owned_smoke(source:Node2D) -> Array[Node]:
	var found:Array[Node] = []
	for p:Node in get_nodes_in_group("MCSmokeTrail"):
		if p.get_meta("mc_emitter_id",0)==source.get_instance_id(): found.append(p)
	return found

func wither_at(parent:Node2D) -> Node2D:
	var previous:Node2D = arena
	arena = parent
	var source:Node2D = actor("凋灵",Vector2(0,180))
	source.name = "TrailWither"
	source.summoned = true
	source.set_process(false)
	arena = previous
	return source

func finish() -> void:
	if not checked_skulls and is_instance_valid(host_root) and is_instance_valid(guest_root) and guest_peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED:
		checked_skulls = true
		var source:Node2D = wither_at(host_root)
		var remote:Node2D = wither_at(guest_root)
		var skull:Node2D = source.SKULL.new()
		host_root.add_child(skull)
		skull.configure(source,Vector2.RIGHT)
		skull.global_position = Vector2(50,180)
		skull.set_physics_process(false)
		await process_frame
		var host_hp:int = source.health
		var remote_hp:int = remote.health
		skull._physics_process(0.1)
		check(owned_smoke(source).size()==4,"authority skull produces its own distance-spaced trail once")
		var received:bool = false
		for frame:int in range(30):
			await create_timer(0.02).timeout
			if not owned_smoke(remote).is_empty():
				received = true
				break
			skull._physics_process(1.0/60.0)
		check(received,"real ENet delivers ongoing unreliable skull smoke through Wither without a remote skull node")
		print("SKULL_NET_DETAIL ",source.get_path()," -> ",remote.get_path()," health=",remote.health," active=",remote.is_combat_runtime_active()," particles=",owned_smoke(remote).size())
		check(source.health==host_hp and remote.health==remote_hp,"visual RPC carries no damage settlement")
		var local_copy:Node2D = remote.SKULL.new()
		guest_root.add_child(local_copy)
		local_copy.configure(remote,Vector2.RIGHT)
		local_copy.set_physics_process(false)
		var count:int = owned_smoke(remote).size()
		local_copy._physics_process(0.1)
		check(local_copy.global_position==Vector2.ZERO and owned_smoke(remote).size()==count,"guest projectile cannot move or duplicate its authoritative trail")
		skull.queue_free()
		local_copy.queue_free()
		# Preserve and replicate hit progress while return steering is active.
		var combo:Node2D = host_root.get_node("Flyer1")
		var remote_combo:Node2D = guest_root.get_node("Flyer1")
		combo._begin_flight(3)
		combo._chain_damage_multiplier = combo.base_landing_damage_multiplier*4.0
		combo.global_position = Vector2(400,0)
		combo._glide_velocity = Vector2.RIGHT*600.0
		combo._update_flight(1.0/60.0)
		check(combo._airborne and combo._returning_to_map and combo._chain_level==3,"authority soft return retains ongoing combo")
		check(await until(func():return remote_combo._returning_to_map and remote_combo._airborne and remote_combo._chain_level==3 and is_equal_approx(remote_combo._chain_damage_multiplier,combo._chain_damage_multiplier)),"live chain level and damage multiplier survive return on the remote peer")
	print("SKULL_TRAIL_NETWORK checks=",checks," failures=",failures)
	await super.finish()
