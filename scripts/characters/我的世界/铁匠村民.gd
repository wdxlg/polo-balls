extends ball

# Minecraft 分区自动成长角色：铁匠村民。
# - 自动锻造；持续不进行实际攻击时锻造越来越快，受到伤害不会重置，眩晕打断攻击期间也会继续累计。
# - 装备阶段：无 -> 铁 -> 钻石 -> 下界合金。
# - 装备未满时每 3 次锻造随机升级头盔或剑；两件装备满级后每次锻造随机永久 +10 伤害或 +10 护甲。
# - 没有剑时完全不能攻击；获得剑后使用近战挥剑攻击。
# - V89：锻造阶段格固定为 3 个并与主进度条严格居中；已点亮阶段格带辉光，装备满级后阶段格消失。
# - V89：场景内新增“锻造_可视调整”预览节点，运行时直接读取这些节点的位置/旋转/缩放/Skew，允许在 2D 编辑器里拖拽调整锻造动画关键姿态。

const TIER_NONE:int = 0
const TIER_IRON:int = 1
const TIER_DIAMOND:int = 2
const TIER_NETHERITE:int = 3

const BLACKSMITH_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/铁匠村民/铁匠.png")
const IRON_HELMET_BACK:Texture2D = preload("res://Images/characters/默认/盔甲架/Iron_Helmet.png")
const IRON_HELMET_FRONT:Texture2D = preload("res://Images/characters/默认/盔甲架/头盔前.png")
const DIAMOND_HELMET_BACK:Texture2D = preload("res://Images/characters/我的世界/铁匠村民/Diamond_Helmet.png")
const DIAMOND_HELMET_FRONT:Texture2D = preload("res://Images/characters/我的世界/铁匠村民/钻石头盔前.png")
const NETHERITE_HELMET_BACK:Texture2D = preload("res://Images/characters/我的世界/铁匠村民/Netherite_Helmet.png")
const NETHERITE_HELMET_FRONT:Texture2D = preload("res://Images/characters/我的世界/铁匠村民/下界前.png")

const IRON_SWORD_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/铁匠村民/Iron_Sword.png")
const DIAMOND_SWORD_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/钻石剑/钻石剑.png")
const NETHERITE_SWORD_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/钻石剑/下界合金剑.png")
const HAMMER_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/重锤/重锤.png")
const SINGLE_FORGE_SFX:AudioStream = preload("res://audio/characters/我的世界/铁匠村民/单次锻造.ogg")
const HELMET_UPGRADE_SFX:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/铁匠村民/头盔升级/头盔升级1.ogg"),
	preload("res://audio/characters/我的世界/铁匠村民/头盔升级/头盔升级2.ogg"),
	preload("res://audio/characters/我的世界/铁匠村民/头盔升级/头盔升级3.ogg"),
	preload("res://audio/characters/我的世界/铁匠村民/头盔升级/头盔升级4.ogg"),
	preload("res://audio/characters/我的世界/铁匠村民/头盔升级/头盔升级5.ogg"),
]
const SMITHING_SUCCESS_SFX:Array[AudioStream] = [
	preload("res://audio/sfx/我的世界/锻造/下界合金锻造1.ogg"),
	preload("res://audio/sfx/我的世界/锻造/下界合金锻造2.ogg"),
]
const MC_DAMAGE_SFX:Array[AudioStream] = [
	preload("res://audio/characters/女巫/hit1.ogg"),
	preload("res://audio/characters/女巫/hit2.ogg"),
	preload("res://audio/characters/女巫/hit3.ogg"),
]
const FALLBACK_STRONG_ATTACK_SFX:Array[AudioStream] = [
	preload("res://audio/sfx/我的世界/近战/重锤/猛击重/重锤猛击重.ogg"),
]
const SWEEP_ATTACK_SFX:Array[AudioStream] = [
	preload("res://audio/sfx/我的世界/近战/横扫/横扫01.ogg"),
	preload("res://audio/sfx/我的世界/近战/横扫/横扫02.ogg"),
	preload("res://audio/sfx/我的世界/近战/横扫/横扫03.ogg"),
	preload("res://audio/sfx/我的世界/近战/横扫/横扫04.ogg"),
	preload("res://audio/sfx/我的世界/近战/横扫/横扫05.ogg"),
	preload("res://audio/sfx/我的世界/近战/横扫/横扫06.ogg"),
	preload("res://audio/sfx/我的世界/近战/横扫/横扫07.ogg"),
]
const DEATH_SMOKE_FRAMES:SpriteFrames = preload("res://scenes/effects/我的世界/蠹虫死亡烟雾.tres")
const DAMAGE_TEXT_SCENE:PackedScene = preload("res://scenes/damage_text.tscn")
const DEATH_POSE_DURATION:float = 0.90

const COLOR_FORGE:Color = Color8(255,151,43,255)
@export_category("铁匠村民 / 锻造")
@export_range(1.0,20.0,0.1) var forge_base_interval:float = 5.0
@export_range(0.3,10.0,0.1) var forge_min_interval:float = 0.5
@export_range(0.0,5.0,0.05) var forge_acceleration_per_second:float = 1.0
@export_range(1,10,1) var forge_count_for_equipment:int = 3

@export_category("铁匠村民 / 头盔")
@export_range(0,2000,10) var iron_helmet_armor:int = 50
@export_range(0,3000,10) var diamond_helmet_armor:int = 100
@export_range(0,5000,10) var netherite_helmet_armor:int = 200
@export_range(0.0,0.90,0.01) var iron_helmet_damage_reduction:float = 0.10
@export_range(0.0,0.90,0.01) var diamond_helmet_damage_reduction:float = 0.20
@export_range(0.0,0.90,0.01) var netherite_helmet_damage_reduction:float = 0.50

@export_category("铁匠村民 / 剑")
@export_range(0,500,1) var iron_sword_damage:int = 20
@export_range(0,500,1) var diamond_sword_damage:int = 40
@export_range(0,500,1) var netherite_sword_damage:int = 100
@export_range(0.10,3.0,0.05) var sword_attack_cooldown:float = 1.0
@export_range(10.0,160.0,1.0) var sword_attack_range:float = 48.0
@export_range(5.0,175.0,1.0) var sword_half_angle_degrees:float = 42.0
@export_range(0.01,0.50,0.01) var sword_hit_delay:float = 0.22
@export_range(0.10,1.0,0.01) var sword_swing_duration:float = 0.46
@export_range(1.0,1.5,0.01) var high_damage_swing_speed_multiplier:float = 1.15
@export_range(1,12,1) var sword_afterimage_count:int = 10
@export_range(0.05,0.30,0.01) var sword_afterimage_lifetime:float = 0.18
@export_range(0.05,0.80,0.01) var sword_afterimage_alpha:float = 0.58
@export_range(1,5,1) var sword_kill_spin_turns:int = 3
@export_range(0.3,2.0,0.05) var sword_kill_spin_duration:float = 0.45

@export_category("铁匠村民 / 攻击音效")
@export_range(-12.0,12.0,0.5) var sword_swing_base_volume_db:float = 1.5
@export_range(-12.0,12.0,0.5) var sword_hit_base_volume_db:float = 0.0
@export_range(-12.0,12.0,0.5) var sword_critical_hit_base_volume_db:float = 2.0
@export_range(0.1,4.0,0.1) var sword_audio_db_per_damage_doubling:float = 1.5
@export_range(0.0,12.0,0.5) var sword_audio_max_bonus_db:float = 9.0

@export_category("铁匠村民 / 视觉")
@export_range(0.01,0.50,0.005) var sword_visual_scale:float = 0.12
@export_range(0.0,100.0,1.0) var sword_visual_distance:float = 35.0
@export_range(-100.0,100.0,1.0) var sword_visual_vertical_offset:float = -4.0
@export var sword_grip_uv:Vector2 = Vector2(0.206,0.768)

@export_category("铁匠村民 / 锻造动画（场景可视节点优先）")
@export_range(0.18,0.29,0.01) var forge_visual_duration:float = 0.26
@export_range(24.0,160.0,1.0) var forge_item_visual_long_edge:float = 78.0
@export_range(24.0,180.0,1.0) var forge_hammer_visual_long_edge:float = 98.0
# 下列值是没有“Graphics/锻造_可视调整”节点时的后备参数。正式铁匠场景存在可视节点时，运行时会读取节点 Transform。
@export var forge_item_start_position:Vector2 = Vector2(20.0,10.0)
@export var forge_item_hold_position:Vector2 = Vector2(8.0,36.0)
@export_range(0.30,0.80,0.01) var forge_item_flatten_ratio:float = 0.44
@export_range(-35.0,35.0,1.0) var forge_item_skew_degrees:float = 14.0
@export_range(8.0,48.0,1.0) var forge_impact_ring_radius:float = 24.0
@export_range(0.20,0.80,0.01) var forge_impact_ring_flatten_ratio:float = 0.40
@export_range(3,20,1) var forge_impact_streak_count_min:int = 7
@export_range(4,28,1) var forge_impact_streak_count_max:int = 14
@export_range(0.10,0.40,0.01) var forge_impact_effect_duration:float = 0.20
@export var forge_hammer_entry_position:Vector2 = Vector2(34.0,-38.0)
@export_range(-180.0,180.0,1.0) var forge_hammer_entry_rotation_degrees:float = -42.0
@export var forge_hammer_rest_position:Vector2 = Vector2(25.0,-29.0)
@export_range(-180.0,180.0,1.0) var forge_hammer_rest_rotation_degrees:float = -78.0
@export var forge_hammer_impact_position:Vector2 = Vector2(-12.0,92.5)
@export_range(-180.0,180.0,1.0) var forge_hammer_impact_rotation_degrees:float = 18.0
@export var forge_impact_effect_position:Vector2 = Vector2(8.0,31.0)
@export var forge_hammer_grip_uv:Vector2 = Vector2(0.50,0.82)
@export var forge_hammer_head_uv:Vector2 = Vector2(0.50,0.16)
@export var forge_hammer_contact_offset:Vector2 = Vector2(0.0,-5.0)

@export_category("铁匠村民 / 满级后成长")
@export_range(1,200,1) var post_max_damage_gain:int = 10
@export_range(1,500,1) var post_max_armor_gain:int = 10

var helmet_tier:int = TIER_NONE
var sword_tier:int = TIER_NONE
var forge_count:int = 0
var post_max_damage_bonus:int = 0
var post_max_armor_bonus:int = 0

var _forge_progress:float = 0.0
var _time_since_attack:float = 0.0
var _forge_flash_left:float = 0.0
var _attack_serial:int = 0
var _helmet_root:Node2D = null
var _helmet_back:Sprite2D = null
var _helmet_front:Sprite2D = null
var _sword_pivot:Node2D = null
var _sword_sprite:Sprite2D = null
var _sword_tween:Tween = null
var _sword_afterimage_step:int = -1
var _kill_spin_pending:bool = false
var _kill_spin_active:bool = false
var _kill_spin_direction:Vector2 = Vector2.RIGHT
var _kill_spin_serial:int = 0
var _last_kill_spin_serial:int = 0
var _sword_threat_direction:Vector2 = Vector2.RIGHT
var _sword_threat_pending:bool = false
var _sword_hit_active:bool = false
var _sword_hit_marker:int = 0
var _forge_visual_root:Node2D = null
var _forge_item_sprite:Sprite2D = null
var _forge_hammer_pivot:Node2D = null
var _forge_hammer_sprite:Sprite2D = null
var _forge_adjust_root:Node2D = null
var _forge_item_start_guide:Sprite2D = null
var _forge_item_hold_guide:Sprite2D = null
var _forge_hammer_entry_guide:Sprite2D = null
var _forge_hammer_rest_guide:Sprite2D = null
var _forge_hammer_impact_guide:Sprite2D = null
var _forge_impact_guide:Node2D = null
var _forge_tween:Tween = null
var _forge_strike_done:bool = false
var _forge_success_sfx_index:int = -1
var _forge_helmet_sfx_index:int = -1
var _rng := RandomNumberGenerator.new()
var _forge_fx_rng := RandomNumberGenerator.new()
var _base_damage:int = 0
var _base_max_block:int = 0
var _base_damage_reduction:float = 0.0
var _state_sync_left:float = 0.0
var _sword_visual_busy_left:float = 0.0
var _strong_attack_sfx:Array[AudioStream] = []
var _critical_attack_sfx:Array[AudioStream] = []
var _death_sequence_started:bool = false
var _death_visual_started_local:bool = false


func _ready() -> void:
	Has_Collision_Damage = false
	Can_Attack = false
	Can_Skill = false
	Health_Restore = 0
	Attack_Cooling = maxf(sword_attack_cooldown,0.05)
	if image is Sprite2D:
		var sprite := image as Sprite2D
		sprite.texture = BLACKSMITH_TEXTURE
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.offset = Vector2.ZERO

	super._ready()
	_base_damage = Damage
	_base_max_block = max_block
	_base_damage_reduction = Damage_reduction
	_rng.seed = Game.battle_rng_seed_or(
		"scripts/characters/我的世界/铁匠村民.gd:_rng.seed",
		maxi(abs(int(Time.get_ticks_usec()) ^ int(get_instance_id())),1)
	)
	# 锻造白线只影响本地视觉，使用独立 RNG，避免消耗角色 gameplay RNG 改变锻造升级等逻辑。
	_forge_fx_rng.randomize()
	_resolve_minecraft_attack_sfx()
	_cache_equipment_visual_nodes()
	_cache_forge_visual_adjustment_nodes()
	_apply_forge_visual_adjustments_from_scene()
	_ensure_forge_visual_nodes()
	_apply_equipment_stats(false)
	_update_equipment_visuals()
	queue_redraw()


func get_preview_texture() -> Texture2D:
	return BLACKSMITH_TEXTURE


func tick_physics(state:State,delta:float) -> void:
	super.tick_physics(state,delta)
	_update_sword_idle_pose()
	_update_local_visual_clock(delta)

	if not is_multiplayer_authority():
		return
	if health <= 0 or state_machine == null or state_machine.current_state == State.Die:
		return
	if not is_combat_runtime_active():
		return

	# V81：加速依据改为“距离上一次真正开始攻击的时间”。
	# 受到伤害不会重置；dizziness 期间无法继续攻击，因此眩晕会自然让该计时持续累积。
	if dizziness and Attacking:
		_interrupt_sword_attack(true)
	_time_since_attack += maxf(delta,0.0)
	_advance_forging(delta)
	_sync_runtime_state_periodically(delta)


func _advance_forging(delta:float) -> void:
	var base_interval:float = maxf(forge_base_interval,0.05)
	var minimum_interval:float = clampf(forge_min_interval,0.05,base_interval)
	var max_rate_multiplier:float = base_interval / minimum_interval
	var rate_multiplier:float = clampf(
		1.0 + maxf(_time_since_attack,0.0) * maxf(forge_acceleration_per_second,0.0),
		1.0,
		max_rate_multiplier
	)
	_forge_progress += maxf(delta,0.0) * rate_multiplier / base_interval
	while _forge_progress >= 1.0:
		_forge_progress -= 1.0
		_perform_forge()
	queue_redraw()


func _perform_forge() -> void:
	var forge_success:bool = false
	var actual_upgrade_kind:StringName = &""
	var forge_kind:StringName = _choose_forge_visual_kind()
	var forge_tier:int = _forge_preview_tier(forge_kind)

	if _all_equipment_maxed():
		# 满装后只是永久属性成长：明确不播放本轮新增的“头盔装备/升级”音效。
		var bonus_kind:StringName = _grant_post_max_bonus()
		forge_success = true
		forge_tier = TIER_NETHERITE
		if bonus_kind == &"damage":
			forge_kind = &"sword"
			_broadcast_growth_text(&"damage",maxi(post_max_damage_gain,1))
		else:
			forge_kind = &"helmet"
			_broadcast_growth_text(&"block",maxi(post_max_armor_gain,1))
	else:
		forge_count += 1
		if forge_count >= maxi(forge_count_for_equipment,1):
			forge_count = 0
			actual_upgrade_kind = _upgrade_random_equipment()
			forge_success = actual_upgrade_kind != &""
			if forge_success:
				forge_kind = actual_upgrade_kind
				forge_tier = helmet_tier if forge_kind == &"helmet" else sword_tier
		else:
			forge_kind = _choose_forge_visual_kind()
			forge_tier = _forge_preview_tier(forge_kind)

	var success_sfx_index:int = -1
	var helmet_sfx_index:int = -1
	if forge_success:
		if actual_upgrade_kind == &"helmet" and not HELMET_UPGRADE_SFX.is_empty():
			# 用户提供的 5 个短金属音只用于“获得/升级头盔”三次真实装备升级。
			# 满装后的 +属性 不会进入这里；头盔升级也不再叠播通用成功音，避免声音糊在一起。
			helmet_sfx_index = _rng.randi_range(0,HELMET_UPGRADE_SFX.size() - 1)
		elif not SMITHING_SUCCESS_SFX.is_empty():
			success_sfx_index = _rng.randi_range(0,SMITHING_SUCCESS_SFX.size() - 1)

	# 每一次锻造都先把正在加工的装备送到身前，再由 Minecraft 重锤落下。
	# 单次锻造音效与升级成功音效都在锤头接触的同一帧播放。
	_broadcast_forge_animation(forge_kind,forge_tier,success_sfx_index,helmet_sfx_index)

	_update_equipment_visuals()
	queue_redraw()
	_broadcast_runtime_state()


func _choose_forge_visual_kind() -> StringName:
	if helmet_tier >= TIER_NETHERITE and sword_tier < TIER_NETHERITE:
		return &"sword"
	if sword_tier >= TIER_NETHERITE and helmet_tier < TIER_NETHERITE:
		return &"helmet"
	# 非升级的第 1/2 锤只做展示，不额外消耗 RNG，避免改变真正第 3 锤的随机结果。
	return &"helmet" if ((forge_count + helmet_tier + sword_tier) % 2 == 0) else &"sword"


func _forge_preview_tier(kind:StringName) -> int:
	if kind == &"helmet":
		return clampi(helmet_tier + 1,TIER_IRON,TIER_NETHERITE)
	return clampi(sword_tier + 1,TIER_IRON,TIER_NETHERITE)


func _upgrade_random_equipment() -> StringName:
	var choices:Array[StringName] = []
	if helmet_tier < TIER_NETHERITE:
		choices.append(&"helmet")
	if sword_tier < TIER_NETHERITE:
		choices.append(&"sword")
	if choices.is_empty():
		return &""
	var choice:StringName = choices[_rng.randi_range(0,choices.size() - 1)]
	if choice == &"helmet":
		_helmet_upgrade_one_tier()
	else:
		_sword_upgrade_one_tier()
	return choice


func _helmet_upgrade_one_tier() -> void:
	var old_max_block:int = max_block
	helmet_tier = mini(helmet_tier + 1,TIER_NETHERITE)
	_apply_equipment_stats(false)
	var gained_armor:int = maxi(max_block - old_max_block,0)
	if gained_armor > 0:
		block = mini(int(block) + gained_armor,max_block)


func _sword_upgrade_one_tier() -> void:
	sword_tier = mini(sword_tier + 1,TIER_NETHERITE)
	_apply_equipment_stats(false)


func _grant_post_max_bonus() -> StringName:
	if _rng.randi_range(0,1) == 0:
		post_max_damage_bonus += maxi(post_max_damage_gain,1)
		_apply_equipment_stats(false)
		return &"damage"

	var old_max_block:int = max_block
	post_max_armor_bonus += maxi(post_max_armor_gain,1)
	_apply_equipment_stats(false)
	var gained_armor:int = maxi(max_block - old_max_block,0)
	if gained_armor > 0:
		block = mini(int(block) + gained_armor,max_block)
	return &"block"


func _all_equipment_maxed() -> bool:
	return helmet_tier >= TIER_NETHERITE and sword_tier >= TIER_NETHERITE


func _helmet_armor_value() -> int:
	match helmet_tier:
		TIER_IRON:
			return maxi(iron_helmet_armor,0)
		TIER_DIAMOND:
			return maxi(diamond_helmet_armor,0)
		TIER_NETHERITE:
			return maxi(netherite_helmet_armor,0)
	return 0


func _helmet_damage_reduction_value() -> float:
	match helmet_tier:
		TIER_IRON:
			return maxf(iron_helmet_damage_reduction,0.0)
		TIER_DIAMOND:
			return maxf(diamond_helmet_damage_reduction,0.0)
		TIER_NETHERITE:
			return maxf(netherite_helmet_damage_reduction,0.0)
	return 0.0


func _sword_damage_value() -> int:
	match sword_tier:
		TIER_IRON:
			return maxi(iron_sword_damage,0)
		TIER_DIAMOND:
			return maxi(diamond_sword_damage,0)
		TIER_NETHERITE:
			return maxi(netherite_sword_damage,0)
	return 0


func _apply_equipment_stats(refill_all_armor:bool) -> void:
	var previous_max_block:int = max_block
	Damage = _sword_damage_value() + maxi(post_max_damage_bonus,0)
	max_block = _base_max_block + _helmet_armor_value() + maxi(post_max_armor_bonus,0)
	Damage_reduction = clampf(_base_damage_reduction + _helmet_damage_reduction_value(),0.0,0.90)
	Attack_Cooling = maxf(sword_attack_cooldown,0.05)
	Can_Attack = sword_tier > TIER_NONE

	if default_properties != null:
		default_properties["Damage"] = Damage
		default_properties["max_block"] = max_block
		default_properties["Damage_reduction"] = Damage_reduction
		default_properties["Attack_Cooling"] = Attack_Cooling

	if refill_all_armor:
		block = max_block
	elif max_block < previous_max_block:
		block = mini(int(block),max_block)


func Attack() -> void:
	if sword_tier <= TIER_NONE:
		Attacking = false
		return
	if state_machine == null or state_machine.current_state == State.Die or not is_multiplayer_authority():
		return
	super()
	if is_damage_output_disabled() or not is_combat_runtime_active():
		Attacking = false
		return

	var attack_dir:Vector2 = Vector2.ZERO
	if has_player_control_aim():
		attack_dir = player_control_aim_direction(_movement_facing_direction())
	else:
		var target:ball = _nearest_enemy_360(maxf(sword_attack_range,1.0))
		if target == null or not is_instance_valid(target):
			Attacking = false
			return
		attack_dir = combat_target_position(target) - global_position

	if attack_dir.length_squared() <= 0.000001:
		Attacking = false
		return
	attack_dir = attack_dir.normalized()
	# 只有真正找到目标/方向并开始挥剑，才算一次“攻击”并重置锻造加速。
	_time_since_attack = 0.0
	Attacking = true
	_attack_serial += 1
	var ticket:int = _attack_serial
	var current_outgoing_damage:float = attack_damage(1.0)
	var high_damage_swing:bool = current_outgoing_damage > 200.0
	var swing_speed:float = maxf(high_damage_swing_speed_multiplier,1.0) if high_damage_swing else 1.0
	var effective_hit_delay:float = maxf(sword_hit_delay / swing_speed,0.01)
	var effective_swing_duration:float = maxf(sword_swing_duration / swing_speed,0.10)

	# 起手音效按实际攻击输出伤害选取，命中后普通/暴击反馈仍各自独立。
	_broadcast_attack_sfx(current_outgoing_damage)
	_broadcast_sword_swing(attack_dir,high_damage_swing)

	await get_tree().create_timer(effective_hit_delay,false).timeout
	if not _attack_ticket_valid(ticket):
		if ticket == _attack_serial:
			Attacking = false
		return
	_deal_sword_damage(attack_dir)

	var tail_time:float = maxf(effective_swing_duration - effective_hit_delay,0.03)
	await get_tree().create_timer(tail_time,false).timeout
	if ticket == _attack_serial and is_instance_valid(self):
		Attacking = false
		_update_sword_idle_pose(true)


func _nearest_enemy_360(max_range:float) -> ball:
	var best:ball = null
	var best_distance_sq:float = INF
	var max_distance_sq:float = maxf(max_range,1.0) * maxf(max_range,1.0)
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var candidate:ball = node as ball
		if not _is_enemy_target(candidate):
			continue
		var distance_sq:float = global_position.distance_squared_to(combat_target_position(candidate))
		if distance_sq > max_distance_sq or distance_sq >= best_distance_sq:
			continue
		best_distance_sq = distance_sq
		best = candidate
	return best


func _is_enemy_target(target:ball) -> bool:
	if target == null or not is_instance_valid(target) or target == self:
		return false
	if target.Type != Ball_Type.Ball or target.health <= 0 or not target.is_combat_targetable():
		return false
	if target.state_machine != null and target.state_machine.current_state == State.Die:
		return false
	if not Game.Game_Settings.Have_Team_Damage and not Team.is_empty() and not target.Team.is_empty() and Team == target.Team:
		return false
	return true


func _deal_sword_damage(attack_dir:Vector2) -> void:
	if not is_multiplayer_authority() or get_world_2d() == null:
		return
	var shape := CircleShape2D.new()
	shape.radius = maxf(sword_attack_range,1.0)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0,global_position)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = 2
	var results:Array[Dictionary] = get_world_2d().direct_space_state.intersect_shape(query,64)
	var seen:Dictionary = {}
	var half_angle:float = deg_to_rad(clampf(sword_half_angle_degrees,5.0,175.0))
	var outgoing:float = attack_damage(1.0)
	var killed_enemy:bool = false
	if outgoing <= 0.0:
		return
	_rpc_mark_sword_hit(attack_dir)
	if multiplayer.has_multiplayer_peer(): _rpc_mark_sword_hit.rpc(attack_dir)

	for result:Dictionary in results:
		var collider:Variant = result.get("collider",null)
		if not collider is hurtbox:
			continue
		var target:ball = (collider as hurtbox).get_parent() as ball
		if not _is_enemy_target(target):
			continue
		var target_id:int = target.get_instance_id()
		if seen.has(target_id):
			continue
		# Aiming may substitute the mouse point; hit geometry must use each
		# victim's real position, otherwise manual control hits the entire circle.
		var offset:Vector2 = ball.body_point(target,global_position) - global_position
		if offset.length_squared() > 0.000001:
			var direction_to_target:Vector2 = offset.normalized()
			if absf(attack_dir.angle_to(direction_to_target)) > half_angle:
				continue
		seen[target_id] = true
		var health_before:float = float(target.health)
		var enemy_team:bool = Team.is_empty() or target.Team.is_empty() or Team != target.Team
		set_meta("blood_damage_kind","slash")
		var accepted:bool = target.receive_positional_damage(
			outgoing,
			global_position + attack_dir * minf(maxf(sword_attack_range,1.0) * 0.65,42.0),
			false,
			self
		)
		if not accepted or not is_instance_valid(target):
			continue
		var dealt_damage:float = target.get_received_hit_feedback_damage(outgoing,health_before)
		if dealt_damage <= 0.0:
			continue
		if enemy_team and health_before > 0.0 and target.health <= 0:
			killed_enemy = true
		if preload("res://scripts/effects/我的世界/mc_hit_feedback.gd").manages(self): continue # Victim already selected feedback.
		if _is_critical_sword_hit(dealt_damage):
			# 命中反馈严格 >50；与 >100 的挥舞音效判定无关。
			_broadcast_critical_hit_sfx(ball.body_point(target,global_position),dealt_damage)
		else:
			_broadcast_mc_damage_sfx(ball.body_point(target,global_position),dealt_damage)
	# A multi-kill in one sweep celebrates once, after the damaging swing finishes.
	if killed_enemy:
		_broadcast_kill_spin(attack_dir)


func _is_critical_sword_hit(dealt_damage:float) -> bool:
	return is_finite(dealt_damage) and dealt_damage > 50.0


func _sword_threat_available() -> bool:
	return health > 0 and not _death_sequence_started and sword_tier > TIER_NONE and not dizziness and not is_damage_output_disabled() and is_combat_runtime_active()


func _sword_threat_sector() -> Dictionary:
	# Same world-space circle and center-angle gate as _deal_sword_damage.
	# Radius intersects the victim hurtbox; it is not the sword sprite's bounds.
	var radius:float = maxf(sword_attack_range,1.0)
	var half:float = deg_to_rad(clampf(sword_half_angle_degrees,5.0,175.0))
	var heading:float = _sword_threat_direction.angle()
	var points:=PackedVector2Array([global_position])
	for i:int in range(65):
		points.append(global_position + Vector2.RIGHT.rotated(heading-half+2.0*half*float(i)/64.0)*radius)
	return {"shape":"polygon","position":global_position,"points":points,"radius":radius,
		"direction":_sword_threat_direction,"half_angle":half,"damage":attack_damage(1.0),"source":self,"kind":"blacksmith_sword"}


func get_debug_attack_regions() -> Array[Dictionary]:
	if not _sword_hit_active or not _sword_threat_available() or attack_damage(1.0) <= 0.0: return []
	return [_sword_threat_sector()]


func get_debug_detection_regions() -> Array[Dictionary]:
	if not _sword_threat_available(): return []
	# Idle targeting is genuinely 360 degrees; a committed windup locks its sector.
	if _sword_threat_pending:
		var sector:Dictionary = _sword_threat_sector()
		sector["kind"] = "blacksmith_sword_windup"
		return [sector]
	# The acquisition circle is idle-only, not a simultaneous damage area.
	if _sword_hit_active or Attacking or _sword_visual_busy_left > 0.0 or _kill_spin_active:
		return []
	return [{"shape":"circle","position":global_position,"radius":maxf(sword_attack_range,1.0),"kind":"blacksmith_sword_detection"}]


func _refresh_sword_threat_display() -> void:
	if not bool(Game.Game_Settings.get("Training_Debug_Mode",false)) or get_tree().current_scene == null: return
	var analyzer:Node = get_tree().current_scene.get_node_or_null("CombatThreatAnalyzer")
	if analyzer != null and analyzer.has_method("_refresh_debug_world"):
		analyzer._refresh_debug_world()
		analyzer.queue_redraw()


@rpc("authority","call_remote","reliable")
func _rpc_mark_sword_hit(attack_dir:Vector2) -> void:
	_sword_threat_direction = attack_dir.normalized()
	_sword_threat_pending = false
	_sword_hit_active = true
	_sword_hit_marker += 1
	var marker:int = _sword_hit_marker
	_refresh_sword_threat_display() # The instant strike must not miss a 40ms scan.
	await get_tree().physics_frame
	if marker == _sword_hit_marker:
		_sword_hit_active = false
		_refresh_sword_threat_display()


func _movement_facing_direction() -> Vector2:
	var source:Vector2 = Vector2.ZERO
	if is_player_controlled() and player_control_direction.length_squared() > 0.000001:
		source = player_control_direction
	elif direction.length_squared() > 0.000001:
		source = direction
	if source.length_squared() > 0.000001:
		return source.normalized()
	return Vector2.LEFT if is_character_visual_flipped_h() else Vector2.RIGHT


func _attack_ticket_valid(ticket:int) -> bool:
	return (
		ticket == _attack_serial
		and is_instance_valid(self)
		and is_inside_tree()
		and health > 0
		and sword_tier > TIER_NONE
		and state_machine != null
		and state_machine.current_state != State.Die
		and is_combat_runtime_active()
		and not dizziness
	)


func _cache_equipment_visual_nodes() -> void:
	_helmet_root = get_node_or_null("Graphics/头盔_整体调整") as Node2D
	_helmet_back = get_node_or_null("Graphics/头盔_整体调整/头盔后") as Sprite2D
	_helmet_front = get_node_or_null("Graphics/头盔_整体调整/头盔前") as Sprite2D
	_sword_pivot = get_node_or_null("Graphics/剑_攻击枢轴") as Node2D
	_sword_sprite = get_node_or_null("Graphics/剑_攻击枢轴/剑_攻击显示") as Sprite2D
	if _sword_pivot != null:
		_sword_pivot.visible = false
	if _sword_sprite != null:
		_sword_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_sword_sprite.visible = false


func _helmet_back_texture_for_tier(tier:int) -> Texture2D:
	match tier:
		TIER_IRON:
			return IRON_HELMET_BACK
		TIER_DIAMOND:
			return DIAMOND_HELMET_BACK
		TIER_NETHERITE:
			return NETHERITE_HELMET_BACK
	return null


func _helmet_front_texture_for_tier(tier:int) -> Texture2D:
	match tier:
		TIER_IRON:
			return IRON_HELMET_FRONT
		TIER_DIAMOND:
			return DIAMOND_HELMET_FRONT
		TIER_NETHERITE:
			return NETHERITE_HELMET_FRONT
	return null


func _sword_texture_for_tier(tier:int) -> Texture2D:
	match tier:
		TIER_IRON:
			return IRON_SWORD_TEXTURE
		TIER_DIAMOND:
			return DIAMOND_SWORD_TEXTURE
		TIER_NETHERITE:
			return NETHERITE_SWORD_TEXTURE
	return null



func _apply_sword_grip_offset() -> void:
	if _sword_sprite == null or not is_instance_valid(_sword_sprite) or _sword_sprite.texture == null:
		return
	var texture_size:Vector2 = _sword_sprite.texture.get_size()
	var grip_uv:Vector2 = Vector2(clampf(sword_grip_uv.x,0.0,1.0),clampf(sword_grip_uv.y,0.0,1.0))
	# Sprite2D centered=true 时，offset = 半尺寸 - 握把像素位置，可把握把固定到节点原点。
	_sword_sprite.offset = texture_size * (Vector2(0.5,0.5) - grip_uv)


func _update_equipment_visuals() -> void:
	if image is Sprite2D:
		var sprite := image as Sprite2D
		sprite.texture = BLACKSMITH_TEXTURE
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	if _helmet_root == null or _helmet_back == null or _helmet_front == null or _sword_sprite == null:
		_cache_equipment_visual_nodes()

	var helmet_visible:bool = helmet_tier > TIER_NONE
	if _helmet_root != null:
		_helmet_root.visible = helmet_visible
	if helmet_visible:
		if _helmet_back != null:
			_helmet_back.texture = _helmet_back_texture_for_tier(helmet_tier)
		if _helmet_front != null:
			_helmet_front.texture = _helmet_front_texture_for_tier(helmet_tier)

	if _sword_sprite != null:
		_sword_sprite.texture = _sword_texture_for_tier(sword_tier)
		_sword_sprite.scale = Vector2.ONE * maxf(sword_visual_scale,0.001)
		_apply_sword_grip_offset()
		# 剑只在真正挥剑动画期间显示；获得剑只是解锁攻击，不会常驻手持。
		if not Attacking and _sword_visual_busy_left <= 0.0 and not _kill_spin_active:
			_sword_sprite.visible = false


func _update_sword_idle_pose(force:bool = false) -> void:
	if _kill_spin_active:
		return # The attack timer must not hide a celebration that has just started.
	# V81：剑只在攻击段显示，并围绕贴图握把位置的独立枢轴旋转。
	if _sword_sprite == null or not is_instance_valid(_sword_sprite):
		return
	if (Attacking or _sword_visual_busy_left > 0.0) and not force:
		return
	_sword_sprite.visible = false
	if _sword_pivot != null and is_instance_valid(_sword_pivot):
		_sword_pivot.visible = false
		_sword_pivot.scale = Vector2.ONE


func _broadcast_sword_swing(attack_dir:Vector2,high_damage_swing:bool) -> void:
	_play_sword_swing_local(attack_dir,high_damage_swing)
	if multiplayer.has_multiplayer_peer():
		_rpc_play_sword_swing.rpc(attack_dir,high_damage_swing)


@rpc("authority","call_remote","reliable")
func _rpc_play_sword_swing(attack_dir:Vector2,high_damage_swing:bool) -> void:
	_play_sword_swing_local(attack_dir,high_damage_swing)


func _interrupt_sword_attack(sync_remote:bool = false) -> void:
	_sword_threat_pending = false
	_sword_hit_active = false
	_refresh_sword_threat_display()
	_kill_spin_pending = false
	_kill_spin_active = false
	_attack_serial += 1
	Attacking = false
	_sword_visual_busy_left = 0.0
	if _sword_tween != null and _sword_tween.is_valid():
		_sword_tween.kill()
	_update_sword_idle_pose(true)
	if sync_remote and multiplayer.has_multiplayer_peer():
		_rpc_interrupt_sword_attack.rpc()


@rpc("authority","call_remote","reliable")
func _rpc_interrupt_sword_attack() -> void:
	_sword_threat_pending = false
	_sword_hit_active = false
	_refresh_sword_threat_display()
	_kill_spin_pending = false
	_kill_spin_active = false
	_sword_visual_busy_left = 0.0
	if _sword_tween != null and _sword_tween.is_valid():
		_sword_tween.kill()
	_update_sword_idle_pose(true)


func _play_sword_swing_local(attack_dir:Vector2,high_damage_swing:bool) -> void:
	# A real new attack takes priority over cosmetic celebration, never delays combat.
	_kill_spin_pending = false
	_kill_spin_active = false
	if _sword_pivot == null or not is_instance_valid(_sword_pivot) or _sword_sprite == null or not is_instance_valid(_sword_sprite) or sword_tier <= TIER_NONE:
		return
	_sword_sprite.texture = _sword_texture_for_tier(sword_tier)
	_sword_sprite.scale = Vector2.ONE * maxf(sword_visual_scale,0.001)
	# 暗色下界合金剑在角色自身 0.2 倍缩放后容易埋进背景；只在挥剑时略提亮原贴图。
	_sword_sprite.self_modulate = Color(1.35,1.45,1.65) if sword_tier == TIER_NETHERITE else Color.WHITE
	_apply_sword_grip_offset()
	var swing_speed:float = maxf(high_damage_swing_speed_multiplier,1.0) if high_damage_swing else 1.0
	var duration:float = maxf(sword_swing_duration / swing_speed,0.10)
	_sword_visual_busy_left = duration + 0.04
	_sword_afterimage_step = -1
	if _sword_tween != null and _sword_tween.is_valid():
		_sword_tween.kill()

	var direction_value:Vector2 = attack_dir.normalized() if attack_dir.length_squared() > 0.000001 else Vector2.RIGHT
	_sword_threat_direction = direction_value
	_sword_threat_pending = true
	_sword_hit_active = false
	_refresh_sword_threat_display()
	var attack_angle:float = direction_value.angle()
	# Iron_Sword.png 的握把约在贴图 (20.6%, 76.8%)，_apply_sword_grip_offset() 会按当前剑贴图尺寸换算。
	# 剑刃原图约朝 -49°，因此 +49° 后“中立朝向”与 attack_dir 对齐。
	var neutral_angle:float = attack_angle + deg_to_rad(49.0)
	var local_distance:float = maxf(sword_visual_distance,0.0)
	var base_position:Vector2 = direction_value * local_distance + Vector2(0.0,sword_visual_vertical_offset)
	var windup_time:float = duration * 0.18
	var slash_time:float = duration * 0.56
	var follow_time:float = maxf(duration - windup_time - slash_time,0.02)

	_sword_pivot.visible = true
	_sword_sprite.visible = true
	_sword_sprite.position = Vector2.ZERO
	_sword_sprite.rotation = 0.0
	_sword_sprite.flip_h = false
	_sword_sprite.flip_v = false
	_sword_pivot.position = base_position - direction_value * 3.0
	_sword_pivot.rotation = neutral_angle - deg_to_rad(92.0)
	_sword_pivot.scale = Vector2.ONE * 0.95

	# 短蓄力 -> 可辨认的连续主斩 -> 收势。两端减速，避免原缓出曲线在主斩第一帧突跳。
	# >200 伤害时仍按原规则轻微提速，命中延迟和视觉动作按同一倍率缩放。
	_sword_tween = create_tween()
	_sword_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sword_tween.tween_property(_sword_pivot,"rotation",neutral_angle - deg_to_rad(116.0),windup_time)
	_sword_tween.parallel().tween_property(_sword_pivot,"position",base_position - direction_value * 8.0,windup_time)
	_sword_tween.parallel().tween_property(_sword_pivot,"scale",Vector2.ONE * 0.90,windup_time)

	_sword_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sword_tween.tween_method(
		Callable(self,"_apply_sword_slash_progress").bind(neutral_angle,base_position,direction_value),
		0.0,
		1.0,
		slash_time
	)

	_sword_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Transform2D decomposes angles into [-PI, PI]. Never tween that wrapped
	# rotation back to an unwrapped target: across the seam it adds a full turn.
	_sword_tween.tween_method(Callable(self,"_apply_sword_follow_progress").bind(neutral_angle,base_position,direction_value),0.0,1.0,follow_time)
	_sword_tween.finished.connect(_finish_sword_swing_local,CONNECT_ONE_SHOT)


func _apply_sword_follow_progress(progress:float,neutral_angle:float,base_position:Vector2,direction_value:Vector2) -> void:
	if not is_instance_valid(_sword_pivot): return
	var p:float = clampf(progress,0.0,1.0)
	var angle:float = neutral_angle + deg_to_rad(lerpf(46.0,76.0,p))
	var position_value:Vector2 = base_position + direction_value * lerpf(13.0,5.0,p)
	_sword_pivot.transform = Transform2D(angle,Vector2.ONE * lerpf(1.09,1.0,p),0.0,position_value)


func _finish_sword_swing_local() -> void:
	_sword_threat_pending = false
	_refresh_sword_threat_display()
	_sword_visual_busy_left = 0.0
	if _kill_spin_pending:
		_start_kill_spin_local()
	else:
		_update_sword_idle_pose(true)


func _broadcast_kill_spin(attack_dir:Vector2) -> void:
	if not is_multiplayer_authority(): return
	_kill_spin_serial += 1
	_rpc_queue_kill_spin(_kill_spin_serial,attack_dir)
	if multiplayer.has_multiplayer_peer():
		_rpc_queue_kill_spin.rpc(_kill_spin_serial,attack_dir)


@rpc("authority","call_remote","reliable")
func _rpc_queue_kill_spin(serial:int,attack_dir:Vector2) -> void:
	if serial <= _last_kill_spin_serial: return
	_last_kill_spin_serial = serial
	if health <= 0 or dizziness or _death_sequence_started or sword_tier <= TIER_NONE: return
	_kill_spin_direction = attack_dir.normalized() if attack_dir.length_squared() > 0.000001 else Vector2.RIGHT
	_kill_spin_pending = true
	if _sword_tween == null or not _sword_tween.is_running():
		_start_kill_spin_local()


func _start_kill_spin_local() -> void:
	_kill_spin_pending = false
	if health <= 0 or dizziness or _death_sequence_started or sword_tier <= TIER_NONE: return
	if not is_instance_valid(_sword_pivot) or not is_instance_valid(_sword_sprite): return
	_kill_spin_active = true
	_sword_visual_busy_left = 0.0
	_sword_sprite.self_modulate.a = 1.0
	_sword_sprite.texture = _sword_texture_for_tier(sword_tier)
	_sword_sprite.scale = Vector2.ONE * maxf(sword_visual_scale,0.001)
	_apply_sword_grip_offset()
	_sword_sprite.position = Vector2.ZERO
	_sword_sprite.rotation = 0.0
	_sword_sprite.flip_h = false
	_sword_sprite.flip_v = false
	_sword_sprite.visible = true
	_sword_pivot.visible = true
	var start_angle:float = _kill_spin_direction.angle() + deg_to_rad(125.0)
	_apply_kill_spin_progress(0.0,start_angle)
	_sword_tween = create_tween()
	_sword_tween.tween_method(Callable(self,"_apply_kill_spin_progress").bind(start_angle),0.0,1.0,maxf(sword_kill_spin_duration,0.3)).set_trans(Tween.TRANS_LINEAR)
	_sword_tween.finished.connect(_finish_kill_spin_local,CONNECT_ONE_SHOT)


func _apply_kill_spin_progress(progress:float,start_angle:float) -> void:
	if health <= 0 or dizziness or _death_sequence_started or sword_tier <= TIER_NONE:
		_interrupt_sword_attack(false)
		return
	var angle:float = start_angle + TAU * float(clampi(sword_kill_spin_turns,1,5)) * clampf(progress,0.0,1.0)
	var grip:Vector2 = _kill_spin_direction * maxf(sword_visual_distance,0.0) + Vector2(0.0,sword_visual_vertical_offset)
	_sword_pivot.transform = Transform2D(angle,Vector2.ONE,0.0,grip)
	# Fade during the last 35% while the sword keeps spinning at full speed.
	_sword_sprite.self_modulate.a = 1.0-smoothstep(0.65,1.0,clampf(progress,0.0,1.0))


func _finish_kill_spin_local() -> void:
	_kill_spin_active = false
	_sword_visual_busy_left = 0.0
	_update_sword_idle_pose(true)


func _apply_sword_slash_progress(progress:float,neutral_angle:float,base_position:Vector2,direction_value:Vector2) -> void:
	if _sword_pivot == null or not is_instance_valid(_sword_pivot):
		return
	var p:float = clampf(progress,0.0,1.0)
	_sword_pivot.transform = _sword_slash_pose(p,neutral_angle,base_position,direction_value)

	var wanted_count:int = maxi(sword_afterimage_count,1)
	var step:int = mini(int(floor(clampf(p,0.0,0.9999) * float(wanted_count))),wanted_count - 1)
	while _sword_afterimage_step < step:
		_sword_afterimage_step += 1
		# 掉帧时按弧线的各个历史位置补采样，不能把多个残影堆在当前帧同一点。
		var sample:float = minf(p,float(_sword_afterimage_step) / float(maxi(wanted_count - 1,1)))
		var world_pose:Transform2D = _sword_pivot.get_parent().global_transform * _sword_slash_pose(sample,neutral_angle,base_position,direction_value) * _sword_sprite.transform
		_spawn_sword_afterimage(world_pose)


func _sword_slash_pose(progress:float,neutral_angle:float,base_position:Vector2,direction_value:Vector2) -> Transform2D:
	var p:float = clampf(progress,0.0,1.0)
	var angle:float = lerp_angle(neutral_angle - deg_to_rad(116.0),neutral_angle + deg_to_rad(46.0),p)
	var position:Vector2 = (base_position - direction_value * 8.0).lerp(base_position + direction_value * 13.0,p)
	var scale_factor:Vector2 = (Vector2.ONE * 0.90).lerp(Vector2.ONE * 1.09,p)
	return Transform2D(angle,scale_factor,0.0,position)


func _spawn_sword_afterimage(world_pose:Transform2D) -> void:
	if _sword_sprite == null or not is_instance_valid(_sword_sprite) or _sword_sprite.texture == null or not is_inside_tree():
		return
	var ghost := Sprite2D.new()
	ghost.name = "铁匠剑残影"
	ghost.texture = _sword_sprite.texture
	ghost.centered = _sword_sprite.centered
	ghost.offset = _sword_sprite.offset
	ghost.region_enabled = _sword_sprite.region_enabled
	ghost.region_rect = _sword_sprite.region_rect
	ghost.texture_filter = _sword_sprite.texture_filter
	ghost.flip_h = _sword_sprite.flip_h
	ghost.flip_v = _sword_sprite.flip_v
	ghost.z_as_relative = false
	ghost.z_index = 3
	ghost.self_modulate = Color(1.55,1.75,2.0,clampf(sword_afterimage_alpha,0.05,0.80))
	add_child(ghost)
	ghost.top_level = true
	ghost.global_transform = world_pose
	var fade := ghost.create_tween().bind_node(ghost)
	fade.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	fade.tween_property(ghost,"self_modulate:a",0.0,maxf(sword_afterimage_lifetime,0.05))
	fade.tween_callback(ghost.queue_free)


func _update_local_visual_clock(delta:float) -> void:
	var safe_delta:float = maxf(delta,0.0)
	if _sword_visual_busy_left > 0.0:
		_sword_visual_busy_left = maxf(_sword_visual_busy_left - safe_delta,0.0)
		if _sword_visual_busy_left <= 0.0 and _sword_sprite != null and is_instance_valid(_sword_sprite):
			_sword_sprite.visible = false
			if _sword_pivot != null and is_instance_valid(_sword_pivot):
				_sword_pivot.visible = false
	if _forge_flash_left > 0.0:
		_forge_flash_left = maxf(_forge_flash_left - safe_delta,0.0)
		queue_redraw()


func _draw() -> void:
	# 脚下锻造主进度条。阶段格永远是 3 个，中央格的几何中心严格对齐主进度条 X=0。
	var bar_rect := Rect2(-34.0,66.0,68.0,7.0)
	draw_rect(bar_rect,Color(0.03,0.03,0.035,0.90),true)
	var progress_width:float = 64.0 * clampf(_forge_progress,0.0,1.0)
	if progress_width > 0.0:
		# 主条也给一点柔和外辉光，跟下面阶段格的发光语言一致。
		draw_rect(Rect2(-32.5,67.5,progress_width + 1.0,4.0),Color(COLOR_FORGE.r,COLOR_FORGE.g,COLOR_FORGE.b,0.15),true)
	draw_rect(Rect2(-32.0,68.0,progress_width,3.0),COLOR_FORGE,true)

	# 装备全部锻造到下界合金后，三枚阶段格完全消失；之后只保留主条表示永久成长的下一锤。
	if not _all_equipment_maxed():
		var pip_count:int = 3
		var pip_size:float = 6.0
		var pip_step:float = 11.0
		var need:int = maxi(forge_count_for_equipment,1)
		var lit_count:int = 0
		if forge_count > 0:
			lit_count = clampi(int(ceil(float(forge_count) / float(need) * float(pip_count))),0,pip_count)
		for i:int in range(pip_count):
			var center_x:float = (float(i) - 1.0) * pip_step
			var rect := Rect2(center_x - pip_size * 0.5,76.0,pip_size,pip_size)
			var active:bool = i < lit_count
			if active:
				# 两层低 Alpha 外扩矩形形成像素风辉光，不依赖额外 Shader/纹理。
				draw_rect(rect.grow(4.0),Color(COLOR_FORGE.r,COLOR_FORGE.g,COLOR_FORGE.b,0.08),true)
				draw_rect(rect.grow(2.0),Color(COLOR_FORGE.r,COLOR_FORGE.g,COLOR_FORGE.b,0.20),true)
				draw_rect(rect,COLOR_FORGE,true)
				draw_rect(rect,Color(1.0,0.83,0.48,0.95),false,1.0)
			else:
				draw_rect(rect,Color(0.12,0.12,0.135,0.92),true)
				draw_rect(rect,Color(COLOR_FORGE.r,COLOR_FORGE.g,COLOR_FORGE.b,0.36),false,1.0)

	if _forge_flash_left > 0.0:
		var strength:float = clampf(_forge_flash_left / 0.32,0.0,1.0)
		var spark_color:Color = Color(1.0,0.55,0.10,strength)
		for offset:Vector2 in [Vector2(-26,-20),Vector2(28,-14),Vector2(-20,18),Vector2(23,24)]:
			draw_line(offset,offset + offset.normalized() * 9.0,spark_color,3.0)


func _resolve_minecraft_attack_sfx() -> void:
	# 重击用于 <=100 的挥舞；>100 直接复用项目已有七条原版横扫素材。
	# 暴击音只用于已确认承伤 >=100 的命中，找不到时沿用重击兜底。
	_strong_attack_sfx = _find_minecraft_audio_by_keywords([
		"strong_attack",
		"attack_strong",
		"strong attack",
		"重击",
	])
	if _strong_attack_sfx.is_empty():
		for stream:AudioStream in FALLBACK_STRONG_ATTACK_SFX:
			if stream != null:
				_strong_attack_sfx.append(stream)

	_critical_attack_sfx = _find_minecraft_audio_by_keywords([
		"critical_attack",
		"attack_critical",
		"critical attack",
		"crit",
		"暴击",
	])
	if _critical_attack_sfx.is_empty():
		for stream:AudioStream in _strong_attack_sfx:
			if stream != null:
				_critical_attack_sfx.append(stream)


func _find_minecraft_audio_by_keywords(keywords:Array[String]) -> Array[AudioStream]:
	var result:Array[AudioStream] = []
	_collect_matching_audio("res://audio/sfx/我的世界",keywords,result)
	return result


func _collect_matching_audio(root_path:String,keywords:Array[String],output:Array[AudioStream]) -> void:
	var dir:DirAccess = DirAccess.open(root_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry:String = dir.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child_path:String = root_path.path_join(entry)
			if dir.current_is_dir():
				_collect_matching_audio(child_path,keywords,output)
			else:
				var lower_path:String = child_path.to_lower()
				var extension:String = entry.get_extension().to_lower()
				if extension in ["ogg","wav","mp3"]:
					for keyword:String in keywords:
						if keyword.to_lower() in lower_path:
							var loaded:Resource = load(child_path)
							if loaded is AudioStream and not output.has(loaded):
								output.append(loaded as AudioStream)
							break
		entry = dir.get_next()
	dir.list_dir_end()


func _damage_audio_bonus_db(outgoing_damage:float) -> float:
	# 20 伤害作为铁剑听感基线。伤害每翻倍增加固定 dB，持续成长仍会越来越响，
	# 但通过 max bonus 限幅，避免满装后无限 +10 Damage 最终把音量推到失真。
	var safe_damage:float = maxf(outgoing_damage,20.0)
	var octaves:float = log(safe_damage / 20.0) / log(2.0)
	return clampf(octaves * maxf(sword_audio_db_per_damage_doubling,0.0),0.0,maxf(sword_audio_max_bonus_db,0.0))


func _broadcast_attack_sfx(outgoing_damage:float) -> void:
	_play_attack_sfx_local(outgoing_damage)
	if multiplayer.has_multiplayer_peer():
		_rpc_play_attack_sfx.rpc(outgoing_damage)


@rpc("authority","call_remote","unreliable")
func _rpc_play_attack_sfx(outgoing_damage:float) -> void:
	_play_attack_sfx_local(outgoing_damage)


func _play_attack_sfx_local(outgoing_damage:float) -> void:
	# 音效在出剑时按本次 attack_damage(1.0) 的结果选取，而非目标承伤或装备名称。
	# 恰好 100 仍是重击，严格大于 100 才是 Minecraft 原版横扫。
	var pool:Array[AudioStream] = SWEEP_ATTACK_SFX if is_finite(outgoing_damage) and outgoing_damage > 100.0 else _strong_attack_sfx
	if pool.is_empty():
		return
	var stream:AudioStream = pool.pick_random()
	var volume_db:float = sword_swing_base_volume_db + _damage_audio_bonus_db(outgoing_damage)
	_play_world_sfx(stream,global_position,volume_db,randf_range(0.98,1.02),1500.0)


func _broadcast_critical_hit_sfx(world_position:Vector2,outgoing_damage:float) -> void:
	if _critical_attack_sfx.is_empty():
		_broadcast_mc_damage_sfx(world_position,outgoing_damage)
		return
	var index:int = _rng.randi_range(0,_critical_attack_sfx.size() - 1)
	_play_critical_hit_sfx_local(index,world_position,outgoing_damage)
	if multiplayer.has_multiplayer_peer():
		_rpc_play_critical_hit_sfx.rpc(index,world_position,outgoing_damage)


@rpc("authority","call_remote","unreliable")
func _rpc_play_critical_hit_sfx(index:int,world_position:Vector2,outgoing_damage:float) -> void:
	_play_critical_hit_sfx_local(index,world_position,outgoing_damage)


func _play_critical_hit_sfx_local(index:int,world_position:Vector2,outgoing_damage:float) -> void:
	if index < 0 or index >= _critical_attack_sfx.size():
		return
	var volume_db:float = sword_critical_hit_base_volume_db + _damage_audio_bonus_db(outgoing_damage)
	_play_world_sfx(_critical_attack_sfx[index],world_position,volume_db,randf_range(0.98,1.02),1500.0)


func _broadcast_mc_damage_sfx(world_position:Vector2,outgoing_damage:float) -> void:
	if MC_DAMAGE_SFX.is_empty():
		return
	var index:int = _rng.randi_range(0,MC_DAMAGE_SFX.size() - 1)
	_play_mc_damage_sfx_local(index,world_position,outgoing_damage)
	if multiplayer.has_multiplayer_peer():
		_rpc_play_mc_damage_sfx.rpc(index,world_position,outgoing_damage)


@rpc("authority","call_remote","unreliable")
func _rpc_play_mc_damage_sfx(index:int,world_position:Vector2,outgoing_damage:float) -> void:
	_play_mc_damage_sfx_local(index,world_position,outgoing_damage)


func _play_mc_damage_sfx_local(index:int,world_position:Vector2,outgoing_damage:float) -> void:
	if index < 0 or index >= MC_DAMAGE_SFX.size():
		return
	var volume_db:float = sword_hit_base_volume_db + _damage_audio_bonus_db(outgoing_damage)
	_play_world_sfx(MC_DAMAGE_SFX[index],world_position,volume_db,randf_range(0.98,1.02),1450.0)


func _cache_forge_visual_adjustment_nodes() -> void:
	# V89：不用 @tool 跑整套角色 gameplay。直接在场景里放真实 Sprite2D/Marker2D 作为编辑器预览，
	# 这样用户可以在 2D 视图里拖拽/旋转/缩放；开局只读取 Transform，随后隐藏整个预览根节点。
	_forge_adjust_root = get_node_or_null("Graphics/锻造_可视调整") as Node2D
	if _forge_adjust_root == null:
		return
	_forge_item_start_guide = _forge_adjust_root.get_node_or_null("物品_入场") as Sprite2D
	_forge_item_hold_guide = _forge_adjust_root.get_node_or_null("物品_锻造位置") as Sprite2D
	_forge_hammer_entry_guide = _forge_adjust_root.get_node_or_null("锤子_入场") as Sprite2D
	_forge_hammer_rest_guide = _forge_adjust_root.get_node_or_null("锤子_抬起") as Sprite2D
	_forge_hammer_impact_guide = _forge_adjust_root.get_node_or_null("锤子_命中") as Sprite2D
	_forge_impact_guide = _forge_adjust_root.get_node_or_null("白圈和白线_命中点") as Node2D


func _guide_long_edge(sprite:Sprite2D,fallback:float) -> float:
	if sprite == null or not is_instance_valid(sprite) or sprite.texture == null:
		return fallback
	var texture_size:Vector2 = sprite.texture.get_size()
	var long_edge:float = maxf(texture_size.x,texture_size.y)
	if long_edge <= 0.0:
		return fallback
	return maxf(long_edge * absf(sprite.scale.x),1.0)


func _apply_forge_visual_adjustments_from_scene() -> void:
	if _forge_adjust_root == null or not is_instance_valid(_forge_adjust_root):
		return

	if _forge_item_start_guide != null and is_instance_valid(_forge_item_start_guide):
		forge_item_start_position = _forge_item_start_guide.position

	if _forge_item_hold_guide != null and is_instance_valid(_forge_item_hold_guide):
		forge_item_hold_position = _forge_item_hold_guide.position
		forge_item_visual_long_edge = _guide_long_edge(_forge_item_hold_guide,forge_item_visual_long_edge)
		if absf(_forge_item_hold_guide.scale.x) > 0.0001:
			forge_item_flatten_ratio = clampf(absf(_forge_item_hold_guide.scale.y / _forge_item_hold_guide.scale.x),0.10,1.20)
		forge_item_skew_degrees = rad_to_deg(_forge_item_hold_guide.skew)

	if _forge_hammer_entry_guide != null and is_instance_valid(_forge_hammer_entry_guide):
		forge_hammer_entry_position = _forge_hammer_entry_guide.position
		forge_hammer_entry_rotation_degrees = rad_to_deg(_forge_hammer_entry_guide.rotation)
		forge_hammer_visual_long_edge = _guide_long_edge(_forge_hammer_entry_guide,forge_hammer_visual_long_edge)

	if _forge_hammer_rest_guide != null and is_instance_valid(_forge_hammer_rest_guide):
		forge_hammer_rest_position = _forge_hammer_rest_guide.position
		forge_hammer_rest_rotation_degrees = rad_to_deg(_forge_hammer_rest_guide.rotation)

	if _forge_hammer_impact_guide != null and is_instance_valid(_forge_hammer_impact_guide):
		forge_hammer_impact_position = _forge_hammer_impact_guide.position
		forge_hammer_impact_rotation_degrees = rad_to_deg(_forge_hammer_impact_guide.rotation)

	if _forge_impact_guide != null and is_instance_valid(_forge_impact_guide):
		forge_impact_effect_position = _forge_impact_guide.position

	# 这些节点只负责编辑器对位。运行时真正动画仍由“锻造_动画”节点创建，避免预览图重复显示。
	_forge_adjust_root.visible = false


func _ensure_forge_visual_nodes() -> void:
	if _forge_visual_root != null and is_instance_valid(_forge_visual_root):
		return
	var graphics_node:Node2D = get_node_or_null("Graphics") as Node2D
	if graphics_node == null:
		return

	_forge_visual_root = Node2D.new()
	_forge_visual_root.name = "锻造_动画"
	_forge_visual_root.visible = false
	graphics_node.add_child(_forge_visual_root)

	_forge_item_sprite = Sprite2D.new()
	_forge_item_sprite.name = "正在锻造的装备"
	_forge_item_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_forge_item_sprite.z_as_relative = false
	_forge_item_sprite.z_index = 4
	_forge_visual_root.add_child(_forge_item_sprite)

	_forge_hammer_pivot = Node2D.new()
	_forge_hammer_pivot.name = "锻造重锤枢轴"
	_forge_hammer_pivot.z_as_relative = false
	_forge_hammer_pivot.z_index = 6
	_forge_visual_root.add_child(_forge_hammer_pivot)

	_forge_hammer_sprite = Sprite2D.new()
	_forge_hammer_sprite.name = "锻造重锤"
	_forge_hammer_sprite.texture = HAMMER_TEXTURE
	_forge_hammer_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_forge_hammer_pivot.add_child(_forge_hammer_sprite)
	_apply_forge_hammer_grip_offset()


func _apply_forge_hammer_grip_offset() -> void:
	if _forge_hammer_sprite == null or not is_instance_valid(_forge_hammer_sprite) or _forge_hammer_sprite.texture == null:
		return
	var texture_size:Vector2 = _forge_hammer_sprite.texture.get_size()
	var grip_uv:Vector2 = Vector2(clampf(forge_hammer_grip_uv.x,0.0,1.0),clampf(forge_hammer_grip_uv.y,0.0,1.0))
	_forge_hammer_sprite.offset = texture_size * (Vector2(0.5,0.5) - grip_uv)


func _fit_forge_sprite_long_edge(sprite:Sprite2D,target_long_edge:float) -> void:
	if sprite == null or not is_instance_valid(sprite) or sprite.texture == null:
		return
	var texture_size:Vector2 = sprite.texture.get_size()
	var long_edge:float = maxf(texture_size.x,texture_size.y)
	if long_edge <= 0.0:
		return
	sprite.scale = Vector2.ONE * (maxf(target_long_edge,1.0) / long_edge)


func _forge_hammer_impact_pivot(contact_point:Vector2,impact_rotation:float) -> Vector2:
	# V85：不是再凭肉眼给“锤子节点”一个近似终点，而是按贴图上的握把点与锤头接触点计算。
	# 这样在 impact_rotation 这一帧，forge_hammer_head_uv 指向的真实锤头像素会精确落到 contact_point。
	if _forge_hammer_sprite == null or not is_instance_valid(_forge_hammer_sprite) or _forge_hammer_sprite.texture == null:
		return contact_point
	var texture_size:Vector2 = _forge_hammer_sprite.texture.get_size()
	var grip_uv:Vector2 = Vector2(clampf(forge_hammer_grip_uv.x,0.0,1.0),clampf(forge_hammer_grip_uv.y,0.0,1.0))
	var head_uv:Vector2 = Vector2(clampf(forge_hammer_head_uv.x,0.0,1.0),clampf(forge_hammer_head_uv.y,0.0,1.0))
	var head_from_grip:Vector2 = Vector2(
		(head_uv.x - grip_uv.x) * texture_size.x,
		(head_uv.y - grip_uv.y) * texture_size.y
	)
	head_from_grip *= _forge_hammer_sprite.scale
	return contact_point - head_from_grip.rotated(impact_rotation)


func _forge_visual_texture(kind:StringName,tier:int) -> Texture2D:
	if kind == &"helmet":
		return _helmet_back_texture_for_tier(clampi(tier,TIER_IRON,TIER_NETHERITE))
	return _sword_texture_for_tier(clampi(tier,TIER_IRON,TIER_NETHERITE))


func _broadcast_forge_animation(kind:StringName,tier:int,success_sfx_index:int,helmet_sfx_index:int) -> void:
	_play_forge_animation_local(kind,tier,success_sfx_index,helmet_sfx_index)
	if multiplayer.has_multiplayer_peer():
		_rpc_play_forge_animation.rpc(kind,tier,success_sfx_index,helmet_sfx_index)


@rpc("authority","call_remote","reliable")
func _rpc_play_forge_animation(kind:StringName,tier:int,success_sfx_index:int,helmet_sfx_index:int) -> void:
	_play_forge_animation_local(kind,tier,success_sfx_index,helmet_sfx_index)


func _play_forge_animation_local(kind:StringName,tier:int,success_sfx_index:int,helmet_sfx_index:int) -> void:
	_ensure_forge_visual_nodes()
	if _forge_visual_root == null or _forge_item_sprite == null or _forge_hammer_pivot == null or _forge_hammer_sprite == null:
		return
	if _forge_tween != null and _forge_tween.is_valid():
		_forge_tween.kill()

	var work_texture:Texture2D = _forge_visual_texture(kind,tier)
	if work_texture == null:
		return
	_forge_item_sprite.texture = work_texture
	_fit_forge_sprite_long_edge(_forge_item_sprite,forge_item_visual_long_edge)
	_forge_hammer_sprite.texture = HAMMER_TEXTURE
	_fit_forge_sprite_long_edge(_forge_hammer_sprite,forge_hammer_visual_long_edge)
	_apply_forge_hammer_grip_offset()

	_forge_visual_root.visible = true
	_forge_item_sprite.visible = true
	_forge_hammer_pivot.visible = true
	_forge_strike_done = false
	_forge_success_sfx_index = success_sfx_index
	_forge_helmet_sfx_index = helmet_sfx_index
	_apply_forge_visual_progress(0.0)

	_forge_tween = create_tween()
	_forge_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_forge_tween.tween_method(Callable(self,"_apply_forge_visual_progress"),0.0,1.0,maxf(forge_visual_duration,0.18))
	_forge_tween.finished.connect(_finish_forge_animation_local,CONNECT_ONE_SHOT)


func _apply_forge_visual_progress(progress:float) -> void:
	if _forge_visual_root == null or _forge_item_sprite == null or _forge_hammer_pivot == null:
		return
	var p:float = clampf(progress,0.0,1.0)
	var hold:Vector2 = forge_item_hold_position

	# V89：物品/锤子关键姿态优先来自场景里的“锻造_可视调整”节点。
	# 下面仍然保留插值动画，但不再把关键位置硬编码在函数里。
	# 用户实测 V86 左右倾斜方向相反，因此默认 skew 从 -14° 翻到 +14°；
	# 同时 hold 从 X=0 右移到 X=8，Y=36 保持不变。
	var item_in:float = clampf(p / 0.28,0.0,1.0)
	var item_eased:float = 1.0 - pow(1.0 - item_in,3.0)
	var item_base_scale:float = maxf(absf(_forge_item_sprite.scale.x),0.001)
	var flatten_ratio:float = lerpf(0.72,clampf(forge_item_flatten_ratio,0.30,0.80),item_eased)
	var target_skew:float = deg_to_rad(clampf(forge_item_skew_degrees,-35.0,35.0))
	_forge_item_sprite.position = forge_item_start_position.lerp(hold,item_eased)
	_forge_item_sprite.rotation = 0.0
	_forge_item_sprite.scale = Vector2(item_base_scale,item_base_scale * flatten_ratio)
	_forge_item_sprite.skew = lerpf(0.0,target_skew,item_eased)
	_forge_item_sprite.modulate.a = item_eased

	# 22~60%：锤子从“入场 -> 抬起 -> 命中”三张可视预览姿态之间插值。
	# 这三张预览可直接在铁匠村民.tscn 的 2D 视图里拖动和旋转。
	var entry_rotation:float = deg_to_rad(forge_hammer_entry_rotation_degrees)
	var rest_rotation:float = deg_to_rad(forge_hammer_rest_rotation_degrees)
	var impact_rotation:float = deg_to_rad(forge_hammer_impact_rotation_degrees)
	if p < 0.22:
		_forge_hammer_pivot.modulate.a = 0.0
	else:
		var hammer_in:float = clampf((p - 0.22) / 0.20,0.0,1.0)
		_forge_hammer_pivot.modulate.a = hammer_in
		if p < 0.42:
			_forge_hammer_pivot.position = forge_hammer_entry_position.lerp(forge_hammer_rest_position,hammer_in)
			_forge_hammer_pivot.rotation = lerp_angle(entry_rotation,rest_rotation,hammer_in)
		else:
			# 0.42 -> 0.60 恰好完整落锤；命中姿态就是场景里“锤子_命中”的最终 Transform。
			var slam_t:float = clampf((p - 0.42) / 0.18,0.0,1.0)
			var slam_eased:float = 1.0 - pow(1.0 - slam_t,4.0)
			_forge_hammer_pivot.position = forge_hammer_rest_position.lerp(forge_hammer_impact_position,slam_eased)
			_forge_hammer_pivot.rotation = lerp_angle(rest_rotation,impact_rotation,slam_eased)

	if p >= 0.60 and not _forge_strike_done:
		_forge_strike_done = true
		_forge_strike_local(_forge_success_sfx_index,_forge_helmet_sfx_index)

	# 命中后装备轻微下压/震一下，随后装备与重锤一起淡出。
	if p >= 0.60:
		var impact_t:float = clampf((p - 0.60) / 0.18,0.0,1.0)
		var impact_base_scale:float = maxf(absf(_forge_item_sprite.scale.x),0.001)
		var impact_flatten:float = clampf(forge_item_flatten_ratio,0.30,0.80) - sin(impact_t * PI) * 0.04
		_forge_item_sprite.position = hold + Vector2(sin(impact_t * PI * 3.0) * 2.0,impact_t * 3.0)
		_forge_item_sprite.rotation = 0.0
		_forge_item_sprite.scale = Vector2(impact_base_scale,impact_base_scale * maxf(impact_flatten,0.25))
		_forge_item_sprite.skew = deg_to_rad(clampf(forge_item_skew_degrees,-35.0,35.0) + sin(impact_t * PI * 2.0) * 2.0)
	if p >= 0.78:
		var fade_t:float = clampf((p - 0.78) / 0.22,0.0,1.0)
		var alpha:float = 1.0 - fade_t
		_forge_item_sprite.modulate.a = minf(_forge_item_sprite.modulate.a,alpha)
		_forge_hammer_pivot.modulate.a = minf(_forge_hammer_pivot.modulate.a,alpha)
		_forge_hammer_pivot.position += Vector2(0.0,-4.0 * fade_t)


func _forge_strike_local(success_sfx_index:int,helmet_sfx_index:int) -> void:
	_forge_flash_left = 0.32
	queue_redraw()
	_spawn_forge_impact_effect(forge_impact_effect_position)
	_play_world_sfx(SINGLE_FORGE_SFX,global_position,1.5,randf_range(0.98,1.02),1450.0)
	if helmet_sfx_index >= 0 and helmet_sfx_index < HELMET_UPGRADE_SFX.size():
		_play_helmet_upgrade_sfx_local(helmet_sfx_index,global_position)
	elif success_sfx_index >= 0 and success_sfx_index < SMITHING_SUCCESS_SFX.size():
		_play_smithing_success_sfx_local(success_sfx_index,global_position)


func _forge_visual_world_scale() -> float:
	if _forge_visual_root == null or not is_instance_valid(_forge_visual_root):
		return 1.0
	var transform_value:Transform2D = _forge_visual_root.global_transform
	var sx:float = transform_value.x.length()
	var sy:float = transform_value.y.length()
	return clampf((sx + sy) * 0.5,0.35,2.50)


func _spawn_forge_impact_effect(contact_local:Vector2) -> void:
	# V87：锤头真正落到装备的同一帧，从精确 contact point 生成两层反馈：
	# 1) 一个压扁 + shear 的白色冲击圈，视觉上贴在装备所在的 2.5D 平面；
	# 2) 复用项目通用 HitBurstEffect 的 Line2D 动画，向四周放射细白线。
	if _forge_visual_root == null or not is_instance_valid(_forge_visual_root) or not _forge_visual_root.is_inside_tree():
		return
	var parent:Node = get_tree().current_scene
	if parent == null:
		return

	var impact_world:Vector2 = _forge_visual_root.to_global(contact_local)
	var world_scale:float = _forge_visual_world_scale()
	_spawn_forge_impact_ring(parent,impact_world,world_scale)

	# V88：数量不再固定。每次锤击在 min/max 范围内重新抽取，同时对角度、长度、射程、线宽和延迟加少量随机，
	# 避免连续锻造时每一锤都像完全相同的“太阳图标”。
	var count_min:int = clampi(forge_impact_streak_count_min,3,20)
	var count_max:int = clampi(forge_impact_streak_count_max,count_min,28)
	var count:int = _forge_fx_rng.randi_range(count_min,count_max)
	var streaks:Array = []
	var base_duration:float = clampf(forge_impact_effect_duration,0.10,0.40)
	var phase_offset:float = _forge_fx_rng.randf_range(-PI,PI)
	var angular_step:float = TAU / float(maxi(count,1))
	for index:int in range(count):
		# 先近似均匀覆盖 360°，再随机抖动，既不会全部挤在一边，也不会每次形成完全规则的星芒。
		var angle_jitter:float = _forge_fx_rng.randf_range(-angular_step * 0.32,angular_step * 0.32)
		var angle:float = phase_offset + angular_step * float(index) + angle_jitter
		var distance:float = forge_impact_ring_radius * world_scale * _forge_fx_rng.randf_range(1.02,1.82)
		var streak_length:float = forge_impact_ring_radius * world_scale * _forge_fx_rng.randf_range(0.34,0.72)
		streaks.append({
			"spawn_offset": Vector2.ZERO,
			"direction": Vector2.from_angle(angle),
			"distance": distance,
			"length": streak_length,
			"width": maxf(_forge_fx_rng.randf_range(0.52,0.90) * world_scale,0.42),
			"duration": base_duration * _forge_fx_rng.randf_range(0.82,1.12),
			"delay": _forge_fx_rng.randf_range(0.0,0.020),
			"grow_end": _forge_fx_rng.randf_range(0.20,0.29),
			"fade_in_end": 0.08,
			"fade_out_start": _forge_fx_rng.randf_range(0.38,0.50),
			"color": Color(1.0,1.0,1.0,_forge_fx_rng.randf_range(0.90,1.0)),
		})

	# HIT_BURST_EFFECT_SCRIPT 已由父类 ball 定义；子类不再重复声明，避免 GDScript 继承成员冲突。
	var burst = HIT_BURST_EFFECT_SCRIPT.new()
	burst.name = "铁匠锤击_放射白线"
	burst.setup(impact_world,streaks)
	parent.add_child(burst)


func _spawn_forge_impact_ring(parent:Node,impact_world:Vector2,world_scale:float) -> void:
	var ring_root := Node2D.new()
	ring_root.name = "铁匠锤击_倾斜白圈"
	ring_root.top_level = true
	ring_root.z_as_relative = false
	ring_root.z_index = 99
	parent.add_child(ring_root)
	ring_root.global_position = impact_world

	var ring := Line2D.new()
	ring.name = "倾斜白圈"
	ring.width = maxf(1.55 * world_scale,1.0)
	ring.default_color = Color(1.0,1.0,1.0,0.98)
	ring.begin_cap_mode = Line2D.LINE_CAP_ROUND
	ring.end_cap_mode = Line2D.LINE_CAP_ROUND
	ring.joint_mode = Line2D.LINE_JOINT_ROUND
	ring.antialiased = true

	var points := PackedVector2Array()
	var radius:float = maxf(forge_impact_ring_radius,8.0) * world_scale
	var flatten:float = clampf(forge_impact_ring_flatten_ratio,0.20,0.80)
	# shear 方向跟装备 skew 一致，所以白圈看起来是贴在同一个“平放平面”上，而不是屏幕正圆。
	var shear:float = tan(deg_to_rad(clampf(forge_item_skew_degrees,-35.0,35.0))) * 0.72
	for i:int in range(33):
		var angle:float = TAU * float(i) / 32.0
		var y:float = sin(angle) * radius * flatten
		var x:float = cos(angle) * radius + y * shear
		points.append(Vector2(x,y))
	ring.points = points
	ring_root.add_child(ring)

	ring_root.scale = Vector2(0.36,0.36)
	var duration:float = clampf(forge_impact_effect_duration,0.10,0.40)
	var tween:Tween = ring_root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring_root,"scale",Vector2(1.30,1.30),duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring_root,"modulate",Color(1.0,1.0,1.0,0.0),duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(ring_root.queue_free)


func _finish_forge_animation_local() -> void:
	if _forge_visual_root != null and is_instance_valid(_forge_visual_root):
		_forge_visual_root.visible = false
	_forge_success_sfx_index = -1
	_forge_helmet_sfx_index = -1


func _stop_forge_animation_local() -> void:
	if _forge_tween != null and _forge_tween.is_valid():
		_forge_tween.kill()
	_forge_tween = null
	_forge_success_sfx_index = -1
	_forge_helmet_sfx_index = -1
	if _forge_visual_root != null and is_instance_valid(_forge_visual_root):
		_forge_visual_root.visible = false


func _play_helmet_upgrade_sfx_local(index:int,world_position:Vector2) -> void:
	if index < 0 or index >= HELMET_UPGRADE_SFX.size():
		return
	_play_world_sfx(HELMET_UPGRADE_SFX[index],world_position,2.0,randf_range(0.98,1.02),1450.0)


func _play_smithing_success_sfx_local(index:int,world_position:Vector2) -> void:
	if index < 0 or index >= SMITHING_SUCCESS_SFX.size():
		return
	_play_world_sfx(SMITHING_SUCCESS_SFX[index],world_position,3.0,randf_range(0.99,1.01),1600.0)


func _play_world_sfx(
	stream:AudioStream,
	world_position:Vector2,
	volume_db:float = 0.0,
	pitch:float = 1.0,
	max_distance:float = 1400.0
) -> void:
	if stream == null or not is_inside_tree():
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.max_distance = maxf(max_distance,1.0)
	player.attenuation = 0.68
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	# World 根节点由 MultiplayerSpawner 监听。一次性声音挂在角色下面并设 top_level，
	# 既保留世界坐标衰减，又避免临时 AudioStreamPlayer2D 被当成网络出生对象。
	add_child(player)
	player.top_level = true
	player.global_position = world_position
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _broadcast_growth_text(kind:StringName,amount:int) -> void:
	# 与 HealthBar._spawn_damage_text() 完全走同一条生成方式：
	# 只由 authority 在 World 根实例化 damage_text.tscn，让现有 MultiplayerSpawner/
	# MultiplayerSynchronizer 负责远端出生与属性同步，避免再手写第二套跳字 RPC。
	_show_growth_text_local(kind,amount)


func _show_growth_text_local(kind:StringName,amount:int) -> void:
	if not is_multiplayer_authority() or DAMAGE_TEXT_SCENE == null or get_tree() == null or get_tree().current_scene == null:
		return
	var tree:SceneTree = get_tree()
	if tree.get_node_count_in_group("__damage_text_runtime") >= 80:
		return

	var floating:Label = DAMAGE_TEXT_SCENE.instantiate() as Label
	if floating == null:
		return
	floating.add_to_group("__damage_text_runtime")

	var base_position:Vector2 = global_position
	if image != null and is_instance_valid(image):
		base_position = image.global_position
	floating.global_position = base_position + Vector2(randf_range(-9.0,9.0),randf_range(-8.0,4.0))

	var safe_amount:int = maxi(amount,1)
	# V85：本项目切换语言时会对运行时 Label 做“片段翻译”，裸字符串 +10Damage 会被 Damage 片段改成中文，
	# 再切语言时又可能从元数据恢复英文，看起来就像跳字在中/英文之间来回变。这里明确锁定为设计要求的英文战斗短语。
	# U+2060 WORD JOINER 不可见，但能阻止片段替换把 Damage/Block 当成普通翻译片段；同时关闭 Godot 自带自动翻译。
	floating.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var locale_guard:String = "\u2060"
	if kind == &"damage":
		floating.text = "+%dDa%smage" % [safe_amount,locale_guard]
		floating.add_theme_color_override("font_color",Color(1.0,0.16,0.12,1.0))
		floating.add_theme_color_override("font_outline_color",Color(0.30,0.0,0.0,1.0))
	else:
		floating.text = "+%dBl%sock" % [safe_amount,locale_guard]
		floating.add_theme_color_override("font_color",Color(0.86,0.88,0.92,1.0))
		floating.add_theme_color_override("font_outline_color",Color(0.12,0.12,0.14,1.0))

	floating.name = Game.return_random_name(floating)
	tree.current_scene.add_child(floating,true)
	if floating.has_method("set_properties"):
		floating.call("set_properties",safe_amount)


func _has_death_animation() -> bool:
	return true


func Die() -> void:
	if _death_sequence_started:
		return
	_death_sequence_started = true
	var death_position:Vector2 = global_position
	_interrupt_sword_attack(false)
	_stop_forge_animation_local()
	super()
	_broadcast_death_visual(death_position)

	if get_tree() == null:
		if is_multiplayer_authority() and is_instance_valid(self):
			Game.free_node(self)
		return
	await get_tree().create_timer(DEATH_POSE_DURATION).timeout
	if is_instance_valid(self) and is_multiplayer_authority():
		Game.free_node(self)


func _broadcast_death_visual(death_position:Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_start_death_visual.rpc(death_position)
	else:
		_rpc_start_death_visual(death_position)


@rpc("authority","call_local","reliable")
func _rpc_start_death_visual(death_position:Vector2) -> void:
	if _death_visual_started_local:
		return
	_death_visual_started_local = true
	_interrupt_sword_attack(false)
	_stop_forge_animation_local()
	if health_bar != null and is_instance_valid(health_bar):
		health_bar.hide()

	var graphics_node:Node2D = get_node_or_null("Graphics") as Node2D
	if graphics_node != null:
		# 复用骷髅/蠹虫等 Minecraft 角色的死亡表现：先染红，再侧倒约 90°，
		# 角色姿势结束后原地出现 Minecraft 方块烟雾。
		var rotate_sign:float = -1.0 if direction.x >= 0.0 else 1.0
		var tween:Tween = graphics_node.create_tween()
		tween.set_parallel(true)
		tween.tween_property(graphics_node,"modulate",Color(1.0,0.22,0.22,1.0),0.10)
		tween.tween_property(
			graphics_node,
			"rotation",
			graphics_node.rotation + rotate_sign * PI * 0.5,
			DEATH_POSE_DURATION
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	_create_delayed_death_smoke(death_position)


func _create_delayed_death_smoke(death_position:Vector2) -> void:
	var visual_parent:Node = _get_runtime_visual_parent()
	if visual_parent == null:
		return
	var smoke := AnimatedSprite2D.new()
	smoke.name = "铁匠村民死亡烟雾_%d" % smoke.get_instance_id()
	smoke.sprite_frames = DEATH_SMOKE_FRAMES
	smoke.animation = &"死亡烟雾"
	smoke.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	smoke.z_as_relative = false
	smoke.z_index = 8
	smoke.scale = Vector2.ONE * 0.56
	smoke.visible = false
	visual_parent.add_child(smoke,true)
	smoke.global_position = death_position
	smoke.animation_finished.connect(Callable(smoke,"queue_free"),CONNECT_ONE_SHOT)

	var delayed:Tween = smoke.create_tween()
	delayed.tween_interval(DEATH_POSE_DURATION)
	delayed.tween_callback(Callable(smoke,"show"))
	delayed.tween_callback(Callable(smoke,"play").bind(&"死亡烟雾"))


func _get_runtime_visual_parent() -> Node:
	if get_tree() == null:
		return null
	var world:Node = get_tree().current_scene
	if world == null:
		return null
	var container:Node = world.get_node_or_null("V311运行时对象")
	if container != null:
		return container
	container = Node2D.new()
	container.name = "V311运行时对象"
	world.add_child(container,true)
	return container


func _sync_runtime_state_periodically(delta:float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	_state_sync_left -= maxf(delta,0.0)
	if _state_sync_left > 0.0:
		return
	_state_sync_left = 1.5
	_broadcast_runtime_state()


func _broadcast_runtime_state() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	_rpc_sync_runtime_state.rpc(
		helmet_tier,
		sword_tier,
		forge_count,
		post_max_damage_bonus,
		post_max_armor_bonus,
		_forge_progress
	)


@rpc("authority","call_remote","reliable")
func _rpc_sync_runtime_state(
	new_helmet_tier:int,
	new_sword_tier:int,
	new_forge_count:int,
	new_post_max_damage_bonus:int,
	new_post_max_armor_bonus:int,
	new_forge_progress:float
) -> void:
	helmet_tier = clampi(new_helmet_tier,TIER_NONE,TIER_NETHERITE)
	sword_tier = clampi(new_sword_tier,TIER_NONE,TIER_NETHERITE)
	forge_count = maxi(new_forge_count,0)
	post_max_damage_bonus = maxi(new_post_max_damage_bonus,0)
	post_max_armor_bonus = maxi(new_post_max_armor_bonus,0)
	_forge_progress = clampf(new_forge_progress,0.0,0.999999)
	_apply_equipment_stats(false)
	_update_equipment_visuals()
	queue_redraw()
