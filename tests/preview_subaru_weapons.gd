extends "res://tests/test_mc_bat_transform.gd"
func run() -> void:
	var center:Vector2 = await setup_world()
	game.Game_Settings.Training_Debug_Mode = false
	world.versus_label.hide()
	var s:Node2D = spawn("res://scenes/characters/动漫/菜月昴.tscn",center-Vector2(35,0))
	s.state_machine.set_physics_process(false)
	s._timeline.set_physics_process(false)
	s.Speed = 0.0
	s.default_properties.Speed = 0.0
	s.health_bar.hide()
	var e:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(35,0),"Team1")
	e.state_machine.set_physics_process(false)
	e.Has_Collision_Damage = false
	e.self_hitbox.monitoring = false
	e.Max_health = 10000
	e.default_properties.Max_health = 10000
	e.health = 10000
	e.health_bar.hide()
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.global_position = center
	camera.zoom = Vector2(4,4)
	camera.make_current()
	for frame:int in range(40):
		if frame == 13: s._hand_window_left = 0.001 # Skip only the initial wait in this showcase.
		for i:int in range(4):
			s.tick_physics(0,1.0/60.0)
			await physics_frame
		await RenderingServer.frame_post_draw
		var picture:Image = root.get_texture().get_image()
		var size:Vector2i = picture.get_size()
		picture.get_region(Rect2i(Vector2i(size.x/2-210,size.y/2-150),Vector2i(420,300))).save_png("res://tests/subaru_weapon_%02d.png"%frame)
	print("SUBARU_WEAPONS_GPU_CAPTURED 40")
	finish(0)
