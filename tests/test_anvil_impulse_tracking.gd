extends "res://tests/test_anvil_arc.gd"
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
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"impulse pursuit preloads complete")
	var bounds:Rect2 = world.return_map_world_rect(world.map_group["Map50x50"])
	center = bounds.get_center()
	var start:Vector2 = center+Vector2(0,90)
	var unit:Node2D = anvil(start)
	var target:Node2D = dummy(center+Vector2(130,0))
	var replica:Node2D = anvil(center+Vector2(230,100))
	replica.set_multiplayer_authority(2)
	await physics_frame
	await process_frame
	# With pursuit disabled, impulse alone must reach the OLD target X at T.
	unit.fall_track_acceleration = 0.0
	for side:float in [-1.0,0.0,1.0]:
		target.global_position = center+Vector2(side*130.0,0)
		check(restart_jump(unit,target,start),"impulse launch "+str(side))
		var expected_v:float = (target.global_position.x-start.x)/unit._jump_total_time*unit.tracking_speed_scale
		var old_x:float = start.x+(target.global_position.x-start.x)*unit.tracking_speed_scale
		check(is_equal_approx(unit.velocity.x,expected_v) and is_equal_approx(unit._fall_track_velocity,expected_v),"takeoff sets one actual signed impulse velocity, not a separate position track")
		check(absf(expected_v)<=0.001 or absf(expected_v)>unit.fall_track_speed,"initial impulse is not clamped to ordinary pursuit speed")
		target.global_position.x += 60.0
		unit.step_mob(unit._jump_total_time*0.5)
		check(absf(unit.global_position.x-start.x-expected_v*unit._jump_total_time*0.5)<0.04,"impulse alone travels at initial speed despite target movement")
		unit.step_mob(unit._jump_total_time*0.5)
		check(unit.slam_phase==unit.SlamPhase.FALLING and absf(unit.global_position.x-old_x)<0.04,"uncorrected half impulse reaches the scaled reference X without snapping to target")
		check(is_equal_approx(unit._fall_track_velocity,expected_v) and is_equal_approx(unit.velocity.x,expected_v),"jump-to-fall keeps same horizontal momentum")
		var release:Vector2 = unit.global_position
		unit.step_mob(0.04)
		check(absf(unit.global_position.x-release.x-expected_v*0.04)<0.04 and unit.global_position.y>release.y,"fall also integrates existing momentum when acceleration is disabled")
	# Turn request must cancel old velocity before actual reverse movement.
	unit.fall_track_acceleration = 600.0
	for side:float in [-1.0,1.0]:
		target.global_position = center+Vector2(side*130.0,0)
		check(restart_jump(unit,target,start),"reversal launch "+str(side))
		target.global_position.x = center.x-side*200.0
		unit.step_mob(0.1)
		check(absf(unit._fall_track_velocity-side*40.0)<0.04 and absf(unit.global_position.x-start.x-side*7.0)<0.04,"opposite target first decelerates 100 to 40 while still moving original way")
		unit.step_mob(0.2)
		check(unit.slam_phase==unit.SlamPhase.RISING and absf(unit._fall_track_velocity+side*80.0)<0.05,"rising pursuit applies bounded acceleration, not a reversed velocity assignment")
		var before:Vector2 = unit.global_position
		unit.step_mob(0.1)
		check(absf(unit._fall_track_velocity+side*100.0)<0.05 and absf(unit.global_position.x-before.x+side*(29.0/3.0))<0.05,"after crossing zero, position reverses with the correct acceleration integral")
		check(absf(unit.global_position.x-unit.jump_position(unit.phase_elapsed/unit._jump_total_time).x)>20.0,"runtime X is not overwritten by old analytic path")
		check(not unit.get_collision_layer_value(2) and unit.get_collision_mask_value(1),"accelerated jump still passes characters but collides with terrain")
	# One velocity across a fractional jump completion; pursuit never switches off.
	target.global_position = center+Vector2(200,0)
	unit.jump_duration = 0.653
	check(restart_jump(unit,target,start),"fractional phase handoff setup")
	target.global_position.x = center.x+300.0
	unit.step_mob(0.65)
	var old_velocity:float = unit._fall_track_velocity
	var before_handoff:Vector2 = unit.global_position
	unit.step_mob(0.01)
	check(unit.slam_phase==unit.SlamPhase.FALLING and absf(unit._fall_track_velocity-old_velocity)<=6.01 and unit._fall_track_velocity>0.0,"handoff cannot zero or replace momentum; only bounded acceleration changes it")
	check(unit.global_position.x>before_handoff.x and absf(unit.velocity.x-unit._fall_track_velocity)<0.01,"remaining frame time moves with same actual horizontal velocity")
	unit.jump_duration = 0.65
	# Even a last-moment target reversal remains active; no old 0.12s aim lock.
	target.global_position = center+Vector2(52,0)
	check(restart_jump(unit,target,center+Vector2(0,-120)),"falling reversal setup")
	unit._begin_drop(false,100.0)
	target.global_position = unit.global_position+Vector2(-120,30)
	var fall_start:Vector2 = unit.global_position
	unit.step_mob(0.05)
	check(absf(unit._fall_track_velocity-10.0)<0.04 and absf(unit.global_position.x-fall_start.x-1.25)<0.04,"falling tracker cancels existing 40 velocity rather than snapping to target side")
	check(unit._fall_track_point.x==target.global_position.x,"near-impact targeting continues to refresh without old lock or prediction")
	# Snapshot needs both launch budget and CURRENT momentum, never recompute impulse.
	target.global_position = center+Vector2(130,0)
	check(restart_jump(unit,target,start),"replica setup")
	target.global_position.x = center.x-130.0
	unit.step_mob(0.15)
	replica.accept_visual(unit.network_visual_state())
	check(replica.tracking_speed_scale==unit.tracking_speed_scale and is_equal_approx(replica._launch_horizontal_speed,unit._launch_horizontal_speed) and is_equal_approx(replica._fall_track_velocity,unit._fall_track_velocity),"snapshot preserves initial impulse and partially cancelled current velocity")
	unit.step_mob(0.1)
	replica.client_visual_step(0.1)
	check(replica.global_position.distance_to(unit.global_position)<0.05 and absf(replica._fall_track_velocity-unit._fall_track_velocity)<0.05,"replica integrates same rising acceleration without restarting impulse")
	var hp:float = target.health
	var paused:Vector2 = unit.global_position
	var paused_v:float = unit._fall_track_velocity
	game.now_stop_state = true
	unit.step_mob(4.0)
	check(unit.global_position==paused and unit._fall_track_velocity==paused_v,"pause freezes position and momentum")
	game.now_stop_state = false
	var remote_pos:Vector2 = replica.global_position
	replica.step_mob(1.0)
	check(replica.global_position==remote_pos and target.health==hp,"non-authority cannot double-integrate or deal damage")
	# Target loss brakes gently; it must not erase stored speed instantly.
	target.global_position = center+Vector2(130,0)
	check(restart_jump(unit,target,start),"invalid target setup")
	target.Team = unit.Team
	unit.step_mob(0.1)
	check(not unit._fall_track_valid and absf(unit._fall_track_velocity-40.0)<0.04,"lost target coasts/brakes with the same acceleration limit")
	target.Team = "Team1"
	# Ceiling clips vertical motion only; side wall clips horizontal momentum.
	unit.fall_track_acceleration = 0.0
	check(restart_jump(unit,target,start),"ceiling setup")
	var ceiling:StaticBody2D = obstacle(unit.jump_position(0.2),Vector2(200,4))
	await physics_frame
	await process_frame
	advance_until(unit,func(): return unit.slam_phase!=unit.SlamPhase.RISING,1.0)
	check(unit.slam_phase==unit.SlamPhase.FALLING and absf(unit._fall_track_velocity-100.0)<0.04 and unit.get_collision_layer_value(2),"ceiling starts fall retaining tangent momentum and restoring character body")
	var contact:Vector2 = unit.global_position
	unit.step_mob(0.04)
	check(absf(unit.global_position.x-contact.x-4.0)<0.04 and unit.global_position.y>contact.y,"ceiling contact does not reset horizontal force")
	ceiling.queue_free()
	await physics_frame
	await process_frame
	var wall:StaticBody2D = obstacle(start+Vector2(45,0),Vector2(0.5,bounds.size.y*2.0))
	await physics_frame
	await process_frame
	unit.jump_duration = 0.05
	check(restart_jump(unit,target,start),"uncapped fast impulse setup")
	unit.step_mob(0.1)
	check(unit.global_position.x+unit.body_half_size().x<=wall.global_position.x-0.24 and unit._fall_track_velocity==0.0 and body_inside(unit,bounds,unit.global_position),"uncapped initial impulse cannot tunnel through thin wall or leave map")
	wall.queue_free()
	await physics_frame
	await process_frame
	unit.jump_duration = 0.65
	unit.fall_track_acceleration = 600.0
	check(restart_jump(unit,target,start),"cancellation setup")
	unit._cancel_slam()
	check(unit._fall_track_velocity==0.0 and unit._launch_horizontal_speed==0.0 and not unit._jump_ignores_characters,"cancellation clears impulse and collision override")
	check(restart_jump(unit,target,start),"death setup")
	unit.health = 0.0
	unit.Die()
	check(unit.velocity==Vector2.ZERO and unit._fall_track_velocity==0.0 and unit._launch_horizontal_speed==0.0,"death clears both initial and current momentum")
	print("ANVIL_IMPULSE_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
