extends SceneTree
class EntryArena extends Node2D:
	func _animate_ball_back_inside_map(actor:Node2D,target:Vector2,seconds:float,_raise:bool=true) -> void:
		actor.set_meta("map_rescue_animating",true)
		var tween:Tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		tween.tween_property(actor,"global_position",target,seconds)
		tween.finished.connect(func():
			if is_instance_valid(actor): actor.remove_meta("map_rescue_animating"))
var checks:int = 0
var failures:int = 0
var host_root:Node2D
var guest_root:Node2D
var game:Node
var finished:bool = false
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: "+label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func scope(label:String) -> Node2D:
	var view := SubViewport.new()
	view.name = label
	view.size = Vector2i(400,300)
	view.world_2d = World2D.new()
	root.add_child(view)
	var parent := EntryArena.new()
	parent.name = "Arena"
	view.add_child(parent)
	var spawner := MultiplayerSpawner.new()
	spawner.name = "Spawner"
	spawner.spawn_path = NodePath("..")
	for path:String in ["res://scenes/characters/我的世界/僵尸.tscn","res://scenes/characters/我的世界/僵尸王.tscn","res://scenes/creatures/僵尸粘液球.tscn","res://scenes/ball.tscn"]:
		spawner.add_spawnable_scene(path)
	parent.add_child(spawner)
	return parent
func until(condition:Callable) -> bool:
	var end:int = Time.get_ticks_msec()+5000
	while Time.get_ticks_msec() < end:
		if condition.call(): return true
		await process_frame
	return false
func freeze(id:int) -> void:
	if not is_instance_id_valid(id): return
	var node:Node = instance_from_id(id)
	if node.get("state_machine") is Node: node.get("state_machine").set_physics_process(false)
	if node.is_in_group("MCZombieSlimeBall"): node.set_physics_process(false)
func add_actor(path:String,label:String,point:Vector2,team:String) -> Node2D:
	var node:Node2D = load(path).instantiate()
	node.name = label
	node.Team = team
	node.position = point
	node.Has_Collision_Damage = false
	host_root.add_child(node)
	node.state_machine.set_physics_process(false)
	return node
func run() -> void:
	game = root.get_node("Game")
	game._settings_storage_path = "user://zombie_network_settings.cfg"
	game.now_stop_state = false
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Have_Team_Damage = false
	AudioServer.set_bus_mute(0,true)
	create_timer(30.0).timeout.connect(func():
		if not finished: quit(2))
	host_root = scope("Host")
	guest_root = scope("Guest")
	var scene := Node.new()
	root.add_child(scene)
	current_scene = scene
	var host_api := SceneMultiplayer.new()
	var guest_api := SceneMultiplayer.new()
	set_multiplayer(host_api,host_root.get_path())
	set_multiplayer(guest_api,guest_root.get_path())
	var host_peer := ENetMultiplayerPeer.new()
	host_peer.set_bind_ip("127.0.0.1")
	check(host_peer.create_server(0,1)==OK,"opens a real ENet host")
	host_api.multiplayer_peer = host_peer
	var guest_peer := ENetMultiplayerPeer.new()
	check(guest_peer.create_client("127.0.0.1",host_peer.get_host().get_local_port())==OK,"opens independent ENet client")
	guest_api.multiplayer_peer = guest_peer
	check(await until(func():return host_api.get_peers().size()==1 and guest_peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED),"transport handshake completes")
	node_added.connect(func(node:Node): freeze.call_deferred(node.get_instance_id()))
	var king:Node2D = add_actor("res://scenes/characters/我的世界/僵尸王.tscn","King",Vector2(100,150),"A")
	var zombie:Node2D = add_actor("res://scenes/characters/我的世界/僵尸.tscn","Zombie",Vector2(250,150),"A")
	var target:Node2D = add_actor("res://scenes/ball.tscn","Target",Vector2(273,150),"B")
	check(await until(func():return guest_root.has_node("King/NativeVoice") and guest_root.has_node("Zombie") and guest_root.has_node("Target")),"actual MultiplayerSpawner creates both character replicas")
	var replica:Node2D = guest_root.get_node("King")
	var remote_zombie:Node2D = guest_root.get_node("Zombie")
	check(not replica.is_multiplayer_authority() and king.is_multiplayer_authority(),"client cannot own gameplay authority")
	king.summon_cooldown = 0.0
	check(king.summon_zombies()==2,"host summons exactly two zombies")
	check(await until(func():
		var count:int = 0
		for node:Node in guest_root.get_children():
			if node.is_in_group("MinecraftZombie") and node.name not in ["King","Zombie"]: count += 1
		return count == 2),"both summons replicate through shared spawner")
	var host_child:Node2D = king.living_summons()[0]
	var remote_child:Node2D = guest_root.get_node(NodePath(str(host_child.name)))
	check(await until(func():return is_instance_valid(remote_child._entry_clip) and remote_child._entry_clip.active),"wall clip and emergence phase replicate to the client")
	check(remote_child.entry_face == host_child.entry_face and remote_child.entry_normal == host_child.entry_normal,"entry wall plane is identical on both peers")
	check(not remote_child.can_act(),"replica cannot attack during wall entry")
	check(await until(func():return host_child.entry_left == 0.0 and remote_child.entry_left == 0.0),"entry completion replicates without leaving the client stuck")
	replica.summon_cooldown = 0.0
	check(replica.summon_zombies()==0,"client cannot mint extra summons")
	zombie.bite_cooldown = 0.0
	check(zombie.begin_bite(target),"host starts close-range bite")
	check(await until(func():return is_instance_valid(remote_zombie._bite_fx)),"bite animation crosses real reliable RPC")
	check(remote_zombie._bite_fx.global_position == zombie.bite_point,"bite replica keeps authoritative fixed location")
	check(not remote_zombie.begin_bite(guest_root.get_node("Target")),"replica cannot independently start damaging bite")
	king.throw_cooldown = 0.0
	king.throw_slime(Vector2(280,140))
	var name:String = str(king.name)+"_Slime_"+str(king._shot_serial)
	check(await until(func():return guest_root.has_node(NodePath(name))),"slime is replicated as a real projectile scene")
	var shot:Node2D = host_root.get_node(NodePath(name))
	var remote_shot:Node2D = guest_root.get_node(NodePath(name))
	shot.set_physics_process(false)
	remote_shot.set_physics_process(false)
	check(remote_shot.get_projectile_source()==replica,"projectile resolves owner within its own peer battlefield")
	check(remote_shot._to == shot._to and remote_shot._arc == shot._arc,"spawn packet preserves complete parabolic flight")
	var before:float = target.health
	remote_shot._physics_process(0.2)
	check(target.health == before,"client advances visual flight without dealing damage")
	var copier:Script = load("res://scripts/effects/我的世界/mc_enchant_projectiles.gd")
	var clone:Node2D = copier.spawn_from(shot,copier.snapshot(shot))
	clone.set_physics_process(false)
	var clone_name:String = str(clone.name)
	check(await until(func():return guest_root.has_node(NodePath(clone_name))),"shared multishot clone also replicates as a scene")
	shot.set_projectile_velocity(Vector2(-170,10))
	check(await until(func():return remote_shot._redirected and remote_shot._motion == Vector2(-170,10)),"deflected velocity synchronizes rather than continuing old arc")
	shot.retire()
	check(await until(func():return not guest_root.has_node(NodePath(name))),"authority retirement removes replicated projectile")
	king.queue_free()
	check(await until(func():return not guest_root.has_node("King")),"king removal replicates")
	var living:int = 0
	for node:Node in guest_root.get_children():
		if node.is_in_group("MinecraftZombie") and node.name != "Zombie": living += 1
	check(living==2,"replicated summons survive their king")
	for child:Node in host_root.get_children():
		if not child is MultiplayerSpawner: child.queue_free()
	await create_timer(0.15).timeout
	set_multiplayer(null,host_root.get_path())
	set_multiplayer(null,guest_root.get_path())
	host_peer.close()
	guest_peer.close()
	host_root.get_parent().queue_free()
	guest_root.get_parent().queue_free()
	scene.queue_free()
	await process_frame
	finished = true
	print("ZOMBIE_NETWORK_RESULT checks=",checks," failures=",failures)
	quit(1 if failures else 0)
