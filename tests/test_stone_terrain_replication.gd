extends SceneTree
## Two real local ENet peers and native MultiplayerSpawner/Synchronizer, no character facade.
const STONE_PATH:String = "res://scenes/characters/默认/石头.tscn"
var checks:int = 0
var failures:int = 0
var done:bool = false
var server_root:Node2D
var client_root:Node2D
var server_api:SceneMultiplayer
var client_api:SceneMultiplayer
var server_peer:ENetMultiplayerPeer
var client_peer:ENetMultiplayerPeer

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ",label)

func until(condition:Callable,seconds:float = 3.0) -> bool:
	var deadline:int = Time.get_ticks_msec()+int(seconds*1000.0)
	while Time.get_ticks_msec()<deadline and not done:
		if condition.call(): return true
		await process_frame
	return false

func spawner(parent:Node) -> MultiplayerSpawner:
	var node:=MultiplayerSpawner.new()
	node.name = "TerrainSpawner"
	node.spawn_path = NodePath("..")
	node.add_spawnable_scene(STONE_PATH)
	parent.add_child(node)
	return node

func run() -> void:
	create_timer(18.0).timeout.connect(func(): finish(2))
	server_root = Node2D.new()
	server_root.name = "StoneNetServer"
	client_root = Node2D.new()
	client_root.name = "StoneNetClient"
	root.add_child(server_root)
	root.add_child(client_root)
	server_api = SceneMultiplayer.new()
	client_api = SceneMultiplayer.new()
	set_multiplayer(server_api,server_root.get_path())
	set_multiplayer(client_api,client_root.get_path())
	server_peer = ENetMultiplayerPeer.new()
	server_peer.set_bind_ip("127.0.0.1")
	var error:Error = server_peer.create_server(0,1)
	check(error==OK,"loopback terrain replication server starts")
	if error!=OK: finish(1); return
	server_api.multiplayer_peer = server_peer
	client_peer = ENetMultiplayerPeer.new()
	error = client_peer.create_client("127.0.0.1",server_peer.get_host().get_local_port())
	check(error==OK,"independent client connects through ENet")
	if error!=OK: finish(1); return
	client_api.multiplayer_peer = client_peer
	spawner(server_root)
	spawner(client_root)
	var connected:bool = await until(func(): return client_peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED and server_api.get_peers().size()==1)
	check(connected,"both real multiplayer peers finish their connection handshake")
	if not connected: finish(1); return
	var stone:Node2D = load(STONE_PATH).instantiate()
	stone.name = "NetworkStone"
	stone.position = Vector2(75,96)
	stone.scale = Vector2(1.25,1.25)
	server_root.add_child(stone,true)
	var appeared:bool = await until(func(): return client_root.has_node("NetworkStone"))
	check(appeared,"server placement automatically spawns the same scene on the client")
	if not appeared: finish(1); return
	var replica:Node2D = client_root.get_node("NetworkStone")
	check(replica is StaticBody2D and not replica is CharacterBody2D and replica.is_in_group("PlaceableObstacle") and not replica.is_in_group("Ball"),"remote replica is genuine editable static terrain, never a character")
	check(replica.position.is_equal_approx(stone.position) and replica.scale.is_equal_approx(stone.scale),"initial position and scale survive native spawn replication")
	check(replica.collision_layer==1 and replica.collision_mask==2 and replica.get_node_or_null("hurtbox")==null and not replica.has_method("take_damage"),"replication does not recreate character hitboxes, health or entity collision layers")
	stone.position = Vector2(126,173)
	stone.scale = Vector2(1.5,1.5)
	stone.rotation = 0.2
	var updated:bool = await until(func(): return replica.position.is_equal_approx(stone.position) and replica.scale.is_equal_approx(stone.scale) and is_equal_approx(replica.rotation,stone.rotation))
	check(updated,"terrain placement transforms continue to synchronize after spawn")
	stone.queue_free()
	var removed:bool = await until(func(): return not client_root.has_node("NetworkStone"))
	check(removed,"server removal automatically despawns client terrain")
	finish(0 if failures==0 else 1)

func finish(code:int) -> void:
	if done: return
	done = true
	print("STONE_TERRAIN_REPLICATION checks=",checks," failures=",failures," exit=",code)
	if server_api!=null: server_api.multiplayer_peer = null
	if client_api!=null: client_api.multiplayer_peer = null
	if server_peer!=null: server_peer.close()
	if client_peer!=null: client_peer.close()
	if is_instance_valid(server_root):
		set_multiplayer(null,server_root.get_path())
		server_root.queue_free()
	if is_instance_valid(client_root):
		set_multiplayer(null,client_root.get_path())
		client_root.queue_free()
	await process_frame
	quit(code)
