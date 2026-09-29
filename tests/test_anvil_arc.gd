extends "res://tests/test_anvil_bounce_audio.gd"
## Bounded parabolic jumps and real swept terrain collisions, including replicas.
func layers(unit:Node) -> Array[int]:
	return [unit.collision_layer,unit.collision_mask,unit.self_hitbox.collision_layer,unit.self_hitbox.collision_mask,unit.self_hurtbox.collision_layer,unit.self_hurtbox.collision_mask]
func query_sees(unit:Node2D) -> bool:
	var circle := CircleShape2D.new()
	circle.radius = 1.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0,unit.global_position)
	query.collision_mask = 2
	query.collide_with_areas = true
	query.collide_with_bodies = true
	for item:Dictionary in unit.get_world_2d().direct_space_state.intersect_shape(query,32):
		if item.collider==unit or item.collider==unit.self_hurtbox or item.collider==unit.self_hitbox: return true
	return false
func body_inside(unit:Node2D,bounds:Rect2,point:Vector2) -> bool:
	var half:Vector2 = unit.body_half_size()
	return bounds.grow(0.01).encloses(Rect2(point-half,half*2.0))
func planned_inside(unit:Node2D,bounds:Rect2) -> bool:
	for i:int in range(257):
		if not body_inside(unit,bounds,unit.jump_position(float(i)/256.0)): return false
	return true
func restart_jump(unit:Node2D,target:Node2D,point:Vector2) -> bool:
	unit._cancel_slam()
	unit.global_position = point
	unit.Repel = Vector2.ZERO
	unit.cooldown_left = 0.0
	return unit.begin_slam(target)
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
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"bounded jump preloads complete")
	var bounds:Rect2 = world.return_map_world_rect(world.map_group["Map50x50"])
	center = bounds.get_center()
	var start:Vector2 = center+Vector2(-100,70)
	var unit:Node2D = anvil(start)
	unit.fall_track_acceleration = 0.0 # Isolate reference arc/terrain geometry; pursuit has its own suite.
	var target:Node2D = dummy(center+Vector2(100,0))
	await physics_frame
	await process_frame
	var normal_layers:Array[int] = layers(unit)
	var normal_z:int = unit.image.z_index
	var normal_scale:Vector2 = unit.scale
	check(query_sees(unit) and unit.is_combat_targetable(),"normal anvil has real body/hurtbox collision")
	check(unit.begin_slam(target),"bounded parabolic skill starts")
	var launch_goal:Vector2 = unit._jump_to
	var finish_point:Vector2 = unit.jump_position(1.0)
	check(unit.global_position==start and unit.phase_elapsed==0.0,"starting skill does not teleport")
	check(unit._jump_total_time>=0.5,"normal jump retains visible travel duration")
	check(unit.jump_position(0.0).is_equal_approx(start) and unit.jump_position(1.0).is_equal_approx(finish_point),"parabola connects the fixed launch and scaled impulse reference endpoint")
	var top_phase:float = clampf((4.0*unit._jump_arc_height-(finish_point.y-start.y))/maxf(8.0*unit._jump_arc_height,0.001),0.0,1.0)
	var top:Vector2 = unit.jump_position(top_phase)
	check(planned_inside(unit,bounds) and body_inside(unit,bounds,top),"entire body and analytical apex stay inside the map, not just the endpoint")
	check(top.y>=bounds.position.y+unit.body_half_size().y+0.49,"arc clearance shrinks to the available ceiling headroom")
	check(unit.jump_velocity(0.0).y<0.0 and unit.jump_velocity(1.0).y>0.0,"bounded arc still rises and then descends onto its endpoint")
	var jump_layers:Array[int] = normal_layers.duplicate()
	jump_layers[0] &= ~2
	jump_layers[1] &= ~2
	check(layers(unit)==jump_layers and unit.is_combat_targetable() and unit.is_combat_lockable(),"jump ignores only character body layer/mask while preserving hit/hurt targeting")
	check(unit.image.z_index==normal_z and not unit.has_meta("submission_allow_map_escape"),"jump needs neither above-mask rendering nor a map-escape exemption")
	var hp:float = target.health
	unit.step_mob(unit._jump_total_time*0.25)
	check(unit.global_position.distance_to(unit.jump_position(0.25))<0.03,"unobstructed first quarter follows the planned parabola")
	check(unit.global_position.y<start.lerp(finish_point,0.25).y-10.0,"jump remains curved rather than a straight-line teleport")
	await physics_frame
	await process_frame
	check(query_sees(unit),"real physics queries still see the anvil during flight")
	var paused:Vector2 = unit.global_position
	var paused_time:float = unit.phase_elapsed
	game.now_stop_state = true
	unit.step_mob(1.0)
	check(unit.global_position==paused and unit.phase_elapsed==paused_time,"pause freezes the collidable airborne arc")
	game.now_stop_state = false
	target.global_position.x += 60.0
	unit.step_mob(unit._jump_total_time*0.25)
	check(unit._jump_to==launch_goal and unit.global_position.distance_to(unit.jump_position(0.5))<0.03,"with pursuit disabled, reference impulse stays fixed despite target movement")
	check(target.health==hp and unit.hit_count==0,"rising does not cause premature slam damage")
	check(not unit._damage_with_feedback(target,100.0,target.global_position) and unit._apply_impact_knockback(target,600.0)==null,"rising cannot originate impact damage or knockback")
	unit.set_large_battle_performance_mode(true)
	check(layers(unit)==jump_layers and unit.get_collision_mask_value(1),"large-battle mode preserves terrain and hurtbox collisions during flight")
	unit.set_large_battle_performance_mode(false)
	check(layers(unit)==jump_layers,"leaving optimized mode keeps jump character pass-through active")
	var replica:Node2D = anvil(center+Vector2(250,100))
	replica.set_multiplayer_authority(2)
	replica.accept_visual(unit.network_visual_state())
	check(replica.global_position.distance_to(unit.global_position)<0.01 and layers(replica)==jump_layers,"replica applies the same jump pass-through while keeping terrain/hurtbox enabled")
	var expected:Vector2 = unit.jump_position((unit.phase_elapsed+0.05)/unit._jump_total_time)
	replica.client_visual_step(0.05)
	check(replica.global_position.distance_to(expected)<0.03,"replica interpolates the same bounded parabola")
	unit.step_mob(maxf(unit._jump_total_time*top_phase-unit.phase_elapsed,0.0))
	var apex_position:Vector2 = unit.global_position
	var own_hp:float = unit.health
	world._process_map_squeeze_protection([unit])
	world._process_out_of_bounds_rule(4.0,[unit])
	check(body_inside(unit,bounds,apex_position) and unit.global_position==apex_position and not bool(unit.get_meta("map_rescue_animating",false)),"bounded apex does not trigger real map rescue")
	check(unit.health==own_hp and not world._out_of_bounds_states.has(unit.get_instance_id()),"bounded apex triggers no escape countdown without an exemption")
	unit.step_mob(unit._jump_total_time-unit.phase_elapsed)
	check(unit.slam_phase==unit.SlamPhase.FALLING and unit.global_position.distance_to(finish_point)<0.03 and layers(unit)==normal_layers and unit.image.z_index==normal_z,"arc completion directly enters falling at the fixed endpoint without a hover frame")
	var release_speed:float = clampf(unit.jump_velocity(1.0).y,0.0,unit.terminal_speed)
	check(release_speed>0.0 and absf(unit.fall_speed-release_speed)<0.03 and is_equal_approx(unit.velocity.x,unit._launch_horizontal_speed),"release preserves both initial horizontal and downward velocity")
	unit.step_mob(1.0/120.0)
	var first_drop:float = release_speed/120.0+0.5*unit.gravity_acceleration/(120.0*120.0)
	check(absf(unit.global_position.y-(finish_point.y+first_drop))<0.03 and absf(unit.global_position.x-finish_point.x-unit._launch_horizontal_speed/120.0)<0.03,"next step falls immediately and keeps uncancelled impulse")
	replica.client_visual_step(replica._jump_total_time-replica.phase_elapsed)
	check(replica.slam_phase==replica.SlamPhase.FALLING and replica.global_position.distance_to(finish_point)<0.03 and absf(replica.fall_speed-release_speed)<0.03,"replica also releases immediately with continuous downward speed")
	var replica_position:Vector2 = replica.global_position
	var replica_hits:int = replica.hit_count
	replica.client_visual_step(1.0/60.0)
	check(replica.global_position.y>replica_position.y+0.1 and replica.hit_count==replica_hits and target.health==hp,"replica continues gravity between snapshots without duplicate damage")

	# Non-aligned duration ends inside a physics step: the unused time must fall.
	unit.jump_duration = 0.653
	check(restart_jump(unit,target,start),"fractional-step release setup starts")
	var endpoint:Vector2 = unit.jump_position(1.0)
	release_speed = clampf(unit.jump_velocity(1.0).y,0.0,unit.terminal_speed)
	var tail:float = 1.0/240.0
	unit.step_mob(unit._jump_total_time+tail)
	var expected_y:float = endpoint.y+release_speed*tail+0.5*unit.gravity_acceleration*tail*tail
	check(unit.slam_phase==unit.SlamPhase.FALLING and absf(unit.global_position.y-expected_y)<0.03 and absf(unit.fall_speed-(release_speed+unit.gravity_acceleration*tail))<0.03,"completion consumes the same frame's remaining time rather than inserting a hidden delay")
	var fine:Node2D = anvil(start)
	fine.fall_track_acceleration = 0.0
	fine.jump_duration = 0.653
	check(fine.begin_slam(target),"fine-step release comparison starts")
	var time_left:float = fine._jump_total_time+tail
	var saw_hover:bool = false
	while time_left>0.000001:
		var step:float = minf(time_left,1.0/240.0)
		fine.step_mob(step)
		saw_hover = saw_hover or fine.slam_phase==fine.SlamPhase.HOVER
		time_left -= step
	check(not saw_hover and fine.global_position.distance_to(unit.global_position)<0.03 and absf(fine.fall_speed-unit.fall_speed)<0.03,"fine/coarse schedules release continuously with the same position and speed and no HOVER state")
	fine.queue_free()
	unit.jump_duration = 0.65

	# A real ceiling stops the ascent at its underside, with no hover/teleport.
	target.global_position = center+Vector2(100,0)
	check(restart_jump(unit,target,start),"ceiling collision setup starts a real jump")
	var launch_state:Dictionary = unit.network_visual_state()
	var ceiling:StaticBody2D = obstacle(unit.jump_position(0.2),Vector2(200,4))
	await physics_frame
	await process_frame
	var clang_count:int = unit.obstacle_impact_count
	advance_until(unit,func(): return unit.slam_phase!=unit.SlamPhase.RISING,1.0)
	var contact:Vector2 = unit.global_position
	check(unit.slam_phase==unit.SlamPhase.FALLING and unit.phase_elapsed==0.0 and unit.velocity.y==0.0 and is_equal_approx(unit.velocity.x,unit._launch_horizontal_speed),"ceiling removes upward motion but preserves horizontal impulse")
	check(contact.y-unit.body_half_size().y>=ceiling.global_position.y+2.0-0.02,"real swept body stops below the ceiling instead of passing through it")
	check(contact.distance_to(unit._jump_to)>20.0 and body_inside(unit,bounds,contact),"blocked jump stays at contact instead of snapping to the map top")
	replica.accept_visual(launch_state)
	replica.client_visual_step(0.4)
	check(replica.slam_phase==replica.SlamPhase.FALLING and replica.global_position.x>=contact.x-0.05 and replica.global_position.x<=contact.x+absf(unit._launch_horizontal_speed)*0.4+0.05 and replica.global_position.y>contact.y and replica.global_position.y-replica.body_half_size().y>=ceiling.global_position.y+1.98,"replica hits the same ceiling and immediately predicts a downward fall rather than freezing until a packet")
	unit.step_mob(0.08)
	check(unit.global_position.y>contact.y+0.2 and absf(unit.global_position.x-contact.x-unit._launch_horizontal_speed*0.08)<0.04 and unit.fall_speed>0.0,"ceiling contact falls immediately while keeping tangent momentum")
	check(unit.obstacle_impact_count==clang_count,"upward ceiling contact does not play a downward landing clang")
	replica.accept_visual(unit.network_visual_state())
	check(replica.slam_phase==replica.SlamPhase.FALLING and replica.global_position.distance_to(unit.global_position)<0.01,"interrupted-arc snapshot places the replica at the actual drop position")
	ceiling.queue_free()
	await physics_frame
	await process_frame

	# A one-unit wall must stop both ordinary and very fast/coarse-step jumps.
	var wall:StaticBody2D = obstacle(Vector2(start.x+50.0,center.y),Vector2(1.0,bounds.size.y))
	await physics_frame
	await process_frame
	check(restart_jump(unit,target,start),"side-wall setup starts a real jump")
	advance_until(unit,func(): return unit.slam_phase!=unit.SlamPhase.RISING,1.0)
	contact = unit.global_position
	check(unit.slam_phase==unit.SlamPhase.FALLING and contact.x+unit.body_half_size().x<=wall.global_position.x-0.49,"thin side wall stops the entire body and immediately releases a slam")
	unit.step_mob(0.1)
	check(unit.global_position.y>contact.y+0.5 and absf(unit.global_position.x-contact.x)<0.03,"side-wall contact does not leave the anvil stuck or sliding toward its old destination")
	unit.jump_duration = 0.05
	check(restart_jump(unit,target,start),"fast-jump setup starts")
	unit.step_mob(0.1)
	check(unit.slam_phase==unit.SlamPhase.FALLING and unit.global_position.x+unit.body_half_size().x<=wall.global_position.x-0.49 and body_inside(unit,bounds,unit.global_position),"high-speed jump and coarse caller delta cannot tunnel through a one-unit wall")
	unit.jump_duration = 0.65
	wall.queue_free()
	await physics_frame
	await process_frame

	# Existing support is not a new obstruction while moving away from the floor.
	var floor:StaticBody2D = obstacle(start+Vector2(0,unit.body_half_size().y+3.0),Vector2(250,6))
	await physics_frame
	await process_frame
	check(restart_jump(unit,target,start),"supported anvil can begin another jump")
	unit.step_mob(1.0/120.0)
	check(unit.slam_phase==unit.SlamPhase.RISING and unit.global_position.y<start.y,"takeoff from supporting terrain is not mistaken for an obstacle hit")
	floor.queue_free()
	await physics_frame
	await process_frame

	# Tiny top padding, large requested clearance, both edges and enlarged bodies.
	unit.top_padding = 0.0
	unit.jump_clearance = 180.0
	for edge:int in range(3):
		unit.scale = normal_scale*(1.8 if edge==2 else 1.0)
		var half:Vector2 = unit.body_half_size()
		var point:Vector2 = Vector2(bounds.position.x+half.x+0.75,bounds.position.y+half.y+0.75)
		if edge==1: point = Vector2(bounds.end.x-half.x-0.75,center.y+70.0)
		if edge==2: point.y = center.y+70.0
		target.global_position = Vector2(bounds.position.x+1.0 if edge==1 else bounds.end.x-1.0,center.y)
		check(restart_jump(unit,target,point),"edge/scale jump starts: "+str(edge))
		check(planned_inside(unit,bounds),"whole planned arc respects body-sized map insets: "+str(edge))
		var remained_inside:bool = true
		for tick:int in range(120):
			if unit.slam_phase!=unit.SlamPhase.RISING: break
			unit.step_mob(1.0/120.0)
			remained_inside = remained_inside and body_inside(unit,bounds,unit.global_position)
		check(remained_inside and not unit.has_meta("submission_allow_map_escape"),"every actual edge/scale jump step stays inside without an escape exemption: "+str(edge))
	unit.scale = normal_scale
	unit.top_padding = 4.0
	unit.jump_clearance = 48.0
	target.global_position = center+Vector2(100,0)

	# Disconnected maps must use the launch island, not fly across the empty union.
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
		var other_rect:Rect2 = islands[1].rect
		target.global_position = other_rect.get_center()
		check(restart_jump(unit,target,source_rect.get_center()),"cross-island target still permits a bounded local jump")
		check(unit._drop_bounds==source_rect and planned_inside(unit,source_rect),"cross-island target cannot pull the arc outside its launch island")
		var stayed_on_island:bool = true
		for tick:int in range(120):
			if unit.slam_phase!=unit.SlamPhase.RISING: break
			unit.step_mob(1.0/120.0)
			stayed_on_island = stayed_on_island and body_inside(unit,source_rect,unit.global_position)
		check(stayed_on_island,"actual disconnected-map jump never enters the inter-island void")
		world.now_choose_map = "Map50x50"
		world.refresh_map_presentation()
	else:
		print("SKIP: no disconnected portal map available in this World fixture")
	target.global_position = center+Vector2(100,0)
	check(restart_jump(unit,target,start),"cancellation setup starts")
	unit.step_mob(unit._jump_total_time*0.4)
	unit.Can_Skill = false
	unit.step_mob(0.01)
	check(not unit._active_slam and layers(unit)==normal_layers and body_inside(unit,bounds,unit.global_position),"cancelled jump stays collidable and inside the map")
	unit.Can_Skill = true
	check(restart_jump(unit,target,start),"death setup starts")
	unit.health = 0.0
	unit.Die()
	check(not unit._active_slam and not unit.Using_Skill and unit.velocity==Vector2.ZERO and not unit.has_meta("submission_allow_map_escape"),"death stops the jump without leaking temporary map-escape state")
	print("ANVIL_ARC checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
