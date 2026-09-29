extends "res://tests/test_stone_spear.gd"
func all_merged() -> bool:
	for i:int in range(4):
		if spear._centers[i]!=spear.global_position: return false
		if not spear._copies[i].global_position.is_equal_approx(spear.image.global_position): return false
	return true
func drive(frames:int,delta:float) -> void:
	for frame:int in range(frames):
		await physics_frame
		spear.tick_physics(spear.State.Move,delta)
		spear._process(delta)
func run() -> void:
	create_timer(55.0).timeout.connect(func(): quit(2))
	game=root.get_node("Game")
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	arena=Node2D.new()
	root.add_child(arena)
	current_scene=arena
	arena.process_mode=Node.PROCESS_MODE_DISABLED
	spear=load("res://scenes/characters/我的世界/石矛.tscn").instantiate()
	spear.disable_mode=CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	arena.add_child(spear)
	check(spear.follow_merge_speed==300.0,"reachable full-merge threshold is 300 actual speed")
	check(spear.movement_growth==10.0 and spear.SPEED_DAMAGE_FACTOR==0.25 and spear.orbit_speed_factor==0.018,"latest balance remains unchanged")
	check(spear.body_turn_degrees_per_second==3600.0,"0.05 second U-turn unchanged")
	var last:float=INF
	for speed_value:float in [0.0,30.0,102.0,180.0,299.0,300.0,600.0,1000.0]:
		var gap:float=spear.formation_pose(1,speed_value).offset.length()
		check(gap<=last and gap>=0.0,"gathering never expands as speed increases")
		last=gap
		if speed_value>=300.0:
			for i:int in range(4): check(spear.formation_pose(i,speed_value).offset==Vector2.ZERO,"all target offsets are exactly zero, not an asymptote")
	check(is_equal_approx(spear.formation_pose(1,0.0).offset.length(),32.0),"zero-speed outer spacing stays 32")
	for fps:float in [30.0,60.0,120.0]:
		Engine.physics_ticks_per_second=int(fps)
		for speed_value:float in [300.0,600.0]:
			reset_pose()
			spear._reset_copy_trails()
			spear.Speed=speed_value/0.6
			spear.movement_growth=0.0
			# Full gathering must use the real body, not a still-lagging carrier frame.
			spear._formation_center=Vector2(-40,30)
			var initial:float=spear._centers[1].distance_to(spear.global_position)
			await drive(1,1.0/fps)
			var first:float=spear._centers[1].distance_to(spear.global_position)
			check(first>0.0 and first<initial,"first high-speed frame contracts continuously, no instant snap")
			await drive(int(ceil(fps*0.4)),1.0/fps)
			check(absf(spear._real_speed-speed_value)<0.05,"real movement uses the requested engine physics rate")
			check(all_merged(),"exact body-position convergence at %s Hz and speed %s" % [fps,speed_value])
			for i:int in range(4):
				check(spear._copies[i].global_transform.is_equal_approx(spear.image.global_transform),"straight-line final visible sprite fully overlays main spear")
			# Keep moving and turn sharply: no residual translation lag may reopen a gap.
			spear.direction=Vector2.DOWN
			await drive(3,1.0/fps)
			check(all_merged(),"merged positions remain on body during fast turn")
			spear.direction=Vector2.LEFT
			await drive(3,1.0/fps)
			check(all_merged(),"merged positions remain on body after reversal")
			spear.direction=Vector2(1,1).normalized()
			await drive(3,1.0/fps)
			check(all_merged(),"threshold rounding during diagonal movement cannot reopen a gap")
			check(not spear._copy_trails.samples.is_empty(),"high-speed copy trails remain active while fully merged")
	Engine.physics_ticks_per_second=60
	# Below the threshold, the formation opens smoothly rather than snapping.
	spear.Speed=170.0
	var before:Array=spear._centers.duplicate()
	await drive(1,1.0/60.0)
	var desired:float=spear.formation_pose(1,spear._real_speed).offset.length()
	var real_gap:float=spear._centers[1].distance_to(spear.global_position)
	check(real_gap>0.0 and real_gap<desired+0.1,"slowing down reopens spacing through an intermediate pose")
	game.now_stop_state=true
	before=spear._centers.duplicate()
	spear.tick_physics(spear.State.Move,1.0)
	check(spear._centers==before,"pause still freezes gathering")
	game.now_stop_state=false
	for form:int in [1,2]:
		reset_pose(form)
		for i:int in range(4): check(is_equal_approx(spear.formation_pose(i,1000.0).offset.length(),16.0),"orbit and idle thrust retain one-grid spacing")
	# Switching from orbit while fast converges to the body through existing transition.
	reset_pose(1)
	spear.Speed=1000.0
	spear.movement_growth=0.0
	check(spear.set_formation(0),"switch from orbit to follow at high speed")
	await drive(1,1.0/60.0)
	check(not all_merged(),"stance transition is not a hard positional cut")
	await drive(40,1.0/60.0)
	check(all_merged(),"stance transition ends at exact body position")
	if DisplayServer.get_name()!="headless":
		root.size=Vector2i(1080,720)
		root.content_scale_size=Vector2i(1080,720)
		root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
		var camera:=Camera2D.new()
		camera.zoom=Vector2(5,5)
		camera.position=spear.global_position
		arena.add_child(camera)
		camera.force_update_scroll()
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("E:/godot/polo-balls-checkpoints/stone_spear_merge_20260927/merged.png")==OK,"actual GPU fully-merged pose captured")
	print("STONE_MERGE_RESULT checks=%d failures=%d" % [checks,failures])
	arena.queue_free()
	await physics_frame
	await process_frame
	await process_frame
	quit(0 if failures==0 else 1)
