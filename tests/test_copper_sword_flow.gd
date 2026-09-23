extends "res://tests/test_copper_sword_facing.gd"
## Continuous strokes, genuine angle/time easing, 360-degree damage and short recovery.
func pose_gap(a:Transform2D,b:Transform2D) -> float:
	return a.origin.distance_to(b.origin)+a.x.distance_to(b.x)+a.y.distance_to(b.y)
func stop_restore(unit:Node) -> void:
	unit.cancel_swing()
	unit._advance_return(unit.return_duration)
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(75.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.3).timeout
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"flow-test preloads complete")
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var unit:Node2D = copper(center)
	unit.Can_Skill = false
	unit.default_properties.Can_Skill = false
	var target:Node2D = dummy(center+Vector2(26,0))
	await physics_frame
	await process_frame
	check(unit.image.rotation==0.0 and not unit.is_character_visual_flipped_h(),"idle sword has ordinary right-facing native pose")
	check(unit.begin_swing(),"first full-angle stroke starts")
	check(unit._windup_left>0.0,"only first stroke has an initial raise")
	unit.advance_swing(unit._windup_left)
	var early:float = absf(unit.weapon_angle(0.25)-unit.weapon_angle(0.0))
	var middle:float = absf(unit.weapon_angle(0.50)-unit.weapon_angle(0.25))
	var late:float = absf(unit.weapon_angle(0.75)-unit.weapon_angle(0.50))
	var last:float = absf(unit.weapon_angle(1.0)-unit.weapon_angle(0.75))
	check(early<middle and middle<late and late<last and last>early*5.0,"equal time slices produce increasing blade travel, not smoothstep slowdown")
	var hp:float = target.health
	unit.advance_swing(unit._swing_duration*0.2)
	check(target.health==hp,"slow opening does not apply early melee damage")
	finish_current_swing(unit)
	check(is_equal_approx(hp-target.health,ceilf(unit.attack_damage())),"accelerating stroke damages once through its real blade")
	var lower:Transform2D = unit.image.transform
	var previous_duration:float = unit._swing_duration
	check(unit._holding_pose and not unit._returning and pose_gap(lower,unit._rest_pose())>1.0,"cut ends below, with no neutral-pose return")
	check(unit.begin_swing(),"reverse stroke starts immediately")
	check(not unit._swing_down and unit._windup_left==0.0 and pose_gap(lower,unit.image.transform)<0.001,"downstroke endpoint exactly equals upstroke start, without repeated raising")
	check(unit._swing_duration<previous_duration,"combo increases actual reverse-stroke speed")
	finish_current_swing(unit)
	var upper:Transform2D = unit.image.transform
	check(unit.begin_swing() and unit._swing_down and pose_gap(upper,unit.image.transform)<0.001,"upstroke endpoint exactly equals the next downstroke start")
	stop_restore(unit)

	# Cross a stroke boundary inside ONE engine step; keep the unused frame time.
	unit.reset_combo()
	unit.begin_swing()
	var before_down:bool = unit._swing_down
	unit.step_mob(unit._windup_left+unit._swing_duration+0.025)
	check(unit._swing_active and unit._swing_down!=before_down and unit._windup_left==0.0,"AI connects opposite cuts within the same physics step")
	check(is_equal_approx(unit._swing_elapsed,0.025) and not unit._returning,"frame remainder advances next cut instead of waiting in idle/cooldown")
	stop_restore(unit)

	# Same wall-clock interval: attack speed must visibly move the blade farther.
	unit.reset_combo()
	unit.begin_swing()
	unit.advance_swing(unit._windup_left)
	var start:float = unit.weapon_angle(0.0)
	unit.advance_swing(0.04)
	var slow_travel:float = absf(angle_difference(start,unit.image.rotation))
	var slow_duration:float = unit._swing_duration
	stop_restore(unit)
	unit.combo_hits = 10
	unit.begin_swing()
	unit.advance_swing(unit._windup_left)
	start = unit.weapon_angle(0.0)
	unit.advance_swing(0.04)
	var fast_travel:float = absf(angle_difference(start,unit.image.rotation))
	check(fast_travel>slow_travel*4.0 and unit._swing_duration<slow_duration,"haste changes sword motion in the same 40ms, not just hit scheduling")
	stop_restore(unit)
	unit.reset_combo()
	var normal_cooling:float = unit.Attack_Cooling
	unit.Attack_Cooling = normal_cooling*0.5
	unit.begin_swing()
	check(is_equal_approx(unit._swing_duration,unit.base_swing_duration*0.5),"shared attack-cooling modifiers scale real blade duration")
	stop_restore(unit)
	unit.Attack_Cooling = normal_cooling

	# Actual sprite basis + actual hits in eight directions, including straight up/down.
	for i:int in range(8):
		var aim:Vector2 = Vector2.RIGHT.rotated(float(i)*TAU/8.0)
		target.global_position = center+aim*26.0
		await physics_frame
		await process_frame
		unit.reset_combo()
		unit.direction = Vector2.RIGHT
		unit._update_movement_facing()
		check(unit._select_swing_target()==target,"real target acquisition in direction "+str(i))
		hp = target.health
		unit.begin_swing()
		unit.advance_swing(unit._windup_left)
		var mid_phase:float = pow(0.5,1.0/unit.SWING_EASE_POWER)
		unit.advance_swing(unit._swing_duration*mid_phase)
		var native_blade:Vector2 = Vector2(1,-1) if unit._face_right else Vector2(-1,-1)
		var actual_blade:Vector2 = unit.image.global_transform.basis_xform(native_blade).normalized()
		check(actual_blade.dot(aim)>0.999 and unit.attack_axis().dot(aim)>0.999,"rendered sword truly aims at direction "+str(i)+", not only a left/right flag")
		check(unit.direction==Vector2.RIGHT and unit.velocity==Vector2.ZERO,"arbitrary angle preserves movement "+str(i))
		finish_current_swing(unit)
		check(is_equal_approx(hp-target.health,ceilf(unit.attack_damage())),"exactly one physical hit in direction "+str(i))
		hp = target.health
		stop_restore(unit)
		check(target.health==hp and unit.image.rotation==0.0 and not unit._has_attack_pose(),"recovery is harmless and returns to idle after direction "+str(i))

	# A target crossing the angle wrap may change aim, but never pops at the boundary.
	target.global_position = center+Vector2.LEFT.rotated(-0.05)*26.0
	await physics_frame
	await process_frame
	unit.begin_swing()
	finish_current_swing(unit)
	var seam_end:Transform2D = unit.image.transform
	target.global_position = center+Vector2.LEFT.rotated(0.05)*26.0
	await physics_frame
	await process_frame
	unit.begin_swing()
	check(pose_gap(seam_end,unit.image.transform)<0.001,"retarget across plus/minus pi preserves exact chain endpoint")
	check(absf(angle_difference(unit._swing_aim_from,unit._swing_aim_to))<0.11,"retarget takes short angular route, not a full rotation")
	stop_restore(unit)

	# Recovery starts at the current pose, freezes in pause, then finishes quickly.
	unit.set_player_control_peer(1)
	unit.player_control_direction = Vector2.RIGHT
	unit.begin_swing()
	unit.advance_swing(unit._windup_left+unit._swing_duration*0.65)
	var interrupted:Transform2D = unit.image.transform
	var replica:Node2D = copper(center+Vector2(300,150))
	replica.set_multiplayer_authority(2)
	replica.accept_visual(unit.network_visual_state())
	replica.visual_mob()
	check(pose_gap(replica.image.transform,unit.image.transform)<0.001,"replica reproduces arbitrary-angle stroke pose, not just a flip")
	unit.cancel_swing()
	replica.accept_visual(unit.network_visual_state())
	check(unit._returning and pose_gap(interrupted,unit.image.transform)<0.001,"stop begins a smooth return without an initial snap")
	hp = target.health
	game.now_stop_state = true
	unit.step_mob(2.0)
	check(unit._return_elapsed==0.0 and pose_gap(interrupted,unit.image.transform)<0.001,"pause freezes quick-return animation")
	game.now_stop_state = false
	unit.step_mob(unit.return_duration*0.5)
	replica.client_visual_step(unit.return_duration*0.5)
	replica.visual_mob()
	check(pose_gap(replica.image.transform,unit.image.transform)<0.001,"replica reproduces interpolated quick recovery")
	check(pose_gap(unit.image.transform,unit._rest_pose())<pose_gap(interrupted,unit._rest_pose())*0.3,"quick return is already mostly complete halfway through")
	unit.step_mob(unit.return_duration*0.5+0.001)
	check(not unit._has_attack_pose() and unit.image.rotation==0.0 and target.health==hp,"quick return finishes exactly in its short duration without damage")

	# Tap commits one slash; hold connects cuts; release cannot queue another cut.
	target.global_position = center+Vector2(26,0)
	await physics_frame
	await process_frame
	unit.reset_combo()
	hp = target.health
	unit.player_control_action(0)
	unit.player_control_action_released(0)
	check(unit._swing_active and not unit._manual_attack_held,"a quick tap still commits one full slash")
	unit.step_mob(unit._windup_left+unit._swing_duration+unit.return_duration+0.01)
	check(not unit._has_attack_pose() and is_equal_approx(hp-target.health,ceilf(unit.attack_damage())),"tap completes one hit then returns, with no phantom repeat")
	hp = target.health
	unit.player_control_action(0)
	before_down = unit._swing_down
	unit.step_mob(unit._windup_left+unit._swing_duration+0.02)
	check(unit._manual_attack_held and unit._swing_active and unit._swing_down!=before_down and unit._windup_left==0.0,"holding input seamlessly reverses the sword")
	unit.player_control_action_released(0)
	unit.step_mob(unit._swing_duration-unit._swing_elapsed+unit.return_duration+0.01)
	check(not unit._has_attack_pose() and is_equal_approx(hp-target.health,ceilf(unit.attack_damage())*2.0),"release finishes current cut, blocks the next, and returns promptly")
	unit.player_control_action(0)
	unit.player_control_action_cancelled(0)
	check(not unit._swing_active and unit._returning and not unit._manual_attack_held,"control cancellation stops damage immediately and starts recovery")
	unit._advance_return(unit.return_duration)
	unit.set_player_control_peer(0)
	check(not unit._manual_attack_held and not has_copper_status(unit),"no held-input or text state survives control handoff")
	print("COPPER_SWORD_FLOW checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
