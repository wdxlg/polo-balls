extends "res://scripts/training/test_mc_new5.gd"
func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(45).timeout.connect(func(): finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.5).timeout
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	u=load("res://scripts/characters/我的世界/new5/utils.gd")
	await clear_units()
	var guardian:Node2D=spawn("守卫者",Vector2.ZERO,"Team0")
	guardian.laser_tick=1000
	var target:Node2D=spawn("",Vector2(25,0),"Team1")
	target.health=10000
	target.block=0
	target.Damage_reduction=0
	check(guardian.spike_phase==0 and guardian.spike_frames()==guardian.RETRACTED_FRAMES,"initial true retracted model")
	for frames:SpriteFrames in [guardian.RETRACTED_FRAMES,guardian.HALF_FRAMES]:
		check(frames.get_animation_names().size()==64,"all viewing directions available")
		for angle:int in range(64): check(frames.get_frame_count(StringName("v%02d"%angle))==8,"tail animation preserved per direction")
	var hp:float=target.health
	guardian.step_mob(0.01)
	guardian.step_mob(0.2)
	check(guardian.spike_phase==1 and guardian.spike_frames()==guardian.RETRACTED_FRAMES,"spines remain retracted during charge")
	check(target.health==hp,"no premature burst damage")
	guardian.step_mob(0.11)
	check(guardian.spike_phase==2 and guardian.spike_frames()==guardian.FRAMES,"spines extend at body expansion start")
	check(is_equal_approx(hp-target.health,18.0),"one active burst retains 18 damage")
	check(not guardian.try_spike_contact(target),"burst victim cannot take contact damage immediately")
	target.global_position=center+Vector2(guardian.U.radius(guardian)+guardian.U.radius(target)-0.1,0)
	guardian._contact_clock+=guardian.spike_contact_interval+0.01
	hp=target.health
	check(guardian.try_spike_contact(target),"extended spines deal contact damage")
	check(is_equal_approx(hp-target.health,2.0),"contact damage is only two")
	check(not guardian.try_spike_contact(target),"same target cooldown prevents per-frame damage")
	check(target.Repel.length()>0,"contact has small knockback")
	target.global_position=center+Vector2(150,0)
	guardian._contact_clock+=0.5
	check(not guardian.try_spike_contact(target),"no contact damage at burst-range distance")
	guardian._spike_left=0
	guardian.step_mob(0.075)
	check(guardian.spike_phase==2 and not guardian.spike_charging and guardian.spike_body_scale()>1.2,"extended phase cannot start another active attack")
	guardian._spike_burst_age=guardian.spike_hold_time-0.01
	guardian.step_mob(0.11)
	check(guardian.spike_phase==3 and guardian.spike_frames()==guardian.HALF_FRAMES,"model retracts after hold")
	check(not guardian.try_spike_contact(target),"retraction no longer deals contact damage")
	guardian.step_mob(0.20)
	check(guardian.spike_phase==0 and guardian.spike_frames()==guardian.RETRACTED_FRAMES,"spines return to retracted model")
	check(guardian._spike_left>0,"cooldown begins after retraction")
	target.global_position=center+Vector2(25,0)
	guardian.step_mob(guardian.spike_cooldown+0.01)
	check(guardian.spike_phase==1,"next active charge allowed only after full cycle")
	guardian.dizziness=true
	guardian.step_mob(0.5)
	check(guardian.spike_phase==0 and not guardian.spike_charging,"stun cancels charging")
	guardian.dizziness=false
	# Passive contact query also works when the guardian itself is stationary.
	guardian._spike_burst(guardian.global_position)
	target.global_position=center+Vector2(guardian.U.radius(guardian)+guardian.U.radius(target)-0.2,0)
	guardian._contact_hits.clear()
	await physics_frame
	guardian._contact_hits.clear()
	hp=target.health
	guardian.scan_spike_contacts()
	check(target.health<hp,"stationary guardian detects touching enemy body")
	# Flow UV phase increases eye -> target, with speed ramp independent of beam width.
	guardian.beam_active=true
	guardian.beam_end=center+Vector2(150,80)
	guardian._spike_burst_age=2
	guardian.spike_phase=0
	var last_speed:float=0
	for progress:float in [0.0,0.25,0.5,0.75,0.95]:
		guardian._tick_left=guardian.laser_tick*(1-progress)
		guardian._beam_flow=0
		guardian._process(0.01)
		var speed:float=guardian.beam_flow_speed(progress)
		check(speed>last_speed,"flow accelerates as hit approaches")
		check(guardian._beam_flow>0,"forward UV phase advances")
		check(is_equal_approx(guardian.beam.material.get_shader_parameter("scroll"),guardian._beam_flow),"shader receives integrated forward phase")
		check(is_equal_approx(guardian.beam.material.get_shader_parameter("along_scale"),guardian.beam.points[0].distance_to(guardian.beam_end)/guardian.beam_repeat_length),"UV frequency uses world beam length not changing width")
		last_speed=speed
	var flow:float=guardian._beam_flow
	game.now_stop_state=true
	guardian._process(0.1)
	check(guardian._beam_flow==flow,"flow freezes while battle paused")
	game.now_stop_state=false
	guardian.break_lock()
	check(guardian._beam_flow==0 and not guardian.beam.visible and not guardian.beam_glow.visible,"lock break resets and hides flow")
	await clear_units()
	await create_timer(2).timeout
	finish(0 if failures==0 else 1)
