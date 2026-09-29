extends "res://tests/test_mc_frontier.gd"
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(45).timeout.connect(func(): finish(2))
	world.control.hide()
	world.set_process(false)
	world.set_physics_process(false)
	world.camera_2d.enabled = false
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.global_position = center
	camera.zoom = Vector2.ONE*1.7
	camera.make_current()
	var man:Node2D = actor("雾中人",center+Vector2(-100,-25))
	var enemy:Node2D = actor("苔藓",center+Vector2(70,5),"Team1")
	enemy.velocity = Vector2.RIGHT*30.0
	enemy.visual_mob()
	var other:Node2D = actor("末影人",center+Vector2(90,135),"Team1")
	other.velocity = Vector2(-10,-20)
	man.clock = 1.0
	man.velocity = Vector2.RIGHT*25.0
	man.visual_mob()
	man.fog.fog_alpha = 0.45
	man.fog._process(0.11)
	await create_timer(1.0).timeout
	for i:int in range(8):
		man.global_position.x += 3.0
		man.eye_fx._process(0.03)
		await process_frame
	await RenderingServer.frame_post_draw
	var image:Image = root.get_texture().get_image()
	image.save_png("res://tests/fog_man_preview.png")
	man.fog.mask_view.get_texture().get_image().save_png("res://tests/fog_man_mask.png")
	print("FOG DEBUG alpha=",man.fog.fog_alpha," uniform=",man.fog.mask_material.get_shader_parameter("opacity")," owners=",man.fog.owners().size()," viewport=",man.fog.mask_view.size," eye=",man.eye_texture().resource_path)
	print("FOG GPU PREVIEW saved; image=",image.get_size()," body=",man.image.global_scale," mask=",man.fog.bounds," trails=",man.eye_fx.trails.size())
	check(image.get_width()>0,"GPU frame captured")
	check(man.eye_fx.trails.size()>0,"GPU capture includes moving eye trails")
	var eye:Vector2 = root.get_final_transform()*(man.eye_fx.get_global_transform_with_canvas()*man.eye_fx.eye_points()[0])
	var bright:float = 0.0
	for x:int in range(-3,4):
		for y:int in range(-3,4):
			var pixel:Vector2i = Vector2i(eye)+Vector2i(x,y)
			if pixel.x>=0 and pixel.y>=0 and pixel.x<image.get_width() and pixel.y<image.get_height():
				var color:Color = image.get_pixelv(pixel)
				bright = maxf(bright,color.v)
	check(bright>0.7,"eyes remain visibly bright above dense fog")
	print("FOG TRANSFORM ",man.fog.global_transform," veil=",man.fog.veil.global_transform," visible=",man.fog.veil.is_visible_in_tree()," polygon=",man.fog.veil.polygon)
	man.fog.hide()
	await RenderingServer.frame_post_draw
	var plain:Image = root.get_texture().get_image()
	print("FOG PIXELS with=",image.get_pixel(200,300)," without=",plain.get_pixel(200,300))
	check(image.get_pixel(200,300).b>plain.get_pixel(200,300).b+0.06,"fog actually renders over battlefield rather than only computing a mask")
	finish(0 if failures==0 else 1)
