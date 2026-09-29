extends "res://tests/test_mc_bat.gd"
func setup_world() -> Vector2:
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
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	return world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
func pump_gather(unit:Node2D,frames:int = 240) -> void:
	for i:int in range(frames):
		if not bool(unit.cohort.get("gathering",false)): break
		for member:Node2D in unit.living_members():
			if not member.is_queued_for_deletion(): member.tick_physics(0,1.0/60.0)
		await physics_frame
		await process_frame
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(60.0).timeout.connect(func(): finish(2))
	var b:Node2D = spawn(BAT.SCENE_PATH,center)
	b.state_machine.set_physics_process(false)
	var enemy:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(-60,0),"Team1")
	enemy.state_machine.set_physics_process(false)
	enemy.Has_Collision_Damage = false
	enemy.self_hitbox.monitoring = false
	enemy.Max_health = 10000
	enemy.default_properties.Max_health = 10000
	enemy.health = 10000
	await physics_frame
	await process_frame
	pause_members(b)
	var index:int = 0
	for member:Node2D in b.living_members():
		member.global_position = center+Vector2(-120+index*60,0)
		index += 1
	var initial:Vector2i = totals(b)
	b.fuse_swarm()
	check(not b.vampire and b.living_members().size() == 5 and b.cohort.gathering,"fusion starts with five live converging bats, never an instant replacement")
	check(get_nodes_in_group("MCBatTransformFX").is_empty(),"no explosion before the bats arrive")
	check(b.cohort.gather_point.distance_to(center) < 0.01,"all bats share one fixed gathering point")
	check(not b.feeding_guard_active() and b.attached_target() == null,"gathering cancels feeding rather than retaining 75 percent protection")
	game.now_stop_state = true
	var position_before:Vector2 = b.global_position
	var time_before:float = b.cohort.gather_elapsed
	b.tick_physics(0,1.0)
	check(b.global_position == position_before and b.cohort.gather_elapsed == time_before,"pause freezes convergence movement and timer")
	game.now_stop_state = false
	b.tick_physics(0,1.0/60.0)
	check(b.global_position.distance_to(center) < position_before.distance_to(center) and not b.vampire,"bat physically advances toward the merge point")
	check(b.get_debug_attack_regions().size() == 1,"convergence collision attack exposes its real body geometry")
	await pump_gather(b)
	check(b.vampire and not b.cohort.gathering and b.living_members().size() == 1,"all living bats arrive before one vampire appears")
	check(b.global_position.distance_to(center) < 0.01,"vampire appears at the common convergence point")
	check(totals(b) == initial,"convergence conserves HP and maximum HP without granting collision lifesteal")
	check(enemy.health < 10000 and enemy.health >= 9990,"swept convergence bodies damage crossed enemy, bounded to one hit per bat")
	check(b.collision_mask == 3,"normal terrain and actor collision mask is restored after fusion")
	check(get_nodes_in_group("MCBatTransformFX").size() == 1,"whole swarm emits exactly one transformation effect")
	var fx:Node2D = get_nodes_in_group("MCBatTransformFX")[0]
	fx.set_process(false)
	var bursts:int = 0
	var smokes:int = 0
	for part:Dictionary in fx.particles:
		if part.smoke: smokes += 1
		else: bursts += 1
	check(bursts == 1 and smokes == 16,"effect has one circular explosion plus sixteen smoke particles")
	check(fx.particles[0].position3 == Vector3.ZERO and fx.particles[0].delay == 0.0,"single explosion is centered and starts immediately")
	var smoke:Dictionary = fx.particles[1]
	var smoke_start:Vector3 = smoke.position3
	var smoke_texture:Texture2D = smoke.sprite.texture
	fx.advance_visual(0.3)
	check(smoke.position3.distance_to(smoke_start) > 1.0,"smoke visibly scatters outward rather than remaining a stationary puff")
	check(smoke.sprite.texture != smoke_texture,"smoke also advances through its native particle frames")
	var sounds:Array = get_nodes_in_group("MCNativeSFX").filter(func(n:Node): return n.get_meta("mc_sound_event","") == "entity.breeze.deflect")
	check(not sounds.is_empty(),"fusion plays a real Breeze deflect sound")
	check(BAT.BAT_AUDIO.EVENTS["entity.breeze.deflect"].size() == 3,"all three original Breeze deflect variants are available for random selection")
	check(not b.try_complete_gather() and get_nodes_in_group("MCBatTransformFX").size() == 1,"repeated completion checks cannot duplicate explosion")
	await create_timer(0.12).timeout
	var before_split:Vector2i = totals(b)
	b.split_swarm()
	pause_members(b)
	check(not b.vampire and totals(b) == before_split,"reverse transformation retains split HP conservation")
	check(get_nodes_in_group("MCBatTransformFX").size() == 2,"reverse transformation emits one additional effect, not one per spawned bat")
	var reverse:Node2D = get_nodes_in_group("MCBatTransformFX")[1]
	reverse.set_process(false)
	check(not reverse.get_meta("bat_to_vampire") and reverse.explosion_count == 1 and reverse.smoke_count == 16,"both transformation directions use the identical single-burst smoke effect")
	sounds = get_nodes_in_group("MCNativeSFX").filter(func(n:Node): return n.get_meta("mc_sound_event","") == "entity.breeze.deflect")
	check(not sounds.is_empty(),"reverse transformation also plays Breeze deflect")
	fx.advance_visual(2.0)
	reverse.advance_visual(2.0)
	await process_frame
	check(get_nodes_in_group("MCBatTransformFX").is_empty(),"all completed transformation particles are freed")
	# A finite wall must be routed around; no direct teleport across terrain.
	enemy.global_position = center+Vector2(0,180)
	var barrier := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10,70)
	collision.shape = rect
	barrier.add_child(collision)
	world.add_child(barrier)
	barrier.global_position = center+Vector2(-40,0)
	index = 0
	for member:Node2D in b.living_members():
		member.global_position = center+Vector2([-100,-80,40,60,80][index],0)
		index += 1
	await physics_frame
	await process_frame
	b.fuse_swarm()
	var route:Array = BAT.GATHER_NAV.route(b,b.global_position,b.cohort.gather_point)
	check(route.size() > 1,"blocked convergence finds terrain waypoints instead of a through-wall line")
	await pump_gather(b)
	if not b.vampire:
		for member:Node2D in b.living_members(): print("GATHER_STUCK ",member.global_position-center," path ",member._gather_path," time ",member.cohort.gather_elapsed)
	check(b.vampire,"convergence can complete around a finite terrain obstacle")
	barrier.queue_free()
	await process_frame
	b.split_swarm()
	pause_members(b)
	# Leader can be killed en route; surviving cohort takes over without phantom HP.
	index = 0
	for member:Node2D in b.living_members():
		member.global_position = center+Vector2(-100+index*50,90)
		index += 1
	b.fuse_swarm()
	b.health = 0
	var survivor:Node2D = b.living_members()[0]
	var remaining:Vector2i = totals(survivor)
	await pump_gather(survivor)
	check(survivor.vampire and totals(survivor) == remaining,"leader death mid-convergence preserves survivors and excludes dead HP from fusion")
	survivor.split_swarm()
	pause_members(survivor)
	index = 0
	for member:Node2D in survivor.living_members():
		member.global_position = center+Vector2(-100+index*50,-90)
		index += 1
	survivor.fuse_swarm()
	survivor.cohort.gather_elapsed = 20.0
	survivor.cohort.gather_frame = -1
	var conserved:Vector2i = totals(survivor)
	survivor.tick_physics(0,0.1)
	check(not survivor.vampire and not survivor.cohort.gathering and totals(survivor) == conserved,"unreachable/expired gathering cancels without teleporting or losing health")
	check(survivor.collision_mask == 3,"cancelled convergence restores normal collisions")
	finish(0 if failures == 0 else 1)
