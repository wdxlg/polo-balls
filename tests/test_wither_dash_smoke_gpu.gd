extends "res://scripts/training/test_mc_new5.gd"
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(45).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.5).timeout
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	await clear_units()
	var wither:Node2D = spawn("凋灵",Vector2(-160,0))
	wither.summoned = true
	wither.state_machine.set_physics_process(false)
	wither._head_shot_left.fill(999.0)
	wither._charge_left = 999.0
	wither._charge_dir = Vector2.RIGHT
	wither._charge_remaining = wither._charge_wall_distance(wither.global_position,Vector2.RIGHT)
	wither._charge_total_dist = wither._charge_remaining
	var view:=SubViewport.new()
	view.size = Vector2i(720,480)
	view.world_2d = world.get_world_2d()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var camera:=Camera2D.new()
	camera.zoom = Vector2(2.5,2.5)
	view.add_child(camera)
	camera.make_current()
	for i:int in range(35):
		wither.tick_physics(wither.State.Move,1.0/60.0)
		camera.position = wither.global_position-Vector2(42,0)
		await RenderingServer.frame_post_draw
	check(not get_nodes_in_group("MCSmokeTrail").is_empty(),"GPU scene has active smoke trail")
	var shot:Image = view.get_texture().get_image()
	check(not shot.is_empty(),"GPU image readback succeeds")
	shot.save_png("res://.git/wither-dash-20260926/gpu.png")
	view.queue_free()
	await clear_units()
	print("WITHER_DASH_GPU failures=",failures)
	finish(0 if failures == 0 else 1)
