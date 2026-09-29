extends "res://tests/test_drowned_surface_probe.gd"
var counter:int = 1000
func fresh_spear() -> Node2D:
	counter += 1
	return new_spear(counter)
func run() -> void:
	await setup_probe()
	create_timer(65.0).timeout.connect(func(): finish(2))
	for heading:Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
		caster.global_position = center
		var size_value := Vector2(12,160) if heading.x != 0.0 else Vector2(160,12)
		var wall:StaticBody2D = make_wall(center+heading*120.0,size_value)
		await physics_frame
		var spear:Node2D = fresh_spear()
		var aim:Vector2 = center+heading*98.0
		spear.launch(heading,center,aim)
		check(not spear.landing_wall_ahead(aim).is_empty(),"near wall is found only in the forward corridor: "+str(heading))
		advance_until_stuck(spear)
		check(spear.flight_state == 3 and not spear.planted and spear.wall_ref != null and spear.wall_ref.get_ref() == wall,"four-direction endpoint lodges in the actual wall: "+str(heading))
		check(spear.traveled >= 113.0 and spear.traveled <= 115.0,"wall contact accounts for the final small flight, not a remote snap")
		var old_point:Vector2 = spear.global_position
		wall.global_position += Vector2(4,6)
		spear.advance(0.01)
		check(spear.global_position.is_equal_approx(old_point+Vector2(4,6)),"lodged trident follows its existing wall-local anchor")
		wall.queue_free()
		await process_frame
		spear.advance(0.01)
		check(spear.is_queued_for_deletion(),"removing the support still retires the wall-lodged trident")
		await physics_frame

	# Being near a wall alone is not enough.
	caster.global_position = center
	var side_wall:StaticBody2D = make_wall(center+Vector2(16,-90),Vector2(10,180))
	await physics_frame
	var parallel:Node2D = fresh_spear()
	parallel.launch(Vector2.UP,center,center+Vector2(0,-90))
	check(parallel.landing_wall_ahead(parallel.aim_point).is_empty(),"a parallel side wall cannot steal the landing")
	advance_until_stuck(parallel)
	check(parallel.planted and parallel.plant_contact_point().distance_to(parallel.aim_point) < 1.0,"parallel near-wall throw remains a normal ground plant")
	side_wall.queue_free()
	parallel.retire()
	await physics_frame
	# Terminal decision with a wall appearing behind the already-arrived spear.
	var away:Node2D = fresh_spear()
	away.launch(Vector2.LEFT,center+Vector2(30,0),center)
	away.global_position = center
	away.traveled = away.flight_length
	var behind:StaticBody2D = make_wall(center+Vector2(16,0),Vector2(10,100))
	await physics_frame
	check(away.landing_wall_ahead(center).is_empty(),"behind-facing wall is not selected at arrival")
	away._fly_out(0.016)
	check(away.planted and not away.ground_seek,"spear pointing away from a close wall lands on the ground")
	away.retire()
	behind.queue_free()
	await physics_frame

	var far_wall:StaticBody2D = make_wall(center+Vector2(140,0),Vector2(12,120))
	await physics_frame
	var far:Node2D = fresh_spear()
	far.launch(Vector2.RIGHT,center,center+Vector2(98,0))
	check(far.landing_wall_ahead(far.aim_point).is_empty(),"wall farther than one block is not a nearby endpoint surface")
	advance_until_stuck(far)
	check(far.planted and far.plant_contact_point().distance_to(far.aim_point) < 1.0,"distant wall does not make the spear abandon its locked destination")
	far.retire()
	far_wall.queue_free()
	await physics_frame

	# A short extension is still a flight: another actor in the gap must be hit.
	var guarded_wall:StaticBody2D = make_wall(center+Vector2(130,0),Vector2(12,120))
	var guard:Node2D = dummy(center+Vector2(115,0),"Team1")
	guard.scale = Vector2.ONE*0.04
	await physics_frame
	var contact:Node2D = fresh_spear()
	contact.launch(Vector2.RIGHT,center,center+Vector2(100,0))
	var hp:float = guard.health
	var time:float = 0.0
	while contact.flight_state == 1 and time < 2.0:
		contact.advance(1.0/120.0)
		time += 1.0/120.0
	print("DROWNED_GAP_CONTACT seek=",contact.ground_seek," phase=",contact.flight_state," hp=",guard.health," before=",hp," traveled=",contact.traveled," target_radius=",guard.get_crowd_separation_radius_world()," hit_point=",contact.global_position," target=",guard.global_position)
	check(contact.ground_seek and contact.flight_state == 2 and guard.health < hp,"actor in the final wall gap is hit normally rather than skipped by teleporting")
	contact.retire()
	guard.queue_free()
	guarded_wall.queue_free()
	await physics_frame
	for dt:float in [1.0/30.0,1.0/120.0,0.75]:
		var wall:StaticBody2D = make_wall(center+Vector2(120,0),Vector2(12,140))
		await physics_frame
		var sample:Node2D = fresh_spear()
		sample.launch(Vector2.RIGHT,center,center+Vector2(98,0))
		for i:int in range(150):
			if sample.flight_state != 1: break
			sample.advance(dt)
		check(sample.flight_state == 3 and not sample.planted,"near-wall behavior is independent of frame size: "+str(dt))
		sample.retire()
		wall.queue_free()
		await physics_frame
	var saved_range:float = caster.trident_range
	caster.trident_range = 70.0
	var capped:Node2D = fresh_spear()
	capped.launch(Vector2.RIGHT,center,center+Vector2(400,0))
	advance_until_stuck(capped)
	check(capped.planted and capped.plant_contact_point().distance_to(center+Vector2(70,0)) < 1.0,"endpoint resolution cannot jump from a range-capped flight to a far raw aim point")
	caster.trident_range = saved_range
	capped.retire()

	# One-shot debris replay is independent of weapon lifetime and packet repeats.
	var planted:Node2D = fresh_spear()
	planted.launch(Vector2.RIGHT,center-Vector2(80,90),center-Vector2(0,90))
	planted.stick_ground(center-Vector2(0,90))
	var data:Dictionary = planted.snapshot()
	var count:int = get_nodes_in_group("MCTridentGroundDebris").size()
	var replica:Node2D = fresh_spear()
	replica.receive(data)
	check(get_nodes_in_group("MCTridentGroundDebris").size() == count+1,"recent remote ground landing creates its visible impact once")
	replica.receive(data)
	check(get_nodes_in_group("MCTridentGroundDebris").size() == count+1,"repeated state snapshots do not duplicate the block burst")
	var stale:Dictionary = data.duplicate(true)
	stale.ground_impact_age = 5.0
	var late_join:Node2D = fresh_spear()
	late_join.receive(stale)
	check(get_nodes_in_group("MCTridentGroundDebris").size() == count+1,"old permanently planted poles do not replay impact particles on late state reconstruction")
	var debris:Node2D
	for node:Node in get_nodes_in_group("MCTridentGroundDebris"):
		if int(node.get_meta("mc_trident_source_id",0)) == planted.get_instance_id(): debris = node
	check(is_instance_valid(debris) and debris.get_parent() != planted and debris.block_source_min_count == 5 and debris.block_source_max_count == 8 and debris.block_max_size == 3.6,"trident uses the actual mace block preset in an independent battle effect")
	var elapsed:float = debris._elapsed
	game.now_stop_state = true
	debris._process(3.0)
	check(debris._elapsed == elapsed,"pause cannot consume the ground burst's visible lifetime")
	game.now_stop_state = false
	planted.retire()
	await process_frame
	check(is_instance_valid(debris),"collecting/retiring the weapon cannot cut off its ground-impact burst")
	# Rendering-state exits must reset body, glint and procedural-arc clipping.
	replica.charged = true
	replica.charge_visual.advance(0.08)
	check(float(replica.charge_visual.arc_material.get_shader_parameter("plant_clip")) > 0.5,"procedural electric strokes use the same ground clipping contract")
	replica._begin_return()
	replica.charge_visual.advance(0.0)
	check(float(replica.material.get_shader_parameter("plant_clip")) < 0.5 and float(replica.charge_visual.glint_material.get_shader_parameter("plant_clip")) < 0.5 and float(replica.charge_visual.arc_material.get_shader_parameter("plant_clip")) < 0.5,"leaving the ground clears clipping on all three render layers")
	replica.retire()
	late_join.retire()
	print("DROWNED_SURFACE_RULES checks=",checks," failures=",failures)
	finish(0 if failures == 0 else 1)
