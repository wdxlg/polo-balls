extends "res://scripts/training/test_mc_new5.gd"
## Native production World/Wither/skulls, rendered on the real GPU (no mocked drawing).
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(60).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.5).timeout
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	await clear_units()
	var source:Node2D = spawn("凋灵",Vector2(-100,0))
	source.summoned = true
	source.state_machine.set_physics_process(false)
	source.set_physics_process(false)
	var view:=SubViewport.new()
	view.size = Vector2i(1000,600)
	view.world_2d = world.get_world_2d()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var camera:=Camera2D.new()
	camera.zoom = Vector2(3.4,3.4)
	camera.position = center+Vector2(10,0)
	view.add_child(camera)
	camera.make_current()
	var skulls:Array[Node2D] = []
	for slot:int in range(3):
		source._fire_skull(center+Vector2(300,(slot-1)*155),slot)
		for node:Node in get_nodes_in_group("AI_Hazard"):
			if node.get_script()==source.SKULL and node not in skulls:
				node.set_physics_process(false)
				skulls.append(node)
	var evidence:String = OS.get_environment("ELYTRA_EVIDENCE_DIR")
	if evidence.is_empty(): evidence = "user://skull_trail_gpu"
	DirAccess.make_dir_recursive_absolute(evidence)
	for frame:int in range(42):
		for skull:Node2D in skulls:
			if is_instance_valid(skull) and not skull.is_queued_for_deletion(): skull._physics_process(1.0/60.0)
		for p:Node in get_nodes_in_group("MCSmokeTrail"):
			p.set_process(false)
			p._process(1.0/60.0)
		await RenderingServer.frame_post_draw
		if frame in [24,41]:
			var shot:Image = view.get_texture().get_image()
			check(not shot.is_empty(),"GPU skull trail frame readback "+str(frame))
			shot.save_png(evidence.path_join("skull-trails-"+str(frame)+".png"))
	check(skulls.size()==3 and get_nodes_in_group("MCSmokeTrail").size()>20,"all three actual fired skulls produce visible native smoke")
	view.queue_free()
	await clear_units()
	print("SKULL_TRAIL_GPU failures=",failures)
	finish(0 if failures==0 else 1)
