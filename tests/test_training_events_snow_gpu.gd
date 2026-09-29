extends "res://tests/test_training_events_snow.gd"
## Real GPU: empty start, native snowfall, wall-top 3D cuboids and Settings UI.
var capture_dir:String
var hidden_layers:Dictionary = {}

func grab(name:String = "",settle_frames:int = 2) -> Image:
	for i:int in range(settle_frames):
		await process_frame
		if done: return Image.new()
		# Explicit GPU draw: a paused/occluded window may not emit another post_draw.
		# This renders the actual viewport without advancing combat or melt time.
		RenderingServer.force_draw(false)
	var image:Image = root.get_texture().get_image()
	if not name.is_empty(): image.save_png(capture_dir+"/"+name+".png")
	return image
func gap(a:Color,b:Color) -> float: return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))
func changed_in(rect:Rect2,before:Image,after:Image,transform:Transform2D) -> int:
	var a:Vector2 = transform*rect.position
	var z:Vector2 = transform*rect.end
	var low:=Vector2i(a.min(z).ceil())
	var high:=Vector2i(a.max(z).floor())
	var result:int = 0
	for y:int in range(maxi(0,low.y),mini(before.get_height(),high.y)):
		for x:int in range(maxi(0,low.x),mini(before.get_width(),high.x)):
			if gap(before.get_pixel(x,y),after.get_pixel(x,y))>0.09: result+=1
	return result

func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("This suite requires a real GPU renderer")
		quit(2)
		return
	root.size = Vector2i(1000,720)
	root.content_scale_size = root.size
	game = root.get_node("Game")
	original_settings = game.Game_Settings.duplicate(true)
	original_locale = game.current_locale
	settings_file = game.SETTINGS_PATH
	settings_existed = FileAccess.file_exists(settings_file)
	if settings_existed: settings_bytes = FileAccess.get_file_as_bytes(settings_file)
	game.Game_Settings.Environment = "none"
	game.Game_Settings.Random_Events = false
	game.Game_Settings.Development_Mode = false
	game.Game_Settings.Only_In_Game_Translation = false
	game.Game_Settings.Minecraft_Clouds = false
	game.Game_Settings.Map_Background = "blue"
	await setup_world()
	saved = original_settings
	capture_dir = OS.get_environment("TRAINING_SNOW_CAPTURE_DIR")
	if capture_dir.is_empty(): capture_dir = "user://training_snow_gpu"
	DirAccess.make_dir_recursive_absolute(capture_dir)
	create_timer(240,true,false,true).timeout.connect(func():finish(2))
	conditions = world.battle_conditions
	conditions.set_physics_process(false)
	world.versus_label.hide()
	for layer:CanvasLayer in world.find_children("*","CanvasLayer",true,false):
		hidden_layers[layer] = layer.visible
		layer.visible = false
	var camera:=Camera2D.new()
	world.add_child(camera)
	camera.zoom = Vector2(4,4)
	camera.make_current()
	var actor:Node2D = spawn(GOLEM_PATH,Vector2.ZERO)
	actor.health_bar.hide()
	actor.motion_blur_enabled = false
	var field:Node2D = actor._field
	field.set_physics_process(false)
	if OS.get_environment("SNOW_CAPTURE_ONSET_ONLY")=="1":
		await capture_random_weather(camera,field)
		print("TRAINING_SNOW_ONSET checks=",checks," failures=",failures)
		await finish(0 if failures==0 else 1)
		return
	for style:String in ["blue","grass","sand","stone","nether","end","summit"]:
		setting("Map_Background",style)
		setting("Environment","snow")
		conditions.refresh_layout(true)
		await physics_frame
		await physics_frame
		await process_frame
		field = conditions.field
		check(field.environment_patches.is_empty() and field.wall_view.weather_time==0.0,style+" starts empty before the controlled geometry probe")
		field.set_physics_process(false)
		field.clear_environment()
		field.patches.clear()
		field.queue_redraw()
		var wall:Rect2
		for rect:Rect2 in conditions._walls:
			if rect.size.x>96 and (not wall.has_area() or rect.position.y<wall.position.y): wall = rect
		check(wall.has_area(),style+" exposes real rendered wall geometry")
		if not wall.has_area(): continue
		var cell_size:Vector2 = field.grid_size
		var x_center:float = field.snow_point_at(field.snow_cell_at(wall.get_center())).x
		var floor_y:float = field.snow_point_at(field.snow_cell_at(Vector2(x_center,wall.end.y+cell_size.y))).y
		camera.global_position = Vector2(x_center,floor_y+8)
		camera.reset_smoothing()
		actor.global_position = Vector2(x_center,floor_y+cell_size.y)
		var wall_rects:Array[Rect2] = []
		var floor_rects:Array[Rect2] = []
		for i:int in range(-3,4):
			var cell:Vector2i = field.snow_cell_at(Vector2(x_center+i*cell_size.x,wall.get_center().y))
			var square:Rect2 = field.snow_tile_at(cell)
			var clipped:Rect2 = square.intersection(wall)
			if clipped.has_area():
				wall_rects.append(clipped)
				field.add_environment_patch(conditions,{"cell":cell,"decorative":true,"tile":square,"rects":[clipped]})
			for row:int in range(3):
				var floor_cell:Vector2i = field.snow_cell_at(Vector2(x_center+i*cell_size.x,floor_y+row*cell_size.y))
				var footprint:Rect2 = field.snow_tile_at(floor_cell)
				var footprint_list:Array[Rect2] = [footprint]
				if not conditions.GEOMETRY.subtract(footprint_list,conditions._ground).is_empty(): continue
				floor_rects.append(footprint)
				field.add_environment_patch(conditions,{"cell":floor_cell,"decorative":false,"tile":footprint,"rects":[footprint]})
		game.now_stop_state = true
		actor.image.hide()
		field.hide()
		var empty:Image = await grab(style+"_bare_probe")
		actor.image.show()
		var actor_only:Image = await grab()
		actor.image.hide()
		field.show()
		var snow_only:Image = await grab(style+"_snow_only")
		actor.image.show()
		var together:Image = await grab(style+"_snow_and_golem")
		var transform:Transform2D = field.get_global_transform_with_canvas()
		var wall_pixels:int = 0
		var ground_pixels:int = 0
		var view:Node2D = field.wall_view
		check(is_instance_valid(view.mesh_node) and view.mesh_node.mesh.get_surface_count()==1,style+" wall snow is a genuine shared ArrayMesh, not a painted 2D rectangle")
		if not is_instance_valid(view.mesh_node): continue
		var box:AABB = view.mesh_node.mesh.get_aabb()
		check(is_equal_approx(box.size.y,FIELD.CELL*2.0/16.0) and is_equal_approx(box.position.y,view.renderer.block_height),style+" native 2/16 snow layer sits exactly on the wall top")
		var material:StandardMaterial3D = view.mesh_node.mesh.surface_get_material(0)
		check(material.albedo_texture==view.NATIVE_SNOW and not material.emission_enabled,style+" snow uses original Minecraft texture and real lighting, without emission")
		if style!="blue":
			check(view.renderer==world.map_wall_volume and view.mesh_node.get_parent()==world.map_wall_volume.viewport,style+" wall snow shares the actual wall camera, World3D and lights")
		wall_pixels = changed_in(projected_snow_bounds(view),empty,snow_only,Transform2D.IDENTITY)
		for rect:Rect2 in floor_rects: ground_pixels += changed_in(rect,empty,snow_only,transform)
		print("SNOW_GPU style=",style," wall_pixels=",wall_pixels," ground_pixels=",ground_pixels," wall_z=",field.wall_view.z_index)
		check(wall_pixels>40,style+" raised snow has visible pixels at its actual 3D projected location")
		check(ground_pixels>400,style+" floor uses visible native snow patches")
		var face:Rect2 = wall_rects[wall_rects.size()/2]
		var top:Vector2 = snow_project(view,Vector3(face.get_center().x,view.snow_base_height+view.snow_thickness,wall.get_center().y))
		var side:Vector2 = snow_project(view,Vector3(face.get_center().x,view.snow_base_height+view.snow_thickness*0.5,wall.end.y))
		var top_color:Color = pixel_at(snow_only,top)
		var side_color:Color = pixel_at(snow_only,side)
		print("SNOW_3D_FACE style=",style," top=",top_color," side=",side_color," side_pixel=",side," bare_side=",pixel_at(empty,side))
		check(gap(pixel_at(empty,side),side_color)>0.08 and top_color.get_luminance()>side_color.get_luminance()+0.025,style+" true vertical snow face is visible and shaded differently from its top")
		var center:=Vector2i(actor.get_global_transform_with_canvas().origin.round())
		var tested:int = 0
		var retained:int = 0
		for y:int in range(maxi(0,center.y-60),mini(empty.get_height(),center.y+60)):
			for x:int in range(maxi(0,center.x-45),mini(empty.get_width(),center.x+45)):
				if gap(actor_only.get_pixel(x,y),empty.get_pixel(x,y))>0.35:
					tested+=1
					if gap(actor_only.get_pixel(x,y),together.get_pixel(x,y))<0.09: retained+=1
		check(tested>50 and float(retained)/maxi(tested,1)>0.85,style+" real golem pixels remain above ground snow")
		var snapshot:Dictionary = field.environment_patches.duplicate(true)
		field.advance(120)
		check(field.environment_patches==snapshot,style+" pause preserves the age of rendered snow")
		game.now_stop_state = false
	await check_local_replica_style(field)
	await capture_random_weather(camera,field)
	await check_ui_capture()
	print("TRAINING_SNOW_GPU checks=",checks," failures=",failures," renderer=",RenderingServer.get_current_rendering_method())
	await finish(0 if failures==0 else 1)

func check_ui_capture() -> void:
	root.size = Vector2i(480,800)
	root.content_scale_size = root.size
	game.now_stop_state = true
	for layer:CanvasLayer in hidden_layers:
		if is_instance_valid(layer): layer.visible = bool(hidden_layers[layer])
	world.control.show()
	var ui:Control = world.control
	ui.game_setting.show()
	setting("Random_Events",true)
	ui._show_settings_category("training")
	for locale:String in ["zh","en"]:
		game.set_language(locale,false)
		for i:int in range(8): await process_frame
		var panel:Control = ui.game_setting.get_node("Panel")
		var content:Rect2 = ui.settings_stack.get_global_rect()
		var scroll:Rect2 = ui.settings_scroll.get_global_rect()
		var condition_ui:Control = ui.settings_category_boxes.training.get_node("BattleConditionsSettings")
		check(scroll.end.x<=panel.get_global_rect().end.x+1,locale+" training scroll fits the existing panel")
		check(content.end.x<=scroll.end.x+1,locale+" settings content has no horizontal overflow")
		check(condition_ui.environment_option.get_global_rect().end.x<=scroll.end.x+1,locale+" Environment dropdown fits the settings width")
		ui.settings_scroll.ensure_control_visible(condition_ui.environment_option)
		for i:int in range(3): await process_frame
		await grab("settings_"+locale)

func check_local_replica_style(field:Node2D) -> void:
	game.now_stop_state = true
	var authoritative_cells:Dictionary = field.environment_patches.duplicate(true)
	conditions.set_multiplayer_authority(2)
	setting("Map_Background","blue")
	conditions.refresh_layout()
	check(field.environment_patches==authoritative_cells,"client-only background style never replaces authoritative snow cells")
	await process_frame
	await RenderingServer.frame_post_draw
	check(is_instance_valid(field.wall_view.renderer) and field.wall_view.renderer.z_index==world.map_border_segment_root.z_index+1,"replica uses a real 3D snow-only renderer above the unchanged local blue frame")
	var pieces:Array[Rect2] = []
	for cell:Vector2i in field.environment_patches:
		var record:Dictionary = field.environment_patches[cell]
		if not record.decorative: continue
		for item:Dictionary in field.wall_view.projected_pieces(cell,record): pieces.append(item.rect)
	check(not pieces.is_empty() and conditions.GEOMETRY.subtract(pieces,field.wall_view.visual_walls).is_empty(),"replicated tiled-wall decoration is clipped to the client's thin local walls")
	field.hide()
	var without:Image = await grab()
	field.show()
	var with_snow:Image = await grab("replica_local_blue")
	var pixels:int = 0
	pixels = changed_in(projected_snow_bounds(field.wall_view),without,with_snow,Transform2D.IDENTITY)
	check(pixels>40,"client-style projection renders raised native snow rather than flat painted wall data")
	conditions.set_multiplayer_authority(1)

func snow_project(view:Node2D,point:Vector3) -> Vector2:
	return view.renderer.picture.get_global_transform_with_canvas()*(view.renderer.camera as Camera3D).unproject_position(point)

func projected_snow_bounds(view:Node2D) -> Rect2:
	var box:AABB = view.mesh_node.mesh.get_aabb()
	var bounds:=Rect2(snow_project(view,box.position),Vector2.ZERO)
	for i:int in range(8): bounds = bounds.expand(snow_project(view,box.get_endpoint(i)))
	return bounds.grow(2.0)

func pixel_at(image:Image,point:Vector2) -> Color:
	return image.get_pixel(clampi(roundi(point.x),0,image.get_width()-1),clampi(roundi(point.y),0,image.get_height()-1))

func capture_random_weather(camera:Camera2D,_field:Node2D) -> void:
	setting("Map_Background","grass")
	setting("Environment","snow")
	conditions.refresh_layout(true)
	await physics_frame
	await physics_frame
	game.now_stop_state = true
	var field:Node2D = conditions.field
	var view:Node2D = field.wall_view
	camera.global_position = world.return_map_world_rect(world._current_map_node()).get_center()
	camera.zoom = Vector2(0.7,0.7)
	camera.reset_smoothing()
	var bare:Image = await grab("weather_00_empty")
	check(field.environment_patches.is_empty() and not is_instance_valid(view.mesh_node),"actual first GPU frame has no preplaced ground or 3D wall snow")
	game.now_stop_state = false
	conditions.advance(1.0)
	field.advance(1.0)
	game.now_stop_state = true
	var first:Image = await grab("weather_01_falling")
	var whole:=Rect2(Vector2.ZERO,Vector2(root.size))
	var falling_pixels:int = changed_in(whole,bare,first,Transform2D.IDENTITY)
	print("SNOWFALL_PIXELS ",falling_pixels)
	check(falling_pixels>700 and field.environment_patches.is_empty(),"native Minecraft snowfall is visibly falling before any ground or wall accumulation")
	game.now_stop_state = false
	conditions.advance(0.25)
	field.advance(0.25)
	game.now_stop_state = true
	var moved:Image = await grab("weather_02_moved")
	check(changed_in(whole,first,moved,Transform2D.IDENTITY)>700,"original weather flakes actually move across rendered frames")
	var clock:float = view.weather_time
	conditions.advance(2.0)
	var frozen:Image = await grab()
	check(view.weather_time==clock and changed_in(whole,moved,frozen,Transform2D.IDENTITY)<30,"pause freezes the snowfall image, not only its damage or spawn counter")
	await check_shared_weather_view(view)
	# This sequence uses production combat-delta advancement; no injected snow cells.
	conditions.refresh_layout(true)
	var save_onset:bool = OS.get_environment("SNOW_CAPTURE_ONSET")=="1"
	if save_onset: DirAccess.make_dir_recursive_absolute(capture_dir+"/onset")
	if save_onset: await grab("onset/frame_000")
	for i:int in range(1,49):
		game.now_stop_state = false
		conditions.advance(0.1)
		field.advance(0.1)
		game.now_stop_state = true
		if save_onset: await grab("onset/frame_%03d" % i,1)
	check(field.environment_patches.size()>0 and view.weather_time>4.7,"after a bare start, actual elapsed battle time gradually deposits permanent snow")
	game.now_stop_state = false
	for i:int in range(36):
		conditions.advance(1.0)
		field.advance(1.0)
	game.now_stop_state = true
	await grab("random_weather_production")
	var retained:Dictionary = field.environment_patches.duplicate(true)
	camera.global_position += Vector2(61,-27)
	camera.zoom = Vector2(0.85,0.85)
	await grab("weather_camera_moved")
	check(field.environment_patches==retained,"camera movement/zoom affects weather appearance, not authoritative accumulated snow")
	world.day_night_cycle.set_minutes(0.0)
	await grab("weather_midnight")
	check(field.environment_patches==retained,"night lighting leaves accumulated snow and its gameplay unchanged")
	world.day_night_cycle.reset_to_noon()
	setting("Environment","none")
	await grab("weather_disabled")
	check(not view.weather_enabled and field.environment_patches==retained,"None stops falling weather but retains accumulated snow to melt")
	game.now_stop_state = false
	conditions.advance(view.WEATHER_FADE_SECONDS)
	field.advance(field.full_snow_lifetime+field.snow_fade_duration+0.1)
	game.now_stop_state = true
	await grab("weather_melted_after_off")
	check(field.environment_patches.is_empty() and not is_instance_valid(view.mesh_node),"natural expiry also releases all remaining raised snow meshes")
	var retained_weather_time:float = view.weather_time
	setting("Environment","snow")
	await grab("weather_reenabled_empty")
	check(field.environment_patches.is_empty() and view.weather_time==retained_weather_time and view.weather_fade==0.0,"re-enabling starts transparent without rewinding old snowflake positions")

func check_shared_weather_view(view:Node2D) -> void:
	var capture:=SubViewport.new()
	capture.name = "SnowfallSharedWorldRecordingProbe"
	capture.size = Vector2i(620,840)
	capture.world_2d = world.get_viewport().find_world_2d()
	capture.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var center:Vector2 = world.return_map_world_rect(world._current_map_node()).get_center()
	root.add_child(capture)
	capture.canvas_transform = Transform2D(0.0,Vector2(0.9,0.9),0.0,Vector2(capture.size)*0.5-center*0.9)
	view.weather_enabled = false
	view.weather_fade = 0.0 # Explicit bare-image fixture, not a gameplay toggle.
	view.queue_redraw()
	for i:int in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	var empty:Image = capture.get_texture().get_image()
	view.weather_enabled = true
	view.weather_fade = 1.0
	view.queue_redraw()
	for i:int in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	var snow:Image = capture.get_texture().get_image()
	snow.save_png(capture_dir+"/weather_shared_portrait.png")
	check(changed_in(Rect2(Vector2.ZERO,Vector2(capture.size)),empty,snow,Transform2D.IDENTITY)>700,"shared-World2D portrait/recording viewport also sees real native snowfall")
	capture.render_target_update_mode = SubViewport.UPDATE_DISABLED
	capture.queue_free()
	await process_frame
