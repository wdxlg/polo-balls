extends "res://tests/test_mc_bat.gd"
func run() -> void:
	game = root.get_node("Game")
	BAT = load("res://scripts/characters/我的世界/bat/bat.gd")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(60.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.5).timeout
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var enemy:Node2D = spawn("res://scenes/ball.tscn",center,"Team1")
	enemy.Has_Collision_Damage = false
	enemy.self_hitbox.monitoring = false
	enemy.state_machine.set_physics_process(false)
	enemy.Max_health = 100000
	enemy.default_properties["Max_health"] = 100000
	enemy.health = 100000
	var swarm:Node2D = spawn(BAT.SCENE_PATH,center+Vector2(-40,0))
	# Deterministic encounter fixture: keep the leader headed toward the nearby enemy
	# during its normal initial cooldown instead of randomly leaving the 45-unit range.
	swarm.direction = Vector2.RIGHT
	var seen_fused:bool = false
	var seen_split:bool = false
	var seen_attachment:bool = false
	var moved:bool = false
	var origin:Vector2 = swarm.global_position
	var time:float = 0.0
	while time < 24.0:
		await create_timer(0.1).timeout
		time += 0.1
		if not is_instance_valid(swarm): break
		moved = moved or swarm.global_position.distance_to(origin) > 5.0
		for member:Node2D in swarm.living_members():
			seen_attachment = seen_attachment or member.attached_target() != null
		if swarm.vampire: seen_fused = true
		elif seen_fused: seen_split = true
	check(moved,"live state machine produces standard bat movement")
	check(seen_attachment,"live proximity detection approaches and attaches without scripted attack calls")
	check(enemy.health < 100000,"live bats damage nearby enemy")
	check(seen_fused,"12-second bat timer starts convergence and automatically fuses")
	check(seen_split,"real vampire timer automatically splits back")
	check(swarm.living_members().size() >= 5,"lifesteal growth is retained through the live cycle")
	check(world._collect_alive_victory_sides().size() == 2,"morphing swarm remains one side against its enemy")
	check(swarm.Max_health == swarm.default_properties.Max_health,"live capacity survives repeated World resets")
	print("LIVE SWARM: ",swarm.living_members().size()," bats; totals ",totals(swarm),"; enemy damage ",100000-enemy.health)
	finish(0 if failures == 0 else 1)
