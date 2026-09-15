extends ball

const BOTTLE_SCENE := preload("res://scenes/shooter/酒瓶.tscn")
const BOTTLE_WALL_BREAK_AUDIO:AudioStream = preload("res://audio/characters/醉汉/酒瓶碎裂.mp3")

enum DrunkVisualState {
	NORMAL,
	WINDUP,
	THROW,
	SMASH,
}

# ========================================================
# 醉汉 V110（V93 机制 + V110 躲弹速度上限修复）
# - 保留不稳定醉步，并加入有限度的来弹闪避：只对真正朝自己飞来的投射物做短暂侧移，
#   每个威胁只进行一次概率判定，因此不会变成极速者式的稳定完美闪避。
# - 每次攻击先等待一个较短、随机的攻击冷却；进入攻击后先显示前摇图，
#   前摇时间在 0.05~1.0 秒内随机，结束后才随机决定丢瓶子或砸人。
# - 有敌人时两种攻击都先瞄准当前敌人，再加入小幅随机角度偏差；没有敌人也照常攻击，方向随机。
# - 丢瓶子保持 28 伤害；砸人使用场景中可直接编辑的真实 SmashArea/CollisionShape2D，对重叠敌人造成 56 伤害。
# - SmashArea 只在运行时旋转父节点，CollisionShape2D 的 authored 形状/大小/相对位置永远不被代码覆盖。
# ========================================================

@export_category("醉步")
@export_range(1.0,1000.0,1.0) var chaos_speed_min:float = 45.0
@export_range(1.0,1500.0,1.0) var chaos_speed_max:float = 230.0
@export_range(10.0,3000.0,10.0) var chaos_speed_response:float = 520.0
@export_range(0.03,3.0,0.01) var chaos_turn_interval_min:float = 0.12
@export_range(0.03,3.0,0.01) var chaos_turn_interval_max:float = 0.55
@export_range(0.0,180.0,1.0) var chaos_turn_degrees:float = 105.0
@export_range(0.0,1.0,0.01) var full_random_direction_chance:float = 0.28

@export_category("有限躲弹")
@export var dodge_projectiles:bool = true
@export_range(40.0,600.0,5.0) var dodge_scan_radius:float = 190.0
@export_range(0.05,1.0,0.01) var dodge_prediction_horizon:float = 0.48
@export_range(6.0,100.0,1.0) var dodge_danger_clearance:float = 34.0
@export_range(0.0,1.0,0.01) var dodge_trigger_chance:float = 0.55
@export_range(0.02,0.30,0.01) var dodge_scan_interval:float = 0.07
@export_range(0.05,0.60,0.01) var dodge_time_min:float = 0.14
@export_range(0.05,0.80,0.01) var dodge_time_max:float = 0.26
@export_range(0.0,1.0,0.01) var dodge_direction_weight:float = 0.72
@export_range(1.0,3.0,0.05) var dodge_speed_multiplier:float = 1.15
@export_range(0.0,600.0,5.0) var dodge_min_speed:float = 115.0
@export_range(0.1,2.0,0.05) var dodge_same_threat_lock:float = 0.65

@export_category("随机攻击")
@export_range(0.05,3.0,0.01) var attack_cooldown_min:float = 0.55
@export_range(0.05,3.0,0.01) var attack_cooldown_max:float = 0.85
@export_range(0.05,1.0,0.01) var attack_windup_min:float = 0.05
@export_range(0.05,1.0,0.01) var attack_windup_max:float = 1.0
@export_range(0.0,1.0,0.01) var attack_throw_chance:float = 0.50
@export_range(0.0,45.0,0.5) var attack_spread_degrees:float = 14.0
@export_range(0.02,0.50,0.01) var throw_pose_hold:float = 0.12
@export_range(0.02,0.50,0.01) var smash_pose_hold:float = 0.16

@export_category("酒瓶")
@export_range(10.0,1500.0,10.0) var bottle_speed:float = 360.0
@export_range(0.0,200.0,1.0) var bottle_spawn_offset:float = 35.0
@export var throw_audio:String = "KnifeThrow1"

@export_category("砸人")
@export_range(0.0,10.0,0.05) var smash_damage_multiplier:float = 2.0
@export_range(-40.0,12.0,0.5) var smash_swing_volume_db:float = -2.0
@export_range(0.5,2.0,0.01) var smash_swing_pitch_scale:float = 1.0
@export_range(0.0,0.25,0.01) var smash_swing_random_pitch:float = 0.05
@export_range(100.0,3000.0,10.0) var smash_swing_max_distance:float = 1100.0

@export_category("动作图片")
@export var normal_texture:Texture2D
@export var windup_texture:Texture2D
@export var throw_texture:Texture2D
@export var smash_texture:Texture2D

@onready var _smash_area:Area2D = get_node_or_null("SmashArea") as Area2D
@onready var _smash_shape:CollisionShape2D = get_node_or_null("SmashArea/CollisionShape2D") as CollisionShape2D

var _chaos_turn_left:float = 0.0
var _current_chaos_speed:float = 0.0
var _target_chaos_speed:float = 0.0
var _dodge_scan_left:float = 0.0
var _dodge_time_left:float = 0.0
var _dodge_direction:Vector2 = Vector2.ZERO
var _dodge_decision_locks:Dictionary = {}


func _ready() -> void:
	super._ready()
	if direction.length_squared() <= 0.000001:
		direction = Vector2.from_angle(randf_range(0.0,TAU))
	_target_chaos_speed = _roll_chaos_speed()
	_current_chaos_speed = _target_chaos_speed
	_roll_next_turn_time()
	_roll_next_attack_cooldown()
	_setup_smash_area()
	_set_visual_state_local(DrunkVisualState.NORMAL)


func _setup_smash_area() -> void:
	if _smash_area == null:
		return
	# SmashArea 自己固定在人物原点并旋转；CollisionShape2D 保留场景里 authored 的
	# shape / position / rotation / scale。这样编辑器里调好的碰撞箱不会被运行时代码覆盖。
	_smash_area.top_level = true
	_smash_area.global_scale = Vector2.ONE
	_smash_area.global_rotation = 0.0
	_smash_area.global_position = global_position
	_smash_area.monitoring = true
	_smash_area.monitorable = false


func tick_physics(state:State,delta:float) -> void:
	if not is_multiplayer_authority():
		return

	if dizziness:
		_dodge_time_left = 0.0
		_dodge_direction = Vector2.ZERO
		super.tick_physics(state,delta)
		return

	_chaos_turn_left -= delta
	if _chaos_turn_left <= 0.0:
		_change_chaos_motion()

	_current_chaos_speed = move_toward(
		_current_chaos_speed,
		_target_chaos_speed,
		maxf(chaos_speed_response,1.0) * delta
	)

	# V110：躲弹只计算“本帧有效速度”，绝不把倍率写回 _current_chaos_speed。
	# V109 以前这里每个 physics tick 都执行 current *= dodge_speed_multiplier，
	# 一次 0.2 秒左右的闪避会连续乘很多帧，导致速度指数增长且没有上限。
	_update_projectile_dodge(delta)
	var movement_speed:float = _current_chaos_speed
	if _dodge_time_left > 0.0 and _dodge_direction.length_squared() > 0.000001:
		var base_dir:Vector2 = direction.normalized() if direction.length_squared() > 0.000001 else _dodge_direction
		direction = base_dir.lerp(_dodge_direction,clampf(dodge_direction_weight,0.0,1.0)).normalized()
		var dodge_multiplier:float = maxf(dodge_speed_multiplier,1.0)
		var chaos_high:float = maxf(chaos_speed_min,chaos_speed_max)
		var dodge_speed_cap:float = maxf(chaos_high * dodge_multiplier,dodge_min_speed)
		movement_speed = minf(
			maxf(_current_chaos_speed * dodge_multiplier,dodge_min_speed),
			dodge_speed_cap
		)

	# World 会先恢复 default_properties、再计算 Buff。
	# 这里把 Buff 对 Speed 的倍率继续乘到“醉步/躲弹速度”上，避免醉汉无视速度 Buff。
	# 上面的 dodge_speed_cap 只限制躲弹机制自身；正常 Speed Buff 仍可按规则同比放大最终速度。
	var nominal_speed:float = maxf(float(default_properties.get("Speed",Speed)),0.001)
	var buff_speed_ratio:float = maxf(Speed / nominal_speed,0.0)
	Speed = maxf(movement_speed * buff_speed_ratio,0.0)

	super.tick_physics(state,delta)


func _change_chaos_motion() -> void:
	if direction.length_squared() <= 0.000001 or randf() < full_random_direction_chance:
		direction = Vector2.from_angle(randf_range(0.0,TAU))
	else:
		direction = direction.normalized().rotated(
			deg_to_rad(randf_range(-chaos_turn_degrees,chaos_turn_degrees))
		)
	_target_chaos_speed = _roll_chaos_speed()
	_roll_next_turn_time()


func _roll_chaos_speed() -> float:
	var low:float = minf(chaos_speed_min,chaos_speed_max)
	var high:float = maxf(chaos_speed_min,chaos_speed_max)
	return randf_range(low,high)


func _roll_next_turn_time() -> void:
	var low:float = minf(chaos_turn_interval_min,chaos_turn_interval_max)
	var high:float = maxf(chaos_turn_interval_min,chaos_turn_interval_max)
	_chaos_turn_left = randf_range(maxf(low,0.03),maxf(high,0.03))


func _roll_next_attack_cooldown() -> void:
	var low:float = minf(attack_cooldown_min,attack_cooldown_max)
	var high:float = maxf(attack_cooldown_min,attack_cooldown_max)
	Attack_Cooling = randf_range(maxf(low,0.05),maxf(high,0.05))


func _update_projectile_dodge(delta:float) -> void:
	_update_dodge_decision_locks(delta)
	_dodge_time_left = maxf(_dodge_time_left - delta,0.0)
	if _dodge_time_left <= 0.0:
		_dodge_direction = Vector2.ZERO

	if not dodge_projectiles:
		return
	_dodge_scan_left = maxf(_dodge_scan_left - delta,0.0)
	if _dodge_scan_left > 0.0:
		return
	_dodge_scan_left = maxf(dodge_scan_interval,0.02)

	var threat:Dictionary = _find_projectile_threat()
	if threat.is_empty():
		return
	var source_id:int = int(threat.get("id",0))
	if source_id <= 0 or _dodge_decision_locks.has(source_id):
		return
	_dodge_decision_locks[source_id] = maxf(dodge_same_threat_lock,0.1)
	if randf() > clampf(dodge_trigger_chance,0.0,1.0):
		return

	var projectile_velocity:Vector2 = threat.get("velocity",Vector2.ZERO)
	if projectile_velocity.length_squared() <= 0.000001:
		return
	var perpendicular := Vector2(-projectile_velocity.y,projectile_velocity.x).normalized()
	# 醉汉不是精准闪避者：左右侧随机选一边，再靠方向权重只部分接管醉步。
	if randf() < 0.5:
		perpendicular = -perpendicular
	_dodge_direction = perpendicular
	var low:float = minf(dodge_time_min,dodge_time_max)
	var high:float = maxf(dodge_time_min,dodge_time_max)
	_dodge_time_left = randf_range(maxf(low,0.05),maxf(high,0.05))


func _update_dodge_decision_locks(delta:float) -> void:
	if _dodge_decision_locks.is_empty():
		return
	var expired:Array[int] = []
	for key:Variant in _dodge_decision_locks.keys():
		var source_id:int = int(key)
		var left:float = float(_dodge_decision_locks.get(key,0.0)) - delta
		if left <= 0.0:
			expired.append(source_id)
		else:
			_dodge_decision_locks[key] = left
	for source_id:int in expired:
		_dodge_decision_locks.erase(source_id)


func _find_projectile_threat() -> Dictionary:
	var candidates:Dictionary = {}
	for group_name:String in ["Ball","BattleTransient","ArmsDealerProjectile","HunterPellet","MagnetElectricBall"]:
		for node:Node in get_tree().get_nodes_in_group(group_name):
			if node != null and is_instance_valid(node) and node != self:
				candidates[node.get_instance_id()] = node

	var best:Dictionary = {}
	var best_score:float = INF
	var scan_sq:float = dodge_scan_radius * dodge_scan_radius
	var own_velocity:Vector2 = velocity

	for key:Variant in candidates:
		var node:Node = candidates[key]
		if not _is_projectile_candidate(node) or not node is Node2D:
			continue
		var projectile:Node2D = node as Node2D
		if global_position.distance_squared_to(projectile.global_position) > scan_sq:
			continue
		if not _is_hostile_projectile_node(node):
			continue
		var projectile_velocity:Vector2 = _projectile_velocity(node)
		if projectile_velocity.length_squared() <= 1.0:
			continue

		var relative_position:Vector2 = projectile.global_position - global_position
		var relative_velocity:Vector2 = projectile_velocity - own_velocity
		var rv_sq:float = relative_velocity.length_squared()
		if rv_sq <= 1.0 or relative_position.dot(relative_velocity) >= 0.0:
			continue
		var t_closest:float = clampf(
			-relative_position.dot(relative_velocity) / rv_sq,
			0.0,
			maxf(dodge_prediction_horizon,0.05)
		)
		var closest:Vector2 = relative_position + relative_velocity * t_closest
		if closest.length() > maxf(dodge_danger_clearance,1.0):
			continue
		var score:float = t_closest * 1000.0 + closest.length()
		if score < best_score:
			best_score = score
			best = {
				"id": node.get_instance_id(),
				"velocity": projectile_velocity,
				"time": t_closest,
				"clearance": closest.length(),
			}
	return best


func _is_projectile_candidate(node:Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if node is ball:
		var projectile_ball:ball = node as ball
		return projectile_ball.Type == Ball_Type.Shooter or projectile_ball.Type == Ball_Type.Shooter_with_Health
	if node.is_in_group("ArmsDealerProjectile") or node.is_in_group("HunterPellet") or node.is_in_group("MagnetElectricBall"):
		return true
	if node.is_in_group("BattleTransient"):
		return _projectile_velocity(node).length_squared() > 1.0
	return false


func _is_hostile_projectile_node(node:Node) -> bool:
	var projectile_team:String = _projectile_team(node)
	if projectile_team.is_empty() or Team.is_empty():
		return true
	return projectile_team != Team


func _projectile_team(node:Node) -> String:
	var team_value:String = ""
	if _object_has_property(node,"Team"):
		team_value = str(node.get("Team")).strip_edges()
	if node is ball:
		var projectile_ball:ball = node as ball
		if projectile_ball.Master != null and is_instance_valid(projectile_ball.Master):
			if team_value.is_empty() or team_value == "Ball":
				team_value = str(projectile_ball.Master.Team).strip_edges()
	elif _object_has_property(node,"Master"):
		var master_value:Variant = node.get("Master")
		if master_value is ball and (team_value.is_empty() or team_value == "Ball"):
			team_value = str((master_value as ball).Team).strip_edges()
	return team_value


func _projectile_velocity(node:Node) -> Vector2:
	if node == null or not is_instance_valid(node):
		return Vector2.ZERO
	if _object_has_property(node,"velocity"):
		var velocity_value:Variant = node.get("velocity")
		if velocity_value is Vector2:
			var velocity_vector:Vector2 = velocity_value
			if velocity_vector.length_squared() > 1.0:
				return velocity_vector
	var projectile_direction:Vector2 = Vector2.ZERO
	for property_name:String in ["direction","travel_direction"]:
		if _object_has_property(node,property_name):
			var direction_value:Variant = node.get(property_name)
			if direction_value is Vector2:
				projectile_direction = direction_value
				break
	if projectile_direction.length_squared() <= 0.000001:
		return Vector2.ZERO
	var projectile_speed:float = 0.0
	for speed_name:String in ["Speed","speed","projectile_speed","max_speed"]:
		if _object_has_property(node,speed_name):
			projectile_speed = absf(float(node.get(speed_name)))
			if projectile_speed > 0.0:
				break
	return projectile_direction.normalized() * projectile_speed


func _object_has_property(object:Object,property_name:String) -> bool:
	if object == null:
		return false
	for info:Dictionary in object.get_property_list():
		if str(info.get("name","")) == property_name:
			return true
	return false


func Attack() -> void:
	super()
	if state_machine.current_state == State.Die or not is_multiplayer_authority():
		return

	# 不要求敌人在攻击范围内，甚至场上没有敌人也照常进入随机攻击流程。
	Attacking = true
	_broadcast_visual_state(DrunkVisualState.WINDUP)
	var windup_low:float = minf(attack_windup_min,attack_windup_max)
	var windup_high:float = maxf(attack_windup_min,attack_windup_max)
	var windup:float = randf_range(clampf(windup_low,0.05,1.0),clampf(windup_high,0.05,1.0))
	await get_tree().create_timer(windup).timeout
	if not is_instance_valid(self) or state_machine.current_state == State.Die:
		return

	var enemy:ball = _resolve_attack_target()
	var attack_dir:Vector2 = _roll_attack_direction(enemy)
	if attack_dir.length_squared() <= 0.000001:
		attack_dir = Vector2.from_angle(randf_range(0.0,TAU))
	direction = attack_dir

	var attack_kind:int = _choose_attack_kind()
	if attack_kind == DrunkVisualState.THROW:
		_broadcast_visual_state(DrunkVisualState.THROW)
		_perform_throw(enemy,attack_dir)
		await get_tree().create_timer(maxf(throw_pose_hold,0.02)).timeout
	else:
		_broadcast_visual_state(DrunkVisualState.SMASH)
		await _perform_smash(attack_dir)
		await get_tree().create_timer(maxf(smash_pose_hold,0.02)).timeout

	if is_instance_valid(self) and state_machine.current_state != State.Die:
		_finish_attack_cycle()


func _resolve_attack_target() -> ball:
	var candidate:ball = null
	if Target_Enemy != null and is_instance_valid(Target_Enemy):
		candidate = Target_Enemy
	elif Nearest_Enemy != null and is_instance_valid(Nearest_Enemy):
		candidate = Nearest_Enemy

	if _is_valid_attack_target(candidate):
		return candidate

	# 不依赖近战/远程攻击范围：公共缓存没有目标时，直接从场上找最近可攻击敌人。
	var best:ball = null
	var best_distance_sq:float = INF
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var other:ball = node as ball
		if not _is_valid_attack_target(other):
			continue
		var distance_sq:float = global_position.distance_squared_to(other.global_position)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best = other
	return best


func _is_valid_attack_target(candidate:ball) -> bool:
	if candidate == null or not is_instance_valid(candidate) or candidate == self:
		return false
	if candidate.health <= 0:
		return false
	if not Team.is_empty() and candidate.Team == Team:
		return false
	if candidate.has_method("is_combat_targetable") and not bool(candidate.call("is_combat_targetable")):
		return false
	return true


func _choose_attack_kind() -> int:
	return DrunkVisualState.THROW if randf() < clampf(attack_throw_chance,0.0,1.0) else DrunkVisualState.SMASH


func _roll_attack_direction(enemy:ball) -> Vector2:
	if has_player_control_aim():
		return player_control_aim_direction(direction)
	var aim:Vector2 = Vector2.ZERO
	if enemy != null and is_instance_valid(enemy):
		aim = combat_target_position(enemy) - global_position
	if aim.length_squared() <= 0.000001:
		aim = Vector2.from_angle(randf_range(0.0,TAU))
	var spread:float = deg_to_rad(randf_range(-attack_spread_degrees,attack_spread_degrees))
	return aim.normalized().rotated(spread)


func _perform_throw(enemy:ball,attack_dir:Vector2) -> void:
	var bottle:ball = BOTTLE_SCENE.instantiate()
	bottle.Master = self
	bottle.Master_name = name
	bottle.Team = Team
	bottle.Target_Enemy = null if has_player_control_aim() else enemy
	bottle.Damage = Damage
	bottle.Speed = bottle_speed
	bottle.direction = attack_dir
	bottle.global_position = global_position + attack_dir * bottle_spawn_offset
	bottle.global_rotation = attack_dir.angle()
	bottle.name = Game.return_random_name(bottle)
	var world:Node = get_tree().current_scene
	if world != null:
		world.add_child(bottle,true)
	if throw_audio != "":
		Audios.play_sfx.rpc(throw_audio,{},true)


func _perform_smash(attack_dir:Vector2) -> void:
	if _smash_area == null or not is_instance_valid(_smash_area):
		return

	# 父 Area2D 以人物为旋转原点。CollisionShape2D 的局部位置/大小完全由场景 authored。
	# 例如 authored position=(90,0)：向右攻击仍是右90；向上攻击会自动旋转成上90。
	_smash_area.global_position = global_position
	_smash_area.global_rotation = attack_dir.angle()
	_smash_area.global_scale = Vector2.ONE

	var swing_position:Vector2 = global_position
	if _smash_shape != null and is_instance_valid(_smash_shape):
		swing_position = _smash_shape.global_position
	_broadcast_smash_swing_audio(swing_position)

	# Area2D overlap 列表在物理步更新；旋转完成后等一帧再读取真实 authored Shape。
	await get_tree().physics_frame
	if not is_instance_valid(self) or state_machine.current_state == State.Die:
		return

	var hit_targets:Dictionary = {}
	for area:Area2D in _smash_area.get_overlapping_areas():
		if not area is hurtbox:
			continue
		var target:ball = _hurtbox_target_ball(area as hurtbox)
		if target == null or target == self or not is_instance_valid(target):
			continue
		if hit_targets.has(target.get_instance_id()):
			continue
		if target.health <= 0:
			continue
		if not Team.is_empty() and target.Team == Team:
			continue
		if target.has_method("is_combat_targetable") and not bool(target.call("is_combat_targetable")):
			continue
		hit_targets[target.get_instance_id()] = true
		target.receive_spatial_damage(
			attack_damage(smash_damage_multiplier),
			{"point": target.global_position,"source": self}
		)

	# 远程酒瓶命中人物时场景 Hit_Audio 就是 balls_hit1；近战真正命中后复用同一声音。
	if not hit_targets.is_empty():
		_broadcast_smash_hit_audio()


func _broadcast_smash_swing_audio(impact_position:Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		_play_smash_swing_audio.rpc(impact_position)
	else:
		_play_smash_swing_audio(impact_position)


@rpc("authority","call_local","unreliable")
func _play_smash_swing_audio(impact_position:Vector2) -> void:
	var world:Node = get_tree().current_scene
	if world == null or BOTTLE_WALL_BREAK_AUDIO == null:
		return
	# 与远程酒瓶撞墙一致：独立2D播放器保证酒瓶碎裂尾音不被动作结束截断。
	var player := AudioStreamPlayer2D.new()
	player.name = "DrunkSmashSwingAudio"
	player.stream = BOTTLE_WALL_BREAK_AUDIO
	player.volume_db = smash_swing_volume_db
	player.pitch_scale = smash_swing_pitch_scale * randf_range(
		maxf(1.0 - smash_swing_random_pitch,0.05),
		1.0 + smash_swing_random_pitch
	)
	player.max_distance = smash_swing_max_distance
	player.bus = &"GameplayRecord"
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	world.add_child(player)
	player.global_position = impact_position
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _broadcast_smash_hit_audio() -> void:
	if multiplayer.has_multiplayer_peer():
		_play_smash_hit_audio.rpc()
	else:
		_play_smash_hit_audio()


@rpc("authority","call_local","unreliable")
func _play_smash_hit_audio() -> void:
	# 与 res://scenes/shooter/酒瓶.tscn 的 Hit_Audio="balls_hit1" 完全一致。
	Audios.play_sfx("balls_hit1",{volume = clampf(attack_damage(smash_damage_multiplier) - 12.0,-100.0,0.0)},true,true)


func _finish_attack_cycle() -> void:
	Attacking = false
	_broadcast_visual_state(DrunkVisualState.NORMAL)
	_roll_next_attack_cooldown()


func _broadcast_visual_state(state_value:int) -> void:
	if multiplayer.has_multiplayer_peer():
		_set_visual_state.rpc(state_value)
	else:
		_set_visual_state(state_value)


@rpc("authority","call_local","unreliable")
func _set_visual_state(state_value:int) -> void:
	_set_visual_state_local(state_value)


func _set_visual_state_local(state_value:int) -> void:
	if not image is Sprite2D:
		return
	var wanted:Texture2D = normal_texture
	match state_value:
		DrunkVisualState.WINDUP:
			wanted = windup_texture if windup_texture != null else normal_texture
		DrunkVisualState.THROW:
			wanted = throw_texture if throw_texture != null else normal_texture
		DrunkVisualState.SMASH:
			wanted = smash_texture if smash_texture != null else normal_texture
		_:
			wanted = normal_texture
	if wanted != null:
		(image as Sprite2D).texture = wanted
		var auto_fit:Node = get_node_or_null("CharacterAutoFit")
		if auto_fit != null and auto_fit.has_method("apply_visual_fit_only"):
			auto_fit.call_deferred("apply_visual_fit_only")


func Die() -> void:
	_dodge_time_left = 0.0
	_dodge_direction = Vector2.ZERO
	_broadcast_visual_state(DrunkVisualState.NORMAL)
	super()
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(self):
		Game.free_node(self)
