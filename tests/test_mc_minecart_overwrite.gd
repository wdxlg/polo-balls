extends "res://tests/test_mc_minecart.gd"
func run() -> void:
	var center:Vector2=await setup_world()
	create_timer(60).timeout.connect(func(): finish(2))
	var cart:Node2D=actor("矿车",center)
	var target:Node2D=dummy(center+Vector2(300,300))
	await physics_frame
	await process_frame
	var net:Node2D=cart.rails
	var o:Vector2=net.cell_to_world(net.world_to_cell(center))
	var left:Vector2=o-Vector2(144,0)
	var right:Vector2=o+Vector2(144,0)
	var bottom:Vector2=o+Vector2(0,216)
	cart.global_position=left
	cart.set_player_control_peer(1)
	cart.set_player_control_aim_position(bottom)
	var h:PackedVector2Array=PackedVector2Array([left,right])
	var v:PackedVector2Array=PackedVector2Array([o-Vector2(0,24),bottom])
	var first:Dictionary=build_grid(cart,h)
	check(net.cell_at(o).mask==5 and net.cell_at(o).powered,"old horizontal center is powered")
	check(not net._plan_cells(v)[net.world_to_cell(o)].powered,"replacement would normally place an ordinary vertical cell here")
	net.set_preview(1,v)
	check(net.render_cells()[net.world_to_cell(o)].mask==10,"latest preview covers the old horizontal direction")
	check(net.render_cells()[net.world_to_cell(o)].powered,"preview inherits old powered cell")
	check(net.cell_at(o).mask==5,"preview alone does not change gameplay")
	net.clear_preview(1)
	check(net.render_cells()[net.world_to_cell(o)].mask==5,"cancelled preview reveals committed old rail")
	cart.entry_needs_exit=false
	cart._boarding_lock=0
	cart.idle_left=999
	check(board_fixture(cart,int(first.nodes[0])),"cart starts on old rail before replacement")
	for i:int in range(8): cart.tick_physics(0,0.01)
	var active_edge:int=cart.track_id
	var prior_speed:float=cart.drive_speed
	var replacement:Dictionary=build_grid(cart,v)
	check(not replacement.is_empty(),"new vertical overwrites occupied center and lays all empty cells")
	check(net.nodes.size()==23 and net.render_cells().size()==23,"overlap still has exactly one node and one drawn tile")
	check(net.cell_at(o).mask==10 and net.cell_at(o).powered,"new vertical shape inherits old power permanently")
	check(not net.edge(active_edge).is_empty() and cart.drive_speed==prior_speed,"replacement preserves in-flight edge identity and speed")
	var middle:int=net.cell_at(o).id
	check(net.physical_neighbors(middle).size()==2 and net.neighbors(middle).size()==4,"old horizontal is cut into exits, not retained as a four-way drawn rail")
	var result:Dictionary=run_trip(cart)
	check(cart.global_position.distance_to(bottom)<0.2,"approaching cart transfers from cut old rail into new vertical")
	check(result.monotonic,"replacement handoff does not reset accumulated speed")
	# Newest horizontal wins back, without deleting the unoverlapped vertical sections.
	cart.global_position=left
	var before:int=net.nodes.size()
	build_grid(cart,h)
	check(net.cell_at(o).mask==5 and net.cell_at(o).powered,"next horizontal replaces vertical and still retains power")
	check(net.nodes.size()==before and not net.cell_at(bottom).is_empty(),"replacement never deletes old nonoverlapped cells")
	var counts:Vector2i=Vector2i(net.nodes.size(),net.rails.size())
	build_grid(cart,h)
	check(Vector2i(net.nodes.size(),net.rails.size())==counts,"repeating a placement does not duplicate transfer or physical edges")
	# Replace straight with a real elbow; ordinary new elbow inherits old powered center.
	var elbow:PackedVector2Array=PackedVector2Array([left,o,o+Vector2(0,144)])
	build_grid(cart,elbow)
	check(net.cell_at(o).mask==6 and net.cell_at(o).powered,"new elbow replaces straight shape while keeping power")
	for n:Dictionary in net.nodes.values():
		check(net.physical_neighbors(n.id).size()<=2,"only one physical rail shape remains in every cell")
	var ghost:Node2D=cart.RAILS.new()
	ghost.set_multiplayer_authority(2)
	world.add_child(ghost)
	ghost._receive_state(100,net.network_state())
	check(ghost.render_cells()==net.render_cells(),"snapshot reproduces latest shape and inherited power")
	for n:Dictionary in net.nodes.values():
		check(ghost.physical_neighbors(n.id).size()==net.physical_neighbors(n.id).size(),"snapshot reproduces cut old connections versus new physical rail")
	ghost.queue_free()
	print("RAIL OVERWRITE CONTRACTS: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
