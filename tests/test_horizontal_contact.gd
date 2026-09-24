extends "res://tests/test_anvil_bounce_audio.gd"
const WITHER_STATUS="res://scripts/characters/我的世界/wither/status.gd"
const WITCH_STATUS="res://scripts/effects/我的世界/女巫药水状态.gd"
func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	saved_stop=game.now_stop_state
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Have_Team_Damage=false
	game.Game_Settings.Ball_Can_Move=true
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(90).timeout.connect(func(): finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(.3).timeout
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"contact test preloads complete")
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	obstacle(center+Vector2(0,100),Vector2(1200,12))
	var iron:Node2D=anvil(center+Vector2(-350,-200))
	iron.set_player_control_peer(0)
	iron.Can_Skill=false
	iron.default_properties.Can_Skill=false
	iron.cooldown_left=100
	var victim:Node2D=dummy(center+Vector2(0,80))
	var bait:Node2D=dummy(center+Vector2(400,-200))
	var owner:Node2D=spawn("res://scenes/characters/我的世界/凋零.tscn",center+Vector2(-400,-300),"Team0")
	owner.summoned=true
	owner.health=250
	owner.on_actual_health_damage_received(1,251)
	owner.set_process(false)
	var beacon:Node2D=owner.beacon
	beacon.state_machine.set_physics_process(false)
	beacon.global_position=center+Vector2(-400,-200)
	beacon.set_process(false)
	await physics_frame
	await process_frame
	for crowd:bool in [false,true]:
		for side:float in [-1.0,1.0]:
			for friend:bool in [false,true]:
				var label:String=" crowd="+str(crowd)+" side="+str(side)+" friend="+str(friend)
				victim.Team="Team0" if friend else "Team1"
				victim.global_position=center+Vector2(0,80)
				victim.set_large_battle_performance_mode(crowd)
				iron.set_large_battle_performance_mode(crowd)
				iron.global_position=center+Vector2(-side*70,94-iron.body_half_size().y)
				iron.direction=Vector2(side,0)
				iron.slam_phase=iron.SlamPhase.GROUND
				iron.fall_speed=0
				iron.Repel=Vector2.ZERO
				iron._horizontal_contact=""
				var mask:int=iron.collision_mask
				var count:int=iron.horizontal_bounces
				var clang_count:int=iron.obstacle_impact_count
				var hp:float=victim.health
				await physics_frame
				await process_frame
				for i:int in range(300):
					iron.step_mob(1.0/120.0)
					if iron.horizontal_bounces>count: break
				print("IRON CASE",label," offset=",iron.global_position-center," dir=",iron.direction," bounces=",iron.horizontal_bounces-count," phase=",iron.slam_phase," speed=",iron.Speed," active=",iron.active())
				check(iron.horizontal_bounces==count+1 and iron.direction.x==-side,"anvil rebounds once from character"+label)
				var x:float=iron.global_position.x
				iron.step_mob(.1)
				check((iron.global_position.x-x)*side< -1,"anvil really separates after contact"+label)
				check(iron.collision_mask==mask and iron.obstacle_impact_count==clang_count and victim.health==hp,"anvil side bounce restores mask, no smash damage or clang"+label)
	iron.global_position=center+Vector2(-400,-300)
	for crowd:bool in [false,true]:
		for side:float in [-1.0,1.0]:
			for friend:bool in [false,true]:
				var label:String=" crowd="+str(crowd)+" side="+str(side)+" friend="+str(friend)
				victim.Team="Team0" if friend else "Team1"
				victim.global_position=center+Vector2(0,87.4)
				bait.global_position=center+Vector2(side*400,-200)
				victim.set_large_battle_performance_mode(crowd)
				beacon.set_large_battle_performance_mode(crowd)
				beacon.global_position=center+Vector2(-side*50,87.4)
				beacon._activated=true
				beacon._rebound_left=0
				beacon.warning_left=0
				beacon.firing_left=0
				beacon.beam_timer=100
				beacon.fall_speed=0
				beacon.Repel=Vector2.ZERO
				var mask:int=beacon.collision_mask
				var count:int=beacon.horizontal_bounces
				var hp:float=victim.health
				await physics_frame
				await process_frame
				for i:int in range(240):
					beacon.step_mob(1.0/120.0)
					if beacon.horizontal_bounces>count: break
				print("BEACON CASE",label," offset=",beacon.global_position-center," dir=",beacon._rebound_heading," bounces=",beacon.horizontal_bounces-count," target=",beacon.U.nearest(beacon)," active=",beacon.active())
				check(beacon.horizontal_bounces==count+1 and beacon._rebound_heading==-side,"beacon rebounds from character"+label)
				var x:float=beacon.global_position.x
				beacon.step_mob(.1)
				check((beacon.global_position.x-x)*side < -4 and beacon._rebound_left>0,"beacon pursuit cannot immediately undo rebound"+label)
				check(beacon.collision_mask==mask and beacon.landed and victim.health==hp,"beacon side bounce restores mask and retains gravity without extra damage"+label)
	# Terrain reflection uses the same sustained-away behavior, in both directions.
	victim.global_position=center+Vector2(450,-250)
	for side:float in [-1.0,1.0]:
		var wall:StaticBody2D=obstacle(center+Vector2(side*50,40),Vector2(6,130))
		bait.global_position=center+Vector2(side*300,-150)
		beacon.global_position=center+Vector2(0,87.4)
		beacon._rebound_left=0
		beacon.fall_speed=0
		var count:int=beacon.horizontal_bounces
		await physics_frame
		await process_frame
		# Frame-driven fixture movement must not relocate the chosen far-side bait.
		bait.global_position=center+Vector2(side*300,-150)
		for i:int in range(200):
			beacon.step_mob(1.0/120.0)
			if beacon.horizontal_bounces>count: break
		print("WALL CASE side=",side," offset=",beacon.global_position-center," delta=",beacon.horizontal_bounces-count," heading=",beacon._rebound_heading," wanted=",beacon.U.nearest(beacon)," target_pos=",beacon.U.nearest(beacon).global_position-center)
		check(beacon.horizontal_bounces==count+1 and beacon._rebound_heading==-side,"beacon real wall rebound side="+str(side))
		var x:float=beacon.global_position.x
		beacon.firing_left=3
		beacon.tick_left=10
		beacon.step_mob(.1)
		check(absf(beacon.global_position.x-x-(-side*3))<.05,"firing rebound still respects half-speed envelope")
		beacon._process(0)
		check(beacon._beam_visual.global_position==beacon.beam_origin() and beacon.beam_end.x==beacon.beam_origin().x,"glowing core-aligned beam follows reflected movement and remains vertical")
		beacon.firing_left=0
		wall.queue_free()
		await physics_frame
		await process_frame
	# No false horizontal rebound from supporting ground, and pause freezes latch.
	var count:int=beacon.horizontal_bounces
	beacon._gravity_step(.05,0)
	check(beacon.horizontal_bounces==count and beacon.landed,"ground support cannot trigger horizontal bounce")
	var paused_position:Vector2=beacon.global_position
	var paused_left:float=beacon._rebound_left
	game.now_stop_state=true
	beacon.step_mob(.5)
	check(beacon.global_position==paused_position and beacon._rebound_left==paused_left,"pause freezes rebound motion and its simulation timer")
	game.now_stop_state=false
	owner.global_position=center+Vector2(0,87.4)
	beacon.global_position=center+Vector2(-50,87.4)
	beacon._gravity_step(1.0,60)
	check(beacon.horizontal_bounces==count and absf(beacon.global_position.x-center.x-10)<.02,"summoner collision exception survives temporary side mask")
	# Compare real emitter calls, not just the particle script's default scale.
	victim.Team="Team1"
	var status:Node=load(WITHER_STATUS).new()
	victim.add_child(status)
	status.refresh(owner)
	status.set_process(false)
	status.set_physics_process(false)
	var witch:Node=load(WITCH_STATUS).new()
	victim.add_child(witch)
	witch.target=victim
	witch.set_process(false)
	witch.set_physics_process(false)
	var scale_ok:bool=true
	var behavior_ok:bool=true
	var wither_mean:float=0
	var witch_mean:float=0
	for i:int in range(64):
		status._spawn_particle()
		var p:Sprite2D=get_nodes_in_group("WitherPotionParticle").back()
		wither_mean+=p.global_scale.x
		scale_ok=scale_ok and p.global_scale.x>=.020 and p.global_scale.x<=.030 and p.scale.x==p.scale.y
		behavior_ok=behavior_ok and p.self_modulate==status.PARTICLE_COLOR and p.velocity.y>=-48 and p.velocity.y<=-34 and p.frame_time>=.060 and p.frame_time<=.072
		witch._spawn_status_particle()
		var w:Sprite2D=world.get_child(world.get_child_count()-1) as Sprite2D
		witch_mean+=w.global_scale.x
		scale_ok=scale_ok and w.global_scale.x>=.020 and w.global_scale.x<=.030
	check(scale_ok,"64 Wither and 64 Witch status particles use identical 0.020-0.030 world-scale bounds")
	check(absf(wither_mean/64-witch_mean/64)<.003,"sampled Wither and Witch particle means agree without a hidden parent scale")
	check(behavior_ok and status.PARTICLE_INTERVAL==.14 and status.TICK_DAMAGE_RATIO==.02,"Wither black tint, motion, timing, particle rate and status damage remain unchanged")
	print("PARTICLE_MEANS wither=",wither_mean/64," witch=",witch_mean/64)
	print("HORIZONTAL_CONTACT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
