extends SceneTree
var draw_start:int
var phase:String = "warm"
func pre_draw() -> void: draw_start = Time.get_ticks_usec()
func post_draw() -> void:
	var ms:float = (Time.get_ticks_usec()-draw_start)/1000.0
	if ms>25.0: print("DRAW_STALL ",phase," ",ms)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	RenderingServer.frame_pre_draw.connect(pre_draw)
	RenderingServer.frame_post_draw.connect(post_draw)
	var game:Node = root.get_node("Game")
	game.now_stop_state = false
	game.Game_Settings.Training_Mode = false
	AudioServer.set_bus_mute(0,true)
	var world:Node2D = Node2D.new()
	root.add_child(world)
	current_scene = world
	if "--warm" in OS.get_cmdline_user_args():
		var warmer:Node = load("res://scripts/effects/我的世界/mc_native_prewarm.gd").new()
		world.add_child(warmer)
		var begin:int = Time.get_ticks_usec()
		var previous:int = begin
		var gaps:Array[float] = []
		while warmer.finished.size()+warmer.failed.size()<warmer.CHARACTERS.size():
			await process_frame
			var now:int = Time.get_ticks_usec()
			gaps.append((now-previous)/1000.0)
			previous = now
			if now-begin>60000000:
				print("WARM_TIMEOUT ",warmer.finished," ",warmer.failed)
				quit(1)
				return
		gaps.sort()
		print("WARM_PROFILE total_ms=",(Time.get_ticks_usec()-begin)/1000.0," frames=",gaps.size()," p95_ms=",gaps[int(gaps.size()*0.95)]," max_ms=",gaps.back()," failures=",warmer.failed)
	for pass_index:int in range(2):
		for name:String in ["骷髅","女巫","烈焰人","苦力怕","蠹虫","末影人","唤魔者","潜影贝"]:
			phase = str(pass_index)+name
			var started:int = Time.get_ticks_usec()
			var scene:PackedScene = load("res://scenes/characters/我的世界/"+name+".tscn")
			var loaded:int = Time.get_ticks_usec()
			var unit:Node2D = scene.instantiate()
			unit.Team = "Team0"
			var instanced:int = Time.get_ticks_usec()
			world.add_child(unit)
			unit.state_machine.set_physics_process(false)
			var entered:int = Time.get_ticks_usec()
			await process_frame
			await process_frame
			var settled:int = Time.get_ticks_usec()
			print("COLD_PROFILE ",pass_index," ",name," load_ms=",(loaded-started)/1000.0," instance_ms=",(instanced-loaded)/1000.0," ready_ms=",(entered-instanced)/1000.0," deferred_ms=",(settled-entered)/1000.0," process_ms=",Performance.get_monitor(Performance.TIME_PROCESS)*1000.0," physics_ms=",Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
			unit.queue_free()
			await process_frame
	world.queue_free()
	await process_frame
	await process_frame
	quit()
