class_name GeneratedTerrainSafetyManager
extends Node

# ============================================================
# 生成地形安全管理器
#
# 目的：
# 1. 新地形启用碰撞时如果已经压在角色身上，给这个角色临时碰撞例外，
#    让它先走出去，而不是被 StaticBody2D / AnimatableBody2D 卡死。
# 2. 地形主人（以及关闭友伤时的同队角色）永久无视自己队伍生成的地形，
#    避免棋手/矿工/投资者把自己或队友锁死。
# 3. 如果角色处于 Move 状态、方向有效、速度大于0，却持续几乎不动，
#    且附近确实有生成地形，就短暂无视附近生成地形作为兜底脱困。
#
# 这里不改角色和地图墙本身，只管理加入 GeneratedTerrain 组的临时地形。
# ============================================================

const MANAGER_GROUP:StringName = &"__generated_terrain_safety_manager"
const TERRAIN_GROUP:StringName = &"GeneratedTerrain"
const SCAN_INTERVAL:float = 0.08
const OVERLAP_MARGIN:float = 0.75
const EMERGENCY_NEAR_MARGIN:float = 18.0
const STUCK_TRIGGER_SECONDS:float = 0.72
const ESCAPE_SECONDS:float = 0.80
const PAIR_RELEASE_GRACE_MSEC:int = 220

# terrain instance id -> {shape_id, owner_id, owner_team}
var _terrains:Dictionary = {}
# "terrain_id:actor_id" -> {terrain_id, actor_id}
var _active_pairs:Dictionary = {}
# pair key -> last time this pair was still needed
var _pair_last_desired_msec:Dictionary = {}
# actor instance id -> motion state
var _actor_motion:Dictionary = {}
var _scan_left:float = 0.0


static func ensure_manager(tree:SceneTree) -> Node:
	if tree == null or tree.current_scene == null:
		return null
	var existing:Array[Node] = tree.get_nodes_in_group(MANAGER_GROUP)
	if not existing.is_empty():
		return existing[0]
	var manager := GeneratedTerrainSafetyManager.new()
	manager.name = "GeneratedTerrainSafetyManager"
	tree.current_scene.add_child(manager)
	return manager


func _ready() -> void:
	add_to_group(MANAGER_GROUP)
	# 尽量早于普通角色脚本执行安全扫描。
	process_physics_priority = -100


func register_terrain(body:PhysicsBody2D,shape_node:CollisionShape2D,owner_ball:Variant = null) -> void:
	if body == null or not is_instance_valid(body):
		return
	if shape_node == null or not is_instance_valid(shape_node) or shape_node.shape == null:
		return

	var owner_id:int = 0
	var owner_team:String = ""
	if owner_ball is ball and is_instance_valid(owner_ball):
		var typed_owner:ball = owner_ball as ball
		owner_id = typed_owner.get_instance_id()
		owner_team = typed_owner.Team

	body.add_to_group(TERRAIN_GROUP)
	_terrains[body.get_instance_id()] = {
		"shape_id": shape_node.get_instance_id(),
		"owner_id": owner_id,
		"owner_team": owner_team,
	}


func update_terrain_owner(body:PhysicsBody2D,owner_ball:Variant) -> void:
	if body == null or not is_instance_valid(body):
		return
	var terrain_id:int = body.get_instance_id()
	if not _terrains.has(terrain_id):
		return
	var entry:Dictionary = _terrains[terrain_id]
	if owner_ball is ball and is_instance_valid(owner_ball):
		var typed_owner:ball = owner_ball as ball
		entry["owner_id"] = typed_owner.get_instance_id()
		entry["owner_team"] = typed_owner.Team
	else:
		entry["owner_id"] = 0
		entry["owner_team"] = ""
	_terrains[terrain_id] = entry


# 在 CollisionShape2D 真正启用前主动调用。
# 即使目标角色已经位于生成位置内，也会先建立碰撞例外。
func prime_terrain(body:PhysicsBody2D) -> void:
	if body == null or not is_instance_valid(body):
		return
	var terrain_id:int = body.get_instance_id()
	if not _terrains.has(terrain_id):
		return
	var now_msec:int = Time.get_ticks_msec()
	var actual:Dictionary = _query_balls_for_terrain(terrain_id,OVERLAP_MARGIN)
	for actor_id_variant in actual.keys():
		var actor_id:int = int(actor_id_variant)
		_mark_pair_desired(terrain_id,actor_id,now_msec)

	# 主人/队友的碰撞例外不依赖当前是否重叠，提前建立。
	for actor in _get_live_actors():
		if _is_friendly_for_terrain(terrain_id,actor):
			_mark_pair_desired(terrain_id,actor.get_instance_id(),now_msec)


func _physics_process(delta:float) -> void:
	_scan_left -= delta
	if _scan_left > 0.0:
		return
	var step:float = SCAN_INTERVAL + maxf(-_scan_left,0.0)
	_scan_left = SCAN_INTERVAL
	_scan(step)


func _scan(step:float) -> void:
	_cleanup_dead_terrains()
	var actors:Array[ball] = _get_live_actors()
	_update_actor_motion(actors,step)
	var now_msec:int = Time.get_ticks_msec()

	for terrain_id_variant in _terrains.keys():
		var terrain_id:int = int(terrain_id_variant)
		if not is_instance_id_valid(terrain_id):
			continue

		# 正在真正穿入生成地形的角色：立即放行。
		var actual:Dictionary = _query_balls_for_terrain(terrain_id,OVERLAP_MARGIN)
		for actor_id_variant in actual.keys():
			var actor_id:int = int(actor_id_variant)
			_mark_pair_desired(terrain_id,actor_id,now_msec)
			_notify_terrain_overlap(terrain_id,actor_id)

		# 自己以及关闭友伤时的队友不被己方生成地形阻挡。
		for actor in actors:
			if _is_friendly_for_terrain(terrain_id,actor):
				_mark_pair_desired(terrain_id,actor.get_instance_id(),now_msec)

		# 角色确实“想移动但基本没动”时，才扩大查询范围做一次脱困。
		if _has_any_actor_in_escape_window():
			var nearby:Dictionary = _query_balls_for_terrain(terrain_id,EMERGENCY_NEAR_MARGIN)
			for actor_id_variant in nearby.keys():
				var actor_id:int = int(actor_id_variant)
				if _actor_is_in_escape_window(actor_id,now_msec):
					_mark_pair_desired(terrain_id,actor_id,now_msec)

	_release_stale_pairs(now_msec)
	_cleanup_dead_actor_motion()


func _get_live_actors() -> Array[ball]:
	var result:Array[ball] = []
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var actor:ball = node as ball
		if actor.Type != ball.Ball_Type.Ball or actor.health <= 0:
			continue
		if actor.state_machine != null and actor.state_machine.current_state == ball.State.Die:
			continue
		result.append(actor)
	return result


func _update_actor_motion(actors:Array[ball],step:float) -> void:
	var now_msec:int = Time.get_ticks_msec()
	for actor in actors:
		var actor_id:int = actor.get_instance_id()
		var state:Dictionary = _actor_motion.get(actor_id,{})
		var last_position:Vector2 = state.get("position",actor.global_position)
		var moved:float = actor.global_position.distance_to(last_position)
		var stuck_time:float = float(state.get("stuck_time",0.0))
		var escape_until:int = int(state.get("escape_until",0))

		var wants_move:bool = (
			actor.state_machine != null
			and actor.state_machine.current_state == ball.State.Move
			and actor.Speed > 1.0
			and actor.direction.length_squared() > 0.0001
			and not actor.dizziness
		)
		var expected_move:float = maxf(actor.Speed,0.0) * maxf(step,0.001)
		# 只要实际位移不到预期的约8%，并持续一段时间，才认为可能被硬卡。
		var low_motion_threshold:float = clampf(expected_move * 0.08,0.22,1.25)
		if wants_move and moved <= low_motion_threshold:
			stuck_time += step
		else:
			stuck_time = maxf(stuck_time - step * 2.0,0.0)

		if stuck_time >= STUCK_TRIGGER_SECONDS:
			escape_until = now_msec + int(round(ESCAPE_SECONDS * 1000.0))
			stuck_time = 0.0

		_actor_motion[actor_id] = {
			"position": actor.global_position,
			"stuck_time": stuck_time,
			"escape_until": escape_until,
		}


func _has_any_actor_in_escape_window() -> bool:
	var now_msec:int = Time.get_ticks_msec()
	for actor_id_variant in _actor_motion.keys():
		var state:Dictionary = _actor_motion[actor_id_variant]
		if int(state.get("escape_until",0)) > now_msec:
			return true
	return false


func _actor_is_in_escape_window(actor_id:int,now_msec:int) -> bool:
	if not _actor_motion.has(actor_id):
		return false
	return int((_actor_motion[actor_id] as Dictionary).get("escape_until",0)) > now_msec


func _is_friendly_for_terrain(terrain_id:int,actor:ball) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	if not _terrains.has(terrain_id):
		return false
	var entry:Dictionary = _terrains[terrain_id]
	var owner_id:int = int(entry.get("owner_id",0))
	if owner_id != 0 and actor.get_instance_id() == owner_id:
		return true

	var owner_team:String = str(entry.get("owner_team",""))
	if owner_team == "" or actor.Team == "" or actor.Team != owner_team:
		return false
	# 与项目现有攻击目标规则保持一致：关闭友伤时，同队地形也不阻挡队友。
	return not Game.Game_Settings.Have_Team_Damage


func _query_balls_for_terrain(terrain_id:int,margin:float) -> Dictionary:
	var result:Dictionary = {}
	if not _terrains.has(terrain_id):
		return result
	if not is_instance_id_valid(terrain_id):
		return result
	var terrain_obj:Variant = instance_from_id(terrain_id)
	if not terrain_obj is PhysicsBody2D:
		return result
	var terrain:PhysicsBody2D = terrain_obj as PhysicsBody2D

	var entry:Dictionary = _terrains[terrain_id]
	var shape_id:int = int(entry.get("shape_id",0))
	if shape_id == 0 or not is_instance_id_valid(shape_id):
		return result
	var shape_obj:Variant = instance_from_id(shape_id)
	if not shape_obj is CollisionShape2D:
		return result
	var shape_node:CollisionShape2D = shape_obj as CollisionShape2D
	if shape_node.shape == null:
		return result

	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape_node.shape
	params.transform = shape_node.global_transform
	params.margin = maxf(margin,0.0)
	params.collision_mask = 2
	params.collide_with_bodies = true
	params.collide_with_areas = false
	params.exclude = [terrain.get_rid()]

	var space_state:PhysicsDirectSpaceState2D = terrain.get_world_2d().direct_space_state
	var hits:Array[Dictionary] = space_state.intersect_shape(params,64)
	for hit:Dictionary in hits:
		var collider:Variant = hit.get("collider",null)
		if not collider is ball:
			continue
		var actor:ball = collider as ball
		if actor.Type != ball.Ball_Type.Ball or actor.health <= 0:
			continue
		result[actor.get_instance_id()] = true
	return result


func _notify_terrain_overlap(terrain_id:int,actor_id:int) -> void:
	if not is_instance_id_valid(terrain_id) or not is_instance_id_valid(actor_id):
		return
	var terrain_obj:Variant = instance_from_id(terrain_id)
	var actor_obj:Variant = instance_from_id(actor_id)
	if terrain_obj == null or actor_obj == null:
		return
	if terrain_obj.has_method("on_generated_terrain_overlap") and actor_obj is ball:
		terrain_obj.call("on_generated_terrain_overlap",actor_obj)


func _mark_pair_desired(terrain_id:int,actor_id:int,now_msec:int) -> void:
	if terrain_id == 0 or actor_id == 0:
		return
	var key:String = _pair_key(terrain_id,actor_id)
	_pair_last_desired_msec[key] = now_msec
	if _active_pairs.has(key):
		return
	if not is_instance_id_valid(terrain_id) or not is_instance_id_valid(actor_id):
		return
	var terrain_obj:Variant = instance_from_id(terrain_id)
	var actor_obj:Variant = instance_from_id(actor_id)
	if not terrain_obj is PhysicsBody2D or not actor_obj is PhysicsBody2D:
		return
	var terrain:PhysicsBody2D = terrain_obj as PhysicsBody2D
	var actor:PhysicsBody2D = actor_obj as PhysicsBody2D
	terrain.add_collision_exception_with(actor)
	actor.add_collision_exception_with(terrain)
	_active_pairs[key] = {
		"terrain_id": terrain_id,
		"actor_id": actor_id,
	}


func _release_stale_pairs(now_msec:int) -> void:
	var to_remove:Array[String] = []
	for key_variant in _active_pairs.keys():
		var key:String = str(key_variant)
		var last_desired:int = int(_pair_last_desired_msec.get(key,0))
		if now_msec - last_desired <= PAIR_RELEASE_GRACE_MSEC:
			continue
		to_remove.append(key)
	for key in to_remove:
		_remove_pair(key)


func _remove_pair(key:String) -> void:
	if not _active_pairs.has(key):
		_pair_last_desired_msec.erase(key)
		return
	var pair:Dictionary = _active_pairs[key]
	var terrain_id:int = int(pair.get("terrain_id",0))
	var actor_id:int = int(pair.get("actor_id",0))
	if is_instance_id_valid(terrain_id) and is_instance_id_valid(actor_id):
		var terrain_obj:Variant = instance_from_id(terrain_id)
		var actor_obj:Variant = instance_from_id(actor_id)
		if terrain_obj is PhysicsBody2D and actor_obj is PhysicsBody2D:
			var terrain:PhysicsBody2D = terrain_obj as PhysicsBody2D
			var actor:PhysicsBody2D = actor_obj as PhysicsBody2D
			terrain.remove_collision_exception_with(actor)
			actor.remove_collision_exception_with(terrain)
	_active_pairs.erase(key)
	_pair_last_desired_msec.erase(key)


func _cleanup_dead_terrains() -> void:
	var dead:Array[int] = []
	for terrain_id_variant in _terrains.keys():
		var terrain_id:int = int(terrain_id_variant)
		if not is_instance_id_valid(terrain_id):
			dead.append(terrain_id)
			continue
		var entry:Dictionary = _terrains[terrain_id]
		var shape_id:int = int(entry.get("shape_id",0))
		if shape_id == 0 or not is_instance_id_valid(shape_id):
			dead.append(terrain_id)
	for terrain_id in dead:
		_terrains.erase(terrain_id)
		var prefix:String = "%d:" % terrain_id
		var pair_keys:Array[String] = []
		for key_variant in _active_pairs.keys():
			var key:String = str(key_variant)
			if key.begins_with(prefix):
				pair_keys.append(key)
		for key in pair_keys:
			_remove_pair(key)


func _cleanup_dead_actor_motion() -> void:
	var dead:Array[int] = []
	for actor_id_variant in _actor_motion.keys():
		var actor_id:int = int(actor_id_variant)
		if not is_instance_id_valid(actor_id):
			dead.append(actor_id)
	for actor_id in dead:
		_actor_motion.erase(actor_id)


func _pair_key(terrain_id:int,actor_id:int) -> String:
	return "%d:%d" % [terrain_id,actor_id]
