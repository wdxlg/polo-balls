extends "res://tests/test_mc_frontier.gd"
## Actual GPU layer proof + grid-overlap, arc-turn and random-departure showcase.
func gray_pixels(image:Image,point:Vector2) -> int:
	var region:Rect2i = Rect2i(Vector2i(point)-Vector2i(24,20),Vector2i(48,40)).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	var count:int = 0
	for y:int in range(region.position.y,region.end.y):
		for x:int in range(region.position.x,region.end.x):
			var p:Color = image.get_pixel(x,y)
			var hi:float = maxf(p.r,maxf(p.g,p.b)); var lo:float = minf(p.r,minf(p.g,p.b))
			if hi>0.22 and hi<0.92 and hi-lo<0.075: count += 1
	return count
func run() -> void:
	var center:Vector2 = await setup_world()
	world.control.hide()
	world.set_process(false)
	world.set_physics_process(false)
	world.camera_2d.enabled = false
	var camera := Camera2D.new()
	camera.position_smoothing_enabled = false
	world.add_child(camera)
	camera.make_current()
	var witness:Node2D = dummy(center+Vector2(280,280))
	witness.hide(); witness.health_bar.hide()
	var cart:Node2D = actor("矿车",center)
	cart.side_status_ui_enabled = false
	cart.health_bar.hide()
	cart.set_process(true)
	await process_frame
	var net:Node2D = cart.rails
	var origin:Vector2 = net.cell_to_world(net.world_to_cell(center))
	var a:Vector2 = origin+Vector2(-144,-72)
	var b:Vector2 = origin+Vector2(48,-72)
	var c:Vector2 = origin+Vector2(48,120)
	var d:Vector2 = origin+Vector2(-72,120)
	cart.global_position = a
	var first:Dictionary = net.commit_path(cart,net.prepare_path(cart,PackedVector2Array([a,b,c])))
	check(not first.is_empty(),"GPU grid fixture builds the first L-shaped path")
	var power_point:Vector2 = a+Vector2(168,0)
	cart.global_position = power_point
	cart.direction = Vector2.RIGHT
	cart._snap_facing(Vector2.RIGHT)
	cart.visual_mob()
	cart.cart_fx.visible = false
	camera.global_position = power_point
	camera.zoom = Vector2(3,3)
	camera.force_update_scroll()
	# Compare the correct draw against a deliberately wrong layer at the same opaque car pixels.
	net.z_index = net.BODY_Z+1
	await RenderingServer.frame_post_draw
	var bad:Image = root.get_texture().get_image()
	var point:Vector2 = root.get_final_transform()*cart.get_global_transform_with_canvas().origin
	var hidden_gray:int = gray_pixels(bad,point)
	net.z_index = net.GROUND_Z
	await RenderingServer.frame_post_draw
	var correct:Image = root.get_texture().get_image()
	var body_gray:int = gray_pixels(correct,point)
	check(body_gray > hidden_gray+8,"GPU pixels prove the cart is drawn over the powered rail, not underneath")
	print("GRID_LAYER_PIXELS correct=",body_gray," covered=",hidden_gray)
	cart.global_position = a+Vector2(0,8)
	cart.direction = Vector2.RIGHT
	cart.set_player_control_peer(0) # Normal movement, including the post-trip random direction.
	cart.idle_left = 99.0 # Construction timing is covered in the separate live test.
	cart.cart_fx.visible = true
	cart.state_machine.set_physics_process(true)
	camera.global_position = origin+Vector2(-36,24)
	camera.zoom = Vector2(2,2)
	camera.force_update_scroll()
	var destination:String = "res://tests/rail_grid_capture"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination))
	var ignore:FileAccess = FileAccess.open(destination+"/.gdignore",FileAccess.WRITE)
	ignore.store_string("Generated GPU capture frames.\n"); ignore.close()
	var records:Array[Dictionary] = []
	var overlap_done:bool = false
	var extension_done:bool = false
	var merge_ok:bool = false
	var last_port:Vector2 = Vector2.ZERO
	var exit_distance:float = 0.0
	var entered:int = 0
	var reentered_while_latched:bool = false
	for i:int in range(110):
		Engine.time_scale = 1.0
		await create_timer(0.055,true,false,true).timeout
		if cart.clock > 0.6 and not overlap_done:
			var before:int = net.nodes.size()
			net.commit_path(cart,net.prepare_path(cart,PackedVector2Array([a,b])))
			merge_ok = net.nodes.size()==before and net.cell_at(power_point).powered
			overlap_done = true
		if cart.clock > 1.1 and not extension_done:
			extension_done = not net.commit_path(cart,net.prepare_path(cart,PackedVector2Array([c,d]))).is_empty()
		if cart.departure_count > 0:
			if last_port == Vector2.ZERO: last_port = cart.global_position
			exit_distance = maxf(exit_distance,cart.global_position.distance_to(last_port))
			camera.global_position = (origin+Vector2(-36,24)).lerp(cart.global_position,0.45)
			camera.force_update_scroll()
		if cart.entry_needs_exit and cart.boarded_routes > entered: reentered_while_latched = true
		entered = cart.boarded_routes
		await RenderingServer.frame_post_draw
		var screen:Image = root.get_texture().get_image()
		var focus:Vector2 = root.get_final_transform()*(cart.get_canvas_transform()*camera.global_position)
		var region:Rect2i = Rect2i(Vector2i(focus)-Vector2i(180,130),Vector2i(360,260)).intersection(Rect2i(Vector2i.ZERO,screen.get_size()))
		var frame:Image = screen.get_region(region)
		frame.resize(720,520,Image.INTERPOLATE_NEAREST)
		var filename:String = "frame_%03d.png" % i
		frame.save_png(destination+"/"+filename)
		records.append({"file":filename,"time_ms":int(cart.clock*1000),"speed":cart.drive_speed,"powered":cart.rail_powered,"phase":cart.rush_phase,"cells":net.nodes.size(),"draw_cells":net.last_draw_cell_count,"merged":overlap_done,"power_kept":merge_ok,"turns":cart.turns_taken,"boards":cart.boarded_routes,"departures":cart.departure_count,"needs_exit":cart.entry_needs_exit})
	var metadata:FileAccess = FileAccess.open(destination+"/frames.json",FileAccess.WRITE)
	metadata.store_string(JSON.stringify(records,"\t")); metadata.close()
	check(merge_ok,"GPU overlap preserves one cell and powered priority")
	check(cart.turns_taken>=2,"actual GPU motion follows the visible arc corners")
	check(cart.departure_count>0 and exit_distance>30.0,"cart visibly leaves in its new random direction using normal movement")
	check(not reentered_while_latched,"the random-departure showcase does not immediately bounce back from the same port")
	print("GRID_GPU frames=",records.size()," cells=",net.nodes.size()," draws=",net.last_draw_cell_count," turns=",cart.turns_taken," departures=",cart.departure_count," exit_distance=",exit_distance)
	finish(0 if failures==0 else 1)
