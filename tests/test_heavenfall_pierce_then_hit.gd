extends "res://tests/test_heavenfall_arrow_pierce.gd"
# 天堂箭穿过一个障碍物之后，仍然必须能命中墙后的人物。


func _spawn_homing_bolt(start: Vector2, homing: bool) -> Node:
	var bolt: Node = load("res://scenes/shooter/我的世界/天陨箭矢.tscn").instantiate()
	world.add_child(bolt, true)
	bolt.set_physics_process(false)
	bolt.global_position = start
	var turn: float = 120.0 if homing else 0.0
	var reach: float = 220.0 if homing else 0.0
	bolt.call("configure", bow, bow.Team, Vector2.RIGHT, 620.0, 10.0, 30.0, turn, reach, 5000.0, 3, 60.0, 4.0, 22.0, 0.38)
	return bolt


func _mk_obstacle(kind: String, point: Vector2) -> Node2D:
	if kind == "stone":
		var stone: Node2D = load("res://scenes/characters/默认/石头.tscn").instantiate()
		world.add_child(stone, true)
		stone.global_position = point
		return stone
	return _mk_wall(point)


# 地图内部空洞：安全框会给洞口四周生成墙（与外墙同一个 MapSafetyFrame 根），
# 但洞的另一侧仍是地图地面，箭穿出后必须照常命中。
func _dig_hole(center: Vector2) -> Array[Vector2i]:
	var map: TileMapLayer = world.map_group[world.now_choose_map] as TileMapLayer
	var cell: Vector2i = map.local_to_map(map.to_local(center))
	var dug: Array[Vector2i] = []
	for dx in range(-1, 1):
		for dy in range(-1, 1):
			var c: Vector2i = cell + Vector2i(dx, dy)
			if map.get_cell_source_id(c) != -1:
				_hole_backup.append([c, map.get_cell_source_id(c), map.get_cell_atlas_coords(c), map.get_cell_alternative_tile(c)])
				map.erase_cell(c)
				dug.append(c)
	MapTileGeometry.invalidate(map)
	world._rebuild_map_safety_frame()
	return dug


var _hole_backup: Array = []


func _fill_hole() -> void:
	var map: TileMapLayer = world.map_group[world.now_choose_map] as TileMapLayer
	for entry: Array in _hole_backup:
		map.set_cell(entry[0], entry[1], entry[2], entry[3])
	_hole_backup.clear()
	MapTileGeometry.invalidate(map)
	world._rebuild_map_safety_frame()


func _pierce_then_hit(center: Vector2, homing: bool, label: String, kind: String = "wall") -> void:
	var start: Vector2 = center + Vector2(-60, -40)
	var wall: Node2D = null
	if kind == "hole":
		start = center + Vector2(-55, 0)
		var dug: Array[Vector2i] = _dig_hole(center)
		check(dug.size() == 4, label + ": the 2x2 hole was dug in the map floor")
	else:
		wall = _mk_obstacle(kind, start + Vector2(40, 0))
	var victim: Node2D = _mk_dummy(start + Vector2(120, 0) if kind != "hole" else center + Vector2(55, 0))
	await _park_intruders([victim])
	await physics_frame
	await physics_frame
	var hp_before: float = victim.health
	var bolt: Node = _spawn_homing_bolt(start, homing)
	var pierced: bool = false
	var trail: Array = []
	for i in range(90):
		bolt._physics_process(1.0 / 60.0)
		pierced = pierced or bolt.has_pierced()
		if not bolt.is_queued_for_deletion():
			trail.append(bolt.global_position)
		if bolt.is_queued_for_deletion():
			break
	print("PHITTRACE: ", label, " pierced=", pierced, " leave=", bolt._leave_offscreen, " dead=", bolt._dead, " hp ", hp_before, "->", victim.health, " trail_tail=", trail.slice(maxi(trail.size() - 4, 0)))
	check(pierced, label + ": the arrow pierced the first obstacle")
	check(victim.health < hp_before, label + ": the arrow still hits the character behind the obstacle")
	check(bolt.is_queued_for_deletion() and not bolt._leave_offscreen, label + ": the hit ends the arrow in the map (not an off-screen exit)")
	if wall != null:
		wall.queue_free()
	if kind == "hole":
		_fill_hole()
	victim.queue_free()
	await physics_frame


func run() -> void:
	FX_SCRIPT = load("res://scripts/characters/我的世界/new6/fx_burst.gd")
	DEBRIS_FX_SCRIPT = load("res://scripts/characters/我的世界/new6/heavenfall_arrow_debris.gd")
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Camera_Move = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0, true)
	create_timer(100.0, true, false, true).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world, CONNECT_ONE_SHOT)
	root.add_child(world)
	world.control.hide()
	await create_timer(0.55).timeout
	var arena: Rect2 = world.return_map_world_rect(world.map_group[world.now_choose_map])
	lane_center = arena.get_center()
	world.camera_2d.position_smoothing_enabled = false
	world.camera_2d.global_position = lane_center
	world.camera_2d.force_update_scroll()
	bow = spawn("res://scenes/characters/我的世界/天堂陨落长弓.tscn", lane_center + Vector2(-40, -60))
	bow.state_machine.set_physics_process(false)
	bow.set_physics_process(false)
	await create_timer(0.2).timeout
	bow.set_process(false)
	print("PHIT_ARENA: ", arena, " bow_team=", bow.Team)
	await _pierce_then_hit(lane_center, false, "straight")
	await _pierce_then_hit(lane_center, true, "homing")
	await _pierce_then_hit(lane_center, true, "stone", "stone")
	await _pierce_then_hit(lane_center, false, "map hole straight", "hole")
	await _pierce_then_hit(lane_center, true, "map hole homing", "hole")
	print("HEAVENFALL PIERCE THEN HIT RESULT: %d/%d passed" % [checks - failures, checks])
	finish(0 if failures == 0 else 1)
