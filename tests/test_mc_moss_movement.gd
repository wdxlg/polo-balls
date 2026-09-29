extends "res://tests/test_mc_frontier.gd"
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(60).timeout.connect(func(): finish(2))
	var moss:Node2D = actor("苔藓",center)
	moss.FOOTSTEPS.ensure(moss).set_physics_process(false)
	moss.player_control_direction = Vector2.RIGHT
	moss.Repel = Vector2.ZERO
	await physics_frame
	var original_speed:float = moss.Speed
	moss.move(100.0,1.0/60.0)
	var normal:float = moss.velocity.length()
	check(normal>0.0,"baseline normal movement is nonzero")
	moss.growth_left = 0.0
	check(moss.cultivate(),"placement windup begins")
	var chosen:Array = moss._growth_pending.duplicate(true)
	var start:Vector2 = moss.global_position
	moss.move(100.0,1.0/60.0)
	check(moss.global_position.x>start.x,"placement no longer freezes physical movement")
	check(is_equal_approx(moss.velocity.length(),normal*0.45),"windup uses forty-five percent normal movement speed")
	check(moss._growth_pending==chosen,"moving during windup does not drag or reroll preview cells")
	moss.player_control_direction = Vector2.LEFT
	moss.move(100.0,1.0/60.0)
	moss.visual_mob()
	check(moss.velocity.x<0.0 and not moss._face_right,"player can steer and turn while placing")
	moss.clock = moss._moss_pose_started+moss.placement_shrink_time+0.0001
	check(moss.finish_cultivation(),"moving does not prevent timed placement")
	moss.move(100.0,1.0/60.0)
	check(is_equal_approx(moss.velocity.length(),normal*0.45),"rebound also keeps reduced nonzero speed")
	moss.clock = moss._moss_pose_started+moss.placement_shrink_time+moss.placement_spring_time+0.01
	moss.move(100.0,1.0/60.0)
	check(is_equal_approx(moss.velocity.length(),normal),"animation end immediately restores normal movement")
	check(moss.Speed==original_speed,"temporary slowdown never modifies permanent Speed")
	moss.growth_left = 0.0
	check(moss.cultivate(),"second placement starts")
	moss.cancel_cultivation()
	moss.move(100.0,1.0/60.0)
	check(is_equal_approx(moss.velocity.length(),normal),"cancel restores speed without leaving a slow debuff")
	moss.set_player_control_peer(0)
	moss.direction = Vector2.RIGHT
	moss.growth_left = 0.0
	check(moss.cultivate(),"AI placement starts")
	moss.move(100.0,1.0/60.0)
	check(is_equal_approx(moss.velocity.x,normal*0.45),"AI also moves slowly rather than stopping")
	moss.cancel_cultivation()
	moss.burrowing = true
	start = moss.global_position
	moss.move(100.0,1.0/60.0)
	check(moss.velocity.is_zero_approx() and moss.global_position==start,"burrow movement lock remains unchanged")
	moss.burrowing = false
	print("MOSS MOVEMENT CONTRACTS: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
