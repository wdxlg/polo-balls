extends Node2D
## 时钟停时：从倒下处扩散的大圈。圈内画面黑白录像带化，圈内一切静止（时钟及其残影除外），
## 停留后缩回中心消失；缩回经过的东西随之恢复。
const SHADER:Shader = preload("res://scripts/characters/我的世界/clock/timestop.gdshader")
const GHOST = preload("res://scripts/characters/我的世界/clock/afterimage.gd")
const STATE = preload("res://scripts/characters/我的世界/clock/rewind_state.gd")
const PROJECTILES = preload("res://classes/projectile_interactions.gd")
const LAYER:int = 2990
signal finished

var expand_time:float = 0.9
var hold_time:float = 4.0
var shrink_time:float = 0.9
var max_radius:float = 200.0
var radius:float = 0.0
var age:float = 0.0
var _clock_ref:WeakRef
var _frozen:Dictionary = {}
var _done:bool = false
var _overlay:Polygon2D
var _mat:ShaderMaterial


func setup(clock:Node2D,center:Vector2,r:float,hold:float) -> void:
	name = "ClockTimeStop"
	add_to_group(&"BattleTransient")
	_clock_ref = weakref(clock)
	global_position = center
	max_radius = maxf(r,16.0)
	hold_time = maxf(hold,0.0)
	z_as_relative = false
	z_index = LAYER
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("radius",0.0)
	# 地图自身也用 BackBufferCopy；这里先强制重新抓屏，保证圈内拿到包含人物的最新画面。
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(copy)
	_overlay = Polygon2D.new()
	var e:float = max_radius + 4.0
	_overlay.polygon = PackedVector2Array([Vector2(-e,-e),Vector2(e,-e),Vector2(e,e),Vector2(-e,e)])
	_overlay.material = _mat
	add_child(_overlay)


func is_frozen(node:Node) -> bool:
	return is_instance_valid(node) and _frozen.has(node.get_instance_id())


func _physics_process(delta:float) -> void:
	if _done or Game.now_stop_state: return
	age += delta
	if age < expand_time:
		var f:float = age / expand_time
		radius = max_radius * (1.0 - pow(1.0 - f,3.0))
	elif age < expand_time + hold_time:
		radius = max_radius
	else:
		var f:float = clampf((age - expand_time - hold_time) / shrink_time,0.0,1.0)
		radius = max_radius * (1.0 - f * f)
	_mat.set_shader_parameter("radius",radius)
	_update_freeze()
	if age >= expand_time + hold_time + shrink_time: _finish()


func _update_freeze() -> void:
	var r2:float = radius * radius
	for id:int in _frozen.keys():
		var node:Node2D = (_frozen[id].ref as WeakRef).get_ref() as Node2D
		if not is_instance_valid(node): _frozen.erase(id)
		elif node.global_position.distance_squared_to(global_position) > r2: _thaw(id)
	for node:Node2D in _candidates():
		if not _frozen.has(node.get_instance_id()) and node.global_position.distance_squared_to(global_position) <= r2: _freeze(node)


func _candidates() -> Array[Node2D]:
	var tree:SceneTree = get_tree()
	var clock:Node = _clock_ref.get_ref() as Node
	var seen:Dictionary = {}
	var out:Array[Node2D] = []
	var pools:Array = [tree.get_nodes_in_group(&"Ball"),PROJECTILES.candidates(tree),tree.get_nodes_in_group(&"AI_Hazard"),tree.get_nodes_in_group(&"BattleTransient")]
	var scene:Node = tree.current_scene
	if scene != null:
		var loose:Array[Node] = []
		for child:Node in scene.get_children():
			if child is GPUParticles2D or child is CPUParticles2D or child is AnimatedSprite2D: loose.append(child)
			elif child is Node2D and child.get_script() != null:
				var path:String = (child.get_script() as Script).resource_path
				if path.begins_with("res://scripts/effects/") or path.begins_with("res://scripts/characters/"): loose.append(child)
		pools.append(loose)
	for pool:Array in pools:
		for node:Variant in pool:
			if not (node is Node2D) or not is_instance_valid(node): continue
			var n:Node2D = node as Node2D
			if n == self or n.is_queued_for_deletion() or not n.is_inside_tree() or seen.has(n.get_instance_id()): continue
			seen[n.get_instance_id()] = true
			if clock != null and (n == clock or clock.is_ancestor_of(n)): continue
			if n.get_script() == GHOST or n.get_script() == get_script() or n.is_in_group(&"MCClockTimeField"): continue
			out.append(n)
	return out


func _freeze(node:Node2D) -> void:
	var cols:Array = []
	var list:Array[Node] = node.find_children("*","CollisionObject2D",true,false)
	if node is CollisionObject2D: list.append(node)
	for co:Node in list:
		var body:CollisionObject2D = co as CollisionObject2D
		cols.append([weakref(body),body.disable_mode])
		body.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE if body is Area2D else CollisionObject2D.DISABLE_MODE_MAKE_STATIC
	var entry:Dictionary = {"ref":weakref(node),"mode":node.process_mode,"cols":cols}
	if node is ball: entry["buffs"] = STATE.copy_buffs(node.Buff_Dic)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	var clock:Node = _clock_ref.get_ref() as Node
	if clock is PhysicsBody2D and node is PhysicsBody2D: preload("res://classes/body_collision_exclusions.gd").add_exception((clock as PhysicsBody2D),node)
	_frozen[node.get_instance_id()] = entry


func _thaw(id:int) -> void:
	var entry:Dictionary = _frozen.get(id,{})
	_frozen.erase(id)
	var node:Node = (entry.get("ref") as WeakRef).get_ref() as Node if entry.has("ref") else null
	if not is_instance_valid(node): return
	node.process_mode = int(entry.mode)
	for pair:Array in entry.cols:
		var body:CollisionObject2D = (pair[0] as WeakRef).get_ref() as CollisionObject2D
		if is_instance_valid(body): body.disable_mode = int(pair[1])
	if entry.has("buffs") and node is ball:
		# 停住期间世界照常扣 Buff 时长；恢复成停住那一刻。
		node.Buff_Dic = STATE.copy_buffs(entry.buffs)
		var scene:Node = get_tree().current_scene
		if scene != null and scene.has_method("refresh_runtime_buffs"): scene.call("refresh_runtime_buffs",node)
	var clock:Node = _clock_ref.get_ref() as Node
	if clock is PhysicsBody2D and node is PhysicsBody2D: preload("res://classes/body_collision_exclusions.gd").remove_exception((clock as PhysicsBody2D),node)


func _thaw_all() -> void:
	for id:int in _frozen.keys(): _thaw(id)


func _finish() -> void:
	if _done: return
	_done = true
	_thaw_all()
	finished.emit()
	queue_free()


func _exit_tree() -> void:
	_thaw_all()
