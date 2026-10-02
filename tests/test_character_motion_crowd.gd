extends "res://tests/test_character_motion.gd"
func run() -> void:
	game=root.get_node("Game")
	game._settings_storage_path=OS.get_environment("TEMP").path_join("body_crowd_settings.json")
	saved=game.Game_Settings.duplicate(true)
	game.now_stop_state=false
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Ball_Can_Move=true
	AudioServer.set_bus_mute(0,true)
	create_timer(90,true,false,true).timeout.connect(func():finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50";world.refresh_map_presentation();world.control.hide()
	await create_timer(0.5).timeout
	world.set_physics_process(false)
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	print("CROWD_ARENA ",world.return_map_world_rect(world.map_group["Map50x50"])," center=",center)
	var camera:=Camera2D.new();world.add_child(camera);camera.global_position=center;camera.zoom=Vector2.ONE*1.6;camera.make_current()
	var actors:Array[Node2D]=[]
	var stress:bool=OS.get_cmdline_user_args().has("--stress")
	var columns:int=16 if stress else 8
	var rows:int=20 if stress else 8
	for row:int in range(rows):
		for col:int in range(columns):
			var actor:Node2D=spawn("",Vector2(col*31-(columns-1)*15.5,row*31-(rows-1)*15.5),"Team"+str(col%2))
			actor.direction=Vector2.ZERO;actor.Speed=0;actor.default_properties.Speed=0
			actor.set_large_battle_performance_mode(true)
			actors.append(actor)
	var wall:StaticBody2D=obstacle(Vector2(-(columns-1)*15.5-25.5,0),true);wall.get_child(0).shape.size=Vector2(8,rows*36+100)
	var max_step:float=0.0
	var max_budget:float=0.0
	for frame:int in range(600 if stress else 180):
		var positions:Array[Vector2]=[]
		for actor:Node2D in actors:positions.append(actor.global_position)
		await physics_frame
		await process_frame
		for i:int in range(actors.size()):
			max_step=maxf(max_step,positions[i].distance_to(actors[i].global_position))
			max_budget=maxf(max_budget,actors[i].get_body_motion()._correction_used)
	var worst_overlap:float=0.0;var max_energy:float=0.0;var no_wall_overlap:bool=true;var solid:bool=true
	for i:int in range(actors.size()):
		var a:Node2D=actors[i]
		max_energy=maxf(max_energy,a.get_body_motion().impulse_velocity().length())
		no_wall_overlap=no_wall_overlap and a.global_position.x>=wall.global_position.x+22-0.04
		solid=solid and a.get_collision_mask_value(2)
		for j:int in range(i+1,actors.size()):
			var b:Node2D=actors[j]
			var contacts:PackedVector2Array=a.collision_shape_2d.shape.collide_and_get_contacts(a.collision_shape_2d.global_transform,b.collision_shape_2d.shape,b.collision_shape_2d.global_transform)
			for k:int in range(0,contacts.size()-1,2):worst_overlap=maxf(worst_overlap,contacts[k].distance_to(contacts[k+1]))
	check(solid,"all crowd actors retain real character-body collision")
	check(no_wall_overlap,"dense crowd correction never enters the wall")
	check(worst_overlap<0.15,"dense crowd converges to real non-overlapping shapes")
	check(max_energy<0.01,"overlap correction cannot accumulate kinetic energy")
	check(max_budget<=3.001,"per-frame correction budget prevents explosive crowd ejection")
	print("CROWD_METRICS actors=",actors.size()," budget=",max_budget," overlap=",worst_overlap," correction_step=",max_step," energy=",max_energy," physics_ms=",Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var image:Image=root.get_texture().get_image()
		var path:String=OS.get_environment("TEMP").path_join("body_motion_crowd.png")
		check(image.save_png(path)==OK,"GPU crowd frame captures successfully")
	# Forces cannot escape a genuine enclosure by crossing the surrounding bodies.
	await clear_units();wall.queue_free();await physics_frame
	var victim:Node2D=spawn("",Vector2.ZERO);victim.direction=Vector2.RIGHT;victim.Speed=100
	var blockers:Array[Node2D]=[]
	for axis:Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
		var block:Node2D=spawn("",axis*36,"Team1")
		block.Speed=0;block.direction=Vector2.ZERO;block.set_meta("body_motion_immovable",true)
		block.get_body_motion().set_physics_process(false);blockers.append(block)
	victim.apply_knockback(Vector2.RIGHT,60,200)
	for frame:int in range(30):
		await physics_frame
		victim.move(victim.Speed,1.0/60.0)
	check(victim.global_position.distance_to(center)<0.5,"true body enclosure blocks displacement without phasing")
	check(not victim.dizziness and victim.Can_Attack and victim.Can_Skill,"enclosure is geometric, not a control lock")
	print("CHARACTER_CROWD checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
