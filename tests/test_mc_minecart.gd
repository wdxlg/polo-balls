extends "res://tests/test_mc_frontier.gd"
## User-reported failures: layering, visible turns, endpoint ping-pong, cell overlap and power priority.
func build_grid(cart:Node2D,points:PackedVector2Array) -> Dictionary:
	return cart.rails.commit_path(cart,cart.rails.prepare_path(cart,points))
func run_trip(cart:Node2D,limit:int = 1000) -> Dictionary:
	var views:Dictionary = {}
	var saw_curve:bool = false
	var peak:float = cart.drive_speed
	var previous:float = cart.drive_speed
	var monotonic:bool = true
	for i:int in range(limit):
		if cart.rush_phase != 2: break
		cart.tick_physics(0,0.01)
		if cart._curve_active:
			saw_curve = true
			views[cart._view_index] = true
		if cart.rush_phase == 2: monotonic = monotonic and cart.drive_speed+0.001 >= previous
		peak = maxf(peak,cart.drive_speed)
		previous = cart.drive_speed
	return {"curve":saw_curve,"views":views.size(),"peak":peak,"monotonic":monotonic}
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(70.0).timeout.connect(func(): finish(2))
	var cart:Node2D = actor("矿车",center)
	var target:Node2D = dummy(center+Vector2(192,0))
	await physics_frame
	await process_frame
	var net:Node2D = cart.rails
	var origin:Vector2 = net.cell_to_world(net.world_to_cell(center))
	cart.global_position = origin
	cart.visual_mob()
	check(not cart.image.z_as_relative and cart.image.z_index == net.BODY_Z and cart.image.z_index > net.z_index,"actual cart Image is explicitly above committed and preview rail")
	check(net.z_index == -4 and cart.image.z_index == 5,"ground/body layers have a fixed unambiguous ordering")
	check(cart.rush_interval == 5.0 and cart.Attack_Cooling == 5.0 and not cart.start_charge(),"five-second construction cooldown and scene configuration agree")
	check(cart.idle_left > 4.8 and cart.idle_left <= 5.0,"first construction starts with the shortened cooldown")
	cart.set_player_control_peer(1)
	cart.set_player_control_aim_position(origin+Vector2(192,144))
	cart.idle_left = cart.rush_interval
	cart.step_mob(4.9)
	check(cart.idle_left > 0.0 and not cart.start_charge(),"construction cannot start before five seconds")
	cart.step_mob(0.11)
	check(cart.start_charge() and is_equal_approx(cart.idle_left,5.0),"construction is available at five seconds and resets to five")
	check(is_equal_approx(cart.charge_left,1.0),"one-second construction windup is unchanged")
	cart.step_mob(0.4)
	check(is_equal_approx(cart.idle_left,4.6) and is_equal_approx(cart.charge_left,0.6),"cooldown keeps ticking during windup without an extra wait")
	game.now_stop_state = true
	cart.step_mob(2.0)
	check(is_equal_approx(cart.idle_left,4.6),"pause cannot consume the shortened cooldown")
	game.now_stop_state = false
	cart.end_rush()
	check(not cart.player_control_action_hold_repeat_allowed(1),"holding the turn key does not become accidental braking")
	# Aligned enemies must still produce a visible automatic elbow when there is room.
	cart.set_player_control_peer(0)
	cart.idle_left = 0.0
	target.global_position = origin+Vector2(192,0)
	check(cart.start_charge() and cart.turn_used and cart.planning_points.size()==3,"AI visibly uses its one ninety-degree bend even for an aligned enemy")
	check(net.nodes.is_empty() and not net.render_cells().is_empty(),"planning draws a preview without placing gameplay rail")
	cart.end_rush()
	check(net.render_cells().is_empty(),"cancelled construction removes its preview")
	cart.set_player_control_peer(1)
	cart.set_player_control_aim_position(origin+Vector2(192,144))
	cart.idle_left = 0.0
	check(cart.start_charge(),"manual construction can still begin")
	if not cart.turn_used: check(cart.request_turn(),"manual turn consumes the one opportunity")
	check(cart.planning_points.size()==3 and not cart.request_turn(),"no construction can gain a second corner")
	for point:Vector2 in cart.planning_points:
		check(point == net.cell_to_world(net.world_to_cell(point)),"every planning control point is grid-aligned")
	cart.end_rush()
	# Exact same route and partially overlapping routes are canonical cell merges.
	var left:Vector2 = origin-Vector2(240,0)
	var right:Vector2 = origin+Vector2(240,0)
	var long_path:PackedVector2Array = PackedVector2Array([left,right])
	var first:Dictionary = build_grid(cart,long_path)
	check(not first.is_empty() and net.nodes.size()==21 and net.rails.size()==20,"480 world units occupy exactly twenty-one shared rail cells")
	check(net._cell_ids.size()==net.nodes.size() and net.render_cells().size()==net.nodes.size(),"storage and render list both have exactly one entry per block")
	check(net.cell_at(origin).powered,"the central cell is powered")
	check(not net.cell_at(left).powered and not net.cell_at(right).powered,"outer cells are ordinary rail")
	var counts:Vector2i = Vector2i(net.nodes.size(),net.rails.size())
	build_grid(cart,long_path)
	check(Vector2i(net.nodes.size(),net.rails.size())==counts,"identical construction adds no duplicate cells or links")
	build_grid(cart,PackedVector2Array([left,origin]))
	check(net.nodes.size()==21 and net.cell_at(origin).powered,"new ordinary rail cannot overwrite an existing powered cell")
	check(net.render_cells()[net.world_to_cell(origin)].powered,"powered priority is also used by the actual drawing descriptor")
	var cross_path:PackedVector2Array = PackedVector2Array([origin-Vector2(0,240),origin+Vector2(0,240)])
	build_grid(cart,cross_path)
	check(net.nodes.size()==41,"crossing routes share the center block instead of stacking two rails")
	var intersection:Dictionary = net.cell_at(origin)
	check(intersection.mask==10 and net.physical_neighbors(int(intersection.id)).size()==2,"latest vertical rail replaces old horizontal direction without stacking a crossing")
	check(intersection.powered,"junction merging preserves power priority")
	net.set_preview(101,long_path)
	net.set_preview(102,cross_path)
	check(net.render_cells().size()==41,"multiple overlapping previews still draw only one rail per occupied cell")
	check(net.render_cells()[net.world_to_cell(origin)].powered,"preview merging cannot visually downgrade a powered cell")
	net.clear_preview(101); net.clear_preview(102)
	check(net.render_cells().size()==41,"clearing previews leaves permanent rail untouched")
	var empty:Array[Node2D] = []
	net.tick_rails(86400.0,empty)
	check(net.nodes.size()==41,"time and an empty cart list do not erase the grid")
	net.clear_tracks()
	build_grid(cart,PackedVector2Array([left,origin]))
	check(not net.cell_at(origin).powered,"short-path endpoint begins ordinary")
	build_grid(cart,long_path)
	check(net.cell_at(origin).powered,"a later powered placement upgrades ordinary rail")
	# A powered bend keeps both its bend geometry and its higher-priority power state.
	net.clear_tracks()
	var a:Vector2 = origin-Vector2(144,72)
	var b:Vector2 = a+Vector2(192,0)
	var c:Vector2 = b+Vector2(0,144)
	cart.global_position = a
	var curved:Dictionary = build_grid(cart,PackedVector2Array([a,b,c]))
	check(not curved.is_empty() and net.nodes.size()==15,"L route rasterizes without duplicated corner blocks")
	var corner:Dictionary = net.cell_at(b)
	check(corner.mask==6 and corner.powered,"powered middle wins even at an actual bend cell")
	check(net.is_powered_at(0,b),"powered bend affects gameplay, not only the artwork")
	cart._boarding_lock = 0.0
	cart.entry_needs_exit = false
	check(board_fixture(cart,int(curved.nodes[0])),"a fresh approach can enter the old head")
	var result:Dictionary = run_trip(cart)
	check(result.curve and result.views >= 3,"turning follows a real arc with several native model headings")
	check(cart.turns_taken>0 and cart.global_position.distance_to(c)<0.2,"the actual curved path reaches the far endpoint")
	check(result.monotonic and result.peak>350,"corner traversal preserves accumulated speed and powered acceleration")
	check(cart.entry_needs_exit and cart.departure_count==1,"arrival requires a physical exit before another boarding")
	check(absf(cart.direction.dot(Vector2.DOWN))<0.66,"normal exit randomly releases sideways while preserving inertia")
	var trips:int = cart.boarded_routes
	var completed:int = cart.completed_routes
	var endpoint_position:Vector2 = cart.global_position
	# A manually stationary fixture stays on the endpoint for four seconds: no hidden reverse.
	for i:int in range(40): cart.tick_physics(0,0.1)
	check(cart.rush_phase==0 and cart.boarded_routes==trips and cart.completed_routes==completed,"standing at a tail never loops back after a timer expires")
	check(cart.global_position.distance_to(endpoint_position)>10,"endpoint release physically coasts instead of parking or automatically reversing")
	check(not board_fixture(cart,int(curved.nodes[-1])),"direct boarding also respects the leave-and-reenter latch")
	cart.global_position = c+Vector2(0,72)
	cart._check_rails(cart.global_position,cart.global_position)
	check(not cart.entry_needs_exit,"physically leaving all endpoint areas rearms entry")
	var outside:Vector2 = cart.global_position
	cart.global_position = c+Vector2(0,8)
	cart._check_rails(outside,cart.global_position)
	check(cart.rush_phase==2 and cart.boarded_routes==trips+1,"a genuinely new approach may reuse the tail in reverse")
	run_trip(cart)
	check(cart.global_position.distance_to(a)<0.2,"intentional reentry still reaches the other end")
	# Normal AI movement resumes with the chosen random heading, not with the rail vector.
	cart.set_player_control_peer(0)
	cart.idle_left = 8.0
	var chosen:Vector2 = cart.direction
	var from:Vector2 = cart.global_position
	cart.move(110,0.05)
	var motion:Vector2 = cart.global_position-from
	check(motion.length()>0.1 and motion.normalized().dot(chosen)>0.8,"after arrival the existing normal movement logic uses the random departure")
	cart.set_player_control_peer(1)
	# Persistent cells, authority snapshot and duplicate-grid validation.
	var snapshot:Dictionary = net.network_state()
	var ghost:Node2D = cart.RAILS.new()
	ghost.set_multiplayer_authority(2)
	world.add_child(ghost)
	ghost._receive_state(20,snapshot)
	check(ghost.nodes.size()==net.nodes.size() and ghost.cell_at(b).powered,"snapshots preserve unique cells, geometry and powered priority")
	var bad:Dictionary = snapshot.duplicate(true)
	var duplicate:Dictionary = bad.nodes[0].duplicate()
	duplicate.id = 999999
	bad.nodes.append(duplicate)
	ghost._receive_state(21,bad)
	check(ghost.revision==20,"duplicate block coordinates are rejected instead of stacking on clients")
	ghost._receive_state(19,{"schema":2,"nodes":[],"edges":[]})
	check(ghost.nodes.size()==net.nodes.size(),"stale snapshot cannot erase the existing grid")
	ghost.queue_free()
	var owner:Node2D = actor("矿车",origin+Vector2(240,240))
	await process_frame
	var cell_count:int = net.nodes.size()
	owner.health = 0
	await physics_frame
	await process_frame
	check(net.nodes.size()==cell_count,"owner death still does not remove permanent rail")
	# Cell occupancy and complete bodies are both checked against real terrain.
	net.clear_tracks()
	cart.global_position = origin
	var barrier:StaticBody2D = wall(origin+Vector2(144,0),Vector2(24,144))
	await physics_frame
	await process_frame
	var clipped:PackedVector2Array = net.prepare_path(cart,PackedVector2Array([origin,origin+Vector2(288,0)]))
	check(clipped.size()==2 and clipped[-1].x <= origin.x+120,"grid construction stops before occupied terrain cells")
	var placed:Dictionary = net.commit_path(cart,clipped)
	check(not placed.is_empty() and net.cell_at(barrier.global_position).is_empty(),"no rail is generated inside the wall block")
	barrier.queue_free()
	await process_frame
	cart.global_position = origin
	cart.entry_needs_exit = false
	cart._boarding_lock = 0.0
	board_fixture(cart,int(placed.nodes[0]))
	var speed_before:float = cart.drive_speed
	game.now_stop_state = true
	cart.tick_physics(0,3.0)
	check(cart.drive_speed==speed_before,"combat pause freezes grid travel")
	game.now_stop_state = false
	cart.dizziness = true
	cart.tick_physics(0,0.1)
	check(cart.rush_phase==0 and cart.collision_mask==3 and not net.nodes.is_empty(),"control interruption restores collisions but leaves permanent cells")
	cart.dizziness = false
	check(not cart.image.z_as_relative and cart.image.z_index>net.z_index,"body layer remains correct after movement, turning and interruption")
	print("RAIL GRID CONTRACTS: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)

func board_fixture(cart:Node2D,port:int) -> bool:
	var link:int=cart.rails.choose_edge(port,{},cart._aim_point(),cart.direction)
	if link==0: return false
	var inward:Vector2=cart.rails.node_point(port).direction_to(cart.rails.node_point(cart.rails.other_end(link,port)))
	return cart.board_port(port,inward)
