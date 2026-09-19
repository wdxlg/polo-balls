extends RefCounted
class_name SubmissionCharacterTools

static func map_rect(node:Node) -> Rect2:
	if node == null or not is_instance_valid(node):
		return Rect2()
	var world = node.get_tree().current_scene
	if world == null or not world.has_method("return_map_world_rect"):
		return Rect2()
	var groups:Variant = world.get("map_group")
	var current_map:Variant = world.get("now_choose_map")
	if not groups is Dictionary:
		return Rect2()
	var map_groups:Dictionary = groups
	var key:String = str(current_map)
	if not map_groups.has(key):
		return Rect2()
	var map_node = map_groups[key]
	return world.return_map_world_rect(map_node)

# V434 性能：公共索敌候选。World 在 30Hz 网格重建时已经筛掉投射物、死亡单位、
# 退出 Ball 组 / 退出索敌契约的单位；这里只是拿到那份快照，调用方仍对每个候选
# 逐个执行实时 is_enemy()/距离判断，因此结果与遍历整个 Ball 组一致。
# 没有 World（编辑器/测试场景）或快照为空时退回 SceneTree group，行为不变。
static func targeting_candidates(node:Node) -> Array:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return []
	var tree:SceneTree = node.get_tree()
	var scene:Node = tree.current_scene
	if scene != null and scene.has_method("get_combat_targetable_units_fast"):
		var fast:Array = scene.call("get_combat_targetable_units_fast")
		if not fast.is_empty():
			return fast
	return tree.get_nodes_in_group("Ball")

static func combat_root(entity:ball) -> ball:
	if entity == null or not is_instance_valid(entity):
		return null
	# V431 性能：绝大多数调用者是没有 Master 的本体角色（每帧 2000+ 次调用）。
	# 深度 0/1 时直接返回，不再为环检测分配 Dictionary；结果与下面的通用循环完全一致。
	var first_master:ball = entity.Master
	if first_master == null or not is_instance_valid(first_master):
		return entity
	if first_master == entity:
		return entity
	var second_master:ball = first_master.Master
	if second_master == null or not is_instance_valid(second_master):
		return first_master
	var current:ball = entity
	var visited:Dictionary = {}
	for _i:int in range(12):
		if current == null or not is_instance_valid(current):
			return entity
		var current_id:int = current.get_instance_id()
		if visited.has(current_id):
			break
		visited[current_id] = true
		if current.Master == null or not is_instance_valid(current.Master):
			break
		current = current.Master
	return current

static func effective_team(entity:ball) -> String:
	if entity == null or not is_instance_valid(entity):
		return ""
	return _effective_team_with_root(entity,combat_root(entity))

static func _effective_team_with_root(entity:ball,root:ball) -> String:
	# V349：极少数运行时召唤物在网络生成/ready 的一两个时序点里，
	# Team 属性可能暂时被场景默认值覆盖。房产证“愤怒的人”把 authority
	# 拾取瞬间的固定阵营写进 forced_combat_team，让公共敌我判断始终先读这份稳定值。
	if entity.has_meta(&"forced_combat_team"):
		var forced_team:String = str(entity.get_meta(&"forced_combat_team","")).strip_edges()
		if not forced_team.is_empty() and forced_team != "Ball":
			return forced_team

	if root != null and is_instance_valid(root):
		if root != entity and root.has_meta(&"forced_combat_team"):
			var root_forced:String = str(root.get_meta(&"forced_combat_team","")).strip_edges()
			if not root_forced.is_empty() and root_forced != "Ball":
				return root_forced
		var root_team:String = str(root.Team).strip_edges()
		if not root_team.is_empty():
			return root_team
	return str(entity.Team).strip_edges()

static func same_side(a:ball,b:ball) -> bool:
	if a == null or b == null or not is_instance_valid(a) or not is_instance_valid(b):
		return false
	if a == b:
		return true
	var root_a:ball = combat_root(a)
	var root_b:ball = combat_root(b)
	if root_a != null and root_b != null and root_a == root_b:
		return true
	# V432 性能：根节点已经算出来了，直接复用，不再让 effective_team 各自重走一遍 combat_root。
	var team_a:String = _effective_team_with_root(a,root_a)
	var team_b:String = _effective_team_with_root(b,root_b)
	return not team_a.is_empty() and team_a == team_b

static func is_enemy(owner:ball,candidate:ball) -> bool:
	if owner == null or candidate == null or owner == candidate:
		return false
	if not is_instance_valid(owner) or not is_instance_valid(candidate):
		return false
	# V432 性能：先做整数/枚举过滤（生命、投射物类型），再进入 metadata 与召唤链判定；结果不变。
	if candidate.health <= 0 or candidate.Type == ball.Ball_Type.Shooter or candidate.Type == ball.Ball_Type.Shooter_with_Health:
		return false
	# V418：所有使用投稿角色工具索敌的角色也必须遵守公共可锁定契约。
	# 女巫隐身会通过 ignore_combat_targeting 让 is_combat_targetable() 返回 false。
	if not candidate.is_combat_targetable():
		return false
	# 投稿召唤物永远不把同主人、同召唤链或同队单位当作攻击目标。
	# 这里不依赖全局友伤开关，避免直接伤害接口误伤队友。
	if same_side(owner,candidate):
		return false
	return true

static func nearest_enemy(owner:ball,max_distance:float = INF) -> ball:
	if owner == null or not is_instance_valid(owner):
		return null
	var best:ball = null
	var best_sq:float = INF if max_distance == INF else max_distance * max_distance
	for raw:Node in targeting_candidates(owner):
		if not raw is ball:
			continue
		var candidate:ball = raw as ball
		if not is_enemy(owner,candidate):
			continue
		var d:float = owner.global_position.distance_squared_to(candidate.global_position)
		if d < best_sq:
			best_sq = d
			best = candidate
	return best

static func enemies_in_radius(owner:ball,center:Vector2,radius:float) -> Array[ball]:
	var out:Array[ball] = []
	if owner == null or not is_instance_valid(owner):
		return out
	var radius_sq:float = radius * radius
	for raw:Node in targeting_candidates(owner):
		if not raw is ball:
			continue
		var candidate:ball = raw as ball
		if not is_enemy(owner,candidate):
			continue
		if center.distance_squared_to(candidate.global_position) <= radius_sq:
			out.append(candidate)
	return out

static func safe_spawn_position(node:Node,desired:Vector2,margin:float = 24.0) -> Vector2:
	var rect:Rect2 = map_rect(node)
	if rect.size.x <= margin * 2.0 or rect.size.y <= margin * 2.0:
		return desired
	return Vector2(
		clampf(desired.x,rect.position.x + margin,rect.end.x - margin),
		clampf(desired.y,rect.position.y + margin,rect.end.y - margin)
	)

static func effective_master(source:ball) -> ball:
	if source == null:
		return null
	if source.Master != null and is_instance_valid(source.Master):
		return source.Master
	return source

static func source_is_melee(source:ball) -> bool:
	var root:ball = effective_master(source)
	if root == null:
		return false
	return root.has_type_tag("近战") or root.Type == ball.Ball_Type.Ball and source.Type == ball.Ball_Type.Ball
