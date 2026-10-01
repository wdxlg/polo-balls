extends SceneTree
## Actual World composite, actual character effects. Not an isolated mock floor.
var checks:int = 0
var failures:int = 0
var game:Node
var world:Node
var volume:Node
var saved:Dictionary
var saved_stop:bool
var evidence:String
var finished:bool = false

func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)
func frame() -> void:
	for i:int in range(4): await process_frame
	await RenderingServer.frame_post_draw
func delta(a:Color,b:Color) -> float:
	return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))
func changed(a:Image,b:Image,rect:Rect2i = Rect2i()) -> int:
	var area:Rect2i = Rect2i(Vector2i.ZERO,a.get_size()) if rect.size==Vector2i.ZERO else rect.intersection(Rect2i(Vector2i.ZERO,a.get_size()))
	var count:int = 0
	for y:int in range(area.position.y,area.end.y,2):
		for x:int in range(area.position.x,area.end.x,2):
			if delta(a.get_pixel(x,y),b.get_pixel(x,y))>0.005: count += 1
	return count
func save_image(image:Image,key:String) -> void:
	if evidence.is_empty(): return
	var output:Image = image.duplicate()
	output.convert(Image.FORMAT_RGBA8)
	if root.use_hdr_2d: output.linear_to_srgb()
	output.save_png(evidence.path_join(key+".png"))
func finish(code:int) -> void:
	if finished: return
	finished = true
	if is_instance_valid(world): world.queue_free()
	await create_timer(0.4,true,false,true).timeout
	await RenderingServer.frame_post_draw
	if is_instance_valid(game):
		game.Game_Settings = saved
		game.now_stop_state = saved_stop
	print("TERRAIN_VISIBILITY_RESULT checks=%d failures=%d" % [checks,failures])
	# Return through all suspended fixture scopes before engine/resource teardown.
	quit.call_deferred(code)
func fighter(scene:String,point:Vector2) -> Node2D:
	var unit:Node2D = load("res://scenes/characters/我的世界/"+scene+".tscn").instantiate()
	unit.Team = "Team0"
	unit.position = point
	world.add_child(unit)
	unit.state_machine.set_physics_process(false)
	unit.set_physics_process(false)
	unit.hide()
	return unit
func pixel_rect(rect:Rect2,image:Image) -> Rect2i:
	var scale:Vector2 = Vector2(image.get_size())/root.get_visible_rect().size
	var a:Vector2 = (root.global_canvas_transform*root.canvas_transform*rect.position)*scale
	var b:Vector2 = (root.global_canvas_transform*root.canvas_transform*rect.end)*scale
	return Rect2i(Vector2i(a.ceil()),Vector2i((b-a).floor()))
func effect_pixels(effect:Variant,label:String,key:String,area:Rect2) -> int:
	var items:Array = effect if effect is Array else [effect]
	for item:CanvasItem in items: item.show()
	await frame()
	var shown:Image = root.get_texture().get_image()
	save_image(shown,key)
	for item:CanvasItem in items: item.hide()
	await frame()
	var hidden:Image = root.get_texture().get_image()
	var count:int = changed(shown,hidden,pixel_rect(area,shown))
	print("REAL_TERRAIN_PIXELS ",key," ",count)
	check(count>20,label+" changes actual game pixels above the opaque map floor")
	return count
func cross_layer_shadows() -> void:
	# Verify actual GPU behavior before relying on camera-layer separation:
	# a building culled from the floor camera must still cast onto its floor.
	var view:=SubViewport.new()
	view.size = Vector2i(256,256)
	view.own_world_3d = true
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var floor_mesh:=PlaneMesh.new()
	floor_mesh.size = Vector2(80,80)
	var floor_node:=MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	floor_node.layers = 1
	var material:=StandardMaterial3D.new()
	material.albedo_color = Color(0.7,0.7,0.7)
	floor_node.material_override = material
	view.add_child(floor_node)
	var box:=MeshInstance3D.new()
	var box_mesh:=BoxMesh.new()
	box_mesh.size = Vector3(7,10,7)
	box.mesh = box_mesh
	box.layers = 4
	box.position = Vector3(-6,5,-4)
	view.add_child(box)
	var sun:=DirectionalLight3D.new()
	sun.layers = 1|4
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 100.0
	sun.rotation_degrees = Vector3(-50,-40,0)
	view.add_child(sun)
	var camera:=Camera3D.new()
	camera.cull_mask = 1
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 50
	camera.position = Vector3(0,40,0)
	camera.rotation_degrees = Vector3(-90,0,0)
	view.add_child(camera)
	camera.make_current()
	await frame()
	var with_shadow:Image = view.get_texture().get_image()
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	await frame()
	var without_shadow:Image = view.get_texture().get_image()
	var pixels:int = changed(with_shadow,without_shadow)
	print("CROSS_CAMERA_LAYER_SHADOW_PIXELS ",pixels)
	# On this renderer camera culling also removes shadow casters. Do not mistake
	# an empty difference for correct lighting; check a positive control and proxy.
	camera.cull_mask = 1|4
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	await frame()
	var positive_shadow:Image = view.get_texture().get_image()
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	await frame()
	var positive_pixels:int = changed(positive_shadow,view.get_texture().get_image())
	print("SAME_CAMERA_LAYER_SHADOW_PIXELS ",positive_pixels)
	check(positive_pixels>40,"shadow probe positive control has real directional shadows")
	camera.cull_mask = 1
	var proxy:=MeshInstance3D.new()
	proxy.mesh = box.mesh
	proxy.layers = 1
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	box.add_child(proxy)
	await frame()
	var proxy_pixels:int = changed(view.get_texture().get_image(),without_shadow)
	print("SHARED_MESH_SHADOW_PROXY_PIXELS ",proxy_pixels)
	check(proxy_pixels>40,"shared-mesh shadows-only proxy retains shadows without an opaque building in floor pixels")
	view.queue_free()
	await process_frame

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	evidence = OS.get_environment("TERRAIN_EVIDENCE_DIR")
	create_timer(160.0,true,false,true).timeout.connect(func():finish(2))
	if DisplayServer.get_name()=="headless":
		check(false,"real GPU required for terrain visibility")
		await finish(1)
		return
	AudioServer.set_bus_mute(0,true)
	await cross_layer_shadows()
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Development_Mode = false
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Map_Background = "summit"
	game.Game_Settings.Minecraft_Clouds = false
	game.now_stop_state = true
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.set_physics_process(false)
	game.now_stop_state = true
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	world.set_process(false)
	world.control.hide()
	world.day_night_cycle.advancing = false
	world.day_night_cycle.set_minutes(720.0)
	volume = world.map_wall_volume
	var center:Vector2 = world.return_map_world_rect(world._current_map_node()).get_center()
	var cam:=Camera2D.new()
	world.add_child(cam)
	cam.make_current()
	cam.global_position = center
	cam.zoom = Vector2.ONE*minf(root.get_visible_rect().size.x/360.0,root.get_visible_rect().size.y/360.0)
	cam.force_update_scroll()
	await frame()
	save_image(root.get_texture().get_image(),"terrain_empty")
	var cube:Node2D = fighter("硫方怪",center+Vector2(0,-48))
	cube._spawn_ice_tile(Rect2(center-Vector2(32,8),Vector2(32,16)))
	var ice:CanvasItem = get_first_node_in_group("MCSulfurIceTrail") as CanvasItem
	check(is_instance_valid(ice) and ice.z_index==-4 and not ice.z_as_relative,"real Sulfur Cube spawns its unchanged absolute -4 ice trail")
	if is_instance_valid(ice): await effect_pixels(ice,"Sulfur ice trail","terrain_ice",ice.cell_rect.grow(-1))
	var cart:Node2D = fighter("矿车",center+Vector2(0,-48))
	cart._ensure_rails()
	var rails:Node2D = cart.rails
	var start:Vector2 = rails.cell_to_world(rails.world_to_cell(center+Vector2(-36,32)))
	game.now_stop_state = false
	var built:Dictionary = rails.commit_path(cart,PackedVector2Array([start,start+Vector2(72,0)]))
	game.now_stop_state = true
	check(not built.is_empty() and not rails.nodes.is_empty(),"real minecart commits a legal canonical track through its existing gameplay entry")
	await effect_pixels(rails,"Powered minecart rails","terrain_rails",Rect2(start-Vector2(10,10),Vector2(92,20)))
	var stone:Node2D = load("res://scripts/effects/我的世界/蠹虫石砖场.gd").new()
	world.add_child(stone)
	stone.setup(world,world._current_map_node())
	check(stone.z_index==-5 and not stone._render_chunks.is_empty(),"real silverfish stone chunks retain their below-blood layer")
	await effect_pixels(stone,"Silverfish stone field","terrain_stone",world.return_map_world_rect(world._current_map_node()).grow(-8))
	await structure_and_shadows(center)
	await more_native_terrain(center,cube)
	await occlusion_and_sampling(center,cube,ice,stone)
	# Existing effects survive theme rebuilds; no effect z-index repair is needed.
	for style:String in ["blue","grass","sand","stone","nether","end","summit"]:
		game.set_runtime_game_setting("Map_Background",style,false)
		await frame()
		await effect_pixels(ice,"Existing ice after "+style+" switch","ice_"+style,ice.cell_rect.grow(-1))
		await effect_pixels(rails,"Existing rails after "+style+" switch","rails_"+style,Rect2(start-Vector2(10,10),Vector2(92,20)))
		await effect_pixels(stone,"Existing stone after "+style+" switch","stone_"+style,world.return_map_world_rect(world._current_map_node()).grow(-8))
		check(world.map_background_tiles.z_index==(-7 if style=="summit" else -5),style+" restores only the appropriate map compatibility depth")
	game.now_stop_state = false
	ice._physics_process(2.8)
	game.now_stop_state = true
	check(ice._crack.visible and ice.age>=2.0 and ice.age<4.0,"original ice lifetime and crack stage remain active")
	await effect_pixels(ice,"Native cracking ice","terrain_cracked_ice",ice.cell_rect.grow(-1))
	var paused_age:float = ice.age
	await frame()
	check(is_equal_approx(ice.age,paused_age),"pause preserves the existing ice age")
	world.day_night_cycle.set_minutes(0.0)
	await effect_pixels(ice,"Ice at midnight","terrain_ice_night",ice.cell_rect.grow(-1))
	world.day_night_cycle.set_minutes(720.0)
	await finish(0 if failures==0 else 1)

func structure_and_shadows(center:Vector2) -> void:
	check(volume.floor_picture.z_index==-6 and volume.z_index==-4,"map floor is below all unchanged -5/-4 ground effects; architecture stays below status frames")
	check(volume.floor_viewport.find_world_3d()==volume.viewport.find_world_3d(),"floor and architecture use the same actual lit World3D")
	check(volume.floor_camera.get_camera_projection()==volume.camera.get_camera_projection(),"floor camera shares the final perspective projection")
	var point:Vector2i = Vector2i(volume.camera.unproject_position(Vector3(center.x,0,center.y)))
	var floor_image:Image = volume.floor_viewport.get_texture().get_image()
	var architecture:Image = volume.viewport.get_texture().get_image()
	check(floor_image.get_pixelv(point).a>0.99 and architecture.get_pixelv(point).a<0.001,"opaque center floor exists only in the lower pass, never in the wall image")
	var shared:bool = volume._terrain_shadow_casters.size()==7
	for proxy:MeshInstance3D in volume._terrain_shadow_casters:
		shared = shared and proxy.mesh==proxy.get_parent().mesh and proxy.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		if proxy.layers==volume.FLOOR_LAYER: proxy.hide()
	check(shared,"seven bounded shadow proxies reuse exact meshes instead of copying geometry or compensating light")
	await frame()
	var no_shadows:Image = volume.floor_viewport.get_texture().get_image()
	var shadow_pixels:int = changed(floor_image,no_shadows)
	print("ACTUAL_ARENA_FLOOR_SHADOW_PIXELS ",shadow_pixels)
	check(shadow_pixels>40,"real arena floor retains actual low-wall and column shadows across passes")
	for proxy:MeshInstance3D in volume._terrain_shadow_casters: proxy.show()
	await frame()

func more_native_terrain(center:Vector2,cube:Node2D) -> void:
	var snow:Node2D = fighter("雪傀儡",center+Vector2(-48,-32))
	var field:Node2D = snow._field
	var cell:Vector2i = field.cell_at(center)
	game.now_stop_state = false
	var deposited:bool = field.deposit(snow,cell)
	game.now_stop_state = true
	check(deposited and field.patches.has(cell),"real snow golem deposits a native snow tile through its unchanged entry")
	await effect_pixels(field,"Snow golem snow trail","terrain_snow",Rect2(field.point_at(cell)-Vector2(10,10),Vector2(20,20)))
	var moss:Node2D = fighter("苔藓",center+Vector2(-24,0))
	moss.show()
	moss.image.hide()
	moss.set_process(false)
	game.now_stop_state = false
	var planted:bool = moss.plant(center)
	game.now_stop_state = true
	moss.frontier_fx.set_process(false)
	moss.frontier_fx.queue_redraw()
	check(planted and not moss.patches.is_empty(),"real moss placement retains canonical patch data and native ground artwork")
	await effect_pixels(moss.frontier_fx,"Moss ground patch","terrain_moss",Rect2(center-Vector2(16,16),Vector2(32,32)))
	moss.hide()
	var spider:Node2D = fighter("蜘蛛",center+Vector2(-48,-48))
	spider.show()
	spider.image.hide()
	var silk:Node2D = get_first_node_in_group("MCSpiderSilk") as Node2D
	game.now_stop_state = false
	var attached:bool = true
	for offset:Vector2 in [Vector2(-32,-32),Vector2(32,32),Vector2(32,-32),Vector2(-32,32)]:
		silk._contact_left = 0.0
		attached = silk.touch_wall(center+offset) and attached
	silk._update_crossings()
	game.now_stop_state = true
	silk.queue_redraw()
	check(attached and not silk.webs.is_empty(),"completed real spider strands create a native web through the crossing algorithm")
	await effect_pixels(silk,"Spider strands and cobweb","terrain_web",Rect2(center-Vector2(28,28),Vector2(56,56)))
	spider.hide()
	var sheep:Node2D = fighter("羊",center+Vector2(-18,0))
	sheep.show()
	sheep.image.hide()
	sheep.set_process(false)
	sheep.ram_state = sheep.RamState.GRAZE
	sheep._update_graze_grass()
	var grass:Node2D = sheep._grass_patch
	check(grass.visible and grass.get_child_count()==1,"sheep's existing grazing state uses the one original grass tuft")
	await effect_pixels(grass,"Sheep grazing grass","terrain_grass",Rect2(grass.global_position-Vector2(16,24),Vector2(32,32)))
	sheep.hide()
	var fire:Node2D = load("res://scripts/effects/我的世界/烈焰火场.gd").new()
	world.add_child(fire)
	fire.setup(cube,cube.Team,center,20.0,4.5,0.5,0.11,2.2,0.05)
	fire.set_physics_process(false)
	fire._fire_block.pause()
	await effect_pixels(fire,"Blaze ground fire","terrain_fire",Rect2(center-Vector2(24,24),Vector2(48,48)))
	fire.queue_free()
	var area:Node2D = load("res://scripts/effects/我的世界/女巫药水区域.gd").new()
	world.add_child(area)
	area.global_position = center
	area.setup("poison",cube,28.0,5.2)
	area.set_physics_process(false)
	var particles:Array = []
	for i:int in range(24):
		area._spawn_area_particle()
		var particle:CanvasItem = world.get_child(world.get_child_count()-1) as CanvasItem
		particle.set_process(false)
		particles.append(particle)
	check(particles.size()==24 and particles[0].z_index==-3,"real witch area creates independent native particles at their existing depth")
	await effect_pixels(particles,"Witch lingering potion particles","terrain_potion",Rect2(center-Vector2(34,34),Vector2(68,68)))
	for particle:Node in particles: particle.queue_free()
	area.queue_free()
	var rose:Node2D = load("res://scripts/characters/我的世界/wither/rose.gd").new()
	world.add_child(rose)
	rose.global_position = center
	rose.configure(cube)
	rose.age = 0.6 # Settled visual phase; no fabricated textures or damage settlement.
	rose.set_physics_process(false)
	await effect_pixels(rose,"Normal Wither flower","terrain_flower",Rect2(center-Vector2(14,14),Vector2(28,28)))
	rose.become_wither()
	await effect_pixels(rose,"Converted Wither rose","terrain_rose",Rect2(center-Vector2(14,14),Vector2(28,28)))
	rose.queue_free()

func architecture_mask(image:Image) -> Image:
	var view:=SubViewport.new()
	view.size = image.get_size()
	view.world_2d = World2D.new()
	view.transparent_bg = true
	view.use_hdr_2d = root.use_hdr_2d
	view.msaa_2d = root.msaa_2d
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var copy:Sprite2D = volume.picture.duplicate() as Sprite2D
	view.add_child(copy)
	copy.global_transform = volume.picture.global_transform
	view.canvas_transform = root.get_stretch_transform()*root.canvas_transform
	view.global_canvas_transform = root.global_canvas_transform
	await frame()
	var result:Image = view.get_texture().get_image()
	view.queue_free()
	return result
func occlusion_and_sampling(center:Vector2,cube:Node2D,ice:Node2D,stone:Node2D) -> void:
	var bounds:Rect2 = world.return_map_world_rect(world._current_map_node())
	var sampler:Node = load("res://scripts/effects/地表渲染采样.gd").new()
	world.add_child(sampler)
	var ground:Dictionary = await sampler.capture(bounds.grow(48))
	volume.picture.hide()
	await frame()
	var ground_without_arch:Dictionary = await sampler.capture(bounds.grow(48))
	check(not ground.is_empty() and changed(ground.image,ground_without_arch.image)==0,"existing real ground sampler includes floor but excludes above-ground architecture")
	volume.picture.show()
	volume.floor_picture.hide()
	await frame()
	var missing_floor:Dictionary = await sampler.capture(bounds.grow(48))
	check(changed(ground.image,missing_floor.image)>100,"ground-sampling test actually sees the new 3D floor, not a fallback or empty snapshot")
	volume.floor_picture.show()
	await frame()
	sampler.queue_free()
	var base:Image = root.get_texture().get_image()
	var mask:Image = await architecture_mask(base)
	var large:Node2D = load("res://scripts/effects/我的世界/sulfur_ice_trail.gd").new()
	world.add_child(large)
	large.setup(cube,bounds.grow(75))
	await frame()
	var with_ice:Image = root.get_texture().get_image()
	var opaque:int = 0
	var covered:int = 0
	for y:int in range(2,base.get_height()-2,2):
		for x:int in range(2,base.get_width()-2,2):
			var inside:bool = true
			for dy:int in range(-1,2):
				for dx:int in range(-1,2):
					inside = inside and mask.get_pixel(x+dx,y+dy).a>0.999
			if not inside: continue
			opaque += 1
			if delta(base.get_pixel(x,y),with_ice.get_pixel(x,y))>0.005: covered += 1
	print("GROUND_VS_ARCHITECTURE opaque_interior=",opaque," improperly_covered=",covered)
	check(opaque>100 and covered==0,"late-spawned actual ice remains behind opaque walls, benches and columns")
	check(changed(base,with_ice,pixel_rect(bounds.grow(-8),base))>100,"occlusion test is nonvacuous: same real ice is visible across the floor")
	large.queue_free()
	await frame()
	# Controlled depth swatches test blood and body ordering without running a
	# damage settlement or fabricating a character's artwork.
	var swatches:Array[Polygon2D] = []
	for depth:int in [-4,-2]:
		var probe:=Polygon2D.new()
		probe.polygon = PackedVector2Array([center-Vector2(7,7),center+Vector2(7,-7),center+Vector2(7,7),center+Vector2(-7,7)])
		probe.color = Color(0.9,0.05,0.05) if depth==-4 else Color(0.8,0.8,0.05)
		probe.z_as_relative = false
		probe.z_index = depth
		world.add_child(probe)
		swatches.append(probe)
		stone.show()
		ice.show()
		await frame()
		var covered_floor:Image = root.get_texture().get_image()
		stone.hide()
		ice.hide()
		await frame()
		var bare_floor:Image = root.get_texture().get_image()
		check(changed(covered_floor,bare_floor,pixel_rect(Rect2(center-Vector2(5,5),Vector2(10,10)),bare_floor))==0,"ground remains below the "+("blood" if depth==-4 else "actor")+" depth probe")
	for probe:Node in swatches: probe.queue_free()
	await frame()
