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
	actor._part_recovery_left = 0
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
			check(is_equal_approx(controllers[0].distance,36.0 if kind==0 else 55.0),"actual reduced sword / increased hilt knockback")
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
	check(losses[1]<losses[2] and losses[2]<losses[0],"full charge strongest; hilt stays weak and blade fixed")
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
		facing.advance_attack(facing.attack_duration()*0.5)
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
	var charged:Node2D=weapon(0)
	check(not charged.has_method("begin_brace") and not charged.Can_Skill,"brace method and skill entry removed")
	var original_hp:int=charged.health
	charged.Skill()
	charged.player_control_action(1)
	charged.take_damage(40,true)
	check(original_hp-charged.health==40,"former skill no longer blocks or grants damage reduction")
	charged.set_migrated_health(600,600)
	charged.sword_charge=0
	charged.step_mob(1.0)
	check(is_equal_approx(charged.sword_charge,0.5) and not charged._swing_pending,"AI passively charges without nearby enemies")
	charged.visual_mob()
	var half_angle:float=charged.image.rotation
	var half_height:float=charged.image.global_position.y
	charged.step_mob(1.0)
	charged.visual_mob()
	check(charged.sword_charge==1 and absf(charged.image.rotation)>absf(half_angle),"longer charge raises rotation")
	check(charged.image.global_position.y<half_height,"longer charge lifts the sword")
	charged.step_mob(3.0)
	check(charged.sword_charge==1 and not charged._swing_pending,"full charge waits instead of firing into empty space")
	charged._view_clock=0.1
	charged.visual_mob()
	var pose_a:Transform2D=charged.image.global_transform
	charged._view_clock=0.14
	charged.visual_mob()
	check(not pose_a.is_equal_approx(charged.image.global_transform),"fully charged sword continuously trembles")
	check(charged.get_debug_attack_regions().is_empty(),"charging itself has no damaging hitbox")
	check(charged._status_removed and charged._status_text.is_empty(),"character status descriptions removed")
	var bar:Script=load("res://scripts/characters/我的世界/frontier/creeper_style_bar.gd")
	var creeper:Script=load("res://scripts/characters/我的世界/苦力怕.gd")
	check(bar.OUTER_COLOR==creeper.FUSE_BAR_OUTER_COLOR and bar.BACKGROUND_COLOR==creeper.FUSE_BAR_BACKGROUND_COLOR and bar.BORDER_COLOR==creeper.FUSE_BAR_BORDER_COLOR,"bar uses actual creeper frame/trough/outline colors")
	check(charged.FRONTIER_FX.BAR==charged.BENCH.BAR,"durability and workbench use the same bar renderer")
	var close:Node2D=victim(Vector2(12,0))
	await physics_frame
	charged.step_mob(0.001)
	check(charged._swing_pending and charged._swing_charge==1,"nearby enemy releases stored full charge")
	charged.advance_attack(0.34)
	close.queue_free()
	charged.queue_free()
	await process_frame
	var gate:Node2D=weapon(0)
	gate.sword_charge=0.249
	var wear:int=gate.durability
	check(not gate.begin_swing() and gate.durability==wear,"below minimum charge cannot swing or consume durability")
	gate.set_player_control_peer(1)
	gate.sword_charge=0
	gate.player_control_action(0)
	gate.step_mob(0.49)
	gate.player_control_action_released(0)
	check(not gate._swing_pending and gate.sword_charge==0,"early manual release cancels without a hit")
	gate.player_control_action(0)
	gate.step_mob(0.5)
	gate.player_control_action_released(0)
	check(gate._swing_pending,"manual release at minimum charge attacks")
	var slow:float=gate.attack_duration()
	gate.advance_attack(slow)
	gate.swing_cooldown=0
	gate.sword_charge=1
	gate.begin_swing()
	check(gate.attack_duration()<slow and is_equal_approx(gate.attack_duration(),0.16),"full charge has faster physical and visual swing")
	gate.advance_attack(gate.attack_duration())
	gate.swing_cooldown=0
	gate.set_player_control_peer(0)
	var nearby:Node2D=victim(Vector2(12,0))
	await physics_frame
	gate.step_mob(0.49)
	check(not gate._swing_pending,"enemy contact cannot bypass minimum recharge after a swing")
	gate.step_mob(0.01)
	check(gate._swing_pending,"AI releases only after minimum recharge")
	gate.queue_free()
	nearby.queue_free()
	await process_frame
	var precise:Node2D=weapon(0)
	precise.sword_charge=1
	var distant:Node2D=victim(Vector2(45,0))
	await physics_frame
	check(not precise.has_reachable_swing_target(),"broad distance alone cannot trigger an unreachable swing")
	precise.step_mob(0.1)
	check(not precise._swing_pending and precise.sword_charge==1,"unreachable nearby enemy does not consume stored charge")
	distant.global_position=center+Vector2(12,0)
	await physics_frame
	var before_hp:int=distant.health
	check(precise.has_reachable_swing_target(),"real hurtbox inside actual sweep is reachable")
	check(distant.health==before_hp and precise.durability==45,"prediction is non damaging and does not spend durability")
	precise.step_mob(0.01)
	check(precise._swing_pending,"AI attacks confirmed physical contact")
	precise.frontier_fx.set_process(false)
	precise.advance_attack(precise.attack_duration()*0.4)
	precise.visual_mob()
	precise.frontier_fx.update_sword_trails(0.03)
	var traces:Array=precise.frontier_fx.sword_trails
	check(traces.size()>0,"charged attack emits actual sprite afterimages")
	var ghost:Sprite2D=traces[-1].sprite
	check(ghost.global_transform.is_equal_approx(precise.image.global_transform),"afterimage exactly matches real rendered sword transform")
	check(ghost.texture==precise.image.texture and ghost.offset==precise.image.offset,"afterimage uses real texture and offset")
	check(ghost.material!=precise.image.material and ghost.material.shader==precise.image.material.shader,"afterimage snapshots real shader rather than reconstructing UVs")
	var captured:Transform2D=ghost.global_transform
	precise.global_position+=Vector2(5,4)
	check(ghost.global_transform.is_equal_approx(captured),"afterimage stays at captured world position during movement")
	for tick:int in range(10): precise.frontier_fx.update_sword_trails(0.025)
	check(precise.frontier_fx.sword_trails.size()<=4,"afterimage count is bounded")
	precise.advance_attack(1.0)
	precise.frontier_fx.update_sword_trails(0.2)
	check(precise.frontier_fx.sword_trails.is_empty(),"afterimages fade and clean up")
	precise.queue_free()
	distant.queue_free()
	await process_frame
	var graded_damage:Array[int]=[]
	var graded_push:Array[float]=[]
	for charge:float in [0.25,0.5,1.0]:
		var sword_test:Node2D=weapon(0)
		var target_test:Node2D=victim(Vector2(10,0))
		await physics_frame
		sword_test.sword_charge=charge
		check(sword_test.begin_swing(),"partial or full charge may be released")
		sword_test.advance_attack(0.34)
		graded_damage.append(10000-int(target_test.health))
		var push_nodes:Array=target_test.get_children().filter(func(n:Node):return n.has_method("replace_with_hit"))
		check(push_nodes.size()==1,"charged swing creates pure push")
		graded_push.append(push_nodes[0].distance)
		check(push_nodes[0].stun_duration==0 and not push_nodes[0].lock_control_during_knockback,"charged push still has no stun")
		sword_test.queue_free()
		target_test.queue_free()
		await process_frame
	check(graded_damage[0]<graded_damage[1] and graded_damage[1]<graded_damage[2],"actual damage increases with charge")
	check(graded_push[0]<graded_push[1] and graded_push[1]<graded_push[2],"actual knockback distance increases with charge")
	print("CHARGE_GRADES ",graded_damage," push=",graded_push)
	var manual:Node2D=weapon(0)
	manual.set_player_control_peer(1)
	game.controlled_character_local=manual
	game._local_control_action_hold_mask=0
	game._set_local_control_action_hold(0,true)
	manual.step_mob(1.0)
	check(manual._manual_charging and is_equal_approx(manual.sword_charge,0.5) and not manual._swing_pending,"real control press holds charge rather than attacking")
	game._set_local_control_action_hold(0,false)
	check(manual._swing_pending and is_equal_approx(manual._swing_charge,0.5),"real control release swings at stored charge")
	manual.advance_attack(0.34)
	manual.swing_cooldown=0
	game._set_local_control_action_hold(0,true)
	manual.step_mob(0.3)
	game._clear_local_control_action_holds(false)
	check(not manual._manual_charging and manual.sword_charge==0 and not manual._swing_pending,"clearing controls cancels rather than firing")
	game.controlled_character_local=null
	manual.queue_free()
	await process_frame
	for kind:int in [1,2]:
		var part:Node2D=weapon(kind)
		part.sword_charge=0.8
		part.step_part(10.0)
		check(part.sword_charge==0 and not part._swing_pending,"parts have no charge accumulation")
		part.player_control_action(0)
		check(part._swing_pending and part._swing_charge==1,"parts attack immediately at fixed strength")
		part.visual_mob()
		check(part._status_removed and part._status_text.is_empty(),"part names and state descriptions are not displayed")
		part.queue_free()
		await process_frame
	# Last durability waits for its complete collision animation, including misses.
	var sword:Node2D=weapon(0)
	sword.durability=1
	arm(sword)
	check(sword.durability==0 and sword.part_kind==0,"last durability consumed once, attack is allowed to finish")
	sword.advance_attack(sword.attack_duration()*0.5)
	check(sword.part_kind==0,"no premature split during active attack")
	sword.advance_attack(sword.attack_duration()*0.5)
	await process_frame
	await process_frame
	check(sword.part_kind==1 and is_instance_valid(sword.workbench),"attack completion still splits into parts and bench")
	check(sword.transformation_count==1,"split emits one bat-style transformation")
	check(get_nodes_in_group("MCBatTransformFX").any(func(n:Node):return n.get_meta("wood_sword_transformation",false)),"split reuses bat explosion and smoke")
	check(get_nodes_in_group("MCNativeSFX").any(func(n:Node):return n.get_meta("mc_sound_event","")=="entity.item.break"),"split plays native item-break audio")
	await create_timer(0.1).timeout
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
	check(sword.transformation_count==2,"reassembly also emits transformation once")
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
	print("WOOD_REV8_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
