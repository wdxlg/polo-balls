extends "res://tests/test_training_events_snow_gpu.gd"
## Actual production generator and unified map-block view, with legacy record compatibility.
var metrics:Array = []

func tile_for(record:Dictionary) -> Rect2:
	return record.get("tile",Rect2(FIELD.point_at(record.cell)-Vector2.ONE*FIELD.CELL*0.5,Vector2.ONE*FIELD.CELL))

func finish(code:int) -> void:
	if done: return
	if not capture_dir.is_empty():
		var f:=FileAccess.open(capture_dir.path_join("metrics.json"),FileAccess.WRITE)
		f.store_string(JSON.stringify({"checks":checks,"failures":failures,"metrics":metrics},"\t"))
		f.close()
	print("ENVIRONMENT_SNOW_GRID checks=",checks," failures=",failures)
	await super.finish(code)

func run() -> void:
	game = root.get_node("Game")
	original_settings = game.Game_Settings.duplicate(true)
	original_locale = game.current_locale
	settings_file = game.SETTINGS_PATH
	settings_existed = FileAccess.file_exists(settings_file)
	if settings_existed: settings_bytes = FileAccess.get_file_as_bytes(settings_file)
	game.Game_Settings.Environment = "none"
	game.Game_Settings.Development_Mode = false
	game.Game_Settings.Minecraft_Clouds = false
	game.Game_Settings.Map_Background = "grass"
	root.size = Vector2i(960,720)
	root.content_scale_size = root.size
	await setup_world()
	saved = original_settings
	create_timer(140,true,false,true).timeout.connect(func():finish(2))
	capture_dir = OS.get_environment("SNOW_GRID_EVIDENCE_DIR")
	if capture_dir.is_empty(): capture_dir = "user://environment_snow_grid_test"
	DirAccess.make_dir_recursive_absolute(capture_dir)
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	conditions = world.battle_conditions
	conditions.set_physics_process(false)
	world.set_physics_process(false)
	world.set_process(false)
	world.versus_label.hide()
	for layer:CanvasLayer in world.find_children("*","CanvasLayer",true,false): layer.hide()
	var center:Vector2 = world.return_map_world_rect(world._current_map_node()).get_center()
	var actor:Node2D = spawn(GOLEM_PATH,center)
	actor.set_physics_process(false)
	actor.health_bar.hide()
	var victim:Node2D = dummy(center+Vector2(-10000,-10000))
	victim.set_physics_process(false)
	victim.hide()
	setting("Environment","snow")
	game.begin_battle_random(78231)
	conditions.refresh_layout(true)
	var field:Node2D = conditions.field
	field.set_physics_process(false)
	await physics_frame
	await physics_frame
	check(field.environment_patches.is_empty(),"block-sized environment still begins with no prelaid snow")
	var size:Vector2 = world.map_visual_cell_size(world._current_map_node())
	var origin:Vector2 = conditions._ground[0].position
	var floor_count:int = 0
	var wall_count:int = 0
	var wrong_size:int = 0
	var misaligned:int = 0
	for record:Dictionary in conditions._ground_candidates+conditions._wall_candidates:
		var tile:Rect2 = tile_for(record)
		if not tile.size.is_equal_approx(size): wrong_size += 1
		var at:Vector2 = (tile.position-origin)/size
		if not at.is_equal_approx(at.round()): misaligned += 1
		if record.decorative: wall_count += 1
		else: floor_count += 1
	metrics.append({"phase":"candidates","map_cell":size,"ground":floor_count,"walls":wall_count,"wrong_size":wrong_size,"misaligned":misaligned})
	check(floor_count>20 and wall_count>10,"real generator exposes ground and wall candidates")
	check(wrong_size==0,"each environmental footprint is exactly one actual map block")
	check(misaligned==0,"environment ground and wall cells follow the map block origin")
	check(FIELD.CELL==16.0,"golem fallback grid now matches the normal map block size")
	game.now_stop_state = false
	for i:int in range(80): conditions.advance(0.5)
	game.now_stop_state = true
	var actual:Dictionary = field.environment_patches.duplicate(true)
	check(actual.size()>20,"actual production advancement accumulates block-sized environment snow")
	var geometry_ok:bool = true
	for record:Dictionary in actual.values():
		geometry_ok = geometry_ok and tile_for(record).size.is_equal_approx(size)
		if not record.decorative:
			for rect:Rect2 in record.rects: geometry_ok = geometry_ok and rect.size.is_equal_approx(size)
	check(geometry_ok,"stored/rendered environment rectangles keep the map-block dimensions")
	await process_frame
	# Headless geometry checks cannot await a window presentation signal.
	field.wall_view._sync_geometry()
	if DisplayServer.get_name()!="headless": await grab()
	if done: return
	var view:Node2D = field.wall_view
	check(is_instance_valid(view.mesh_node),"wall accumulation builds actual 3D snow geometry")
	if is_instance_valid(view.mesh_node):
		check(is_equal_approx(view.snow_thickness,minf(size.x,size.y)*2.0/16.0),"wall snow keeps native 2/16 thickness relative to one WALL block")
		var wrong_pieces:int = 0
		for cell:Vector2i in actual:
			if not actual[cell].decorative: continue
			for piece:Dictionary in view.projected_pieces(cell,actual[cell]):
				if not (piece.rect as Rect2).size.is_equal_approx(size): wrong_pieces += 1
		check(wrong_pieces==0,"uncut block walls receive whole one-block snow tops, not 24-unit strips")
	await check_precise_contact(field,victim,actor,size)
	if DisplayServer.get_name()!="headless":
		var camera:=Camera2D.new()
		world.add_child(camera)
		camera.make_current()
		camera.global_position = center
		camera.zoom = Vector2.ONE*3.8
		camera.force_update_scroll()
		view.weather_enabled = false
		view.weather_fade = 0.0 # Explicit bare-image fixture, not a gameplay toggle.
		view.queue_redraw()
		await grab("block_alignment")
		camera.zoom = Vector2.ONE*0.70
		camera.force_update_scroll()
		await check_full_weather(view,camera,center)
		await check_shared_weather_corners(view,center)
		setting("Map_Background","blue")
		setting("Minecraft_Clouds",true)
		world.minecraft_clouds.refresh()
		conditions.refresh_layout()
		await check_full_weather(view,camera,center,"blue_clouds")
	await check_other_layouts(field)
	setting("Environment","none")
	check(not view.weather_enabled and field.environment_patches.is_empty(),"None stops snowfall and keeps an already-bare rebuilt layout empty")
	await finish(0 if failures==0 else 1)

func check_precise_contact(field:Node2D,victim:Node2D,actor:Node2D,size:Vector2) -> void:
	var saved_environment:Dictionary = field.environment_patches.duplicate(true)
	field.clear_environment()
	field.patches.clear()
	# Exact geometry intentionally disagrees with the legacy 24-unit lookup key.
	var tile:=Rect2(Vector2(48,48),size)
	var record:Dictionary = {"cell":Vector2i(3,3),"decorative":false,"rects":[tile],"tile":tile}
	field.add_environment_patch(conditions,record)
	game.now_stop_state = false
	clear_cold(victim)
	park_contact(field,victim,tile.get_center())
	var hp:int = victim.health
	field.check_ground()
	check(victim.health==hp-3,"damage is applied INSIDE the actual one-block snow footprint")
	clear_cold(victim)
	park_contact(field,victim,Vector2(tile.end.x+1,tile.get_center().y))
	hp = victim.health
	field.check_ground()
	check(victim.health==hp,"no invisible cold damage just OUTSIDE the resized snow footprint")
	var info:Dictionary = field.get_debug_hazard_info()
	check(info.get("parts",[]).size()==1 and (info.parts[0].position as Vector2).is_equal_approx(tile.get_center()) and (info.parts[0].half_extents as Vector2).is_equal_approx(size*0.5),"threat geometry matches the actual block, not the old trail grid")
	# A fast crossing and adjacent 16-unit tiles must not alias the 24-unit trail grid.
	park_contact(field,victim,Vector2(40,56))
	victim.global_position = Vector2(72,56)
	hp = victim.health
	field.check_ground()
	check(victim.health==hp-3,"swept motion detects the resized tile between its endpoints")
	clear_cold(victim)
	check(field.deposit(actor,field.snow_cell_at(tile.get_center()),false),"golem and environment snow can coexist at the same actual map block")
	info = field.get_debug_hazard_info()
	var area:float = 0.0
	for part:Dictionary in info.get("parts",[]): area += part.half_extents.x*part.half_extents.y*4.0
	check(is_equal_approx(area,16.0*16.0),"threat union subtracts the true overlap of two same-size snow layers")
	park_contact(field,victim,Vector2(62,62))
	hp = victim.health
	field.check_ground()
	field.check_ground()
	check(victim.health==hp-3,"overlapping one-block snow still shares exactly one target cooldown")
	field.patches.clear()
	var before_break:Dictionary = field.environment_patches.duplicate(true)
	actor.take_damage(float(actor.Max_health)*0.5,true)
	check(not actor.has_pumpkin and field.environment_patches==before_break,"half-health pumpkin fracture does not consume permanent environment snow")
	check(not field.has_method("_land_head") and not field.has_method("_spawn_mini"),"environment grid exposes no retired construction path")
	park_contact(field,victim,tile.get_center())
	hp = victim.health
	field.check_ground()
	check(victim.health==hp-3,"environment snow and its sparse contact index remain effective after head fracture")
	var second:Dictionary = record.duplicate(true)
	second.cell = Vector2i(5,3)
	second.tile = Rect2(Vector2(80,48),size)
	second.rects = [second.tile]
	field._environment_state([record,second],true)
	field.development_begin_merge(func(point:Vector2):return "left" if point.x<72 else "right",{"left":Vector2(-16,0),"right":Vector2(16,0)})
	field.development_preview_merge({}, {"left":{"offset":Vector2.ZERO},"right":{"offset":Vector2.ZERO}})
	field.development_finish_merge()
	check(field.environment_patches.size()==1 and field.environment_patches.has(Vector2i(4,3)),"development merge deduplicates coincident MAP blocks without 24-unit snapping")
	check(tile_for(field.environment_patches.values()[0])==Rect2(Vector2(64,48),size),"development merge preserves exact block size and translated geometry")
	park_contact(field,victim,Vector2(72,56))
	hp = victim.health
	field.check_ground()
	check(victim.health==hp-3,"translated permanent snow rebuilds the actual contact index")
	var local_walls:Array[Rect2] = field.wall_view.visual_walls.duplicate()
	record.decorative = true
	record.rects = [Rect2(48,48,6,16),Rect2(58,48,6,16)]
	var split_walls:Array[Rect2] = [Rect2(48,48,6,16),Rect2(58,48,6,16)]
	field.wall_view.visual_walls = split_walls
	var pieces:Array = field.wall_view.projected_pieces(record.cell,record)
	var no_door_cover:bool = pieces.size()==2
	var door:=Rect2(54,48,4,16)
	for piece:Dictionary in pieces: no_door_cover = no_door_cover and not piece.rect.intersects(door)
	check(no_door_cover,"one-block wall snow clips around a real support gap instead of bridging it")
	field.wall_view.visual_walls = local_walls
	field._environment_state([record],true)
	check(field.get_debug_hazard_info().is_empty(),"16-unit decorative wall pieces remain entirely harmless")
	clear_cold(victim)
	field._environment_state(saved_environment.values(),true)
	game.now_stop_state = true

func changed_corners(a:Image,b:Image) -> Array[int]:
	var w:float = a.get_width()
	var h:float = a.get_height()
	var size:=Vector2(minf(140,w*0.2),minf(140,h*0.2))
	var regions:Array[Rect2] = [Rect2(Vector2(16,16),size),Rect2(Vector2(w-size.x-16,16),size),Rect2(Vector2(16,h-size.y-16),size),Rect2(Vector2(w-size.x-16,h-size.y-16),size)]
	var result:Array[int] = []
	for rect:Rect2 in regions: result.append(changed_in(rect,a,b,Transform2D.IDENTITY))
	return result

func check_full_weather(view:Node2D,camera:Camera2D,center:Vector2,label:String = "grass") -> void:
	view.weather_time = 2.3
	view.weather_fade = 1.0
	for offset:Vector2 in [Vector2.ZERO,Vector2(1400,-1000)]:
		camera.global_position = center+offset
		camera.force_update_scroll()
		view.weather_enabled = false
		view.weather_fade = 0.0 # Explicit bare-image fixture, not a gameplay toggle.
		view.queue_redraw()
		var bare:Image = await grab()
		view.weather_enabled = true
		view.weather_fade = 1.0
		view.queue_redraw()
		var snow:Image = await grab(label+"_full_"+("center" if offset==Vector2.ZERO else "panned"))
		var corners:Array[int] = changed_corners(bare,snow)
		metrics.append({"phase":label,"offset":offset,"corner_changes":corners,"image_size":snow.get_size()})
		print("FULL_SCREEN_SNOW ",label," offset=",offset," corners=",corners)
		for i:int in range(4): check(corners[i]>60,label+": real falling snow reaches corner "+str(i)+(" after distant pan" if offset!=Vector2.ZERO else " outside the map"))
		var frozen:Image = await grab()
		var frozen_corners:Array[int] = changed_corners(snow,frozen)
		check(frozen_corners==[0,0,0,0],label+": paused full-screen snowfall stays pixel-identical outside animated actors")
	camera.global_position = center
	camera.force_update_scroll()

func check_shared_weather_corners(view:Node2D,center:Vector2) -> void:
	var capture:=SubViewport.new()
	capture.size = Vector2i(640,1000)
	capture.world_2d = root.world_2d
	capture.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(capture)
	capture.canvas_transform = Transform2D(0.0,Vector2(0.6,0.6),0.0,Vector2(capture.size)*0.5-(center+Vector2(-1800,1300))*0.6)
	view.weather_enabled = false
	view.weather_fade = 0.0 # Explicit bare-image fixture, not a gameplay toggle.
	view.queue_redraw()
	await grab()
	var bare:Image = capture.get_texture().get_image()
	view.weather_enabled = true
	view.weather_fade = 1.0
	view.queue_redraw()
	await grab()
	var snow:Image = capture.get_texture().get_image()
	snow.save_png(capture_dir+"/shared_portrait_full.png")
	var corners:Array[int] = changed_corners(bare,snow)
	metrics.append({"phase":"shared_portrait","corner_changes":corners})
	for i:int in range(4): check(corners[i]>60,"independent portrait shared view gets weather in corner "+str(i))
	capture.render_target_update_mode = SubViewport.UPDATE_DISABLED
	capture.queue_free()
	await process_frame

func check_other_layouts(field:Node2D) -> void:
	for style:String in ["blue","grass","sand","stone","nether","end","summit"]:
		setting("Map_Background",style)
		conditions.refresh_layout(true)
		await process_frame
		var size:Vector2 = world.map_visual_cell_size(world._current_map_node())
		var origin:Vector2 = conditions._ground[0].position
		var correct:bool = not conditions._ground_candidates.is_empty() and not conditions._wall_candidates.is_empty()
		for record:Dictionary in conditions._ground_candidates+conditions._wall_candidates:
			var tile:Rect2 = tile_for(record)
			var at:Vector2 = (tile.position-origin)/size
			correct = correct and tile.size.is_equal_approx(size) and at.is_equal_approx(at.round())
			if not record.decorative:
				var area:Array[Rect2] = [tile]
				correct = correct and conditions.GEOMETRY.subtract(area,conditions._ground).is_empty()
		check(correct,style+": production candidates retain one-block sizing, origin and floor support")
		if style=="blue":
			var clipped:bool = true
			for record:Dictionary in conditions._wall_candidates:
				for rect:Rect2 in record.rects: clipped = clipped and minf(rect.size.x,rect.size.y)<size.x*0.5
			check(clipped,"blue theme keeps its thin support frame rather than inventing full block walls")
	setting("Map_Background","grass")
	var map:Node2D = world._current_map_node()
	var old_transform:Transform2D = map.transform
	map.scale = Vector2(1.5,2.0)
	map.position += Vector2(7,11)
	world.refresh_map_presentation()
	conditions.refresh_layout(true)
	var expected:Vector2 = world.map_visual_cell_size(map)
	var correct:bool = expected.is_equal_approx(Vector2(24,32)) and not conditions._ground_candidates.is_empty()
	var origin:Vector2 = conditions._ground[0].position
	for record:Dictionary in conditions._ground_candidates+conditions._wall_candidates:
		var tile:Rect2 = tile_for(record)
		var at:Vector2 = (tile.position-origin)/expected
		correct = correct and tile.size.is_equal_approx(expected) and at.is_equal_approx(at.round())
	check(correct,"nonuniformly scaled/translated map uses its actual 24x32 blocks, not a hard-coded 16 or 24")
	map.transform = old_transform
	world.refresh_map_presentation()
	conditions.refresh_layout(true)
	check(field.environment_patches.is_empty(),"changing layout from a bare setup does not seed preexisting snow")
