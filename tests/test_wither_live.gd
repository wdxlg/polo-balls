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
	var wither:Node2D = spawn("凋零",Vector2.ZERO,"Team0")
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
	check(absf(wrapf(wither._bedrock_model.rotation.y-PI*0.5,-PI,PI)) < 0.05,"moving right turns the actual model right, not left or merely mirroring a sprite")
	check(not wither.is_character_visual_flipped_h(),"real Wither yaw must not be horizontally mirrored by the base movement")
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
	wither._blast(enemy.global_position,64.0,45.0,enemy,true)
	check(is_equal_approx(before-enemy.health,75.0),"one skull direct impact settles exactly 75 damage, not another splash")
	check(enemy.get_node_or_null("WitherStatus") != null,"skull applies visible Wither status")
	var potion_particles:Array[Node] = get_nodes_in_group("WitherPotionParticle")
	check(not potion_particles.is_empty(),"Wither impact emits Witch-style black potion particles immediately")
	if not potion_particles.is_empty():
		var particle:Sprite2D = potion_particles.back() as Sprite2D
		check(particle.get_script().resource_path.ends_with("女巫药水粒子.gd") and particle.get_parent() == world,"Wither particles reuse the eight-frame Witch sprite in world space")
		check(particle.self_modulate.r < 0.16 and particle.self_modulate.g < 0.16 and particle.self_modulate.b < 0.16,"Wither particle tint is near black")
	wither._blast(enemy.global_position,64.0,45.0,enemy,true)
	check(enemy.get_node_or_null("WitherStatus") != null,"second impact refreshes one status instead of stacking nodes")
	# Sweep a real skull into a real enemy and a nearby ordinary flower.
	# This checks the actual projectile path, not only a manual _blast call.
	var nearby_flower:Node2D = load("res://scripts/characters/我的世界/wither/rose.gd").new()
	world.add_child(nearby_flower,true)
	nearby_flower.global_position = enemy.global_position-Vector2(30,0)
	nearby_flower.configure(wither)
	nearby_flower.age = 0.6
	var skull:Node2D = load("res://scripts/characters/我的世界/wither/skull.gd").new()
	world.add_child(skull,true)
	skull.global_position = enemy.global_position-Vector2(80,0)
	skull.configure(wither,Vector2.RIGHT)
	check(skull.rotation == 0.0 and skull.heading == Vector2.RIGHT,"skull face stays upright in real World while flying right")
	var explosions_before:int = get_nodes_in_group("MCExplosion").size()
	skull._physics_process(0.5)
	var explosions_after:Array[Node] = get_nodes_in_group("MCExplosion")
	check(skull.exploded and explosions_after.size() == explosions_before+1,"real skull impact spawns exactly one shared MC explosion")
	check(nearby_flower.withered,"a real skull impact converts an ordinary poppy inside its blast")
	nearby_flower.queue_free()
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
	check(is_equal_approx(before-enemy.health,enemy.Max_health*0.02),"each Wither tick deals 2% of maximum health, not a fixed 4 points")
	var rose:Node2D = load("res://scripts/characters/我的世界/wither/rose.gd").new()
	world.add_child(rose,true)
	rose.global_position = enemy.global_position
	rose.configure(wither)
	rose.age = 0.6
	check(rose.get_ai_hazard_info().get("radius",0.0) == 11.0 and rose.get_ai_hazard_info().get("kind","") == "ordinary_rose","ordinary poppy keeps the small trap radius and is not yet a Wither rose")
	status.remaining = 1.0
	before = enemy.health
	rose._physics_process(0.016)
	check(rose.consumed and rose.is_queued_for_deletion() and is_equal_approx(before-enemy.health,4.0),"stepping on an ordinary poppy deals the prior 4 damage and consumes it")
	check(is_equal_approx(status.remaining,1.0),"ordinary poppy does not add or refresh Wither status")
	var converted:Node2D = load("res://scripts/characters/我的世界/wither/rose.gd").new()
	world.add_child(converted,true)
	converted.global_position = enemy.global_position+Vector2(90,0)
	converted.configure(wither)
	converted.age = 0.6
	var far_flower:Node2D = load("res://scripts/characters/我的世界/wither/rose.gd").new()
	world.add_child(far_flower,true)
	far_flower.global_position = converted.global_position+Vector2(170,0)
	far_flower.configure(wither)
	far_flower.age = 0.6
	wither._blast(converted.global_position,64.0,0.0,null,false)
	check(not converted.withered,"awakening blast does not transform poppies")
	wither._blast(converted.global_position,64.0,0.0,null,true)
	check(converted.withered and converted.is_in_group("WitherRose"),"skull blast converts only roses within its area")
	check(not far_flower.withered,"poppies outside the skull blast remain ordinary")
	converted.global_position = enemy.global_position
	before = enemy.health
	converted._physics_process(0.016)
	check(converted.consumed and converted.is_queued_for_deletion() and is_equal_approx(before-enemy.health,4.0),"transformed rose deals the same 4 damage and disappears when stepped on")
	check(status.remaining > 2.9,"transformed rose refreshes the same Wither status")
	far_flower.queue_free()
	status.remaining = 3.0
	status.tick_left = 1.0
	before = enemy.health
	status._physics_process(3.4)
	check(is_equal_approx(before-enemy.health,enemy.Max_health*0.06),"three-second Wither performs exactly three 2%-max-health ticks even with a long physics frame")
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
	beacon.landed = true
	beacon.global_position = center+Vector2(20,40)
	enemy.global_position = center+Vector2(140,40)
	await physics_frame
	beacon.beam_direction = Vector2.RIGHT
	beacon.beam_end = beacon._clipped_beam()
	beacon.warning_left = 0.6
	beacon.step_mob(0.61)
	check(beacon.firing_left > 0 and beacon.get_ai_hazard_info().get("shape","") == "segment","beam warning becomes an actual line threat")
	before = enemy.health
	for i:int in range(3): beacon.step_mob(0.5)
	check(enemy.health < before,"ground beacon beam damages enemy through periodic ticks")
	check(beacon.beams_fired == 1 and not wither._buff.is_empty(),"completed beam grants exactly one random Wither effect")
	# Let the real character state machine tick, rather than calling its skill helpers.
	wither._rose_left = 0.05
	wither._shot_left = 0.05
	wither._charge_left = 999.0
	wither.state_machine.set_physics_process(true)
	await create_timer(2.0).timeout
	check(get_nodes_in_group("WitherFlower").size() > 0,"live physics grows ordinary poppies first")
	check(wither._shot_left > 1.0,"live physics triggers the scheduled skull attack")
	await clear_units()
	finish(0 if failures == 0 else 1)
