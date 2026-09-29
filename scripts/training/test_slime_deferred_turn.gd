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
	for stage:int in range(3):
		var slime:Node2D=spawn(["史莱姆","史莱姆_中","史莱姆_小"][stage],Vector2.ZERO,"Team0","characters" if stage==0 else "creatures")
		var target:Node2D=spawn("",Vector2(0,300),"Team1")
		target.health=10000
		slime.direction=Vector2.RIGHT
		slime.rest_left=0
		slime.step_mob(0.001)
		target.global_position=center+Vector2(u.radius(slime)+u.radius(target)+3,-slime.jump_height*0.55)
		await physics_frame
		var recorded:bool=false
		for i:int in range(120):
			await physics_frame
			var dt:float=slime.get_physics_process_delta_time()
			slime.step_mob(dt)
			slime.move(slime.Speed,dt)
			if slime.airborne:
				check(slime.jump_direction.x>0.99,"character collision cannot turn airborne heading")
				if slime._pending_character_direction.length_squared()>0.001:
					recorded=true
					check(slime.direction.is_equal_approx(slime.jump_direction),"ground direction remains locked until landing")
			else: break
		check(recorded,"real character contact records pending turn stage "+str(stage))
		check(slime.direction.x<0,"recorded turn applied after landing")
		check(slime._pending_character_direction==Vector2.ZERO,"pending turn consumed once")
		slime.rest_left=0
		slime.step_mob(0.001)
		check(slime.jump_direction.x<0,"next jump uses deferred character heading")
		# Character scripts may directly assign direction instead of triggering own contact.
		slime.direction=Vector2.DOWN
		slime.step_mob(0.01)
		check(slime.jump_direction.x<0 and slime._pending_character_direction==Vector2.DOWN,"external turn also waits for landing")
		await clear_units()
	# Prepared children are inert, get their real identity only on activation.
	var parent:Node2D=spawn("史莱姆",Vector2.ZERO,"Team0")
	await create_timer(0.3).timeout
	check(parent._prepared_children.size()==2,"two children prepared in advance")
	for child:Node2D in parent._prepared_children:
		check(not child.is_inside_tree(),"prepared child has no physics/timers/groups")
		check(child.get_node("Health_Bar/TextureRect/Label").get_theme_font("font").multichannel_signed_distance_field,"split label preconverted to MSDF")
	var family:String=parent.slime_family
	parent.Die()
	var count:int=0
	for node:Node in get_nodes_in_group("Ball"):
		if node.get_script()==parent.get_script() and node.slime_stage==1:
			node.state_machine.set_physics_process(false)
			count+=1
			check(node.slime_family==family and node.Team=="Team0","prepared child inherits family and team at activation")
	check(count==2,"preparation does not change split count")
	await clear_units()
	check(int(world.get_meta("mc_slime_preparation").total)==0,"deletion releases all unused prototypes")
	await create_timer(2).timeout
	finish(0 if failures==0 else 1)
