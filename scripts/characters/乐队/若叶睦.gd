extends ball

const CUCUMBER_POT_SCENE:PackedScene = preload("res://scenes/terrain/若叶睦_黄瓜花盆.tscn")
const MUTSUMI_TEXTURE:Texture2D = preload("res://Images/characters/人物/若叶睦/若叶睦.png")
const MORTIS_TEXTURE:Texture2D = preload("res://Images/characters/人物/若叶睦/墨提斯.png")
const MUTSUMI_DEATH_TEXTURE:Texture2D = preload("res://Images/characters/人物/若叶睦/ChatGPT_Image_2026年8月31日_00_59_29.png")
const WAKABA_DEATH_SFX:AudioStream = preload("res://audio/characters/若叶睦/若叶睦尖叫.MP3")
const MORTIS_SWITCH_VOICE:AudioStream = preload("res://audio/characters/若叶睦/若叶睦找我吗.MP3")
const MUTSUMI_SWITCH_VOICE:AudioStream = preload("res://audio/characters/若叶睦/若叶睦真的吗.MP3")
const MORTIS_GUITAR_HIT_VOICE:AudioStream = preload("res://audio/characters/若叶睦/若叶睦全都不会.MP3")
const MUTSUMI_WATERING_HUM_VOICE:AudioStream = preload("res://audio/characters/若叶睦/若叶睦哼1.MP3")
const CUCUMBER_TEXTURE:Texture2D = preload("res://Images/characters/人物/若叶睦/04_黄瓜本体.png")
const CUCUMBER_EAT_SFX_1:AudioStream = preload("res://audio/characters/若叶睦/eat1.mp3")
const CUCUMBER_EAT_SFX_2:AudioStream = preload("res://audio/characters/若叶睦/eat2.mp3")
const CUCUMBER_EAT_SFX_3:AudioStream = preload("res://audio/characters/若叶睦/eat3.mp3")
const WATER_IMPACT_BURST_SCRIPT = preload("res://scripts/effects/umbrella_hit_burst.gd")
const MORTIS_KILL_BLOOD_SCRIPT = preload("res://scripts/effects/若叶睦_击杀血液.gd")
const POT_PLACE_SFX:AudioStream = preload("res://audio/characters/若叶睦/放置_[cut_0sec].mp3")
const WATERING_LOOP_SFX:AudioStream = preload("res://audio/characters/若叶睦/浇水_[cut_3sec].mp3")
const MORTIS_GUITAR_HIT_SFX:AudioStream = preload("res://audio/characters/若叶睦/电吉他.mp3")
const MORTIS_GUITAR_COLLISION_HIT_SFX:AudioStream = preload("res://audio/sfx/physics/balls_hit1.sfxr")
const MORTIS_PUNCH_SWING_SFX:AudioStream = preload("res://audio/characters/拳击手/拳击手_挥拳.mp3")
const MORTIS_PUNCH_HIT_SFX:AudioStream = preload("res://audio/characters/拳击手/拳击手_命中.mp3")
const MORTIS_GUITAR_SWING_SFX:AudioStream = preload("res://audio/characters/矿工/挥舞.mp3")

enum Personality {
	MUTSUMI,
	MORTIS,
}

enum WakabaSfx {
	POT_PLACE,
	PUNCH_SWING,
	PUNCH_HIT,
	GUITAR_SWING,
	GUITAR_HIT,
	GUITAR_COLLISION_HIT,
	SWITCH_TO_MORTIS_VOICE,
	SWITCH_TO_MUTSUMI_VOICE,
	GUITAR_HIT_VOICE,
	WATERING_HUM_VOICE,
	CUCUMBER_EAT_1,
	CUCUMBER_EAT_2,
	CUCUMBER_EAT_3,
}

const MORTIS_PUNCH_START_DISTANCE:float = 68.0
const MORTIS_PUNCH_CONTACT_DISTANCE:float = 215.0
const MORTIS_PUNCH_LEFT_ANGLE_OFFSET:float = -0.08
const MORTIS_PUNCH_RIGHT_ANGLE_OFFSET:float = 0.08
const MORTIS_GUITAR_ORBIT_RADIUS:float = 118.0
const MORTIS_GUITAR_VERTICAL_OFFSET:float = -10.0
const MORTIS_GUITAR_CONTACT_SWING_OFFSET:float = 0.02
const MORTIS_KILL_BLOOD_PUNCH:int = 0
const MORTIS_KILL_BLOOD_GUITAR:int = 1

@export_category("若叶睦 - 人格切换")
@export_range(3.0,60.0,0.5) var mutsumi_auto_switch_time:float = 16.0
@export_range(0.05,1.0,0.01) var mutsumi_damage_switch_ratio:float = 0.30
@export_range(0.5,12.0,0.1) var mutsumi_damage_window:float = 4.5
@export_range(1.0,30.0,0.5) var mortis_no_damage_return_time:float = 8.0
@export_range(0.01,1.0,0.01) var mortis_heal_return_ratio:float = 0.18

@export_category("若叶睦 - 黄瓜")
@export_range(0.5,30.0,0.1) var plant_cooldown:float = 12.0
@export_range(1,8,1) var max_active_pots:int = 4
@export_range(16.0,80.0,1.0) var pot_interaction_radius:float = 34.0
@export_range(1.0,30.0,0.5) var vine_growth_time:float = 7.0
@export_range(1.0,30.0,0.5) var cucumber_growth_time:float = 10.0
@export_range(1,6,1) var cucumbers_per_vine:int = 3
@export_range(1.0,5.0,0.1) var watering_growth_multiplier:float = 2.4
@export_range(0.1,1.0,0.05) var watering_move_multiplier:float = 0.55
@export_range(0.0,0.5,0.005) var cucumber_instant_heal_ratio:float = 0.075
@export_range(0.0,0.5,0.005) var cucumber_hot_heal_ratio:float = 0.12
@export_range(0.5,12.0,0.25) var cucumber_hot_duration:float = 4.0


@export_category("若叶睦 - 吃黄瓜演出")
@export_range(0.5,2.5,0.05) var cucumber_eat_duration:float = 1.15
@export_range(2,6,1) var cucumber_eat_sound_min_count:int = 3
@export_range(2,8,1) var cucumber_eat_sound_max_count:int = 5
@export_range(0.08,0.35,0.01) var cucumber_eat_sound_gap_min:float = 0.12
@export_range(0.08,0.40,0.01) var cucumber_eat_sound_gap_max:float = 0.20
@export_range(16.0,80.0,1.0) var cucumber_mouth_visual_size:float = 48.0
@export_range(2,12,1) var cucumber_crumbs_per_burst:int = 6

@export_category("若叶睦 - 盆栽枯萎")
@export_range(2.0,60.0,0.5) var pot_wither_after_unwatered:float = 10.0
@export_range(0.25,8.0,0.05) var pot_wither_cucumber_interval:float = 0.40
@export_range(0.5,12.0,0.1) var pot_wither_disappear_delay:float = 0.65

@export_category("若叶睦 - 阵亡演出")
@export_range(0.05,1.0,0.05) var death_halo_reveal_time:float = 0.24
@export_range(0.0,1.0,0.05) var death_halo_hold_time:float = 0.16
@export_range(0.8,5.0,0.1) var death_ascend_duration:float = 1.75
@export_range(20.0,500.0,5.0) var death_ascend_distance:float = 105.0
@export_range(40.0,260.0,5.0) var death_halo_height:float = 118.0
@export_range(20.0,120.0,2.0) var death_halo_radius_x:float = 48.0
@export_range(6.0,40.0,1.0) var death_halo_radius_y:float = 12.0
@export_range(1.0,12.0,0.5) var death_halo_line_width:float = 4.0
@export_range(-60.0,-12.0,1.0) var death_audio_end_db:float = -46.0
# 兼容旧版人物场景中仍保存的导出字段；V93 起不再用于阵亡演出。
@export_range(1.0,20.0,0.5) var death_tremble_amplitude:float = 6.0
@export_range(0.02,0.16,0.005) var death_tremble_interval:float = 0.045

@export_category("若叶睦 - 浇水视觉")
@export_range(0.015,0.12,0.005) var water_drop_interval:float = 0.040
@export_range(0.12,0.80,0.01) var water_drop_travel_time:float = 0.34
@export_range(2.0,18.0,0.5) var water_drop_length:float = 7.0
@export_range(0.4,4.0,0.1) var water_drop_width:float = 1.5
@export_range(10.0,120.0,1.0) var water_arc_height:float = 44.0
@export_range(50.0,900.0,10.0) var water_impact_visual_speed:float = 620.0

@export_category("墨提斯 - 拳击")
@export_range(20.0,180.0,2.0) var mortis_punch_range:float = 70.0
@export_range(0.1,5.0,0.05) var mortis_punch_cooldown:float = 1.1
@export_range(0.0,5.0,0.05) var mortis_punch_damage_multiplier:float = 0.65
@export_range(0.02,0.5,0.01) var mortis_double_punch_interval:float = 0.12
@export_range(0.0,120.0,1.0) var mortis_punch_knockback_distance:float = 18.0
@export_range(50.0,1200.0,10.0) var mortis_punch_knockback_speed:float = 340.0
@export_range(0.05,0.30,0.005) var mortis_punch_visual_scale:float = 0.145

@export_category("墨提斯 - 吉他")
@export_range(30.0,260.0,2.0) var mortis_guitar_min_range:float = 80.0
@export_range(40.0,360.0,2.0) var mortis_guitar_max_range:float = 185.0
@export_range(0.5,12.0,0.1) var mortis_guitar_cooldown:float = 4.3
@export_range(0.0,8.0,0.05) var mortis_guitar_damage_multiplier:float = 2.35
@export_range(20.0,180.0,1.0) var mortis_guitar_arc_degrees:float = 112.0
@export_range(0.0,240.0,1.0) var mortis_guitar_knockback_distance:float = 78.0
@export_range(100.0,1800.0,10.0) var mortis_guitar_knockback_speed:float = 760.0
@export_range(0.05,0.30,0.005) var mortis_guitar_visual_scale:float = 0.165
@export_range(0.010,0.080,0.002) var mortis_guitar_trail_interval:float = 0.026
@export_range(0.05,0.40,0.01) var mortis_guitar_trail_lifetime:float = 0.18
@export_range(0.05,0.80,0.01) var mortis_guitar_trail_alpha:float = 0.30

@export_category("墨提斯 - 击杀血液")
@export_range(2,10,1) var mortis_punch_kill_blood_count:int = 5
@export_range(1.0,12.0,0.5) var mortis_punch_kill_blood_spread_degrees:float = 6.5
@export_range(90.0,260.0,5.0) var mortis_punch_kill_blood_force:float = 170.0
@export_range(4,14,1) var mortis_guitar_kill_blood_count:int = 11
@export_range(4.0,18.0,0.5) var mortis_guitar_kill_blood_spread_degrees:float = 14.0
@export_range(140.0,360.0,5.0) var mortis_guitar_kill_blood_force:float = 285.0

@export_category("墨提斯 - 图片攻击碰撞")
@export_range(0.01,0.95,0.01) var mortis_attack_alpha_threshold:float = 0.10
@export_range(0.25,8.0,0.25) var mortis_attack_polygon_epsilon:float = 2.0

var personality:int = Personality.MUTSUMI
var _mutsumi_auto_left:float = 0.0
var _mutsumi_recent_damage:float = 0.0
var _mutsumi_damage_window_left:float = 0.0
var _mortis_no_damage_elapsed:float = 0.0
var _mortis_heal_accumulated:float = 0.0
var _plant_cooldown_left:float = 0.0
var _punch_cooldown_left:float = 0.0
var _guitar_cooldown_left:float = 0.0
var _mortis_action_busy:bool = false
var _owned_pots:Array[WeakRef] = []
var _hot_left:float = 0.0
var _hot_rate:float = 0.0
var _hot_fraction:float = 0.0
var _punch_visual_serial:int = 0
var _punch_collision_shapes:Array[ConvexPolygonShape2D] = []
var _guitar_collision_shapes:Array[ConvexPolygonShape2D] = []
var _guitar_trail_last_spawn_msec:int = -1000000
var _watering_drop_elapsed:float = 0.0
var _watering_drops:Array[Dictionary] = []
var _watering_audio_active:bool = false
var _watering_loop_player:AudioStreamPlayer2D = null
var _death_sequence_started:bool = false
var _death_sequence_player:AudioStreamPlayer2D = null
var _death_halo:Node2D = null
var _death_visual_tween:Tween = null
var _death_halo_tween:Tween = null
var _death_audio_tween:Tween = null
var _death_base_modulate:Color = Color.WHITE
var _death_base_global_position:Vector2 = Vector2.ZERO
var _cucumber_eating:bool = false
var _cucumber_eat_serial:int = 0
var _cucumber_eat_visual:Sprite2D = null
var _cucumber_pending_instant_ratio:float = 0.0
var _cucumber_pending_hot_ratio:float = 0.0
var _cucumber_pending_duration:float = 0.0

@onready var _punch_visual:Sprite2D = get_node_or_null("Graphics/PunchVisual") as Sprite2D
@onready var _guitar_visual:Sprite2D = get_node_or_null("Graphics/GuitarVisual") as Sprite2D
@onready var _guitar_trail_root:Node2D = get_node_or_null("Graphics/GuitarTrailRoot") as Node2D
@onready var _watering_can_visual:Sprite2D = get_node_or_null("Graphics/WateringCanVisual") as Sprite2D
@onready var _watering_spout:Marker2D = get_node_or_null("Graphics/WateringCanVisual/Spout") as Marker2D

func _ready() -> void:
	Has_Collision_Damage = false
	Can_Attack = false
	Can_Skill = false
	Health_Restore = 0
	super._ready()
	_prepare_mortis_attack_collision_shapes()
	_apply_personality_visual()
	_mutsumi_auto_left = maxf(mutsumi_auto_switch_time, 0.1)
	_plant_cooldown_left = 0.8
	_set_action_visuals_hidden()
	_update_personality_ui()

func is_mutsumi_personality() -> bool:
	return personality == Personality.MUTSUMI

func is_mortis_personality() -> bool:
	return personality == Personality.MORTIS

func move(speed:float,delta:float) -> void:
	var adjusted_speed:float = speed
	if is_mutsumi_personality() and _is_touching_owned_pot():
		adjusted_speed *= clampf(watering_move_multiplier, 0.05, 1.0)
	super.move(adjusted_speed,delta)

func tick_physics(state:State,delta:float) -> void:
	super.tick_physics(state,delta)
	if not is_multiplayer_authority() or health <= 0:
		return

	_update_hot(delta)
	# V172：吃黄瓜由角色 authority 主动检查自己的花盆，不再依赖花盆脚本按人格反向猜测。
	# 这样墨提斯与若叶睦使用完全同一条入口，避免墨提斯状态下漏吃。
	_try_consume_owned_cucumber()
	_plant_cooldown_left = maxf(_plant_cooldown_left - delta, 0.0)
	_punch_cooldown_left = maxf(_punch_cooldown_left - delta, 0.0)
	_guitar_cooldown_left = maxf(_guitar_cooldown_left - delta, 0.0)

	if personality == Personality.MUTSUMI:
		_update_mutsumi(delta)
	else:
		_update_mortis(delta)
	_update_watering_visual(delta)

func _update_mutsumi(delta:float) -> void:
	_mutsumi_auto_left = maxf(_mutsumi_auto_left - delta, 0.0)
	if _mutsumi_damage_window_left > 0.0:
		_mutsumi_damage_window_left = maxf(_mutsumi_damage_window_left - delta, 0.0)
		if _mutsumi_damage_window_left <= 0.0:
			_mutsumi_recent_damage = 0.0

	if _mutsumi_auto_left <= 0.0:
		_switch_personality(Personality.MORTIS)
		return

	if not is_player_controlled() and _plant_cooldown_left <= 0.0 and is_combat_runtime_active():
		_plant_cucumber_pot()

func _update_mortis(delta:float) -> void:
	_mortis_no_damage_elapsed += delta
	if _mortis_no_damage_elapsed >= maxf(mortis_no_damage_return_time, 0.1):
		_switch_personality(Personality.MUTSUMI)
		return

	if is_player_controlled() or _mortis_action_busy or not is_combat_runtime_active():
		return

	var target:ball = _find_nearest_enemy()
	if target == null:
		return
	var to_target:Vector2 = combat_target_position(target) - global_position
	var attack_direction:Vector2 = to_target.normalized() if to_target.length_squared() > 0.000001 else Vector2.RIGHT

	# V164：AI 不再只看角色中心距离决定“要不要出招”。
	# 正常情况下先把拳头/吉他放到真正伤害结算帧的姿态，用 V163 的图片 Alpha 碰撞
	# 预查询目标 Hurtbox；只有该姿态确实能碰到当前目标才允许启动攻击。
	# 这样敌人还在图片实际攻击范围之外时，墨提斯会继续追近，而不会原地空挥。
	if _punch_cooldown_left <= 0.0 and _can_punch_reach_target(target,attack_direction):
		_run_double_punch(attack_direction)
		return
	if _guitar_cooldown_left <= 0.0 and _can_guitar_reach_target(target,attack_direction):
		_run_guitar_swing(attack_direction)

func on_actual_health_damage_received(actual_health_damage:float,_health_before:float) -> void:
	if actual_health_damage <= 0.0:
		return
	if personality == Personality.MUTSUMI:
		if _mutsumi_damage_window_left <= 0.0:
			_mutsumi_recent_damage = 0.0
		_mutsumi_recent_damage += actual_health_damage
		_mutsumi_damage_window_left = maxf(mutsumi_damage_window, 0.1)
		if _mutsumi_recent_damage >= float(Max_health) * clampf(mutsumi_damage_switch_ratio, 0.01, 1.0):
			_switch_personality(Personality.MORTIS)
	else:
		# 墨提斯每次受伤都会重置“多久没受伤”的回归计时。
		_mortis_no_damage_elapsed = 0.0

func heal(amount:float) -> int:
	var healed:int = super.heal(amount)
	if healed > 0 and personality == Personality.MORTIS:
		_mortis_heal_accumulated += float(healed)
		if _mortis_heal_accumulated >= float(Max_health) * clampf(mortis_heal_return_ratio, 0.01, 1.0):
			_switch_personality(Personality.MUTSUMI)
	return healed

func controlled_attack_action() -> void:
	if personality != Personality.MORTIS or _mortis_action_busy:
		return
	var aim_direction:Vector2 = player_control_aim_direction(direction)
	var aim_distance:float = global_position.distance_to(player_control_aim_world_position(global_position + aim_direction * mortis_punch_range))
	if aim_distance <= mortis_punch_range and _punch_cooldown_left <= 0.0:
		_run_double_punch(aim_direction)
	elif _guitar_cooldown_left <= 0.0:
		_run_guitar_swing(aim_direction)

func controlled_skill_action() -> void:
	if personality == Personality.MUTSUMI:
		if _plant_cooldown_left <= 0.0:
			_plant_cucumber_pot()
		return
	# 墨提斯右键固定尝试吉他，便于直接控制时自由选招。
	if not _mortis_action_busy and _guitar_cooldown_left <= 0.0:
		_run_guitar_swing(player_control_aim_direction(direction))

func _switch_personality(next_personality:int) -> void:
	if personality == next_personality:
		return
	personality = next_personality
	_mortis_action_busy = false
	_set_action_visuals_hidden()
	if personality == Personality.MORTIS:
		_mortis_no_damage_elapsed = 0.0
		_mortis_heal_accumulated = 0.0
		_punch_cooldown_left = 0.15
		_guitar_cooldown_left = 0.65
	else:
		_mutsumi_auto_left = maxf(mutsumi_auto_switch_time, 0.1)
		_mutsumi_recent_damage = 0.0
		_mutsumi_damage_window_left = 0.0
		_plant_cooldown_left = minf(_plant_cooldown_left, 1.0)
	_apply_personality_visual()
	_update_personality_ui()
	_sync_personality_visual(personality)
	# V170：人格真正完成切换后再播放对应语音。初始化不会经过本函数，因此不会误播。
	if personality == Personality.MORTIS:
		_play_wakaba_sfx_everywhere(WakabaSfx.SWITCH_TO_MORTIS_VOICE,global_position,5.0,1.0,1150.0)
	else:
		_play_wakaba_sfx_everywhere(WakabaSfx.SWITCH_TO_MUTSUMI_VOICE,global_position,10.0,1.0,1150.0)

func _plant_cucumber_pot() -> void:
	if not is_multiplayer_authority() or health <= 0:
		return
	_trim_owned_pots()
	var pot:Node2D = CUCUMBER_POT_SCENE.instantiate() as Node2D
	if pot == null:
		return
	pot.name = "若叶睦_黄瓜花盆_%d" % Time.get_ticks_usec()
	get_tree().current_scene.add_child(pot,true)
	pot.global_position = global_position
	pot.call("setup", self, {
		"interaction_radius": pot_interaction_radius,
		"vine_growth_time": vine_growth_time,
		"cucumber_growth_time": cucumber_growth_time,
		"max_cucumbers": cucumbers_per_vine,
		"watering_growth_multiplier": watering_growth_multiplier,
		"instant_heal_ratio": cucumber_instant_heal_ratio,
		"hot_heal_ratio": cucumber_hot_heal_ratio,
		"hot_duration": cucumber_hot_duration,
		"wither_after_unwatered": pot_wither_after_unwatered,
		"wither_cucumber_interval": pot_wither_cucumber_interval,
		"wither_disappear_delay": pot_wither_disappear_delay,
	})
	_owned_pots.append(weakref(pot))
	_play_wakaba_sfx_everywhere(WakabaSfx.POT_PLACE,pot.global_position,-3.0,1.0,850.0)
	_plant_cooldown_left = maxf(plant_cooldown, 0.1)

func _trim_owned_pots() -> void:
	var valid:Array[WeakRef] = []
	for ref:WeakRef in _owned_pots:
		var raw:Variant = ref.get_ref() if ref != null else null
		if raw is Node and is_instance_valid(raw):
			valid.append(ref)
	_owned_pots = valid
	while _owned_pots.size() >= maxi(max_active_pots,1):
		var ref:WeakRef = _owned_pots.pop_front()
		var raw:Variant = ref.get_ref() if ref != null else null
		if raw is Node and is_instance_valid(raw):
			(raw as Node).queue_free()

func _is_touching_owned_pot() -> bool:
	for node:Node in get_tree().get_nodes_in_group("MutsumiCucumberPot"):
		if node == null or not is_instance_valid(node) or not node.has_method("is_owned_by"):
			continue
		if not bool(node.call("is_owned_by", self)):
			continue
		if not node is Node2D:
			continue
		var radius:float = float(node.get("interaction_radius"))
		if global_position.distance_to((node as Node2D).global_position) <= maxf(radius,1.0):
			return true
	return false

func _try_consume_owned_cucumber() -> void:
	if health <= 0 or health >= Max_health:
		return
	# 若叶睦与墨提斯都是同一个角色实例的两个人格；吃黄瓜不再做人格白名单判断。
	# 花盆自己验证 ownership、距离、成熟黄瓜、枯萎状态和食用间隔。
	for node:Node in get_tree().get_nodes_in_group("MutsumiCucumberPot"):
		if node == null or not is_instance_valid(node):
			continue
		if not node.has_method("try_consume_cucumber_by"):
			continue
		if bool(node.call("try_consume_cucumber_by", self)):
			# 每个物理帧最多吃一根，避免多个重叠花盆在同一帧同时被吃空。
			return

func _find_watering_target_pot() -> Node2D:
	if personality != Personality.MUTSUMI or health <= 0:
		return null
	var nearest:Node2D = null
	var nearest_distance:float = INF
	for node:Node in get_tree().get_nodes_in_group("MutsumiCucumberPot"):
		if node == null or not is_instance_valid(node) or not node is Node2D:
			continue
		if not node.has_method("is_owned_by") or not bool(node.call("is_owned_by", self)):
			continue
		var pot:Node2D = node as Node2D
		var radius:float = maxf(float(node.get("interaction_radius")), 1.0)
		var distance_value:float = global_position.distance_to(pot.global_position)
		if distance_value <= radius and distance_value < nearest_distance:
			nearest = pot
			nearest_distance = distance_value
	return nearest

func _update_watering_visual(delta:float) -> void:
	_update_existing_water_drops(delta)
	var pot:Node2D = _find_watering_target_pot()
	_set_watering_audio_everywhere(pot != null)
	if _watering_can_visual == null or _watering_spout == null:
		_clear_watering_drops()
		return
	if pot == null:
		_watering_can_visual.visible = false
		_watering_drop_elapsed = 0.0
		# V167：一旦不再处于真实浇水状态，立即清掉所有仍在飞行的蓝色水滴。
		# 旧版允许它们继续飞完，如果此时角色 tick/authority 又发生切换，就可能留下失去更新者的 Line2D。
		_clear_watering_drops()
		return

	var pot_local:Vector2 = to_local(pot.global_position)
	var side:float = -1.0 if pot_local.x < 0.0 else 1.0
	# 原图壶嘴朝左；盆栽在右边时用负 X scale 镜像，让壶嘴始终朝盆栽。
	var abs_scale:float = 0.18
	_watering_can_visual.scale = Vector2(abs_scale if side < 0.0 else -abs_scale, abs_scale)
	_watering_can_visual.position = Vector2(side * 78.0, -46.0)
	_watering_can_visual.rotation = deg_to_rad(side * 7.0)
	_watering_can_visual.visible = true

	_watering_drop_elapsed += maxf(delta,0.0)
	var interval:float = maxf(water_drop_interval,0.015)
	var spawned:int = 0
	while _watering_drop_elapsed >= interval and spawned < 5:
		_watering_drop_elapsed -= interval
		_spawn_water_drop(pot)
		spawned += 1
	if spawned >= 5:
		_watering_drop_elapsed = minf(_watering_drop_elapsed,interval)

func _spawn_water_drop(pot:Node2D) -> void:
	if pot == null or not is_instance_valid(pot) or _watering_spout == null:
		return
	var start:Vector2 = _watering_spout.global_position
	var finish:Vector2 = pot.global_position + Vector2(randf_range(-5.0,5.0),randf_range(-10.0,-5.0))
	var distance_value:float = start.distance_to(finish)
	var control:Vector2 = (start + finish) * 0.5 + Vector2(0.0,-clampf(water_arc_height + distance_value * 0.10,18.0,110.0))
	var line:=Line2D.new()
	line.name = "若叶睦_浇水滴"
	line.width = maxf(water_drop_width,0.4)
	line.default_color = Color(0.22,0.72,1.0,0.96)
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	line.z_as_relative = false
	line.z_index = 43
	line.points = PackedVector2Array([Vector2(-water_drop_length * 0.5,0.0),Vector2(water_drop_length * 0.5,0.0)])
	# V167：水滴改成若叶睦自己的 top_level 子节点。视觉仍使用世界坐标，不会跟着角色移动，
	# 但角色被移除时 Godot 会随父节点一起释放这些水滴，避免挂在 current_scene 根部成为孤儿。
	add_child(line)
	line.top_level = true
	line.global_position = start
	var duration:float = randf_range(maxf(water_drop_travel_time * 0.88,0.08),maxf(water_drop_travel_time * 1.12,0.10))
	# 即使角色的 tick / authority 意外中断，每滴水也有自己的超时保险，不依赖角色继续更新才能消失。
	var safety_tween:Tween = line.create_tween()
	safety_tween.tween_interval(duration + 0.20)
	safety_tween.tween_callback(Callable(line,"queue_free"))
	_watering_drops.append({
		"line": line,
		"start": start,
		"control": control,
		"finish": finish,
		"elapsed": 0.0,
		"duration": duration,
		"pot": weakref(pot),
	})

func _update_existing_water_drops(delta:float) -> void:
	if _watering_drops.is_empty():
		return
	var survivors:Array[Dictionary] = []
	for data:Dictionary in _watering_drops:
		var line:Line2D = data.get("line",null) as Line2D
		if line == null or not is_instance_valid(line):
			continue
		var elapsed:float = float(data.get("elapsed",0.0)) + maxf(delta,0.0)
		var duration:float = maxf(float(data.get("duration",water_drop_travel_time)),0.05)
		var t:float = clampf(elapsed / duration,0.0,1.0)
		var start:Vector2 = data.get("start",global_position)
		var control:Vector2 = data.get("control",global_position)
		var finish:Vector2 = data.get("finish",global_position)
		var position_now:Vector2 = _quadratic_bezier_point(start,control,finish,t)
		var tangent:Vector2 = _quadratic_bezier_tangent(start,control,finish,t)
		line.global_position = position_now
		if tangent.length_squared() > 0.000001:
			line.global_rotation = tangent.angle()
		if t >= 1.0:
			line.queue_free()
			_spawn_water_impact_white_lines(data,finish,tangent)
			continue
		data["elapsed"] = elapsed
		survivors.append(data)
	_watering_drops = survivors

func _spawn_water_impact_white_lines(data:Dictionary,impact_position:Vector2,incoming_tangent:Vector2) -> void:
	var pot_ref:WeakRef = data.get("pot",null) as WeakRef
	var raw:Variant = pot_ref.get_ref() if pot_ref != null else null
	if not raw is Node2D or not is_instance_valid(raw):
		return
	var pot:Node2D = raw as Node2D
	var scene:Node = get_tree().current_scene
	if scene == null:
		return
	var normal:Vector2 = Vector2.UP
	if incoming_tangent.length_squared() > 0.000001:
		# 水滴最终向下砸进盆栽，因此白线从盆面向外（主要朝上）喷开。
		normal = (-incoming_tangent.normalized()).lerp(Vector2.UP,0.72).normalized()
	var seed:int = Game.battle_rng_seed_or("scripts/characters/乐队/若叶睦.gd:seed",int(Time.get_ticks_usec()) ^ int(pot.get_instance_id()) ^ int(randf() * 2147483647.0))
	WATER_IMPACT_BURST_SCRIPT.spawn(scene,pot,impact_position,normal,maxf(water_impact_visual_speed,1.0),seed)

func _quadratic_bezier_point(start:Vector2,control:Vector2,finish:Vector2,t:float) -> Vector2:
	var clamped_t:float = clampf(t,0.0,1.0)
	var inv:float = 1.0 - clamped_t
	return inv * inv * start + 2.0 * inv * clamped_t * control + clamped_t * clamped_t * finish

func _quadratic_bezier_tangent(start:Vector2,control:Vector2,finish:Vector2,t:float) -> Vector2:
	var clamped_t:float = clampf(t,0.0,1.0)
	return 2.0 * (1.0 - clamped_t) * (control - start) + 2.0 * clamped_t * (finish - control)

func _clear_watering_drops() -> void:
	for data:Dictionary in _watering_drops:
		var line:Line2D = data.get("line",null) as Line2D
		if line != null and is_instance_valid(line) and not line.is_queued_for_deletion():
			line.queue_free()
	_watering_drops.clear()
	# V167 保险清理：即使某滴因为数组状态异常没有留在 _watering_drops，
	# 只要仍是本角色的直系水滴子节点，也一并回收。不会碰其它角色的水滴。
	for child:Node in get_children():
		if child is Line2D and String(child.name).begins_with("若叶睦_浇水滴"):
			if not child.is_queued_for_deletion():
				child.queue_free()

func _hide_watering_visual() -> void:
	if _watering_can_visual != null:
		_watering_can_visual.visible = false
	_watering_drop_elapsed = 0.0
	_clear_watering_drops()

func _animate_punch_and_hit(attack_direction:Vector2) -> void:
	if _punch_visual == null or not is_instance_valid(_punch_visual):
		_perform_punch_hit(attack_direction)
		return
	var dir:Vector2 = attack_direction.normalized() if attack_direction.length_squared() > 0.000001 else Vector2.RIGHT
	# V191：attack_direction 是世界方向；拳头 Sprite 使用本地坐标，所以先抵消角色根节点
	# 因 Sans 定向重力产生的 global_rotation，避免重力朝左/上时拳头再被多转一次。
	var local_dir:Vector2 = dir.rotated(-global_rotation)
	_punch_visual_serial += 1
	var serial:int = _punch_visual_serial
	# V164：去掉随机横向抖动，让 AI 的预检测姿态与真正命中帧完全一致。
	var start_position:Vector2 = local_dir * MORTIS_PUNCH_START_DISTANCE
	var hit_position:Vector2 = local_dir * MORTIS_PUNCH_CONTACT_DISTANCE
	_punch_visual.position = start_position
	_punch_visual.rotation = local_dir.angle() + PI * 0.5
	var punch_scale:float = maxf(mortis_punch_visual_scale,0.01)
	_punch_visual.scale = Vector2(punch_scale,punch_scale)
	_punch_visual.modulate = Color(1.0,1.0,1.0,1.0)
	_punch_visual.visible = true
	_play_wakaba_sfx_everywhere(WakabaSfx.PUNCH_SWING,global_position + start_position,0.0,randf_range(0.97,1.04),1100.0)
	var thrust:Tween = create_tween()
	thrust.tween_property(_punch_visual,"position",hit_position,0.070).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await thrust.finished
	if not is_instance_valid(self) or health <= 0 or personality != Personality.MORTIS or serial != _punch_visual_serial:
		return
	_perform_punch_hit(dir)
	var retract:Tween = create_tween()
	retract.tween_property(_punch_visual,"position",start_position,0.085).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	retract.parallel().tween_property(_punch_visual,"modulate:a",0.55,0.085)
	await retract.finished
	if is_instance_valid(self) and _punch_visual != null and is_instance_valid(_punch_visual) and serial == _punch_visual_serial:
		_punch_visual.visible = false
		_punch_visual.modulate.a = 1.0

func _set_guitar_swing_pose(swing_offset:float,base_angle:float) -> void:
	if _guitar_visual == null or not is_instance_valid(_guitar_visual):
		return
	var swing_angle:float = base_angle + swing_offset
	_guitar_visual.position = Vector2.RIGHT.rotated(swing_angle) * MORTIS_GUITAR_ORBIT_RADIUS + Vector2(0.0,MORTIS_GUITAR_VERTICAL_OFFSET)
	# 吉他原图的琴身在局部 +Y、琴颈/琴头在局部 -Y。
	# 抡击时应让琴身朝挥击外侧、琴颈靠近角色；V160 的 +PI/2 恰好反了。
	_guitar_visual.rotation = swing_angle - PI * 0.5
	var guitar_scale:float = maxf(mortis_guitar_visual_scale,0.01)
	_guitar_visual.scale = Vector2(guitar_scale,guitar_scale)
	_guitar_visual.modulate = Color(1.0,1.0,1.0,1.0)
	_maybe_spawn_guitar_trail_ghost()

func _animate_guitar_to_contact(attack_direction:Vector2) -> void:
	if _guitar_visual == null or not is_instance_valid(_guitar_visual):
		await get_tree().process_frame
		return
	var base_angle:float = attack_direction.angle() - global_rotation
	_guitar_visual.visible = true
	_play_wakaba_sfx_everywhere(WakabaSfx.GUITAR_SWING,global_position,-5.0,randf_range(0.98,1.02),1000.0)
	_set_guitar_swing_pose(-1.10,base_angle)
	var windup:Tween = create_tween()
	windup.tween_method(Callable(self,"_set_guitar_swing_pose").bind(base_angle),-1.10,MORTIS_GUITAR_CONTACT_SWING_OFFSET,0.155).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await windup.finished

func _animate_guitar_follow_through(attack_direction:Vector2) -> void:
	if _guitar_visual == null or not is_instance_valid(_guitar_visual):
		await get_tree().process_frame
		return
	var base_angle:float = attack_direction.angle() - global_rotation
	var follow:Tween = create_tween()
	follow.tween_method(Callable(self,"_set_guitar_swing_pose").bind(base_angle),MORTIS_GUITAR_CONTACT_SWING_OFFSET,1.18,0.205).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	follow.parallel().tween_property(_guitar_visual,"modulate:a",0.72,0.205)
	await follow.finished
	if is_instance_valid(self) and _guitar_visual != null and is_instance_valid(_guitar_visual):
		_guitar_visual.visible = false
		_guitar_visual.modulate.a = 1.0

func _hide_combat_item_visuals() -> void:
	_punch_visual_serial += 1
	if _punch_visual != null:
		_punch_visual.visible = false
	if _guitar_visual != null:
		_guitar_visual.visible = false
	_clear_guitar_trail_ghosts()

func _set_action_visuals_hidden() -> void:
	_hide_combat_item_visuals()
	_hide_watering_visual()

func consume_cucumber_from_pot(instant_ratio:float,hot_ratio:float,duration:float) -> bool:
	# V173：食用改为完整演出。开始吃时先从盆上取走一根，黄瓜在嘴边抖动并掉碎屑；
	# 演出期间 _cucumber_eating 锁住，不能再从任何花盆拿第二根，结束时才结算回血。
	if health <= 0 or health >= Max_health or _cucumber_eating:
		return false
	_cucumber_eating = true
	_cucumber_eat_serial += 1
	_cucumber_pending_instant_ratio = maxf(instant_ratio,0.0)
	_cucumber_pending_hot_ratio = maxf(hot_ratio,0.0)
	_cucumber_pending_duration = maxf(duration,0.05)
	_begin_cucumber_eat_visual(_cucumber_eat_serial)
	return true

func _begin_cucumber_eat_visual(serial:int) -> void:
	if _cucumber_eat_visual != null and is_instance_valid(_cucumber_eat_visual):
		_cucumber_eat_visual.queue_free()
	var visual:=Sprite2D.new()
	visual.name = "CucumberEatingVisual"
	visual.texture = CUCUMBER_TEXTURE
	visual.z_index = 48
	visual.position = Vector2(0.0,-24.0)
	var tex_size:Vector2 = CUCUMBER_TEXTURE.get_size()
	var longest:float = maxf(tex_size.x,tex_size.y)
	var fit_scale:float = cucumber_mouth_visual_size / maxf(longest,1.0)
	visual.scale = Vector2.ONE * fit_scale
	add_child(visual)
	_cucumber_eat_visual = visual
	var shake:=visual.create_tween().set_loops()
	shake.tween_property(visual,"position:y",visual.position.y - 3.2,0.08).set_trans(Tween.TRANS_SINE)
	shake.tween_property(visual,"position:y",visual.position.y + 3.2,0.08).set_trans(Tween.TRANS_SINE)
	var total:float = maxf(cucumber_eat_duration,0.35)
	var sound_count:int = randi_range(mini(cucumber_eat_sound_min_count,cucumber_eat_sound_max_count),maxi(cucumber_eat_sound_min_count,cucumber_eat_sound_max_count))
	var sound_timeline:=create_tween()
	for i:int in range(sound_count):
		sound_timeline.tween_callback(func(): _play_random_cucumber_bite(serial))
		if i < sound_count - 1:
			sound_timeline.tween_interval(randf_range(minf(cucumber_eat_sound_gap_min,cucumber_eat_sound_gap_max),maxf(cucumber_eat_sound_gap_min,cucumber_eat_sound_gap_max)))
	var crumb_timeline:=create_tween()
	var bursts:int = maxi(3,int(ceil(total / 0.24)))
	for i:int in range(bursts):
		crumb_timeline.tween_callback(func(): _spawn_cucumber_crumbs(serial))
		if i < bursts - 1:
			crumb_timeline.tween_interval(total / float(bursts))
	var finish:=create_tween()
	finish.tween_interval(total)
	finish.tween_callback(func(): _finish_cucumber_eat(serial))

func _play_random_cucumber_bite(serial:int) -> void:
	if not _cucumber_eating or serial != _cucumber_eat_serial or health <= 0:
		return
	var kind:int = [WakabaSfx.CUCUMBER_EAT_1,WakabaSfx.CUCUMBER_EAT_2,WakabaSfx.CUCUMBER_EAT_3].pick_random()
	_play_wakaba_sfx_everywhere(kind,global_position + Vector2(0.0,-22.0),2.0,randf_range(0.96,1.05),760.0)

func _spawn_cucumber_crumbs(serial:int) -> void:
	if not _cucumber_eating or serial != _cucumber_eat_serial or CUCUMBER_TEXTURE == null:
		return
	var size:Vector2 = CUCUMBER_TEXTURE.get_size()
	if size.x < 2.0 or size.y < 2.0:
		return
	for i:int in range(maxi(cucumber_crumbs_per_burst,1)):
		var crumb:=Sprite2D.new()
		crumb.name = "CucumberCrumb"
		crumb.texture = CUCUMBER_TEXTURE
		crumb.region_enabled = true
		var side:float = randf_range(24.0,48.0)
		var rx:float = randf_range(0.0,maxf(size.x - side,0.0))
		var ry:float = randf_range(0.0,maxf(size.y - side,0.0))
		crumb.region_rect = Rect2(rx,ry,side,side)
		crumb.position = Vector2(randf_range(-11.0,11.0),randf_range(-28.0,-16.0))
		# V174：碎屑明显放大，并使用最近邻过滤，让“来自黄瓜图片的方块碎片”更清楚。
		crumb.scale = Vector2.ONE * randf_range(0.30,0.46)
		crumb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		crumb.z_index = 50
		add_child(crumb)
		var tween:=crumb.create_tween().set_parallel(true)
		tween.tween_property(crumb,"position",crumb.position + Vector2(randf_range(-24.0,24.0),randf_range(46.0,82.0)),randf_range(0.46,0.68)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(crumb,"rotation",crumb.rotation + randf_range(-2.8,2.8),0.58)
		tween.tween_property(crumb,"modulate:a",0.0,0.56).set_delay(0.12)
		tween.finished.connect(crumb.queue_free,CONNECT_ONE_SHOT)

func _finish_cucumber_eat(serial:int) -> void:
	if serial != _cucumber_eat_serial:
		return
	if _cucumber_eat_visual != null and is_instance_valid(_cucumber_eat_visual):
		_cucumber_eat_visual.queue_free()
	_cucumber_eat_visual = null
	var instant_ratio:float = _cucumber_pending_instant_ratio
	var hot_ratio:float = _cucumber_pending_hot_ratio
	var duration:float = _cucumber_pending_duration
	_cucumber_pending_instant_ratio = 0.0
	_cucumber_pending_hot_ratio = 0.0
	_cucumber_pending_duration = 0.0
	_cucumber_eating = false
	if health <= 0:
		return
	var instant_amount:float = float(Max_health) * instant_ratio
	var hot_total:float = float(Max_health) * hot_ratio
	heal(instant_amount)
	if hot_total > 0.0:
		_hot_left = maxf(duration,0.05)
		_hot_rate = hot_total / _hot_left
		_hot_fraction = 0.0

func _update_hot(delta:float) -> void:
	if _hot_left <= 0.0 or _hot_rate <= 0.0 or health <= 0:
		return
	var step:float = minf(delta,_hot_left)
	_hot_left = maxf(_hot_left - step,0.0)
	_hot_fraction += _hot_rate * step
	var whole:int = int(floor(_hot_fraction))
	if whole > 0:
		_hot_fraction -= float(whole)
		heal(float(whole))
	if _hot_left <= 0.0:
		_hot_rate = 0.0
		_hot_fraction = 0.0

func _run_double_punch(attack_direction:Vector2) -> void:
	if _mortis_action_busy:
		return
	_mortis_action_busy = true
	_punch_cooldown_left = maxf(mortis_punch_cooldown,0.05)
	var dir:Vector2 = attack_direction.normalized() if attack_direction.length_squared() > 0.000001 else Vector2.RIGHT
	await _animate_punch_and_hit(dir.rotated(MORTIS_PUNCH_LEFT_ANGLE_OFFSET))
	if is_instance_valid(self) and health > 0 and personality == Personality.MORTIS:
		await get_tree().create_timer(maxf(mortis_double_punch_interval * 0.35,0.02),false,true).timeout
	if is_instance_valid(self) and health > 0 and personality == Personality.MORTIS:
		await _animate_punch_and_hit(dir.rotated(MORTIS_PUNCH_RIGHT_ANGLE_OFFSET))
	_mortis_action_busy = false

func _can_punch_reach_target(target:ball,attack_direction:Vector2) -> bool:
	if target == null or not _is_valid_enemy(target):
		return false
	var dir:Vector2 = attack_direction.normalized() if attack_direction.length_squared() > 0.000001 else Vector2.RIGHT
	if not _punch_collision_shapes.is_empty() and _punch_visual != null and is_instance_valid(_punch_visual):
		for angle_offset:float in [MORTIS_PUNCH_LEFT_ANGLE_OFFSET,MORTIS_PUNCH_RIGHT_ANGLE_OFFSET]:
			var punch_dir:Vector2 = dir.rotated(angle_offset)
			var local_punch_dir:Vector2 = punch_dir.rotated(-global_rotation)
			var local_position:Vector2 = local_punch_dir * MORTIS_PUNCH_CONTACT_DISTANCE
			var local_rotation:float = local_punch_dir.angle() + PI * 0.5
			var scale_value:float = maxf(mortis_punch_visual_scale,0.01)
			var attack_transform:Transform2D = _sprite_global_transform_for_local_pose(
				_punch_visual,local_position,local_rotation,Vector2(scale_value,scale_value)
			)
			if _attack_shapes_hit_specific_target(_punch_collision_shapes,attack_transform,target):
				return true
		return false
	# 图片碰撞构建失败时才沿用旧距离条件作为安全回退。
	return global_position.distance_to(combat_target_position(target)) <= mortis_punch_range

func _can_guitar_reach_target(target:ball,attack_direction:Vector2) -> bool:
	if target == null or not _is_valid_enemy(target):
		return false
	var dir:Vector2 = attack_direction.normalized() if attack_direction.length_squared() > 0.000001 else Vector2.RIGHT
	if not _guitar_collision_shapes.is_empty() and _guitar_visual != null and is_instance_valid(_guitar_visual):
		var swing_angle:float = dir.angle() - global_rotation + MORTIS_GUITAR_CONTACT_SWING_OFFSET
		var local_position:Vector2 = Vector2.RIGHT.rotated(swing_angle) * MORTIS_GUITAR_ORBIT_RADIUS + Vector2(0.0,MORTIS_GUITAR_VERTICAL_OFFSET)
		var local_rotation:float = swing_angle - PI * 0.5
		var scale_value:float = maxf(mortis_guitar_visual_scale,0.01)
		var attack_transform:Transform2D = _sprite_global_transform_for_local_pose(
			_guitar_visual,local_position,local_rotation,Vector2(scale_value,scale_value)
		)
		return _attack_shapes_hit_specific_target(_guitar_collision_shapes,attack_transform,target)
	# 图片碰撞构建失败时才沿用旧中距离条件作为安全回退。
	var distance_value:float = global_position.distance_to(combat_target_position(target))
	return distance_value >= mortis_guitar_min_range and distance_value <= mortis_guitar_max_range

func _sprite_global_transform_for_local_pose(
	sprite:Sprite2D,
	local_position:Vector2,
	local_rotation:float,
	local_scale:Vector2
) -> Transform2D:
	var local_transform:Transform2D = Transform2D(local_rotation,local_scale,sprite.skew,local_position)
	var parent_2d:Node2D = sprite.get_parent() as Node2D
	if parent_2d == null:
		return local_transform
	return parent_2d.global_transform * local_transform

func _attack_shapes_hit_specific_target(
	shapes:Array[ConvexPolygonShape2D],
	attack_transform:Transform2D,
	target:ball
) -> bool:
	if shapes.is_empty() or target == null or not _is_valid_enemy(target):
		return false
	var world:World2D = get_world_2d()
	if world == null:
		return false
	var space_state:PhysicsDirectSpaceState2D = world.direct_space_state
	for shape:ConvexPolygonShape2D in shapes:
		var query:PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
		query.shape = shape
		query.transform = attack_transform
		query.collision_mask = 2
		query.collide_with_bodies = false
		query.collide_with_areas = true
		var hits:Array[Dictionary] = space_state.intersect_shape(query,32)
		for hit:Dictionary in hits:
			var collider:Object = hit.get("collider",null) as Object
			if collider == null or not collider is hurtbox:
				continue
			var hit_target:ball = _hurtbox_target_ball(collider as hurtbox)
			if hit_target == target:
				return true
	return false

func _perform_punch_hit(attack_direction:Vector2) -> void:
	var targets:Array[ball] = []
	if not _punch_collision_shapes.is_empty() and _punch_visual != null and is_instance_valid(_punch_visual):
		targets = _attack_targets_from_sprite_alpha(_punch_visual,_punch_collision_shapes)
	else:
		# 只有图片 Alpha 多边形构建失败时才保留旧圆形范围作为安全回退，正常项目不走这里。
		var center:Vector2 = global_position + attack_direction * (mortis_punch_range * 0.48)
		var radius:float = mortis_punch_range * 0.52
		targets = _enemies_in_circle(center,radius)
	for target:ball in targets:
		var hit_dir:Vector2 = attack_direction
		var away:Vector2 = target.global_position - global_position
		if away.length_squared() > 0.000001:
			hit_dir = away.normalized()
		var target_health_before:int = int(target.health)
		var target_position_at_hit:Vector2 = target.global_position
		var did_hit:bool = target.receive_spatial_damage(
			attack_damage(mortis_punch_damage_multiplier),
			{"point":target_position_at_hit,"source":self},
			false,
			false
		)
		if did_hit:
			_play_wakaba_sfx_everywhere(WakabaSfx.PUNCH_HIT,target_position_at_hit,0.5,randf_range(0.97,1.035),1200.0)
			if mortis_punch_knockback_distance > 0.0:
				target.apply_knockback(hit_dir,mortis_punch_knockback_distance,mortis_punch_knockback_speed,0.0,0.0,{"source":self})
			if target_health_before > 0 and target.health <= 0:
				target.set_meta("_wakaba_specific_kill_blood_spawned",true)
				_spawn_mortis_kill_blood_everywhere(target_position_at_hit,hit_dir,MORTIS_KILL_BLOOD_PUNCH)

func _run_guitar_swing(attack_direction:Vector2) -> void:
	if _mortis_action_busy:
		return
	_mortis_action_busy = true
	_guitar_cooldown_left = maxf(mortis_guitar_cooldown,0.1)
	var dir:Vector2 = attack_direction.normalized() if attack_direction.length_squared() > 0.000001 else Vector2.RIGHT
	await _animate_guitar_to_contact(dir)
	if not is_instance_valid(self) or health <= 0 or personality != Personality.MORTIS:
		_mortis_action_busy = false
		return
	var targets:Array[ball] = []
	if not _guitar_collision_shapes.is_empty() and _guitar_visual != null and is_instance_valid(_guitar_visual):
		targets = _attack_targets_from_sprite_alpha(_guitar_visual,_guitar_collision_shapes)
	else:
		# 只有图片 Alpha 多边形构建失败时才保留旧扇形范围作为安全回退，正常项目不走这里。
		var min_dot:float = cos(deg_to_rad(clampf(mortis_guitar_arc_degrees,20.0,180.0) * 0.5))
		for target:ball in _all_valid_enemies():
			var fallback_to_target:Vector2 = target.global_position - global_position
			var fallback_distance:float = fallback_to_target.length()
			if fallback_distance <= 0.001 or fallback_distance > mortis_guitar_max_range:
				continue
			if dir.dot(fallback_to_target / fallback_distance) < min_dot:
				continue
			targets.append(target)
	var guitar_hit_any:bool = false
	for target:ball in targets:
		var to_target:Vector2 = target.global_position - global_position
		var knockback_dir:Vector2 = dir
		if to_target.length_squared() > 0.000001:
			knockback_dir = to_target.normalized()
		var target_health_before:int = int(target.health)
		var target_position_at_hit:Vector2 = target.global_position
		var did_hit:bool = target.receive_spatial_damage(
			attack_damage(mortis_guitar_damage_multiplier),
			{"point":target_position_at_hit,"source":self},
			false,
			false
		)
		if did_hit:
			guitar_hit_any = true
			_play_wakaba_sfx_everywhere(WakabaSfx.GUITAR_HIT,target_position_at_hit,-1.0,randf_range(0.98,1.02),1250.0)
			_play_wakaba_sfx_everywhere(WakabaSfx.GUITAR_COLLISION_HIT,target_position_at_hit,-3.0,randf_range(0.97,1.03),1250.0)
			if mortis_guitar_knockback_distance > 0.0:
				target.apply_knockback(knockback_dir,mortis_guitar_knockback_distance,mortis_guitar_knockback_speed,0.08,0.0,{"source":self})
			if target_health_before > 0 and target.health <= 0:
				target.set_meta("_wakaba_specific_kill_blood_spawned",true)
				_spawn_mortis_kill_blood_everywhere(target_position_at_hit,knockback_dir,MORTIS_KILL_BLOOD_GUITAR)
	# “全都不会”是吉他实际打中人的角色语音：一次挥击无论同时命中多少目标，只播一次。
	if guitar_hit_any:
		_play_wakaba_sfx_everywhere(WakabaSfx.GUITAR_HIT_VOICE,global_position,7.0,1.0,1250.0)
	await _animate_guitar_follow_through(dir)
	_mortis_action_busy = false

func _prepare_mortis_attack_collision_shapes() -> void:
	_punch_collision_shapes = _build_sprite_alpha_convex_shapes(_punch_visual)
	_guitar_collision_shapes = _build_sprite_alpha_convex_shapes(_guitar_visual)
	if _punch_collision_shapes.is_empty():
		push_warning("墨提斯拳头图片碰撞构建失败，将仅在运行时使用旧圆形范围回退。")
	if _guitar_collision_shapes.is_empty():
		push_warning("墨提斯吉他图片碰撞构建失败，将仅在运行时使用旧扇形范围回退。")

func _build_sprite_alpha_convex_shapes(sprite:Sprite2D) -> Array[ConvexPolygonShape2D]:
	var result:Array[ConvexPolygonShape2D] = []
	if sprite == null or not is_instance_valid(sprite) or sprite.texture == null:
		return result
	var source_image:Image = sprite.texture.get_image()
	if source_image == null or source_image.is_empty():
		return result
	var bitmap:BitMap = BitMap.new()
	bitmap.create_from_image_alpha(source_image,clampf(mortis_attack_alpha_threshold,0.01,0.95))
	var bitmap_size:Vector2i = bitmap.get_size()
	if bitmap_size.x <= 0 or bitmap_size.y <= 0:
		return result
	var polygons:Array[PackedVector2Array] = bitmap.opaque_to_polygons(
		Rect2i(Vector2i.ZERO,bitmap_size),
		maxf(mortis_attack_polygon_epsilon,0.25)
	)
	var texture_size:Vector2 = Vector2(float(bitmap_size.x),float(bitmap_size.y))
	var draw_origin:Vector2 = sprite.offset
	if sprite.centered:
		draw_origin -= texture_size * 0.5
	for polygon:PackedVector2Array in polygons:
		if polygon.size() < 3:
			continue
		var local_polygon:PackedVector2Array = PackedVector2Array()
		for point:Vector2 in polygon:
			var local_point:Vector2 = point + draw_origin
			if sprite.flip_h:
				local_point.x = sprite.offset.x * 2.0 - local_point.x
			if sprite.flip_v:
				local_point.y = sprite.offset.y * 2.0 - local_point.y
			local_polygon.append(local_point)
		var convex_parts:Array[PackedVector2Array] = Geometry2D.decompose_polygon_in_convex(local_polygon)
		for convex:PackedVector2Array in convex_parts:
			if convex.size() < 3:
				continue
			var shape:ConvexPolygonShape2D = ConvexPolygonShape2D.new()
			shape.points = convex
			result.append(shape)
	return result

func _attack_targets_from_sprite_alpha(sprite:Sprite2D,shapes:Array[ConvexPolygonShape2D]) -> Array[ball]:
	var targets:Array[ball] = []
	if sprite == null or not is_instance_valid(sprite) or shapes.is_empty():
		return targets
	var world:World2D = get_world_2d()
	if world == null:
		return targets
	var space_state:PhysicsDirectSpaceState2D = world.direct_space_state
	var seen:Dictionary = {}
	for shape:ConvexPolygonShape2D in shapes:
		var query:PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
		query.shape = shape
		query.transform = sprite.global_transform
		query.collision_mask = 2
		query.collide_with_bodies = false
		query.collide_with_areas = true
		var hits:Array[Dictionary] = space_state.intersect_shape(query,64)
		for hit:Dictionary in hits:
			var collider:Object = hit.get("collider",null) as Object
			if collider == null or not collider is hurtbox:
				continue
			var target:ball = _hurtbox_target_ball(collider as hurtbox)
			if target == null or not _is_valid_enemy(target):
				continue
			var target_id:int = target.get_instance_id()
			if seen.has(target_id):
				continue
			seen[target_id] = true
			targets.append(target)
	return targets

func _maybe_spawn_guitar_trail_ghost() -> void:
	if _guitar_visual == null or not is_instance_valid(_guitar_visual) or not _guitar_visual.visible:
		return
	if _guitar_trail_root == null or not is_instance_valid(_guitar_trail_root):
		return
	var now_msec:int = Time.get_ticks_msec()
	var interval_msec:int = maxi(int(round(maxf(mortis_guitar_trail_interval,0.001) * 1000.0)),1)
	if now_msec - _guitar_trail_last_spawn_msec < interval_msec:
		return
	_guitar_trail_last_spawn_msec = now_msec
	var ghost:Sprite2D = Sprite2D.new()
	ghost.texture = _guitar_visual.texture
	ghost.centered = _guitar_visual.centered
	ghost.offset = _guitar_visual.offset
	ghost.flip_h = _guitar_visual.flip_h
	ghost.flip_v = _guitar_visual.flip_v
	ghost.region_enabled = _guitar_visual.region_enabled
	ghost.region_rect = _guitar_visual.region_rect
	ghost.position = _guitar_visual.position
	ghost.rotation = _guitar_visual.rotation
	ghost.scale = _guitar_visual.scale
	ghost.z_index = _guitar_visual.z_index - 1
	ghost.modulate = Color(1.0,1.0,1.0,clampf(mortis_guitar_trail_alpha,0.0,1.0))
	_guitar_trail_root.add_child(ghost)
	var fade:Tween = ghost.create_tween()
	fade.tween_property(ghost,"modulate:a",0.0,maxf(mortis_guitar_trail_lifetime,0.01)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	fade.tween_callback(Callable(ghost,"queue_free"))

func _clear_guitar_trail_ghosts() -> void:
	_guitar_trail_last_spawn_msec = -1000000
	if _guitar_trail_root == null or not is_instance_valid(_guitar_trail_root):
		return
	for child:Node in _guitar_trail_root.get_children():
		child.queue_free()


func _spawn_mortis_kill_blood_everywhere(origin:Vector2,base_direction:Vector2,profile:int) -> void:
	if not is_multiplayer_authority():
		return
	var direction_value:Vector2 = base_direction.normalized() if base_direction.length_squared() > 0.000001 else Vector2.RIGHT
	var count:int = mortis_punch_kill_blood_count
	var spread:float = mortis_punch_kill_blood_spread_degrees
	var force_value:float = mortis_punch_kill_blood_force
	if profile == MORTIS_KILL_BLOOD_GUITAR:
		count = mortis_guitar_kill_blood_count
		spread = mortis_guitar_kill_blood_spread_degrees
		force_value = mortis_guitar_kill_blood_force
	var seed_value:int = int(randi())
	if multiplayer.has_multiplayer_peer():
		_rpc_spawn_mortis_kill_blood.rpc(origin,direction_value,profile,seed_value,count,spread,force_value)
	else:
		_rpc_spawn_mortis_kill_blood(origin,direction_value,profile,seed_value,count,spread,force_value)


@rpc("authority","call_local","unreliable")
func _rpc_spawn_mortis_kill_blood(
	origin:Vector2,
	base_direction:Vector2,
	profile:int,
	seed_value:int,
	projectile_count:int,
	spread_degrees:float,
	force_value:float
) -> void:
	if not is_inside_tree():
		return
	var scene_root:Node = get_tree().current_scene
	if scene_root == null:
		return
	var effect:Node2D = MORTIS_KILL_BLOOD_SCRIPT.new() as Node2D
	if effect == null:
		return
	effect.name = "WakabaMortisKillBloodBurst"
	scene_root.add_child(effect)
	effect.call("configure",origin,base_direction,profile,seed_value,projectile_count,spread_degrees,force_value)


func _play_wakaba_sfx_everywhere(kind:int,position_value:Vector2,volume_db:float,pitch:float,max_distance:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_wakaba_sfx.rpc(kind,position_value,volume_db,pitch,max_distance)
	else:
		_rpc_play_wakaba_sfx(kind,position_value,volume_db,pitch,max_distance)


@rpc("authority","call_local","unreliable")
func _rpc_play_wakaba_sfx(kind:int,position_value:Vector2,volume_db:float,pitch:float,max_distance:float) -> void:
	var stream:AudioStream = null
	match kind:
		WakabaSfx.POT_PLACE:
			stream = POT_PLACE_SFX
		WakabaSfx.PUNCH_SWING:
			stream = MORTIS_PUNCH_SWING_SFX
		WakabaSfx.PUNCH_HIT:
			stream = MORTIS_PUNCH_HIT_SFX
		WakabaSfx.GUITAR_SWING:
			stream = MORTIS_GUITAR_SWING_SFX
		WakabaSfx.GUITAR_HIT:
			stream = MORTIS_GUITAR_HIT_SFX
		WakabaSfx.GUITAR_COLLISION_HIT:
			stream = MORTIS_GUITAR_COLLISION_HIT_SFX
		WakabaSfx.SWITCH_TO_MORTIS_VOICE:
			stream = MORTIS_SWITCH_VOICE
		WakabaSfx.SWITCH_TO_MUTSUMI_VOICE:
			stream = MUTSUMI_SWITCH_VOICE
		WakabaSfx.GUITAR_HIT_VOICE:
			stream = MORTIS_GUITAR_HIT_VOICE
		WakabaSfx.WATERING_HUM_VOICE:
			stream = MUTSUMI_WATERING_HUM_VOICE
		WakabaSfx.CUCUMBER_EAT_1:
			stream = CUCUMBER_EAT_SFX_1
		WakabaSfx.CUCUMBER_EAT_2:
			stream = CUCUMBER_EAT_SFX_2
		WakabaSfx.CUCUMBER_EAT_3:
			stream = CUCUMBER_EAT_SFX_3
		_:
			return
	if stream == null or not is_inside_tree():
		return
	var scene_root:Node = get_tree().current_scene
	if scene_root == null:
		return
	var player:=AudioStreamPlayer2D.new()
	player.name = "WakabaMutsumiSFX"
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = clampf(pitch,0.75,1.30)
	player.max_distance = maxf(max_distance,50.0)
	player.attenuation = 0.50
	player.max_polyphony = 8
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	scene_root.add_child(player)
	player.global_position = position_value
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _set_watering_audio_everywhere(active:bool) -> void:
	if _watering_audio_active == active:
		return
	_watering_audio_active = active
	if multiplayer.has_multiplayer_peer():
		_rpc_set_watering_audio.rpc(active)
	else:
		_rpc_set_watering_audio(active)


@rpc("authority","call_local","reliable")
func _rpc_set_watering_audio(active:bool) -> void:
	if active:
		_start_watering_loop_local()
		# V170：进入一次连续浇花状态时播放一次“哼”；原浇水水声仍独立循环。
		_rpc_play_wakaba_sfx(WakabaSfx.WATERING_HUM_VOICE,global_position,12.0,1.0,900.0)
	else:
		_stop_watering_loop_local()


func _start_watering_loop_local() -> void:
	if _watering_loop_player != null and is_instance_valid(_watering_loop_player):
		if not _watering_loop_player.playing:
			_watering_loop_player.play()
		return
	var loop_stream:AudioStream = WATERING_LOOP_SFX.duplicate() as AudioStream
	if loop_stream == null:
		return
	if loop_stream is AudioStreamMP3:
		(loop_stream as AudioStreamMP3).loop = true
	_watering_loop_player = AudioStreamPlayer2D.new()
	_watering_loop_player.name = "WakabaWateringLoop"
	_watering_loop_player.stream = loop_stream
	_watering_loop_player.volume_db = -8.0
	_watering_loop_player.max_distance = 760.0
	_watering_loop_player.attenuation = 0.65
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		_watering_loop_player.bus = &"GameplayRecord"
	add_child(_watering_loop_player)
	_watering_loop_player.position = Vector2.ZERO
	_watering_loop_player.play()


func _stop_watering_loop_local() -> void:
	if _watering_loop_player == null or not is_instance_valid(_watering_loop_player):
		_watering_loop_player = null
		return
	_watering_loop_player.stop()
	_watering_loop_player.queue_free()
	_watering_loop_player = null


func _all_valid_enemies() -> Array[ball]:
	var result:Array[ball] = []
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if node is ball and _is_valid_enemy(node as ball):
			result.append(node as ball)
	return result

func _enemies_in_circle(center:Vector2,radius:float) -> Array[ball]:
	var result:Array[ball] = []
	var radius_sq:float = radius * radius
	for target:ball in _all_valid_enemies():
		if center.distance_squared_to(target.global_position) <= radius_sq:
			result.append(target)
	return result

func _find_nearest_enemy() -> ball:
	var nearest:ball = null
	var nearest_distance_sq:float = INF
	for target:ball in _all_valid_enemies():
		var d:float = global_position.distance_squared_to(target.global_position)
		if d < nearest_distance_sq:
			nearest_distance_sq = d
			nearest = target
	return nearest

func _is_valid_enemy(target:ball) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(self,target): return false # 皓宸复制品及其产物不把己方选为目标
	if target == null or not is_instance_valid(target) or target == self or target.health <= 0:
		return false
	if not target.is_combat_targetable():
		return false
	if target.state_machine != null and target.state_machine.current_state == State.Die:
		return false
	if not Game.Game_Settings.Have_Team_Damage and not Team.is_empty() and target.Team == Team:
		return false
	return true

func _apply_personality_visual() -> void:
	if _death_sequence_started:
		return
	if image == null or not is_instance_valid(image):
		return
	image.visible = true
	image.texture = MUTSUMI_TEXTURE if personality == Personality.MUTSUMI else MORTIS_TEXTURE
	var auto_fit:Node = get_node_or_null("CharacterAutoFit")
	if auto_fit != null and auto_fit.has_method("apply_visual_fit_only"):
		auto_fit.call_deferred("apply_visual_fit_only")

func _sync_personality_visual(next_personality:int) -> void:
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		_remote_set_personality_visual.rpc(next_personality)

@rpc("authority","call_remote","reliable")
func _remote_set_personality_visual(next_personality:int) -> void:
	personality = next_personality
	_apply_personality_visual()
	_update_personality_ui()

func _update_personality_ui() -> void:
	# V171：人格文字提示删除；人格状态仍由角色图片、动作与语音表达。
	pass

func _exit_tree() -> void:
	_stop_watering_loop_local()
	_stop_wakaba_death_tweens_local()


func _has_death_animation() -> bool:
	# V94：实体死亡后立即退出玩法，只保留这个节点作为短暂的纯视觉载体。
	# 返回 true 仅用于阻止 ball.gd 在 Die() 返回后同帧再次 queue_free()。
	return true


func Die() -> void:
	if _death_sequence_started:
		return
	_death_sequence_started = true
	if is_multiplayer_authority():
		_set_watering_audio_everywhere(false)
	else:
		_stop_watering_loop_local()
	_set_action_visuals_hidden()
	_clear_watering_drops()
	_enter_wakaba_death_visual_only_mode()
	for ref:WeakRef in _owned_pots:
		var raw:Variant = ref.get_ref() if ref != null else null
		if raw is Node and is_instance_valid(raw):
			(raw as Node).queue_free()
	_owned_pots.clear()

	_begin_wakaba_death_sequence_local(is_multiplayer_authority())
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		_remote_begin_wakaba_death_sequence.rpc()


func _enter_wakaba_death_visual_only_mode() -> void:
	# HP 已经为 0：从这里开始若叶睦不再是战斗角色，只留下死亡图片、光环与声音。
	velocity = Vector2.ZERO
	Repel = Vector2.ZERO
	Nearest_Enemy = null
	Target_Enemy = null
	Can_Attack = false
	Can_Skill = false
	Attacking = false
	Using_Skill = false
	set_process(false)
	set_physics_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)

	# 立即解除直接控制。这样“跟随我控制的角色”不会继续追着升天动画移动；
	# 服务器也会清掉对应 peer -> character 的控制映射。
	if Game != null and Game.has_method("release_character_control_for_death"):
		Game.call("release_character_control_for_death",self)
	set_player_control_peer(0)

	# World 的镜头中心、VS/目标扫描等公共路径主要枚举 Ball 组。
	# 死亡动画节点立即退出该组，避免视觉残影继续参与任何玩法/镜头统计。
	if is_in_group("Ball"):
		remove_from_group("Ball")

	collision_layer = 0
	collision_mask = 0
	_disable_wakaba_collision_tree(self)

	if health_restore_timer != null and is_instance_valid(health_restore_timer):
		health_restore_timer.stop()
	if hurting_timer != null and is_instance_valid(hurting_timer):
		hurting_timer.stop()
	if health_bar != null and is_instance_valid(health_bar):
		health_bar.visible = false
	if status_image != null and is_instance_valid(status_image):
		status_image.visible = false
	if side_status_ui != null and is_instance_valid(side_status_ui):
		side_status_ui.queue_free()
		side_status_ui = null
	if _character_ground_shadow != null and is_instance_valid(_character_ground_shadow):
		_character_ground_shadow.visible = false
	if _special_character_threat_overlay != null and is_instance_valid(_special_character_threat_overlay):
		_special_character_threat_overlay.visible = false


func _disable_wakaba_collision_tree(root:Node) -> void:
	for child:Node in root.get_children():
		if child is CollisionObject2D:
			var collision_object:CollisionObject2D = child as CollisionObject2D
			collision_object.collision_layer = 0
			collision_object.collision_mask = 0
			if collision_object is Area2D:
				(collision_object as Area2D).set_deferred("monitoring",false)
				(collision_object as Area2D).set_deferred("monitorable",false)
		if child is CollisionShape2D:
			(child as CollisionShape2D).set_deferred("disabled",true)
		_disable_wakaba_collision_tree(child)


func _begin_wakaba_death_sequence_local(wait_for_completion:bool) -> void:
	_stop_wakaba_death_tweens_local()
	_show_wakaba_death_visual()
	_death_base_global_position = global_position
	_death_base_modulate = modulate
	modulate = Color(_death_base_modulate.r,_death_base_modulate.g,_death_base_modulate.b,1.0)
	_create_wakaba_death_halo()

	if _death_sequence_player != null and is_instance_valid(_death_sequence_player):
		_death_sequence_player.stop()
		_death_sequence_player.queue_free()
	_death_sequence_player = AudioStreamPlayer2D.new()
	_death_sequence_player.name = "若叶睦_阵亡音"
	_death_sequence_player.stream = WAKABA_DEATH_SFX
	_death_sequence_player.volume_db = 6.0
	_death_sequence_player.max_distance = 1100.0
	_death_sequence_player.attenuation = 0.55
	_death_sequence_player.process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		_death_sequence_player.bus = &"GameplayRecord"
	add_child(_death_sequence_player)
	_death_sequence_player.play()

	var reveal_time:float = maxf(death_halo_reveal_time,0.05)
	var hold_time:float = maxf(death_halo_hold_time,0.0)
	var ascend_time:float = maxf(death_ascend_duration,0.1)
	var ascend_delay:float = reveal_time + hold_time

	if _death_halo != null and is_instance_valid(_death_halo):
		_death_halo.modulate = Color(1.0,1.0,1.0,0.0)
		_death_halo.scale = Vector2(0.78,0.78)
		_death_halo_tween = create_tween()
		_death_halo_tween.tween_property(_death_halo,"modulate",Color(1.0,1.0,1.0,1.0),reveal_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_death_halo_tween.parallel().tween_property(_death_halo,"scale",Vector2.ONE,reveal_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# V95：保留 V94 的微升天；白光已删除。死亡实体已从玩法/镜头系统脱离，这里只负责视觉载体移动与渐隐。
	var target_position:Vector2 = _death_base_global_position + Vector2(0.0,-maxf(death_ascend_distance,0.0))
	var target_modulate:Color = Color(_death_base_modulate.r,_death_base_modulate.g,_death_base_modulate.b,0.0)
	_death_visual_tween = create_tween()
	_death_visual_tween.tween_interval(ascend_delay)
	_death_visual_tween.tween_property(self,"global_position",target_position,ascend_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_death_visual_tween.parallel().tween_property(self,"modulate",target_modulate,ascend_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if wait_for_completion:
		_death_visual_tween.tween_callback(_finish_wakaba_death_sequence)

	# 阵亡音跟随纯视觉演出一起衰减；人物完全透明时声音也已经接近听不见。
	if _death_sequence_player != null and is_instance_valid(_death_sequence_player):
		var stream_length:float = maxf(WAKABA_DEATH_SFX.get_length(),0.0)
		var remaining_audio:float = maxf(stream_length - ascend_delay,0.25) if stream_length > 0.0 else ascend_time
		var fade_time:float = minf(ascend_time,remaining_audio)
		_death_audio_tween = create_tween()
		_death_audio_tween.tween_interval(ascend_delay)
		_death_audio_tween.tween_property(_death_sequence_player,"volume_db",death_audio_end_db,maxf(fade_time,0.2)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	if wait_for_completion:
		var fallback_timer:SceneTreeTimer = get_tree().create_timer(ascend_delay + ascend_time + 0.6,true,false,true)
		fallback_timer.timeout.connect(_finish_wakaba_death_sequence,CONNECT_ONE_SHOT)


func _show_wakaba_death_visual() -> void:
	if image != null and is_instance_valid(image):
		image.visible = true
		image.texture = MUTSUMI_DEATH_TEXTURE
		image.self_modulate = Color.WHITE
	var auto_fit:Node = get_node_or_null("CharacterAutoFit")
	if auto_fit != null and auto_fit.has_method("apply_visual_fit_only"):
		auto_fit.call_deferred("apply_visual_fit_only")


func _create_wakaba_death_halo() -> void:
	if _death_halo != null and is_instance_valid(_death_halo):
		_death_halo.queue_free()
	_death_halo = Node2D.new()
	_death_halo.name = "若叶睦_天使光环"
	_death_halo.position = Vector2(0.0,-maxf(death_halo_height,0.0))
	_death_halo.z_index = 80
	var graphics_node:Node = get_node_or_null("Graphics")
	if graphics_node != null:
		graphics_node.add_child(_death_halo)
	else:
		add_child(_death_halo)

	var points:PackedVector2Array = _build_wakaba_halo_points(maxf(death_halo_radius_x,1.0),maxf(death_halo_radius_y,1.0),48)
	var glow:Line2D = Line2D.new()
	glow.name = "Glow"
	glow.points = points
	glow.width = maxf(death_halo_line_width * 2.35,1.5)
	glow.default_color = Color(1.0,0.82,0.10,0.16)
	glow.antialiased = true
	_death_halo.add_child(glow)

	var ring:Line2D = Line2D.new()
	ring.name = "Ring"
	ring.points = points
	ring.width = maxf(death_halo_line_width,1.0)
	ring.default_color = Color(1.0,0.92,0.28,0.98)
	ring.antialiased = true
	_death_halo.add_child(ring)


func _build_wakaba_halo_points(radius_x:float,radius_y:float,segments:int) -> PackedVector2Array:
	var result:PackedVector2Array = PackedVector2Array()
	var count:int = maxi(segments,12)
	for index:int in range(count + 1):
		var angle:float = TAU * float(index) / float(count)
		result.append(Vector2(cos(angle) * radius_x,sin(angle) * radius_y))
	return result


func _stop_wakaba_death_tweens_local() -> void:
	if _death_visual_tween != null and _death_visual_tween.is_valid():
		_death_visual_tween.kill()
	_death_visual_tween = null
	if _death_halo_tween != null and _death_halo_tween.is_valid():
		_death_halo_tween.kill()
	_death_halo_tween = null
	if _death_audio_tween != null and _death_audio_tween.is_valid():
		_death_audio_tween.kill()
	_death_audio_tween = null


func _finish_wakaba_death_sequence() -> void:
	if not is_multiplayer_authority():
		return
	if not is_inside_tree() or is_queued_for_deletion():
		return
	_stop_wakaba_death_tweens_local()
	queue_free()


@rpc("authority","call_remote","reliable")
func _remote_begin_wakaba_death_sequence() -> void:
	_death_sequence_started = true
	_stop_watering_loop_local()
	_set_action_visuals_hidden()
	_clear_watering_drops()
	_enter_wakaba_death_visual_only_mode()
	_begin_wakaba_death_sequence_local(false)
