extends SceneTree
var game:Node
var world:Node
var saved:Dictionary
var saved_stop:bool
func _initialize() -> void: call_deferred("run")
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	world.versus_label.hide()
	await create_timer(0.4).timeout
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var names:Array[String] = ["唤魔者","潜影贝","末影人"]
	for i:int in range(3):
		var unit:Node2D = load("res://scenes/characters/我的世界/" + names[i] + ".tscn").instantiate()
		unit.Team = "Team0"
		world.add_child(unit,true)
		unit.global_position = center + Vector2(float(i-1)*95.0,0)
		unit.state_machine.set_physics_process(false)
		if i == 1:
			unit.shell_open = true
			unit._update_shell_visual()
		if i == 2:
			unit.rage_remaining = 6.0
			unit.tick_physics(0,0.5)
		var label := Label.new()
		world.add_child(label)
		label.global_position = unit.global_position + Vector2(-18,27)
		label.text = names[i]
		label.add_theme_font_size_override("font_size",12)
		label.modulate = Color.WHITE
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.global_position = center
	camera.zoom = Vector2(3,3)
	camera.make_current()
	await process_frame
	await RenderingServer.frame_post_draw
	var image:Image = root.get_texture().get_image()
	print("MC_PREVIEW_SIZE=",image.get_size())
	var size:Vector2i = image.get_size()
	image = image.get_region(Rect2i(Vector2i(int(size.x*0.12),int(size.y*0.39)),Vector2i(int(size.x*0.76),int(size.y*0.24))))
	print("MC_PREVIEW_BASE64=",Marshalls.raw_to_base64(image.save_png_to_buffer()))
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	world.queue_free()
	current_scene = null
	await process_frame
	await process_frame
	print("MC_PREVIEW_EXIT=0")
	quit()
