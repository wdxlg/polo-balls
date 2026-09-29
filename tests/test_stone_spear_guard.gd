extends "res://tests/test_stone_spear.gd"
func incoming_at(unit:Node2D,point:Vector2,radius:float=1.0) -> Node2D:
	var hit:Node2D=unit.self_hitbox
	hit.monitoring=false
	hit.global_scale=Vector2.ONE
	hit.global_position=point
	var shape:=CircleShape2D.new()
	shape.radius=radius
	hit.get_node("CollisionShape2D").shape=shape
	hit.get_node("CollisionShape2D").disabled=false
	hit._last_hit_msec_by_target.clear()
	return hit
func run() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	game=root.get_node("Game")
	game.now_stop_state=false
	game.Game_Settings.Have_Team_Damage=false
	AudioServer.set_bus_mute(0,true)
	arena=Node2D.new()
	root.add_child(arena)
	current_scene=arena
	arena.process_mode=Node.PROCESS_MODE_DISABLED
	spear=load("res://scenes/characters/我的世界/石矛.tscn").instantiate()
	spear.Team="Team0"
	spear.disable_mode=CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	arena.add_child(spear)
	check(spear.follow_cohesion_reference_speed==45.0,"follow response still uses the faster curve")
	for speed_value:float in [0.0,30.0,45.0,102.0,180.0,300.0,1000.0]:
		check(is_equal_approx(spear.follow_cohesion(speed_value),spear.cohesion(speed_value*4.0)),"four times earlier follow response at %s" % speed_value)
		for i:int in range(4):
			var open_gap:float=16.0*(1.0+i%2)
			var actual:float=spear.formation_pose(i,speed_value).offset.length()
			check(actual<=open_gap+0.0001,"follow spacing stays within the fully open layout")
			check(actual>=0.0 and (speed_value<spear.follow_merge_speed or actual==0.0),"follow spacing reaches zero at full gathering")
	check(spear.follow_response(1,102.0)>26.0,"outer copy responds promptly already at birth speed")
	check(spear.follow_response(0,102.0)>spear.follow_response(1,102.0),"outer rank retains slightly longer lag")
	# Production integration still approaches the new radius smoothly.
	for fps:float in [30.0,60.0,120.0]:
		Engine.physics_ticks_per_second=int(fps)
		await physics_frame
		await process_frame # Allow move_and_slide to use the newly selected engine timestep.
		reset_pose()
		spear.Speed=300.0 # actual 180: gathering now starts ABOVE birth speed
		spear.movement_growth=0.0
		var before:float=absf(spear._centers[1].y)
		await physics_frame
		spear.tick_physics(spear.State.Move,1.0/fps)
		check(absf(spear._real_speed-180.0)<0.05,"guard fixture uses actual 180 movement speed at the selected physics rate")
		var desired:float=absf(spear.formation_pose(1,spear._real_speed).offset.y)
		check(absf(spear._centers[1].y)<before and absf(spear._centers[1].y)>desired,"first movement frame is an intermediate pose at %s Hz" % fps)
		for frame:int in range(int(fps*0.2)):
			await physics_frame
			spear.tick_physics(spear.State.Move,1.0/fps)
		check(absf(absf(spear._centers[1].y)-desired)<0.15,"outer copy settles within 0.2 seconds after accelerating above birth speed")
		check(spear._copies[1].global_position.is_equal_approx(spear._centers[1]),"faster contraction moves actual geometry and sprite together")
	Engine.physics_ticks_per_second=60
	spear.Speed=170.0
	spear.movement_growth=10.0
	reset_pose(1)
	check(spear._tip_guards.size()==4,"exactly four guard hurtboxes, not a body shield")
	var enemy:Node2D=victim(Vector2(200,200))
	enemy.Can_Attack=true
	enemy.Damage=20
	await process_frame
	for i:int in range(4):
		var guard:Node2D=spear._tip_guards[i]
		var point:Vector2=spear._centers[i]+Vector2.from_angle(spear._angles[i])*spear.tip_distance()
		check(guard.global_position.is_equal_approx(point),"guard center equals visible simulated spearhead")
		check(guard.collision_layer==2 and guard.get_parent()==spear,"guard uses public hurtbox ownership and layer")
		var hit:Node2D=incoming_at(enemy,point)
		var hp:int=spear.health
		var count:int=spear.guard_feedback_count
		spear._guard_feedback_until.clear()
		check(not hit.try_hit_hurtbox(guard),"public melee contact rejected at copy tip")
		check(spear.health==hp and is_instance_valid(enemy) and not enemy.is_queued_for_deletion(),"block prevents health loss without deleting melee attacker")
		check(spear.guard_feedback_count==count+1 and spear.last_guard_position.is_equal_approx(point),"wooden-spear block feedback at touched tip")
		check(not hit.try_hit_hurtbox(guard) and spear.guard_feedback_count==count+1,"duplicate contact bypass does not duplicate feedback")
	# Real physics Area2D entry, not only a direct call to the public contact hook.
	var physical:Node2D=victim(Vector2(-300,-300))
	physical.Can_Attack=true
	var physical_hit:Node2D=incoming_at(physical,Vector2(-300,-300))
	physical_hit.disable_mode=CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	physical_hit.collision_mask=2
	physical_hit.monitoring=true
	await physics_frame
	await process_frame
	var auto_before:int=spear.guard_feedback_count
	var auto_hp:int=spear.health
	physical_hit.global_position=spear._tip_guards[1].global_position
	await physics_frame
	await physics_frame
	await process_frame
	check(spear.guard_feedback_count==auto_before+1 and spear.health==auto_hp,"actual physics area entry triggers tip block exactly once")
	physical.queue_free()
	# Huge attacks touching a tip are blocked even when body callback comes first.
	var hit:Node2D=incoming_at(enemy,Vector2.ZERO,40.0)
	spear._guard_feedback_until.clear()
	var hp:int=spear.health
	var count:int=spear.guard_feedback_count
	check(not hit.try_hit_hurtbox(spear.self_hurtbox) and spear.health==hp,"large hit body-first order still respects actual tip overlap")
	for guard:Node2D in spear._tip_guards: hit.try_hit_hurtbox(guard)
	check(spear.guard_feedback_count==count+1,"one attack across body and all four tips has one feedback")
	# No nearest-tip approximation: shaft, central body, main tip and gaps are open.
	for point:Vector2 in [Vector2.ZERO,Vector2(15,0),Vector2(0,-16),Vector2(20,20)]:
		hit=incoming_at(enemy,point,0.3)
		check(spear.can_receive_hit_contact(hit,spear.self_hurtbox),"non-tip point is not protected: %s" % point)
	hit=incoming_at(enemy,Vector2.ZERO,1.0)
	hp=spear.health
	check(hit.try_hit_hurtbox(spear.self_hurtbox) and spear.health<hp,"unprotected body still takes real melee damage")
	# Follow and thrust do not inherit the new contact shield; stale guard callbacks are inert.
	for form:int in [0,2]:
		reset_pose(form)
		for guard:Node2D in spear._tip_guards: check(guard.collision_layer==0,"non-orbit guard not registered for collision")
		hit=incoming_at(enemy,spear._tip_guards[0].global_position)
		check(spear.can_receive_hit_contact(hit,spear.self_hurtbox),"other stance body has no orbit defense")
		count=spear.guard_feedback_count
		check(not hit.try_hit_hurtbox(spear._tip_guards[0]) and spear.guard_feedback_count==count,"stale guard callback has no block feedback")
	reset_pose(1)
	# Switching in and out updates defense immediately but does not snap the copies.
	var old_centers:Array=spear._centers.duplicate()
	check(spear.set_formation(0),"switch out succeeds")
	check(spear._tip_guards[0].collision_layer==0 and spear._centers==old_centers,"switch out removes guard immediately without snapping")
	check(spear.set_formation(1),"switch into orbit succeeds")
	check(spear._tip_guards[0].collision_layer==2 and spear._centers==old_centers,"transition guard follows the still-visible tip, not the future orbit")
	# Same passive behavior as wood, independent of offensive permissions.
	spear.dizziness=true
	spear.Can_Attack=false
	hit=incoming_at(enemy,spear._tip_guards[0].global_position)
	check(not spear.can_receive_hit_contact(hit,spear._tip_guards[0]),"passive tip guard survives stun and disabled attack like wood")
	spear.dizziness=false
	spear.Can_Attack=true
	game.now_stop_state=true
	count=spear.guard_feedback_count
	hit.try_hit_hurtbox(spear._tip_guards[0])
	check(spear.guard_feedback_count==count,"pause does not emit block feedback")
	game.now_stop_state=false
	# Friendly projectile is untouched, real enemy Shooter follows public disposal.
	for team:String in ["Team0","Team1"]:
		var shot:Node2D=victim(Vector2(300,300),team)
		shot.Type=shot.Ball_Type.Shooter
		shot.Speed=200.0
		shot.direction=Vector2.RIGHT
		var shot_hit:Node2D=incoming_at(shot,spear._tip_guards[2].global_position)
		hp=spear.health
		shot_hit.try_hit_hurtbox(spear._tip_guards[2])
		check(spear.health==hp,"projectile tip contact never damages defender")
		check(shot.Speed==(200.0 if team=="Team0" else 0.0),"team filtering and projectile stop use public rules")
		await process_frame
		if team=="Team1": check(not is_instance_valid(shot) or shot.is_queued_for_deletion() or shot.state_machine.current_state==shot.State.Die,"enemy projectile enters public deferred disposal")
		else:
			check(is_instance_valid(shot) and not shot.is_queued_for_deletion(),"friendly projectile is not destroyed")
			shot.queue_free()
	await process_frame
	var found_audio:bool=false
	for player:Node in get_nodes_in_group("MCNativeSFX"):
		if player.get_meta("mc_sound_event","")=="stone_spear.block":
			found_audio=true
			check(player.stream==spear.BLOCK_SFX and is_equal_approx(player.volume_db,-1.0),"original wooden-spear block audio and gain reused")
	check(found_audio,"real guard emitted audio through shared safe queue")
	check(not get_nodes_in_group("MCExpandingRing").is_empty(),"contact emits short white ring through shared effect")
	check(spear.SPEED_DAMAGE_FACTOR==0.25 and spear.body_turn_degrees_per_second==3600.0,"damage nerf and 0.05-second U-turn preserved")
	# Death and despawn do not leave orphan guard shapes.
	spear.health=0
	hit=incoming_at(enemy,spear._tip_guards[0].global_position)
	count=spear.guard_feedback_count
	hit.try_hit_hurtbox(spear._tip_guards[0])
	check(spear.guard_feedback_count==count,"dead actor cannot block or play feedback")
	var guard_refs:Array=spear._tip_guards.duplicate()
	spear.queue_free()
	await process_frame
	for guard:Variant in guard_refs: check(not is_instance_valid(guard),"guard removed with character")
	print("STONE_GUARD_RESULT checks=%d failures=%d" % [checks,failures])
	arena.queue_free()
	await physics_frame # Flush death-resolution coroutines before ending the fixture.
	await create_timer(0.25).timeout # Let deferred audio/feedback teardown finish.
	await process_frame
	await process_frame
	quit(0 if failures==0 else 1)
