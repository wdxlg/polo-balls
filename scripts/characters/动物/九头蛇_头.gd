extends ball

const LOCAL_SFX = preload("res://scripts/audio/local_positional_sfx.gd")

@export_category("九头蛇头 - 活动范围")
@export_range(40.0,500.0,1.0) var tether_radius:float = 145.0
@export_range(40.0,700.0,1.0) var attack_search_radius:float = 180.0
@export_range(20.0,300.0,1.0) var rest_radius:float = 64.0
@export var rest_angle:float = -PI * 0.5
@export_range(0.0,45.0,1.0) var idle_sway_degrees:float = 13.0
@export_range(0.1,8.0,0.1) var idle_sway_speed:float = 1.7
@export_range(0.0,1.0,0.05) var tether_soft_zone:float = 0.88

@export_category("九头蛇头 - 稳定锁敌")
# 当前目标只要仍然活着并处于释放范围内，就持续追踪，避免每个物理帧来回换目标。
@export_range(0.05,1.0,0.01) var target_scan_interval:float = 0.12
@export_range(1.0,2.0,0.01) var target_release_radius_multiplier:float = 1.15
@export_range(0.1,1.0,0.01) var target_switch_distance_ratio:float = 0.62
@export_range(0.0,3.0,0.05) var target_lock_min_time:float = 0.55
@export_range(0.0,0.5,0.01) var target_lead_seconds:float = 0.08

@export_category("九头蛇头 - 攻击运动")
@export_range(0.0,1.0,0.01) var recoil_time:float = 0.18
@export_range(0.0,300.0,1.0) var target_stop_distance:float = 10.0

var head_serial:int = 0
var _idle_phase:float = 0.0
var _recoil_left:float = 0.0
var _death_reported:bool = false
var _suppress_split:bool = false

var _locked_target_id:int = 0
var _target_scan_left:float = 0.0
var _target_lock_elapsed:float = 0.0

# 断头重生阶段：头从身体中心沿脖子方向真正“长出来”。
var _emerging:bool = false
var _emerge_elapsed:float = 0.0
var _emerge_duration:float = 0.8
var _emerge_angle:float = -PI * 0.5
var _normal_graphics_scale:Vector2 = Vector2.ONE
var _base_collision_layer:int = 0
var _base_collision_mask:int = 0
var _base_hitbox_monitoring:bool = true
var _base_hurtbox_monitorable:bool = true


func _ready() -> void:
	# 头通过身体碰撞直接攻击；没有独立 Attack/Skill 状态。
	manual_controllable_subentity = true
	Has_Collision_Damage = true
	Can_Attack = false
	Can_Skill = false
	super._ready()

	_idle_phase = fmod(float(get_instance_id()) * 0.013 + float(head_serial) * 0.91,TAU)
	_base_collision_layer = collision_layer
	_base_collision_mask = collision_mask
	if self_hitbox != null:
		_base_hitbox_monitoring = self_hitbox.monitoring
	if self_hurtbox != null:
		_base_hurtbox_monitorable = self_hurtbox.monitorable
	var graphics := get_node_or_null("Graphics") as Node2D
	if graphics != null:
		_normal_graphics_scale = graphics.scale
	call_deferred("_register_with_body_retry")
func _hydra_body() -> ball:
	if Master != null and is_instance_valid(Master):
		return Master
	if Master_name.is_empty() or not is_inside_tree():
		return null
	var world := get_tree().current_scene
	if world == null:
		return null
	var resolved = world.get_node_or_null(NodePath(Master_name))
	if resolved is ball:
		Master = resolved as ball
		Team = Master.Team
		return Master
	return null




# 头部是九头蛇本体的攻击方式之一：最终伤害始终读取主人的整体攻击力。
func attack_damage(multiplier:float = 1.0) -> float:
	var body:ball = _hydra_body()
	if body != null and is_instance_valid(body):
		return body.attack_damage(multiplier)
	return super.attack_damage(multiplier)


func current_hit_damage_multiplier() -> float:
	var body:ball = _hydra_body()
	if body != null and is_instance_valid(body):
		# V431 性能：每次命中都会调用；属性存在性改用按脚本缓存的属性名集合。
		if PROPERTY_INDEX.has_property(body,"head_damage_multiplier"):
			return maxf(float(body.get("head_damage_multiplier")),0.0)
	return 1.0


const PROPERTY_INDEX = preload("res://classes/property_index.gd")


func _register_with_body_retry() -> void:
	for _attempt in range(30):
		if not is_instance_valid(self) or not is_inside_tree():
			return
		var body:ball = _hydra_body()
		if body != null and is_instance_valid(body):
			if body.has_method("_register_hydra_head"):
				body.call("_register_hydra_head",self)
			return
		await get_tree().process_frame

	# Authority 上出现孤儿头时直接清理；远端则等待 MultiplayerSpawner 同步删除。
	if is_multiplayer_authority() and is_instance_valid(self):
		Game.free_node(self)


# 只由九头蛇身体在“断头重生”时调用。
func begin_regrow_emergence(angle:float,duration:float) -> void:
	var body:ball = _hydra_body()
	if body == null or not is_instance_valid(body):
		return

	_emerging = true
	_emerge_elapsed = 0.0
	_emerge_duration = maxf(duration,0.08)
	_emerge_angle = angle
	_locked_target_id = 0
	_target_scan_left = 0.0
	_target_lock_elapsed = 0.0
	direction = Vector2.ZERO
	global_position = body.global_position

	# 长出来之前不参与实体碰撞/攻击/受击，避免出生在身体中心时被物理系统强行挤飞。
	collision_layer = 0
	collision_mask = 0
	if self_hitbox != null:
		self_hitbox.monitoring = false
	if self_hurtbox != null:
		self_hurtbox.monitorable = false

	var graphics := get_node_or_null("Graphics") as Node2D
	if graphics != null:
		graphics.scale = _normal_graphics_scale * 0.38
		graphics.modulate.a = 0.72


func _update_emergence(body:ball,delta:float) -> void:
	_emerge_elapsed += delta
	var t:float = clampf(_emerge_elapsed / maxf(_emerge_duration,0.08),0.0,1.0)
	# cubic ease-out：刚长出来明显，接近正常位置时自然减速。
	var eased:float = 1.0 - pow(1.0 - t,3.0)
	var outward:Vector2 = Vector2.from_angle(_emerge_angle)
	global_position = body.global_position + outward * rest_radius * eased
	direction = outward

	var graphics := get_node_or_null("Graphics") as Node2D
	if graphics != null:
		graphics.scale = _normal_graphics_scale * lerpf(0.38,1.0,eased)
		graphics.modulate.a = lerpf(0.72,1.0,eased)

	if t < 1.0:
		return

	_emerging = false
	collision_layer = _base_collision_layer
	collision_mask = _base_collision_mask
	if self_hitbox != null:
		self_hitbox.monitoring = _base_hitbox_monitoring
	if self_hurtbox != null:
		self_hurtbox.monitorable = _base_hurtbox_monitorable
	if graphics != null:
		graphics.scale = _normal_graphics_scale
		graphics.modulate.a = 1.0
	_target_scan_left = 0.0


func tick_physics(state:State,delta:float) -> void:
	# 远端由 MultiplayerSynchronizer 接收 authority 的位置；不在本机做 AI 决策。
	if not is_multiplayer_authority():
		super.tick_physics(state,delta)
		return

	var body:ball = _hydra_body()
	if body == null or not is_instance_valid(body) or body.health <= 0:
		die_with_body()
		return

	if health <= 0 or state == State.Die:
		super.tick_physics(state,delta)
		return

	if _emerging:
		_update_emergence(body,delta)
		return

	_recoil_left = maxf(_recoil_left - delta,0.0)
	_target_lock_elapsed += delta
	_target_scan_left -= delta
	if _recoil_left <= 0.0 and not is_player_controlled():
		_update_attack_direction(body,delta)

	super.tick_physics(state,delta)
	_enforce_tether(body)


func _update_attack_direction(body:ball,_delta:float) -> void:
	var target:ball = _current_attack_target(body)
	var desired_point:Vector2

	if target != null:
		desired_point = combat_target_position(target)
		# 对移动目标做很短的前置量，减少蛇头总是追在敌人身后的感觉。
		desired_point += combat_target_velocity(target) * target_lead_seconds
	else:
		var time_seconds:float = float(Time.get_ticks_msec()) * 0.001
		var sway:float = sin(time_seconds * idle_sway_speed + _idle_phase) * deg_to_rad(idle_sway_degrees)
		desired_point = body.global_position + Vector2.from_angle(rest_angle + sway) * rest_radius

	var to_desired:Vector2 = desired_point - global_position
	if target != null and to_desired.length() <= target_stop_distance:
		direction = Vector2.ZERO
		return
	if to_desired.length_squared() <= 0.0001:
		return

	var desired_dir:Vector2 = to_desired.normalized()
	var body_offset:Vector2 = global_position - body.global_position
	var body_distance:float = body_offset.length()
	if body_distance > 0.001:
		var radial:Vector2 = body_offset / body_distance
		var soft_limit:float = maxf(tether_radius * clampf(tether_soft_zone,0.5,0.98),20.0)
		# 快到脖子极限时，不允许继续径向向外冲；加入回拉，沿圆弧滑动而不是卡死在边界。
		if body_distance >= soft_limit:
			var outward_amount:float = desired_dir.dot(radial)
			if outward_amount > 0.0:
				desired_dir = desired_dir - radial * outward_amount
				desired_dir -= radial * 0.28
				if desired_dir.length_squared() > 0.0001:
					desired_dir = desired_dir.normalized()

	direction = desired_dir


func _current_attack_target(body:ball) -> ball:
	# 如果玩家/角色逻辑显式指定了目标，优先保持这个目标。
	var forced:ball = _forced_target(body)
	if forced != null:
		_set_locked_target(forced)
		return forced

	var release_radius:float = attack_search_radius * maxf(target_release_radius_multiplier,1.0)
	var locked:ball = _get_locked_target()
	var lock_is_valid:bool = _is_valid_target(locked,body,release_radius)

	# 锁定至少保持一小段时间，而且扫描不是每个 physics tick 都做。
	if lock_is_valid and (_target_lock_elapsed < target_lock_min_time or _target_scan_left > 0.0):
		return locked

	_target_scan_left = maxf(target_scan_interval,0.05)
	var candidate:ball = _find_best_target(body)

	if lock_is_valid:
		if candidate == null or candidate == locked:
			return locked
		# 只有新目标明显更近时才允许换锁，形成滞回，避免两个敌人在相近距离时反复横跳。
		var current_distance_sq:float = global_position.distance_squared_to(locked.global_position)
		var candidate_distance_sq:float = global_position.distance_squared_to(candidate.global_position)
		var switch_ratio:float = clampf(target_switch_distance_ratio,0.1,1.0)
		if _target_lock_elapsed >= target_lock_min_time and candidate_distance_sq < current_distance_sq * switch_ratio * switch_ratio:
			_set_locked_target(candidate)
			return candidate
		return locked

	if candidate != null:
		_set_locked_target(candidate)
		return candidate

	_clear_locked_target()
	return null


func _forced_target(body:ball) -> ball:
	# Target_Enemy 由其他角色逻辑持有，目标可能已经在上一帧被删除。
	# 必须先检查实例有效性，再做类型判断/转换。
	var raw_target:Variant = body.Target_Enemy
	if not is_instance_valid(raw_target):
		return null
	if raw_target is ball:
		var body_target:ball = raw_target as ball
		if _is_valid_target(body_target,body,attack_search_radius):
			return body_target
	return null


func _get_locked_target() -> ball:
	# 不长期保存对象指针，而保存 Object instance ID。
	# 目标死亡并被 free 后，ID 会失效，不会留下“previously freed”的强类型悬空引用。
	if _locked_target_id == 0:
		return null
	if not is_instance_id_valid(_locked_target_id):
		_locked_target_id = 0
		return null
	var resolved:Variant = instance_from_id(_locked_target_id)
	if not is_instance_valid(resolved) or not resolved is ball:
		_locked_target_id = 0
		return null
	return resolved as ball


func _clear_locked_target() -> void:
	_locked_target_id = 0
	_target_lock_elapsed = 0.0


func _set_locked_target(target:ball) -> void:
	if target == null or not is_instance_valid(target):
		_clear_locked_target()
		return
	var new_id:int = target.get_instance_id()
	if new_id == _locked_target_id:
		return
	_locked_target_id = new_id
	_target_lock_elapsed = 0.0
	_target_scan_left = maxf(target_scan_interval,0.05)


func _find_best_target(body:ball) -> ball:
	var best:ball = null
	var best_score:float = INF
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not is_instance_valid(node) or not node is ball:
			continue
		var candidate:ball = node as ball
		if not _is_valid_target(candidate,body,attack_search_radius):
			continue

		# 主评分看头到敌人的距离，少量加入身体距离，既容易咬到人又不会选到脖子另一侧的奇怪目标。
		var head_distance_sq:float = global_position.distance_squared_to(candidate.global_position)
		var body_distance_sq:float = body.global_position.distance_squared_to(candidate.global_position)
		var score:float = head_distance_sq + body_distance_sq * 0.18
		if score < best_score:
			best_score = score
			best = candidate
	return best


func _is_valid_target(raw_target:Variant,body:ball,radius:float) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(self,raw_target): return false # 皓宸复制品及其产物不把己方选为目标
	# 这里故意使用 Variant：如果上一帧目标刚被 free，强类型参数会在进入函数体前
	# 就因为“previously freed”无法转换成 ball 而抛错，导致 is_instance_valid 根本执行不到。
	if not is_instance_valid(raw_target):
		return false
	if not raw_target is ball:
		return false
	var target:ball = raw_target as ball
	if target == self or target == body or target.health <= 0:
		return false
	# 与 world.gd 的常规目标规则保持一致：纯投射物/Creature 不作为锁敌目标；有血 Shooter 可以。
	if target.Type == Ball_Type.Shooter or target.Type == Ball_Type.Creature:
		return false
	if is_instance_valid(target.Master) and target.Master == body:
		return false
	if Team != "" and target.Team != "" and Team == target.Team:
		return false
	if target.state_machine != null and is_instance_valid(target.state_machine) and target.state_machine.current_state == State.Die:
		return false
	var allowed_radius:float = maxf(radius,1.0)
	# 搜敌范围始终以九头蛇身体为圆心；头在外侧移动不会让锁敌圈跟着乱漂。
	if body.global_position.distance_squared_to(target.global_position) > allowed_radius * allowed_radius:
		return false
	return true


func _enforce_tether(body:ball) -> void:
	var offset:Vector2 = global_position - body.global_position
	var distance:float = offset.length()
	var max_radius:float = maxf(tether_radius,40.0)
	if distance <= max_radius or distance <= 0.001:
		return

	var legal_position:Vector2 = body.global_position + offset / distance * max_radius
	var correction:Vector2 = legal_position - global_position
	if correction.length_squared() > 0.0001:
		# 这里只修正越过脖子极限的少量距离，仍通过 CharacterBody2D 的碰撞移动完成。
		move_and_collide(correction)


func when_collide(speed:float,collision:KinematicCollision2D) -> void:
	super.when_collide(speed,collision)
	if collision == null:
		return
	var other = collision.get_collider()
	if other is ball:
		var target:ball = other as ball
		if target != self and target != _hydra_body() and target.health > 0:
			if Team == "" or target.Team == "" or Team != target.Team:
				# 命中后短暂保留父类算出的反弹方向，形成“伸头咬一下再缩回”的感觉。
				_recoil_left = maxf(recoil_time,0.0)
				if is_multiplayer_authority():
					_play_local_sfx_everywhere("snake_bite",target.global_position,-10.0,randf_range(0.92,1.08),520.0)


func _play_local_sfx_everywhere(key:String,position_value:Vector2,volume_db:float,pitch:float,max_distance:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_local_sfx.rpc(key,position_value,volume_db,pitch,max_distance)
	else:
		_rpc_play_local_sfx(key,position_value,volume_db,pitch,max_distance)


@rpc("authority","call_local","unreliable")
func _rpc_play_local_sfx(key:String,position_value:Vector2,volume_db:float,pitch:float,max_distance:float) -> void:
	LOCAL_SFX.play(self,key,position_value,volume_db,pitch,max_distance)


func Die() -> void:
	if _death_reported:
		return
	_death_reported = true
	_locked_target_id = 0
	if is_multiplayer_authority():
		_play_local_sfx_everywhere("snake_die",global_position,-10.0,randf_range(0.94,1.06),560.0)
	super()

	if is_multiplayer_authority() and not _suppress_split:
		var body:ball = _hydra_body()
		if body != null and is_instance_valid(body) and body.has_method("_on_hydra_head_died"):
			body.call("_on_hydra_head_died",self,global_position)

	await get_tree().create_timer(0.32).timeout
	if is_instance_valid(self):
		Game.free_node(self)


func die_with_body() -> void:
	if _suppress_split:
		return
	_suppress_split = true
	_death_reported = true
	_locked_target_id = 0
	if is_multiplayer_authority() and is_instance_valid(self):
		Game.free_node(self)


func _exit_tree() -> void:
	if Master != null and is_instance_valid(Master) and Master.has_method("_unregister_hydra_head"):
		Master.call("_unregister_hydra_head",self)
