extends SceneTree
# Real GPU integration: source lighting, mountain/cloud/arena composition and retired settings.
const THEMES = preload("res://scripts/effects/我的世界/地图背景主题.gd")
var checks:int = 0
var failures:int = 0
var game:Node
var world:Node
var volume:Node
var cloud:Node
var saved:Dictionary
var saved_stop:bool
var done:bool = false
var evidence:String

func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)
func finish(code:int) -> void:
	if done: return
	done = true
	if is_instance_valid(game):
		game.Game_Settings = saved
		game.now_stop_state = saved_stop
	if is_instance_valid(world): world.queue_free()
	await process_frame
	print("SCENERY_LAYERS_RESULT checks=%d failures=%d" % [checks,failures])
	quit(code)
func frame() -> void:
	for i:int in range(4): await process_frame
	await RenderingServer.frame_post_draw
func difference(a:Color,b:Color) -> float:
	return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))
func luma(a:Color) -> float: return a.r*0.2126+a.g*0.7152+a.b*0.0722
func capture() -> Image: return root.get_texture().get_image()
func mask_for(image:Image) -> Image:
	# Measure the actual 2D composite alpha, not raw 3D texels: fractional world/UV
	# reprojection can shift a silhouette sample by one texel at a nearest-filtered edge.
	var mask_view:=SubViewport.new()
	mask_view.size = image.get_size()
	# Isolate the swatch from live World2D BackBufferCopy/clip passes.
	mask_view.world_2d = World2D.new()
	mask_view.transparent_bg = true
	mask_view.use_hdr_2d = root.use_hdr_2d
	mask_view.msaa_2d = root.msaa_2d
	mask_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(mask_view)
	for source:Sprite2D in [volume.floor_picture,volume.picture]:
		var composite:Sprite2D = source.duplicate() as Sprite2D
		mask_view.add_child(composite)
		composite.global_transform = source.global_transform
	print("MASK_ROOT_TRANSFORMS size=",image.get_size()," logical=",root.get_visible_rect().size," final=",root.get_final_transform()," stretch=",root.get_stretch_transform())
	# A viewport texture excludes the Window letterbox offset. Use its actual
	# stretch only, then the same world canvas as the live composite.
	mask_view.canvas_transform = root.get_stretch_transform()*root.canvas_transform
	mask_view.global_canvas_transform = root.global_canvas_transform
	await frame()
	var mask:Image = mask_view.get_texture().get_image()
	mask_view.queue_free()
	return mask
func compare(a:Image,b:Image,mask:Image) -> Dictionary:
	var result:Dictionary = {"foreground_changed":0,"background_changed":0,"foreground_count":0,"background_count":0,"foreground_interior_count":0,"edge_changed":0,"interior_changed":0}
	for y:int in range(int(a.get_height()*0.15),int(a.get_height()*0.95),4):
		for x:int in range(0,a.get_width(),4):
			var alpha:float = mask.get_pixel(x,y).a
			var changed:bool = difference(a.get_pixel(x,y),b.get_pixel(x,y))>0.005
			if alpha>0.999:
				result.foreground_count += 1
				# At fractional Window stretch, separately rasterized nearest masks
				# can disagree at an exact half-texel silhouette by one pixel.
				# Count/report that fringe separately; opaque interiors are strict.
				var interior:bool = x>0 and x<a.get_width()-1 and y>0 and y<a.get_height()-1
				if interior:
					for dy:int in range(-1,2):
						for dx:int in range(-1,2): interior = interior and mask.get_pixel(x+dx,y+dy).a>0.999
				if interior: result.foreground_interior_count += 1
				if changed:
					result.foreground_changed += 1
					if interior: result.interior_changed += 1
					else: result.edge_changed += 1
			elif alpha<0.001:
				result.background_count += 1
				if changed: result.background_changed += 1
	return result

func save_image(image:Image,name:String) -> void:
	if evidence.is_empty(): return
	var view:Image = image.duplicate()
	view.convert(Image.FORMAT_RGBA8)
	if root.use_hdr_2d: view.linear_to_srgb()
	view.save_png(evidence.path_join(name+".png"))
func same_projection() -> bool:
	for pass_camera:Camera3D in [volume.background_camera,volume.floor_camera]:
		if volume.camera.get_camera_projection()!=pass_camera.get_camera_projection() or not volume.camera.global_transform.is_equal_approx(pass_camera.global_transform): return false
	return volume.viewport.size==volume.background_viewport.size and volume.viewport.size==volume.floor_viewport.size
func layers_are(node:Node,mask:int) -> bool:
	for mesh:MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		if mesh.layers!=mask: return false
	return true

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	evidence = OS.get_environment("SUMMIT_EVIDENCE_DIR")
	create_timer(170.0,true,false,true).timeout.connect(func():finish(2))
	if DisplayServer.get_name()=="headless":
		check(false,"GPU renderer required; do not replace compositing evidence with headless checks")
		await finish(1)
		return
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Development_Mode = false
	game.Game_Settings.Map_Background = "courtyard3d"
	game.Game_Settings.Minecraft_Clouds = true
	game.now_stop_state = true
	AudioServer.set_bus_mute(0,true)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	# Keep normal visual/clip synchronization alive; freeze battle and clock instead.
	game.now_stop_state = true
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	world.control.hide()
	world.day_night_cycle.advancing = false
	world.day_night_cycle.set_minutes(720.0)
	check(THEMES.OPTIONS.size()==7 and not THEMES.OPTIONS.has("courtyard3d"),"seven supported choices; courtyard removed from registry")
	check(THEMES.normalize("courtyard3d")=="blue" and world.map_background_style()=="blue","retired saved choice safely resolves to blue without rewriting user settings")
	check(world.control.map_background_option.get_selected_metadata()=="blue" and world.control.map_background_option.item_count==7,"real settings dropdown shows the safe fallback and no retired option")
	check(not FileAccess.file_exists("res://scripts/effects/courtyard_3d.gd") and not DirAccess.dir_exists_absolute("res://Images/backgrounds/courtyard3d"),"retired implementation and exclusive assets removed")
	var catalog:Script = load("res://global/translation_catalog.gd")
	check(not catalog.TABLE.zh.has("MAP_BACKGROUND_COURTYARD3D") and not catalog.TABLE.en.has("MAP_BACKGROUND_COURTYARD3D"),"retired Chinese and English labels removed")
	var original_base_z:int = world.get_node("Background").z_index
	var original_base_relative:bool = world.get_node("Background").z_as_relative
	game.set_runtime_game_setting("Map_Background","summit",false)
	volume = world.map_wall_volume
	cloud = world.minecraft_clouds
	var cam:=Camera2D.new()
	world.add_child(cam)
	cam.make_current()
	cam.position_smoothing_enabled = false
	var center:Vector2 = world.return_map_world_rect(world._current_map_node()).get_center()
	cam.global_position = center
	cam.zoom = Vector2.ONE*minf(root.get_visible_rect().size.x/510.0,root.get_visible_rect().size.y/510.0)
	cam.force_update_scroll()
	await frame()
	check(volume.viewport.find_world_3d()==volume.background_viewport.find_world_3d() and volume.viewport.find_world_3d()==volume.floor_viewport.find_world_3d(),"mountains and arena share the identical live World3D, sun and environment")
	check(same_projection(),"foreground and background cameras have identical actual projection and transform")
	check(volume.camera.cull_mask==volume.FOREGROUND_LAYER and volume.background_camera.cull_mask==volume.SCENERY_LAYER and volume.floor_camera.cull_mask==volume.FLOOR_LAYER,"cameras differ only in semantic visibility masks")
	check(layers_are(volume.summit_arena.mountain,volume.SCENERY_LAYER) and layers_are(volume.summit_arena.backdrop,volume.SCENERY_LAYER) and layers_are(volume.summit_arena.landscape,volume.SCENERY_LAYER),"all authored mountains and valley floor use the background channel")
	check(cloud.between_layers and not cloud.overhead and cloud.regions.size()==1,"summit cloud plane extends continuously under real 3D foreground alpha")
	check(volume.background_picture.z_index<cloud.z_index and cloud.z_index<volume.floor_picture.z_index and volume.floor_picture.z_index<-5 and volume.z_index==-4,"explicit mountain < cloud < floor < character terrain < architecture order")
	check(world.map_outside_grid_root.z_index<volume.background_picture.z_index and world.get_node("Background").z_index<world.map_outside_grid_root.z_index,"original blue sprite and fallback grid cannot hide the mountains")
	var no_emission:bool = true
	for surface:int in volume.mesh_node.mesh.get_surface_count():
		var material:StandardMaterial3D = volume.mesh_node.mesh.surface_get_material(surface) as StandardMaterial3D
		no_emission = no_emission and material!=null and not material.emission_enabled
	check(no_emission,"map wall materials use real scene light rather than per-theme emission compensation")
	# Render the same material at the same point in both passes: catches mismatched light,
	# exposure, camera overrides and accidental independent World3D creation.
	var probes:Array[MeshInstance3D] = []
	var white:=StandardMaterial3D.new()
	white.albedo_color = Color(0.6,0.6,0.6)
	white.roughness = 1.0
	var probe_mesh:=PlaneMesh.new()
	probe_mesh.size = Vector2(24,24)
	for layer:int in [volume.FOREGROUND_LAYER,volume.SCENERY_LAYER,volume.FLOOR_LAYER]:
		var probe:=MeshInstance3D.new()
		probe.mesh = probe_mesh
		probe.material_override = white
		probe.layers = layer
		probe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		probe.position = Vector3(center.x,80,center.y)
		volume.viewport.add_child(probe)
		probes.append(probe)
	var mountain_id:int = volume.summit_arena.mountain.get_instance_id()
	for minutes:float in [720.0,1080.0,0.0]:
		world.day_night_cycle.set_minutes(minutes)
		await frame()
		var point:Vector2i = Vector2i(volume.camera.unproject_position(probes[0].global_position).round())
		var a:Color = volume.viewport.get_texture().get_image().get_pixelv(point)
		var b:Color = volume.background_viewport.get_texture().get_image().get_pixelv(point)
		var c:Color = volume.floor_viewport.get_texture().get_image().get_pixelv(point)
		print("SCENERY_LIGHT_PROBE minutes=",minutes," foreground=",a," scenery=",b," floor=",c," error=",maxf(difference(a,b),difference(a,c)))
		check(a.a>0.99 and b.a>0.99 and c.a>0.99 and difference(a,b)<0.005 and difference(a,c)<0.005,"identical material receives identical actual GPU lighting at minute "+str(minutes))
	check(is_zero_approx(volume.sun_light.shadow_opacity) and is_zero_approx(volume.shadow_picture.modulate.a),"night fades direct 3D shadows and old-map catcher shadows once each")
	check(volume.summit_arena.mountain.get_instance_id()==mountain_id,"day/night changes do not rebuild authored geometry")
	for probe:MeshInstance3D in probes: probe.queue_free()
	world.day_night_cycle.set_minutes(720.0)
	game.set_runtime_game_setting("Minecraft_Clouds",false,false)
	await frame()
	var without_clouds:Image = capture()
	var mask:Image = await mask_for(without_clouds)
	volume.background_picture.hide()
	await frame()
	var without_mountains:Image = capture()
	volume.background_picture.show()
	var background_stats:Dictionary = compare(without_clouds,without_mountains,mask)
	print("MOUNTAIN_VISIBILITY ",background_stats)
	check(background_stats.background_changed>500,"mountains are visible in the actual game composite, not merely in an offscreen viewport")
	check(background_stats.interior_changed==0,"removing mountains cannot alter opaque arena, bench or column interiors")
	game.set_runtime_game_setting("Minecraft_Clouds",true,false)
	await frame()
	var noon:Image = capture()
	save_image(noon,"scenery_noon")
	var cloud_stats:Dictionary = compare(without_clouds,noon,mask)
	print("CLOUD_COMPOSITE ",cloud_stats)
	check(cloud_stats.foreground_interior_count>100 and cloud_stats.background_count>1000,"GPU masks contain both actual arena architecture and surrounding scenery")
	check(cloud_stats.background_changed>500,"native clouds visibly overlay mountains in the actual game composite")
	check(cloud_stats.interior_changed==0,"clouds never cover opaque arena floor, perimeter wall, bench or column interiors")
	# Prove that the test is not vacuous: those same clouds would cover arena pixels
	# if the actual foreground 3D pass were hidden.
	volume.picture.hide()
	volume.floor_picture.hide()
	await frame()
	var exposed_clouds:Image = capture()
	game.set_runtime_game_setting("Minecraft_Clouds",false,false)
	await frame()
	var exposed_clear:Image = capture()
	var overlap:Dictionary = compare(exposed_clear,exposed_clouds,mask)
	print("CLOUD_BEHIND_FOREGROUND ",overlap)
	check(overlap.interior_changed>100,"clouds really pass behind foreground geometry; no footprint masking hides the overlap")
	volume.picture.show()
	volume.floor_picture.show()
	game.set_runtime_game_setting("Minecraft_Clouds",true,false)
	world.day_night_cycle.set_minutes(0.0)
	await frame()
	var night:Image = capture()
	save_image(night,"scenery_midnight")
	var day_cloud:float = 0.0
	var night_cloud:float = 0.0
	var day_map:float = 0.0
	var night_map:float = 0.0
	for y:int in range(int(noon.get_height()*0.15),int(noon.get_height()*0.95),8):
		for x:int in range(0,noon.get_width(),8):
			if mask.get_pixel(x,y).a>0.999:
				day_map += luma(noon.get_pixel(x,y)); night_map += luma(night.get_pixel(x,y))
			elif difference(noon.get_pixel(x,y),without_clouds.get_pixel(x,y))>0.05:
				day_cloud += luma(noon.get_pixel(x,y)); night_cloud += luma(night.get_pixel(x,y))
	check(day_cloud>1.0 and night_cloud<day_cloud*0.8,"visible clouds participate in the same world night tint")
	check(day_map>1.0 and night_map<day_map*0.8,"arena participates in the same world night tint")
	world.day_night_cycle.set_minutes(720.0)
	for sample:Vector3 in [Vector3(21.37,-14.29,0.65),Vector3(-34.41,28.71,1.3)]:
		cam.global_position = center+Vector2(sample.x,sample.y)
		cam.zoom = Vector2.ONE*sample.z
		cam.force_update_scroll()
		await frame()
		check(same_projection(),"fractional pan/zoom keeps all actual 3D projections synchronized")
	var pass_id:int = volume.background_viewport.get_instance_id()
	var floor_pass_id:int = volume.floor_viewport.get_instance_id()
	for style:String in ["grass","stone","blue","summit","blue"]:
		game.set_runtime_game_setting("Map_Background",style,false)
		await frame()
		check(volume.background_picture.visible==(style=="summit") and volume.floor_picture.visible==(style=="summit"),style+" activates only its required scenery composite")
		check(volume.background_viewport.render_target_update_mode==(SubViewport.UPDATE_ALWAYS if style=="summit" else SubViewport.UPDATE_DISABLED) and volume.floor_viewport.render_target_update_mode==volume.background_viewport.render_target_update_mode,style+" does not waste a hidden scenery render")
		if style!="summit":
			check(world.get_node("Background").z_index==original_base_z and world.get_node("Background").z_as_relative==original_base_relative,style+" restores the original base background depth exactly")
	check(volume.background_viewport.get_instance_id()==pass_id and volume.floor_viewport.get_instance_id()==floor_pass_id,"repeated theme switches reuse bounded background and floor viewports")
	await finish(0 if failures==0 else 1)
