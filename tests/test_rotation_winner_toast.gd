extends SceneTree
## 轮换模式切换时的胜利弹窗：同一种角色（含数量复制）弹出角色本人；混合队伍弹出队伍。
var world:Node
var game:Node
var checks:int = 0
var failures:int = 0
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("ROTATION_TOAST FAIL: "+label)
func setup(waves:Array,blue_count:int,red_count:int) -> void:
	world.reset()
	await process_frame
	await process_frame
	var gs:Dictionary = game.Game_Settings
	gs.Training_Mode_Type = "rotation"; gs.Rotation_Match_Type = "duel"; gs.Training_Wheel_Battle = false
	gs.Rotation_Multi_Characters = true
	gs.Rotation_Blue_Count = blue_count; gs.Rotation_Red_Count = red_count
	world.control.team.show()
	world._battle_setup_next_id = 1
	for r:int in range(waves.size()):
		for pair:Array in waves[r]:
			world._enqueue_rotation_character("",str(pair[1]),world._rotation_spawn_position(str(pair[0])),str(pair[0]),"",r + 1)
	world.control.hide(); world.control.team.hide()
	world._update_special_training_modes(0.0)
	for unit:Node in get_nodes_in_group("Ball"): unit.process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
func run() -> void:
	create_timer(120.0,true,false,true).timeout.connect(func(): print("ROTATION_TOAST TIMEOUT"); quit(2))
	game = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Boss_Intro = false
	game.Game_Settings.Map_Background = "blue"
	game.current_locale = "zh"
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	await process_frame
	await process_frame
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	var hud:Control = world.duel_top_hud
	# 蓝方数量 2：两只苦力怕，同一种角色 → 弹出苦力怕本人。
	await setup([[["left","苦力怕"],["right","烈焰人"]]],2,1)
	check(world._rotation_active_records.left.size() == 1 and get_nodes_in_group("Ball").size() >= 3,"blue count 2 spawns two copies of one character")
	hud.begin_round_result("left")
	check(hud.winner_index == 0 and str(hud.sides[0].raw_name) == "苦力怕" and not hud.sides[0].has("team_wool"),"same-character copies are shown as the character")
	check(hud.victory_body_text() == "苦力怕 获得了胜利","toast names the character, not the team: "+hud.victory_body_text())
	hud.end_round_result()
	# 同一波两个不同角色 → 弹出蓝队（羊毛）。
	await setup([[["left","苦力怕"],["left","骷髅"],["right","烈焰人"]]],1,1)
	check(world._rotation_active_records.left.size() == 2,"mixed wave has two different characters")
	hud.begin_round_result("left")
	check(str(hud.sides[0].raw_name) == "__rotation_left" and str(hud.sides[0].get("team_wool","")) == "blue","mixed team keeps the team identity and blue wool")
	check(hud.victory_body_text() == "蓝队 获得了胜利","toast names the team: "+hud.victory_body_text())
	hud.end_round_result()
	# 同一波两个相同角色（两条名单记录） → 仍是这个角色；红方单人获胜 → 角色本人。
	await setup([[["left","骷髅"],["left","骷髅"],["right","烈焰人"]]],1,1)
	hud.begin_round_result("left")
	check(str(hud.sides[0].raw_name) == "骷髅" and hud.victory_body_text() == "骷髅 获得了胜利","two entries of the same character still show the character")
	hud.end_round_result()
	hud.begin_round_result("right")
	check(hud.winner_index == 1 and hud.victory_body_text() == "烈焰人 获得了胜利","single red winner shows the character")
	hud.end_round_result()
	check(hud.rotation_wave_kinds([{"round":1,"scene_path":"a"},{"round":1,"scene_path":"a"},{"round":2,"scene_path":"b"}],0) == 1 and hud.rotation_wave_kinds([{"round":1,"char":"x"},{"round":1,"char":"y"}],1) == 2,"wave kinds counted per round by scene, then name")
	world.reset()
	await process_frame
	game.Game_Settings = saved
	world.queue_free()
	await process_frame
	var door:Node = root.get_node_or_null("DarkOakDoorTransition")
	if door != null: door.queue_free()
	print("ROTATION_TOAST_RESULT checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)

