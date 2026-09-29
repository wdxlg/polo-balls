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
		var wall:StaticBody2D=obstacle(Vector2(u.radius(slime)+10,0),true)
		await physics_frame
		slime.direction=Vector2.RIGHT
		slime.rest_left=0
		slime.step_mob(0.001)
		check(slime.jump_distance>=slime.jump_min_distance,"wall does not create zero-distance loop")
		var bounced:bool=false
		var contact_x:float=0.0
		var total_travel:float=0.0
		var before:Vector2=slime.global_position
		for i:int in range(120):
			await physics_frame
			var dt:float=slime.get_physics_process_delta_time()
			slime.move(slime.Speed,dt)
			total_travel+=before.distance_to(slime.global_position)
			before=slime.global_position
			if not bounced and slime.jump_direction.x<0:
				bounced=true
				contact_x=slime.global_position.x
				check(slime._jump_remaining>0,"collision preserves remaining travel")
				check(slime.direction.x<0,"bounce updates next jump direction")
			slime.step_mob(dt)
			if not slime.airborne: break
		check(bounced,"real wall collision reflects jump stage "+str(stage))
		check(slime.global_position.x<contact_x-2,"continues away from wall during same jump")
		check(total_travel<=slime.jump_distance+2.0*slime.jump_height+1,"bounce does not reset distance budget")
		slime.rest_left=0
		slime.step_mob(0.001)
		check(slime.airborne and slime.jump_direction.x<0,"next jump heads away instead of into wall")
		wall.queue_free()
		await clear_units()
	await create_timer(2).timeout
	finish(0 if failures==0 else 1)
