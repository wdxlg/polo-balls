extends RefCounted
## 赛前发育：共享一个 World，但每人所在的完整地图拥有独立的平移几何。
## 使用 World 已有的地面/阴影/边框/安全墙绘制，避免克隆角色或创建多个 World。
## 所有候补都是实际运行的 ball；合并后停放实例，轮到时原实例重新入场。

const OFF:int = 0
const SETUP:int = 1
const RUNNING:int = 2
const MERGING:int = 3
const BATTLE:int = 4
const DEFAULT_CHARACTER_DIR:String = "res://scenes/characters/默认/"
const MERGE_SECONDS:float = 1.35
# 16px moss and 24px snow/rails share the same translated map. Both sides'
# *individual* offsets must be integral multiples of lcm(16,24), not just
# their distance apart, or rekeying the two world-space grids loses a tile.
const TERRAIN_PHASE:float = 48.0

var world
var phase:int = OFF
var elapsed:float = 0.0
var base_rect:Rect2 = Rect2()
var base_islands:Array[Dictionary] = []
var current_islands:Array[Dictionary] = []
var lanes:Dictionary = {} # side:index -> {side,index,offset}
var candidates:Dictionary = {} # setup id -> live character, including future reserves
var portal_clones:Dictionary = {} # side:index -> an independent PortalMap, when applicable
var _merge_nodes:Array[Dictionary] = []
var _merge_start_offsets:Dictionary = {}
var _merge_terrain_managers:Array[Node2D] = []
var _merge_tween:Tween
var _map_name:String = ""

func _init(owner) -> void:
	world = owner

func configured() -> bool:
	return bool(Game.Game_Settings.get("Development_Mode",false)) and Game.get_training_mode_type() in ["manual","rotation"]

func is_prebattle() -> bool:
	return phase == SETUP or phase == RUNNING or phase == MERGING

func is_running() -> bool:
	return phase == RUNNING

func time_text() -> String:
	var seconds:int = floori(elapsed)
	return "%02d:%02d" % [seconds / 60, seconds % 60]

func is_default_character(char_name:String) -> bool:
	return str(world.character_scene_path(char_name)).begins_with(DEFAULT_CHARACTER_DIR)

func prepare() -> void:
	if not configured() or phase == SETUP or phase == RUNNING or phase == MERGING:
		return
	var map_node:Node = world._current_map_node()
	if map_node == null:
		return
	# 先读取原地图，随后 map_islands/return_map_world_rect 才开始提供平移后的副本。
	base_rect = world.return_map_world_rect(map_node)
	base_islands = world.map_islands(map_node)
	if not base_rect.has_area() or base_islands.is_empty():
		return
	_map_name = world.now_choose_map
	elapsed = 0.0
	phase = SETUP
	_sync_lanes(false)
	world.refresh_map_presentation()
	world._refresh_center_watermark()

func cleanup(refresh:bool = true) -> void:
	if phase == MERGING and world.is_inside_tree():
		# Cancel a partial animation before undoing the prebattle translation.
		_merge_frame(0.0)
		for manager:Node2D in _merge_terrain_managers:
			if is_instance_valid(manager): manager.call("development_finish_merge")
	_merge_terrain_managers.clear()
	if _merge_tween != null and _merge_tween.is_valid():
		_merge_tween.kill()
	_merge_tween = null
	Game.set_development_time_multiplier(1.0)
	for entry:Dictionary in _merge_nodes:
		var n:Variant = entry.get("node")
		if is_instance_valid(n) and n is Node and (n as Node).has_meta("development_merge_mode"):
			(n as Node).process_mode = int((n as Node).get_meta("development_merge_mode"))
			(n as Node).remove_meta("development_merge_mode")
	_merge_nodes.clear()
	if is_prebattle():
		var original_lanes:Dictionary = lanes.duplicate(true)
		var base_lanes:Dictionary = {}
		for key:Variant in original_lanes: base_lanes[key] = {"offset":Vector2.ZERO}
		_rebase_shared_managers(original_lanes,base_lanes)
		for transient:Node in world.get_tree().get_nodes_in_group("BattleTransient"):
			if not transient is Node2D or transient.is_queued_for_deletion() or not world.is_ancestor_of(transient): continue
			if transient.is_in_group("Ball") or transient.is_in_group("MCSpiderSilk"): continue
			if transient.get_parent() != world and not (transient as Node2D).top_level: continue
			var terrain_key:String = _merge_lane_key(transient as Node2D)
			if terrain_key.is_empty(): continue
			var change:Vector2 = -_offset(terrain_key)
			(transient as Node2D).global_position += change
			_rebase_transient_terrain(transient,change)
		for node:Node in world.get_tree().get_nodes_in_group("Ball"):
			if not node is Node2D or not node.has_meta("development_lane_key"):
				continue
			var key:String = str(node.get_meta("development_lane_key"))
			(node as Node2D).global_position -= _offset(key)
			_rebase_owned_terrain(node,-_offset(key))
			_rebase_owner_silk(node,-_offset(key))
			if node.has_meta("development_setup_process_mode"):
				node.process_mode = int(node.get_meta("development_setup_process_mode"))
				node.remove_meta("development_setup_process_mode")
	# 如在布阵时关闭开关，未来队员回到“只有名单，没有实例”的原规则。
	for raw_id:Variant in candidates.keys():
		var b:Variant = candidates[raw_id]
		if is_instance_valid(b) and b is Node and not (b as Node).is_queued_for_deletion():
			if (b as Node).has_meta("development_reserve"):
				_unpark_candidate(b as ball)
			elif is_prebattle() and _candidate_index(int(raw_id)) > 0:
				(b as Node).queue_free()
	candidates.clear()
	_drop_portal_clones()
	base_islands.clear()
	current_islands.clear()
	lanes.clear()
	_map_name = ""
	elapsed = 0.0
	phase = OFF
	if refresh and world.is_inside_tree():
		world.refresh_map_presentation()
		world._refresh_center_watermark()

func update(delta:float) -> void:
	if not is_prebattle():
		return
	if _map_name != world.now_choose_map:
		cleanup()
		prepare()
		return
	if phase == SETUP and not world.control.is_set_team() and _has_both_sides():
		_start()
	if phase != RUNNING or world.get_tree().paused or Game.now_stop_state:
		return
	elapsed = minf(elapsed + maxf(delta,0.0), maxf(float(Game.Game_Settings.get("Development_Duration",60.0)),1.0))
	world._refresh_center_watermark()
	if elapsed >= maxf(float(Game.Game_Settings.get("Development_Duration",60.0)),1.0):
		_begin_merge()

func _has_both_sides() -> bool:
	if Game.is_rotation_training_mode():
		return not world._rotation_rosters["left"].is_empty() and not world._rotation_rosters["right"].is_empty()
	var left:bool = false
	var right:bool = false
	for node:Node in world._battle_units_cache:
		if not node is ball or node.is_queued_for_deletion() or (node as ball).health <= 0:
			continue
		if (node as ball).Type != ball.Ball_Type.Ball or node.has_meta("development_neutral"):
			continue
		var key:String = str(node.get_meta("development_lane_key",""))
		left = left or key.begins_with("left:")
		right = right or key.begins_with("right:")
	return left and right

func _start() -> void:
	phase = RUNNING
	# 轮换的预览原来只在“正式开战”时解除冻结；发育期须先让每名候补活动。
	world._restore_special_prestart_nodes()
	for node:Node in world.get_tree().get_nodes_in_group("Ball"):
		if node.has_meta("development_setup_process_mode"):
			node.process_mode = int(node.get_meta("development_setup_process_mode"))
			node.remove_meta("development_setup_process_mode")
	Game.set_development_time_multiplier(float(Game.Game_Settings.get("Development_Speed",2.0)))
	world._reset_victory_bell_state()
	world._refresh_center_watermark()

func _lane_counts() -> Dictionary:
	if Game.is_rotation_training_mode():
		return {"left":maxi(1,world._rotation_rosters["left"].size()),"right":maxi(1,world._rotation_rosters["right"].size())}
	return {"left":1,"right":1}

func _sync_lanes(refresh:bool,reassign:Dictionary = {}) -> void:
	if not is_prebattle():
		return
	var old:Dictionary = lanes.duplicate(true)
	var updated:Dictionary = {}
	var counts:Dictionary = _lane_counts()
	var cell:Vector2 = world.map_visual_cell_size(world._current_map_node())
	var x_gap:float = maxf(cell.x*3.0,base_rect.size.x*0.12)
	var y_gap:float = maxf(cell.y*3.0,base_rect.size.y*0.12)
	# For an even lane count the center offset is half a pitch. A 96px pitch
	# therefore keeps every lane aligned to both native terrain grids.
	var x_pitch:float = ceilf((base_rect.size.x+x_gap)/(TERRAIN_PHASE*2.0))*TERRAIN_PHASE*2.0
	var y_pitch:float = ceilf((base_rect.size.y+y_gap)/(TERRAIN_PHASE*2.0))*TERRAIN_PHASE*2.0
	for side:String in ["left","right"]:
		var count:int = int(counts[side])
		for i:int in range(count):
			var key:String = "%s:%d" % [side,i]
			var offset:Vector2 = Vector2(x_pitch*(-0.5 if side == "left" else 0.5),(float(i)-(float(count)-1.0)*0.5)*y_pitch)
			updated[key] = {"side":side,"index":i,"offset":offset}
	lanes = updated
	if not old.is_empty() and phase != MERGING: _rebase_shared_managers(old,updated,reassign)
	# 添加候补后上下重排；运行中的角色也保持相对于其发育地图的位置。
	for node:Node in world.get_tree().get_nodes_in_group("Ball"):
		if not node is Node2D or not node.has_meta("development_lane_key"):
			continue
		var key:String = str(node.get_meta("development_lane_key"))
		if old.has(key) and lanes.has(key):
			var change:Vector2 = _offset(key) - (old[key] as Dictionary).get("offset",Vector2.ZERO)
			var silk:Node = node.get_node_or_null("SpiderSilk")
			if is_instance_valid(silk) and silk.has_method("development_prepare_merge"): silk.call("development_prepare_merge")
			(node as Node2D).global_position += change
			_rebase_owned_terrain(node,change)
			_rebase_owner_silk(node,change)
	for transient:Node in world.get_tree().get_nodes_in_group("BattleTransient"):
		if not transient is Node2D or transient.is_queued_for_deletion() or not world.is_ancestor_of(transient): continue
		if transient.is_in_group("Ball") or transient.is_in_group("MCSpiderSilk"): continue
		if transient.get_parent() != world and not (transient as Node2D).top_level: continue
		var old_key:String = str(transient.get_meta("development_lane_key",""))
		if old_key.is_empty():
			if _merge_lane_key(transient as Node2D).is_empty(): continue
			old_key = _lane_for_point_in((transient as Node2D).global_position,old)
		var new_key:String = str(reassign.get(old_key,old_key))
		if old.has(old_key) and lanes.has(new_key):
			var change:Vector2 = _offset(new_key)-(old[old_key] as Dictionary).get("offset",Vector2.ZERO)
			(transient as Node2D).global_position += change
			_rebase_transient_terrain(transient,change)
	_sync_portal_clones()
	_build_islands()
	if refresh:
		world.refresh_map_presentation()
		world._refresh_center_watermark()

func _build_islands() -> void:
	current_islands.clear()
	for raw_lane:Variant in lanes.values():
		var offset:Vector2 = (raw_lane as Dictionary).get("offset",Vector2.ZERO)
		for original:Dictionary in base_islands:
			var ground:Array[Rect2] = []
			for rect:Rect2 in original["regions"]:
				ground.append(Rect2(rect.position+offset,rect.size))
			var walls:Array[Rect2] = []
			for rect:Rect2 in original["walls"]:
				walls.append(Rect2(rect.position+offset,rect.size))
			var physical:Rect2 = original["rect"]
			current_islands.append({"name":original["name"],"rect":Rect2(physical.position+offset,physical.size),"regions":ground,"walls":walls,"development_lane_key":str(raw_lane["side"])+":"+str(raw_lane["index"])})

func _sync_portal_clones() -> void:
	var source:PortalMap = world.map_group.get(_map_name) as PortalMap
	if source == null:
		_drop_portal_clones()
		return
	# 原门只是一份地图的数据源；每张发育地图均有自己的门和传送路径。
	if source.is_active():
		source.set_active(false)
	for raw_key:Variant in portal_clones.keys():
		var old_key:String = str(raw_key)
		if not lanes.has(old_key):
			var obsolete:Variant = portal_clones[old_key]
			if is_instance_valid(obsolete):
				(obsolete as PortalMap).set_active(false)
				(obsolete as PortalMap).queue_free()
			portal_clones.erase(old_key)
	for raw_key:Variant in lanes.keys():
		var key:String = str(raw_key)
		var clone:PortalMap = portal_clones.get(key) as PortalMap
		if not is_instance_valid(clone):
			clone = source.duplicate() as PortalMap
			if clone == null:
				continue
			clone.name = "DevelopmentPortal_" + key.replace(":","_")
			clone.position = source.position + _offset(key)
			world.add_child(clone,true)
			clone.set_active(true)
			portal_clones[key] = clone
		else:
			clone.position = source.position + _offset(key)
			clone.collect_islands()
			clone.rebuild_gates()

func _drop_portal_clones() -> void:
	for raw:Variant in portal_clones.values():
		if is_instance_valid(raw):
			(raw as PortalMap).set_active(false)
			(raw as PortalMap).hide()
			(raw as PortalMap).queue_free()
	portal_clones.clear()

func portal_for_lane(key:String) -> PortalMap:
	var raw:Variant = portal_clones.get(key)
	return raw as PortalMap if is_instance_valid(raw) else null

func refresh_portal_visuals(width:float,inset:float,antialiased:bool) -> void:
	for raw:Variant in portal_clones.values():
		if is_instance_valid(raw):
			var clone:PortalMap = raw as PortalMap
			clone.set_wall_carving(world._is_grass_map_background())
			clone.refresh_visuals(width,inset,antialiased)

func _transit_lane_key(node:Node) -> String:
	# shooter 可能在 node_added 时尚未得到 Master / 出生坐标。物理帧用主人或
	# 实际位置决定通道，避免子弹误传到另一支队伍的副本。
	if node is ball:
		var owner:Variant = (node as ball).Master
		if is_instance_valid(owner) and owner is Node and owner != node:
			var master_key:String = str((owner as Node).get_meta("development_lane_key",""))
			if lanes.has(master_key):
				node.set_meta("development_lane_key",master_key)
				return master_key
	var key:String = str(node.get_meta("development_lane_key",""))
	if node is Node2D:
		var pos:Vector2 = (node as Node2D).global_position
		if not lanes.has(key) or not Rect2(base_rect.position+_offset(key),base_rect.size).has_point(pos):
			key = lane_for_point(pos)
			node.set_meta("development_lane_key",key)
	return key

func process_portal_transits(delta:float,ball_group:Array,ball_projectiles:Array,other_projectiles:Array) -> void:
	if phase != RUNNING:
		return
	var payloads:Dictionary = {}
	for raw_key:Variant in portal_clones.keys():
		var key:String = str(raw_key)
		payloads[key] = {"characters":[],"shots":[],"other":[]}
	for b:Node in ball_group:
		if is_instance_valid(b):
			var key:String = _transit_lane_key(b)
			if payloads.has(key): (payloads[key] as Dictionary)["characters"].append(b)
	for shot:Variant in ball_projectiles:
		if is_instance_valid(shot):
			var key:String = _transit_lane_key(shot as Node)
			if payloads.has(key): (payloads[key] as Dictionary)["shots"].append(shot)
	for shot:Variant in other_projectiles:
		if is_instance_valid(shot):
			var key:String = _transit_lane_key(shot as Node)
			if payloads.has(key): (payloads[key] as Dictionary)["other"].append(shot)
	for raw_key:Variant in portal_clones.keys():
		var key:String = str(raw_key)
		var clone:PortalMap = portal_for_lane(key)
		if clone == null:
			continue
		var payload:Dictionary = payloads[key]
		clone.process_transits(delta,payload["characters"],payload["shots"],payload["other"])

func world_rect() -> Rect2:
	var result:Rect2 = Rect2()
	var first:bool = true
	for entry:Dictionary in current_islands:
		var rect:Rect2 = entry["rect"]
		if first:
			result = rect
			first = false
		else:
			result = result.merge(rect)
	return result

func _offset(key:String) -> Vector2:
	var lane:Dictionary = lanes.get(key,{})
	return lane.get("offset",Vector2.ZERO)

func lane_for_point(pos:Vector2) -> String:
	return _lane_for_point_in(pos,lanes)

func _lane_for_point_in(pos:Vector2,lane_defs:Dictionary) -> String:
	var best:String = "left:0"
	var best_distance:float = INF
	for raw_key:Variant in lane_defs.keys():
		var key:String = str(raw_key)
		var offset:Vector2 = (lane_defs[key] as Dictionary).get("offset",Vector2.ZERO)
		var rect:Rect2 = Rect2(base_rect.position+offset,base_rect.size)
		if rect.has_point(pos):
			return key
		var nearest:Vector2 = Vector2(clampf(pos.x,rect.position.x,rect.end.x),clampf(pos.y,rect.position.y,rect.end.y))
		var distance:float = pos.distance_squared_to(nearest)
		if distance < best_distance:
			best_distance = distance
			best = key
	return best

func _rebase_shared_managers(before:Dictionary,after:Dictionary,reassign:Dictionary = {}) -> void:
	if before.is_empty() or not world.is_inside_tree(): return
	var offsets:Dictionary = {}
	for key:Variant in before: offsets[key] = (before[key] as Dictionary).get("offset",Vector2.ZERO)
	var destinations:Dictionary = after.duplicate(true)
	for key:Variant in reassign:
		var new_key:String = str(reassign[key])
		if after.has(new_key): destinations[key] = after[new_key]
	var changed:bool = false
	for key:Variant in offsets:
		if destinations.has(key) and not (offsets[key] as Vector2).is_equal_approx((destinations[key] as Dictionary).get("offset",Vector2.ZERO)):
			changed = true
			break
	if not changed: return
	# An active route references rail node IDs from the old lane layout.
	for cart:Node in world.get_tree().get_nodes_in_group("MCMinecart"):
		if not world.is_ancestor_of(cart): continue
		if int(cart.get("rush_phase")) != 0: cart.call("end_rush")
		cart.set("entry_needs_exit",false)
	for name:String in ["MCSnowField","MinecartRails"]:
		var manager:Node = world.get_node_or_null(NodePath(name))
		if not is_instance_valid(manager) or not manager.is_inside_tree() or manager.is_queued_for_deletion() or not manager.has_method("development_begin_merge"): continue
		var at_old_lane:Callable = Callable(self,"_lane_for_point_in").bind(before)
		if name == "MCSnowField": manager.call("development_begin_merge",at_old_lane,offsets,false)
		else: manager.call("development_begin_merge",at_old_lane,offsets)
		manager.call("development_preview_merge",offsets,destinations)
		manager.call("development_finish_merge")

func _lane_for_team(team:String,point:Vector2) -> String:
	if team == "Team0":
		return "left:0"
	if team == "Team1":
		return "right:0"
	return lane_for_point(point)

func _candidate_lane(setup_id:int) -> String:
	for side:String in ["left","right"]:
		var roster:Array = world._rotation_rosters[side]
		for i:int in range(roster.size()):
			if int((roster[i] as Dictionary).get("id",-2)) == setup_id:
				return "%s:%d" % [side,i]
	return ""

func _candidate_index(setup_id:int) -> int:
	var key:String = _candidate_lane(setup_id)
	return int(key.get_slice(":",1)) if not key.is_empty() else -1

func normalize_manual_entry(entry:Dictionary) -> Dictionary:
	var result:Dictionary = entry.duplicate(true)
	if not is_prebattle():
		return result
	var point:Vector2 = Vector2(float(entry.get("x",0.0)),float(entry.get("y",0.0)))
	var clicked:String = lane_for_point(point)
	var canonical:Vector2 = point - _offset(clicked)
	result["x"] = canonical.x
	result["y"] = canonical.y
	result["development_base_position"] = true
	result["development_lane_key"] = _lane_for_team(str(entry.get("team","")),point)
	return result

func spawn_placement(entry:Dictionary,position:Vector2) -> Dictionary:
	if not is_prebattle():
		return {}
	var setup_id:int = int(entry.get("id",-1))
	var candidate_key:String = _candidate_lane(setup_id) if Game.is_rotation_training_mode() else ""
	if not candidate_key.is_empty():
		return {"position":position+_offset(candidate_key),"lane":candidate_key}
	if bool(entry.get("development_neutral",false)):
		return {"position":position,"lane":lane_for_point(position)}
	if bool(entry.get("development_base_position",false)):
		var key:String = str(entry.get("development_lane_key",_lane_for_team(str(entry.get("team","")),position)))
		return {"position":position+_offset(key),"lane":key}
	var clicked:String = lane_for_point(position)
	var target:String = _lane_for_team(str(entry.get("team","")),position)
	return {"position":position-_offset(clicked)+_offset(target),"lane":target}

func on_spawn(b:ball,entry:Dictionary,placement:Dictionary) -> void:
	if not is_prebattle() or placement.is_empty() or b == null:
		return
	b.set_meta("development_lane_key",str(placement.get("lane","left:0")))
	if bool(entry.get("development_neutral",false)) or b.scene_file_path.begins_with(DEFAULT_CHARACTER_DIR):
		b.set_meta("development_neutral",true)
	var id:int = int(entry.get("id",-1))
	if Game.is_rotation_training_mode() and not _candidate_lane(id).is_empty():
		candidates[id] = b
	if phase == SETUP and not b.has_meta("development_setup_process_mode"):
		b.set_meta("development_setup_process_mode",int(b.process_mode))
		b.process_mode = Node.PROCESS_MODE_DISABLED

func on_scene_node_added(node:Node) -> void:
	if not is_prebattle() or not node is ball:
		return
	var owner:ball = null
	if (node as ball).Master is ball and is_instance_valid((node as ball).Master):
		owner = (node as ball).Master
	elif node.get_parent() is ball:
		owner = node.get_parent() as ball
	var key:String = str(node.get_meta("development_lane_key",""))
	if not lanes.has(key):
		key = str(owner.get_meta("development_lane_key","")) if owner != null else ""
		if not lanes.has(key):
			key = lane_for_point((node as ball).global_position)
		node.set_meta("development_lane_key",key)
	if owner != null and owner.has_meta("development_neutral"):
		node.set_meta("development_neutral",true)
	if phase == SETUP:
		if not node.has_meta("development_setup_process_mode"):
			node.set_meta("development_setup_process_mode",int(node.process_mode))
		node.process_mode = Node.PROCESS_MODE_DISABLED
	elif phase == MERGING:
		if not node.has_meta("development_merge_mode"):
			node.set_meta("development_merge_mode",int(node.process_mode))
		node.process_mode = Node.PROCESS_MODE_DISABLED
		_merge_nodes.append({"node":node,"lane":key,"local":(node as Node2D).global_position-_offset(key)})

func same_lane(a:Node,b:Node) -> bool:
	if phase != RUNNING:
		return true
	var a_key:String = str(a.get_meta("development_lane_key",""))
	var b_key:String = str(b.get_meta("development_lane_key",""))
	return a_key.is_empty() or b_key.is_empty() or a_key == b_key

func on_rotation_enqueued(side:String) -> void:
	if not is_prebattle():
		return
	_sync_lanes(true)
	var roster:Array = world._rotation_rosters[side]
	if roster.is_empty():
		return
	var record:Dictionary = roster.back()
	var id:int = int(record.get("id",-1))
	if candidates.has(id) and is_instance_valid(candidates[id]):
		return
	# 第一位沿用原有的冻结预览；后面的每一位在自己的地图上实例化并发育。
	if roster.size() > 1:
		var entry:Dictionary = world._queue_entry_for_record(record,side,world._rotation_spawn_position(side))
		var b:ball = world._spawn_character_from_setup(entry)
		if b != null:
			b.set_meta("rotation_side",side)
			candidates[id] = b

func seed_rotation_roster() -> void:
	if not is_prebattle() or not Game.is_rotation_training_mode():
		return
	_sync_lanes(true)
	for side:String in ["left","right"]:
		var roster:Array = world._rotation_rosters[side]
		for i:int in range(1,roster.size()):
			var record:Dictionary = roster[i]
			var id:int = int(record.get("id",-1))
			if candidates.has(id) and is_instance_valid(candidates[id]):
				continue
			var entry:Dictionary = world._queue_entry_for_record(record,side,world._rotation_spawn_position(side))
			var b:ball = world._spawn_character_from_setup(entry)
			if b != null:
				b.set_meta("rotation_side",side)
				candidates[id] = b

func _rebase_owned_terrain(node:Node,change:Vector2) -> void:
	if change.is_zero_approx() or not node.is_in_group("MCMossOwner"): return
	# Moss's patches and queued growth are world-space data on the actor, not
	# children of its Node2D. Move the same data read by both paint and damage.
	for patch:Dictionary in node.get("patches"): patch.point += change
	for pending:Dictionary in node.get("_growth_pending"): pending.point += change
	if bool(node.get("burrowing")):
		node.set("burrow_origin",node.get("burrow_origin")+change)
		node.set("burrow_destination",node.get("burrow_destination")+change)
	var fx:Variant = node.get("frontier_fx")
	if is_instance_valid(fx) and fx is CanvasItem: fx.queue_redraw()

func _rebase_owner_silk(node:Node,change:Vector2) -> void:
	if change.is_zero_approx(): return
	var silk:Node = node.get_node_or_null("SpiderSilk")
	if is_instance_valid(silk) and silk.has_method("development_rebase"): silk.call("development_rebase",change)

func _rebase_transient_terrain(node:Node,change:Vector2) -> void:
	if change.is_zero_approx(): return
	if node.is_in_group("MCSulfurIceTrail"):
		# Its tile image is node-local but its speed-boost hitbox is a world Rect2.
		var rect:Rect2 = node.get("cell_rect")
		node.set("cell_rect",Rect2(rect.position+change,rect.size))
	if node.is_in_group("DeltaBarbedWire"):
		# Previous-frame target points are only a motion cache, not terrain.
		# Re-seed it after the merge rather than sweeping across two arenas.
		(node.get("_inside") as Dictionary).clear()

func _merge_lane_key(node:Node2D) -> String:
	var key:String = str(node.get_meta("development_lane_key",""))
	if not key.is_empty(): return key
	if node.is_in_group("MCSpiderSilk"):
		var owner:Variant = node.get("unit")
		if not is_instance_valid(owner): return ""
		key = str(owner.get_meta("development_lane_key",""))
		return key if lanes.has(key) else lane_for_point(owner.global_position)
	# These are world-origin *shared* render/data services, not objects in
	# whichever lane happens to lie closest to (0,0).
	if node.name in ["MCSnowField","MinecartRails","MCFogField"]: return ""
	if node.get_parent() == world and node.is_in_group("BattleTransient") and node.global_position.is_zero_approx(): return ""
	return lane_for_point(node.global_position)

func _begin_merge() -> void:
	if phase != RUNNING:
		return
	phase = MERGING
	elapsed = maxf(float(Game.Game_Settings.get("Development_Duration",60.0)),1.0)
	# Godot 在 time_scale=0 或 SceneTree.paused 时会停掉整个渲染循环；
	# 改为只冻结发育计时、角色及 World 的战斗更新，保持独立真实时间动画可运行。
	Game.set_development_time_multiplier(1.0)
	_merge_nodes.clear()
	_merge_start_offsets.clear()
	_merge_terrain_managers.clear()
	for key:Variant in lanes.keys():
		_merge_start_offsets[str(key)] = _offset(str(key))
	for silk:Node in world.get_tree().get_nodes_in_group("MCSpiderSilk"):
		if world.is_ancestor_of(silk): silk.call("development_prepare_merge")
	# Graph routes and charge previews refer to lane-local rail IDs. Preserve
	# committed track, but end in-flight cart trips before two graphs coalesce.
	for cart:Node in world.get_tree().get_nodes_in_group("MCMinecart"):
		if not world.is_ancestor_of(cart): continue
		if int(cart.get("rush_phase")) != 0: cart.call("end_rush")
		cart.set("entry_needs_exit",false)
	var seen:Dictionary = {}
	for group:String in ["Ball","Shooter","BattleTransient"]:
		for node:Node in world.get_tree().get_nodes_in_group(group):
			if not node is Node2D or node.is_queued_for_deletion() or not world.is_ancestor_of(node):
				continue
			if seen.has(node.get_instance_id()):
				continue
			seen[node.get_instance_id()] = true
			var key:String = _merge_lane_key(node as Node2D)
			if not key.is_empty() and not lanes.has(key):
				continue
			if not node.has_meta("development_merge_mode"):
				node.set_meta("development_merge_mode",int(node.process_mode))
			node.process_mode = Node.PROCESS_MODE_DISABLED
			var move_node:bool = not key.is_empty() and not node.is_in_group("MCSpiderSilk")
			_merge_nodes.append({"node":node,"lane":key,"move":move_node,"local":(node as Node2D).global_position - _offset(key) if move_node else Vector2.ZERO,"last_offset":_offset(key)})
	for manager_name:String in ["MCSnowField","MinecartRails"]:
		var manager:Node = world.get_node_or_null(NodePath(manager_name))
		if manager is Node2D and manager.has_method("development_begin_merge"):
			manager.call("development_begin_merge",Callable(self,"lane_for_point"),_merge_start_offsets)
			_merge_terrain_managers.append(manager as Node2D)
	_merge_tween = world.create_tween()
	_merge_tween.set_ignore_time_scale(true)
	_merge_tween.tween_method(Callable(self,"_merge_frame"),0.0,1.0,MERGE_SECONDS)
	_merge_tween.finished.connect(_complete_merge,CONNECT_ONE_SHOT)

func _merge_frame(progress:float) -> void:
	if phase != MERGING or not world.is_inside_tree():
		return
	# t²：先缓慢靠近，再逐渐加快；两张地图在原地图中心完全重合。
	var remaining:float = 1.0 - progress*progress
	for raw_key:Variant in _merge_start_offsets.keys():
		var key:String = str(raw_key)
		var lane:Dictionary = lanes[key]
		lane["offset"] = (_merge_start_offsets[key] as Vector2) * remaining
		lanes[key] = lane
	if not portal_clones.is_empty():
		var source:PortalMap = world.map_group.get(_map_name) as PortalMap
		for raw_key:Variant in portal_clones.keys():
			var clone:PortalMap = portal_for_lane(str(raw_key))
			if clone != null:
				clone.position = source.position + _offset(str(raw_key))
	for entry:Dictionary in _merge_nodes:
		var n:Variant = entry.get("node")
		if is_instance_valid(n) and n is Node2D and not (n as Node2D).is_queued_for_deletion():
			var key:String = str(entry["lane"])
			if key.is_empty(): continue
			var current:Vector2 = _offset(key)
			var change:Vector2 = current - (entry["last_offset"] as Vector2)
			if bool(entry["move"]):
				(n as Node2D).global_position = (entry["local"] as Vector2) + current
				_rebase_owned_terrain(n,change)
				_rebase_transient_terrain(n,change)
			elif n.is_in_group("MCSpiderSilk") and not change.is_zero_approx():
				n.call("development_rebase",change)
			entry["last_offset"] = current
	for manager:Node2D in _merge_terrain_managers:
		if is_instance_valid(manager): manager.call("development_preview_merge",_merge_start_offsets,lanes)
	_build_islands()
	# 物理与时钟已冻结，只有地面、边框、阴影、遮罩和相机取景随副本移动。
	var map_node:Node = world._current_map_node()
	var map_rect:Rect2 = world_rect()
	world._refresh_map_background_tiles(map_node)
	world._refresh_map_outside_grid(world.return_map_visual_rect(map_node))
	world._refresh_map_outside_mask(map_rect)
	world._refresh_map_border_geometry(world.return_map_visual_rect(map_node))
	world._refresh_center_watermark_layout()
	world._apply_camera_zoom()

func _belongs_to_default(b:ball) -> bool:
	if b == null or not is_instance_valid(b):
		return false
	if b.has_meta("development_neutral") or b.scene_file_path.begins_with(DEFAULT_CHARACTER_DIR):
		return true
	if is_instance_valid(b.Master) and b.Master is ball and b.Master != b:
		return _belongs_to_default(b.Master)
	return false

func _complete_merge() -> void:
	if phase != MERGING:
		return
	_merge_frame(1.0)
	for manager:Node2D in _merge_terrain_managers:
		if is_instance_valid(manager): manager.call("development_finish_merge")
	_merge_terrain_managers.clear()
	# 合并后移除所有默认分区单位（包括盔甲架），不碰蓝/红队成员。
	for node:Node in world.get_tree().get_nodes_in_group("Ball"):
		if node is ball and _belongs_to_default(node as ball):
			Game.free_node(node)
	for entry:Dictionary in _merge_nodes:
		var n:Variant = entry.get("node")
		if is_instance_valid(n) and n is Node and (n as Node).has_meta("development_merge_mode"):
			(n as Node).process_mode = int((n as Node).get_meta("development_merge_mode"))
			(n as Node).remove_meta("development_merge_mode")
	_merge_nodes.clear()
	if Game.is_rotation_training_mode():
		for raw_id:Variant in candidates.keys():
			var id:int = int(raw_id)
			var b:Variant = candidates[id]
			if is_instance_valid(b) and b is ball and not (b as ball).is_queued_for_deletion() and _candidate_index(id) > 0:
				_park_candidate(b as ball)
	_drop_portal_clones()
	phase = BATTLE
	current_islands.clear()
	lanes.clear()
	base_islands.clear()
	_merge_start_offsets.clear()
	Game.set_development_time_multiplier(1.0)
	world.refresh_map_presentation()
	world._refresh_center_watermark()
	world._reset_victory_bell_state()
	# 正式战斗才启动已有的 duel / wheel / challenge 队列及 VS HUD。
	world._update_special_training_modes(0.0)
	world.refresh_versus_text()

func _collision_tree(node:Node,park:bool) -> void:
	if node is CollisionObject2D:
		var body:CollisionObject2D = node as CollisionObject2D
		if park:
			body.set_meta("development_collision_layer",body.collision_layer)
			body.set_meta("development_collision_mask",body.collision_mask)
			body.collision_layer = 0
			body.collision_mask = 0
		elif body.has_meta("development_collision_layer"):
			body.collision_layer = int(body.get_meta("development_collision_layer"))
			body.collision_mask = int(body.get_meta("development_collision_mask"))
			body.remove_meta("development_collision_layer")
			body.remove_meta("development_collision_mask")
	for child:Node in node.get_children():
		_collision_tree(child,park)

func _park_candidate(b:ball) -> void:
	if b.has_meta("development_reserve"):
		return
	b.set_meta("development_reserve",true)
	b.set_meta("development_reserve_process_mode",int(b.process_mode))
	b.set_meta("ignore_combat_targeting",true)
	_collision_tree(b,true)
	b.visible = false
	b.process_mode = Node.PROCESS_MODE_DISABLED

func _unpark_candidate(b:ball) -> void:
	if not b.has_meta("development_reserve"):
		return
	_collision_tree(b,false)
	b.visible = true
	b.process_mode = int(b.get_meta("development_reserve_process_mode",Node.PROCESS_MODE_INHERIT))
	b.remove_meta("development_reserve_process_mode")
	b.remove_meta("development_reserve")
	b.remove_meta("ignore_combat_targeting")

func take_candidate(setup_id:int,pos:Vector2) -> ball:
	if phase != BATTLE or not candidates.has(setup_id):
		return null
	var b:Variant = candidates[setup_id]
	if not is_instance_valid(b) or not b is ball or (b as ball).is_queued_for_deletion() or (b as ball).health <= 0:
		candidates.erase(setup_id)
		return null
	_unpark_candidate(b as ball)
	(b as ball).global_position = pos
	return b as ball

func on_character_removed(setup_id:int) -> void:
	if setup_id < 0:
		return
	candidates.erase(setup_id)
	if not is_prebattle() or not Game.is_rotation_training_mode():
		return
	var old_offsets:Dictionary = {}
	for raw_key:Variant in lanes.keys():
		old_offsets[str(raw_key)] = _offset(str(raw_key))
	var new_positions:Dictionary = {}
	var lane_reassignments:Dictionary = {}
	for raw_id:Variant in candidates.keys():
		var b:Variant = candidates[raw_id]
		if not is_instance_valid(b) or not b is ball:
			candidates.erase(raw_id)
			continue
		var old_key:String = str((b as ball).get_meta("development_lane_key",""))
		var new_key:String = _candidate_lane(int(raw_id))
		if new_key.is_empty() or old_key == new_key:
			continue
		new_positions[raw_id] = (b as ball).global_position - (old_offsets.get(old_key,Vector2.ZERO) as Vector2)
		lane_reassignments[old_key] = new_key
		(b as ball).set_meta("development_lane_key",new_key)
	_sync_lanes(false,lane_reassignments)
	for raw_id:Variant in new_positions.keys():
		var b:Variant = candidates.get(raw_id)
		if is_instance_valid(b) and b is ball:
			var final_position:Vector2 = (new_positions[raw_id] as Vector2) + _offset(str((b as ball).get_meta("development_lane_key")))
			var change:Vector2 = final_position - (b as ball).global_position
			(b as ball).global_position = final_position
			_rebase_owned_terrain(b,change)
			_rebase_owner_silk(b,change)
	for side:String in ["left","right"]:
		var roster:Array = world._rotation_rosters[side]
		if roster.is_empty():
			continue
		var first_id:int = int((roster[0] as Dictionary).get("id",-1))
		var first:Variant = candidates.get(first_id)
		if not is_instance_valid(first) or not first is ball:
			continue
		world._rotation_preview_character[side] = first
		(first as ball).set_meta("rotation_prestart_preview",true)
		if phase == SETUP:
			(first as ball).process_mode = Node.PROCESS_MODE_DISABLED
	world.refresh_map_presentation()
