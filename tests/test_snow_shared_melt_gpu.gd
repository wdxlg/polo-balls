extends "res://tests/test_training_events_snow_gpu.gd"
## Actual 2D floor + lit 3D wall snow; unchanged footprint through a short opacity fade.
var metrics:Array = []
var caption:Label
var frames:int = 0
var movie:bool = false

func finish(code:int) -> void:
	if done: return
	if code==2: push_error("Snow melt GPU timed out before completing all checks")
	var f:=FileAccess.open(capture_dir.path_join("metrics.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures,"exit_code":code,"timed_out":code==2,"frames":frames,"metrics":metrics},"\t"));f.close()
	print("SNOW_SHARED_MELT_GPU checks=",checks," failures=",failures)
	await super.finish(code)

func energy(rect:Rect2,bare:Image,image:Image,transform:Transform2D) -> float:
	var a:Vector2 = transform*rect.position
	var b:Vector2 = transform*rect.end
	var low:Vector2i = Vector2i(a.min(b).ceil())
	var high:Vector2i = Vector2i(a.max(b).floor())
	var result:float = 0.0
	for y:int in range(maxi(0,low.y),mini(image.get_height(),high.y)):
		for x:int in range(maxi(0,low.x),mini(image.get_width(),high.x)):
			result += gap(bare.get_pixel(x,y),image.get_pixel(x,y))
	return result

func capture(label:String = "") -> Image:
	var image:Image = await grab(label)
	if movie:
		image.save_png(capture_dir.path_join("frames/frame_%03d.png" % frames))
		frames += 1
	return image

func run() -> void:
	if DisplayServer.get_name()=="headless": push_error("Actual GPU required"); quit(2); return
	game = root.get_node("Game")
	original_settings = game.Game_Settings.duplicate(true)
	original_locale = game.current_locale
	settings_file = game.SETTINGS_PATH
	settings_existed = FileAccess.file_exists(settings_file)
	if settings_existed: settings_bytes = FileAccess.get_file_as_bytes(settings_file)
	game.Game_Settings.Environment = "none"
	game.Game_Settings.Map_Background = "grass"
	game.Game_Settings.Minecraft_Clouds = false
	game.Game_Settings.Development_Mode = false
	root.size = Vector2i(1000,720)
	root.content_scale_size = root.size
	await setup_world()
	saved = original_settings
	capture_dir = OS.get_environment("SNOW_MELT_EVIDENCE_DIR")
	if capture_dir.is_empty(): capture_dir = "user://snow_melt_gpu"
	DirAccess.make_dir_recursive_absolute(capture_dir)
	movie = OS.get_environment("SNOW_MELT_CAPTURE_FRAMES")=="1"
	if movie: DirAccess.make_dir_recursive_absolute(capture_dir.path_join("frames"))
	create_timer(130,true,false,true).timeout.connect(func():finish(2))
	conditions = world.battle_conditions
	conditions.set_physics_process(false)
	world.set_physics_process(false)
	world.set_process(false)
	world.control.hide()
	world.versus_label.hide()
	for layer:CanvasLayer in root.find_children("*","CanvasLayer",true,false): layer.hide()
	var source:Node2D = spawn(GOLEM_PATH,world.return_map_world_rect(world._current_map_node()).get_center())
	source.Can_Attack = false
	source.set_physics_process(false)
	source.hide()
	setting("Environment","snow")
	conditions.refresh_layout(true)
	var field:Node2D = conditions.field
	field.set_physics_process(false)
	field.patches.clear()
	field.clear_environment()
	var wall:Rect2
	for rect:Rect2 in conditions._walls:
		if rect.size.x>96 and (not wall.has_area() or rect.position.y<wall.position.y): wall = rect
	check(wall.has_area(),"real map exposes a supported block-wall top")
	var center:Vector2 = Vector2(wall.get_center().x,wall.end.y+36)
	var cell:Vector2i = field.snow_cell_at(center)
	var left:Vector2i = cell+Vector2i(-2,0)
	var right:Vector2i = cell+Vector2i(2,0)
	source.global_position = field.snow_point_at(left)
	var wall_record:Dictionary
	var best:float = INF
	for item:Dictionary in conditions._wall_candidates:
		var tile:Rect2 = item.tile
		if not tile.intersects(wall): continue
		var distance:float = tile.get_center().distance_squared_to(Vector2(center.x,wall.get_center().y))
		if distance<best: best=distance; wall_record=item.duplicate(true)
	check(not wall_record.is_empty(),"wall probe uses a real production one-block candidate")
	setting("Environment","none")
	game.now_stop_state = false
	field.deposit(source,left,false)
	var ground:Dictionary = {"cell":right,"tile":field.snow_tile_at(right),"rects":[field.snow_tile_at(right)],"decorative":false}
	field.add_environment_patch(conditions,ground)
	field.add_environment_patch(conditions,wall_record)
	game.now_stop_state = true
	var camera:=Camera2D.new()
	world.add_child(camera)
	camera.make_current()
	camera.global_position = Vector2(center.x,wall.end.y+15)
	camera.zoom = Vector2.ONE*5.5
	camera.force_update_scroll()
	var ui:=CanvasLayer.new()
	ui.layer = 60
	world.add_child(ui)
	caption = Label.new()
	caption.position = Vector2(22,18)
	caption.add_theme_font_size_override("font_size",22)
	caption.add_theme_color_override("font_outline_color",Color.BLACK)
	caption.add_theme_constant_override("outline_size",4)
	ui.add_child(caption)
	caption.text = "统一一格雪｜左：雪傀儡雪径 · 右：环境地面雪 · 上：真实墙顶雪"
	field.hide()
	var bare:Image = await capture("bare")
	if done: return # Timeout cleanup may have freed the field while awaiting a draw.
	field.show()
	var full:Image = await capture("full_blocks")
	if done: return # Timeout cleanup may have freed the field while awaiting a draw.
	var view:Node2D = field.wall_view
	check(is_instance_valid(view.mesh_node),"wall snow still has a real lit 3D mesh")
	var geometry:AABB = view.mesh_node.mesh.get_aabb()
	var mesh_id:int = view.mesh_node.get_instance_id()
	var transform:Transform2D = field.get_global_transform_with_canvas()
	var trail_rect:Rect2 = field.patches[left].tile
	var env_rect:Rect2 = field.environment_patches[right].tile
	check(trail_rect.size==env_rect.size and trail_rect.size==field.grid_size,"actual trail/environment drawings have the same full block size")
	var wall_roi:Rect2 = projected_snow_bounds(view)
	var full_floor:float = energy(trail_rect,bare,full,transform)
	var full_env:float = energy(env_rect,bare,full,transform)
	var full_wall:float = energy(wall_roi,bare,full,Transform2D.IDENTITY)
	check(full_floor>100 and full_env>100 and full_wall>40,"all three surfaces have genuinely visible snow pixels")
	game.now_stop_state = false
	field.advance(8.0)
	game.now_stop_state = true
	caption.text = "融化：不缩成半格，保持原占地快速渐隐"
	await capture("fade_start")
	if done: return # Timeout cleanup may have freed the field while awaiting a draw.
	for i:int in range(1,5):
		game.now_stop_state = false
		field.advance(0.075)
		game.now_stop_state = true
		var current:Image = await capture("fade_%d" % i)
		if done: return # Timeout cleanup may have freed the field while awaiting a draw.
		if i==2:
			var floor_energy:float = energy(trail_rect,bare,current,transform)
			var env_energy:float = energy(env_rect,bare,current,transform)
			var wall_energy:float = energy(wall_roi,bare,current,Transform2D.IDENTITY)
			check(is_equal_approx(field.snow_alpha(field.patches[left]),0.5) and field.patches[left].tile==trail_rect,"mid-fade keeps the same geometry and exact half-opacity state")
			check(floor_energy<full_floor*0.92 and floor_energy>full_floor*0.15,"real ground trail pixels visibly fade before deletion")
			check(env_energy<full_env*0.92 and env_energy>full_env*0.15,"real environment ground pixels use the same intermediate fade")
			check(wall_energy<full_wall*0.92 and wall_energy>full_wall*0.08,"true wall snow also visibly fades rather than remaining opaque")
			check(view.mesh_node.mesh.get_aabb()==geometry and view.mesh_node.get_instance_id()==mesh_id,"wall fade does not shrink geometry or allocate one node per tile/frame")
			metrics.append({"phase":"half","floor_ratio":floor_energy/full_floor,"environment_ratio":env_energy/full_env,"wall_ratio":wall_energy/full_wall})
			var frozen:Image = await capture()
			if done: return # Timeout cleanup may have freed the field while awaiting a draw.
			check(energy(trail_rect,current,frozen,transform)<1.0 and energy(wall_roi,current,frozen,Transform2D.IDENTITY)<5.0,"paused floor AND 3D coverage fade remain stable")
	game.now_stop_state = false
	field.advance(0.01)
	game.now_stop_state = true
	var gone:Image = await capture("gone")
	if done: return # Timeout cleanup may have freed the field while awaiting a draw.
	check(field.patches.is_empty() and field.environment_patches.is_empty() and not is_instance_valid(view.mesh_node),"finished fade releases both ground layers, wall mesh and shadow proxies")
	check(energy(trail_rect,bare,gone,transform)<2 and energy(env_rect,bare,gone,transform)<2 and energy(wall_roi,bare,gone,Transform2D.IDENTITY)<6,"no visible white patch or floating wall shadow remains after expiry")
	# Normal weather still fades only on combat delta; changing the environment
	# must not reset snow already in its halfway-faded state.
	game.now_stop_state = false
	field.deposit(source,left,false)
	field.add_environment_patch(conditions,ground)
	field.advance(8.15)
	var before_alpha:float = field.snow_alpha(field.patches[left])
	setting("Environment","snow")
	field.wall_view.set_weather(false) # Isolate accumulation pixels from falling flakes for this probe.
	check(is_equal_approx(field.snow_alpha(field.patches[left]),before_alpha),"enabling weather never restamps a half-faded existing trail")
	field.advance(0.15)
	check(field.patches.has(left) and is_equal_approx(field.snow_alpha(field.patches[left]),0.25),"snow environment halves the visible fade speed too")
	field.advance(0.16)
	check(field.patches.is_empty(),"the slowed fade still terminates normally")
	game.now_stop_state = true
	await finish(0 if failures==0 else 1)
