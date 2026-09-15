extends MoonSanityCharacter

const TEX_NORMAL_STAND:Texture2D = preload("res://Images/characters/月计/殷红迷雾/普通站立.png")
const TEX_NORMAL_THRUST:Texture2D = preload("res://Images/characters/月计/殷红迷雾/普通刺.png")
const TEX_NORMAL_SLASH1:Texture2D = preload("res://Images/characters/月计/殷红迷雾/普通斩.png")
const TEX_NORMAL_SLASH2:Texture2D = preload("res://Images/characters/月计/殷红迷雾/普通斩2.png")
const TEX_NORMAL_DASH:Texture2D = preload("res://Images/characters/月计/殷红迷雾/普通冲刺.png")
const TEX_NORMAL_GUARD:Texture2D = preload("res://Images/characters/月计/殷红迷雾/普通防御.png")

const TEX_EGO_STAND:Texture2D = preload("res://Images/characters/月计/殷红迷雾/ego站立.png")
const TEX_EGO_BACKSTEP:Texture2D = preload("res://Images/characters/月计/殷红迷雾/ego后退.png")
const TEX_EGO_THRUST:Texture2D = preload("res://Images/characters/月计/殷红迷雾/ego突刺.png")
const TEX_EGO_SLASH1:Texture2D = preload("res://Images/characters/月计/殷红迷雾/ego斩.png")
const TEX_EGO_SLASH2:Texture2D = preload("res://Images/characters/月计/殷红迷雾/ego斩.png")
const TEX_EGO_HORIZONTAL:Texture2D = preload("res://Images/characters/月计/殷红迷雾/尸横遍野.png")
const TEX_EGO_DASH:Texture2D = preload("res://Images/characters/月计/殷红迷雾/ego冲刺.png")
const TEX_EGO_GUARD:Texture2D = preload("res://Images/characters/月计/殷红迷雾/ego防御.png")
const TEX_EXECUTE:Array[Texture2D] = [
	preload("res://Images/characters/月计/殷红迷雾/ego斩杀1.png"),
	preload("res://Images/characters/月计/殷红迷雾/斩杀2.png"),
	preload("res://Images/characters/月计/殷红迷雾/斩杀3.png"),
	preload("res://Images/characters/月计/殷红迷雾/斩杀4.png"),
	preload("res://Images/characters/月计/殷红迷雾/斩杀5.png"),
	preload("res://Images/characters/月计/殷红迷雾/斩杀6.png"),
]
const EGO_BGM:AudioStream = preload("res://audio/characters/月计/殷红迷雾/EGO_BGM.ogg")
const SFX_NORMAL_THRUST:AudioStream = preload("res://audio/characters/月计/殷红迷雾/刺.MP3")
const SFX_NORMAL_SLASH:AudioStream = preload("res://audio/characters/月计/殷红迷雾/斩1.MP3")
const SFX_EGO_THRUST:AudioStream = preload("res://audio/characters/月计/殷红迷雾/ego刺.MP3")
const SFX_EGO_SLASH_1:AudioStream = preload("res://audio/characters/月计/殷红迷雾/ego斩1.MP3")
const SFX_EGO_SLASH_2:AudioStream = preload("res://audio/characters/月计/殷红迷雾/ego斩2.MP3")
const SFX_EGO_HORIZONTAL:AudioStream = preload("res://audio/characters/月计/殷红迷雾/尸横遍野.MP3")
const SFX_EXECUTE:AudioStream = preload("res://audio/characters/月计/殷红迷雾/血雾弥漫.MP3")

# “血雾弥漫”音频中的 6 个独立声段起点（秒）。
# 由原始 8.176s 音频的静音间隔切分：每张斩杀图从对应声段开始一直保持到下一段。
const EXECUTION_CUE_TIMES = [0.0, 1.354, 2.400, 3.445, 4.529, 6.580]
const EXECUTION_AUDIO_LENGTH:float = 8.176
const BLADE_LIGHT_EFFECT_PATH:String = "res://scripts/effects/殷红迷雾_刀光.gd"

enum GeburaSfx {
	NORMAL_THRUST,
	NORMAL_SLASH,
	EGO_THRUST,
	EGO_SLASH_1,
	EGO_SLASH_2,
	EGO_HORIZONTAL,
	EXECUTE,
}

# 刀光类型与独立特效脚本中的 BladeLightKind 顺序保持一致。
enum GeburaBladeLightKind {
	THRUST, # 突刺直线刀光。
	SLASH, # 普通/E.G.O 弧形斩击刀光。
	HORIZONTAL, # 尸横遍野的长距离横向刀光。
	EXECUTION, # 血雾弥漫分段斩击刀光。
}

@export_category("殷红迷雾 - 基础战斗")
# 起手检查和实际伤害碰撞体是两套独立 Shape。
# 蓝色圆完整覆盖八方向攻击范围；起手判定使用这个圆与敌人的实际 CollisionObject2D/Area2D 区域做 Shape 重叠，
# 不再只检查敌人中心点。只要敌人的任意实际碰撞区域进入蓝圈，就可以触发普通攻击。
@export_range(1.0,1.80,0.01) var attack_check_scale:float = 1.18
@export_range(0.0,80.0,1.0) var attack_check_padding:float = 8.0
# E.G.O 下普通刺/斩的真实伤害体积与起手检查体积同时按此倍率放大。
@export_range(1.0,3.0,0.05) var ego_range_multiplier:float = 1.80
@export_range(0.02,0.5,0.01) var attack_pose_time:float = 0.13
@export_range(0.0,1.0,0.01) var positive_max_damage_bonus:float = 0.50
@export_range(0.0,1.0,0.01) var negative_max_damage_penalty:float = 0.25
@export_range(0.0,0.9,0.01) var negative_max_damage_reduction:float = 0.25

@export_category("殷红迷雾 - 实体攻击体积")
# 普通状态的真实攻击体积。E.G.O 时由 ego_range_multiplier 统一放大，
# 因此伤害范围和对应检查范围会一起扩大，不再各自维护一套互相打架的尺寸。
@export var thrust_hitbox_size:Vector2 = Vector2(220.0,64.0)
@export var slash_hitbox_size:Vector2 = Vector2(185.0,150.0)
# 下面这个只作为找不到 Map10x10 时的后备尺寸；正常运行时尸横遍野按 10x10 基准地图实时计算。
@export var ego_horizontal_hitbox_size:Vector2 = Vector2(144.0,48.0)
@export_range(0.10,1.20,0.01) var ego_horizontal_length_map10_ratio:float = 0.90
@export_range(0.05,0.80,0.01) var ego_horizontal_width_map10_ratio:float = 0.30
@export_range(20.0,180.0,1.0) var execution_hitbox_radius:float = 78.0
@export_range(0.02,0.40,0.01) var execution_column_width_map10_ratio:float = 0.10
@export_range(0.50,1.20,0.01) var execution_column_height_map10_ratio:float = 1.00
@export_range(0.5,4.0,0.05) var execution_column_raw_damage_multiplier:float = 1.50

@export_category("殷红迷雾 - 防御 / 反击")
@export_range(0.1,3.0,0.05) var guard_duration:float = 0.85
@export_range(0.5,12.0,0.1) var guard_cooldown:float = 4.2
@export_range(0.0,1.0,0.01) var normal_guard_damage_reduction:float = 0.50
@export_range(40.0,400.0,1.0) var counter_check_range:float = 145.0
@export_range(100.0,1800.0,10.0) var counter_dash_speed:float = 760.0
@export_range(10.0,100.0,1.0) var counter_arrival_gap:float = 52.0

@export_category("殷红迷雾 - E.G.O")
@export_range(0.0,1.0,0.01) var ego_damage_reduction:float = 0.50
@export_range(1.0,4.0,0.05) var ego_damage_multiplier:float = 2.0
@export_range(0.1,1.0,0.05) var ego_attack_cooldown_multiplier:float = 0.50
@export_range(0.0,30.0,0.1) var ego_execution_unlock_delay:float = 5.0
@export_range(0.05,0.95,0.01) var ego_execution_health_ratio:float = 0.50
@export_range(0.0,30.0,0.1) var ego_horizontal_unlock_delay:float = 5.0
@export_range(1.0,30.0,0.25) var ego_horizontal_cooldown:float = 10.0
@export_range(0.5,4.0,0.05) var ego_horizontal_raw_damage_multiplier:float = 1.35
@export_range(0.05,2.0,0.05) var ego_horizontal_pose_time:float = 0.55
@export_range(5.0,120.0,1.0) var ego_horizontal_backstep_distance:float = 42.0
@export_range(0.02,0.60,0.01) var ego_horizontal_backstep_pause:float = 0.16
@export_range(10.0,120.0,1.0) var ego_horizontal_arrival_gap:float = 42.0
@export_range(100.0,2200.0,10.0) var ego_dash_speed:float = 1000.0
@export_range(5.0,120.0,1.0) var ego_backstep_distance:float = 46.0
@export_range(10.0,120.0,1.0) var ego_thrust_behind_distance:float = 42.0
@export_range(-40.0,6.0,0.5) var ego_bgm_volume_db:float = -5.0

@export_category("殷红迷雾 - 视觉")
@export_range(0.05,0.6,0.01) var visual_rotation_recover_time:float = 0.22

@export_category("殷红迷雾 - 血肉拖尾")
@export var blade_light_enabled:bool = true
@export_range(0.18,1.20,0.01) var blade_light_lifetime:float = 0.72
@export_range(0.5,2.0,0.05) var blade_light_normal_length_scale:float = 1.42
@export_range(0.5,2.5,0.05) var blade_light_ego_length_scale:float = 1.72
@export_range(8.0,180.0,1.0) var blade_light_normal_width:float = 52.0
@export_range(8.0,220.0,1.0) var blade_light_ego_width:float = 78.0
@export var blade_light_normal_color:Color = Color(0.92,0.0,0.012,1.0)
@export var blade_light_ego_color:Color = Color(1.0,0.0,0.008,1.0)

@export_category("殷红迷雾 - 位移残影")
@export var displacement_afterimage_enabled:bool = true
@export_range(0.015,0.15,0.005) var displacement_afterimage_interval:float = 0.045
@export_range(0.05,0.6,0.01) var displacement_afterimage_fade_time:float = 0.22
@export_range(0.05,0.9,0.01) var displacement_afterimage_alpha:float = 0.38

var ego_active:bool = false
var _ego_started_msec:int = 0
var _base_attack_cooling:float = 1.0
var _guarding:bool = false
var _guard_counter_used:bool = false
var _movement_invulnerable:bool = false
var _action_locked:bool = false
var _incoming_hit_for_sanity:float = 0.0
var _visual_direction_index:int = 4
var _visual_pose:StringName = &"stand"
var _ego_bgm_player:AudioStreamPlayer = null
var _action_serial:int = 0
var _visual_recover_tween:Tween = null
var _visual_face_right:bool = false
var _last_horizontal_msec:int = -1000000000
var _owned_sfx_players:Array[AudioStreamPlayer] = []
var _execution_hard_lock:bool = false
var _execution_lock_position:Vector2 = Vector2.ZERO

func _ready() -> void:
	Has_Collision_Damage = false
	Can_Skill = true
	Health_Restore = 0
	_base_attack_cooling = maxf(Attack_Cooling,0.05)
	Skill_Cooling = guard_cooldown
	image_color = Color.WHITE
	image_color_mix = 0.0
	super._ready()
	_apply_visual_local(&"stand",_visual_direction_index)
	_check_ego_trigger()

func change_sanity(delta:float) -> void:
	super.change_sanity(delta)
	_check_ego_trigger()

func _check_ego_trigger() -> void:
	if ego_active:
		return
	if sanity >= SANITY_MAX - 0.001 or sanity <= SANITY_MIN + 0.001:
		_enter_ego()

func _enter_ego() -> void:
	if ego_active:
		return
	ego_active = true
	_ego_started_msec = Time.get_ticks_msec()
	Attack_Cooling = maxf(_base_attack_cooling * ego_attack_cooldown_multiplier,0.05)
	if _sanity_bar != null and is_instance_valid(_sanity_bar):
		_sanity_bar.set_overdrive(true)
	_start_ego_bgm_local()
	_apply_visual_local(&"stand",_visual_direction_index)
	if multiplayer.has_multiplayer_peer():
		_remote_enter_ego.rpc()

@rpc("authority","call_remote","reliable")
func _remote_enter_ego() -> void:
	if ego_active:
		return
	ego_active = true
	_ego_started_msec = Time.get_ticks_msec()
	Attack_Cooling = maxf(_base_attack_cooling * ego_attack_cooldown_multiplier,0.05)
	if _sanity_bar != null and is_instance_valid(_sanity_bar):
		_sanity_bar.set_overdrive(true)
	_start_ego_bgm_local()
	_apply_visual_local(&"stand",_visual_direction_index)

func _start_ego_bgm_local() -> void:
	if _ego_bgm_player != null and is_instance_valid(_ego_bgm_player):
		if not _ego_bgm_player.playing:
			_ego_bgm_player.play()
		return
	_ego_bgm_player = AudioStreamPlayer.new()
	_ego_bgm_player.name = "GeburaEgoBGM"
	_ego_bgm_player.stream = EGO_BGM
	_ego_bgm_player.volume_db = ego_bgm_volume_db
	add_child(_ego_bgm_player)
	_ego_bgm_player.finished.connect(_on_ego_bgm_finished)
	_ego_bgm_player.play()

func _on_ego_bgm_finished() -> void:
	if ego_active and _ego_bgm_player != null and is_instance_valid(_ego_bgm_player):
		_ego_bgm_player.play()

# 造成的任何伤害都会走 ball.effective_outgoing_damage()；在这里统一套理智/E.G.O倍率。
func effective_outgoing_damage(raw_damage:float) -> float:
	var base:float = super.effective_outgoing_damage(raw_damage)
	if base <= 0.0:
		return 0.0
	if ego_active:
		return base * ego_damage_multiplier
	var ratio:float = clampf(sanity / SANITY_MAX,-1.0,1.0)
	if ratio >= 0.0:
		return base * (1.0 + positive_max_damage_bonus * ratio)
	return base * (1.0 - negative_max_damage_penalty * absf(ratio))

# 理智损失永远按“减伤前的原始伤害”计算，所以负理智的防御提升、普通防御、E.G.O减伤
# 都不会让理智掉得更少。闪避/斩杀冲刺属于真正无敌，不视为受到伤害。
func take_damage(damage:float,ignore_block:bool = false) -> void:
	if damage <= 0.0:
		return
	if _movement_invulnerable:
		return
	_incoming_hit_for_sanity = maxf(damage,0.0)
	_apply_raw_damage_sanity_loss(_incoming_hit_for_sanity)

	var old_reduction:float = Damage_reduction
	var reduction:float = 0.0
	if ego_active:
		reduction = ego_damage_reduction
	elif sanity < 0.0:
		reduction = negative_max_damage_reduction * clampf(absf(sanity) / SANITY_MAX,0.0,1.0)

	if _guarding:
		if ego_active:
			reduction = 1.0
		else:
			reduction = 1.0 - (1.0 - reduction) * (1.0 - normal_guard_damage_reduction)

	Damage_reduction = clampf(reduction,0.0,1.0)
	super.take_damage(damage,ignore_block)
	Damage_reduction = old_reduction
	_incoming_hit_for_sanity = 0.0

# 禁用月计基类“按实际扣血量掉理智”的默认实现，避免减伤后重复计算。
func on_actual_health_damage_received(_actual_health_damage:float,_health_before:float) -> void:
	pass

func _apply_raw_damage_sanity_loss(raw_damage:float) -> void:
	if not is_inside_tree() or not is_multiplayer_authority() or raw_damage <= 0.0:
		return
	var ratio:float = raw_damage / maxf(float(Max_health),1.0)
	var loss:float = maxf(sanity_min_loss_per_damage_event,ratio * sanity_loss_per_own_healthbar)
	change_sanity(-loss)

func Skill() -> void:
	if not is_multiplayer_authority() or _action_locked:
		Using_Skill = false
		return
	Using_Skill = true
	_guarding = true
	_guard_counter_used = false
	_action_serial += 1
	var serial:int = _action_serial
	_set_visual(&"guard",_visual_direction_index)
	_guard_window(serial)

func _guard_window(serial:int) -> void:
	await get_tree().create_timer(guard_duration).timeout
	if not is_inside_tree() or serial != _action_serial:
		return
	_guarding = false
	Using_Skill = false
	_set_visual(&"stand",_visual_direction_index)

func _on_hurtbox_on_hurt(incoming_hit:hitbox) -> void:
	if not is_multiplayer_authority() or not _guarding or _guard_counter_used:
		return
	var attacker:ball = _incoming_hit_attacker(incoming_hit)
	if attacker == null or not is_instance_valid(attacker) or attacker == self:
		return
	if not _is_enemy_ball(attacker):
		return
	_guard_counter_used = true
	# 一次防御只反击一次；反击真正启动时就结束防御窗口。
	# 旧代码在这里递增 _action_serial，却让旧 _guard_window() 因序号不匹配直接 return，
	# 导致 _guarding 永远保持 true。E.G.O 防御又是完全免伤，于是会永久无敌且 Attack() 永远被拒绝。
	_guarding = false
	Using_Skill = false
	_counter_sequence(attacker)

func Attack() -> void:
	super()
	if not is_multiplayer_authority() or _action_locked or _guarding:
		Attacking = false
		return

	# 直接控制：左键永远按鼠标八方向出普通攻击，不要求敌人存在，也不触发 AI 的处决/横斩选靶。
	if has_player_control_aim():
		Attacking = true
		_action_serial += 1
		var manual_serial:int = _action_serial
		_manual_attack_sequence(player_control_aim_direction(direction),manual_serial)
		return

	# E.G.O 的处决/尸横遍野保留原本的特殊远程触发逻辑。
	var nearest_target:ball = _nearest_enemy_ball()
	if nearest_target == null:
		Attacking = false
		return
	var special_ready:bool = ego_active and (_can_execute(nearest_target) or _can_horizontal_split())

	# 普通刺/斩不能只看敌人中心。蓝色检测圆与敌人的任意实际碰撞区域相交，就应该起手。
	# 同时从已经进入检测圆的敌人中选择最近者，避免“最近敌人中心没进圈，却挡住另一个已进圈敌人”的情况。
	var target:ball = nearest_target if special_ready else _nearest_enemy_overlapping_attack_check()
	if target == null:
		Attacking = false
		return

	Attacking = true
	_action_serial += 1
	var serial:int = _action_serial
	_attack_sequence(target,serial)

func _regular_attack_hitbox_size(dir_idx:int) -> Vector2:
	var base_size:Vector2 = thrust_hitbox_size if posmod(dir_idx,2) == 0 else slash_hitbox_size
	var multiplier:float = maxf(ego_range_multiplier,1.0) if ego_active else 1.0
	return Vector2(maxf(base_size.x * multiplier,1.0),maxf(base_size.y * multiplier,1.0))


func _regular_attack_forward_ratio(dir_idx:int) -> float:
	return 0.40 if posmod(dir_idx,2) == 0 else 0.36


func _attack_volume_outer_radius_for_size(size:Vector2,forward_ratio:float) -> float:
	# 真实矩形攻击体积以人物原点为参照：中心在前方 offset，矩形再向前/侧面延伸半尺寸。
	# 取最远角到原点的距离，就是能完整包住该方向攻击矩形的最小圆半径。
	var half_size:Vector2 = size * 0.5
	var forward_offset:float = size.x * forward_ratio
	var far_corner:Vector2 = Vector2(forward_offset + half_size.x,half_size.y)
	return far_corner.length()


func _regular_attack_check_radius_local() -> float:
	# 检查区不是某一个方向的长方形，而是完整覆盖“上下左右刺 + 四个斜向斩”
	# 全部真实攻击体积的同心圆。由于八方向只是把同一矩形旋转，取刺/斩两类
	# 最远角中的最大值即可得到八方向并集的最小包围圆。
	var thrust_size:Vector2 = _regular_attack_hitbox_size(0)
	var slash_size:Vector2 = _regular_attack_hitbox_size(1)
	var thrust_radius:float = _attack_volume_outer_radius_for_size(
		thrust_size,
		_regular_attack_forward_ratio(0)
	)
	var slash_radius:float = _attack_volume_outer_radius_for_size(
		slash_size,
		_regular_attack_forward_ratio(1)
	)
	var attack_outer_radius:float = maxf(thrust_radius,slash_radius)

	# 起手圆要比八方向真实伤害并集再宽一圈：敌人的碰撞边缘刚进入蓝圈就能起手。
	# attack_hitbox_size 在 E.G.O 下已经整体 × ego_range_multiplier；padding 同比放大，
	# 因而 E.G.O 的攻击范围和检查范围仍然整体按相同比例扩大。
	var ego_mult:float = maxf(ego_range_multiplier,1.0) if ego_active else 1.0
	return attack_outer_radius * maxf(attack_check_scale,1.0) + maxf(attack_check_padding,0.0) * ego_mult


func _regular_attack_check_radius_world() -> float:
	# 角色节点一般是等比缩放；取全局 X/Y 最大缩放保证蓝色圆不会漏掉真实攻击体积。
	var scale_v:Vector2 = global_transform.get_scale().abs()
	var world_scale:float = maxf(maxf(scale_v.x,scale_v.y),0.001)
	return _regular_attack_check_radius_local() * world_scale


func _nearest_enemy_overlapping_attack_check() -> ball:
	# 不再依赖 direct_space_state.intersect_shape() 的碰撞层/Area 注册状态。
	# 蓝色检测圆直接与每个敌人的“人物本体 + hurtbox”实际 Shape 做几何相交：
	# 调试里看到实体区域进入蓝圈，起手判定就一定与之保持一致。
	var best:ball = null
	var best_d2:float = INF
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var candidate:ball = raw as ball
		if not _valid_enemy(candidate):
			continue
		if not _enemy_occupied_region_overlaps_attack_check(candidate):
			continue
		var d2:float = global_position.distance_squared_to(candidate.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = candidate
	return best


func _enemy_occupied_region_overlaps_attack_check(candidate:ball) -> bool:
	if not _valid_enemy(candidate):
		return false

	var circle := CircleShape2D.new()
	circle.radius = maxf(_regular_attack_check_radius_world(),0.001)
	var circle_xform := Transform2D(0.0,global_position)
	var found_relevant_shape:bool = false

	# 角色场景普遍同时拥有根 CharacterBody2D 的 CollisionShape2D、hitbox 和 hurtbox。
	# 起手检测只认“人物占据区域/受击区域”，不认敌人的攻击 hitbox；否则一把很长的武器
	# 伸进蓝圈也会让殷红迷雾提前攻击。
	for raw_shape:Node in candidate.find_children("*","CollisionShape2D",true,false):
		if not raw_shape is CollisionShape2D:
			continue
		var shape_node:CollisionShape2D = raw_shape as CollisionShape2D
		if shape_node.disabled or shape_node.shape == null:
			continue
		if _collision_shape_belongs_to_outgoing_hitbox(shape_node,candidate):
			continue
		found_relevant_shape = true
		if circle.collide(circle_xform,shape_node.shape,shape_node.global_transform):
			return true

	# 兼容少数没有 CollisionShape2D 子节点的特殊角色。
	# 这种角色只能退回中心点，但不会影响正常角色的“实际区域进入即触发”。
	if not found_relevant_shape:
		return global_position.distance_to(candidate.global_position) <= circle.radius
	return false


func _collision_shape_belongs_to_outgoing_hitbox(shape_node:CollisionShape2D,owner_ball:ball) -> bool:
	var node:Node = shape_node.get_parent()
	while node != null and node != owner_ball:
		if node is hurtbox:
			return false
		if node is hitbox:
			return true
		node = node.get_parent()
	return false


func _target_inside_attack_check(target:ball,_dir_idx:int) -> bool:
	return _enemy_occupied_region_overlaps_attack_check(target)


# 威胁调试的标准“蓝色检测范围”接口。
# 殷红迷雾的普通起手区是一个以人物为圆心、完整覆盖八方向全部真实攻击体积的圆；
# 白->红仍只显示攻击动作真正生成出来的 Area2D/CollisionShape2D。
func get_debug_detection_regions() -> Array[Dictionary]:
	var result:Array[Dictionary] = []
	if health <= 0 or not is_inside_tree():
		return result

	result.append({
		"shape":"circle",
		"position":global_position,
		"radius":_regular_attack_check_radius_world(),
		"kind":"attack_detection",
	})

	# 防御反击是另一套独立检查范围，防御时照常显示。
	if _guarding:
		result.append({
			"shape":"circle",
			"position":global_position,
			"radius":maxf(counter_check_range,1.0),
			"kind":"counter_detection",
		})
	return result


func _attack_sequence(target:ball,serial:int) -> void:
	_action_locked = true
	if not _valid_enemy(target):
		_finish_action(serial)
		return

	if _can_execute(target):
		await _execute_target(target,serial)
		_finish_action(serial)
		return

	if _can_horizontal_split():
		await _perform_horizontal_split(target,serial)
		_finish_action(serial)
		return

	if not _valid_enemy(target):
		_finish_action(serial)
		return
	await _perform_attack_on(target,serial,false)
	_finish_action(serial)

func _manual_attack_sequence(aim_direction:Vector2,serial:int) -> void:
	_action_locked = true
	if serial != _action_serial:
		_finish_action(serial)
		return
	if aim_direction.length_squared() <= 0.000001:
		aim_direction = direction if direction.length_squared() > 0.000001 else Vector2.RIGHT
	var dir_idx:int = _direction_index(aim_direction)
	var attack_dir:Vector2 = _direction_vector(dir_idx)
	var is_thrust:bool = dir_idx % 2 == 0
	var damage_amount:float = attack_damage()
	direction = attack_dir

	if ego_active and is_thrust:
		_set_visual(&"backstep",dir_idx)
		await _dash_by_vector(-attack_dir * ego_backstep_distance,ego_dash_speed,true)
		if serial != _action_serial:
			_finish_action(serial)
			return
		_set_visual(&"thrust",dir_idx)
		_play_gebura_sfx(GeburaSfx.EGO_THRUST)
		var ego_thrust_size:Vector2 = _regular_attack_hitbox_size(dir_idx)
		var ego_area:Area2D = _create_local_rect_attack_volume(attack_dir,ego_thrust_size,damage_amount,ego_thrust_size.x * _regular_attack_forward_ratio(dir_idx))
		_spawn_blade_light_on_area(GeburaBladeLightKind.THRUST,ego_area,ego_thrust_size,true,1.0)
		await _dash_by_vector(attack_dir * maxf(ego_thrust_behind_distance,ego_thrust_size.x * 0.75),ego_dash_speed,true)
		await _finish_attack_volume_window(ego_area,attack_pose_time)
		_finish_action(serial)
		return

	if is_thrust:
		_set_visual(&"thrust",dir_idx)
		_play_gebura_sfx(GeburaSfx.EGO_THRUST if ego_active else GeburaSfx.NORMAL_THRUST)
		var thrust_size:Vector2 = _regular_attack_hitbox_size(dir_idx)
		var thrust_area:Area2D = _create_local_rect_attack_volume(attack_dir,thrust_size,damage_amount,thrust_size.x * _regular_attack_forward_ratio(dir_idx))
		_spawn_blade_light_on_area(GeburaBladeLightKind.THRUST,thrust_area,thrust_size,ego_active,1.0)
		await _finish_attack_volume_window(thrust_area,attack_pose_time)
		_finish_action(serial)
		return

	_set_visual(&"slash1",dir_idx)
	if ego_active:
		_play_gebura_sfx(GeburaSfx.EGO_SLASH_1 if randi() % 2 == 0 else GeburaSfx.EGO_SLASH_2)
	else:
		_play_gebura_sfx(GeburaSfx.NORMAL_SLASH)
	var slash_size:Vector2 = _regular_attack_hitbox_size(dir_idx)
	var slash_area:Area2D = _create_local_rect_attack_volume(attack_dir,slash_size,damage_amount,slash_size.x * _regular_attack_forward_ratio(dir_idx))
	_spawn_blade_light_on_area(GeburaBladeLightKind.SLASH,slash_area,slash_size,ego_active,1.0)
	await _finish_attack_volume_window(slash_area,attack_pose_time)
	if ego_active and serial == _action_serial:
		_set_visual(&"slash2",dir_idx)
		var slash_area_2:Area2D = _create_local_rect_attack_volume(attack_dir,slash_size,damage_amount,slash_size.x * _regular_attack_forward_ratio(dir_idx))
		_spawn_blade_light_on_area(GeburaBladeLightKind.SLASH,slash_area_2,slash_size,true,-1.0)
		await _finish_attack_volume_window(slash_area_2,attack_pose_time)
	_finish_action(serial)


func _counter_sequence(attacker:ball) -> void:
	if _action_locked:
		return
	_action_locked = true
	_action_serial += 1
	var serial:int = _action_serial
	var target:ball = attacker
	if not _valid_enemy(target):
		_finish_action(serial)
		return
	if global_position.distance_to(target.global_position) > counter_check_range:
		await _dash_to_target_gap(target,counter_arrival_gap,counter_dash_speed,false)
	if _valid_enemy(target):
		await _perform_attack_on(target,serial,true)
		var killed:bool = not _valid_enemy(target)
		if killed:
			var next_target:ball = _nearest_enemy_ball()
			if next_target != null:
				await _dash_to_target_gap(next_target,counter_arrival_gap,counter_dash_speed,false)
				if _valid_enemy(next_target):
					await _perform_attack_on(next_target,serial,true)
	_finish_action(serial)

func _perform_attack_on(target:ball,serial:int,_is_counter:bool) -> void:
	if not _valid_enemy(target) or serial != _action_serial:
		return
	var to_target:Vector2 = target.global_position - global_position
	if to_target.length_squared() <= 0.0001:
		to_target = Vector2.LEFT
	var dir_idx:int = _direction_index(to_target)
	var attack_dir:Vector2 = _direction_vector(dir_idx)
	var is_thrust:bool = dir_idx % 2 == 0
	var damage_amount:float = attack_damage()

	if ego_active and is_thrust:
		# E.G.O 突刺：后撤和穿刺位移各自只在位移函数内部开启无敌。
		# 不再把 _movement_invulnerable 长时间挂在整个攻击协程上，避免目标死亡/时间停止时留下永久无敌。
		_set_visual(&"backstep",dir_idx)
		await _dash_by_vector(-attack_dir * ego_backstep_distance,ego_dash_speed,true)
		if not _valid_enemy(target):
			return
		var behind:Vector2 = target.global_position + attack_dir * ego_thrust_behind_distance
		_set_visual(&"thrust",dir_idx)
		_play_gebura_sfx(GeburaSfx.EGO_THRUST)
		var ego_thrust_size:Vector2 = _regular_attack_hitbox_size(dir_idx)
		var thrust_area:Area2D = _create_local_rect_attack_volume(attack_dir,ego_thrust_size,damage_amount,ego_thrust_size.x * _regular_attack_forward_ratio(dir_idx))
		_spawn_blade_light_on_area(GeburaBladeLightKind.THRUST,thrust_area,ego_thrust_size,true,1.0) # 刀光直接读取真实突刺 Area2D 的世界 Transform，保证和伤害位置重合。
		await _dash_to_point(behind,ego_dash_speed,true)
		await _finish_attack_volume_window(thrust_area,attack_pose_time)
		return

	if is_thrust:
		_set_visual(&"thrust",dir_idx)
		_play_gebura_sfx(GeburaSfx.EGO_THRUST if ego_active else GeburaSfx.NORMAL_THRUST)
		var thrust_size:Vector2 = _regular_attack_hitbox_size(dir_idx)
		var thrust_area:Area2D = _create_local_rect_attack_volume(attack_dir,thrust_size,damage_amount,thrust_size.x * _regular_attack_forward_ratio(dir_idx))
		_spawn_blade_light_on_area(GeburaBladeLightKind.THRUST,thrust_area,thrust_size,ego_active,1.0) # 普通/E.G.O 突刺刀光都绑定真实伤害矩形中心。
		await _finish_attack_volume_window(thrust_area,attack_pose_time)
		return

	_set_visual(&"slash1",dir_idx)
	if ego_active:
		_play_gebura_sfx(GeburaSfx.EGO_SLASH_1 if randi() % 2 == 0 else GeburaSfx.EGO_SLASH_2)
	else:
		_play_gebura_sfx(GeburaSfx.NORMAL_SLASH)
	var slash_size:Vector2 = _regular_attack_hitbox_size(dir_idx)
	var slash_area:Area2D = _create_local_rect_attack_volume(attack_dir,slash_size,damage_amount,slash_size.x * _regular_attack_forward_ratio(dir_idx))
	_spawn_blade_light_on_area(GeburaBladeLightKind.SLASH,slash_area,slash_size,ego_active,1.0) # 第一斩的月牙中心直接跟随真实伤害 Area2D。
	await _finish_attack_volume_window(slash_area,attack_pose_time)
	if ego_active and _valid_enemy(target):
		_set_visual(&"slash2",dir_idx)
		var slash_area_2:Area2D = _create_local_rect_attack_volume(attack_dir,slash_size,damage_amount,slash_size.x * _regular_attack_forward_ratio(dir_idx))
		_spawn_blade_light_on_area(GeburaBladeLightKind.SLASH,slash_area_2,slash_size,true,-1.0) # E.G.O 第二斩使用同一真实伤害框，但月牙反向扫回。
		await _finish_attack_volume_window(slash_area_2,attack_pose_time)

func _can_horizontal_split() -> bool:
	if not ego_active:
		return false
	var now:int = Time.get_ticks_msec()
	var elapsed:float = float(now - _ego_started_msec) / 1000.0
	if elapsed < ego_horizontal_unlock_delay:
		return false
	return float(now - _last_horizontal_msec) / 1000.0 >= ego_horizontal_cooldown


func _perform_horizontal_split(reference_target:ball,serial:int) -> void:
	if not ego_active or serial != _action_serial:
		return
	_last_horizontal_msec = Time.get_ticks_msec()

	var aim:Vector2 = Vector2.LEFT
	if _valid_enemy(reference_target):
		aim = reference_target.global_position - global_position
	elif direction.length_squared() > 0.0001:
		aim = direction
	if aim.length_squared() <= 0.0001:
		aim = Vector2.LEFT
	var approach_idx:int = _direction_index(aim)
	var approach_dir:Vector2 = _direction_vector(approach_idx)

	# 尸横遍野：先用后撤图实际退一步，短暂停顿，再冲到目标身前。
	# 两段位移都走统一 dash，所以都会生成残影。
	_set_visual(&"backstep",approach_idx)
	await _dash_by_vector(-approach_dir * maxf(ego_horizontal_backstep_distance,0.0),ego_dash_speed,true)
	if not is_inside_tree() or serial != _action_serial or not ego_active:
		return
	if ego_horizontal_backstep_pause > 0.0:
		await get_tree().create_timer(ego_horizontal_backstep_pause,true,false,true).timeout
	if not is_inside_tree() or serial != _action_serial or not ego_active:
		return

	if _valid_enemy(reference_target):
		_set_visual(&"dash",approach_idx)
		await _dash_to_target_gap(reference_target,ego_horizontal_arrival_gap,ego_dash_speed,true)
		if not is_inside_tree() or serial != _action_serial or not ego_active:
			return

	var dir:Vector2 = approach_dir
	if _valid_enemy(reference_target):
		dir = reference_target.global_position - global_position
	if dir.length_squared() <= 0.0001:
		dir = approach_dir
	var dir_idx:int = _direction_index(dir)
	var attack_dir:Vector2 = _direction_vector(dir_idx)
	_set_visual(&"horizontal",dir_idx)
	_play_gebura_sfx(GeburaSfx.EGO_HORIZONTAL)

	# 按 Map10x10 的世界尺寸实时计算：长度约 0.9 倍地图，宽度约 0.3 倍地图。
	# 矩形从殷红迷雾身前向攻击方向延伸，不是全场点名伤害。
	var reference_rect:Rect2 = _map10x10_world_rect()
	var horizontal_size:Vector2 = ego_horizontal_hitbox_size
	if reference_rect.size.x > 0.0 and reference_rect.size.y > 0.0:
		horizontal_size = Vector2(
			maxf(reference_rect.size.x * ego_horizontal_length_map10_ratio,1.0),
			maxf(reference_rect.size.y * ego_horizontal_width_map10_ratio,1.0)
		)
	var damage_amount:float = attack_damage(ego_horizontal_raw_damage_multiplier)
	var horizontal_area:Area2D = _create_local_rect_attack_volume(
		attack_dir,
		horizontal_size,
		damage_amount,
		horizontal_size.x * 0.5
	)
	_spawn_blade_light_on_area(GeburaBladeLightKind.HORIZONTAL,horizontal_area,horizontal_size,true,1.0) # 尸横遍野的刀光完整覆盖真实横向攻击矩形。
	await _finish_attack_volume_window(horizontal_area,maxf(ego_horizontal_pose_time,0.05))

func _can_execute(target:ball) -> bool:
	if not ego_active or not _valid_enemy(target):
		return false
	var elapsed:float = float(Time.get_ticks_msec() - _ego_started_msec) / 1000.0
	if elapsed < ego_execution_unlock_delay:
		return false
	return float(target.health) / maxf(float(target.Max_health),1.0) < ego_execution_health_ratio

func _execute_target(target:ball,serial:int) -> void:
	if not _valid_enemy(target):
		return
	_movement_invulnerable = true
	var to_target:Vector2 = target.global_position - global_position
	var dir_idx:int = _direction_index(to_target)
	_set_visual(&"dash",dir_idx)
	# 斩杀眩晕不调用 apply_stun()，因此不会生成眩晕图标。
	target.dizziness = true
	var target_dir:Vector2 = to_target.normalized() if to_target.length_squared() > 0.0001 else Vector2.LEFT
	var stop_point:Vector2 = target.global_position - target_dir * 46.0
	await _dash_to_point(stop_point,ego_dash_speed,true)
	if not _valid_enemy(target) or serial != _action_serial:
		_movement_invulnerable = false
		return

	# “血雾弥漫”正式演出开始后锁死世界位置。期间不能被移动、击退、外部 Repel
	# 或其它技能拖走；每个 physics frame 都恢复到这一点。
	_execution_hard_lock = true
	_execution_lock_position = global_position
	velocity = Vector2.ZERO
	Repel = Vector2.ZERO

	# 冲到位以后才开始音频，确保第一张图就是第一段声音。执行帧全部保持正常角度，
	# 只允许水平镜像朝向目标，不再随 8 方向旋转。
	var execute_player:AudioStreamPlayer = _play_gebura_sfx(GeburaSfx.EXECUTE)
	var frame_index:int = 0
	_set_visual(&"execute_0",dir_idx)
	_spawn_execution_blade_light(target_dir,target.global_position,frame_index) # 第一张斩杀图围绕被处决目标闪出。

	if execute_player != null and is_instance_valid(execute_player):
		await get_tree().process_frame
		var started:bool = execute_player.playing
		var safety_elapsed:float = 0.0
		while is_inside_tree() and serial == _action_serial and is_instance_valid(execute_player):
			if execute_player.playing:
				started = true
				var playback_pos:float = execute_player.get_playback_position()
				while frame_index + 1 < EXECUTION_CUE_TIMES.size() and playback_pos >= float(EXECUTION_CUE_TIMES[frame_index + 1]):
					frame_index += 1
					_set_visual(StringName("execute_%d" % frame_index),dir_idx)
					_spawn_execution_blade_light(target_dir,target.global_position if _valid_enemy(target) else global_position,frame_index) # 每个声段围绕目标位置生成一束新的刀光。
			elif started:
				break
			var dt:float = maxf(get_process_delta_time(),0.001)
			safety_elapsed += dt
			if safety_elapsed > EXECUTION_AUDIO_LENGTH + 1.0:
				break
			await get_tree().process_frame
	else:
		var fallback_elapsed:float = 0.0
		while fallback_elapsed < EXECUTION_AUDIO_LENGTH and serial == _action_serial and is_inside_tree():
			var next_index:int = frame_index + 1
			if next_index < EXECUTION_CUE_TIMES.size() and fallback_elapsed >= float(EXECUTION_CUE_TIMES[next_index]):
				frame_index = next_index
				_set_visual(StringName("execute_%d" % frame_index),dir_idx)
				_spawn_execution_blade_light(target_dir,target.global_position if _valid_enemy(target) else global_position,frame_index) # 无音频播放器时也保持目标位置与后备时间轴同步。
			var dt:float = maxf(get_process_delta_time(),0.001)
			fallback_elapsed += dt
			await get_tree().process_frame

	if not is_inside_tree() or serial != _action_serial:
		_execution_hard_lock = false
		_movement_invulnerable = false
		return

	# 演出结束：锁定目标仍然用真实小范围碰撞体执行处决；同时在它所在 X 轴生成
	# 一条竖直伤害矩形，高度 = Map10x10 高度，宽度 = Map10x10 宽度的 1/10。
	var column_x:float = target.global_position.x if _valid_enemy(target) else global_position.x
	if _valid_enemy(target):
		var execute_damage:float = float(target.health) + float(target.Max_health)
		var execute_area:Area2D = _create_world_circle_attack_volume(
			target.global_position,
			execution_hitbox_radius,
			execute_damage,
			target.get_instance_id()
		)
		await _finish_attack_volume_window(execute_area,0.06)

	var reference_rect:Rect2 = _map10x10_world_rect()
	var column_size:Vector2 = Vector2(16.0,160.0)
	var column_center:Vector2 = Vector2(column_x,global_position.y)
	if reference_rect.size.x > 0.0 and reference_rect.size.y > 0.0:
		column_size = Vector2(
			maxf(reference_rect.size.x * execution_column_width_map10_ratio,1.0),
			maxf(reference_rect.size.y * execution_column_height_map10_ratio,1.0)
		)
		column_center.y = reference_rect.position.y + reference_rect.size.y * 0.5
	var column_damage:float = attack_damage(execution_column_raw_damage_multiplier)
	var column_area:Area2D = _create_world_rect_attack_volume(column_center,column_size,column_damage,0.0)
	await _finish_attack_volume_window(column_area,0.10)

	_execution_hard_lock = false
	_movement_invulnerable = false

# 按真实攻击 Area2D 的世界位置、旋转、尺寸与人物相对位置生成动态血肉拖尾，并同步远端视觉。
func _spawn_blade_light_on_area(kind:int,area:Area2D,attack_size:Vector2,ego_variant:bool,sweep_sign:float = 1.0) -> void:
	if not blade_light_enabled or area == null or not is_instance_valid(area):
		return
	# Area 可能继承人物的缩放/镜像；离开人物层级后必须使用完整世界尺寸。
	var axis_scale:=Vector2(area.global_transform.x.length(),area.global_transform.y.length())
	var effect_size:Vector2 = attack_size * axis_scale
	var visual_width:float = (blade_light_ego_width if ego_variant else blade_light_normal_width) * axis_scale.y
	var tint:Color = blade_light_ego_color if ego_variant else blade_light_normal_color
	var character_local_position:Vector2 = (global_position - area.global_position).rotated(-area.global_rotation)
	var visual_sign:float = sweep_sign * (-1.0 if area.global_transform.determinant() < 0.0 else 1.0)
	_spawn_blade_light_local(kind,area.global_position,area.global_rotation,effect_size,visual_width,tint,blade_light_lifetime,visual_sign,character_local_position,ego_variant)
	if multiplayer.has_multiplayer_peer():
		_remote_spawn_blade_light.rpc(kind,area.global_position,area.global_rotation,effect_size,visual_width,tint,blade_light_lifetime,visual_sign,character_local_position,ego_variant)

# 在指定世界点生成一次特殊血肉拖尾，主要用于血雾弥漫围绕处决目标的演出。
func _spawn_blade_light_at_world(kind:int,origin:Vector2,rotation_angle:float,effect_size:Vector2,visual_width:float,tint:Color,lifetime:float,sweep_sign:float = 1.0,ego_variant:bool = true) -> void:
	if not blade_light_enabled:
		return
	var character_local_position:=Vector2(-effect_size.x * 0.52,0.0) # 世界特效没有对应攻击 Area 时，从拖尾左端附近作为武器起点。
	_spawn_blade_light_local(kind,origin,rotation_angle,effect_size,visual_width,tint,lifetime,sweep_sign,character_local_position,ego_variant)
	if multiplayer.has_multiplayer_peer():
		_remote_spawn_blade_light.rpc(kind,origin,rotation_angle,effect_size,visual_width,tint,lifetime,sweep_sign,character_local_position,ego_variant)

# 远端只重放视觉血肉拖尾，不参与任何攻击、伤害或威胁判定。
@rpc("authority","call_remote","unreliable")
func _remote_spawn_blade_light(kind:int,origin:Vector2,rotation_angle:float,effect_size:Vector2,visual_width:float,tint:Color,lifetime:float,sweep_sign:float,character_local_position:Vector2,ego_variant:bool) -> void:
	_spawn_blade_light_local(kind,origin,rotation_angle,effect_size,visual_width,tint,lifetime,sweep_sign,character_local_position,ego_variant)

# 在当前场景创建 GPU 血肉刀光节点；主体、深红流动与移动眼睛由单个 Sprite2D Shader 完成。
func _spawn_blade_light_local(kind:int,origin:Vector2,rotation_angle:float,effect_size:Vector2,visual_width:float,tint:Color,lifetime:float,sweep_sign:float,character_local_position:Vector2,ego_variant:bool) -> void:
	if not ResourceLoader.exists(BLADE_LIGHT_EFFECT_PATH):
		return
	var effect_script:Script = ResourceLoader.load(BLADE_LIGHT_EFFECT_PATH) as Script
	if effect_script == null:
		return
	var effect:=Node2D.new()
	effect.name = "殷红迷雾_GPU血肉刀光_V64" # Remote 场景树版本标识，确认本次单 Sprite GPU 刀光已加载。
	effect.set_script(effect_script)
	var parent_node:Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
	if parent_node == null:
		return
	parent_node.add_child(effect)
	effect.global_position = origin # 先加入场景树再设置世界 Transform，避免父节点 Transform 污染出生点。
	effect.global_rotation = rotation_angle
	if effect.has_method("configure"):
		effect.call("configure",kind,effect_size,visual_width,tint,lifetime,sweep_sign,character_local_position,ego_variant)
	else:
		effect.queue_free()

# 血雾弥漫按六个演出分段，在被处决目标附近交替生成正反方向的血肉拖尾。
func _spawn_execution_blade_light(attack_dir:Vector2,target_position:Vector2,frame_index:int) -> void:
	var safe_dir:Vector2 = attack_dir.normalized() if attack_dir.length_squared() > 0.0001 else Vector2.RIGHT
	var sweep_sign:float = -1.0 if posmod(frame_index,2) == 0 else 1.0
	var length:float = 235.0 + float(frame_index) * 14.0
	var size:=Vector2(length,150.0 + float(frame_index) * 6.0)
	_spawn_blade_light_at_world(GeburaBladeLightKind.EXECUTION,target_position,safe_dir.angle(),size,blade_light_ego_width * 1.10,blade_light_ego_color,blade_light_lifetime,sweep_sign,true)

# ============================================================
# 殷红迷雾真实攻击体积
# ============================================================
# 所有普攻、反击、E.G.O 双斩、突刺、尸横遍野、血雾弥漫都走这里。
# Area2D 本身不直接“点名”目标；只有 CollisionShape2D 与敌方 PhysicsBody 真正重叠时才结算。
func _create_local_rect_attack_volume(
	attack_dir:Vector2,
	size:Vector2,
	damage_amount:float,
	forward_offset:float
) -> Area2D:
	var safe_dir:Vector2 = attack_dir.normalized() if attack_dir.length_squared() > 0.0001 else Vector2.LEFT
	var rect:RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(maxf(size.x,1.0),maxf(size.y,1.0))
	var area:Area2D = _new_attack_volume(rect,damage_amount,0)
	if area == null:
		return null
	add_child(area)
	# V191：safe_dir 是世界攻击方向；根节点被重力旋转后仍保持真实世界瞄准。
	area.global_position = global_position + safe_dir * forward_offset
	area.global_rotation = safe_dir.angle()
	return area


func _create_world_circle_attack_volume(
	world_position:Vector2,
	radius:float,
	damage_amount:float,
	target_only_id:int = 0
) -> Area2D:
	var circle:CircleShape2D = CircleShape2D.new()
	circle.radius = maxf(radius,1.0)
	var area:Area2D = _new_attack_volume(circle,damage_amount,target_only_id)
	if area == null:
		return null
	var holder:Node = get_tree().current_scene
	if holder == null:
		holder = get_parent()
	if holder == null:
		area.queue_free()
		return null
	holder.add_child(area)
	area.global_position = world_position
	return area


func _create_world_rect_attack_volume(
	world_center:Vector2,
	size:Vector2,
	damage_amount:float,
	world_rotation:float = 0.0,
	target_only_id:int = 0
) -> Area2D:
	var rect:RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(maxf(size.x,1.0),maxf(size.y,1.0))
	var area:Area2D = _new_attack_volume(rect,damage_amount,target_only_id)
	if area == null:
		return null
	var holder:Node = get_tree().current_scene
	if holder == null:
		holder = get_parent()
	if holder == null:
		area.queue_free()
		return null
	holder.add_child(area)
	area.global_position = world_center
	area.global_rotation = world_rotation
	return area


# 读取 World 中 Map10x10 的真实世界矩形。特殊攻击尺寸用它做基准，
# 因此以后 TileSet 单格尺寸或地图整体缩放变化时不需要重新手调攻击尺寸。
func _map10x10_world_rect() -> Rect2:
	var scene_root:Node = get_tree().current_scene
	if scene_root == null:
		return Rect2()
	var map_node:Node = scene_root.find_child("Map10x10",true,false)
	if not map_node is TileMapLayer:
		return Rect2()
	var layer:TileMapLayer = map_node as TileMapLayer
	if scene_root.has_method("return_map_world_rect"):
		var via_world:Variant = scene_root.call("return_map_world_rect",layer)
		if via_world is Rect2:
			return via_world
	if layer.tile_set == null:
		return Rect2()
	var used:Rect2i = layer.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return Rect2()
	var tile_size:Vector2 = Vector2(layer.tile_set.tile_size)
	var local_min:Vector2 = Vector2(used.position) * tile_size
	var local_max:Vector2 = Vector2(used.end) * tile_size
	var corners:PackedVector2Array = PackedVector2Array([
		layer.to_global(local_min),
		layer.to_global(Vector2(local_max.x,local_min.y)),
		layer.to_global(local_max),
		layer.to_global(Vector2(local_min.x,local_max.y)),
	])
	var min_p:Vector2 = corners[0]
	var max_p:Vector2 = corners[0]
	for point:Vector2 in corners:
		min_p.x = minf(min_p.x,point.x)
		min_p.y = minf(min_p.y,point.y)
		max_p.x = maxf(max_p.x,point.x)
		max_p.y = maxf(max_p.y,point.y)
	return Rect2(min_p,max_p - min_p)


func _new_attack_volume(shape:Shape2D,damage_amount:float,target_only_id:int) -> Area2D:
	if shape == null or damage_amount <= 0.0:
		return null
	var area:Area2D = Area2D.new()
	area.name = "GeburaAttackVolume"
	area.collision_layer = 0
	# 1 = 地图/实体，2 = 角色。Area 只监测，不产生刚体阻挡；实际伤害仅筛选 enemy ball。
	area.collision_mask = 3
	area.monitoring = true
	area.monitorable = false
	area.set_meta("threat_debug_damage",damage_amount)
	area.set_meta("gebura_attack_damage",damage_amount)
	area.set_meta("gebura_attack_target_only_id",target_only_id)
	area.set_meta("gebura_attack_hit_ids",{})

	var collision_shape:CollisionShape2D = CollisionShape2D.new()
	collision_shape.name = "CollisionShape2D"
	collision_shape.shape = shape
	area.add_child(collision_shape)
	area.body_entered.connect(_on_gebura_attack_volume_body_entered.bind(area))
	return area


func _on_gebura_attack_volume_body_entered(body:Node2D,area:Area2D) -> void:
	if not is_multiplayer_authority() or area == null or not is_instance_valid(area):
		return
	if body == null or not is_instance_valid(body) or not body is ball:
		return
	var target:ball = body as ball
	if not _valid_enemy(target):
		return

	var target_only_id:int = int(area.get_meta("gebura_attack_target_only_id",0))
	if target_only_id != 0 and target.get_instance_id() != target_only_id:
		return

	var raw_hit_ids:Variant = area.get_meta("gebura_attack_hit_ids",{})
	var hit_ids:Dictionary = raw_hit_ids if raw_hit_ids is Dictionary else {}
	var target_id:int = target.get_instance_id()
	if hit_ids.has(target_id):
		return
	hit_ids[target_id] = true
	area.set_meta("gebura_attack_hit_ids",hit_ids)

	var damage_amount:float = maxf(float(area.get_meta("gebura_attack_damage",0.0)),0.0)
	if damage_amount <= 0.0:
		return
	target.receive_positional_damage(damage_amount,target.global_position,false,self)


func _poll_attack_volume(area:Area2D) -> void:
	if area == null or not is_instance_valid(area):
		return
	for body:Node2D in area.get_overlapping_bodies():
		_on_gebura_attack_volume_body_entered(body,area)


func _finish_attack_volume_window(area:Area2D,hold_time:float) -> void:
	if area == null or not is_instance_valid(area):
		if hold_time > 0.0:
			await get_tree().create_timer(hold_time,true,false,true).timeout
		return
	# 新 Area2D 至少经过一个 physics frame 才能得到可靠 overlap；随后持续保持到动作结束。
	await get_tree().physics_frame
	if area == null or not is_instance_valid(area):
		return
	_poll_attack_volume(area)
	if hold_time > 0.0:
		# 攻击体积收尾使用真实时间，避免一刀击杀最后目标后游戏时间倍率变为 0，
		# 协程永远卡在这里而留下 _action_locked。
		await get_tree().create_timer(hold_time,true,false,true).timeout
	if area != null and is_instance_valid(area):
		_poll_attack_volume(area)
		area.queue_free()


func _direction_vector(dir_idx:int) -> Vector2:
	return Vector2.RIGHT.rotated(float(posmod(dir_idx,8)) * PI / 4.0)


func _finish_action(serial:int) -> void:
	if serial != _action_serial:
		return
	# 动作收尾必须把所有临时战斗状态复原。即使这是从防御反击进入的攻击，
	# 也不能让 E.G.O 的完全防御、位移无敌或 Using_Skill 残留到下一次动作。
	_action_locked = false
	_movement_invulnerable = false
	_execution_hard_lock = false
	_guarding = false
	Using_Skill = false
	Attacking = false
	_set_visual(&"stand",_visual_direction_index)

func tick_physics(state:State,delta:float) -> void:
	if _execution_hard_lock:
		# 血雾弥漫演出期间位置是硬锁，不接受基础移动、击退、外力或其它角色脚本的位移累积。
		global_position = _execution_lock_position
		velocity = Vector2.ZERO
		Repel = Vector2.ZERO
		if is_multiplayer_authority():
			stand(delta)
			global_position = _execution_lock_position
			velocity = Vector2.ZERO
			Repel = Vector2.ZERO
		return
	if _action_locked:
		_update_motion_inertia_visual(state,delta)
		if is_multiplayer_authority():
			stand(delta)
			Repel = Vector2.ZERO
		return
	super.tick_physics(state,delta)

func _dash_to_target_gap(target:ball,gap:float,speed:float,invulnerable:bool) -> void:
	if not _valid_enemy(target):
		return
	var delta_pos:Vector2 = target.global_position - global_position
	if delta_pos.length_squared() <= 0.0001:
		return
	var point:Vector2 = target.global_position - delta_pos.normalized() * gap
	await _dash_to_point(point,speed,invulnerable)

func _dash_by_vector(offset:Vector2,speed:float,invulnerable:bool) -> void:
	await _dash_to_point(global_position + offset,speed,invulnerable)

func _dash_to_point(point:Vector2,speed:float,invulnerable:bool) -> void:
	var old_invulnerable:bool = _movement_invulnerable
	if invulnerable:
		_movement_invulnerable = true
	var timeout:float = global_position.distance_to(point) / maxf(speed,1.0) + 0.18
	var afterimage_elapsed:float = displacement_afterimage_interval
	if global_position.distance_to(point) > 3.0:
		_spawn_displacement_afterimage()
	while is_inside_tree() and timeout > 0.0:
		var to_point:Vector2 = point - global_position
		var distance:float = to_point.length()
		if distance <= 3.0:
			break
		var dt:float = maxf(get_physics_process_delta_time(),0.001)
		var step:float = minf(distance,speed * dt)
		var collision:KinematicCollision2D = move_and_collide(to_point.normalized() * step)
		afterimage_elapsed += dt
		if afterimage_elapsed >= displacement_afterimage_interval:
			_spawn_displacement_afterimage()
			afterimage_elapsed = 0.0
		if collision != null:
			break
		timeout -= dt
		await get_tree().physics_frame
	if invulnerable:
		_movement_invulnerable = old_invulnerable


func _spawn_displacement_afterimage() -> void:
	_spawn_displacement_afterimage_local()
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		_remote_spawn_displacement_afterimage.rpc()


@rpc("authority","call_remote","unreliable")
func _remote_spawn_displacement_afterimage() -> void:
	_spawn_displacement_afterimage_local()


func _spawn_displacement_afterimage_local() -> void:
	if not displacement_afterimage_enabled or displacement_afterimage_alpha <= 0.0:
		return
	var source:Sprite2D = image as Sprite2D
	if source == null or not is_instance_valid(source) or source.texture == null:
		return
	var holder:Node = get_parent()
	if holder == null or not is_instance_valid(holder):
		return

	# 只复制这一帧真正显示的 Sprite2D，不复制脚本、碰撞或角色节点。
	# 因此残影会保留当前动作的纹理、旋转、镜像、单图缩放/偏移，然后留在世界原地渐隐。
	var ghost:Sprite2D = Sprite2D.new()
	ghost.name = "GeburaAfterimage"
	ghost.texture = source.texture
	ghost.centered = source.centered
	ghost.offset = source.offset
	ghost.flip_h = source.flip_h
	ghost.flip_v = source.flip_v
	ghost.region_enabled = source.region_enabled
	ghost.region_rect = source.region_rect
	ghost.frame = source.frame
	ghost.hframes = source.hframes
	ghost.vframes = source.vframes
	ghost.texture_filter = source.texture_filter
	ghost.z_index = z_index + source.z_index
	ghost.z_as_relative = true
	ghost.modulate = source.modulate
	holder.add_child(ghost)
	ghost.global_transform = source.global_transform
	var source_self:Color = source.self_modulate
	ghost.self_modulate = Color(source_self.r,source_self.g,source_self.b,clampf(displacement_afterimage_alpha * source_self.a,0.0,1.0))

	var fade:Tween = ghost.create_tween().bind_node(ghost)
	fade.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	fade.tween_property(ghost,"self_modulate:a",0.0,maxf(displacement_afterimage_fade_time,0.01))
	fade.tween_callback(ghost.queue_free)

func _nearest_enemy_ball() -> ball:
	var best:ball = null
	var best_d2:float = INF
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var candidate:ball = node as ball
		if not _valid_enemy(candidate):
			continue
		var d2:float = global_position.distance_squared_to(candidate.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = candidate
	return best

func _valid_enemy(candidate:Variant) -> bool:
	# 目标可能在 await 期间死亡并 queue_free。已释放对象传给静态 ball 参数时，
	# GDScript 会在进入函数体前直接报 Invalid type，所以这里必须先以 Variant 接收。
	if candidate == null or not is_instance_valid(candidate):
		return false
	if not candidate is ball:
		return false
	var enemy:ball = candidate as ball
	if enemy == self or enemy.health <= 0:
		return false
	if not _is_enemy_ball(enemy):
		return false
	return enemy.state_machine == null or enemy.state_machine.current_state != State.Die

func _is_enemy_ball(candidate:ball) -> bool:
	if candidate == null or candidate == self:
		return false
	var my_team:String = str(Team).strip_edges()
	var other_team:String = str(candidate.Team).strip_edges()
	if my_team.is_empty() or other_team.is_empty():
		return true
	return my_team != other_team

func _direction_index(vector:Vector2) -> int:
	if vector.length_squared() <= 0.0001:
		return _visual_direction_index
	var angle:float = vector.angle()
	return posmod(int(round(angle / (PI / 4.0))),8)

func _set_visual(pose:StringName,dir_idx:int) -> void:
	_apply_visual_local(pose,dir_idx)
	if multiplayer.has_multiplayer_peer():
		_remote_visual.rpc(pose,dir_idx)

@rpc("authority","call_remote","unreliable")
func _remote_visual(pose:StringName,dir_idx:int) -> void:
	_apply_visual_local(pose,dir_idx)

func _apply_visual_local(pose:StringName,dir_idx:int) -> void:
	_visual_pose = pose
	_visual_direction_index = posmod(dir_idx,8)
	var sprite:Sprite2D = image as Sprite2D
	if sprite == null or not is_instance_valid(sprite):
		return

	# 图片、统一高度、中心对齐以及每张图的独立位置/缩放都交给
	# Graphics/Image 上的 @tool 视觉脚本管理。这样编辑器预览和运行时使用同一套数据。
	if sprite.has_method("apply_runtime_pose"):
		sprite.call("apply_runtime_pose",pose,ego_active)

	if pose == &"stand":
		# 站立/移动朝向由 ball 的统一左右镜像逻辑管理；视觉脚本会同步镜像每张图
		# 的 X 构图偏移，因此朝左移动不会再出现人物整体偏离角色中心。
		if sprite.has_method("apply_runtime_flip"):
			sprite.call("apply_runtime_flip",is_character_visual_flipped_h())
		_start_rotation_recovery(sprite)
		return

	# 防御动作永远保持正常角度。只继承人物当前左右朝向，不参与八方向攻击旋转，
	# 也不在防御结束前启动旋转恢复 Tween。
	if pose == &"guard":
		_stop_rotation_recovery()
		if sprite.has_method("apply_runtime_flip"):
			sprite.call("apply_runtime_flip",is_character_visual_flipped_h())
		sprite.rotation = 0.0
		return

	# 血雾弥漫 1~6 必须始终是原图正常角度，只按目标在左右哪边进行水平镜像。
	# 不能像普通八方向攻击那样旋转 45/90 度。
	if String(pose).begins_with("execute_"):
		_stop_rotation_recovery()
		var face_right:bool = _direction_vector(_visual_direction_index).x > 0.001
		set_character_visual_flip_h(face_right)
		sprite.rotation = 0.0
		return

	_stop_rotation_recovery()
	var desired_angle:float = float(_visual_direction_index) * PI / 4.0
	# 战斗图基准朝左。比较原图朝左与水平翻转朝右两种方案，
	# 选择绝对旋转角更小的一种，避免为了八方向攻击把人物倒立。
	var unflipped_rotation:float = wrapf(desired_angle - PI,-PI,PI)
	var flipped_rotation:float = wrapf(desired_angle,-PI,PI)
	if absf(flipped_rotation) < absf(unflipped_rotation):
		_visual_face_right = true
		set_character_visual_flip_h(true)
		sprite.rotation = flipped_rotation
	else:
		_visual_face_right = false
		set_character_visual_flip_h(false)
		sprite.rotation = unflipped_rotation

func set_character_visual_flip_h(flipped:bool) -> void:
	super.set_character_visual_flip_h(flipped)
	var sprite:Sprite2D = image as Sprite2D
	if sprite != null and is_instance_valid(sprite) and sprite.has_method("apply_runtime_flip"):
		sprite.call("apply_runtime_flip",flipped)


func _play_gebura_sfx(kind:int) -> AudioStreamPlayer:
	# 本地先启动并返回播放器，斩杀可用 get_playback_position() 精确跟随音频段落。
	var local_player:AudioStreamPlayer = _play_gebura_sfx_local(kind)
	if multiplayer.has_multiplayer_peer():
		_remote_play_gebura_sfx.rpc(kind)
	return local_player


@rpc("authority","call_remote","unreliable")
func _remote_play_gebura_sfx(kind:int) -> void:
	_play_gebura_sfx_local(kind)


func _play_gebura_sfx_local(kind:int) -> AudioStreamPlayer:
	var stream:AudioStream = null
	match kind:
		GeburaSfx.NORMAL_THRUST: stream = SFX_NORMAL_THRUST
		GeburaSfx.NORMAL_SLASH: stream = SFX_NORMAL_SLASH
		GeburaSfx.EGO_THRUST: stream = SFX_EGO_THRUST
		GeburaSfx.EGO_SLASH_1: stream = SFX_EGO_SLASH_1
		GeburaSfx.EGO_SLASH_2: stream = SFX_EGO_SLASH_2
		GeburaSfx.EGO_HORIZONTAL: stream = SFX_EGO_HORIZONTAL
		GeburaSfx.EXECUTE: stream = SFX_EXECUTE
	if stream == null:
		return null
	var player:AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = stream
	player.name = "GeburaCombatSfx"
	add_child(player)
	_owned_sfx_players.append(player)
	player.finished.connect(func() -> void:
		_owned_sfx_players.erase(player)
		if is_instance_valid(player):
			player.queue_free()
	)
	player.play()
	return player


func _start_rotation_recovery(sprite:Sprite2D) -> void:
	_stop_rotation_recovery()
	if is_zero_approx(sprite.rotation):
		sprite.rotation = 0.0
		return
	_visual_recover_tween = create_tween().bind_node(self)
	_visual_recover_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_visual_recover_tween.tween_property(sprite,"rotation",0.0,visual_rotation_recover_time)

func _stop_rotation_recovery() -> void:
	if _visual_recover_tween != null and _visual_recover_tween.is_valid():
		_visual_recover_tween.kill()
	_visual_recover_tween = null
