extends "res://tests/test_anvil.gd"
## Real-renderer whole-path capture; copies are test-only breadcrumbs, never gameplay effects.
func changed_pixels(a:Image,b:Image) -> int:
	var count:int = 0
	for y:int in range(a.get_height()):
		for x:int in range(a.get_width()):
			var d:Color = a.get_pixel(x,y)-b.get_pixel(x,y)
			if absf(d.r)+absf(d.g)+absf(d.b)>0.02: count += 1
	return count
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(90.0).timeout.connect(func(): finish(2))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(800,600)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.3).timeout
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"arc GPU preloads complete")
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var unit:Node2D = anvil(center+Vector2(-120,60))
	var target:Node2D = dummy(center+Vector2(120,0))
	unit.health_bar.hide()
	target.health_bar.hide()
	target.image.hide()
	unit.begin_slam(target)
	var low:Vector2 = unit._jump_from
	var high:Vector2 = unit._jump_from
	var path := PackedVector2Array()
	for i:int in range(65):
		var point:Vector2 = unit.jump_position(float(i)/64.0)
		path.append(point)
		low = low.min(point)
		high = high.max(point)
	var bounds:Rect2 = unit.map_bounds_for(unit.global_position)
	var half:Vector2 = unit.body_half_size()
	var inside:bool = true
	for point:Vector2 in path:
		inside = inside and bounds.grow(0.01).encloses(Rect2(point-half,half*2.0))
	check(inside,"GPU overview samples keep the full anvil body inside the map")
	var rect:Rect2 = Rect2(low,high-low).grow(40.0)
	world.camera_2d.enabled = false
	world.set_process(false)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.global_position = rect.get_center()
	camera.zoom = Vector2.ONE*minf(760.0/rect.size.x,560.0/rect.size.y)
	camera.make_current()
	camera.force_update_scroll()
	await process_frame
	# Verify the real sprite stays visible on its bounded, collidable in-map arc.
	for phase:float in [0.35,0.75]:
		unit.step_mob(maxf(unit._jump_total_time*phase-unit.phase_elapsed,0.0))
		camera.global_position = unit.global_position
		camera.zoom = Vector2(4,4)
		camera.force_update_scroll()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var point:Vector2 = root.get_final_transform()*unit.get_global_transform_with_canvas().origin
		var region:Rect2i = Rect2i(Vector2i(point)-Vector2i(90,90),Vector2i(180,180))
		var shown:Image = root.get_texture().get_image().get_region(region)
		unit.image.hide()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var hidden:Image = root.get_texture().get_image().get_region(region)
		unit.image.show()
		check(changed_pixels(shown,hidden)>15,"real GPU shows travelling anvil at arc phase "+str(phase))
	# Test-only overview: hide menu canvases and freeze automatic camera adjustments.
	for layer:Node in world.find_children("*","CanvasLayer",true,false): layer.hide()
	game.now_stop_state = true
	camera.global_position = rect.get_center()
	camera.zoom = Vector2.ONE*minf(660.0/rect.size.x,430.0/rect.size.y)
	camera.force_update_scroll()
	var guide := Line2D.new()
	guide.points = path
	guide.width = 1.1
	guide.default_color = Color(0.9,0.65,0.25,0.8)
	guide.z_as_relative = false
	guide.z_index = 96
	world.add_child(guide)
	for phase:float in [0.0,0.15,0.30,0.45,0.60,0.75,0.90,1.0]:
		var pose := Sprite2D.new()
		pose.texture = unit.TEXTURE
		pose.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pose.z_as_relative = false
		pose.z_index = unit.image.z_index
		world.add_child(pose)
		pose.global_position = unit.jump_position(phase)
		pose.global_scale = unit.image.global_scale
		pose.modulate.a = 0.85
	unit.image.hide()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var capture:Image = root.get_texture().get_image()
	capture.save_png("res://tests/anvil_arc_path.png")
	check(path[0]==unit._jump_from and path[-1]==unit._jump_to,"GPU path overview includes exact launch and landing endpoints")
	print("ANVIL_ARC_GPU checks=",checks," failures=",failures," capture=res://tests/anvil_arc_path.png")
	finish(0 if failures==0 else 1)
