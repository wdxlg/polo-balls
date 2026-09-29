extends "res://tests/test_mc_minecart.gd"
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(60.0).timeout.connect(func(): finish(2))
	var cart:Node2D = actor("矿车",center)
	var target:Node2D = dummy(center+Vector2(0,-192))
	await physics_frame
	await process_frame
	var net:Node2D = cart.rails
	var origin:Vector2 = net.cell_to_world(net.world_to_cell(center))
	var left:Vector2 = origin-Vector2(192,0)
	var right:Vector2 = origin+Vector2(192,0)
	cart.global_position = left
	cart.set_player_control_peer(1)
	var first:Dictionary = build_grid(cart,PackedVector2Array([left,right]))
	var crossing:PackedVector2Array = PackedVector2Array([origin-Vector2(0,144),origin+Vector2(0,144)])
	build_grid(cart,crossing)
	check(net.nodes.size()==29,"crossing keeps every nonoverlapping cell on BOTH sides")
	check(net.cell_at(origin).mask==10,"latest vertical cell replaces old horizontal shape")
	for n:Dictionary in net.nodes.values():
		check(net.physical_neighbors(n.id).size()<=2,"one rail per block, never a T or four-way overlay")
	var masks:Dictionary = net.render_cells()
	net.set_preview(1,crossing)
	check(net.render_cells()[net.world_to_cell(origin)].mask==10 and net.render_cells()[net.world_to_cell(origin)].powered==masks[net.world_to_cell(origin)].powered,"latest preview keeps vertical shape and inherited power")
	net.clear_preview(1)
	var count:int = net.nodes.size()
	build_grid(cart,crossing)
	check(net.nodes.size()==count,"repeat overlap never duplicates a block")
	cart._boarding_lock = 0.0
	cart.entry_needs_exit = false
	cart.set_player_control_aim_position(target.global_position)
	check(board_fixture(cart,int(first.nodes[0])),"board original rail")
	run_trip(cart)
	check(cart.global_position.distance_to(origin-Vector2(0,144))<0.2,"old horizontal now terminates into the replacing vertical rail")
	# A close port must not pull the preview endpoint into the neighboring row.
	cart.global_position = left+Vector2(0,24)
	var raw:PackedVector2Array = PackedVector2Array([left+Vector2(0,24),right+Vector2(0,24)])
	var prepared:PackedVector2Array = net.prepare_path(cart,raw)
	check(prepared==raw,"nearby old ports do not shorten or shift a new nonoverlapping row")
	var parallel:Dictionary = net.commit_path(cart,prepared)
	check(not parallel.is_empty() and parallel.cells.size()==17,"entire adjacent nonoverlapping row is laid")
	check(net.cell_at(left).mask==3,"adjacent parallel row endpoints now connect into bends")
	# Separate attacks whose endpoints touch by one block must create one continuous trip.
	net.clear_tracks()
	cart.global_position = left
	first = build_grid(cart,PackedVector2Array([left,origin]))
	var end:Vector2 = origin+Vector2(144,96)
	var second:Dictionary = build_grid(cart,PackedVector2Array([origin+Vector2(24,0),origin+Vector2(144,0),end]))
	check(not second.is_empty(),"second independent elbow is placed")
	check(net.neighbors(int(net.cell_at(origin).id)).size()==2,"old exit connects to adjacent new track")
	cart.entry_needs_exit = false
	cart._boarding_lock = 0.0
	cart.idle_left = 0.0
	cart.set_player_control_peer(0)
	var builds:int = cart.laid_routes
	cart.velocity=Vector2.RIGHT*120
	cart.step_mob(0.01)
	check(cart.rush_phase==2 and cart.laid_routes==builds,"boarding existing rails takes priority over construction cooldown")
	cart.idle_left = 999.0
	var trips:int = cart.completed_routes
	var result:Dictionary = run_trip(cart)
	check(cart.global_position.distance_to(end)<0.2,"cart follows old track then continues along the new elbow")
	check(cart.completed_routes==trips+1,"connected exit is one uninterrupted trip, not exit and reboard")
	check(result.monotonic and result.curve,"handoff preserves speed and curved turning")
	cart.global_position = end
	cart.entry_needs_exit = false
	cart._boarding_lock = 0.0
	check(board_fixture(cart,int(net.cell_at(end).id)),"joined route can be entered in reverse")
	run_trip(cart)
	check(cart.global_position.distance_to(left)<0.2,"reverse traversal also crosses the connected exit")
	var ghost:Node2D = cart.RAILS.new()
	ghost.set_multiplayer_authority(2)
	world.add_child(ghost)
	ghost._receive_state(100,net.network_state())
	check(ghost.render_cells()==net.render_cells(),"snapshot preserves the nonoverlapping joined layout")
	ghost.queue_free()
	print("RAIL CONTINUITY CONTRACTS: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
