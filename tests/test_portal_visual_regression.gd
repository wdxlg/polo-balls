extends SceneTree
var failures:int = 0
var checks:int = 0
func _initialize() -> void:
	call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	else:
		print("PASS: ",label)
func run() -> void:
	create_timer(20.0).timeout.connect(func(): quit(2))
	var game:Node = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Map_Background = "blue"
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	# 使用独立测试布局，不要求用户始终保留旧示例中的岛名/门组数。
	var fixture:Node = world.get_node("Map_Portal")
	for child:Node in fixture.get_children():
		if child is TileMapLayer:
			fixture.remove_child(child)
			child.queue_free()
	for i:int in range(2):
		var island := TileMapLayer.new()
		island.name = "IslandA" if i == 0 else "IslandB"
		island.position = Vector2(i*192,0)
		island.tile_set = load("res://addons/portal_map_editor/portal_brush.tres")
		for x:int in range(8):
			for y:int in range(8): island.set_cell(Vector2i(x,y),0,Vector2i.ZERO)
		fixture.add_child(island)
	var group:TileMapLayer = load("res://addons/portal_map_editor/portal_tiles.gd").new()
	group.name = "RegressionGroup"
	fixture.add_child(group)
	for x:int in range(2,5):
		group.set_cell(Vector2i(x,8),0,Vector2i.ZERO)
		group.set_cell(Vector2i(12+x,-1),0,Vector2i(1,0))
	fixture.collect_islands()
	world.now_choose_map = "Map_Portal"
	world.refresh_map_presentation()
	await process_frame
	var portal:Node = world.map_group["Map_Portal"]
	check(not portal.portal_groups().is_empty() and portal.links.is_empty(),"current user layout uses native groups without legacy endpoint resources")
	for gate:Dictionary in portal.gates():
		for key:String in ["entry","exit"]:
			var desc:Dictionary = gate[key]
			var rect:Rect2 = portal.island_rect(desc.island)
			var origin:float = rect.position.y if desc.side < 2 else rect.position.x
			var step:float = portal.edge_cell_size(desc.island,desc.side)
			check(is_zero_approx(fposmod(desc.a-origin,step)) and is_zero_approx(fposmod(desc.b-desc.a,step)),"gate endpoints use whole tiles")
	var visuals:Node = portal.get_node("PortalVisuals")
	var line_count:int = 0
	for child:Node in visuals.get_children():
		check(not str(child.name).begins_with("VoidGlow") and not str(child.name).begins_with("NotchOutline"),"blue background has no cavity/filled glow")
		if child is Line2D and str(child.name).begins_with("GateLine"):
			line_count += 1
			check(child.width <= portal._border_width,"gate line no thicker than border")
	check(line_count > 0,"blue background has visible gate lines")
	var scroll:Node = world.control.get_node("Map/Map_Inner/ScrollContainer")
	check(scroll is ScrollContainer and world.control.map_box.get_parent() == scroll,"map buttons are inside editable scrolling scene container")
	game.Game_Settings.Map_Background = "grass"
	world.refresh_map_presentation()
	await process_frame
	visuals = portal.get_node("PortalVisuals")
	var notches:int = 0
	for cavity:Rect2 in portal.void_rects():
		var covered:bool = false
		for part:Polygon2D in world.map_outside_grid_parts:
			if part.visible and Geometry2D.is_point_in_polygon(cavity.get_center(),part.polygon):
				covered = part.material == world.map_outside_grid_material
				break
		check(covered,"portal gap uses the actual parallax grid material")
	var gates:int = 0
	check(portal.get_node("PortalVoid").get_child_count() == 0,"wall gap has no opaque cover; existing background and shadows remain visible")
	for child:Node in visuals.get_children():
		if str(child.name).begins_with("NotchSide"):
			notches += 1
			check(child.points.size() == 2 and child.default_color == Color.BLACK and child.width == portal._border_width,"side extensions are black border segments, not glowing")
			check(not portal._pulse_nodes.has(child),"black side edges never pulse")
			check(child.begin_cap_mode == Line2D.LINE_CAP_NONE and child.end_cap_mode == Line2D.LINE_CAP_NONE,"black sides do not overshoot endpoints with box caps")
		if str(child.name).begins_with("GateLine"):
			gates += 1
			check(child.points.size() == 2 and child.default_color != Color.BLACK,"only inner portal face is a luminous line")
	check(notches > 0 and gates > 0,"grass wall combines black sides and luminous inner face")
	var rect:Rect2 = portal.island_rect("IslandA")
	var points:PackedVector2Array = portal.notch_outline_points("IslandA",3,rect.position.x+32,rect.position.x+80)
	check(points[0].y > rect.end.y+15 and absf(points[1].y-rect.end.y) <= 3.0,"notch starts at added outer wall and ends at playable inner edge")
	await create_timer(2.0).timeout
	game.Game_Settings = saved
	world.queue_free()
	await process_frame
	print("PORTAL_REGRESSION checks=",checks," failures=",failures)
	quit(1 if failures else 0)
