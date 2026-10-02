extends SceneTree
# 回归：非矩形岛（IslandB 为 L 形）的地面内部不得存在任何物理层 1 的碰撞。
# 历史 bug：PortalMap.set_active 打开了岛 TileMapLayer 自带的瓦片碰撞，
# 自动地形在凹角处铺出的“边框条”落在地面内部，空地上出现看不见的墙。
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
	create_timer(60.0).timeout.connect(func(): quit(2))
	var game:Node = root.get_node("Game")
	game._settings_storage_path=OS.get_environment("TEMP").path_join("portal_motion_settings.json")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Map_Background = "grass"
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map_Portal"
	world.refresh_map_presentation()
	world.control.hide()
	await process_frame
	await physics_frame
	await physics_frame
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"shared preloads settle before scene cleanup")
	var map:Node = world.get_node("Map_Portal")
	var G = load("res://classes/map_tile_geometry.gd")
	for e:Dictionary in map.island_entries():
		check(not (e.layer as TileMapLayer).collision_enabled,"island %s keeps tile collision disabled; walls come from World safety frame" % e.name)
	var ground:Array[Rect2] = world.current_map_island_rects()
	check(ground.size() >= 4,"scene portal map decomposes into multiple ground regions (non-rectangular island present)")
	var edges:Array = G.edges(ground)
	var space:PhysicsDirectSpaceState2D = world.get_world_2d().direct_space_state
	var radius:float = 6.0
	var interior_hits:int = 0
	var near_edge_hits:int = 0
	var first_bad:String = ""
	for r:Rect2 in ground:
		var y:float = r.position.y+1.0
		while y < r.end.y:
			var x:float = r.position.x+1.0
			while x < r.end.x:
				var p:Vector2 = Vector2(x,y)
				var dmin:float = INF
				for e in edges:
					dmin = minf(dmin,Geometry2D.get_closest_point_to_segment(p,G.point(e,e.a),G.point(e,e.b)).distance_to(p))
				if dmin > radius+0.5:
					var q := PhysicsShapeQueryParameters2D.new()
					var circ := CircleShape2D.new(); circ.radius = radius
					q.shape = circ; q.transform = Transform2D(0.0,p); q.collision_mask = 1
					var hits:Array = space.intersect_shape(q,2)
					if not hits.is_empty():
						if dmin > 16.0: interior_hits += 1
						else: near_edge_hits += 1
						if first_bad.is_empty(): first_bad = "%s hit by %s (dist to boundary %.1f)" % [str(p),str(hits[0].collider.name),dmin]
				x += 2.0
			y += 2.0
	check(interior_hits == 0,"no collision anywhere inside painted ground far from boundary; first=%s" % first_bad)
	check(near_edge_hits == 0,"no collision leaks inward across ground boundary; first=%s" % first_bad)
	# 边界外一格必须仍然有墙（安全框仍在）。
	var outside_ok:bool = true
	for e in edges:
		var n:Vector2 = [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN][int(e.side)]
		var mid:Vector2 = G.point(e,(float(e.a)+float(e.b))*0.5)+n*8.0
		var q2 := PhysicsPointQueryParameters2D.new()
		q2.position = mid; q2.collision_mask = 1
		if space.intersect_point(q2,1).is_empty(): outside_ok = false
	check(outside_ok,"every exposed ground edge still has a wall just outside it")
	game.Game_Settings = saved
	print("PORTAL_ISLAND_COLLISION checks=",checks," failures=",failures)
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
