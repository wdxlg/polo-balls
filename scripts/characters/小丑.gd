extends ball

# ========================================================
# 小丑：随机武器角色 V9（平滑瞄准 + 投射物可见性 + 回旋镖修复 + 数值重平衡）
#
# 武器流程：
# EMPTY -> ROLLING -> ROLL_COMPLETE -> ARMED -> 使用 -> EMPTY
#
# 美术：
# Inspector 可直接拖入 4 张小丑表情、10 张“小丑拿着武器”的整图、常用弹丸/场景物件图。
# 武器人物图直接替换 Graphics/Image；不再把武器作为独立 Sprite 放在角色旁边。
# ========================================================

const BASIC_BULLET_SCENE:PackedScene = preload("res://scenes/shooter/子弹.tscn")
const CLOWN_PROJECTILE_SCENE:PackedScene = preload("res://scenes/shooter/clown/clown_projectile.tscn")
const CLOWN_AREA_OBJECT_SCENE:PackedScene = preload("res://scenes/shooter/clown/clown_area_object.tscn")
const CLOWN_MOTION_EFFECT = preload("res://scripts/shooter/clown/clown_motion_effect.gd")


enum ClownWeaponState {
	EMPTY,
	ROLLING,
	ROLL_COMPLETE,
	ARMED,
}


enum Weapon {
	BANANA_PEEL,
	CONFETTI_CANNON,
	TOY_HAMMER,
	SNIPER_RIFLE,
	ROCKET_LAUNCHER,
	BLACK_HOLE_GUN,
	CHAIN_LIGHTNING,
	FREEZE_SPRAYER,
	BOOMERANG,
	BROKEN_PISTOL,
}


# 1~6，越高越强。
# 强武器 >= 5：欢呼 + 彩带。
# 弱武器 <= 2：叹气。
var weapon_power:Array[int] = [
	2, # 香蕉皮
	2, # 彩带炮
	3, # 玩具锤
	5, # 狙击枪
	5, # 火箭筒
	6, # 黑洞枪
	5, # 连锁闪电枪
	3, # 冰冻喷雾器
	4, # 回旋镖
	1, # 坏掉的手枪
]

var weapon_names:Array[String] = [
	"香蕉皮",
	"彩带炮",
	"玩具锤",
	"狙击枪",
	"火箭筒",
	"黑洞枪",
	"连锁闪电枪",
	"冰冻喷雾器",
	"回旋镖",
	"坏掉的手枪",
]

# 注意：这里故意不用 const PackedFloat32Array。
# Godot 4.7 的 const 必须是编译期常量，而 PackedFloat32Array(...) 构造不是常量表达式。
# 这正是你截图第 76 行报错的原因。
@export_category("武器概率（顺序对应 Weapon enum）")
@export var weapon_weights:PackedFloat32Array = PackedFloat32Array([
	1.35, # 香蕉皮：常见控制
	1.20, # 彩带炮：常见近距铺场
	1.05, # 玩具锤：中等强度
	0.48, # 狙击枪：稀有强力单点
	0.58, # 火箭筒：稀有范围爆发
	0.20, # 黑洞枪：最稀有
	0.38, # 连锁闪电枪：稀有群攻
	0.95, # 冰冻喷雾器：常规控制
	0.90, # 回旋镖：常规持续输出
	1.20, # 坏掉的手枪：常见搞笑弱武器
])


# 这些都是你现有工程中已经被场景/脚本引用过的旧图路径。
# 后面正式美术做好，只需要换这里或改成 Inspector 资源数组。
var old_texture_pool:Array[String] = [
	"res://Images/218e3a934d164c65be7216bb3cc243ce.png",
	"res://Images/46e4d6a5e62b4b9497432fce6703ebc8.png",
	"res://Images/92b96e9f1b4d47f494adc8872574de70.png",
	"res://Images/Base-01.png",
	"res://Images/Status/dazed.png",
	"res://Images/characters/三角洲/乌鲁鲁/PixPin_2026-05-22_14-25-50.png",
	"res://Images/characters/三角洲/红狼/PixPin_2026-05-22_14-21-55.png",
	"res://Images/characters/三角洲/红狼/PixPin_2026-05-22_14-27-06.png",
	"res://Images/characters/三角洲/背刺/PixPin_2026-05-22_14-08-10.png",
	"res://Images/characters/杀戮尖塔/储君/剑/剑_converted_1.png",
	"res://Images/characters/杀戮尖塔/储君/剑/剑_converted_2.png",
	"res://Images/characters/杀戮尖塔/储君/剑/剑_converted_3.png",
	"res://Images/characters/杀戮尖塔/储君/剑/剑_converted_4.png",
	"res://Images/characters/杀戮尖塔/储君/剑/剑_converted_5.png",
	"res://Images/characters/杀戮尖塔/储君/剑/剑_converted_6.png",
	"res://Images/characters/杀戮尖塔/储君/剑/剑_converted_7.png",
	"res://Images/characters/杀戮尖塔/战士/攻击/攻击_converted__1__1.png",
	"res://Images/characters/杀戮尖塔/战士/攻击/攻击_converted__1__2.png",
	"res://Images/characters/杀戮尖塔/战士/攻击/攻击_converted__1__3.png",
	"res://Images/characters/杀戮尖塔/战士/攻击/攻击_converted__1__4.png",
	"res://Images/characters/杀戮尖塔/战士/攻击/攻击_converted__1__5.png",
	"res://Images/characters/杀戮尖塔/猎人/攻击/攻击_2.png",
	"res://Images/characters/杀戮尖塔/猎人/攻击/攻击_3.png",
	"res://Images/characters/杀戮尖塔/猎人/攻击/攻击_4.png",
	"res://Images/characters/杀戮尖塔/猎人/站立/站立_1.png",
	"res://Images/characters/杀戮尖塔/猎人/站立/站立_2.png",
	"res://Images/characters/杀戮尖塔/猎人/站立/站立_3.png",
	"res://Images/characters/杀戮尖塔/猎人/站立/站立_4.png",
	"res://Images/characters/杀戮尖塔/猎人/子弹/snakebite.png",
	"res://Images/characters/杀戮尖塔/蜂群术士/正常/蜂群术士_正常_1.png",
	"res://Images/characters/杀戮尖塔/蜂群术士/正常/蜂群术士_正常_2.png",
	"res://Images/characters/杀戮尖塔/蜂群术士/正常/蜂群术士_正常_3.png",
	"res://Images/characters/杀戮尖塔/蜂群术士/正常/蜂群术士_正常_4.png",
	"res://Images/characters/杀戮尖塔/观者/PixPin_2026-05-20_00-37-57.png",
	"res://Images/characters/杀戮尖塔/门扉缔造者/PixPin_2026-05-20_12-25-27.png",
	"res://Images/characters/杀戮尖塔/门扉缔造者/PixPin_2026-05-20_12-26-20.png",
	"res://Images/characters/杀戮尖塔/门扉缔造者/PixPin_2026-05-20_12-26-25.png",
]


@export_category("小丑随机过程")
@export var roll_duration:float = 0.90
@export var roll_tick_count:int = 8
@export var roll_complete_hold:float = 0.34
@export var armed_hold_before_use:float = 0.22
@export var prevent_same_weapon_twice:bool = true

@export_category("小丑角色贴图（直接把 PNG 拖进 Inspector）")
# 四张角色表情图：
# 正常 = 无武器/普通结果；沉思 = 随机中；大笑 = 抽到强武器；沮丧 = 抽到弱武器。
# 留空时自动回退到旧贴图池，不影响测试。
@export var clown_normal_texture:Texture2D
@export var clown_thinking_texture:Texture2D
@export var clown_laugh_texture:Texture2D
@export var clown_sad_texture:Texture2D

@export_category("十把武器人物贴图（整张替换 Graphics/Image）")
# 这里每一张都应该是“完整的小丑 + 当前武器”合成图，
# 例如香蕉槽位不是单独香蕉，而是“小丑拿着香蕉”的整张角色图。
# 所有图片直接替换 ball.tscn 现有的 Graphics/Image，不再生成额外武器 Sprite。
@export var clown_banana_texture:Texture2D
@export var clown_confetti_texture:Texture2D
@export var clown_toy_hammer_texture:Texture2D
@export var clown_sniper_texture:Texture2D
@export var clown_rocket_texture:Texture2D
@export var clown_black_hole_texture:Texture2D
@export var clown_chain_lightning_texture:Texture2D
@export var clown_freeze_texture:Texture2D
@export var clown_boomerang_texture:Texture2D
@export var clown_broken_pistol_texture:Texture2D

@export_category("弹丸 / 场景物件贴图（可选，留空继续随机旧图）")
@export var banana_peel_texture:Texture2D
@export var confetti_piece_texture:Texture2D
@export var toy_hammer_projectile_texture:Texture2D
@export var sniper_bullet_texture:Texture2D
@export var rocket_projectile_texture:Texture2D
@export var boomerang_projectile_texture:Texture2D
@export var broken_pistol_bullet_texture:Texture2D

@export_category("武器出手前摇")
# 抽到武器后不会立刻出手。
# 前摇期间小丑的 Graphics/Image 会持续旋转朝向当前目标。
@export var banana_prepare_time:float = 0.22
@export var confetti_prepare_time:float = 0.28
@export var toy_hammer_prepare_time:float = 0.30
@export var sniper_prepare_time:float = 0.18
@export var rocket_prepare_time:float = 0.36
@export var black_hole_prepare_time:float = 0.42
@export var chain_lightning_prepare_time:float = 0.30
@export var freeze_prepare_time:float = 0.24
@export var boomerang_prepare_time:float = 0.28
@export var broken_pistol_prepare_time:float = 0.22

@export_category("武器人物图瞄准")
# 使用指数插值做帧率无关的角度平滑。数值越大转得越快。
@export_range(1.0,40.0,0.5) var weapon_aim_smoothing:float = 14.0
# 停止瞄准后也平滑回到人物图片的基础角度。
@export_range(1.0,40.0,0.5) var weapon_return_smoothing:float = 11.0

@export_category("随机/结果音效")
@export var rolling_tick_sfx:String = "MouseEnterButton1"
@export var roll_complete_sfx:String = "ButtonUpMouseOut"
@export var strong_cheer_sfx:String = "God"
@export var weak_sigh_sfx:String = "Debuff1"

@export_category("统一命中反馈")
@export var clown_hit_feedback_enabled:bool = true
@export_range(0.02,0.30,0.01) var clown_hit_feedback_cooldown:float = 0.08
@export var clown_hit_feedback_min_power:float = 34.0
@export var clown_hit_feedback_max_power:float = 150.0

@export_category("香蕉皮")
@export var banana_arm_delay:float = 0.55
@export var banana_lifetime:float = 8.0
@export var banana_slide_speed:float = 540.0
@export var banana_slide_distance:float = 150.0
@export_range(0.0,2.0,0.05) var banana_wall_bounce_strength:float = 0.0
@export var banana_crash_damage_multiplier:float = 0.85
@export var banana_crash_stun:float = 0.55

@export_category("彩带炮")
# V9.4：彩带改为弹道式攻击。
# 从小丑前方斜向喷出，带向上的初速度，随后被屏幕向下的重力拉回形成抛物线。
@export var confetti_piece_count:int = 18
# 旧的 launch/upward 字段继续保留，避免已有 Inspector 覆盖失效；
# V9.5 实际弹道改为“指定飞行时间 -> 反求初速度”，保证轨迹经过目标附近。
@export var confetti_launch_speed:float = 235.0
@export var confetti_upward_speed:float = 190.0
@export var confetti_gravity:float = 520.0
@export_range(0.20,2.0,0.01) var confetti_flight_time_min:float = 0.62
@export_range(0.20,2.0,0.01) var confetti_flight_time_max:float = 0.88
# 为了让抛物线肉眼可见，即使目标略低，也尽量保证初始速度至少向上这么多。
@export_range(0.0,500.0,5.0) var confetti_min_upward_speed:float = 115.0
@export_range(0.0,60.0,1.0) var confetti_target_spread:float = 15.0
@export_range(0.0,1.0,0.05) var confetti_target_prediction:float = 0.20
@export var confetti_spawn_lateral_spread:float = 9.0
@export var confetti_fall_delete_distance:float = 110.0
@export var confetti_lifetime:float = 1.55
@export var confetti_damage_multiplier:float = 0.08

@export_category("玩具锤")
@export var toy_hammer_speed:float = 350.0
@export var toy_hammer_damage_multiplier:float = 1.65
# V7：使用 ball.apply_knockback()，距离/速度/撞墙反弹/眩晕可以独立控制。
@export var toy_hammer_knockback_distance:float = 105.0
@export var toy_hammer_knockback_speed:float = 860.0
@export_range(0.0,2.0,0.05) var toy_hammer_wall_bounce_strength:float = 0.22
@export var toy_hammer_stun_duration:float = 0.16
@export var toy_hammer_recoil_distance:float = 38.0
@export var toy_hammer_recoil_speed:float = 500.0

@export_category("狙击枪")
@export var sniper_aim_duration:float = 0.62
@export var sniper_bullet_speed:float = 1650.0
@export var sniper_damage_multiplier:float = 4.50
@export var sniper_max_predict_time:float = 0.75
@export var sniper_range:float = 1150.0

@export_category("火箭筒")
@export var rocket_speed:float = 260.0
@export var rocket_damage_multiplier:float = 3.20
@export var rocket_explosion_radius:float = 150.0
@export var rocket_explosion_knockback_distance:float = 120.0
@export var rocket_explosion_knockback_speed:float = 850.0
@export_range(0.0,2.0,0.05) var rocket_explosion_wall_bounce_strength:float = 0.30
@export var rocket_explosion_stun_duration:float = 0.14

@export_category("黑洞枪")
@export var black_hole_cast_range:float = 360.0
# V9.2：黑洞不再瞬间出现在目标点，而是先飞出一颗可见的黑洞核心。
@export var black_hole_projectile_speed:float = 285.0
@export var black_hole_projectile_min_travel_time:float = 0.20
@export var black_hole_projectile_max_travel_time:float = 0.78
@export var black_hole_radius:float = 235.0
@export var black_hole_duration:float = 1.60
# V5：单位是持续吸引速度 px/s，不再是偶尔写一次 Repel 的“小推力”。
@export var black_hole_pull_speed:float = 620.0
@export_range(0.0,1.0,0.01) var black_hole_edge_pull_ratio:float = 0.42
@export var black_hole_tick_interval:float = 0.25
@export var black_hole_tick_damage_multiplier:float = 0.12
@export var black_hole_final_damage_multiplier:float = 3.20
@export var black_hole_final_radius:float = 145.0
@export var black_hole_final_knockback_distance:float = 135.0
@export var black_hole_final_knockback_speed:float = 900.0
@export_range(0.0,2.0,0.05) var black_hole_final_wall_bounce_strength:float = 0.38
@export var black_hole_final_stun_duration:float = 0.12

@export_category("连锁闪电枪")
@export var chain_lightning_targets:int = 4
@export var chain_lightning_range:float = 265.0
@export var chain_lightning_first_damage_multiplier:float = 2.10
@export var chain_lightning_decay:float = 0.72
@export var chain_lightning_stun:float = 0.14

@export_category("冰冻喷雾器")
@export var freeze_range:float = 205.0
@export var freeze_half_angle_degrees:float = 34.0
@export var freeze_damage_multiplier:float = 0.55
@export var freeze_speed_multiplier:float = 0.50
@export var freeze_duration:float = 1.45

@export_category("回旋镖")
@export var boomerang_speed:float = 520.0
@export var boomerang_distance:float = 285.0
@export var boomerang_damage_multiplier:float = 1.10
@export var boomerang_knockback_distance:float = 28.0
@export var boomerang_knockback_speed:float = 460.0
@export_range(0.0,2.0,0.05) var boomerang_wall_bounce_strength:float = 0.10
@export_range(0.05,1.0,0.01) var boomerang_same_target_cooldown:float = 0.24
@export var boomerang_sweep_radius:float = 42.0

@export_category("坏掉的手枪")
@export_range(0.0,1.0,0.01) var broken_pistol_jam_chance:float = 0.42
@export_range(0.0,1.0,0.01) var broken_pistol_backfire_chance:float = 0.12
@export var broken_pistol_damage_multiplier:float = 0.80
@export var broken_pistol_bullet_visual_size:float = 58.0


var clown_weapon_state:int = ClownWeaponState.EMPTY
var current_weapon:int = -1
var last_weapon:int = -1

var rng:RandomNumberGenerator = RandomNumberGenerator.new()

# 3 张旧图兜底：EMPTY / ROLLING / ROLL_COMPLETE
var state_skin_paths:Array[String] = []
var available_texture_pool:Array[String] = []
var last_projectile_skin:String = ""

var result_label:Label = null
var sniper_aim_line:Line2D = null
var _black_hole_cast_serial:int = 0
var _clown_hit_feedback_times:Dictionary = {}

# Graphics/Image 自己就是小丑的唯一角色贴图层。
# 记录场景中原本的 rotation，把它当作美术“朝右”的基准角度。
var _image_base_rotation:float = 0.0
var _weapon_aim_lock:bool = false
var _weapon_aim_direction:Vector2 = Vector2.RIGHT
var _weapon_return_to_base:bool = false
var _weapon_aim_angular_velocity:float = 0.0
var _weapon_visual_facing_left:bool = false


func _ready() -> void:
	super()

	Can_Attack = false
	Can_Skill = true
	rng.seed = Game.battle_rng_seed_or("scripts/characters/小丑.gd:rng",int(Time.get_ticks_usec()) ^ int(get_instance_id()))

	if image:
		_image_base_rotation = image.rotation

	_build_available_texture_pool()
	_create_temporary_visual_nodes()

	if is_multiplayer_authority():
		_assign_unique_state_skins()
		if multiplayer.has_multiplayer_peer():
			_sync_state_skin_paths.rpc(state_skin_paths)
		else:
			_sync_state_skin_paths(state_skin_paths)


func _build_available_texture_pool() -> void:
	available_texture_pool.clear()
	for path:String in old_texture_pool:
		if ResourceLoader.exists(path):
			available_texture_pool.append(path)

	if available_texture_pool.size() < 3:
		push_warning(
			"小丑表情兜底至少需要 3 张可用旧贴图，目前只有 %d 张。" % available_texture_pool.size()
		)


func _create_temporary_visual_nodes() -> void:
	# 小丑人物以及“拿着武器”的状态都只使用 ball.tscn 原有的 Graphics/Image。
	# 不再创建 ClownWeaponVisual，也不会对角色图做额外尺寸适配。
	if image:
		image.visible = true

	result_label = Label.new()
	result_label.name = "ClownWeaponResultLabel"
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.position = Vector2(-85.0,-65.0)
	result_label.size = Vector2(170.0,30.0)
	result_label.scale = Vector2(2.2,2.2)
	# 结果文字属于根节点，不跟着 Graphics/Image 一起旋转；
	# z_index 高于人物图片，始终显示在角色前面。
	result_label.z_index = 30
	result_label.visible = false
	add_child(result_label)


func _assign_unique_state_skins() -> void:
	state_skin_paths.clear()

	var shuffled:Array[String] = available_texture_pool.duplicate()
	_shuffle_string_array(shuffled)

	# 旧贴图仅作为“正常 / 随机中 / 随机完成”三种表情的兜底。
	# 武器状态不再拿随机旧武器图盖在小丑旁边。
	var needed:int = 3
	for i:int in range(needed):
		if i < shuffled.size():
			state_skin_paths.append(shuffled[i])
		elif not available_texture_pool.is_empty():
			state_skin_paths.append(
				available_texture_pool[rng.randi_range(0,available_texture_pool.size() - 1)]
			)
		else:
			state_skin_paths.append("")


func _shuffle_string_array(values:Array[String]) -> void:
	for i:int in range(values.size() - 1,0,-1):
		var j:int = rng.randi_range(0,i)
		var temp:String = values[i]
		values[i] = values[j]
		values[j] = temp


@rpc("authority","call_local","reliable")
func _sync_state_skin_paths(paths:Array[String]) -> void:
	state_skin_paths = paths.duplicate()
	_apply_visual_for_state(ClownWeaponState.EMPTY)


func _skin_index_for_state(state_value:int,weapon_id:int = -1) -> int:
	match state_value:
		ClownWeaponState.EMPTY:
			return 0
		ClownWeaponState.ROLLING:
			return 1
		ClownWeaponState.ROLL_COMPLETE:
			return 2
		ClownWeaponState.ARMED:
			return 2
	return 0


func _expression_texture_for_state(state_value:int,weapon_id:int = -1) -> Texture2D:
	match state_value:
		ClownWeaponState.EMPTY:
			if clown_normal_texture != null:
				return clown_normal_texture
		ClownWeaponState.ROLLING:
			if clown_thinking_texture != null:
				return clown_thinking_texture
		ClownWeaponState.ROLL_COMPLETE,ClownWeaponState.ARMED:
			if weapon_id >= 0 and weapon_id < weapon_power.size():
				var power:int = weapon_power[weapon_id]
				if power >= 5 and clown_laugh_texture != null:
					return clown_laugh_texture
				if power <= 2 and clown_sad_texture != null:
					return clown_sad_texture
			if clown_normal_texture != null:
				return clown_normal_texture
	return null


func _weapon_pose_texture_for_id(weapon_id:int) -> Texture2D:
	match weapon_id:
		Weapon.BANANA_PEEL: return clown_banana_texture
		Weapon.CONFETTI_CANNON: return clown_confetti_texture
		Weapon.TOY_HAMMER: return clown_toy_hammer_texture
		Weapon.SNIPER_RIFLE: return clown_sniper_texture
		Weapon.ROCKET_LAUNCHER: return clown_rocket_texture
		Weapon.BLACK_HOLE_GUN: return clown_black_hole_texture
		Weapon.CHAIN_LIGHTNING: return clown_chain_lightning_texture
		Weapon.FREEZE_SPRAYER: return clown_freeze_texture
		Weapon.BOOMERANG: return clown_boomerang_texture
		Weapon.BROKEN_PISTOL: return clown_broken_pistol_texture
	return null


func _fallback_texture_from_skin_index(index:int) -> Texture2D:
	if index < 0 or index >= state_skin_paths.size():
		return null
	var path:String = state_skin_paths[index]
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _apply_visual_for_state(state_value:int,weapon_id:int = -1) -> void:
	if image == null:
		return

	var selected_texture:Texture2D = null

	# ROLL_COMPLETE 继续负责“强 -> 大笑 / 弱 -> 沮丧 / 普通 -> 正常”的反馈。
	# 真正进入 ARMED 后，整张 Graphics/Image 换成“小丑拿着当前武器”的合成图。
	if state_value == ClownWeaponState.ARMED and weapon_id >= 0 and weapon_id < Weapon.size():
		selected_texture = _weapon_pose_texture_for_id(weapon_id)

	if selected_texture == null:
		selected_texture = _expression_texture_for_state(state_value,weapon_id)

	if selected_texture == null:
		selected_texture = _fallback_texture_from_skin_index(
			_skin_index_for_state(state_value,weapon_id)
		)

	image.texture = selected_texture
	image.visible = selected_texture != null

	# 非持武器状态回到场景 Image 自己设置的基础角度。
	# 香蕉是地面陷阱，不瞄准敌人，人物图始终保持基础角度。
	if state_value != ClownWeaponState.ARMED:
		_weapon_aim_lock = false
		_weapon_return_to_base = false
		_weapon_aim_angular_velocity = 0.0
		_weapon_visual_facing_left = false
		set_character_visual_flip_h(false)
		image.rotation = _image_base_rotation
	elif weapon_id == Weapon.BANANA_PEEL:
		_weapon_aim_lock = false
		_weapon_return_to_base = false
		_weapon_aim_angular_velocity = 0.0
		_weapon_visual_facing_left = false
		set_character_visual_flip_h(false)
		image.rotation = _image_base_rotation


func tick_physics(state:State,delta:float) -> void:
	# 先让 ball 完成自己的移动、flip_h 和碰撞处理。
	super.tick_physics(state,delta)

	# 然后再覆盖人物朝向，避免 ball.move() 按移动方向 flip_h 后
	# 把“拿着武器”的整张图翻到错误方向。
	# 这里不再每帧硬设置 angle，而是用帧率无关插值平滑旋转。
	if image != null:
		if _weapon_aim_lock:
			_apply_weapon_aim_visual(_weapon_aim_direction,delta)
		elif _weapon_return_to_base:
			_spring_image_rotation_to(_image_base_rotation,weapon_return_smoothing,delta)
			if absf(wrapf(image.rotation - _image_base_rotation,-PI,PI)) < 0.01 and absf(_weapon_aim_angular_velocity) < 0.08:
				image.rotation = _image_base_rotation
				_weapon_aim_angular_velocity = 0.0
				_weapon_visual_facing_left = false
				set_character_visual_flip_h(false)
				_weapon_return_to_base = false


func Skill() -> void:
	super()

	if state_machine.current_state == State.Die:
		return
	if not is_multiplayer_authority():
		return
	if clown_weapon_state != ClownWeaponState.EMPTY:
		return

	Using_Skill = true
	await _roll_and_use_new_weapon()
	Using_Skill = false


func _roll_and_use_new_weapon() -> void:
	_set_clown_weapon_state(ClownWeaponState.ROLLING)

	var tick_count:int = maxi(roll_tick_count,1)
	var tick_delay:float = roll_duration / float(tick_count)

	for i:int in range(tick_count):
		if state_machine.current_state == State.Die:
			return

		var pitch:float = lerpf(0.84,1.28,float(i) / float(maxi(tick_count - 1,1)))
		_play_sfx_everywhere(rolling_tick_sfx,{"pitch":pitch},false,true)

		if multiplayer.has_multiplayer_peer():
			_rpc_roll_pulse.rpc(i)
		else:
			_rpc_roll_pulse(i)

		await get_tree().create_timer(tick_delay).timeout

	current_weapon = _roll_weapon()
	last_weapon = current_weapon

	_set_clown_weapon_state(ClownWeaponState.ROLL_COMPLETE,current_weapon)
	_play_sfx_everywhere(roll_complete_sfx,{},true,true)
	_show_weapon_result(current_weapon)

	await get_tree().create_timer(roll_complete_hold).timeout
	if state_machine.current_state == State.Die:
		return

	_set_clown_weapon_state(ClownWeaponState.ARMED,current_weapon)

	await get_tree().create_timer(armed_hold_before_use).timeout
	if state_machine.current_state == State.Die:
		return

	var target:ball = _return_target()
	await _execute_current_weapon(target)

	current_weapon = -1
	_set_clown_weapon_state(ClownWeaponState.EMPTY)


func _roll_weapon() -> int:
	if weapon_weights.is_empty():
		return rng.randi_range(0,Weapon.size() - 1)

	var result:int = rng.rand_weighted(weapon_weights)
	if result < 0 or result >= Weapon.size():
		result = rng.randi_range(0,Weapon.size() - 1)

	if prevent_same_weapon_twice and Weapon.size() > 1 and last_weapon >= 0:
		for _attempt:int in range(12):
			if result != last_weapon:
				break
			result = rng.rand_weighted(weapon_weights)
			if result < 0 or result >= Weapon.size():
				result = rng.randi_range(0,Weapon.size() - 1)

	return result


func _set_clown_weapon_state(new_state:int,weapon_id:int = -1) -> void:
	clown_weapon_state = new_state
	if multiplayer.has_multiplayer_peer():
		_rpc_apply_clown_state.rpc(new_state,weapon_id)
	else:
		_rpc_apply_clown_state(new_state,weapon_id)


@rpc("authority","call_local","reliable")
func _rpc_apply_clown_state(new_state:int,weapon_id:int) -> void:
	clown_weapon_state = new_state
	_apply_visual_for_state(clown_weapon_state,weapon_id)

	if result_label == null:
		return

	match clown_weapon_state:
		ClownWeaponState.EMPTY:
			result_label.visible = false
		ClownWeaponState.ROLLING:
			result_label.text = "???"
			result_label.visible = true
		ClownWeaponState.ROLL_COMPLETE:
			result_label.text = Game.t("抽到了！")
			result_label.visible = true
		ClownWeaponState.ARMED:
			if weapon_id >= 0 and weapon_id < weapon_names.size():
				result_label.text = weapon_names[weapon_id]
			result_label.visible = true


@rpc("authority","call_local","unreliable")
func _rpc_roll_pulse(step:int) -> void:
	if image == null:
		return

	# 随机脉冲也直接作用于现有 Image，并恢复到 Image 当前尺寸。
	# 没有额外的“小丑图片大小”配置。
	var base_scale:Vector2 = image.scale
	var tween:Tween = create_tween()
	tween.tween_property(image,"scale",base_scale * 1.18,0.04)
	tween.tween_property(image,"scale",base_scale,0.06)

	if result_label:
		var marks:Array[String] = ["?","??","???"]
		result_label.text = marks[step % marks.size()]


func _show_weapon_result(weapon_id:int) -> void:
	if weapon_id < 0 or weapon_id >= weapon_power.size():
		return

	var power:int = weapon_power[weapon_id]
	if power >= 5:
		_play_sfx_everywhere(strong_cheer_sfx,{},true,true)
		if multiplayer.has_multiplayer_peer():
			_rpc_spawn_confetti.rpc()
		else:
			_rpc_spawn_confetti()
	elif power <= 2:
		_play_sfx_everywhere(weak_sigh_sfx,{"pitch":0.80},false,true)
		if multiplayer.has_multiplayer_peer():
			_rpc_weak_result_wobble.rpc()
		else:
			_rpc_weak_result_wobble()


@rpc("authority","call_local","reliable")
func _rpc_spawn_confetti() -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return

	for _i:int in range(34):
		var piece:Polygon2D = Polygon2D.new()
		piece.polygon = PackedVector2Array([
			Vector2(-1.5,-3.5),
			Vector2(1.5,-3.5),
			Vector2(1.5,3.5),
			Vector2(-1.5,3.5),
		])
		piece.color = Color.from_hsv(randf(),0.82,1.0,1.0)
		piece.global_position = global_position
		piece.z_index = 20
		world.add_child(piece)

		var angle:float = randf_range(-PI,0.0)
		var distance:float = randf_range(55.0,135.0)
		var destination:Vector2 = global_position + Vector2.RIGHT.rotated(angle) * distance
		destination.y += randf_range(25.0,85.0)

		var tween:Tween = piece.create_tween()
		tween.set_parallel(true)
		tween.tween_property(piece,"global_position",destination,0.80)
		tween.tween_property(piece,"rotation",randf_range(-TAU * 2.0,TAU * 2.0),0.80)
		tween.tween_property(piece,"modulate",Color(1.0,1.0,1.0,0.0),0.80)
		tween.finished.connect(piece.queue_free)


@rpc("authority","call_local","reliable")
func _rpc_weak_result_wobble() -> void:
	if image == null:
		return

	var start_rotation:float = image.rotation
	var tween:Tween = create_tween()
	tween.tween_property(image,"rotation",start_rotation - 0.17,0.08)
	tween.tween_property(image,"rotation",start_rotation + 0.17,0.08)
	tween.tween_property(image,"rotation",start_rotation,0.12)


func _play_sfx_everywhere(sfx_name:String,params:Dictionary = {},randomize_sound:bool = false,create_new:bool = false) -> void:
	if sfx_name == "":
		return
	if Audios == null or Audios.Sfx == null or not Audios.Sfx.has_node(sfx_name):
		return

	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc(sfx_name,params,randomize_sound,create_new)
	else:
		Audios.play_sfx(sfx_name,params,randomize_sound,create_new)


func _return_target() -> ball:
	if is_instance_valid(Target_Enemy) and Target_Enemy is ball:
		return Target_Enemy as ball
	if is_instance_valid(Nearest_Enemy) and Nearest_Enemy is ball:
		return Nearest_Enemy as ball
	return null


func _aim_direction(target:ball) -> Vector2:
	if is_instance_valid(target):
		var delta_position:Vector2 = combat_target_position(target) - global_position
		if delta_position.length_squared() > 0.001:
			return delta_position.normalized()

	if direction.length_squared() > 0.001:
		return direction.normalized()
	return Vector2.RIGHT


func _apply_weapon_aim_visual(aim_dir:Vector2,delta:float) -> void:
	if image == null:
		return
	if aim_dir.length_squared() <= 0.001:
		return

	var normalized_dir:Vector2 = aim_dir.normalized()
	var facing_left:bool = normalized_dir.x < 0.0
	if facing_left != _weapon_visual_facing_left:
		_weapon_visual_facing_left = facing_left
		# 跨过左右半区时保留一点反向惯性，避免“啪”地硬切。
		_weapon_aim_angular_velocity *= -0.34

	# 不再让整张人物武器图旋转到 90°~270° 的倒立区间。
	# 左侧目标把角度折回 180°，再只做左右镜像：
	# 例如瞄准 160° -> 显示 -20° + 水平镜像。
	var display_angle:float = normalized_dir.angle()
	if facing_left:
		display_angle = wrapf(display_angle + PI,-PI,PI)
	var target_angle:float = _image_base_rotation + display_angle

	set_character_visual_flip_h(facing_left)
	_spring_image_rotation_to(target_angle,weapon_aim_smoothing,delta)


func _spring_image_rotation_to(target_angle:float,smoothing:float,delta:float) -> void:
	if image == null:
		return

	# 欠阻尼角度弹簧。相比普通 lerp 会轻微越过目标后回正，
	# 因而瞄准/回正都有可见但不夸张的“弹动”。
	var dt:float = maxf(delta,0.0)
	var stiffness:float = maxf(smoothing,1.0) * 7.0
	var damping:float = sqrt(stiffness) * 1.28
	var angle_error:float = wrapf(target_angle - image.rotation,-PI,PI)
	_weapon_aim_angular_velocity += angle_error * stiffness * dt
	_weapon_aim_angular_velocity *= exp(-damping * dt)
	_weapon_aim_angular_velocity = clampf(_weapon_aim_angular_velocity,-10.0,10.0)
	image.rotation = wrapf(image.rotation + _weapon_aim_angular_velocity * dt,-PI,PI)


# 保留旧函数名作为兼容入口，统一转到弹簧瞄准。
func _smooth_image_rotation_to(target_angle:float,smoothing:float,delta:float) -> void:
	_spring_image_rotation_to(target_angle,smoothing,delta)


func _weapon_prepare_duration(weapon_id:int) -> float:
	match weapon_id:
		Weapon.BANANA_PEEL: return banana_prepare_time
		Weapon.CONFETTI_CANNON: return confetti_prepare_time
		Weapon.TOY_HAMMER: return toy_hammer_prepare_time
		Weapon.SNIPER_RIFLE: return sniper_prepare_time
		Weapon.ROCKET_LAUNCHER: return rocket_prepare_time
		Weapon.BLACK_HOLE_GUN: return black_hole_prepare_time
		Weapon.CHAIN_LIGHTNING: return chain_lightning_prepare_time
		Weapon.FREEZE_SPRAYER: return freeze_prepare_time
		Weapon.BOOMERANG: return boomerang_prepare_time
		Weapon.BROKEN_PISTOL: return broken_pistol_prepare_time
	return 0.20


func _prepare_weapon_attack(target:ball,duration:float) -> ball:
	var live_target:ball = target
	var elapsed:float = 0.0
	var wait_time:float = maxf(duration,0.05)

	_weapon_aim_lock = true
	_weapon_return_to_base = false

	while elapsed < wait_time:
		if state_machine.current_state == State.Die:
			_weapon_aim_lock = false
			return null

		var refreshed_target:ball = _return_target()
		if is_instance_valid(refreshed_target):
			live_target = refreshed_target

		var aim_dir:Vector2 = _aim_direction(live_target)
		if aim_dir.length_squared() > 0.001:
			_weapon_aim_direction = aim_dir.normalized()

		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()

	return live_target


func _prepare_weapon_without_aim(duration:float) -> void:
	# 香蕉皮属于脚下陷阱：只保留出手前摇，不旋转人物去追踪敌人。
	_weapon_aim_lock = false
	_weapon_return_to_base = true
	var elapsed:float = 0.0
	var wait_time:float = maxf(duration,0.05)
	while elapsed < wait_time:
		if state_machine.current_state == State.Die:
			return
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()


func _release_weapon_aim_lock() -> void:
	_weapon_aim_lock = false
	_weapon_return_to_base = true


func _execute_current_weapon(target:ball) -> void:
	# 香蕉皮是脚下陷阱：有出手前摇，但不需要瞄准，也绝不旋转去追敌人。
	# 其他武器才持续重新获取目标并平滑转向。
	if current_weapon == Weapon.BANANA_PEEL:
		await _prepare_weapon_without_aim(_weapon_prepare_duration(current_weapon))
	else:
		target = await _prepare_weapon_attack(
			target,
			_weapon_prepare_duration(current_weapon)
		)

	if state_machine.current_state == State.Die:
		_release_weapon_aim_lock()
		return

	match current_weapon:
		Weapon.BANANA_PEEL:
			await _use_banana_peel(target)
		Weapon.CONFETTI_CANNON:
			await _use_confetti_cannon(target)
		Weapon.TOY_HAMMER:
			await _use_toy_hammer(target)
		Weapon.SNIPER_RIFLE:
			await _use_sniper_rifle(target)
		Weapon.ROCKET_LAUNCHER:
			await _use_rocket_launcher(target)
		Weapon.BLACK_HOLE_GUN:
			await _use_black_hole_gun(target)
		Weapon.CHAIN_LIGHTNING:
			await _use_chain_lightning(target)
		Weapon.FREEZE_SPRAYER:
			await _use_freeze_sprayer(target)
		Weapon.BOOMERANG:
			await _use_boomerang(target)
		Weapon.BROKEN_PISTOL:
			await _use_broken_pistol(target)

	_release_weapon_aim_lock()


func _texture_path_or_random(texture:Texture2D) -> String:
	if texture != null and texture.resource_path != "":
		return texture.resource_path
	return _random_projectile_skin()


# ========================================================
# 1. 香蕉皮
# 原地放置，延迟后生效；自己/队友/敌人都能踩。
# 踩中者沿“踩中瞬间的移动方向”快速滑行。
# 若途中撞墙/撞人：受伤 + 眩晕。
# ========================================================
func _use_banana_peel(_target:ball) -> void:
	var banana = CLOWN_AREA_OBJECT_SCENE.instantiate()
	banana.object_mode = 0 # BANANA
	banana.Master = self
	banana.Master_name = name
	banana.Team = Team
	banana.global_position = global_position
	banana.arm_delay = banana_arm_delay
	banana.life_time = banana_lifetime
	banana.texture_path = _texture_path_or_random(banana_peel_texture)
	_add_combat_node(banana)

	_play_sfx_everywhere("草放置",{"pitch":1.18},true,true)
	await get_tree().create_timer(0.14).timeout


# 被 banana area object 调用。
# V7：直接走 ball.apply_knockback() 通用接口。
# 香蕉只负责给通用击退系统提供“距离/速度/撞墙反弹/碰撞伤害/眩晕”等参数。
func _apply_banana_slip(target:ball) -> void:
	if not is_multiplayer_authority():
		return
	if not _is_live_real_ball(target):
		return

	var slide_dir:Vector2 = _current_motion_direction(target)
	if slide_dir.length_squared() <= 0.001:
		slide_dir = Vector2.RIGHT.rotated(rng.randf_range(0.0,TAU))

	# V7：香蕉不再依赖小丑专用 motion effect。
	# 所有 ball 现在都能直接使用通用 apply_knockback()。
	target.apply_knockback(
		slide_dir,
		banana_slide_distance,
		banana_slide_speed,
		banana_wall_bounce_strength,
		banana_crash_stun,
		{
			"source": self,
			"lock_control": true,
			"stun_only_on_collision": true,
			"collision_damage": attack_damage(banana_crash_damage_multiplier),
			"max_wall_bounces": 1,
			"stop_on_character": true,
			"character_bounce_strength": 0.0,
			"use_speed_falloff": false,
		}
	)


func _current_motion_direction(target:ball) -> Vector2:
	if target.velocity.length_squared() > 1.0:
		return target.velocity.normalized()
	if target.direction.length_squared() > 0.001:
		return target.direction.normalized()
	return Vector2.ZERO


# ========================================================
# 2. 彩带炮
# V9.4：真正的抛物线彩带。
# 每条彩带从炮口附近斜向喷出，叠加一个向上的初速度，
# 然后由屏幕向下重力持续加速；命中即消失，落下一段距离也会消失。
# ========================================================
func _use_confetti_cannon(target:ball) -> void:
	var base_dir:Vector2 = _aim_direction(target).normalized()
	if base_dir.length_squared() <= 0.001:
		base_dir = Vector2.RIGHT

	var side_dir:Vector2 = Vector2(-base_dir.y,base_dir.x)
	var count:int = maxi(confetti_piece_count,1)
	var spawn_origin:Vector2 = global_position + base_dir * 14.0
	var gravity_value:float = maxf(confetti_gravity,1.0)
	var gravity_vec:Vector2 = Vector2.DOWN * gravity_value
	var flight_min:float = maxf(minf(confetti_flight_time_min,confetti_flight_time_max),0.20)
	var flight_max:float = maxf(maxf(confetti_flight_time_min,confetti_flight_time_max),flight_min)

	for i:int in range(count):
		var lateral_offset:float = rng.randf_range(
			-maxf(confetti_spawn_lateral_spread,0.0),
			maxf(confetti_spawn_lateral_spread,0.0)
		)
		var piece_spawn:Vector2 = spawn_origin + side_dir * lateral_offset

		# 先选飞行时间，再由标准抛体公式反求 v0：
		# target = start + v0*t + 1/2*g*t^2
		# 这样每一条彩带都是真正的二次抛物线，而不是“朝敌人方向 + 固定向上速度”。
		var flight_time:float = rng.randf_range(flight_min,flight_max)

		# 如果目标在下方，过短的 t 会导致初速度也朝下，看起来不像抛射。
		# 根据希望的最小向上初速度，计算一个需要的最短飞行时间。
		var locked_target_position:Vector2 = combat_target_position(target)
		var dy:float = locked_target_position.y - piece_spawn.y
		var min_up:float = maxf(confetti_min_upward_speed,0.0)
		var discriminant:float = min_up * min_up + 2.0 * gravity_value * dy
		if discriminant >= 0.0:
			var required_time:float = (min_up + sqrt(discriminant)) / gravity_value
			flight_time = maxf(flight_time,required_time)

		# 少量预测只负责让移动目标不至于总从整束彩带下面/上面跑掉；
		# 仍然给每条彩带一个小的终点散布，保持“彩带炮”而不是精准狙击。
		var target_point:Vector2 = locked_target_position
		if target.velocity.length_squared() > 1.0:
			target_point += target.velocity * flight_time * clampf(confetti_target_prediction,0.0,1.0)
		target_point += side_dir * rng.randf_range(-maxf(confetti_target_spread,0.0),maxf(confetti_target_spread,0.0))

		var displacement:Vector2 = target_point - piece_spawn
		var launch_velocity:Vector2 = (
			displacement - gravity_vec * (0.5 * flight_time * flight_time)
		) / flight_time

		var piece = CLOWN_AREA_OBJECT_SCENE.instantiate()
		piece.object_mode = 1 # CONFETTI
		piece.Master = self
		piece.Master_name = name
		piece.Team = Team
		piece.global_position = piece_spawn
		piece.direction = launch_velocity.normalized()
		piece.initial_velocity = launch_velocity
		piece.projectile_gravity = gravity_value
		piece.minimum_flight_time = flight_time
		piece.fall_delete_distance = confetti_fall_delete_distance * rng.randf_range(0.90,1.12)
		var spin_sign:float = -1.0 if rng.randf() < 0.5 else 1.0
		piece.spin_speed = spin_sign * rng.randf_range(4.0,7.0)
		piece.life_time = maxf(
			confetti_lifetime * rng.randf_range(0.92,1.08),
			flight_time + 0.40
		)
		piece.damage_amount = attack_damage(confetti_damage_multiplier)
		piece.texture_path = _texture_path_or_random(confetti_piece_texture)
		_add_combat_node(piece)

	_play_sfx_everywhere("ButtonDown1",{"pitch":1.42,"volume":-5.0},true,true)
	await get_tree().create_timer(0.20).timeout


# ========================================================
# 3. 玩具锤
# 扔向敌人；命中后把敌人推开一点。
# 小丑自己同时受到相反方向后坐力。
# ========================================================
func _use_toy_hammer(target:ball) -> void:
	var dir:Vector2 = _aim_direction(target)
	var hammer = CLOWN_PROJECTILE_SCENE.instantiate()
	hammer.projectile_mode = 0 # HAMMER
	hammer.Master = self
	hammer.Master_name = name
	hammer.Team = Team
	hammer.global_position = global_position
	hammer.direction = dir
	hammer.Speed = toy_hammer_speed
	hammer.impact_damage = attack_damage(toy_hammer_damage_multiplier)
	hammer.impact_knockback_distance = toy_hammer_knockback_distance
	hammer.impact_knockback_speed = toy_hammer_knockback_speed
	hammer.impact_wall_bounce_strength = toy_hammer_wall_bounce_strength
	hammer.impact_stun_duration = toy_hammer_stun_duration
	hammer.projectile_skin_path = _texture_path_or_random(toy_hammer_projectile_texture)
	hammer.global_rotation = hammer.Default_Rotation + dir.angle()
	_add_combat_node(hammer)

	apply_knockback(
		-dir,
		toy_hammer_recoil_distance,
		toy_hammer_recoil_speed,
		0.0,
		0.0,
		{
			"source": self,
			"lock_control": false,
			"stop_on_character": false,
			"use_speed_falloff": true,
			"end_speed_ratio": 0.25,
		}
	)
	_play_sfx_everywhere("战士attack1",{"pitch":1.35},true,true)
	await get_tree().create_timer(0.16).timeout


# ========================================================
# 4. 狙击枪
# 先瞄准；瞄准过程不断根据敌人速度更新预判线。
# 开火时使用解析拦截预测，不只瞄准当前位置。
# 极高速子弹，高伤害，并直接穿过 block + Damage_reduction。
# ========================================================
func _use_sniper_rifle(target:ball) -> void:
	var old_speed:float = Speed
	Speed = default_properties.Speed * 0.30

	var elapsed:float = 0.0
	while elapsed < sniper_aim_duration:
		if state_machine.current_state == State.Die:
			Speed = old_speed
			_hide_sniper_aim_everywhere()
			return

		var live_target:ball = _return_target()
		if live_target == null:
			live_target = target

		var aim_dir:Vector2 = _predict_intercept_direction(live_target,sniper_bullet_speed)
		_weapon_aim_direction = aim_dir
		_show_sniper_aim_everywhere(global_position,global_position + aim_dir * sniper_range,true)

		await get_tree().create_timer(0.06).timeout
		elapsed += 0.06

	var final_target:ball = _return_target()
	if final_target == null:
		final_target = target

	var final_dir:Vector2 = _predict_intercept_direction(final_target,sniper_bullet_speed)
	_weapon_aim_direction = final_dir
	_hide_sniper_aim_everywhere()

	var bullet = CLOWN_PROJECTILE_SCENE.instantiate()
	bullet.projectile_mode = 1 # SNIPER
	bullet.Master = self
	bullet.Master_name = name
	bullet.Team = Team
	bullet.global_position = global_position
	bullet.direction = final_dir
	bullet.Speed = sniper_bullet_speed
	bullet.impact_damage = attack_damage(sniper_damage_multiplier)
	bullet.ignore_armor_on_hit = true
	bullet.projectile_skin_path = _texture_path_or_random(sniper_bullet_texture)
	bullet.global_rotation = bullet.Default_Rotation + final_dir.angle()
	_add_combat_node(bullet)

	_rpc_show_beam_everywhere(
		global_position,
		global_position + final_dir * sniper_range,
		3.0,
		Color(1.0,0.18,0.16,0.80),
		0.10
	)
	_play_sfx_everywhere("狙击枪发射",{"pitch":1.0,"volume":-2.0},false,true)
	_apply_motion_impulse(self,-final_dir * 180.0,0.10)
	Speed = old_speed
	await get_tree().create_timer(0.16).timeout


func _predict_intercept_direction(target:ball,projectile_speed:float) -> Vector2:
	if not is_instance_valid(target) or projectile_speed <= 1.0:
		return _aim_direction(target)

	var relative:Vector2 = combat_target_position(target) - global_position
	if relative.length_squared() <= 0.001:
		return _aim_direction(target)

	var target_velocity:Vector2 = combat_target_velocity(target)
	# 特殊锁定目标（例如极速者）的 lock velocity 可能故意很小；
	# 此时不要退回真实 direction * Speed，否则预测会重新“猜中”真实位置。
	var locked_position:Vector2 = combat_target_position(target)
	if target_velocity.length_squared() < 1.0 and locked_position.distance_to(target.global_position) <= 1.0:
		target_velocity = target.direction * maxf(target.Speed,0.0)

	var speed_sq:float = projectile_speed * projectile_speed
	var a:float = target_velocity.dot(target_velocity) - speed_sq
	var b:float = 2.0 * relative.dot(target_velocity)
	var c:float = relative.dot(relative)
	var intercept_time:float = -1.0

	if absf(a) < 0.0001:
		if absf(b) > 0.0001:
			var linear_time:float = -c / b
			if linear_time > 0.0:
				intercept_time = linear_time
	else:
		var discriminant:float = b * b - 4.0 * a * c
		if discriminant >= 0.0:
			var sqrt_disc:float = sqrt(discriminant)
			var t1:float = (-b - sqrt_disc) / (2.0 * a)
			var t2:float = (-b + sqrt_disc) / (2.0 * a)

			if t1 > 0.0 and t2 > 0.0:
				intercept_time = minf(t1,t2)
			elif t1 > 0.0:
				intercept_time = t1
			elif t2 > 0.0:
				intercept_time = t2

	if intercept_time < 0.0:
		intercept_time = relative.length() / projectile_speed

	intercept_time = clampf(intercept_time,0.0,sniper_max_predict_time)
	var predicted_position:Vector2 = combat_target_position(target) + target_velocity * intercept_time
	var predicted_dir:Vector2 = predicted_position - global_position
	if predicted_dir.length_squared() <= 0.001:
		return _aim_direction(target)
	return predicted_dir.normalized()


# ========================================================
# 5. 火箭筒
# 直射火箭；碰到敌人或墙就爆炸，范围高伤 + 击退。
# ========================================================
func _use_rocket_launcher(target:ball) -> void:
	var dir:Vector2 = _aim_direction(target)
	var rocket = CLOWN_PROJECTILE_SCENE.instantiate()
	rocket.projectile_mode = 2 # ROCKET
	rocket.Master = self
	rocket.Master_name = name
	rocket.Team = Team
	rocket.global_position = global_position
	rocket.direction = dir
	rocket.Speed = rocket_speed
	rocket.explosion_damage = attack_damage(rocket_damage_multiplier)
	rocket.explosion_radius = rocket_explosion_radius
	rocket.projectile_skin_path = _texture_path_or_random(rocket_projectile_texture)
	rocket.global_rotation = rocket.Default_Rotation + dir.angle()
	_add_combat_node(rocket)

	_play_sfx_everywhere("火箭筒发射",{"volume":-5.0,"pitch":1.0},false,true)
	apply_knockback(
		-dir,
		34.0,
		520.0,
		0.0,
		0.0,
		{
			"source": self,
			"lock_control": false,
			"stop_on_character": false,
			"use_speed_falloff": true,
			"end_speed_ratio": 0.25,
		}
	)
	await get_tree().create_timer(0.18).timeout


# ========================================================
# 6. 黑洞枪（强）
# 在目标方向一定距离生成黑洞；持续吸敌人，最后坍缩爆炸。
# ========================================================
func _use_black_hole_gun(target:ball) -> void:
	var aim_dir:Vector2 = _aim_direction(target)
	var center:Vector2 = global_position + aim_dir * minf(black_hole_cast_range,190.0)

	if is_instance_valid(target):
		var predicted:Vector2 = combat_target_position(target) + combat_target_velocity(target) * 0.24
		var offset:Vector2 = predicted - global_position
		if offset.length() > black_hole_cast_range:
			offset = offset.normalized() * black_hole_cast_range
		center = global_position + offset

	_black_hole_cast_serial += 1
	var cast_id:int = _black_hole_cast_serial

	# V9.2：旧版黑洞直接瞬移到落点，视觉上等同于“无限飞行速度”。
	# 现在先把一个黑洞核心从枪口飞到落点，到达后才正式开始吸引。
	var travel_distance:float = global_position.distance_to(center)
	var travel_duration:float = travel_distance / maxf(black_hole_projectile_speed,1.0)
	travel_duration = clampf(
		travel_duration,
		maxf(black_hole_projectile_min_travel_time,0.01),
		maxf(black_hole_projectile_max_travel_time,black_hole_projectile_min_travel_time)
	)
	_rpc_show_black_hole_projectile_everywhere(global_position,center,travel_duration)
	_play_sfx_everywhere("Blue",{"volume":-8.0,"pitch":0.72},false,true)
	await get_tree().create_timer(travel_duration).timeout
	if state_machine.current_state == State.Die:
		return

	_rpc_show_black_hole_everywhere(center,black_hole_duration)
	_play_sfx_everywhere("BlueLoop",{"volume":-7.0,"pitch":0.68},false,true)

	# 黑洞已经部署后就允许人物恢复普通朝向逻辑，
	# 不需要在黑洞持续的 1~2 秒内一直锁着人物旋转。
	_release_weapon_aim_lock()

	var elapsed:float = 0.0
	var tick_elapsed:float = black_hole_tick_interval
	while elapsed < black_hole_duration:
		if state_machine.current_state == State.Die:
			return

		var remaining:float = maxf(black_hole_duration - elapsed,0.08)
		for enemy:ball in _return_damageable_balls():
			var distance:float = enemy.global_position.distance_to(center)
			if distance > black_hole_radius:
				continue

			# 关键修复：不要在这里偶尔写一次 Repel。
			# ball.gd 每个物理帧末尾会清零 Repel，所以 V4 的写法经常完全看不到吸力。
			# 现在给目标自身挂一个持续物理子节点，它每个 physics frame 都补回吸力。
			_apply_black_hole_pull(
				enemy,
				center,
				black_hole_radius,
				black_hole_pull_speed,
				black_hole_edge_pull_ratio,
				remaining,
				cast_id
			)

		if tick_elapsed >= black_hole_tick_interval:
			tick_elapsed = 0.0
			for enemy:ball in _return_damageable_balls():
				if enemy.global_position.distance_to(center) <= black_hole_radius:
					_clown_damage_target(
						enemy,
						attack_damage(black_hole_tick_damage_multiplier),
						Vector2.ZERO,
						false,
						true,
						{"shape":"circle","center":center,"radius":black_hole_radius,"source":self}
					)

		await get_tree().physics_frame
		var step:float = get_physics_process_delta_time()
		elapsed += step
		tick_elapsed += step

	_rpc_show_explosion_everywhere(center,black_hole_final_radius,Color(0.36,0.08,0.70,0.95))
	for enemy:ball in _return_damageable_balls():
		var distance:float = enemy.global_position.distance_to(center)
		if distance <= black_hole_final_radius:
			var repel_dir:Vector2 = enemy.global_position - center
			if repel_dir.length_squared() <= 0.001:
				repel_dir = Vector2.RIGHT.rotated(rng.randf_range(0.0,TAU))
			else:
				repel_dir = repel_dir.normalized()
			_clown_damage_target(
				enemy,
				attack_damage(black_hole_final_damage_multiplier),
				Vector2.ZERO,
				false,
				true,
				{"shape":"circle","center":center,"radius":black_hole_final_radius,"source":self}
			)
			enemy.apply_knockback(
				repel_dir,
				black_hole_final_knockback_distance,
				black_hole_final_knockback_speed,
				black_hole_final_wall_bounce_strength,
				black_hole_final_stun_duration,
				{
					"source": self,
					"lock_control": true,
					"max_wall_bounces": 2,
					"stop_on_character": true,
				}
			)

	_play_sfx_everywhere("explosion1",{"pitch":0.66},true,true)
	await get_tree().create_timer(0.14).timeout


# ========================================================
# 7. 连锁闪电枪（强）
# 第一个目标伤害最高，随后自动寻找附近未命中的敌人继续跳跃。
# ========================================================
func _use_chain_lightning(target:ball) -> void:
	var first:ball = target
	if not _can_damage_ball(first):
		first = _find_nearest_damageable(global_position,INF,{})
	if first == null:
		await get_tree().create_timer(0.10).timeout
		return

	var visited:Dictionary = {}
	var current:ball = first
	var start_point:Vector2 = global_position
	var max_targets:int = maxi(chain_lightning_targets,1)

	for index:int in range(max_targets):
		if current == null or not _can_damage_ball(current):
			break

		visited[current.get_instance_id()] = true
		var damage_multiplier:float = chain_lightning_first_damage_multiplier * pow(chain_lightning_decay,index)
		var hit_direction:Vector2 = current.global_position - start_point
		if hit_direction.length_squared() <= 0.001:
			hit_direction = Vector2.RIGHT
		else:
			hit_direction = hit_direction.normalized()

		_rpc_show_beam_everywhere(
			start_point,
			current.global_position,
			8.0,
			Color(0.45,0.85,1.0,0.95),
			0.16
		)
		_clown_damage_target(
			current,
			attack_damage(damage_multiplier),
			hit_direction * 110.0,
			false,
			true,
			{"shape":"capsule","from":start_point,"to":current.global_position,"half_width":4.0,"source":self}
		)

		if chain_lightning_stun > 0.0:
			_stun_ball(current,chain_lightning_stun)

		start_point = current.global_position
		current = _find_nearest_damageable(start_point,chain_lightning_range,visited)

	_play_sfx_everywhere("Mc锻造",{"pitch":1.65,"volume":-3.0},true,true)
	await get_tree().create_timer(0.20).timeout


func _find_nearest_damageable(from_position:Vector2,max_range:float,visited:Dictionary) -> ball:
	var nearest:ball = null
	var nearest_distance:float = max_range

	for candidate:ball in _return_damageable_balls():
		if visited.has(candidate.get_instance_id()):
			continue
		var distance:float = candidate.global_position.distance_to(from_position)
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest = candidate

	return nearest


# ========================================================
# 8. 冰冻喷雾器（正常）
# 短距离扇形；低中伤，显著减速一段时间。
# ========================================================
func _use_freeze_sprayer(target:ball) -> void:
	var aim_dir:Vector2 = _aim_direction(target)
	var cos_limit:float = cos(deg_to_rad(freeze_half_angle_degrees))

	_rpc_show_cone_everywhere(
		global_position,
		aim_dir,
		freeze_range,
		freeze_half_angle_degrees,
		Color(0.50,0.90,1.0,0.45)
	)
	_play_sfx_everywhere("Blue",{"pitch":1.12,"volume":-5.0},true,true)

	var world = get_tree().current_scene
	for enemy:ball in _return_damageable_balls():
		var offset:Vector2 = enemy.global_position - global_position
		var distance:float = offset.length()
		if distance <= 0.001 or distance > freeze_range:
			continue
		if aim_dir.dot(offset.normalized()) < cos_limit:
			continue

		_clown_damage_target(
			enemy,
			attack_damage(freeze_damage_multiplier),
			aim_dir * 55.0,
			false,
			true,
			{
				"shape":"sector",
				"origin":global_position,
				"direction":aim_dir,
				"radius":freeze_range,
				"half_angle_degrees":freeze_half_angle_degrees,
				"source":self
			}
		)

		if world != null and world.has_method("new_buff"):
			world.new_buff(
				enemy,
				self,
				"小丑_冰冻喷雾",
				Buff.new(
					1,
					freeze_duration,
					Buff.Buff_types.Speed,
					freeze_speed_multiplier,
					Buff.Algorithms.mul
				),
				"cover"
			)

	await get_tree().create_timer(0.24).timeout


# ========================================================
# 9. 回旋镖（正常）
# 飞出后自动返回；命中后会反弹，并按短冷却允许再次伤害同一个敌人。
# ========================================================
func _use_boomerang(target:ball) -> void:
	var dir:Vector2 = _aim_direction(target)
	var boomerang = CLOWN_PROJECTILE_SCENE.instantiate()
	boomerang.projectile_mode = 3 # BOOMERANG
	boomerang.Master = self
	boomerang.Master_name = name
	boomerang.Team = Team
	boomerang.global_position = global_position
	boomerang.direction = dir
	boomerang.Speed = boomerang_speed
	boomerang.impact_damage = attack_damage(boomerang_damage_multiplier)
	boomerang.impact_knockback_distance = boomerang_knockback_distance
	boomerang.impact_knockback_speed = boomerang_knockback_speed
	boomerang.impact_wall_bounce_strength = boomerang_wall_bounce_strength
	boomerang.impact_stun_duration = 0.0
	boomerang.boomerang_distance = boomerang_distance
	boomerang.boomerang_same_target_cooldown = boomerang_same_target_cooldown
	boomerang.boomerang_sweep_radius = boomerang_sweep_radius
	boomerang.projectile_skin_path = _texture_path_or_random(boomerang_projectile_texture)
	boomerang.global_rotation = boomerang.Default_Rotation + dir.angle()
	_add_combat_node(boomerang)

	_play_sfx_everywhere("KnifeThrow1",{"pitch":0.88},true,true)
	await get_tree().create_timer(0.16).timeout


# ========================================================
# 10. 坏掉的手枪（垃圾）
# 42% 卡壳；12% 炸膛伤自己；其余概率发射一枚仍然不太靠谱、但看得见的弱弹。
# ========================================================
func _use_broken_pistol(target:ball) -> void:
	var roll:float = rng.randf()

	if roll < broken_pistol_jam_chance:
		_play_sfx_everywhere("ButtonDown1",{"pitch":0.52,"volume":-3.0},false,true)
		await get_tree().create_timer(0.30).timeout
		return

	if roll < broken_pistol_jam_chance + broken_pistol_backfire_chance:
		_damage_ball_without_team_filter(
			self,
			attack_damage(0.65),
			false
		)
		apply_knockback(
			Vector2.RIGHT.rotated(rng.randf_range(0.0,TAU)),
			52.0,
			580.0,
			0.35,
			0.10,
			{
				"source": self,
				"lock_control": true,
				"max_wall_bounces": 1,
				"stop_on_character": true,
			}
		)
		_rpc_show_explosion_everywhere(global_position,38.0,Color(1.0,0.55,0.18,0.85))
		_play_sfx_everywhere("explosion1",{"pitch":1.65,"volume":-8.0},true,true)
		await get_tree().create_timer(0.30).timeout
		return

	var dir:Vector2 = _aim_direction(target)
	dir = dir.rotated(deg_to_rad(rng.randf_range(-48.0,48.0)))
	_spawn_basic_projectile(
		dir,
		attack_damage(broken_pistol_damage_multiplier),
		520.0,
		broken_pistol_bullet_visual_size,
		broken_pistol_bullet_texture
	)
	_play_sfx_everywhere("G18单发",{"pitch":1.65,"volume":-8.0},true,true)
	await get_tree().create_timer(0.20).timeout


func _fit_sprite_to_size(sprite:Sprite2D,target_size:float) -> void:
	# 仅用于临时子弹/投射物旧图适配。
	# 小丑人物 Graphics/Image 本身绝不会经过这个函数缩放。
	if sprite == null or sprite.texture == null:
		return

	var size:Vector2 = sprite.texture.get_size()
	var max_side:float = maxf(size.x,size.y)
	if max_side <= 0.0:
		return

	var scale_value:float = target_size / max_side
	sprite.scale = Vector2.ONE * scale_value


func _spawn_basic_projectile(
	dir:Vector2,
	damage_amount:float,
	speed_amount:float,
	visual_size:float,
	custom_texture:Texture2D = null
) -> ball:
	var projectile:ball = BASIC_BULLET_SCENE.instantiate()
	projectile.Master = self
	projectile.Master_name = name
	projectile.Team = Team
	projectile.Damage = maxi(int(round(damage_amount)),1)
	projectile.Speed = speed_amount
	projectile.global_position = global_position
	projectile.direction = dir.normalized()
	projectile.global_rotation = projectile.Default_Rotation + projectile.direction.angle()

	var skin_path:String = _texture_path_or_random(custom_texture)
	var sprite:Sprite2D = projectile.get_node_or_null("Graphics/Image") as Sprite2D
	if sprite != null and skin_path != "" and ResourceLoader.exists(skin_path):
		sprite.texture = load(skin_path)
		_fit_sprite_to_size(sprite,visual_size)

	_add_combat_node(projectile)
	if is_instance_valid(projectile) and projectile is PhysicsBody2D:
		(projectile as PhysicsBody2D).add_collision_exception_with(self)
	return projectile


func _random_projectile_skin() -> String:
	if available_texture_pool.is_empty():
		return ""

	var result:String = available_texture_pool[rng.randi_range(0,available_texture_pool.size() - 1)]
	if available_texture_pool.size() > 1:
		for _attempt:int in range(8):
			if result != last_projectile_skin:
				break
			result = available_texture_pool[rng.randi_range(0,available_texture_pool.size() - 1)]

	last_projectile_skin = result
	return result


func _add_combat_node(node:Node) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		node.queue_free()
		return

	node.name = Game.return_random_name(node)
	world.add_child(node,true)


func _return_damageable_balls() -> Array[ball]:
	var result:Array[ball] = []
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if _can_damage_ball(target):
			result.append(target)
	return result


func _is_live_real_ball(target:ball) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not target.is_combat_targetable():
		return false
	if target.health <= 0:
		return false
	if target.state_machine and target.state_machine.current_state == State.Die:
		return false
	return true


func _can_damage_ball(target:ball) -> bool:
	if not _is_live_real_ball(target):
		return false
	if target == self:
		return false

	if (
		Team != ""
		and Team == target.Team
		and not Game.Game_Settings.Have_Team_Damage
		and not Ignore_Team_Damage_Setting
	):
		return false

	return true


# 给 clown_projectile.gd / clown_area_object.gd 调用。
# ignore_armor=true：直接扣 health，无视 block 与 Damage_reduction。
func _clown_damage_target(
	target:ball,
	amount:float,
	repel_force:Vector2 = Vector2.ZERO,
	ignore_armor:bool = false,
	play_default_hit_audio:bool = true,
	damage_space:Variant = null
) -> void:
	if not is_multiplayer_authority():
		return
	if not _can_damage_ball(target):
		return

	# 小丑有很多不经过通用 Hitbox 的武器。必须把真实攻击覆盖区域交给目标，
	# 否则决斗者只能看到“要扣血”却不知道这次攻击是否真的覆盖破绽。
	var resolved_space:Variant = damage_space
	if resolved_space == null:
		resolved_space = {"shape":"point","point":target.global_position,"source":self}
	target.receive_spatial_damage(amount,resolved_space,ignore_armor,ignore_armor)

	var feedback_dir:Vector2 = repel_force
	if feedback_dir.length_squared() <= 0.001:
		feedback_dir = target.global_position - global_position
	_trigger_clown_hit_feedback(target,amount,feedback_dir,play_default_hit_audio)

	if repel_force.length_squared() > 0.001:
		_apply_motion_impulse(target,repel_force,0.16)

	var world = get_tree().current_scene
	if world != null and world.get("camera_shake_amount") != null:
		world.camera_shake_amount += minf(amount,80.0)


# 香蕉/炸膛使用：不做敌我过滤，允许自己和队友受伤。
func _damage_ball_without_team_filter(target:ball,amount:float,ignore_armor:bool) -> void:
	if not is_multiplayer_authority():
		return
	if not _is_live_real_ball(target):
		return

	target.receive_spatial_damage(
		amount,
		{"shape":"all","source":self},
		ignore_armor,
		ignore_armor
	)

	var feedback_dir:Vector2 = target.global_position - global_position
	_trigger_clown_hit_feedback(target,amount,feedback_dir)


func _trigger_clown_hit_feedback(target:ball,amount:float,hit_direction:Vector2,play_hit_audio:bool = true) -> void:
	if not clown_hit_feedback_enabled:
		return
	if target == null or not is_instance_valid(target):
		return

	var direction_value:Vector2 = hit_direction
	if direction_value.length_squared() <= 0.001:
		direction_value = Vector2.RIGHT
	else:
		direction_value = direction_value.normalized()

	# hit_white 在有护盾/格挡时可能直接 return；这里额外做一次轻微挤压，
	# 保证“命中了”在任何武器上都有肉眼可见的反馈。
	if target.has_method("Figure_collide_transform"):
		var feedback_power:float = clampf(
			maxf(amount,1.0) * 10.0,
			clown_hit_feedback_min_power,
			clown_hit_feedback_max_power
		)
		target.call("Figure_collide_transform",direction_value,feedback_power)

	# 高频持续伤害（黑洞 tick / 多条彩带）不应该每次都生成网络特效和声音。
	var target_id:int = target.get_instance_id()
	var now_sec:float = Time.get_ticks_msec() / 1000.0
	var last_time:float = float(_clown_hit_feedback_times.get(target_id,-9999.0))
	if now_sec - last_time < clown_hit_feedback_cooldown:
		return
	_clown_hit_feedback_times[target_id] = now_sec

	var spark_radius:float = clampf(8.0 + sqrt(maxf(amount,0.0)) * 2.1,9.0,20.0)
	_rpc_show_hit_spark_everywhere(target.global_position,spark_radius)

	# 普通武器沿用小丑本身配置的 Hit_Audio；枪械子弹可关闭它，改播专用命中音。
	if play_hit_audio and Hit_Audio != "":
		_play_sfx_everywhere(
			Hit_Audio,
			{
				"volume": clampf(amount - 18.0,-18.0,-2.0),
				"pitch": rng.randf_range(0.94,1.06),
			},
			true,
			true
		)


func _apply_motion_impulse(target:ball,force:Vector2,duration:float = 0.16) -> void:
	# 兼容旧的小丑调用：内部已经转为通用 ball.apply_knockback()。
	# 新代码应优先直接传 distance / speed / wall_bounce / stun。
	if not is_multiplayer_authority():
		return
	if not _is_live_real_ball(target):
		return
	if force.length_squared() <= 0.001 or duration <= 0.0:
		return

	var legacy_speed:float = force.length()
	# 旧效果是衰减速度，这里用约 62% 的面积换算成路径距离。
	var estimated_distance:float = legacy_speed * duration * 0.62
	target.apply_knockback(
		force.normalized(),
		estimated_distance,
		legacy_speed,
		0.0,
		0.0,
		{
			"source": self,
			"lock_control": false,
			"stop_on_character": true,
			"use_speed_falloff": true,
			"end_speed_ratio": 0.22,
		}
	)


func _apply_black_hole_pull(
	target:ball,
	center:Vector2,
	radius:float,
	pull_speed:float,
	edge_ratio:float,
	duration:float,
	cast_id:int
) -> void:
	if not is_multiplayer_authority():
		return
	if not _is_live_real_ball(target):
		return

	var effect_name:String = "ClownBlackHolePull_%d_%d" % [get_instance_id(),cast_id]
	var existing:Node = target.get_node_or_null(NodePath(effect_name))
	if existing != null:
		existing.set("target_point",center)
		existing.set("pull_radius",radius)
		existing.set("motion_speed",pull_speed)
		existing.set("pull_edge_ratio",edge_ratio)
		existing.set("duration",maxf(duration,0.08))
		existing.set("_elapsed",0.0)
		return

	var effect = CLOWN_MOTION_EFFECT.new()
	effect.name = effect_name
	effect.target = target
	effect.target_point = center
	effect.pull_radius = radius
	effect.motion_speed = pull_speed
	effect.pull_edge_ratio = edge_ratio
	effect.duration = maxf(duration,0.08)
	target.add_child(effect)


func _stun_ball(target:ball,duration:float) -> void:
	if not is_multiplayer_authority():
		return
	if not _is_live_real_ball(target):
		return
	target.apply_stun(duration)


# 火箭调用。
func _clown_explosion(
	position_value:Vector2,
	radius:float,
	damage_amount:float
) -> void:
	if not is_multiplayer_authority():
		return

	_rpc_show_explosion_everywhere(position_value,radius,Color(1.0,0.48,0.12,0.95))
	_play_sfx_everywhere("火箭筒爆炸",{"volume":-2.0,"pitch":1.0},false,true)

	for target:ball in _return_damageable_balls():
		var distance:float = position_value.distance_to(target.global_position)
		if distance > radius:
			continue

		var falloff:float = lerpf(1.0,0.58,clampf(distance / maxf(radius,1.0),0.0,1.0))
		var repel_dir:Vector2 = target.global_position - position_value
		if repel_dir.length_squared() <= 0.001:
			repel_dir = Vector2.RIGHT.rotated(rng.randf_range(0.0,TAU))
		else:
			repel_dir = repel_dir.normalized()

		_clown_damage_target(
			target,
			damage_amount * falloff,
			Vector2.ZERO,
			false,
			true,
			{"shape":"circle","center":position_value,"radius":radius,"source":self}
		)

		target.apply_knockback(
			repel_dir,
			rocket_explosion_knockback_distance * falloff,
			rocket_explosion_knockback_speed * lerpf(0.72,1.0,falloff),
			rocket_explosion_wall_bounce_strength,
			rocket_explosion_stun_duration,
			{
				"source": self,
				"lock_control": true,
				"max_wall_bounces": 2,
				"stop_on_character": true,
			}
		)


func _show_sniper_aim_everywhere(start:Vector2,finish:Vector2,is_visible:bool) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_update_sniper_aim.rpc(start,finish,is_visible)
	else:
		_rpc_update_sniper_aim(start,finish,is_visible)


func _hide_sniper_aim_everywhere() -> void:
	_show_sniper_aim_everywhere(Vector2.ZERO,Vector2.ZERO,false)


@rpc("authority","call_local","unreliable")
func _rpc_update_sniper_aim(start:Vector2,finish:Vector2,is_visible:bool) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return

	if sniper_aim_line == null or not is_instance_valid(sniper_aim_line):
		sniper_aim_line = Line2D.new()
		sniper_aim_line.name = "ClownSniperAim"
		sniper_aim_line.width = 2.0
		sniper_aim_line.default_color = Color(1.0,0.08,0.08,0.48)
		sniper_aim_line.z_index = 18
		world.add_child(sniper_aim_line)

	sniper_aim_line.visible = is_visible
	if not is_visible:
		return

	sniper_aim_line.clear_points()
	sniper_aim_line.add_point(start)
	sniper_aim_line.add_point(finish)


func _rpc_show_explosion_everywhere(position_value:Vector2,radius:float,color:Color) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_show_explosion.rpc(position_value,radius,color)
	else:
		_rpc_show_explosion(position_value,radius,color)


@rpc("authority","call_local","reliable")
func _rpc_show_explosion(position_value:Vector2,radius:float,color:Color) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return

	var ring:Polygon2D = Polygon2D.new()
	var points:PackedVector2Array = PackedVector2Array()
	var segments:int = 30
	for i:int in range(segments):
		var angle:float = TAU * float(i) / float(segments)
		points.append(Vector2.RIGHT.rotated(angle) * 8.0)

	ring.polygon = points
	ring.color = color
	ring.global_position = position_value
	ring.z_index = 18
	world.add_child(ring)

	var scale_target:float = maxf(radius / 8.0,1.0)
	var tween:Tween = ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring,"scale",Vector2.ONE * scale_target,0.28)
	tween.tween_property(ring,"modulate",Color(1.0,1.0,1.0,0.0),0.32)
	tween.finished.connect(ring.queue_free)


func _rpc_show_beam_everywhere(
	start:Vector2,
	finish:Vector2,
	width:float,
	color:Color = Color(0.92,0.98,1.0,0.92),
	duration:float = 0.16
) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_show_beam.rpc(start,finish,width,color,duration)
	else:
		_rpc_show_beam(start,finish,width,color,duration)


@rpc("authority","call_local","reliable")
func _rpc_show_beam(start:Vector2,finish:Vector2,width:float,color:Color,duration:float) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return

	var line:Line2D = Line2D.new()
	line.add_point(start)
	line.add_point(finish)
	line.width = width
	line.default_color = color
	line.z_index = 19
	world.add_child(line)

	var tween:Tween = line.create_tween()
	tween.tween_property(line,"modulate",Color(1.0,1.0,1.0,0.0),duration)
	tween.finished.connect(line.queue_free)


func _rpc_show_hit_spark_everywhere(position_value:Vector2,radius:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_show_hit_spark.rpc(position_value,radius)
	else:
		_rpc_show_hit_spark(position_value,radius)


@rpc("authority","call_local","unreliable")
func _rpc_show_hit_spark(position_value:Vector2,radius:float) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return

	# 12 个交替长短半径的点组成一个小型命中闪光。
	var spark:Polygon2D = Polygon2D.new()
	var points:PackedVector2Array = PackedVector2Array()
	for i:int in range(12):
		var angle:float = TAU * float(i) / 12.0
		var point_radius:float = radius if i % 2 == 0 else radius * 0.42
		points.append(Vector2.RIGHT.rotated(angle) * point_radius)
	spark.polygon = points
	spark.color = Color(1.0,0.86,0.18,0.96)
	spark.global_position = position_value
	spark.z_index = 25
	world.add_child(spark)

	var tween:Tween = spark.create_tween()
	tween.set_parallel(true)
	tween.tween_property(spark,"scale",Vector2.ONE * 1.55,0.11)
	tween.tween_property(spark,"modulate",Color(1.0,1.0,1.0,0.0),0.13)
	tween.finished.connect(spark.queue_free)


func _rpc_show_black_hole_projectile_everywhere(start:Vector2,finish:Vector2,duration:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_show_black_hole_projectile.rpc(start,finish,duration)
	else:
		_rpc_show_black_hole_projectile(start,finish,duration)


@rpc("authority","call_local","reliable")
func _rpc_show_black_hole_projectile(start:Vector2,finish:Vector2,duration:float) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return

	var orb:Polygon2D = Polygon2D.new()
	var points:PackedVector2Array = PackedVector2Array()
	var segments:int = 20
	for i:int in range(segments):
		var angle:float = TAU * float(i) / float(segments)
		points.append(Vector2.RIGHT.rotated(angle) * 12.0)
	orb.polygon = points
	orb.color = Color(0.24,0.03,0.38,0.98)
	orb.global_position = start
	orb.z_index = 22
	world.add_child(orb)

	var tween:Tween = orb.create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(orb,"global_position",finish,maxf(duration,0.01))
	tween.tween_property(orb,"rotation",TAU * 2.0,maxf(duration,0.01))
	tween.tween_property(orb,"scale",Vector2.ONE * 1.30,maxf(duration,0.01))
	tween.finished.connect(orb.queue_free)


func _rpc_show_black_hole_everywhere(center:Vector2,duration:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_show_black_hole.rpc(center,duration)
	else:
		_rpc_show_black_hole(center,duration)


@rpc("authority","call_local","reliable")
func _rpc_show_black_hole(center:Vector2,duration:float) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return

	var hole:Polygon2D = Polygon2D.new()
	var points:PackedVector2Array = PackedVector2Array()
	var segments:int = 30
	for i:int in range(segments):
		var angle:float = TAU * float(i) / float(segments)
		points.append(Vector2.RIGHT.rotated(angle) * 19.0)

	hole.polygon = points
	hole.color = Color(0.10,0.02,0.17,0.96)
	hole.global_position = center
	hole.z_index = 17
	world.add_child(hole)

	var tween:Tween = hole.create_tween()
	tween.set_loops(maxi(int(duration / 0.32),1))
	tween.tween_property(hole,"rotation",hole.rotation + PI,0.16)
	tween.tween_property(hole,"rotation",hole.rotation + TAU,0.16)

	get_tree().create_timer(duration).timeout.connect(func():
		if is_instance_valid(hole):
			hole.queue_free()
	)


func _rpc_show_cone_everywhere(
	origin:Vector2,
	dir:Vector2,
	range_value:float,
	half_angle_degrees:float,
	color:Color
) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_show_cone.rpc(origin,dir,range_value,half_angle_degrees,color)
	else:
		_rpc_show_cone(origin,dir,range_value,half_angle_degrees,color)


@rpc("authority","call_local","reliable")
func _rpc_show_cone(
	origin:Vector2,
	dir:Vector2,
	range_value:float,
	half_angle_degrees:float,
	color:Color
) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return

	var cone:Polygon2D = Polygon2D.new()
	var points:PackedVector2Array = PackedVector2Array([Vector2.ZERO])
	var half_angle:float = deg_to_rad(half_angle_degrees)
	var base_angle:float = dir.angle()
	var segments:int = 14

	for i:int in range(segments + 1):
		var t:float = float(i) / float(segments)
		var angle:float = lerpf(base_angle - half_angle,base_angle + half_angle,t)
		points.append(Vector2.RIGHT.rotated(angle) * range_value)

	cone.polygon = points
	cone.color = color
	cone.global_position = origin
	cone.z_index = 15
	world.add_child(cone)

	var tween:Tween = cone.create_tween()
	tween.tween_property(cone,"modulate",Color(1.0,1.0,1.0,0.0),0.28)
	tween.finished.connect(cone.queue_free)


func Die() -> void:
	super()

	_weapon_aim_lock = false

	if image:
		image.visible = false
	if result_label:
		result_label.visible = false
	if sniper_aim_line and is_instance_valid(sniper_aim_line):
		sniper_aim_line.queue_free()

	await get_tree().create_timer(2.0).timeout
	Game.free_node(self)
