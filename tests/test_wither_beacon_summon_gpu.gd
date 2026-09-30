extends "res://scripts/training/test_mc_new5.gd"
const ARTIFACTS:String = "user://beacon_summon_gpu/"
var beacon:Node2D
var wither:Node2D

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	game.Game_Settings.Development_Mode = false
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0, true)
	create_timer(30).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world, CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.5).timeout
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	await clear_units()
	var platform:StaticBody2D = obstacle(Vector2(0, 54), true)
	(platform.get_child(0).shape as RectangleShape2D).size = Vector2(260, 12)
	await physics_frame
	wither = spawn("凋灵", Vector2(0, -155))
	wither.summoned = true
	wither.prepare_training_boss_specialization(1.0)
	wither.health = 250
	wither.on_actual_health_damage_received(1, 251)
	beacon = wither.beacon
	beacon.state_machine.set_physics_process(false)
	await process_frame
	beacon._process(0)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ARTIFACTS))
	var view:=SubViewport.new()
	view.size = Vector2i(384, 512)
	view.world_2d = world.get_world_2d()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var camera:=Camera2D.new()
	camera.zoom = Vector2(4.5, 4.5)
	camera.position = center + Vector2(0, -40)
	view.add_child(camera)
	camera.make_current()
	# Capture flight (frame 10), landed star (frame 30), white flash morph (frame 38) and settled block (frame 55).
	for i:int in range(60):
		beacon.clock += 1.0/30.0
		beacon.step_mob(1.0/30.0)
		beacon._process(0)
		await RenderingServer.frame_post_draw
		if i in [10, 30, 38, 55]:
			view.get_texture().get_image().save_png(ARTIFACTS + ("frame_%02d.png" % i))
	print("BEACON_SUMMON_GPU_CAPTURED")
	view.queue_free()
	await clear_units()
	finish(0)
