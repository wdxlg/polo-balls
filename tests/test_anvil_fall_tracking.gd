extends "res://tests/test_anvil_arc.gd"
func drop_fixture(unit:Node2D,target:Node2D,point:Vector2,speed:float = 100.0) -> bool:
	if not restart_jump(unit,target,point): return false
	unit._launch_horizontal_speed = 0.0 # Isolate a stationary-start fall from takeoff impulse.
	unit._fall_track_velocity = 0.0
	unit._begin_drop(false,speed)
	return true
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
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"fall tracking preloads complete")
	var bounds:Rect2 = world.return_map_world_rect(world.map_group["Map50x50"])
	center = bounds.get_center()
	var start:Vector2 = center+Vector2(0,-140)
	var unit:Node2D = anvil(center+Vector2(-120,70))
	var target:Node2D = dummy(center+Vector2(100,0))
	var replica:Node2D = anvil(center+Vector2(220,70))
	replica.set_multiplayer_authority(2)
	await physics_frame
	await process_frame
	check(is_equal_approx(unit.fall_track_speed*unit.tracking_speed_scale,40.0) and unit.tracking_speed_scale==0.5,"default tracking is deliberately slower than ordinary movement")
	unit.velocity = Vector2(-500,120)
	check(unit.begin_slam(target),"impulse replaces prior cruising velocity")
	check(is_equal_approx(unit.velocity.x,(target.global_position.x-unit._jump_from.x)/unit._jump_total_time*unit.tracking_speed_scale),"launch impulse derives from old target X and duration")
	var initial_v:float = unit._fall_track_velocity
	target.global_position.x = unit.global_position.x-100.0
	unit.step_mob(0.1)
	check(absf(unit._fall_track_velocity-initial_v)<=unit.fall_track_acceleration*0.1+0.01 and unit._fall_track_velocity>0.0,"rising pursuit brakes existing impulse rather than reversing it instantly")
	for side:float in [-1.0,1.0]:
		target.global_position = center+Vector2(side*100.0,0)
		check(drop_fixture(unit,target,start),"signed falling tracker setup "+str(side))
		unit.player_control_direction = Vector2(-side,0)
		unit.direction = Vector2(-side,0)
		var saved_speed:float = unit.Speed
		unit.Speed *= 3.0
		replica.accept_visual(unit.network_visual_state())
		var hp:float = target.health
		unit.step_mob(0.2)
		replica.client_visual_step(0.2)
		check(absf(unit.global_position.x-start.x-side*(40.0*0.2-40.0*40.0/(2.0*600.0)))<0.03 and absf(unit._fall_track_velocity-side*40.0)<0.03,"tracking accelerates to cap, independent of cruising input and Speed buffs")
		check(absf(unit.global_position.y-start.y-(100.0*0.2+0.5*unit.gravity_acceleration*0.04))<0.04,"tracking does not slow or reset vertical gravity")
		check(replica.global_position.distance_to(unit.global_position)<0.04 and target.health==hp,"snapshot replica reproduces tracking without duplicate damage")
		unit.Speed = saved_speed
		var before:Vector2 = unit.global_position
		target.global_position.x = before.x-side*70.0
		unit.step_mob(0.1)
		check(absf(unit.global_position.x-before.x-side*1.0)<0.03,"target crossing brakes continuously instead of instantly reversing velocity")
		before = unit.global_position
		game.now_stop_state = true
		unit.step_mob(2.0)
		replica.client_visual_step(2.0)
		check(unit.global_position==before,"pause freezes tracking and gravity")
		game.now_stop_state = false
	# Near alignment must settle rather than overshoot or oscillate.
	target.global_position = center+Vector2(3,0)
	check(drop_fixture(unit,target,start),"near-alignment fixture")
	unit.step_mob(0.1)
	check(unit.global_position.x>start.x and unit.global_position.x<start.x+1.0 and unit._fall_track_velocity>0.0,"near alignment converges smoothly without crossing the deadzone")
	var settled_x:float = unit.global_position.x
	unit.step_mob(0.1)
	check(unit.global_position.x>=settled_x and unit.global_position.x<=start.x+1.01 and unit._fall_track_velocity<4.0,"alignment error and speed shrink without left/right jitter")
	target.global_position = center+Vector2(100,0)
	check(drop_fixture(unit,target,start),"speed zero fixture")
	unit.fall_track_speed = 0.0
	unit.step_mob(0.1)
	check(absf(unit.global_position.x-start.x)<0.01,"zero tuning value disables only lateral tracking")
	unit.fall_track_speed = 80.0
	check(drop_fixture(unit,target,start),"invalid target fixture")
	target.Team = unit.Team
	unit.step_mob(0.05)
	check(not unit._fall_track_valid and absf(unit.global_position.x-start.x)<0.01,"friendly target stops tracking instead of acquiring a new enemy")
	target.Team = "Team1"
	unit.step_mob(0.05)
	check(unit._fall_track_valid and absf(unit.global_position.x-start.x-0.75)<0.03,"still-valid original target can resume tracking")
	var doomed:Node2D = dummy(center+Vector2(-100,0))
	check(drop_fixture(unit,doomed,start),"dying target fixture")
	doomed.health = 0.0
	unit.step_mob(0.05)
	check(not unit._fall_track_valid and absf(unit.global_position.x-start.x)<0.01,"dead target stops lateral tracking but fall continues")
	doomed.free()
	unit.step_mob(0.05)
	check(not unit._fall_track_valid and absf(unit.global_position.x-start.x)<0.01,"freed weak target is safe and cannot cause a retarget snap")
	# Continuous pressure into a thin wall must slide DOWN, never suspend in air.
	var wall:StaticBody2D = obstacle(start+Vector2(unit.body_half_size().x+6.0,0),Vector2(0.5,bounds.size.y*2.0))
	target.global_position = center+Vector2(100,0)
	await physics_frame
	await process_frame
	check(drop_fixture(unit,target,start),"wall slide tracking fixture")
	replica.accept_visual(unit.network_visual_state())
	var hp_before:float = target.health
	var clang_before:int = unit.obstacle_impact_count
	unit.step_mob(0.3)
	replica.client_visual_step(0.3)
	check(unit.global_position.x+unit.body_half_size().x<=wall.global_position.x-0.24,"thin wall blocks repeated horizontal tracking pressure")
	check(absf(unit.global_position.y-start.y-(100.0*0.3+0.5*unit.gravity_acceleration*0.09))<0.05 and unit.fall_speed>400.0,"wall-blocked tracking preserves downward acceleration without hovering")
	check(target.health==hp_before and unit.obstacle_impact_count==clang_before,"side tracking collision neither damages through wall nor rings landing clang")
	check(replica.global_position.distance_to(unit.global_position)<0.05,"replica slides down same wall without divergence")
	wall.queue_free()
	await physics_frame
	await process_frame
	for side:float in [-1.0,1.0]:
		var target_x:float = bounds.position.x+0.1 if side<0.0 else bounds.end.x-0.1
		target.global_position = Vector2(target_x,center.y)
		var edge:Vector2 = Vector2(bounds.position.x+unit.body_half_size().x+2.0 if side<0.0 else bounds.end.x-unit.body_half_size().x-2.0,start.y)
		check(drop_fixture(unit,target,edge),"map boundary tracking fixture "+str(side))
		unit.step_mob(0.2)
		check(body_inside(unit,bounds,unit.global_position) and unit.global_position.y>edge.y,"entire body remains within map under outward tracking "+str(side))
	# Ground movement remains old roaming/input behavior; no grounded chase.
	unit._cancel_slam()
	unit.slam_phase = unit.SlamPhase.GROUND
	unit.global_position = Vector2(center.x,bounds.end.y-unit.body_half_size().y)
	unit.player_control_direction = Vector2.RIGHT
	target.global_position = center+Vector2(-100,0)
	var ground_x:float = unit.global_position.x
	unit.step_mob(0.1)
	check(unit.global_position.x>ground_x and unit._fall_tracking_velocity(0.1)==0.0,"landed actor follows right input rather than chasing target left")
	# Coarse/fine schedules and tuned speed use identical bounded integration.
	target.global_position = center+Vector2(100,0)
	var fine:Node2D = anvil(start)
	check(drop_fixture(unit,target,start) and drop_fixture(fine,target,start),"coarse/fine setup")
	unit.fall_track_speed = 17.0
	fine.fall_track_speed = 17.0
	replica.accept_visual(unit.network_visual_state())
	check(is_equal_approx(replica.fall_track_speed,17.0),"snapshot carries configured slow speed")
	unit.step_mob(0.13)
	for i:int in range(13): fine.step_mob(0.01)
	check(unit.global_position.distance_to(fine.global_position)<0.04 and absf(unit.global_position.x-start.x-(8.5*0.13-8.5*8.5/(2.0*600.0)))<0.03,"coarse/fine frames agree on slow pursuit distance")
	fine.free()
	unit.fall_track_speed = 80.0
	# Islands remain isolated even when target moves to another portal island.
	var portal_name:String = ""
	for key:Variant in world.map_group:
		var map:Node = world.map_group[key]
		if map!=null and map.has_method("island_entries") and map.island_entries().size()>=2:
			portal_name = str(key)
			break
	if not portal_name.is_empty():
		world.now_choose_map = portal_name
		world.refresh_map_presentation()
		var islands:Array = world.map_group[portal_name].island_entries()
		var source_rect:Rect2 = islands[0].rect
		target.global_position = islands[1].rect.get_center()
		check(drop_fixture(unit,target,source_rect.get_center()),"cross-island jump remains allowed locally")
		var island_x:float = unit.global_position.x
		unit.step_mob(0.02)
		check(not unit._fall_track_valid and absf(unit.global_position.x-island_x)<0.01 and body_inside(unit,source_rect,unit.global_position),"falling never tracks an enemy across inter-island void")
		world.now_choose_map = "Map50x50"
		world.refresh_map_presentation()
	else: check(false,"portal island fixture is required")
	target.global_position = center+Vector2(100,0)
	check(drop_fixture(unit,target,start),"skill cancellation setup")
	unit.Can_Skill = false
	unit.step_mob(0.01)
	check(not unit._active_slam and not unit._fall_track_valid,"cancellation clears tracking state")
	unit.Can_Skill = true
	check(drop_fixture(unit,target,start),"death setup")
	unit.health = 0.0
	unit.Die()
	check(unit.velocity==Vector2.ZERO and not unit._fall_track_valid,"death clears tracking and velocity")
	print("ANVIL_FALL_TRACK_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
