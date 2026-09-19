extends "res://tests/benchmark_200.gd"
## 混合角色基准：从完整角色名单随机抽 N 个（默认 100，两队各半）在 Map50x50 混战。
## --seed=  抽样种子（默认 20260919）；--count= 人数；--label= 输出 JSON 名；--exclude=a,b 排除角色。
var pick_seed:int = 20260919
var exclude:Array[String] = []
var roster:Array[String] = []
func _initialize() -> void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			pick_seed = int(arg.trim_prefix("--seed="))
		if arg.begins_with("--exclude="):
			for raw:String in arg.trim_prefix("--exclude=").split(",",false):
				exclude.append(raw.strip_edges())
	unit_count = 100
	super._initialize()
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
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func() -> void: current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.visible = false
	await create_timer(1.0).timeout
	_before_spawn()
	var names:Array[String] = world.return_all_character_names()
	for banned:String in exclude:
		names.erase(banned)
	var rng := RandomNumberGenerator.new()
	rng.seed = pick_seed
	var histogram:Dictionary = {}
	for i:int in range(unit_count):
		var picked:String = names[rng.randi_range(0,names.size() - 1)]
		roster.append(picked)
		histogram[picked] = int(histogram.get(picked,0)) + 1
	print("MIXED_ROSTER seed=",pick_seed," pool=",names.size()," ",JSON.stringify(histogram))
	world._battle_random_seed = game.begin_battle_random(20260914)
	var rect:Rect2 = world.return_map_world_rect(world.map_group["Map50x50"])
	var cols:int = int(ceil(sqrt(float(unit_count))))
	var rows:int = int(ceil(float(unit_count) / float(cols)))
	var started:int = Time.get_ticks_usec()
	for i:int in range(unit_count):
		var col:int = i % cols
		var row:int = i / cols
		var point:Vector2 = rect.position + rect.size * Vector2(0.08 + 0.84 * float(col) / float(maxi(cols - 1,1)),0.08 + 0.84 * float(row) / float(maxi(rows - 1,1)))
		world.create_char("Team0" if col < cols / 2 else "Team1",roster[i],point)
	spawn_ms = float(Time.get_ticks_usec() - started) / 1000.0
	min_alive = unit_count
	# create_char 会因 MC 资源预热器排队而异步完成；等所有角色真正入场后再开始采样。
	var wait_started:int = Time.get_ticks_usec()
	# 挂着远程 profiler 时生成会慢 2~3 倍，等待上限放宽到 90 s，避免采样期混入生成开销。
	while world._count_primary_battle_characters() < unit_count and Time.get_ticks_usec() - wait_started < 90000000:
		await process_frame
	spawn_ms = float(Time.get_ticks_usec() - started) / 1000.0
	print("BENCH_SPAWN ",spawn_ms," ms; units=",world.get_battle_units_fast().size()," primary=",world._count_primary_battle_characters())
	await create_timer(2.0).timeout
	last_usec = Time.get_ticks_usec()
	sampling = true
func _finish() -> void:
	var alive:Dictionary = {}
	for unit:Node in world.get_battle_units_fast():
		# 不能在 --script 脚本里引用 ball 类名：它会在 autoload 注册前强制编译 ball.gd。
		if unit != null and is_instance_valid(unit) and int(unit.get("Type")) == 0 and float(unit.get("health")) > 0.0:
			var key:String = unit.scene_file_path.get_file().get_basename()
			alive[key] = int(alive.get(key,0)) + 1
	print("MIXED_ALIVE_AT_END ",JSON.stringify(alive))
	super._finish()
