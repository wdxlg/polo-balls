extends "res://tests/test_stone_spear.gd"
func run() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))
	game=root.get_node("Game")
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	arena=Node2D.new()
	root.add_child(arena)
	current_scene=arena
	arena.process_mode=Node.PROCESS_MODE_DISABLED
	spear=load("res://scenes/characters/我的世界/石矛.tscn").instantiate()
	arena.add_child(spear)
	check(spear.body_turn_degrees_per_second==3600.0,"180 degree U-turn takes 0.05 seconds")
	check(spear.movement_growth==10.0,"latest reduced movement acceleration preserved")
	check(spear.formation_angle_response==8.0 and spear.formation_position_response==10.0,"copy follow smoothing unchanged")
	for fps:float in [30.0,60.0,120.0]:
		for desired:float in [PI*0.5,PI]:
			reset_pose()
			spear.direction=Vector2.from_angle(desired)
			var frames:int=0
			while absf(angle_difference(spear._facing,desired))>0.0001 and frames<60:
				spear.tick_physics(spear.State.Stand,1.0/fps)
				frames+=1
			var expected:float=desired/deg_to_rad(3600.0)
			check(float(frames)/fps<=expected+1.0/fps+0.0001,"turn completes at configured rate: fps=%s angle=%s" % [fps,rad_to_deg(desired)])
			check(absf(angle_difference(spear._facing,desired))<0.0001,"body reaches exact direction without overshoot")
			check(absf(angle_difference(spear._formation_heading,desired))>0.01,"copies still visibly follow behind the faster body")
	reset_pose()
	spear.direction=Vector2.DOWN
	spear.tick_physics(spear.State.Stand,1.0/60.0)
	check(absf(rad_to_deg(spear._facing)-60.0)<0.001,"one 60Hz frame turns 60 degrees")
	check(spear._angles[0]>0.0 and spear._angles[0]<spear._facing,"first copy continues smooth angle animation")
	check(absf(angle_difference(spear.image.global_rotation,spear._facing+PI*0.75))<0.0001,"rendered main spear follows actual faster heading")
	check(absf(angle_difference(spear.self_hurtbox.global_rotation,spear._facing))<0.0001,"hurt geometry follows actual faster heading")
	spear.permanent_speed_bonus=63.0
	spear.tick_physics(spear.State.Stand,1.0/60.0)
	check(spear.permanent_speed_bonus==63.0,"turning does not consume permanent growth")
	var angle:float=spear._facing
	game.now_stop_state=true
	spear.tick_physics(spear.State.Stand,0.1)
	check(spear._facing==angle,"pause still freezes turn")
	game.now_stop_state=false
	spear.dizziness=true
	spear.tick_physics(spear.State.Stand,0.1)
	check(spear._facing==angle,"stun still prevents turning")
	reset_pose(2)
	spear._stab_wait=0.0
	check(spear.begin_stab(),"thrust launches normally")
	spear.direction=Vector2.DOWN
	spear.tick_physics(spear.State.Stand,0.08)
	check(spear._facing==0.0,"committed outward thrust remains direction-locked")
	reset_pose()
	spear._facing=PI-0.02
	spear.direction=Vector2.from_angle(-PI+0.02)
	spear.tick_physics(spear.State.Stand,1.0/60.0)
	check(absf(angle_difference(spear._facing,-PI+0.02))<0.0001,"wrap across PI takes short turn")
	reset_pose()
	spear.direction=Vector2.LEFT
	for step:int in range(3): spear.tick_physics(spear.State.Stand,1.0/60.0)
	check(absf(angle_difference(spear._facing,PI))<0.0001,"180 degree U-turn finishes in exactly three 60Hz frames")
	reset_pose()
	spear.Team="Team0"
	var target:Node2D=victim(Vector2.from_angle(PI/3.0)*spear.tip_distance())
	await physics_frame
	var hp:int=target.health
	spear._sweep_tip(0,Vector2.ZERO,Vector2.ZERO,0.0,PI*2.0/3.0,1.0/30.0,Vector2.ZERO)
	check(target.health<hp,"fast-turn arc midpoint is hit, not skipped by a chord")
	hp=target.health
	spear._sweep_tip(0,Vector2.ZERO,Vector2.ZERO,0.0,PI*2.0/3.0,1.0/30.0,Vector2.ZERO)
	check(target.health==hp,"arc subdivisions keep per-tip damage deduplication")
	print("STONE_TURN_RESULT checks=%d failures=%d" % [checks,failures])
	arena.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures==0 else 1)
