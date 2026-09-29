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
	var times:Array[float] = [-1.0,0.22,0.49,0.86]
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
		image.save_png("res://tests/wither_skeleton_preview_%d.png" % i)
		images.append(image)
	var differences:Array[int] = []
	for i:int in range(1,4):
		var count:int = 0
		for y:int in range(600):
			for x:int in range(800):
				var a:Color = images[0].get_pixel(x,y)
				var b:Color = images[i].get_pixel(x,y)
				if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b) > 0.2: count += 1
		differences.append(count)
	print("WITHER_SKELETON_GPU_ACTOR_DIFFERENCES ",differences)
	arena.queue_free()
	await process_frame
	quit(0 if differences[0] > 300 and differences[1] > 300 and differences[2] > 300 else 1)
