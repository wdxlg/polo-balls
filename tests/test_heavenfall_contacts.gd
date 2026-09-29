extends "res://tests/test_mc_new6_load.gd"
# Reproduce characters that also occupy terrain layer 1, including large bodies.
# They must be hit once by arrows and must NEVER reflect the arrow or the rift.


func new_bolt(source: Node2D, point: Vector2) -> Node2D:
	var bolt: Node2D = load("res://scenes/shooter/我的世界/天陨箭矢.tscn").instantiate()
	world.add_child(bolt)
	bolt.global_position = point
	bolt.configure(source, source.Team, Vector2.RIGHT, 620.0, 10.0, 30.0, 0.0, 0.0, 5000.0, 1, 10.0, 4.0, 5.0, 0.38)
	bolt.set_physics_process(false)
	return bolt


func clear_projectiles() -> void:
	for node: Node in _bolts() + _rifts() + _falls():
		node.queue_free()
	await process_frame


func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0, true)
	create_timer(60.0, true, false, true).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world, CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	var center: Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var bow: Node2D = spawn("res://scenes/characters/我的世界/天堂陨落长弓.tscn", center + Vector2(-180, 90))
	bow.Can_Attack = true
	bow.state_machine.set_physics_process(false)
	var giant: Node2D = _mk_enemy(center + Vector2(80, 0))
	giant.get_node("CharacterAutoFit").set("enabled", false)
	giant.collision_shape_2d.set_meta("_character_auto_fit_v3_manual", true)
	giant.collision_layer = 3 # Deliberately overlaps terrain AND character layers.
	var big_shape := CircleShape2D.new()
	big_shape.radius = 300.0 # 60 world units at the character's 0.2 scale; > old 26px scan.
	giant.collision_shape_2d.shape = big_shape
	await physics_frame
	await process_frame
	check(is_equal_approx(bow.rift_length, 90.0), "default rift is shortened from 150 to 90")
	var path: PackedVector2Array = bow._build_rift_path(giant.global_position, Vector2.RIGHT)
	check(path.size() > 3 and path[0].is_equal_approx(giant.global_position), "character overlap cannot relocate the fracture center")
	check((path[path.size() - 1] - path[0]).dot(Vector2.RIGHT) > 35.0, "primary fracture keeps its intended local direction through a character")
	var arena: Rect2 = bow._heaven_arena_rect().grow(-bow.rift_safe_margin)
	var limb: PackedVector2Array = bow._grow_crack_limb(giant.global_position, Vector2.UP, 30.0, arena)
	check(limb.size() >= 3, "branches also ignore character terrain bodies")
	var hp: float = giant.health
	var bolt: Node2D = new_bolt(bow, center)
	bolt._physics_process(0.07)
	check(bolt._dead and bolt.is_queued_for_deletion(), "large-body contact consumes the arrow immediately")
	check(not bolt.has_pierced() and bolt._dir.x > 0.99, "hitting a person never counts as a pass-through or reverses the arrow")
	check(giant.health < hp, "large-body contact damages the victim even outside the old 26px allowance")
	var bolt_pushes:int = 0
	for effect:Node in giant.get_children():
		if effect.get_script() != null and str(effect.get_script().resource_path).ends_with("knockback_effect.gd"):
			bolt_pushes += 1
	check(bolt_pushes == 0 and giant.Repel.is_zero_approx(), "direct Heavenfall bolt damage does not push; only the arrival shockwave may push")
	check(_rifts().size() == 1 and _falls().size() == 1, "one person hit creates exactly one rift and one configured rain volley")
	if not _rifts().is_empty():
		var tear: Node2D = _rifts()[0]
		check((tear._points[tear._points.size() - 1] - tear._points[0]).x > 0.0, "impact rift points forward instead of bouncing back from the victim")
	else:
		check(false, "impact rift was created")
	await clear_projectiles()
	# A normal layer-2 victim must still work; the fix is not just a terrain exception.
	giant.collision_layer = 2
	giant.global_position = center + Vector2(80, 0)
	await physics_frame
	hp = giant.health
	bolt = new_bolt(bow, center)
	bolt._physics_process(0.07)
	check(bolt._dead and not bolt.has_pierced() and giant.health < hp, "ordinary layer-2 characters are terminal hits too")
	await clear_projectiles()
	# Friendly characters are not reflective obstacles when friendly fire is off.
	giant.collision_layer = 3
	giant.Team = bow.Team
	giant.global_position = center + Vector2(80, 0)
	await physics_frame
	hp = giant.health
	bolt = new_bolt(bow, center)
	bolt._physics_process(0.07)
	check(not bolt._dead and not bolt.has_pierced() and bolt._dir.x > 0.99, "friendly terrain-layer characters are passed through, not treated as obstacles")
	check(is_equal_approx(giant.health, hp), "friendly-fire rules remain intact")
	await clear_projectiles()
	# A real wall behind the skipped friendly body is passed through once instead of reflected.
	var wall: StaticBody2D = _mk_wall(center + Vector2(170, 0))
	await physics_frame
	bolt = new_bolt(bow, center)
	bolt._physics_process(0.3)
	check(bolt.has_pierced() and bolt._dir.x > 0.99 and not bolt._dead, "actual terrain behind a friendly character is passed through once instead of reflected")
	var wall_b: StaticBody2D = _mk_wall(center + Vector2(268, 0))
	await physics_frame
	for i in range(60):
		bolt._physics_process(1.0 / 60.0)
		if bolt.is_queued_for_deletion():
			break
	check(bolt.is_queued_for_deletion(), "a second wall still stops the arrow after its single pass-through")
	wall_b.queue_free()
	var reflected: PackedVector2Array = bow._build_rift_path(center + Vector2(130, 0), Vector2.RIGHT)
	check((reflected[reflected.size() - 1] - reflected[0]).x > 35.0, "fractures pass through real walls while arrows retain their own wall bounce")
	await clear_projectiles()
	# Stop at terrain before a small target behind it, not the target's proximity allowance.
	giant.Team = "Team1"
	giant.collision_layer = 2
	giant.global_position = center + Vector2(260, 0)
	var small_shape := CircleShape2D.new()
	small_shape.radius = 50.0
	giant.collision_shape_2d.shape = small_shape
	await physics_frame
	hp = giant.health
	bolt = new_bolt(bow, center)
	var inside_frames: int = 0
	for i in range(40):
		bolt._physics_process(1.0 / 60.0)
		if bolt.is_inside_obstacle():
			inside_frames += 1
		if bolt.has_pierced() and not bolt.is_inside_obstacle():
			break
	check(inside_frames >= 1 and not bolt._dead and is_equal_approx(giant.health, hp), "a wall hides targets while the arrow is still inside it instead of leaking a fallback hit")
	await clear_projectiles()
	bow.rng.seed = 912
	var crossing: PackedVector2Array = bow._build_rift_path(center + Vector2(150, 0), Vector2.RIGHT)
	var crossing_limbs: Array = bow._grow_rift_branches(crossing)
	wall.collision_layer = 0
	giant.collision_layer = 0
	await physics_frame
	bow.rng.seed = 912
	var clear_path: PackedVector2Array = bow._build_rift_path(center + Vector2(150, 0), Vector2.RIGHT)
	var clear_limbs: Array = bow._grow_rift_branches(clear_path)
	check(crossing == clear_path and crossing_limbs == clear_limbs, "seeded fracture geometry is identical with and without terrain/people")
	var edge_origin: Vector2 = Vector2(arena.end.x + bow.rift_safe_margin - 1.0, center.y)
	var edge_path: PackedVector2Array = bow._build_rift_path(edge_origin, Vector2.RIGHT)
	check(edge_path[0].is_equal_approx(edge_origin) and edge_path[edge_path.size()-1].x > edge_origin.x + 30.0, "map boundary does not move or reflect fracture geometry")
	var safe_anchor: Vector2 = bow._snap_rift_anchor(edge_path)
	check(arena.has_point(safe_anchor) and bow._heaven_body_clear(safe_anchor), "terrain-independent visuals still choose a safe in-arena dodge landing")
	var centered:bool=true
	var enough_roots:bool=true
	for seed_value in range(64):
		bow.rng.seed=seed_value+100
		var origin:Vector2=center+Vector2(13,-7)
		var primary:PackedVector2Array=bow._build_rift_path(origin,Vector2.RIGHT.rotated(float(seed_value)*0.37))
		var limbs:Array=bow._grow_rift_branches(primary)
		centered=centered and primary[0].is_equal_approx(origin)
		var root_count:int=1
		for branch_path:PackedVector2Array in limbs:
			if branch_path[0].is_equal_approx(origin):root_count+=1
		enough_roots=enough_roots and root_count>=4 and root_count<=6
	check(centered,"64 seeds keep the connecting opening at the exact impact point")
	check(enough_roots,"all generated major arms attach to the central connecting region")
	wall.queue_free()
	giant.queue_free()
	bow.queue_free()
	await process_frame
	print("HEAVENFALL CONTACT RESULT: %d/%d passed" % [checks - failures, checks])
	finish(0 if failures == 0 else 1)
