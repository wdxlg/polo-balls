extends ball

const GUARD_SCENE:PackedScene = preload("res://scenes/characters/人物/保安.tscn")
const REINFORCEMENT_REQUEST_SCRIPT = preload("res://scripts/characters/保安_增援请求.gd")
const CAR_COLLISION_SCRIPT = preload("res://scripts/effects/保安_巡逻车碰撞.gd")
const IMAGE_DIR:String = "res://Images/characters/人物/保安"
const HARD_MAX_GUARDS_PER_TEAM:int = 10

# 投稿音效：全部使用本地资源，不经过网络下载/运行时 WAV 解码。
const PHONE_SFX:AudioStream = preload("res://audio/characters/保安/保安_打电话.mp3")
const FORK_SWING_SFX:AudioStream = preload("res://audio/characters/保安/保安_钢叉.mp3")
const CAR_HORN_SFX:AudioStream = preload("res://audio/characters/保安/保安_车喇叭.mp3")
const DISEMBARK_SFX:AudioStream = preload("res://audio/characters/保安/保安_下车.mp3")
# 钢叉真正命中角色时不再使用普通反弹的 balls_collide1。
# 项目中“有碰撞伤害的角色真正打到人”统一走 ball.gd 的 Hit_Audio = "balls_hit1"，
# 保安命中也复用同一条 Audios 音效链路。

# ============================================================
# 保安
# - 单个 80 血，身体不造成碰撞伤害。
# - 上场后自动补成 3 人小队；自动生成的两名不会再次触发“初始 3 人”。
# - 钢叉：前方小范围突刺，32 伤害，1.9 秒冷却；命中会击退并改写目标移动方向。
# - 自己首次降到半血(40)及以下时尝试呼叫增援。
# - 同队任意保安死亡时，其他所有仍存活的同队保安都会各自响应并尝试呼叫一次增援。
# - 呼叫有 1 秒前摇；前摇内呼叫者死亡，呼叫失败。
# - 前摇完成后创建独立的“增援请求”节点；此后呼叫者死亡也不影响增援抵达。
# - 同队“活着的保安 + 已确认在路上的增援”达到 10 时，不再开始新呼叫。
# ============================================================

@export_category("保安 - 外观")
@export var normal_texture:Texture2D
@export var attack_texture:Texture2D
@export var radio_texture:Texture2D
@export var fork_texture:Texture2D
@export var car_texture:Texture2D
@export_range(0.05,1.5,0.05) var attack_visual_duration:float = 0.55

@export_category("保安 - 音效")
@export_range(-36.0,12.0,0.5) var phone_sfx_volume_db:float = 4.0
@export_range(-36.0,12.0,0.5) var fork_sfx_volume_db:float = 4.0
# 命中声复用 ball.gd 的碰撞伤害音效。
# 这个值只作为最低响度，防止低伤害 Buff/Debuff 后完全听不见。
@export_range(-36.0,12.0,0.5) var fork_hit_sfx_min_volume_db:float = -2.0
@export_range(-36.0,12.0,0.5) var car_horn_sfx_volume_db:float = 6.0
@export_range(-36.0,12.0,0.5) var disembark_sfx_volume_db:float = 6.0
@export_range(120.0,3200.0,20.0) var guard_sfx_max_distance:float = 1600.0
@export_range(0.05,2.0,0.05) var guard_sfx_attenuation:float = 0.30

@export_category("保安 - 初始小队")
@export var spawn_initial_squad:bool = true
@export_range(1,10,1) var initial_squad_size:int = 3
@export_range(18.0,90.0,1.0) var initial_squad_spacing:float = 38.0
@export_range(0.0,80.0,1.0) var spawn_map_margin:float = 24.0

@export_category("保安 - 钢叉")
@export_range(20.0,180.0,2.0) var enemy_notice_radius:float = 78.0
@export_range(0.05,1.0,0.01) var fork_windup:float = 0.24
@export_range(10.0,120.0,1.0) var fork_forward_offset:float = 44.0
@export_range(6.0,70.0,1.0) var fork_hit_radius:float = 34.0
# Damage（攻击力）就是钢叉基础伤害。
@export_range(0.0,10.0,0.05) var fork_damage_multiplier:float = 1.0
@export_range(0.0,180.0,2.0) var fork_knockback_distance:float = 48.0
@export_range(50.0,1400.0,10.0) var fork_knockback_speed:float = 540.0
@export_range(0.0,45.0,1.0) var fork_direction_jitter_degrees:float = 10.0
@export_range(24.0,100.0,1.0) var fork_visual_world_length:float = 58.0
@export_range(4.0,60.0,1.0) var fork_visual_stab_distance:float = 24.0
@export_range(0.08,0.6,0.01) var fork_visual_duration:float = 0.22

@export_category("保安 - 对讲机")
@export_range(0.1,5.0,0.05) var radio_cast_time:float = 1.0
@export_range(0.1,8.0,0.05) var reinforcement_arrival_delay:float = 1.8
@export_range(1,10,1) var max_guards_per_team:int = 10
@export_range(0.2,3.0,0.05) var reinforcement_car_drive_time:float = 0.95
@export_range(0.1,2.0,0.05) var reinforcement_car_wait_time:float = 0.45
@export_range(45.0,150.0,1.0) var reinforcement_car_world_width:float = 88.0
@export_range(8.0,60.0,1.0) var reinforcement_disembark_distance:float = 24.0

@export_category("保安 - 巡逻车碰撞")
@export_range(0.0,10.0,0.05) var reinforcement_car_collision_damage_multiplier:float = 1.5625
@export_range(0.0,180.0,2.0) var reinforcement_car_knockback_distance:float = 72.0
@export_range(50.0,1400.0,10.0) var reinforcement_car_knockback_speed:float = 760.0

const VISUAL_NORMAL:int = 0
const VISUAL_ATTACK:int = 1
const VISUAL_RADIO:int = 2

var _default_texture:Texture2D = null
var _visual_token:int = 0
var _attack_token:int = 0
var _attack_windup_active:bool = false
var _locked_attack_target_id:int = 0
var _locked_attack_direction:Vector2 = Vector2.RIGHT
var _half_health_call_used:bool = false
var _radio_casting:bool = false
var _radio_token:int = 0
var _death_event_sent:bool = false
var _initial_squad_spawned:bool = false
var _queued_death_calls:int = 0
var _phone_audio:AudioStreamPlayer2D = null


func _ensure_initial_guard_team() -> void:
	# 已经有真实队伍时完全尊重外部设置，例如红队/蓝队。
	var current_team:String = str(Team).strip_edges()
	if not current_team.is_empty() and current_team != "Ball":
		return

	# 只有权威端生成私有队伍字符串，避免不同网络端各自用 instance_id 生成不同值。
	if not is_multiplayer_authority():
		return

	# 空 Team 在 world.gd 中代表 solo，所以必须给“一次上场的保安小队”一个非空身份。
	# 每个被玩家独立放下的保安都会得到不同 ID；它自动生成的两名队友和后续增援会复制此 Team。
	var setup_part:String = ""
	if has_meta("battle_setup_id"):
		setup_part = str(get_meta("battle_setup_id"))
	if setup_part.is_empty():
		setup_part = str(get_instance_id())
	Team = "__guard_squad_" + setup_part



func get_health_threshold_values() -> PackedFloat32Array:
	# 半血及以下首次呼叫增援。
	return PackedFloat32Array([float(Max_health) * 0.5])

func _ready() -> void:
	# 项目规则中空 Team 代表“每个角色都是独立阵营”。
	# 保安一次上场却是一个整体小队，因此在无队伍/遗留默认 Ball 的情况下，
	# 由权威端先给本次上场创建一个私有隐藏队伍，再生成另外两名保安。
	# Team 本身已在 ball.tscn 的 MultiplayerSynchronizer 中同步，远端会收到同一值。
	_ensure_initial_guard_team()

	Has_Collision_Damage = false
	Can_Skill = false
	Max_health = 80
	Attack_Cooling = 1.9
	# 投稿素材默认朝右，因此关闭基类的 dir_left（“原图朝左”）设定。
	# 必须在 super._ready() 之前写入，避免基类第一帧按错误朝向镜像。
	dir_left = false
	super._ready()
	add_to_group("SecurityGuard")
	_ensure_phone_audio_player()
	_auto_load_textures()
	if image is Sprite2D:
		_default_texture = (image as Sprite2D).texture
	_set_visual_state_local(VISUAL_NORMAL)

	# 场景默认角色代表“一次上场”，自动生成的队友会先把该字段设为 false。
	if is_multiplayer_authority() and spawn_initial_squad and not _initial_squad_spawned:
		_initial_squad_spawned = true
		call_deferred("_spawn_initial_teammates")


func get_preview_texture() -> Texture2D:
	_auto_load_textures()
	return normal_texture


func _auto_load_textures() -> void:
	if normal_texture == null:
		normal_texture = _load_first_texture([
			IMAGE_DIR.path_join("保安_正常.png"),
			IMAGE_DIR.path_join("保安_正常.webp"),
			IMAGE_DIR.path_join("保安_正常.svg")
		])
	if attack_texture == null:
		attack_texture = _load_first_texture([
			IMAGE_DIR.path_join("保安_攻击.png"),
			IMAGE_DIR.path_join("保安_攻击.webp"),
			IMAGE_DIR.path_join("保安_攻击.svg")
		])
	if radio_texture == null:
		radio_texture = _load_first_texture([
			IMAGE_DIR.path_join("保安_对讲机.png"),
			IMAGE_DIR.path_join("保安_对讲机.webp"),
			IMAGE_DIR.path_join("保安_对讲机.svg")
		])
	if fork_texture == null:
		fork_texture = _load_first_texture([
			IMAGE_DIR.path_join("保安_钢叉.png"),
			IMAGE_DIR.path_join("保安_钢叉.webp"),
			IMAGE_DIR.path_join("保安_钢叉.svg")
		])
	if car_texture == null:
		car_texture = _load_first_texture([
			IMAGE_DIR.path_join("保安_巡逻车.png"),
			IMAGE_DIR.path_join("保安_巡逻车.webp"),
			IMAGE_DIR.path_join("保安_巡逻车.svg")
		])


func _load_first_texture(paths:Array[String]) -> Texture2D:
	for path:String in paths:
		if not ResourceLoader.exists(path):
			continue
		var resource:Resource = ResourceLoader.load(path)
		if resource is Texture2D:
			return resource as Texture2D
	return null


func get_next_state(state:State) -> int:
	# 对讲机前摇期间完全不启动攻击/技能；角色移动由 tick_physics() 强制 stand。
	if _radio_casting:
		var saved_can_attack:bool = Can_Attack
		Can_Attack = false
		var radio_next:int = super.get_next_state(state)
		Can_Attack = saved_can_attack
		return radio_next

	# 基类默认冷却一到就 Attack。保安只有附近真的存在敌人才出叉，避免空挥消耗冷却。
	if (
		is_multiplayer_authority()
		and Can_Attack
		and not is_damage_output_disabled()
		and state_machine.last_state_dis.Attack >= Attack_Cooling
		and _nearest_attack_target() == null
	):
		var saved_attack_timer:float = float(state_machine.last_state_dis.Attack)
		Can_Attack = false
		var next_state:int = super.get_next_state(state)
		Can_Attack = true
		state_machine.last_state_dis.Attack = saved_attack_timer
		return next_state

	return super.get_next_state(state)


func tick_physics(state:State,delta:float) -> void:
	if is_multiplayer_authority() and health > 0:
		_try_half_health_radio()
		_try_queued_death_radio()

	if _radio_casting or _attack_windup_active:
		# 呼叫和举叉前摇都明确停下，给敌人反制/躲避窗口。
		stand(delta)
		Repel = Vector2.ZERO
		return

	super.tick_physics(state,delta)


func Attack() -> void:
	if state_machine.current_state == State.Die or not is_multiplayer_authority():
		return
	if _radio_casting or is_damage_output_disabled():
		Attacking = false
		return

	var target:ball = _nearest_attack_target()
	if target == null and not has_player_control_aim():
		Attacking = false
		return

	var to_target:Vector2 = player_control_aim_direction(direction) if has_player_control_aim() else (target.global_position - global_position)
	if to_target.length_squared() <= 0.000001:
		to_target = direction if direction.length_squared() > 0.000001 else Vector2.RIGHT

	Attacking = true
	_attack_windup_active = true
	_locked_attack_target_id = target.get_instance_id() if target != null else 0
	_locked_attack_direction = to_target.normalized()
	direction = _locked_attack_direction
	_attack_token += 1
	var token:int = _attack_token

	# 第一步：先切到投稿素材里的“持叉捅出”攻击图。
	_show_visual_everywhere(VISUAL_ATTACK)

	# 第二步：前摇进行一小段后，让独立钢叉从人物位置沿锁定方向真正“捅出去”。
	# 钢叉只负责表现，不参与碰撞；命中仍由下面的小范围判定结算。
	var fork_lead:float = minf(maxf(fork_windup * 0.38,0.05),maxf(fork_windup - 0.03,0.05))
	await get_tree().create_timer(fork_lead).timeout
	if not is_instance_valid(self) or token != _attack_token or health <= 0:
		return
	# 举叉前摇的前半段允许做一次很轻的重新瞄准。旧版完全锁死最初方向，
	# 目标只要横向移动一点，后面的“点对圆”判定就经常空掉。
	var lead_target:ball = _ball_from_id(_locked_attack_target_id)
	if has_player_control_aim():
		# 手动控制期间允许前摇中继续微调鼠标，绝不重新吸向敌人。
		_locked_attack_direction = player_control_aim_direction(_locked_attack_direction)
		direction = _locked_attack_direction
	elif lead_target != null and _is_valid_enemy(lead_target):
		var refreshed:Vector2 = lead_target.global_position - global_position
		if refreshed.length_squared() > 0.000001 and refreshed.length() <= enemy_notice_radius + fork_hit_radius:
			_locked_attack_direction = refreshed.normalized()
			direction = _locked_attack_direction
	_show_fork_stab_everywhere(_locked_attack_direction)

	var remain_windup:float = maxf(fork_windup - fork_lead,0.02)
	await get_tree().create_timer(remain_windup).timeout
	if not is_instance_valid(self) or token != _attack_token or health <= 0:
		return

	_attack_windup_active = false
	if not is_damage_output_disabled():
		_resolve_fork_hit()
	Attacking = false

	# 攻击图继续保持一段时间，让“切图 -> 钢叉捅出 -> 收势”完整可见。
	_restore_normal_after(maxf(attack_visual_duration,0.05),token)


func _resolve_fork_hit() -> void:
	var attack_dir:Vector2 = _locked_attack_direction
	if attack_dir.length_squared() <= 0.000001:
		attack_dir = Vector2.RIGHT
	attack_dir = attack_dir.normalized()

	# 旧版只检查“目标中心是否刚好落在前方某个小圆里”，所以即使叉子的图片已经
	# 穿过敌人的碰撞体，只要敌人中心点偏了一点也会判定为空。
	# 现在改成沿整段钢叉路径做一个有宽度的前方碰撞走廊，并优先命中原来锁定的敌人。
	var target:ball = _find_fork_hit_target(attack_dir)
	if target == null:
		return

	_play_fork_hit_sfx_everywhere((global_position + target.global_position) * 0.5)

	var damage_amount:float = attack_damage(fork_damage_multiplier)
	if damage_amount > 0.0:
		var fork_start_distance:float = maxf(fork_forward_offset - fork_hit_radius,0.0)
		var fork_end_distance:float = fork_forward_offset + fork_hit_radius + 8.0
		var fork_start:Vector2 = global_position + attack_dir * fork_start_distance
		var fork_end:Vector2 = global_position + attack_dir * fork_end_distance
		target.receive_spatial_damage(
			damage_amount,
			{
				"shape":"capsule",
				"from":fork_start,
				"to":fork_end,
				"half_width":maxf(fork_hit_radius,1.0),
				"source":self,
				# 钢叉不穿透人物。决斗者必须按来源侧的第一身体接触点判断，
				# 不能因为整根胶囊穿过身体后又碰到背部弱点就算破绽命中。
				"blocked_by_body":true,
				"source_position":fork_start,
			},
			false
		)

	var push_dir:Vector2 = target.global_position - global_position
	if push_dir.length_squared() <= 0.000001:
		push_dir = attack_dir
	push_dir = push_dir.normalized()

	if fork_knockback_distance > 0.0:
		target.apply_knockback(
			push_dir,
			fork_knockback_distance,
			fork_knockback_speed,
			0.22,
			0.0,
			{
				"source":self,
				"max_wall_bounces":1,
				"stop_on_character":true,
				"character_bounce_strength":0.15,
			}
		)

	# 钢叉的核心干扰：不仅瞬时推开，还把目标接下来的自主移动方向改到被叉开的方向。
	var jitter_rad:float = deg_to_rad(maxf(fork_direction_jitter_degrees,0.0))
	var redirected:Vector2 = push_dir.rotated(randf_range(-jitter_rad,jitter_rad)).normalized()
	target.direction = redirected


func _find_fork_hit_target(attack_dir:Vector2) -> ball:
	# 把钢叉判定当作一条“从角色前方延伸出去的粗线段”。
	# 起点略微离开身体，终点覆盖到视觉钢叉的前端；半宽则由 fork_hit_radius 控制。
	var start_distance:float = 8.0
	var end_distance:float = maxf(
		fork_forward_offset + fork_hit_radius + 8.0,
		start_distance + 4.0
	)
	var segment_start:Vector2 = global_position + attack_dir * start_distance
	var segment_end:Vector2 = global_position + attack_dir * end_distance
	var hit_half_width:float = maxf(fork_hit_radius,1.0)

	var locked_id:int = _locked_attack_target_id
	var best:ball = null
	var best_score:float = INF

	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var candidate:ball = node as ball
		if not _is_valid_enemy(candidate):
			continue

		var closest:Vector2 = _closest_point_on_segment(candidate.global_position,segment_start,segment_end)
		var lateral_distance:float = candidate.global_position.distance_to(closest)
		if lateral_distance > hit_half_width:
			continue

		# 原来锁定的敌人只要还在钢叉走廊里就优先命中，避免多目标挤在一起时乱跳。
		if candidate.get_instance_id() == locked_id:
			return candidate

		# 其他敌人则选择最靠近钢叉中心线、同时更靠前的那个。
		var forward_distance:float = maxf((candidate.global_position - segment_start).dot(attack_dir),0.0)
		var score:float = lateral_distance * 4.0 + forward_distance * 0.15
		if score < best_score:
			best_score = score
			best = candidate

	return best


func _closest_point_on_segment(point:Vector2,a:Vector2,b:Vector2) -> Vector2:
	var ab:Vector2 = b - a
	var len_sq:float = ab.length_squared()
	if len_sq <= 0.000001:
		return a
	var t:float = clampf((point - a).dot(ab) / len_sq,0.0,1.0)
	return a + ab * t


func _nearest_attack_target() -> ball:
	var best:ball = null
	var best_dist_sq:float = maxf(enemy_notice_radius,0.0) * maxf(enemy_notice_radius,0.0)
	for node:Node in SubmissionCharacterTools.targeting_candidates(self):
		if not node is ball:
			continue
		var candidate:ball = node as ball
		if not _is_valid_enemy(candidate):
			continue
		var dist_sq:float = global_position.distance_squared_to(candidate.global_position)
		if dist_sq <= best_dist_sq:
			best_dist_sq = dist_sq
			best = candidate
	return best


func _is_valid_enemy(target:ball) -> bool:
	if target == null or not is_instance_valid(target) or target == self:
		return false
	if not target.is_combat_targetable():
		return false
	if not Game.Game_Settings.Have_Team_Damage and Team != "" and target.Team == Team:
		return false
	return true


func _ball_from_id(instance_id_value:int) -> ball:
	if instance_id_value <= 0 or not is_instance_id_valid(instance_id_value):
		return null
	var value:Variant = instance_from_id(instance_id_value)
	if value is ball:
		return value as ball
	return null


func _try_half_health_radio() -> void:
	if _half_health_call_used or _radio_casting or _attack_windup_active or Attacking:
		return
	if health <= 0 or health > int(floor(float(Max_health) * 0.5)):
		return
	_begin_radio_call("half_health")


func request_replacement_for_teammate_death(_death_position:Vector2) -> void:
	if not is_multiplayer_authority() or health <= 0:
		return
	# 每个存活保安都会独立收到死亡事件；忙碌时先排队，空下来后仍会响应。
	_queued_death_calls += 1
	_try_queued_death_radio()


func _try_queued_death_radio() -> void:
	if _queued_death_calls <= 0:
		return
	if health <= 0 or _radio_casting or _attack_windup_active or Attacking:
		return
	if _team_guard_total_with_pending() >= _guard_cap():
		return
	_queued_death_calls -= 1
	_begin_radio_call("teammate_death")


func _begin_radio_call(reason:String) -> bool:
	if not is_multiplayer_authority() or health <= 0 or _radio_casting:
		return false
	if _team_guard_total_with_pending() >= _guard_cap():
		return false

	_radio_casting = true
	_radio_token += 1
	var token:int = _radio_token
	_show_visual_everywhere(VISUAL_RADIO)
	_show_radio_waves_everywhere(maxf(radio_cast_time,0.1))
	_set_phone_audio_everywhere(true)

	await get_tree().create_timer(maxf(radio_cast_time,0.05)).timeout
	# 这就是“呼叫期间死亡则失败”的边界：没有活着撑到前摇结束，就不创建请求节点。
	if not is_instance_valid(self) or token != _radio_token or health <= 0:
		return false

	_radio_casting = false
	_set_phone_audio_everywhere(false)
	_show_visual_everywhere(VISUAL_NORMAL)

	# 别的保安可能在这一秒里先完成呼叫；成功前再检查一次硬上限。
	if _team_guard_total_with_pending() >= _guard_cap():
		return false

	# 呼叫成功这一刻就锁定“保安刚才站的位置”。
	# 此后原保安即使死亡，请求节点和巡逻车动画也不会取消。
	var confirmed_position:Vector2 = _clamp_point_to_map(global_position,spawn_map_margin)
	var request:Node2D = REINFORCEMENT_REQUEST_SCRIPT.new()
	request.name = "GuardReinforcement_%d" % Time.get_ticks_usec()
	request.set("Team",Team)
	request.set("guard_scene",GUARD_SCENE)
	request.set("arrival_delay",reinforcement_arrival_delay)
	request.set("car_drive_time",reinforcement_car_drive_time)
	request.set("max_team_count",max_guards_per_team)
	request.set("spawn_map_margin",spawn_map_margin)
	request.set("spawn_position",confirmed_position)
	request.set("disembark_distance",reinforcement_disembark_distance)
	get_tree().current_scene.add_child(request,true)

	_show_reinforcement_car_everywhere(
		confirmed_position,
		reinforcement_arrival_delay,
		reinforcement_car_drive_time,
		reinforcement_car_wait_time,
		reinforcement_car_world_width
	)

	if reason == "half_health":
		_half_health_call_used = true
	return true


func _show_fork_stab_everywhere(attack_dir:Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_show_fork_stab.rpc(attack_dir)
	else:
		_rpc_show_fork_stab(attack_dir)


@rpc("authority","call_local","unreliable")
func _rpc_show_fork_stab(attack_dir:Vector2) -> void:
	# 投稿的钢叉音效对应“叉子向前捅”的动作；空挥也应该听得到。
	_play_one_shot_2d(FORK_SWING_SFX,global_position,fork_sfx_volume_db,1.0)
	if fork_texture == null:
		_auto_load_textures()
	if fork_texture == null:
		return
	var world:Node = get_tree().current_scene
	if world == null:
		return

	var dir:Vector2 = attack_dir
	if dir.length_squared() <= 0.000001:
		dir = Vector2.RIGHT
	dir = dir.normalized()

	var effect := Node2D.new()
	effect.name = "GuardForkStab"
	effect.z_index = 1250
	world.add_child(effect)
	effect.global_position = global_position

	var fork := Sprite2D.new()
	fork.texture = fork_texture
	fork.centered = true
	fork.z_index = 1
	effect.add_child(fork)

	var texture_size:Vector2 = fork_texture.get_size()
	var texture_height:float = maxf(texture_size.y,1.0)
	var visual_scale:float = maxf(fork_visual_world_length,1.0) / texture_height
	fork.scale = Vector2.ONE * visual_scale

	# 素材中的钢叉朝“上”，把把手末端放在角色原点，再旋转到敌人方向。
	fork.offset = Vector2(0.0,-texture_height * 0.5)
	fork.rotation = dir.angle() + PI * 0.5

	var start_pos:Vector2 = global_position + dir * 5.0
	var end_pos:Vector2 = global_position + dir * maxf(fork_visual_stab_distance,6.0)
	fork.global_position = start_pos
	fork.modulate.a = 0.96

	var duration:float = maxf(fork_visual_duration,0.08)
	var out_time:float = duration * 0.52
	var back_time:float = duration - out_time
	var tween:Tween = effect.create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(fork,"global_position",end_pos,out_time)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(fork,"global_position",start_pos + dir * 3.0,back_time)
	tween.parallel().tween_property(fork,"modulate:a",0.0,back_time)
	tween.finished.connect(effect.queue_free,CONNECT_ONE_SHOT)


func _show_reinforcement_car_everywhere(
	stop_position:Vector2,
	delay_before_entry:float,
	drive_time:float,
	wait_time:float,
	world_width:float
) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_show_reinforcement_car.rpc(
			stop_position,
			delay_before_entry,
			drive_time,
			wait_time,
			world_width
		)
	else:
		_rpc_show_reinforcement_car(
			stop_position,
			delay_before_entry,
			drive_time,
			wait_time,
			world_width
		)


@rpc("authority","call_local","reliable")
func _rpc_show_reinforcement_car(
	stop_position:Vector2,
	delay_before_entry:float,
	drive_time:float,
	wait_time:float,
	world_width:float
) -> void:
	if car_texture == null:
		_auto_load_textures()
	if car_texture == null:
		return
	var world:Node = get_tree().current_scene
	if world == null:
		return

	var effect := Node2D.new()
	effect.name = "GuardReinforcementCar"
	effect.z_index = 900
	# 呼叫成功后到真正发车前，车辆节点虽然已经存在，但完全隐藏；
	# 到发车时才从“当前屏幕”外侧出现并立即开始移动，不会在地图边缘停着等。
	effect.visible = false
	world.add_child(effect)

	# 喇叭随车辆移动；下车声固定在呼叫成功时锁定的位置。
	# 两个播放器都挂在独立的车辆特效节点下，即使原来的呼叫保安已经死亡也能正常播完。
	var horn_audio := AudioStreamPlayer2D.new()
	horn_audio.name = "GuardCarHornAudio"
	horn_audio.stream = CAR_HORN_SFX
	horn_audio.bus = &"Sfx"
	horn_audio.volume_db = car_horn_sfx_volume_db
	horn_audio.max_distance = guard_sfx_max_distance
	horn_audio.attenuation = guard_sfx_attenuation

	var disembark_audio := AudioStreamPlayer2D.new()
	disembark_audio.name = "GuardDisembarkAudio"
	disembark_audio.stream = DISEMBARK_SFX
	disembark_audio.bus = &"Sfx"
	disembark_audio.volume_db = disembark_sfx_volume_db
	disembark_audio.max_distance = guard_sfx_max_distance
	disembark_audio.attenuation = guard_sfx_attenuation
	effect.add_child(disembark_audio)
	disembark_audio.global_position = stop_position

	var visible_world_rect:Rect2 = _get_visible_world_rect(effect)
	var fallback_rect:Rect2 = _get_map_rect()
	var travel_rect:Rect2 = visible_world_rect
	if travel_rect.size.x <= 1.0 or travel_rect.size.y <= 1.0:
		travel_rect = fallback_rect

	var start_pos:Vector2
	var exit_pos:Vector2
	var from_left:bool = true
	if travel_rect.size.x > 1.0 and travel_rect.size.y > 1.0:
		from_left = stop_position.x <= travel_rect.get_center().x
		# world_width 已经是车辆在世界里的实际宽度。用半车宽再加一点保险距离，
		# 确保开始运动时整辆车都在屏幕外，而不是露出半辆车。
		var outside:float = maxf(world_width * 0.58 + 12.0,42.0)
		if from_left:
			start_pos = Vector2(travel_rect.position.x - outside,stop_position.y)
			exit_pos = Vector2(travel_rect.end.x + outside,stop_position.y)
		else:
			start_pos = Vector2(travel_rect.end.x + outside,stop_position.y)
			exit_pos = Vector2(travel_rect.position.x - outside,stop_position.y)
	else:
		from_left = direction.x >= 0.0
		var fallback_span:float = 420.0
		start_pos = stop_position + Vector2(-fallback_span if from_left else fallback_span,0.0)
		exit_pos = stop_position + Vector2(fallback_span if from_left else -fallback_span,0.0)

	# 车辆本身使用独立 Sprite2D 脚本做扫掠碰撞。这样即使原呼叫保安在车到达前死亡，
	# 车仍会跟随自己的 Tween 完成 50 点撞击伤害与击退，不依赖呼叫者继续存活。
	var car = CAR_COLLISION_SCRIPT.new()
	car.texture = car_texture
	car.centered = true
	car.flip_h = not from_left
	car.global_position = start_pos
	var texture_size:Vector2 = car_texture.get_size()
	var texture_width:float = maxf(texture_size.x,1.0)
	var texture_height:float = maxf(texture_size.y,1.0)
	var scale_value:float = maxf(world_width,20.0) / texture_width
	car.scale = Vector2.ONE * scale_value
	effect.add_child(car)

	var car_world_height:float = texture_height * scale_value
	var car_move_direction:Vector2 = Vector2.RIGHT if from_left else Vector2.LEFT
	car.call(
		"configure_collision_damage",
		Team,
		is_multiplayer_authority(),
		car_move_direction,
		stop_position,
		attack_damage(reinforcement_car_collision_damage_multiplier),
		# 只取车图中间约 70% 的长度作为真实撞击车身，去掉保险杠/透明边缘。
		maxf(world_width * 0.35,12.0),
		# 高度也明显收紧，避免车顶/透明留白隔着一段距离撞到人。
		maxf(car_world_height * 0.27,8.0),
		reinforcement_car_knockback_distance,
		reinforcement_car_knockback_speed
	)

	car.add_child(horn_audio)
	horn_audio.position = Vector2.ZERO

	# “总部确认后的等待”期间车辆不可见。等待结束的同一刻显示车辆并直接开始驶入。
	# 驶入使用 CUBIC + EASE_OUT：一开始速度明显更快，越接近呼叫点越慢。
	# 这比之前 QUAD 的减速感更明显，也正好让停车/下人看起来更自然。
	var tween:Tween = effect.create_tween()
	tween.tween_interval(maxf(delay_before_entry,0.0))
	tween.tween_callback(effect.show)
	# 车真正从屏幕外出现并开始驶入的这一刻鸣笛，不会在等待阶段提前响。
	tween.tween_callback(Callable(horn_audio,"play"))
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(car,"global_position",stop_position,maxf(drive_time,0.1))
	# 车辆到停车点后立刻关闭撞击伤害。
	# 碰撞脚本内部也会按 stop_position 自动截断，这里再关一次作为 Tween 阶段的明确保险。
	tween.tween_callback(Callable(car,"set_damage_active").bind(false))
	# 停车后才播放“保安下车”音效；等待和之后的离场都不再造成车辆伤害。
	tween.tween_callback(Callable(disembark_audio,"play"))
	tween.tween_interval(maxf(wait_time,0.05))
	# 离场只是视觉动画：从停车状态缓慢起步，再逐渐加速离开屏幕，不带碰撞伤害。
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(car,"global_position",exit_pos,maxf(drive_time * 0.72,0.18))
	tween.finished.connect(effect.queue_free,CONNECT_ONE_SHOT)


func _spawn_initial_teammates() -> void:
	if not is_instance_valid(self) or health <= 0 or not is_multiplayer_authority():
		return
	var wanted_extra:int = maxi(initial_squad_size - 1,0)
	for index:int in range(wanted_extra):
		if _count_live_team_guards() >= _guard_cap():
			break
		var teammate:ball = GUARD_SCENE.instantiate() as ball
		if teammate == null:
			continue
		teammate.set("spawn_initial_squad",false)
		# 必须在入树前就写入同一 Team，确保 teammate._ready()/super._ready() 从第一帧开始就是队友。
		var squad_team:String = Team
		teammate.Team = squad_team
		teammate.Target_Enemy = Target_Enemy
		var base_dir:Vector2 = direction.normalized() if direction.length_squared() > 0.000001 else Vector2.RIGHT
		teammate.direction = base_dir.rotated((-0.28 if index % 2 == 0 else 0.28))
		teammate.name = Game.return_random_name(teammate)
		get_tree().current_scene.add_child(teammate,true)
		# 再写一次作为保险：若项目中的其他入树初始化逻辑改写了 Team，立即拉回小队 Team。
		teammate.Team = squad_team

		var side_sign:float = -1.0 if index % 2 == 0 else 1.0
		var row:int = int(index / 2) + 1
		var offset:Vector2 = base_dir.rotated(PI * 0.5) * initial_squad_spacing * side_sign * float(row)
		teammate.global_position = _clamp_point_to_map(global_position + offset,spawn_map_margin)


func _guard_cap() -> int:
	return mini(maxi(max_guards_per_team,1),HARD_MAX_GUARDS_PER_TEAM)


func _count_live_team_guards() -> int:
	var count:int = 0
	for node:Node in get_tree().get_nodes_in_group("SecurityGuard"):
		if not node is ball:
			continue
		var guard:ball = node as ball
		if guard.Team != Team or guard.health <= 0:
			continue
		count += 1
	return count


func _count_pending_team_reinforcements() -> int:
	var count:int = 0
	for node:Node in get_tree().get_nodes_in_group("GuardReinforcementRequest"):
		if node == null or not is_instance_valid(node):
			continue
		if str(node.get("Team")) == Team:
			count += 1
	return count


func _team_guard_total_with_pending() -> int:
	return _count_live_team_guards() + _count_pending_team_reinforcements()


func _notify_all_teammates_about_death() -> void:
	if not is_multiplayer_authority():
		return

	# V54：同队一个保安死亡，其他所有存活保安都收到同一次死亡通知。
	# 每个保安都走自己已有的 request_replacement_for_teammate_death()：
	# - 空闲：立即开始对讲机前摇；
	# - 正在攻击 / 举叉 / 已经呼叫：先排队，空下来后再响应；
	# - 同队活人 + 已确认在路上的增援达到硬上限时，现有上限逻辑会阻止继续生成。
	#
	# 不再按距离选择“最近的一名保安”。
	for node:Node in get_tree().get_nodes_in_group("SecurityGuard"):
		if node == self or not node is ball:
			continue

		var teammate:ball = node as ball
		if teammate.Team != Team or teammate.health <= 0:
			continue
		if not teammate.has_method("request_replacement_for_teammate_death"):
			continue

		teammate.call(
			"request_replacement_for_teammate_death",
			global_position
		)


func _get_visible_world_rect(reference:CanvasItem) -> Rect2:
	if reference == null or not is_instance_valid(reference) or not reference.is_inside_tree():
		return Rect2()
	var viewport_rect:Rect2 = reference.get_viewport_rect()
	if viewport_rect.size.x <= 1.0 or viewport_rect.size.y <= 1.0:
		return Rect2()

	# get_canvas_transform() 是“世界画布 -> Viewport”的变换；取逆即可把屏幕四角换回世界坐标。
	# 取四个角而不是只取对角线，这样即使以后 Camera2D 有旋转也不会算错边界。
	var viewport_to_world:Transform2D = reference.get_canvas_transform().affine_inverse()
	var corners:Array[Vector2] = [
		viewport_to_world * viewport_rect.position,
		viewport_to_world * Vector2(viewport_rect.end.x,viewport_rect.position.y),
		viewport_to_world * viewport_rect.end,
		viewport_to_world * Vector2(viewport_rect.position.x,viewport_rect.end.y)
	]
	var min_x:float = corners[0].x
	var max_x:float = corners[0].x
	var min_y:float = corners[0].y
	var max_y:float = corners[0].y
	for point:Vector2 in corners:
		min_x = minf(min_x,point.x)
		max_x = maxf(max_x,point.x)
		min_y = minf(min_y,point.y)
		max_y = maxf(max_y,point.y)
	return Rect2(Vector2(min_x,min_y),Vector2(max_x - min_x,max_y - min_y))


func _get_map_rect() -> Rect2:
	var world = get_tree().current_scene
	if world == null or not world.has_method("return_map_world_rect"):
		return Rect2()
	if not world.map_group.has(str(world.now_choose_map)):
		return Rect2()
	var map_node = world.map_group[str(world.now_choose_map)]
	if not map_node is TileMapLayer:
		return Rect2()
	return world.return_map_world_rect(map_node)


func _clamp_point_to_map(point:Vector2,margin_value:float) -> Vector2:
	var rect:Rect2 = _get_map_rect()
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return point
	var margin:float = maxf(margin_value,0.0)
	var min_x:float = rect.position.x + margin
	var max_x:float = rect.end.x - margin
	var min_y:float = rect.position.y + margin
	var max_y:float = rect.end.y - margin
	if min_x > max_x:
		min_x = (rect.position.x + rect.end.x) * 0.5
		max_x = min_x
	if min_y > max_y:
		min_y = (rect.position.y + rect.end.y) * 0.5
		max_y = min_y
	return Vector2(clampf(point.x,min_x,max_x),clampf(point.y,min_y,max_y))


func _ensure_phone_audio_player() -> AudioStreamPlayer2D:
	if _phone_audio != null and is_instance_valid(_phone_audio):
		return _phone_audio
	var player := AudioStreamPlayer2D.new()
	player.name = "GuardPhoneAudio"
	player.stream = PHONE_SFX
	player.bus = &"Sfx"
	player.volume_db = phone_sfx_volume_db
	player.max_distance = guard_sfx_max_distance
	player.attenuation = guard_sfx_attenuation
	add_child(player)
	_phone_audio = player
	return _phone_audio


func _set_phone_audio_everywhere(playing:bool) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_set_phone_audio.rpc(playing)
	else:
		_rpc_set_phone_audio(playing)


@rpc("authority","call_local","reliable")
func _rpc_set_phone_audio(playing:bool) -> void:
	var player:AudioStreamPlayer2D = _ensure_phone_audio_player()
	if player == null:
		return
	player.volume_db = phone_sfx_volume_db
	player.max_distance = guard_sfx_max_distance
	if playing:
		player.stop()
		player.play()
	else:
		player.stop()


func _play_one_shot_2d(stream:AudioStream,world_position:Vector2,volume_value:float,pitch_value:float = 1.0) -> void:
	if stream == null:
		return
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.bus = &"Sfx"
	player.volume_db = volume_value
	player.pitch_scale = pitch_value
	player.max_distance = guard_sfx_max_distance
	player.attenuation = guard_sfx_attenuation
	world.add_child(player)
	player.global_position = world_position
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _play_fork_hit_sfx_everywhere(hit_position:Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_fork_hit_sfx.rpc(hit_position)
	else:
		_rpc_play_fork_hit_sfx(hit_position)


@rpc("authority","call_local","unreliable")
func _rpc_play_fork_hit_sfx(_hit_position:Vector2) -> void:
	# 与 ball.gd 的碰撞伤害角色保持同一命中音：balls_hit1。
	# ball.gd 原公式是 outgoing_damage - 12 dB；这里继续复用同一命中音量计算。
	# create_new_audio=true 允许多名保安同时命中时各自拥有 playback voice，不互相把声音截断。
	var hit_volume:float = clampf(attack_damage(fork_damage_multiplier) - 12.0,-100.0,0.0)
	hit_volume = maxf(hit_volume,fork_hit_sfx_min_volume_db)
	# 本函数自身已经通过 call_local RPC 在每个客户端各执行一次，
	# 这里只本地播放，避免再套一层 RPC 导致多人时重复叠音。
	Audios.play_sfx("balls_hit1",{volume = hit_volume},true,true)


func _show_visual_everywhere(state_value:int) -> void:
	_visual_token += 1
	if multiplayer.has_multiplayer_peer():
		_rpc_set_visual_state.rpc(state_value,_visual_token)
	else:
		_rpc_set_visual_state(state_value,_visual_token)


@rpc("authority","call_local","reliable")
func _rpc_set_visual_state(state_value:int,token:int) -> void:
	if token < _visual_token:
		return
	_visual_token = token
	_set_visual_state_local(state_value)


func _set_visual_state_local(state_value:int) -> void:
	if not (image is Sprite2D):
		return
	var wanted:Texture2D = normal_texture if normal_texture != null else _default_texture
	if state_value == VISUAL_ATTACK and attack_texture != null:
		wanted = attack_texture
	elif state_value == VISUAL_RADIO and radio_texture != null:
		wanted = radio_texture
	if wanted == null:
		return
	(image as Sprite2D).texture = wanted


func _restore_normal_after(delay:float,attack_token:int) -> void:
	await get_tree().create_timer(maxf(delay,0.05)).timeout
	if not is_instance_valid(self) or attack_token != _attack_token or _radio_casting:
		return
	_show_visual_everywhere(VISUAL_NORMAL)


func _show_radio_waves_everywhere(duration:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_show_radio_waves.rpc(duration)
	else:
		_rpc_show_radio_waves(duration)


@rpc("authority","call_local","unreliable")
func _rpc_show_radio_waves(duration:float) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var effect := Node2D.new()
	effect.name = "GuardRadioWave"
	effect.z_index = 1200
	world.add_child(effect)
	effect.global_position = global_position + Vector2(0.0,-26.0)

	for index:int in range(3):
		var ring := Line2D.new()
		ring.width = 1.8
		ring.default_color = Color(0.45,0.95,1.0,0.9)
		ring.closed = false
		var points := PackedVector2Array()
		var radius:float = 6.0 + float(index) * 5.0
		# 上半圆无线电波纹。
		for step:int in range(9):
			var angle:float = lerpf(-PI * 0.82,-PI * 0.18,float(step) / 8.0)
			points.append(Vector2.RIGHT.rotated(angle) * radius)
		ring.points = points
		effect.add_child(ring)

	var tween:Tween = effect.create_tween().set_parallel(true)
	tween.tween_property(effect,"position:y",effect.position.y - 7.0,maxf(duration,0.1))
	tween.tween_property(effect,"modulate:a",0.0,maxf(duration,0.1))
	tween.finished.connect(effect.queue_free,CONNECT_ONE_SHOT)


func Die() -> void:
	# 如果保安正在呼叫时被击杀，立刻停止对讲机声音；呼叫本身也会因为 token/health 检查而失败。
	if _radio_casting and is_multiplayer_authority():
		_set_phone_audio_everywhere(false)
	if not _death_event_sent and is_multiplayer_authority():
		_death_event_sent = true
		_radio_token += 1
		_attack_token += 1
		_notify_all_teammates_about_death()
	super()
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(self):
		Game.free_node(self)

# ============================================================
# RL 通用威胁接口：钢叉
# ============================================================
func get_ai_attack_threats(_receiver:ball) -> Array:
	if not _attack_windup_active or health <= 0:
		return []
	var dir:Vector2 = _locked_attack_direction.normalized() if _locked_attack_direction.length_squared() > 0.000001 else Vector2.RIGHT
	var start_distance:float = maxf(fork_forward_offset-fork_hit_radius,0.0)
	var end_distance:float = fork_forward_offset+fork_hit_radius+8.0
	return [{
		"shape":"segment",
		"start":global_position+dir*start_distance,
		"end":global_position+dir*end_distance,
		"radius":maxf(fork_hit_radius,2.0),
		"damage":attack_damage(fork_damage_multiplier),
		"danger_in":maxf(fork_windup,0.0),
		"danger_duration":0.12,
		"kind":"guard_fork",
		"source":self,
	}]
