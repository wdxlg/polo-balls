extends "res://scripts/training/test_mc_new5.gd"
func broken_pair(offset:Vector2 = Vector2.ZERO) -> Array:
	var sword:Node2D = spawn("木剑",offset)
	sword.spend_durability(50)
	await process_frame
	await process_frame
	var bench:Node2D = sword.workbench
	bench.set_physics_process(false)
	var blade:Node2D
	for part:Node2D in bench.living_pieces():
		part.state_machine.set_physics_process(false)
		part.dock_delay = 0.0
		if part != sword: blade = part
	return [sword,blade,bench]
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(110).timeout.connect(func():finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.5).timeout
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var sword:Node2D = spawn("木剑",Vector2.ZERO)
	check(sword.durability == 45,"new sword has 45 durability")
	for amount:float in [1,4,5,6,9,10,11,15,20,21,25,200]:
		sword.set_migrated_health(600,600)
		sword.durability = 45
		sword.brace_left = 0
		sword.block = 0
		sword.take_damage(amount,true)
		check(sword.durability == 45-clampi(int(ceil(amount/5.0)),1,5),"actual damage durability tier "+str(amount))
	sword.set_migrated_health(600,600)
	sword.durability = 45
	sword.max_block = 100
	sword.block = 100
	sword.take_damage(10)
	check(sword.durability == 45,"fully shielded hit does not spend actual-health durability")
	sword.block = 0
	sword.brace_left = 0.4
	sword.take_damage(100)
	check(sword.durability == 40,"brace costs only actual-damage tier, not duplicate absorbed-damage costs")
	sword.brace_left = 0
	sword.riposte_left = 0
	sword.durability = 45
	sword.sword_charge = 1
	check(sword.begin_swing(),"empty swing begins")
	check(sword.durability == 44,"empty attack spends one")
	sword.swing_left = 0
	check(sword.resolve_swing() == 0,"empty attack misses")
	check(sword.durability == 44,"resolution does not spend again")
	var targets:Array[Node2D] = []
	for offset:Vector2 in [Vector2(30,0),Vector2(40,5),Vector2(45,-5)]:
		var victim:Node2D = spawn("",offset,"Team1")
		victim.Max_health = 10000
		victim.health = 10000
		targets.append(victim)
	sword.sword_charge = 1
	sword.swing_cooldown = 0
	check(sword.begin_swing(),"sweep begins")
	sword.swing_left = 0
	check(sword.resolve_swing() == 3,"sweep can hit three enemies")
	check(sword.durability == 43,"multi-target attack still costs only one")
	sword.sword_charge = 1
	sword.swing_cooldown = 0
	sword.durability = 1
	check(sword.begin_swing(),"last durability attack begins")
	check(sword.part_kind == 0,"last swing is not replaced before its hit")
	sword.swing_left = 0
	check(sword.resolve_swing() > 0,"last durability attack still hits")
	await process_frame
	await process_frame
	check(sword.part_kind == 1,"original actor becomes independently living hilt")
	var bench:Node2D = sword.workbench
	bench.set_physics_process(false)
	check(bench.living_pieces().size() == 2,"exactly two live pieces")
	check(bench.global_position.distance_to(center)<0.01,"workbench stays at break origin")
	check(bench.get_parent().name == "MCLocalEffects","bench avoids multiplayer spawn root")
	var blade:Node2D
	for part:Node2D in bench.living_pieces():
		part.state_machine.set_physics_process(false)
		part.dock_delay = 0
		if part != sword: blade = part
	check(blade.part_kind == 2 and blade.Team == sword.Team,"blade has independent ball identity and inherited team")
	check(sword.Max_health == 300 and blade.Max_health == 300,"split max health is conserved")
	check(sword.health+blade.health == 565,"split current health conserved after brace hit")
	check(sword.image.texture != blade.image.texture,"hilt and blade use distinct original-sword cuts")
	for victim:Node2D in targets: victim.queue_free()
	await process_frame
	blade.global_position = center+Vector2(160,0)
	sword.global_position = center+Vector2(-160,0)
	blade.direction = Vector2.UP
	blade.step_part(0.1)
	check(blade.direction == Vector2.UP,"no enemy: blade does not seek bench")
	var victim:Node2D = spawn("",Vector2(130,-70),"Team1")
	victim.Max_health = 10000
	victim.health = 10000
	blade.step_part(0.1)
	check(blade.direction == Vector2.UP,"near enemy does not redirect blade")
	for heading:Vector2 in [Vector2.RIGHT,Vector2.UP,Vector2.LEFT,Vector2.DOWN,Vector2(1,1).normalized()]:
		blade.velocity = heading*100
		blade.direction = heading
		blade.swing_visual_left = 0
		blade.visual_mob()
		check(absf(angle_difference(blade.image.rotation,heading.angle()+PI*0.25))<0.001,"blade artwork follows movement heading")
	victim.global_position = blade.global_position+Vector2(30,0)
	blade.velocity = Vector2.ZERO
	blade.sword_charge = 1
	blade.swing_left = 0
	blade.swing_cooldown = 0
	blade._swing_pending = false
	var hp:int = victim.health
	check(blade.begin_swing(),"blade thrust begins")
	blade.swing_left = 0
	check(blade.resolve_swing() == 1 and victim.health < hp,"blade thrust deals damage")
	victim.global_position = sword.global_position+Vector2(30,0)
	sword.sword_charge = 1
	sword.swing_left = 0
	sword.swing_cooldown = 0
	sword._swing_pending = false
	hp = victim.health
	check(sword.begin_swing(),"hilt swing begins")
	sword.swing_left = 0
	check(sword.resolve_swing() == 1 and victim.health < hp,"hilt swing deals damage")
	check(victim.get_children().any(func(n:Node): return n.has_method("replace_with_hit")),"knockback target remains valid")
	victim.queue_free()
	sword.global_position = center
	blade.global_position = center+Vector2(100,0)
	bench.age = bench.materialize_duration
	bench.update_opacity()
	var blade_hp:int = blade.health
	hp = sword.health
	sword.take_damage(100,true)
	check(hp-sword.health == 50,"bench gives 50 percent reduction including bypass-block damage")
	check(blade.health == blade_hp,"hilt damage does not deduct blade HP")
	bench.advance(1.0)
	check(sword.health == hp-50+15,"bench heals 5 percent max health per second")
	check(bench.progress == 0,"one touching piece cannot repair")
	blade.global_position = center+Vector2(8,0)
	bench.advance(1.0)
	check(bench.progress == 1.0 and sword.part_kind == 1,"both touching starts timed repair")
	blade.global_position = center+Vector2(100,0)
	bench.advance(0.1)
	check(bench.progress == 0,"leaving bench resets repair")
	hp = blade.health
	blade.take_damage(100,true)
	check(hp-blade.health == 100,"outside bench has no reduction")
	blade.global_position = center+Vector2(8,0)
	game.now_stop_state = true
	hp = sword.health
	bench.advance(10)
	check(bench.progress == 0 and sword.health == hp,"paused battle neither repairs nor heals")
	game.now_stop_state = false
	bench.advance(2.39)
	check(sword.part_kind == 1,"repair must wait full duration")
	bench.advance(0.02)
	check(sword.part_kind == 0 and sword.durability == 45,"repair forms new 45-durability sword")
	check(sword.Max_health == 600 and sword.health <= 600,"reformed health bounded to original maximum")
	check(blade.is_queued_for_deletion() and bench.is_queued_for_deletion(),"repair consumes blade and old bench")
	check(sword.successful_repairs == 1,"repair exactly once")
	await process_frame
	sword.spend_durability(50)
	await process_frame
	await process_frame
	check(sword.part_kind == 1 and is_instance_valid(sword.workbench) and not is_instance_valid(bench),"new sword can break into a fresh family again")
	await clear_units()
	await process_frame
	var pair:Array = await broken_pair(Vector2(-100,0))
	var fade:Node2D = pair[2]
	fade.age = 0.0
	fade.update_opacity()
	for part:Node2D in [pair[0],pair[1]]:
		part.global_position = fade.global_position+Vector2(-8 if part == pair[0] else 8,0)
	check(is_equal_approx(fade.modulate.a,0.2),"bench starts at 20 percent opacity")
	fade.progress = 100.0
	fade.complete_repair()
	check(pair[0].part_kind == 1,"direct completion cannot bypass materialization")
	fade.progress = 0.0
	fade.advance(1.5)
	check(is_equal_approx(fade.modulate.a,0.6) and fade.progress == 0,"half materialized; no repair time banked")
	game.now_stop_state = true
	fade.advance(10)
	check(is_equal_approx(fade.age,1.5),"pause freezes materialization")
	game.now_stop_state = false
	fade.advance(1.5)
	check(is_equal_approx(fade.modulate.a,1.0) and fade.progress == 0,"fully visible after three seconds, only now eligible")
	fade.age = 2.9
	fade.progress = 0.0
	fade.advance(0.2)
	check(is_equal_approx(fade.progress,0.1),"crossing frame counts only post-materialization time")
	fade.progress = 0.0
	for kind:int in [0,1,2]:
		var moving:Node2D = spawn("木剑",Vector2(0,-250))
		moving.part_kind = kind
		moving.direction = Vector2.UP
		moving.dock_delay = 0
		moving.sword_charge = 1
		var near:Node2D = spawn("",Vector2(30,-250),"Team1")
		near.Max_health = 10000
		near.health = 10000
		moving.step_mob(0.01)
		check(moving.direction == Vector2.UP,"all forms keep normal direction with enemy nearby "+str(kind))
		check(moving.swing_visual_left>0,"all forms automatically swing at nearby enemy "+str(kind))
		moving.swing_visual_left = 0.30
		moving.visual_mob()
		var angle:float = moving.image.rotation
		moving.swing_visual_left = 0.10
		moving.visual_mob()
		check(absf(angle_difference(angle,moving.image.rotation))>0.5,"visible swing arc for each form "+str(kind))
		moving.move(130.0,0.016)
		check(is_equal_approx(moving.velocity.length(),78.0),"ordinary move speed, no fragment/lunge bonus "+str(kind))
		moving.queue_free()
		near.queue_free()
		await process_frame
	var other_pair:Array = await broken_pair(Vector2(120,0))
	var h:Node2D = pair[0]
	var b:Node2D = pair[1]
	var table:Node2D = pair[2]
	h.global_position = table.global_position
	other_pair[1].global_position = table.global_position
	check(not table.touching(other_pair[1]),"another sword's blade cannot use or complete this bench")
	b.health = 0
	table.advance(5.0)
	check(h.part_kind == 1 and table.progress == 0,"dead blade prevents repair without resurrection")
	check(table.living_pieces().size() == 1,"survivor keeps independent life")
	h.queue_free()
	await process_frame
	table.advance(1.1)
	check(table.is_queued_for_deletion(),"bench cleans up when no surviving pieces remain")
	await clear_units()
	for wait_index:int in range(1200):
		if not is_instance_valid(world._mc_prewarmer) or world._mc_prewarmer.finished.size()+world._mc_prewarmer.failed.size() >= world._mc_prewarmer.CHARACTERS.size(): break
		await process_frame
	print("WOOD_REV2_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
