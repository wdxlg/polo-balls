extends "res://scripts/training/test_mc_new5.gd"
## Real World physics: charge through props/actors to the current map edge.
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(90.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.5).timeout
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	await clear_units()
	var wither:Node2D = spawn("凋灵",Vector2(-240,0),"Team0")
	var enemy:Node2D = spawn("",Vector2(165,0),"Team1")
	enemy.Max_health = 1000.0
	enemy.health = 1000.0
	enemy.Damage_reduction = 0.0
	enemy.block = 0
	wither.summoned = true
	wither._head_shot_left.fill(999.0)
	wither._global_shot_left = 999.0
	wither._charge_left = 999.0
	var crate:StaticBody2D = obstacle(Vector2(-145,0),true)
	var second:StaticBody2D = obstacle(Vector2(15,0),false)
	var off_path:StaticBody2D = obstacle(Vector2(-145,190),false)
	var stone:StaticBody2D = load("res://scenes/characters/默认/石头.tscn").instantiate() as StaticBody2D
	world.add_child(stone,true)
	stone.global_position = center+Vector2(-95,0)
	var layer:TileMapLayer = world._current_map_node() as TileMapLayer
	var initial_visible:bool = layer.visible
	var initial_collision:bool = layer.collision_enabled
	var cell:Vector2i = layer.local_to_map(layer.to_local(center+Vector2(75,0)))
	var floor_data:Array = [layer.get_cell_source_id(cell),layer.get_cell_atlas_coords(cell),layer.get_cell_alternative_tile(cell)]
	layer.visible = true
	layer.collision_enabled = true
	layer.set_cell(cell,0,Vector2i(0,0),0)
	layer.update_internals()
	# A BuilderWall is a ball, not StaticBody2D: it must also be smashed.
	var builder:Node2D = spawn("",Vector2(-15,0),"Team1")
	builder.add_to_group("BuilderWall")
	builder.Max_health = 3000.0
	builder.health = 3000.0
	var boundary:StaticBody2D = obstacle(Vector2(300,0),true,true)
	await physics_frame
	var start:Vector2 = wither.global_position
	var expected:float = wither._charge_wall_distance(start,Vector2.RIGHT)
	check(expected > 130.0,"rightward charge reaches the map edge instead of old 130-unit limit")
	wither._charge_dir = Vector2.RIGHT
	wither._charge_windup = 0.01
	wither.tick_physics(wither.State.Move,0.02)
	var before:float = enemy.health
	var warnings:Array = wither.get_ai_attack_threats(enemy)
	check(not warnings.is_empty() and warnings[0].end.distance_to(start+Vector2.RIGHT*expected)<0.01,"visible danger segment reaches exactly the actual wall endpoint")
	check(is_equal_approx(wither.CHARGE_SPEED,325.0),"charge base speed is 65 percent of previous 500")
	wither.tick_physics(wither.State.Move,350.0/(325.0*1.55))
	check(is_equal_approx(wither.global_position.x-start.x,350.0),"actual initial charge displacement uses reduced speed curve")
	var particles:Array[Node] = get_nodes_in_group("MCSmokeTrail")
	check(not particles.is_empty(),"charge movement emits native smoke particles")
	for particle:Node in particles:
		check(particle.global_position.x < wither.global_position.x,"smoke is behind the moving body")
		check(particle.texture == wither.CHARGE_SMOKE,"smoke uses original Minecraft texture")
		particle.set_process(false)
		var age:float = particle._age
		game.now_stop_state = true
		particle._process(0.1)
		check(is_equal_approx(particle._age,age),"smoke freezes during game pause")
		game.now_stop_state = false
		particle._process(0.7)
		check(particle.is_queued_for_deletion(),"smoke expires after its lifetime")
	check(wither.global_position.x > second.global_position.x,"charge crosses both colliding props without sliding or stopping")
	check(not crate.visible and not second.visible,"every in-path static obstacle shatters on first contact")
	check(not is_instance_valid(stone) or stone.is_queued_for_deletion(),"placed stone immune to Ghast blasts is also destroyed by Wither charge")
	check(off_path.visible and off_path.collision_layer == 1,"obstacle outside swept body is preserved")
	var terrain:Node = world.get_node("GhastObstacleDamage")
	check(not terrain.colliding(layer.get_cell_tile_data(cell),layer.tile_set),"colliding map tile in the charge corridor becomes traversable floor")
	check(builder.health <= 0.0,"ball-based builder wall is destroyed instead of stopping the charge")
	for i:int in range(40):
		if wither._charge_remaining <= 0.0: break
		wither.tick_physics(wither.State.Move,0.4)
	check(is_equal_approx(before-enemy.health,80.0),"charge damages a crossed enemy once, even behind destroyed props")
	check(wither._charge_remaining <= 0.0 and absf(wither.global_position.x-start.x-expected)<0.1,"charge stops at the current map wall with body clearance")
	check(boundary.visible and boundary.collision_layer == 1,"map boundary survives the whole pass")
	check(wither.get_ai_attack_threats(enemy).is_empty(),"damage segment disappears at the actual stop")
	# Changing heading must end at the first axis reached, not at the far
	# corner of a bounding box or at a fixed travel distance.
	wither.global_position = center+Vector2(-190,-70)
	var diagonal:Vector2 = Vector2(1.0,0.35).normalized()
	var diagonal_start:Vector2 = wither.global_position
	var diagonal_length:float = wither._charge_wall_distance(diagonal_start,diagonal)
	wither._charge_dir = diagonal
	wither._charge_remaining = diagonal_length
	wither._charge_hits.clear()
	wither._charge_broken.clear()
	for i:int in range(40):
		if wither._charge_remaining <= 0.0: break
		wither.tick_physics(wither.State.Move,0.4)
	check(wither.global_position.distance_to(diagonal_start+diagonal*diagonal_length)<0.1,"diagonal charge clips to the first map wall without tunneling outside")
	# The normal AI/cooldown path must enter the same full-length charge,
	# not just the test's direct windup injection above.
	wither.global_position = center+Vector2(-180,0)
	enemy.global_position = wither.global_position+Vector2(110,0)
	wither._charge_left = 0.0
	wither.tick_physics(wither.State.Move,0.016)
	check(wither._charge_windup > 0.0 and wither._charge_dir.x > 0.9,"real cooldown and nearby target schedule the wall-bound charge")
	await physics_frame # Drain the engine's deferred collision-layer writes.
	# A real rematch/reset, not a manual manager.reset_all(), must restore
	# persistent terrain without touching the indestructible map boundary.
	world.reset()
	await process_frame
	await physics_frame
	check(crate.visible and second.visible and crate.collision_layer == 1,"battle reset restores charge-shattered persistent props")
	check(layer.get_cell_atlas_coords(cell) == Vector2i(0,0),"battle reset restores the mined collision tile")
	layer.set_cell(cell,floor_data[0],floor_data[1],floor_data[2])
	layer.collision_enabled = initial_collision
	layer.visible = initial_visible
	await clear_units()
	print("WITHER_DASH_SMOKE failures=",failures)
	finish(0 if failures == 0 else 1)
