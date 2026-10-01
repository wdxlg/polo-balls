extends "res://tests/test_evoker_totem_wave.gd"
var host_root:Node2D
var guest_root:Node2D
func scope(label:String) -> Node2D:
	var view:=SubViewport.new()
	view.name = label
	view.size = Vector2i(400,300)
	view.world_2d = World2D.new()
	root.add_child(view)
	var parent:=Node2D.new()
	parent.name = "Arena"
	view.add_child(parent)
	return parent
func until(condition:Callable) -> bool:
	var end:int = Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<end:
		if condition.call(): return true
		await process_frame
	return false
func run() -> void:
	begin()
	host_root = scope("Host")
	guest_root = scope("Guest")
	var host_api:=SceneMultiplayer.new()
	var guest_api:=SceneMultiplayer.new()
	set_multiplayer(host_api,host_root.get_path())
	set_multiplayer(guest_api,guest_root.get_path())
	var host_peer:=ENetMultiplayerPeer.new()
	host_peer.set_bind_ip("127.0.0.1")
	check(host_peer.create_server(0,1)==OK,"authority opens real ephemeral ENet transport")
	host_api.multiplayer_peer = host_peer
	var guest_peer:=ENetMultiplayerPeer.new()
	check(guest_peer.create_client("127.0.0.1",host_peer.get_host().get_local_port())==OK,"replica uses independent real ENet client")
	guest_api.multiplayer_peer = guest_peer
	var source:Node2D = unit("唤魔者",Vector2(25,10),"Team0",host_root,"Caster")
	var replica:Node2D = unit("唤魔者",Vector2(25,10),"Team0",guest_root,"Caster")
	var enemy:Node2D = unit("",Vector2(115,10),"Team1",host_root,"Target")
	var remote_enemy:Node2D = unit("",Vector2(115,10),"Team1",guest_root,"Target")
	node_added.connect(func(node:Node):
		if node.get_script()==load("res://scripts/effects/我的世界/evoker_totem_wave.gd"): node.set_physics_process(false))
	check(await until(func():return host_api.get_peers().size()==1 and guest_peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED),"real scene-scoped handshake completes")
	check(source.is_multiplayer_authority() and not replica.is_multiplayer_authority(),"only host owns lethal prevention and damage")
	check(source.get_world_2d()!=replica.get_world_2d(),"replicas live in independent physics worlds")
	check(not is_instance_valid(replica._totem_wave),"client has no wave before true host trigger")
	var wave:Node2D = release(source)
	check(await until(func():return is_instance_valid(replica._totem_wave)),"real lethal trigger delivers authority RPC to client")
	var remote_wave:Node2D = replica._totem_wave
	check(wave.get_world_2d()==source.get_world_2d() and remote_wave.get_world_2d()==replica.get_world_2d(),"both effects stay in their own battlefield")
	check(remote_wave.global_position==Vector2(25,10) and remote_wave.max_radius==160 and is_equal_approx(remote_wave.duration,0.6),"reliable packet preserves trigger origin, reach and duration")
	remote_wave.advance(0.4)
	check(remote_enemy.health==500 and enemy.health==500 and push_of(remote_enemy)==null,"client advances visuals without any local damage or knockback")
	check(remote_wave.threats(remote_enemy).is_empty(),"replica cannot advertise locally damaging wave")
	wave.advance(0.4)
	check(enemy.health==492 and remote_enemy.health==500,"host hits once without cross-world or duplicate client hit")
	check(push_of(enemy)!=null and push_of(remote_enemy)==null,"knockback is awarded only by authority")
	check(is_equal_approx(wave.radius,remote_wave.radius) and is_equal_approx(wave.opacity(),remote_wave.opacity()),"same combat age gives matching expanding and fading geometry")
	source._show_totem_wave.rpc(Vector2(999,999),900,9)
	await create_timer(0.12).timeout
	check(replica._totem_wave==remote_wave and remote_wave.global_position==Vector2(25,10) and get_nodes_in_group("MCEvokerTotemWave").size()==2,"duplicate RPC cannot spawn another ring or relocate its center")
	# A client-side lethal write cannot mint a new gameplay effect.
	replica.health = 0
	check(not replica._totem_used and replica._totem_wave==remote_wave,"client lethal write cannot consume a totem or replay the ring")
	wave.advance(0.3)
	remote_wave.advance(0.3)
	await process_frame
	check(not is_instance_valid(wave) and not is_instance_valid(remote_wave),"both peers independently retire the completed effect")
	for parent:Node2D in [host_root,guest_root]:
		for child:Node in parent.get_children(): child.queue_free()
	await process_frame
	await process_frame
	set_multiplayer(null,host_root.get_path())
	set_multiplayer(null,guest_root.get_path())
	host_peer.close()
	guest_peer.close()
	host_root.get_parent().queue_free()
	guest_root.get_parent().queue_free()
	print("TOTEM_WAVE_ENET_RESULT checks=",checks," failures=",failures)
	await finish()
