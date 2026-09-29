extends "res://scripts/training/test_mc_new5.gd"

func tick_actor(slime:Node2D,delta:float,effect:Node=null) -> void:
	# Drive the actual shared tick dispatch: dizziness redirects Move to Stand.
	slime.tick_physics(slime.State.Move,delta)
	if is_instance_valid(effect) and not effect._finished: effect._physics_process(delta)

func start_jump(slime:Node2D,fraction:float) -> void:
	slime.direction=Vector2.RIGHT
	slime.rest_left=0.0
	slime.step_mob(0.001)
	while slime.jump_elapsed<slime.jump_duration*fraction:
		await physics_frame
		tick_actor(slime,slime.get_physics_process_delta_time())

func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	Engine.time_scale=1.0
	AudioServer.set_bus_mute(0,true)
	create_timer(100,true,false,true).timeout.connect(func():finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.5).timeout
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	u=load("res://scripts/characters/我的世界/new5/utils.gd")
	for stage:int in range(3):
		for fraction:float in [0.15,0.5,0.85]:
			await clear_units()
			var slime:Node2D=spawn(["史莱姆","史莱姆_中","史莱姆_小"][stage],Vector2.ZERO,"Team0","characters" if stage==0 else "creatures")
			var source:Node2D=spawn("",Vector2(300,300),"Team1")
			await start_jump(slime,fraction)
			var hit:Vector2=slime.global_position
			var effect:Node=slime.apply_knockback(Vector2.LEFT,45.0,180.0,0.0,0.45,{"source":source,"smooth_motion":false,"minimum_motion_time":0.0,"control_recovery_time":0.0})
			effect.set_physics_process(false)
			check(slime.airborne and slime.dizziness,"real knockback takes control during flight stage="+str(stage)+" phase="+str(fraction))
			var smooth:bool=true
			var only_knock_x:bool=true
			var coherent:bool=true
			var landed_while_locked:bool=false
			var done:bool=false
			for frame:int in range(150):
				await physics_frame
				var dt:float=slime.get_physics_process_delta_time()
				var from:Vector2=slime.global_position
				var locked:bool=slime.dizziness
				var max_step:float=(4.0*slime.jump_height/slime.jump_duration+1.5*slime.jump_distance/slime.jump_duration+slime.Repel.length())*dt+0.5
				tick_actor(slime,dt,effect if is_instance_valid(effect) else null)
				smooth=smooth and slime.global_position.distance_to(from)<=max_step
				if locked: only_knock_x=only_knock_x and slime.global_position.x<=from.x+0.01
				coherent=coherent and slime.get_node("CollisionShape2D").global_position.is_equal_approx(slime.global_position)
				landed_while_locked=landed_while_locked or (not slime.airborne and slime.dizziness)
				if not is_instance_valid(effect) or effect._finished:
					done=true
					break
			check(done and landed_while_locked,"airborne motion completes during control instead of waiting for recovery")
			var release:Vector2=slime.global_position
			await physics_frame
			tick_actor(slime,slime.get_physics_process_delta_time())
			check(smooth and slime.global_position.distance_to(release)<0.1,"recovery has no single-frame replay or snap back")
			check(only_knock_x and absf(slime.global_position.x-(hit.x-45.0))<1.0,"locked jump travel is discarded and real knockback displacement is retained")
			check(coherent and absf(slime.global_position.y-center.y)<0.1 and is_zero_approx(slime._jump_lift),"body/collider finish the arc smoothly with no hidden leftover lift")
			check(not slime.airborne and not slime.dizziness and slime.rest_left>0.0,"landing/rest and control release each complete normally")
	# A short lock recovers before landing: only NEW per-frame travel may resume.
	await clear_units()
	var slime:Node2D=spawn("史莱姆",Vector2.ZERO)
	var source:Node2D=spawn("",Vector2(300,300),"Team1")
	await start_jump(slime,0.15)
	var effect:Node=slime.apply_knockback(Vector2.LEFT,8.0,160.0,0.0,0.0,{"source":source,"smooth_motion":false,"minimum_motion_time":0.0,"control_recovery_time":0.04})
	effect.set_physics_process(false)
	var smooth:bool=true
	var resumed_airborne:bool=false
	for frame:int in range(90):
		await physics_frame
		var dt:float=slime.get_physics_process_delta_time()
		var from:Vector2=slime.global_position
		var max_step:float=(4.0*slime.jump_height/slime.jump_duration+1.5*slime.jump_distance/slime.jump_duration+slime.Repel.length())*dt+0.5
		tick_actor(slime,dt,effect if is_instance_valid(effect) else null)
		smooth=smooth and slime.global_position.distance_to(from)<=max_step
		resumed_airborne=resumed_airborne or (not slime.dizziness and slime.airborne)
		if not slime.airborne: break
	check(smooth and resumed_airborne,"short knockback including shared recovery transition cannot replay skipped jump frames")
	check(not slime.airborne and absf(slime.global_position.y-center.y)<0.1,"short lock still lands on the smoothly translated arc")
	# Collision remains real while the airborne Stand path consumes its arc.
	await clear_units()
	slime=spawn("史莱姆",Vector2.ZERO)
	source=spawn("",Vector2(300,300),"Team1")
	await start_jump(slime,0.25)
	var wall:StaticBody2D=obstacle(Vector2(-40,0),true)
	wall.get_child(0).shape.size=Vector2(8,200)
	await physics_frame
	effect=slime.apply_knockback(Vector2.LEFT,100.0,260.0,0.0,0.45,{"source":source,"control_recovery_time":0.0})
	effect.set_physics_process(false)
	var blocked:bool=true
	for frame:int in range(120):
		await physics_frame
		tick_actor(slime,slime.get_physics_process_delta_time(),effect if is_instance_valid(effect) else null)
		blocked=blocked and slime.global_position.x>=wall.global_position.x+4.0+u.radius(slime)-0.5
		if not slime.dizziness and not slime.airborne: break
	check(blocked and not slime.dizziness and not slime.airborne,"airborne knockback still stops at solid walls and finishes without delayed movement")
	wall.queue_free()
	# Non-locking displacement still stacks with the normal jump each frame.
	await clear_units()
	slime=spawn("史莱姆",Vector2.ZERO)
	await start_jump(slime,0.25)
	var before:Vector2=slime.global_position
	await physics_frame
	var dt:float=slime.get_physics_process_delta_time()
	var phase:float=slime._motion_phase
	var t:float=minf(1.0,(slime.jump_elapsed+dt)/slime.jump_duration)
	var travel:float=slime.jump_distance*((3*t*t-2*t*t*t)-(3*phase*phase-2*phase*phase*phase))
	slime.Repel=Vector2.LEFT*120.0
	tick_actor(slime,dt)
	check(absf(slime.global_position.x-before.x-(travel-120.0*dt))<0.1,"non-locking Repel remains additive rather than resetting the jump origin")
	# Vertical knockback also retains a continuous path, not an old-height catch-up.
	for axis:Vector2 in [Vector2.UP,Vector2.DOWN]:
		await clear_units()
		slime=spawn("史莱姆",Vector2.ZERO)
		source=spawn("",Vector2(300,300),"Team1")
		await start_jump(slime,0.3)
		effect=slime.apply_knockback(axis,40.0,200.0,0.0,0.45,{"source":source,"control_recovery_time":0.0})
		effect.set_physics_process(false)
		smooth=true
		for frame:int in range(180):
			await physics_frame
			dt=slime.get_physics_process_delta_time()
			before=slime.global_position
			var bound:float=(4.0*slime.jump_height/slime.jump_duration+1.5*slime.jump_distance/slime.jump_duration+slime.Repel.length())*dt+0.5
			tick_actor(slime,dt,effect if is_instance_valid(effect) else null)
			smooth=smooth and slime.global_position.distance_to(before)<=bound
			if not slime.dizziness and not slime.airborne: break
		before=slime.global_position
		await physics_frame
		tick_actor(slime,slime.get_physics_process_delta_time())
		check(smooth and not slime.airborne and slime.global_position.distance_to(before)<0.1,"vertical knockback finishes without a queued height correction: "+str(axis))
	# Golem flight moves the body directly, instead of writing ordinary Repel.
	await clear_units()
	slime=spawn("史莱姆",Vector2.ZERO)
	var golem:Node2D=spawn("铁傀儡",Vector2(300,300),"Team1")
	await start_jump(slime,0.35)
	effect=golem.launch_target(slime,55.0,260.0,Vector2.UP)
	effect.set_physics_process(false)
	smooth=true
	var saw_landing:bool=false
	for frame:int in range(220):
		await physics_frame
		dt=slime.get_physics_process_delta_time()
		before=slime.global_position
		var external_speed:float=absf(effect._vertical_speed) if is_instance_valid(effect) and not effect.landed else 0.0
		var bound:float=(4.0*slime.jump_height/slime.jump_duration+external_speed+40.0)*dt+0.5
		tick_actor(slime,dt,effect if is_instance_valid(effect) else null)
		smooth=smooth and slime.global_position.distance_to(before)<=bound
		if is_instance_valid(effect): saw_landing=saw_landing or effect.landed
		if not slime.dizziness and not slime.airborne: break
	before=slime.global_position
	await physics_frame
	tick_actor(slime,slime.get_physics_process_delta_time())
	check(smooth and saw_landing and not slime.dizziness,"real golem physical launch coexists with continuous slime arc consumption")
	check(not slime.airborne and slime.global_position.distance_to(before)<0.1 and not slime.has_meta("golem_air_height"),"golem recovery cannot snap a slime back to its old jump position")
	slime.rest_left=0.0
	slime.step_mob(0.001)
	check(slime.airborne and slime.global_position.is_equal_approx(before),"next jump starts at the retained current position, without a stored origin reset")
	print("SLIME_KNOCKBACK_CONTINUITY checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
