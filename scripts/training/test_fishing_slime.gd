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
	var fisher:Node2D=spawn("钓鱼竿",Vector2.ZERO)
	var target:Node2D=spawn("",Vector2(160,0),"Team1")
	target.health=10000
	check(fisher.image.scale.x<10.0 and fisher.sword.scale.x<2.2,"rod and sword reduced")
	check(fisher.AUDIO.EVENTS.has("entity.player.hurt"),"MC hurt event available")
	fisher.cast_at(target.global_position)
	check(fisher.cast_point(0.5).y<center.y-20,"cast visibly arcs above endpoints")
	check(fisher.cast_point(1.0).is_equal_approx(target.global_position),"ballistic destination")
	var hp:float=target.health
	for i:int in range(70):
		fisher.step_mob(0.01)
		if fisher.hook_mode==2: break
	check(fisher.hook_mode==2 and fisher.hooked==target,"parabolic hook attaches")
	check(target.health<hp,"outbound hook damages")
	check(not target.has_meta("mc_hook_hurt_only"),"temporary hurt override restored")
	fisher._attached_time=0.7
	hp=target.health
	fisher.step_mob(0.01)
	check(fisher.hook_mode==4 and target.health<hp,"attached hook retrieves with damage")
	check(target.Repel.x<0,"retrieval pulls toward owner")
	var return_hp:float=target.health
	fisher.step_mob(0.01)
	check(target.health==return_hp,"same target not damaged every return frame")
	for i:int in range(70): fisher.step_mob(0.01)
	check(fisher.hook_mode==0,"retrieval visibly completes")
	# Miss: fixed world point, delayed retrieval, intercept on the return path.
	target.global_position=center+Vector2(0,300)
	fisher.cast_at(center+Vector2(180,0))
	for i:int in range(70):
		fisher.step_mob(0.01)
		if fisher.hook_mode==3: break
	check(fisher.hook_mode==3,"miss rests instead of vanishing")
	var resting:Vector2=fisher.hook_point
	fisher.global_position+=Vector2(0,10)
	fisher.step_mob(0.3)
	check(fisher.hook_mode==3 and fisher.hook_point==resting,"resting hook stays in world space")
	target.global_position=center+Vector2(110,4)
	fisher._rest_left=0.01
	fisher.step_mob(0.02)
	check(fisher.hook_mode==4,"miss auto retrieves after delay")
	hp=target.health
	for i:int in range(60): fisher.step_mob(0.01)
	check(target.health<hp and target.Repel.x<0,"miss return can hit and pull new enemy")
	# Obstacle at the parabola apex: stop on its near face, wait, retract.
	fisher.global_position=center
	target.global_position=center+Vector2(0,300)
	var wall:StaticBody2D=obstacle(Vector2(90,-35),true)
	await physics_frame
	fisher.cast_at(center+Vector2(180,0))
	for i:int in range(70):
		fisher.step_mob(0.01)
		if fisher.hook_mode==3: break
	check(fisher.hook_mode==3 and fisher.hook_point.x<center.x+90,"hook rests on obstacle near face")
	resting=fisher.hook_point
	fisher.step_mob(0.2)
	check(fisher.hook_point==resting,"obstacle rest is stable")
	fisher.pull_hook()
	for i:int in range(70): fisher.step_mob(0.01)
	check(fisher.hook_mode==0,"obstacle hook returns without getting stuck")
	wall.queue_free()
	await physics_frame
	fisher.cast_at(center+Vector2(180,0))
	fisher.dizziness=true
	fisher.step_mob(0.01)
	check(fisher.hook_mode==0,"stun cleans up hook")
	await clear_units()
	for stage:int in range(3):
		var role:String=["史莱姆","史莱姆_中","史莱姆_小"][stage]
		var slime:Node2D=spawn(role,Vector2.ZERO,"Team0","characters" if stage==0 else "creatures")
		check(slime.body_stretch(false,0.2)<0.7,"landing squash stage "+str(stage))
		check(slime.body_stretch(true,0.18)>1.2,"takeoff stretch stage "+str(stage))
		check(is_equal_approx(slime.body_stretch(true,1.0),slime.body_stretch(false,0.0)),"landing pose continuous")
		check(is_equal_approx(slime.body_stretch(false,1.0),slime.body_stretch(true,0.0)),"takeoff pose continuous")
		for air:bool in [false,true]:
			var previous:float=slime.body_stretch(air,0.0)
			for i:int in range(1,101):
				var value:float=slime.body_stretch(air,float(i)/100)
				check(absf(value-previous)<0.14,"continuous squash/stretch sample")
				previous=value
		var before:Vector2=slime.global_position
		slime.airborne=false
		slime.move(slime.Speed,0.016)
		check(slime.global_position==before,"no sliding between jumps")
		slime.direction=Vector2.RIGHT
		slime.rest_left=0
		slime.step_mob(0.01)
		check(slime.airborne,"jump begins")
		slime._process(0.008)
		var y:float=slime.image.position.y
		slime._process(0.008)
		check(not is_equal_approx(y,slime.image.position.y),"render animation advances between physics ticks")
		var state:Dictionary=slime.visual_state()
		check(state.has("rest") and state.has("jump_direction"),"remote jump phase and direction serialized")
		await clear_units()
	# Let unrelated asynchronous resource prewarming finish before world teardown.
	await create_timer(2.0).timeout
	finish(0 if failures==0 else 1)
