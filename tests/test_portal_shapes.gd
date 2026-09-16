extends SceneTree
const G = preload("res://classes/map_tile_geometry.gd")
var checks:int = 0
var failures:int = 0
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error(label)
func run() -> void:
	create_timer(25.0).timeout.connect(func(): quit(2))
	var game:Node = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Map_Background = "grass"
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	var map:Node = world.get_node("Map_Portal")
	map.global_transform = Transform2D.IDENTITY
	for child:Node in map.get_children():
		if child is TileMapLayer:
			map.remove_child(child)
			child.queue_free()
	var l := TileMapLayer.new()
	l.name = "ConcaveL"
	l.tile_set = load("res://addons/portal_map_editor/portal_brush.tres")
	var h := TileMapLayer.new()
	h.name = "HoledRing"
	h.tile_set = l.tile_set
	h.position = Vector2(256,0)
	for x:int in range(12):
		for y:int in range(12):
			if x < 4 or y >= 8: l.set_cell(Vector2i(x,y),0,Vector2i.ZERO)
			if x < 4 or x >= 8 or y < 4 or y >= 8: h.set_cell(Vector2i(x,y),0,Vector2i.ZERO)
	map.add_child(l)
	map.add_child(h)
	var group:TileMapLayer = load("res://addons/portal_map_editor/portal_tiles.gd").new()
	group.name = "InsideEdges"
	map.add_child(group)
	for y:int in range(4,7): group.set_cell(Vector2i(4,y),0,Vector2i.ZERO)
	for y:int in range(5,7): group.set_cell(Vector2i(20,y),0,Vector2i.ZERO)
	map.collect_islands()
	world.now_choose_map = "Map_Portal"
	world.refresh_map_presentation()
	world.control.hide()
	await process_frame
	var lr:Array[Rect2] = map.island_regions("ConcaveL")
	var hr:Array[Rect2] = map.island_regions("HoledRing")
	check(lr.size() == 2,"L ground merges into two regions, not its enclosing rectangle")
	check(hr.size() == 4,"ring ground preserves its internal hole")
	var area:float = 0.0
	for r:Rect2 in lr: area += r.get_area()
	check(is_equal_approx(area,80.0*256.0),"merged area equals exactly the painted L cells")
	check(map.island_at(Vector2(100,40)).is_empty(),"concave missing quadrant is outside")
	check(map.island_at(Vector2(352,96)).is_empty(),"enclosed unpainted hole is outside")
	check(map.island_at(Vector2(32,96)) == "ConcaveL","painted L arm remains valid ground")
	check(not world.can_place_character_at(Vector2(352,96)),"placement rejects enclosed hole")
	check(not world.can_place_character_at(Vector2(65,40)),"placement rejects even nearby unpainted cells")
	check(world.can_place_character_at(Vector2(32,128)),"placement across merged-region seam remains valid")
	check(G.edges(lr).size() == 6 and G.edges(hr).size() == 8,"exposed edges contain concavities and hole, without rectangle seams")
	check(map.gates().size() == 2,"two monochrome doors on concave and hole boundaries connect")
	var gate:Dictionary = map._find_gate(Vector2(61,88),Vector2(200,0),Vector2(3,3),0.016,true)
	check(not gate.is_empty(),"portal contact detects actual concave wall, not AABB edge")
	if not gate.is_empty():
		check(is_equal_approx(float(gate.entry.line),64.0) and is_equal_approx(float(gate.exit.line),320.0),"portal faces retain their distinct fixed edge coordinates")
		var arrival:Vector2 = map._map_position(gate,Vector2(61,88),Vector2(3,3))
		check(map.island_at(arrival) == "HoledRing" and arrival.x < 320.0,"hole-boundary transit arrives on ground side")
		check(map.gap_intervals("HoledRing",1,80,112,448).is_empty(),"inner-edge portal does not cut same-facing outer edge")
		var unsafe:bool = false
		for body:Node2D in world._map_safety_frame.get_children():
			var size:Vector2 = body.get_child(0).shape.size
			var wall:Rect2 = Rect2(body.global_position-size*0.5,size)
			for r:Rect2 in world.current_map_island_rects():
				if wall.intersection(r).get_area() > 0.001: unsafe = true
		check(not unsafe,"all collision walls lie outside painted ground, never on decomposition seams")
		check(world.map_inside_shadow.surface.polygons.size() == 6,"inner shadow mesh covers actual floor regions only")
		check(world.map_background_shadow.distance_to_union(Vector2(352,96)) > 0.0,"hole center remains outside union shadow footprint")
		check(not G.contains(world._map_shape_visual(map),Vector2(352,96)),"grass and wood preserve parallax at hole center")
		var clip:Control = map._particle_clip("HoledRing")
		check(clip.material is ShaderMaterial and clip.material.get_shader_parameter("ground_count") == 4,"particles use exact region clipping, not just rectangular Control clipping")
		game.now_stop_state = false
		map._burst_budget = 6
		map._play_transit_effects(gate,Vector2(61,88),arrival,12.0)
		var ring:Node2D = clip.get_node_or_null("PortalArrivalRing")
		check(ring != null and ring.global_position.is_equal_approx(arrival),"transit ring exists at destination")
		check(map._particle_clip("ConcaveL").get_node_or_null("PortalArrivalRing") == null,"no circular transit effect at departure")
		var audio:bool = false
		for player:Node in get_nodes_in_group("MCNativeSFX"):
			if player.get_meta("mc_sound_event","") == "entity.enderman.teleport": audio = true
		check(audio,"successful transit uses existing Enderman teleport audio event")
		if ring != null:
			check(ring.get_child_count() == 3 and ring.get_child(0) is Line2D and ring.get_child(0).material == clip.material,"arrival effect is glowing outline strokes with exact ground clipping")
			await create_timer(0.1).timeout
			check(is_instance_valid(ring) and ring.scale.x > 0.4 and ring.modulate.a < 1.0,"arrival outline expands and fades")
			if "--capture" in OS.get_cmdline_user_args():
				var camera := Camera2D.new()
				world.add_child(camera)
				camera.global_position = Vector2(224,96)
				camera.zoom = Vector2(2.0,2.0)
				camera.make_current()
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://tests/portal_shapes_preview.png")
				print("CAPTURE tests/portal_shapes_preview.png")
			await create_timer(0.5).timeout
			check(not is_instance_valid(ring),"arrival ring releases itself after fading")
	# Repaint existing layer in same frame: explicit collect must invalidate old geometry.
	l.set_cell(Vector2i(8,1),0,Vector2i.ZERO)
	map.collect_islands()
	check(map.island_at(Vector2(136,24)) == "ConcaveL","same-frame painted disconnected patch updates occupancy")
	l.erase_cell(Vector2i(8,1))
	map.collect_islands()
	check(map.island_at(Vector2(136,24)).is_empty(),"same-frame erasing removes ground without filling it")
	game.Game_Settings = saved
	print("PORTAL_SHAPES checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
