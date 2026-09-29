extends "res://tests/test_mc_minecart.gd"
func approach(cart:Node2D,position:Vector2,motion:Vector2) -> void:
	cart.end_rush()
	cart.global_position=position
	cart.velocity=motion
	cart.direction=motion.normalized() if not motion.is_zero_approx() else Vector2.RIGHT
	cart.entry_needs_exit=false
	cart._boarding_lock=0
	cart.idle_left=999
	cart.set_player_control_peer(0)
func run() -> void:
	var center:Vector2=await setup_world()
	create_timer(65).timeout.connect(func(): finish(2))
	var cart:Node2D=actor("矿车",center)
	var target:Node2D=dummy(center+Vector2(240,240))
	await physics_frame
	await process_frame
	var net:Node2D=cart.rails
	var o:Vector2=net.cell_to_world(net.world_to_cell(center))
	# Screenshot cases: two parallel vertical ends, and two parallel horizontal ends.
	for horizontal:bool in [false,true]:
		for reverse:bool in [false,true]:
			net.clear_tracks()
			var axis:Vector2=Vector2.RIGHT if horizontal else Vector2.DOWN
			var side:Vector2=Vector2.DOWN if horizontal else Vector2.RIGHT
			var a:Vector2=o
			var b:Vector2=o+side*24
			approach(cart,a,axis*120)
			var first:PackedVector2Array=PackedVector2Array([a,a+axis*48])
			var second:PackedVector2Array=PackedVector2Array([b,b+axis*48])
			build_grid(cart,second if reverse else first)
			build_grid(cart,first if reverse else second)
			var id:int=net.cell_at(a).id
			var adjacent:int=net.cell_at(b).id
			var joined:bool=false
			for link:Variant in net.physical_neighbors(id):
				joined=joined or net.other_end(link,id)==adjacent
			check(joined,"parallel adjacent endpoints connect regardless of orientation/build order")
			check(net.is_elbow(id) and net.is_elbow(adjacent),"both endpoints visibly become connected bends, not straight dead ends")
			check(net.nodes.size()==6 and net.render_cells().size()==6,"connection does not add stacked or duplicate tiles")
			check(board_fixture(cart,id),"connected parallel pair can be boarded")
			run_trip(cart,2000)
			check(cart.laps_completed==2 and cart.rush_phase==3,"actual cart traverses the connected bends and completes two-loop exit")
	net.clear_tracks()
	var left:Vector2=o-Vector2(96,0)
	var right:Vector2=o+Vector2(96,0)
	approach(cart,left,Vector2.RIGHT*200)
	build_grid(cart,PackedVector2Array([left,right]))
	var head:int=net.cell_at(left).id
	var tail:int=net.cell_at(right).id
	for motion:Vector2 in [Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(1,1),Vector2.ZERO]:
		approach(cart,left-Vector2(12,0),motion*200)
		check(not cart.board_port(head),"left entrance rejects outward, sideways, diagonal and stationary motion")
	approach(cart,left+Vector2(8,0),Vector2.RIGHT*200)
	check(not cart.board_port(head),"approaching left entrance from the inside is rejected")
	approach(cart,left+Vector2(-12,12),Vector2.RIGHT*200)
	check(not cart.board_port(head),"parallel movement outside the rail width is not sucked onto rail")
	approach(cart,left-Vector2(12,0),Vector2.RIGHT*200)
	check(cart.board_port(head) and cart.rush_direction==Vector2.RIGHT,"left entrance accepts inward rightward movement")
	approach(cart,right+Vector2(12,0),Vector2.LEFT*200)
	check(cart.board_port(tail) and cart.rush_direction==Vector2.LEFT,"right entrance accepts inward leftward movement")
	approach(cart,left-Vector2(12,0),Vector2.DOWN*200)
	cart._check_rails(left+Vector2(-12,-16),cart.global_position)
	check(cart.rush_phase==0,"real side pass is not automatically boarded")
	approach(cart,left-Vector2(12,0),Vector2.RIGHT*200)
	cart._check_rails(left-Vector2(24,0),cart.global_position)
	check(cart.rush_phase==2,"real inward approach automatically boards")
	net.clear_tracks()
	var top:Vector2=o-Vector2(0,96)
	var bottom:Vector2=o+Vector2(0,96)
	approach(cart,top,Vector2.DOWN*200)
	build_grid(cart,PackedVector2Array([top,bottom]))
	approach(cart,top-Vector2(0,12),Vector2.DOWN*200)
	check(cart.board_port(net.cell_at(top).id),"top entrance accepts downward movement")
	approach(cart,bottom+Vector2(0,12),Vector2.UP*200)
	check(cart.board_port(net.cell_at(bottom).id),"bottom entrance accepts upward movement")
	approach(cart,top-Vector2(0,12),Vector2.UP*200)
	check(not cart.board_port(net.cell_at(top).id),"top entrance rejects outward upward movement")
	approach(cart,top,Vector2.DOWN*200)
	board_fixture(cart,net.cell_at(top).id)
	cart.drive_speed=720
	cart.end_rush(true)
	cart.Speed=110
	cart.global_position=o
	cart.rush_direction=Vector2.RIGHT
	cart.direction=Vector2.RIGHT
	cart.entry_needs_exit=true
	cart._exit_point=o
	cart.move(0,0.05)
	check(is_equal_approx(cart.drive_speed,702),"off-rail decay is doubled: 360 per second, 18 removed in 0.05s")
	check(cart.has_momentum_attack(),"faster decay still retains collision attacks above ordinary speed")
	print("RAIL ENTRY CONTRACTS: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
