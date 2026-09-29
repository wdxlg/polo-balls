extends "res://tests/test_stone_spear.gd"
func drive(frames:int,delta:float) -> void:
	for frame:int in range(frames):
		await physics_frame
		spear.tick_physics(spear.State.Move,delta)
		spear._process(delta)
func run() -> void:
	create_timer(40.0).timeout.connect(func(): quit(2))
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
	check(spear.Speed==170.0 and spear.movement_growth==10.0,"birth speed and growth unchanged")
	check(spear.follow_merge_speed==300.0 and spear.SPEED_DAMAGE_FACTOR==0.25,"merge endpoint and damage nerf unchanged")
	for v:float in [-10.0,0.0,30.0,102.0]:
		check(spear.follow_gather_progress(v)==0.0,"base-speed or slower movement cannot prematurely gather")
		for i:int in range(4):
			check(is_equal_approx(spear.formation_pose(i,v).offset.length(),16.0*(1+i%2)),"birth layout retains one/two-grid spacing")
	var previous:float=0.0
	for v:float in [103.0,120.0,180.0,250.0,300.0]:
		var progress:float=spear.follow_gather_progress(v)
		check(progress>previous and progress<=1.0,"only acceleration above birth speed progressively gathers")
		previous=progress
	check(spear.follow_gather_progress(300.0)==1.0 and spear.follow_gather_progress(1000.0)==1.0,"full gathering still occurs exactly at 300")
	for fps:float in [30.0,60.0,120.0]:
		Engine.physics_ticks_per_second=int(fps)
		reset_pose()
		spear.Speed=170.0
		spear.movement_growth=0.0
		await drive(int(fps*0.3),1.0/fps)
		check(absf(spear._real_speed-102.0)<0.02,"requested physics rate produces actual birth speed")
		for i:int in range(4):
			check(absf(absf(spear._centers[i].y-spear.global_position.y)-16.0*(1+i%2))<0.01,"moving at birth speed stays visibly open at %s Hz" % fps)
			check(spear._copies[i].global_position.is_equal_approx(spear._centers[i]),"open visual copies match physical positions")
		var before:float=absf(spear._centers[1].y-spear.global_position.y)
		spear.Speed=300.0
		await drive(1,1.0/fps)
		var now:float=absf(spear._centers[1].y-spear.global_position.y)
		var goal:float=spear.formation_pose(1,spear._real_speed).offset.length()
		check(now<before and now>goal,"acceleration begins gathering through an intermediate pose")
		await drive(int(fps*0.3),1.0/fps)
		check(absf(absf(spear._centers[1].y)-goal)<0.02,"accelerated gathering still converges promptly")
	Engine.physics_ticks_per_second=60
	reset_pose()
	spear._reset_copy_trails()
	spear.Speed=170.0
	spear.movement_growth=10.0
	await drive(60,1.0/60.0)
	check(absf(spear.permanent_speed_bonus-10.0)<0.01,"normal first moving second still earns ten growth")
	check(absf(spear._centers[1].y)>25.0 and absf(spear._centers[1].y)<32.0,"first second remains spread out rather than squeezing onto the body")
	check(spear._copy_trails.samples.is_empty(),"opening does not trigger high-speed trails")
	for form:int in [1,2]:
		reset_pose(form)
		for i:int in range(4): check(is_equal_approx(spear.formation_pose(i,102.0).offset.length(),16.0),"other formations retain their original spacing")
	if DisplayServer.get_name()!="headless":
		reset_pose()
		spear.Speed=170.0
		spear.movement_growth=0.0
		await drive(20,1.0/60.0)
		root.size=Vector2i(1080,720)
		root.content_scale_size=Vector2i(1080,720)
		root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
		var camera:=Camera2D.new()
		camera.zoom=Vector2(5,5)
		camera.position=spear.global_position
		arena.add_child(camera)
		camera.force_update_scroll()
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("E:/godot/polo-balls-checkpoints/stone_spear_opening_20260927/opening.png")==OK,"production birth-speed open layout captured on GPU")
	print("STONE_OPENING_RESULT checks=%d failures=%d" % [checks,failures])
	arena.queue_free()
	await physics_frame
	await process_frame
	await process_frame
	quit(0 if failures==0 else 1)
