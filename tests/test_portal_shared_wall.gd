extends SceneTree
var failures:int = 0
var checks:int = 0
func _initialize() -> void:
	call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error(label)
func run() -> void:
	create_timer(20.0).timeout.connect(func(): quit(2))
	var game:Node = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Map_Background = "grass"
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	var map:Node = world.get_node("Map_Portal")
	# 只改本测试实例，绝不保存/覆盖用户绘制的场景。
	for group:TileMapLayer in map.portal_groups():
		map.remove_child(group)
		group.queue_free()
	for child:Node in map.get_children():
		if child is TileMapLayer:
			map.remove_child(child)
			child.queue_free()
	# 不依赖用户场景的岛名或尺寸，创建独立的两岛测试夹具。
	var a := TileMapLayer.new()
	a.name = "IslandA"
	a.tile_set = load("res://addons/portal_map_editor/portal_brush.tres")
	for x:int in range(8):
		for y:int in range(8): a.set_cell(Vector2i(x,y),0,Vector2i.ZERO)
	map.add_child(a)
	var b := TileMapLayer.new()
	b.name = "IslandB"
	b.tile_set = a.tile_set
	b.tile_map_data = a.tile_map_data
	b.position = Vector2(144,0)
	map.add_child(b)
	var group:TileMapLayer = load("res://addons/portal_map_editor/portal_tiles.gd").new()
	group.name = "SharedWallBridge"
	group.direct_connection = true
	map.add_child(group)
	for y:int in range(3,6): group.set_cell(Vector2i(8,y),0,Vector2i.ZERO)
	map.collect_islands()
	world.now_choose_map = "Map_Portal"
	world.refresh_map_presentation()
	world.control.hide()
	await process_frame
	check(map.gates().size() == 2,"one painted bridge has two directly connected faces")
	var side_count:int = 0
	for node:Node in map.get_node("PortalVisuals").get_children():
		if str(node.name).begins_with("NotchSide"): side_count += 1
	check(side_count == 2,"shared bridge has exactly two side segments, without duplicate inward tails")
	var ra:Rect2 = map.island_rect("IslandA")
	var rb:Rect2 = map.island_rect("IslandB")
	var crossed:bool = false
	for node:Node in world.map_border_segment_root.get_children():
		if not node is Line2D: continue
		var line:Line2D = node as Line2D
		if line.points.size() < 2: continue
		var p:Vector2 = line.to_global(line.points[0])
		var q:Vector2 = line.to_global(line.points[1])
		var mid:Vector2 = (p+q)*0.5
		if ra.grow(-0.01).has_point(mid) or rb.grow(-0.01).has_point(mid): crossed = true
	check(not crossed,"actual world border nodes do not draw a shared-wall seam through either island")
	check(map.gates()[0].color == map.gates()[1].color,"both physical sides use the same layer tint")
	var shadow:Node = world.map_background_shadow
	check(shadow.footprints.size() >= 2 and world._island_extra_background_shadows.is_empty(),"two islands share one union shadow pass instead of alpha stacking")
	var solid:Vector2 = ra.position+Vector2(150,64)
	check(shadow.distance_to_union(solid) <= 0.0,"old seam shadow is not projected inside the neighboring island")
	var center:Vector2 = ra.position+Vector2(136,72)
	check(shadow.distance_to_union(center) > 0.0,"actual open corridor is outside the union footprint")
	var near_side:Vector2 = ra.position+Vector2(136,50)
	check(shadow.distance_to_union(near_side) < shadow.distance_to_union(center),"corridor shade follows its end walls, not the two virtual island seams")
	var particle_root:Node2D = map.get_node("PortalParticlesClipped")
	check(particle_root.z_index < world.map_outside_mask_root.z_index+world.z_index,"particles draw below the outside-map mask")
	var total:int = 0
	var ramp:Gradient = null
	var scale_curve:Curve = null
	var resource_shared:bool = true
	for clip:Control in particle_root.get_children():
		check(clip.clip_contents and clip.mouse_filter == Control.MOUSE_FILTER_IGNORE,"each emitter is additionally clipped by its own physical island rectangle")
		for emitter:Node in clip.get_children():
			if not emitter is CPUParticles2D: continue
			var particles:CPUParticles2D = emitter as CPUParticles2D
			total += particles.amount
			check(map.contains_point(particles.global_position),"particle emission begins inside a playable island")
			check(particles.fixed_fps == 30 and particles.preprocess == 0.0,"particle simulation uses 30Hz with no rebuild warmup burst")
			if ramp == null:
				ramp = particles.color_ramp
				scale_curve = particles.scale_amount_curve
			else:
				resource_shared = resource_shared and ramp == particles.color_ramp and scale_curve == particles.scale_amount_curve
	check(resource_shared and ramp != null,"emitters reuse fade and scale resources")
	check(total > 0 and total <= 256 and total < 56,"bridge particle count is width-based and bounded below old two-times-28 budget")
	world.map_outside_mask_enabled = false
	world.refresh_map_presentation()
	particle_root = map.get_node("PortalParticlesClipped")
	var clips_on:bool = true
	for clip:Control in particle_root.get_children(): clips_on = clips_on and clip.clip_contents
	check(clips_on,"particle clipping remains enabled even if the general world mask is disabled")
	world.map_outside_mask_enabled = true
	world.refresh_map_presentation()
	await create_timer(2.0).timeout
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/portal_shared_wall_preview.png")
		print("CAPTURE tests/portal_shared_wall_preview.png")
	# 独立压力场景：128 个分开的门面应仍受全图粒子预算限制。
	map.remove_child(b)
	b.queue_free()
	for x:int in range(64):
		for y:int in range(64): a.set_cell(Vector2i(x,y),0,Vector2i.ZERO)
	group.clear()
	for x:int in range(64):
		group.set_cell(Vector2i(x,-1),0,Vector2i(x%2,0))
		group.set_cell(Vector2i(x,64),0,Vector2i(x%2,0))
	map.collect_islands()
	map.rebuild_gates()
	map.refresh_visuals(2.0,-17.0,false)
	total = 0
	for clip:Control in map.get_node("PortalParticlesClipped").get_children():
		for emitter:Node in clip.get_children():
			if emitter is CPUParticles2D: total += emitter.amount
	check(map.gates().size() == 128 and total == 256,"128 gate faces still use at most 256 simulated particles in total")
	game.Game_Settings = saved
	world.queue_free()
	await process_frame
	print("SHARED_WALL checks=",checks," failures=",failures)
	quit(1 if failures else 0)
