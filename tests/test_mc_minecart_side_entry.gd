extends "res://tests/test_mc_minecart.gd"
func ready_cart(cart:Node2D,point:Vector2,goal:Vector2) -> void:
	cart.end_rush()
	cart.global_position = point
	cart.entry_needs_exit = false
	cart._boarding_lock = 0.0
	cart.idle_left = 999.0
	cart.set_player_control_peer(1)
	cart.set_player_control_aim_position(goal)
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(60).timeout.connect(func(): finish(2))
	var cart:Node2D = actor("矿车",center)
	var _target:Node2D = dummy(center+Vector2(240,240))
	await physics_frame
	await process_frame
	var net:Node2D = cart.rails
	var o:Vector2 = net.cell_to_world(net.world_to_cell(center))
	check(net.z_index==-4 and not net.z_as_relative,"preview and committed rails use absolute ground layer -4")
	check(net.z_index> -5 and net.z_index<world.z_index,"rails above floor but below World default character/obstacle/projectile layer")
	check(net.z_index<cart.image.z_index,"cart body is above ground rail")
	# Lower horizontal endpoint, vertical bottom one cell directly above it: BOTH build orders.
	for reverse:bool in [false,true]:
		net.clear_tracks()
		var start:Vector2 = o-Vector2(96,0)
		var end:Vector2 = o-Vector2(0,96)
		ready_cart(cart,start,end)
		var h:PackedVector2Array = PackedVector2Array([start,o])
		var v:PackedVector2Array = PackedVector2Array([o-Vector2(0,24),end])
		build_grid(cart,v if reverse else h)
		build_grid(cart,h if reverse else v)
		check(net.cell_at(o).mask==12,"horizontal end visibly bends upward irrespective of build order")
		check(net.neighbors(int(net.cell_at(o).id)).size()==2,"adjacent vertical end physically connects")
		check(board_fixture(cart,int(net.cell_at(start).id)),"board horizontal before bend")
		var result:Dictionary = run_trip(cart)
		check(cart.global_position.distance_to(end)<0.2 and result.curve,"actual cart turns onto the independently laid vertical track")
		check(result.monotonic,"connecting corner conserves speed")
	# Three vertical cells; horizontal exit to the LEFT of the middle. Both build orders.
	for reverse:bool in [false,true]:
		net.clear_tracks()
		var start:Vector2 = o-Vector2(72,0)
		var end:Vector2 = o+Vector2(0,24)
		ready_cart(cart,start,end+Vector2(0,100))
		var h:PackedVector2Array = PackedVector2Array([start,o-Vector2(24,0)])
		var v:PackedVector2Array = PackedVector2Array([o-Vector2(0,24),end])
		build_grid(cart,v if reverse else h)
		build_grid(cart,h if reverse else v)
		var middle:int = int(net.cell_at(o).id)
		check(net.cell_at(o).mask==10 and net.physical_neighbors(middle).size()==2,"three-cell vertical rail keeps its original single straight art")
		check(net.neighbors(middle).size()==3,"side entry is allowed without drawing a second rail on the middle block")
		check(board_fixture(cart,int(net.cell_at(start).id)),"board left horizontal route")
		var completed:int = cart.completed_routes
		var result:Dictionary = run_trip(cart)
		check(cart.global_position.distance_to(end)<0.2,"horizontal exit transfers into middle then follows vertical rail")
		check(cart.completed_routes==completed+1 and result.monotonic,"side transfer never ends trip or resets speed")
		ready_cart(cart,o-Vector2(0,24),start)
		check(board_fixture(cart,int(net.cell_at(o-Vector2(0,24)).id)),"board vertical head toward a side target")
		run_trip(cart)
		check(cart.global_position.distance_to(end)<0.2,"already on vertical: continue current rail rather than prematurely turn to side target")
		var ghost:Node2D = cart.RAILS.new()
		ghost.set_multiplayer_authority(2)
		world.add_child(ghost)
		ghost._receive_state(100,net.network_state())
		check(ghost.render_cells()==net.render_cells() and ghost.neighbors(middle).size()==3,"network snapshot preserves separate appearance and side-entry connectivity")
		ghost.queue_free()
	# Literal single horizontal cell next to the middle of the three-cell vertical.
	net.clear_tracks()
	ready_cart(cart,o-Vector2(24,0),o+Vector2(0,100))
	var single:int = net._node(net.world_to_cell(cart.global_position),false,true)
	net.nodes[single].draw_mask = 5
	build_grid(cart,PackedVector2Array([o-Vector2(0,24),o+Vector2(0,24)]))
	check(net.nodes.size()==4 and net.render_cells().size()==4,"literal user example has exactly four rail cells")
	check(board_fixture(cart,single),"single horizontal block can board through its connected exit")
	run_trip(cart)
	check(cart.global_position.distance_to(o+Vector2(0,24))<0.2,"single horizontal block transfers into the three-cell vertical")
	await check_ground_render(cart)
	print("RAIL SIDE ENTRY CONTRACTS: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)

func check_ground_render(cart:Node2D) -> void:
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(64,64)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.world_2d=World2D.new()
	root.add_child(viewport)
	var stage:=Node2D.new()
	stage.z_index=world.z_index
	viewport.add_child(stage)
	var ground:=Polygon2D.new()
	ground.polygon=PackedVector2Array([Vector2.ZERO,Vector2(64,0),Vector2(64,64),Vector2(0,64)])
	ground.color=Color.BLACK
	ground.z_as_relative=false
	ground.z_index=-5
	stage.add_child(ground)
	var rail:Node2D=cart.RAILS.new()
	stage.add_child(rail)
	var a:int=rail._node(Vector2i(1,1),false,true)
	var b:int=rail._node(Vector2i(2,1),false,true)
	rail._connect(a,b)
	rail._publish()
	rail.set_preview(1,PackedVector2Array([Vector2(24,48),Vector2(48,48)]))
	await RenderingServer.frame_post_draw
	var image:Image=viewport.get_texture().get_image()
	var visible_pixels:int=0
	for y:int in range(12,60):
		for x:int in range(12,36):
			if image.get_pixel(x,y)!=Color.BLACK: visible_pixels+=1
	check(visible_pixels>40 and rail.last_draw_cell_count==4,"GPU renders committed rails and preview above floor")
	for layer:int in [-1,0,1]:
		var entity:=Polygon2D.new()
		entity.polygon=PackedVector2Array([Vector2(12,12),Vector2(36,12),Vector2(36,60),Vector2(12,60)])
		entity.color=Color.RED
		entity.z_index=layer
		stage.add_child(entity)
		await RenderingServer.frame_post_draw
		image=viewport.get_texture().get_image()
		var covered:bool=true
		for y:int in range(13,59):
			for x:int in range(13,35):
				covered=covered and image.get_pixel(x,y).is_equal_approx(Color.RED)
		check(covered,"GPU: world entity layer %d fully covers rail and preview"%layer)
		entity.queue_free()
		await process_frame
	viewport.queue_free()
