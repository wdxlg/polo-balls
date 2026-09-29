extends "res://tests/test_mc_bat_transform.gd"
func run() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	var center:Vector2 = await setup_world()
	var s:Node2D = spawn("res://scenes/characters/动漫/菜月昴.tscn",center)
	s.state_machine.set_physics_process(false)
	s._timeline.set_physics_process(false)
	for i:int in range(20):
		var u:Node2D = spawn("res://scenes/ball.tscn",center+Vector2((i%5)*25,(i/5)*25),"Team1")
		u.state_machine.set_physics_process(false)
		u.Has_Collision_Damage = false
		u.self_hitbox.monitoring = false
	await process_frame
	# Isolate recorder cost from World background asset imports.
	for node:Node in world.find_children("*","Node",true,false):
		if node.get_script() != null and node.get_script().resource_path.ends_with("mc_native_prewarm.gd"): node.set_process(false)
	var warm:Script = load("res://scripts/effects/我的世界/mc_native_prewarm.gd")
	for role:String in warm.CHARACTERS:
		var path:String = "res://scenes/characters/我的世界/"+role+".tscn"
		var status:int = ResourceLoader.load_threaded_get_status(path)
		if status in [ResourceLoader.THREAD_LOAD_IN_PROGRESS,ResourceLoader.THREAD_LOAD_LOADED]: ResourceLoader.load_threaded_get(path)
	var t:Node = s._timeline
	var samples:Array[int] = []
	var memory:float = Performance.get_monitor(Performance.MEMORY_STATIC)
	var history:Array = []
	for i:int in range(12):
		history.append(t._capture_world_snapshot())
		samples.append(t.last_capture_usec)
	print("SUBARU_21_ACTORS_CAPTURE_USEC ",samples)
	print("SUBARU_12_SNAPSHOTS_MEMORY_BYTES ",Performance.get_monitor(Performance.MEMORY_STATIC)-memory)
	var start:int = Time.get_ticks_usec()
	await t._restore_world_snapshot(history[0])
	print("SUBARU_21_RESTORE_WALL_USEC ",Time.get_ticks_usec()-start," slices ",t.last_restore_slices)
	print("SUBARU_POOL_OBJECTS ",t._capture_codec.objects.size()," SCRIPT_FIELDS ",t._script_names(s).size())
	history.clear()
	finish(0)
