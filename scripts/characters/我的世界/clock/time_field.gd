extends Node
## 时钟的全局时间加速器（无上限）。倍率取场上存活时钟的最大 time_scale；
## 多出来的时间按整物理步补跑：时钟自身、投射物、药水/凋零状态、独立危险物与昼夜时间。
## 其它角色（Ball / Creature 类型）及挂在其身上的攻击节点不补跑。
const PROJECTILES = preload("res://classes/projectile_interactions.gd")
const GROUP:StringName = &"MCClockTimeField"
## 角色类节点用 move_and_slide（固定物理步长），只能多跑整步；超过上限的部分
## 只由按 delta 计算的节点（状态、昼夜、非角色投射物）以放大的步长补齐。
const MAX_EXTRA_STEPS:int = 32
var time_scale_now:float = 1.0
var extra_steps:int = 0
var _carry:float = 0.0
var _idle:float = 0.0


static func ensure(clock:Node) -> void:
	var tree:SceneTree = clock.get_tree()
	if tree == null or not tree.get_nodes_in_group(GROUP).is_empty(): return
	var field:Node = (load("res://scripts/characters/我的世界/clock/time_field.gd") as GDScript).new()
	field.name = "ClockTimeField"
	field.add_to_group(GROUP)
	var parent:Node = tree.current_scene if tree.current_scene != null else tree.root
	parent.add_child.call_deferred(field)


func current_scale() -> float:
	var k:float = 1.0
	for node:Node in get_tree().get_nodes_in_group(&"MCClock"):
		if is_instance_valid(node) and not node.is_queued_for_deletion() and node.health > 0:
			k = maxf(k,float(node.get("time_scale")))
	return k


func _combat_active() -> bool:
	var tree:SceneTree = get_tree()
	if tree.paused or Game.now_stop_state or Engine.time_scale <= 0.000001: return false
	var scene:Node = tree.current_scene
	if scene != null and scene.has_method("is_combat_runtime_active"): return bool(scene.call("is_combat_runtime_active"))
	return true


func _physics_process(delta:float) -> void:
	if get_tree().get_nodes_in_group(&"MCClock").is_empty():
		_idle += delta
		if _idle > 2.0: queue_free()
		return
	_idle = 0.0
	if not _combat_active(): return
	time_scale_now = current_scale()
	if time_scale_now <= 1.0001:
		_carry = 0.0
		return
	var step:float = delta
	_carry += delta * (time_scale_now - 1.0)
	var whole:int = int(floor((_carry + 0.000001) / step))
	if whole <= 0: return
	_carry -= float(whole) * step
	var n:int = mini(whole,MAX_EXTRA_STEPS)
	var stretched:float = step * float(whole) / float(n)
	var nodes:Array[Node] = accelerated_nodes()
	for i:int in n: _extra_tick(nodes,step,stretched)
	extra_steps += n


static func is_character(node:Node) -> bool:
	return node is ball and int(node.get("Type")) in [ball.Ball_Type.Ball,ball.Ball_Type.Creature] and not node.is_in_group(&"MCClock")


static func _carried_by_character(node:Node) -> bool:
	var p:Node = node.get_parent()
	while p != null:
		if is_character(p): return true
		p = p.get_parent()
	return false


func accelerated_nodes() -> Array[Node]:
	var tree:SceneTree = get_tree()
	var seen:Dictionary = {}
	var out:Array[Node] = []
	for clock:Node in tree.get_nodes_in_group(&"MCClock"):
		_take(clock,seen,out)
	for node:Node in PROJECTILES.candidates(tree):
		if not is_character(node): _take(node,seen,out)
	for unit:Node in tree.get_nodes_in_group(&"Ball"):
		for child:Node in unit.get_children():
			var n:String = str(child.name)
			if n == "WitherStatus" or n.begins_with("MinecraftStatus_"): _take(child,seen,out)
	for hazard:Node in tree.get_nodes_in_group(&"AI_Hazard"):
		if not hazard is ball and not _carried_by_character(hazard): _take(hazard,seen,out)
	return out


static func _take(node:Node,seen:Dictionary,out:Array[Node]) -> void:
	if not is_instance_valid(node) or node.is_queued_for_deletion() or not node.is_inside_tree(): return
	var id:int = node.get_instance_id()
	if seen.has(id): return
	seen[id] = true
	out.append(node)


static func tick_node(node:Node,step:float,stretched:float = -1.0) -> void:
	if stretched <= 0.0: stretched = step
	if not is_instance_valid(node) or node.is_queued_for_deletion() or not node.is_inside_tree() or not node.can_process(): return
	if node is ball:
		if node.health <= 0: return
		var machine:Node = node.get("state_machine")
		if is_instance_valid(machine) and machine.is_physics_processing(): machine.call("_physics_process",step)
	elif node.is_physics_processing() and node.has_method("_physics_process"):
		node.call("_physics_process",stretched)
	elif node.is_processing() and node.has_method("_process"):
		node.call("_process",stretched)


func _extra_tick(nodes:Array[Node],step:float,stretched:float) -> void:
	for node:Node in nodes: tick_node(node,step,stretched)
	var scene:Node = get_tree().current_scene
	var cycle:Variant = scene.get("day_night_cycle") if scene != null else null
	if cycle is Node and is_instance_valid(cycle) and cycle.has_method("advance"): cycle.call("advance",stretched)
