extends SceneTree
# 蠹虫石砖场在 PortalMap（多岛/环形）地图上也要铺砖；传送门四角的缺口侧壁黑线不能压在相邻门面上。
var checks:int = 0
var failures:int = 0
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func run() -> void:
	var game:Node = root.get_node("Game")
	game.Game_Settings.Map_Background = "grass"
	game.Game_Settings.Training_Mode = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(25.0).timeout.connect(func(): finish(2))
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map_Portal2"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.3).timeout
	var map:Node = world.map_group["Map_Portal2"]
	check(map.has_method("gates") and map.gates().size() == 8,"ring layout exposes eight door faces")
	# --- 四角黑线：每条缺口侧壁都不得落进垂直方向门面的空腔里。
	var voids:Array[Rect2] = map.void_rects()
	var overlapping:int = 0
	var notch_count:int = 0
	for child:Node in map._visual_root.get_children():
		if not (child is Line2D) or not str(child.name).begins_with("NotchSide"): continue
		notch_count += 1
		var line:Line2D = child as Line2D
		var mid:Vector2 = line.to_global((line.points[0] + line.points[1]) * 0.5)
		var dir:Vector2 = (line.points[1] - line.points[0]).normalized()
		for v:Rect2 in voids:
			# 只看与线段方向垂直的空腔（即相邻边的门），同轴空腔是它自己的门。
			var vertical_void:bool = v.size.y > v.size.x
			var vertical_line:bool = absf(dir.y) > absf(dir.x)
			if vertical_void == vertical_line: continue
			if v.grow(-0.5).has_point(mid): overlapping += 1
	# 环形走廊里每扇门的侧壁都恰好落在相邻门面的空腔上（走廊是连通的），因此一条黑色侧壁都不该画。
	check(notch_count == 0,"ring corridor draws no notch side lines at all (%d)" % notch_count)
	check(overlapping == 0,"no notch side line lies inside a perpendicular door void (%d overlapping)" % overlapping)
	# 具体到左上角：IslandA2 顶边门 (y=2184) 的左侧壁不应在 x=755 处向下延伸进左边门的空腔。
	var corner_black:int = 0
	for child:Node in map._visual_root.get_children():
		if child is Line2D and str(child.name).begins_with("NotchSide"):
			var l:Line2D = child
			var a:Vector2 = l.to_global(l.points[0])
			var b:Vector2 = l.to_global(l.points[1])
			if Rect2(Vector2(754,2183),Vector2(18,18)).grow(-0.5).has_point((a+b)*0.5): corner_black += 1
	check(corner_black == 0,"top-left corner cell has no stray black side line")
	# --- 蠹虫石砖：在环形 PortalMap 上生成一只蠹虫，石砖场应铺满两座岛的所有实格。
	var insect:Node2D = load("res://scenes/characters/我的世界/蠹虫.tscn").instantiate()
	insect.Team = "Team0"
	insect.Can_Attack = false
	insect.Can_Skill = false
	world.add_child(insect,true)
	insect.global_position = map.island_rect("IslandA").get_center()
	await process_frame
	await process_frame
	var field:Node = insect._stone_field
	check(field != null and is_instance_valid(field),"silverfish creates a stone field on a PortalMap")
	if field == null: return finish(1)
	check(field.is_for_map(map),"stone field is bound to the PortalMap node")
	var expected:int = 0
	for layer:TileMapLayer in map.islands.values(): expected += layer.get_used_cells().size()
	check(field._stone_cells.size() == expected,"stone cells cover every painted cell of every island (%d/%d)" % [field._stone_cells.size(),expected])
	check(field._used_rect.size == Vector2i(12,12),"used rect spans the outer ring (%s)" % str(field._used_rect.size))
	# 蓝色走廊（岛间空隙）没有石砖：IslandA2 内圈第一格
	var gap_world:Vector2 = Vector2(755.0 + 8.0,2184.0 + 8.0)
	var gap_coord:Vector2i = field._map_layer.local_to_map(field._map_layer.to_local(gap_world))
	check(not field.has_stone_cell(gap_coord),"blue corridor between islands stays free of stone")
	var floor_coord:Vector2i = field._map_layer.local_to_map(field._map_layer.to_local(Vector2(739.0+8.0,2168.0+8.0)))
	check(field.has_stone_cell(floor_coord),"outer ring floor receives stone")
	var drawn:int = 0
	for chunk:Node in field.get_children():
		if "_coords" in chunk: drawn += chunk._coords.size()
	check(drawn == expected,"render chunks only draw floor cells (%d)" % drawn)
	# 石砖反应只挑有地板的格子。
	field.trigger_near(gap_world,"Team0",true,7,false,-1,"")
	var touched_gap:bool = false
	for coord:Vector2i in field._tile_states.keys():
		if not field.has_stone_cell(coord): touched_gap = true
	check(not touched_gap,"stone reaction never cracks corridor cells")
	# 出生点夹取仍落在有地板的格子里。
	var edge_coord:Vector2i = field._map_layer.local_to_map(field._map_layer.to_local(Vector2(739.0+8.0,2168.0+8.0)))
	var spawn_pos:Vector2 = field._safe_spawn_world_position(edge_coord)
	var spawn_coord:Vector2i = field._map_layer.local_to_map(field._map_layer.to_local(spawn_pos))
	check(field.has_stone_cell(spawn_coord),"safe spawn position stays on a floor cell")
	finish(0 if failures == 0 else 1)
func finish(code:int) -> void:
	print("PORTAL_STONE checks=",checks," failures=",failures)
	quit(code)
