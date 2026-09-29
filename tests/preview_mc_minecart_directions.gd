extends "res://tests/test_mc_bat_transform.gd"
## Deliberately arranged direction/rolling showcase, not an autonomous combat benchmark.
func run() -> void:
	var center:Vector2 = await setup_world()
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	center = world.return_map_world_rect(world.map_group["Map10x10"]).get_center()
	world.control.hide()
	world.set_process(false)
	var cart:Node2D = spawn("res://scenes/characters/我的世界/矿车.tscn",center)
	cart.Can_Attack = true
	cart.state_machine.set_physics_process(false)
	cart.set_process(false)
	cart.health_bar.hide()
	await process_frame
	cart.rails.set_physics_process(false)
	DirAccess.make_dir_recursive_absolute("res://tests/minecart_direction_capture")
	var camera := Camera2D.new()
	world.add_child(camera)
	world.camera_2d.enabled = false
	camera.make_current()
	var contact:Image = Image.create(512,256,false,Image.FORMAT_RGB8)
	for i:int in range(64):
		cart.direction = Vector2.RIGHT.rotated(TAU*float(i)/64.0)
		cart._snap_facing(cart.direction)
		cart.move(110,0.05)
		cart.advance_cart_visual(0.08)
		cart.visual_mob()
		camera.global_position = cart.global_position
		camera.zoom = Vector2(5,5)
		camera.reset_smoothing()
		camera.force_update_scroll()
		await RenderingServer.frame_post_draw
		var image:Image = root.get_texture().get_image()
		var point:Vector2 = root.get_final_transform()*cart.get_global_transform_with_canvas().origin
		var crop:Image = image.get_region(Rect2i(Vector2i(point)-Vector2i(64,64),Vector2i(128,128)))
		crop.convert(Image.FORMAT_RGB8)
		crop.save_png("res://tests/minecart_direction_capture/frame_%02d.png" % i)
		if i%8 == 0:
			var slot:int = i/8
			contact.blit_rect(crop,Rect2i(0,0,128,128),Vector2i(slot%4*128,int(slot/4)*128))
	contact.save_png("res://tests/minecart_direction_capture/contact.png")
	print("MINECART GPU DIRECTIONS: 64 captured model/rolling frames")
	finish(0)
