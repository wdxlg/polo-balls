extends "res://tests/test_anvil_knockback.gd"
func half_of(victim:Node2D) -> Vector2:
	var shape:CollisionShape2D = victim.get_node("CollisionShape2D")
	return (shape.global_transform*shape.shape.get_rect()).size*0.5
func hold_below(unit:Node2D,victim:Node2D,x:float = 0.0) -> void:
	victim.global_position = unit.global_position+Vector2(x,unit.body_half_size().y+half_of(victim).y-0.5)
func press_reset(unit:Node2D,point:Vector2) -> void:
	unit._cancel_slam()
	unit.global_position = point
	unit.slam_phase = unit.SlamPhase.FALLING
	unit._active_slam = false
	unit._drop_connected = false
	unit.fall_speed = 100.0
	unit._fall_hits.clear()
	unit._crush_clock = 0.0
	unit.cooldown_left = 99.0
	unit.player_control_direction = Vector2.ZERO
	unit.Repel = Vector2.ZERO
func run() -> void:
	game = root.get_node("Game")
	game._settings_storage_path=OS.get_environment("TEMP").path_join("anvil_crush_settings.json")
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
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"crush preloads complete")
	var bounds:Rect2 = world.return_map_world_rect(world.map_group["Map50x50"])
	center = bounds.get_center()
	var unit:Node2D = anvil(center+Vector2(0,-200))
	var victim:Node2D = dummy(center)
	var second:Node2D = dummy(center)
	var friend:Node2D = dummy(center,"Team0")
	var side:Node2D = dummy(center)
	var above:Node2D = dummy(center)
	unit.knockback_per_speed = 0.0 # Isolate genuine moving underside contact timing.
	unit.Can_Skill = false
	unit.default_properties.Can_Skill = false
	press_reset(unit,center+Vector2(0,-200))
	hold_below(unit,victim,-3.0)
	hold_below(unit,second,3.0)
	hold_below(unit,friend)
	side.global_position = unit.global_position+Vector2(unit.body_half_size().x+half_of(side).x-2.0,0)
	above.global_position = unit.global_position-Vector2(0,half_of(above).y)
	await physics_frame
	await process_frame
	check(victim in unit._contacts_at(unit.global_position) and second in unit._contacts_at(unit.global_position),"underside detects genuinely compressed targets")
	check(side not in unit._contacts_at(unit.global_position) and above not in unit._contacts_at(unit.global_position) and friend not in unit._contacts_at(unit.global_position),"same-height side/top/friendly contacts are excluded")
	check(not unit._damage_with_feedback(side,100.0,unit.global_position) and not unit._damage_with_feedback(above,100.0,unit.global_position),"damage helper itself rejects non-bottom targets")
	var times:Array[float] = []
	var previous_ticks:int = unit.crush_tick_count
	var expected_pressure:float = 0.0
	var first_loss:float = 0.0
	var side_hp:float = side.health
	var above_hp:float = above.health
	var friend_hp:float = friend.health
	for i:int in range(54):
		hold_below(unit,victim,-3.0)
		hold_below(unit,second,3.0)
		hold_below(unit,friend)
		side.global_position = unit.global_position+Vector2(unit.body_half_size().x+half_of(side).x-2.0,0)
		above.global_position = unit.global_position-Vector2(0,half_of(above).y)
		await physics_frame
		await process_frame
		unit.step_mob(1.0/120.0)
		if i==0: first_loss = 100000.0-victim.health
		else: expected_pressure += unit.falling_damage(unit.fall_speed-unit.gravity_acceleration/120.0)/120.0/unit.crush_interval
		if unit.crush_tick_count>previous_ticks:
			check(unit.crush_tick_count-previous_ticks<=2,"each bottom victim gets at most one pressure settlement per movement step")
			times.append(unit._crush_clock)
			previous_ticks = unit.crush_tick_count
	check(times.size()>20 and unit.hit_count==2,"maintained contact keeps losing HP without repeating full first impacts")
	check(times.size()>1 and times[0]<0.05 and times[1]-times[0]<0.05,"continuous damage begins before the old 0.20-second lockout")
	check(absf((100000.0-victim.health)-first_loss-floorf(expected_pressure))<=1.0,"sustained loss matches the time budget, not full damage or rounded-up damage every physics step")
	check(victim.health<100000 and second.health<100000 and side.health==side_hp and above.health==above_hp and friend.health==friend_hp,"only actual underside enemies take continuous crush damage")
	check(unit.chain_hits==2 and unit._drop_connected and unit.slam_count==0,"repeated pulses do not multiply chain credit or launch midair")
	var hp:float = victim.health
	var clock:float = unit._crush_clock
	game.now_stop_state = true
	unit.step_mob(2.0)
	check(victim.health==hp and unit._crush_clock==clock,"pause freezes crush cooldown and damage")
	game.now_stop_state = false
	victim.global_position.x += 200.0
	second.global_position.x += 200.0
	friend.global_position.x += 200.0
	side.global_position.x += 200.0
	above.global_position.x += 200.0
	await physics_frame
	await process_frame
	unit.step_mob(0.21)
	check(victim.health==hp,"leaving underside immediately ends pressure even after cooldown expires")
	hold_below(unit,victim)
	await physics_frame
	await process_frame
	unit.slam_phase = unit.SlamPhase.GROUND
	check(not unit._damage_with_feedback(victim,100,unit.global_position),"grounded anvil cannot keep doing crush damage")
	unit.slam_phase = unit.SlamPhase.RISING
	check(not unit._damage_with_feedback(victim,100,unit.global_position),"ascending anvil cannot deal pressure damage")
	unit.slam_phase = unit.SlamPhase.FALLING
	unit.set_multiplayer_authority(2)
	check(not unit._damage_with_feedback(victim,100,unit.global_position),"remote replica cannot deal pressure damage")
	unit.set_multiplayer_authority(1)
	# A thin solid strip between bottom and target must block damage too.
	press_reset(unit,center+Vector2(-120,-80))
	hold_below(unit,victim)
	var platform:StaticBody2D = obstacle(unit.global_position+Vector2(0,unit.body_half_size().y+0.25),Vector2(80,0.5))
	await physics_frame
	await process_frame
	check(victim not in unit._contacts_at(unit.global_position),"thin terrain blocks underside damage even inside contact tolerance")
	platform.queue_free()
	await physics_frame
	await process_frame
	# Natural brief contact: no following/repositioning after the fall begins.
	press_reset(unit,center+Vector2(-120,-100))
	unit.fall_speed = 360.0
	hold_below(unit,victim)
	await physics_frame
	await process_frame
	var initial_hits:int = unit.hit_count
	var initial_ticks:int = unit.crush_tick_count
	unit.step_mob(1.0/120.0)
	var impact_hp:float = victim.health
	unit.step_mob(1.0/60.0)
	check(unit.hit_count==initial_hits+1 and unit.crush_tick_count>initial_ticks and victim.health<impact_hp,"an ordinary brief falling contact deals follow-up damage before 0.20s, without moving the victim to follow")
	unit.step_mob(0.15)
	hp = victim.health
	unit.step_mob(0.10)
	check(victim.health==hp,"passing below the stationary victim ends pressure with no lingering DOT")
	# An actual terrain landing below both bodies stops all remaining pressure.
	var landing_floor:StaticBody2D = obstacle(unit.global_position+Vector2(0,unit.body_half_size().y+8.0),Vector2(90,4))
	await physics_frame
	await process_frame
	unit.step_mob(0.1)
	check(unit.slam_phase==unit.SlamPhase.GROUND,"contact test really lands on solid terrain")
	hold_below(unit,victim)
	await physics_frame
	await process_frame
	hp = victim.health
	unit.step_mob(0.4)
	check(victim.health==hp,"real landing leaves no damage timer running under the anvil")
	landing_floor.queue_free()
	await physics_frame
	await process_frame
	# Identical physical descent at 30/60/120Hz: fixed movement substeps and
	# fractional damage budget must not turn higher frame rates into extra DPS.
	var losses:Array[float] = []
	var gravity:float = unit.gravity_acceleration
	unit.gravity_acceleration = 0.0
	# A web-like actual-motion lease slows the physical fall itself; it must not
	# change fall_speed as an inherited stat or permanently affect the next fall.
	victim.global_position = center+Vector2(300,300)
	second.global_position = center+Vector2(340,300)
	friend.global_position = center+Vector2(380,300)
	side.global_position = center+Vector2(420,300)
	above.global_position = center+Vector2(460,300)
	await physics_frame
	await process_frame
	press_reset(unit,center+Vector2(-120,-180))
	unit.fall_speed = 360.0
	var free_from:Vector2 = unit.global_position
	unit.step_mob(0.1)
	var free_distance:float = unit.global_position.y-free_from.y
	unit.set_motion_speed_factor(&"fixture_cobweb",unit,0.25,0.10)
	press_reset(unit,free_from)
	unit.fall_speed = 360.0
	unit.step_mob(0.1)
	var slow_distance:float = unit.global_position.y-free_from.y
	check(is_equal_approx(unit.motion_speed_factor(),0.25),"actual-motion control never rewrites inherited speed fields")
	check(is_equal_approx(slow_distance,free_distance*0.25),"falling anvil is slowed by the actual movement factor")
	unit.set_motion_speed_factor(&"fixture_cobweb",unit,1.0,0.0)
	check(is_equal_approx(unit.motion_speed_factor(),1.0),"expired actual-motion factor restores the next fall")
	for hz:int in [30,60,120]:
		press_reset(unit,center+Vector2(-120,-100))
		unit.fall_speed = 360.0
		hold_below(unit,victim)
		await physics_frame
		await process_frame
		hp = victim.health
		for i:int in range(hz/10): unit.step_mob(1.0/float(hz))
		losses.append(hp-victim.health)
	check(losses[0]>45.0 and losses[0]==losses[1] and losses[1]==losses[2],"30/60/120Hz physical falls yield identical first-impact plus sustained HP loss")
	print("ANVIL_CONTACT_RATE_LOSSES: ",losses)
	unit.gravity_acceleration = gravity
	# Authority/death/output-disable also protect the actual settlement path.
	press_reset(unit,center+Vector2(-120,-100))
	hold_below(unit,victim)
	await physics_frame
	await process_frame
	hp = victim.health
	unit.set_multiplayer_authority(2)
	unit._press_contact(victim,360.0,unit.global_position,0.1)
	check(victim.health==hp,"remote replica cannot originate sustained pressure")
	unit.set_multiplayer_authority(1)
	unit.apply_damage_disable(1.0)
	unit._press_contact(victim,360.0,unit.global_position,0.1)
	check(victim.health==hp,"damage-disabled anvil cannot settle contact damage")
	unit._damage_output_disabled_until_msec = 0
	var own_hp:float = unit.health
	unit.health = 0
	unit._press_contact(victim,360.0,unit.global_position,0.1)
	check(victim.health==hp,"dead anvil cannot leave damaging pressure behind")
	unit.health = own_hp
	# Each confirmed damage step adds its own ordinary impulse, independently of
	# the audio interval, without resetting an older impulse or locking control.
	unit.knockback_per_speed = 0.06
	press_reset(unit,center+Vector2(-120,-100))
	unit.fall_speed = 360.0
	hold_below(unit,victim)
	await physics_frame
	await process_frame
	unit.step_mob(1.0/120.0)
	var pushes:Array[Node] = knockbacks(victim)
	check(pushes.size()==1,"first contact starts exactly one real pressure knockback controller")
	if not pushes.is_empty():
		var push:Node = pushes[0]
		check(not push.lock_control_during_knockback and not victim.dizziness,"first impact preserves normal control")
		var cues_before:int = damage_sounds(unit).size()
		var ticks_before:int = unit.crush_tick_count
		push._elapsed = 0.07
		hp = victim.health
		var pressure_speed:float = unit.fall_speed
		unit.step_mob(1.0/120.0)
		check(victim.health<hp and unit.crush_tick_count==ticks_before+1,"continued bottom contact actually loses HP on the next physics step")
		check(knockbacks(victim).size()==2 and knockbacks(victim)[0]==push and push._elapsed==0.07,"the same damage settlement adds an independent impulse without refreshing the first")
		push = knockbacks(victim).back()
		check(push.direction==Vector2.DOWN and victim.get_body_motion().impulse_velocity().y>0.0 and push.distance<=unit.maximum_knockback_distance,"continued pressure adds a downward vector with bounded reference strength")
		check(damage_sounds(unit).size()==cues_before,"continuous knockback is independent of the throttled audio cue")
		check(is_equal_approx(push.distance,unit.impact_knockback_distance(pressure_speed)*0.25),"continued pressure uses exactly one quarter of the original knockback rule")
		check(not push.lock_control_during_knockback and not push._lock_acquired and not victim.dizziness,"neither first nor sustained impact acquires a control lock")
		push._elapsed = 0.07
		victim.Damage_reduction = 1.0
		hp = victim.health
		unit.step_mob(1.0/120.0)
		check(victim.health==hp and knockbacks(victim).size()==2 and push._elapsed==0.07,"fully blocked pressure cannot renew the control effect")
		victim.Damage_reduction = 0.0
		unit.slam_phase = unit.SlamPhase.GROUND
		unit._press_contact(victim,400.0,unit.global_position,0.1)
		check(knockbacks(victim).size()==2 and push._elapsed==0.07,"grounded contact cannot renew the pressure impulse")
		unit.slam_phase = unit.SlamPhase.FALLING
		unit._crush_clock += 1.0/120.0
		unit._press_contact(victim,400.0,unit.global_position,1.0/120.0)
		var pushed_from:Vector2 = victim.global_position
		victim.default_properties.Speed = 0.0
		victim.Has_Collision_Damage = false
		victim.state_machine.set_physics_process(true)
		# Stop adding contact; the last finite impulse is allowed to finish naturally.
		unit.global_position.x -= 100.0
		await create_timer(0.45).timeout
		check(victim.global_position.y>pushed_from.y+5.0,"renewed pressure really displaces the target under normal engine physics")
		await settle_knockback(victim)
		check(knockbacks(victim).is_empty() and not victim.dizziness,"after contact ends, the last finite impulse finishes without a stuck control lock")
		victim.state_machine.set_physics_process(false)
	# Real victim physics: floor + left/right wall, escape toward the open side.
	unit.knockback_per_speed = 0.06
	for blocked_sign:float in [-1.0,1.0]:
		victim.global_position = center+Vector2(0,100)
		var vh:Vector2 = half_of(victim)
		var floor:StaticBody2D = obstacle(victim.global_position+Vector2(0,vh.y+2.2),Vector2(220,4))
		var wall:StaticBody2D = obstacle(victim.global_position+Vector2(blocked_sign*(vh.x+3.0),0),Vector2(4,120))
		press_reset(unit,victim.global_position-Vector2(0,unit.body_half_size().y+vh.y+2.0))
		unit.fall_speed = 400.0
		victim.default_properties.Speed = 0.0
		victim.Has_Collision_Damage = false
		victim.set_process(true)
		victim.state_machine.set_physics_process(true)
		await physics_frame
		await process_frame
		var hits:int = unit.hit_count
		var before:Vector2 = victim.global_position
		advance_until(unit,func(): return unit.hit_count>hits,0.4)
		var effects:Array[Node] = knockbacks(victim)
		check(effects.size()==1 and effects[0].direction.x==-blocked_sign and effects[0].direction.y==0.0,"pinned victim gets one horizontal push toward unblocked side")
		check(unit in victim.get_collision_exceptions(),"escape temporarily ignores only the pressing anvil body")
		check(victim.self_hurtbox.get_collision_layer_value(2),"side escape does not disable attack hurtbox")
		hp = victim.health
		await create_timer(0.45).timeout
		await physics_frame
		await process_frame
		check((victim.global_position.x-before.x)*(-blocked_sign)>8.0,"real physics moves pinned enemy sideways out of the anvil")
		check(victim.global_position.y+vh.y<=floor.global_position.y-2.0+0.2 and bounds.encloses(Rect2(victim.global_position-vh,vh*2.0)),"escape cannot go through floor or outside map")
		await settle_knockback(victim)
		await physics_frame;await process_frame
		check(victim.health==hp and knockbacks(victim).is_empty() and unit not in victim.get_collision_exceptions(),"escape ends without hidden damage, stuck control, or leaked collision exception")
		victim.state_machine.set_physics_process(false)
		floor.queue_free(); wall.queue_free()
		await physics_frame
		await process_frame
	# No free side: refuse to force the victim into solid walls.
	victim.global_position = center+Vector2(0,100)
	var vh:Vector2 = half_of(victim)
	var floor:StaticBody2D = obstacle(victim.global_position+Vector2(0,vh.y+2.05),Vector2(150,4))
	var left:StaticBody2D = obstacle(victim.global_position-Vector2(vh.x+2.05,0),Vector2(4,120))
	var right:StaticBody2D = obstacle(victim.global_position+Vector2(vh.x+2.05,0),Vector2(4,120))
	press_reset(unit,victim.global_position-Vector2(0,unit.body_half_size().y+vh.y))
	await physics_frame
	await process_frame
	check(unit._apply_impact_knockback(victim,600.0)==null and knockbacks(victim).is_empty(),"closed pocket gets no shove into walls")
	floor.queue_free();left.queue_free();right.queue_free()
	await physics_frame
	await process_frame
	# Do not remove someone else's preexisting exception; remove our own on redirect.
	preload("res://classes/body_collision_exclusions.gd").add_exception(victim,unit)
	var effect:Node = victim.apply_knockback(Vector2.RIGHT,5.0,80.0,0.0,0.0,{"source":unit})
	var lease:Node = unit.ESCAPE_LEASE.new()
	victim.add_child(lease)
	lease.setup(unit,effect)
	check(not lease.owns_exception,"escape lease recognizes a preexisting caller-owned collision exception")
	lease.free()
	check(unit in victim.get_collision_exceptions(),"lease cleanup preserves preexisting collision exception")
	preload("res://classes/body_collision_exclusions.gd").remove_exception(victim,unit)
	lease = unit.ESCAPE_LEASE.new()
	victim.add_child(lease)
	lease.setup(unit,effect)
	effect.source = friend
	lease._physics_process(0.0)
	check(lease.is_queued_for_deletion(),"another source redirect ends the old anvil escape lease")
	await process_frame
	check(unit not in victim.get_collision_exceptions(),"redirect cleanup restores body collision owned by this lease")
	print("ANVIL_CRUSH_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
