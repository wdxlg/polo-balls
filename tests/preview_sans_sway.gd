extends "res://tests/test_mc_bat_transform.gd"
func run() -> void:
	var center:Vector2 = await setup_world()
	game.Game_Settings.Training_Debug_Mode = false
	world.versus_label.hide()
	var s:Node2D = spawn("res://scenes/characters/传说之下/Sans.tscn",center)
	s.state_machine.set_physics_process(false)
	s.set_process(false)
	s.health_bar.hide()
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.global_position = center
	camera.zoom = Vector2(8,8)
	camera.make_current()
	s._idle_sway_elapsed = 0.0
	for i:int in range(24):
		s._update_sans_visual(1.0/12.0)
		await RenderingServer.frame_post_draw
		var picture:Image = root.get_texture().get_image()
		var size:Vector2i = picture.get_size()
		picture.get_region(Rect2i(Vector2i(size.x/2-160,size.y/2-150),Vector2i(320,300))).save_png("res://tests/sans_sway_%02d.png"%i)
	print("SANS_SWAY_GPU_CAPTURED 24")
	finish(0)
