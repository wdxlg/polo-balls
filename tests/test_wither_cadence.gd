extends "res://scripts/training/test_mc_new5.gd"
## Real World fixture: three independent skull clocks, shared shot gap,
## faster poppies, and one consistent awakening damage/visual/threat radius.

func check(ok:bool,label:String) -> void:
	super.check(ok,label)
	if ok: print("PASS: "+label)

func _step(actor:Node2D,dt:float) -> void:
	actor.tick_physics(actor.State.Stand,dt)

func _skulls() -> Array[Node2D]:
	var found:Array[Node2D] = []
	for node:Node in get_nodes_in_group("AI_Hazard"):
		if not node.is_queued_for_deletion() and node.get_script() != null and node.get_script().resource_path.ends_with("/wither/skull.gd"):
			found.append(node as Node2D)
	return found

func _flowers(source:Node2D) -> Array[Node2D]:
	var found:Array[Node2D] = []
	for node:Node in get_nodes_in_group("WitherFlower"):
		if node.is_queued_for_deletion(): continue
		var ref:Variant = node.get("source_ref")
		if ref is WeakRef and ref.get_ref() == source: found.append(node as Node2D)
	return found

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(45.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.5).timeout
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"resources finish loading")
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	await clear_units()
	var wither:Node2D = spawn("凋灵",Vector2.ZERO,"Team0")
	var enemy:Node2D = spawn("",Vector2(230,0),"Team1")
	enemy.Max_health = 5000.0
	enemy.health = 5000.0
	enemy.Damage_reduction = 0.0
	enemy.block = 0
	check(wither.skull_interval == 3.0 and wither.skull_global_cooldown == 0.45 and wither.rose_interval == 4.0 and wither._rose_left == 4.0,"new attack and initial flower timings are active in the scene")
	wither.summoned = true
	wither._head_shot_left.fill(0.0)
	wither._rose_left = 999.0
	wither._charge_left = 999.0
	_step(wither,0.01)
	check(wither._windup_head == 0 and _skulls().is_empty(),"first ready head winds up without firing early")
	_step(wither,0.31)
	check(_skulls().size() == 1 and wither._head_shot_left[0] == 3.0 and wither._head_shot_left[1] == 0.0 and wither._head_shot_left[2] == 0.0,"central head fires and only its personal clock resets")
	check(_skulls().back().global_position.distance_to(wither.head_muzzle_world_position(0)) < 0.5,"first projectile leaves the central head's live muzzle")
	check(is_equal_approx(wither._global_shot_left,0.45),"shared cooldown starts when the projectile is actually fired")
	_step(wither,0.20)
	check(_skulls().size() == 1 and wither._windup_head == -1 and wither._global_shot_left > 0.0,"ready side heads cannot start inside the shared cooldown")
	_step(wither,0.26)
	check(wither._windup_head == 1 and _skulls().size() == 1,"left head may wind up as soon as the shared gap ends")
	_step(wither,0.31)
	check(_skulls().size() == 2 and wither._head_shot_left[0] > 0.0 and wither._head_shot_left[1] == 3.0 and wither._head_shot_left[2] == 0.0,"left head fires while the central head still cools")
	check(_skulls().back().global_position.distance_to(wither.head_muzzle_world_position(2)) < 0.5,"left projectile leaves the left head's live muzzle")
	_step(wither,0.46)
	check(wither._windup_head == 2,"right head is not blocked by the other two head cooldowns")
	_step(wither,0.31)
	check(_skulls().size() == 3 and wither._next_shoot_head == 0 and wither._head_shot_left[2] == 3.0,"three distinct heads fire in under two seconds, then wrap")
	check(_skulls().back().global_position.distance_to(wither.head_muzzle_world_position(1)) < 0.5,"right projectile leaves the right head's live muzzle")
	_step(wither,1.50)
	check(wither._windup_head == 0 and wither._head_shot_left[1] > 0.0 and wither._head_shot_left[2] > 0.0,"central head becomes ready again before either side head")
	_step(wither,0.31)
	check(_skulls().size() == 4 and wither._head_shot_left[1] > 0.0 and wither._head_shot_left[2] > 0.0,"head 0 fires a second time without resetting the other clocks")
	wither._global_shot_left = 0.0
	wither._head_shot_left[1] = 0.0
	_step(wither,0.01)
	check(wither._windup_head == 1,"head 1 begins another windup")
	enemy.health = 0.0
	_step(wither,0.31)
	check(wither._windup_head == -1 and wither._windup == 0.0 and wither._head_shot_left[1] == 0.0 and wither._global_shot_left == 0.0 and _skulls().size() == 4,"losing the target cancels windup without consuming either cooldown")
	enemy.health = 5000.0
	_step(wither,0.01)
	_step(wither,0.31)
	check(_skulls().size() == 5,"a cancelled head can retry and fire once a target returns")
	var before_pause:float = wither._head_shot_left[1]
	game.now_stop_state = true
	_step(wither,0.80)
	check(is_equal_approx(wither._head_shot_left[1],before_pause),"pause freezes the independent timers")
	game.now_stop_state = false
	wither.apply_beacon_buff("haste")
	wither._head_shot_left.fill(0.0)
	wither._global_shot_left = 0.0
	wither._next_shoot_head = 2
	_step(wither,0.01)
	_step(wither,0.31)
	var haste_rate:float = float(load("res://scripts/effects/我的世界/mc_status_effects.gd").properties("haste",1).attack_rate)
	check(_skulls().size() == 6 and is_equal_approx(wither._head_shot_left[2],wither.skull_interval/haste_rate) and wither._head_shot_left[2] < wither.skull_interval,"haste shortens only the head that just fired")
	check(wither._head_shot_left[0] == 0.0 and wither._head_shot_left[1] == 0.0 and is_equal_approx(wither._global_shot_left,0.45),"haste does not consume the other heads or the shared gap")
	wither._head_shot_left.fill(999.0)
	wither._global_shot_left = 999.0
	wither._rose_left = wither.rose_interval
	_step(wither,3.95)
	check(_flowers(wither).is_empty(),"first poppy does not appear before four seconds")
	_step(wither,0.06)
	check(_flowers(wither).size() == 1 and not _flowers(wither)[0].withered and _flowers(wither)[0].life == 12.0,"first ordinary poppy grows at the new four-second interval")
	_step(wither,4.0)
	_step(wither,4.0)
	check(_flowers(wither).size() == 3,"four-second cycles fill the existing three-flower cap")
	_step(wither,4.0)
	check(_flowers(wither).size() == 3,"faster cycles still respect the three-flower cap")
	_flowers(wither)[0].queue_free()
	_step(wither,4.0)
	check(_flowers(wither).size() == 3,"a queued/expired flower can be replaced on the next cycle")
	wither.summoned = false
	wither.summon_time = wither.summon_duration-0.2
	var threats:Array = wither.get_ai_attack_threats(enemy)
	check(threats.size() == 1 and threats[0].radius == 72.0 and threats[0].damage == 45.0,"awakening warning uses the actual smaller 72-radius damage area")
	var before_visuals:int = get_nodes_in_group("MCExplosion").size()
	wither._sync_event("awake",wither.global_position)
	var synced_visuals:Array = get_nodes_in_group("MCExplosion")
	check(synced_visuals.size() == before_visuals+1 and synced_visuals.back().radius == 72.0,"remote awakening renders the shared smaller explosion")
	# 105 is within the former 110-radius blast, but outside 72 plus this
	# target's collision allowance. An unchanged damage radius would fail.
	var old_only_distance:float = 105.0
	check(old_only_distance > 72.0+enemy.get_crowd_separation_radius_world() and old_only_distance < 110.0+enemy.get_crowd_separation_radius_world(),"far target separates the old and new blast reach")
	enemy.global_position = wither.global_position+Vector2(old_only_distance,0)
	var before_far:float = enemy.health
	wither._blast(wither.global_position,wither.AWAKENING_BLAST_RADIUS,45.0,null,false)
	check(is_equal_approx(enemy.health,before_far),"an enemy outside the reduced blast takes no damage")
	enemy.global_position = wither.global_position+Vector2(45,0)
	var before_near:float = enemy.health
	_step(wither,0.20)
	var local_visuals:Array = get_nodes_in_group("MCExplosion")
	check(wither.summoned and is_equal_approx(before_near-enemy.health,45.0),"the actual awakening blast still hits a nearby enemy once for 45")
	check(local_visuals.size() == before_visuals+2 and local_visuals.back().radius == 72.0,"host awakening visual matches its authority damage and the threat circle")
	await clear_units()
	finish(0 if failures == 0 else 1)
