extends SceneTree
## V431：classes/property_index.gd 的等价性契约——对全部角色场景与常见投射物场景，
## 缓存的属性名集合必须与逐次 Object.get_property_list() 完全一致；同时验证磁铁/威胁分析器/
## 鼓手/投稿角色工具 编辑后仍可加载、且 combat_root 快速路径与通用循环结果一致。
var checks:int = 0
var failures:int = 0
func _initialize() -> void: call_deferred("_run")
func _check(ok:bool,message:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PROPERTY_INDEX FAILED: " + message)
func _names_slow(object:Object) -> Dictionary:
	var result:Dictionary = {}
	for info:Dictionary in object.get_property_list(): result[str(info.get("name",""))] = true
	return result
func _collect_scenes(path:String,out:Array[String]) -> void:
	var dir:DirAccess = DirAccess.open(path)
	if dir == null: return
	dir.list_dir_begin()
	var name:String = dir.get_next()
	while name != "":
		if dir.current_is_dir():
			if not name.begins_with("."): _collect_scenes(path + name + "/",out)
		elif name.ends_with(".tscn"):
			out.append(path + name)
		name = dir.get_next()
func _run() -> void:
	var index = load("res://classes/property_index.gd")
	var scenes:Array[String] = []
	_collect_scenes("res://scenes/characters/",scenes)
	_collect_scenes("res://scenes/shooter/",scenes)
	var instantiated:int = 0
	var started:int = Time.get_ticks_usec()
	for scene_path:String in scenes:
		var packed:PackedScene = load(scene_path)
		if packed == null or not packed.can_instantiate(): continue
		var node:Node = packed.instantiate()
		if node == null: continue
		instantiated += 1
		var fast:Dictionary = index.names(node)
		var slow:Dictionary = _names_slow(node)
		_check(fast.size() == slow.size() and fast.keys().all(func(k): return slow.has(k)),scene_path + " names differ")
		# 第二次查询必须命中缓存并返回同一份只读集合。
		var again:Dictionary = index.names(node)
		_check(again.is_read_only(),scene_path + " cached set is not read-only")
		for probe:String in ["direction","Speed","velocity","influence_radius","Team","health","not_a_property_xyz"]:
			_check(index.has_property(node,probe) == slow.has(probe),scene_path + " has_property(" + probe + ") mismatch")
		node.free()
	print("PROPERTY_INDEX scenes=",scenes.size()," instantiated=",instantiated," elapsed_ms=",float(Time.get_ticks_usec() - started) / 1000.0)
	_check(instantiated >= 100,"expected at least 100 instantiable scenes, got %d" % instantiated)
	# null / freed 对象
	_check(index.names(null).is_empty(),"null object must yield empty set")
	_check(not index.has_property(null,"x"),"null object has no property")
	# 不同脚本不共享缓存：Node 与 Node2D 属性集合不同
	var plain:Node = Node.new()
	var plain_2d:Node2D = Node2D.new()
	_check(not index.has_property(plain,"position") and index.has_property(plain_2d,"position"),"native class separation")
	plain.free(); plain_2d.free()
	# 编辑过的脚本仍能加载
	for script_path:String in ["res://scripts/characters/磁铁.gd","res://scripts/training/combat_threat_analyzer.gd","res://scripts/characters/鼓手.gd","res://scripts/characters/投稿角色工具.gd"]:
		var script_res:Script = load(script_path)
		_check(script_res != null and script_res.can_instantiate(),script_path + " failed to load/compile")
	# combat_root 快速路径 == 通用链
	var tools = load("res://scripts/characters/投稿角色工具.gd")
	var ball_scene:PackedScene = load("res://scenes/ball.tscn")
	var a:Node = ball_scene.instantiate()
	var b:Node = ball_scene.instantiate()
	var c:Node = ball_scene.instantiate()
	_check(tools.combat_root(a) == a,"root of masterless unit is itself")
	b.Master = a
	_check(tools.combat_root(b) == a,"root of depth-1 summon is its master")
	c.Master = b
	_check(tools.combat_root(c) == a,"root of depth-2 summon is the top master")
	a.Master = a
	_check(tools.combat_root(a) == a,"self-cycle returns itself")
	a.Master = c
	_check(tools.combat_root(a) != null,"3-cycle terminates")
	a.free(); b.free(); c.free()
	print("PROPERTY_INDEX_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	await process_frame
	quit(0 if failures == 0 else 1)
