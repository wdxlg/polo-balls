extends SceneTree
# 在真实 GPU 上对纯阴影画布读回像素，并截取六种真实 World 背景。
const SHADOW = preload("res://scripts/effects/我的世界/地图内沿阴影.gd")
const THEMES = preload("res://scripts/effects/我的世界/地图背景主题.gd")
var checks:int = 0
var failures:int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MAP_WALL_3D_VISUAL FAIL: "+label)
	else: print("PASS: ",label)

func _frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw

func _changed_pixels(before:Image,after:Image) -> int:
	if before.get_size()!=after.get_size(): return 0
	var original:Image = before.duplicate()
	var relief:Image = after.duplicate()
	original.resize(225,400,Image.INTERPOLATE_NEAREST)
	relief.resize(225,400,Image.INTERPOLATE_NEAREST)
	var changed:int = 0
	for y:int in range(400):
		for x:int in range(225):
			var a:Color = original.get_pixel(x,y)
			var b:Color = relief.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>0.065: changed += 1
	return changed

func _run() -> void:
	create_timer(65.0).timeout.connect(func(): quit(2))
	var folder:String = "user://map_wall_3d"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var view := SubViewport.new()
	view.size = Vector2i(160,160)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var inner:Node2D = SHADOW.new()
	view.add_child(inner)
	var area:Rect2 = Rect2(0,0,160,160)
	var regions:Array[Rect2] = [area]
	var sides:Array[Dictionary] = [
		{"side":0,"line":0.0,"a":0.0,"b":160.0},
		{"side":1,"line":160.0,"a":0.0,"b":160.0},
		{"side":2,"line":0.0,"a":0.0,"b":160.0},
		{"side":3,"line":160.0,"a":0.0,"b":160.0},
	]
	inner.configure_regions(regions,Vector2(16,16),sides,Vector2(-32,32))
	await _frame()
	var img:Image = view.get_texture().get_image()
	check(img.get_pixel(80,8).a>0.23 and img.get_pixel(152,80).a>0.23,"north and east walls cast visible inward shadows")
	check(img.get_pixel(8,80).a<0.15 and img.get_pixel(80,152).a<0.15,"west and south walls have only weak contact shade")
	check(img.get_pixel(80,80).a<0.02 and img.get_pixel(80,8).a<0.47,"floor center stays clear and corners cannot stack above one shadow")
	img.save_png(folder+"/shadow_default.png")
	var gap:Array[Dictionary] = [
		{"side":2,"line":0.0,"a":0.0,"b":55.0},
		{"side":2,"line":0.0,"a":105.0,"b":160.0},
	]
	inner.configure_regions(regions,Vector2(16,16),gap,Vector2(-32,32))
	await _frame()
	img = view.get_texture().get_image()
	check(img.get_pixel(80,4).a<0.02 and img.get_pixel(35,8).a>0.23,"door interrupts both ambient and projected shadow")
	img.save_png(folder+"/shadow_door.png")
	inner.configure_regions(regions,Vector2(16,16),sides,Vector2(32,-32))
	await _frame()
	img = view.get_texture().get_image()
	check(img.get_pixel(8,80).a>0.23 and img.get_pixel(80,152).a>0.23 and img.get_pixel(80,8).a<0.15,"changing light direction reverses the inward cast")
	view.queue_free()
	var game:Node = root.get_node("Game")
	var old:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Map_Background = "blue"
	AudioServer.set_bus_mute(0,true)
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	world.control.hide()
	var layer:Node = world.map_group["Map10x10"]
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.make_current()
	camera.zoom = Vector2.ONE*2.3
	for style:String in THEMES.OPTIONS:
		game.set_runtime_game_setting("Map_Background",style,false)
		world.refresh_map_presentation()
		camera.global_position=world.return_map_display_rect(layer).get_center()
		world.map_wall_volume.hide()
		await _frame()
		var flat:Image = root.get_texture().get_image()
		world.map_wall_volume.show()
		await _frame()
		var picture:Image = root.get_texture().get_image()
		check(picture.get_width()>100 and world.map_wall_volume.visible,"%s: real World frame captured with active volume" % style)
		var relief_pixels:int = _changed_pixels(flat,picture)
		check(relief_pixels>24,"%s: raised face changes real GPU pixels beyond flat wall" % style)
		print("MAP_WALL_DEPTH_PIXELS_",style,"=",relief_pixels)
		var ratio:float = minf(640.0/maxf(picture.get_width(),1),400.0/maxf(picture.get_height(),1))
		picture.resize(maxi(1,int(picture.get_width()*ratio)),maxi(1,int(picture.get_height()*ratio)),Image.INTERPOLATE_NEAREST)
		var path:String = folder+"/world_"+style+".png"
		check(picture.save_png(path)==OK,"%s: screenshot saved" % style)
		print("MAP_WALL_PREVIEW_",style,"=",ProjectSettings.globalize_path(path))
	game.set_runtime_game_setting("Map_Background","grass",false)
	world.refresh_map_presentation()
	var ground:Rect2 = world.return_map_world_rect(layer)
	var owner := Node2D.new()
	world.add_child(owner)
	owner.global_position = ground.position+Vector2(ground.size.x*0.5,18.0)
	var door:int = world.open_waiter_door(owner,38.0,28.0,46.0,0.05)
	check(door>0,"real grass map opens visible waiter door")
	await create_timer(0.09).timeout
	await _frame()
	var door_image:Image = root.get_texture().get_image()
	var door_ratio:float = minf(640.0/maxf(door_image.get_width(),1),400.0/maxf(door_image.get_height(),1))
	door_image.resize(maxi(1,int(door_image.get_width()*door_ratio)),maxi(1,int(door_image.get_height()*door_ratio)),Image.INTERPOLATE_NEAREST)
	check(door_image.save_png(folder+"/world_grass_door.png")==OK,"real grass door frame saved")
	if door>0: world.close_waiter_door(door,0.05)
	game.Game_Settings = old
	world.queue_free()
	await process_frame
	print("MAP_WALL_3D_VISUAL checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
