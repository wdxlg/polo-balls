extends "res://tests/test_character_motion.gd"
func box(offset:Vector2,manual:bool=false) -> Node2D:
	var unit:Node2D=spawn("",offset,"Team0" if manual else "Team1")
	unit.set_player_control_peer(1 if manual else 0)
	unit.get_body_motion().set_physics_process(false)
	unit.Speed=100 if manual else 58
	var shape:=RectangleShape2D.new();shape.size=Vector2(16,16)
	unit.collision_shape_2d.shape=shape
	unit.collision_shape_2d.position=Vector2.ZERO
	unit.collision_shape_2d.global_scale=Vector2.ONE
	return unit
func run() -> void:
	game=root.get_node("Game");saved=game.Game_Settings.duplicate(true)
	game._settings_storage_path=OS.get_environment("TEMP").path_join("pressure_settings.json")
	game.Game_Settings.Training_Mode=false;game.Game_Settings.Ball_Can_Move=true;game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(90,true,false,true).timeout.connect(func():finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT);root.add_child(world)
	world.now_choose_map="Map50x50";world.refresh_map_presentation();world.control.hide()
	await create_timer(0.5).timeout
	world.set_physics_process(false);center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	for count:int in [10,30]:
		for angle:float in [0.0,PI*0.5]:await enclosure(count,angle)
	await barriers()
	print("CHARACTER_PRESSURE checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
func enclosure(count:int,angle:float) -> void:
	await clear_units()
	var player:Node2D=box(Vector2.ZERO,true)
	var units:Array[Node2D]=[player]
	var offsets:Array[Vector2]=[]
	for y:int in range(-2,3):
		for x:int in range(-2,4):
			if x!=0 or y!=0:offsets.append(Vector2(x,y)*16.05)
	offsets.sort_custom(func(a:Vector2,b:Vector2):return a.length_squared()<b.length_squared())
	offsets.append(Vector2(4,0)*16.05)
	for i:int in range(count):units.append(box(offsets[i].rotated(angle)))
	var wish:Vector2=Vector2.RIGHT.rotated(angle)
	var max_budget:float=0.0
	var max_overlap:float=0.0
	var order:Array[Node2D]=units.duplicate()
	if angle>0.1:order.reverse()
	for frame:int in range(300):
		await physics_frame
		player.set_player_control_direction(wish);player.direction=wish
		for unit:Node2D in order:
			if unit!=player:unit.direction=unit.global_position.direction_to(player.global_position)
			unit.move(unit.Speed,1.0/60.0)
		for unit:Node2D in order:
			unit.get_body_motion().separate_overlaps()
			max_budget=maxf(max_budget,unit.get_body_motion()._correction_used)
		for i:int in range(units.size()):
			for j:int in range(i+1,units.size()):
				var gap:Vector2=(units[i].global_position-units[j].global_position).abs()
				max_overlap=maxf(max_overlap,maxf(0.0,minf(16.0-gap.x,16.0-gap.y)))
	var forward:float=(player.global_position-center).dot(wish)
	check(forward>40,"sustained manual input makes headway through a chasing enclosure")
	check(max_budget<=3.001,"pressure and overlap correction share one bounded displacement budget")
	check(max_overlap<0.15,"pressure does not phase bodies through each other")
	check(not player.dizziness and player.Can_Attack,"pressure never locks movement or attacks")
	print("PRESSURE n=",count," angle=",angle," forward=",forward," budget=",max_budget," overlap=",max_overlap)
func barriers() -> void:
	await clear_units()
	var player:Node2D=box(Vector2.ZERO,true)
	var units:Array[Node2D]=[player]
	for i:int in range(1,7):
		var unit:Node2D=box(Vector2(float(i)*16.05,0));unit.Speed=0;unit.direction=Vector2.ZERO
		units.append(unit)
	var wall:StaticBody2D=obstacle(Vector2(112,0),true)
	wall.get_child(0).shape.size=Vector2(8,240)
	await physics_frame
	var farthest:float=0.0
	# Native kinematic recovery has a subpixel contact skin, including without
	# pressure. Bound that edge error while forbidding passage through the wall.
	var respected:bool=true
	for frame:int in range(180):
		await physics_frame
		player.set_player_control_direction(Vector2.RIGHT);player.move(player.Speed,1.0/60.0)
		for i:int in range(1,units.size()):units[i].stand(1.0/60.0)
		for unit:Node2D in units:
			unit.get_body_motion().separate_overlaps()
			farthest=maxf(farthest,unit.global_position.x-center.x)
			respected=respected and unit.global_position.x<=center.x+100.20
	print("PRESSURE_WALL edge_error=",maxf(0.0,farthest-100.0))
	check(respected,"the far-end wall constrains the whole pushing chain")
	var start:Vector2=player.global_position
	for frame:int in range(120):
		await physics_frame
		player.set_player_control_direction(Vector2.UP);player.move(player.Speed,1.0/60.0)
		for unit:Node2D in units:unit.get_body_motion().separate_overlaps()
	check(player.global_position.y<start.y-40,"wall pressure does not lock a free tangential escape direction")
	wall.queue_free();await clear_units()
	player=box(Vector2.ZERO,true)
	var fixed:Node2D=box(Vector2(16.05,0));fixed.Speed=0;fixed.direction=Vector2.ZERO
	fixed.set_meta("body_motion_immovable",true)
	var fixed_start:Vector2=fixed.global_position
	for frame:int in range(90):
		await physics_frame
		player.set_player_control_direction(Vector2.RIGHT);player.move(player.Speed,1.0/60.0)
		player.get_body_motion().separate_overlaps();fixed.get_body_motion().separate_overlaps()
	check(fixed.global_position.is_equal_approx(fixed_start),"explicitly immovable bodies stay immovable")
	check(player.global_position.x<fixed.global_position.x-15.9,"manual pressure is not mutual ghosting")
