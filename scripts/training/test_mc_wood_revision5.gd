extends "res://scripts/training/test_mc_new5.gd"
func weapon(kind:int) -> Node2D:
	var actor:Node2D = spawn("木剑",Vector2.ZERO)
	actor.part_kind = kind
	actor.bench_destroyed = kind != 0
	actor.direction = Vector2.RIGHT
	actor.visual_mob()
	actor.ensure_attack_shape()
	return actor
func victim(offset:Vector2) -> Node2D:
	var actor:Node2D = spawn("",offset,"Team1")
	actor.Max_health = 10000
	actor.default_properties["Max_health"] = 10000
	actor.health = 10000
	actor.collision_layer = 0
	actor.collision_mask = 0
	return actor
func arm(actor:Node2D) -> void:
	actor.cancel_attack()
	actor.swing_visual_left = 0
	actor.swing_cooldown = 0
	actor.sword_charge = 1
	actor.brace_left = 0
	check(actor.begin_swing(),"attack can start")
func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(110).timeout.connect(func():finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.5).timeout
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var losses:Array[int] = []
	for kind:int in [0,1,2]:
		var actor:Node2D = weapon(kind)
		check(actor.attack_area is Area2D and actor.attack_shape is ConvexPolygonShape2D,"each form has a real weapon collision shape")
		check(actor.attack_shape.points.size() >= 3,"shape follows opaque weapon texture")
		check(actor.attack_area.get_parent()==actor.image,"hitbox follows weapon sprite transform")
		var target:Node2D = victim(Vector2(45,0))
		await physics_frame
		await process_frame
		arm(actor)
		actor.advance_attack(actor.attack_duration())
		check(target.health==10000,"inside former guaranteed range but outside weapon cannot be hit "+str(kind))
		target.global_position=center+Vector2(12 if kind==0 else 5 if kind==1 else 21,0)
		await physics_frame
		await process_frame
		arm(actor)
		check(actor.resolve_swing()==0,"windup has no damage")
		check(actor.get_debug_attack_regions().is_empty(),"windup has no active debug hitbox")
		actor.advance_attack(actor.attack_duration())
		var loss:int = 10000-int(target.health)
		losses.append(loss)
		check(loss>0,"swept physical contact damages target "+str(kind))
		var controllers:Array = target.get_children().filter(func(n:Node): return n.has_method("replace_with_hit"))
		if kind == 2: check(controllers.is_empty(),"blade creates no knockback controller")
		else:
			check(controllers.size()==1,"sword/hilt creates one knockback controller")
			check(controllers[0].stun_duration==0.0 and not controllers[0].lock_control_during_knockback,"push has neither stun nor movement lock")
			check(not target.dizziness,"being pushed does not make target dizzy")
			check(is_equal_approx(controllers[0].distance,12.0 if kind==0 else 55.0),"actual reduced sword / increased hilt knockback")
		var hp:int = target.health
		actor.resolve_swing()
		actor.advance_attack(0.5)
		check(target.health==hp,"one attack cannot repeatedly damage the same hurtbox")
		for controller:Node in controllers: controller.call("_finish",false)
		await process_frame
		target.global_position=center+Vector2(12 if kind==0 else 5 if kind==1 else 21,0)
		arm(actor)
		target.global_position=center+Vector2(150,100)
		await physics_frame
		actor.advance_attack(actor.attack_duration())
		check(target.health==hp,"target can dodge after aim is chosen")
		target.global_position=center+Vector2(12 if kind==0 else 5 if kind==1 else 21,0)
		var layer:int=target.self_hurtbox.collision_layer
		target.self_hurtbox.collision_layer=0
		await physics_frame
		arm(actor)
		actor.advance_attack(actor.attack_duration())
		check(target.health==hp,"no hurtbox collision means no damage; no radius fallback")
		target.self_hurtbox.collision_layer=layer
		await physics_frame
		actor.direction=Vector2.UP
		arm(actor)
		actor.move(130,0.016)
		check(actor.direction==Vector2.UP and is_equal_approx(actor.velocity.length(),78.0),"attacking does not steer or accelerate body")
		actor.cancel_attack()
		actor.queue_free()
		target.queue_free()
		await process_frame
	check(losses[1]<losses[0] and losses[0]<losses[2],"hilt damage lowest, blade damage highest")
	var blade:Node2D=weapon(2)
	check(is_equal_approx(blade.attack_duration(),0.20) and is_equal_approx(blade.attack_recovery(),0.28),"fast blade timing")
	var target:Node2D=victim(Vector2(22,0))
	await physics_frame
	arm(blade)
	blade.advance_attack(0.1)
	blade.visual_mob()
	var debug:Array = blade.get_debug_attack_regions()
	check(debug.size()==1 and debug[0].points[0].distance_to(blade.weapon_transform(0.5)*blade.attack_shape.points[0])<0.001,"training overlay uses exact physics polygon")
	check(blade.image.global_transform.is_equal_approx(blade.weapon_transform(0.5)),"rendered blade and collision pose agree")
	var hp:int=target.health
	blade.advance_attack(0.1)
	check(target.health==hp,"retraction does not double hit")
	blade.queue_free()
	target.queue_free()
	await process_frame
	# A wall between body and victim blocks even a thrust tip that extends past it.
	blade=weapon(2)
	target=victim(Vector2(23,0))
	var blocker:Node2D=obstacle(Vector2(11,0),true)
	await physics_frame
	await process_frame
	arm(blade)
	blade.advance_attack(0.2)
	check(target.health==10000,"blade cannot damage through a wall")
	blocker.queue_free()
	blade.queue_free()
	target.queue_free()
	await process_frame
	for kind:int in [0,1]:
		var facing:Node2D=weapon(kind)
		for travel:Vector2 in [Vector2.RIGHT,Vector2(1,1).normalized(),Vector2.UP,Vector2.DOWN]:
			facing.velocity=travel*100
			facing.direction=travel
			facing.visual_mob()
			check(is_zero_approx(facing.image.rotation) and not facing.is_character_visual_flipped_h(),"sword/hilt keep upright right-facing for vertical/diagonal travel")
		facing.velocity=Vector2.LEFT*100
		facing.visual_mob()
		check(is_zero_approx(facing.image.rotation) and facing.is_character_visual_flipped_h(),"sword/hilt flip left without rotation")
		facing.velocity=Vector2.UP*100
		facing.visual_mob()
		check(is_zero_approx(facing.image.rotation) and facing.is_character_visual_flipped_h(),"vertical movement preserves previous horizontal facing")
		facing.velocity=Vector2.RIGHT*100
		facing.direction=Vector2.RIGHT
		arm(facing)
		facing.advance_attack(0.17)
		facing.visual_mob()
		var right_points:PackedVector2Array=[]
		for p:Vector2 in facing.attack_shape.points: right_points.append(facing.weapon_transform(0.5)*p)
		facing._swing_left_facing=true
		facing.visual_mob()
		check(facing.is_character_visual_flipped_h(),"left swing uses a horizontal mirror")
		for p:Vector2 in facing.attack_shape.points:
			var point:Vector2=facing.weapon_transform(0.5)*p
			var mirror:Vector2=Vector2(2*facing.global_position.x-point.x,point.y)
			var matches:bool=false
			for candidate:Vector2 in right_points:
				if candidate.distance_to(mirror)<0.01: matches=true
			check(matches,"mirrored collision polygon matches mirrored artwork")
		facing.queue_free()
		await process_frame
	var motion_blade:Node2D=weapon(2)
	for travel:Vector2 in [Vector2.RIGHT,Vector2.UP,Vector2.LEFT,Vector2.DOWN,Vector2(1,1).normalized()]:
		motion_blade.velocity=travel*100
		motion_blade.direction=-travel
		motion_blade.swing_visual_left=0
		motion_blade.visual_mob()
		check(absf(angle_difference(motion_blade.image.rotation,travel.angle()+PI*0.25))<0.001,"blade faces actual velocity, not unrelated aim or direction")
		arm(motion_blade)
		motion_blade.advance_attack(0.1)
		motion_blade.visual_mob()
		check(absf(angle_difference(motion_blade.image.rotation,travel.angle()+PI*0.25))<0.001,"blade thrust stays aligned with movement")
		check(motion_blade.image.global_transform.is_equal_approx(motion_blade.weapon_transform(0.5)),"directional blade hitbox and artwork agree")
		motion_blade.cancel_attack()
	motion_blade.swing_visual_left=0.2
	motion_blade.client_visual_step(0.05)
	check(is_equal_approx(motion_blade.swing_visual_left,0.15),"client attack animation continues smoothly")
	motion_blade.queue_free()
	await process_frame
	# Last durability waits for its complete collision animation, including misses.
	var sword:Node2D=weapon(0)
	sword.durability=1
	arm(sword)
	check(sword.durability==0 and sword.part_kind==0,"last durability consumed once, attack is allowed to finish")
	sword.advance_attack(0.17)
	check(sword.part_kind==0,"no premature split during active attack")
	sword.advance_attack(0.17)
	await process_frame
	await process_frame
	check(sword.part_kind==1 and is_instance_valid(sword.workbench),"attack completion still splits into parts and bench")
	var bench:Node2D=sword.workbench
	bench.set_physics_process(false)
	var other:Node2D
	for part:Node2D in bench.living_pieces():
		part.state_machine.set_physics_process(false)
		part.dock_delay=0
		part.global_position=bench.global_position+Vector2(-8 if part==sword else 8,0)
		if part!=sword: other=part
	bench.age=0
	sword.move(130,0.016)
	check(sword.velocity.length()>0,"immaterial bench does not stop parts")
	sword.global_position=bench.global_position-Vector2(8,0)
	bench.advance(3.0)
	check(bench.is_materialized() and bench.progress==0,"materialization does not pre-charge repair")
	bench.advance(2.41)
	check(sword.part_kind==0 and sword.durability==45,"normal repair still succeeds")
	await process_frame
	sword.spend_durability(45)
	await process_frame
	await process_frame
	bench=sword.workbench
	for part:Node2D in bench.living_pieces():
		part.state_machine.set_physics_process(false)
		if part!=sword: other=part
	other.health=0
	check(bench._shattered and sword.bench_destroyed,"part death still destroys bench and prevents recreation")
	await clear_units()
	while world._mc_prewarmer.finished.size()+world._mc_prewarmer.failed.size()<world._mc_prewarmer.CHARACTERS.size(): await process_frame
	print("WOOD_COLLISION_DAMAGE ",losses)
	print("WOOD_REV5_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
