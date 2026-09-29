extends "res://tests/test_mc16_spider_drowned.gd"
func run() -> void:
	game=root.get_node("Game"); saved=game.Game_Settings.duplicate(true); saved_stop=game.now_stop_state
	game.Game_Settings.Training_Mode=false; game.Game_Settings.Ball_Can_Move=true; game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false; AudioServer.set_bus_mute(0,true)
	create_timer(60).timeout.connect(func():finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50";world.refresh_map_presentation();world.control.hide()
	await create_timer(0.4).timeout
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var drowned:Node=spawn("res://scenes/characters/我的世界/溺尸.tscn",center)
	var enemy:Node=dummy(center+Vector2(160,0))
	await process_frame
	var driver:Node=drowned.mc_native_animation
	var hand:Node=drowned.hand_visual
	var spear:Node=drowned._trident
	check(drowned.trident_hand_position().distance_to(driver.hand_world_position()+Vector2(0,-4))<0.001,"held and return anchors both shift upward four pixels")
	check(spear.DRAW_SIZE==16.0,"outbound/return/stuck weapon all use compact 16px texture box")
	for clip:StringName in [&"idle",&"walk",&"throw"]:
		if not driver.frames.has_animation(clip): continue
		for frame:int in [0,3,6]:
			driver._set_clip(clip);driver.clip_time=float(frame)/driver.frames.get_animation_speed(clip);driver.frame_index=-1;driver._render_frame()
			for flipped:bool in [false,true]:
				drowned._visual_facing_flipped_h=flipped;hand.sync_pose()
				check(hand.visible and hand.weapon.scale.x>=3.0,"full-sized weapon is visible in animated hand")
				check(hand.weapon.to_global(Vector2(hand.record.grip)).distance_to(hand.to_global(Vector2(hand.record.grip)))<0.001,"enlarging and mirroring preserve native grip pivot")
				var path:PackedVector2Array=PackedVector2Array(hand.record.path)
				var axis:Vector2=hand.weapon.global_transform.basis_xform(path[path.size()-1]-path[0]).normalized()
				check(axis.dot(Vector2.UP)>0.999,"idle hand holds spear upright across native frames and both facings")
	drowned._visual_facing_flipped_h=false
	check(drowned.throw_trident(enemy),"throw enters windup")
	check(drowned.has_trident and spear.flight_state==spear.Phase.HELD and hand.visible,"weapon stays in hand during throw preparation")
	check(not drowned.throw_trident(enemy),"windup cannot duplicate a pending throw")
	var left:float=drowned._throw_left
	game.now_stop_state=true;drowned._advance_trident_throw(1.0)
	check(drowned._throw_left==left,"pause freezes throw preparation")
	game.now_stop_state=false
	drowned._advance_trident_throw(0.1)
	check(spear.flight_state==spear.Phase.HELD,"weapon does not leave early")
	# Last third of preparation is fully horizontal, before release.
	drowned._advance_trident_throw(0.03)
	hand.sync_pose()
	var throw_path:PackedVector2Array=PackedVector2Array(hand.record.path)
	var throw_axis:Vector2=hand.weapon.global_transform.basis_xform(throw_path[throw_path.size()-1]-throw_path[0]).normalized()
	check(throw_axis.dot(Vector2.RIGHT)>0.999 and hand.visible,"rightward throw rotates held spear horizontal before release")
	check(hand.weapon.to_global(Vector2(hand.record.grip)).distance_to(hand.to_global(Vector2(hand.record.grip)))<0.001,"throw rotation remains anchored at native hand grip")
	driver.clip_time=0.16;driver.frame_index=-1;driver._render_frame();hand.sync_pose()
	var origin:Vector2=drowned.trident_hand_position()
	drowned._advance_trident_throw(0.06)
	check(spear.flight_state==spear.Phase.OUTBOUND and not drowned.has_trident,"release launches exactly the held spear")
	check(spear.global_position.distance_to(origin)<0.01 and not hand.visible,"release begins at current hand with no duplicate held weapon")
	var hp:float=enemy.health
	for i:int in 80:
		spear.advance(0.02)
		if spear.flight_state==spear.Phase.RETURNING: break
	check(enemy.health<hp,"enlarged weapon preserves actual projectile damage")
	# Long-return fixture separates the slow start, accelerated trail and final catch.
	spear.global_position=center+Vector2(400,0)
	spear.return_trail._initialized=false
	spear.return_trail.samples.clear()
	var angle_before:float=spear.rotation
	spear.advance(0.02)
	check(spear.rotation-angle_before<0.12 and spear.return_speed_at(spear._return_elapsed)<80.0,"return begins with slow movement and slow spin")
	check(spear.return_trail.samples.is_empty(),"slow return has no afterimages")
	check(spear.return_spin_at(0.18)==60.0 and spear.return_speed_at(0.18)<drowned.trident_return_speed*1.5*0.25,"spin reaches maximum while translation is still below quarter of top speed")
	check(spear.RETURN_SPIN_ACCEL_TIME*4.0<spear.RETURN_ACCEL_TIME,"spin accelerates more than four times sooner than translation")
	var fine_angle:float=0.0
	for i:int in 18:
		fine_angle+=spear._return_integral((i+1)*0.01,4.0,60.0,0.18)-spear._return_integral(i*0.01,4.0,60.0,0.18)
	check(is_equal_approx(fine_angle,spear._return_integral(0.18,4.0,60.0,0.18)),"separate fast spin remains frame-rate independent")
	var slow_speed:float=spear.return_speed_at(spear._return_elapsed)
	var slow_spin:float=spear.return_spin_at(spear._return_elapsed)
	for i:int in 8: spear.advance(0.04)
	check(spear.return_speed_at(spear._return_elapsed)>slow_speed*4 and spear.return_spin_at(spear._return_elapsed)>slow_spin*4,"translation accelerates while rotation reaches high speed earlier")
	check(spear.return_trail.samples.size()>8 and spear.return_trail.samples.size()<=24,"fast return has denser bounded afterimages")
	check(is_equal_approx(spear.return_speed_at(0.75),drowned.trident_return_speed*1.5) and spear.return_spin_at(0.75)==60.0,"acceleration settles at bounded top speed and spin")
	check(spear.return_trail.samples.size()>0,"return creates explicit weapon afterimages despite global character blur restriction")
	check(spear.return_trail.draw_size==16.0,"afterimages match compact projectile size")
	var age_before:float=spear.return_trail.samples[0].age
	game.now_stop_state=true;spear.advance(0.2)
	check(spear.return_trail.samples[0].age==age_before,"pause freezes return afterimages")
	game.now_stop_state=false
	hp=enemy.health
	for i:int in 100:
		spear.advance(0.02)
		if spear.flight_state==spear.Phase.HELD: break
	check(spear.flight_state==spear.Phase.HELD and drowned.has_trident and enemy.health==hp,"loyalty returns to hand without extra return damage")
	check(drowned._catch_left>0.0 and driver.current_clip==&"catch","catch starts a dedicated native arm recoil animation")
	check(driver.frames.has_animation(&"catch") and not driver.frames.get_animation_loop(&"catch"),"catch animation is finite and distinct from idle")
	check(spear.RETURN_ACCEL_TIME==0.75,"return acceleration takes longer without changing maximum speed")
	var max_throw_x:float=-INF
	for frame:Dictionary in hand.LAYERS.TRACKS["throw"]: max_throw_x=maxf(max_throw_x,frame.grip.x)
	check(driver.CATCH_LAYERS.FRAMES[0].grip.x>max_throw_x,"catch starts with native arm behind even the furthest throwing pose")
	var peak_x:float=driver.CATCH_LAYERS.FRAMES[0].grip.x
	for frame:Dictionary in driver.CATCH_LAYERS.FRAMES: peak_x=maxf(peak_x,frame.grip.x)
	check(peak_x>driver.CATCH_LAYERS.FRAMES[0].grip.x,"brief extra rearward recoil creates impact before recovery")
	game.now_stop_state=true
	var catch_before:float=drowned._catch_left
	drowned._advance_trident_catch(1.0)
	check(drowned._catch_left==catch_before,"pause freezes catch recovery")
	game.now_stop_state=false
	var catch_frame:int=driver.frame_index
	driver.advance(0.12);hand.sync_pose()
	check(driver.frame_index!=catch_frame and hand.visible,"catch body and held weapon advance together")
	check(hand.weapon.to_global(Vector2(hand.record.grip)).distance_to(hand.to_global(Vector2(hand.record.grip)))<0.001,"catch arm animation retains weapon grip alignment")
	drowned._advance_trident_catch(0.40);driver.advance(0.40)
	check(drowned._catch_left==0.0 and driver.current_clip!=&"catch","catch recovers to normal pose")
	drowned.catch_trident(spear)
	check(drowned._catch_left>0.0 and drowned.throw_trident(enemy),"new attack may immediately interrupt catch with no recovery gate")
	check(drowned._catch_left==0.0 and driver.current_clip==&"throw","valid attack takes animation priority over catch in the same call")
	# Cancel only the test's pending shot to retain the next left-facing throw case.
	drowned._throw_left=-1.0;drowned._throw_target=null;driver.refresh_trident_pose()
	spear.advance(0.26)
	check(spear.return_trail.samples.is_empty(),"afterimages fade after catch instead of persisting on held spear")
	enemy.global_position=center+Vector2(-160,0)
	check(drowned.throw_trident(enemy),"can prepare another throw after catch")
	drowned._advance_trident_throw(0.13);hand.sync_pose()
	throw_path=PackedVector2Array(hand.record.path)
	throw_axis=hand.weapon.global_transform.basis_xform(throw_path[throw_path.size()-1]-throw_path[0]).normalized()
	check(throw_axis.dot(Vector2.LEFT)>0.999,"leftward throw also rotates horizontally toward target")
	enemy.queue_free();await process_frame
	drowned._advance_trident_throw(0.2)
	check(drowned._throw_left<0.0 and drowned.has_trident,"lost target cancels preparation without losing inventory")
	var normal:Node=dummy(center+Vector2(0,300))
	check(not normal.motion_blur_enabled and not normal.motion_stretch_enabled,"all normal characters default to clear un-stretched visuals")
	normal.motion_blur_enabled=true;normal.motion_blur_force_strength=1.0
	normal._set_motion_blur_values(Vector2.RIGHT,1000.0,1.0)
	check(normal._motion_blur_strength==0.0 and not is_instance_valid(normal._motion_blur_ghost),"old scene/debug overrides cannot enable non-exempt character blur")
	normal.AfterImage_Speed=1.0;normal._process_auto_after_image(0.1)
	check(not normal._after_image_last_transform_valid and normal._after_image_path_points.is_empty(),"non-exempt character speed afterimages stay disabled")
	var cow:Node=spawn("res://scenes/characters/动物/牛.tscn",center+Vector2(0,400))
	check(cow.motion_blur_enabled and cow.allows_character_motion_effects(),"cow explicitly retains motion effects")
	cow._set_motion_blur_values(Vector2.RIGHT,900.0,1.0)
	check(cow._motion_blur_strength>0.0,"cow still produces high-speed blur")
	var wood:Node=spawn("res://scenes/characters/我的世界/木矛.tscn",center+Vector2(0,500))
	check(wood.motion_blur_enabled and wood.allows_character_motion_effects(),"wooden spear explicitly retains motion effects")
	wood._set_motion_blur_values(Vector2.RIGHT,900.0,1.0)
	check(wood._motion_blur_strength>0.0,"wooden spear high-speed blur remains enabled")
	var train:Node=load("res://scripts/creatures/火车长_列车.gd").new()
	check(train.train_motion_blur_pixels>0.0 and train.train_motion_blur_alpha>0.0,"summoned train independent blur parameters remain enabled")
	train.free()
	print("HAND_BLUR_TEST checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
