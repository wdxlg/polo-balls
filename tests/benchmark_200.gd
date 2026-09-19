extends "res://scripts/training/benchmark_round2_phases.gd"
## 200 角色基准：Map50x50，两队各 100。--char=角色名 可替换角色；--label=xxx 输出 JSON 名。
var char_name:String = "小刀猎"
var unit_count:int = 200
func _initialize() -> void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--char="):
			char_name = arg.trim_prefix("--char=")
		if arg.begins_with("--count="):
			unit_count = clampi(int(arg.trim_prefix("--count=")),2,400)
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
	world._battle_random_seed = game.begin_battle_random(20260914)
	var rect:Rect2 = world.return_map_world_rect(world.map_group["Map50x50"])
	var cols:int = int(ceil(sqrt(float(unit_count))))
	var rows:int = int(ceil(float(unit_count) / float(cols)))
	var started:int = Time.get_ticks_usec()
	for i:int in range(unit_count):
		var col:int = i % cols
		var row:int = i / cols
		var point:Vector2 = rect.position + rect.size * Vector2(0.08 + 0.84 * float(col) / float(maxi(cols - 1,1)),0.08 + 0.84 * float(row) / float(maxi(rows - 1,1)))
		world.create_char("Team0" if col < cols / 2 else "Team1",char_name,point)
	spawn_ms = float(Time.get_ticks_usec() - started) / 1000.0
	min_alive = unit_count
	print("BENCH_SPAWN ",spawn_ms," ms; units=",world.get_battle_units_fast().size())
	await create_timer(2.0).timeout
	last_usec = Time.get_ticks_usec()
	sampling = true

func _before_spawn() -> void:
	pass
func _finish() -> void:
	# 节点类型直方图：看 200 人 + 飞刀时树里到底堆了什么。
	var histogram:Dictionary = {}
	var process_nodes:int = 0
	var physics_nodes:int = 0
	var stack:Array = [root]
	while not stack.is_empty():
		var node:Node = stack.pop_back()
		histogram[node.get_class()] = int(histogram.get(node.get_class(),0)) + 1
		if node.is_processing(): process_nodes += 1
		if node.is_physics_processing(): physics_nodes += 1
		for child:Node in node.get_children(true):
			stack.append(child)
	var keys:Array = histogram.keys()
	keys.sort_custom(func(a,b): return histogram[a] > histogram[b])
	var top:Array = []
	for i in range(mini(24,keys.size())):
		top.append("%s=%d" % [keys[i],histogram[keys[i]]])
	print("NODE_HISTOGRAM total=",get_node_count()," processing=",process_nodes," physics_processing=",physics_nodes," ",", ".join(top))
	super._finish()
