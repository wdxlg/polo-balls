extends SceneTree
## 轮换模式切换：同一种角色（含数量复制）显示角色本人、混合队伍显示队伍；门关上后卡片滑下，经验条充满后开门；最后一场不关门，直接结算并放烟花。
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
	# 真实切换流程：门关上后卡片从上方滑下，经验条按等待时间充满，满了才开门。
	await setup([[["left","苦力怕"],["right","烈焰人"]],[["left","骷髅"],["right","苦力怕"]]],1,1)
	var loser:Node = world._find_character_by_setup_id_any(int(world._rotation_active_setup.right))
	loser.health = 0
	loser.queue_free()
	var door:Node = null
	var deadline:int = Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline:
		door = root.get_node_or_null("DarkOakDoorTransition")
		if door != null and door.phase == door.Phase.COVERED: break
		await process_frame
	check(door != null and door.phase == door.Phase.COVERED and is_equal_approx(door.wait_seconds,world.ROTATION_RESULT_WAIT_SECONDS),"doors close and hold for the result")
	var card:Node = door.shield.get_node_or_null("RotationResultCard") if door != null else null
	check(card != null,"the result card sits on the closed doors")
	if card != null:
		await create_timer(0.6,true,false,true).timeout
		check(card.slide >= 0.99 and card.card_rect().position.y > 0.0,"card slid down from the top")
		check(card.body_text() == "苦力怕 获得了胜利" and card.title_text() == "挑战已完成！" and ["下一场：苦力怕 vs 苦力怕","下一场：骷髅 vs 苦力怕"].has(card.hint_text()),"card shows the winner and the next matchup: "+card.body_text()+" / "+card.hint_text())
		var early:float = door.loading_progress
		check(door.phase == door.Phase.COVERED and early > 0.15 and early < 0.6,"experience bar fills with the waiting time: %.2f" % early)
		await create_timer(0.5,true,false,true).timeout
		check(door.phase == door.Phase.COVERED and door.loading_progress > early,"doors stay closed while the bar fills")
		deadline = Time.get_ticks_msec() + 4000
		while Time.get_ticks_msec() < deadline and door.phase == door.Phase.COVERED: await process_frame
		check(door.phase != door.Phase.COVERED,"a full bar opens the doors")
		deadline = Time.get_ticks_msec() + 3000
		while Time.get_ticks_msec() < deadline and world._rotation_transitioning: await process_frame
		check(not world._rotation_transitioning and door.wait_seconds == 0.0 and world._find_character_by_setup_id_any(int(world._rotation_active_setup.left)) != null,"next round starts and the shared door leaves wait mode")
		check(not is_instance_valid(world._match_fireworks),"a middle rotation round does not launch fireworks")
		for unit:Node in get_nodes_in_group("Ball"): unit.process_mode = Node.PROCESS_MODE_DISABLED
		var final_winner:Node = world._find_character_by_setup_id_any(int(world._rotation_active_setup.left))
		var final_loser:Node = world._find_character_by_setup_id_any(int(world._rotation_active_setup.right))
		final_loser.health = 0
		final_loser.queue_free()
		deadline = Time.get_ticks_msec() + 3000
		while Time.get_ticks_msec() < deadline and not world._rotation_finished: await process_frame
		await create_timer(0.5,true,false,true).timeout
		check(world._rotation_finished and not world._rotation_transitioning,"last rotation round finishes the series")
		check(door.phase == door.Phase.IDLE and not is_instance_valid(world._rotation_door) and not is_instance_valid(world._rotation_toast_mirror),"the series end skips the door transition")
		check(is_instance_valid(final_winner) and world._find_character_by_setup_id_any(int(world._rotation_active_setup.left)) == final_winner,"final winner stays on the field")
		check(hud.round_result_locked and hud.victory_body_text() == "骷髅 获得了胜利","series result shows the final winner: "+hud.victory_body_text())
		check(is_instance_valid(world._match_fireworks),"series end launches fireworks")
	check(hud.rotation_wave_kinds([{"round":1,"scene_path":"a"},{"round":1,"scene_path":"a"},{"round":2,"scene_path":"b"}],0) == 1 and hud.rotation_wave_kinds([{"round":1,"char":"x"},{"round":1,"char":"y"}],1) == 2,"wave kinds counted per round by scene, then name")
	world.reset()
	await process_frame
	game.Game_Settings = saved
	world.queue_free()
	await process_frame
	var leftover_door:Node = root.get_node_or_null("DarkOakDoorTransition")
	if leftover_door != null: leftover_door.queue_free()
	print("ROTATION_TOAST_RESULT checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)



