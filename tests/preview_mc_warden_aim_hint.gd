extends "res://tests/test_mc_frontier.gd"
## GPU 预览：左 = 尖啸体探测波（带残影）+ 瞄准圈；中 = 声波蓄力瞄准（多圈不同相位）；右 = 瞄准结束后残留的圈在渐隐。
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
		w.frontier_fx.aim_rings.clear(); w.frontier_fx._aim_spawn_left=0.0
		w.form=w.Form.DORMANT
		w.listen_heading=Vector2.RIGHT
		# 瞄准点故意放在假人脚下前方空地，避免被假人身体盖住；三格取不同相位看扩散圈
		var target:Vector2=enemy.global_position+Vector2(-40,26)
		if state==0:
			w.alert_level=100; w.begin_probe(); w.emit_probe()
			var wave:Node2D=w.waves.back()
			wave.set_physics_process(false)
			for i:int in range(12): wave.advance(0.03)
			w._aim("probe",target,0.32)
			w.frontier_fx.update_aim_rings(0.01); w.frontier_fx.update_aim_rings(0.16)
		elif state==1:
			w.form=w.Form.AWAKE; w._form_stats(true); w.direction=Vector2.RIGHT
			w._aim("sonic",target,1.15)
			for i:int in range(3): w.frontier_fx.update_aim_rings(0.14)
			w._sonic_heading=Vector2.RIGHT; w.sonic_origin=o; w.sonic_end=o+Vector2.RIGHT*w.sonic_range; w.sonic_left=0.5
		else:
			w.form=w.Form.AWAKE; w._form_stats(true); w.direction=Vector2.RIGHT
			w._aim("melee",target,0.2); w.frontier_fx.update_aim_rings(0.01)
			w._clear_aim(); w.frontier_fx.update_aim_rings(0.2)
		w.visual_mob(); w.frontier_fx.time=0.37+0.6*state; w.frontier_fx.queue_redraw()
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
	montage.save_png("res://tests/warden_aim_hint_preview.png")
	print("WARDEN AIM GPU: probe / sonic / melee")
	finish(0)
