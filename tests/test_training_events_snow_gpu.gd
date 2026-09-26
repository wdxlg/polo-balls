extends "res://tests/test_training_events_snow.gd"
## Real GPU captures of the production field, wall overlay and Settings UI.
var capture_dir:String
var hidden_layers:Dictionary = {}

func grab(name:String = "") -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
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
	create_timer(90).timeout.connect(func():finish(2))
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
	for style:String in ["blue","grass","summit"]:
		setting("Map_Background",style)
		setting("Environment","snow")
		conditions.refresh_layout(true)
		await physics_frame
		await physics_frame
		await process_frame
		field = conditions.field
		field.set_physics_process(false)
		field.clear_environment()
		field.patches.clear()
		field.queue_redraw()
		var wall:Rect2
		for rect:Rect2 in conditions._walls:
			if rect.size.x>96 and (not wall.has_area() or rect.position.y<wall.position.y): wall = rect
		check(wall.has_area(),style+" exposes real rendered wall geometry")
		if not wall.has_area(): continue
		var x_center:float = FIELD.point_at(FIELD.cell_at(wall.get_center())).x
		var floor_y:float = ceil((wall.end.y+24.0)/FIELD.CELL)*FIELD.CELL
		camera.global_position = Vector2(x_center,floor_y+30)
		camera.reset_smoothing()
		actor.global_position = Vector2(x_center,floor_y+24)
		var wall_rects:Array[Rect2] = []
		var floor_rects:Array[Rect2] = []
		for i:int in range(-3,4):
			var cell:Vector2i = FIELD.cell_at(Vector2(x_center+i*24,wall.get_center().y))
			var square:=Rect2(FIELD.point_at(cell)-Vector2.ONE*12,Vector2.ONE*24)
			var clipped:Rect2 = square.intersection(wall)
			if clipped.has_area():
				wall_rects.append(clipped)
				field.add_environment_patch(conditions,{"cell":cell,"decorative":true,"rects":[clipped]})
			for row:int in range(3):
				var floor_cell:Vector2i = FIELD.cell_at(Vector2(x_center+i*24,floor_y+row*24))
				var footprint:=Rect2(FIELD.point_at(floor_cell)-Vector2.ONE*12,Vector2.ONE*24)
				var footprint_list:Array[Rect2] = [footprint]
				if not conditions.GEOMETRY.subtract(footprint_list,conditions._ground).is_empty(): continue
				floor_rects.append(footprint)
				field.add_environment_patch(conditions,{"cell":floor_cell,"decorative":false,"rects":[footprint]})
		game.now_stop_state = true
		actor.image.hide()
		field.hide()
		var empty:Image = await grab()
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
		for rect:Rect2 in wall_rects: wall_pixels += changed_in(rect,empty,snow_only,transform)
		for rect:Rect2 in floor_rects: ground_pixels += changed_in(rect,empty,snow_only,transform)
		print("SNOW_GPU style=",style," wall_pixels=",wall_pixels," ground_pixels=",ground_pixels," wall_z=",field.wall_view.z_index)
		check(wall_pixels>40,style+" wall decoration has actual visible snow pixels on the wall surface")
		check(ground_pixels>400,style+" floor uses visible native snow patches")
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
		check(field.environment_patches==snapshot,style+" pause preserves permanent rendered snow")
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
	check(field.wall_view.z_index==world.map_border_segment_root.z_index-field.z_index+1,"replica wall overlay follows the local blue frame's actual depth")
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
	for rect:Rect2 in pieces: pixels+=changed_in(rect,without,with_snow,field.get_global_transform_with_canvas())
	check(pixels>40,"client-style projection has visible native snow pixels rather than hidden wall data")
	conditions.set_multiplayer_authority(1)

func capture_random_weather(camera:Camera2D,_field:Node2D) -> void:
	setting("Map_Background","grass")
	conditions.refresh_layout(true)
	await physics_frame
	await physics_frame
	game.now_stop_state = false
	for i:int in range(48): conditions.advance(1.0)
	game.now_stop_state = true
	camera.global_position = world.return_map_world_rect(world._current_map_node()).get_center()
	camera.zoom = Vector2(0.7,0.7)
	camera.reset_smoothing()
	await grab("random_weather_production")
