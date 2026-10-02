extends "res://tests/test_zombie_network.gd"
func run() -> void:
	game=root.get_node("Game")
	game._settings_storage_path="user://body_motion_network.cfg"
	game.now_stop_state=false;game.Game_Settings.Training_Mode=false
	AudioServer.set_bus_mute(0,true)
	create_timer(35).timeout.connect(func():quit(2))
	host_root=scope("Host");guest_root=scope("Guest")
	var scene:=Node.new();root.add_child(scene);current_scene=scene
	var host_api:=SceneMultiplayer.new();var guest_api:=SceneMultiplayer.new()
	set_multiplayer(host_api,host_root.get_path());set_multiplayer(guest_api,guest_root.get_path())
	var host_peer:=ENetMultiplayerPeer.new();host_peer.set_bind_ip("127.0.0.1")
	check(host_peer.create_server(0,1)==OK,"real ENet server")
	host_api.multiplayer_peer=host_peer
	var guest_peer:=ENetMultiplayerPeer.new()
	check(guest_peer.create_client("127.0.0.1",host_peer.get_host().get_local_port())==OK,"independent ENet client")
	guest_api.multiplayer_peer=guest_peer
	check(await until(func():return host_api.get_peers().size()==1 and guest_peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED),"transport handshake")
	node_added.connect(func(node:Node):freeze.call_deferred(node.get_instance_id()))
	var a:Node2D=add_actor("res://scenes/ball.tscn","A",Vector2(150,150),"A")
	var b:Node2D=add_actor("res://scenes/ball.tscn","B",Vector2(192,150),"B")
	a.Speed=200;a.direction=Vector2.RIGHT;b.Speed=0;b.direction=Vector2.ZERO
	check(await until(func():return guest_root.has_node("A") and guest_root.has_node("B")),"both actual body scenes replicate")
	var replica:Node2D=guest_root.get_node("B")
	var before:Vector2=b.global_position
	for frame:int in range(25):
		await physics_frame
		a.move(a.Speed,1.0/60.0);b.stand(1.0/60.0)
	check(b.global_position.x>before.x+3,"host resolves a real bilateral body impulse")
	check(await until(func():return replica.global_position.distance_to(b.global_position)<0.4),"replica receives resulting authoritative position")
	var initial:Vector2=replica.global_position
	replica.apply_knockback(Vector2.UP,80,400)
	replica.move(200,1.0/60.0)
	check(replica.global_position==initial and replica.get_body_motion().impulse_velocity().is_zero_approx(),"replica cannot simulate a second knockback")
	check(not replica.dizziness,"replica receives no phantom input lock")
	var effect:Node=b.apply_knockback(Vector2.DOWN,35,140)
	before=b.global_position
	for frame:int in range(24):
		await physics_frame
		b.stand(1.0/60.0)
	check(b.global_position.y>before.y+15 and not b.dizziness,"host impulse remains mobile and really moves body")
	check(await until(func():return replica.global_position.distance_to(b.global_position)<0.4),"ordinary impulse displacement converges on client")
	check(not replica.dizziness and replica.Can_Attack,"network impulse does not block client attacks")
	if is_instance_valid(effect):effect._finish(false)
	for child:Node in host_root.get_children():
		if not child is MultiplayerSpawner:child.queue_free()
	await create_timer(0.15).timeout
	set_multiplayer(null,host_root.get_path());set_multiplayer(null,guest_root.get_path())
	host_peer.close();guest_peer.close()
	host_root.get_parent().queue_free();guest_root.get_parent().queue_free();scene.queue_free();await process_frame
	print("CHARACTER_MOTION_NETWORK checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
