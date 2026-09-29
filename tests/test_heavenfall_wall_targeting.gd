extends "res://tests/test_mc_new6_load.gd"
# Headless regression: AI must draw and fire at enemies behind real terrain.
# Target eligibility, range, cooldown and projectile collision rules stay separate.
# Load after autoload initialization; preloading these from --script compiles Game too early.
var TERRAIN: Script
var TARGETS: Script
var bow: Node2D


func reset_draw() -> void:
	bow.drawing = 0.0
	bow._cool = 0.0
	bow.facing = Vector2.UP


func expect_no_shot(label: String) -> void:
	reset_draw()
	var before: int = _bolts().size()
	bow.step_mob(float(bow.draw_time) + 0.01)
	check(_bolts().size() == before and is_zero_approx(bow.drawing), label)
	for bolt: Node in _bolts():
		bolt.set_physics_process(false)


func run() -> void:
	game = root.get_node("Game")
	TERRAIN = load("res://scripts/characters/我的世界/new6/heavenfall_collision.gd")
	TARGETS = load("res://scripts/characters/我的世界/new5/utils.gd")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0, true)
	create_timer(45.0, true, false, true).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world, CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	var center: Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	# Isolate targeting from units loaded/spawned by the real battle world.
	for other: Node in get_nodes_in_group("Ball"):
		other.process_mode = Node.PROCESS_MODE_DISABLED
		other.remove_from_group("Ball")
		if other is Node2D:
			other.global_position = center + Vector2(4000, 4000)
	bow = spawn("res://scenes/characters/我的世界/天堂陨落长弓.tscn", center + Vector2(-50, 0))
	bow.state_machine.set_physics_process(false)
	bow.set_physics_process(false)
	bow.Can_Attack = true
	var target: Node2D = _mk_enemy(center + Vector2(50, 0))
	var ally: Node2D = _mk_enemy(center + Vector2(-30, -30))
	ally.Team = bow.Team
	var wall: StaticBody2D = _mk_wall(center)
	await physics_frame
	await process_frame
	var obstruction: Dictionary = TERRAIN.terrain(bow, bow.global_position, target.global_position)
	check(obstruction.get("collider") == wall, "fixture: a real terrain wall blocks the line to the enemy")
	check(TARGETS.nearest(bow) == target, "nearest eligible enemy is selected despite a closer friendly unit")
	check(bow.can_act(), "fixture: the authoritative bow is allowed to attack")

	reset_draw()
	bow.step_mob(float(bow.draw_time) * 0.5)
	check(is_equal_approx(bow.drawing, float(bow.draw_time) * 0.5), "the bow starts drawing with its enemy behind a wall")
	check(bow.facing.is_equal_approx(Vector2.RIGHT), "the bow aims toward the occluded enemy")
	check(_bolts().is_empty(), "the normal draw time is still required before releasing an arrow")
	bow.step_mob(float(bow.draw_time) * 0.5 + 0.01)
	var shots: Array[Node] = _bolts()
	check(shots.size() == 1, "a complete draw automatically fires one arrow through the wall")
	for bolt: Node in shots:
		bolt.set_physics_process(false)
	if shots.size() == 1:
		check(shots[0]._dir.is_equal_approx(Vector2.RIGHT) and shots[0]._homing_target(bow) == target, "the fired arrow keeps the correct heading and can track the occluded enemy")
	bow.step_mob(0.1)
	check(_bolts().size() == shots.size() and is_zero_approx(bow.drawing), "cooldown prevents an immediate second shot")

	bow.Can_Attack = false
	expect_no_shot("disabling attacks still prevents firing through walls")
	bow.Can_Attack = true
	bow.dizziness = true
	expect_no_shot("stun still prevents firing through walls")
	bow.dizziness = false
	var near_position: Vector2 = target.global_position
	target.global_position = bow.global_position + Vector2(float(bow.shoot_range) + TARGETS.radius(target) + 10.0, 0)
	expect_no_shot("an enemy beyond the existing shooting range is not fired at")
	target.global_position = near_position
	target.Team = bow.Team
	expect_no_shot("friendly units are not acquired when friendly fire is off")
	target.Team = "Team1"
	target.remove_from_group("Ball")
	expect_no_shot("no eligible enemy means no drawing or firing")
	target.add_to_group("Ball")

	wall.collision_layer = 0
	await physics_frame
	await process_frame
	check(TERRAIN.terrain(bow, bow.global_position, target.global_position).is_empty(), "control: removing the terrain layer clears the line of sight")
	reset_draw()
	var before: int = _bolts().size()
	bow.step_mob(float(bow.draw_time) + 0.01)
	check(_bolts().size() == before + 1, "unobstructed targeting and firing still work")
	for bolt: Node in _bolts():
		bolt.set_physics_process(false)
	print("HEAVENFALL WALL TARGETING RESULT: %d/%d passed" % [checks - failures, checks])
	finish(0 if failures == 0 else 1)
