extends "res://tests/test_mc_bat_transform.gd"
var recording:bool = false
func record_sequence() -> void:
	recording = true
	for i:int in range(48):
		await capture("frame_%02d"%i)
		await create_timer(1.0/15.0).timeout
	recording = false
func capture(label:String) -> void:
	await RenderingServer.frame_post_draw
	var picture:Image = root.get_texture().get_image()
	var size:Vector2i = picture.get_size()
	var rect := Rect2i(Vector2i(size.x/2-210,size.y/2-150),Vector2i(420,300))
	picture.get_region(rect).save_png("res://tests/bat_transform_"+label+".png")
func run() -> void:
	var center:Vector2 = await setup_world()
	game.Game_Settings.Training_Debug_Mode = false
	world.versus_label.hide()
	var b:Node2D = spawn(BAT.SCENE_PATH,center)
	b.state_machine.set_physics_process(false)
	await physics_frame
	await process_frame
	pause_members(b)
	var i:int = 0
	for member:Node2D in b.living_members():
		member.global_position = center+Vector2.RIGHT.rotated(TAU*float(i)/5.0)*100.0
		member.health_bar.hide() # Preview only: expose the small bodies and particle silhouette.
		i += 1
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.global_position = center
	camera.zoom = Vector2(3,3)
	camera.make_current()
	record_sequence()
	await create_timer(0.2).timeout
	await capture("01_before")
	b.fuse_swarm()
	for member:Node2D in b.living_members(): member.state_machine.set_physics_process(true)
	await create_timer(0.28).timeout
	await capture("02_gather")
	var wait:float = 0.0
	while not b.vampire and wait < 5.0:
		await create_timer(0.02).timeout
		wait += 0.02
	b.state_machine.set_physics_process(false)
	await create_timer(0.1).timeout
	await capture("03_fuse_burst")
	await create_timer(0.3).timeout
	await capture("04_fuse_smoke")
	await create_timer(0.9).timeout
	b.split_swarm()
	pause_members(b)
	for member:Node2D in b.living_members(): member.health_bar.hide()
	await create_timer(0.1).timeout
	await capture("05_split_burst")
	await create_timer(0.3).timeout
	await capture("06_split_smoke")
	while recording: await process_frame
	print("BAT_TRANSFORM_GPU_CAPTURED ",b.living_members().size())
	finish(0)
