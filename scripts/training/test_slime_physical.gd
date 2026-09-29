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
	game.Game_Settings.Have_Team_Damage=true
	var parent:Node2D=spawn("史莱姆",Vector2.ZERO,"")
	var family:String=parent.slime_family
	parent.Die()
	var children:Array[Node2D]=[]
	for node:Node in get_nodes_in_group("Ball"):
		if node!=parent and node.get_script()==parent.get_script():
			node.state_machine.set_physics_process(false)
			children.append(node)
	check(children.size()==2,"two split children")
	for child:Node2D in children: check(child.slime_family==family,"family inherited before ready")
	children[0].global_position=center
	children[1].global_position=center+Vector2(1,0)
	var hp:float=children[1].health
	children[0]._pulse(false)
	children[0]._pulse(true)
	check(children[1].health==hp,"siblings immune to both pulses with friendly fire enabled")
	children[0].Die()
	for node:Node in get_nodes_in_group("Ball"):
		if node.get_script()==parent.get_script() and node.slime_stage==2:
			check(node.slime_family==family,"grandchildren inherit same family")
	await clear_units()
	game.Game_Settings.Have_Team_Damage=false
	for stage:int in range(3):
		var slime:Node2D=spawn(["史莱姆","史莱姆_中","史莱姆_小"][stage],Vector2.ZERO,"Team0","characters" if stage==0 else "creatures")
		var target:Node2D=spawn("",Vector2(200,0),"Team1")
		target.health=10000
		var tr:float=u.radius(target)
		target.global_position=center+Vector2(slime.pulse_radius(true)+tr+1,0)
		check(not slime.pulse_contains(target,true),"outside landing circle excluded")
		target.global_position=center+Vector2(slime.pulse_radius(true)+tr-1,0)
		check(slime.pulse_contains(target,true),"inside landing circle included")
		target.global_position=center+Vector2(u.radius(slime)+tr,0)
		check(slime.pulse_contains(target,false),"initial body contact included")
		check(slime.pulse_radius(false)<slime.pulse_radius(true),"takeoff circle smaller than landing")
		var analyzer:Node=load("res://scripts/training/combat_threat_analyzer.gd").new()
		world.add_child(analyzer)
		game.Game_Settings.Training_Debug_Mode=true
		var declared:int=0
		for threat:Dictionary in analyzer.get_world_threats():
			if str(threat.get("kind","")).begins_with("slime_"): declared+=1
		check(declared>=2,"threat display receives actual slime circles")
		analyzer.queue_free()
		target.queue_free()
		await physics_frame
		slime.direction=Vector2.RIGHT
		slime.rest_left=0
		slime.step_mob(0.001)
		var start:Vector2=slime.global_position
		var min_y:float=start.y
		var shadow_min:float=1.0
		var bar_min:float=slime.health_bar.global_position.y
		var bar_start:float=bar_min
		for i:int in range(100):
			await physics_frame
			var dt:float=slime.get_physics_process_delta_time()
			slime.step_mob(dt)
			slime.move(slime.Speed,dt)
			slime._process(dt)
			min_y=minf(min_y,slime.global_position.y)
			bar_min=minf(bar_min,slime.health_bar.global_position.y)
			if is_instance_valid(slime._character_ground_shadow): shadow_min=minf(shadow_min,slime._character_ground_shadow.scale.x)
			check(slime.get_node("CollisionShape2D").global_position.is_equal_approx(slime.global_position),"body collider follows real arc")
			if not slime.airborne: break
		check(min_y<start.y-5,"root position actually rises")
		check(bar_min<bar_start-3,"health bar follows airborne body")
		check(shadow_min<0.8,"shadow shrinks at height")
		check(absf(slime.global_position.y-start.y)<1,"unobstructed arc lands on ground without teleport")
		check(not slime.airborne,"physical landing ends jump")
		# Ceiling physically blocks upward arc; no sprite-only lift through it.
		slime.global_position=center
		var wall:StaticBody2D=obstacle(Vector2(0,-u.radius(slime)-10),true)
		wall.get_child(0).shape.size=Vector2(300,8)
		await physics_frame
		slime.direction=Vector2.RIGHT
		slime.rest_left=0
		slime.step_mob(0.001)
		for i:int in range(100):
			await physics_frame
			var dt:float=slime.get_physics_process_delta_time()
			slime.step_mob(dt)
			slime.move(slime.Speed,dt)
			check(slime.global_position.y>=wall.global_position.y+4+u.radius(slime)-0.5,"arc cannot pass through ceiling")
			if not slime.airborne: break
		wall.queue_free()
		await clear_units()
	await create_timer(2).timeout
	finish(0 if failures==0 else 1)
