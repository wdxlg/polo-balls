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


# Shared fresh-character copies. Parameters preserve Dice's historical third-
# stats/current-health/cooldown behavior and allow other abilities to differ.
const COPY_STAT_KEYS:Array[String] = ["Max_health","Damage","Speed","Attack_Cooling","Skill_Cooling","Health_Restore","Damage_reduction","max_block","max_energy"]
static func capture_character_template(target:ball) -> Dictionary:
	if not is_instance_valid(target) or target.is_queued_for_deletion(): return {}
	var scene:String = str(target.scene_file_path)
	var stats:Dictionary = {}
	for key:String in COPY_STAT_KEYS: stats[key] = target.get(key)
	return {"scene":scene,"label":scene.get_file().get_basename(),"stats":stats,
		"health":maxi(int(target.health),1),"block":maxi(int(target.block),0),"energy":maxi(int(target.energy),0)}

static func build_character_copy_profile(snapshot:Dictionary,factor:float,options:Dictionary = {}) -> Dictionary:
	if snapshot.is_empty() or not snapshot.has("stats"): return {}
	var raw:Dictionary = snapshot.stats
	var ratio:float = maxf(factor,0.0)
	var cooldown:float = maxf(float(options.get("cooldown_factor",1.0)),0.0001)
	var stats:Dictionary = {}
	for key:String in COPY_STAT_KEYS:
		var value:float = float(raw.get(key,0.0))
		match key:
			"Speed": stats[key] = value
			"Attack_Cooling","Skill_Cooling": stats[key] = value if is_equal_approx(cooldown,1.0) else maxf(value*cooldown,0.01)
			"Damage_reduction": stats[key] = value*ratio
			_: stats[key] = maxi(ceili(maxf(value,0.0)*ratio),1 if key=="Max_health" else 0)
	var full:bool = bool(options.get("full_vitals",true))
	return {"version":1,"source_scene":str(snapshot.scene),"source_label":str(snapshot.get("label","")),"stats":stats,
		"health":int(stats.Max_health) if full else clampi(ceili(float(snapshot.get("health",1))*ratio),1,int(stats.Max_health)),
		"block":int(stats.max_block) if full else maxi(ceili(float(snapshot.get("block",0))*ratio),0),
		"energy":int(stats.max_energy) if full else maxi(ceili(float(snapshot.get("energy",0))*ratio),0),
		"monochrome":bool(options.get("monochrome",false)),"master_name":str(options.get("master_name","")),
		"team":str(options.get("team","")),"neutral_owner":str(options.get("neutral_owner",""))}

static func apply_character_copy_profile(unit:ball,profile:Dictionary,apply_vitals:bool = true) -> void:
	if not is_instance_valid(unit) or profile.is_empty(): return
	var stats:Dictionary = profile.get("stats",{})
	unit.inherit_master_attack_power = false
	for key:String in COPY_STAT_KEYS:
		if stats.has(key): unit.set(key,stats[key])
	if not apply_vitals: return
	if unit.default_properties != null:
		for key:String in COPY_STAT_KEYS:
			if stats.has(key): unit.default_properties[key] = unit.get(key)
	# Reuse the shared silent state-migration path: creating a weaker copy is
	# not a hit/heal/kill, and cannot trip half-health or death passives.
	var had_silent:bool = unit.has_meta("death_return_restore")
	var saved_silent:Variant = unit.get_meta("death_return_restore",false)
	unit.set_meta("death_return_restore",true)
	unit.health = clampi(int(profile.get("health",unit.Max_health)),1,maxi(unit.Max_health,1))
	if unit.health_bar != null:
		unit.block = clampi(int(profile.get("block",0)),0,maxi(unit.max_block,0))
		unit.energy = clampi(int(profile.get("energy",0)),0,maxi(unit.max_energy,0))
	if had_silent: unit.set_meta("death_return_restore",saved_silent)
	else: unit.remove_meta("death_return_restore")
	var parent:Node = unit.get_parent()
	var owner_name:String = str(profile.get("master_name",""))
	if not owner_name.is_empty():
		unit.Master_name = owner_name
		if not is_instance_valid(unit.Master) and parent != null: unit.Master = parent.get_node_or_null(NodePath(owner_name)) as ball
	if not is_instance_valid(unit.Master) and not unit.has_meta("battle_lifecycle_identity"):
		var identity:Dictionary = profile.get("lifecycle",{})
		if not identity.is_empty(): unit.set_meta("battle_lifecycle_identity",identity.duplicate())
	var team:String = str(profile.get("team",unit.Team))
	if team.is_empty() and not str(profile.get("neutral_owner","")).is_empty(): team = "ReplicaFamily:"+str(profile.neutral_owner)
	unit.Team = team
	unit.set_meta(&"forced_combat_team",team)
	if bool(profile.get("monochrome",false)): unit._refresh_character_copy_visuals()

static func spawn_character_copy(context:Node,snapshot:Dictionary,point:Vector2,factor:float = 0.5,options:Dictionary = {}) -> ball:
	if not is_instance_valid(context) or not context.is_inside_tree() or not context.is_multiplayer_authority() or snapshot.is_empty(): return null
	var path:String = str(snapshot.get("scene",""))
	if path.is_empty() or not ResourceLoader.exists(path): return null
	var packed:PackedScene = load(path) as PackedScene
	if packed == null: return null
	var instance:Node = packed.instantiate()
	if not instance is ball:
		instance.free()
		return null
	var unit:ball = instance as ball
	var owner:ball = options.get("owner",context if context is ball else null) as ball
	var parent:Node = options.get("parent",context.get_parent()) as Node
	if not is_instance_valid(parent) or not parent.is_inside_tree() or parent.is_queued_for_deletion():
		unit.free()
		return null
	var settings:Dictionary = options.duplicate()
	if is_instance_valid(owner):
		settings["master_name"] = str(owner.name)
		settings["team"] = owner.Team
	var profile:Dictionary = build_character_copy_profile(snapshot,factor,settings)
	if profile.is_empty():
		unit.free()
		return null
	unit.character_copy_profile = profile
	apply_character_copy_profile(unit,profile,false)
	unit.Master = owner
	unit.Master_name = str(profile.get("master_name",""))
	unit.Team = str(profile.get("team",""))
	if unit.Team.is_empty() and not str(profile.get("neutral_owner","")).is_empty(): unit.Team = "ReplicaFamily:"+str(profile.neutral_owner)
	unit.set_meta(&"forced_combat_team",unit.Team)
	for key:Variant in settings.get("metadata",{}): unit.set_meta(key,settings.metadata[key])
	if bool(settings.get("assign_random_name",true)): unit.name = Game.return_random_name(unit)
	unit.set_multiplayer_authority(context.get_multiplayer_authority())
	var prepare:Callable = settings.get("prepare_instance",Callable())
	if prepare.is_valid(): prepare.call(unit)
	var world:Node = context.get_tree().current_scene
	var ticket:int = int(settings.get("lifecycle_ticket",0))
	if ticket > 0:
		if not world.has_method("apply_battle_spawn_identity") or not world.apply_battle_spawn_identity(unit,ticket):
			unit.free()
			return null
	elif is_instance_valid(owner) and world.has_method("bind_battle_lifecycle"):
		world.bind_battle_lifecycle(unit,owner)
	if unit.has_meta("battle_lifecycle_identity"):
		profile["lifecycle"] = (unit.get_meta("battle_lifecycle_identity") as Dictionary).duplicate()
		unit.character_copy_profile = profile
	unit.position = (parent as Node2D).to_local(point) if parent is Node2D else point
	parent.add_child(unit,true)
	# Signal/metadata hooks finish after the whole subclass _ready, but keep
	# this call for already-ready custom factories and historical Dice callers.
	apply_character_copy_profile(unit,profile,true)
	if Game.Game_Settings.Ball_Can_Move and world.has_method("_apply_or_record_initial_battle_direction"):
		world._apply_or_record_initial_battle_direction(unit)
	return unit
