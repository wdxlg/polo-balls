extends SceneTree
var checks:int=0
var failures:int=0

func _initialize() -> void:
	_run.call_deferred()

func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error("DAY_NIGHT_VISUAL FAIL: "+label)
	else: print("PASS: ",label)

func _frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw

func _sample(image:Image,screen:Vector2,logical:Vector2) -> Color:
	var point:Vector2i = Vector2i(screen*Vector2(image.get_size())/logical)
	point.x=clampi(point.x,1,image.get_width()-2)
	point.y=clampi(point.y,1,image.get_height()-2)
	var color:Color=Color(0,0,0,0)
	for y:int in range(-1,2):
		for x:int in range(-1,2): color+=image.get_pixel(point.x+x,point.y+y)
	return color/9.0

func _luma(c:Color) -> float:
	return (c.r+c.g+c.b)/3.0

func _world_sample(image:Image,point:Vector2,view:Viewport) -> float:
	return _luma(_sample(image,view.get_canvas_transform()*point,view.get_visible_rect().size))

func _save(image:Image,path:String) -> void:
	var picture:Image=image.duplicate()
	picture.convert(Image.FORMAT_RGBA8)
	if root.use_hdr_2d: picture.linear_to_srgb()
	check(picture.save_png(path)==OK,"saved "+path.get_file())

func _run() -> void:
	create_timer(115.0,true,false,true).timeout.connect(func():quit(2))
	var game:Node=root.get_node("Game")
	var old:Dictionary=game.Game_Settings.duplicate(true)
	var old_stop:bool=game.now_stop_state
	game.Game_Settings.Map_Background="grass"
	game.Game_Settings.Training_Mode=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	var world:Node=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map10x10"
	world.refresh_map_presentation()
	world.control.hide()
	var cycle:Node2D=world.day_night_cycle
	cycle.advancing=false
	var physical:Rect2=world.map_island_rects(world.map_group["Map10x10"])[0]
	var cell:Vector2=world.map_visual_cell_size(world.map_group["Map10x10"])
	var camera:=Camera2D.new()
	world.add_child(camera)
	camera.make_current()
	camera.zoom=Vector2.ONE*3.8
	camera.global_position=physical.get_center()
	# 显式测一块 unshaded 内容，防止仅 CanvasModulate 而实际背景不变暗。
	var swatch:=Polygon2D.new()
	swatch.polygon=PackedVector2Array([Vector2(-8,-8),Vector2(8,-8),Vector2(8,8),Vector2(-8,8)])
	swatch.position=physical.get_center()+Vector2(0,cell.y*2)
	swatch.z_index=40
	var shader:=Shader.new()
	shader.code="shader_type canvas_item; render_mode unshaded; void fragment(){ COLOR=vec4(0.8,0.5,0.2,1.0); }"
	var material:=ShaderMaterial.new()
	material.shader=shader
	swatch.material=material
	world.add_child(swatch)
	var ui_probe:=ColorRect.new()
	ui_probe.color=Color(0.7,0.7,0.7)
	ui_probe.position=Vector2(24,100)
	ui_probe.size=Vector2(50,50)
	ui_probe.mouse_filter=Control.MOUSE_FILTER_IGNORE
	world.get_node("CanvasLayer").add_child(ui_probe)
	var capture:=SubViewport.new()
	capture.name="DayNightSharedWorldCapture"
	capture.size=Vector2i(540,960)
	capture.world_2d=root.world_2d
	capture.use_hdr_2d=root.use_hdr_2d
	capture.canvas_cull_mask=1
	capture.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(capture)
	await _frame()
	capture.canvas_transform=Transform2D(Vector2(0.5,0),Vector2(0,0.5),Vector2.ZERO)*root.get_canvas_transform()
	var folder:String="user://day_night_cycle"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var floor_point:Vector2=physical.get_center()
	var outside_point:Vector2=Vector2(physical.get_center().x,physical.position.y-cell.y*3.0)
	var noon_floor:float=0.0
	var noon_outside:float=0.0
	var noon_unshaded:float=0.0
	var noon_ui:Color
	var noon_capture:float=0.0
	var dusk_floor:float=0.0
	var midnight_floor:float=0.0
	var mesh_id:int=world.map_wall_volume.mesh_node.mesh.get_instance_id()
	for minute:int in [720,1080,0,390,480]:
		cycle.set_minutes(float(minute))
		await _frame()
		var image:Image=root.get_texture().get_image()
		cycle.clock_label.hide()
		await _frame()
		var without_clock:Image=root.get_texture().get_image()
		var rect:Rect2=cycle.clock_label.get_global_rect()
		var pixel_scale:Vector2=Vector2(image.get_size())/root.get_visible_rect().size
		var area:Rect2i=Rect2i(rect.position*pixel_scale,rect.size*pixel_scale).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
		var clock_pixels:int=0
		for y:int in range(area.position.y,area.end.y):
			for x:int in range(area.position.x,area.end.x):
				if absf(_luma(image.get_pixel(x,y))-_luma(without_clock.get_pixel(x,y)))>0.12: clock_pixels+=1
		check(clock_pixels>8,"%s clock text actually visible at top right" % cycle.time_text())
		check(is_equal_approx(rect.position.y,24.0) and is_equal_approx(root.get_visible_rect().size.x-rect.end.x,24.0),"clock keeps 24px top/right inset")
		print("DAY_NIGHT_CLOCK rect=",rect," visible_pixels=",clock_pixels)
		cycle.clock_label.show()
		await _frame()
		var recorded:Image=capture.get_texture().get_image()
		var floor_luma:float=_world_sample(image,floor_point,root)
		var ui:Color=_sample(image,Vector2(48,124),root.get_visible_rect().size)
		var capture_luma:float=_world_sample(recorded,floor_point,capture)
		if minute==720:
			noon_floor=floor_luma
			noon_outside=_world_sample(image,outside_point,root)
			noon_unshaded=_world_sample(image,swatch.global_position,root)
			noon_ui=ui
			noon_capture=capture_luma
		elif minute==1080:
			dusk_floor=floor_luma
			check(dusk_floor<noon_floor*0.92,"18:00 floor is visibly dimmer than noon")
		elif minute==0:
			midnight_floor=floor_luma
			check(midnight_floor<dusk_floor*0.85 and midnight_floor>noon_floor*0.1,"midnight is darker than dusk but battle remains visible")
			check(_world_sample(image,outside_point,root)<noon_outside*0.75,"real unshaded outside background also becomes night")
			check(_world_sample(image,swatch.global_position,root)<noon_unshaded*0.75,"unshaded characters/effects are included by world tint")
			check(capture_luma<noon_capture*0.75 and capture_luma>noon_capture*0.1,"shared World2D recording-style viewport receives the same night, no extra clock tick")
			check(cycle.time_text()=="00:00","main and extra GPU viewports do not advance frozen time")
		elif minute==390:
			check(floor_luma>midnight_floor*1.1 and floor_luma<noon_floor*0.95,"06:30 sunrise brightens gradually")
		elif minute==480:
			check(absf(floor_luma-noon_floor)<0.02,"08:00 restores original daytime floor brightness")
		check(absf(ui.r-noon_ui.r)<0.002 and absf(ui.g-noon_ui.g)<0.002,"%s UI stays readable and undimmed" % cycle.time_text())
		check(world.map_wall_volume.mesh_node.mesh.get_instance_id()==mesh_id,"%s light animation retains wall mesh" % cycle.time_text())
		var light:Vector3=world.map_wall_volume.sun_light.global_basis.z
		check(Vector2(light.x,light.z).normalized().distance_to(world.map_wall_light_direction)<0.001,"%s real 3D sun follows clock direction" % cycle.time_text())
		print("DAY_NIGHT_PIXEL time=",cycle.time_text()," floor=",floor_luma," capture=",capture_luma)
		# 验证色块仅供断言，不进入用户预览图。
		swatch.hide()
		ui_probe.hide()
		await _frame()
		_save(root.get_texture().get_image(),folder+"/grass_%04d.png" % minute)
		swatch.show()
		ui_probe.show()
	for style:String in ["blue","sand","stone","nether","end"]:
		game.set_runtime_game_setting("Map_Background",style,false)
		world.refresh_map_presentation()
		cycle.set_minutes(720)
		await _frame()
		var day:float=_world_sample(root.get_texture().get_image(),floor_point,root)
		cycle.set_minutes(0)
		await _frame()
		var night:float=_world_sample(root.get_texture().get_image(),floor_point,root)
		check(night<day*0.75 and night>day*0.08,"%s floor participates in real GPU day/night" % style)
		if style=="blue": check(not world.map_wall_volume.visible,"blue remains flat at midnight")
	game.Game_Settings=old
	game.now_stop_state=old_stop
	capture.render_target_update_mode=SubViewport.UPDATE_DISABLED
	capture.queue_free()
	world.queue_free()
	await _frame()
	print("DAY_NIGHT_VISUAL checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
