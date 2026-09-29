extends Node

# V323：菜月昴专用“死亡回归”战场时间轴。
# 第一次死亡只需要恢复开局快照；第一次死亡之后才开始滚动记录，避免无上限保存整局历史。
# V325：恢复阶段改为分帧时间预算 + 单次属性表缓存，避免死亡回归把大量节点重建/脚本属性恢复
# 全塞进一个主线程帧导致明显卡顿。
# V327：完整回溯所有战斗对象。Ball 与 BattleTransient 都恢复“存在性 + 状态”；
# 快照外对象会移除，快照内缺失对象会按原场景重建。第一次死亡前也持续采样，避免开局快照只抓到菜月昴。

const RESTORE_FRAME_BUDGET_USEC:int = 2200
const VALUES = preload("res://scripts/characters/动漫/死亡回归快照值.gd")
var _codec:RefCounted
var _capture_codec:RefCounted
var _shared_states:Dictionary = {}
var _codec_generation_time:float = 0.0
var _property_cache:Dictionary = {}
var _factory_cache:Dictionary = {}
var _world_base_children:Dictionary = {}
var last_capture_usec:int = 0
var last_restore_slices:int = 0
var last_unsupported:Array = []
var _resume_nodes:Array[Dictionary] = []

var subaru:ball = null
var world:Node = null
var snapshot_interval:float = 0.10
var shrink_ratio_per_return:float = 0.5
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
	process_physics_priority = -10000
	for child:Node in world.get_children(): _world_base_children[child.get_instance_id()] = true
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
	if _restoring or get_tree().paused or Game.now_stop_state or not subaru.is_combat_runtime_active():
		return
	_loop_elapsed += maxf(delta,0.0)
	_sample_accumulator += maxf(delta,0.0)
	if _sample_accumulator < snapshot_interval:
		return
	_sample_accumulator = 0.0
	# The opening checkpoint is immutable: later summons must never replace it.
	# Until the first death only that checkpoint is needed, so no rolling full scans.
	if _first_death_elapsed < 0.0: return
	var current_snapshot:Dictionary = _capture_world_snapshot()
	_history.append({"t":_loop_elapsed,"snapshot":current_snapshot})
	_trim_history()

func return_count() -> int:
	return _return_count

func current_max_rewind_seconds() -> float:
	if _first_death_elapsed < 0.0:
		return 0.0
	var reductions:int = maxi(_return_count - 1,0)
	return maxf(_first_death_elapsed * pow(1.0-shrink_ratio_per_return,float(reductions)),min_rewind_seconds)

func perform_death_return() -> Dictionary:
	if not _combat_started or _restoring or subaru == null or not is_instance_valid(subaru):
		return {}
	_restoring = true
	var previous_pause:bool = get_tree().paused
	var previous_stop:bool = Game.now_stop_state
	get_tree().paused = true
	Game.now_stop_state = true
	world.set_meta("death_return_restoring",true)
	last_restore_slices = 0
	var result:Dictionary = {}
	if _first_death_elapsed < 0.0:
		_first_death_elapsed = maxf(_loop_elapsed,min_rewind_seconds)
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
	_capture_codec = null
	_shared_states.clear()
	world.set_meta("death_return_generation",int(world.get_meta("death_return_generation",0))+1)
	world.remove_meta("death_return_restoring")
	Game.now_stop_state = previous_stop
	get_tree().paused = previous_pause
	_restoring = false
	return result

func _choose_history_snapshot(target_time:float) -> Dictionary:
	if _history.is_empty():
		return {}
	for entry:Dictionary in _history:
		if float(entry.get("t",0.0)) >= target_time-0.0001: return entry
	return _history[-1]

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

func _collect_roots() -> Array[Node]:
	var found:Dictionary = {}
	for group:String in ["Ball","BattleTransient","AI_Hazard","MCExplosion"]:
		for node:Node in get_tree().get_nodes_in_group(group):
			if is_instance_valid(node) and world.is_ancestor_of(node): found[node.get_instance_id()] = node
	for node:Node in world.get_children():
		if node == self or node.name.begins_with("V323死亡回归时间轴") or node.name == "菜月昴_死亡回归死档": continue
		var script:Script = node.get_script()
		var is_effect:bool = script != null and script.resource_path.begins_with("res://scripts/effects/")
		if is_effect or (not _world_base_children.has(node.get_instance_id()) and (node is Node2D or node is CanvasLayer)):
			found[node.get_instance_id()] = node
	var roots:Array[Node] = []
	for node:Node in found.values():
		var parent:Node = node.get_parent()
		var nested:bool = false
		while parent != null and parent != world:
			if found.has(parent.get_instance_id()): nested = true; break
			parent = parent.get_parent()
		if not nested and not node.is_queued_for_deletion(): roots.append(node)
	return roots

func _descendants(root:Node) -> Array[Node]:
	var nodes:Array[Node] = [root]
	var index:int = 0
	while index < nodes.size():
		for child:Node in nodes[index].get_children():
			if root == subaru and child in [subaru.get("_return_visual_timer"),subaru.get("_return_scream_player"),subaru.get("_return_sound_player"),subaru.get("_return_music_player")]: continue
			if root is ball and child == root.health_bar: continue # UI is refreshed from exact vitals, not captured UI tweens.
			nodes.append(child)
		index += 1
	return nodes

func _capture_world_snapshot() -> Dictionary:
	var started:int = Time.get_ticks_usec()
	if _capture_codec == null or _loop_elapsed-_codec_generation_time >= 30.0:
		_capture_codec = VALUES.new()
		_capture_codec.world = world
		_codec_generation_time = _loop_elapsed
		_shared_states.clear()
	_codec = _capture_codec
	_codec.paths.clear()
	_codec.unsupported.clear()
	var roots:Array[Node] = _collect_roots()
	for root:Node in roots:
		var key:int = _ensure_rewind_key(root)
		for node:Node in _descendants(root): _codec.paths[node.get_instance_id()] = [key,root.get_path_to(node)]
	var states:Array[Dictionary] = []
	for node:Node in roots: states.append(_capture_node(node))
	var world_values:Dictionary = {}
	for property:StringName in _script_names(world):
		var name:String = str(property)
		if name.begins_with("_timed_") or name.begins_with("_victory_bell_") or name.begins_with("_damage_") or name == "now_choose_map":
			world_values[property] = _codec.encode(world.get(property))
	var rng:Variant = _codec.encode(Game._battle_random_counters)
	last_capture_usec = Time.get_ticks_usec()-started
	last_unsupported = _codec.unsupported.keys()
	return {"nodes":states,"objects":_codec.objects,"world":world_values,"rng":rng,"captured_usec":Time.get_ticks_usec()}

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
		"script_values":{},
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
	var metadata:Dictionary = {}
	for tag:StringName in node.get_meta_list():
		if tag not in [&"v323_rewind_key",&"death_return_restore"]: metadata[tag] = _codec.encode(node.get_meta(tag))
	state["metadata"] = metadata
	state["groups"] = node.get_groups()
	var components:Array[Dictionary] = []
	var structure:Array[String] = []
	for child:Node in _descendants(node):
		var path:NodePath = node.get_path_to(child)
		structure.append(str(path)+child.get_class())
		components.append({"path":path,"class":child.get_class(),"script":child.get_script(),"values":_share_state(str(child.get_instance_id())+"s",_capture_safe_script_values(child)),"native":_share_state(str(child.get_instance_id())+"n",_capture_native(child)),"signals":_capture_signals(child)})
	state["components"] = components
	# Reuse the original scene, not duplicate a live actor with external signal links.
	# Dynamic child nodes are reconstructed from component descriptors below.
	var scene_path:String = node.scene_file_path
	if scene_path != "":
		if not _factory_cache.has(scene_path): _factory_cache[scene_path] = load(scene_path)
		state["factory"] = _factory_cache[scene_path]
	else:
		state["class"] = node.get_class()
		state["script"] = node.get_script()
	return state

func _share_state(key:String,state:Dictionary) -> Dictionary:
	var signature:int = hash(state)
	var previous:Dictionary = _shared_states.get(key,{})
	if previous.get("hash",-1) == signature and previous.get("state",{}) == state: return previous.state
	_shared_states[key] = {"hash":signature,"state":state}
	return state

func _script_names(node:Node) -> Array[StringName]:
	var script:Script = node.get_script()
	var key:String = node.get_class()+str(script.get_instance_id() if script else 0)
	if _property_cache.has(key): return _property_cache[key]
	var names:Array[StringName] = []
	for info:Dictionary in node.get_property_list():
		if (int(info.get("usage",0)) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and (int(info.get("usage",0)) & PROPERTY_USAGE_READ_ONLY) == 0:
			names.append(StringName(info.name))
	_property_cache[key] = names
	return names

func _capture_signals(node:Node) -> Array:
	var names:Array[StringName] = []
	if node is Timer: names.append(&"timeout")
	if node is Area2D: names.append_array([&"area_entered",&"area_exited",&"body_entered",&"body_exited"])
	if node is AnimationPlayer or node is AnimatedSprite2D: names.append(&"animation_finished")
	var script:Script = node.get_script()
	if script:
		for signal_info:Dictionary in script.get_script_signal_list(): names.append(signal_info.name)
	var result:Array = []
	for signal_name:StringName in names:
		var connections:Array = []
		for connection:Dictionary in node.get_signal_connection_list(signal_name):
			connections.append({"callable":_codec.encode(connection.callable),"flags":connection.flags})
		result.append({"name":signal_name,"connections":connections})
	return result

func _capture_native(node:Node) -> Dictionary:
	var values:Dictionary = {"process_mode":node.process_mode,"_process":node.is_processing(),"_physics":node.is_physics_processing()}
	var fields:Array[StringName] = []
	if node is Node2D: fields.append_array([&"transform",&"visible",&"modulate",&"self_modulate",&"z_index"])
	if node is CollisionObject2D: fields.append_array([&"collision_layer",&"collision_mask"])
	if node is CollisionShape2D: fields.append_array([&"disabled",&"shape"])
	if node is Area2D: fields.append_array([&"monitoring",&"monitorable"])
	if node is CharacterBody2D: fields.append(&"velocity")
	if node is Sprite2D: fields.append_array([&"texture",&"frame",&"flip_h",&"flip_v",&"offset"])
	if node is Line2D: fields.append_array([&"points",&"width",&"default_color"])
	if node is Timer:
		fields.append_array([&"wait_time",&"one_shot",&"paused",&"autostart"])
		values["_timer"] = [node.time_left,node.is_stopped()]
	if node is AnimationPlayer: values["_animation"] = [node.current_animation,node.current_animation_position if node.current_animation != "" else 0.0,node.is_playing()]
	if node is AnimatedSprite2D: fields.append_array([&"animation",&"frame",&"frame_progress",&"speed_scale",&"sprite_frames"])
	for field:StringName in fields: values[field] = _codec.encode(node.get(field))
	return values

func _capture_safe_script_values(node:Node) -> Dictionary:
	var values:Dictionary = {}
	for property_name:StringName in _script_names(node):
		if property_name in [&"health",&"block"]: continue
		if node == subaru and (str(property_name).begins_with("_return") or property_name == &"_timeline"): continue
		var value:Variant = node.get(property_name)
		if value is Tween or value is SceneTreeTimer or value is SceneTree:
			_codec.unsupported[value.get_class()] = true
			continue
		values[property_name] = _codec.encode(value)
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
	var key:int = node.get_instance_id()
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
	_resume_nodes.clear()
	for root:Node in _collect_roots():
		for child:Node in _descendants(root):
			child.set_process(false)
			child.set_physics_process(false)
			child.process_mode = Node.PROCESS_MODE_DISABLED
			if child is Timer: child.paused = true
	var desired:Dictionary = {}
	for raw_state:Variant in snapshot.get("nodes",[]):
		if raw_state is Dictionary:
			desired[int((raw_state as Dictionary).get("key",0))] = raw_state
	# V333：这里只缓存 ObjectID，不缓存 Node 本身。大量兔子/召唤物在分帧恢复期间
	# 仍可能死亡或被其它系统释放，ObjectID 可在每次使用前安全验证。
	var current_by_key:Dictionary = {}
	for node:Node in _collect_roots():
		current_by_key[_ensure_rewind_key(node)] = node.get_instance_id()

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
		if world.is_ancestor_of(extra):
			extra.queue_free()
			queued_extra = true
		if Time.get_ticks_usec() - slice_started_usec >= RESTORE_FRAME_BUDGET_USEC:
			await get_tree().process_frame
			slice_started_usec = Time.get_ticks_usec()

	if queued_extra:
		await get_tree().process_frame
		slice_started_usec = Time.get_ticks_usec()

	var root_map:Dictionary = {}
	for key:Variant in desired:
		var node:Node = _node_from_instance_id(int(current_by_key.get(key,0)))
		if node == null: node = _recreate_node_from_state(desired[key])
		if node != null: root_map[key] = node
		if Time.get_ticks_usec()-slice_started_usec >= RESTORE_FRAME_BUDGET_USEC:
			last_restore_slices += 1
			await get_tree().process_frame
			slice_started_usec = Time.get_ticks_usec()
	# _ready() may queue descendant construction. Let it settle before binding references.
	await get_tree().process_frame
	var removed_children:bool = false
	for key:Variant in root_map:
		var root_node:Node = root_map[key]
		var expected:Dictionary = {}
		for component:Dictionary in desired[key].get("components",[]): expected[component.path] = true
		for child:Node in _descendants(root_node):
			if child != root_node and not expected.has(root_node.get_path_to(child)):
				child.queue_free()
				removed_children = true
	if removed_children: await get_tree().process_frame
	for key:Variant in root_map:
		var root_node:Node = root_map[key]
		for component:Dictionary in desired[key].get("components",[]):
			if root_node.get_node_or_null(component.path) != null: continue
			var path:String = str(component.path)
			var parent:Node = root_node.get_node_or_null(NodePath(path.get_base_dir())) if path.contains("/") else root_node
			if parent == null: continue
			var child:Node = ClassDB.instantiate(component.get("class","Node")) as Node
			if child == null: continue
			child.name = path.get_file()
			if component.get("script") != null: child.set_script(component.script)
			parent.add_child(child)
	_codec = VALUES.new()
	_codec.world = world
	_codec.begin_decode(snapshot.get("objects",[]),root_map)
	for key:Variant in root_map:
		var node:Node = root_map[key]
		if not is_instance_valid(node): continue
		_apply_node_state(node,desired[key])
		if Time.get_ticks_usec()-slice_started_usec >= RESTORE_FRAME_BUDGET_USEC:
			last_restore_slices += 1
			await get_tree().process_frame
			slice_started_usec = Time.get_ticks_usec()
	for property:Variant in snapshot.get("world",{}): world.set(property,_codec.decode(snapshot.world[property]))
	Game._battle_random_counters = _codec.decode(snapshot.get("rng",{}))
	world.refresh_map_presentation()
	# Do not let PROCESS_MODE_ALWAYS nodes tick between restore slices.
	for entry:Dictionary in _resume_nodes:
		var resumed:Node = _node_from_instance_id(entry.id)
		if resumed == null: continue
		resumed.process_mode = entry.mode
		resumed.set_process(entry.process)
		resumed.set_physics_process(entry.physics)
		if resumed is Timer: resumed.paused = entry.get("timer_paused",false)
	_resume_nodes.clear()

func _recreate_node_from_state(state:Dictionary) -> Node:
	var packed:PackedScene = state.get("factory")
	var node:Node
	if packed != null:
		node = packed.instantiate()
	else:
		node = ClassDB.instantiate(state.get("class","Node2D")) as Node
		if node != null and state.get("script") != null:
			node.set_script(state.script)
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

	node.set_meta("death_return_restore",true)
	parent.add_child(node)
	return node

func _apply_node_state(node:Node,state:Dictionary) -> void:
	node.set_meta("death_return_restore",true)
	for tag:StringName in node.get_meta_list():
		if tag not in [&"v323_rewind_key",&"death_return_restore"] and not state.get("metadata",{}).has(tag): node.remove_meta(tag)
	for tag:Variant in state.get("metadata",{}): node.set_meta(tag,_codec.decode(state.metadata[tag]))
	for group:StringName in node.get_groups():
		if group not in state.get("groups",[]): node.remove_from_group(group)
	for group:StringName in state.get("groups",[]): node.add_to_group(group)
	for component:Dictionary in state.get("components",[]):
		var child:Node = node.get_node_or_null(component.path)
		if child == null: continue
		var valid:Dictionary = _node_property_name_set(child)
		for property:Variant in component["values"]:
			if valid.has(property): child.set(property,_codec.decode(component["values"][property]))
		for signal_state:Dictionary in component.get("signals",[]):
			var callbacks:Array[Callable] = []
			for connection:Dictionary in signal_state.connections:
				var callback:Variant = _codec.decode(connection.callable)
				if callback is Callable and callback.is_valid(): callbacks.append(callback)
			for existing:Dictionary in child.get_signal_connection_list(signal_state.name):
				if existing.callable not in callbacks: child.disconnect(signal_state.name,existing.callable)
			for connection:Dictionary in signal_state.connections:
				var callback:Variant = _codec.decode(connection.callable)
				if callback is Callable and callback.is_valid() and not child.is_connected(signal_state.name,callback): child.connect(signal_state.name,callback,int(connection.flags))
		var native:Dictionary = component.native
		for property:Variant in native:
			if not str(property).begins_with("_") and property != "process_mode": child.set(property,_codec.decode(native[property]))
		_resume_nodes.append({"id":child.get_instance_id(),"process":native.get("_process",false),"physics":native.get("_physics",false),"timer_paused":native.get("paused",false),"mode":native.get("process_mode",0)})
		child.set_process(false)
		child.set_physics_process(false)
		if child is Timer and native.has("_timer"):
			child.stop()
			if not native._timer[1]: child.start(maxf(native._timer[0],0.001))
			child.paused = true
		if child is AnimationPlayer and native.has("_animation"):
			var data:Array = native._animation
			if data[0] != "" and child.has_animation(data[0]):
				child.play(data[0]); child.seek(data[1],true)
				if not data[2]: child.pause()
	if node is ball:
		var fighter:ball = node
		fighter.health = int(state.get("health",fighter.health))
		var suppressed:bool = fighter.health_bar.suppress_floating_text if fighter.health_bar else false
		if fighter.health_bar: fighter.health_bar.suppress_floating_text = true
		fighter.block = int(state.get("block",fighter.block))
		if fighter.health_bar: fighter.health_bar.suppress_floating_text = suppressed
		if fighter.state_machine:
			fighter.state_machine.current_state = int(state.get("state",0))
			fighter.state_machine.last_state_dis = state.get("state_dis",{}).duplicate(true)
	if node is Node2D: node.global_transform = state.get("transform",node.global_transform)
	if node is CharacterBody2D: node.velocity = state.get("velocity",node.velocity)
	if node.has_meta("v323_rewind_recreating"): node.remove_meta("v323_rewind_recreating")
	node.remove_meta("death_return_restore")
	if node.has_method("after_death_return_restore"): node.call("after_death_return_restore")

func _node_property_name_set(node:Object) -> Dictionary:
	var result:Dictionary = {}
	for info:Dictionary in node.get_property_list():
		result[StringName(info.get("name",&""))] = true
	return result
