extends "res://tests/test_mc_bat.gd"
var settings_existed:bool
var settings_bytes:PackedByteArray
var cloud:Node2D

func _frame() -> void:
	await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	RenderingServer.force_draw(false)

func capture_view(size:Vector2i,shared:bool) -> SubViewport:
	var view:=SubViewport.new()
	view.size = size
	view.transparent_bg = not shared
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.canvas_cull_mask = 1
	if shared:
		view.world_2d = root.world_2d
		view.use_hdr_2d = root.use_hdr_2d
	else: view.world_2d = World2D.new()
	root.add_child(view)
	return view

func changed(a:Image,b:Image,rect:Rect2i) -> int:
	var count:int = 0
	for y:int in range(rect.position.y,rect.end.y):
		for x:int in range(rect.position.x,rect.end.x):
			if (a.get_pixel(x,y)-b.get_pixel(x,y)).to_rgba32() != Color(0,0,0,0).to_rgba32():
				var ca:Color = a.get_pixel(x,y)
				var cb:Color = b.get_pixel(x,y)
				if absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b) > 0.04: count += 1
	return count

func gpu_checks() -> void:
	if DisplayServer.get_name() == "headless": print("CLOUD_GPU_SKIPPED headless"); return
	var isolated:SubViewport = capture_view(Vector2i(512,384),false)
	var poly:=Polygon2D.new()
	poly.polygon = PackedVector2Array([Vector2.ZERO,Vector2(512,0),Vector2(512,384),Vector2(0,384)])
	cloud.cloud_material.set_shader_parameter("parallax",1.0) # Isolate footprint geometry from camera movement.
	poly.material = cloud.cloud_material
	isolated.add_child(poly)
	cloud.reset_drift()
	await _frame()
	var image:Image = isolated.get_texture().get_image()
	image.save_png("user://minecraft_clouds_flat_native_volume.png")
	var visible_pixels:int = 0
	var face_levels:Dictionary = {}
	for y:int in image.get_height():
		for x:int in image.get_width():
			var c:Color = image.get_pixel(x,y)
			if c.a > 0.1:
				visible_pixels += 1
				face_levels[int(round(c.r/maxf(c.a,0.01)*100.0))] = true
	print("CLOUD_GPU pixels=",visible_pixels," face_levels=",face_levels)
	check(visible_pixels > 500 and visible_pixels < 512*384*0.75,"native cloud mask produces separated clouds, not a screen-filling fog")
	check(face_levels.size() == 2 and face_levels.has(70) and face_levels.has(100),"GPU shows a solid white flat body and darker straight lower edge")
	var longest_rim:int = 0
	for x:int in image.get_width():
		var run:int = 0
		for y:int in image.get_height():
			var c:Color = image.get_pixel(x,y)
			if c.a > 0.1 and int(round(c.r/c.a*100.0)) == 70:
				run += 1
				longest_rim = maxi(longest_rim,run)
			else: run = 0
	check(longest_rim == int(ceil(cloud.THICKNESS)),"GPU lower edge has the approved 32/3-pixel thickness, not the rejected 3px paper rim")
	print("CLOUD_FLAT_EDGE_PX ",longest_rim)
	var native:Image = cloud.CLOUD_TEXTURE.get_image()
	var exact:bool = true
	for y:int in range(7):
		for x:int in range(10):
			var point:Vector2i = Vector2i(Vector2(x+0.5,y+0.5)*Vector2(cloud.CELL_SIZE,cloud.CELL_SIZE*cloud.PLANE_DEPTH))
			exact = exact and ((image.get_pixelv(point).a > 0.5) == (native.get_pixel(x,y).a > 0.5))
	check(exact,"GPU cloud-cell center occupancy exactly matches 70 original texture texels")
	check(is_equal_approx(cloud.PLANE_DEPTH,1.0) and cloud.cloud_material.get_shader_parameter("height_shift")==Vector2(0,cloud.THICKNESS),"cloud plane has square cells and a purely vertical edge: no compression, tilt or diagonal shear")
	check(is_equal_approx(cloud.THICKNESS/cloud.CELL_SIZE,1.0/3.0),"approved cloud edge preserves native 12:4 width/thickness proportions")
	var opaque_only:bool = true
	var flat_differences:int = 0
	for y:int in image.get_height():
		for x:int in image.get_width():
			var c:Color = image.get_pixel(x,y)
			opaque_only = opaque_only and (c.a < 0.001 or c.a > 0.999)
			var sample_point:=Vector2(x+0.5,y+0.5)
			var body_cell:Vector2i = Vector2i((sample_point/cloud.CELL_SIZE).floor())
			var lower_cell:Vector2i = Vector2i(((sample_point-Vector2(0,cloud.THICKNESS))/cloud.CELL_SIZE).floor())
			var body:bool = native.get_pixel(posmod(body_cell.x,256),posmod(body_cell.y,256)).a > 0.5
			var edge:bool = native.get_pixel(posmod(lower_cell.x,256),posmod(lower_cell.y,256)).a > 0.5
			var expected_alpha:float = 1.0 if body or edge else 0.0
			var expected_light:float = 1.0 if body else (0.70 if edge else 0.0)
			if absf(c.a-expected_alpha)>0.001 or absf(c.r-expected_light)>0.005 or absf(c.g-expected_light)>0.005 or absf(c.b-expected_light)>0.005: flat_differences += 1
	check(opaque_only,"GPU cloud pixels are strictly opaque or empty: no translucent checkerboard bleed or soft alpha fringe")
	check(flat_differences==0,"all 196608 GPU pixels match the uncompressed native footprint plus straight lower edge, including wrapped texels")
	print("CLOUD_FLAT_REFERENCE compared=",image.get_width()*image.get_height()," different=",flat_differences)

	cloud.cloud_material.set_shader_parameter("travel",cloud.CELL_SIZE)
	await _frame()
	var shifted:Image = isolated.get_texture().get_image()
	var shift_equal:bool = true
	for y:int in range(4,380,7):
		for x:int in range(4,512-int(cloud.CELL_SIZE)-4,7):
			if shifted.get_pixel(x,y) != image.get_pixel(x+int(cloud.CELL_SIZE),y): shift_equal = false
	check(shift_equal,"a one-cell drift translates the native volume without re-randomizing its shape")
	cloud.reset_drift()
	for depth:float in [cloud.BACKGROUND_PARALLAX,cloud.OVERHEAD_PARALLAX]:
		cloud.cloud_material.set_shader_parameter("parallax",depth)
		isolated.canvas_transform = Transform2D.IDENTITY
		await _frame()
		var before:Image = isolated.get_texture().get_image()
		isolated.canvas_transform = Transform2D(0.0,Vector2(-40,0))
		await _frame()
		var after:Image = isolated.get_texture().get_image()
		var displacement:int = int(round(40.0*depth))
		var equal_pixels:int = 0
		var total_pixels:int = 0
		for y:int in range(8,376,5):
			for x:int in range(8,440,5):
				total_pixels += 1
				if after.get_pixel(x,y)==before.get_pixel(x+displacement,y): equal_pixels += 1
		check(equal_pixels==total_pixels,"GPU camera pan 40px moves clouds by %dpx at depth %.2f" % [displacement,depth])
		print("CLOUD_PARALLAX depth=",depth," displacement=",displacement," equal=",equal_pixels,"/",total_pixels)

	for depth:float in [cloud.BACKGROUND_PARALLAX,cloud.OVERHEAD_PARALLAX]:
		cloud.cloud_material.set_shader_parameter("parallax",depth)
		isolated.canvas_transform = Transform2D.IDENTITY
		await _frame()
		var before:Image = isolated.get_texture().get_image()
		isolated.canvas_transform = Transform2D(0.0,Vector2(0,-40))
		await _frame()
		var after:Image = isolated.get_texture().get_image()
		var displacement:int = int(round(40.0*depth))
		var mismatches:int = 0
		for y:int in range(8,330,5):
			for x:int in range(8,504,5):
				if after.get_pixel(x,y)!=before.get_pixel(x,y+displacement): mismatches += 1
		check(mismatches==0,"GPU vertical camera pan has uniform %dpx parallax at depth %.2f, no row-dependent perspective" % [displacement,depth])
		print("CLOUD_VERTICAL_PARALLAX depth=",depth," displacement=",displacement," mismatches=",mismatches)
	isolated.canvas_transform = Transform2D.IDENTITY
	cloud.cloud_material.set_shader_parameter("parallax",cloud.BACKGROUND_PARALLAX)
	var small:SubViewport = capture_view(Vector2i(256,192),false)
	var copy:Polygon2D = poly.duplicate() as Polygon2D
	small.add_child(copy)
	small.canvas_transform = Transform2D(Vector2(0.5,0),Vector2(0,0.5),Vector2.ZERO)
	await _frame()
	var large_image:Image = isolated.get_texture().get_image()
	var small_image:Image = small.get_texture().get_image()
	var compared:int = 0
	var different:int = 0
	for y:int in range(4,188,3):
		for x:int in range(4,252,3):
			var point:Vector2i = Vector2i(x*2,y*2)
			var value:Color = large_image.get_pixelv(point)
			if value != large_image.get_pixelv(point+Vector2i.ONE) or value != large_image.get_pixelv(point-Vector2i.ONE): continue
			compared += 1
			if small_image.get_pixel(x,y) != value: different += 1
	check(compared>1000 and different==0,"different-resolution views with identical framing derive the same cloud camera center")
	print("CLOUD_CAPTURE_PARITY compared=",compared," different=",different)
	small.queue_free()
	cloud.refresh() # Restore map-selected parallax for actual world captures.
	isolated.queue_free()
	await process_frame
	# Same World2D path used by overview / recording views; no main-camera uniform.
	var view:SubViewport = capture_view(Vector2i(640,480),true)
	var second:SubViewport = capture_view(Vector2i(640,480),true)
	var map_node:Node = world._current_map_node()
	var arena:Rect2 = world.return_map_world_rect(map_node)
	var shift:Vector2 = Vector2(320,240)-arena.get_center()
	view.canvas_transform = Transform2D(0.0,shift)
	second.canvas_transform = view.canvas_transform
	game.set_runtime_game_setting("Map_Background","blue",false)
	game.set_runtime_game_setting("Minecraft_Clouds",false,false)
	await _frame()
	var off:Image = view.get_texture().get_image()
	game.set_runtime_game_setting("Minecraft_Clouds",true,false)
	await _frame()
	var on:Image = view.get_texture().get_image()
	var inner:Rect2i = Rect2i(arena.grow(-12).position+shift,arena.grow(-12).size).intersection(Rect2i(0,0,640,480))
	check(changed(off,on,inner)>10,"blue-map overhead clouds actually cross the playable arena")
	var point:=Vector2(-99999,-99999)
	for y:int in range(inner.position.y,inner.end.y):
		for x:int in range(inner.position.x,inner.end.x):
			if on.get_pixel(x,y).g-off.get_pixel(x,y).g > 0.08: point = Vector2(x,y)-shift; break
		if point.x > -99998: break
	check(point.x > -99998,"find an actual overhead cloud pixel inside the map for an occlusion probe")
	if point.x > -99998:
		var marker:=Polygon2D.new()
		marker.polygon = PackedVector2Array([Vector2(-5,-5),Vector2(5,-5),Vector2(5,5),Vector2(-5,5)])
		marker.color = Color.RED
		marker.position = point
		marker.z_as_relative = false
		marker.z_index = 0
		world.add_child(marker)
		await _frame()
		var pixel:Vector2i = Vector2i(point+shift)
		var with_cloud:Color = view.get_texture().get_image().get_pixelv(pixel)
		game.set_runtime_game_setting("Minecraft_Clouds",false,false)
		await _frame()
		var without_cloud:Color = view.get_texture().get_image().get_pixelv(pixel)
		check(with_cloud.g > without_cloud.g+0.2,"overhead cloud draws above a character-layer red marker")
		marker.queue_free()
	game.set_runtime_game_setting("Map_Background","grass",false)
	game.set_runtime_game_setting("Minecraft_Clouds",false,false)
	await _frame()
	await _frame()
	off = view.get_texture().get_image()
	game.set_runtime_game_setting("Minecraft_Clouds",true,false)
	await _frame()
	on = view.get_texture().get_image()
	check(changed(off,on,inner)==0,"grass-map background clouds do not paint over the arena or characters")
	check(changed(off,on,Rect2i(0,0,640,480))>100,"grass-map clouds remain visible in the surrounding background")
	check(on.get_data()==second.get_texture().get_image().get_data(),"two shared World2D recording-sized views see identical cloud placement and color")
	on.save_png("user://minecraft_clouds_flat_grass.png")
	world.day_night_cycle.set_minutes(0.0)
	await _frame()
	var night:Image = view.get_texture().get_image()
	var noon_sum:float = 0.0
	var night_sum:float = 0.0
	for y:int in range(0,480,4):
		for x:int in range(0,640,4):
			noon_sum += on.get_pixel(x,y).r
			night_sum += night.get_pixel(x,y).r
	check(night_sum < noon_sum*0.85,"existing day/night overlay darkens native clouds without darkening UI")
	world.day_night_cycle.set_minutes(720.0)
	game.set_runtime_game_setting("Map_Background","blue",false)
	await _frame()
	view.get_texture().get_image().save_png("user://minecraft_clouds_flat_blue.png")
	# A different zoom and center must not move the cloud's world anchor.
	second.canvas_transform = Transform2D(Vector2(2,0),Vector2(0,2),shift*2-Vector2(160,120))
	await _frame()
	check(second.get_texture().get_image().get_data()!=view.get_texture().get_image().get_data(),"independently zoomed capture uses its own projection, not the main viewport's screen UV")
	view.queue_free()
	second.queue_free()
	await process_frame

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	settings_existed = FileAccess.file_exists(game.SETTINGS_PATH)
	if settings_existed: settings_bytes = FileAccess.get_file_as_bytes(game.SETTINGS_PATH)
	create_timer(85.0,true,false,true).timeout.connect(func(): finish(2))
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Development_Mode = false
	game.Game_Settings.Map_Background = "blue"
	game.Game_Settings.Minecraft_Clouds = true
	game.now_stop_state = true
	AudioServer.set_bus_mute(0,true)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.set_physics_process(false)
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	world.control.hide()
	world.day_night_cycle.advancing = false
	world.day_night_cycle.set_minutes(720.0)
	cloud = world.minecraft_clouds
	check(is_instance_valid(cloud) and cloud.enabled and cloud.visible,"world creates enabled native clouds")
	check(cloud.overhead and cloud.z_index == 3000 and is_equal_approx(cloud.cloud_material.get_shader_parameter("parallax"),cloud.OVERHEAD_PARALLAX),"blue background selects overhead clouds below the day/night/UI layers")
	check(cloud.get_parent()==world and cloud.visibility_layer==1,"clouds belong to the shared world canvas, not a main-only CanvasLayer")
	var native:Image = cloud.CLOUD_TEXTURE.get_image()
	var occupied:int = 0
	for y:int in native.get_height():
		for x:int in native.get_width():
			if native.get_pixel(x,y).a>0.5: occupied += 1
	check(native.get_size()==Vector2i(256,256) and occupied==13356,"original 1.21.4 cloud occupancy survives import unchanged")
	check(not cloud.is_in_group("AI_Hazard") and not cloud.is_in_group("BattleTransient"),"persistent atmosphere is neither a threat nor a combat transient")
	check(not game._is_network_shared_setting("Minecraft_Clouds") and not game._shared_settings_snapshot().has("Minecraft_Clouds"),"cloud toggle stays local, not host-synchronized gameplay")
	cloud.advance(1.0)
	check(is_zero_approx(cloud.travel),"battle pause freezes drift")
	game.now_stop_state = false
	cloud.advance(2.0)
	check(is_equal_approx(cloud.travel,2.0*cloud.DRIFT_SPEED),"drift advances from scaled physics delta at the configured native speed")
	paused = true
	cloud.advance(1.0)
	paused = false
	check(is_equal_approx(cloud.travel,2.0*cloud.DRIFT_SPEED),"SceneTree pause freezes manual cloud updates too")
	cloud.advance(-1.0)
	cloud.advance(NAN)
	check(is_equal_approx(cloud.travel,2.0*cloud.DRIFT_SPEED),"invalid or negative delta cannot corrupt cloud motion")
	game.set_runtime_game_setting("Minecraft_Clouds",false,false)
	cloud.advance(10.0)
	check(not cloud.visible and is_equal_approx(cloud.travel,2.0*cloud.DRIFT_SPEED),"off switch immediately hides clouds and stops their clock")
	game.set_runtime_game_setting("Minecraft_Clouds",true,false)
	check(cloud.visible and is_equal_approx(cloud.travel,2.0*cloud.DRIFT_SPEED),"re-enabling resumes without a wall-time jump")
	game.set_runtime_game_setting("Map_Background","grass",false)
	check(not cloud.overhead and cloud.z_index==-5 and is_equal_approx(cloud.cloud_material.get_shader_parameter("parallax"),cloud.BACKGROUND_PARALLAX),"grass selects the farther background cloud plane")
	var center:Vector2 = world.return_map_world_rect(world._current_map_node()).get_center()
	var covers_center:bool = false
	for rect:Rect2 in cloud.regions: covers_center = covers_center or rect.has_point(center)
	check(not covers_center and cloud.regions.size()>=4,"grass cloud polygons use the world island complement, not a full-screen overlay")
	check(is_equal_approx(cloud.travel,2.0*cloud.DRIFT_SPEED),"map style changes preserve cloud phase")
	for theme:String in ["sand","stone","nether","end","courtyard3d","summit"]:
		game.set_runtime_game_setting("Map_Background",theme,false)
		check(not cloud.overhead and cloud.z_index==-5,"other tiled theme safely uses background mode: "+theme)
	var tested_islands:bool = false
	for key:Variant in world.map_group.keys():
		if world.map_island_rects(world.map_group[key]).size() < 2: continue
		world.now_choose_map = str(key)
		world.refresh_map_presentation()
		var no_overlap:bool = true
		for region:Rect2 in cloud.regions:
			for island:Rect2 in world._map_shape_visual(world._current_map_node()):
				no_overlap = no_overlap and not region.intersects(island)
		check(no_overlap,"multi-island background regions exclude every island footprint")
		tested_islands = true
		break
	check(tested_islands,"fixture exercises an actual multi-island map")
	world.now_choose_map = "Map10x10"
	game.set_runtime_game_setting("Map_Background","blue",false)
	check(cloud.overhead and cloud.regions.size()==1,"switching back to blue restores overhead mode without stale background geometry")
	var part_count:int = cloud._parts.size()
	for i:int in range(20): game.set_runtime_game_setting("Minecraft_Clouds",i%2==0,false)
	game.set_runtime_game_setting("Minecraft_Clouds",true,false)
	check(cloud._parts.size()==part_count,"repeated toggles reuse bounded polygon nodes")
	cloud.reset_drift()
	check(is_zero_approx(cloud.travel),"reset hook restores deterministic initial drift")
	game.now_stop_state = true
	var parameter_box:Node = world.control.settings_category_boxes["parameters"]
	var count:int = 0
	var button:TextureButton
	for node:Node in world.control._collect_descendants(parameter_box):
		if node is TextureButton and node.get_meta("game_setting_key","")=="Minecraft_Clouds": count += 1; button=node
	check(count==1 and button!=null,"Settings > Parameters has exactly one real cloud switch")
	if button!=null:
		button.button_up.emit()
		check(not cloud.visible and not game.Game_Settings.Minecraft_Clouds,"actual parameter button toggles the renderer")
		var cfg:=ConfigFile.new()
		check(cfg.load(game.SETTINGS_PATH)==OK and not bool(cfg.get_value("game_settings","Minecraft_Clouds",true)),"existing persistence path saves the selected cloud state")
		game.Game_Settings.Minecraft_Clouds = true
		game.load_persistent_settings()
		check(not game.Game_Settings.Minecraft_Clouds,"saved cloud choice survives settings reload")
		game.set_runtime_game_setting("Minecraft_Clouds",true,false)
	var catalog:Script = load("res://global/translation_catalog.gd")
	check(catalog.TABLE.zh.SETTING_MINECRAFT_CLOUDS=="原版方块云" and catalog.TABLE.en.SETTING_MINECRAFT_CLOUDS=="Minecraft Clouds","parameter switch has Chinese and English labels")
	await gpu_checks()
	var cloud_id:int = cloud.get_instance_id()
	game.now_stop_state = false
	cloud.advance(5.0)
	world.rematch_last_battle()
	check(is_equal_approx(cloud.travel,5.0*cloud.DRIFT_SPEED),"empty rematch does not reset cloud phase unexpectedly")
	world.reset()
	check(is_instance_valid(cloud) and cloud.get_instance_id()==cloud_id and is_zero_approx(cloud.travel),"actual world reset preserves atmosphere node and resets cloud phase")
	print("MINECRAFT_CLOUDS: %d checks / %d failures" % [checks,failures])
	finish(0 if failures==0 else 1)

func finish(code:int) -> void:
	if done: return
	if game != null:
		if settings_existed:
			var file:=FileAccess.open(game.SETTINGS_PATH,FileAccess.WRITE)
			file.store_buffer(settings_bytes)
			file.close()
		elif FileAccess.file_exists(game.SETTINGS_PATH): DirAccess.remove_absolute(ProjectSettings.globalize_path(game.SETTINGS_PATH))
	super.finish(code)
