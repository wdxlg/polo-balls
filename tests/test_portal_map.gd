extends SceneTree
# 新组瓦片门的实际角色/子弹物理穿越回归；图形及随机路由分别由专项测试覆盖。
var game:Node
var world:Node
var saved:Dictionary
var saved_stop:bool
var failures:int = 0
var checks:int = 0
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func spawn(path:String,point:Vector2,team:String = "Team0") -> Node2D:
	var unit:Node2D = load(path).instantiate()
	unit.Team = team
	unit.Can_Attack = false
	unit.Can_Skill = false
	unit.Health_Restore = 0
	world.add_child(unit,true)
	unit.global_position = point
	return unit
# 角色到达目标岛后会继续跑并在对面墙反弹（甚至再次穿门回来），
# 因此这里在“刚进入目标矩形”的那一刻采样并立即停住。
func await_inside(unit:Node2D,rect:Rect2,timeout:float = 0.8) -> Dictionary:
	var elapsed:float = 0.0
	while elapsed < timeout:
		await physics_frame
		elapsed += 1.0/60.0
		if not is_instance_valid(unit):
			return {"ok":false}
		if rect.has_point(unit.global_position):
			var snapshot:Dictionary = {"ok":true,"pos":unit.global_position,"dir":unit.direction,"vel":unit.velocity}
			unit.Speed = 0
			if "default_properties" in unit:
				unit.default_properties["Speed"] = 0
			return snapshot
	return {"ok":false,"pos":unit.global_position if is_instance_valid(unit) else Vector2.INF}
func moving(path:String,point:Vector2,direction:Vector2) -> Node2D:
	var unit:Node2D = spawn(path,point,"Team1")
	unit.Speed = 400
	unit.default_properties["Speed"] = 400
	unit.direction = direction
	return unit
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Map_Background = "grass"
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(30.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map_Portal"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.3).timeout
	var map:Node = world.map_group["Map_Portal"]
	var ra:Rect2 = map.island_rect("IslandA")
	var rb:Rect2 = map.island_rect("IslandB")
	var rc:Rect2 = map.island_rect("IslandC")
	check(map.is_active() and map.portal_groups().size() == 3,"three portal groups are active")
	# 三个图层都画了 A|B 之间的桥格：桥只属于第一个图层（直连），后两个图层各剩两扇门互传。
	check(map.gates().size() == 6,"bridge belongs to the first layer only; later layers keep their own two-door pairs")
	var cross_layer:bool = false
	for gate:Dictionary in map.gates():
		for option:Dictionary in gate.destinations:
			for face:Dictionary in option.faces:
				for other:Dictionary in map.gates():
					if other.group_id != gate.group_id and map._faces_overlap(face,other.entry): cross_layer = true
	check(not cross_layer,"no destination face belongs to a door of another layer")
	check(world.return_map_world_rect(map).encloses(ra) and world.return_map_world_rect(map).encloses(rc),"camera bounds contain all islands")
	check(world._map_safety_frame.get_child_count() >= 12,"safety frames exist for all three islands")
	check(world.map_outside_mask_parts.size() > 4,"outside mask includes inter-island gaps")
	# 场景现状：Portal_Characters2（仅角色）A 底 [16,96] <-> B 顶 [192,304]；
	# Portal_Characters3 红门 A 顶 [32,96] <-> B 底 [240,304]，测试里临时改成“仅子弹”。
	var chars_group:TileMapLayer = map.get_node("Portal_Characters2")
	var proj_group:TileMapLayer = map.get_node("Portal_Characters3")
	proj_group.pass_mode = 2
	map.rebuild_gates()
	var unit:Node2D = moving("res://scenes/ball.tscn",Vector2(ra.position.x+56,ra.end.y-40),Vector2.DOWN)
	var result:Dictionary = await await_inside(unit,rb)
	check(result.ok,"character crosses A-bottom door into B-top door of the same layer")
	check(result.ok and result.dir.y > 0.5,"bottom-to-top transit preserves inward downward travel")
	unit.queue_free()
	await physics_frame
	unit = moving("res://scenes/ball.tscn",Vector2(rb.position.x+100,rb.position.y+40),Vector2.UP)
	result = await await_inside(unit,ra)
	check(result.ok,"same-layer door sends character back without an exit/entry flag")
	unit.queue_free()
	await physics_frame
	unit = moving("res://scenes/shooter/子弹.tscn",Vector2(ra.position.x+56,ra.end.y-40),Vector2.DOWN)
	result = await await_inside(unit,rb,0.45)
	check(not result.ok,"characters-only group physically blocks projectile transit")
	if is_instance_valid(unit): unit.queue_free()
	await physics_frame
	unit = moving("res://scenes/shooter/子弹.tscn",Vector2(rb.position.x+120,rb.end.y-40),Vector2.DOWN)
	result = await await_inside(unit,ra)
	check(result.ok,"projectile crosses B-bottom red door into A-top red door of the same layer")
	check(result.ok and (result.vel.y > 0.0 or result.dir.y > 0.5),"bottom-to-top projectile keeps travelling downward")
	if is_instance_valid(unit): unit.queue_free()
	await physics_frame
	unit = moving("res://scenes/ball.tscn",Vector2(rb.position.x+120,rb.end.y-40),Vector2.DOWN)
	result = await await_inside(unit,ra,0.45)
	check(not result.ok and rb.has_point(unit.global_position),"projectiles-only group keeps characters on source island")
	unit.queue_free()
	await physics_frame
	chars_group.pass_mode = 0
	map.rebuild_gates()
	unit = moving("res://scenes/shooter/子弹.tscn",Vector2(ra.position.x+56,ra.end.y-40),Vector2.DOWN)
	result = await await_inside(unit,rb)
	check(result.ok,"both mode permits projectile through former character-only group")
	if is_instance_valid(unit): unit.queue_free()
	chars_group.pass_mode = 1
	proj_group.pass_mode = 1
	await create_timer(1.0).timeout
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	await process_frame
	check(not map.is_active() and map.get_node_or_null("PortalVisuals") == null,"switching to ordinary map deactivates and clears portal visuals")
	finish(0)
func finish(code:int) -> void:
	if code == 0 and failures > 0: code = 1
	print("PORTAL_TEST checks=",checks," failures=",failures)
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	quit(code)
