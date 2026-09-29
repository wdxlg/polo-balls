extends SceneTree
var checks:int = 0
var failures:int = 0
const OUTPUT:String = "E:/godot/polo-balls-checkpoints/summit_lighting_clouds_20260926/"
func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures += 1
func frame() -> void:
	for i:int in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
func scenery_image(volume:Node) -> Image:
	var foreground:Image = volume.viewport.get_texture().get_image()
	if not is_instance_valid(volume.background_viewport) or not volume._background_active: return foreground
	var composed:Image = volume.background_viewport.get_texture().get_image()
	var floor_image:Image = volume.floor_viewport.get_texture().get_image()
	composed.blend_rect(floor_image,Rect2i(Vector2i.ZERO,floor_image.get_size()),Vector2i.ZERO)
	composed.blend_rect(foreground,Rect2i(Vector2i.ZERO,foreground.get_size()),Vector2i.ZERO)
	return composed
func safety(world:Node) -> Array[String]:
	var result:Array[String] = []
	for body:Node in world._map_safety_frame.find_children("*","StaticBody2D",true,false):
		var shape:CollisionShape2D = body.get_node_or_null("CollisionShape2D")
		if shape != null and shape.shape is RectangleShape2D: result.append(str(body.global_position)+str(shape.shape.size)+str(body.collision_layer))
	result.sort()
	return result
func run() -> void:
	create_timer(150).timeout.connect(func():quit(2))
	var game:Node = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	AudioServer.set_bus_mute(0,true)
	game.Game_Settings.Map_Background = "stone"
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	# Map-only fixture: do not race unrelated character prewarming during shutdown.
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.day_night_cycle.advancing = false
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	world.control.hide()
	var physical:Rect2 = world.map_island_rects(world.map_group["Map10x10"])[0]
	var before:Array[String] = safety(world)
	game.set_runtime_game_setting("Map_Background","summit",false)
	world.refresh_map_presentation()
	var view:=Camera2D.new()
	world.add_child(view)
	view.position = physical.get_center()
	view.zoom = Vector2.ONE*minf(root.get_visible_rect().size.x/(physical.size.x+310),root.get_visible_rect().size.y/(physical.size.y+310))
	view.make_current()
	await frame()
	var volume:Node = world.map_wall_volume
	var arena:Node = volume.summit_arena
	check(arena != null,"normal background setting instantiates summit arena")
	var range_ready:bool = arena != null and arena.landscape != null and arena.landscape.terrain is MeshInstance3D and arena.landscape.far_floor is MeshInstance3D and is_finite(arena.landscape.observed_min_height) and is_finite(arena.landscape.observed_max_height)
	check(range_ready,"range was built with real meshes and finite heights")
	if not range_ready:
		game.Game_Settings=saved
		world.queue_free()
		await process_frame
		print("SUMMIT_ARENA_RESULT checks=",checks," failures=",failures)
		quit(1)
		return
	check(arena.mountain.get_parent()==arena and arena.get_parent()==volume.viewport,"mountain and arena share live 3D world, camera and light")
	check(arena.mountain.find_children("*","MeshInstance3D",true,false).size()==17,"refined mountain retains all 17 authored mesh groups")
	check(arena.MOUNTAIN.resource_path.ends_with("shandian_natural.glb"),"main mountain uses natural apex and varied branch snow model")
	check(is_equal_approx(arena.mountain_source_bounds.end.y,109.875),"placement reads actual refined model bounds, not old flattened peak height")
	check(is_equal_approx((arena.mountain.global_transform*arena.mountain_source_bounds.end).y,arena.mountain_highest_y),"higher natural apex keeps the original world-space clearance ceiling")
	check(arena.mesh_count<=6,"arena geometry batched into at most six floor/architecture material meshes")
	check(arena.floor_regions==world.map_island_rects(world.map_group["Map10x10"]),"floor follows actual battle islands")
	check(arena.mountain_highest_y<0,"fixed mountain lowered below playable floor")
	check(safety(world)==before,"existing 2D safety collisions preserved")
	check(arena.find_children("*","CollisionObject3D",true,false).is_empty(),"no extra 3D gameplay collision")
	check(volume.z_index==-4,"scenery stays below tooltips and combat actors")
	check(volume.shadow_viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"no duplicate ground-shadow pass")
	check(game.ui_t("MAP_BACKGROUND_SUMMIT")!="MAP_BACKGROUND_SUMMIT","translated setting available")
	var found:bool = false
	for i:int in range(world.control.map_background_option.item_count):
		if world.control.map_background_option.get_item_metadata(i)=="summit": found=true
	check(found,"summit appears in normal settings dropdown")
	var clear:bool = true
	for decoration:Rect2 in arena.decoration_regions:
		for floor_rect:Rect2 in arena.floor_regions:
			if decoration.intersects(floor_rect): clear=false
	check(clear,"stands and columns never occupy playable floor")
	var image:Image = root.get_texture().get_image()
	check(not image.is_empty(),"actual GPU frame read back")
	image.convert(Image.FORMAT_RGBA8)
	if root.use_hdr_2d: image.linear_to_srgb()
	image.save_png(OUTPUT+"gameplay.png")
	var mirror:=SubViewport.new()
	mirror.size = Vector2i(root.get_visible_rect().size*0.5)
	mirror.world_2d = root.world_2d
	mirror.use_hdr_2d = root.use_hdr_2d
	mirror.canvas_cull_mask = 1
	mirror.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(mirror)
	mirror.canvas_transform = Transform2D(Vector2(0.5,0),Vector2(0,0.5),Vector2.ZERO)*root.get_canvas_transform()
	await frame()
	var main_pixels:Image = root.get_texture().get_image()
	var mirror_pixels:Image = mirror.get_texture().get_image()
	var difference:float = 0.0
	for y:int in range(-2,3):
		for x:int in range(-2,3):
			var probe:Vector2 = physical.get_center()+Vector2(float(x)*11.3,float(y)*13.1)
			var mp:Vector2i = Vector2i((root.get_canvas_transform()*probe)*Vector2(main_pixels.get_size())/root.get_visible_rect().size)
			var rp:Vector2i = Vector2i((mirror.canvas_transform*probe)*Vector2(mirror_pixels.get_size())/Vector2(mirror.size))
			difference += absf(main_pixels.get_pixelv(mp).get_luminance()-mirror_pixels.get_pixelv(rp).get_luminance())
	difference /= 25.0
	print("SUMMIT_SHARED_VIEWPORT_MEAN_LUMA_ERROR=",difference)
	check(difference<0.06,"shared recording-style viewport preserves arena appearance")
	mirror.render_target_update_mode = SubViewport.UPDATE_DISABLED
	mirror.queue_free()
	await process_frame
	var id_before:int = arena.get_instance_id()
	var point:Vector2 = physical.get_center()+Vector2(13.2,-5.7)
	for offset:Vector2 in [Vector2(7.35,-11.2),Vector2(-16.8,9.1)]:
		view.position = physical.get_center()+offset
		await frame()
		var projected:Vector2 = volume.camera.unproject_position(Vector3(point.x,0,point.y))/volume._render_scale
		check(projected.distance_to(root.get_canvas_transform()*point)<1.1,"fractional camera ground alignment")
	view.position = physical.get_center()
	world.day_night_cycle.set_minutes(0)
	await frame()
	check(arena.get_instance_id()==id_before,"night lighting does not rebuild mountain or arena")
	var night:Image = root.get_texture().get_image()
	night.convert(Image.FORMAT_RGBA8)
	if root.use_hdr_2d: night.linear_to_srgb()
	night.save_png(OUTPUT+"night.png")
	check(night.get_pixel(night.get_width()/2,night.get_height()/2).get_luminance()<image.get_pixel(image.get_width()/2,image.get_height()/2).get_luminance(),"night floor darker than noon")
	world.day_night_cycle.set_minutes(720)
	await frame()
	check(is_equal_approx(arena.PLATFORM_DROP_CELLS,0.3),"minimal floating platform has only a thin 0.3-cell underside")
	check(arena.MAX_SEAT_HEIGHT_CELLS<=0.45,"seating height reduced below half a cell")
	check(arena.column_count==4,"exactly four corner columns")
	check(arena.seat_segment_count==8,"two continuous bench spans on each side, not per-block piles")
	var source_meshes:Array[Mesh]=[]
	for mesh_node:MeshInstance3D in arena.mountain.find_children("*","MeshInstance3D",true,false): source_meshes.append(mesh_node.mesh)
	var landmark_count:int=0
	var landmarks_hidden:bool=true
	var shared_meshes:bool=true
	var actual_range_top:float=-INF
	for ridge:Node3D in arena.landscape.authored_instances:
		var meshes:Array[Node]=ridge.find_children("*","MeshInstance3D",true,false)
		if meshes.size()!=17: shared_meshes=false
		for mesh_node:MeshInstance3D in meshes:
			if mesh_node.mesh not in source_meshes: shared_meshes=false
			if String(mesh_node.name).to_lower().contains("landmark"):
				landmark_count+=1
				if mesh_node.visible: landmarks_hidden=false
			actual_range_top=maxf(actual_range_top,(mesh_node.global_transform*mesh_node.get_aabb().end).y)
	check(landmarks_hidden and landmark_count==arena.landscape.authored_instances.size()*3,"surrounding mountains do not repeat the original summit landmark")
	check(shared_meshes,"all surrounding ridges share the same 17 refined detailed meshes and materials")
	check(actual_range_top<arena.mountain_highest_y-world.map_visual_cell_size(world.map_group["Map10x10"]).x*4.0 and arena.backdrop_highest_y<arena.mountain_highest_y,"original mountain is highest above every secondary ridge")
	print("AUTHORED_RANGE instances=",arena.landscape.authored_instances.size()," highest=",actual_range_top," original=",arena.mountain_highest_y," bench_spans=",arena.seat_segment_count)
	var seat_material:StandardMaterial3D = arena.get_node("Seats").mesh.surface_get_material(0)
	check(not seat_material.albedo_texture.resource_path.contains("sandstone"),"no active sandstone on arena architecture")
	check(seat_material.albedo_color.b>=seat_material.albedo_color.r,"arena uses cool grey stone palette")
	check(arena.landscape.terrain is MeshInstance3D and arena.landscape.far_floor is MeshInstance3D,"continuous landscape is real 3D geometry")
	check(arena.landscape.max_peak_height<=-world.map_visual_cell_size(world.map_group["Map10x10"]).x*6.0,"range stays at least six cells below battle floor")
	check(arena.landscape.peak_count>=20,"many distinct peaks, not a single mountain or flat rock plane")
	check(arena.landscape.observed_max_height-arena.landscape.observed_min_height>world.map_visual_cell_size(world.map_group["Map10x10"]).x*15.0,"continuous range has deep valleys and substantial relief")
	check(arena.landscape.observed_max_height<=arena.landscape.max_peak_height,"all generated mountain vertices respect air-gap ceiling")
	print("FLOATING_RANGE peaks=",arena.landscape.peak_count," minimum=",arena.landscape.observed_min_height," maximum=",arena.landscape.observed_max_height)
	var clearance:float=-arena.PLATFORM_DROP_CELLS*world.map_visual_cell_size(world.map_group["Map10x10"]).x-maxf(arena.landscape.observed_max_height,maxf(arena.mountain_highest_y,arena.backdrop_highest_y))
	check(clearance>=arena.FLOATING_CLEARANCE_CELLS*world.map_visual_cell_size(world.map_group["Map10x10"]).x-0.01,"real air gap separates the entire arena from the mountains")
	check(arena.backdrop_highest_y<0,"authored rear mountain is also below floating arena")
	var intrusions:int=0
	for mountain_mesh:MeshInstance3D in arena.backdrop.find_children("*","MeshInstance3D",true,false):
		for surface_index:int in range(mountain_mesh.mesh.get_surface_count()):
			var positions:PackedVector3Array=mountain_mesh.mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_VERTEX]
			for vertex:Vector3 in positions:
				var position_3d:Vector3=mountain_mesh.global_transform*vertex
				if position_3d.y<=0: continue
				for island:Rect2 in arena.floor_regions:
					if island.has_point(Vector2(position_3d.x,position_3d.z)): intrusions+=1
	check(intrusions==0,"authored mountain never enters playable floor volume")
	check(arena.landscape.far_floor.material_override.uv1_world_triplanar,"world-space rock texture stays anchored while coverage expands")
	var terrain_id:int = arena.landscape.terrain.mesh.get_instance_id()
	var original_zoom:Vector2 = view.zoom
	for pose:Vector3 in [Vector3(0,0,1),Vector3(90.3,-74.5,0.65),Vector3(-133.2,112.7,1.3)]:
		view.position=physical.get_center()+Vector2(pose.x,pose.y)
		view.zoom=original_zoom*pose.z
		await frame()
		var rgba:Image=scenery_image(volume)
		var holes:int=0
		for yy:int in range(1,12):
			for xx:int in range(1,10):
				if rgba.get_pixel(int(float(xx)*rgba.get_width()/10.0),int(float(yy)*rgba.get_height()/12.0)).a<0.99: holes+=1
		check(holes==0,"no uncovered background across pan/zoom "+str(pose))
	check(arena.landscape.terrain.mesh.get_instance_id()==terrain_id and arena.landscape.build_count==1,"camera movement does not rebuild shared mountain geometry")
	view.position=physical.get_center()
	view.zoom=original_zoom
	await frame()
	var complete:Image=root.get_texture().get_image()
	complete.convert(Image.FORMAT_RGBA8)
	if root.use_hdr_2d: complete.linear_to_srgb()
	complete.save_png(OUTPUT+"gameplay.png")
	# Same world, diagnostic oblique camera only. Not a changed combat projection.
	RenderingServer.frame_pre_draw.disconnect(volume._sync_projection_before_draw)
	volume.camera.position = Vector3(physical.get_center().x+physical.size.x*1.5,physical.size.x*4.0,physical.get_center().y+physical.size.y*1.65)
	var combat_fov:float = volume.camera.fov
	volume.camera.fov = 52.0
	volume.camera.look_at(Vector3(physical.get_center().x,-physical.size.x*0.30,physical.get_center().y-physical.size.y*0.2))
	await frame()
	scenery_image(volume).save_png(OUTPUT+"oblique.png")
	volume.camera.fov = combat_fov
	volume.camera.rotation_degrees = Vector3(-90,0,0)
	RenderingServer.frame_pre_draw.connect(volume._sync_projection_before_draw)
	var owner:=Node2D.new()
	world.add_child(owner)
	owner.global_position = physical.position+Vector2(physical.size.x*0.5,18)
	var door:int = world.open_waiter_door(owner,38.0)
	world.refresh_map_presentation()
	await frame()
	check(door>=0,"waiter door still opens on summit")
	var g:Rect2 = Rect2(physical.get_center().x-18,physical.position.y-90,36,90)
	clear=true
	for decoration:Rect2 in volume.summit_arena.decoration_regions:
		if decoration.intersects(g):clear=false
	check(clear,"outside seating leaves doorway approach clear")
	world.close_waiter_door(door,0.0)
	for map_key:String in ["Map50x50","Map_Portal","Map10x10"]:
		world.now_choose_map=map_key
		world.refresh_map_presentation()
		await frame()
		check(volume.summit_arena.floor_regions==world.map_island_rects(world.map_group[map_key]),map_key+" adaptive floor coverage")
		check(volume.summit_arena.mesh_count<=6,map_key+" bounded scenery batches")
	for style:String in ["blue","grass","sand","stone","nether","end","summit"]:
		game.set_runtime_game_setting("Map_Background",style,false)
		world.refresh_map_presentation()
		await frame()
		check((volume.summit_arena != null)==(style=="summit"),style+" summit cleanup")
		check(volume.background_picture.visible==(style=="summit") and volume.floor_picture.visible==(style=="summit"),style+" scenery pass isolation")
		if style=="blue":check(not volume.visible,"blue stays 2D")
		elif style != "summit":check(volume.shadow_picture.visible,style+" old shadow pass restored")
	game.Game_Settings=saved
	world.queue_free()
	await process_frame
	print("SUMMIT_ARENA_RESULT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
