extends SceneTree
var failures:int = 0
var checks:int = 0
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error(label)
func fixture(positions:Array[Vector2]) -> Node:
	var map:Node = load("res://classes/portal_map.gd").new()
	for i:int in range(positions.size()):
		var island := TileMapLayer.new()
		island.name = "Island%d" % i
		island.position = positions[i]
		island.tile_set = load("res://addons/portal_map_editor/portal_brush.tres")
		for x:int in range(4):
			for y:int in range(4): island.set_cell(Vector2i(x,y),0,Vector2i.ZERO)
		map.add_child(island)
	var group:TileMapLayer = load("res://addons/portal_map_editor/portal_tiles.gd").new()
	group.name = "Portals"
	map.add_child(group)
	root.add_child(map)
	map.collect_islands()
	map._portal_rng.seed = 271828
	return map
func paint(group:TileMapLayer,blue:Array[Vector2i],red:Array[Vector2i] = []) -> void:
	group.clear()
	for cell:Vector2i in blue: group.set_cell(cell,0,Vector2i.ZERO)
	for cell:Vector2i in red: group.set_cell(cell,0,Vector2i(1,0))
func from_face(map:Node,side:int,u:float,chars:bool = true) -> Dictionary:
	var rect:Rect2 = map.island_rect("Island0")
	var point:Vector2
	var velocity:Vector2
	match side:
		0:
			point = Vector2(rect.position.x+1,u)
			velocity = Vector2.LEFT*100
		1:
			point = Vector2(rect.end.x-1,u)
			velocity = Vector2.RIGHT*100
		2:
			point = Vector2(u,rect.position.y+1)
			velocity = Vector2.UP*100
		_:
			point = Vector2(u,rect.end.y-1)
			velocity = Vector2.DOWN*100
	return map._find_gate(point,velocity,Vector2(4,4),1.0/60.0,chars)
func run() -> void:
	create_timer(20.0).timeout.connect(func(): quit(2))
	var map:Node = fixture([Vector2.ZERO])
	var group:TileMapLayer = map.get_node("Portals")
	paint(group,[Vector2i(4,1)])
	map.rebuild_gates()
	check(map.gates().is_empty(),"single blue door without direct bridge is inactive")
	group.direct_connection = true
	map.rebuild_gates()
	check(map.gates().is_empty(),"direct switch alone does not activate a door touching only one island")
	paint(group,[Vector2i(4,1),Vector2i(1,4)])
	group.direct_connection = false
	map.rebuild_gates()
	check(map.gates().size() == 2,"two blue doors on the same island connect both ways")
	var routed:Dictionary = from_face(map,1,24)
	check(not routed.is_empty() and routed.entry.island == routed.exit.island and routed.door_id != routed.destination_id,"same-island transit never chooses its own door")
	check(map._map_vector(routed,Vector2.RIGHT).is_equal_approx(Vector2.UP),"right-to-bottom exit rotates travel automatically inward")
	var destination:Vector2 = map._map_position(routed,Vector2(63,24),Vector2(4,4))
	check(destination.x >= 20 and destination.x <= 28 and destination.y < 64,"arrival fits inside destination door span")
	paint(group,[Vector2i(4,1),Vector2i(1,4),Vector2i(1,-1)])
	map.rebuild_gates()
	var mono_seen:Dictionary = {}
	var no_self:bool = true
	for i:int in range(120):
		routed = from_face(map,1,24)
		mono_seen[routed.destination_id] = true
		no_self = no_self and routed.destination_id != routed.door_id
	check(mono_seen.size() == 2 and no_self,"single-color three-door group randomly reaches either other door, never itself")
	paint(group,[],[Vector2i(4,1),Vector2i(1,4)])
	map.rebuild_gates()
	check(map.gates().size() == 2,"red-only doors obey the same rules as blue-only doors")
	paint(group,[Vector2i(4,1)],[Vector2i(-1,0),Vector2i(1,-1),Vector2i(1,4)])
	map.rebuild_gates()
	var seen:Dictionary = {}
	var opposite_only:bool = true
	for i:int in range(300):
		routed = from_face(map,1,24)
		if routed.is_empty():
			opposite_only = false
			continue
		seen[routed.destination_id] = int(seen.get(routed.destination_id,0))+1
		opposite_only = opposite_only and routed.exit_color_id == 1
	check(opposite_only and seen.size() == 3,"one blue randomly reaches every red door, not the first red only")
	var balanced:bool = true
	for count:int in seen.values(): balanced = balanced and count > 50 and count < 150
	check(balanced,"destination sampling is distributed across doors")
	var back_ok:bool = true
	for side:int in [0,2,3]:
		routed = from_face(map,side,8 if side == 0 else 24)
		back_ok = back_ok and not routed.is_empty() and routed.exit.side == 1 and routed.exit_color_id == 0
	check(back_ok,"all red doors return to the sole blue door")
	group.set_cell(Vector2i(4,3),0,Vector2i.ZERO)
	map.rebuild_gates()
	seen.clear()
	for i:int in range(150):
		routed = from_face(map,0,8)
		if not routed.is_empty(): seen[routed.destination_id] = true
	check(seen.size() == 2,"multiple red and blue doors route randomly to opposite color")
	group.pass_mode = 1
	map.rebuild_gates()
	check(not from_face(map,1,24,true).is_empty() and from_face(map,1,24,false).is_empty(),"characters-only blocks projectiles")
	group.pass_mode = 2
	map.rebuild_gates()
	check(from_face(map,1,24,true).is_empty() and not from_face(map,1,24,false).is_empty(),"projectiles-only blocks characters")
	group.pass_mode = 0
	map.rebuild_gates()
	check(not from_face(map,1,24,true).is_empty() and not from_face(map,1,24,false).is_empty(),"both mode allows characters and projectiles")
	paint(group,[Vector2i(4,0),Vector2i(4,1),Vector2i(4,3)])
	map.rebuild_gates()
	check(group.portal_doors(map).size() == 2,"same-color connected cells are one door, separated cells are distinct doors")
	check(group.portal_doors(map)[0].faces[0].b-group.portal_doors(map)[0].faces[0].a == 32.0,"connected brush cells merge into a continuous door face")
	paint(group,[Vector2i(4,0)],[Vector2i(4,1)])
	map.rebuild_gates()
	check(group.portal_doors(map).size() == 2 and map.gates().size() == 2,"adjacent different colors remain separate connected doors")
	var second:TileMapLayer = load("res://addons/portal_map_editor/portal_tiles.gd").new()
	map.add_child(second)
	paint(group,[Vector2i(4,0)])
	paint(second,[],[Vector2i(1,4)])
	map.rebuild_gates()
	check(map.gates().is_empty(),"different TileMapLayers are isolated groups, not globally paired")
	# 两个图层画到同一段墙：门归先出现的图层，后面的图层这扇门整体作废且不作为目的地。
	paint(group,[Vector2i(4,1),Vector2i(1,4)])
	paint(second,[Vector2i(4,1),Vector2i(-1,0)],[Vector2i(1,-1)])
	map.rebuild_gates()
	var first_gates:int = 0
	var second_gates:int = 0
	var second_ok:bool = true
	for gate:Dictionary in map.gates():
		if gate.group_id == group.get_instance_id(): first_gates += 1
		elif gate.group_id == second.get_instance_id():
			second_gates += 1
			second_ok = second_ok and int(gate.entry.side) != 1
			for option:Dictionary in gate.destinations:
				for face:Dictionary in option.faces: second_ok = second_ok and int(face.side) != 1
	check(first_gates == 2 and second_gates == 2 and second_ok,"overlapping door belongs to the earlier layer; later layer ignores it as entry and destination")
	check(map.shadowed_doors(second).size() == 1 and map.shadowed_doors(group).is_empty(),"later layer reports exactly its shadowed door for editor warnings")
	routed = from_face(map,1,24)
	check(not routed.is_empty() and routed.group_id == group.get_instance_id() and routed.exit.side == 3,"entering the shared wall uses the earlier layer's pairing")
	second.queue_free()
	await process_frame
	map.queue_free()
	await process_frame
	map = fixture([Vector2.ZERO,Vector2(80,0)])
	group = map.get_node("Portals")
	paint(group,[Vector2i(4,1)])
	map.rebuild_gates()
	check(group.portal_doors(map).size() == 1 and group.portal_doors(map)[0].faces.size() == 2,"one painted gap cell detects both adjacent island faces")
	check(map.gates().is_empty(),"single bridge cell remains inactive when direct connection is off")
	group.direct_connection = true
	map.rebuild_gates()
	routed = from_face(map,1,24)
	check(map.gates().size() == 2 and not routed.is_empty() and routed.exit.island == "Island1" and routed.direct,"direct connection activates both sides of a single bridge door")
	check(map._map_vector(routed,Vector2.RIGHT).is_equal_approx(Vector2.RIGHT),"direct left-to-right bridge preserves travel direction")
	group.direct_connection = false
	group.set_cell(Vector2i(1,-1),0,Vector2i(1,0))
	map.rebuild_gates()
	routed = from_face(map,1,24)
	check(not routed.is_empty() and routed.exit.side == 2 and not routed.direct,"without direct mode bridge waits for another door and routes to that door")
	group.direct_connection = true
	map.rebuild_gates()
	routed = from_face(map,1,24)
	check(routed.exit.island == "Island1" and routed.direct,"direct bridge takes priority over colored remote destinations")
	check(routed.color == routed.exit_color and routed.color == group.group_color(),"all faces in a group share one runtime tint independent of brush color")
	var tint:Color = group.group_color()
	map.rebuild_gates()
	check(group.group_color() == tint,"group tint remains stable when gates rebuild")
	var third:TileMapLayer = load("res://addons/portal_map_editor/portal_tiles.gd").new()
	third.name = "AnotherColorGroup"
	map.add_child(third)
	check(third.group_color() != tint,"different portal layers receive different pseudo-random colors")
	map.set_wall_carving(true)
	map.set_active(true)
	map.refresh_visuals(2.0,-17.0,false)
	var shared:Array = map.exposed_border_segments("Island0",Vector2(81,-17),Vector2(81,81),2.0)
	check(shared.is_empty(),"one-cell-gap grass maps have no black border through the adjacent island")
	var external:Array = map.exposed_border_segments("Island0",Vector2(-17,-17),Vector2(81,-17),2.0)
	check(not external.is_empty(),"merged wall keeps its exposed outer border")
	var sides:Array = map.notch_side_segments("Island0",1,16.0,32.0)
	var within:bool = sides.size() == 2
	for segment:PackedVector2Array in sides:
		for point:Vector2 in segment: within = within and point.x >= 64.0 and point.x <= 80.0
	check(within,"bridge side lines stop at the two inner island edges, without inward overshoot")
	var side_count:int = 0
	for child:Node in map.get_node("PortalVisuals").get_children():
		if str(child.name).begins_with("NotchSide"):
			var line:Line2D = child as Line2D
			if line.points[0].x >= 64 and line.points[1].x <= 80: side_count += 1
	check(side_count == 2,"shared bridge side segments are drawn once, not once per island")
	map.queue_free()
	await process_frame
	map = fixture([Vector2.ZERO,Vector2(128,0)])
	var legacy:Resource = load("res://classes/portal_link.gd").new()
	legacy.from_island = "Island0"
	legacy.to_island = "Island1"
	legacy.from_side = 1
	legacy.to_side = 0
	legacy.whole_edge = false
	legacy.from_offset = 16.0
	legacy.from_length = 16.0
	legacy.to_offset = 16.0
	legacy.to_length = 16.0
	legacy.pass_mode = 1
	map.links.append(legacy)
	map._ensure_editor_gate_nodes()
	map.rebuild_gates()
	check(map.links.is_empty() and map.portal_groups().size() == 2 and map.gates().size() == 2,"legacy resource migrates once into one additional blue/red group")
	map._ensure_editor_gate_nodes()
	check(map.portal_groups().size() == 2,"reloading migration does not duplicate painted groups")
	check(not from_face(map,1,24,true).is_empty() and from_face(map,1,24,false).is_empty(),"legacy migration preserves pass mode")
	map.queue_free()
	await process_frame
	print("PORTAL_GROUPS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
