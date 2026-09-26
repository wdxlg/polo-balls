extends "res://tests/test_minecraft_clouds.gd"
## Runs the existing cloud regression, then measures actual pixel motion against
## each background shader and the summit's live Camera3D projection.
const THEMES = preload("res://scripts/effects/我的世界/地图背景主题.gd")
const MOTION_VIEW_SIZE := Vector2i(512,384)
const CAMERA_SCREEN_STEP:float = 100.0

func gpu_checks() -> void:
	await super.gpu_checks()
	if DisplayServer.get_name() == "headless": return
	await relative_motion_checks()
	await summit_motion_checks()
	print("CLOUD_PARALLAX_SCOPED_CHECKS_COMPLETE")

func motion_quad(view:SubViewport,material:Material) -> Polygon2D:
	var quad:=Polygon2D.new()
	# Covers every camera/zoom sample without moving/clipping the test geometry.
	quad.polygon = PackedVector2Array([Vector2(-8192,-8192),Vector2(8192,-8192),Vector2(8192,8192),Vector2(-8192,8192)])
	quad.material = material
	view.add_child(quad)
	return quad

func motion_transform(center:Vector2,zoom:float) -> Transform2D:
	return Transform2D(Vector2(zoom,0),Vector2(0,zoom),Vector2(MOTION_VIEW_SIZE)*0.5-center*zoom)

func translation_errors(before:Image,after:Image,shift:Vector2i) -> Vector2i:
	var compared:int = 0
	var different:int = 0
	for y:int in range(12,after.get_height()-12,5):
		for x:int in range(12,after.get_width()-12,5):
			var p:=Vector2i(x,y)
			var q:Vector2i = p+shift
			if q.x<12 or q.y<12 or q.x>=before.get_width()-12 or q.y>=before.get_height()-12: continue
			compared += 1
			if after.get_pixelv(p)!=before.get_pixelv(q): different += 1
	return Vector2i(compared,different)

func save_motion_image(image:Image,name:String,hdr:bool = false) -> void:
	var folder:String = OS.get_environment("CLOUD_PARALLAX_ARTIFACTS")
	if folder.is_empty(): return
	DirAccess.make_dir_recursive_absolute(folder)
	var copy:Image = image.duplicate()
	copy.convert(Image.FORMAT_RGBA8)
	if hdr: copy.linear_to_srgb()
	copy.save_png(folder.path_join(name+".png"))

func relative_motion_checks() -> void:
	var sky:SubViewport = capture_view(MOTION_VIEW_SIZE,false)
	var background:SubViewport = capture_view(MOTION_VIEW_SIZE,false)
	var sky_quad:Polygon2D = motion_quad(sky,null)
	var background_quad:Polygon2D = motion_quad(background,null)
	var start_center:=Vector2(256,192)
	var old_travel:float = cloud.travel
	for style:String in ["blue","grass","sand","stone","nether","end"]:
		game.set_runtime_game_setting("Map_Background",style,false)
		world._update_map_outside_grid_parallax()
		var cloud_material:ShaderMaterial = cloud.cloud_material.duplicate()
		var background_material:ShaderMaterial = world.map_outside_grid_material.duplicate()
		sky_quad.material = cloud_material
		background_quad.material = background_material
		cloud_material.set_shader_parameter("travel",0.0)
		background_material.set_shader_parameter("viewport_size",Vector2(MOTION_VIEW_SIZE))
		var cloud_ratio:float = cloud_material.get_shader_parameter("parallax")
		var background_ratio:float = background_material.get_shader_parameter("parallax_scale")
		check(is_equal_approx(cloud_ratio,1.25) and cloud_ratio>background_ratio,"runtime cloud motion exceeds the unchanged background: "+style)
		check(is_equal_approx(background_ratio,float(THEMES.theme(style).get("grid_parallax"))),"background motion itself is not slowed to fake the cloud improvement: "+style)
		for zoom:float in [0.5,1.0,2.0]:
			background_material.set_shader_parameter("camera_zoom",Vector2.ONE*zoom)
			for axis:Vector2 in [Vector2.RIGHT,Vector2.DOWN]:
				sky.canvas_transform = motion_transform(start_center,zoom)
				background.canvas_transform = sky.canvas_transform
				background_material.set_shader_parameter("camera_position",start_center)
				await _frame()
				var sky_before:Image = sky.get_texture().get_image()
				var background_before:Image = background.get_texture().get_image()
				var moved_center:Vector2 = start_center+axis*CAMERA_SCREEN_STEP/zoom
				sky.canvas_transform = motion_transform(moved_center,zoom)
				background.canvas_transform = sky.canvas_transform
				background_material.set_shader_parameter("camera_position",moved_center)
				await _frame()
				var sky_after:Image = sky.get_texture().get_image()
				var background_after:Image = background.get_texture().get_image()
				var cloud_shift:Vector2i = Vector2i((axis*CAMERA_SCREEN_STEP*cloud_ratio).round())
				var background_shift:Vector2i = Vector2i((axis*CAMERA_SCREEN_STEP*background_ratio).round())
				var cloud_match:Vector2i = translation_errors(sky_before,sky_after,cloud_shift)
				var background_match:Vector2i = translation_errors(background_before,background_after,background_shift)
				var wrong_cloud_shift:Vector2i = translation_errors(sky_before,sky_after,background_shift)
				var label:String = "%s zoom=%.1f axis=%s" % [style,zoom,str(axis)]
				check(cloud_match.x>1000 and cloud_match.y==0,"GPU cloud pixels move 125px per 100px camera pan: "+label)
				check(background_match.x>1000 and background_match.y==0,"GPU background pixels retain their smaller displacement: "+label)
				check(cloud_shift.length()>background_shift.length() and wrong_cloud_shift.y>100,"GPU cloud image does not merely follow the background: "+label)
				print("CLOUD_RELATIVE_MOTION ",label," cloud=",cloud_shift," background=",background_shift," cloud_samples=",cloud_match," background_samples=",background_match)
				if style=="grass" and is_equal_approx(zoom,1.0) and axis==Vector2.RIGHT:
					save_motion_image(sky_before,"cloud_pan_before")
					save_motion_image(sky_after,"cloud_pan_after")
					save_motion_image(background_before,"background_pan_before")
					save_motion_image(background_after,"background_pan_after")
	# A second viewport shares the same material/canvas, but has its own camera.
	var independent:SubViewport = capture_view(MOTION_VIEW_SIZE,false)
	independent.world_2d = sky.world_2d
	sky.canvas_transform = motion_transform(start_center,1.0)
	independent.canvas_transform = motion_transform(start_center+Vector2(80,40),0.5)
	await _frame()
	var main_before:Image = sky.get_texture().get_image()
	var other_before:Image = independent.get_texture().get_image()
	sky.canvas_transform = motion_transform(start_center+Vector2(100,-100),1.0)
	await _frame()
	check(other_before.get_data()==independent.get_texture().get_image().get_data(),"panning one viewport does not drag independently centered recording/overview clouds")
	check(main_before.get_data()!=sky.get_texture().get_image().get_data(),"the moved viewport actually changes its own cloud image")
	check(is_equal_approx(cloud.travel,old_travel),"camera parallax does not accelerate the cloud's natural drift clock")
	independent.queue_free()
	sky.queue_free()
	background.queue_free()
	await process_frame

func summit_motion_checks() -> void:
	game.set_runtime_game_setting("Map_Background","summit",false)
	var volume:Node = world.map_wall_volume
	var camera:=Camera2D.new()
	world.add_child(camera)
	camera.position_smoothing_enabled = false
	camera.make_current()
	var center:Vector2 = world.return_map_world_rect(world._current_map_node()).get_center()
	check(is_instance_valid(volume.background_camera) and volume.summit_arena.mountain_highest_y<0.0,"measure the real summit scenery camera and the nearest mountain height, not a guessed background coefficient")
	var peak:=Vector3(center.x,volume.summit_arena.mountain_highest_y,center.y)
	var cloud_ratio:float = cloud.cloud_material.get_shader_parameter("parallax")
	for zoom:float in [0.5,1.0,2.0]:
		camera.zoom = Vector2.ONE*zoom
		for axis:Vector2 in [Vector2.RIGHT,Vector2.DOWN]:
			camera.global_position = center
			camera.force_update_scroll()
			await _frame()
			var before:Vector2 = volume.background_camera.unproject_position(peak)/volume._render_scale
			if is_equal_approx(zoom,1.0) and axis==Vector2.RIGHT:
				save_motion_image(root.get_texture().get_image(),"summit_pan_before",root.use_hdr_2d)
			camera.global_position = center+axis*CAMERA_SCREEN_STEP/zoom
			camera.force_update_scroll()
			await _frame()
			var after:Vector2 = volume.background_camera.unproject_position(peak)/volume._render_scale
			var background_pixels:float = before.distance_to(after)
			var cloud_pixels:float = CAMERA_SCREEN_STEP*cloud_ratio
			check(background_pixels>0.1 and cloud_pixels>background_pixels,"cloud pan exceeds even the nearest summit mountain projection: zoom %.1f axis %s" % [zoom,str(axis)])
			check((after-before).dot(axis)<0.0,"cloud and summit scenery move opposite the camera, not in reversed directions")
			print("CLOUD_SUMMIT_MOTION zoom=",zoom," axis=",axis," cloud=",cloud_pixels," nearest_mountain=",background_pixels)
			if is_equal_approx(zoom,1.0) and axis==Vector2.RIGHT:
				save_motion_image(root.get_texture().get_image(),"summit_pan_after",root.use_hdr_2d)
	check(volume.background_picture.z_index<cloud.z_index and cloud.z_index<volume.z_index,"stronger parallax preserves mountain < cloud < arena occlusion")
	world.camera_2d.make_current()
	camera.queue_free()
	game.set_runtime_game_setting("Map_Background","blue",false)
	await process_frame
