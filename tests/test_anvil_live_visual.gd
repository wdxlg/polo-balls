extends "res://tests/test_anvil.gd"
## Real engine/state-machine timing and an actual GPU contact sheet, not manual damage calls.
func snapshot(unit:Node2D,camera:Camera2D) -> Image:
	var stopped:bool = game.now_stop_state
	game.now_stop_state = true
	camera.global_position = unit.global_position
	camera.force_update_scroll()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var frame:Image = root.get_texture().get_image()
	var point:Vector2 = root.get_final_transform()*unit.get_global_transform_with_canvas().origin
	var crop:Image = frame.get_region(Rect2i(Vector2i(point)-Vector2i(128,128),Vector2i(256,256)))
	crop.convert(Image.FORMAT_RGB8)
	game.now_stop_state = stopped
	return crop
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(90.0).timeout.connect(func(): finish(2))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(640,480)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.3).timeout
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"live anvil GPU preloads complete")
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var unit:Node2D = anvil(center+Vector2(-90,-25))
	var target:Node2D = dummy(center)
	target.default_properties.Speed = 0.0
	target.Has_Collision_Damage = false
	target.state_machine.set_physics_process(true)
	var target_start_y:float = target.global_position.y
	unit.health_bar.hide()
	target.health_bar.hide()
	world.camera_2d.enabled = false
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.zoom = Vector2(3.5,3.5)
	camera.make_current()
	var shots:Array[Image] = []
	shots.append(await snapshot(unit,camera))
	unit.set_player_control_peer(0)
	unit.set_process(true)
	unit.state_machine.set_physics_process(true)
	var hp:float = target.health
	var got_rise:bool = false
	var got_apex:bool = false
	var got_fall:bool = false
	var got_hit:bool = false
	var got_repeat:bool = false
	var peak_speed:float = 0.0
	var hover_frames:int = 0
	var deadline:int = Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<deadline and (not got_repeat or unit.hit_count<2):
		await physics_frame
		peak_speed = maxf(peak_speed,unit.fall_speed)
		if unit.slam_phase==unit.SlamPhase.HOVER: hover_frames += 1
		if not got_rise and unit.slam_phase==unit.SlamPhase.RISING and unit.phase_elapsed>unit.jump_duration*0.4:
			shots.append(await snapshot(unit,camera));got_rise = true
		# Ignore the ordinary FALLING spawn state before the first skill actually rises.
		elif got_rise and not got_apex and unit.slam_phase==unit.SlamPhase.FALLING:
			var bounds:Rect2 = unit.map_bounds_for(target.global_position)
			var release_y:float = bounds.position.y+unit.body_half_size().y+unit.top_padding
			var frame_travel:float = unit.fall_speed/float(Engine.physics_ticks_per_second)+0.1
			check(absf(unit.global_position.x-target.global_position.x)<1.0 and unit.global_position.y>=release_y-0.1 and unit.global_position.y-release_y<=frame_travel,"live AI passes the enemy-aligned map-top release without a waiting frame")
			check(unit.fall_speed>0.0 and unit.fall_speed>=unit.jump_velocity(1.0).y-0.1,"live release retains downward momentum immediately")
			shots.append(await snapshot(unit,camera));got_apex = true
		elif not got_fall and unit.slam_phase==unit.SlamPhase.FALLING and unit.fall_speed>200.0:
			shots.append(await snapshot(unit,camera));got_fall = true
		elif not got_hit and unit.hit_count>0 and unit.slam_phase==unit.SlamPhase.FALLING:
			shots.append(await snapshot(unit,camera));got_hit = true
		elif got_hit and not got_repeat and unit.slam_phase==unit.SlamPhase.RISING:
			shots.append(await snapshot(unit,camera));got_repeat = true
	check(got_rise and got_apex and got_fall and got_hit and got_repeat,"real state machine visibly completes leap, seamless top release, fall, impact and automatic repeat")
	check(hover_frames==0,"real GPU combat renders no HOVER phase between the leap and the slam")
	check(unit.hit_count>=2 and unit.slam_count>=2 and unit.landing_count>=1 and target.health<hp,"autonomous real-time combat causes repeated physical damage without test-side skill calls")
	check(target.global_position.y>target_start_y+10.0,"live victim is actually knocked downward while automatic slams continue")
	check(peak_speed>unit.minimum_impact_speed,"live descent genuinely accelerates before impact")
	check(unit.image.texture==unit.TEXTURE and unit.image.visible,"native anvil model sprite is the actual live character art")
	var contact:Image = Image.create(768,512,false,Image.FORMAT_RGB8)
	for i:int in range(mini(shots.size(),6)):
		contact.blit_rect(shots[i],Rect2i(0,0,256,256),Vector2i((i%3)*256,(i/3)*256))
	contact.save_png("res://tests/anvil_live_contact.png")
	unit.Can_Skill = false
	unit.default_properties.Can_Skill = false
	await create_timer(0.05).timeout
	var count:int = unit.slam_count
	await create_timer(0.3).timeout
	check(unit.slam_count==count,"live skill disable stops future automatic leaps")
	print("ANVIL_LIVE_GPU checks=",checks," failures=",failures," capture=res://tests/anvil_live_contact.png")
	finish(0 if failures==0 else 1)
