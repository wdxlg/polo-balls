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
	for iteration:int in range(3):
		var actor:Node2D=spawn("史莱姆",Vector2.ZERO,"Team0")
		await create_timer(0.25).timeout
		check(actor._prepared_children.size()==2,"large prepared both off-tree children")
		var begin:int=Time.get_ticks_usec()
		actor.Die()
		var split_usec:int=Time.get_ticks_usec()-begin
		var medium_usec:int=0
		var mediums:Array[Node]=[]
		for node:Node in get_nodes_in_group("Ball"):
			if node.get_script()==actor.get_script() and node.slime_stage==1:
				mediums.append(node)
				node.state_machine.set_physics_process(false)
		check(mediums.size()==2,"exactly two medium")
		await create_timer(0.25).timeout
		for medium:Node in mediums:
			begin=Time.get_ticks_usec()
			medium.Die()
			medium_usec+=Time.get_ticks_usec()-begin
		print("SPLIT_PROFILE iteration=",iteration," large_us=",split_usec," two_medium_us=",medium_usec)
		await clear_units()
	await create_timer(2).timeout
	finish(0 if failures==0 else 1)
