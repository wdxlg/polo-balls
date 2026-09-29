extends "res://tests/test_mc_frontier.gd"
## Normal idle movement is enabled: verifies random departure, not a parked ping-pong fixture.
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(65.0).timeout.connect(func(): finish(2))
	var cart:Node2D = spawn("res://scenes/characters/我的世界/矿车.tscn",center+Vector2(-130,-100))
	cart.Can_Attack = true
	cart.Can_Skill = true
	cart.default_properties["Can_Attack"] = true
	cart.direction = Vector2.RIGHT
	var target:Node2D = dummy(center+Vector2(110,90))
	var first_attack:float = -1.0
	var saw_preview:bool = false
	var saw_curve_plan:bool = false
	var powered:bool = false
	var peak:float = 0.0
	var last_heading:Vector2 = Vector2.RIGHT
	var departures:int = 0
	var coasting_departures:int = 0
	var saw_idle_motion:bool = false
	var unique_ok:bool = true
	var layers_ok:bool = true
	var initial_cells:Array[Vector2i] = []
	var persist_ok:bool = true
	var elapsed:float = 0.0
	while elapsed < 24.0:
		await create_timer(0.04).timeout
		elapsed += 0.04
		if cart.rush_phase == 1:
			saw_preview = true
			saw_curve_plan = saw_curve_plan or cart.planning_points.size()==3
			if first_attack < 0: first_attack = cart.clock
		if cart.departure_count > departures:
			if cart.rush_phase==3 and cart.drive_speed>0: coasting_departures += 1
			departures = cart.departure_count
		if cart.rush_phase == 2:
			last_heading = cart.rush_direction
			powered = powered or cart.rail_powered
			peak = maxf(peak,cart.drive_speed)
		elif cart.rush_phase == 0 and departures > 0:
			saw_idle_motion = saw_idle_motion or cart.velocity.length()>1.0
		if is_instance_valid(cart.rails):
			unique_ok = unique_ok and cart.rails.nodes.size()==cart.rails._cell_ids.size()
			layers_ok = layers_ok and not cart.image.z_as_relative and cart.image.z_index>cart.rails.z_index
			if initial_cells.is_empty() and not cart.rails.nodes.is_empty():
				for n:Dictionary in cart.rails.nodes.values(): initial_cells.append(n.cell)
			for cell:Vector2i in initial_cells: persist_ok = persist_ok and cart.rails._cell_ids.has(cell)
	check(first_attack>=4.95 and first_attack<=5.5,"normal-moving cart uses the shortened five-second construction clock")
	check(saw_preview and saw_curve_plan and cart.turns_taken>0,"automatic battles visibly plan and execute at least one real turn")
	check(powered and peak>350,"powered grid cells accelerate actual travel")
	check(target.health<10000,"real grid movement can damage the target")
	check(departures>0 and coasting_departures>0,"completed trips retain speed and enter inertial coasting")
	check(saw_idle_motion,"normal movement resumes after leaving the track")
	check(unique_ok,"real repeated construction keeps one storage cell per block")
	check(layers_ok,"body stays above track during planning, rush and idle movement")
	check(persist_ok and not initial_cells.is_empty(),"later construction never deletes earlier grid cells")
	check(cart.cart_fx.particles.size()<=56 and cart.cart_fx.trail.size()<=14,"effects remain bounded")
	print("RAIL GRID LIVE: first_attack=",first_attack," damage=",10000-target.health," peak=",peak," turns=",cart.turns_taken," departures=",departures," coasting=",coasting_departures," builds=",cart.laid_routes," boards=",cart.boarded_routes," cells=",cart.rails.nodes.size())
	finish(0 if failures==0 else 1)
