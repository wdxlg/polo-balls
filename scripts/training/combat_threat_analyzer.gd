extends Node2D

# ============================================================
# 通用战斗威胁抽象层
# ============================================================
# AI 不认识“拳击手/保安/军官”这些名字，只认识：
# 1. 会移动的伤害体（projectile/body）
# 2. 线段/圆形/矩形攻击区域
# 3. 持续地形与阻挡
# 4. 控制场
# 5. 目标的反制/反射/防御风险
#
# 新角色如果使用标准 ball 投射物 / Has_Collision_Damage / AI_Hazard，自动被识别。
# 非标准技能只需要实现 get_ai_attack_threats(receiver) / get_ai_strategy_info(receiver)，
# 神经网络本身无需增加角色名字或专属输入。

@export_category("扫描")
@export_range(0.01,0.25,0.005) var scan_interval:float = 0.04
@export_range(100.0,4000.0,10.0) var max_scan_distance:float = 1500.0
@export_range(100.0,5000.0,10.0) var velocity_normalizer:float = 1600.0
@export_range(10.0,1000.0,10.0) var extent_normalizer:float = 320.0
@export_range(10.0,5000.0,10.0) var damage_red_at:float = 250.0
@export_range(0.1,5.0,0.05) var danger_time_normalizer:float = 1.5
@export_range(1,12,1) var max_threats:int = 6
@export_range(1,8,1) var max_targets:int = 4

@export_category("调试")
@export_range(0.05,1.0,0.05) var debug_fill_alpha:float = 0.22
@export_range(0.0,0.5,0.01) var debug_collision_fill_alpha:float = 0.08
@export_range(0.0,0.5,0.01) var debug_detection_fill_alpha:float = 0.055
@export_range(0.0,1.0,0.01) var debug_detection_outline_alpha:float = 0.28
@export_range(0.25,3.0,0.25) var debug_outline_width:float = 0.5
@export_range(8.0,80.0,1.0) var debug_direction_length:float = 30.0
@export_range(0.5,6.0,0.25) var debug_direction_width:float = 2.0
@export_range(3.0,18.0,0.5) var debug_direction_head_size:float = 7.0

var receiver:ball = null
var _scan_left:float = 0.0
var _debug_scan_left:float = 0.0
var _debug_was_enabled:bool = false
var _threats:Array[Dictionary] = []
# 调试层是“全场威胁视图”，不依赖某个极速者或某个 receiver。
# AI 查询仍通过 receiver 获取“对指定角色而言”的相对威胁。
var _debug_threats:Array[Dictionary] = []
var _targets:Array[Dictionary] = []
var _clock:float = 0.0
var _nuke_first_seen:Dictionary = {}


func _ready() -> void:
	# 即使 ESC 设置菜单让游戏暂停，也要能立即刷新/清掉威胁调试图形。
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 调试层位于普通 2D 战斗对象上方；CanvasLayer UI 仍会自然盖在它上面。
	z_as_relative = false
	z_index = 4000
	_debug_was_enabled = bool(Game.Game_Settings.get("Training_Debug_Mode",false))
	visible = _debug_was_enabled
	if _debug_was_enabled:
		_refresh_debug_world()
		queue_redraw()


# receiver 是“正在询问威胁的角色”，可以是任意 ball.Ball_Type.Ball，
# 不要求它是极速者，也不要求它实现任何 RL 专属方法。
func set_receiver(value:ball) -> void:
	receiver = value
	_scan_left = 0.0
	_refresh_now()


func _physics_process(delta:float) -> void:
	_clock += delta
	_scan_left -= delta
	_debug_scan_left -= delta

	# 调试显示只由设置开关控制，不再依赖训练模式，也不依赖是否存在极速者。
	var debug_enabled:bool = bool(Game.Game_Settings.get("Training_Debug_Mode",false))
	if debug_enabled != _debug_was_enabled:
		_debug_was_enabled = debug_enabled
		visible = debug_enabled
		if debug_enabled:
			_debug_scan_left = 0.0
			_refresh_debug_world()
		else:
			# 关闭时立刻清空并请求一次重绘，避免旧方框残留。
			_debug_threats.clear()
		queue_redraw()

	# AI 的 receiver 相对扫描与调试扫描完全分离。
	if _scan_left <= 0.0 and receiver != null and is_instance_valid(receiver) and receiver.is_inside_tree():
		_scan_left = maxf(scan_interval,0.01)
		_refresh_now()

	if debug_enabled and _debug_scan_left <= 0.0:
		_debug_scan_left = maxf(scan_interval,0.01)
		_refresh_debug_world()
		queue_redraw()


# 通用接口：任何角色都可以复用同一套威胁抽象。
func get_threats_for(value:ball) -> Array[Dictionary]:
	if value == null or not is_instance_valid(value) or not value.is_inside_tree():
		return []
	if value != receiver:
		set_receiver(value)
	elif _scan_left <= 0.0:
		_refresh_now()
	return _threats.duplicate(true)


func get_targets_for(value:ball) -> Array[Dictionary]:
	if value == null or not is_instance_valid(value) or not value.is_inside_tree():
		return []
	if value != receiver:
		set_receiver(value)
	elif _scan_left <= 0.0:
		_refresh_now()
	return _targets.duplicate(true)


# 通用调试/工具接口：取得当前全场的威胁区域，不需要指定角色。
func get_world_threats() -> Array[Dictionary]:
	if _debug_scan_left <= 0.0:
		_refresh_debug_world()
	return _debug_threats.duplicate(true)


func get_observation_for(value:ball) -> Array[float]:
	if value != receiver:
		set_receiver(value)
	elif _scan_left <= 0.0:
		_refresh_now()

	var obs:Array[float] = []
	if receiver == null or not is_instance_valid(receiver):
		return zero_observation()

	# self: 8
	obs.append(clampf(float(receiver.health) / maxf(float(receiver.Max_health),1.0),0.0,1.0))
	var max_energy_value:float = maxf(float(receiver.get("max_energy")) if _has_property(receiver,"max_energy") else 1.0,1.0)
	var energy_value:float = float(receiver.get("energy")) if _has_property(receiver,"energy") else 0.0
	obs.append(clampf(energy_value / max_energy_value,0.0,1.0))
	obs.append(clampf(receiver.direction.x,-1.0,1.0))
	obs.append(clampf(receiver.direction.y,-1.0,1.0))
	obs.append(clampf(float(receiver.Speed) / 1200.0,0.0,1.0))
	obs.append(clampf(float(receiver.Damage) / damage_red_at,0.0,1.0))
	var attack_active:bool = bool(receiver.get("_attack_active")) if _has_property(receiver,"_attack_active") else false
	obs.append(1.0 if attack_active else 0.0)
	var attack_stage:float = float(receiver.call("_attack_speed_stage")) if receiver.has_method("_attack_speed_stage") else 0.0
	obs.append(clampf(attack_stage / 4.0,0.0,1.0))

	# threat: 6 x 12
	for index:int in range(max_threats):
		if index < _threats.size():
			_append_threat_obs(obs,_threats[index])
		else:
			for _j:int in range(12): obs.append(0.0)

	# target: 4 x 12
	for index:int in range(max_targets):
		if index < _targets.size():
			_append_target_obs(obs,_targets[index])
		else:
			for _j:int in range(12): obs.append(0.0)
	return obs


func zero_observation() -> Array[float]:
	var result:Array[float] = []
	var count:int = 8 + max_threats * 12 + max_targets * 12
	for _i:int in range(count): result.append(0.0)
	return result


func get_best_threat() -> Dictionary:
	return _threats[0].duplicate(true) if not _threats.is_empty() else {}


func get_threats() -> Array[Dictionary]:
	return _threats.duplicate(true)


func get_targets() -> Array[Dictionary]:
	return _targets.duplicate(true)


func _refresh_now() -> void:
	_threats.clear()
	_targets.clear()
	if receiver == null or not is_instance_valid(receiver) or not receiver.is_inside_tree():
		return

	_scan_ball_entities()
	_scan_declared_attacks()
	_scan_hazards()
	_scan_bomber_bombs()
	_scan_manual_training_threats()
	_scan_special_runtime_fields()
	_scan_targets()

	_threats.sort_custom(func(a:Dictionary,b:Dictionary) -> bool: return float(a.get("severity",0.0)) > float(b.get("severity",0.0)))
	if _threats.size() > max_threats:
		_threats.resize(max_threats)
	_targets.sort_custom(func(a:Dictionary,b:Dictionary) -> bool: return float(a.get("target_score",0.0)) > float(b.get("target_score",0.0)))
	if _targets.size() > max_targets:
		_targets.resize(max_targets)


# ============================================================
# 全场调试扫描
# ============================================================
# 这里扫描“世界里实际存在/正在前摇的威胁区域”，不以极速者为中心。
# 因此：
# - 没有极速者也能显示；
# - 任意角色的投射物 / hitbox / 声明式攻击 / 危险地形都能显示；
# - 这份数据只负责可视化，不改变 AI observation 的固定维度。
func _refresh_debug_world() -> void:
	_debug_threats.clear()

	# 蓝色低透明度：角色/机制真正用于“是否开始攻击/技能”的检查区域。
	# 这只是调试层，不进入 AI observation，也不参与物理碰撞。
	_debug_scan_detection_regions()

	# V95：角色可单独声明“只给调试显示看的攻击范围”。
	# 这类区域不会进入 AI observation，适合重锤这种脚本几何：即使角色当前空闲，
	# 用户开启“威胁调试显示”后也能稳定看到下一次实际结算所使用的攻击圆。
	_debug_scan_explicit_attack_regions()

	# 调试层优先画“运行时真正存在的 CollisionShape2D”：
	# - 能造成伤害：白 -> 红（由伤害量决定）
	# - 无伤害碰撞/检测区域：绿色
	# - 显式标记 threat_debug_detection 的检测 Shape：蓝色
	# 这样人物本体、棋子实体、地面石头、投射物、实际 Hitbox 都使用真实几何。
	_debug_scan_collision_regions()

	# 没有物理 CollisionShape2D 的脚本攻击（爆炸、延迟斩击、核弹等）
	# 仍通过它们声明的真实伤害几何补充显示。
	_debug_scan_declared_attacks()
	_debug_scan_hazards()
	_debug_scan_bomber_bombs()
	_debug_scan_manual_training_threats()
	_debug_scan_special_runtime_fields()


func _debug_scan_ball_entities() -> void:
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var entity:ball = node as ball
		if entity.health <= 0:
			continue

		if entity.Type == ball.Ball_Type.Shooter or entity.Type == ball.Ball_Type.Shooter_with_Health:
			var projectile_shape:CollisionShape2D = entity.get_node_or_null("CollisionShape2D") as CollisionShape2D
			if projectile_shape == null:
				projectile_shape = _first_collision_shape(entity)
			if projectile_shape != null:
				_debug_add_shape_threat(entity,projectile_shape,_effective_damage(entity),0.0,0.12,false,0.0,"projectile",_motion_velocity(entity))
			else:
				_debug_add_circle_threat(entity,entity.global_position,_motion_velocity(entity),_collision_radius(entity),_effective_damage(entity),0.0,0.12,false,0.0,"projectile")
		elif entity.Type == ball.Ball_Type.Creature or entity.has_collision_damage():
			var body_shape:CollisionShape2D = entity.get_node_or_null("CollisionShape2D") as CollisionShape2D
			if body_shape == null:
				body_shape = _first_collision_shape(entity)
			if body_shape != null:
				_debug_add_shape_threat(entity,body_shape,_effective_damage(entity),0.0,0.10,false,0.0,"body_collision",_motion_velocity(entity))
			else:
				_debug_add_circle_threat(entity,entity.global_position,_motion_velocity(entity),_collision_radius(entity),_effective_damage(entity),0.0,0.10,false,0.0,"body_collision")

		# 正在工作的真实 hitbox 也直接画出其实际 CollisionShape2D。
		var hb:Area2D = entity.get_node_or_null("hitbox") as Area2D
		if hb != null and hb.monitoring:
			var shape_node:CollisionShape2D = _first_collision_shape(hb)
			if shape_node != null and not shape_node.disabled:
				var hitbox_radius:float = _collision_radius_from_shape(shape_node)
				var body_radius:float = _collision_radius(entity)
				if not entity.has_collision_damage() or hitbox_radius > body_radius * 1.15:
					_debug_add_shape_threat(entity,shape_node,_effective_damage(entity),0.0,0.08,false,0.0,"active_hitbox",_motion_velocity(entity))


func _debug_scan_declared_attacks() -> void:
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var attacker:ball = node as ball
		if attacker.Type != ball.Ball_Type.Ball or attacker.health <= 0 or not attacker.has_method("get_ai_attack_threats"):
			continue
		# 若角色提供了专用 get_debug_attack_regions()，调试层已经在上一阶段画过，
		# 这里不要再把同一个 get_ai_attack_threats() 区域叠画一遍。AI 正常扫描不受影响。
		if attacker.has_method("get_debug_attack_regions"):
			continue
		# 声明式接口只负责没有 CollisionShape2D 的“脚本伤害区域”。
		# 无伤害控制场不属于红白威胁，也不冒充绿色物理碰撞。
		var context:ball = _nearest_hostile_character(attacker)
		var raw:Variant = attacker.call("get_ai_attack_threats",context)
		if not raw is Array:
			continue
		for item:Variant in raw:
			if item is Dictionary and float((item as Dictionary).get("damage",0.0)) > 0.0:
				_debug_add_declared_threat(item as Dictionary,attacker)


func _debug_scan_hazards() -> void:
	for node:Node in get_tree().get_nodes_in_group("AI_Hazard"):
		if node == null or not is_instance_valid(node) or not node.has_method("get_ai_hazard_info"):
			continue

		var info:Dictionary = _debug_hazard_info(node)
		if info.is_empty():
			continue
		var damage:float = maxf(float(info.get("damage",0.0)),0.0)
		if damage <= 0.0:
			# 无伤害 Hazard（例如纯阻挡/控制）只有真正 CollisionShape2D 才会显示绿色。
			continue

		# 如果这个 Hazard 已经有当前有效的真实伤害 CollisionShape2D，
		# _debug_scan_collision_regions() 已经精确画过，不再叠一层抽象圆/矩形。
		if _debug_node_has_active_damage_collision(node):
			continue

		var source_node:Node = _node_from_variant(info.get("source",node),node)
		if source_node == null:
			continue
		_debug_add_declared_threat(info,source_node)


func _debug_scan_bomber_bombs() -> void:
	for node:Node in get_tree().get_nodes_in_group("BomberBomb"):
		if not node is Node2D:
			continue
		var props:Dictionary = _property_names(node)
		var radius:float = float(node.get("explosion_radius")) if props.has("explosion_radius") else 80.0
		var damage:float = float(node.get("damage_amount")) if props.has("damage_amount") else 0.0
		var danger_in:float = 0.0
		if props.has("is_ground") and bool(node.get("is_ground")):
			danger_in = danger_time_normalizer
		elif props.has("_fuse_left"):
			danger_in = maxf(float(node.get("_fuse_left")),0.0)
		_debug_add_circle_threat(node,(node as Node2D).global_position,Vector2.ZERO,radius,damage,danger_in,0.18,false,0.0,"explosion")


func _debug_scan_manual_training_threats() -> void:
	var scene:Node = get_tree().current_scene
	if scene != null:
		var manual:Node = scene.get_node_or_null("ManualTrainingController")
		if manual != null and manual.has_method("get_active_manual_melee_threats"):
			var characters:Array[ball] = _alive_characters()
			var raw:Variant = manual.call("get_active_manual_melee_threats",characters[0] if not characters.is_empty() else null)
			if raw is Array:
				for item:Variant in raw:
					if item is Dictionary:
						_debug_add_declared_threat(item as Dictionary,manual)

	for node:Node in get_tree().get_nodes_in_group("ManualTrainingProjectile"):
		if node is Node2D:
			var damage:float = float(node.get_meta("manual_training_damage",0.0))
			var radius:float = maxf(float(node.get_meta("manual_training_radius",8.0)),2.0)
			var velocity:Vector2 = Vector2.ZERO
			if _has_property(node,"direction") and _has_property(node,"Speed"):
				velocity = Vector2(node.get("direction")) * float(node.get("Speed"))
			_debug_add_circle_threat(node,(node as Node2D).global_position,velocity,radius,damage,0.0,0.12,false,0.0,"manual_projectile")


func _debug_scan_special_runtime_fields() -> void:
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var actor:ball = node as ball
		if actor.health <= 0:
			continue
		var props:Dictionary = _property_names(actor)
		if props.has("_shadow_active") and bool(actor.get("_shadow_active")) and props.has("_shadow_world_position") and props.has("shadow_hit_radius"):
			var center:Vector2 = actor.get("_shadow_world_position")
			var delay:float = maxf(float(actor.get("_shadow_hit_left")),0.0) if props.has("_shadow_hit_left") else 0.0
			var mult:float = float(actor.get("shadow_damage_multiplier")) if props.has("shadow_damage_multiplier") else 1.0
			_debug_add_circle_threat(actor,center,Vector2.ZERO,float(actor.get("shadow_hit_radius")),_effective_damage(actor)*mult,delay,0.12,false,0.0,"delayed_area")

	for node:Node in get_tree().get_nodes_in_group("OfficerNuke"):
		if not node is Node2D or not node.has_meta("ai_threat_target"):
			continue
		var target_pos:Vector2 = node.get_meta("ai_threat_target")
		var radius:float = float(node.get_meta("ai_threat_radius",320.0))
		var damage:float = float(node.get_meta("ai_threat_damage",1200.0))
		var id:int = node.get_instance_id()
		if not _nuke_first_seen.has(id):
			_nuke_first_seen[id] = _clock
		var total_delay:float = float(node.get_meta("ai_threat_delay",1.45))
		var danger_in:float = maxf(total_delay-(_clock-float(_nuke_first_seen[id])),0.0)
		_debug_add_circle_threat(node,target_pos,Vector2.ZERO,radius,damage,danger_in,0.25,false,0.0,"nuke")


# ============================================================
# 调试：实际攻击/技能检测范围（蓝色）
# ============================================================
# 标准接口：角色可实现 get_debug_detection_regions()，返回世界坐标几何：
#   {"shape":"circle", "position":Vector2, "radius":float}
#   {"shape":"rect", "position":Vector2, "half_extents":Vector2, "rotation":float}
#   {"shape":"segment", "start":Vector2, "end":Vector2, "radius":float}
# 这些区域只用于说明“什么时候会起手/锁定/触发技能”，不是伤害范围。
#
# 为兼容已有角色，还会自动读取一小组明确用于索敌/起手的传统字段。
# 非圆形或条件复杂的角色应实现上面的接口，避免用角色名字写特例。
func _debug_scan_detection_regions() -> void:
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var actor:ball = node as ball
		if actor.health <= 0 or not actor.is_inside_tree():
			continue

		var used_custom:bool = false
		if actor.has_method("get_debug_detection_regions"):
			var raw:Variant = actor.call("get_debug_detection_regions")
			if raw is Array:
				for item:Variant in raw:
					if item is Dictionary:
						_debug_add_declared_detection(item as Dictionary,actor)
				used_custom = true

		if used_custom:
			continue

		# 旧角色的通用圆形检测字段。只认这些明确语义的名字，
		# 不扫描所有 *_range，避免把投射物飞行距离/特效半径误画成起手检测。
		var props:Dictionary = _property_names(actor)
		var range_names:Array[String] = [
			"attack_range", "ranged_attack_range", "ranged_range", "umbrella_range",
			"enemy_notice_radius", "hiss_detect_range", "stab_range",
			"black_hole_cast_range", "push_activation_range", "gun_range"
		]
		for property_name:String in range_names:
			if not props.has(property_name):
				continue
			var radius:float = maxf(float(actor.get(property_name)),0.0)
			if radius <= 0.0:
				continue
			_debug_add_detection_circle(actor,actor.global_position,radius,"auto_" + property_name)


func _debug_scan_explicit_attack_regions() -> void:
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var actor:ball = node as ball
		if actor.health <= 0 or not actor.is_inside_tree() or not actor.has_method("get_debug_attack_regions"):
			continue
		var raw:Variant = actor.call("get_debug_attack_regions")
		if not raw is Array:
			continue
		for item:Variant in raw:
			if not item is Dictionary:
				continue
			var info:Dictionary = (item as Dictionary).duplicate(true)
			# _debug_add_declared_threat() 只接受真实伤害区域。若角色只给了几何，
			# 使用角色当前有效伤害作为颜色强度，但不改变任何玩法伤害。
			if float(info.get("damage",0.0)) <= 0.0:
				info["damage"] = maxf(_effective_damage(actor),1.0)
			_debug_add_declared_threat(info,actor)


func _debug_add_declared_detection(info:Dictionary,source:Node) -> void:
	var shape:String = str(info.get("shape","circle"))
	if shape == "polygon":
		_debug_add_declared_polygon(info,source,"detection",0.0)
	elif shape == "rect":
		_debug_add_detection_rect(
			source,
			Vector2(info.get("position",Vector2.ZERO)),
			Vector2(info.get("half_extents",Vector2.ONE * 8.0)),
			float(info.get("rotation",0.0)),
			str(info.get("kind","detection"))
		)
	elif shape == "segment":
		_debug_add_detection_segment(
			source,
			Vector2(info.get("start",Vector2.ZERO)),
			Vector2(info.get("end",Vector2.ZERO)),
			maxf(float(info.get("radius",2.0)),1.0),
			str(info.get("kind","detection"))
		)
	else:
		_debug_add_detection_circle(
			source,
			Vector2(info.get("position",Vector2.ZERO)),
			maxf(float(info.get("radius",4.0)),1.0),
			str(info.get("kind","detection"))
		)


func _debug_add_detection_circle(source:Node,position:Vector2,radius:float,kind:String) -> void:
	var info:Dictionary = _make_debug_threat(source,"circle",position,Vector2.ZERO,Vector2(radius,radius),0.0,0.0,0.05,false,0.0,kind,{"radius":radius})
	info["debug_role"] = "detection"
	_debug_threats.append(info)


func _debug_add_detection_rect(source:Node,center:Vector2,half:Vector2,rotation:float,kind:String) -> void:
	var info:Dictionary = _make_debug_threat(source,"rect",center,Vector2.ZERO,half,0.0,0.0,0.05,false,0.0,kind,{"half_extents":half,"rotation":rotation})
	info["debug_role"] = "detection"
	_debug_threats.append(info)


func _debug_add_detection_segment(source:Node,a:Vector2,b:Vector2,radius:float,kind:String) -> void:
	var center:Vector2 = (a + b) * 0.5
	var info:Dictionary = _make_debug_threat(source,"segment",center,Vector2.ZERO,Vector2(a.distance_to(b) * 0.5,radius),0.0,0.0,0.05,false,0.0,kind,{"start":a,"end":b,"radius":radius})
	info["debug_role"] = "detection"
	_debug_threats.append(info)


# ============================================================
# 调试：真实碰撞 / 真实伤害区域
# ============================================================
# V3.2 以后不再画“角色兜底威胁框”。
# 调试显示直接遍历当前场景里的 CollisionShape2D：
# - 此形状当前能造成伤害：debug_role = "damage"，颜色由白 -> 红；
# - 此形状当前没有伤害、但确实参与碰撞/检测：debug_role = "collision"，绿色；
# - Hurtbox 只是“可被打区域”，不属于阻挡/伤害提示，避免和人物本体重复。
#
# 对没有 CollisionShape2D 的脚本范围攻击，后面的 declared attack / hazard /
# explosion 扫描仍会补充真实的脚本伤害几何。
func _debug_scan_collision_regions() -> void:
	var scene:Node = get_tree().current_scene
	if scene == null:
		return
	_debug_scan_collision_regions_recursive(scene)


func _debug_scan_collision_regions_recursive(root:Node) -> void:
	if root == null or not is_instance_valid(root):
		return

	if root is CollisionShape2D:
		var shape_node:CollisionShape2D = root as CollisionShape2D
		if _debug_collision_shape_is_active(shape_node):
			var collision_parent:Node = shape_node.get_parent()
			var damage:float = _debug_damage_for_collision_shape(shape_node)
			var is_detection:bool = _debug_collision_shape_is_detection(shape_node)
			var role:String = "damage" if damage > 0.0 else ("detection" if is_detection else "collision")
			var source:Node = _debug_collision_source(shape_node)
			_debug_add_exact_collision_shape(
				source if source != null else collision_parent,
				shape_node,
				damage,
				role,
				"actual_damage" if damage > 0.0 else ("actual_detection" if is_detection else "actual_collision")
			)

	for child:Node in root.get_children():
		_debug_scan_collision_regions_recursive(child)


func _debug_collision_shape_is_detection(shape_node:CollisionShape2D) -> bool:
	if shape_node == null or not is_instance_valid(shape_node):
		return false
	if shape_node.has_meta("threat_debug_detection") and bool(shape_node.get_meta("threat_debug_detection")):
		return true
	var parent:Node = shape_node.get_parent()
	return parent != null and parent.has_meta("threat_debug_detection") and bool(parent.get_meta("threat_debug_detection"))


func _debug_collision_shape_is_active(shape_node:CollisionShape2D) -> bool:
	if shape_node == null or not is_instance_valid(shape_node):
		return false
	if shape_node.disabled or shape_node.shape == null or not shape_node.is_inside_tree():
		return false

	var parent:Node = shape_node.get_parent()
	if parent == null or not parent is CollisionObject2D:
		return false

	# Hurtbox 是受击检测区，不是“会伤害别人/会挡住别人”的区域。
	# 人物本体的 PhysicsBody CollisionShape2D 会另外以绿色显示。
	if parent is hurtbox:
		return false

	if parent is hitbox:
		# 非 monitoring 的 hitbox 当前不会自动接触命中，不应显示为常驻绿色区域。
		return (parent as Area2D).monitoring

	if parent is Area2D:
		var area:Area2D = parent as Area2D
		# layer/mask 都为 0 且也不 monitoring/monitorable 的 Area 没有任何物理意义。
		if area.collision_layer == 0 and area.collision_mask == 0 and not area.monitoring and not area.monitorable:
			return false
		# 显式允许脚本隐藏仅用于内部计算的传感器。
		if area.has_meta("threat_debug_hidden") and bool(area.get_meta("threat_debug_hidden")):
			return false
		return area.monitoring or area.monitorable or area.collision_layer != 0 or area.collision_mask != 0

	var obj:CollisionObject2D = parent as CollisionObject2D
	if obj.has_meta("threat_debug_hidden") and bool(obj.get_meta("threat_debug_hidden")):
		return false
	return obj.collision_layer != 0 or obj.collision_mask != 0


func _debug_collision_source(shape_node:CollisionShape2D) -> Node:
	var parent:Node = shape_node.get_parent()
	if parent is hitbox:
		var hb_owner:Node = parent.get_parent()
		if hb_owner is ball:
			return hb_owner
	if parent is Area2D:
		var hazard:Node = _debug_find_hazard_ancestor(parent)
		if hazard != null:
			return hazard
	return parent


func _debug_damage_for_collision_shape(shape_node:CollisionShape2D) -> float:
	if shape_node == null or shape_node.shape == null:
		return 0.0

	var parent:Node = shape_node.get_parent()
	if parent == null:
		return 0.0

	# 标准化覆盖：任何新机制都可以直接把真实碰撞对象标上这个 meta，
	# 威胁调试就不需要再增加角色名字特例。即使值是 0，也视为显式覆盖。
	if shape_node.has_meta("threat_debug_damage"):
		return maxf(float(shape_node.get_meta("threat_debug_damage")),0.0)
	if parent.has_meta("threat_debug_damage"):
		return maxf(float(parent.get_meta("threat_debug_damage")),0.0)

	# 标准 hitbox：只有当前 monitoring 时才是实际接触伤害区。
	if parent is hitbox:
		var hb:Area2D = parent as Area2D
		if not hb.monitoring:
			return 0.0
		var owner_node:Node = parent.get_parent()
		if owner_node is ball:
			return _effective_damage(owner_node as ball)
		return 0.0

	# ball 本体发生“身体碰撞伤害”时，根 CollisionShape2D 就是真实伤害区域。
	if parent is ball:
		var entity:ball = parent as ball
		return _effective_damage(entity) if entity.has_collision_damage() else 0.0

	# AI_Hazard 中真正 monitoring 的 Area2D 通常就是伤害传感区。
	# 例如棋子：StaticBody2D 实体轮廓是绿色，子 Area2D 伤害圈按伤害变色。
	if parent is Area2D and (parent as Area2D).monitoring:
		var hazard:Node = _debug_find_hazard_ancestor(parent)
		if hazard != null:
			var info:Dictionary = _debug_hazard_info(hazard)
			if not info.is_empty():
				return maxf(float(info.get("damage",0.0)),0.0)

	# 通用非 ball 伤害体：只读取明确表示“这个碰撞对象自身造成伤害”的字段。
	# 不读取 base_touch_damage 这类祖先字段，避免把棋子的实体阻挡体误染成红色。
	for key:String in ["collision_damage","damage_amount","impact_damage"]:
		if _has_property(parent,key):
			return maxf(float(parent.get(key)),0.0)

	return 0.0


func _debug_find_hazard_ancestor(node:Node) -> Node:
	var current:Node = node
	var depth:int = 0
	while current != null and depth < 8:
		if current.is_in_group("AI_Hazard") and current.has_method("get_ai_hazard_info"):
			return current
		current = current.get_parent()
		depth += 1
	return null


func _debug_hazard_info(hazard:Node) -> Dictionary:
	if hazard == null or not is_instance_valid(hazard) or not hazard.has_method("get_ai_hazard_info"):
		return {}

	# 一些 Hazard（棋子等）要求传入 receiver 才返回数据；调试层只需要其几何/伤害，
	# 所以依次拿任意活着的角色作为上下文。
	for context:ball in _alive_characters():
		var raw:Variant = hazard.call("get_ai_hazard_info",context)
		if raw is Dictionary and not (raw as Dictionary).is_empty():
			return raw as Dictionary

	var raw_without_receiver:Variant = hazard.call("get_ai_hazard_info",null)
	if raw_without_receiver is Dictionary:
		return raw_without_receiver as Dictionary
	return {}


func _debug_node_has_active_damage_collision(root:Node) -> bool:
	if root == null or not is_instance_valid(root):
		return false
	if root is CollisionShape2D:
		var shape_node:CollisionShape2D = root as CollisionShape2D
		if _debug_collision_shape_is_active(shape_node) and _debug_damage_for_collision_shape(shape_node) > 0.0:
			return true
	for child:Node in root.get_children():
		if _debug_node_has_active_damage_collision(child):
			return true
	return false


func _debug_add_exact_collision_shape(
	source:Node,
	shape_node:CollisionShape2D,
	damage:float,
	role:String,
	kind:String
) -> void:
	if shape_node == null or shape_node.shape == null:
		return

	var shape:Shape2D = shape_node.shape
	var points:PackedVector2Array = PackedVector2Array()

	if shape is CircleShape2D:
		var radius:float = (shape as CircleShape2D).radius
		for index:int in range(32):
			var angle:float = TAU * float(index) / 32.0
			points.append(shape_node.to_global(Vector2(cos(angle),sin(angle)) * radius))

	elif shape is RectangleShape2D:
		var half:Vector2 = (shape as RectangleShape2D).size * 0.5
		points = PackedVector2Array([
			shape_node.to_global(Vector2(-half.x,-half.y)),
			shape_node.to_global(Vector2( half.x,-half.y)),
			shape_node.to_global(Vector2( half.x, half.y)),
			shape_node.to_global(Vector2(-half.x, half.y)),
		])

	elif shape is CapsuleShape2D:
		var capsule:CapsuleShape2D = shape as CapsuleShape2D
		var radius:float = capsule.radius
		var half_body:float = maxf(capsule.height * 0.5 - radius,0.0)
		for index:int in range(13):
			var t:float = float(index) / 12.0
			var angle:float = lerpf(PI,TAU,t)
			points.append(shape_node.to_global(Vector2(cos(angle)*radius,-half_body + sin(angle)*radius)))
		for index:int in range(13):
			var t:float = float(index) / 12.0
			var angle:float = lerpf(0.0,PI,t)
			points.append(shape_node.to_global(Vector2(cos(angle)*radius,half_body + sin(angle)*radius)))

	elif shape is ConvexPolygonShape2D:
		for local_point:Vector2 in (shape as ConvexPolygonShape2D).points:
			points.append(shape_node.to_global(local_point))

	elif shape is SegmentShape2D:
		var segment:SegmentShape2D = shape as SegmentShape2D
		_debug_add_segment_threat(
			source,
			shape_node.to_global(segment.a),
			shape_node.to_global(segment.b),
			maxf(debug_outline_width * 0.5,0.5),
			damage,
			0.0,
			0.08,
			role == "collision",
			0.0,
			kind
		)
		_debug_threats[_debug_threats.size()-1]["debug_role"] = role
		return

	else:
		# 未专门支持的 Shape2D 用它自己的真实 AABB 作为最后退路；
		# 仍然遵守 CollisionShape2D 的 global transform，不再用角色半径猜测。
		var rect:Rect2 = shape.get_rect()
		points = PackedVector2Array([
			shape_node.to_global(rect.position),
			shape_node.to_global(rect.position + Vector2(rect.size.x,0.0)),
			shape_node.to_global(rect.position + rect.size),
			shape_node.to_global(rect.position + Vector2(0.0,rect.size.y)),
		])

	if points.size() < 3:
		return

	var center:Vector2 = Vector2.ZERO
	for point:Vector2 in points:
		center += point
	center /= float(points.size())

	var info:Dictionary = _make_debug_threat(
		source,
		"polygon",
		center,
		Vector2.ZERO,
		Vector2.ZERO,
		damage,
		0.0,
		0.08,
		role == "collision",
		0.0,
		kind,
		{"points":points,"debug_role":role}
	)
	_debug_threats.append(info)


func _alive_characters() -> Array[ball]:
	var result:Array[ball] = []
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if node is ball:
			var candidate:ball = node as ball
			if candidate.Type == ball.Ball_Type.Ball and candidate.health > 0 and candidate.is_inside_tree():
				result.append(candidate)
	return result


func _nearest_hostile_character(source:ball) -> ball:
	var best:ball = null
	var best_d2:float = INF
	for candidate:ball in _alive_characters():
		if candidate == source or not _balls_are_hostile(source,candidate):
			continue
		var d2:float = source.global_position.distance_squared_to(candidate.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = candidate
	return best


func _balls_are_hostile(a:ball,b:ball) -> bool:
	if a == null or b == null:
		return false
	var team_a:String = a.Team
	var team_b:String = b.Team
	if a.Master != null and is_instance_valid(a.Master) and (team_a.is_empty() or team_a == "Ball"):
		team_a = a.Master.Team
	if b.Master != null and is_instance_valid(b.Master) and (team_b.is_empty() or team_b == "Ball"):
		team_b = b.Master.Team
	return team_a.is_empty() or team_b.is_empty() or team_a != team_b


func _debug_add_declared_polygon(info:Dictionary,source:Node,role:String,damage:float) -> void:
	var points:PackedVector2Array = info.get("points",PackedVector2Array())
	if points.size() < 3: return
	var region:Dictionary = info.duplicate(true)
	region["source"] = source
	region["source_id"] = source.get_instance_id() if is_instance_valid(source) else 0
	region["debug_role"] = role
	region["damage"] = damage
	_debug_threats.append(region)


func _debug_add_declared_threat(info:Dictionary,default_source:Node) -> void:
	var source:Node = _node_from_variant(info.get("source",default_source),default_source)
	var damage:float = maxf(float(info.get("damage",_source_damage(source))),0.0)
	if damage <= 0.0:
		return

	var shape:String = str(info.get("shape","circle"))
	var danger_in:float = maxf(float(info.get("danger_in",0.0)),0.0)
	var duration:float = maxf(float(info.get("danger_duration",0.1)),0.02)
	var blocking:bool = bool(info.get("blocking",false))
	var control:float = float(info.get("control",0.0))
	var before_count:int = _debug_threats.size()

	if shape == "polygon":
		_debug_add_declared_polygon(info,source,"damage",damage)
	elif shape == "segment":
		var a:Vector2 = info.get("start",Vector2.ZERO)
		var b:Vector2 = info.get("end",a)
		var radius:float = maxf(float(info.get("radius",4.0)),1.0)
		_debug_add_segment_threat(source,a,b,radius,damage,danger_in,duration,blocking,control,str(info.get("kind","segment")))
	elif shape == "rect":
		_debug_add_rect_threat(source,Vector2(info.get("position",Vector2.ZERO)),Vector2(info.get("half_extents",Vector2.ONE*8.0)),float(info.get("rotation",0.0)),Vector2(info.get("velocity",Vector2.ZERO)),damage,danger_in,duration,blocking,control,str(info.get("kind","rect")))
	else:
		_debug_add_circle_threat(source,Vector2(info.get("position",Vector2.ZERO)),Vector2(info.get("velocity",Vector2.ZERO)),maxf(float(info.get("radius",4.0)),1.0),damage,danger_in,duration,blocking,control,str(info.get("kind","circle")))

	var explicit_direction_value:Variant = info.get("direction",Vector2.ZERO)
	for index:int in range(before_count,_debug_threats.size()):
		_debug_threats[index]["debug_role"] = "damage"
		if explicit_direction_value is Vector2 and (explicit_direction_value as Vector2).length_squared() > 0.000001:
			_debug_threats[index]["direction"] = (explicit_direction_value as Vector2).normalized()


func _debug_add_circle_threat(source:Node,position:Vector2,velocity:Vector2,radius:float,damage:float,danger_in:float,duration:float,blocking:bool,control:float,kind:String) -> void:
	var extent:=Vector2(radius,radius)
	_debug_threats.append(_make_debug_threat(source,"circle",position,velocity,extent,damage,danger_in,duration,blocking,control,kind,{"radius":radius}))


func _debug_add_segment_threat(source:Node,a:Vector2,b:Vector2,radius:float,damage:float,danger_in:float,duration:float,blocking:bool,control:float,kind:String,velocity:Vector2 = Vector2.ZERO) -> void:
	var center:Vector2 = (a+b)*0.5
	var ext:=Vector2(a.distance_to(b)*0.5,radius)
	_debug_threats.append(_make_debug_threat(source,"segment",center,velocity,ext,damage,danger_in,duration,blocking,control,kind,{"start":a,"end":b,"radius":radius}))


func _debug_add_rect_threat(source:Node,center:Vector2,half:Vector2,rotation:float,velocity:Vector2,damage:float,danger_in:float,duration:float,blocking:bool,control:float,kind:String) -> void:
	_debug_threats.append(_make_debug_threat(source,"rect",center,velocity,half,damage,danger_in,duration,blocking,control,kind,{"half_extents":half,"rotation":rotation}))


func _make_debug_threat(source:Node,shape:String,position:Vector2,velocity:Vector2,extent:Vector2,damage:float,danger_in:float,duration:float,blocking:bool,control:float,kind:String,extra:Dictionary) -> Dictionary:
	var time_score:float = 1.0-clampf(danger_in/danger_time_normalizer,0.0,1.0)
	var damage_score:float = clampf(damage/damage_red_at,0.0,2.0)
	var severity:float = damage_score*1.4 + time_score*1.1 + control*0.35 + (0.25 if blocking else 0.0)
	var source_id:int = source.get_instance_id() if source != null and is_instance_valid(source) else 0
	var d:Dictionary = {
		"source":source,"source_id":source_id,"shape":shape,"position":position,"velocity":velocity,"extent":extent,
		"damage":maxf(damage,0.0),"danger_in":maxf(danger_in,0.0),"danger_duration":maxf(duration,0.02),
		"blocking":blocking,"control":clampf(control,0.0,1.0),"kind":kind,"severity":severity,
	}
	for key:Variant in extra.keys():
		d[key] = extra[key]
	# V4.7：所有威胁统一暴露 direction:Vector2。移动体优先使用速度方向，
	# 线段/矩形使用几何朝向，最后才回退到 source 自己的朝向。
	d["direction"] = _resolve_threat_direction(d,source)
	return d


func _debug_add_shape_threat(source:Node,shape_node:CollisionShape2D,damage:float,danger_in:float,duration:float,blocking:bool,control:float,kind:String,velocity:Vector2 = Vector2.ZERO) -> void:
	if shape_node == null or shape_node.shape == null:
		return
	var sh:Shape2D = shape_node.shape
	var scale_v:Vector2 = shape_node.global_scale.abs()
	if sh is CircleShape2D:
		_debug_add_circle_threat(source,shape_node.global_position,velocity,(sh as CircleShape2D).radius*maxf(scale_v.x,scale_v.y),damage,danger_in,duration,blocking,control,kind)
	elif sh is RectangleShape2D:
		var half:Vector2 = (sh as RectangleShape2D).size*scale_v*0.5
		_debug_add_rect_threat(source,shape_node.global_position,half,shape_node.global_rotation,velocity,damage,danger_in,duration,blocking,control,kind)
	elif sh is CapsuleShape2D:
		var cap:CapsuleShape2D = sh as CapsuleShape2D
		var radius:float = cap.radius*maxf(scale_v.x,scale_v.y)
		var half_len:float = maxf(cap.height*scale_v.y*0.5-radius,0.0)
		var axis:Vector2 = Vector2.UP.rotated(shape_node.global_rotation)
		_debug_add_segment_threat(source,shape_node.global_position-axis*half_len,shape_node.global_position+axis*half_len,radius,damage,danger_in,duration,blocking,control,kind,velocity)
	else:
		_debug_add_circle_threat(source,shape_node.global_position,velocity,_collision_radius_from_shape(shape_node),damage,danger_in,duration,blocking,control,kind)


func _scan_ball_entities() -> void:
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var entity:ball = node as ball
		if entity == receiver or not _is_hostile_ball(entity) or entity.health <= 0:
			continue
		if receiver.global_position.distance_squared_to(entity.global_position) > max_scan_distance * max_scan_distance:
			continue

		if entity.Type == ball.Ball_Type.Shooter or entity.Type == ball.Ball_Type.Shooter_with_Health:
			var projectile_damage:float = _effective_damage(entity)
			var projectile_shape:CollisionShape2D = entity.get_node_or_null("CollisionShape2D") as CollisionShape2D
			if projectile_shape == null:
				projectile_shape = _first_collision_shape(entity)
			if projectile_shape != null:
				_add_shape_threat(entity,projectile_shape,projectile_damage,0.0,0.12,false,0.0,"projectile",_motion_velocity(entity))
			else:
				_add_circle_threat(entity,entity.global_position,_motion_velocity(entity),_collision_radius(entity),projectile_damage,0.0,0.12,false,0.0,"projectile")
		elif entity.Type == ball.Ball_Type.Creature or entity.has_collision_damage():
			var body_shape:CollisionShape2D = entity.get_node_or_null("CollisionShape2D") as CollisionShape2D
			if body_shape == null:
				body_shape = _first_collision_shape(entity)
			if body_shape != null:
				_add_shape_threat(entity,body_shape,_effective_damage(entity),0.0,0.10,false,0.0,"body_collision",_motion_velocity(entity))
			else:
				_add_circle_threat(entity,entity.global_position,_motion_velocity(entity),_collision_radius(entity),_effective_damage(entity),0.0,0.10,false,0.0,"body_collision")

		# 临时扩大/开启的真实 Hitbox：用于战士等“攻击时碰撞箱变大”的角色。
		var hb:Area2D = entity.get_node_or_null("hitbox") as Area2D
		if hb != null and hb.monitoring:
			var shape_node:CollisionShape2D = _first_collision_shape(hb)
			if shape_node != null and not shape_node.disabled:
				var hitbox_radius:float = _collision_radius_from_shape(shape_node)
				var body_radius:float = _collision_radius(entity)
				# 普通贴身伤害体不重复占用 threat slot；只有 hitbox 明显比本体大时才额外暴露。
				if not entity.has_collision_damage() or hitbox_radius > body_radius * 1.15:
					_add_shape_threat(entity,shape_node,_effective_damage(entity),0.0,0.08,false,0.0,"active_hitbox",_motion_velocity(entity))


func _scan_declared_attacks() -> void:
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var enemy:ball = node as ball
		if enemy == receiver or not _is_hostile_ball(enemy) or enemy.health <= 0:
			continue
		if not enemy.has_method("get_ai_attack_threats"):
			continue
		var raw:Variant = enemy.call("get_ai_attack_threats",receiver)
		if not raw is Array:
			continue
		for item:Variant in raw:
			if item is Dictionary:
				_add_declared_threat(item as Dictionary,enemy)


func _scan_hazards() -> void:
	for node:Node in get_tree().get_nodes_in_group("AI_Hazard"):
		if node == null or not is_instance_valid(node) or not node.has_method("get_ai_hazard_info"):
			continue
		var raw:Variant = node.call("get_ai_hazard_info",receiver)
		if not raw is Dictionary or (raw as Dictionary).is_empty():
			continue
		var info:Dictionary = raw as Dictionary
		var owner:Node = _node_from_variant(info.get("source",node),node)
		if owner == null or not _source_is_hostile(owner):
			continue
		_add_declared_threat(info,owner)


func _scan_bomber_bombs() -> void:
	for node:Node in get_tree().get_nodes_in_group("BomberBomb"):
		if not node is Node2D or not _source_is_hostile(node):
			continue
		var props:Dictionary = _property_names(node)
		var radius:float = float(node.get("explosion_radius")) if props.has("explosion_radius") else 80.0
		var damage:float = float(node.get("damage_amount")) if props.has("damage_amount") else 0.0
		var danger_in:float = 0.0
		if props.has("is_ground") and bool(node.get("is_ground")):
			# 地雷本身不会自己爆，但一旦链爆会形成这个区域；作为持续潜在危险呈现。
			danger_in = danger_time_normalizer
		elif props.has("_fuse_left"):
			danger_in = maxf(float(node.get("_fuse_left")),0.0)
		_add_circle_threat(node,node.global_position,Vector2.ZERO,radius,damage,danger_in,0.18,false,0.0,"explosion")


func _scan_manual_training_threats() -> void:
	var scene:Node = get_tree().current_scene
	if scene == null:
		return
	var manual:Node = scene.get_node_or_null("ManualTrainingController")
	if manual != null and manual.has_method("get_active_manual_melee_threats"):
		var raw:Variant = manual.call("get_active_manual_melee_threats",receiver)
		if raw is Array:
			for item:Variant in raw:
				if item is Dictionary: _add_declared_threat(item as Dictionary,manual)

	for node:Node in get_tree().get_nodes_in_group("ManualTrainingProjectile"):
		if node is Node2D:
			var damage:float = float(node.get_meta("manual_training_damage",0.0))
			var radius:float = maxf(float(node.get_meta("manual_training_radius",8.0)),2.0)
			var velocity:Vector2 = Vector2.ZERO
			if _has_property(node,"direction") and _has_property(node,"Speed"):
				velocity = Vector2(node.get("direction")) * float(node.get("Speed"))
			_add_circle_threat(node,(node as Node2D).global_position,velocity,radius,damage,0.0,0.12,false,0.0,"manual_projectile")


func _scan_special_runtime_fields() -> void:
	# 这里按“机制字段”而不是角色名字识别；同机制的新角色会自动被概括。
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var enemy:ball = node as ball
		if enemy == receiver or not _is_hostile_ball(enemy) or enemy.health <= 0:
			continue
		var props:Dictionary = _property_names(enemy)

		# 影子/延迟分身式范围伤害。
		if props.has("_shadow_active") and bool(enemy.get("_shadow_active")) and props.has("_shadow_world_position") and props.has("shadow_hit_radius"):
			var center:Vector2 = enemy.get("_shadow_world_position")
			var delay:float = maxf(float(enemy.get("_shadow_hit_left")),0.0) if props.has("_shadow_hit_left") else 0.0
			var mult:float = float(enemy.get("shadow_damage_multiplier")) if props.has("shadow_damage_multiplier") else 1.0
			_add_circle_threat(enemy,center,Vector2.ZERO,float(enemy.get("shadow_hit_radius")),_effective_damage(enemy)*mult,delay,0.12,false,0.0,"delayed_area")

		# 磁铁类“控制场”：无直接伤害，但会改变角色/投射物方向。
		if props.has("influence_radius") and props.has("character_turn_strength"):
			_add_circle_threat(enemy,enemy.global_position,Vector2.ZERO,float(enemy.get("influence_radius")),0.0,0.0,0.20,false,1.0,"control_field")

	# 军官核弹落点：节点本身会带通用 ai_* meta（补丁给军官增加）。
	for node:Node in get_tree().get_nodes_in_group("OfficerNuke"):
		if not node is Node2D or not node.has_meta("ai_threat_target"):
			continue
		if node.has_meta("officer_nuke_owner"):
			var owner_id:int = int(node.get_meta("officer_nuke_owner"))
			var owner_obj:Object = instance_from_id(owner_id)
			if owner_obj is ball and not _is_hostile_ball(owner_obj as ball):
				continue
		var target_pos:Vector2 = node.get_meta("ai_threat_target")
		var radius:float = float(node.get_meta("ai_threat_radius",320.0))
		var damage:float = float(node.get_meta("ai_threat_damage",1200.0))
		var id:int = node.get_instance_id()
		if not _nuke_first_seen.has(id): _nuke_first_seen[id] = _clock
		var total_delay:float = float(node.get_meta("ai_threat_delay",1.45))
		var danger_in:float = maxf(total_delay-(_clock-float(_nuke_first_seen[id])),0.0)
		_add_circle_threat(node,target_pos,Vector2.ZERO,radius,damage,danger_in,0.25,false,0.0,"nuke")


func _scan_targets() -> void:
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if target == receiver or target.Type != ball.Ball_Type.Ball or target.health <= 0 or not _is_hostile_ball(target):
			continue
		var rel:Vector2 = target.global_position - receiver.global_position
		if rel.length() > max_scan_distance:
			continue
		var info:Dictionary = {
			"source":target,
			"position":target.global_position,
			"velocity":_motion_velocity(target),
			"health_ratio":clampf(float(target.health)/maxf(float(target.Max_health),1.0),0.0,1.0),
			"damage":_effective_damage(target),
			"counter_risk":0.0,
			"reflect_risk":0.0,
			"defense_risk":clampf((float(target.block) if _has_property(target,"block") else 0.0)/maxf(float(target.Max_health),1.0),0.0,1.0),
			"control_risk":0.0,
		}
		_apply_strategy_info(info,target)
		var distance_score:float = 1.0-clampf(rel.length()/max_scan_distance,0.0,1.0)
		var health_score:float = 1.0-float(info["health_ratio"])
		info["target_score"] = distance_score*0.55 + health_score*0.25 - float(info["counter_risk"])*0.45 - float(info["reflect_risk"])*0.35
		_targets.append(info)


func _apply_strategy_info(info:Dictionary,target:ball) -> void:
	if target.has_method("get_ai_strategy_info"):
		var raw:Variant = target.call("get_ai_strategy_info",receiver)
		if raw is Dictionary:
			for key:Variant in (raw as Dictionary).keys(): info[key] = (raw as Dictionary)[key]

	var props:Dictionary = _property_names(target)
	# 伤害越多越接近大反击（军官类）。
	if props.has("rage_percent"):
		info["counter_risk"] = maxf(float(info.get("counter_risk",0.0)),clampf(float(target.get("rage_percent"))/100.0,0.0,1.0))
	if props.has("nuke_active") and bool(target.get("nuke_active")):
		info["counter_risk"] = 1.0
	# 受伤累计触发反击（裁判类）。
	if props.has("card_damage_threshold") and target.has_method("_current_window_damage"):
		var threshold:float = maxf(float(target.get("card_damage_threshold")),1.0)
		info["counter_risk"] = maxf(float(info.get("counter_risk",0.0)),clampf(float(target.call("_current_window_damage"))/threshold,0.0,1.0))
	# 反射窗口。
	if props.has("_reflect_active") and bool(target.get("_reflect_active")):
		info["reflect_risk"] = 1.0
	# 决斗者等方向格挡可通过自定义接口覆盖；基础 block 也会给 defense_risk。
	if props.has("remaining_lives") and props.has("total_lives"):
		var total:float = maxf(float(target.get("total_lives")),1.0)
		info["defense_risk"] = maxf(float(info.get("defense_risk",0.0)),clampf((float(target.get("remaining_lives"))-1.0)/total,0.0,1.0)*0.35)
	if props.has("influence_radius") and receiver.global_position.distance_to(target.global_position) <= float(target.get("influence_radius")):
		info["control_risk"] = 1.0


func _append_threat_obs(obs:Array[float],info:Dictionary) -> void:
	var rel:Vector2 = Vector2(info.get("position",Vector2.ZERO)) - receiver.global_position
	var rel_vel:Vector2 = Vector2(info.get("velocity",Vector2.ZERO)) - _motion_velocity(receiver)
	var ext:Vector2 = Vector2(info.get("extent",Vector2.ZERO))
	obs.append(1.0)
	obs.append(clampf(rel.x/max_scan_distance,-1.0,1.0))
	obs.append(clampf(rel.y/max_scan_distance,-1.0,1.0))
	obs.append(clampf(rel_vel.x/velocity_normalizer,-1.0,1.0))
	obs.append(clampf(rel_vel.y/velocity_normalizer,-1.0,1.0))
	obs.append(clampf(ext.x/extent_normalizer,0.0,1.0))
	obs.append(clampf(ext.y/extent_normalizer,0.0,1.0))
	obs.append(clampf(float(info.get("damage",0.0))/damage_red_at,0.0,1.0))
	obs.append(clampf(float(info.get("danger_in",0.0))/danger_time_normalizer,0.0,1.0))
	obs.append(clampf(float(info.get("danger_duration",0.0))/danger_time_normalizer,0.0,1.0))
	obs.append(1.0 if bool(info.get("blocking",false)) else 0.0)
	obs.append(clampf(float(info.get("control",0.0)),0.0,1.0))


func _append_target_obs(obs:Array[float],info:Dictionary) -> void:
	var rel:Vector2 = Vector2(info.get("position",Vector2.ZERO)) - receiver.global_position
	var vel:Vector2 = Vector2(info.get("velocity",Vector2.ZERO))
	obs.append(1.0)
	obs.append(clampf(rel.x/max_scan_distance,-1.0,1.0))
	obs.append(clampf(rel.y/max_scan_distance,-1.0,1.0))
	obs.append(clampf(vel.x/velocity_normalizer,-1.0,1.0))
	obs.append(clampf(vel.y/velocity_normalizer,-1.0,1.0))
	obs.append(clampf(float(info.get("health_ratio",0.0)),0.0,1.0))
	obs.append(clampf(float(info.get("damage",0.0))/damage_red_at,0.0,1.0))
	obs.append(clampf(float(info.get("counter_risk",0.0)),0.0,1.0))
	obs.append(clampf(float(info.get("reflect_risk",0.0)),0.0,1.0))
	obs.append(clampf(float(info.get("defense_risk",0.0)),0.0,1.0))
	obs.append(clampf(float(info.get("control_risk",0.0)),0.0,1.0))
	obs.append(clampf(rel.length()/max_scan_distance,0.0,1.0))


func _add_declared_threat(info:Dictionary,default_source:Node) -> void:
	var shape:String = str(info.get("shape","circle"))
	var source:Node = _node_from_variant(info.get("source",default_source),default_source)
	var damage:float = float(info.get("damage",_source_damage(source)))
	var danger_in:float = maxf(float(info.get("danger_in",0.0)),0.0)
	var duration:float = maxf(float(info.get("danger_duration",0.1)),0.02)
	var blocking:bool = bool(info.get("blocking",false))
	var control:float = float(info.get("control",1.0 if bool(info.get("control_only",false)) else 0.0))
	var before_count:int = _threats.size()
	if shape == "segment":
		var a:Vector2 = info.get("start",Vector2.ZERO)
		var b:Vector2 = info.get("end",a)
		var radius:float = maxf(float(info.get("radius",4.0)),1.0)
		_add_segment_threat(source,a,b,radius,damage,danger_in,duration,blocking,control,str(info.get("kind","segment")))
	elif shape == "rect":
		var center:Vector2 = info.get("position",Vector2.ZERO)
		var half:Vector2 = info.get("half_extents",Vector2.ONE*8.0)
		_add_rect_threat(source,center,half,float(info.get("rotation",0.0)),Vector2(info.get("velocity",Vector2.ZERO)),damage,danger_in,duration,blocking,control,str(info.get("kind","rect")))
	else:
		_add_circle_threat(source,Vector2(info.get("position",Vector2.ZERO)),Vector2(info.get("velocity",Vector2.ZERO)),maxf(float(info.get("radius",4.0)),1.0),damage,danger_in,duration,blocking,control,str(info.get("kind","circle")))

	var explicit_direction_value:Variant = info.get("direction",Vector2.ZERO)
	if explicit_direction_value is Vector2 and (explicit_direction_value as Vector2).length_squared() > 0.000001:
		var explicit_direction:Vector2 = (explicit_direction_value as Vector2).normalized()
		for index:int in range(before_count,_threats.size()):
			_threats[index]["direction"] = explicit_direction


func _add_circle_threat(source:Node,position:Vector2,velocity:Vector2,radius:float,damage:float,danger_in:float,duration:float,blocking:bool,control:float,kind:String) -> void:
	if receiver.global_position.distance_to(position) > max_scan_distance + radius:
		return
	# 对移动伤害体统一计算相对运动的最近交会时间。这样新增角色只要发射标准 ball，
	# 不需要为角色名字写专门代码，AI 也能得到“多久后真正可能碰到我”。
	if velocity.length_squared() > 1.0:
		var rel_pos:Vector2 = position - receiver.global_position
		var rel_vel:Vector2 = velocity - _motion_velocity(receiver)
		if rel_vel.length_squared() > 1.0:
			var t_closest:float = clampf(-rel_pos.dot(rel_vel) / rel_vel.length_squared(),0.0,danger_time_normalizer)
			var closest:Vector2 = rel_pos + rel_vel * t_closest
			var receiver_radius:float = _collision_radius(receiver)
			if closest.length() <= radius + receiver_radius + 4.0:
				danger_in = maxf(danger_in,t_closest)
			else:
				# 仍保留在 observation/debug 中，但把“立即危险”压低；KEEP 可以是正确动作。
				danger_in = maxf(danger_in,danger_time_normalizer)
	var extent:=Vector2(radius,radius)
	_threats.append(_make_threat(source,"circle",position,velocity,extent,damage,danger_in,duration,blocking,control,kind,{"radius":radius}))


func _add_segment_threat(source:Node,a:Vector2,b:Vector2,radius:float,damage:float,danger_in:float,duration:float,blocking:bool,control:float,kind:String,velocity:Vector2 = Vector2.ZERO) -> void:
	var center:Vector2 = (a+b)*0.5
	if receiver.global_position.distance_to(center) > max_scan_distance + a.distance_to(b)*0.5:
		return
	var ext:=Vector2(a.distance_to(b)*0.5,radius)
	_threats.append(_make_threat(source,"segment",center,velocity,ext,damage,danger_in,duration,blocking,control,kind,{"start":a,"end":b,"radius":radius}))


func _add_rect_threat(source:Node,center:Vector2,half:Vector2,rotation:float,velocity:Vector2,damage:float,danger_in:float,duration:float,blocking:bool,control:float,kind:String) -> void:
	if receiver.global_position.distance_to(center) > max_scan_distance + half.length(): return
	_threats.append(_make_threat(source,"rect",center,velocity,half,damage,danger_in,duration,blocking,control,kind,{"half_extents":half,"rotation":rotation}))


func _make_threat(source:Node,shape:String,position:Vector2,velocity:Vector2,extent:Vector2,damage:float,danger_in:float,duration:float,blocking:bool,control:float,kind:String,extra:Dictionary) -> Dictionary:
	var distance:float = receiver.global_position.distance_to(position)
	var time_score:float = 1.0-clampf(danger_in/danger_time_normalizer,0.0,1.0)
	var damage_score:float = clampf(damage/damage_red_at,0.0,2.0)
	var distance_score:float = 1.0-clampf(distance/max_scan_distance,0.0,1.0)
	var severity:float = damage_score*1.4 + time_score*1.1 + distance_score*0.6 + control*0.35 + (0.25 if blocking else 0.0)
	var source_id:int = source.get_instance_id() if source != null and is_instance_valid(source) else 0
	var d:Dictionary = {
		"source":source,"source_id":source_id,"shape":shape,"position":position,"velocity":velocity,"extent":extent,
		"damage":maxf(damage,0.0),"danger_in":maxf(danger_in,0.0),"danger_duration":maxf(duration,0.02),
		"blocking":blocking,"control":clampf(control,0.0,1.0),"kind":kind,"severity":severity,
	}
	for key:Variant in extra.keys(): d[key]=extra[key]
	d["direction"] = _resolve_threat_direction(d,source)
	return d


func _add_shape_threat(source:Node,shape_node:CollisionShape2D,damage:float,danger_in:float,duration:float,blocking:bool,control:float,kind:String,velocity:Vector2 = Vector2.ZERO) -> void:
	if shape_node.shape == null: return
	var sh:Shape2D = shape_node.shape
	var scale_v:Vector2 = shape_node.global_scale.abs()
	if sh is CircleShape2D:
		_add_circle_threat(source,shape_node.global_position,velocity,(sh as CircleShape2D).radius*maxf(scale_v.x,scale_v.y),damage,danger_in,duration,blocking,control,kind)
	elif sh is RectangleShape2D:
		var half:Vector2 = (sh as RectangleShape2D).size*scale_v*0.5
		_add_rect_threat(source,shape_node.global_position,half,shape_node.global_rotation,velocity,damage,danger_in,duration,blocking,control,kind)
	elif sh is CapsuleShape2D:
		var cap:CapsuleShape2D = sh as CapsuleShape2D
		var radius:float = cap.radius*maxf(scale_v.x,scale_v.y)
		var half_len:float = maxf(cap.height*scale_v.y*0.5-radius,0.0)
		var axis:Vector2 = Vector2.UP.rotated(shape_node.global_rotation)
		_add_segment_threat(source,shape_node.global_position-axis*half_len,shape_node.global_position+axis*half_len,radius,damage,danger_in,duration,blocking,control,kind,velocity)
	else:
		_add_circle_threat(source,shape_node.global_position,velocity,_collision_radius_from_shape(shape_node),damage,danger_in,duration,blocking,control,kind)


func _first_collision_shape(root:Node) -> CollisionShape2D:
	for child:Node in root.get_children():
		if child is CollisionShape2D:
			return child as CollisionShape2D
		var nested:CollisionShape2D = _first_collision_shape(child)
		if nested != null: return nested
	return null


func _collision_radius(entity:ball) -> float:
	var shape:CollisionShape2D = entity.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape == null: shape = _first_collision_shape(entity)
	return _collision_radius_from_shape(shape) if shape != null else 12.0


func _collision_radius_from_shape(shape_node:CollisionShape2D) -> float:
	if shape_node == null or shape_node.shape == null: return 12.0
	var scale_v:Vector2 = shape_node.global_scale.abs()
	var sh:Shape2D = shape_node.shape
	if sh is CircleShape2D: return (sh as CircleShape2D).radius*maxf(scale_v.x,scale_v.y)
	if sh is RectangleShape2D: return ((sh as RectangleShape2D).size*scale_v).length()*0.5
	if sh is CapsuleShape2D: return maxf((sh as CapsuleShape2D).height*scale_v.y*0.5,(sh as CapsuleShape2D).radius*scale_v.x)
	return 12.0


func _motion_velocity(entity:ball) -> Vector2:
	if entity.velocity.length_squared() > 1.0: return entity.velocity
	if entity.direction.length_squared() > 0.0001: return entity.direction.normalized()*float(entity.Speed)
	return Vector2.ZERO


func _effective_damage(entity:ball) -> float:
	if entity == null: return 0.0
	# V107：调试/训练读取真实当前攻击值。这样动态倍率与继承主人攻击力的召唤物
	# 不会继续显示旧的裸 Damage。
	return maxf(entity.attack_damage(entity.current_hit_damage_multiplier()),0.0)


func _node_from_variant(value:Variant,fallback:Node = null) -> Node:
	# Object 被 free 后，Variant 仍可能保留一个悬空 Object 引用；不要先用 `is Node`。
	# typeof + is_instance_valid 能在真正解引用之前把这种值过滤掉。
	if typeof(value) == TYPE_OBJECT and is_instance_valid(value):
		var candidate:Node = value as Node
		if candidate != null:
			return candidate
	if fallback != null and is_instance_valid(fallback):
		return fallback
	return null


func _resolve_threat_direction(info:Dictionary,source:Node) -> Vector2:
	var explicit_value:Variant = info.get("direction",Vector2.ZERO)
	if explicit_value is Vector2:
		var explicit_direction:Vector2 = explicit_value as Vector2
		if explicit_direction.length_squared() > 0.000001:
			return explicit_direction.normalized()

	var velocity_value:Variant = info.get("velocity",Vector2.ZERO)
	if velocity_value is Vector2:
		var velocity_direction:Vector2 = velocity_value as Vector2
		if velocity_direction.length_squared() > 0.000001:
			return velocity_direction.normalized()

	var shape:String = str(info.get("shape","circle"))
	if shape == "segment":
		var segment_direction:Vector2 = Vector2(info.get("end",Vector2.ZERO)) - Vector2(info.get("start",Vector2.ZERO))
		if segment_direction.length_squared() > 0.000001:
			return segment_direction.normalized()
	elif shape == "rect":
		return Vector2.RIGHT.rotated(float(info.get("rotation",0.0))).normalized()

	if source != null and is_instance_valid(source):
		if _has_property(source,"direction"):
			var source_direction_value:Variant = source.get("direction")
			if source_direction_value is Vector2:
				var source_direction:Vector2 = source_direction_value as Vector2
				if source_direction.length_squared() > 0.000001:
					return source_direction.normalized()
		if source is Node2D:
			return Vector2.RIGHT.rotated((source as Node2D).global_rotation).normalized()
	return Vector2.ZERO


func _source_damage(source:Node) -> float:
	if source == null or not is_instance_valid(source):
		return 0.0
	if source is ball:
		return _effective_damage(source as ball)
	if _has_property(source,"damage_amount"):
		return maxf(float(source.get("damage_amount")),0.0)
	return 0.0


func _source_is_hostile(source:Node) -> bool:
	if source == null:
		return true
	if not is_instance_valid(source):
		return false
	if source is ball:
		return _is_hostile_ball(source as ball)
	var props:Dictionary = _property_names(source)
	if props.has("stone_owner"):
		var stone_owner:Node = _node_from_variant(source.get("stone_owner"))
		if stone_owner is ball:
			return _is_hostile_ball(stone_owner as ball)
	if props.has("wise_owner"):
		var wise_owner:Node = _node_from_variant(source.get("wise_owner"))
		if wise_owner is ball:
			return _is_hostile_ball(wise_owner as ball)
	if props.has("Team"):
		var team:String = str(source.get("Team"))
		return team.is_empty() or team != receiver.Team
	if props.has("Master_name") and not str(source.get("Master_name")).is_empty():
		var master:Node = get_tree().current_scene.get_node_or_null(str(source.get("Master_name")))
		if master is ball: return _is_hostile_ball(master as ball)
	return true


func _is_hostile_ball(entity:ball) -> bool:
	if entity == null or not is_instance_valid(entity) or receiver == null or not is_instance_valid(receiver):
		return false
	var team:String = entity.Team
	if entity.Master != null and is_instance_valid(entity.Master) and (team.is_empty() or team == "Ball"):
		team = entity.Master.Team
	return receiver.Team.is_empty() or team.is_empty() or receiver.Team != team


func _property_names(node:Object) -> Dictionary:
	var result:Dictionary = {}
	if node == null or not is_instance_valid(node):
		return result
	for info:Dictionary in node.get_property_list(): result[str(info.get("name",""))]=true
	return result


func _has_property(node:Object,name:String) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	for info:Dictionary in node.get_property_list():
		if str(info.get("name","")) == name: return true
	return false


func _draw() -> void:
	if not bool(Game.Game_Settings.get("Training_Debug_Mode",false)):
		return

	# 蓝色检测范围放最底层，其次绿色无伤害碰撞，最后白->红实际伤害。
	for info:Dictionary in _debug_threats:
		if _debug_region_role(info) == "detection":
			_debug_draw_region(info)
	for info:Dictionary in _debug_threats:
		if _debug_region_role(info) == "collision":
			_debug_draw_region(info)
	for info:Dictionary in _debug_threats:
		if _debug_region_role(info) == "damage":
			_debug_draw_region(info)


func _debug_region_role(info:Dictionary) -> String:
	var explicit:String = str(info.get("debug_role",""))
	if explicit == "collision" or explicit == "damage" or explicit == "detection":
		return explicit
	return "damage" if float(info.get("damage",0.0)) > 0.0 else "collision"


func _debug_draw_region(info:Dictionary) -> void:
	var damage:float = maxf(float(info.get("damage",0.0)),0.0)
	var role:String = _debug_region_role(info)

	var solid:Color
	var fill_alpha:float
	if role == "detection":
		# 真正用于“是否起手/锁定/触发”的检测区域：低透明度蓝色。
		solid = Color(0.12,0.48,1.0,debug_detection_outline_alpha)
		fill_alpha = debug_detection_fill_alpha
	elif role == "collision":
		# 无伤害、但实际参与物理碰撞/检测：绿色。
		solid = Color(0.16,1.0,0.26,1.0)
		fill_alpha = debug_collision_fill_alpha
	else:
		# 真正伤害区域：只按“这一区域一次实际伤害量”从白渐变到红。
		var t:float = clampf(damage/maxf(damage_red_at,1.0),0.0,1.0)
		solid = Color.WHITE.lerp(Color(1.0,0.035,0.035,1.0),t)
		fill_alpha = debug_fill_alpha

	var fill:Color = Color(solid.r,solid.g,solid.b,fill_alpha)
	var shape:String = str(info.get("shape","circle"))

	if shape == "polygon":
		var global_points:PackedVector2Array = info.get("points",PackedVector2Array())
		if global_points.size() < 3:
			return
		var local_points:PackedVector2Array = PackedVector2Array()
		for point:Vector2 in global_points:
			local_points.append(to_local(point))
		draw_colored_polygon(local_points,fill)
		var closed:PackedVector2Array = local_points.duplicate()
		closed.append(local_points[0])
		draw_polyline(closed,solid,debug_outline_width,true)

	elif shape == "segment":
		var a:Vector2 = to_local(Vector2(info.get("start",Vector2.ZERO)))
		var b:Vector2 = to_local(Vector2(info.get("end",Vector2.ZERO)))
		var radius:float = maxf(float(info.get("radius",1.0)),1.0)
		draw_line(a,b,fill,maxf(radius*2.0,1.0),false)
		draw_line(a,b,solid,debug_outline_width,true)
		draw_circle(a,radius,fill,true)
		draw_circle(b,radius,fill,true)
		draw_arc(a,radius,0.0,TAU,20,solid,debug_outline_width,true)
		draw_arc(b,radius,0.0,TAU,20,solid,debug_outline_width,true)

	elif shape == "rect":
		var center:Vector2 = to_local(Vector2(info.get("position",Vector2.ZERO)))
		var half:Vector2 = info.get("half_extents",Vector2.ONE*8.0)
		draw_set_transform(center,float(info.get("rotation",0.0)),Vector2.ONE)
		draw_rect(Rect2(-half,half*2.0),fill,true)
		draw_rect(Rect2(-half,half*2.0),solid,false,debug_outline_width)
		draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)

	else:
		var center:Vector2 = to_local(Vector2(info.get("position",Vector2.ZERO)))
		var radius:float = float(info.get("radius",Vector2(info.get("extent",Vector2.ONE*4.0)).x))
		draw_circle(center,radius,fill,true)
		draw_circle(center,radius,solid,false,debug_outline_width)

	# V4.7：伤害/检测提示框中心增加方向箭头。绿色纯碰撞框不画箭头，避免墙体/地形满屏箭头。
	if role != "collision":
		_debug_draw_direction(info,Color(solid.r,solid.g,solid.b,0.96))


func _debug_draw_direction(info:Dictionary,color_value:Color) -> void:
	var direction_value:Variant = info.get("direction",Vector2.ZERO)
	if not direction_value is Vector2:
		return
	var world_direction:Vector2 = direction_value as Vector2
	if world_direction.length_squared() <= 0.000001:
		return
	world_direction = world_direction.normalized()

	var world_center:Vector2 = Vector2(info.get("position",Vector2.ZERO))
	var local_center:Vector2 = to_local(world_center)
	var local_tip_reference:Vector2 = to_local(world_center + world_direction)
	var local_direction:Vector2 = local_tip_reference - local_center
	if local_direction.length_squared() <= 0.000001:
		return
	local_direction = local_direction.normalized()

	var length:float = maxf(debug_direction_length,8.0)
	var start:Vector2 = local_center - local_direction * length * 0.18
	var tip:Vector2 = local_center + local_direction * length * 0.82
	var width:float = maxf(debug_direction_width,0.5)
	draw_line(start,tip,color_value,width,true)

	var head_size:float = maxf(debug_direction_head_size,3.0)
	var side:Vector2 = local_direction.orthogonal()
	var head_base:Vector2 = tip - local_direction * head_size
	var head:PackedVector2Array = PackedVector2Array([
		tip,
		head_base + side * head_size * 0.55,
		head_base - side * head_size * 0.55,
	])
	draw_colored_polygon(head,color_value)
