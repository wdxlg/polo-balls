extends SceneTree
## Focused GPU snapshot of the shared explosion at the Wither's new radius.
## Run without --headless; no arena, 3D viewport, audio or gameplay mutation.
const ARTIFACT:String = "user://wither_cadence/awakening_explosion.png"

func _initialize() -> void: call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("WITHER_VISUAL: SKIP (needs a rendering display)")
		quit(0)
		return
	var canvas:=Node2D.new()
	canvas.name = "WitherExplosionCanvas"
	root.add_child(canvas)
	current_scene = canvas
	var viewport:=SubViewport.new()
	viewport.size = Vector2i(384,384)
	viewport.transparent_bg = true
	viewport.world_2d = canvas.get_world_2d()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera:=Camera2D.new()
	camera.zoom = Vector2(1.7,1.7)
	viewport.add_child(camera)
	camera.make_current()
	var visual:Node2D = load("res://scenes/effects/我的世界/MC爆炸.tscn").instantiate()
	visual.radius = 72.0
	visual.play_audio = false
	visual.visual_seed = 20260925
	canvas.add_child(visual)
	visual.advance_visual(0.11)
	await RenderingServer.frame_post_draw
	var frame:Image = viewport.get_texture().get_image()
	var drawn:int = 0
	for y:int in range(frame.get_height()):
		for x:int in range(frame.get_width()):
			if frame.get_pixel(x,y).a > 0.1: drawn += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://wither_cadence"))
	var error:Error = frame.save_png(ARTIFACT)
	print("WITHER_VISUAL: radius=",visual.radius," drawn_pixels=",drawn," size=",frame.get_size()," png_error=",error)
	viewport.queue_free()
	canvas.queue_free()
	quit(0 if visual.radius == 72.0 and drawn > 100 and error == OK else 1)
