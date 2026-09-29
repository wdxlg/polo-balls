extends "res://tests/test_terrain_visibility.gd"
## Actual summit view, frozen native actors/terrain, unchanged camera in every A/B.
var focus_camera:Camera2D
var arena:Rect2
var cloud:Node
var metrics:Array = []

func finish(code:int) -> void:
	if finished: return
	finished = true
	if not evidence.is_empty():
		var f:=FileAccess.open(evidence.path_join("focus_metrics.json"),FileAccess.WRITE)
		f.store_string(JSON.stringify({"checks":checks,"failures":failures,"metrics":metrics},"\t"))
		f.close()
	if is_instance_valid(world): world.queue_free()
	await create_timer(0.4,true,false,true).timeout
	if is_instance_valid(game):
		game.Game_Settings = saved
		game.now_stop_state = saved_stop
	print("BATTLE_FOCUS_RESULT checks=%d failures=%d" % [checks,failures])
	quit.call_deferred(code)

func set_focus(strength:float) -> void:
	if volume.has_method("apply_battle_focus"):
		volume.battle_focus_strength = strength
		volume.apply_battle_focus(volume._composite_material)

func lum(c:Color) -> float: return c.r*0.2126+c.g*0.7152+c.b*0.0722

func region_pixels(rect:Rect2,image:Image,view:Viewport) -> Rect2i:
	if view == null: return pixel_rect(rect,image)
	var transform:Transform2D = view.global_canvas_transform*view.canvas_transform
	var a:Vector2 = transform*rect.position
	var b:Vector2 = transform*rect.end
	return Rect2i(Vector2i(a.ceil()),Vector2i((b-a).floor()))

func actual_pixel_canvas() -> Transform2D:
	var scale:Vector2 = Vector2(root.get_texture().get_image().get_size())/root.get_visible_rect().size
	return Transform2D(Vector2(scale.x,0),Vector2(0,scale.y),Vector2.ZERO)*root.global_canvas_transform*root.canvas_transform

func compare_regions(before:Image,after:Image,view:Viewport = null) -> Dictionary:
	var protected:Rect2i = region_pixels(arena.grow(-12),before,view)
	var outside:Rect2i = region_pixels(arena.grow(42),before,view)
	var result:Dictionary = {"protected_changed":0,"protected_samples":0,"background_changed":0,"background_samples":0,"old_luma":0.0,"new_luma":0.0,"old_highlights":0.0,"new_highlights":0.0,"highlight_samples":0,"old_detail":0.0,"new_detail":0.0}
	for y:int in range(60,before.get_height()-40,3):
		for x:int in range(0,before.get_width()-3,3):
			var p:=Vector2i(x,y)
			var a:Color=before.get_pixelv(p)
			var b:Color=after.get_pixelv(p)
			if protected.has_point(p):
				result.protected_samples += 1
				if delta(a,b)>0.005: result.protected_changed += 1
			elif not outside.has_point(p):
				result.background_samples += 1
				if delta(a,b)>0.005: result.background_changed += 1
				result.old_luma += lum(a)
				result.new_luma += lum(b)
				result.old_detail += absf(lum(a)-lum(before.get_pixel(x+2,y)))
				result.new_detail += absf(lum(b)-lum(after.get_pixel(x+2,y)))
				if lum(a)>0.7:
					result.highlight_samples += 1
					result.old_highlights += lum(a)
					result.new_highlights += lum(b)
	return result

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	evidence = OS.get_environment("FOCUS_EVIDENCE_DIR")
	create_timer(180.0,true,false,true).timeout.connect(func():finish(2))
	if DisplayServer.get_name()=="headless":
		check(false,"actual GPU renderer required")
		await finish(1)
		return
	AudioServer.set_bus_mute(0,true)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Development_Mode = false
	game.Game_Settings.Map_Background = "summit"
	game.Game_Settings.Minecraft_Clouds = true
	game.now_stop_state = true
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	root.size = Vector2i(720,1280)
	world.set_physics_process(false)
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	world.control.hide()
	world.day_night_cycle.advancing = false
	world.day_night_cycle.set_minutes(720.0)
	volume = world.map_wall_volume
	cloud = world.minecraft_clouds
	arena = world.return_map_world_rect(world._current_map_node())
	var center:Vector2 = arena.get_center()
	focus_camera = Camera2D.new()
	world.add_child(focus_camera)
	focus_camera.make_current()
	focus_camera.global_position = center+Vector2(0,28)
	focus_camera.zoom = Vector2.ONE*3.2
	focus_camera.force_update_scroll()
	var cube:Node2D = fighter("硫方怪",center+Vector2(-30,-22))
	cube.show()
	cube._spawn_ice_tile(Rect2(center+Vector2(-48,-9),Vector2(32,16)))
	var cow:Node2D = fighter("雪傀儡",center+Vector2(38,-18))
	cow.Team = "Team1"
	cow.show()
	var cart:Node2D = fighter("矿车",center+Vector2(30,38))
	cart.show()
	cart._ensure_rails()
	var start:Vector2 = cart.rails.cell_to_world(cart.rails.world_to_cell(center+Vector2(-40,38)))
	game.now_stop_state = false
	var built:Dictionary = cart.rails.commit_path(cart,PackedVector2Array([start,start+Vector2(72,0)]))
	check(not built.is_empty() and not cart.rails.nodes.is_empty(),"native track data is present in the visual fixture")
	game.now_stop_state = true
	# Let the existing deferred rail renderer build its geometry before freezing.
	await frame()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	await frame()
	var original_transform:Transform2D = root.canvas_transform
	var original_projection:Projection = volume.camera.get_camera_projection()
	var sun_energy:float = volume.sun_light.light_energy
	var ambient:Environment = volume.viewport.get_node("BlockAmbientLight").environment
	var ambient_energy:float = ambient.ambient_light_energy
	if OS.get_environment("FOCUS_BASELINE")=="1":
		for clock:float in [720.0,0.0]:
			world.day_night_cycle.set_minutes(clock)
			await frame()
			save_image(root.get_texture().get_image(),"original_day" if clock>0 else "original_night")
		check(true,"unmodified production daylight/night screenshots captured with native actors, ice and rails")
		await finish(0)
		return
	check(volume.has_method("apply_battle_focus"),"shared summit focus controller exists")
	if not volume.has_method("apply_battle_focus"):
		await finish(1)
		return
	for clock:float in [720.0,0.0]:
		var phase:String = "day" if clock>0 else "night"
		world.day_night_cycle.set_minutes(clock)
		set_focus(0.0)
		await frame()
		var before:Image = root.get_texture().get_image()
		var raw_floor:Image = volume.floor_viewport.get_texture().get_image()
		save_image(before,"before_"+phase)
		set_focus(1.0)
		await frame()
		var after:Image = root.get_texture().get_image()
		save_image(after,"after_"+phase)
		var result:Dictionary = compare_regions(before,after)
		result.phase = phase
		metrics.append(result)
		print("FOCUS_METRICS ",JSON.stringify(result))
		check(result.protected_samples>1000 and result.protected_changed==0,phase+": actual floor, actors, health and native terrain stay pixel-identical")
		check(result.background_samples>1000 and result.background_changed>1000,phase+": adjustment is visibly present outside the arena")
		check(result.new_detail<result.old_detail,phase+": peripheral detail contrast is reduced without blurring")
		check(changed(raw_floor,volume.floor_viewport.get_texture().get_image())==0,phase+": actual 3D floor and its shadows are unchanged")
		if clock>0:
			check(result.highlight_samples>100 and result.new_highlights<result.old_highlights*0.95,"day: snow/cloud highlights are quieter")
		else:
			check(result.new_luma>result.old_luma*0.90,"night: no excessive extra darkening")
		check(cloud.cloud_material.get_shader_parameter("focus_daylight")==volume._focus_daylight,phase+": cloud grading tracks paused manual clock changes")
	check(volume.sun_light.light_energy==sun_energy and ambient.ambient_light_energy==ambient_energy,"shared real sunlight and ambient energy are unchanged")
	check(root.canvas_transform==original_transform and volume.camera.get_camera_projection()==original_projection,"camera center, zoom and projection are untouched by the adjustment")
	check(volume.floor_picture.get_instance_shader_parameter("focus_role")==null or float(volume.floor_picture.get_instance_shader_parameter("focus_role"))==0.0,"floor compositor is excluded from grading")
	await architecture_and_shared_views()
	await other_themes_unchanged()
	await finish(0 if failures==0 else 1)

func isolated_architecture() -> SubViewport:
	var view:=SubViewport.new()
	view.world_2d = World2D.new()
	view.size = root.get_texture().get_image().get_size()
	view.transparent_bg = true
	view.use_hdr_2d = root.use_hdr_2d
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var copy:Sprite2D = volume.picture.duplicate() as Sprite2D
	view.add_child(copy)
	copy.set_instance_shader_parameter("focus_role",2.0)
	copy.global_transform = volume.picture.global_transform
	view.canvas_transform = actual_pixel_canvas()
	return view

func architecture_and_shared_views() -> void:
	world.day_night_cycle.set_minutes(720.0)
	var arch:SubViewport = isolated_architecture()
	var shared:=SubViewport.new()
	shared.size = root.get_texture().get_image().get_size()
	shared.use_hdr_2d = root.use_hdr_2d
	shared.world_2d = root.world_2d
	shared.canvas_cull_mask = 1
	shared.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(shared)
	# Canvas transforms require the shared canvas to be attached to the viewport.
	shared.canvas_transform = actual_pixel_canvas()
	set_focus(0.0)
	await frame()
	var arch_before:Image = arch.get_texture().get_image()
	var shared_before:Image = shared.get_texture().get_image()
	set_focus(1.0)
	await frame()
	var arch_after:Image = arch.get_texture().get_image()
	var shared_after:Image = shared.get_texture().get_image()
	print("FOCUS_VIEW_TRANSFORMS root_texture=",root.get_texture().get_size()," root_image=",root.get_texture().get_image().get_size()," logical=",root.get_visible_rect().size," shared_size=",shared.size," shared_image=",shared_after.get_size()," canvas=",shared.canvas_transform)
	var covered:int = 0
	var modified:int = 0
	var alpha_changes:int = 0
	var bright_before:float = 0.0
	var bright_after:float = 0.0
	var bright_count:int = 0
	var luminances:Array[float] = []
	for yy:int in range(0,arch_before.get_height(),2):
		for xx:int in range(0,arch_before.get_width(),2):
			var c:Color = arch_before.get_pixel(xx,yy)
			if c.a>0.999: luminances.append(lum(c))
	luminances.sort()
	var bright_threshold:float = luminances[int(luminances.size()*0.80)] if not luminances.is_empty() else 1.0
	for y:int in range(0,arch_before.get_height(),2):
		for x:int in range(0,arch_before.get_width(),2):
			var a:Color = arch_before.get_pixel(x,y)
			var b:Color = arch_after.get_pixel(x,y)
			if absf(a.a-b.a)>0.001: alpha_changes += 1
			if a.a>0.999:
				covered += 1
				if delta(a,b)>0.005: modified += 1
				if lum(a)>=bright_threshold and lum(a)>0.001:
					bright_count += 1
					bright_before += lum(a)
					bright_after += lum(b)
	var arch_stats:Dictionary = {"phase":"architecture","covered":covered,"modified":modified,"alpha_changes":alpha_changes,"bright_count":bright_count,"bright_threshold":bright_threshold,"max_luminance":luminances[-1] if not luminances.is_empty() else 0.0,"old_highlights":bright_before,"new_highlights":bright_after}
	metrics.append(arch_stats)
	print("FOCUS_ARCHITECTURE ",JSON.stringify(arch_stats))
	check(covered>1000 and modified>20,"actual columns/seats receive a gentle visual adjustment")
	check(alpha_changes==0,"walls/columns/door openings keep their exact silhouettes and occlusion")
	check(bright_count>20 and bright_after<bright_before,"actual architectural highlights are reduced")
	var report:Dictionary = compare_regions(shared_before,shared_after,shared)
	report.phase = "shared_recording_view"
	metrics.append(report)
	print("FOCUS_SHARED ",JSON.stringify(report))
	check(report.protected_samples>1000 and report.protected_changed==0,"shared recording-style viewport preserves actors and terrain pixels")
	check(report.background_changed>1000 and report.new_detail<report.old_detail,"same world-space focus applies in a separate shared viewport")
	check(volume.background_viewport.find_world_3d()==volume.viewport.find_world_3d() and volume.floor_viewport.find_world_3d()==volume.viewport.find_world_3d(),"all three original channels still share one real World3D")
	var count:int = 0
	for child:Node in volume.get_children():
		if child is SubViewport: count += 1
	check(count==4,"grading adds no new production rendering viewport")
	arch.queue_free()
	shared.queue_free()
	await frame()

func other_themes_unchanged() -> void:
	for theme:String in ["blue","grass","sand","stone","nether","end"]:
		game.set_runtime_game_setting("Map_Background",theme,false)
		await frame()
		set_focus(0.0)
		await frame()
		var before:Image = root.get_texture().get_image()
		set_focus(1.0)
		await frame()
		var after:Image = root.get_texture().get_image()
		check(changed(before,after)==0,theme+": disabled summit grading leaves other themes pixel-identical")
		check(float(cloud.cloud_material.get_shader_parameter("focus_strength"))==0.0,theme+": cloud focus resets when leaving summit")
	game.set_runtime_game_setting("Map_Background","summit",false)
	await frame()
	check(float(volume._composite_material.get_shader_parameter("focus_strength"))==1.0 and float(cloud.cloud_material.get_shader_parameter("focus_strength"))==1.0,"switching back to summit restores both scenery and cloud grading")
	check(cloud.OVERHEAD_PARALLAX==1.25 and cloud.BACKGROUND_PARALLAX==1.25 and cloud.PLANE_DEPTH==1.0,"approved square cloud geometry and 1.25 parallax remain unchanged")
