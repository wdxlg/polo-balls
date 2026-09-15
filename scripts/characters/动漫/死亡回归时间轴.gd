extends Node

# V323：菜月昴专用“死亡回归”战场时间轴。
# 第一次死亡只需要恢复开局快照；第一次死亡之后才开始滚动记录，避免无上限保存整局历史。
# V325：恢复阶段改为分帧时间预算 + 单次属性表缓存，避免死亡回归把大量节点重建/脚本属性恢复
# 全塞进一个主线程帧导致明显卡顿。
# V327：完整回溯所有战斗对象。Ball 与 BattleTransient 都恢复“存在性 + 状态”；
# 快照外对象会移除，快照内缺失对象会按原场景重建。第一次死亡前也持续采样，避免开局快照只抓到菜月昴。

const RESTORE_FRAME_BUDGET_USEC:int = 2200

var subaru:ball = null
var world:Node = null
var snapshot_interval:float = 0.10
var shrink_ratio_per_return:float = 0.18
var min_rewind_seconds:float = 0.50

var _combat_started:bool = false
var _combat_start_msec:int = 0
var _first_death_elapsed:float = -1.0
var _return_count:int = 0
var _loop_elapsed:float = 0.0
var _sample_accumulator:float = 0.0
var _initial_snapshot:Dictionary = {}
var _initial_ball_count:int = 0
var _history:Array[Dictionary] = []
var _next_rewind_key:int = 1
var _restoring:bool = false

func initialize(owner:ball, interval:float, shrink_ratio:float, min_seconds:float) -> void:
	subaru = owner
	world = owner.get_tree().current_scene if owner != null else null
	snapshot_interval = maxf(interval,0.04)
	shrink_ratio_per_return = clampf(shrink_ratio,0.0,0.95)
	min_rewind_seconds = maxf(min_seconds,0.5)
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_physics_process(true)

func _physics_process(delta:float) -> void:
	if subaru == null or not is_instance_valid(subaru) or world == null or not is_instance_valid(world):
		queue_free()
		return
	if not subaru.is_multiplayer_authority():
		return
	if not _combat_started:
		if not subaru.is_combat_runtime_active():
			return
		_combat_started = true
		_combat_start_msec = Time.get_ticks_msec()
		_initial_snapshot = _capture_world_snapshot()
		_initial_ball_count = _snapshot_ball_count(_initial_snapshot)
		_loop_elapsed = 0.0
		_history.clear()
		_history.append({"t":0.0,"snapshot":_initial_snapshot})
		return
	if _restoring or not subaru.is_combat_runtime_active():
		return
	_loop_elapsed += maxf(delta,0.0)
	_sample_accumulator += maxf(delta,0.0)
	if _sample_accumulator < snapshot_interval:
		return
	_sample_accumulator = 0.0
	var current_snapshot:Dictionary = _capture_world_snapshot()
	# 第一次死亡前也持续采样；如果其他角色比菜月昴更晚完成生成，
	# 就用角色数量更多的完整快照升级开局快照。
	if _first_death_elapsed < 0.0:
		var current_ball_count:int = _snapshot_ball_count(current_snapshot)
		if current_ball_count > _initial_ball_count:
			_initial_snapshot = current_snapshot
			_initial_ball_count = current_ball_count
	_history.append({"t":_loop_elapsed,"snapshot":current_snapshot})
	_trim_history()

func return_count() -> int:
	return _return_count

func current_max_rewind_seconds() -> float:
	if _first_death_elapsed < 0.0:
		return 0.0
	var reductions:int = maxi(_return_count - 1,0)
	return maxf(_first_death_elapsed * (1.0 - shrink_ratio_per_return * float(reductions)),min_rewind_seconds)

func perform_death_return() -> Dictionary:
	if not _combat_started or _restoring or subaru == null or not is_instance_valid(subaru):
		return {}
	_restoring = true
	var result:Dictionary = {}
	if _first_death_elapsed < 0.0:
		_first_death_elapsed = maxf(float(Time.get_ticks_msec() - _combat_start_msec) / 1000.0,min_rewind_seconds)
		_return_count = 1
		await _restore_world_snapshot(_initial_snapshot)
		_loop_elapsed = 0.0
		_history.clear()
		# 已经恢复到开局快照，不再立刻重复全场 capture 一次。原实现这里会在
		# 最重的重建帧里再扫描所有 Ball/脚本属性，是死亡回归卡顿的第二个峰值。
		_history.append({"t":0.0,"snapshot":_initial_snapshot})
		result = {
			"return_count":_return_count,
			"rewound_seconds":_first_death_elapsed,
			"max_rewind_seconds":current_max_rewind_seconds(),
			"first_return":true,
		}
	else:
		_return_count += 1
		var max_rewind:float = current_max_rewind_seconds()
		var target_time:float = maxf(_loop_elapsed - max_rewind,0.0)
		var chosen:Dictionary = _choose_history_snapshot(target_time)
		if chosen.is_empty():
			chosen = {"t":0.0,"snapshot":_initial_snapshot}
		var chosen_time:float = float(chosen.get("t",0.0))
		await _restore_world_snapshot(chosen.get("snapshot",{}))
		var rewound:float = maxf(_loop_elapsed - chosen_time,0.0)
		_loop_elapsed = chosen_time
		_prune_history_after(chosen_time)
		result = {
			"return_count":_return_count,
			"rewound_seconds":rewound,
			"max_rewind_seconds":max_rewind,
			"first_return":false,
		}
	_sample_accumulator = 0.0
	_restoring = false
	return result

func _choose_history_snapshot(target_time:float) -> Dictionary:
	if _history.is_empty():
		return {}
	var chosen:Dictionary = _history[0]
	for entry:Dictionary in _history:
		if float(entry.get("t",0.0)) <= target_time + 0.0001:
			chosen = entry
		else:
			break
	return chosen

func _trim_history() -> void:
	if _history.size() <= 2:
		return
	var keep_seconds:float = maxf(current_max_rewind_seconds() + snapshot_interval * 3.0,min_rewind_seconds)
	var cutoff:float = _loop_elapsed - keep_seconds
	while _history.size() > 2 and float(_history[1].get("t",0.0)) < cutoff:
		_history.remove_at(0)

func _prune_history_after(time_value:float) -> void:
	while not _history.is_empty() and float(_history[-1].get("t",0.0)) > time_value + 0.0001:
		_history.pop_back()
	if _history.is_empty():
		_history.append({"t":time_value,"snapshot":_capture_world_snapshot()})

func _capture_world_snapshot() -> Dictionary:
	var states:Array[Dictionary] = []
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if node is ball and is_instance_valid(node):
			states.append(_capture_node(node))
	for node:Node in get_tree().get_nodes_in_group("BattleTransient"):
		if is_instance_valid(node) and not node is ball:
			states.append(_capture_node(node))
	return {"nodes":states}

func _snapshot_ball_count(snapshot:Dictionary) -> int:
	var count:int = 0
	for raw_state:Variant in snapshot.get("nodes",[]):
		if raw_state is Dictionary and String((raw_state as Dictionary).get("kind","")) == "ball":
			count += 1
	return count

func _capture_node(node:Node) -> Dictionary:
	var key:int = _ensure_rewind_key(node)
	var parent_path:NodePath = NodePath(".")
	if world != null and node.get_parent() != null:
		parent_path = world.get_path_to(node.get_parent())
	var state:Dictionary = {
		"key":key,
		"kind":"ball" if node is ball else "transient",
		"name":String(node.name),
		"scene":String(node.scene_file_path),
		"parent":parent_path,
		"authority":node.get_multiplayer_authority(),
		"script_values":_capture_safe_script_values(node),
	}
	if node is Node2D:
		state["transform"] = (node as Node2D).global_transform
	if node is CharacterBody2D:
		state["velocity"] = (node as CharacterBody2D).velocity
	if node is ball:
		var fighter:ball = node as ball
		state["health"] = fighter.health
		state["block"] = fighter.block
		state["direction"] = fighter.direction
		state["repel"] = fighter.Repel
		state["team"] = fighter.Team
		if fighter.state_machine != null:
			state["state"] = int(fighter.state_machine.current_state)
			state["state_dis"] = fighter.state_machine.last_state_dis.duplicate(true)
	return state

func _capture_safe_script_values(node:Node) -> Dictionary:
	var values:Dictionary = {}
	for info:Dictionary in node.get_property_list():
		var usage:int = int(info.get("usage",0))
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var property_name:StringName = info.get("name",&"")
		if property_name in [&"health",&"block",&"direction",&"Repel",&"Team",&"state_machine",&"image",&"Master",&"Nearest_Enemy",&"Target_Enemy"]:
			continue
		if node == subaru:
			var property_text:String = String(property_name)
			if property_text.begins_with("_return") or property_name in [&"_timeline",&"_fist_root",&"_fist_arm",&"_fist_head",&"_fist_sfx_player",&"_fist_hit_area",&"_fist_hit_shape"]:
				continue
		var value:Variant = node.get(property_name)
		if _is_safe_snapshot_value(value):
			values[property_name] = value
	return values

func _is_safe_snapshot_value(value:Variant) -> bool:
	return typeof(value) in [
		TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_FLOAT,TYPE_STRING,TYPE_STRING_NAME,
		TYPE_VECTOR2,TYPE_VECTOR2I,TYPE_VECTOR3,TYPE_VECTOR3I,TYPE_VECTOR4,TYPE_VECTOR4I,
		TYPE_RECT2,TYPE_RECT2I,TYPE_TRANSFORM2D,TYPE_TRANSFORM3D,TYPE_COLOR,
		TYPE_PACKED_BYTE_ARRAY,TYPE_PACKED_INT32_ARRAY,TYPE_PACKED_INT64_ARRAY,
		TYPE_PACKED_FLOAT32_ARRAY,TYPE_PACKED_FLOAT64_ARRAY,TYPE_PACKED_STRING_ARRAY,
		TYPE_PACKED_VECTOR2_ARRAY,TYPE_PACKED_VECTOR3_ARRAY,TYPE_PACKED_COLOR_ARRAY
	]

func _ensure_rewind_key(node:Node) -> int:
	if node.has_meta("v323_rewind_key"):
		return int(node.get_meta("v323_rewind_key"))
	var key:int = _next_rewind_key
	_next_rewind_key += 1
	node.set_meta("v323_rewind_key",key)
	return key

func _node_from_instance_id(instance_id:int) -> Node:
	# V333：恢复过程会分帧 await。普通 Node 引用即使仍保存在 Dictionary 中，也可能在下一帧
	# 已经被其它战斗逻辑 queue_free；Godot 不会自动把这种旧引用改成 null。
	# 因此跨帧缓存只保存 instance_id，需要使用时再验证并取回节点。
	if instance_id <= 0 or not is_instance_id_valid(instance_id):
		return null
	var object:Object = instance_from_id(instance_id)
	if object == null or not is_instance_valid(object) or not object is Node:
		return null
	return object as Node

func _restore_world_snapshot(snapshot:Dictionary) -> void:
	if snapshot.is_empty() or world == null or not is_instance_valid(world):
		return
	var desired:Dictionary = {}
	for raw_state:Variant in snapshot.get("nodes",[]):
		if raw_state is Dictionary:
			desired[int((raw_state as Dictionary).get("key",0))] = raw_state
	# V333：这里只缓存 ObjectID，不缓存 Node 本身。大量兔子/召唤物在分帧恢复期间
	# 仍可能死亡或被其它系统释放，ObjectID 可在每次使用前安全验证。
	var current_by_key:Dictionary = {}
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if is_instance_valid(node) and node.has_meta("v323_rewind_key"):
			current_by_key[int(node.get_meta("v323_rewind_key"))] = node.get_instance_id()
	for node:Node in get_tree().get_nodes_in_group("BattleTransient"):
		if is_instance_valid(node) and node.has_meta("v323_rewind_key"):
			current_by_key[int(node.get_meta("v323_rewind_key"))] = node.get_instance_id()

	# V325：删除、现存节点状态恢复、缺失节点实例化都按微秒预算切片。
	# Godot 的场景实例化与 _ready() 必须在主线程完成，无法真正并行；分片的目标是
	# 不让所有工作集中在同一个渲染帧，从而把“卡一下”摊平到极短的数个帧内。
	var slice_started_usec:int = Time.get_ticks_usec()
	var queued_extra:bool = false
	for raw_key:Variant in current_by_key.keys():
		var key:int = int(raw_key)
		if desired.has(key):
			continue
		var extra:Node = _node_from_instance_id(int(current_by_key.get(key,0)))
		if extra == null or extra == subaru:
			continue
		# V327：完整回溯必须恢复存在性。目标时间点尚未存在的角色、召唤物、
		# 投射物和临时效果都移除；菜月昴本体由死亡回归流程保留。
		if extra is ball or extra.is_in_group("BattleTransient"):
			extra.queue_free()
			queued_extra = true
		if Time.get_ticks_usec() - slice_started_usec >= RESTORE_FRAME_BUDGET_USEC:
			await get_tree().process_frame
			slice_started_usec = Time.get_ticks_usec()

	if queued_extra:
		await get_tree().process_frame
		slice_started_usec = Time.get_ticks_usec()

	var missing_states:Array[Dictionary] = []
	for raw_key:Variant in desired.keys():
		var key:int = int(raw_key)
		var state:Dictionary = desired[key]
		var node:Node = _node_from_instance_id(int(current_by_key.get(key,0)))
		if node == null:
			missing_states.append(state)
			continue
		_apply_node_state(node,state)
		if Time.get_ticks_usec() - slice_started_usec >= RESTORE_FRAME_BUDGET_USEC:
			await get_tree().process_frame
			slice_started_usec = Time.get_ticks_usec()

	for state:Dictionary in missing_states:
		var node:Node = _recreate_node_from_state(state)
		if node != null and is_instance_valid(node):
			_apply_node_state(node,state)
		if Time.get_ticks_usec() - slice_started_usec >= RESTORE_FRAME_BUDGET_USEC:
			await get_tree().process_frame
			slice_started_usec = Time.get_ticks_usec()

func _recreate_node_from_state(state:Dictionary) -> Node:
	var scene_path:String = String(state.get("scene",""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return null
	var packed:PackedScene = ResourceLoader.load(scene_path,"PackedScene") as PackedScene
	if packed == null:
		return null
	var node:Node = packed.instantiate()
	if node == null:
		return null
	var parent:Node = world.get_node_or_null(state.get("parent",NodePath(".")))
	if parent == null:
		parent = world
	node.name = String(state.get("name",node.name))
	node.set_multiplayer_authority(int(state.get("authority",1)),true)
	node.set_meta("v323_rewind_key",int(state.get("key",0)))

	# V377：部分场景的 _ready() 有“一次性生成附属对象”的副作用。
	# 兔子就是典型：PackedScene 默认 spawn_initial_pair=true，如果先 add_child()，
	# _ready() 会在历史变量写回前排队生成伙伴，死亡回归便可能把 3 只恢复成 4 只。
	# 给需要它的场景一个入树前准备钩子；普通场景不实现该方法，不受影响。
	if node.has_method("prepare_death_return_recreate"):
		node.call("prepare_death_return_recreate",state)

	parent.add_child(node)
	return node

func _apply_node_state(node:Node,state:Dictionary) -> void:
	if node is ball:
		var fighter:ball = node as ball
		fighter.set_physics_process(true)
		fighter.Team = String(state.get("team",fighter.Team))
		fighter.direction = state.get("direction",fighter.direction)
		fighter.Repel = state.get("repel",fighter.Repel)
		fighter.block = int(state.get("block",fighter.block))

		# 完整回溯按目标时间点原样恢复生命与状态。死亡回归不是“治疗”，
		# 因此恢复快照时临时关闭 health_bar 的浮动文字，避免每个角色都冒出 +N 回血字。
		var old_suppress_floating_text:bool = false
		var can_suppress_floating_text:bool = fighter.health_bar != null and is_instance_valid(fighter.health_bar)
		if can_suppress_floating_text:
			old_suppress_floating_text = bool(fighter.health_bar.suppress_floating_text)
			fighter.health_bar.suppress_floating_text = true
		fighter.health = int(state.get("health",fighter.health))
		if can_suppress_floating_text and fighter.health_bar != null and is_instance_valid(fighter.health_bar):
			fighter.health_bar.suppress_floating_text = old_suppress_floating_text

		if fighter.state_machine != null:
			var restored_state:int = int(state.get("state",ball.State.Move))
			fighter.state_machine.current_state = restored_state
			var state_dis:Variant = state.get("state_dis",null)
			if state_dis is Dictionary:
				fighter.state_machine.last_state_dis = (state_dis as Dictionary).duplicate(true)

	var script_values:Dictionary = state.get("script_values",{}) as Dictionary
	var valid_properties:Dictionary = _node_property_name_set(node)
	for raw_name:Variant in script_values.keys():
		var property_name:StringName = StringName(raw_name)
		if valid_properties.has(property_name):
			node.set(property_name,script_values[raw_name])
	if node is Node2D and state.has("transform"):
		(node as Node2D).global_transform = state["transform"]
	if node is CharacterBody2D and state.has("velocity"):
		(node as CharacterBody2D).velocity = state["velocity"]
	if node.has_meta("v323_rewind_recreating"):
		node.remove_meta("v323_rewind_recreating")

func _node_property_name_set(node:Object) -> Dictionary:
	var result:Dictionary = {}
	for info:Dictionary in node.get_property_list():
		result[StringName(info.get("name",&""))] = true
	return result
