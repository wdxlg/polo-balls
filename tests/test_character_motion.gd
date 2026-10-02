extends "res://scripts/training/test_mc_new5.gd"

func pair(a_position:Vector2,b_position:Vector2) -> Array:
	var a:Node2D = spawn("",a_position)
	var b:Node2D = spawn("",b_position,"Team1")
	for unit:Node2D in [a,b]:
		unit.Speed = 200.0
		unit.get_body_motion().set_physics_process(false)
	return [a,b]
func move_pair(a:Node2D,b:Node2D,frames:int,reverse:bool=false) -> void:
	for i:int in range(frames):
		await physics_frame
		var dt:float = a.get_physics_process_delta_time()
		if reverse:
			b.move(b.Speed,dt); a.move(a.Speed,dt)
		else:
			a.move(a.Speed,dt); b.move(b.Speed,dt)
		a.get_body_motion().separate_overlaps()
		b.get_body_motion().separate_overlaps()
func run() -> void:
	game=root.get_node("Game")
	game._settings_storage_path=OS.get_environment("TEMP").path_join("body_motion_settings.json")
	saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(75,true,false,true).timeout.connect(func():finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.5).timeout
	world.set_physics_process(false)
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	for reverse:bool in [false,true]:
		for large:bool in [false,true]:
			await clear_units()
			var actors:Array = pair(Vector2(-25,0),Vector2(25,0))
			var a:Node2D=actors[0]; var b:Node2D=actors[1]
			a.direction=Vector2.RIGHT; b.direction=Vector2.LEFT
			a.set_large_battle_performance_mode(large); b.set_large_battle_performance_mode(large)
			await move_pair(a,b,16,reverse)
			check(a.direction.x<0 and b.direction.x>0,"bilateral head-on direction; order="+str(reverse)+" large="+str(large))
			check(a.global_position.x<center.x-20 and b.global_position.x>center.x+20,"both bodies physically separate, not feedback only")
			check(a.get_collision_mask_value(2) and b.get_collision_mask_value(2),"large battle retains actual body collision")
			check(a.velocity.length()<150 and b.velocity.length()<150,"motor rebound does not multiply kinetic energy")
	await clear_units()
	var actors:Array=pair(Vector2(-42,0),Vector2.ZERO)
	var a:Node2D=actors[0]; var b:Node2D=actors[1]
	a.direction=Vector2.RIGHT; b.direction=Vector2.ZERO; b.Speed=0
	var before:float=b.global_position.x
	await move_pair(a,b,20)
	check(b.global_position.x>before+1.0,"stationary actor receives real displacement")
	# Algebraic contact checks isolate glancing and repeated/separating pairs.
	await physics_frame
	var am:Node=a.get_body_motion();var bm:Node=b.get_body_motion()
	am.current_velocity=Vector2(120,35);bm.current_velocity=Vector2(-120,35)
	am.resolve_pair(b,Vector2.LEFT)
	check(am.current_velocity.x<0 and bm.current_velocity.x>0,"normal impulse affects both actors")
	check(absf(am.current_velocity.y-35)<0.001 and absf(bm.current_velocity.y-35)<0.001,"tangential speed preserved")
	var old:Vector2=am.current_velocity
	am.resolve_pair(b,Vector2.LEFT)
	check(am.current_velocity.is_equal_approx(old),"same pair cannot bounce twice per frame")
	await physics_frame
	am.current_velocity=Vector2.LEFT*100;bm.current_velocity=Vector2.RIGHT*100
	am.resolve_pair(b,Vector2.LEFT)
	check(am.current_velocity.x == -100 and bm.current_velocity.x == 100,"separating bodies get no new impulse")
	# Exact rectangle/circle overlap, no circle-radius pseudo-contact.
	await clear_units()
	actors=pair(Vector2.ZERO,Vector2(20,0));a=actors[0];b=actors[1]
	a.Speed=0;b.Speed=0;a.direction=Vector2.ZERO;b.direction=Vector2.ZERO
	var rectangle:=RectangleShape2D.new();rectangle.size=Vector2(12,52)
	a.collision_shape_2d.shape=rectangle
	var circle:=CircleShape2D.new();circle.radius=8
	b.collision_shape_2d.shape=circle
	a.collision_shape_2d.global_scale=Vector2.ONE
	b.collision_shape_2d.global_scale=Vector2.ONE
	await physics_frame
	var pos:Vector2=a.global_position
	a.get_body_motion().separate_overlaps()
	check(a.global_position.is_equal_approx(pos),"non-overlapping narrow rectangle is not pushed by its broad radius")
	b.global_position=a.global_position+Vector2(10,0)
	for frame:int in range(6):
		await physics_frame
		a.get_body_motion().separate_overlaps();b.get_body_motion().separate_overlaps()
	check(b.global_position.x-a.global_position.x>=13.97,"actual shapes are separated")
	check(a.get_body_motion().impulse_velocity().is_zero_approx(),"position correction adds no kinetic energy")
	var wall:StaticBody2D=obstacle(Vector2(-12,0),true)
	wall.get_child(0).shape.size=Vector2(8,120)
	a.global_position=center+Vector2(-1.8,0);b.global_position=center+Vector2(8,0)
	for frame:int in range(12):
		await physics_frame
		a.get_body_motion().separate_overlaps();b.get_body_motion().separate_overlaps()
	check(a.global_position.x>=center.x-2.01,"overlap correction respects nearby wall")
	check(b.global_position.x-a.global_position.x>=13.9,"blocked share is redistributed to free side")
	wall.queue_free()
	print("CHARACTER_MOTION checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
