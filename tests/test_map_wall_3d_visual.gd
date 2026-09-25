extends SceneTree
# Windows D3D12 读回/截图：五种原版贴图、低矮无缝网格、移动镜头的视差和真实地影。
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

func _world_pixel(img:Image,screen_position:Vector2) -> Color:
	# 游戏内部画布是 1080x1920，GPU 主视口可能按 0.5 倍实际栅格读回。
	var canvas_size:Vector2 = root.get_visible_rect().size
	var x:int = clampi(roundi(screen_position.x*img.get_width()/canvas_size.x),0,img.get_width()-1)
	var y:int = clampi(roundi(screen_position.y*img.get_height()/canvas_size.y),0,img.get_height()-1)
	return img.get_pixel(x,y)

func _luma(c:Color) -> float:
	return (c.r+c.g+c.b)/3.0

func _wall_alpha(volume:Node2D,point:Vector2,height:float,shadow:bool=false) -> float:
	var view:SubViewport = volume.shadow_viewport if shadow else volume.viewport
	var coords:Vector2 = volume.camera.unproject_position(volume._ground_point(point,height))
	var img:Image = view.get_texture().get_image()
	var x:int = roundi(coords.x)
	var y:int = roundi(coords.y)
	if x<0 or y<0 or x>=img.get_width() or y>=img.get_height(): return 0.0
	return img.get_pixel(x,y).a

func _save_detail(img:Image,path:String) -> bool:
	var width:int = mini(900,mini(img.get_width(),img.get_height()))
	var rect:Rect2i = Rect2i((img.get_width()-width)/2,(img.get_height()-width)/2,width,width)
	var crop:Image = img.get_region(rect)
	crop.resize(600,600,Image.INTERPOLATE_NEAREST)
	return crop.save_png(path)==OK

func _run() -> void:
	create_timer(115.0).timeout.connect(func():quit(2))
	var folder:String = "user://map_wall_true3d"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
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
	var physical:Rect2 = world.map_island_rects(layer)[0]
	var cell:Vector2 = world.map_visual_cell_size(layer)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.make_current()
	camera.zoom = Vector2.ONE*2.3
	camera.global_position = physical.get_center()
	await _frame()
	check(world.map_wall_volume==null,"blue keeps its original flat boundary without allocating either 3D viewport")
	check(_save_detail(root.get_texture().get_image(),folder+"/world_blue_detail.png"),"blue screenshot saved")
	var top_point:Vector2 = Vector2(physical.get_center().x+cell.x*0.5,physical.position.y-cell.y*0.5)
	var shadow_point:Vector2 = Vector2(physical.get_center().x-cell.x*2.0,physical.position.y+cell.y*0.3)
	var clear_point:Vector2 = shadow_point+Vector2(0,cell.y*0.7)
	for style:String in ["grass","sand","stone","nether","end"]:
		game.set_runtime_game_setting("Map_Background",style,false)
		world.refresh_map_presentation()
		camera.global_position = physical.get_center()
		await _frame()
		var volume:Node2D = world.map_wall_volume
		var mesh_image:Image = volume.viewport.get_texture().get_image()
		var shadow_image:Image = volume.shadow_viewport.get_texture().get_image()
		check(_colored_pixels(mesh_image)>120,"%s: GPU renders opaque original Minecraft block faces" % style)
		check(_wall_alpha(volume,top_point,volume.block_height)>0.5,"%s: real low-height block at the north boundary" % style)
		var seamless:bool = true
		for offset:int in range(-3,4):
			var seam:Vector2 = Vector2(physical.position.x+cell.x*(5+offset),top_point.y)
			if _wall_alpha(volume,seam,volume.block_height)<0.98: seamless=false
		check(seamless,"%s: GPU north-wall cell joins stay opaque, no transparent cracks" % style)
		var cast_alpha:float = _wall_alpha(volume,shadow_point,-0.08,true)
		check(cast_alpha>0.08 and _wall_alpha(volume,clear_point,-0.08,true)<0.03 and _wall_alpha(volume,shadow_point,0.0)<0.05,"%s: shadow-only GPU pass hits floor near wall but not open floor or block pass" % style)
		volume.hide()
		await _frame()
		var flat:Image = root.get_texture().get_image()
		volume.show()
		await _frame()
		var picture:Image = root.get_texture().get_image()
		var delta:int = _changed_pixels(flat,picture)
		check(delta>48,"%s: genuine 3D blocks and real shadow alter the 2D scene" % style)
		if style=="grass" or style=="sand":
			var screen_point:Vector2 = world.get_viewport().get_canvas_transform()*shadow_point
			check(_luma(_world_pixel(flat,screen_point))-_luma(_world_pixel(picture,screen_point))>0.025,"%s: 3D directional shadow is visibly DARK on the existing ground" % style)
		print("MAP_WALL_TRUE3D_PIXELS_",style,"=",delta," REAL_SHADOW_ALPHA=",cast_alpha)
		var full:Image = picture.duplicate()
		var ratio:float = minf(640.0/maxf(full.get_width(),1),400.0/maxf(full.get_height(),1))
		full.resize(maxi(1,int(full.get_width()*ratio)),maxi(1,int(full.get_height()*ratio)),Image.INTERPOLATE_NEAREST)
		check(full.save_png(folder+"/world_"+style+".png")==OK and _save_detail(picture,folder+"/world_"+style+"_detail.png"),"%s: real-world screenshot saved" % style)
		if style=="grass":
			check(mesh_image.save_png(folder+"/wall_mesh_grass.png")==OK and shadow_image.save_png(folder+"/shadow_receiver_grass.png")==OK,"grass: block pass and real 3D shadow pass saved separately")
	game.set_runtime_game_setting("Map_Background","grass",false)
	world.refresh_map_presentation()
	camera.zoom = Vector2.ONE*3.0
	camera.global_position = physical.get_center()+Vector2(-cell.x*6.0,0.0)
	await _frame()
	var volume:Node2D = world.map_wall_volume
	var left_base:Vector2 = volume.camera.unproject_position(volume._ground_point(top_point,0.0))
	var left_top:Vector2 = volume.camera.unproject_position(volume._ground_point(top_point,volume.block_height))
	var left_image:Image = volume.viewport.get_texture().get_image()
	check(root.get_texture().get_image().save_png(folder+"/world_grass_camera_left.png")==OK,"camera-left frame saved")
	camera.global_position = physical.get_center()+Vector2(cell.x*6.0,0.0)
	await _frame()
	var right_base:Vector2 = volume.camera.unproject_position(volume._ground_point(top_point,0.0))
	var right_top:Vector2 = volume.camera.unproject_position(volume._ground_point(top_point,volume.block_height))
	var right_image:Image = volume.viewport.get_texture().get_image()
	check(root.get_texture().get_image().save_png(folder+"/world_grass_camera_right.png")==OK,"camera-right frame saved")
	var left_offset:float = (left_top-left_base).x/volume._render_scale
	var right_offset:float = (right_top-right_base).x/volume._render_scale
	check(left_offset>2.0 and right_offset< -2.0 and left_offset-right_offset>6.0 and absf(left_offset)<9.0 and absf(right_offset)<9.0,"low wall retains opposite perspective but exposes less side when Camera2D crosses it")
	check(_changed_pixels(left_image,right_image)>100,"GPU actually redraws wall from the new camera; no frozen whole-map texture")
	print("MAP_WALL_PARALLAX left=",left_offset," right=",right_offset)
	camera.zoom = Vector2.ONE*2.3
	camera.global_position = physical.get_center()
	await _frame()
	var before_light:Image = volume.viewport.get_texture().get_image()
	var north_before:float = _wall_alpha(volume,shadow_point,-0.08,true)
	world.map_wall_light_direction = Vector2(-1,1)
	world.refresh_map_presentation()
	await _frame()
	var after_light:Image = volume.viewport.get_texture().get_image()
	var south_point:Vector2 = Vector2(physical.get_center().x+cell.x*2.0,physical.end.y-cell.y*0.3)
	var north_after:float = _wall_alpha(volume,shadow_point,-0.08,true)
	var south_after:float = _wall_alpha(volume,south_point,-0.08,true)
	check(_changed_pixels(before_light,after_light)>16,"moving DirectionalLight3D re-lights the actual six-faced mesh")
	check(north_before>0.08 and north_after<0.05 and south_after>0.08,"reversing the REAL light moves the ground shadow from north/east to south/west")
	world.map_wall_light_direction = Vector2(1,-1)
	world.refresh_map_presentation()
	await _frame()
	check(_wall_alpha(volume,top_point,volume.block_height)>0.5,"closed map has an actual 3D block at the future door")
	var owner := Node2D.new()
	world.add_child(owner)
	owner.global_position = physical.position+Vector2(physical.size.x*0.5,18.0)
	var door:int = world.open_waiter_door(owner,38.0,28.0,46.0,0.05)
	check(door>0,"waiter opens a physical map door")
	if door>0:
		var info:Dictionary = world._waiter_doors[door]
		var side:int = int(info.side)
		var along:float = info.center.y if side<2 else info.center.x
		var probe:Vector2 = [Vector2(physical.position.x-cell.x*0.5,along),Vector2(physical.end.x+cell.x*0.5,along),Vector2(along,physical.position.y-cell.y*0.5),Vector2(along,physical.end.y+cell.y*0.5)][side]
		await create_timer(0.09).timeout
		await _frame()
		check(_wall_alpha(volume,probe,volume.block_height)<0.1,"open doorway has no 3D block at its real opening")
		check(_save_detail(root.get_texture().get_image(),folder+"/world_grass_door_detail.png"),"open door screenshot saved")
		world.close_waiter_door(door,0.05)
	await create_timer(0.12).timeout
	for map_key:String in ["Map50x50","Map_Portal"]:
		world.now_choose_map = map_key
		world.refresh_map_presentation()
		camera.zoom = Vector2.ONE*0.75
		camera.global_position = world.return_map_display_rect(world.map_group[map_key]).get_center()
		await _frame()
		var larger:Node2D = world.map_wall_volume
		var image:Image = larger.viewport.get_texture().get_image()
		check(larger.block_count>0 and _colored_pixels(image)>100,"%s: viewport actually draws screen-visible 3D boundary / islands" % map_key)
		var miniature:Image = image.duplicate()
		var fit:float = minf(1.0,800.0/float(maxi(image.get_width(),image.get_height())))
		miniature.resize(maxi(1,roundi(image.get_width()*fit)),maxi(1,roundi(image.get_height()*fit)),Image.INTERPOLATE_NEAREST)
		check(miniature.save_png(folder+"/wall_mesh_"+map_key+".png")==OK,"%s: moving-camera 3D pass screenshot saved" % map_key)
	game.Game_Settings = old
	world.queue_free()
	await _frame()
	print("MAP_WALL_TRUE_3D_VISUAL checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
