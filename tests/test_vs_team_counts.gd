extends SceneTree
## The World VS counts live characters per presentation side, not saved slots.

var checks:int = 0
var failures:int = 0
var game:Node
var world:Node
var actors:Array[Node2D] = []

func _initialize() -> void: run.call_deferred()

func check(ok:bool, description:String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ", description)
	if not ok: failures += 1

func spawn_named(name:String, team:String, master:Node2D = null) -> Node2D:
	var actor:Node2D = load("res://scenes/ball.tscn").instantiate()
	actor.Team = team
	actor.set_meta("morph_display_name", name)
	if master != null: actor.Master = master
	actor.position = Vector2(80 + actors.size() * 14, 100)
	world.add_child(actor, true)
	actor.Can_Attack = false
	actor.Can_Skill = false
	actor.set_physics_process(false)
	actor.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	actors.append(actor)
	return actor

func run() -> void:
	create_timer(45.0, true, false, true).timeout.connect(func(): push_error("VS_TEAM_COUNT_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	var original_settings:Dictionary = game.Game_Settings.duplicate(true)
	var original_locale:String = game.current_locale
	game.Game_Settings.Development_Mode = false
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Camera_Move = false
	game.Game_Settings.Map_Background = "blue"
	game.now_stop_state = false
	game.set_language("zh", false)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world, CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.control.hide()
	await create_timer(0.2, true, false, true).timeout
	world.set_process(false)
	world.set_physics_process(false)

	# Repeated names are not necessarily adjacent in either team's roster.
	var first:Node2D = spawn_named("钻石剑", "Team0")
	spawn_named("木剑", "Team0")
	var second:Node2D = spawn_named("钻石剑", "Team0")
	var rival:Node2D = spawn_named("钻石剑", "Team1")
	spawn_named("钻石剑", "Team1")
	var third:Node2D = spawn_named("钻石剑", "Team0")
	var sides:Dictionary = world.return_battle_sides()
	check(sides.order == ["team:Team0", "team:Team1"], "same name on different teams remains a separate side")
	check(sides.members["team:Team0"].size() == 4 and sides.members["team:Team1"].size() == 2, "counts originate from actual live World members")
	var zh:String = world.build_versus_text()
	check(zh.contains("[b]钻石剑 * 3 + 木剑[/b]"), "same-team duplicates are compacted in first-appearance order")
	check(zh.contains("[b]钻石剑 * 2[/b]") and zh.contains("[b]VS[/b]"), "enemy side has its own count and VS stays visible")
	check(not zh.contains("* 1") and not zh.contains("钻石剑 + 钻石剑"), "singletons have no multiplier and duplicates are not repeated")
	world._battle_setup.append({"id":9901,"team":"Team0","char":"钻石剑"})
	check(world.build_versus_text() == zh, "an absent character in the saved roster does not inflate the live count")
	world._battle_setup.clear()
	world.refresh_versus_text()
	check(world.versus_label.visible and world.versus_label.text == zh, "the actual map label uses the compact title")

	var mirror:Node = load("res://scripts/ui/battle_record_locale.gd").new()
	root.add_child(mirror)
	mirror._build_dictionary()
	game.set_language("en", false)
	world._last_versus_text = ""
	world.refresh_versus_text()
	var en:String = world.build_versus_text()
	check(en.contains("[b]Diamond Sword * 3 + Wooden Sword[/b]") and en.contains("[b]Diamond Sword * 2[/b]"), "direct English language uses identical grouping with translated names")
	check(mirror.translate(zh, "en", true) == en, "automatic English recording translation matches direct English VS")
	mirror.queue_free()
	game.set_language("zh", false)
	world._last_versus_text = ""
	world.refresh_versus_text()

	first.health = 0
	world.refresh_versus_text()
	check(world.versus_label.text.contains("[b]木剑 + 钻石剑 * 2[/b]"), "a real death decreases the current team count and retains live-member order")
	world.remove_child(second)
	second.free()
	world.refresh_versus_text()
	check(world.versus_label.text.contains("[b]木剑 + 钻石剑[/b]") and not world.versus_label.text.contains("* 1"), "removal returns to a single unsuffixed character")
	spawn_named("钻石剑", "Team0")
	world.refresh_versus_text()
	check(world.versus_label.text.contains("[b]木剑 + 钻石剑 * 2[/b]"), "a new actual character increases the count")
	rival.Team = "Team0"
	world.refresh_versus_text()
	check(world.versus_label.text.contains("[b]木剑 + 钻石剑 * 3[/b]") and not world.versus_label.text.contains("[b]钻石剑 * 2[/b]"), "switching teams moves one unit between independent counts")
	check(world.return_battle_sides().members["team:Team1"].size() == 1, "former opponent's side has one surviving participant")

	var solo1:Node2D = spawn_named("木剑", "")
	var solo2:Node2D = spawn_named("木剑", "")
	sides = world.return_battle_sides()
	check(sides.order.size() == 4 and sides.members[world.return_ball_side_key(solo1)].size() == 1 and sides.members[world.return_ball_side_key(solo2)].size() == 1, "no-Team characters remain separate solo sides")
	check(not world.build_versus_text().contains("木剑 * 2"), "identical solo names are never compacted into a fake team")
	spawn_named("钻石剑", "Team0", third)
	check(world.build_versus_text().contains("[b]木剑 + 钻石剑 * 3[/b]"), "ordinary summons are not counted as extra VS participants")
	third.health = 0
	# Drive the existing 5Hz UI scheduler deterministically (no wall-time sleeps).
	world._top_text_refresh_elapsed = world.top_text_refresh_interval
	world._process(0.001)
	check(world.versus_label.text.contains("[b]木剑 + 钻石剑 * 2[/b]"), "normal 5Hz VS refresh updates the visible number after death")

	world.queue_free()
	await process_frame
	game.Game_Settings = original_settings
	game.set_language(original_locale, false)
	print("VS_TEAM_COUNTS: %d checks / %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
