extends SceneTree
## 单机（OfflineMultiplayerPeer）下 .rpc() 与直接调用的开销对比，以及音效播放各环节耗时。
var world:Node
var probe:Node
func _initialize() -> void: call_deferred("run")
func _us(t0:int,n:int) -> String: return "%.1f us" % (float(Time.get_ticks_usec()-t0)/float(n))
func run() -> void:
	var game:Node = root.get_node("Game")
	var audios:Node = root.get_node("Audios")
	game.Game_Settings["Training_Mode"] = false
	game.now_stop_state = false
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.visible = false
	await create_timer(0.5).timeout
	probe = load("res://tests/micro_rpc_probe_node.gd").new()
	world.add_child(probe)
	print("has_multiplayer_peer=",root.multiplayer.has_multiplayer_peer()," peer=",root.multiplayer.multiplayer_peer)
	var N:int = 2000
	var t0:int = Time.get_ticks_usec()
	for i in range(N): probe.noop("KnifeThrow1",{},true)
	print("direct noop(String,Dictionary,bool): ",_us(t0,N))
	t0 = Time.get_ticks_usec()
	for i in range(N): probe.noop.rpc("KnifeThrow1",{},true)
	print("noop.rpc(String,Dictionary,bool): ",_us(t0,N))
	t0 = Time.get_ticks_usec()
	for i in range(N): probe.noop.rpc("KnifeThrow1",{volume=-3.0},true)
	print("noop.rpc(String,{volume},bool): ",_us(t0,N))
	t0 = Time.get_ticks_usec()
	for i in range(N): probe.noop_vec.rpc(Vector2(1,2),3)
	print("noop_vec.rpc(Vector2,int): ",_us(t0,N))
	t0 = Time.get_ticks_usec()
	for i in range(N): probe.noop_vec_unreliable.rpc(Vector2(1,2),3)
	print("noop_vec_unreliable.rpc(Vector2,int): ",_us(t0,N))
	t0 = Time.get_ticks_usec()
	for i in range(N): probe.rpc("noop_vec",Vector2(1,2),3)
	print("Node.rpc(name,...): ",_us(t0,N))
	var sfx:Node = audios.Sfx
	var player:AudioStreamPlayer = sfx.get_node("KnifeThrow1")
	print("KnifeThrow1 stream=",player.stream.get_class()," polyphony=",player.max_polyphony)
	N = 300
	t0 = Time.get_ticks_usec()
	for i in range(N): player.play()
	print("AudioStreamPlayer.play() KnifeThrow1 (restart same player): ",_us(t0,N))
	t0 = Time.get_ticks_usec()
	for i in range(N): audios.play_sfx("KnifeThrow1",{},true)
	print("Audios.play_sfx(KnifeThrow1) direct: ",_us(t0,N))
	t0 = Time.get_ticks_usec()
	for i in range(N): audios.play_sfx.rpc("KnifeThrow1",{},true)
	print("Audios.play_sfx.rpc(KnifeThrow1): ",_us(t0,N))
	var hit:AudioStreamPlayer = sfx.get_node("balls_hit1")
	print("balls_hit1 stream=",hit.stream.get_class()," polyphony=",hit.max_polyphony)
	t0 = Time.get_ticks_usec()
	for i in range(N): audios.play_sfx("balls_hit1",{volume=-5.0},true)
	print("Audios.play_sfx(balls_hit1) direct: ",_us(t0,N))
	t0 = Time.get_ticks_usec()
	for i in range(N): audios.play_sfx.rpc("balls_hit1",{volume=-5.0},true)
	print("Audios.play_sfx.rpc(balls_hit1): ",_us(t0,N))
	t0 = Time.get_ticks_usec()
	for i in range(N): audios.play_sfx("balls_collide1",{},true)
	print("Audios.play_sfx(balls_collide1) direct: ",_us(t0,N))
	var total:int = 0
	for i in range(30):
		await process_frame
		var t1:int = Time.get_ticks_usec()
		for j in range(5): audios.play_sfx.rpc("balls_hit1",{volume=-5.0},true)
		total += Time.get_ticks_usec()-t1
	print("play_sfx.rpc(balls_hit1) 5/frame over 30 frames: %.1f us each" % (float(total)/150.0))
	total = 0
	for i in range(30):
		await process_frame
		var t1:int = Time.get_ticks_usec()
		for j in range(5): audios.play_sfx.rpc("KnifeThrow1",{},true)
		total += Time.get_ticks_usec()-t1
	print("play_sfx.rpc(KnifeThrow1) 5/frame over 30 frames: %.1f us each" % (float(total)/150.0))
	quit()
