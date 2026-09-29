extends "res://tests/test_mc_minecart.gd"
func reset_cart(cart:Node2D,point:Vector2,goal:Vector2) -> void:
	cart.end_rush()
	cart.global_position=point
	cart.entry_needs_exit=false
	cart._boarding_lock=0
	cart.idle_left=999
	cart.set_player_control_peer(1)
	cart.set_player_control_aim_position(goal)
func run() -> void:
	var center:Vector2=await setup_world()
	create_timer(65).timeout.connect(func(): finish(2))
	var cart:Node2D=actor("矿车",center)
	var victim:Node2D=dummy(center+Vector2(240,240))
	await physics_frame
	await process_frame
	cart.Speed=110
	var net:Node2D=cart.rails
	var o:Vector2=net.cell_to_world(net.world_to_cell(center))
	var a:Vector2=o-Vector2(96,96)
	var b:Vector2=o+Vector2(96,-96)
	var c:Vector2=o+Vector2(96,96)
	var d:Vector2=o+Vector2(-96,96)
	reset_cart(cart,a,c)
	build_grid(cart,PackedVector2Array([a,b,c]))
	build_grid(cart,PackedVector2Array([c,d,a]))
	check(net.loop_nodes(int(net.cell_at(a).id)).size()==32,"two L builds form one physical closed loop")
	for corner:Vector2 in [a,b,c,d]:
		check(net.cell_at(corner).port and net.find_port(corner)!=0,"closed-loop corner is a boardable entrance")
	check(not net.cell_at((a+b)*0.5).port,"straight loop cells do not become arbitrary entrances")
	check(board_fixture(cart,int(net.cell_at(a).id)),"cart boards a closed loop corner")
	var distance:float=0
	var previous:Vector2=cart.global_position
	var saw_first:bool=false
	var previous_speed:float=cart.drive_speed
	for i:int in range(2500):
		if cart.rush_phase!=2: break
		previous_speed=cart.drive_speed
		cart.tick_physics(0,0.01)
		distance+=previous.distance_to(cart.global_position)
		previous=cart.global_position
		if cart.laps_completed==1:
			saw_first=true
	check(saw_first and cart.laps_completed==2,"loop runs exactly two laps, not one or forever")
	check(distance>1400 and distance<1600,"actual body travels two rounded loop perimeters")
	check(cart.rush_phase==3 and cart.drive_speed>=previous_speed,"loop ejects with exit speed retained")
	check(cart.rush_direction.dot((a-o).normalized())>=0.25,"loop ejection points outward from the loop")
	check(cart.has_momentum_attack() and not cart.get_debug_attack_regions().is_empty(),"ejected cart retains rail collision damage and threat display")
	var exit_speed:float=cart.drive_speed
	var from:Vector2=cart.global_position
	cart.move(0,0.05)
	check(cart.global_position.distance_to(from)>exit_speed*0.04,"ejection produces real high-speed body motion")
	check(cart.drive_speed<exit_speed and cart.drive_speed>exit_speed-20,"coast speed decays gradually rather than resetting")
	var frozen:float=cart.drive_speed
	game.now_stop_state=true
	cart.tick_physics(0,0.2)
	check(cart.drive_speed==frozen,"pause freezes coasting speed")
	game.now_stop_state=false
	var anchor:int=net.cell_at(a).id
	var reverse_edge:int=0
	for link:Variant in net.physical_neighbors(anchor):
		if int(link)!=cart._loop_first_edge: reverse_edge=int(link)
	reset_cart(cart,a,c)
	check(cart._begin_trip(anchor,reverse_edge),"closed loop can be entered in the opposite direction")
	run_trip(cart,2000)
	check(cart.laps_completed==2 and cart.rush_phase==3,"reverse traversal also ejects after exactly two laps")
	var ghost:Node2D=cart.RAILS.new()
	ghost.set_multiplayer_authority(2)
	world.add_child(ghost)
	ghost._receive_state(100,net.network_state())
	check(ghost.loop_nodes(anchor).size()==32 and ghost.nodes[anchor].port,"snapshot rebuilds closed-loop membership and corner entrance")
	ghost.queue_free()
	# Clear loop, independently verify ordinary endpoint release.
	net.clear_tracks()
	var left:Vector2=o-Vector2(192,0)
	var right:Vector2=o
	reset_cart(cart,left,right)
	build_grid(cart,PackedVector2Array([left,right]))
	check(board_fixture(cart,int(net.cell_at(left).id)),"board open rail")
	cart.drive_speed=500
	run_trip(cart)
	check(cart.rush_phase==3 and cart.global_position.distance_to(right)<0.2,"normal endpoint starts coasting at the endpoint")
	check(cart.drive_speed>500 and absf(cart.rush_direction.dot(Vector2.RIGHT))<0.66,"normal exit preserves speed but randomly changes heading")
	# Collision damage, sound path, knockback and cooldown are shared with on-rail hits.
	victim.global_position=cart.global_position+Vector2(24,0)
	await physics_frame
	var hp:float=victim.health
	check(cart.hit_enemy(victim,cart.global_position) and victim.health<hp,"coasting impact actually damages a victim")
	check(not cart.hit_enemy(victim,cart.global_position),"on/off-track impact shares the per-victim cooldown")
	victim.global_position=o+Vector2(240,240)
	var retained:float=cart.drive_speed
	cart.entry_needs_exit=false
	cart._boarding_lock=0
	cart.global_position=left
	check(board_fixture(cart,int(net.cell_at(left).id)),"can re-enter while still coasting")
	check(cart.drive_speed==retained,"next entry inherits remaining speed, not start speed")
	cart.end_rush(true)
	cart.entry_needs_exit=true
	cart.global_position=o+Vector2(0,144)
	cart.rush_direction=Vector2.RIGHT
	cart.direction=Vector2.RIGHT
	cart.drive_speed=cart.normal_travel_speed()+2
	cart.move(0,0.05)
	check(cart.rush_phase==0 and is_equal_approx(cart.drive_speed,cart.normal_travel_speed()),"decay stops at actual ordinary movement speed")
	check(not cart.has_momentum_attack() and cart.get_debug_attack_regions().is_empty(),"bonus collision attack ends at ordinary speed")
	retained=cart.drive_speed
	cart.global_position=left
	cart.entry_needs_exit=false
	cart._boarding_lock=0
	check(board_fixture(cart,int(net.cell_at(left).id)) and cart.drive_speed==retained,"fully decayed reentry inherits ordinary speed too")
	cart.drive_speed=800
	cart.end_rush(true)
	var snapshot:Dictionary=cart.visual_state()
	cart.accept_visual(snapshot)
	check(cart.rush_phase==3 and cart.drive_speed==800,"visual snapshot preserves coasting phase and speed")
	cart.dizziness=true
	cart.step_mob(0.01)
	check(cart.rush_phase==0 and cart.drive_speed==0,"stun safely cancels coasting")
	cart.dizziness=false
	# Real high-speed approach into a different entrance, not a direct board_port shortcut.
	var new_entry:Vector2=o+Vector2(48,0)
	build_grid(cart,PackedVector2Array([new_entry,new_entry+Vector2(96,0)]))
	reset_cart(cart,left,new_entry+Vector2(96,0))
	board_fixture(cart,int(net.cell_at(left).id))
	cart.drive_speed=600
	run_trip(cart)
	var released:float=cart.drive_speed
	# Isolate entry detection from the randomized release direction in this fixture.
	cart.rush_direction=Vector2.RIGHT
	cart.direction=Vector2.RIGHT
	var boards:int=cart.boarded_routes
	for i:int in range(100):
		if cart.rush_phase!=3: break
		cart.move(0,0.005)
	check(cart.rush_phase==2 and cart.boarded_routes==boards+1,"physical coasting catches another entrance without the old 0.9-second lock")
	check(cart.drive_speed>released*0.9 and cart.drive_speed<=released,"automatic reentry keeps decayed release speed")
	cart.end_rush(true)
	cart.drive_speed=80
	cart._hit_until.clear()
	victim.global_position=cart.global_position+Vector2(24,0)
	await physics_frame
	check(cart.has_momentum_attack() and cart.hit_enemy(victim,cart.global_position),"off-track impact remains active below 90 until ordinary speed 66")
	var headings:Dictionary={}
	for i:int in range(12):
		cart.rush_phase=2
		cart.rush_direction=Vector2.RIGHT
		cart.drive_speed=730
		cart.global_position=o
		cart.end_rush(true)
		headings[roundi(cart.direction.angle()*1000)]=true
		check(absf(cart.direction.dot(Vector2.RIGHT))<0.66,"random release does not continue or reverse along the old track")
		check(is_equal_approx(cart.drive_speed,730) and cart.velocity.is_equal_approx(cart.direction*730),"random heading is applied to actual velocity without losing speed")
	check(headings.size()>3,"repeated exits produce varied random directions")
	cart.health=0
	cart.step_mob(0.01)
	check(cart.rush_phase==0 and cart.drive_speed==0,"death cancels inertia and impact state")
	var source:String=cart.get_script().source_code
	check(not source.contains("side_status_set_permanent") and not source.contains("Lay attack"),"character-attached construction countdown/description is removed")
	print("RAIL COAST CONTRACTS: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
