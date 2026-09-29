extends "res://tests/test_mc_frontier.gd"
## Arranged GPU poses for visual inspection; gameplay is independently tested.
func run() -> void:
	var o:Vector2=await setup_world()
	world.control.hide()
	world.set_process(false)
	world.set_physics_process(false)
	world.camera_2d.enabled=false
	var camera:=Camera2D.new()
	camera.position_smoothing_enabled=false
	world.add_child(camera)
	camera.global_position=o+Vector2(62,0)
	camera.zoom=Vector2.ONE*2.4
	camera.make_current()
	var w:Node2D=actor("监守者",o)
	var enemy:Node2D=dummy(o+Vector2(120,0))
	world.get_node("MCBattleNoise").set_physics_process(false)
	w.health_bar.hide(); enemy.health_bar.hide(); w.side_status_ui_enabled=false
	w.frontier_fx.particles.clear()
	var frames:Array[Image]=[]
	for state:int in range(3):
		w._cancel_attacks(true)
		w.form=w.Form.DORMANT
		w.alert_level=80
		w.listen_heading=Vector2.RIGHT
		if state==1:
			w.alert_level=100; w.begin_probe(); w.emit_probe()
			var wave:Node2D=w.waves.back()
			wave.set_physics_process(false)
			wave.advance(0.64)
			if w.waves.back().kind=="return":
				var echo:Node2D=w.waves.back()
				echo.set_physics_process(false)
				echo.advance(0.06)
		elif state==2:
			# Visual fixture only: real summoning is covered by five swept-hit/return tests.
			w.form=w.Form.AWAKE; w._form_stats(true)
			w.direction=Vector2.RIGHT
			w._launch_wave("sonic",o,Vector2.RIGHT)
			var wave:Node2D=w.waves.back()
			wave.set_physics_process(false)
			wave.advance(0.14)
		w.visual_mob(); w.frontier_fx.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var screen:Image=root.get_texture().get_image()
		var point:Vector2=root.get_final_transform()*w.get_canvas_transform()* (o+Vector2(62,0))
		var region:Rect2i=Rect2i(Vector2i(point)-Vector2i(180,110),Vector2i(360,220)).intersection(Rect2i(Vector2i.ZERO,screen.get_size()))
		var frame:Image=screen.get_region(region)
		frame.resize(360,220,Image.INTERPOLATE_NEAREST)
		frames.append(frame)
	var montage:=Image.create(1080,220,false,Image.FORMAT_RGB8)
	for i:int in range(frames.size()):
		frames[i].convert(Image.FORMAT_RGB8)
		montage.blit_rect(frames[i],Rect2i(0,0,360,220),Vector2i(i*360,0))
	montage.save_jpg("res://tests/warden_sound_preview.jpg",0.86)
	print("WARDEN GPU: alert / outbound and returning probe / sonic wave")
	finish(0)
