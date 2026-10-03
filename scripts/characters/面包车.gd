extends ball

const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const MINION_SCENE:PackedScene = preload("res://scenes/creatures/投稿随从.tscn")
const MINION_SCRIPT = preload("res://scripts/creatures/投稿随从.gd")
const VAN_TEXTURE_RIGHT:Texture2D = preload("res://Images/characters/人物/面包车/面包车.png")
const VAN_TEXTURE_LEFT:Texture2D = preload("res://Images/characters/人物/面包车/面包车_向左.png")
const VAN_FORWARD_AUDIO:AudioStream = preload("res://audio/characters/面包车/前进.mp3")
const VAN_REVERSE_AUDIO:AudioStream = preload("res://audio/characters/面包车/倒车.mp3")
const VAN_WALL_AUDIO:AudioStream = preload("res://audio/characters/面包车/撞墙.mp3")
const VAN_EXIT_AUDIO_0:AudioStream = preload("res://audio/characters/面包车/下车_[cut_1sec].mp3")
const VAN_EXIT_AUDIO_1:AudioStream = preload("res://audio/characters/面包车/下车_[cut_1sec] (1).mp3")
const VAN_EXIT_AUDIO_2:AudioStream = preload("res://audio/characters/面包车/下车_[cut_1sec] (2).mp3")
const VAN_EXIT_AUDIO_3:AudioStream = preload("res://audio/characters/面包车/下车_[cut_1sec] (3).mp3")
const VAN_EXIT_AUDIOS = [VAN_EXIT_AUDIO_0,VAN_EXIT_AUDIO_1,VAN_EXIT_AUDIO_2,VAN_EXIT_AUDIO_3]

@export_category("面包车")
@export_range(1.0,10.0,0.05) var ram_max_damage_multiplier:float = 8.3333333
@export_range(0.0,10.0,0.05) var ram_min_damage_multiplier:float = 2.0833333
# 兼容旧场景字段；V28 起冲撞不再眩晕，改为按速度击退。
@export_range(0.0,3.0,0.1) var ram_stun:float = 0.0
@export_range(18.0,60.0,1.0) var ram_hit_radius:float = 36.0
@export_range(0.0,120.0,2.0) var ram_knockback_min_distance:float = 8.0
@export_range(20.0,220.0,2.0) var ram_knockback_max_distance:float = 70.0
@export_range(50.0,900.0,10.0) var ram_knockback_min_speed:float = 120.0
@export_range(150.0,1400.0,10.0) var ram_knockback_max_speed:float = 560.0
@export_range(0.2,8.0,0.1) var ram_target_cooldown:float = 2.5
@export_range(1.0,3.0,0.05) var ram_knockback_speed_curve:float = 1.70
# V153：冲撞攻击范围不再由脚本参数控制。
# 车头/车尾范围直接由 scenes/characters/人物/面包车.tscn 中的两个 CollisionShape2D 决定，
# 用户可在 2D 编辑器里直接拖动、缩放碰撞箱。
@export_range(0.02,0.4,0.01) var cripple_ratio:float = 0.18

@export_category("倒车召唤")
@export_range(1.0,30.0,0.5) var summon_interval:float = 10.0
@export_range(20.0,90.0,1.0) var summon_rear_offset:float = 48.0
@export_range(0.0,40.0,1.0) var summon_side_jitter:float = 12.0
@export_range(14.0,40.0,1.0) var summon_clear_radius:float = 23.0
@export_range(20.0,70.0,1.0) var summon_side_clearance:float = 36.0
@export_range(0.1,1.5,0.05) var summon_collision_grace:float = 0.70
@export_range(0.1,1.0,0.05) var normal_minion_health_multiplier:float = 0.50
@export_range(-30.0,12.0,0.5) var summon_audio_volume_db:float = -3.0
@export_range(0,500,10) var summon_audio_min_gap_msec:int = 120
@export_range(0.30,1.50,0.05) var summon_reverse_duration:float = 0.78
@export_range(0.20,1.00,0.01) var summon_reverse_clear_ratio:float = 0.58

@export_category("Boss特殊化")
@export_range(200,5000,10) var boss_specialized_health:int = 1200
@export_range(0.5,1.0,0.01) var boss_summon_interval_ratio:float = 0.82
@export_range(1.0,2.5,0.01) var boss_mobility_multiplier:float = 1.12
@export_range(1.0,1.5,0.01) var boss_speed_multiplier:float = 1.05
@export_range(0.1,0.9,0.01) var boss_all_minions_health_ratio:float = 0.50

@export_category("车辆行动")
@export_range(20.0,360.0,5.0) var drive_acceleration:float = 165.0
@export_range(20.0,480.0,5.0) var drive_brake:float = 280.0
@export_range(0.2,1.0,0.01) var reverse_speed_ratio:float = 0.48
@export_range(0.2,2.0,0.05) var reverse_duration:float = 0.55
@export_range(0.2,3.0,0.05) var reverse_rearm_delay:float = 0.78
@export_range(0.2,4.0,0.05) var steering_rate:float = 2.25
@export_range(0.5,16.0,0.1) var steering_input_smoothing:float = 8.8
@export_range(0.5,16.0,0.1) var steering_acceleration:float = 8.0
@export_range(0.5,16.0,0.1) var throttle_smoothing:float = 6.0
@export_range(0.0,1.0,0.05) var minimum_steering_factor:float = 0.90
@export_range(0.0,1.0,0.05) var ram_min_speed_ratio:float = 0.42
@export_range(0.1,1.0,0.05) var rear_ram_damage_ratio:float = 0.55
@export_range(0.0,1.0,0.01) var target_lead_seconds:float = 0.04
@export_range(0.1,1.2,0.05) var target_lead_max_seconds:float = 0.26

@export_group("车辆巡航")
@export_range(0.1,1.0,0.05) var roam_speed_ratio:float = 0.58
@export_range(30.0,220.0,5.0) var roam_wall_margin:float = 82.0
@export_range(30.0,180.0,5.0) var roam_reach_distance:float = 58.0
@export_range(1.0,12.0,0.25) var roam_repick_seconds:float = 4.5

@export_group("车辆避墙")
# ball.tscn 的角色实体在 layer 2，地图/墙体在 layer 1；探测只看墙，避免把目标当障碍。
@export_flags_2d_physics var wall_probe_mask:int = 1
@export_range(30.0,220.0,5.0) var wall_probe_min_distance:float = 58.0
@export_range(30.0,280.0,5.0) var wall_probe_max_distance:float = 128.0
@export_range(10.0,80.0,1.0) var wall_probe_side_angle_degrees:float = 34.0
@export_range(30.0,180.0,5.0) var wall_safe_margin:float = 88.0
@export_range(0.5,5.0,0.1) var wall_avoidance_strength:float = 2.35
@export_range(0.1,1.0,0.05) var blocked_speed_ratio:float = 0.22
@export_range(0.25,2.0,0.05) var wall_escape_min_time:float = 0.72
@export_range(0.4,3.0,0.05) var wall_escape_max_time:float = 1.55
@export_range(30.0,180.0,5.0) var wall_escape_min_distance:float = 82.0
@export_range(0.3,2.5,0.05) var wall_recovery_duration:float = 1.15
@export_range(10.0,80.0,1.0) var wall_recovery_side_angle_degrees:float = 38.0
@export_range(0.5,4.0,0.1) var wall_escape_steering_multiplier:float = 2.15
@export_range(0.0,8.0,0.25) var wall_escape_probe_clearance:float = 2.0
@export_range(8.0,32.0,1.0) var vehicle_probe_front_offset:float = 21.0
@export_range(2.0,18.0,1.0) var vehicle_probe_half_width:float = 7.0
@export_range(0.55,1.0,0.01) var vehicle_wall_body_scale:float = 0.96
@export_range(0.1,1.0,0.05) var character_collision_sync_interval:float = 0.30

@export_group("智能驾驶")
@export_range(50.0,220.0,5.0) var smart_lookahead_min:float = 82.0
@export_range(80.0,300.0,5.0) var smart_lookahead_max:float = 168.0
@export_range(0.2,2.0,0.05) var wall_follow_min_time:float = 0.85
@export_range(0.1,1.0,0.05) var wall_follow_clear_time:float = 0.32
@export_range(0.1,1.2,0.05) var stuck_trigger_time:float = 0.30
@export_range(0.05,0.8,0.05) var stuck_motion_ratio:float = 0.22

@export_group("智能追击")
@export_range(35.0,150.0,1.0) var hard_turn_angle_degrees:float = 76.0
@export_range(0.05,0.55,0.01) var hard_turn_speed_ratio:float = 0.14
@export_range(1.0,3.0,0.05) var low_speed_turn_boost:float = 2.10
@export_range(1.0,2.5,0.05) var hard_turn_yaw_boost:float = 1.35
@export_range(1.0,2.0,0.05) var close_target_steering_boost:float = 1.45
@export_range(50.0,360.0,5.0) var close_target_distance:float = 180.0
@export_range(0.2,1.0,0.01) var ai_direct_clear_ratio:float = 0.72
@export_range(0.2,1.0,0.01) var ai_wall_follow_speed_ratio:float = 0.52
@export_range(40.0,240.0,5.0) var ai_close_reverse_distance:float = 145.0
@export_range(90.0,175.0,1.0) var ai_close_reverse_angle_degrees:float = 132.0
@export_range(0.2,1.0,0.01) var ai_reverse_clear_ratio:float = 0.78

@export_group("多单位驾驶")
@export_range(0.2,3.0,0.05) var multi_target_lock_seconds:float = 1.15
@export_range(0.2,1.0,0.01) var multi_target_switch_ratio:float = 0.68
@export_range(80.0,420.0,5.0) var crowd_ram_radius:float = 220.0
@export_range(2,8,1) var crowd_ram_enemy_threshold:int = 2
@export_range(0.05,0.8,0.01) var crowd_ram_pass_grace:float = 0.34
@export_range(0.05,0.50,0.01) var enemy_blocked_reverse_delay:float = 0.14
@export_range(0.10,0.80,0.01) var enemy_blocked_motion_ratio:float = 0.38
@export_range(0.10,0.90,0.01) var enemy_wall_probe_ratio:float = 0.42

@export_group("撞击后退")
@export_range(0.2,1.5,0.05) var ram_reverse_duration:float = 0.48
@export_range(0.2,1.0,0.05) var ram_reverse_speed_ratio:float = 0.52

@export_group("车辆音效")
# 三段素材原始响度差异很大，这里只做播放增益补偿，不改音频文件本身。
@export_range(-30.0,12.0,0.5) var forward_audio_volume_db:float = 7.0
@export_range(-30.0,18.0,0.5) var reverse_audio_volume_db:float = 2.5
@export_range(-30.0,12.0,0.5) var wall_audio_volume_db:float = -4.0
@export_range(100.0,1500.0,25.0) var vehicle_audio_max_distance:float = 720.0
@export_range(0.0,40.0,1.0) var engine_audio_min_speed:float = 8.0

var _crippled:bool = false
var _ram_last_hit:Dictionary = {}
var _summon_elapsed:float = 0.0
var _last_summon_audio_msec:int = -100000
var _boss_specialized:bool = false
var _boss_half_health_wave_triggered:bool = false
var _boss_half_health_pending:Array[int] = []
var _boss_half_health_spawn_retry_queued:bool = false
var _boss_half_health_spawn_serial:int = 0

var _vehicle_heading:float = 0.0
var _vehicle_speed:float = 0.0
var _vehicle_turn_rate:float = 0.0
var _smoothed_drive_direction:Vector2 = Vector2.RIGHT
var _smoothed_speed_target:float = 0.0
var _visual_face_left:bool = false
var _reverse_left:float = 0.0
var _reverse_rearm_left:float = 0.0
var _graphics_base_rotation:float = 0.0
var _wall_escape_left:float = 0.0
var _wall_escape_elapsed:float = 0.0
var _wall_escape_heading:float = 0.0
var _wall_escape_normal:Vector2 = Vector2.ZERO
var _wall_escape_start_position:Vector2 = Vector2.ZERO
var _wall_recovery_left:float = 0.0
var _wall_recovery_direction:Vector2 = Vector2.ZERO
var _ram_reverse_left:float = 0.0
var _wall_follow_active:bool = false
var _wall_follow_direction:Vector2 = Vector2.ZERO
var _wall_follow_elapsed:float = 0.0
var _wall_follow_clear_elapsed:float = 0.0
var _avoidance_side_sign:float = 0.0
var _stuck_elapsed:float = 0.0
var _character_collision_sync_left:float = 0.0
var _player_control_was_active:bool = false
var _friendly_collision_refs:Dictionary = {}
var _vehicle_target_lock_ref:WeakRef = null
var _vehicle_target_lock_left:float = 0.0
var _enemy_blocked_elapsed:float = 0.0
var _crowd_pass_until_msec:Dictionary = {}
var _summon_reverse_requested:bool = false

var _roam_point:Vector2 = Vector2.ZERO
var _roam_point_valid:bool = false
var _roam_repick_left:float = 0.0

var _forward_audio_player:AudioStreamPlayer2D = null
var _reverse_audio_player:AudioStreamPlayer2D = null
var _forward_loop_stream:AudioStreamMP3 = null
var _reverse_loop_stream:AudioStreamMP3 = null
var _engine_audio_mode:int = 0 # 0=停，1=前进，-1=倒车
var _vehicle_body_collision:CollisionShape2D = null
var _vehicle_hurt_collision:CollisionShape2D = null
var _vehicle_body_collision_base_position:Vector2 = Vector2.ZERO
var _vehicle_body_collision_base_rotation:float = 0.0
var _vehicle_hurt_collision_base_position:Vector2 = Vector2.ZERO
var _vehicle_hurt_collision_base_rotation:float = 0.0
var _ram_attack_root:Node2D = null
var _ram_front_collision:CollisionShape2D = null
var _ram_rear_collision:CollisionShape2D = null
var _ram_box_query:PhysicsShapeQueryParameters2D = null


func get_health_threshold_values() -> PackedFloat32Array:
	var values := PackedFloat32Array()
	# V142：普通面包车不显示任何生命阈值黑线。
	# 只有 Boss 特殊化继续复用现有 HealthBar 的 50% 黑线。
	if _boss_specialized or bool(get_meta("training_boss_specialized",false)):
		values.append(float(Max_health) * boss_all_minions_health_ratio)
	return values


func _ready() -> void:
	Can_Attack = false
	Can_Skill = false
	Has_Collision_Damage = false
	Health_Restore = 0
	# 面包车是俯视角车辆，所有物理碰撞都按墙面处理，避免 Grounded 模式的地板/墙分类干扰转向。
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	safe_margin = 0.04
	# 车辆不使用普通角色的“脚步”碰撞音效。真正撞人仍由受击/冲撞伤害播放命中声。
	Collide_Audio_Node = ""
	super._ready()
	# V134：面包车恢复真实车身碰撞。layer 1=地图/墙，layer 2=角色；
	# 车辆会真正与人物发生 CharacterBody2D 接触，而不再全局添加人物 collision exception。
	# 智能避墙的 test_move 会在 _body_clearance_ratio() 临时只使用 wall_probe_mask，
	# 因此“能撞到人物”不会让驾驶 AI 把敌人误判成墙并主动绕开。
	collision_mask = wall_probe_mask | 2
	max_slides = 8
	_vehicle_body_collision = get_node_or_null("CollisionShape2D") as CollisionShape2D
	_vehicle_hurt_collision = get_node_or_null("hurtbox/CollisionShape2D") as CollisionShape2D
	if _vehicle_body_collision != null:
		_vehicle_body_collision_base_position = _vehicle_body_collision.position
		_vehicle_body_collision_base_rotation = _vehicle_body_collision.rotation
		_vehicle_body_collision.scale *= Vector2(vehicle_wall_body_scale,vehicle_wall_body_scale)
	if _vehicle_hurt_collision != null:
		_vehicle_hurt_collision_base_position = _vehicle_hurt_collision.position
		_vehicle_hurt_collision_base_rotation = _vehicle_hurt_collision.rotation
	# V153：攻击命中范围直接读取场景里的两个 CollisionShape2D。
	# 它们只作为攻击检测形状，不参与车辆实体撞墙，因此可以在 2D 编辑器里自由调整大小/位置。
	_ram_attack_root = get_node_or_null("冲撞攻击碰撞") as Node2D
	_ram_front_collision = get_node_or_null("冲撞攻击碰撞/车头攻击区域/车头碰撞箱") as CollisionShape2D
	_ram_rear_collision = get_node_or_null("冲撞攻击碰撞/车尾攻击区域/车尾碰撞箱") as CollisionShape2D
	_ram_box_query = PhysicsShapeQueryParameters2D.new()
	_ram_box_query.collision_mask = 2
	_ram_box_query.collide_with_bodies = true
	_ram_box_query.collide_with_areas = false
	_ram_box_query.exclude = [get_rid()]
	if self_hitbox != null:
		self_hitbox.monitoring = false
	if graphics != null:
		_graphics_base_rotation = graphics.rotation
	_vehicle_heading = 0.0
	_vehicle_speed = 0.0
	_vehicle_turn_rate = 0.0
	_smoothed_drive_direction = Vector2.RIGHT
	_smoothed_speed_target = 0.0
	_visual_face_left = false
	_roam_repick_left = 0.0
	_summon_elapsed = 0.0
	_setup_vehicle_audio()
	_update_vehicle_visual()


func _physics_process(_delta:float) -> void:
	if not is_multiplayer_authority() or health <= 0:
		return

	# V151：召唤仍然保持“真实倒车后从车尾下人”，但冷却满以后不再等待 AI
	# 碰巧因为撞人/墙体进入倒档。自动驾驶会主动请求一次短倒车；这样 V150 多人
	# 连续冲撞不倒车时，召唤系统也不会被间接彻底关闭。
	_summon_elapsed += _delta
	var summon_due:bool = _summon_elapsed >= summon_interval
	if summon_due and not is_player_controlled():
		if _is_reverse_gear_active() and _vehicle_speed <= -maxf(engine_audio_min_speed,12.0):
			if _spawn_random_van_minion():
				_summon_elapsed = 0.0
				_summon_reverse_requested = false
		elif not is_player_controlled() and not _summon_reverse_requested and _wall_escape_left <= 0.0 and _ram_reverse_left <= 0.0:
			var rear_direction:Vector2 = -Vector2.RIGHT.rotated(_vehicle_heading)
			var rear_check_distance:float = maxf(summon_rear_offset + 44.0,88.0)
			# 这里只检查地图墙；人物不参与路径规划。后方有基本空间才主动挂倒档，
			# 避免为了召唤自己倒进墙里。
			if _body_clearance_ratio(rear_direction,rear_check_distance) >= summon_reverse_clear_ratio:
				_summon_reverse_requested = true
				_begin_reverse(maxf(summon_reverse_duration,reverse_duration * 0.90))
	if _summon_reverse_requested and not _is_reverse_gear_active() and _vehicle_speed >= -engine_audio_min_speed:
		# 倒车阶段结束但仍未找到合法出生点时允许下一次重新请求，不丢失已满冷却。
		_summon_reverse_requested = false

	# 手控时召唤只响应玩家点击，不能仅因玩家倒车就自动下人。

	var ratio:float = float(health) / maxf(float(Max_health),1.0)
	# V135：物理帧保留兜底检查，但真正的首次触发也会在 on_actual_health_damage_received()
	# 中立即登记，避免伤害时序/暂停状态让半血波次漏掉。
	_check_boss_half_health_wave_trigger()
	_queue_boss_half_health_wave_attempt()
	if not _crippled and ratio <= cripple_ratio:
		_crippled = true
		Speed = 44.0
		default_properties["Speed"] = Speed
		_vehicle_speed = clampf(_vehicle_speed,-Speed * reverse_speed_ratio,Speed)
	# V141：冲撞统一在 tick_physics() 的真实移动之后，用扫掠矩形 + slide collision 结算。
	# 不再在这里额外做第二次范围查询，避免大规模战斗下每台面包车每物理帧重复查询人物层。


func controlled_attack_action() -> void:
	# 左键：冷却已满且真实倒车达到速度要求时，从车尾下人。
	if not is_player_controlled() or not is_multiplayer_authority() or health <= 0 or not is_combat_runtime_active():
		return
	if _summon_elapsed < summon_interval or not _is_reverse_gear_active() or _vehicle_speed > -maxf(engine_audio_min_speed,12.0):
		return
	if _spawn_random_van_minion():
		_summon_elapsed = 0.0
		_summon_reverse_requested = false


# 面包车完全绕过普通角色的 direction * Speed 追踪。
# 无敌人时巡航；有敌人时追撞；所有情况下都先做地图边缘和前方墙体避障。
func tick_physics(state:State,delta:float) -> void:
	if not is_multiplayer_authority():
		return
	if state == State.Die or health <= 0:
		_vehicle_speed = 0.0
		velocity = Vector2.ZERO
		_update_engine_audio()
		return

	if dizziness:
		_vehicle_speed = move_toward(_vehicle_speed,0.0,drive_brake * delta)
		stand(delta)
		_update_engine_audio()
		return

	if not Game.Game_Settings.Ball_Can_Move:
		_vehicle_speed = 0.0
		stand(delta)
		_update_engine_audio()
		return

	# V150：车身实体碰撞只需要拦敌人和墙。队友（包括自己下车的小弟）不应成为
	# 自动驾驶的动态路障，否则只要场上多一个同队单位，move_and_slide() 就会反复改写
	# 车辆速度/主碰撞，表现成原地修正、倒车和卡住。定期同步同队 collision exception。
	_character_collision_sync_left = maxf(_character_collision_sync_left - delta,0.0)
	if _character_collision_sync_left <= 0.0:
		_character_collision_sync_left = maxf(character_collision_sync_interval,0.05)
		_sync_friendly_collision_exceptions()
	_vehicle_target_lock_left = maxf(_vehicle_target_lock_left - delta,0.0)

	# V144：面包车覆写了公共 ball.tick_physics()，因此不能依赖 ball.move() 自动应用
	# player_control_direction。玩家接管时必须完全绕过追敌/巡航/避墙 AI，只把 WASD
	# 解释成车辆油门、倒车和方向盘；退出控制后才恢复自动驾驶。
	if is_player_controlled():
		_tick_player_controlled_vehicle(delta)
		return
	elif _player_control_was_active:
		_player_control_was_active = false
		_vehicle_turn_rate = 0.0
		_smoothed_drive_direction = Vector2.RIGHT.rotated(_vehicle_heading)
		_smoothed_speed_target = _vehicle_speed
		_wall_follow_active = false
		_wall_follow_elapsed = 0.0
		_wall_follow_clear_elapsed = 0.0
		_stuck_elapsed = 0.0

	_reverse_left = maxf(_reverse_left - delta,0.0)
	_reverse_rearm_left = maxf(_reverse_rearm_left - delta,0.0)
	_ram_reverse_left = maxf(_ram_reverse_left - delta,0.0)
	_wall_recovery_left = maxf(_wall_recovery_left - delta,0.0)
	_roam_repick_left = maxf(_roam_repick_left - delta,0.0)
	if _wall_escape_left > 0.0:
		_wall_escape_left = maxf(_wall_escape_left - delta,0.0)
		_wall_escape_elapsed += delta
	if _wall_follow_active:
		_wall_follow_elapsed += delta

	var map_rect:Rect2 = TOOLS.map_rect(self)
	var target:ball = _vehicle_target()
	var has_target:bool = target != null and is_instance_valid(target)
	var goal_position:Vector2

	if has_target:
		goal_position = combat_target_position(target)
		# V147：只做轻量预测。远处稍微看未来，贴脸几乎直接追当前位置，
		# 避免旧版 0.6s 级预测让车不断追着目标未来点画圈。
		var target_distance:float = global_position.distance_to(goal_position)
		var lead_weight:float = clampf((target_distance - 120.0) / 420.0,0.0,1.0)
		var lead_time:float = lerpf(target_lead_seconds,target_lead_max_seconds,lead_weight)
		goal_position += combat_target_velocity(target) * lead_time
	else:
		goal_position = _roam_goal(map_rect)

	var forward:Vector2 = Vector2.RIGHT.rotated(_vehicle_heading)
	var to_goal:Vector2 = goal_position - global_position
	var goal_direction:Vector2 = forward
	if to_goal.length_squared() > 0.0001:
		goal_direction = to_goal.normalized()

	# V147：驾驶决策做减法。正常追击只认目标方向；只有“目标直线路径确实被墙挡住”
	# 才进入沿墙状态，而且选定绕行侧后至少坚持 wall_follow_min_time，避免每帧左右改主意。
	if has_target and _wall_escape_left <= 0.0 and _wall_recovery_left <= 0.0:
		_update_wall_follow(goal_position,goal_direction,map_rect,delta)
	else:
		_wall_follow_active = false
		_wall_follow_elapsed = 0.0
		_wall_follow_clear_elapsed = 0.0

	var desired_direction:Vector2 = goal_direction
	if _wall_recovery_left > 0.0 and _wall_recovery_direction.length_squared() > 0.0001:
		desired_direction = _wall_recovery_direction.normalized()
	elif _wall_follow_active and _wall_follow_direction.length_squared() > 0.0001:
		desired_direction = _wall_follow_direction.normalized()
	else:
		# 未进入绕墙状态时只叠加温和的边界/前保险杠排斥，不再运行旧版 21 个
		# 候选方向扫描。这样目标在移动时方向不会每帧跳到另一个候选角。
		var avoidance_data:Dictionary = _wall_avoidance(forward,map_rect)
		var avoidance:Vector2 = avoidance_data.get("vector",Vector2.ZERO)
		if avoidance.length_squared() > 0.0001:
			var avoidance_weight:float = clampf(avoidance.length() * 0.30,0.0,0.72)
			desired_direction = (desired_direction + avoidance.normalized() * avoidance_weight).normalized()

	if _wall_escape_left > 0.0:
		_smoothed_drive_direction = Vector2.RIGHT.rotated(_wall_escape_heading)
	else:
		var steer_weight:float = 1.0 - exp(-steering_input_smoothing * delta)
		if _smoothed_drive_direction.length_squared() <= 0.0001:
			_smoothed_drive_direction = desired_direction
		else:
			_smoothed_drive_direction = _smoothed_drive_direction.lerp(desired_direction,steer_weight).normalized()

	var desired_heading:float = _smoothed_drive_direction.angle()
	if _wall_escape_left > 0.0:
		desired_heading = _wall_escape_heading
	var steering_error:float = wrapf(desired_heading - _vehicle_heading,-PI,PI)
	var abs_error:float = absf(steering_error)

	# V147：不再因为“目标在车后”就频繁倒车。只有目标很近、角度明确在车尾，
	# 且真实车身向后有足够净空时才做一次短倒车攻击；远处目标一律减速转头。
	if (
		has_target
		and _reverse_left <= 0.0
		and _ram_reverse_left <= 0.0
		and _wall_escape_left <= 0.0
		and _wall_recovery_left <= 0.0
		and _reverse_rearm_left <= 0.0
		and to_goal.length() <= ai_close_reverse_distance
		and abs_error >= deg_to_rad(ai_close_reverse_angle_degrees)
		and _body_clearance_ratio(-forward,maxf(ai_close_reverse_distance * 0.70,72.0)) >= ai_reverse_clear_ratio
	):
		_begin_reverse(reverse_duration * 0.82)

	var desired_speed:float
	if _wall_escape_left > 0.0:
		desired_speed = -Speed * reverse_speed_ratio
	elif _ram_reverse_left > 0.0:
		desired_speed = -Speed * ram_reverse_speed_ratio
	elif _reverse_left > 0.0:
		desired_speed = -Speed * reverse_speed_ratio
	else:
		var cruise_ratio:float = 1.0 if has_target else roam_speed_ratio
		# 方向误差直接决定油门：朝向越偏，越先减速转正。超过约 90° 后只保留
		# 很小爬行速度，因此不会再带着大速度绕目标画圆。
		var turn_ratio:float = clampf(abs_error / PI,0.0,1.0)
		var turn_speed_factor:float = lerpf(1.0,hard_turn_speed_ratio,pow(turn_ratio,1.20))
		if abs_error >= deg_to_rad(hard_turn_angle_degrees):
			turn_speed_factor = minf(turn_speed_factor,lerpf(hard_turn_speed_ratio,0.34,1.0 - turn_ratio))

		# 只检查当前真正想开的方向能走多远，而不是同时比较 21 条互相打架的候选路线。
		var lookahead:float = lerpf(smart_lookahead_min,smart_lookahead_max,clampf(absf(_vehicle_speed) / maxf(Speed,1.0),0.0,1.0))
		var ray_clear:float = float(_probe_wall(desired_direction,lookahead).get("clear_ratio",1.0))
		var body_clear:float = _body_clearance_ratio(desired_direction,lookahead)
		var clearance:float = minf(ray_clear,body_clear)
		var clearance_factor:float = lerpf(blocked_speed_ratio,1.0,clampf(clearance,0.0,1.0))
		desired_speed = Speed * cruise_ratio * minf(turn_speed_factor,clearance_factor)
		if _wall_follow_active:
			desired_speed = minf(desired_speed,Speed * ai_wall_follow_speed_ratio)
		if _wall_recovery_left > 0.0:
			desired_speed = minf(desired_speed,Speed * 0.46)

	var throttle_weight:float = 1.0 - exp(-throttle_smoothing * delta)
	_smoothed_speed_target = lerpf(_smoothed_speed_target,desired_speed,throttle_weight)

	var changing_gear:bool = (
		absf(_vehicle_speed) > 0.01
		and absf(_smoothed_speed_target) > 0.01
		and sign(_vehicle_speed) != sign(_smoothed_speed_target)
	)
	var speed_step:float = drive_brake if changing_gear or absf(_smoothed_speed_target) < absf(_vehicle_speed) else drive_acceleration
	_vehicle_speed = move_toward(_vehicle_speed,_smoothed_speed_target,speed_step * delta)

	# V135 智能转向：低速和大角度追击时给更强转向权，解决“目标已经在侧后方，
	# 面包车还带着高速度画大圆”的迟钝感。普通战术倒车也允许转向：此时不是让
	# “车头朝目标”，而是让“车尾朝目标”，所以把期望车头方向翻转 180°；
	# 撞人后的 ram_reverse 仍保持直退，避免刚撞上就横摆。
	var steering_error_for_motion:float = steering_error
	if _reverse_left > 0.0 and _ram_reverse_left <= 0.0 and _wall_escape_left <= 0.0:
		var reverse_desired_heading:float = wrapf(desired_heading + PI,-PI,PI)
		steering_error_for_motion = wrapf(reverse_desired_heading - _vehicle_heading,-PI,PI)
	if _ram_reverse_left <= 0.0 or _wall_escape_left > 0.0:
		var speed_ratio:float = clampf(absf(_vehicle_speed) / maxf(Speed,1.0),0.0,1.0)
		var steering_factor:float = lerpf(minimum_steering_factor,1.0,speed_ratio)
		var steering_multiplier:float = wall_escape_steering_multiplier if _wall_escape_left > 0.0 else 1.0
		var turn_boost:float = lerpf(low_speed_turn_boost,1.0,speed_ratio)
		if absf(steering_error_for_motion) >= deg_to_rad(hard_turn_angle_degrees):
			turn_boost *= hard_turn_yaw_boost
		if has_target and global_position.distance_to(goal_position) <= close_target_distance:
			turn_boost *= close_target_steering_boost
		var max_yaw_rate:float = steering_rate * steering_factor * steering_multiplier * turn_boost
		var target_yaw_rate:float = clampf(steering_error_for_motion * 3.55,-max_yaw_rate,max_yaw_rate)
		_vehicle_turn_rate = move_toward(
			_vehicle_turn_rate,
			target_yaw_rate,
			steering_acceleration * steering_multiplier * turn_boost * delta
		)
		_vehicle_heading = wrapf(_vehicle_heading + _vehicle_turn_rate * delta,-PI,PI)
	else:
		_vehicle_turn_rate = move_toward(_vehicle_turn_rate,0.0,steering_acceleration * 1.35 * delta)

	forward = Vector2.RIGHT.rotated(_vehicle_heading)
	direction = forward if _vehicle_speed >= 0.0 else -forward
	_sync_vehicle_collision_orientation()
	_update_vehicle_visual()

	var drive_velocity:Vector2 = forward * _vehicle_speed
	if _wall_escape_left > 0.0 and _wall_escape_normal.length_squared() > 0.0001:
		# 碰墙后的前几帧强制给一个“离墙法线”分量，避免车头尚未来得及转正时继续被 safe margin 卡住。
		var reverse_direction:Vector2 = -forward
		var escape_blend:float = 1.0 - clampf(_wall_escape_elapsed / maxf(wall_escape_min_time * 0.60,0.08),0.0,1.0)
		var guaranteed_escape:Vector2 = (reverse_direction * (1.0 - escape_blend) + _wall_escape_normal * escape_blend).normalized()
		drive_velocity = guaranteed_escape * absf(_vehicle_speed)
	velocity = drive_velocity + Repel
	_last_requested_velocity = velocity
	if velocity.length_squared() <= MOTION_EPSILON_SQ:
		velocity = Vector2.ZERO
		Repel = Vector2.ZERO
		_update_engine_audio()
		return

	var requested_velocity:Vector2 = velocity
	var position_before_move:Vector2 = global_position
	move_with_body_slide(delta)
	var actual_displacement:Vector2 = global_position - position_before_move
	var actual_move_distance:float = actual_displacement.length()
	# V141 保留：按真实车身从上一位置扫到当前位置，补足车侧/车角擦过时的离散碰撞漏判。
	_process_ram_swept_contacts(position_before_move,global_position,absf(_vehicle_speed))
	# 冲撞伤害优先读取这一帧真实发生的全部 slide collision。这样即使人物碰撞
	# 不是“主碰撞”（例如同一帧还擦到墙），也不会漏掉已经真实撞上的目标。
	_process_physical_contact_hits()
	_process_wall_hit_bursts_from_slide_collisions(absf(_vehicle_speed))
	# V151：人物实体把车堵住时，解卡不能依赖“这一帧是否成功造成冲撞伤害”。
	# damage cooldown 或低速都可能让伤害函数返回 false，但 CharacterBody2D 仍然会被人顶停。
	_resolve_enemy_body_blocking(delta,actual_displacement,requested_velocity)

	var collision:KinematicCollision2D = _select_primary_slide_collision(requested_velocity)
	if collision != null:
		_handle_vehicle_collision(collision,requested_velocity)
	else:
		_update_stuck_recovery(delta,actual_move_distance,requested_velocity,map_rect)

	if collision == null and _wall_escape_left > 0.0 and _wall_escape_elapsed >= wall_escape_min_time:
		# 必须真的退开足够距离才结束脱困。只看“探针刚刚清空”会造成退几像素就重新追人，
		# 于是又撞回同一堵墙。
		var escaped_distance:float = global_position.distance_to(_wall_escape_start_position)
		var escape_probe:Dictionary = _probe_wall(-Vector2.RIGHT.rotated(_vehicle_heading),maxf(wall_probe_min_distance * 0.45,wall_escape_probe_clearance))
		if escaped_distance >= wall_escape_min_distance and not bool(escape_probe.get("hit",false)):
			_end_wall_escape()

	# 超时也要结束倒车阶段，但之后仍进入离墙恢复路线，不会立刻回头撞墙。
	if _wall_escape_left <= 0.0 and _wall_escape_elapsed > 0.0 and _wall_escape_normal.length_squared() > 0.0001:
		_end_wall_escape()

	_update_engine_audio()
	Repel = Vector2.ZERO


# V141：车体碰撞形状必须跟着车辆 heading 旋转。旧版只旋转 Graphics，
# 所以视觉上斜着开的车仍拿水平矩形做实体碰撞，车角擦过敌人时很容易出现“看起来撞到了、物理却没碰到”。
func _sync_vehicle_collision_orientation() -> void:
	if _vehicle_body_collision != null and is_instance_valid(_vehicle_body_collision):
		_vehicle_body_collision.position = _vehicle_body_collision_base_position.rotated(_vehicle_heading)
		_vehicle_body_collision.rotation = _vehicle_body_collision_base_rotation + _vehicle_heading
	if _vehicle_hurt_collision != null and is_instance_valid(_vehicle_hurt_collision):
		_vehicle_hurt_collision.position = _vehicle_hurt_collision_base_position.rotated(_vehicle_heading)
		_vehicle_hurt_collision.rotation = _vehicle_hurt_collision_base_rotation + _vehicle_heading
	if _ram_attack_root != null and is_instance_valid(_ram_attack_root):
		_ram_attack_root.rotation = _vehicle_heading


# V153：攻击判定完全以场景中的“车头碰撞箱 / 车尾碰撞箱”为准。
# 真实车身 CollisionShape2D 只负责实体撞墙/堵人，不再决定攻击范围。
func _process_ram_swept_contacts(from_position:Vector2,to_position:Vector2,impact_speed:float) -> void:
	if _crippled or _ram_box_query == null:
		return
	var minimum_ram_speed:float = maxf(Speed * ram_min_speed_ratio,35.0)
	if absf(impact_speed) < minimum_ram_speed or absf(_vehicle_speed) < minimum_ram_speed:
		return

	var motion:Vector2 = to_position - from_position
	# 当前帧位移通常很短，但仍额外检查“上一位置 / 中点 / 当前位置”，
	# 避免高速时从薄目标旁边跨过去。碰撞箱本身的大小与位置仍完全来自场景。
	if _vehicle_speed >= 0.0:
		_query_ram_collision_box(_ram_front_collision,impact_speed,1,motion)
		_query_ram_collision_box(_ram_rear_collision,impact_speed,-1,motion)
	else:
		_query_ram_collision_box(_ram_rear_collision,impact_speed,-1,motion)
		_query_ram_collision_box(_ram_front_collision,impact_speed,1,motion)


func _query_ram_collision_box(collision:CollisionShape2D,impact_speed:float,hit_zone:int,motion:Vector2) -> void:
	if collision == null or not is_instance_valid(collision) or collision.disabled or collision.shape == null:
		return
	_ram_box_query.shape = collision.shape
	var current_transform:Transform2D = collision.global_transform
	var sample_offsets:Array[Vector2] = [motion, motion * 0.5, Vector2.ZERO]
	for offset:Vector2 in sample_offsets:
		var sample_transform:Transform2D = current_transform
		sample_transform.origin -= offset
		_ram_box_query.transform = sample_transform
		var hits:Array[Dictionary] = get_world_2d().direct_space_state.intersect_shape(_ram_box_query,64)
		for hit:Dictionary in hits:
			var raw:Variant = hit.get("collider")
			if raw is ball:
				_try_apply_ram_to_target(raw as ball,impact_speed,hit_zone)


# V144：玩家直接控制面包车。
# W/S = 前进/倒车，A/D = 转向；进入控制的第一帧立即清空全部 AI 脱困/倒车状态并停车。
func _tick_player_controlled_vehicle(delta:float) -> void:
	if not _player_control_was_active:
		_player_control_was_active = true
		_vehicle_speed = 0.0
		_vehicle_turn_rate = 0.0
		_smoothed_speed_target = 0.0
		_reverse_left = 0.0
		_reverse_rearm_left = 0.0
		_ram_reverse_left = 0.0
		_wall_escape_left = 0.0
		_wall_escape_elapsed = 0.0
		_wall_escape_normal = Vector2.ZERO
		_wall_recovery_left = 0.0
		_wall_recovery_direction = Vector2.ZERO
		_wall_follow_active = false
		_wall_follow_elapsed = 0.0
		_wall_follow_clear_elapsed = 0.0
		_stuck_elapsed = 0.0
		_vehicle_target_lock_ref = null
		_vehicle_target_lock_left = 0.0
		_enemy_blocked_elapsed = 0.0
		Repel = Vector2.ZERO

	var input_dir:Vector2 = player_control_direction
	# Game 会把对角 WASD 归一化；车辆控制按“按键是否按下”取满轴，避免 W+A 只有 0.707 油门。
	var throttle:float = signf(-input_dir.y) if absf(input_dir.y) > 0.01 else 0.0
	var steer_input:float = signf(input_dir.x) if absf(input_dir.x) > 0.01 else 0.0

	var desired_speed:float = 0.0
	if throttle > 0.01:
		desired_speed = Speed * throttle
	elif throttle < -0.01:
		desired_speed = Speed * reverse_speed_ratio * throttle

	var changing_gear:bool = (
		absf(_vehicle_speed) > 0.01
		and absf(desired_speed) > 0.01
		and sign(_vehicle_speed) != sign(desired_speed)
	)
	var speed_step:float = drive_acceleration
	if changing_gear or absf(desired_speed) < absf(_vehicle_speed):
		speed_step = drive_brake * (1.35 if is_zero_approx(throttle) else 1.0)
	_vehicle_speed = move_toward(_vehicle_speed,desired_speed,speed_step * delta)
	if is_zero_approx(throttle) and absf(_vehicle_speed) <= 2.0:
		_vehicle_speed = 0.0

	var speed_ratio:float = clampf(absf(_vehicle_speed) / maxf(Speed,1.0),0.0,1.0)
	var steering_factor:float = lerpf(minimum_steering_factor,1.0,speed_ratio)
	var max_yaw_rate:float = steering_rate * steering_factor * lerpf(low_speed_turn_boost,1.0,speed_ratio)
	var reverse_steer_sign:float = -1.0 if _vehicle_speed < -0.01 else 1.0
	var target_yaw_rate:float = steer_input * max_yaw_rate * reverse_steer_sign
	_vehicle_turn_rate = move_toward(
		_vehicle_turn_rate,
		target_yaw_rate,
		steering_acceleration * maxf(low_speed_turn_boost,1.0) * delta
	)
	if absf(steer_input) <= 0.01:
		_vehicle_turn_rate = move_toward(_vehicle_turn_rate,0.0,steering_acceleration * 1.6 * delta)
	_vehicle_heading = wrapf(_vehicle_heading + _vehicle_turn_rate * delta,-PI,PI)

	var forward:Vector2 = Vector2.RIGHT.rotated(_vehicle_heading)
	direction = forward if _vehicle_speed >= 0.0 else -forward
	_sync_vehicle_collision_orientation()
	_update_vehicle_visual()

	velocity = forward * _vehicle_speed + Repel
	_last_requested_velocity = velocity
	if velocity.length_squared() <= MOTION_EPSILON_SQ:
		velocity = Vector2.ZERO
		Repel = Vector2.ZERO
		_update_engine_audio()
		return

	var position_before_move:Vector2 = global_position
	move_with_body_slide(delta)
	_process_ram_swept_contacts(position_before_move,global_position,absf(_vehicle_speed))
	_process_physical_contact_hits()
	_process_wall_hit_bursts_from_slide_collisions(absf(_vehicle_speed))

	# 手动模式不启动 wall_escape / 自动倒车 / 自动重新寻路；碰撞只由 CharacterBody2D 正常处理。
	_update_engine_audio()
	Repel = Vector2.ZERO


# move_and_slide() 一帧可能同时产生多次碰撞，而主碰撞不一定是人物。
# 逐个扫描真实物理接触，命中第一个可受伤敌人后立即结束本帧冲撞结算。
func _vehicle_target() -> ball:
	# 显式 Target_Enemy 永远优先。
	if is_instance_valid(Target_Enemy) and Target_Enemy is ball:
		var explicit_target:ball = Target_Enemy as ball
		if explicit_target.health > 0 and TOOLS.is_enemy(self,explicit_target):
			_set_vehicle_target_lock(explicit_target)
			return explicit_target

	var locked:ball = _vehicle_locked_target()
	if locked != null and _vehicle_target_lock_left > 0.0:
		return locked

	var candidate:ball = null
	var reusable:Node = return_reusable_combat_target()
	if reusable is ball:
		var reusable_ball:ball = reusable as ball
		if reusable_ball.health > 0 and TOOLS.is_enemy(self,reusable_ball):
			candidate = reusable_ball
	if candidate == null:
		candidate = TOOLS.nearest_enemy(self)

	if locked != null:
		if candidate == null:
			_vehicle_target_lock_left = multi_target_lock_seconds * 0.35
			return locked
		if candidate != locked:
			var locked_distance_sq:float = global_position.distance_squared_to(locked.global_position)
			var candidate_distance_sq:float = global_position.distance_squared_to(candidate.global_position)
			var switch_ratio_sq:float = multi_target_switch_ratio * multi_target_switch_ratio
			# 多目标接近时禁止“谁刚刚近 2px 就换谁”。只有新目标显著更近才换锁。
			if candidate_distance_sq >= locked_distance_sq * switch_ratio_sq:
				_vehicle_target_lock_left = multi_target_lock_seconds * 0.35
				return locked

	if candidate != null:
		_set_vehicle_target_lock(candidate)
	else:
		_vehicle_target_lock_ref = null
		_vehicle_target_lock_left = 0.0
	return candidate


func _vehicle_locked_target() -> ball:
	if _vehicle_target_lock_ref == null:
		return null
	var raw:Variant = _vehicle_target_lock_ref.get_ref()
	if not raw is ball:
		_vehicle_target_lock_ref = null
		return null
	var candidate:ball = raw as ball
	if not is_instance_valid(candidate) or candidate.health <= 0 or not TOOLS.is_enemy(self,candidate):
		_vehicle_target_lock_ref = null
		return null
	return candidate


func _set_vehicle_target_lock(target:ball) -> void:
	if target == null or not is_instance_valid(target):
		return
	_vehicle_target_lock_ref = weakref(target)
	_vehicle_target_lock_left = maxf(multi_target_lock_seconds,0.0)


func _nearby_enemy_count(radius:float) -> int:
	var count:int = 0
	var radius_sq:float = radius * radius
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if raw == self or not raw is ball:
			continue
		var candidate:ball = raw as ball
		if candidate.health <= 0 or not TOOLS.is_enemy(self,candidate):
			continue
		if global_position.distance_squared_to(candidate.global_position) <= radius_sq:
			count += 1
			if count >= crowd_ram_enemy_threshold:
				return count
	return count


func _sync_friendly_collision_exceptions() -> void:
	var desired:Dictionary = {}
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if raw == self or not raw is ball or not raw is PhysicsBody2D:
			continue
		var ally:ball = raw as ball
		if ally.health <= 0 or not TOOLS.same_side(self,ally):
			continue
		var ally_id:int = ally.get_instance_id()
		desired[ally_id] = weakref(ally)
		if not _friendly_collision_refs.has(ally_id):
			preload("res://classes/body_collision_exclusions.gd").add_exception(self,ally)
			preload("res://classes/body_collision_exclusions.gd").add_exception((ally as PhysicsBody2D),self)
			_friendly_collision_refs[ally_id] = weakref(ally)

	for key:Variant in _friendly_collision_refs.keys():
		var ally_id:int = int(key)
		if desired.has(ally_id):
			continue
		var stored:Variant = _friendly_collision_refs.get(ally_id)
		var raw_ally:Variant = stored.get_ref() if stored is WeakRef else null
		if raw_ally is PhysicsBody2D and is_instance_valid(raw_ally):
			var ally_body:PhysicsBody2D = raw_ally as PhysicsBody2D
			preload("res://classes/body_collision_exclusions.gd").remove_exception(self,ally_body)
			preload("res://classes/body_collision_exclusions.gd").remove_exception(ally_body,self)
		_friendly_collision_refs.erase(ally_id)


func _grant_crowd_ram_pass_through(target:ball) -> void:
	if target == null or not is_instance_valid(target) or not target is PhysicsBody2D:
		return
	var id:int = target.get_instance_id()
	var until_msec:int = Time.get_ticks_msec() + int(maxf(crowd_ram_pass_grace,0.05) * 1000.0)
	var already_active:bool = _crowd_pass_until_msec.has(id)
	_crowd_pass_until_msec[id] = maxi(int(_crowd_pass_until_msec.get(id,0)),until_msec)
	if already_active:
		return
	var body:PhysicsBody2D = target as PhysicsBody2D
	preload("res://classes/body_collision_exclusions.gd").add_exception(self,body)
	preload("res://classes/body_collision_exclusions.gd").add_exception(body,self)
	_release_crowd_ram_pass_through(id,weakref(target))


func _release_crowd_ram_pass_through(target_id:int,target_ref:WeakRef) -> void:
	# V151：同一目标连续接触时只延长一个截止时间，不再创建多组互相抢着
	# remove_collision_exception 的 timer。旧做法会让最早的 0.2s timer 提前重新
	# 打开碰撞，目标仍在车身里时就再次把车辆钉住。
	while is_instance_valid(self) and _crowd_pass_until_msec.has(target_id):
		var remaining_msec:int = int(_crowd_pass_until_msec[target_id]) - Time.get_ticks_msec()
		if remaining_msec <= 0:
			break
		await get_tree().create_timer(maxf(float(remaining_msec) / 1000.0,0.03),false,true).timeout
	if not is_instance_valid(self):
		return
	_crowd_pass_until_msec.erase(target_id)
	var raw:Variant = target_ref.get_ref()
	if not raw is PhysicsBody2D or not is_instance_valid(raw):
		return
	# 同队永久例外优先，不能在临时宽限结束时重新打开队友碰撞。
	if raw is ball and TOOLS.same_side(self,raw as ball):
		return
	preload("res://classes/body_collision_exclusions.gd").remove_exception(self,raw)
	preload("res://classes/body_collision_exclusions.gd").remove_exception((raw as PhysicsBody2D),self)


func _resolve_enemy_body_blocking(delta:float,actual_displacement:Vector2,requested_velocity:Vector2) -> void:
	if is_player_controlled() or requested_velocity.length_squared() <= MOTION_EPSILON_SQ:
		_enemy_blocked_elapsed = 0.0
		return

	var enemy_contacts:Array[ball] = []
	for index:int in range(get_slide_collision_count()):
		var collision:KinematicCollision2D = get_slide_collision(index)
		if collision == null:
			continue
		var raw:Variant = collision.get_collider()
		if raw is ball and TOOLS.is_enemy(self,raw as ball):
			enemy_contacts.append(raw as ball)
	if enemy_contacts.is_empty():
		_enemy_blocked_elapsed = maxf(_enemy_blocked_elapsed - delta * 4.0,0.0)
		return

	var expected_move:float = requested_velocity.length() * delta
	if expected_move <= 1.0:
		_enemy_blocked_elapsed = 0.0
		return

	# V154：不能再用“这一帧总共移动了多少距离”判断是否被敌人堵住。
	# move_and_slide() 顶着敌人/墙时可能把车辆横向滑开；横向滑动距离很大，
	# 但沿真正驾驶方向几乎没有推进。旧算法会把这种滑墙误判成“仍然移动正常”，
	# 于是车辆会继续顶人一段时间才触发解卡。这里只计算沿请求运动方向的有效推进。
	var travel_direction:Vector2 = requested_velocity.normalized()
	var forward_progress:float = maxf(actual_displacement.dot(travel_direction),0.0)
	var progress_ratio:float = forward_progress / maxf(expected_move,0.001)
	if progress_ratio > enemy_blocked_motion_ratio:
		_enemy_blocked_elapsed = maxf(_enemy_blocked_elapsed - delta * 3.0,0.0)
		return

	_enemy_blocked_elapsed += delta
	var wall_probe_distance:float = maxf(wall_probe_min_distance * 1.15,86.0)
	var wall_probe:Dictionary = _probe_wall(travel_direction,wall_probe_distance)
	var wall_is_close:bool = bool(wall_probe.get("hit",false)) and float(wall_probe.get("clear_ratio",1.0)) <= enemy_wall_probe_ratio
	var crowd_ram:bool = _nearby_enemy_count(crowd_ram_radius) >= crowd_ram_enemy_threshold

	# 几乎没有任何前向推进时视为“硬阻塞”，不再强制等满 enemy_blocked_reverse_delay。
	# 这样车头把敌人压在墙边、或车身被敌人正面卡住时，本帧/下一帧就会撤离。
	var hard_block_ratio:float = minf(enemy_blocked_motion_ratio * 0.45,0.18)
	var hard_blocked:bool = progress_ratio <= hard_block_ratio

	# 多敌人且前方不是紧贴墙：把当前真正阻车的前排临时从实体碰撞中放行。
	# 伤害仍由扫掠/slide collision 自己按 cooldown 结算，因此“能穿过前排”不等于重复伤害。
	if crowd_ram and not wall_is_close:
		for enemy:ball in enemy_contacts:
			_grant_crowd_ram_pass_through(enemy)
		_enemy_blocked_elapsed = 0.0
		return

	if not hard_blocked and _enemy_blocked_elapsed < enemy_blocked_reverse_delay and not wall_is_close:
		return

	# 单个敌人被顶住，或敌人背后马上就是墙：无论冲撞伤害此刻是否在 cooldown，
	# 都必须立即撤出并重新进攻。墙边优先使用墙面法线脱困；其它情况短倒车。
	_enemy_blocked_elapsed = 0.0
	_vehicle_target_lock_ref = null
	_vehicle_target_lock_left = 0.0
	if wall_is_close:
		var normal:Vector2 = wall_probe.get("normal",Vector2.ZERO)
		if normal.length_squared() > 0.0001:
			_start_wall_escape(normal.normalized())
			return
	_begin_ram_reverse()


# V142 起该安全矩形只用于“小弟出生点”限制，不再用于每帧钳制移动。
func _van_minion_safe_rect(map_rect:Rect2) -> Rect2:
	var margin:float = maxf(summon_clear_radius + 10.0,28.0)
	var inner:Rect2 = map_rect.grow(-margin)
	return inner if inner.size.x > 8.0 and inner.size.y > 8.0 else map_rect


func _clamp_van_minion_spawn_to_map(spawn_point:Vector2) -> Vector2:
	var map_rect:Rect2 = TOOLS.map_rect(self)
	if map_rect.size.x <= 1.0 or map_rect.size.y <= 1.0:
		return spawn_point
	var safe_rect:Rect2 = _van_minion_safe_rect(map_rect)
	return Vector2(
		clampf(spawn_point.x,safe_rect.position.x,safe_rect.end.x),
		clampf(spawn_point.y,safe_rect.position.y,safe_rect.end.y)
	)


# V146：删除 V142 的车载小弟“每帧安全内沿钳制”。
# 小弟正常移动继续依赖实体地图墙 + ball.when_collide() 反弹；若中心真的被挤出地图，
# 交给 World 既有地图越界救回机制处理，禁止在墙前人为截停。


func _roam_goal(map_rect:Rect2) -> Vector2:
	if map_rect.size.x <= 1.0 or map_rect.size.y <= 1.0:
		# 极端情况下拿不到地图范围，也保持缓慢向当前车头巡航，不原地静止。
		return global_position + Vector2.RIGHT.rotated(_vehicle_heading) * 180.0

	if (
		not _roam_point_valid
		or _roam_repick_left <= 0.0
		or global_position.distance_to(_roam_point) <= roam_reach_distance
		or not map_rect.has_point(_roam_point)
	):
		_pick_roam_point(map_rect)
	return _roam_point


func _pick_roam_point(map_rect:Rect2) -> void:
	var margin:float = minf(
		roam_wall_margin,
		maxf(minf(map_rect.size.x,map_rect.size.y) * 0.28,18.0)
	)
	var inner:Rect2 = map_rect.grow(-margin)
	if inner.size.x < 30.0 or inner.size.y < 30.0:
		inner = map_rect.grow(-minf(20.0,minf(map_rect.size.x,map_rect.size.y) * 0.12))

	var best:Vector2 = inner.get_center()
	var best_distance_sq:float = -1.0
	for _i:int in range(6):
		var candidate := Vector2(
			randf_range(inner.position.x,inner.end.x),
			randf_range(inner.position.y,inner.end.y)
		)
		var d:float = global_position.distance_squared_to(candidate)
		if d > best_distance_sq:
			best = candidate
			best_distance_sq = d
	_roam_point = best
	_roam_point_valid = true
	_roam_repick_left = roam_repick_seconds * randf_range(0.82,1.22)


func _update_wall_follow(goal_position:Vector2,goal_direction:Vector2,map_rect:Rect2,delta:float) -> void:
	var to_goal:Vector2 = goal_position - global_position
	if to_goal.length_squared() <= 0.0001:
		_wall_follow_active = false
		return

	var direct_length:float = minf(to_goal.length(),maxf(smart_lookahead_max * 1.45,170.0))
	var hit:Dictionary = _probe_wall(to_goal.normalized(),direct_length)
	var blocked:bool = bool(hit.get("hit",false)) and float(hit.get("clear_ratio",1.0)) < ai_direct_clear_ratio

	if not blocked:
		if _wall_follow_active:
			_wall_follow_clear_elapsed += delta
			if _wall_follow_clear_elapsed >= wall_follow_clear_time:
				_wall_follow_active = false
				_wall_follow_elapsed = 0.0
				_wall_follow_clear_elapsed = 0.0
				_avoidance_side_sign = 0.0
		return

	_wall_follow_clear_elapsed = 0.0
	var normal:Vector2 = hit.get("normal",Vector2.ZERO)
	if normal.length_squared() <= 0.0001:
		return
	normal = normal.normalized()

	# 已经决定绕哪边时先坚持，不允许目标稍微移动就左右翻面。
	if _wall_follow_active and _wall_follow_elapsed < wall_follow_min_time and _wall_follow_direction.length_squared() > 0.0001:
		return

	var tangent_a:Vector2 = normal.rotated(PI * 0.5).normalized()
	var tangent_b:Vector2 = -tangent_a
	var toward_center:Vector2 = map_rect.get_center() - global_position
	var center_dir:Vector2 = toward_center.normalized() if toward_center.length_squared() > 0.0001 else Vector2.ZERO
	var tangent_probe_distance:float = maxf(smart_lookahead_min * 1.15,96.0)
	var clear_a:float = minf(
		float(_probe_wall(tangent_a,tangent_probe_distance).get("clear_ratio",1.0)),
		_body_clearance_ratio(tangent_a,tangent_probe_distance)
	)
	var clear_b:float = minf(
		float(_probe_wall(tangent_b,tangent_probe_distance).get("clear_ratio",1.0)),
		_body_clearance_ratio(tangent_b,tangent_probe_distance)
	)

	# 选择真正更有空间、同时更接近目标的一侧，而不是只看目标夹角。
	var score_a:float = clear_a * 2.0 + tangent_a.dot(goal_direction) * 0.95 + tangent_a.dot(center_dir) * 0.28
	var score_b:float = clear_b * 2.0 + tangent_b.dot(goal_direction) * 0.95 + tangent_b.dot(center_dir) * 0.28
	if _avoidance_side_sign > 0.0:
		score_a += 0.55
	elif _avoidance_side_sign < 0.0:
		score_b += 0.55

	var tangent:Vector2 = tangent_a if score_a >= score_b else tangent_b
	_avoidance_side_sign = 1.0 if score_a >= score_b else -1.0
	# 少量离墙分量确保车身不会贴着碰撞边缘磨墙；主体仍然沿墙前进。
	_wall_follow_direction = (tangent * 0.94 + normal * 0.34).normalized()
	_wall_follow_active = true
	_wall_follow_elapsed = 0.0


func _choose_smart_drive_direction(goal_direction:Vector2,forward:Vector2,map_rect:Rect2) -> Dictionary:
	var speed_ratio:float = clampf(absf(_vehicle_speed) / maxf(Speed,1.0),0.0,1.0)
	var lookahead:float = lerpf(smart_lookahead_min,smart_lookahead_max,speed_ratio)
	# 比上一版看得更宽，接近墙角时允许提前选择大角度绕行路线。
	var offsets := PackedFloat32Array([-150.0,-132.0,-116.0,-100.0,-84.0,-68.0,-52.0,-36.0,-22.0,-11.0,0.0,11.0,22.0,36.0,52.0,68.0,84.0,100.0,116.0,132.0,150.0])
	var inner_margin:float = maxf(ram_hit_radius + 16.0,38.0)
	var inner_rect:Rect2 = map_rect.grow(-inner_margin)
	if inner_rect.size.x <= 8.0 or inner_rect.size.y <= 8.0:
		inner_rect = map_rect

	var best_direction:Vector2 = goal_direction
	var best_score:float = -INF
	var best_clear:float = 0.0
	var front_clear:float = 1.0
	var best_side_sign:float = 0.0

	for degrees:float in offsets:
		var candidate:Vector2 = forward.rotated(deg_to_rad(degrees)).normalized()
		var side_factor:float = absf(degrees) / 150.0
		var candidate_lookahead:float = lookahead * lerpf(1.0,0.76,side_factor)
		var probe:Dictionary = _probe_wall(candidate,candidate_lookahead)
		# 射线只看“中心线/保险杠”，还可能漏掉车身角落。再用 CharacterBody2D.test_move()
		# 对真实车体做一次扫掠，两者取更保守值，减少车头觉得有路但车身实际卡墙。
		var ray_clear_ratio:float = float(probe.get("clear_ratio",1.0))
		var body_clear_ratio:float = _body_clearance_ratio(candidate,candidate_lookahead)
		var clear_ratio:float = minf(ray_clear_ratio,body_clear_ratio)
		if is_zero_approx(degrees):
			front_clear = clear_ratio

		var projected:Vector2 = global_position + candidate * candidate_lookahead
		if map_rect.size.x > 1.0 and map_rect.size.y > 1.0 and not inner_rect.has_point(projected):
			clear_ratio *= 0.36

		var alignment:float = clampf((candidate.dot(goal_direction) + 1.0) * 0.5,0.0,1.0)
		var forwardness:float = clampf((candidate.dot(forward) + 1.0) * 0.5,0.0,1.0)
		var candidate_side:float = signf(forward.cross(candidate))
		var side_memory:float = 0.0
		if _avoidance_side_sign != 0.0 and candidate_side == _avoidance_side_sign:
			side_memory = 0.30
		var score:float = clear_ratio * clear_ratio * 2.75 + alignment * 1.55 + forwardness * 0.28 + side_memory
		# 几乎堵死的方向即使直指目标也不值得继续顶。
		if clear_ratio < 0.22:
			score -= 1.35
		if score > best_score:
			best_score = score
			best_direction = candidate
			best_clear = clear_ratio
			best_side_sign = candidate_side

	if front_clear < 0.70 and best_side_sign != 0.0:
		_avoidance_side_sign = best_side_sign
	elif front_clear > 0.92 and not _wall_follow_active:
		_avoidance_side_sign = 0.0

	return {
		"direction": best_direction,
		"front_clear_ratio": front_clear,
		"best_clear_ratio": best_clear,
	}


func _update_stuck_recovery(delta:float,actual_move_distance:float,requested_velocity:Vector2,map_rect:Rect2) -> void:
	if _wall_escape_left > 0.0 or _reverse_left > 0.0 or _ram_reverse_left > 0.0:
		_stuck_elapsed = 0.0
		return
	var expected_move:float = requested_velocity.length() * delta
	if expected_move < 3.0:
		_stuck_elapsed = maxf(_stuck_elapsed - delta * 2.0,0.0)
		return
	if actual_move_distance <= expected_move * stuck_motion_ratio:
		_stuck_elapsed += delta
	else:
		_stuck_elapsed = maxf(_stuck_elapsed - delta * 2.5,0.0)

	if _stuck_elapsed < stuck_trigger_time:
		return
	_stuck_elapsed = 0.0
	var normal:Vector2 = _combined_wall_escape_normal()
	if normal.length_squared() <= 0.0001:
		normal = map_rect.get_center() - global_position
	if normal.length_squared() <= 0.0001:
		normal = -Vector2.RIGHT.rotated(_vehicle_heading)
	_start_wall_escape(normal.normalized())


func _wall_avoidance(forward:Vector2,map_rect:Rect2) -> Dictionary:
	var avoidance:Vector2 = Vector2.ZERO

	# 先用地图矩形做稳定的边界排斥，避免车已经贴墙才开始反应。
	if map_rect.size.x > 1.0 and map_rect.size.y > 1.0:
		var left_distance:float = global_position.x - map_rect.position.x
		var right_distance:float = map_rect.end.x - global_position.x
		var top_distance:float = global_position.y - map_rect.position.y
		var bottom_distance:float = map_rect.end.y - global_position.y
		avoidance += Vector2.RIGHT * _edge_weight(left_distance)
		avoidance += Vector2.LEFT * _edge_weight(right_distance)
		avoidance += Vector2.DOWN * _edge_weight(top_distance)
		avoidance += Vector2.UP * _edge_weight(bottom_distance)

	var speed_ratio:float = clampf(absf(_vehicle_speed) / maxf(Speed,1.0),0.0,1.0)
	var ray_length:float = lerpf(wall_probe_min_distance,wall_probe_max_distance,speed_ratio)
	var side_angle:float = deg_to_rad(wall_probe_side_angle_degrees)
	var left_dir:Vector2 = forward.rotated(-side_angle)
	var right_dir:Vector2 = forward.rotated(side_angle)

	var front_hit:Dictionary = _probe_wall(forward,ray_length)
	var left_hit:Dictionary = _probe_wall(left_dir,ray_length * 0.82)
	var right_hit:Dictionary = _probe_wall(right_dir,ray_length * 0.82)

	var front_ratio:float = float(front_hit.get("clear_ratio",1.0))
	var left_ratio:float = float(left_hit.get("clear_ratio",1.0))
	var right_ratio:float = float(right_hit.get("clear_ratio",1.0))

	if bool(front_hit.get("hit",false)):
		var front_normal:Vector2 = front_hit.get("normal",Vector2.ZERO)
		avoidance += front_normal * (1.0 - front_ratio) * 2.2
	if bool(left_hit.get("hit",false)):
		avoidance += forward.rotated(side_angle) * (1.0 - left_ratio) * 1.35
	if bool(right_hit.get("hit",false)):
		avoidance += forward.rotated(-side_angle) * (1.0 - right_ratio) * 1.35

	# 正前方被挡时，明确偏向更空旷的一侧，避免左右力刚好抵消后继续直顶墙。
	if front_ratio < 0.72:
		if left_ratio > right_ratio + 0.05:
			avoidance += left_dir * (0.72 - front_ratio) * 1.6
		elif right_ratio > left_ratio + 0.05:
			avoidance += right_dir * (0.72 - front_ratio) * 1.6
		elif map_rect.size.x > 1.0 and map_rect.size.y > 1.0:
			var toward_center:Vector2 = map_rect.get_center() - global_position
			if toward_center.length_squared() > 0.0001:
				avoidance += toward_center.normalized() * (0.72 - front_ratio) * 1.6

	return {
		"vector": avoidance,
		"front_clear_ratio": front_ratio,
		"left_clear_ratio": left_ratio,
		"right_clear_ratio": right_ratio,
	}


func _edge_weight(distance_to_edge:float) -> float:
	if distance_to_edge >= wall_safe_margin:
		return 0.0
	var t:float = 1.0 - clampf(distance_to_edge / maxf(wall_safe_margin,1.0),0.0,1.0)
	return t * t * 1.7


func _probe_wall(ray_direction:Vector2,ray_length:float) -> Dictionary:
	if ray_direction.length_squared() <= 0.0001 or ray_length <= 0.0:
		return {"hit": false,"clear_ratio": 1.0,"normal": Vector2.ZERO}
	var direction_normalized:Vector2 = ray_direction.normalized()
	var side:Vector2 = direction_normalized.rotated(PI * 0.5)
	var offsets := PackedFloat32Array([-vehicle_probe_half_width,0.0,vehicle_probe_half_width])
	var best_ratio:float = 1.0
	var best_normal:Vector2 = Vector2.ZERO
	var any_hit:bool = false
	var space := get_world_2d().direct_space_state

	# 从假想前保险杠并排发 3 根射线，近似车辆宽度。中心有路但车角会蹭墙时，
	# 侧射线会更早把该方向判成危险，避免临到墙边才反应。
	for offset:float in offsets:
		var origin:Vector2 = global_position + direction_normalized * vehicle_probe_front_offset + side * offset
		var query := PhysicsRayQueryParameters2D.create(
			origin,
			origin + direction_normalized * ray_length,
			wall_probe_mask,
			[get_rid()]
		)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var result:Dictionary = space.intersect_ray(query)
		if result.is_empty():
			continue
		any_hit = true
		var hit_position:Vector2 = result.get("position",origin + direction_normalized * ray_length)
		var hit_normal:Vector2 = result.get("normal",Vector2.ZERO)
		var distance:float = origin.distance_to(hit_position)
		var ratio:float = clampf(distance / maxf(ray_length,1.0),0.0,1.0)
		if ratio < best_ratio:
			best_ratio = ratio
			best_normal = hit_normal

	return {
		"hit": any_hit,
		"clear_ratio": best_ratio,
		"normal": best_normal,
	}


# 用车辆自己的 CollisionShape2D 预测某个方向能走多远。test_move() 不实际移动节点，
# 但会使用真实车体碰撞形状，比单纯射线更能发现墙角/窄口。
func _body_clearance_ratio(move_direction:Vector2,distance:float) -> float:
	if move_direction.length_squared() <= 0.0001 or distance <= 0.0:
		return 1.0
	var dir:Vector2 = move_direction.normalized()
	var transform_now:Transform2D = global_transform
	# 车身真实 collision_mask 包含人物，但路径规划这里只能把地图墙当障碍。
	# 临时切换 mask 做 test_move，随后立即恢复，避免 AI 因敌人挡在前方而主动绕开。
	var original_mask:int = collision_mask
	collision_mask = wall_probe_mask
	var blocked_full:bool = test_move(transform_now,dir * distance,null,safe_margin,false)
	if not blocked_full:
		collision_mask = original_mask
		return 1.0
	var low:float = 0.0
	var high:float = 1.0
	for _i:int in range(5):
		var mid:float = (low + high) * 0.5
		if test_move(transform_now,dir * distance * mid,null,safe_margin,false):
			high = mid
		else:
			low = mid
	collision_mask = original_mask
	return clampf(low,0.0,1.0)


# V134：人物层不再全局 collision exception；只有刚下车的小弟保留短暂 grace。
func _begin_reverse(duration:float) -> void:
	_reverse_left = maxf(duration,0.0)
	_reverse_rearm_left = maxf(reverse_rearm_delay,_reverse_left)


func _handle_vehicle_collision(collision:KinematicCollision2D,incoming_velocity:Vector2) -> void:
	if collision == null:
		return

	var collider:Variant = collision.get_collider()
	if collider is ball:
		# V150：人物接触不再在这里直接触发倒车。真正的“撞中敌人后是否倒车”只由
		# _try_apply_ram_to_target() 统一决定；旧逻辑会让任意 ball（甚至同队/自己小弟）
		# 成为倒车触发器，多单位场景里就会不断换挡。
		var other:ball = collider as ball
		if TOOLS.is_enemy(self,other):
			var incoming_dir:Vector2 = incoming_velocity.normalized() if incoming_velocity.length_squared() > 0.0001 else Vector2.RIGHT.rotated(_vehicle_heading)
			var impact_power:float = _calculate_collision_impact_power(collision,absf(_vehicle_speed))
			_trigger_collision_feedback(incoming_dir,impact_power,collision)
		return

	if _is_wall_like_collision(collision):
		# 墙体只走墙面白线，不播放普通角色的碰撞/脚步音。
		var normal:Vector2 = _combined_wall_escape_normal()
		if normal.length_squared() <= 0.0001:
			normal = collision.get_normal().normalized()
		_start_wall_escape(normal)


func _combined_wall_escape_normal() -> Vector2:
	var summed:Vector2 = Vector2.ZERO
	for index:int in range(get_slide_collision_count()):
		var candidate:KinematicCollision2D = get_slide_collision(index)
		if candidate == null or not _is_wall_like_collision(candidate):
			continue
		var normal:Vector2 = candidate.get_normal()
		if normal.length_squared() > 0.0001:
			summed += normal.normalized()
	if summed.length_squared() <= 0.0001:
		return Vector2.ZERO
	return summed.normalized()


func _start_wall_escape(away_normal:Vector2) -> void:
	if away_normal.length_squared() <= 0.0001:
		away_normal = (TOOLS.map_rect(self).get_center() - global_position).normalized()
	if away_normal.length_squared() <= 0.0001:
		away_normal = -Vector2.RIGHT.rotated(_vehicle_heading)

	away_normal = away_normal.normalized()
	if _wall_escape_left > 0.0:
		# 连续接触同一堵墙不能每帧把脱困计时重置，否则会永远停留在“刚撞墙”。
		if _wall_escape_normal.length_squared() > 0.0001:
			_wall_escape_normal = (_wall_escape_normal + away_normal).normalized()
		else:
			_wall_escape_normal = away_normal
		_wall_escape_heading = (-_wall_escape_normal).angle()
		_wall_escape_left = maxf(_wall_escape_left,wall_escape_min_time * 0.45)
		return

	_wall_escape_normal = away_normal
	_wall_escape_start_position = global_position
	_play_vehicle_one_shot(VAN_WALL_AUDIO,wall_audio_volume_db)
	_wall_recovery_left = 0.0
	_wall_recovery_direction = Vector2.ZERO
	_ram_reverse_left = 0.0
	# 倒车的实际移动方向是 -forward，所以让 forward 朝向墙内（-normal），车尾自然退出墙面。
	_wall_escape_heading = (-_wall_escape_normal).angle()
	_wall_escape_left = maxf(wall_escape_max_time,wall_escape_min_time)
	_wall_escape_elapsed = 0.0
	_reverse_left = 0.0
	_reverse_rearm_left = maxf(reverse_rearm_delay,wall_escape_min_time)
	# 墙撞击后立即给一个小的负速度，保证下一物理帧真的开始离墙，
	# 不再先在墙上原地“换挡”半秒。
	_vehicle_speed = -minf(maxf(Speed * 0.22,10.0),32.0)
	_smoothed_speed_target = _vehicle_speed
	_vehicle_turn_rate *= 0.35
	_update_engine_audio()


func _end_wall_escape() -> void:
	var away_normal:Vector2 = _wall_escape_normal.normalized() if _wall_escape_normal.length_squared() > 0.0001 else Vector2.ZERO
	_wall_escape_left = 0.0
	_wall_escape_elapsed = 0.0
	_wall_escape_start_position = global_position

	# 退开以后先沿“离墙 + 沿墙侧向”开一段。选择更朝地图中心的那一侧，
	# 让车辆真正脱离墙区后再重新锁定敌人。
	if away_normal.length_squared() > 0.0001:
		var side_angle:float = deg_to_rad(wall_recovery_side_angle_degrees)
		var option_a:Vector2 = away_normal.rotated(side_angle).normalized()
		var option_b:Vector2 = away_normal.rotated(-side_angle).normalized()
		var toward_center:Vector2 = TOOLS.map_rect(self).get_center() - global_position
		if toward_center.length_squared() > 0.0001:
			var center_dir:Vector2 = toward_center.normalized()
			_wall_recovery_direction = option_a if option_a.dot(center_dir) >= option_b.dot(center_dir) else option_b
		else:
			_wall_recovery_direction = option_a
		_wall_recovery_left = wall_recovery_duration
	else:
		_wall_recovery_direction = Vector2.ZERO
		_wall_recovery_left = 0.0

	_wall_escape_normal = Vector2.ZERO
	_reverse_rearm_left = maxf(_reverse_rearm_left,wall_recovery_duration + 0.25)
	_vehicle_turn_rate *= 0.45


func _begin_ram_reverse() -> void:
	if _wall_escape_left > 0.0:
		return
	_ram_reverse_left = maxf(_ram_reverse_left,ram_reverse_duration)
	_reverse_left = 0.0
	_reverse_rearm_left = maxf(_reverse_rearm_left,ram_reverse_duration + 0.18)
	# 撞人后直接挂入倒档，不在原地先停住。车辆会明确退开，再重新加速冲撞。
	_vehicle_speed = -maxf(Speed * 0.26,24.0)
	_smoothed_speed_target = -Speed * ram_reverse_speed_ratio
	_vehicle_turn_rate *= 0.45
	_update_engine_audio()


func _update_vehicle_visual() -> void:
	if graphics == null:
		return
	var visual_heading:float = wrapf(_vehicle_heading,-PI,PI)
	var heading_cos:float = cos(visual_heading)
	# 在接近竖直方向时加一点迟滞，避免左右纹理一帧一换。
	if not _visual_face_left and heading_cos < -0.12:
		_visual_face_left = true
	elif _visual_face_left and heading_cos > 0.12:
		_visual_face_left = false

	if _visual_face_left:
		visual_heading = wrapf(visual_heading + PI,-PI,PI)
	graphics.rotation = _graphics_base_rotation + visual_heading

	if image is Sprite2D:
		var sprite:Sprite2D = image as Sprite2D
		# 不再运行时 flip_h。当前项目会自动裁透明边并调整 Sprite2D.offset，
		# 对这种大透明 PNG 运行时翻转可能把可见主体带出自动拟合中心。
		# 直接切换同尺寸镜像纹理，视觉仍然是左右翻转，但坐标/offset 完全稳定。
		sprite.flip_h = false
		sprite.flip_v = false
		sprite.texture = VAN_TEXTURE_LEFT if _visual_face_left else VAN_TEXTURE_RIGHT


func _try_ram() -> void:
	if _crippled:
		return
	var impact_speed:float = absf(_vehicle_speed)
	var minimum_ram_speed:float = maxf(Speed * ram_min_speed_ratio,35.0)
	if impact_speed < minimum_ram_speed:
		return

	# V153：静止/低位移帧也直接查询场景里的车头/车尾攻击碰撞箱。
	_process_ram_swept_contacts(global_position,global_position,impact_speed)


# V153 统一处理车头 / 车尾攻击碰撞：
# - 只有场景中两个可编辑 CollisionShape2D 重叠到敌人时才有冲撞伤害；
# - 伤害仍随实际速度提升，低于 ram_min_speed_ratio 阈值完全没有伤害；
# - 车头完整伤害，车尾使用 rear_ram_damage_ratio。
func _try_apply_ram_to_target(target:ball,impact_speed:float,hit_zone:int) -> bool:
	if _crippled or target == null or not is_instance_valid(target):
		return false
	if not TOOLS.is_enemy(self,target):
		return false

	var current_speed:float = absf(impact_speed)
	var minimum_ram_speed:float = maxf(Speed * ram_min_speed_ratio,35.0)
	if current_speed < minimum_ram_speed or absf(_vehicle_speed) < minimum_ram_speed:
		return false

	# V153：命中区域由实际重叠的场景碰撞箱直接决定，不再用目标中心点角度推算车头/车侧/车尾。
	# hit_zone: 1=车头，-1=车尾。只有这两个攻击碰撞箱会造成冲撞伤害。
	var hit_is_front:bool = hit_zone > 0
	var hit_is_rear:bool = hit_zone < 0
	if not hit_is_front and not hit_is_rear:
		return false

	var forward:Vector2 = Vector2.RIGHT.rotated(_vehicle_heading)
	var travel_direction:Vector2 = forward * signf(_vehicle_speed)
	var to_target:Vector2 = target.global_position - global_position

	var id:int = target.get_instance_id()
	var now:int = Time.get_ticks_msec()
	if _ram_last_hit.has(id) and now - int(_ram_last_hit[id]) < int(ram_target_cooldown * 1000.0):
		return false

	var max_vehicle_speed:float = maxf(Speed,minimum_ram_speed + 1.0)
	var speed_damage_ratio:float = clampf(
		(current_speed - minimum_ram_speed) / (max_vehicle_speed - minimum_ram_speed),
		0.0,
		1.0
	)
	var damage_multiplier:float = lerpf(ram_min_damage_multiplier,ram_max_damage_multiplier,speed_damage_ratio)
	if hit_is_rear:
		damage_multiplier *= rear_ram_damage_ratio
	var current_ram_damage:float = attack_damage(damage_multiplier)
	var dealt:bool = target.receive_positional_damage(current_ram_damage,global_position,false,self)
	if not dealt:
		return false

	_ram_last_hit[id] = now
	Audios.play_sfx.rpc("balls_hit1",{volume = -4.0},true,true)

	# V141：击退不再从“刚过伤害阈值”就给 34px/360 的大推力。
	# 使用幂曲线让低速只轻推，中高速才快速抬升；最高值也比 V140 更克制。
	var knockback_ratio:float = pow(speed_damage_ratio,maxf(ram_knockback_speed_curve,1.0))
	var knockback_distance:float = lerpf(
		ram_knockback_min_distance,
		ram_knockback_max_distance,
		knockback_ratio
	)
	var knockback_speed:float = lerpf(
		ram_knockback_min_speed,
		ram_knockback_max_speed,
		knockback_ratio
	)
	if hit_is_rear:
		knockback_distance *= 0.62
		knockback_speed *= 0.68
	var knockback_direction:Vector2 = travel_direction
	if to_target.length_squared() > 0.0001:
		knockback_direction = (travel_direction * 0.78 + to_target.normalized() * 0.22).normalized()
	target.apply_knockback(
		knockback_direction,
		knockback_distance,
		knockback_speed,
		0.0,
		0.0,
		{
			"source": self,
			"lock_control": true,
			"stop_on_character": true,
			"smooth_motion": true,
			"use_speed_falloff": true,
			"end_speed_ratio": 0.20,
		}
	)
	# V150 多敌人冲撞：单个敌人仍保留原来的“撞中后短倒车”；附近有多个敌人时
	# 禁止因为第一名敌人就立刻换挡，并给刚命中的敌人一个极短实体穿越宽限。这样车身
	# 仍然先发生真实接触/伤害，但下一物理帧能继续冲向队伍里的其它单位，而不是被第一人卡死。
	var crowd_ram:bool = _nearby_enemy_count(crowd_ram_radius) >= crowd_ram_enemy_threshold
	if crowd_ram:
		_grant_crowd_ram_pass_through(target)
	if hit_is_front and _vehicle_speed > 0.0 and not is_player_controlled() and not crowd_ram:
		_begin_ram_reverse()
	return true


func _is_reverse_gear_active() -> bool:
	return (
		_wall_escape_left > 0.0
		or _ram_reverse_left > 0.0
		or _reverse_left > 0.0
		or _vehicle_speed < -engine_audio_min_speed
	)


func _spawn_random_van_minion() -> bool:
	var kinds:Array[int] = [
		MINION_SCRIPT.Kind.VAN_KNIFE,
		MINION_SCRIPT.Kind.VAN_BATON,
		MINION_SCRIPT.Kind.VAN_FIST,
	]
	if kinds.is_empty():
		return false
	var kind_value:int = kinds[randi_range(0,kinds.size() - 1)]
	return _spawn_van_minion(kind_value)


func _spawn_van_minion(kind_value:int) -> bool:
	var spawn_info:Dictionary = _find_clear_van_minion_spawn()
	if not bool(spawn_info.get("ok",false)):
		# 普通倒车召唤仍保留严格空旷判定；只有 Boss 50% 波次使用专用保证槽位。
		return false
	var spawn_point:Vector2 = spawn_info.get("position",global_position)
	return _spawn_van_minion_at(kind_value,spawn_point)


func _spawn_van_minion_at(kind_value:int,spawn_point:Vector2) -> bool:
	spawn_point = _clamp_van_minion_spawn_to_map(spawn_point)
	var world:Node = get_tree().current_scene
	if world == null or MINION_SCENE == null:
		return false

	var minion:ball = MINION_SCENE.instantiate() as ball
	if minion == null:
		return false

	minion.Master = self
	minion.Master_name = name
	minion.Team = Team
	minion.inherit_master_attack_power = true
	minion.Target_Enemy = Target_Enemy
	minion.set("kind",kind_value)
	# V142：只有普通面包车的车载小弟基础生命减半；Boss 特殊化召出的三种小弟保持原生命。
	minion.set("spawn_health_multiplier",1.0 if _boss_specialized else normal_minion_health_multiplier)
	minion.name = Game.return_random_name(minion)

	world.add_child(minion,true)
	minion.global_position = spawn_point

	# 刚下车时短暂忽略面包车本体，避免车辆还在倒车就把自己的小弟顶进墙里。
	if minion is PhysicsBody2D:
		preload("res://classes/body_collision_exclusions.gd").add_exception(self,minion)
		preload("res://classes/body_collision_exclusions.gd").add_exception((minion as PhysicsBody2D),self)
		_release_van_minion_collision_exception(weakref(minion))
	_play_random_van_exit_audio()
	return true


func _find_clear_van_minion_spawn() -> Dictionary:
	var map_rect:Rect2 = TOOLS.map_rect(self)
	if map_rect.size.x <= 1.0 or map_rect.size.y <= 1.0:
		return {"ok": false}

	var forward:Vector2 = Vector2.RIGHT.rotated(_vehicle_heading)
	var side:Vector2 = forward.rotated(PI * 0.5)
	var inner:Rect2 = map_rect.grow(-(summon_clear_radius + 4.0))
	if inner.size.x <= 8.0 or inner.size.y <= 8.0:
		inner = map_rect

	# 优先左右后侧“车门区”，刻意避开倒车正中心轮迹；侧后方都堵住才考虑更远正后方。
	var side_sign:float = 1.0 if randf() < 0.5 else -1.0
	var side_offsets := PackedFloat32Array([
		side_sign * summon_side_clearance,
		-side_sign * summon_side_clearance,
		side_sign * (summon_side_clearance + 14.0),
		-side_sign * (summon_side_clearance + 14.0),
		side_sign * (summon_side_clearance + 30.0),
		-side_sign * (summon_side_clearance + 30.0),
		side_sign * (summon_side_clearance * 0.72),
		-side_sign * (summon_side_clearance * 0.72),
		0.0,
	])
	var rear_distances := PackedFloat32Array([
		summon_rear_offset,
		summon_rear_offset + 18.0,
		summon_rear_offset + 34.0,
		summon_rear_offset + 52.0,
		summon_rear_offset + 76.0,
	])

	var best_position:Vector2 = Vector2.ZERO
	var best_score:float = -INF
	for rear_distance:float in rear_distances:
		for side_offset:float in side_offsets:
			var jitter:float = randf_range(-summon_side_jitter,summon_side_jitter)
			var candidate:Vector2 = global_position - forward * rear_distance + side * (side_offset + jitter)
			if not inner.has_point(candidate):
				continue
			if not _van_minion_spawn_position_is_clear(candidate):
				continue
			var clearance_score:float = _van_minion_spawn_clearance_score(candidate)
			var side_bonus:float = clampf(absf(side_offset) / maxf(summon_side_clearance,1.0),0.0,1.5) * 0.10
			var score:float = clearance_score + side_bonus - rear_distance * 0.0008
			if score > best_score:
				best_score = score
				best_position = candidate

	if best_score == -INF:
		return {"ok": false}
	return {"ok": true,"position": best_position}


func _van_minion_spawn_position_is_clear(position_value:Vector2) -> bool:
	var shape := CircleShape2D.new()
	shape.radius = summon_clear_radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0,position_value)
	# layer 1 = 地图/墙，layer 2 = 人物；下车点两者都不能重叠。
	query.collision_mask = wall_probe_mask | 2
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var hits:Array[Dictionary] = get_world_2d().direct_space_state.intersect_shape(query,8)
	return hits.is_empty()


func _van_minion_spawn_clearance_score(position_value:Vector2) -> float:
	var space := get_world_2d().direct_space_state
	var sample_distance:float = maxf(summon_clear_radius * 3.2,64.0)
	var total_ratio:float = 0.0
	var min_ratio:float = 1.0
	var samples:int = 8
	for i:int in range(samples):
		var dir:Vector2 = Vector2.RIGHT.rotated(TAU * float(i) / float(samples))
		var query := PhysicsRayQueryParameters2D.create(
			position_value,
			position_value + dir * sample_distance,
			wall_probe_mask,
			[]
		)
		query.collide_with_bodies = true
		query.collide_with_areas = false
		var hit:Dictionary = space.intersect_ray(query)
		var ratio:float = 1.0
		if not hit.is_empty():
			var hit_position:Vector2 = hit.get("position",position_value + dir * sample_distance)
			ratio = clampf(position_value.distance_to(hit_position) / sample_distance,0.0,1.0)
		total_ratio += ratio
		min_ratio = minf(min_ratio,ratio)
	var average_ratio:float = total_ratio / float(samples)
	return min_ratio * 0.68 + average_ratio * 0.32


func _release_van_minion_collision_exception(minion_ref:WeakRef) -> void:
	await get_tree().create_timer(summon_collision_grace,false,true).timeout
	if not is_instance_valid(self):
		return
	var raw:Variant = minion_ref.get_ref()
	if not raw is PhysicsBody2D:
		return
	var minion_body:PhysicsBody2D = raw as PhysicsBody2D
	if is_instance_valid(minion_body):
		# V150：自己下车的小弟是同队动态单位，不能在 grace 后重新变成母车的实体路障。
		# 同队碰撞例外由 _sync_friendly_collision_exceptions() 持续维护。
		if minion_body is ball and TOOLS.same_side(self,minion_body as ball):
			return
		preload("res://classes/body_collision_exclusions.gd").remove_exception(self,minion_body)
		preload("res://classes/body_collision_exclusions.gd").remove_exception(minion_body,self)


func has_training_boss_specialization() -> bool:
	return true


func prepare_training_boss_specialization(_boss_multiplier:float) -> void:
	# 专属 Boss 形态使用明确的 1200 基础生命，不再叠加 World 的通用生命倍率；
	# Damage 等其它通用 Boss 数值倍率仍保留 World 已经应用后的值。
	Max_health = boss_specialized_health
	# World 的通用 Boss 强化会先把 Speed 也乘 Boss 倍率（默认 3x）。面包车自己的车辆驾驶
	# 又直接使用 Speed，不走普通 ball.move()，所以 V137 的 Boss 会从 135 直接冲到 405，
	# 这既过快，也让局部避墙/转向显得更笨。专属形态把速度恢复到原始车速附近，只保留轻微 1.05x。
	var generic_multiplier:float = maxf(_boss_multiplier,1.0)
	var pre_boss_speed:float = maxf(Speed / generic_multiplier,0.0)
	Speed = pre_boss_speed * maxf(boss_speed_multiplier,1.0)
	# 比普通面包车更频繁下人，但只做“略微”强化。
	summon_interval = maxf(summon_interval * boss_summon_interval_ratio,1.0)
	# Boss 仍只做轻度数值机动强化；驾驶/避墙 AI 与普通面包车使用完全同一套逻辑。
	var mobility:float = maxf(boss_mobility_multiplier,1.0)
	drive_acceleration *= mobility
	drive_brake *= lerpf(1.0,mobility,0.85)
	steering_rate *= mobility
	steering_acceleration *= mobility
	steering_input_smoothing *= lerpf(1.0,mobility,0.75)
	minimum_steering_factor = clampf(minimum_steering_factor + (mobility - 1.0) * 0.38,0.0,1.0)
	wall_escape_steering_multiplier *= lerpf(1.0,mobility,0.55)
	# 更快放弃已经失效的沿墙路线，避免特殊化后因为旧墙状态长时间不重新判断目标。
	wall_follow_min_time *= 0.72
	wall_follow_clear_time *= 0.72
	stuck_trigger_time *= 0.72
	_roam_repick_left = 0.0


func activate_training_boss_specialization(_boss_multiplier:float) -> void:
	_boss_specialized = true
	_boss_half_health_wave_triggered = false
	_boss_half_health_pending.clear()
	_boss_half_health_spawn_retry_queued = false
	_boss_half_health_spawn_serial = 0
	# prepare_* 在 ready 前把 Max_health 改为 1200；这里再次同步当前生命，确保专属 Boss 满血开场。
	health = Max_health


# V135：半血波次的主触发入口放到真实扣血回调，不再只依赖 _physics_process() 轮询。
func on_actual_health_damage_received(_actual_health_damage:float,_health_before:float) -> void:
	if not is_multiplayer_authority():
		return
	_check_boss_half_health_wave_trigger()


func _check_boss_half_health_wave_trigger() -> void:
	if not _boss_specialized or _boss_half_health_wave_triggered:
		return
	var threshold_health:float = float(Max_health) * boss_all_minions_health_ratio
	if float(health) > threshold_health:
		return
	_boss_half_health_wave_triggered = true
	_boss_half_health_pending = [
		MINION_SCRIPT.Kind.VAN_KNIFE,
		MINION_SCRIPT.Kind.VAN_BATON,
		MINION_SCRIPT.Kind.VAN_FIST,
	]
	_boss_half_health_spawn_serial += 1
	_queue_boss_half_health_wave_attempt()


func _queue_boss_half_health_wave_attempt() -> void:
	if not _boss_specialized or _boss_half_health_pending.is_empty() or _boss_half_health_spawn_retry_queued:
		return
	_boss_half_health_spawn_retry_queued = true
	# 伤害可能发生在 Area2D/PhysicsServer2D 的查询回调里；真正 add_child 必须退出物理 flush 后执行。
	call_deferred("_try_spawn_boss_half_health_wave_deferred",_boss_half_health_spawn_serial)


func _try_spawn_boss_half_health_wave_deferred(serial:int) -> void:
	_boss_half_health_spawn_retry_queued = false
	if not is_inside_tree() or not is_multiplayer_authority():
		return
	if not _boss_specialized or serial != _boss_half_health_spawn_serial or _boss_half_health_pending.is_empty():
		return

	# Boss 半血阶段不再复用“普通下车必须避开所有人物”的严格判定。
	# 三种小弟各用一个专属槽位，只要求不生成到墙里；即使 Boss 正在被敌群包围也必须能下车。
	var remaining:Array[int] = []
	var pending_count:int = _boss_half_health_pending.size()
	for index:int in range(pending_count):
		var kind_value:int = _boss_half_health_pending[index]
		var spawn_info:Dictionary = _find_boss_wave_spawn_position(index,pending_count)
		if not bool(spawn_info.get("ok",false)):
			remaining.append(kind_value)
			continue
		var spawn_point:Vector2 = spawn_info.get("position",global_position)
		if not _spawn_van_minion_at(kind_value,spawn_point):
			remaining.append(kind_value)
	_boss_half_health_pending = remaining


func _find_boss_wave_spawn_position(slot_index:int,slot_count:int) -> Dictionary:
	var map_rect:Rect2 = TOOLS.map_rect(self)
	if map_rect.size.x <= 1.0 or map_rect.size.y <= 1.0:
		return {"ok": false}
	var margin:float = summon_clear_radius + 5.0
	var inner:Rect2 = map_rect.grow(-margin)
	if inner.size.x <= 8.0 or inner.size.y <= 8.0:
		inner = map_rect

	var forward:Vector2 = Vector2.RIGHT.rotated(_vehicle_heading)
	var side:Vector2 = forward.rotated(PI * 0.5)
	var centered_index:float = float(slot_index) - float(maxi(slot_count - 1,0)) * 0.5
	var preferred_side:float = centered_index * maxf(summon_side_clearance * 1.35,44.0)
	var rear_base:float = maxf(summon_rear_offset + 14.0,62.0)
	var candidate_offsets:Array[Vector2] = [
		-forward * rear_base + side * preferred_side,
		-forward * (rear_base + 20.0) + side * preferred_side,
		-forward * rear_base + side * (preferred_side + 24.0),
		-forward * rear_base + side * (preferred_side - 24.0),
	]
	# 额外环形候选保证靠墙时仍能把人放到车身其它侧；优先顺序仍以后侧为主。
	for degrees:float in [-140.0,-110.0,-70.0,70.0,110.0,140.0,180.0]:
		candidate_offsets.append(forward.rotated(deg_to_rad(degrees)) * (rear_base + 24.0))

	for offset:Vector2 in candidate_offsets:
		var candidate:Vector2 = global_position + offset
		candidate.x = clampf(candidate.x,inner.position.x,inner.end.x)
		candidate.y = clampf(candidate.y,inner.position.y,inner.end.y)
		if _van_minion_spawn_position_is_wall_clear(candidate):
			return {"ok": true,"position": candidate}
	return {"ok": false}


func _van_minion_spawn_position_is_wall_clear(position_value:Vector2) -> bool:
	var shape := CircleShape2D.new()
	shape.radius = maxf(summon_clear_radius * 0.88,14.0)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0,position_value)
	query.collision_mask = wall_probe_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var hits:Array[Dictionary] = get_world_2d().direct_space_state.intersect_shape(query,4)
	return hits.is_empty()


func can_receive_hit_contact(source_hitbox:hitbox,_hurt:hurtbox) -> bool:
	if _crippled or source_hitbox == null:
		return true
	var raw:Node = source_hitbox.get_parent()
	if raw is ball:
		var source:ball = raw as ball
		if TOOLS.source_is_melee(source):
			var attacker:ball = TOOLS.effective_master(source)
			if attacker != null and attacker != self:
				var world = get_tree().current_scene
				if world != null and world.has_method("new_buff"):
					world.new_buff(attacker,self,"面包车_震荡",Buff.new(2,2.5,Buff.Buff_types.Attack_Cooling,1.20,Buff.Algorithms.mul),"cover")
	return true


func _setup_vehicle_audio() -> void:
	if _forward_audio_player != null and is_instance_valid(_forward_audio_player):
		return

	_forward_loop_stream = VAN_FORWARD_AUDIO.duplicate() as AudioStreamMP3
	_reverse_loop_stream = VAN_REVERSE_AUDIO.duplicate() as AudioStreamMP3
	if _forward_loop_stream != null:
		_forward_loop_stream.loop = true
		_forward_loop_stream.loop_offset = 0.0
	if _reverse_loop_stream != null:
		_reverse_loop_stream.loop = true
		_reverse_loop_stream.loop_offset = 0.0

	_forward_audio_player = _make_engine_loop_player("VanForwardAudio",_forward_loop_stream,forward_audio_volume_db)
	_reverse_audio_player = _make_engine_loop_player("VanReverseAudio",_reverse_loop_stream,reverse_audio_volume_db)
	_update_engine_audio()


func _make_engine_loop_player(player_name:String,stream:AudioStream,volume_db:float) -> AudioStreamPlayer2D:
	var player := AudioStreamPlayer2D.new()
	player.name = player_name
	player.stream = stream
	player.volume_db = volume_db
	player.max_distance = maxf(vehicle_audio_max_distance,100.0)
	player.attenuation = 1.0
	player.max_polyphony = 1
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	add_child(player)
	return player


func _update_engine_audio() -> void:
	if _forward_audio_player == null or _reverse_audio_player == null:
		return
	if not is_instance_valid(_forward_audio_player) or not is_instance_valid(_reverse_audio_player):
		return

	# 前进和倒车使用两个独立循环播放器。只要挂入倒档就立刻响倒车声，
	# 不再依赖同一个播放器 stop -> 换 stream -> play 的时序。
	var reverse_gear_active:bool = _is_reverse_gear_active()
	var forward_active:bool = (
		not reverse_gear_active
		and (_vehicle_speed > engine_audio_min_speed or _smoothed_speed_target > engine_audio_min_speed)
	)

	if reverse_gear_active:
		if _forward_audio_player.playing:
			_forward_audio_player.stop()
		# 倒车素材在实际混音里存在感偏弱，倒档一挂入就使用独立播放器强制播放，
		# 并给足增益；不会再被前进循环的 stop/play 时序覆盖。
		_reverse_audio_player.volume_db = reverse_audio_volume_db
		_reverse_audio_player.attenuation = 0.15
		_reverse_audio_player.max_distance = maxf(vehicle_audio_max_distance,2400.0)
		if not _reverse_audio_player.playing:
			_reverse_audio_player.play(0.0)
		_engine_audio_mode = -1
	elif forward_active:
		if _reverse_audio_player.playing:
			_reverse_audio_player.stop()
		_forward_audio_player.volume_db = forward_audio_volume_db
		if not _forward_audio_player.playing:
			_forward_audio_player.play()
		_engine_audio_mode = 1
	else:
		if _forward_audio_player.playing:
			_forward_audio_player.stop()
		if _reverse_audio_player.playing:
			_reverse_audio_player.stop()
		_engine_audio_mode = 0


func _play_random_van_exit_audio() -> void:
	if VAN_EXIT_AUDIOS.is_empty():
		return
	var now:int = Time.get_ticks_msec()
	# Boss 半血三人会在同一帧连续生成；视为一次“全员下车”事件，只随机播一段，避免三段短音效叠在一起爆音。
	if now - _last_summon_audio_msec < summon_audio_min_gap_msec:
		return
	_last_summon_audio_msec = now
	var stream:AudioStream = VAN_EXIT_AUDIOS[randi_range(0,VAN_EXIT_AUDIOS.size() - 1)] as AudioStream
	_play_vehicle_one_shot(stream,summon_audio_volume_db)


func _play_vehicle_one_shot(stream:AudioStream,volume_db:float) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.name = "VanOneShotAudio"
	player.stream = stream
	player.volume_db = volume_db
	player.max_distance = maxf(vehicle_audio_max_distance,100.0)
	player.attenuation = 1.0
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	add_child(player)
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func Die() -> void:
	# 面包车报废时，仍在场的三种小混混不陪车一起留场战斗：
	# 立刻播放“跑路了兄弟”，停手并沿最近地图边界逃出去。
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if node == null or not is_instance_valid(node):
			continue
		if node.get("Master") != self:
			continue
		if node.has_method("begin_van_flee_from_master_death"):
			node.call("begin_van_flee_from_master_death")

	_vehicle_speed = 0.0
	_vehicle_turn_rate = 0.0
	_smoothed_speed_target = 0.0
	_reverse_left = 0.0
	_ram_reverse_left = 0.0
	_wall_escape_left = 0.0
	_update_engine_audio()
	super()
	queue_free()
