extends "res://scripts/training/benchmark_100.gd"
func _run() -> void:
	game = root.get_node("Game")
	saved_settings = game.Game_Settings.duplicate(true)
	saved_locale = game.current_locale
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	Engine.time_scale = 1.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.visible = false
	await create_timer(0.5).timeout
	world._battle_random_seed = game.begin_battle_random(20260914)
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var roles:Array[String] = ["磐灯守卫","霆针游侠","时砂司祭"]
	for team:int in range(2):
		for i:int in range(3):
			world.create_char("Team"+str(team),roles[i],center+Vector2(-160+team*320,(i-1)*90))
	min_alive = 6
	await create_timer(1.0).timeout
	last_usec = Time.get_ticks_usec()
	sampling = true
func _finish() -> void:
	var status:Array = []
	for unit:Node in world.get_battle_units_fast():
		if unit.Type == 0:
			status.append({"name":unit.name,"health":unit.health,"block":unit.block,"acting":unit.Attacking or unit.Using_Skill})
	print("AI_AUTOBATTLE ",JSON.stringify({"roster":"3 vs 3 AI originals; not the 100-knife benchmark","fighters":status,"fps":samples.size()/sample_elapsed,"peak_nodes":peak_nodes}))
	game.Game_Settings = saved_settings
	game.current_locale = saved_locale
	quit()
