extends SceneTree
## Real-scene roster bindings and authority-side manual action gating.
var checks:int = 0
var failures:int = 0
var game:Node
var arena:Node2D
var previous_scene:Node
var previous_target:Node
var previous_stop:bool

func _initialize() -> void: call_deferred("run")

func check(condition:bool,label:String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("ROSTER_CONTROL_FAIL " + label)

func spawn(path:String,probe:String = "") -> Node2D:
	var actor:Node2D = (load(path) as PackedScene).instantiate() as Node2D
	if not probe.is_empty(): actor.set_script(load(probe))
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	arena.add_child(actor,true)
	actor.set_physics_process(false)
	return actor

func verify(path:String,wanted:Array) -> void:
	var actor:Node = (load(path) as PackedScene).instantiate()
	check(actor.player_control_action_ids() == wanted,path + " real action order")
	actor.free()

func finish() -> void:
	game._clear_local_control_action_holds(false)
	game._controlled_peer_paths.clear()
	game._controlled_path_peers.clear()
	game._remote_control_action_hold_masks.clear()
	game._remote_control_assignments.clear()
	game._set_local_control_target(previous_target)
	game.now_stop_state = previous_stop
	current_scene = previous_scene
	arena.queue_free()
	print("ROSTER_CONTROL_RESULT checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)

func run() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	game = root.get_node("Game")
	previous_scene = current_scene
	previous_target = game.get_local_controlled_character()
	previous_stop = game.now_stop_state
	game.now_stop_state = false
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena

	# C-selection remains available for the whole roster, but unused mouse slots are empty.
	var roles:Dictionary = {
		"人物/国王":[&"controlled_attack_action"],
		"人物/伪军头子":[&"controlled_attack_action"],
		"人物/炸弹客":[&"controlled_attack_action"],
		"meme/时光":[&"controlled_attack_action"],
		"meme/野生狗奶":[&"controlled_attack_action"],
		"人物/黑帮老大":[&"controlled_attack_action",&"controlled_skill_action",&"controlled_money_action"],
		"人物/训犬师":[&"controlled_attack_action",&"controlled_skill_action"],
		"人物/棋手":[&"controlled_attack_action"],
		"动物/猫":[&"controlled_attack_action",&"controlled_skill_action"],
		"人物/原始人":[&"controlled_attack_action"],
		"动漫/菜月昴":[&"controlled_attack_action",&"controlled_skill_action"],
		"动漫/五条悟":[&"controlled_attack_action",&"controlled_skill_action",&"controlled_middle_action",&"controlled_teleport",&"controlled_domain",&"controlled_instant_domain",&"controlled_barrier_flip"],
		"动漫/宿傩":[&"controlled_attack_action",&"controlled_skill_action",&"controlled_middle_action",&"controlled_amplification",&"controlled_domain",&"controlled_mahoraga",&"controlled_agito",&"controlled_world_slash"],
		"动漫/魔虚罗":[&"controlled_attack_action",&"controlled_skill_action",&"controlled_middle_action"],
		"动漫/嵌合暗兽":[&"controlled_attack_action",&"controlled_skill_action",&"controlled_middle_action"],
		"人物/伤心的男人":[&"controlled_attack_action"],
		"人物/形态/疲倦的人_悲伤形态":[&"controlled_attack_action"],
		"人物/红绿灯":[&"controlled_attack_action"],
		"人物/重女":[&"controlled_attack_action"],
		"人物/掷骰子的人":[&"controlled_attack_action",&"controlled_skill_action",&"controlled_middle_action"],
		"月计/堇紫泪滴":[&"controlled_attack_action",&"controlled_skill_action"],
		"人物/智者":[&"controlled_attack_action"],
		"我的世界/末影人":[&"controlled_attack_action"],
		"人物/面包车":[&"controlled_attack_action"],
		"人物/投资者":[&"controlled_attack_action"],
		"人物/火车长":[&"controlled_attack_action"],
		"人物/疲倦的人":[],
		"我的世界/铁匠村民":[],
		"我的世界/时钟":[],
		"人物/变形者":[&"controlled_attack_action"],
		"我的世界/雾中人":[&"controlled_attack_action",&"controlled_skill_action"],
		"meme/肌肉男":[],
		"动物/牛":[],
	}
	for suffix:String in roles:
		verify("res://scenes/characters/" + suffix + ".tscn",roles[suffix])
	var clone:Node2D = spawn("res://scenes/creatures/末影分身.tscn")
	check(clone.manual_controllable_subentity and game._can_control_candidate(clone) and clone.player_control_action_ids().is_empty(),"enderman clone is independently C-selectable without invented attacks")

	var wild_dog:Node2D = spawn("res://scenes/characters/meme/野生狗奶.tscn","res://tests/manual_wild_dog_milk_probe.gd")
	wild_dog.set_player_control_peer(1)
	wild_dog._cycle_left = 0.5
	wild_dog.player_control_action(0)
	check(wild_dog.test_starts == 0,"wild dog cannot start time acceleration before first delay")
	wild_dog._cycle_left = 0.0
	wild_dog.tick_physics(wild_dog.State.Move,0.1)
	check(wild_dog.test_starts == 0,"wild dog ready timer never auto-starts while controlled")
	wild_dog.player_control_action(0)
	wild_dog.player_control_action(0)
	check(wild_dog.test_starts == 1,"wild dog left starts one time field, no duplicate during active phase")
	wild_dog._time_active = false
	wild_dog.set_player_control_peer(0)
	wild_dog.tick_physics(wild_dog.State.Move,0.1)
	check(wild_dog.test_starts == 2,"wild dog resumes automatic cycle after exiting C")

	var tired:Node2D = spawn("res://scenes/characters/人物/疲倦的人.tscn","res://tests/manual_tired_spawn_probe.gd")
	check(tired.player_control_action_ids().is_empty(),"tired actor has no attack before sleeping")
	tired._fall_asleep()
	check(tired.player_control_action_ids() == [&"Attack"],"sleeping actor gains real left-click volley")
	tired.Team = "manual_left"
	var tired_enemy:Node2D = spawn("res://scenes/ball.tscn")
	tired_enemy.Team = "manual_right"
	tired_enemy.global_position = Vector2(100.0,0.0)
	tired.set_player_control_peer(1)
	tired.set_player_control_aim_position(tired.global_position + Vector2.DOWN*200.0)
	tired.Attack()
	check(not tired.test_directions.is_empty() and tired.test_directions[0].dot(Vector2.DOWN)>0.5,"sleeping volley snapshots mouse aim instead of AI target direction")

	var smith:Node2D = spawn("res://scenes/characters/我的世界/铁匠村民.tscn")
	check(smith.player_control_action_ids().is_empty(),"unarmed smith has no sword button")
	smith.sword_tier = smith.TIER_IRON
	smith._apply_equipment_stats(false)
	check(smith.player_control_action_ids() == [&"Attack"],"forged sword unlocks existing left-click sword swing")

	var conductor:Node2D = spawn("res://scenes/characters/人物/火车长.tscn")
	var train:Node2D = spawn("res://scenes/creatures/火车长_列车.tscn","res://tests/manual_train_launch_probe.gd")
	train.owner_conductor = conductor
	train._started = true
	train._state = train.STATE_STAGED
	train.launch_interval = 30.0
	train.minimum_station_dwell = 2.5
	train.coal_count = 1
	conductor._train = train
	check(not train.can_request_manual_launch(),"train cannot launch before its coal-adjusted cooldown")
	conductor.set_player_control_peer(1)
	check(train._conductor_is_manually_controlled(),"train sees authority-side manual conductor")
	train._launch_elapsed = 25.0
	conductor.player_control_action(0)
	check(train.test_launches == 0,"train click respects thirty minus four seconds with one coal")
	train._launch_elapsed = 26.0
	conductor.player_control_action(0)
	check(train.test_launches == 1 and train._state == train.STATE_DEPARTING,"train click departs exactly once when ready")
	conductor.player_control_action(0)
	check(train.test_launches == 1,"departing train rejects repeated press")
	conductor.set_player_control_peer(0)
	check(not train._conductor_is_manually_controlled(),"train returns to automatic mode after C exit")

	var van:Node2D = spawn("res://scenes/characters/人物/面包车.tscn","res://tests/manual_van_spawn_probe.gd")
	van.set_player_control_peer(1)
	van._summon_elapsed = van.summon_interval
	van._reverse_left = 1.0
	van._vehicle_speed = -maxf(van.engine_audio_min_speed,12.0)
	van._physics_process(0.05)
	check(van.test_spawns == 0,"manual reverse never auto-summons")
	van.player_control_action(0)
	check(van.test_spawns == 1 and van._summon_elapsed == 0.0,"manual reverse click summons and consumes cooldown")
	van._summon_elapsed = van.summon_interval
	van._vehicle_speed = -2.0
	van.player_control_action(0)
	check(van.test_spawns == 1,"van cannot summon without actual reverse speed")
	van._vehicle_speed = -maxf(van.engine_audio_min_speed,12.0)
	van.set_player_control_peer(0)
	van._physics_process(0.01)
	check(van.test_spawns == 2,"AI van resumes automatic reverse summons after exit")

	var investor:Node2D = spawn("res://scenes/characters/人物/投资者.tscn")
	investor._create_market_controller()
	var market:Node = investor._market_controller
	investor.set_player_control_peer(1)
	investor.player_control_action(0)
	check(market._manual_column_requested,"investor click requests next column")
	market._manual_column_requested = false
	market._manual_column_ready = false
	investor.player_control_action(0)
	check(not market._manual_column_requested,"investor click cannot skip existing column interval")
	market._manual_column_ready = true
	investor.set_player_control_peer(0)
	investor.player_control_action(0)
	check(not market._manual_column_requested,"investor cannot request a column after leaving control")

	var fog:Node2D = spawn("res://scenes/characters/我的世界/雾中人.tscn")
	var enemy:Node2D = spawn("res://scenes/ball.tscn")
	fog.Team = "manual_left"
	enemy.Team = "manual_right"
	enemy.global_position = Vector2(130.0,0.0)
	fog.set_player_control_peer(1)
	fog.set_player_control_aim_position(enemy.global_position)
	fog.phase = fog.Phase.RAGE
	fog.lightning_wait = false
	fog.rage_left = 5.0
	fog.rush = fog.Rush.RECOVER
	fog.rush_left = 0.0
	fog.step_mob(0.05)
	check(fog.rush == fog.Rush.RECOVER,"fog rage does not auto-start a random rush under control")
	fog.player_control_action(0)
	check(fog.rush == fog.Rush.MIST,"fog left starts the existing mist dash at cursor enemy")
	fog.player_control_action(1)
	check(fog.rush == fog.Rush.MIST,"fog right cannot interrupt an active dash")
	fog.dash_remaining = 0.0
	fog.step_mob(0.05)
	fog.step_mob(fog.attack_interval + 0.01)
	fog.player_control_action(1)
	check(fog.rush == fog.Rush.FACE_VANISH,"fog right starts face burst after recovery")

	var morph:Node2D = spawn("res://scenes/characters/人物/变形者.tscn")
	morph.transform_preview_duration = 0.0
	morph.set_player_control_peer(1)
	morph.set_player_control_direction(Vector2.RIGHT)
	morph.set_player_control_aim_position(Vector2(420.0,32.0))
	game._set_local_control_target(morph)
	var old_morph_path:String = str(morph.get_path())
	game._controlled_peer_paths[1] = old_morph_path
	game._controlled_path_peers[old_morph_path] = 1
	game._remote_control_action_hold_masks[1] = 1
	morph._start_transform_wait()
	check(not morph._transform_wait_started,"controlled morph never auto-starts its transform timer")
	var successor:Node2D = (load("res://scenes/ball.tscn") as PackedScene).instantiate() as Node2D
	morph._replace_self_with_form(successor,"res://scenes/ball.tscn")
	check(successor.player_control_direction == Vector2.RIGHT and successor.has_player_control_aim(),"morph carries movement and aim at handoff")
	await process_frame
	check(game.get_local_controlled_character() == successor and successor.is_player_controlled(),"morph transfers local control to new body")
	check(str(game._controlled_peer_paths.get(1,"")) == str(successor.get_path()) and not game._controlled_path_peers.has(old_morph_path),"morph rebinds server peer/path assignment")
	check(not game._remote_control_action_hold_masks.has(1),"morph cancels stale server button holds")
	var controller:Node = successor.get_node_or_null("MorphFormController")
	check(controller != null,"morph keeps its original return controller")
	if controller != null:
		controller.transform_preview_duration = 0.0
		controller._restore_original(successor)
		await process_frame
		var restored:Node = game.get_local_controlled_character()
		check(restored != null and restored != successor and restored.is_player_controlled(),"morph returns control to original body")
		check(restored != null and str(game._controlled_peer_paths.get(1,"")) == str(restored.get_path()),"restored morph remains server-owned by same peer")
		game._release_control_for_peer(1)
		game._set_local_control_target(null)

	# A reliable assignment may arrive before the new form's MultiplayerSpawner node.
	var incoming_path:String = str(arena.get_path()) + "/IncomingControl"
	game._sync_control_assignments({1:incoming_path})
	var incoming:Node2D = (load("res://scenes/ball.tscn") as PackedScene).instantiate() as Node2D
	incoming.name = "IncomingControl"
	incoming.process_mode = Node.PROCESS_MODE_DISABLED
	arena.add_child(incoming)
	await process_frame
	check(game.get_local_controlled_character() == incoming,"client resolves replacement when new node arrives after assignment")
	game._sync_control_assignments({})
	check(game.get_local_controlled_character() == null,"client release clears replaced local control")
	# Simulate a C release while the new network body has not spawned: stale grant and
	# the coroutine must not reacquire the body after explicit cancellation.
	var abandoned_path:String = str(arena.get_path()) + "/AbandonedControl"
	game._sync_control_assignments({1:abandoned_path})
	game._local_control_release_requested = true
	game._control_character_result(NodePath(abandoned_path))
	var abandoned:Node2D = (load("res://scenes/ball.tscn") as PackedScene).instantiate() as Node2D
	abandoned.name = "AbandonedControl"
	abandoned.process_mode = Node.PROCESS_MODE_DISABLED
	arena.add_child(abandoned)
	await process_frame
	check(game.get_local_controlled_character() == null,"client C release ignores stale grant before new body spawns")
	game._sync_control_assignments({})
	check(not game._local_control_release_requested,"server release acknowledgment resets pending local release")
	finish()
