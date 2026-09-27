extends SceneTree
var actor:Node2D
var arena:Node2D
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.get_node("Game").now_stop_state = false
	root.size = Vector2i(800,600)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var bg:=ColorRect.new()
	bg.color = Color("68717a")
	bg.position = Vector2(-1000,-1000)
	bg.size = Vector2(2000,2000)
	bg.z_index = -10
	arena.add_child(bg)
	actor = load("res://scenes/characters/我的世界/凋灵骷髅.tscn").instantiate()
	actor.name = "WitherSkeletonPreview"
	actor.Team = "A"
	arena.add_child(actor)
	actor.state_machine.set_physics_process(false)
	actor.set_physics_process(false)
	actor.set_process(false)
	actor.voice.set_physics_process(false)
	actor.get_node("Health_Bar").hide()
	var camera:=Camera2D.new()
	camera.position = Vector2(8,0)
	camera.zoom = Vector2.ONE*3.0
	arena.add_child(camera)
	await process_frame
	print("WITHER_SKELETON_PREVIEW scale=",actor.global_scale," body=",actor.image.global_scale," collider=",actor.collision_shape_2d.shape.size)
	if DisplayServer.get_name() == "headless": quit(2); return
	var images:Array[Image] = []
	var times:Array[float] = [-1.0,0.15,0.31,0.57,0.80,0.94,1.06,1.179]
	for i:int in range(times.size()):
		actor.combo_time = times[i]
		actor.combo_heading = Vector2.RIGHT
		actor.direction = Vector2.RIGHT
		actor._face_right = true
		actor.visual_mob()
		await process_frame
		await RenderingServer.frame_post_draw
		await process_frame
		await RenderingServer.frame_post_draw
		var image:Image = root.get_texture().get_image()
		image.save_png("res://tests/wither_skeleton_body_preview_%d.png" % i)
		images.append(image)
	var differences:Array[int] = []
	for i:int in range(1,images.size()):
		var count:int = 0
		for y:int in range(600):
			for x:int in range(800):
				var a:Color = images[0].get_pixel(x,y)
				var b:Color = images[i].get_pixel(x,y)
				if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b) > 0.2: count += 1
		differences.append(count)
	print("WITHER_SKELETON_GPU_ACTOR_DIFFERENCES ",differences)
	for i:int in range(8):
		actor.combo_heading = Vector2.RIGHT.rotated(float(i)*TAU/8.0)
		actor._face_right = actor._geometry_face_right(actor.combo_heading)
		actor.combo_time = 0.23
		actor.visual_mob()
		actor._fade_sprite.hide()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/wither_skeleton_body_direction_%d.png" % i)
	# Upright resting/walking grip, both facings, on actual rendered enlarged body.
	for facing:int in range(2):
		actor.direction = Vector2.RIGHT if facing == 0 else Vector2.LEFT
		actor.combo_time = -1.0
		for pose:int in range(4):
			actor._walking = pose >= 2
			actor._view_clock = float(pose%2)*0.25
			actor.visual_mob()
			actor._fade_sprite.hide()
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tests/wither_skeleton_body_held_%d_%d.png" % [facing,pose])
	actor._walking = false
	actor._view_clock = 0.0
	actor.direction = Vector2.RIGHT
	# Actual GPU time samples of the complete wind-up/cuts/recovery sequence.
	actor.combo_heading = Vector2.RIGHT
	actor._face_right = true
	for i:int in range(143):
		actor.combo_time = float(i)/120.0
		actor.visual_mob()
		actor._fade_sprite.hide()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.backups/wither_skeleton_body_20260927/motion_%02d.png" % i)
	# Now use the real 60Hz state machine + up-to-144Hz render loop, not manually set poses.
	Engine.max_fps = 144
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	actor.cancel_combo()
	actor.cooldown_left = 0.0
	actor.Speed = 0.0
	actor.direction = Vector2.RIGHT
	actor.begin_combo(Vector2.RIGHT)
	actor.set_process(true)
	actor.set_physics_process(true)
	actor.state_machine.set_physics_process(true)
	var trace:Array[Dictionary] = []
	var previous_physics:float = -2.0
	var previous_draw:float = -2.0
	var subframe_updates:int = 0
	var completed:bool = false
	for frame:int in range(360):
		await process_frame
		await RenderingServer.frame_post_draw
		var physical:float = actor.combo_time
		var displayed:float = actor._recovery_draw_time
		if physical >= actor.COMBO_DURATION and displayed >= actor.COMBO_DURATION:
			trace.append({"usec":Time.get_ticks_usec(),"physics":physical,"display":displayed,"angle":actor.blade_angle(displayed)})
			if is_equal_approx(previous_physics,physical) and displayed > previous_draw+0.000001: subframe_updates += 1
			previous_physics = physical
			previous_draw = displayed
		if physical < 0.0:
			completed = true
			break
	var trace_file:FileAccess = FileAccess.open("res://.backups/wither_skeleton_body_20260927/live_render_trace.json",FileAccess.WRITE)
	trace_file.store_string(JSON.stringify(trace))
	trace_file.close()
	print("WITHER_SKELETON_LIVE_RENDER samples=%d subframe_updates=%d completed=%s" % [trace.size(),subframe_updates,str(completed)])
	arena.queue_free()
	await process_frame
	quit(0 if differences[0] > 300 and differences[1] > 300 and differences[2] > 300 and differences[3] > 300 and completed and subframe_updates>0 else 1)
