extends "res://tests/test_anvil_crush.gd"

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
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"balance preloads complete")
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var unit:Node2D = anvil(center+Vector2(0,-120))
	var victim:Node2D = dummy(center)
	var other:Node2D = dummy(center+Vector2(4,0))
	await physics_frame
	await process_frame
	check(unit.tracking_speed_scale==0.5 and is_equal_approx(unit.Skill_Cooling,2.8),"default pursuit is halved and miss cooldown remains 2.8 seconds")
	check(unit.sustained_knockback_ratio==0.25 and unit.Damage==40 and unit.crush_interval==0.20 and is_equal_approx(unit.falling_damage(600),100.0),"damage, speed scaling and pressure budget are unchanged")
	unit.knockback_per_speed = 0.0 # Isolate actual three-pass sequencing from target displacement.
	check(unit.begin_slam(victim) and unit.combo_slams==1,"manual first slam counts as one of the three")
	check(not unit.begin_slam(victim),"duplicate command cannot add another first slam")
	advance_until(unit,func(): return unit.slam_count==5 and unit.slam_phase==unit.SlamPhase.RISING,20.0)
	check(unit.slam_count==5 and unit.combo_slams==5 and unit.landing_count==4,"successful fourth and fifth slams continue beyond the removed three-slam cap")
	check(unit.hit_count==8 and unit.crush_tick_count>0,"multiple victims and pressure damage do not interrupt unlimited chains")
	check(unit.miss_count==0 and unit._active_slam and unit.cooldown_left==0.0,"successful chains have no forced cooldown after three")
	# Make the fifth descent miss; only a miss must end the chain.
	target_miss_fixture(unit,victim,other)
	await physics_frame
	await process_frame
	advance_until(unit,func(): return unit.slam_phase==unit.SlamPhase.GROUND and unit.miss_count==1,6.0)
	check(not unit._active_slam and not unit.Using_Skill and is_equal_approx(unit.cooldown_left,2.8),"a real miss still ends unlimited chaining with the normal cooldown")
	unit.fall_track_acceleration = 600.0
	check(not unit.begin_slam(victim) and not unit.begin_slam(victim,true),"manual and chained calls cannot bypass miss cooldown")
	var remaining:float = unit.cooldown_left
	game.now_stop_state = true
	unit.step_mob(4.0)
	check(unit.cooldown_left==remaining and unit.slam_count==5,"pause freezes miss recovery")
	game.now_stop_state = false
	unit.step_mob(2.79)
	check(unit.cooldown_left>0.0 and not unit.begin_slam(victim) and unit.slam_count==5,"still blocked just before the miss recovery boundary")
	unit.step_mob(0.02)
	check(unit.begin_slam(victim) and unit.combo_slams==1 and unit.slam_count==6,"cooldown expiration permits a fresh unlimited chain")
	# A natural drop during recovery may damage, but cannot erase recovery.
	unit._cancel_slam()
	unit.combo_slams = 3
	unit.cooldown_left = 2.8
	unit.global_position = center+Vector2(-120,-100)
	hold_below(unit,victim)
	other.global_position = center+Vector2(250,0)
	unit._fall_hits.clear()
	await physics_frame
	await process_frame
	var hp:float = victim.health
	unit._crush_clock += 0.01
	unit._press_contact(victim,360.0,unit.global_position,0.01)
	check(victim.health<hp and unit._drop_connected and not unit._active_slam and unit.cooldown_left==2.8 and unit.combo_slams==3,"falling contact still hurts but cannot restart a combo during mandatory cooldown")
	unit.velocity.y = 360.0
	unit._land()
	check(unit.slam_phase==unit.SlamPhase.GROUND and unit.cooldown_left==2.8,"natural landing during cooldown cannot schedule another slam")
	# Natural contact outside cooldown starts its own first counted descent.
	unit.slam_phase = unit.SlamPhase.FALLING
	unit.cooldown_left = 0.0
	unit._fall_hits.clear()
	unit._crush_clock += 0.01
	unit._press_contact(victim,360.0,unit.global_position,0.01)
	check(unit.combo_slams==1 and unit._active_slam,"eligible natural fall counts as the first descent, not a free fourth slam")
	var replica:Node2D = anvil(center+Vector2(220,-80))
	replica.set_multiplayer_authority(2)
	replica.accept_visual(unit.visual_state())
	check(replica.combo_slams==unit.combo_slams and not replica.begin_slam(victim,true),"snapshot carries combo count without granting replica damage authority")
	replica.queue_free()
	# Public impulse controller: full first hit, then quarter-distance unlocked pressure.
	unit.Can_Skill = false
	unit.default_properties.Can_Skill = false
	press_reset(unit,center+Vector2(-120,-100))
	unit.knockback_per_speed = 0.06
	hold_below(unit,victim)
	await physics_frame
	await process_frame
	var push:Node = unit._apply_impact_knockback(victim,600.0,unit.global_position)
	check(push!=null and push.distance==36.0 and push.lock_control_during_knockback and victim.dizziness,"initial 600-speed impact retains 36-unit push and original control")
	var gentle:Node = unit._apply_impact_knockback(victim,600.0,unit.global_position,true)
	check(gentle==push and gentle.distance==9.0 and knockbacks(victim).size()==1,"subsequent pressure reuses the controller at exactly 25 percent distance")
	check(not gentle.lock_control_during_knockback and not gentle._lock_acquired and not victim.dizziness and int(victim.get_meta("generic_motion_lock_count",0))==0,"light pressure releases only its previously acquired movement lock")
	unit._apply_impact_knockback(victim,80.0,unit.global_position,true)
	check(push.distance==3.0,"old minimum distance is scaled down instead of restoring the full 12-unit minimum")
	unit._apply_impact_knockback(victim,100000.0,unit.global_position,true)
	check(push.distance==15.0,"continued pressure retains the scaled 15-unit maximum")
	push._finish(false)
	await process_frame
	# Existing independent control state must survive anvil lock release.
	victim.dizziness = true
	push = unit._apply_impact_knockback(victim,600.0,unit.global_position)
	gentle = unit._apply_impact_knockback(victim,600.0,unit.global_position,true)
	check(gentle!=null and victim.dizziness,"unlocking anvil pressure does not remove preexisting unrelated dizziness")
	if gentle!=null: gentle._finish(false)
	victim.dizziness = false
	await process_frame
	# Real target movement while contact is being simulated, not a flag-only check.
	press_reset(unit,center+Vector2(-120,-100))
	unit.fall_speed = 360.0
	hold_below(unit,victim)
	victim.Speed = 90.0
	victim.default_properties.Speed = 90.0
	victim.Has_Collision_Damage = false
	victim.set_player_control_peer(1)
	victim.set_player_control_direction(Vector2.RIGHT)
	victim.state_machine.set_physics_process(true)
	await physics_frame
	await process_frame
	var start:Vector2 = victim.global_position
	var ticks:int = unit.crush_tick_count
	var moved_while_pushed:bool = false
	for i:int in range(12):
		var x:float = victim.global_position.x
		unit.step_mob(1.0/60.0)
		var current:Array[Node] = knockbacks(victim)
		var unlocked:bool = not current.is_empty() and not current[0].lock_control_during_knockback
		await physics_frame
		await process_frame
		moved_while_pushed = moved_while_pushed or (unlocked and victim.global_position.x>x+0.1)
	check(unit.crush_tick_count>ticks and victim.global_position.x>start.x+1.0 and moved_while_pushed,"enemy physically steers sideways while continued pressure is pushing, not only after it ends")
	print("ANVIL_BALANCE_ESCAPE: delta=",victim.global_position-start," pressure_ticks=",unit.crush_tick_count-ticks," moved_while_pushed=",moved_while_pushed)
	victim.set_player_control_direction(Vector2.ZERO)
	unit.global_position.x -= 120.0
	await create_timer(0.4).timeout
	check(knockbacks(victim).is_empty() and not victim.dizziness,"last light impulse finishes after separation without a stuck control lock")
	print("ANVIL_BALANCE_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)

func target_miss_fixture(unit:Node2D,victim:Node2D,other:Node2D) -> void:
	unit.fall_track_acceleration = 0.0
	victim.global_position.x = center.x+250.0
	other.global_position.x = center.x+250.0
