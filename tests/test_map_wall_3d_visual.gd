extends SceneTree
# D3D12 截图/读回：五种材质真实六面体、蓝色平面、动态光照与开门断墙。
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
		push_error("MAP_WALL_TRUE_3D_VISUAL FAIL: "+label)
	else: print("PASS: ",label)

func _frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw

func _changed_pixels(before:Image,after:Image) -> int:
	if before.get_size()!=after.get_size(): return 0
	var a:Image = before.duplicate()
	var b:Image = after.duplicate()
	a.resize(225,400,Image.INTERPOLATE_NEAREST)
	b.resize(225,400,Image.INTERPOLATE_NEAREST)
	var changed:int = 0
	for y:int in range(400):
		for x:int in range(225):
			var c:Color = a.get_pixel(x,y)
			var d:Color = b.get_pixel(x,y)
			if absf(c.r-d.r)+absf(c.g-d.g)+absf(c.b-d.b)>0.065: changed += 1
	return changed

func _colored_pixels(img:Image) -> int:
	var count:int = 0
	var step:int = maxi(1,img.get_width()/200)
	for y:int in range(0,img.get_height(),step):
		for x:int in range(0,img.get_width(),step):
			if img.get_pixel(x,y).a>0.7: count += 1
	return count

func _wall_alpha(volume:Node2D,point:Vector2,height:float) -> float:
	var coords:Vector2 = volume.camera.unproject_position(volume._ground_point(point,height))
	var img:Image = volume.viewport.get_texture().get_image()
	var x:int = clampi(roundi(coords.x),0,img.get_width()-1)
	var y:int = clampi(roundi(coords.y),0,img.get_height()-1)
	return img.get_pixel(x,y).a

func _save_detail(img:Image,path:String) -> bool:
	var width:int = mini(900,mini(img.get_width(),img.get_height()))
	var rect:Rect2i = Rect2i((img.get_width()-width)/2,(img.get_height()-width)/2,width,width)
	var crop:Image = img.get_region(rect)
	crop.resize(600,600,Image.INTERPOLATE_NEAREST)
	return crop.save_png(path)==OK

func _run() -> void:
	create_timer(95.0).timeout.connect(func(): quit(2))
	var folder:String = "user://map_wall_true3d"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var view := SubViewport.new()
	view.size = Vector2i(160,160)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var inner:Node2D = SHADOW.new()
	view.add_child(inner)
	var regions:Array[Rect2] = [Rect2(0,0,160,160)]
	var sides:Array[Dictionary] = [
		{"side":0,"line":0.0,"a":0.0,"b":160.0},
		{"side":1,"line":160.0,"a":0.0,"b":160.0},
		{"side":2,"line":0.0,"a":0.0,"b":160.0},
		{"side":3,"line":160.0,"a":0.0,"b":160.0},
	]
	inner.configure_regions(regions,Vector2(16,16),sides,Vector2(-32,32))
	await _frame()
	var img:Image = view.get_texture().get_image()
	check(img.get_pixel(80,8).a>0.23 and img.get_pixel(152,80).a>0.23,"floor north/east shadows continue to follow cut 3D wall edges")
	check(img.get_pixel(8,80).a<0.15 and img.get_pixel(80,152).a<0.15,"west/south receive only contact shading")
	check(img.get_pixel(80,80).a<0.02 and img.get_pixel(80,8).a<0.47,"floor center clear; corners cannot double stack")
	img.save_png(folder+"/shadow_default.png")
	var gap:Array[Dictionary] = [
		{"side":2,"line":0.0,"a":0.0,"b":55.0},
		{"side":2,"line":0.0,"a":105.0,"b":160.0},
	]
	inner.configure_regions(regions,Vector2(16,16),gap,Vector2(-32,32))
	await _frame()
	img = view.get_texture().get_image()
	check(img.get_pixel(80,4).a<0.02 and img.get_pixel(35,8).a>0.23,"door interrupts floor shadow")
	inner.configure_regions(regions,Vector2(16,16),sides,Vector2(32,-32))
	await _frame()
	img = view.get_texture().get_image()
	check(img.get_pixel(8,80).a>0.23 and img.get_pixel(80,152).a>0.23 and img.get_pixel(80,8).a<0.15,"changing the light direction reverses floor shadow")
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
	camera.global_position=world.return_map_display_rect(layer).get_center()
	await _frame()
	check(world.map_wall_volume==null,"blue renders its original flat edge without instantiating 3D")
	check(_save_detail(root.get_texture().get_image(),folder+"/world_blue_detail.png"),"blue screenshot saved")
	for style:String in ["grass","sand","stone","nether","end"]:
		game.set_runtime_game_setting("Map_Background",style,false)
		world.refresh_map_presentation()
		camera.global_position=world.return_map_display_rect(layer).get_center()
		await _frame()
		var volume:Node2D = world.map_wall_volume
		var mesh_pixels:int = _colored_pixels(volume.viewport.get_texture().get_image())
		check(mesh_pixels>120,"%s: GPU renders opaque pixels from real lit 3D mesh" % style)
		var wall:Rect2 = volume.wall_rects[0]
		check(_wall_alpha(volume,wall.get_center(),volume.block_height)>0.5,"%s: original cube TOP is actually visible in 3D viewport" % style)
		volume.hide()
		await _frame()
		var flat:Image = root.get_texture().get_image()
		volume.show()
		await _frame()
		var picture:Image = root.get_texture().get_image()
		var delta:int = _changed_pixels(flat,picture)
		check(delta>48,"%s: genuine 3D blocks add visible depth to 2D World" % style)
		print("MAP_WALL_TRUE3D_PIXELS_",style,"=",delta," OPAQUE_3D_PIXELS=",mesh_pixels)
		var full:Image = picture.duplicate()
		var ratio:float = minf(640.0/maxf(full.get_width(),1),400.0/maxf(full.get_height(),1))
		full.resize(maxi(1,int(full.get_width()*ratio)),maxi(1,int(full.get_height()*ratio)),Image.INTERPOLATE_NEAREST)
		check(full.save_png(folder+"/world_"+style+".png")==OK and _save_detail(picture,folder+"/world_"+style+"_detail.png"),"%s: full scene and close-up saved" % style)
		if style=="grass":
			check(volume.viewport.get_texture().get_image().save_png(folder+"/wall_mesh_grass.png")==OK,"grass: transparent 3D pass saved separately")
	# 光从右上变成左下时，真实网格各面的颜色也必须由 GPU 重新计算。
	game.set_runtime_game_setting("Map_Background","grass",false)
	world.refresh_map_presentation()
	await _frame()
	var before_light:Image = world.map_wall_volume.viewport.get_texture().get_image()
	world.map_wall_light_direction = Vector2(-1,1)
	world.refresh_map_presentation()
	await _frame()
	var after_light:Image = world.map_wall_volume.viewport.get_texture().get_image()
	check(_changed_pixels(before_light,after_light)>16,"DirectionalLight3D changes actual GPU-lit faces when source reverses")
	world.map_wall_light_direction = Vector2(1,-1)
	world.refresh_map_presentation()
	await _frame()
	var ground:Rect2 = world.return_map_world_rect(layer)
	var door_point:Vector2 = Vector2(ground.get_center().x,ground.position.y-world.map_visual_cell_size(layer).y*0.5)
	check(_wall_alpha(world.map_wall_volume,door_point,world.map_wall_volume.block_height)>0.5,"closed wall has a real 3D block at the future door")
	var owner := Node2D.new()
	world.add_child(owner)
	owner.global_position=ground.position+Vector2(ground.size.x*0.5,18.0)
	var door:int = world.open_waiter_door(owner,38.0,28.0,46.0,0.05)
	check(door>0,"real map opens waiter door")
	if door>0:
		var info:Dictionary = world._waiter_doors[door]
		var side:int = int(info.side)
		var along:float = info.center.y if side<2 else info.center.x
		var cell:Vector2 = world.map_visual_cell_size(layer)
		door_point = [Vector2(ground.position.x-cell.x*0.5,along),Vector2(ground.end.x+cell.x*0.5,along),Vector2(along,ground.position.y-cell.y*0.5),Vector2(along,ground.end.y+cell.y*0.5)][side]
	await create_timer(0.09).timeout
	await _frame()
	check(_wall_alpha(world.map_wall_volume,door_point,world.map_wall_volume.block_height)<0.1,"open door removes GPU 3D material in its true opening center")
	check(_save_detail(root.get_texture().get_image(),folder+"/world_grass_door_detail.png"),"open doorway close-up saved")
	if door>0: world.close_waiter_door(door,0.05)
	await create_timer(0.10).timeout
	for map_key:String in ["Map50x50","Map_Portal"]:
		world.now_choose_map = map_key
		world.refresh_map_presentation()
		await _frame()
		var larger:Node2D = world.map_wall_volume
		var pass_image:Image = larger.viewport.get_texture().get_image()
		check(larger.block_count>0 and _colored_pixels(pass_image)>150,"%s: GPU renders true 3D blocks on the actual large/multi-island map" % map_key)
		var miniature:Image = pass_image.duplicate()
		var fit:float = minf(1.0,800.0/float(maxi(pass_image.get_width(),pass_image.get_height())))
		miniature.resize(maxi(1,roundi(pass_image.get_width()*fit)),maxi(1,roundi(pass_image.get_height()*fit)),Image.INTERPOLATE_NEAREST)
		check(miniature.save_png(folder+"/wall_mesh_"+map_key+".png")==OK,"%s: 3D pass screenshot saved" % map_key)
	game.Game_Settings = old
	world.queue_free()
	# 给 D3D12 两帧回收 SubViewport 的 GPU 资源再退出测试进程。
	await _frame()
	print("MAP_WALL_TRUE_3D_VISUAL checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
