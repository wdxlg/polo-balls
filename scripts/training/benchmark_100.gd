extends SceneTree
## Manual benchmark only. Never loaded by the game's main scene.
## Run: godot --path . --script res://scripts/training/benchmark_100.gd -- --label=baseline
var world:Node
var game:Node
var saved_settings:Dictionary
var saved_locale:String
var label:String = "verify"
var started_usec:int = Time.get_ticks_usec()
var duration_seconds:float = 12.0
var spawn_ms:float = 0.0
var samples:Array[float] = []
var physics_samples:Array[float] = []
var sample_elapsed:float = 0.0
var last_usec:int = 0
var sampling:bool = false
var peak_nodes:int = 0
var peak_shooters:int = 0
var min_alive:int = 100
var peak_draw_calls:int = 0
var sample_counter:int = 0

func _initialize() -> void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):
			label = arg.trim_prefix("--label=").validate_filename()
		if arg.begins_with("--duration="):
			duration_seconds = clampf(float(arg.trim_prefix("--duration=")),2.0,120.0)
	call_deferred("_run")

func _run() -> void:
	game = root.get_node("Game")
	saved_settings = game.Game_Settings.duplicate(true)
	saved_locale = game.current_locale
	game.Game_Settings["Training_Mode"] = false
	game.Game_Settings["Training_Mode_Type"] = "manual"
	game.Game_Settings["Ball_Can_Move"] = true
	game.Game_Settings["Have_Team_Damage"] = false
	game.Game_Settings["Blood_Effects"] = true
	game.now_stop_state = false
	Engine.time_scale = 1.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var scene:PackedScene = load("res://scenes/world.tscn")
	world = scene.instantiate()
	world.tree_entered.connect(func() -> void: current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.visible = false
	await create_timer(1.0).timeout
	world._battle_random_seed = game.begin_battle_random(20260914)
	var rect:Rect2 = world.return_map_world_rect(world.map_group["Map50x50"])
	var started:int = Time.get_ticks_usec()
	for i:int in range(100):
		var col:int = i % 10
		var row:int = i / 10
		var point:Vector2 = rect.position + rect.size * Vector2(0.12 + float(col) * 0.084,0.12 + float(row) * 0.084)
		world.create_char("Team0" if col < 5 else "Team1","小刀猎",point)
	spawn_ms = float(Time.get_ticks_usec() - started) / 1000.0
	print("BENCH_SPAWN ",spawn_ms," ms; units=",world.get_battle_units_fast().size())
	await create_timer(2.0).timeout
	last_usec = Time.get_ticks_usec()
	sampling = true

func _process(_delta:float) -> bool:
	if Time.get_ticks_usec() - started_usec > 180000000:
		if game != null and is_instance_valid(game) and not saved_settings.is_empty():
			game.Game_Settings = saved_settings
			game.current_locale = saved_locale
		push_error("Benchmark watchdog: result not completed within 180 seconds")
		quit(2)
		return false
	if not sampling:
		return false
	var now:int = Time.get_ticks_usec()
	var elapsed:float = float(now - last_usec) / 1000000.0
	last_usec = now
	sample_elapsed += elapsed
	samples.append(elapsed * 1000.0)
	physics_samples.append(float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
	peak_nodes = maxi(peak_nodes,int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	peak_draw_calls = maxi(peak_draw_calls,int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	sample_counter += 1
	if sample_counter == 1 or sample_counter % 5 == 0:
		peak_shooters = maxi(peak_shooters,get_nodes_in_group("Ball").size() - world.get_battle_units_fast().size())
		min_alive = mini(min_alive,int(world._count_primary_battle_characters()))
	if sample_elapsed >= duration_seconds:
		sampling = false
		call_deferred("_finish")
	return false

func _percentile(values:Array[float],q:float) -> float:
	if values.is_empty():
		return 0.0
	return values[clampi(int(ceil(q * float(values.size()))) - 1,0,values.size() - 1)]

func _finish() -> void:
	samples.sort()
	physics_samples.sort()
	var result:Dictionary = {
		"label":label,"map":"Map50x50","character":"小刀猎","initial_characters":100,
		"teams":"50 vs 50; no friendly fire","training":false,"blood_effects":true,
		"seed":20260914,"duration_s":sample_elapsed,"frames":samples.size(),
		"fps_average":float(samples.size()) / maxf(sample_elapsed,0.001),
		"frame_ms_p50":_percentile(samples,0.50),"frame_ms_p95":_percentile(samples,0.95),
		"frame_ms_p99":_percentile(samples,0.99),"frame_ms_max":samples.back(),
		"physics_ms_p50":_percentile(physics_samples,0.50),"physics_ms_p95":_percentile(physics_samples,0.95),
		"spawn_100_ms":spawn_ms,"min_alive_sampled":min_alive,"peak_nodes":peak_nodes,
		"peak_shooters_sampled":peak_shooters,"peak_draw_calls":peak_draw_calls,
		"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),
		"window_size":str(DisplayServer.window_get_size()),"godot":Engine.get_version_info().string,
		"settings":game.Game_Settings.duplicate(true)
	}
	var file:FileAccess = FileAccess.open("res://scripts/training/benchmark_"+label+".json",FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result,"\t"))
		file.close()
	print("BENCH_RESULT ",JSON.stringify(result))
	game.Game_Settings = saved_settings
	game.current_locale = saved_locale
	quit()
