extends "res://tests/test_mc_new6_load.gd"
# Real project window and its original Camera2D. Never disable canvas_items
# stretching or substitute a 3x preview camera to make the effect visible.
var rift: Node2D
var shot_center: Vector2
var capture_names: Array[String] = []

func frame() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func delta_count(a: Image, b: Image, area: Rect2i) -> int:
	var bounds: Rect2i=area.intersection(Rect2i(Vector2i.ZERO,a.get_size()))
	var n: int=0
	for y in range(bounds.position.y,bounds.end.y):
		for x in range(bounds.position.x,bounds.end.x):
			var p:Color=a.get_pixel(x,y)
			var q:Color=b.get_pixel(x,y)
			if maxf(maxf(absf(p.r-q.r),absf(p.g-q.g)),absf(p.b-q.b))>0.01:n+=1
	return n

func effect_pixels() -> Rect2i:
	var transform:Transform2D=root.get_stretch_transform()*rift.get_global_transform_with_canvas()
	var bounds:Rect2=transform*rift._copy_bounds
	return Rect2i(bounds.position.floor(),bounds.size.ceil()).grow(3)

func save_capture(image:Image,name:String) -> void:
	if root.use_hdr_2d:
		for y in range(image.get_height()):
			for x in range(image.get_width()):image.set_pixel(x,y,image.get_pixel(x,y).linear_to_srgb())
	image.convert(Image.FORMAT_RGBA8)
	check(image.save_png("user://"+name)==OK,"default-view actual capture saved")
	capture_names.append(name)

func check_view(label:String,camera_position:Vector2,zoom:Vector2,capture:String="") -> void:
	# World.process_always is driven externally even if set_process(false).
	# Exercise real pan/toolbar controls instead of fighting that controller.
	game.Game_Settings.Camera_Move=false
	world.mouse_offset=camera_position-world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	world.toolbar_zoom_multiplier=zoom.x/maxf(world._base_camera_zoom_value(),0.001)
	world.process_always(0.0)
	world.camera_2d.global_position=camera_position
	world.camera_2d.zoom=zoom
	world.camera_2d.make_current()
	world.camera_2d.force_update_scroll()
	await physics_frame
	await physics_frame
	world.camera_2d.force_update_scroll()
	await process_frame
	rift._surface.visible=false
	rift._space_warp.visible=false
	rift._space_copy.copy_mode=BackBufferCopy.COPY_MODE_DISABLED
	var empty:Image=await frame()
	check(world.camera_2d.global_position.is_equal_approx(camera_position) and world.camera_2d.zoom.is_equal_approx(zoom),label+": actual gameplay camera reaches the requested pose")
	rift._surface.visible=true
	var core:Image=await frame()
	var core_transform:Transform2D=rift.get_global_transform_with_canvas()
	var region:Rect2i=effect_pixels()
	var visible_pixels:int=delta_count(empty,core,region)
	check(visible_pixels>10,label+": openings render without moving to a special camera location")
	var all_visible:bool=true
	var transform:Transform2D=root.get_stretch_transform()*rift.get_global_transform_with_canvas()
	for crack:Dictionary in rift._cached_cracks:
		var path:PackedVector2Array=crack["points"]
		if int(crack["id"])!=rift.CENTER_ID and path[0].distance_to(rift._points[0])>0.01:
			continue # tiny secondary hairs are part of an arm, not separate openings
		var samples:Array=crack["samples"]
		var bounds:=Rect2(transform*(samples[0]["p"] as Vector2),Vector2.ZERO)
		for sample:Dictionary in samples:bounds=bounds.expand(transform*(sample["p"] as Vector2))
		var cut_area:=Rect2i(bounds.position.floor(),bounds.size.ceil()).grow(3)
		if delta_count(empty,core,cut_area)<2:all_visible=false
	check(all_visible,label+": connected opening and major arms are visible")
	rift._space_warp.visible=true
	rift._space_copy.copy_mode=BackBufferCopy.COPY_MODE_RECT
	rift._warp_material.set_shader_parameter("warp_strength",0.0)
	var identity:Image=await frame()
	var lost:int=delta_count(core,identity,region)
	if lost>0:print("COPY_DEBUG ",label," core_xf=",core_transform," copy_xf=",rift.get_global_transform_with_canvas()," rect=",rift._space_copy.rect," stretch=",root.get_stretch_transform())
	check(lost==0,label+": partial copy preserves the scene under window stretching")
	rift._warp_material.set_shader_parameter("warp_strength",rift.WARP_STRENGTH)
	var active:Image=await frame()
	check(delta_count(empty,active,region)>10,label+": actual distortion does not erase the openings")
	print("DEFAULT_VISIBILITY ",label,": window=",root.size," zoom=",zoom," image=",core.get_size()," visible_pixels=",visible_pixels," lost_pixels=",lost)
	if not capture.is_empty():save_capture(active,capture)

func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	saved_stop=game.now_stop_state
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(120.0,true,false,true).timeout.connect(func(): finish(2))
	var rift_script:Script=load("res://scripts/characters/我的世界/new6/heavenfall_rift.gd")
	if not rift_script.can_instantiate():
		check(false,"rift script compiles")
		quit(1)
		return
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.control.hide()
	await create_timer(0.5).timeout
	var original_map:String=world.now_choose_map
	var rect:Rect2=world.return_map_world_rect(world.map_group[original_map])
	shot_center=rect.get_center()
	var bow:Node2D=spawn("res://scenes/characters/我的世界/天堂陨落长弓.tscn",shot_center+Vector2(-55,0))
	bow.state_machine.set_physics_process(false)
	bow.set_physics_process(false)
	await create_timer(0.2).timeout
	world.set_process(false)
	world.set_physics_process(false)
	bow.set_process(false)
	game.now_stop_state=true
	world.camera_2d.position_smoothing_enabled=false
	world.camera_2d.reset_smoothing()
	world.camera_2d.force_update_scroll()
	await process_frame
	var original_camera:Vector2=world.camera_2d.global_position
	var original_zoom:Vector2=world.camera_2d.zoom
	bow.rng.seed=317
	bow.spawn_heaven_rift(shot_center,Vector2.RIGHT)
	rift=_rifts().back()
	rift.set_process(false)
	rift._age=0.4
	rift._sync_visual()
	await check_view("project_default",original_camera,original_zoom,"heavenfall_connected_default.png")
	await check_view("default_pan_left",original_camera+Vector2(-20,15),original_zoom)
	await check_view("default_pan_right",original_camera+Vector2(20,-15),original_zoom)
	await check_view("default_zoom_out",original_camera,original_zoom*0.65)
	# Larger arena, using World's own fit calculation and the SAME real camera.
	rift.queue_free()
	await process_frame
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.toolbar_zoom_multiplier=1.0
	world.mouse_offset=Vector2.ZERO
	world._apply_camera_zoom()
	rect=world.return_map_world_rect(world.map_group["Map50x50"])
	shot_center=rect.get_center()
	bow.global_position=shot_center+Vector2(-55,0)
	var map_zoom:Vector2=world.camera_2d.zoom
	bow.rng.seed=416
	bow.spawn_heaven_rift(shot_center,Vector2.RIGHT)
	rift=_rifts().back()
	rift.set_process(false)
	rift._age=0.4
	rift._sync_visual()
	await check_view("large_map_fit",shot_center,map_zoom,"heavenfall_connected_large_map.png")
	await check_view("large_map_pan",shot_center+Vector2(105,-80),map_zoom)
	await check_view("large_map_zoom_out",shot_center,map_zoom*0.65)
	await check_view("large_map_zoom_in",shot_center,map_zoom*1.8)
	root.size=Vector2i(720,1280)
	await process_frame
	await check_view("resized_portrait",shot_center,map_zoom)
	root.size=Vector2i(960,640)
	await process_frame
	await check_view("landscape_stretch",shot_center,map_zoom)
	print("HEAVENFALL DEFAULT VIEW RESULT: %d/%d passed" % [checks-failures,checks])
	print("DEFAULT_CAPTURES: ",capture_names)
	finish(0 if failures==0 else 1)
