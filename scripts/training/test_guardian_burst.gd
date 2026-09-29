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
	var target:Node2D=spawn("",Vector2(150,0),"Team1")
	target.health=10000
	target.block=0
	target.Damage_reduction=0
	guardian.step_mob(0.1)
	check(not guardian.spike_charging,"no charge outside spike radius")
	target.global_position=center+Vector2(25,0)
	var hp:float=target.health
	guardian.step_mob(0.01)
	check(guardian.spike_charging and target.health==hp,"enemy entering starts charge without damage")
	guardian.step_mob(0.20)
	check(target.health==hp and guardian.spike_body_scale()<0.9,"charge shrinks body before hit")
	guardian.step_mob(0.11)
	check(is_equal_approx(hp-target.health,18.0),"spike burst deals increased 18 damage")
	check(not guardian.spike_charging and guardian._spike_burst_age==0,"burst begins once")
	check(get_nodes_in_group("MCGuardianSpikeFX").size()==1,"one rectangular burst effect")
	target.global_position=center+Vector2(150,0)
	guardian.step_mob(0.075)
	check(guardian.spike_body_scale()>1.2,"rapid elastic enlargement")
	guardian.step_mob(0.3)
	check(is_equal_approx(guardian.spike_body_scale(),1.0),"body returns to normal scale")
	check(is_equal_approx(hp-target.health,18.0),"cooldown prevents repeated damage")
	guardian.step_mob(guardian.spike_hold_time+guardian.spike_retract_time)
	target.global_position=center+Vector2(25,0)
	guardian._spike_left=0
	guardian.step_mob(0.01)
	guardian.step_mob(0.15)
	target.global_position=center+Vector2(150,0)
	guardian.step_mob(0.2)
	check(not guardian.spike_charging and is_zero_approx(guardian._spike_charge),"leaving range cancels charge")
	target.global_position=center+Vector2(25,0)
	guardian.step_mob(0.01)
	guardian.dizziness=true
	guardian.step_mob(0.5)
	check(not guardian.spike_charging and target.health==hp-18,"stun cancels without phantom hit")
	guardian.dizziness=false
	target.global_position=center+Vector2(100,0)
	var wall:StaticBody2D=obstacle(Vector2(18,0),true)
	target.global_position=center+Vector2(30,0)
	await physics_frame
	guardian.step_mob(0.5)
	check(not guardian.spike_charging,"wall blocks spike trigger")
	wall.queue_free()
	await physics_frame
	# Same tint, increasing saturation and increasing additive aura throughout charge.
	guardian.beam_active=true
	guardian.beam_end=center+Vector2(150,50)
	var last_s:float=0
	var last_glow:float=-1
	for i:int in range(11):
		var progress:float=float(i)/10
		guardian._tick_left=guardian.laser_tick*(1-progress)
		guardian.visual_mob()
		var color:Color=guardian.beam.default_color
		var glow:float=guardian.beam_glow.material.get_shader_parameter("glow_strength")
		check(color.s>=last_s-0.001,"beam saturation grows")
		check(glow>last_glow,"beam glow grows")
		check(guardian.beam_glow.points==guardian.beam.points,"glow aligned with native beam")
		last_s=color.s
		last_glow=glow
	guardian.break_lock()
	check(not guardian.beam.visible and not guardian.beam_glow.visible,"lock break hides both layers")
	guardian._spike_burst(guardian.global_position)
	var fx:Node=guardian._spike_effects.back()
	guardian.health=0
	guardian.Die()
	check(fx.is_queued_for_deletion() and not fx.visible,"death clears spike burst immediately")
	await clear_units()
	await create_timer(2).timeout
	finish(0 if failures==0 else 1)
