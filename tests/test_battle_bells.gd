extends SceneTree
## 开战钟声 + 胜利铃：开战敲一次我的世界的钟；轮换中间场的胜利铃跟着门上滑下的胜利卡片响；下一场开门后再敲钟；最后一场照常响胜利铃。
var world:Node
var game:Node
var checks:int = 0
var failures:int = 0
var events:Array[Dictionary] = []
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("BATTLE_BELLS FAIL: "+label)
func _on_child(node:Node) -> void:
	if not node is AudioStreamPlayer: return
	var label:String = str(node.name)
	if label.contains("BattleStartBell") or label.contains("VictoryBell"):
		var door:Node = root.get_node_or_null("DarkOakDoorTransition")
		events.append({"kind":"start" if label.contains("BattleStartBell") else "victory","stream":(node as AudioStreamPlayer).stream,
			"phase":int(door.phase) if door != null else -1})
func count(kind:String) -> int:
	return events.filter(func(e:Dictionary) -> bool: return e.kind == kind).size()
func wait_until(cond:Callable,ms:int) -> void:
	var deadline:int = Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline and not cond.call(): await process_frame
func run() -> void:
	create_timer(90.0,true,false,true).timeout.connect(func(): print("BATTLE_BELLS TIMEOUT"); quit(2))
	game = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Boss_Intro = false
	game.Game_Settings.Map_Background = "blue"
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	await process_frame
	await process_frame
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	game.now_stop_state = false
	root.child_entered_tree.connect(_on_child)
	world.reset()
	await process_frame
	var gs:Dictionary = game.Game_Settings
	gs.Training_Mode_Type = "rotation"; gs.Rotation_Match_Type = "duel"; gs.Training_Wheel_Battle = false
	gs.Rotation_Multi_Characters = true; gs.Rotation_Blue_Count = 1; gs.Rotation_Red_Count = 1
	world.control.team.show()
	world._battle_setup_next_id = 1
	var waves:Array = [[["left","苦力怕"],["right","烈焰人"]],[["left","骷髅"],["right","苦力怕"]]]
	for r:int in range(waves.size()):
		for pair:Array in waves[r]: world._enqueue_rotation_character("",str(pair[1]),world._rotation_spawn_position(str(pair[0])),str(pair[0]),"",r + 1)
	world.control.hide(); world.control.team.hide()
	world._update_special_training_modes(0.0)
	for unit:Node in get_nodes_in_group("Ball"): unit.process_mode = Node.PROCESS_MODE_DISABLED
	await wait_until(func() -> bool: return count("start") > 0,2000)
	check(count("start") == 1 and count("victory") == 0,"battle start rings the Minecraft bell once")
	check(events.size() > 0 and str((events[0].stream as AudioStream).resource_path).contains("我的世界/bell/bell_use0"),"start bell uses block.bell.use")
	for i:int in range(10): await process_frame
	check(count("start") == 1,"the start bell does not repeat during the fight")
	var loser:Node = world._find_character_by_setup_id_any(int(world._rotation_active_setup.right))
	loser.health = 0
	loser.queue_free()
	var door:Node = null
	await wait_until(func() -> bool:
		var d:Node = root.get_node_or_null("DarkOakDoorTransition")
		return d != null and d.phase == d.Phase.COVERED,6000)
	door = root.get_node_or_null("DarkOakDoorTransition")
	check(door != null and door.phase == door.Phase.COVERED and bool(world._victory_bell_played),"round result is recorded while the doors close")
	await create_timer(0.7,true,false,true).timeout
	var victory_phases:Array = events.filter(func(e:Dictionary) -> bool: return e.kind == "victory").map(func(e:Dictionary) -> int: return int(e.phase))
	check(victory_phases.size() == 3 and victory_phases.all(func(p:int) -> bool: return p == int(door.Phase.COVERED)),"three victory bells ring when the result card slides down (%s)" % str(victory_phases))
	check(count("start") == 1,"no start bell behind the closed doors")
	await wait_until(func() -> bool: return not world._rotation_transitioning and count("start") >= 2,6000)
	var second_start:Array = events.filter(func(e:Dictionary) -> bool: return e.kind == "start")
	check(second_start.size() == 2 and int(second_start[1].phase) != int(door.Phase.CLOSING) and int(second_start[1].phase) != int(door.Phase.COVERED),"the next round rings the start bell when the doors open")
	for unit:Node in get_nodes_in_group("Ball"): unit.process_mode = Node.PROCESS_MODE_DISABLED
	var final_loser:Node = world._find_character_by_setup_id_any(int(world._rotation_active_setup.right))
	final_loser.health = 0
	final_loser.queue_free()
	await wait_until(func() -> bool: return world._rotation_finished,3000)
	await create_timer(0.7,true,false,true).timeout
	check(world._rotation_finished and count("victory") == 6 and count("start") == 2,"series end rings the victory bells with the result (victory=%d start=%d)" % [count("victory"),count("start")])
	root.child_entered_tree.disconnect(_on_child)
	world.reset()
	await process_frame
	game.Game_Settings = saved
	world.queue_free()
	await process_frame
	var leftover_door:Node = root.get_node_or_null("DarkOakDoorTransition")
	if leftover_door != null: leftover_door.queue_free()
	print("BATTLE_BELLS_RESULT checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)

