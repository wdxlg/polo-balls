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
	var guardian:Node2D=spawn("守卫者",Vector2.ZERO,"Team0")
	var target:Node2D=spawn("",Vector2(150,0),"Team1")
	target.health=10000
	for angle:int in range(0,360,10):
		guardian.break_lock()
		target.global_position=center+Vector2.RIGHT.rotated(deg_to_rad(angle))*150.0
		guardian.step_mob(0.01)
		check(guardian.locked==target and guardian.beam_active,"acquires at "+str(angle)+" degrees")
	check(not guardian.in_sector(Vector2(guardian.laser_range+1,0)),"range limit preserved")
	guardian.break_lock()
	target.global_position=center+Vector2(150,0)
	guardian.step_mob(0.01)
	var charge:float=guardian._tick_left
	target.global_position=center+Vector2(-110,110)
	guardian.step_mob(0.1)
	check(guardian.locked==target and is_equal_approx(guardian._tick_left,charge-0.1),"crossing old sectors preserves charge")
	var closer:Node2D=spawn("",Vector2(50,0),"Team1")
	guardian.step_mob(0.01)
	check(guardian.locked==target,"closer target cannot steal valid lock")
	closer.queue_free()
	await process_frame
	target.global_position=center+Vector2(150,0)
	var wall:StaticBody2D=obstacle(Vector2(75,0),true)
	await physics_frame
	guardian.step_mob(0.01)
	check(not guardian.beam_active,"wall still blocks lock")
	wall.queue_free()
	await physics_frame
	guardian.step_mob(0.01)
	guardian.dizziness=true
	guardian.step_mob(0.01)
	check(not guardian.beam_active,"stun still interrupts charge")
	guardian.dizziness=false
	target.global_position=center+Vector2(300,0)
	guardian.step_mob(0.01)
	check(not guardian.beam_active,"out of range cannot acquire")
	target.global_position=center+Vector2(105,105)
	guardian.step_mob(0.01)
	var hp:float=target.health
	guardian.step_mob(guardian.laser_tick)
	check(is_equal_approx(hp-target.health,90.0),"diagonal laser retains 90 damage")
	await clear_units()
	await create_timer(2).timeout
	finish(0 if failures==0 else 1)
