extends "res://scripts/training/test_mc_new5.gd"
## Real World fixture; freeze other actors' state machines, then step Wither skills.
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(40).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.5).timeout
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	await clear_units()
	var wither:Node2D = spawn("凋灵",Vector2.ZERO,"Team0")
	var enemy:Node2D = spawn("",Vector2(160,0),"Team1")
	enemy.Max_health = 1000
	enemy.health = 1000
	enemy.Damage_reduction = 0.0
	enemy.block = 0
	check(wither.health == 500 and not wither.summoned,"Wither enters battle at placed position and full health")
	check(wither.image.texture is ViewportTexture and wither._bedrock_model.bones.size() == 6,"Mojang Bedrock six-bone model renders in a live 3D viewport")
	wither._bedrock_model.animate(0.0,Vector2.DOWN,false,0.9,false,[Vector2.DOWN,Vector2.DOWN,Vector2.DOWN],1.0)
	var previous_head_angle:float = wither._bedrock_model.bones["head1"].rotation_degrees.y
	wither._bedrock_model.animate(1.0,Vector2.DOWN,false,0.9,false,[Vector2.RIGHT,Vector2.LEFT,Vector2.DOWN],1.0)
	check(wither._bedrock_model.bones["head1"].rotation_degrees.y != previous_head_angle,"original head tracking rotates a live 3D head bone")
	check(wither._bedrock_model.bones["head1"].rotation.y != wither._bedrock_model.bones["head2"].rotation.y,"separate Wither heads track separate target directions")
	check(wither._bedrock_model.bones["upperbodypart2"].rotation_degrees.x != 0.0,"original body movement formula animates ribs")
	wither._bedrock_model.animate(2.0,Vector2.LEFT,true,1.0,true)
	check(wither._bedrock_model.armor_layer.visible,"half-health Bedrock shield uses a separately animated vanilla armor rig")
	check(absf(wither._bedrock_model.bones["upperbodypart2"].rotation_degrees.x-(0.065+0.05*cos(4.0))*180.0)<0.01,"rib angle follows official Bedrock Molang expression")
	var rig_angle_before:float = wither._bedrock_model.bones["upperbodypart2"].rotation_degrees.x
	await create_timer(0.25).timeout
	check(absf(wither._bedrock_model.bones["upperbodypart2"].rotation_degrees.x-rig_angle_before)>0.01,"real frame updates continue to animate the 3D bone without manually calling animate")
	wither.take_damage(100.0)
	check(wither.health == 500,"summoning is immune to damage")
	wither.summoned = true
	wither.image.visible = true
	# Regression: normal movement must run through ball.move (0.6 baseline),
	# not the old stationary-or-teleporting local Wither AI.
	await physics_frame
	wither.state_machine.set_physics_process(false)
	wither.direction = Vector2.RIGHT
	var start_x:float = wither.global_position.x
	wither.move(110.0,1.0/60.0)
	check(wither.global_position.x > start_x,"summoned Wither actually moves with no target requirement")
	check(absf(wither.velocity.x-66.0) < 0.1,"Wither uses common ball.move baseline speed multiplier")
	wither._update_live_pose(1.0)
	check(absf(wither._bedrock_model.rotation.y) < 0.01 and wither._bedrock_model.rotation.z > 0.2,"moving right tilts a still-front-facing body instead of turning it")
	check(wither._bedrock_model.bones["head1"].rotation.y > 0.8,"while moving right, the central head looks at the enemy to the right")
	check(not wither.is_character_visual_flipped_h(),"the base movement must not mirror the live tilted 3D model")
	var original_enemy_position:Vector2 = enemy.global_position
	enemy.global_position = wither.global_position+Vector2(-180,0)
	wither._update_live_pose(1.0)
	check(wither._bedrock_model.rotation.z > 0.2 and wither._bedrock_model.bones["head1"].rotation.y < -0.8,"enemy crossing left turns only the head, not the right-leaning torso")
	enemy.global_position = wither.global_position+Vector2(0,180)
	wither.velocity = Vector2.ZERO
	wither._update_live_pose(1.0)
	check(absf(wither._bedrock_model.rotation.x)+absf(wither._bedrock_model.rotation.z) < 0.01,"stopping movement straightens the body while an enemy remains visible")
	check(wither._bedrock_model.bones["head1"].rotation.x < -0.25 and absf(wither._bedrock_model.bones["head1"].rotation.y) < 0.3,"an enemy below makes the head tilt down rather than flip backward")
	enemy.global_position = original_enemy_position
	wither.velocity = Vector2.RIGHT*66.0
	wither._update_live_pose(1.0)
	var skull_target:Vector2 = enemy.global_position
	for i:int in range(3):
		var muzzle:Vector2 = wither.head_muzzle_world_position([0,2,1][i])
		wither._fire_skull(skull_target)
		var real_shots:Array[Node] = get_nodes_in_group("AI_Hazard")
		var fired:Node2D = real_shots.back() as Node2D
		check(fired.global_position.distance_to(muzzle) < 0.5,"skull %d originates from its currently posed 3D mouth"%i)
		check(fired.heading.dot((skull_target-muzzle).normalized()) > 0.999,"skull %d aims from its own muzzle"%i)
		fired.queue_free()
	var before:float = enemy.health
	wither._blast(enemy.global_position,64.0,wither.SKULL.SPLASH_DAMAGE,enemy,true)
	check(is_equal_approx(before-enemy.health,50.0),"one skull direct impact settles exactly 50 damage, not another splash")
	check(enemy.get_node_or_null("WitherStatus") != null,"skull applies visible Wither status")
	var potion_particles:Array[Node] = get_nodes_in_group("WitherPotionParticle")
	check(not potion_particles.is_empty(),"Wither impact emits Witch-style black potion particles immediately")
	if not potion_particles.is_empty():
		var particle:Sprite2D = potion_particles.back() as Sprite2D
		check(particle.get_script().resource_path.ends_with("女巫药水粒子.gd") and particle.get_parent() == world,"Wither particles reuse the eight-frame Witch sprite in world space")
		check(particle.global_scale.x>=.020 and particle.global_scale.x<=.030,"Wither status particles match Witch status world-space size")
		check(particle.self_modulate.r < 0.16 and particle.self_modulate.g < 0.16 and particle.self_modulate.b < 0.16,"Wither particle tint is near black")
	wither._blast(enemy.global_position,64.0,wither.SKULL.SPLASH_DAMAGE,enemy,true)
	check(enemy.get_node_or_null("WitherStatus") != null,"second impact refreshes one status instead of stacking nodes")
	# Sweep a real skull into a real enemy; the removed flower skill is absent.
	var skull:Node2D = load("res://scripts/characters/我的世界/wither/skull.gd").new()
	world.add_child(skull,true)
	skull.global_position = enemy.global_position-Vector2(80,0)
	skull.configure(wither,Vector2.RIGHT)
	check(skull.rotation == 0.0 and skull.heading == Vector2.RIGHT,"skull face stays upright in real World while flying right")
	var explosions_before:int = get_nodes_in_group("MCExplosion").size()
	skull._physics_process(0.5)
	var explosions_after:Array[Node] = get_nodes_in_group("MCExplosion")
	check(skull.exploded and explosions_after.size() == explosions_before+1,"real skull impact spawns exactly one shared MC explosion")
	if explosions_after.size() > explosions_before:
		var visual:Node = explosions_after.back()
		check(is_equal_approx(visual.radius,64.0) and not visual.play_audio,"skull explosion uses the shared effect and keeps one sound")
	var status:Node = enemy.get_node("WitherStatus")
	var particle_count:int = get_nodes_in_group("WitherPotionParticle").size()
	status._process(0.2)
	check(get_nodes_in_group("WitherPotionParticle").size() > particle_count,"black Witch-style potion particles continue while Wither is active")
	status.tick_left = 1.0
	before = enemy.health
	status._physics_process(1.1)
	check(is_equal_approx(before-enemy.health,10.0),"Wither I removes 1% of a 1000-max-health enemy each second")
	status.remaining = 3.0
	status.tick_left = 1.0
	before = enemy.health
	status._physics_process(3.4)
	check(is_equal_approx(before-enemy.health,30.0),"three-second Wither ticks at t=1,2,3, never after expiry in a long frame")
	wither.health = 250
	wither.on_actual_health_damage_received(1.0,251.0)
	check(wither.heart_dropped and is_instance_valid(wither.beacon),"first half-health crossing summons one attackable beacon")
	var beacon:Node2D = wither.beacon
	check(beacon.health == 180,"beacon has its own health")
	beacon.landed = false
	beacon.global_position = center+Vector2(20,-60)
	var drop_y:float = beacon.global_position.y
	beacon.step_mob(0.1)
	check(beacon.landed or beacon.global_position.y > drop_y,"falling heart obeys gravity or collides with ground")
	wither.on_actual_health_damage_received(1.0,251.0)
	check(wither.beacon == beacon,"half-health trigger cannot duplicate the beacon")
	beacon.state_machine.set_physics_process(false)
	var floor_body:StaticBody2D = obstacle(Vector2(20,100),true)
	(floor_body.get_child(0).shape as RectangleShape2D).size = Vector2(360,12)
	beacon.global_position = center+Vector2(20,40)
	enemy.global_position = center+Vector2(20,-100)
	await physics_frame
	beacon.step_mob(0.4)
	check(beacon.landed and beacon._activated,"real beacon body lands on full-size collider")
	beacon.beam_direction = Vector2.UP
	beacon.beam_end = beacon._clipped_beam()
	beacon.warning_left = 0.6
	beacon.step_mob(0.61)
	check(beacon.firing_left > 0 and beacon.get_ai_hazard_info().get("shape","") == "rect","beam warning becomes an actual animated rectangular threat")
	check(not wither._buff.is_empty() and wither._buff==beacon.last_buff,"live beacon grants the effect as soon as it starts firing")
	before = enemy.health
	for i:int in range(10): beacon.step_mob(0.5)
	check(enemy.health < before,"ground beacon beam damages enemy through periodic ticks")
	check(beacon.beams_fired == 1 and wither._buff==beacon.last_buff,"completed beam retains the effect granted at launch")
	floor_body.queue_free()
	# Let the real character state machine tick, rather than calling its skill helpers.
	wither._head_shot_left.fill(0.05)
	wither._global_shot_left = 0.0
	wither._charge_left = 999.0
	wither.state_machine.set_physics_process(true)
	await create_timer(0.25).timeout
	check(get_nodes_in_group("WitherFlower").is_empty(),"live physics creates no removed flowers")
	await create_timer(1.75).timeout
	var fired_head:bool = false
	for left:float in wither._head_shot_left:
		if left > 0.5: fired_head = true
	check(fired_head,"live physics triggers at least one independently cooled skull attack")
	wither.state_machine.set_physics_process(false)
	var analyzer:Node = world.get_node_or_null("CombatThreatAnalyzer")
	check(analyzer!=null,"actual World exposes threat display for balanced Wither")
	if analyzer!=null:
		var visible_skull:Node2D = wither.SKULL.new()
		world.add_child(visible_skull)
		visible_skull.configure(wither,Vector2.RIGHT)
		visible_skull.global_position = center+Vector2(0,-120)
		visible_skull.set_physics_process(false)
		wither._charge_windup = 0.45
		wither._charge_dir = Vector2.RIGHT
		game.Game_Settings.Training_Debug_Mode = true
		analyzer._physics_process(0.2)
		var matched:bool = false
		for threat:Dictionary in analyzer._debug_threats:
			if threat.source==wither and threat.shape=="segment" and is_equal_approx(threat.damage,wither.own_attack_damage(100.0)): matched = true
		check(analyzer.visible and matched,"enabled display uses live 100-base charge damage")
		matched = false
		for threat:Dictionary in analyzer._debug_threats:
			if threat.get("kind","")=="wither_skull" and is_equal_approx(threat.damage,wither.own_attack_damage(50.0)): matched = true
		check(matched,"enabled display calls the standard receiver-aware head hazard and shows live 50-base damage")
		visible_skull.queue_free()
		wither._charge_windup = 0.0
		analyzer._refresh_debug_world()
		matched = false
		for threat:Dictionary in analyzer._debug_threats:
			if threat.source==wither and threat.shape=="segment": matched = true
		check(not matched,"ending charge removes its displayed attack segment")
		game.Game_Settings.Training_Debug_Mode = false
		analyzer._physics_process(0.1)
		check(not analyzer.visible and analyzer._debug_threats.is_empty(),"disabling threat display clears all balanced attack markers")
	var previous_locale:String = game.current_locale
	for locale:String in ["zh","en"]:
		game.current_locale = locale
		var text:String = world._armor_test_special_effect_summary(wither,wither.Type_Tags)
		check(text==wither.get_armor_test_effect_summary() and not text.contains("玫瑰") and not text.to_lower().contains("rose"),"actual World uses updated "+locale+" description without flowers")
	game.current_locale = previous_locale
	await clear_units()
	finish(0 if failures == 0 else 1)
