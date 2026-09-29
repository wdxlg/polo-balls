extends "res://tests/test_mc_frontier.gd"
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(65.0).timeout.connect(func(): finish(2))
	var moss:Node2D = actor("苔藓",center)
	var origin:Vector2 = Vector2(moss.cell_at(center))*moss.CELL
	moss.global_position = origin
	var target:Node2D = dummy(origin+Vector2(200,0))
	var friend:Node2D = dummy(origin+Vector2(200,100),"Team0")
	await physics_frame
	moss.rng.seed = 317
	moss.growth_left = 0.0
	check(moss.cultivate() and moss.patches.is_empty(),"cultivation starts before actual placement")
	complete_moss_growth(moss)
	check(moss.patches.size() == 6,"six unique random growth cells")
	var seen:Dictionary = {}
	for patch:Dictionary in moss.patches:
		var offset:Vector2i = moss.cell_at(patch.point)-moss.cell_at(origin)
		check(absi(offset.x)<=2 and absi(offset.y)<=2 and not seen.has(patch.point) and patch.layers==1,"growth stays within centered 5x5 and never selects a cell twice")
		seen[patch.point] = true
	moss.patches.clear()
	for x:int in range(-2,3):
		for y:int in range(-2,3):
			for layer:int in range(3): moss.plant(origin+Vector2(x,y)*24.0)
	check(moss.patches.size()==25,"all 25 valid cells can fill, no obsolete twelve-cell cap")
	moss.growth_left = 0.0
	check(not moss.cultivate(),"fully saturated 5x5 cannot grow")
	var tile:Vector2 = origin+Vector2(24,0)
	var patch:Dictionary = moss.patch_at(tile)
	patch.layers = 2
	moss.growth_left = 0.0
	check(moss.cultivate() and patch.layers==2,"stacking also waits for rebound")
	complete_moss_growth(moss)
	check(patch.layers==3 and moss.patches.size()==25,"only remaining eligible cell gets one layer, full cells are skipped")
	check(not moss.plant(origin+Vector2(72,0)),"plant rejects outside 5x5")
	moss.patches.clear()
	moss.plant(tile)
	target.global_position = tile
	friend.global_position = tile
	var friendly_hp:int = friend.health
	for layers:int in range(1,4):
		moss.patch_at(tile).layers = layers
		moss.clock += 1.01
		var hp:int = target.health
		moss.check_trampling()
		check(target.health==hp-10*layers,"continuous damage scales with layer count "+str(layers))
		moss.check_trampling()
		check(target.health==hp-10*layers and moss.patch_at(tile).layers==layers,"same-window damage is debounced and does not consume layers")
	check(friend.health==friendly_hp,"friendly units are not damaged")
	check(moss.slow_ratio(1)>moss.slow_ratio(2) and moss.slow_ratio(2)>moss.slow_ratio(3),"more layers mean stronger slowing")
	target.global_position = origin+Vector2(200,0)
	var hp:int = target.health
	moss.clock += 2.0
	moss.check_trampling()
	check(target.health==hp,"leaving moss stops damage")
	moss.global_position = tile
	moss.health = 300
	moss.growth_left = 999.0
	moss.step_mob(1.01)
	check(moss.health==306,"self heals on moss")
	moss.global_position = origin
	moss.step_mob(1.01)
	check(moss.health==306,"self does not heal off moss")
	check(moss.U.trace(moss,tile-Vector2(11,0),tile+Vector2(11,0)).is_empty(),"moss has no physical collision")
	moss.patches.clear()
	moss.plant(origin)
	moss.plant(origin+Vector2(24,24))
	target.global_position = origin+Vector2(24,24)
	check(not moss.begin_burrow(),"diagonal-only adjacency cannot trigger burrow")
	moss.plant(origin+Vector2(24,0))
	moss.plant(origin+Vector2(24,24))
	check(moss.begin_burrow(),"orthogonal connecting tile enables burrow")
	var destination:Vector2 = moss.burrow_destination
	check(destination==target.global_position and not moss.finish_burrow(),"destination is captured at entry and emergence cannot happen early")
	var collision_before:int = moss._saved_collision_layer
	check(moss.collision_layer==0 and moss.collision_mask==0,"burrow disables physical body collision temporarily")
	moss.direction = Vector2.RIGHT
	moss.move(100,0.1)
	check(moss.global_position==origin,"underground character cannot walk away")
	var pending:float = moss.burrow_left
	game.now_stop_state = true
	moss.tick_physics(0,2.0)
	check(moss.burrow_left==pending and moss.burrowing,"pause freezes burrow countdown")
	game.now_stop_state = false
	target.global_position = origin+Vector2(200,0)
	hp = target.health
	moss.burrow_left = 0.0
	check(moss.finish_burrow() and moss.global_position==destination,"emerges at old enemy cell rather than chasing")
	check(target.health==hp and moss.patch_at(destination).layers==1,"moving away evades emergence and exactly one exit layer is consumed")
	check(moss.collision_layer==collision_before and not moss.burrowing,"emergence restores body collision")
	check(not moss.finish_burrow() and moss.patch_at(destination).layers==1,"duplicate resolution cannot consume extra layers")
	check(not moss.begin_burrow(),"burrow cooldown cannot be bypassed")
	moss.global_position = origin
	moss.plant(origin)
	moss.plant(origin+Vector2(24,0))
	target.global_position = destination
	friend.global_position = destination
	moss.burrow_wait = 0.0
	check(moss.begin_burrow(),"second valid cast starts after cooldown")
	moss.burrow_left = 0.0
	hp = target.health
	friendly_hp = friend.health
	check(moss.finish_burrow() and target.health==hp-60,"emergence deals sixty base damage to enemy at exit")
	check(friend.health==friendly_hp and moss.patch_at(destination).is_empty(),"friendly spared and final exit layer disappears")
	var has_knockback:bool = false
	for child:Node in target.get_children():
		if child.has_method("is_active_effect") and child.is_active_effect(): has_knockback = true
	check(has_knockback,"emergence uses shared knockback controller")
	moss.global_position = origin
	moss.plant(origin)
	moss.plant(origin+Vector2(24,0))
	moss.plant(destination)
	moss.burrow_wait = 0.0
	check(moss.begin_burrow(),"destructible-exit fixture enters burrow")
	var manager:Node = load("res://scripts/effects/我的世界/ghast_obstacle_damage.gd").ensure(moss)
	var updates:Array = manager.collect_blast(moss,destination,1.0)
	check(not updates.is_empty(),"blast detects non-colliding moss obstacles")
	manager.apply_updates(updates)
	check(moss.patch_at(destination).is_empty(),"single explosion clears entire exit cell")
	moss.burrow_left = 0.0
	check(not moss.finish_burrow() and moss.global_position==origin and not moss.burrowing,"destroyed exit cancels safely at origin")
	moss.plant(destination)
	manager.apply_updates(updates)
	check(not moss.patch_at(destination).is_empty(),"stale repeated explosion cannot destroy newly planted replacement")
	moss.burrow_wait = 0.0
	check(moss.begin_burrow(),"stun fixture enters burrow")
	moss.dizziness = true
	moss.step_mob(0.1)
	check(not moss.burrowing and moss.global_position==origin and moss.collision_layer==collision_before,"stun cancels pending ambush and restores body")
	moss.dizziness = false
	var snapshot:Dictionary = moss.visual_state()
	var mirror:Node2D = actor("苔藓",origin+Vector2(300,100))
	mirror.accept_visual(snapshot)
	check(mirror.patches==moss.patches and mirror.burrow_destination==moss.burrow_destination,"network snapshot carries layer counts and locked destination")
	mirror.patches.clear()
	var ghast:Node2D = actor("恶魂",origin+Vector2(-180,0),"Team1")
	moss.plant(destination)
	moss.plant(destination)
	var shot:Node2D = ghast.fire_at(destination)
	check(is_instance_valid(shot),"actual ghast creates fireball")
	if is_instance_valid(shot):
		shot.state_machine.set_physics_process(false)
		shot.global_position = destination
		shot.explode()
		check(moss.patch_at(destination).is_empty(),"actual ghast explosion destroys all three moss layers")
	print("MOSS CONTRACTS: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
