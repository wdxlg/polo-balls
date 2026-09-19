extends SceneTree
## 蓝框左上角“几x几”标签：计数与真实生成网格一致，overlay 可绘制。
var checks:int = 0
var failures:int = 0
func check(cond:bool,label:String) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL: " + label)
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var game:Node = root.get_node("Game")
	var world:Node = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	await create_timer(0.8).timeout
	var placement = game._placement
	var border:Dictionary = world.return_now_map_border()
	var origin:Vector2 = border["start"] + Vector2(120,120)
	# 1) 单点：1x1
	var c:Vector2i = placement._box_placement_grid_counts(world,origin,origin + Vector2(5,5))
	check(c == Vector2i(1,1),"tiny box -> 1x1, got %s" % [c])
	# 2) 横向 90px -> 4，纵向 0 -> 1
	c = placement._box_placement_grid_counts(world,origin,origin + Vector2(90,0))
	check(c == Vector2i(4,1),"90x0 box -> 4x1, got %s" % [c])
	# 3) 计数与实际生成点数一致（框在地图内部，无点被过滤）
	for extent in [Vector2(90,60),Vector2(300,150),Vector2(31,29)]:
		c = placement._box_placement_grid_counts(world,origin,origin + extent)
		var points:Array = placement._box_placement_points(world,origin,origin + extent)
		check(points.size() == c.x * c.y,"points %d == %dx%d for %s" % [points.size(),c.x,c.y,extent])
	# 4) 上限 256 收敛
	c = placement._box_placement_grid_counts(world,origin,origin + Vector2(900,900))
	check(c.x * c.y <= 256 and c.x * c.y > 200,"cap 256, got %s" % [c])
	# 5) overlay 接口与绘制
	var overlay:Control = placement.PLACEMENT_BOX_OVERLAY_SCRIPT.new()
	root.add_child(overlay)
	check(overlay.has_method("set_grid_counts"),"overlay has set_grid_counts")
	overlay.set_selection_points(Vector2(100,100),Vector2(220,160))
	overlay.set_grid_counts(5,3)
	check(overlay.grid_count_x == 5 and overlay.grid_count_y == 3,"counts stored")
	overlay.set_grid_counts(0,-2)
	check(overlay.grid_count_x == 1 and overlay.grid_count_y == 1,"counts clamp to >=1")
	await process_frame
	await process_frame
	check(is_instance_valid(overlay) and overlay.visible,"overlay drew without error")
	print("PLACEMENT_GRID_LABEL_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures > 0 else 0)

