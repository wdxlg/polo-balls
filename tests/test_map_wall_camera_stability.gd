extends SceneTree
const WALL = preload("res://scripts/effects/我的世界/地图立体墙.gd")
var checks:int=0
var failures:int=0

class LateCamera:
	extends Node
	var camera:Camera2D
	var step:int=0
	func _process(_delta:float) -> void:
		step+=1
		camera.global_position=Vector2(80.13+sin(step*0.17)*15.0,80.31+cos(step*0.13)*13.0)
		camera.zoom=Vector2.ONE*(2.0+sin(step*0.11)*0.65)
		camera.force_update_scroll()

func _initialize() -> void:
	_run.call_deferred()

func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error("WALL_STABILITY FAIL: "+label)
	else: print("PASS: ",label)

func _frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw

func _alpha_error(actual:Image,reference:Image) -> Vector2:
	var error:float=0.0
	var mass:float=0.0
	var actual_mass:float=0.0
	var actual_center:=Vector2.ZERO
	var reference_center:=Vector2.ZERO
	for y:int in range(0,actual.get_height(),2):
		for x:int in range(0,actual.get_width(),2):
			var a:float=actual.get_pixel(x,y).a
			var b:float=reference.get_pixel(x,y).a
			error+=absf(a-b)
			mass+=b
			actual_mass+=a
			actual_center+=Vector2(x,y)*a
			reference_center+=Vector2(x,y)*b
	return Vector2(error/maxf(mass,1.0),(actual_center/maxf(actual_mass,1.0)).distance_to(reference_center/maxf(mass,1.0)))

func _run() -> void:
	create_timer(115.0,true,false,true).timeout.connect(func():quit(2))
	var folder:String="user://wall_camera_stability"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var view:=SubViewport.new()
	view.size=Vector2i(640,640)
	view.world_2d=World2D.new()
	view.transparent_bg=true
	view.snap_2d_transforms_to_pixel=true
	view.snap_2d_vertices_to_pixel=false
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var volume:Node2D=WALL.new()
	view.add_child(volume)
	var camera:=Camera2D.new()
	camera.position_smoothing_enabled=false
	view.add_child(camera)
	camera.make_current()
	camera.position=Vector2(80.13,80.31)
	camera.zoom=Vector2.ONE*2.3
	camera.force_update_scroll()
	var ground:Array[Rect2]=[Rect2(0,0,160,160)]
	var walls:Array[Rect2]=[Rect2(-16,-16,192,16),Rect2(-16,160,192,16),Rect2(-16,0,16,160),Rect2(160,0,16,160)]
	var edges:Array[Dictionary]=[]
	volume.configure_regions(ground,walls,edges,Vector2(16,16),"grass",Vector2(1,-1),0.4)
	volume.shadow_picture.hide() # 单独比较墙体合成与其真实3D来源，不混入地影。
	await _frame()
	var mesh_id:int=volume.mesh_node.mesh.get_instance_id()
	var worst_static:Vector2=Vector2.ZERO
	for snap:bool in [false,true]:
		view.snap_2d_transforms_to_pixel=snap
		var worst:Vector2=Vector2.ZERO
		for i:int in range(8):
			camera.position=Vector2(80.13+i*0.17,80.31+i*0.23)
			camera.zoom=Vector2.ONE*(1.15+float(i)*0.23)
			camera.force_update_scroll()
			await _frame()
			var actual:Image=view.get_texture().get_image()
			var reference:Image=volume.viewport.get_texture().get_image()
			var error:Vector2=_alpha_error(actual,reference)
			worst=worst.max(error)
			if snap and i==5:
				actual.save_png(folder+"/composite.png")
				reference.save_png(folder+"/source_3d.png")
		print("WALL_STABILITY_STATIC snap=",snap," mismatch=",worst.x," shift_px=",worst.y)
		check(worst.x<0.008 and worst.y<0.25,"pixel snap %s: subpixel pan/zoom does not displace composited wall" % snap)
		worst_static=worst_static.max(worst)
	view.snap_2d_transforms_to_pixel=true
	var mover:=LateCamera.new()
	mover.camera=camera
	mover.process_priority=1000
	view.add_child(mover)
	var worst_motion:Vector2=Vector2.ZERO
	var worst_alignment:float=0.0
	for i:int in range(24):
		await _frame()
		var actual:Image=view.get_texture().get_image()
		var reference:Image=volume.viewport.get_texture().get_image()
		worst_motion=worst_motion.max(_alpha_error(actual,reference))
		var point:Vector2=Vector2(20,20)
		var projected:Vector2=volume.camera.unproject_position(Vector3(point.x,0,point.y))
		worst_alignment=maxf(worst_alignment,projected.distance_to(view.get_canvas_transform()*point))
		if i%4==0: actual.save_png(folder+"/motion_%02d.png" % i)
	print("WALL_STABILITY_MOTION mismatch=",worst_motion.x," shift_px=",worst_motion.y," final_canvas_error=",worst_alignment)
	check(worst_motion.x<0.008 and worst_motion.y<0.25,"continuous late-frame camera motion stays locked to the 3D frame")
	check(worst_alignment<0.15,"3D projection uses the final rendered Camera2D canvas, not previous process order")
	check(volume.mesh_node.mesh.get_instance_id()==mesh_id,"camera motion never rebuilds geometry")
	check(view.snap_2d_transforms_to_pixel,"project pixel snapping stays enabled for other sprites")
	mover.set_process(false)
	mover.queue_free()
	camera.position_smoothing_enabled=true
	camera.position=Vector2(94.25,65.75)
	await _frame()
	var before_scroll:Transform2D=view.get_canvas_transform()
	for i:int in range(4): volume._update_projection()
	check(view.get_canvas_transform().is_equal_approx(before_scroll),"projection refresh never advances Camera2D smoothing")
	camera.position_smoothing_enabled=false
	paused=true
	camera.position=Vector2(75.37,82.69)
	camera.zoom=Vector2.ONE*2.4
	camera.force_update_scroll()
	await _frame()
	var paused_error:Vector2=_alpha_error(view.get_texture().get_image(),volume.viewport.get_texture().get_image())
	check(paused_error.x<0.008 and paused_error.y<0.25,"paused toolbar pan/zoom keeps wall aligned")
	paused=false
	camera.position=Vector2(80.13,80.31)
	camera.zoom=Vector2.ONE*2.0
	camera.force_update_scroll()
	await _frame()
	var capture:=SubViewport.new()
	capture.size=Vector2i(640,640)
	capture.transparent_bg=true
	capture.world_2d=view.world_2d
	capture.snap_2d_transforms_to_pixel=true
	capture.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(capture)
	var source_center:Vector2=view.get_canvas_transform().affine_inverse()*Vector2(320,320)
	capture.canvas_transform=Transform2D(Vector2.RIGHT,Vector2.DOWN,Vector2(320,320)-source_center)
	await _frame()
	var reference:Image=volume.viewport.get_texture().get_image()
	reference.resize(320,320,Image.INTERPOLATE_NEAREST)
	var expected:Image=Image.create(640,640,false,Image.FORMAT_RGBA8)
	expected.fill(Color.TRANSPARENT)
	expected.blit_rect(reference,Rect2i(0,0,320,320),Vector2i(160,160))
	var capture_error:Vector2=_alpha_error(capture.get_texture().get_image(),expected)
	print("WALL_STABILITY_CAPTURE mismatch=",capture_error.x," shift_px=",capture_error.y)
	check(capture_error.x<0.06 and capture_error.y<0.6,"shared recording/overview canvas preserves world UV reprojection at different zoom")
	capture.render_target_update_mode=SubViewport.UPDATE_DISABLED
	capture.queue_free()
	view.remove_child(volume)
	check(not RenderingServer.frame_pre_draw.is_connected(Callable(volume,"_sync_projection_before_draw")),"leaving tree disconnects render callback")
	volume.free()
	await _frame()
	view.render_target_update_mode=SubViewport.UPDATE_DISABLED
	view.queue_free()
	await process_frame
	print("WALL_STABILITY checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
