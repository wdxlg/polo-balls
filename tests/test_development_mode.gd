extends SceneTree

var game:Node
var world:Node2D
var original:Dictionary
var failures:int = 0
var checks:int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks += 1
	if ok:
		print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func _entry(id:int,team:String,side:String) -> Dictionary:
	var center:Vector2 = world._development.base_rect.get_center()
	return {"id":id,"char":"Test","scene_path":"res://scenes/ball.tscn","team":team,
		"x":center.x,"y":center.y,"development_base_position":true,"development_lane_key":side+":0"}

func run() -> void:
	create_timer(65.0,true,false,true).timeout.connect(func(): print("TIMEOUT"); quit(2))
	game = root.get_node("Game")
	original = game.Game_Settings.duplicate(true)
	game.Game_Settings.Development_Mode = true
	game.Game_Settings.Development_Duration = 1.0
	game.Game_Settings.Development_Speed = 2.0
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Map_Background = "blue"
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	await process_frame
	await process_frame
	world.control.team.show()
	check(world._development.phase == world._development.SETUP,"setting builds prebattle map")
	check(world.control.development_options.visible and world.control.development_duration_spin.value == 1.0 and world.control.development_speed_spin.value == 2.0,"enabled setting shows its duration and fast-forward controls")
	var left:Rect2 = Rect2(world._development.base_rect.position+world._development._offset("left:0"),world._development.base_rect.size)
	var right:Rect2 = Rect2(world._development.base_rect.position+world._development._offset("right:0"),world._development.base_rect.size)
	check(left.size == right.size and left.size == world._development.base_rect.size,"left and right each get the entire original map")
	check(left.end.x < right.position.x and world.map_islands(world._current_map_node()).size() == 2,"maps are horizontal with separate borders")
	var a:Node = world._spawn_character_from_setup(_entry(1,"Team0","left"))
	var b:Node = world._spawn_character_from_setup(_entry(2,"Team1","right"))
	var neutral_point:Vector2 = left.position + left.size*Vector2(0.76,0.76)
	var c:Node = world._spawn_character_from_setup({"id":-1,"char":"Neutral","scene_path":"res://scenes/ball.tscn","team":"", "x":neutral_point.x,"y":neutral_point.y,"development_neutral":true})
	check(a != null and b != null and c != null,"both teams and a neutral unit spawn")
	if a == null or b == null or c == null:
		quit(2)
		return
	var armor:Node = world._spawn_character_from_setup({"id":-8,"char":"盔甲架","scene_path":"res://scenes/characters/默认/盔甲架.tscn","team":"","x":left.get_center().x+left.size.x*0.22,"y":left.get_center().y})
	check(armor != null and str(armor.Team).is_empty() and armor.has_meta("development_neutral") and left.has_point(armor.global_position),"real default armor stand is neutral on the map where it was placed")
	for unit:Node in [a,b,c]:
		unit.Can_Attack = false
		unit.Can_Skill = false
		unit.Speed = 0
		unit.Health_Restore = 0
	check(left.has_point(a.global_position) and right.has_point(b.global_position) and str(c.Team).is_empty(),"units remain in their respective arenas; neutral has no team")
	check(a.process_mode == Node.PROCESS_MODE_DISABLED,"setup characters are frozen")
	world.control.team.hide()
	world._development.update(0.20)
	check(world._development.phase == world._development.RUNNING and is_equal_approx(game._time_scale._development_time_multiplier,2.0),"closing setup starts 2x growth clock")
	check(a.process_mode != Node.PROCESS_MODE_DISABLED and b.process_mode != Node.PROCESS_MODE_DISABLED,"both teams really act during development")
	await process_frame # Give the newly-instanced World one ordinary render frame before the transition.
	a.health = 23
	var original_local:Vector2 = a.global_position - world._development._offset("left:0")
	world._development.update(0.80)
	check(world._development.phase == world._development.MERGING and a.process_mode == Node.PROCESS_MODE_DISABLED and world._development.time_text() == "00:01","deadline pauses the clock and units for the merge")
	world._development._merge_frame(0.5)
	check((a.global_position-original_local).distance_to(world._development._merge_start_offsets["left:0"]*0.75) < 0.1,"slow-then-fast merge keeps relative coordinates")
	await create_timer(1.8,true,false,true).timeout
	check(world._development.phase == world._development.BATTLE,"merge starts the ordinary battle")
	check(is_instance_valid(a) and a.health == 23,"active character and its growth are preserved after battle begins")
	check(not is_instance_valid(c) or c.is_queued_for_deletion(),"neutral/default units disappear after merging")
	check(not is_instance_valid(armor) or armor.is_queued_for_deletion(),"default armor stand is removed with other default units")
	check(is_equal_approx(game._time_scale._development_time_multiplier,1.0),"player speed is restored after merging")
	check(world._center_watermark_name.text != "00:01","ordinary watermark returns for battle")
	world._battle_setup.clear()
	world._battle_setup.append(_entry(1,"Team0","left"))
	world._battle_setup.append(_entry(2,"Team1","right"))
	world._battle_setup_map = world.now_choose_map
	world.rematch_last_battle()
	await process_frame
	await process_frame
	var replay_blue:Node = world._find_character_by_setup_id_any(1)
	check(world._development.is_prebattle() and world.map_islands(world._current_map_node()).size() == 2,"ordinary rematch starts fresh development with two complete maps")
	check(replay_blue != null and replay_blue != a and replay_blue.has_meta("development_lane_key") and str(replay_blue.get_meta("development_lane_key")) == "left:0","ordinary rematch creates a new fighter in its own arena")

	# 轮换：每名候补都要实际运行，合并后作为原实例等候上场。
	world.reset()
	await process_frame
	game.Game_Settings.Training_Mode_Type = "rotation"
	game.Game_Settings.Rotation_Match_Type = "duel"
	world._development.cleanup(false)
	world._reset_special_training_state()
	world._development.prepare()
	world.control.team.show()
	world._enqueue_rotation_character("","Blue0",world._rotation_spawn_position("left"),"left","res://scenes/ball.tscn")
	world._enqueue_rotation_character("","Blue1",world._rotation_spawn_position("left"),"left","res://scenes/ball.tscn")
	world._enqueue_rotation_character("","Red0",world._rotation_spawn_position("right"),"right","res://scenes/ball.tscn")
	world._enqueue_rotation_character("","Red1",world._rotation_spawn_position("right"),"right","res://scenes/ball.tscn")
	world._enqueue_rotation_character("","Blue2",world._rotation_spawn_position("left"),"left","res://scenes/ball.tscn")
	var third_id:int = int(world._rotation_rosters.left[2].id)
	var third:Node = world._development.candidates.get(third_id)
	var third_local:Vector2 = third.global_position-world._development._offset("left:2")
	var removed_id:int = int(world._rotation_rosters.left[1].id)
	var deleted:bool = world.delete_rotation_queue_setup_id(removed_id,"left")
	await process_frame
	check(deleted and not world._development.candidates.has(removed_id) and world._rotation_rosters.left.size() == 2 and world.map_islands(world._current_map_node()).size() == 4,"deleting a queued fighter removes its personal map")
	check(is_instance_valid(third) and str(third.get_meta("development_lane_key")) == "left:1" and third.global_position.distance_to(third_local+world._development._offset("left:1")) < 0.01,"remaining fighter moves with its map and keeps its relative position")
	var blue_roster:Array = world._rotation_rosters["left"]
	var red_roster:Array = world._rotation_rosters["right"]
	var blue_next:int = int(blue_roster[1].id)
	var red_next:int = int(red_roster[1].id)
	var next_blue:Node = world._development.candidates.get(blue_next)
	var next_red:Node = world._development.candidates.get(red_next)
	check(world.map_islands(world._current_map_node()).size() == 4,"two contestants per team have four full maps")
	check(next_blue != null and next_red != null and next_blue.global_position.y != world._development.candidates[int(blue_roster[0].id)].global_position.y,"teammates grow on separate vertical maps")
	if next_blue == null or next_red == null:
		quit(2)
		return
	world.control.team.hide()
	world._development.update(0.2)
	check(next_blue.process_mode != Node.PROCESS_MODE_DISABLED and next_red.process_mode != Node.PROCESS_MODE_DISABLED and world.is_combat_runtime_active(),"every queued fighter really develops before the match")
	next_blue.health = 37
	world._development.update(0.8)
	await create_timer(1.8,true,false,true).timeout
	check(world._rotation_started and int(world._rotation_active_setup["left"]) == int(blue_roster[0].id),"rotation begins only after the map merger")
	check(next_blue.has_meta("development_reserve") and next_red.has_meta("development_reserve") and next_blue.health == 37,"future fighters are parked with developed state intact")
	var promoted:Node = world._spawn_next_rotation_character("left")
	check(promoted == next_blue and promoted.health == 37 and int(world._rotation_active_setup["left"]) == blue_next,"next fighter enters by original roster order without re-instantiation")
	check(not next_red.is_queued_for_deletion(),"other future candidate remains available")

	# 多岛传送门地图也有两张完整副本，门属于副本而非原图。
	world.reset()
	await process_frame
	game.Game_Settings.Training_Mode_Type = "manual"
	world._development.cleanup(false)
	world.now_choose_map = "Map_Portal"
	world._development.prepare()
	var original_portal:Node = world.map_group["Map_Portal"]
	var left_portal:Node = world._development.portal_for_lane("left:0")
	var right_portal:Node = world._development.portal_for_lane("right:0")
	check(left_portal != null and right_portal != null and left_portal.gates().size() == 6 and right_portal.gates().size() == 6,"each complete portal map has its own six usable gates")
	check(not original_portal.is_active() and world.map_islands(original_portal).size() == 6,"original portal is inactive; each side has all three islands")
	game.Game_Settings.Map_Background = "grass"
	world.refresh_map_presentation()
	check(left_portal._wall_carving and right_portal._wall_carving and left_portal.get_node_or_null("PortalVisuals") != null and right_portal.get_node_or_null("PortalVisuals") != null,"grass-style copies have independent carved door visuals")
	game.Game_Settings.Map_Background = "blue"
	world.refresh_map_presentation()
	var island_center:Vector2 = original_portal.island_rect("IslandA").get_center()
	world.control.team.show()
	var island_blue:Node = world._spawn_character_from_setup({"id":21,"char":"Test","scene_path":"res://scenes/ball.tscn","team":"Team0","x":island_center.x,"y":island_center.y,"development_base_position":true,"development_lane_key":"left:0"})
	var island_red:Node = world._spawn_character_from_setup({"id":22,"char":"Test","scene_path":"res://scenes/ball.tscn","team":"Team1","x":island_center.x,"y":island_center.y,"development_base_position":true,"development_lane_key":"right:0"})
	game.Game_Settings.Development_Duration = 5.0
	world.control.team.hide()
	world._development.update(0.2)
	var portal_a:Rect2 = left_portal.island_rect("IslandA")
	var portal_b:Rect2 = left_portal.island_rect("IslandB")
	island_blue.global_position = Vector2(portal_a.position.x+56.0,portal_a.end.y-40.0)
	island_blue.Speed = 400.0
	island_blue.default_properties["Speed"] = 400.0
	island_blue.direction = Vector2.DOWN
	var crossed:bool = false
	for tick:int in range(60):
		await physics_frame
		if portal_b.has_point(island_blue.global_position):
			crossed = true
			break
	island_blue.Speed = 0.0
	island_blue.default_properties["Speed"] = 0.0
	check(crossed and not right_portal.island_rect("IslandB").has_point(island_blue.global_position),"a growing character travels through its own portal, never the other team's portal")
	game.Game_Settings.Development_Duration = 1.0
	await process_frame
	world._development.update(0.8)
	await create_timer(1.8,true,false,true).timeout
	check(world._development.phase == world._development.BATTLE and original_portal.is_active() and world._development.portal_clones.is_empty(),"merging restores the real portal map")
	check(is_instance_valid(island_blue) and is_instance_valid(island_red),"portal-map teams survive merging")
	check(original_portal.island_rect("IslandB").has_point(island_blue.global_position),"portal traversal destination keeps its relative place after maps merge")

	# 车轮战/挑战均应使用发育期已经创建的候补，同时保留原有胜负/换人规则。
	for rule:String in ["wheel","challenge"]:
		world.reset()
		await process_frame
		world._development.cleanup(false)
		world.now_choose_map = "Map10x10"
		game.Game_Settings.Training_Mode_Type = "rotation"
		game.Game_Settings.Rotation_Match_Type = rule
		world._reset_special_training_state()
		world._development.prepare()
		world.control.team.show()
		for side:String in ["left","right"]:
			for i:int in range(2):
				world._enqueue_rotation_character("",side+str(i),world._rotation_spawn_position(side),side,"res://scenes/ball.tscn")
		for candidate:Node in world._development.candidates.values():
			candidate.Can_Attack = false
			candidate.Can_Skill = false
			candidate.Health_Restore = 0
		var left_roster:Array = world._rotation_rosters.left
		var right_roster:Array = world._rotation_rosters.right
		var future_left:Node = world._development.candidates[int(left_roster[1].id)]
		var future_right:Node = world._development.candidates[int(right_roster[1].id)]
		future_left.health = 31
		future_right.health = 29
		world.control.team.hide()
		world._development.update(0.2)
		await process_frame
		world._development.update(0.8)
		await create_timer(1.7,true,false,true).timeout
		var first_left:Node = world._find_character_by_setup_id_any(int(left_roster[0].id))
		var first_right:Node = world._find_character_by_setup_id_any(int(right_roster[0].id))
		check(world._rotation_started and first_left != null and first_right != null,rule+": original queue starts after development")
		first_left.health = 24
		first_right.health = 0
		first_right.queue_free()
		await create_timer(0.6,true,false,true).timeout
		check(world._find_character_by_setup_id_any(int(right_roster[1].id)) == future_right and future_right.health == 29,rule+": next red keeps its development")
		check(world._find_character_by_setup_id_any(int(left_roster[0].id)) == first_left and first_left.health == 24,rule+": surviving blue stays in battle")
		if rule == "challenge":
			future_right.health = 0
			future_right.queue_free()
			await create_timer(0.7,true,false,true).timeout
			check(world._find_character_by_setup_id_any(int(left_roster[1].id)) == future_left and future_left.health == 31,"challenge: next blue survives round cleanup with its growth")
			check(int(world._rotation_active_setup.right) == int(right_roster[0].id),"challenge: red queue restarts at its original first fighter")
	world.rematch_last_battle()
	await process_frame
	await process_frame
	check(world._development.is_prebattle() and world._development.candidates.size() == 4 and not world._rotation_started,"rematch rebuilds a new growth phase with all four candidates")
	world.reset()
	await process_frame
	check(world._development.phase == world._development.SETUP and world._development.elapsed == 0.0 and world._development.candidates.is_empty(),"reset clears prior development and starts a fresh setup")
	game.set_runtime_game_setting("Development_Mode",false,false)
	await process_frame
	check(world._development.phase == world._development.OFF and not world.control.development_options.visible and world.map_islands(world._current_map_node()).size() == 1,"disabling mode hides timing settings and restores a single normal map")
	world.queue_free()
	await process_frame
	game.Game_Settings = original
	game.set_development_time_multiplier(1.0)
	print("Development checks: ",checks,"; failures: ",failures)
	quit(0 if failures == 0 else 1)
