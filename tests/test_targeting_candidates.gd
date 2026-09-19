extends SceneTree
## V434：World 可索敌候选快照必须与“遍历 Ball 组 + is_combat_targetable”一致，
## 且投稿角色工具 nearest_enemy / new5 nearest 通过快照得到的结果与全量扫描完全相同。
var checks:int = 0
var failures:int = 0
var T = null
func check(cond:bool,label:String) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL: " + label)
func _group_expected() -> Array:
	var out:Array = []
	for node in get_nodes_in_group("Ball"):
		if node.get("Type") == null: continue
		if node.has_method("is_combat_targetable") and node.is_combat_targetable():
			out.append(node)
	return out
func _brute_nearest(owner) -> Node:
	var best = null
	var best_sq:float = INF
	for raw in get_nodes_in_group("Ball"):
		if raw.get("Type") == null: continue
		if not T.is_enemy(owner,raw): continue
		var d:float = owner.global_position.distance_squared_to(raw.global_position)
		if d < best_sq:
			best_sq = d
			best = raw
	return best
func _same_set(a:Array,b:Array) -> bool:
	if a.size() != b.size(): return false
	for x in a:
		if not b.has(x): return false
	return true
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	T = load("res://scripts/characters/投稿角色工具.gd")
	var game:Node = root.get_node("Game")
	game.Game_Settings["Training_Mode"] = false
	game.Game_Settings["Training_Mode_Type"] = "manual"
	game.now_stop_state = false
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func() -> void: current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	await create_timer(0.8).timeout
	world._battle_random_seed = game.begin_battle_random(20260919)
	var border:Dictionary = world.return_now_map_border()
	var origin:Vector2 = border["start"] + Vector2(200,200)
	var before:Array = get_nodes_in_group("Ball")
	var layout:Array = [["Team0",Vector2(0,0)],["Team1",Vector2(90,10)],["Team1",Vector2(300,40)],["Team0",Vector2(60,200)],["Team1",Vector2(-150,-80)],["Team1",Vector2(500,500)]]
	for entry in layout:
		world.create_char(entry[0],"剑客",origin + entry[1])
	await process_frame
	var units:Array = []
	for node in get_nodes_in_group("Ball"):
		if not before.has(node) and node.get("Type") == 0: units.append(node)
	check(units.size() == 6,"spawned 6 units (got %d)" % units.size())
	if units.size() < 6:
		print("TARGETING_CANDIDATES_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
		quit(1)
		return
	# 等待若干物理帧让 30Hz 网格重建
	for i in range(6): await physics_frame
	var fast:Array = world.get_combat_targetable_units_fast()
	check(not fast.is_empty(),"fast snapshot non-empty")
	check(_same_set(fast,_group_expected()),"snapshot == group scan filtered by is_combat_targetable")
	var owner = units[0]
	check(owner.get("Team") == "Team0","owner is Team0")
	var via_fast = T.nearest_enemy(owner)
	check(via_fast == _brute_nearest(owner),"nearest_enemy via snapshot == brute force")
	check(via_fast == units[1],"nearest is the 90px Team1 unit")
	# 距离上限
	check(T.nearest_enemy(owner,50.0) == null,"max_distance respected")
	# 半径查询
	var in_r:Array = T.enemies_in_radius(owner,owner.global_position,320.0)
	check(in_r.size() == 3,"enemies_in_radius 320 -> 3 (got %d)" % in_r.size())
	# 1) 最近敌人死亡：快照尚未刷新时，nearest_enemy 仍必须实时排除它
	units[1].health = 0
	check(T.nearest_enemy(owner) == _brute_nearest(owner),"dead unit excluded before snapshot refresh")
	check(T.nearest_enemy(owner) == units[4],"next nearest after death is (-150,-80) unit")
	for i in range(6): await physics_frame
	check(not world.get_combat_targetable_units_fast().has(units[1]),"dead unit dropped from snapshot after refresh")
	# 2) 退出索敌契约
	units[4].set_meta(&"ignore_combat_targeting",true)
	check(T.nearest_enemy(owner) == units[2],"ignore_combat_targeting excluded immediately")
	for i in range(6): await physics_frame
	check(not world.get_combat_targetable_units_fast().has(units[4]),"ignored unit dropped from snapshot")
	check(_same_set(world.get_combat_targetable_units_fast(),_group_expected()),"snapshot still == group scan")
	# 3) 退出 Ball 组（薇欧拉/小狗叫式来客）
	units[2].remove_from_group("Ball")
	for i in range(6): await physics_frame
	check(not world.get_combat_targetable_units_fast().has(units[2]),"unit removed from Ball group dropped from snapshot")
	check(T.nearest_enemy(owner) == _brute_nearest(owner),"nearest_enemy still == brute after group removal")
	check(T.nearest_enemy(owner) == units[5],"last remaining enemy chosen")
	# 4) 全部敌人失效后返回 null（快照为空时退回 group 扫描，仍应为 null）
	units[5].health = 0
	check(T.nearest_enemy(owner) == null,"no enemy -> null")
	# 5) new5 utils.nearest 与暴力一致
	var U = load("res://scripts/characters/我的世界/new5/utils.gd")
	units[5].health = 100
	var brute = null
	var brute_sq:float = INF
	for raw in get_nodes_in_group("Ball"):
		if raw.get("Type") == null: continue
		if not U.enemy(owner,raw) or not raw.is_combat_lockable(): continue
		var d:float = owner.global_position.distance_squared_to(raw.global_position)
		if d < brute_sq:
			brute_sq = d
			brute = raw
	check(U.nearest(owner) == brute,"new5 utils.nearest == brute force")
	check(brute == units[5],"new5 nearest picks revived unit")
	print("TARGETING_CANDIDATES_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures > 0 else 0)

