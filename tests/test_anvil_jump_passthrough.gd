extends "res://tests/test_anvil_arc.gd"
func scan_hurtbox(unit:Node2D) -> bool:
	var shape := CircleShape2D.new()
	shape.radius = 1.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0,unit.global_position)
	query.collision_mask = 2
	query.collide_with_areas = true
	query.collide_with_bodies = false
	for item:Dictionary in unit.get_world_2d().direct_space_state.intersect_shape(query,32):
		if item.collider==unit.self_hurtbox: return true
	return false
func body_sweep(probe:Node2D,unit:Node2D,test_only:bool = true) -> KinematicCollision2D:
	probe.collision_mask = 2
	probe.global_position = unit.global_position-Vector2(70,0)
	return probe.move_and_collide(Vector2(140,0),test_only,0.001,false)
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
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
	await create_timer(0.3).timeout
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"jump pass-through preloads complete")
	var bounds:Rect2 = world.return_map_world_rect(world.map_group["Map50x50"])
	center = bounds.get_center()
	var start:Vector2 = center+Vector2(-100,80)
	var unit:Node2D = anvil(start)
	unit.fall_track_acceleration = 0.0 # Isolate collision path from active steering.
	var target:Node2D = dummy(center+Vector2(120,0))
	var probe:Node2D = dummy(center+Vector2(-200,80))
	await physics_frame
	await process_frame
	var original:Array[int] = layers(unit)
	check(unit.get_collision_layer_value(2) and unit.get_collision_mask_value(1),"ordinary body advertises character collision and scans terrain")
	var contact:KinematicCollision2D = body_sweep(probe,unit)
	check(contact!=null and contact.get_collider()==unit,"another moving character really collides with normal anvil")
	check(unit.begin_slam(target),"jump starts")
	check(not unit.get_collision_layer_value(2) and not unit.get_collision_mask_value(2) and unit.get_collision_mask_value(1),"jump disables both character body directions but preserves terrain mask")
	check(layers(unit).slice(2)==original.slice(2) and unit.is_combat_targetable() and unit.is_combat_lockable(),"hurtbox/hitbox and targeting remain normal")
	contact = body_sweep(probe,unit,false)
	check(contact==null and probe.global_position.x>unit.global_position.x+60.0,"enemy can actually move through jumping anvil instead of blocking or pushing it")
	probe.Team = unit.Team
	contact = body_sweep(probe,unit,false)
	check(contact==null and probe.global_position.x>unit.global_position.x+60.0,"friendly character also passes through the jump")
	probe.Team = "Team1"
	probe.global_position = center+Vector2(-240,140)
	var blocker:Node2D = dummy(unit.jump_position(0.20))
	var friend:Node2D = dummy(unit.jump_position(0.35),"Team0")
	await physics_frame
	await process_frame
	var hp:float = unit.health
	var enemy_hp:float = blocker.health
	check(scan_hurtbox(unit),"area-only attack query still detects jumping anvil hurtbox")
	unit.receive_positional_damage(7.0,probe.global_position,false,probe)
	check(unit.health<hp and not unit.get_collision_layer_value(2),"ignoring bodies does not make jumping anvil invulnerable")
	unit.step_mob(unit._jump_total_time*0.45)
	check(unit.slam_phase==unit.SlamPhase.RISING and unit.global_position.distance_to(unit.jump_position(0.45))<0.04,"actual jump traverses enemy and ally bodies without early drop or trajectory deflection")
	check(blocker.health==enemy_hp and unit.hit_count==0,"passing through on jump does not create slam damage")
	var paused:Vector2 = unit.global_position
	game.now_stop_state = true
	unit.step_mob(1.0)
	check(unit.global_position==paused and not unit.get_collision_layer_value(2),"paused jump stays paused and keeps character body exclusion")
	game.now_stop_state = false
	var fresh:Node2D = dummy(center+Vector2(200,140))
	contact = body_sweep(fresh,unit,false)
	check(contact==null,"newly spawned character also ignores the existing jump without exception lists")
	fresh.global_position = center+Vector2(200,140)
	unit.set_large_battle_performance_mode(true)
	check(not unit.get_collision_layer_value(2) and not unit.get_collision_mask_value(2) and unit.get_collision_mask_value(1),"large battle enable cannot restore body collision during jump")
	unit.set_large_battle_performance_mode(false)
	check(not unit.get_collision_layer_value(2) and not unit.get_collision_mask_value(2) and layers(unit).slice(2)==original.slice(2),"large battle disable keeps jump exclusion and unchanged area layers")
	var replica:Node2D = anvil(center+Vector2(240,140))
	replica.set_multiplayer_authority(2)
	replica.accept_visual(unit.network_visual_state())
	check(not replica.get_collision_layer_value(2) and replica.get_collision_mask_value(1) and layers(replica).slice(2)==original.slice(2),"replica applies only temporary character body exclusion")
	replica.client_visual_step(0.05)
	check(replica.slam_phase==replica.SlamPhase.RISING and not replica.get_collision_layer_value(2),"replica prediction keeps character pass-through while rising")
	replica.global_position = center+Vector2(240,140)
	unit.step_mob(unit._jump_total_time-unit.phase_elapsed)
	check(unit.slam_phase==unit.SlamPhase.FALLING and layers(unit)==original and not unit._jump_ignores_characters,"normal completion restores body collision before falling")
	await physics_frame
	await process_frame
	contact = body_sweep(probe,unit)
	check(contact!=null and contact.get_collider()==unit,"moving character sees anvil body again after jump")
	replica.accept_visual(unit.network_visual_state())
	check(layers(replica)==original and not replica._jump_ignores_characters,"replica falling snapshot restores ordinary body collision")
	replica.global_position = center+Vector2(240,140)
	probe.global_position = center+Vector2(-240,140)
	blocker.global_position = center+Vector2(-210,130)
	friend.global_position = center+Vector2(-240,100)
	check(restart_jump(unit,target,start),"cancellation fixture jumps")
	unit._cancel_slam()
	check(layers(unit)==original and not unit._jump_ignores_characters,"cancellation restores original body layers and masks")
	# Preserve unrelated body-layer/mask bits rather than overwriting entire masks.
	unit.collision_layer |= 8
	unit.collision_mask |= 10
	var custom:Array[int] = layers(unit)
	check(restart_jump(unit,target,start),"custom collision bits fixture jumps")
	check(unit.collision_layer==(custom[0]&~2) and unit.collision_mask==(custom[1]&~2),"temporary jump edits only character bit, not unrelated layers")
	unit._cancel_slam()
	check(layers(unit)==custom,"cancellation restores previously enabled character mask as well")
	unit.collision_layer = original[0]
	unit.collision_mask = original[1]
	# Real terrain still clips the moving body and restores collision immediately.
	check(restart_jump(unit,target,start),"terrain fixture jumps")
	var ceiling:StaticBody2D = obstacle(unit.jump_position(0.20),Vector2(180,4))
	await physics_frame
	await process_frame
	advance_until(unit,func(): return unit.slam_phase!=unit.SlamPhase.RISING,1.0)
	check(unit.slam_phase==unit.SlamPhase.FALLING and unit.global_position.y-unit.body_half_size().y>=ceiling.global_position.y+1.98,"ignoring characters does not ignore a real ceiling")
	check(layers(unit)==original and body_inside(unit,bounds,unit.global_position),"terrain-interrupted jump immediately restores body collision inside map")
	ceiling.queue_free()
	await physics_frame
	await process_frame
	check(restart_jump(unit,target,start),"death fixture jumps")
	unit.health = 0.0
	unit.Die()
	check(not unit._jump_ignores_characters and unit.get_collision_layer_value(2)==bool(original[0]&2),"death does not leak temporary character exclusion")
	var removed:Node2D = anvil(start)
	check(removed.begin_slam(target),"removal fixture jumps")
	world.remove_child(removed)
	check(not removed._jump_ignores_characters and removed.get_collision_layer_value(2),"leaving scene restores temporary body state")
	removed.free()
	print("ANVIL_JUMP_PASS_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
