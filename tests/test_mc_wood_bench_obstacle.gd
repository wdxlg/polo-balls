extends "res://tests/test_mc_frontier.gd"
func run() -> void:
	var o:Vector2=await setup_world()
	create_timer(60).timeout.connect(func(): finish(2))
	var sword:Node2D=actor("木剑",o)
	sword._split_requested=true; sword.split_sword()
	await physics_frame
	await process_frame
	var bench:StaticBody2D=sword.workbench
	bench.set_physics_process(false)
	var parts:Array=bench.living_pieces()
	for piece:Node2D in parts:
		piece.state_machine.set_physics_process(false)
		piece.dock_delay=0
		piece.global_position=o+Vector2(80 if piece==sword else -80,0)
	check(bench.image.texture.get_size()*bench.image.scale==Vector2(34,34),"workbench image is reduced from 40 to 34")
	check(bench.obstacle_shape.shape.size==Vector2(34,34),"physical obstacle matches reduced image size")
	check(bench.collision_layer==0,"materializing workbench remains nonblocking")
	bench.age=bench.materialize_duration; bench.update_opacity()
	await process_frame
	await physics_frame
	check(bench.collision_layer==1 and not bench.obstacle_shape.disabled,"materialized workbench becomes a real terrain obstacle")
	var ray:=PhysicsRayQueryParameters2D.create(o+Vector2(-60,0),o+Vector2(60,0),1)
	var hit:Dictionary=world.get_world_2d().direct_space_state.intersect_ray(ray)
	check(hit.get("collider")==bench,"ordinary obstacle raycasts hit the workbench")
	var body:=CharacterBody2D.new()
	body.collision_layer=2; body.collision_mask=1
	var collider:=CollisionShape2D.new(); var circle:=CircleShape2D.new(); circle.radius=4
	collider.shape=circle; body.add_child(collider); world.add_child(body)
	body.global_position=o+Vector2(-60,0)
	var collision:KinematicCollision2D=body.move_and_collide(Vector2(120,0))
	check(collision!=null and collision.get_collider()==bench and body.global_position.x<o.x,"moving body cannot pass through the table")
	body.queue_free()
	for piece:Node2D in parts:
		piece.global_position=o+Vector2((17+sword.U.radius(piece)-0.5)*(1 if piece==sword else -1),0)
		check(bench.touching(piece),"fragment can repair from the outside edge without seeing the bench as an obstruction")
	bench.advance(0.25)
	check(bench.progress>0 and parts[0].repairing and parts[1].repairing,"both fragments can start normal repair while outside solid bench")
	var manager:Node=load("res://scripts/effects/我的世界/ghast_obstacle_damage.gd").ensure(sword)
	for n:int in range(3):
		var updates:Array=manager.collect_blast(sword,o,24)
		check(updates.any(func(u:Dictionary): return str(u.get("path",""))==str(world.get_path_to(bench))),"normal obstacle blast collection finds workbench")
		manager.apply_updates(updates)
		if n<2: check(not bench.is_queued_for_deletion(),"workbench survives before third obstacle blast")
	check(bench.is_queued_for_deletion() and sword.bench_destroyed and parts[1].bench_destroyed,"third blast destroys obstacle and invalidates its family's repair bench")
	await process_frame
	sword.ensure_workbench()
	check(not is_instance_valid(sword.workbench),"destroyed obstacle is not silently recreated")
	print("WOOD BENCH OBSTACLE: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
