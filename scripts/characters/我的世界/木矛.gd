extends ball
# 当前规则：起手前原移动路径可命中的是顺向被动穿刺，否则是转向主动穿刺。
# 两者触发时获得短暂可超上限的爆发，被动更强且2倍伤害。
# 穿出后平滑扣除爆发前蓄速的50%/75%，不继续归零到基础速度。
# 普通低速刺、速度伤害、矛头格挡保留；历史版本规则不再作为当前说明。

const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const WOODEN_SPEAR_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/木矛/木矛.png")
const ATTACK_SFX:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/木矛/attack1.ogg"),
	preload("res://audio/characters/我的世界/木矛/attack2.ogg"),
	preload("res://audio/characters/我的世界/木矛/attack3.ogg"),
]
const HIT_SFX:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/木矛/hit1.ogg"),
	preload("res://audio/characters/我的世界/木矛/hit2.ogg"),
	preload("res://audio/characters/我的世界/木矛/hit3.ogg"),
]
const USE_SFX:AudioStream = preload("res://audio/characters/我的世界/木矛/use.ogg")
const BLOCK_SFX:AudioStream = preload("res://audio/sfx/防御/BlockAtt.ogg")

@export_category("木矛 / 碰撞与朝向")
@export_range(-180.0,180.0,1.0) var visual_rotation_offset_degrees:float = 135.0
# 以下位置/尺寸是场景局部单位；真正攻击距离计算会读取 global_transform，转换为世界尺寸，避免根节点 0.2 缩放造成距离错判。
@export_range(20.0,90.0,1.0) var spear_tip_local_distance:float = 63.0
@export var spear_tip_local_size:Vector2 = Vector2(24.0,16.0)
@export_range(-30.0,30.0,0.5) var shaft_local_center_offset:float = -5.0
@export var shaft_local_size:Vector2 = Vector2(112.0,14.0)
@export var body_collision_local_size:Vector2 = Vector2(108.0,10.0)

@export_category("木矛 / 移动蓄速")
# 场景 Speed 是固定基础/出生/眩晕重置速度；开局随机的是移动方向，不是移速。
@export_range(20.0,800.0,5.0) var max_move_speed:float = 420.0
@export_range(0.0,160.0,1.0) var move_acceleration_per_second:float = 26.0
# 仅非穿刺成功命中加速；顺向命中更多，不突破日常上限。
@export_range(0.0,40.0,1.0) var normal_hit_speed_gain:float = 8.0
@export_range(0.0,60.0,1.0) var straight_hit_speed_gain:float = 14.0
@export_range(0.0,0.25,0.01) var obstacle_bonus_speed_loss_ratio:float = 0.05
var _last_obstacle_slowdown_msec:int = -1000000
# 穿越完成后用这段时间平滑扣除蓄速；目标是保留剩余蓄速，而非回到基础速度。
@export_range(0.10,2.0,0.05) var pass_speed_recovery_time:float = 0.65
# 顺向被动穿刺的蓄速损失比例（变量名保留兼容；现在平滑扣除，不再瞬间扣速）。
@export_range(0.0,0.95,0.01) var passive_pass_immediate_bonus_speed_loss_ratio:float = 0.75

@export_category("木矛 / 击退抗性")
# 木矛不接受通用 Repel 位移；击退只削减它自己的移动动量。
# knockback_speed 视作“击退力度”：力度超过当前移速时才会把移动方向压到击退方向。
# 小幅减轻受击动量损失；强击退改向、零速击退和低速恢复规则保持不变。
@export_range(0.0,1.0,0.01) var knockback_slowdown_ratio:float = 0.11
# V122：击退可以把木矛自身移动速度真正削到 0；两个最低速度保护默认关闭，仅保留为可调兼容参数。
@export_range(0.0,1.0,0.01) var knockback_overpower_min_speed_ratio:float = 0.0
@export_range(0.0,1.0,0.01) var knockback_weak_min_speed_ratio:float = 0.0
# 低于基础速度后先短暂停顿，再快速回到基础 Speed；期间不走普通“移动越久越快”的蓄速。
@export_range(0.0,1.0,0.01) var knockback_low_speed_recovery_delay:float = 0.22
@export_range(0.05,1.0,0.01) var knockback_low_speed_recovery_duration:float = 0.18
# 已经完全停住时，再受到击退就恢复公共正常击退位移。
@export_range(0.0,10.0,0.1) var knockback_zero_speed_epsilon:float = 0.5

@export_category("木矛 / 速度伤害")
# 自身速度从基础到最高速度时，对应的最大伤害倍率。
@export_range(1.0,5.0,0.05) var self_speed_damage_max_multiplier:float = 2.40
# 敌人朝木矛移动时提高伤害，背离木矛移动时降低伤害。
# enemy_velocity_reference_speed 表示达到多大“朝向/背离速度”时接近倍率上下限。
@export_range(20.0,500.0,5.0) var enemy_velocity_reference_speed:float = 120.0
@export_range(0.1,1.0,0.05) var enemy_velocity_damage_min_multiplier:float = 0.50
@export_range(1.0,2.0,0.05) var enemy_velocity_damage_max_multiplier:float = 2.00
@export_range(1.0,30.0,0.5) var minimum_final_damage:float = 5.0

@export_category("木矛 / 普通突刺")
# 起手检测仍是以矛头为圆心的圆；敌人中心进圈才允许开始刺。
@export_range(8.0,120.0,1.0) var base_attack_radius:float = 18.0
@export_range(0.0,100.0,1.0) var speed_attack_radius_bonus:float = 24.0
# 主动刺本身不再设置特殊突刺速度或固定距离，只改变移动方向。
# 若一直没有真实命中，超过此时间就结束 Attack，但不会反向后撤。
@export_range(0.20,1.50,0.02) var thrust_max_duration:float = 0.72
# 主动朝向刺触发瞬间获得一次额外速度；只加一次，随后仍按普通移动/蓄速规则继续。
@export_range(0.0,200.0,5.0) var thrust_trigger_instant_speed_bonus:float = 55.0
# 高速主动刺的极小“刺穿内圈”，同样以矛头为圆心并按敌人中心判定。
@export_range(2.0,32.0,0.5) var high_speed_thrust_pass_inner_radius:float = 16.0
# 普通主动刺命中后才按反方向 ± 此角度后撤。
@export_range(0.0,45.0,1.0) var retreat_random_half_angle_degrees:float = 45.0
# 转向主动穿刺的临时爆发。顺向被动使用更高倍率；二者都允许超过日常速度上限。
@export_range(1.0,2.0,0.02) var active_thrust_pass_boost_multiplier:float = 1.22
@export_range(1.0,1.5,0.02) var active_thrust_pass_boost_cap_vs_max:float = 1.22
@export_range(0.08,0.60,0.02) var active_thrust_pass_boost_duration:float = 0.22
@export_range(1.0,2.0,0.01) var passive_pass_boost_multiplier:float = 1.35
@export_range(0.0,0.5,0.01) var target_distance_tie_ratio:float = 0.15
# 转向主动穿刺结束后的蓄速损失比例（变量名保留兼容，不再按红圈优先分类）。
@export_range(0.0,0.95,0.01) var active_circle_pass_bonus_speed_loss_ratio:float = 0.50

@export_category("木矛 / 突刺转向")
# 突刺不再瞬间扭头：先用一个很短的物理过程转向，再进入原有直刺阶段。
@export_range(0.03,0.30,0.01) var thrust_turn_duration:float = 0.11
@export_range(0.0,45.0,1.0) var thrust_turn_skip_below_degrees:float = 4.0
# V115：移动目标会在刺的整个过程中持续更新方向；同时做很短的速度预判，避免只瞄敌人的旧位置。
@export_range(180.0,1440.0,10.0) var thrust_tracking_turn_speed_degrees:float = 900.0
@export_range(0.0,0.35,0.01) var thrust_target_lead_time_max:float = 0.18
@export_range(0.0,1.5,0.05) var thrust_target_lead_strength:float = 0.90
# 只在转向阶段生成快照残影；自动残影与 motion blur 仍保持关闭。
@export_range(0.012,0.10,0.002) var thrust_turn_afterimage_interval:float = 0.028
@export_range(0.05,0.40,0.01) var thrust_turn_afterimage_lifetime:float = 0.16
@export_range(0.0,1.0,0.02) var thrust_turn_afterimage_alpha:float = 0.42
@export var thrust_turn_afterimage_tint:Color = Color(0.78,0.90,1.0,1.0)

@export_category("木矛 / 普通碰撞转向")
# 碰墙/实体反弹后，玩法方向立即采用物理反弹结果；这里只给长矛朝向一个很短的视觉/碰撞形状旋转过渡。
# 不生成残影，避免普通碰撞时画面过重。
@export_range(0.03,0.25,0.01) var collision_turn_duration:float = 0.08
@export_range(0.0,45.0,1.0) var collision_turn_skip_below_degrees:float = 3.0

@export_category("木矛 / 高速穿越")
@export_range(1.05,4.0,0.05) var pass_speed_threshold_ratio:float = 3.80
@export_range(1.0,4.0,0.05) var pass_damage_multiplier:float = 2.0
@export_range(2.0,30.0,0.5) var pass_clearance_distance:float = 8.0
@export_range(0.10,1.5,0.05) var pass_timeout:float = 0.70
@export_range(0.0,24.0,0.5) var pass_prearm_margin:float = 6.0

@export_category("木矛 / 穿越残影")
# 不做持续拖尾；只有真正穿过敌人的那一小段时间生成短寿命世界快照。
@export_range(0.012,0.10,0.002) var pass_afterimage_interval:float = 0.032
@export_range(0.05,0.40,0.01) var pass_afterimage_lifetime:float = 0.17
@export_range(0.0,1.0,0.02) var pass_afterimage_alpha:float = 0.50
@export var pass_afterimage_tint:Color = Color(0.72,0.88,1.0,1.0)

@export_category("木矛 / 威胁调试")
# 开启项目“威胁调试显示”时，木矛自己额外画出真实起手检测圆；不再依赖外部 overlay 是否挂载成功。
@export_range(0.5,5.0,0.25) var debug_attack_circle_width:float = 1.5
@export_range(24,128,8) var debug_attack_circle_segments:int = 64

@export_category("木矛 / 音效")
@export_range(-18.0,8.0,0.5) var attack_sfx_volume_db:float = -1.0
@export_range(-18.0,8.0,0.5) var hit_sfx_volume_db:float = -1.0
@export_range(-18.0,8.0,0.5) var use_sfx_volume_db:float = 0.0
@export_range(-18.0,8.0,0.5) var block_sfx_volume_db:float = -1.0
@export_range(500.0,3000.0,50.0) var sfx_max_distance:float = 1450.0
@export_range(0.0,0.12,0.005) var sfx_pitch_variation:float = 0.035

@onready var spear_sprite:Sprite2D = $Graphics/Image
@onready var spear_tip_guard:hurtbox = $SpearTipGuard
@onready var spear_tip_guard_shape:CollisionShape2D = $SpearTipGuard/CollisionShape2D

var _attack_range_debug_line:Line2D = null
var _attack_range_debug_radius:float = -1.0
var _pass_range_debug_line:Line2D = null
var _pass_range_debug_radius:float = -1.0

var _base_move_speed:float = 1.0
var _current_move_speed:float = 1.0
var _facing_direction:Vector2 = Vector2.RIGHT
var _last_world_position:Vector2 = Vector2.ZERO
var _position_initialized:bool = false
var _was_dizzy:bool = false

var _attack_active:bool = false
var _attack_target:ball = null
var _attack_direction:Vector2 = Vector2.RIGHT
var _attack_elapsed:float = 0.0
# 保留枚举名兼容；RED_CIRCLE=起手需转向，FORWARD_PATH=原路线直穿。
enum ActiveThrustPassTrigger { NONE, RED_CIRCLE, FORWARD_PATH }
var _attack_needed_turn:bool = true
var _penetration_budget_active:bool = false
var _penetration_accumulated_speed:float = 0.0
var _speed_recovery_target:float = 0.0
var _pass_hit_ids:Dictionary = {}

var _attack_pass_through:bool = false
var _attack_pass_hit:bool = false
var _attack_pass_trigger:ActiveThrustPassTrigger = ActiveThrustPassTrigger.NONE
var _attack_hit_ids:Dictionary = {}
var _attack_collision_exception:PhysicsBody2D = null
# V121：主动穿透命中后，只有木矛实体碰撞框后缘完整越过目标实体前缘才恢复碰撞。
var _attack_pass_clearance_armed:bool = false
var _attack_pass_target_front_forward:float = 0.0

# 刺前短暂转向状态。转向帧仍沿插值后的方向正常移动，但刺击超时计时从转向完成后才开始。
var _attack_turn_active:bool = false
var _attack_turn_elapsed:float = 0.0
var _attack_turn_start_angle:float = 0.0
var _attack_turn_target_angle:float = 0.0
var _attack_turn_afterimage_elapsed:float = 0.0

# 普通碰撞/反弹后的短暂转向动画。玩法 direction 已经是新方向；这里只平滑更新长矛视觉与三套碰撞朝向。
var _collision_turn_active:bool = false
var _collision_turn_elapsed:float = 0.0
var _collision_turn_start_angle:float = 0.0
var _collision_turn_target_angle:float = 0.0

# 穿刺触发时临时提速；未穿出时到期退回爆发前速度，穿出后转入比例扣速。
var _thrust_boost_active:bool = false
var _thrust_boost_elapsed:float = 0.0
var _thrust_boost_start_speed:float = 0.0
var _thrust_boost_return_speed:float = 0.0

# 自然顺向穿刺状态；与Attack中的FORWARD_PATH共用爆发/双倍/扣速规则。
var _pass_active:bool = false
var _pass_target:ball = null
var _pass_direction:Vector2 = Vector2.RIGHT
var _pass_elapsed:float = 0.0
var _pass_hit:bool = false
var _pass_target_start_forward:float = 0.0
var _pass_last_tip_position:Vector2 = Vector2.ZERO
var _attack_last_tip_position:Vector2 = Vector2.ZERO
var _attack_last_target_position:Vector2 = Vector2.ZERO
var _pass_afterimage_elapsed:float = 0.0

var _speed_recovery_active:bool = false
var _speed_recovery_start:float = 0.0
var _speed_recovery_elapsed:float = 0.0

# V122：击退把速度压到基础值以下时，先等待再快速回基础速度。
var _low_speed_recovery_wait:float = 0.0
var _low_speed_recovery_active:bool = false
var _low_speed_recovery_elapsed:float = 0.0
var _low_speed_recovery_start:float = 0.0

var _rng := RandomNumberGenerator.new()
var _sfx_rng := RandomNumberGenerator.new()
var _use_speed_sfx_latched:bool = false
var _last_block_feedback_hit_id:int = -1
var _last_block_feedback_msec:int = -1000000


func _ready() -> void:
	Has_Collision_Damage = false
	Can_Attack = true
	Can_Skill = false
	Health_Restore = 0

	if spear_sprite != null:
		image = spear_sprite
		spear_sprite.texture = WOODEN_SPEAR_TEXTURE
		spear_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	super._ready()

	_base_move_speed = maxf(Speed,1.0)
	max_move_speed = maxf(max_move_speed,_base_move_speed)
	_rng.seed = Game.battle_rng_seed_or(
		"scripts/characters/我的世界/木矛.gd:_rng.seed",
		maxi(abs(int(Time.get_ticks_usec()) ^ int(get_instance_id()) ^ 0x57EA2),1)
	)
	_sfx_rng.seed = Game.battle_rng_seed_or(
		"scripts/characters/我的世界/木矛.gd:_sfx_rng.seed",
		maxi(abs(int(Time.get_ticks_usec()) ^ int(get_instance_id()) ^ 0x51F0A),1)
	)
	# V110：出生速度固定从基础 Speed 开始；随机的是 World 统一分配的开局移动方向。
	_current_move_speed = _base_move_speed
	Speed = _base_move_speed

	_configure_collision_geometry()
	# 木矛的矛头就是常驻攻击 Hitbox：不论是否处于 Attack，真实碰到敌方 Hurtbox 都能造成碰撞伤害。
	# Has_Collision_Damage 仍保持 false，避免 CharacterBody2D 的矛身实体接触被公共逻辑误当成攻击。
	if self_hitbox != null:
		self_hitbox.monitoring = true
		self_hitbox.monitorable = false
		self_hitbox.collision_layer = 0
		self_hitbox.collision_mask = 2
		self_hitbox.duplicate_hit_guard_seconds = 0.035
	if self_hurtbox != null:
		self_hurtbox.monitorable = true
		self_hurtbox.collision_layer = 2
		self_hurtbox.collision_mask = 0
	if spear_tip_guard != null:
		spear_tip_guard.monitorable = true
		spear_tip_guard.collision_layer = 2
		spear_tip_guard.collision_mask = 0

	# direction==ZERO 时不要在角色脚本里写死方向；World 会和其他普通角色一样统一随机并记录开局方向。
	if direction.length_squared() > 0.000001:
		_set_facing_direction(direction.normalized())
	else:
		_set_facing_direction(Vector2.RIGHT)
	_last_world_position = global_position
	_position_initialized = true
	_was_dizzy = dizziness

	# 删除持续高速拖尾/动态模糊；只保留“刺前转向快照”和“真实穿越快照”两种短寿命残影。
	motion_blur_enabled = false
	AfterImage_Speed = -1.0
	_clear_after_image_path()
	_ensure_attack_range_debug_circle()
	_update_attack_range_debug_circle(true)


func _is_character_ground_shadow_owner() -> bool:
	# 木矛本身就是一件武器，没有人物脚底影子。
	return false


func get_preview_texture() -> Texture2D:
	return WOODEN_SPEAR_TEXTURE


# 骷髅箭等插入型投射物应跟随木矛真正旋转的视觉，而不是只跟随不旋转的 CharacterBody2D 根节点。
func get_projectile_embed_parent() -> Node2D:
	if spear_sprite != null and is_instance_valid(spear_sprite):
		return spear_sprite
	return self


func _configure_collision_geometry() -> void:
	if self_hitbox != null:
		var node := self_hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if node != null:
			var shape := RectangleShape2D.new()
			shape.size = Vector2(maxf(spear_tip_local_size.x,2.0),maxf(spear_tip_local_size.y,2.0))
			node.shape = shape
			node.disabled = false
	if spear_tip_guard_shape != null:
		var guard_shape := RectangleShape2D.new()
		guard_shape.size = Vector2(maxf(spear_tip_local_size.x,2.0),maxf(spear_tip_local_size.y,2.0))
		spear_tip_guard_shape.shape = guard_shape
		spear_tip_guard_shape.disabled = false
	if self_hurtbox != null:
		var hurt_shape_node := self_hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if hurt_shape_node != null:
			var hurt_shape := RectangleShape2D.new()
			hurt_shape.size = Vector2(maxf(shaft_local_size.x,4.0),maxf(shaft_local_size.y,2.0))
			hurt_shape_node.shape = hurt_shape
			hurt_shape_node.disabled = false
	if collision_shape_2d != null:
		var body_shape := RectangleShape2D.new()
		body_shape.size = Vector2(maxf(body_collision_local_size.x,4.0),maxf(body_collision_local_size.y,2.0))
		collision_shape_2d.shape = body_shape
		collision_shape_2d.disabled = false


# 木矛免疫通用“被推着滑行”的击退。
# 仍然读取击退力度来削减自身动量：弱于当前移速只减速；强于当前移速则改成击退方向。
# 若该击退同时携带 stun_duration，则只保留眩晕，不保留任何 Repel 位移。
func apply_knockback(
	knockback_direction:Vector2,
	knockback_distance:float,
	knockback_speed:float = 700.0,
	wall_bounce_strength:float = 0.0,
	stun_duration:float = 0.0,
	options:Dictionary = {}
) -> Node:
	if health <= 0:
		return null
	if state_machine != null and state_machine.current_state == State.Die:
		return null

	var force:float = maxf(knockback_speed,0.0)
	# V122：如果木矛已经完全失去自身移动动量，再来的击退就按普通角色处理真实位移。
	# 这一次不再把击退转换成“继续减速”，也不强制清零 Repel。
	if (
		_current_move_speed <= maxf(knockback_zero_speed_epsilon,0.0)
		and knockback_distance > 0.0
		and force > 0.0
	):
		_schedule_low_speed_recovery(true)
		return super.apply_knockback(
			knockback_direction,
			knockback_distance,
			knockback_speed,
			wall_bounce_strength,
			stun_duration,
			options
		)

	if knockback_distance > 0.0 and force > 0.0:
		_apply_knockback_momentum_response(knockback_direction,force)

	# 仍有自身动量时，击退只削动量，不写入通用 Repel 位移。
	Repel = Vector2.ZERO

	# 击退附带的眩晕仍然允许生效；用“0 距离击退”只复用公共眩晕/控制锁系统。
	if stun_duration > 0.0:
		var stun_options:Dictionary = options.duplicate(true)
		stun_options["collision_damage"] = 0.0
		stun_options["wall_bounce_strength"] = 0.0
		return super.apply_knockback(
			Vector2.ZERO,
			0.0,
			0.0,
			0.0,
			stun_duration,
			stun_options
		)
	return null


func _apply_knockback_momentum_response(knockback_direction:Vector2,force:float) -> void:
	if force <= 0.0: return
	_cancel_penetration_speed()
	var current_speed:float = maxf(_current_move_speed,0.0)
	var safe_force:float = maxf(force,0.0)
	if safe_force <= 0.0:
		return

	var slowdown:float = safe_force * clampf(knockback_slowdown_ratio,0.0,1.0)
	# “是否压过木矛动量”至少以基础速度作为门槛。
	# 这样像骷髅箭这种约等于基础速度的弱击退，不会因为上一发刚减速，下一发就突然变成强制改向。
	var momentum_threshold:float = maxf(current_speed,_base_move_speed)
	var overpowered:bool = safe_force > momentum_threshold + 0.001
	var new_speed:float = maxf(current_speed - slowdown,0.0)

	if overpowered:
		# 强击退只“夺走动量并改向”，不会把木矛本体直接推出去。
		var incoming_dir:Vector2 = knockback_direction.normalized()
		if incoming_dir.length_squared() > 0.000001:
			_cleanup_attack(true)
			_cleanup_pass(false)
			direction = incoming_dir
			_set_facing_direction(direction)
		var minimum_after_overpower:float = _base_move_speed * clampf(knockback_overpower_min_speed_ratio,0.0,1.0)
		new_speed = maxf(new_speed,minimum_after_overpower)
	else:
		# V122：弱击退也允许把自身动量继续削到 0；默认不再有 85% 基础速度保护。
		var weak_floor:float = _base_move_speed * clampf(knockback_weak_min_speed_ratio,0.0,1.0)
		new_speed = maxf(new_speed,weak_floor)

	# 被击退削速时取消临时提速/高速回落曲线，低于基础速度则改走“延迟 -> 快速回基速”。
	_thrust_boost_active = false
	_speed_recovery_active = false
	_current_move_speed = clampf(new_speed,0.0,maxf(max_move_speed,_base_move_speed))
	if _current_move_speed < _base_move_speed - 0.001:
		_schedule_low_speed_recovery(overpowered)
	else:
		_clear_low_speed_recovery()
	Speed = _current_move_speed


func get_next_state(state:State) -> int:
	if not is_multiplayer_authority():
		return -1

	# 高速被动穿越正在发生时，保持普通 Move，不让公共冷却系统把它解释成主动攻击。
	if _pass_active and state == State.Move:
		var saved_can_attack_pass:bool = Can_Attack
		var saved_pass_attack_timer:float = float(state_machine.last_state_dis.Attack) if state_machine != null else 0.0
		Can_Attack = false
		var pass_result:int = super.get_next_state(state)
		Can_Attack = saved_can_attack_pass
		if state_machine != null:
			state_machine.last_state_dis.Attack = saved_pass_attack_timer
		return pass_result

	# AI 只有在当前“真实动态近战范围”里存在目标时才允许进入 Attack。
	if (
		not is_player_controlled()
		and Can_Attack
		and state_machine != null
		and state_machine.last_state_dis.Attack >= Attack_Cooling
		and _find_attack_target() == null
	):
		var saved_attack_timer:float = float(state_machine.last_state_dis.Attack)
		var saved_can_attack_range:bool = Can_Attack
		Can_Attack = false
		var range_result:int = super.get_next_state(state)
		Can_Attack = saved_can_attack_range
		state_machine.last_state_dis.Attack = saved_attack_timer
		return range_result

	return super.get_next_state(state)


func Attack() -> void:
	if (
		_attack_active
		or _pass_active
		or not is_multiplayer_authority()
		or health <= 0
		or state_machine == null
		or state_machine.current_state == State.Die
		or dizziness
		or not is_combat_runtime_active()
		or is_damage_output_disabled()
	):
		Attacking = false
		return

	var target:ball = _find_attack_target()
	if target == null:
		Attacking = false
		return

	var offset:Vector2 = combat_target_position(target) - global_position
	if offset.length_squared() <= 0.000001:
		Attacking = false
		return

	_collision_turn_active = false
	_collision_turn_elapsed = 0.0
	_attack_active = true
	_attack_target = target
	# 必须在改向和起手加速之前按原移动路径分类，并在本次攻击中锁定。
	var original_direction:Vector2 = _current_move_direction().normalized()
	_attack_needed_turn = not _path_can_hit_target(target,original_direction)
	_attack_direction = offset.normalized() if _attack_needed_turn else original_direction
	_attack_elapsed = 0.0
	_attack_hit_ids.clear()
	_attack_pass_hit = false
	_attack_pass_trigger = ActiveThrustPassTrigger.NONE
	_attack_pass_clearance_armed = false
	_attack_pass_target_front_forward = 0.0
	_pass_afterimage_elapsed = 0.0
	Attacking = true

	# V124：主动朝向刺一触发就获得一次瞬时加速。
	if _current_move_speed < _pass_threshold_speed():
		_apply_thrust_trigger_instant_acceleration()

	# V107：先短暂转向，不再在 Attack() 这一帧瞬间把长矛从旧方向掰到目标方向。
	_attack_turn_start_angle = _facing_direction.angle()
	_attack_turn_target_angle = _attack_direction.angle()
	_attack_turn_elapsed = 0.0
	_attack_turn_afterimage_elapsed = 0.0
	var turn_delta:float = absf(wrapf(_attack_turn_target_angle - _attack_turn_start_angle,-PI,PI))
	_attack_turn_active = _attack_needed_turn and turn_delta > deg_to_rad(maxf(thrust_turn_skip_below_degrees,0.0))
	if _attack_turn_active:
		_spawn_thrust_turn_afterimage()
	else:
		_set_facing_direction(_attack_direction)
	_broadcast_attack_sfx()

	# 主动刺只改变移动方向，不再规划“前冲多少像素”或强制改成特殊突刺速度。
	# 为避免 CharacterBody2D 身体先挡住矛头，对本次目标临时放行实体碰撞；真正伤害仍只认矛头 Area2D。
	_attack_collision_exception = target
	add_collision_exception_with(target)
	_attack_last_tip_position = _spear_tip_world_position()
	_attack_last_target_position = combat_target_position(target)

	# V119：主动刺穿不再只在起手瞬间看一次“目标中心是否进内圈”。
	# 速度达标后，只要敌方 Hurtbox 已触碰红圈，或当前刺向本来就会穿过敌人，就允许这次刺转为穿透刺。
	_update_active_thrust_pass_state()


func _apply_thrust_trigger_instant_acceleration() -> void:
	if _speed_recovery_active: return
	var bonus:float = maxf(thrust_trigger_instant_speed_bonus,0.0)
	if bonus <= 0.0:
		return

	# 主动刺应当立刻拥有这次推进，不让低速恢复过程在下一帧把速度拉回基础值。
	_clear_low_speed_recovery()
	var speed_cap:float = maxf(max_move_speed,_base_move_speed)
	_current_move_speed = minf(maxf(_current_move_speed,0.0) + bonus,speed_cap)
	Speed = _current_move_speed


func tick_physics(state:State,delta:float) -> void:
	_update_attack_range_debug_circle()
	if not is_multiplayer_authority():
		super.tick_physics(state,delta)
		_update_attack_range_debug_circle()
		return

	# “眩晕重置移速”：只在进入 dizziness 的瞬间执行一次，同时中断当前刺/穿越。
	if dizziness and not _was_dizzy:
		_reset_speed_to_base()
		_cleanup_attack(true)
		_cleanup_pass(false)
	_was_dizzy = dizziness

	if health <= 0:
		_cleanup_attack(true)
		_cleanup_pass(false)
		super.tick_physics(state,delta)
		return

	_tick_thrust_boost(delta)
	_tick_speed_recovery(delta)
	_tick_low_speed_recovery(delta)

	if _attack_active:
		_tick_thrust(state,delta)
		return

	# 高速被动穿越只锁住“这一次真正撞上的方向”，除此之外继续走 ball 的普通移动逻辑。
	if _pass_active:
		direction = _pass_direction
		_set_facing_direction(_pass_direction)

	Speed = _current_move_speed
	_update_tip_hitbox_monitoring()
	_prepare_pass_collision_exception()

	var frame_start:Vector2 = global_position
	super.tick_physics(state,delta)
	var frame_delta:Vector2 = global_position - frame_start
	if _collision_turn_active:
		_tick_collision_turn_animation(delta)
	elif frame_delta.length_squared() > 0.0004:
		_set_facing_direction(frame_delta.normalized())
	if frame_delta.length_squared() > 0.0004:
		if (
			not _speed_recovery_active
			and not _low_speed_recovery_active
			and _low_speed_recovery_wait <= 0.0
			and _current_move_speed >= _base_move_speed - 0.001
			and not _thrust_boost_active
			and not _penetration_budget_active
			and not dizziness
			and state == State.Move
		):
			_current_move_speed = minf(
				_current_move_speed + maxf(move_acceleration_per_second,0.0) * maxf(delta,0.0),
				maxf(max_move_speed,_base_move_speed)
			)

	if _pass_active and _pass_hit:
		_tick_pass_afterimage(delta)
	_tick_pass_completion(delta)
	_update_use_speed_sfx_state()
	_last_world_position = global_position
	_position_initialized = true
	_update_attack_range_debug_circle()


func _tick_thrust(state:State,delta:float) -> void:
	if not _attack_is_valid():
		_finish_attack_miss()
		return

	var dt:float = maxf(delta,0.0)

	# V107：刺前先完成短暂的方向过渡。该帧已经执行了正常移动，因此结束转向的下一物理帧才正式进入直刺，避免单帧移动两次。
	if _attack_turn_active:
		_tick_thrust_turn(state,dt)
		return

	_attack_elapsed += dt
	if _attack_has_missed_target():
		_finish_attack_miss()
		return
	_update_attack_direction_tracking(dt)
	_update_active_thrust_pass_state()
	direction = _attack_direction
	_set_facing_direction(_attack_direction)

	# 主动刺就是“把正常移动方向改向敌人”。不设置额外突刺速度，不按计划距离停车。
	Speed = _current_move_speed
	var start:Vector2 = global_position
	var saved_crowd:Vector2 = _crowd_separation_velocity
	_crowd_separation_velocity = Vector2.ZERO
	super.tick_physics(State.Attack,delta)
	_crowd_separation_velocity = saved_crowd

	# 撞墙时 when_collide() 会直接结束本次刺并留下公共反弹后的 direction；不要再把方向强制改回墙内。
	if not _attack_active:
		if not _collision_turn_active:
			_set_facing_direction(direction)
		_update_attack_range_debug_circle()
		return

	# 高速主动刺可能一帧跨过 Hurtbox；用矛头世界轨迹补一次 swept 检测。
	_try_attack_swept_tip_hit()
	if not _attack_active:
		return

	# ball.move() 会写通用水平 flip；旋转型长矛每帧重新锁回真正突刺方向。
	_set_facing_direction(_attack_direction)
	_update_attack_range_debug_circle()
	if _attack_pass_through and _attack_pass_hit:
		_tick_pass_afterimage(dt)

	var moved:Vector2 = global_position - start
	if (
		moved.length_squared() > 0.0004
		and not _speed_recovery_active
		and not _low_speed_recovery_active
		and _low_speed_recovery_wait <= 0.0
		and _current_move_speed >= _base_move_speed - 0.001
		and not _thrust_boost_active
		and not _penetration_budget_active
	):
		_current_move_speed = minf(
			_current_move_speed + maxf(move_acceleration_per_second,0.0) * dt,
			maxf(max_move_speed,_base_move_speed)
		)

	# area_entered 若在起手前已经重叠不会重新触发，因此每帧补查一次真实矛头 overlap。
	_try_spear_hitbox_overlaps()
	# 普通刺命中时回调会立刻清掉 _attack_active 并后撤。
	if not _attack_active:
		return

	# 主动穿透命中后继续向前。只有木矛实体碰撞框后缘完整越过目标实体前缘后才恢复身体碰撞。
	if _attack_pass_through and _attack_pass_hit:
		var pass_finished:bool = _active_attack_pass_fully_cleared()
		var pass_timed_out:bool = _attack_elapsed >= maxf(thrust_max_duration,0.20) + maxf(pass_timeout,0.10)
		if pass_finished or pass_timed_out:
			_finish_attack_pass()
			return

	# 空刺只是在超时后结束 Attack；因为没有刺中，所以绝不触发反向后撤。
	if _attack_elapsed >= maxf(thrust_max_duration,0.20):
		_finish_attack_miss()


func _tick_thrust_turn(_state:State,dt:float) -> void:
	var duration:float = maxf(thrust_turn_duration,0.03)
	# 转向期间也持续瞄当前/预判目标位置，移动敌人不会在 0.11s 转身动画里直接跑出矛尖方向。
	if _attack_target != null and is_instance_valid(_attack_target):
		var predicted_turn_target:Vector2 = _predicted_attack_target_position(_attack_target)
		var turn_offset:Vector2 = predicted_turn_target - global_position
		if turn_offset.length_squared() > 0.000001:
			_attack_turn_target_angle = turn_offset.angle()
	_attack_turn_elapsed = minf(_attack_turn_elapsed + maxf(dt,0.0),duration)
	var t:float = clampf(_attack_turn_elapsed / duration,0.0,1.0)
	var eased:float = smoothstep(0.0,1.0,t)
	var angle:float = lerp_angle(_attack_turn_start_angle,_attack_turn_target_angle,eased)
	var turn_dir:Vector2 = Vector2.RIGHT.rotated(angle)
	direction = turn_dir
	_set_facing_direction(turn_dir)
	# 转向阶段同样实时检查红圈/当前路径；一旦满足就锁定为本次穿透刺。
	_update_active_thrust_pass_state(turn_dir)

	# 转向阶段仍然只是正常移动，不额外加速；同时暂时去掉 crowd separation，避免视觉转向被反向推力拉扯。
	Speed = _current_move_speed
	var saved_crowd:Vector2 = _crowd_separation_velocity
	_crowd_separation_velocity = Vector2.ZERO
	var start:Vector2 = global_position
	super.tick_physics(State.Attack,dt)
	_crowd_separation_velocity = saved_crowd
	if not _attack_active:
		if not _collision_turn_active:
			_set_facing_direction(direction)
		_update_attack_range_debug_circle()
		return
	_try_attack_swept_tip_hit()
	if not _attack_active:
		return
	# 公共 move() 可能写水平 flip，所以移动完以后再把图片与三套碰撞区锁回当前插值角度。
	_set_facing_direction(turn_dir)

	var moved:Vector2 = global_position - start
	if (
		moved.length_squared() > 0.0004
		and not _speed_recovery_active
		and not _low_speed_recovery_active
		and _low_speed_recovery_wait <= 0.0
		and _current_move_speed >= _base_move_speed - 0.001
		and not _thrust_boost_active
		and not _penetration_budget_active
	):
		_current_move_speed = minf(
			_current_move_speed + maxf(move_acceleration_per_second,0.0) * maxf(dt,0.0),
			maxf(max_move_speed,_base_move_speed)
		)

	_attack_turn_afterimage_elapsed += maxf(dt,0.0)
	var interval:float = maxf(thrust_turn_afterimage_interval,0.012)
	if _attack_turn_afterimage_elapsed >= interval:
		_attack_turn_afterimage_elapsed = fmod(_attack_turn_afterimage_elapsed,interval)
		_spawn_thrust_turn_afterimage()

	# 矛头一直都有伤害，因此转向扫过敌人时照样使用真实 Area2D overlap；若这时已刺中，会立即进入原有命中后撤/主动刺穿处理。
	_try_spear_hitbox_overlaps()
	_update_attack_range_debug_circle()
	if not _attack_active:
		return

	if t >= 1.0:
		_attack_turn_active = false
		_attack_turn_elapsed = 0.0
		_attack_turn_afterimage_elapsed = 0.0
		# 正式刺出前再锁一次当前移动目标，避免转向结束时仍沿起手旧角度直刺。
		if _attack_target != null and is_instance_valid(_attack_target):
			var predicted_end:Vector2 = _predicted_attack_target_position(_attack_target)
			var end_offset:Vector2 = predicted_end - global_position
			if end_offset.length_squared() > 0.000001:
				_attack_direction = end_offset.normalized()
		direction = _attack_direction
		_set_facing_direction(_attack_direction)



func _predicted_attack_target_position(target:ball) -> Vector2:
	if target == null or not is_instance_valid(target):
		return global_position + _attack_direction
	var target_position:Vector2 = combat_target_position(target)
	var tip_position:Vector2 = _spear_tip_world_position()
	var distance_to_target:float = tip_position.distance_to(target_position)
	var own_speed:float = maxf(_current_move_speed,1.0)
	var lead_time:float = clampf(distance_to_target / own_speed,0.0,maxf(thrust_target_lead_time_max,0.0))
	return target_position + target.velocity * lead_time * maxf(thrust_target_lead_strength,0.0)


func _update_attack_direction_tracking(dt:float) -> void:
	# 顺向刺绝不转成追踪刺；转向主动刺只允许命中前的小幅追踪。
	if not _attack_needed_turn: return
	# 穿透一旦真实命中就锁定当前穿刺方向，避免在目标体内继续追踪造成横向拐弯。
	if _attack_pass_through and _attack_pass_hit:
		return
	if _attack_target == null or not is_instance_valid(_attack_target) or not TOOLS.is_enemy(self,_attack_target):
		return
	var predicted:Vector2 = _predicted_attack_target_position(_attack_target)
	var desired:Vector2 = predicted - global_position
	if desired.length_squared() <= 0.000001:
		return
	var current_angle:float = _attack_direction.angle()
	var desired_angle:float = desired.angle()
	var delta_angle:float = wrapf(desired_angle - current_angle,-PI,PI)
	var max_step:float = deg_to_rad(maxf(thrust_tracking_turn_speed_degrees,0.0)) * maxf(dt,0.0)
	var next_angle:float = current_angle + clampf(delta_angle,-max_step,max_step)
	_attack_direction = Vector2.RIGHT.rotated(next_angle).normalized()


func _queue_wood_spear_afterimage(
	ghost_transform:Transform2D,
	trail_dir:Vector2,
	lifetime:float,
	alpha:float,
	tint:Color,
	blur_start:float,
	blur_end:float,
	end_scale:Vector2
) -> void:
	# Area2D / physics query 回调期间不能直接增删会改变物理监控状态的节点。
	# 把残影真正的生成推迟到安全时机，并把本次样式作为参数一并捕获，避免 deferred 后读到已经恢复的公共 AfterImage 参数。
	call_deferred(
		"_spawn_wood_spear_afterimage_deferred",
		ghost_transform,
		trail_dir,
		lifetime,
		alpha,
		tint,
		blur_start,
		blur_end,
		end_scale
	)


func _spawn_wood_spear_afterimage_deferred(
	ghost_transform:Transform2D,
	trail_dir:Vector2,
	lifetime:float,
	alpha:float,
	tint:Color,
	blur_start:float,
	blur_end:float,
	end_scale:Vector2
) -> void:
	if not is_inside_tree() or spear_sprite == null or not is_instance_valid(spear_sprite) or not spear_sprite.visible:
		return
	var old_lifetime:float = AfterImage_Lifetime
	var old_alpha:float = AfterImage_Alpha
	var old_end_alpha:float = AfterImage_End_Alpha
	var old_tint:Color = AfterImage_Tint
	var old_end_tint:Color = AfterImage_End_Tint
	var old_blur:float = AfterImage_Blur_Pixels
	var old_end_blur:float = AfterImage_End_Blur_Pixels
	var old_smear:float = AfterImage_Smear_Pixels
	var old_end_smear:float = AfterImage_End_Smear_Pixels
	var old_start_scale:Vector2 = AfterImage_Start_Scale
	var old_end_scale:Vector2 = AfterImage_End_Scale

	AfterImage_Lifetime = maxf(lifetime,0.05)
	AfterImage_Alpha = clampf(alpha,0.0,1.0)
	AfterImage_End_Alpha = 0.0
	AfterImage_Tint = tint
	AfterImage_End_Tint = Color(tint.r,tint.g,tint.b,0.0)
	AfterImage_Blur_Pixels = blur_start
	AfterImage_End_Blur_Pixels = blur_end
	AfterImage_Smear_Pixels = 0.0
	AfterImage_End_Smear_Pixels = 0.0
	AfterImage_Start_Scale = Vector2.ONE
	AfterImage_End_Scale = end_scale
	_spawn_after_image_at_transform(ghost_transform,trail_dir)

	AfterImage_Lifetime = old_lifetime
	AfterImage_Alpha = old_alpha
	AfterImage_End_Alpha = old_end_alpha
	AfterImage_Tint = old_tint
	AfterImage_End_Tint = old_end_tint
	AfterImage_Blur_Pixels = old_blur
	AfterImage_End_Blur_Pixels = old_end_blur
	AfterImage_Smear_Pixels = old_smear
	AfterImage_End_Smear_Pixels = old_end_smear
	AfterImage_Start_Scale = old_start_scale
	AfterImage_End_Scale = old_end_scale


func _spawn_thrust_turn_afterimage() -> void:
	if spear_sprite == null or not is_instance_valid(spear_sprite) or not spear_sprite.visible:
		return
	_queue_wood_spear_afterimage(
		spear_sprite.global_transform,
		_facing_direction,
		thrust_turn_afterimage_lifetime,
		thrust_turn_afterimage_alpha,
		thrust_turn_afterimage_tint,
		0.6,
		2.2,
		Vector2(0.98,0.98)
	)


func _tick_pass_afterimage(delta:float) -> void:
	# 只有“已经真实命中并正在穿过目标”的时间段生成残影；平时高速移动绝不生成持续拖尾。
	_pass_afterimage_elapsed += maxf(delta,0.0)
	var interval:float = maxf(pass_afterimage_interval,0.012)
	if _pass_afterimage_elapsed >= interval:
		_pass_afterimage_elapsed = fmod(_pass_afterimage_elapsed,interval)
		_spawn_pass_afterimage()


func _spawn_pass_afterimage() -> void:
	if spear_sprite == null or not is_instance_valid(spear_sprite) or not spear_sprite.visible:
		return
	_queue_wood_spear_afterimage(
		spear_sprite.global_transform,
		_facing_direction,
		pass_afterimage_lifetime,
		pass_afterimage_alpha,
		pass_afterimage_tint,
		0.35,
		1.6,
		Vector2(0.985,0.985)
	)


func _begin_pass_afterimages() -> void:
	_pass_afterimage_elapsed = 0.0
	_spawn_pass_afterimage()


func _attack_is_valid() -> bool:
	var self_valid:bool = (
		_attack_active
		and is_multiplayer_authority()
		and health > 0
		and state_machine != null
		and state_machine.current_state != State.Die
		and not dizziness
		and is_combat_runtime_active()
		and not is_damage_output_disabled()
	)
	if not self_valid:
		return false
	# 穿透已经命中后，即使目标被这一击杀死，也继续把整个实体穿完再恢复碰撞。
	if _attack_pass_through and _attack_pass_hit:
		return true
	return (
		_attack_target != null
		and is_instance_valid(_attack_target)
		and TOOLS.is_enemy(self,_attack_target)
	)


func _target_body_front_forward(target:ball,world_direction:Vector2) -> float:
	if target == null or not is_instance_valid(target):
		return 0.0
	var dir:Vector2 = world_direction.normalized() if world_direction.length_squared() > 0.000001 else Vector2.RIGHT
	var target_shape:CollisionShape2D = target.collision_shape_2d
	if target_shape != null and is_instance_valid(target_shape) and not target_shape.disabled and target_shape.shape != null:
		return target_shape.global_position.dot(dir) + _shape_extent_world(target_shape,dir)
	return combat_target_position(target).dot(dir) + _target_hurt_extent_along(target,dir)


func _arm_active_attack_pass_clearance(target:ball) -> void:
	var dir:Vector2 = _attack_direction.normalized() if _attack_direction.length_squared() > 0.000001 else _facing_direction
	_attack_pass_target_front_forward = _target_body_front_forward(target,dir)
	_attack_pass_clearance_armed = true


func _active_attack_pass_fully_cleared() -> bool:
	if not _attack_pass_clearance_armed:
		return false
	var dir:Vector2 = _attack_direction.normalized() if _attack_direction.length_squared() > 0.000001 else _facing_direction
	var rear_forward:float = global_position.dot(dir)
	if collision_shape_2d != null and is_instance_valid(collision_shape_2d) and not collision_shape_2d.disabled and collision_shape_2d.shape != null:
		rear_forward = collision_shape_2d.global_position.dot(dir) - _shape_extent_world(collision_shape_2d,dir)
	return rear_forward >= _attack_pass_target_front_forward + maxf(pass_clearance_distance,2.0)


func _finish_attack_kill_continue() -> void:
	if not _attack_active: return
	var attack_dir:Vector2 = _attack_direction
	_cleanup_attack(false)
	direction = attack_dir
	_set_facing_direction(direction)
	Speed = _current_move_speed
	Attacking = false


func _finish_attack_hit_retreat() -> void:
	if not _attack_active:
		return
	var attack_dir:Vector2 = _attack_direction
	_cleanup_attack(false)

	var half:float = deg_to_rad(clampf(retreat_random_half_angle_degrees,0.0,45.0))
	var retreat:Vector2 = (-attack_dir).rotated(_rng.randf_range(-half,half))
	if retreat.length_squared() <= 0.000001:
		retreat = -attack_dir
	direction = retreat.normalized()
	_set_facing_direction(direction)
	Speed = _current_move_speed
	Attacking = false


func _finish_attack_miss() -> void:
	if not _attack_active:
		return
	var attack_dir:Vector2 = _attack_direction
	_cleanup_attack(false)
	# 没命中就不后撤，继续沿刚才刺出的方向正常移动。
	direction = attack_dir
	_set_facing_direction(direction)
	Speed = _current_move_speed
	Attacking = false


func _finish_attack_pass() -> void:
	if not _attack_active: return
	var attack_dir:Vector2 = _attack_direction
	_cleanup_attack(false)
	direction = attack_dir
	_set_facing_direction(direction)
	Speed = _current_move_speed
	Attacking = false


func _apply_normal_hit_speed_gain(straight:bool) -> void:
	var gain:float = maxf(straight_hit_speed_gain if straight else normal_hit_speed_gain,0.0)
	# 临时爆发尚在回落且高于上限时，不增加也不把当前速度截断。
	gain = minf(gain,maxf(maxf(max_move_speed,_base_move_speed)-_current_move_speed,0.0))
	_current_move_speed += gain
	if _speed_recovery_active:
		# 不取消穿刺后的扣速；同步移动曲线两端，避免下一帧吞掉普通命中的奖励。
		_speed_recovery_start += gain
		_speed_recovery_target = minf(_speed_recovery_target+gain,maxf(max_move_speed,_base_move_speed))
	if _current_move_speed >= _base_move_speed:
		_clear_low_speed_recovery()
	Speed = _current_move_speed


func _speed_after_obstacle(value:float) -> float:
	return value - maxf(value-_base_move_speed,0.0)*clampf(obstacle_bonus_speed_loss_ratio,0.0,0.25)


func _apply_obstacle_speed_loss() -> void:
	var now:int = Time.get_ticks_msec()
	if now-_last_obstacle_slowdown_msec < 120: return
	_last_obstacle_slowdown_msec = now
	_current_move_speed = _speed_after_obstacle(_current_move_speed)
	if _speed_recovery_active:
		_speed_recovery_start = _speed_after_obstacle(_speed_recovery_start)
		_speed_recovery_target = _speed_after_obstacle(_speed_recovery_target)
	Speed = _current_move_speed


func _begin_penetration_speed(passive:bool) -> void:
	if _penetration_budget_active or _speed_recovery_active: return
	_penetration_budget_active = true
	_penetration_accumulated_speed = clampf(_current_move_speed,0.0,maxf(max_move_speed,_base_move_speed))
	_clear_low_speed_recovery()
	var factor:float = maxf(passive_pass_boost_multiplier,active_thrust_pass_boost_multiplier) if passive else active_thrust_pass_boost_multiplier
	var cap_factor:float = maxf(passive_pass_boost_multiplier,active_thrust_pass_boost_cap_vs_max) if passive else active_thrust_pass_boost_cap_vs_max
	_thrust_boost_return_speed = _penetration_accumulated_speed
	_thrust_boost_start_speed = minf(_penetration_accumulated_speed*maxf(factor,1.0),maxf(max_move_speed,_base_move_speed)*maxf(cap_factor,1.0))
	_thrust_boost_elapsed = 0.0
	_thrust_boost_active = true
	_current_move_speed = _thrust_boost_start_speed
	Speed = _current_move_speed


func _end_penetration_speed(hit:bool,passive:bool) -> void:
	if not _penetration_budget_active: return
	var accumulated:float = _penetration_accumulated_speed
	_penetration_budget_active = false
	_thrust_boost_active = false
	if not hit:
		# 空穿/提前中断只移除临时爆发，不能凭空返还受击损失。
		_current_move_speed = minf(_current_move_speed,accumulated)
		Speed = _current_move_speed
		return
	var loss:float = passive_pass_immediate_bonus_speed_loss_ratio if passive else active_circle_pass_bonus_speed_loss_ratio
	var target_speed:float = _base_move_speed + maxf(accumulated-_base_move_speed,0.0)*(1.0-clampf(loss,0.0,0.95))
	_start_speed_recovery(minf(_current_move_speed,target_speed))


func _cancel_penetration_speed() -> void:
	# 击退/眩晕优先，旧爆发和扣速曲线不得在下一帧覆盖新速度。
	if _penetration_budget_active:
		_current_move_speed = minf(_current_move_speed,_penetration_accumulated_speed)
	_penetration_budget_active = false
	_thrust_boost_active = false
	_speed_recovery_active = false
	Speed = _current_move_speed


func _cleanup_attack(clear_attacking:bool = true) -> void:
	if _attack_active:
		_end_penetration_speed(_attack_pass_hit,_attack_pass_trigger == ActiveThrustPassTrigger.FORWARD_PATH)
	if _attack_collision_exception != null and is_instance_valid(_attack_collision_exception):
		remove_collision_exception_with(_attack_collision_exception)
	_attack_collision_exception = null
	_attack_active = false
	_attack_target = null
	_attack_elapsed = 0.0
	_attack_turn_active = false
	_attack_turn_elapsed = 0.0
	_attack_turn_afterimage_elapsed = 0.0
	_attack_pass_through = false
	_attack_pass_hit = false
	_attack_pass_trigger = ActiveThrustPassTrigger.NONE
	_attack_pass_clearance_armed = false
	_attack_pass_target_front_forward = 0.0
	_pass_afterimage_elapsed = 0.0
	_attack_hit_ids.clear()
	_attack_last_tip_position = Vector2.ZERO
	_attack_last_target_position = Vector2.ZERO
	if clear_attacking:
		Attacking = false


func _attack_has_missed_target() -> bool:
	if _attack_turn_active or _attack_pass_hit or not is_instance_valid(_attack_target): return false
	var forward_dir:Vector2 = _attack_direction.normalized()
	if forward_dir.length_squared() < 0.000001: return false
	# 只有目标整个受击框已落到矛尖后面才算擦过；近身及转向阶段不误中止。
	var forward:float = (combat_target_position(_attack_target)-_spear_tip_world_position()).dot(forward_dir)
	return forward < -(_target_hurt_extent_along(_attack_target,forward_dir)+maxf(_tip_world_length(forward_dir)*0.5,1.0))


func _tick_thrust_boost(delta:float) -> void:
	if not _thrust_boost_active:
		return
	_thrust_boost_elapsed += maxf(delta,0.0)
	var duration:float = maxf(active_thrust_pass_boost_duration,0.08)
	var t:float = clampf(_thrust_boost_elapsed / duration,0.0,1.0)
	_current_move_speed = lerpf(_thrust_boost_start_speed,_thrust_boost_return_speed,smoothstep(0.0,1.0,t))
	if t >= 1.0:
		_thrust_boost_active = false
		_current_move_speed = _thrust_boost_return_speed
	Speed = _current_move_speed


func _update_active_thrust_pass_state(direction_override:Vector2 = Vector2.ZERO) -> void:
	if _attack_pass_through or not _attack_active or _speed_recovery_active:
		return
	if _attack_target == null or not is_instance_valid(_attack_target):
		return
	if _current_move_speed < _pass_threshold_speed():
		return
	var trigger:ActiveThrustPassTrigger = _active_thrust_pass_trigger_for_target(_attack_target,direction_override)
	if trigger != ActiveThrustPassTrigger.NONE:
		_attack_pass_trigger = trigger
		_attack_pass_through = true
		_begin_penetration_speed(trigger == ActiveThrustPassTrigger.FORWARD_PATH)


func _active_thrust_pass_trigger_for_target(target:ball,direction_override:Vector2 = Vector2.ZERO) -> ActiveThrustPassTrigger:
	if not is_instance_valid(target) or _current_move_speed < _pass_threshold_speed() or _speed_recovery_active:
		return ActiveThrustPassTrigger.NONE
	var move_dir:Vector2 = direction_override if direction_override.length_squared() > 0.000001 else _attack_direction
	if not _attack_needed_turn:
		return ActiveThrustPassTrigger.FORWARD_PATH if _path_can_hit_target(target,move_dir) else ActiveThrustPassTrigger.NONE
	# 需要转向的这一刺永远归主动；转到正对敌人也不能改领被动奖励。
	var offset:Vector2 = combat_target_position(target)-_attack_detection_center()
	var radial:Vector2 = offset.normalized() if offset.length_squared()>0.000001 else _facing_direction
	var touches_inner:bool = offset.length() <= maxf(high_speed_thrust_pass_inner_radius,0.0)+_target_hurt_extent_along(target,radial)
	return ActiveThrustPassTrigger.RED_CIRCLE if touches_inner or _path_can_hit_target(target,move_dir) else ActiveThrustPassTrigger.NONE


func _path_can_hit_target(target:ball,move_dir:Vector2) -> bool:
	if not is_instance_valid(target) or move_dir.length_squared() <= 0.000001: return false
	move_dir = move_dir.normalized()
	var side_dir:Vector2 = move_dir.orthogonal()
	var offset:Vector2 = combat_target_position(target)-_spear_tip_world_position()
	var forward_extent:float = _target_hurt_extent_along(target,move_dir)
	var side_extent:float = _target_hurt_extent_along(target,side_dir)
	var forward:float = offset.dot(move_dir)
	var corridor:float = side_extent+maxf(_tip_world_width(move_dir)*0.5,0.5)
	var limit:float = _dynamic_attack_radius()+forward_extent+maxf(_tip_world_length(move_dir),1.0)
	return absf(offset.dot(side_dir)) <= corridor and forward >= -forward_extent and forward <= limit


func _attack_detection_center() -> Vector2:
	# 攻击检测圆严格以矛头 Hitbox 的世界中心为圆心。
	# self_hitbox 已经随当前朝向放在矛头位置，因此直接读 global_position，
	# 不再自己把局部 spear_tip_local_distance 与世界坐标混算。
	if self_hitbox != null and is_instance_valid(self_hitbox) and self_hitbox.is_inside_tree():
		return self_hitbox.global_position
	return global_position


func _find_attack_target() -> ball:
	# 检测圆不变。只有距离接近(最近目标+半径15%)的候选之间才考虑顺向偏好。
	var center:Vector2 = _attack_detection_center()
	var radius:float = _dynamic_attack_radius()
	var candidates:Array[ball] = []
	var nearest:float = INF
	for candidate:ball in TOOLS.enemies_in_radius(self,center,maxf(radius,1.0)):
		var distance:float = center.distance_to(combat_target_position(candidate))
		if distance > radius+0.001: continue
		candidates.append(candidate)
		nearest = minf(nearest,distance)
	var best:ball = null
	var best_score:float = INF
	var tie:float = radius*clampf(target_distance_tie_ratio,0.0,0.5)
	for candidate:ball in candidates:
		var distance:float = center.distance_to(combat_target_position(candidate))
		if distance > nearest+tie: continue
		var score:float = _attack_target_score(candidate,distance,tie)
		if score < best_score:
			best = candidate
			best_score = score
	return best


func _attack_target_score(target:ball,distance:float,tie:float) -> float:
	var dir:Vector2 = _current_move_direction().normalized()
	var to_target:Vector2 = (combat_target_position(target)-global_position).normalized()
	var turn_cost:float = (1.0-clampf(dir.dot(to_target),-1.0,1.0))*0.5
	return distance + tie*2.0*_speed_progress()*turn_cost


func get_debug_detection_regions() -> Array[Dictionary]:
	var result:Array[Dictionary] = []
	if health <= 0 or not is_inside_tree():
		return result
	result.append({
		"shape":"circle",
		"position":_attack_detection_center(),
		"radius":_dynamic_attack_radius(),
		"kind":"wood_spear_attack_detection_circle",
	})
	if _current_move_speed >= _pass_threshold_speed():
		result.append({
			"shape":"circle",
			"position":_attack_detection_center(),
			"radius":maxf(high_speed_thrust_pass_inner_radius,0.0),
			"kind":"wood_spear_active_pass_inner_circle",
		})
	return result


func _debug_attack_circle_enabled() -> bool:
	if not is_instance_valid(Game):
		return false
	return bool(Game.Game_Settings.get("Training_Debug_Mode",false))


func _ensure_attack_range_debug_circle() -> void:
	if _attack_range_debug_line != null and is_instance_valid(_attack_range_debug_line):
		return
	var line:= Line2D.new()
	line.name = "木矛_攻击检测圆_调试"
	line.top_level = true
	line.z_index = 500
	line.width = maxf(debug_attack_circle_width,0.5)
	line.default_color = Color(0.12,0.48,1.0,0.92)
	line.visible = false
	add_child(line)
	_attack_range_debug_line = line
	_attack_range_debug_radius = -1.0

	var pass_line:= Line2D.new()
	pass_line.name = "木矛_高速主动刺穿内圈_调试"
	pass_line.top_level = true
	pass_line.z_index = 501
	pass_line.width = maxf(debug_attack_circle_width,0.5)
	pass_line.default_color = Color(1.0,0.16,0.12,0.96)
	pass_line.visible = false
	add_child(pass_line)
	_pass_range_debug_line = pass_line
	_pass_range_debug_radius = -1.0


func _update_attack_range_debug_circle(force_geometry:bool = false) -> void:
	_ensure_attack_range_debug_circle()
	if _attack_range_debug_line == null or not is_instance_valid(_attack_range_debug_line):
		return
	var enabled:bool = health > 0 and _debug_attack_circle_enabled()
	_attack_range_debug_line.visible = enabled
	if _pass_range_debug_line != null and is_instance_valid(_pass_range_debug_line):
		_pass_range_debug_line.visible = enabled and _current_move_speed >= _pass_threshold_speed()
	if not enabled:
		return

	var center:Vector2 = _attack_detection_center()
	_attack_range_debug_line.global_position = center
	_attack_range_debug_line.global_rotation = 0.0
	_attack_range_debug_line.global_scale = Vector2.ONE
	_attack_range_debug_line.width = maxf(debug_attack_circle_width,0.5)
	var radius:float = _dynamic_attack_radius()
	if force_geometry or absf(radius - _attack_range_debug_radius) > 0.05:
		_attack_range_debug_radius = radius
		var segments:int = maxi(debug_attack_circle_segments,24)
		var pts:= PackedVector2Array()
		pts.resize(segments + 1)
		for i:int in range(segments + 1):
			var angle:float = TAU * float(i) / float(segments)
			pts[i] = Vector2(cos(angle),sin(angle)) * radius
		_attack_range_debug_line.points = pts

	if _pass_range_debug_line != null and is_instance_valid(_pass_range_debug_line):
		_pass_range_debug_line.global_position = center
		_pass_range_debug_line.global_rotation = 0.0
		_pass_range_debug_line.global_scale = Vector2.ONE
		_pass_range_debug_line.width = maxf(debug_attack_circle_width,0.5)
		var pass_radius:float = maxf(high_speed_thrust_pass_inner_radius,0.0)
		if force_geometry or absf(pass_radius - _pass_range_debug_radius) > 0.05:
			_pass_range_debug_radius = pass_radius
			var pass_segments:int = maxi(debug_attack_circle_segments,24)
			var pass_pts:= PackedVector2Array()
			pass_pts.resize(pass_segments + 1)
			for j:int in range(pass_segments + 1):
				var pass_angle:float = TAU * float(j) / float(pass_segments)
				pass_pts[j] = Vector2(cos(pass_angle),sin(pass_angle)) * pass_radius
			_pass_range_debug_line.points = pass_pts


func _speed_progress() -> float:
	var denom:float = maxf(max_move_speed - _base_move_speed,0.001)
	return clampf((_current_move_speed - _base_move_speed) / denom,0.0,1.0)


func _dynamic_attack_radius() -> float:
	return maxf(base_attack_radius,1.0) + maxf(speed_attack_radius_bonus,0.0) * _speed_progress()


func _pass_threshold_speed() -> float:
	return _base_move_speed * maxf(pass_speed_threshold_ratio,1.05)


func _self_speed_damage_multiplier() -> float:
	return lerpf(1.0,maxf(self_speed_damage_max_multiplier,1.0),_speed_progress())


func _enemy_velocity_damage_multiplier(target:ball) -> float:
	if target == null or not is_instance_valid(target):
		return 1.0
	var enemy_to_self:Vector2 = global_position - target.global_position
	if enemy_to_self.length_squared() <= 0.000001:
		return 1.0
	var approach_speed:float = target.velocity.dot(enemy_to_self.normalized())
	var reference:float = maxf(enemy_velocity_reference_speed,1.0)
	var raw:float = 1.0 + approach_speed / reference
	return clampf(
		raw,
		clampf(enemy_velocity_damage_min_multiplier,0.05,1.0),
		clampf(enemy_velocity_damage_max_multiplier,1.0,2.0)
	)


func _resolved_damage_against(target:ball,extra_multiplier:float = 1.0) -> float:
	var raw:float = attack_damage(
		_self_speed_damage_multiplier()
		* _enemy_velocity_damage_multiplier(target)
		* maxf(extra_multiplier,0.0)
	)
	if raw <= 0.0:
		return 0.0
	return maxf(raw,maxf(minimum_final_damage,0.0))


func current_hit_damage_multiplier() -> float:
	# 只用于外部威胁/UI读取；真实伤害还会根据“被打者朝向木矛的速度”逐目标计算。
	return _self_speed_damage_multiplier()


# 继承场景 hitbox 的 on_hit 信号会调用这个同名方法；V99 在这里完全接管木矛矛头伤害。
func _on_hitbox_on_hit(hurt:hurtbox) -> void:
	if not is_multiplayer_authority() or health <= 0 or dizziness or is_damage_output_disabled():
		return
	var target:ball = _ball_from_hurtbox(hurt)
	if target == null or not TOOLS.is_enemy(self,target):
		return

	var target_id:int = target.get_instance_id()
	var extra:float = 1.0

	# 矛头始终是伤害碰撞箱：低速普通移动碰到敌人也会按当前双方速度结算一次普通伤害。
	# 顺向穿刺(含Attack内FORWARD_PATH)是2x；转向主动穿刺与普通刺是1x。
	if _attack_active:
		if _attack_hit_ids.has(target_id):
			return
		_attack_hit_ids[target_id] = true
		extra = _penetration_damage_multiplier()
	elif _pass_active or (_current_move_speed >= _pass_threshold_speed() and not _speed_recovery_active):
		if not _pass_active: _start_pass_through(target)
		if _pass_hit_ids.has(target_id): return
		_pass_hit_ids[target_id] = true
		extra = _penetration_damage_multiplier()

	var damage:float = _resolved_damage_against(target,extra)
	if damage <= 0.0:
		return
	# 命中前锁定是否为穿刺及方向类别，不能因回调结束攻击而误领奖励。
	var normal_hit:bool = not _attack_pass_through and not _pass_active and not _penetration_budget_active
	var straight_hit:bool = not _attack_active or not _attack_needed_turn
	var impact:Vector2 = self_hitbox.global_position if self_hitbox != null else global_position
	set_meta("blood_damage_kind","pierce")
	set_meta("blood_attack_velocity",_facing_direction * _current_move_speed)
	if target.receive_positional_damage(damage,impact,false,self):
		if normal_hit:
			_apply_normal_hit_speed_gain(straight_hit)
		_broadcast_hit_sfx(impact)
		var killed_target:bool = target.health <= 0 or (target.state_machine != null and target.state_machine.current_state == State.Die)
		if _attack_active and target == _attack_target:
			if killed_target:
				# 穿透刺击杀也不能立刻恢复碰撞；继续保持碰撞例外直到整个木矛实体穿出。
				if _attack_pass_through:
					_attack_pass_hit = true
					_arm_active_attack_pass_clearance(target)
					_begin_pass_afterimages()
				else:
					_finish_attack_kill_continue()
			elif _attack_pass_through:
				_attack_pass_hit = true
				_arm_active_attack_pass_clearance(target)
				_begin_pass_afterimages()
			else:
				# 普通刺只有“真的刺中且目标还活着”才转头后撤。
				_finish_attack_hit_retreat()
		elif _pass_active and target == _pass_target:
			_pass_hit = true
			_begin_pass_afterimages()


func _ball_from_hurtbox(area:hurtbox) -> ball:
	if area == null or not is_instance_valid(area):
		return null
	var parent_node:Node = area.get_parent()
	if parent_node is ball:
		return parent_node as ball
	if area.owner is ball:
		return area.owner as ball
	return null


func _try_spear_hitbox_overlaps() -> void:
	if self_hitbox == null or not is_instance_valid(self_hitbox) or not self_hitbox.monitoring:
		return
	for raw:Area2D in self_hitbox.get_overlapping_areas():
		if raw is hurtbox:
			self_hitbox.try_hit_hurtbox(raw as hurtbox)


# 矛头 Guard Hurtbox 优先格挡：即便一个大 Hitbox 同时盖到矛身和矛头，只要它碰到 Guard 就整击拒绝。
func should_bypass_duplicate_hit_guard(_incoming_hit:hitbox,contact_hurtbox:hurtbox) -> bool:
	# 矛头 Guard 是优先格挡区：即使同一个大 Hitbox 刚先碰到矛身，也要继续处理矛头接触。
	return spear_tip_guard != null and contact_hurtbox == spear_tip_guard


# 矛头 Guard Hurtbox 优先格挡：即便一个大 Hitbox 同时盖到矛身和矛头，只要它碰到 Guard 就整击拒绝。
func can_receive_hit_contact(incoming_hit:hitbox,contact_hurtbox:hurtbox) -> bool:
	if incoming_hit == null or not is_instance_valid(incoming_hit):
		return true
	if spear_tip_guard != null and is_instance_valid(spear_tip_guard):
		if contact_hurtbox == spear_tip_guard:
			return false
		# 大范围攻击可能先报告矛身再报告 Guard；如果此刻实际已经与 Guard 重叠，也按格挡处理。
		if incoming_hit.monitoring and incoming_hit.overlaps_area(spear_tip_guard):
			return false
		# 兼容极大的来袭 Hitbox：中心明显更靠近矛头时也按矛头格挡。
		if self_hurtbox != null and is_instance_valid(self_hurtbox):
			var hit_pos:Vector2 = incoming_hit.global_position
			if hit_pos.distance_squared_to(spear_tip_guard.global_position) < hit_pos.distance_squared_to(self_hurtbox.global_position):
				return false
	return true


func _spear_guard_feedback_position() -> Vector2:
	if spear_tip_guard != null and is_instance_valid(spear_tip_guard) and spear_tip_guard.is_inside_tree():
		return spear_tip_guard.global_position
	if self_hitbox != null and is_instance_valid(self_hitbox) and self_hitbox.is_inside_tree():
		return self_hitbox.global_position
	return global_position


func _should_emit_spear_guard_feedback(incoming_hit:hitbox) -> bool:
	var hit_id:int = incoming_hit.get_instance_id() if incoming_hit != null and is_instance_valid(incoming_hit) else -1
	var now_msec:int = Time.get_ticks_msec()
	# 同一个大 Hitbox 可能在同一物理步先后碰到矛身与 Guard；只播一次声音/特效。
	if hit_id == _last_block_feedback_hit_id and now_msec - _last_block_feedback_msec < 120:
		return false
	_last_block_feedback_hit_id = hit_id
	_last_block_feedback_msec = now_msec
	return true


# 覆写公共“拒绝命中”反馈：木矛的格挡发生在矛头，而不是角色根节点。
# 明确在矛头位置播放 BlockAtt.ogg + 公共白色格挡爆线 + 一个短促白圈。
func on_incoming_hit_rejected(incoming_hit:hitbox) -> void:
	if incoming_hit == null or not is_instance_valid(incoming_hit):
		return
	if state_machine != null and state_machine.current_state == State.Die:
		return

	var attacker:ball = _incoming_hit_attacker(incoming_hit)
	var impact_position:Vector2 = _spear_guard_feedback_position()
	var source_position:Vector2 = incoming_hit.global_position
	if attacker != null and is_instance_valid(attacker):
		source_position = attacker.global_position
	var travel_direction:Vector2 = impact_position - source_position
	if travel_direction.length_squared() <= 0.000001:
		travel_direction = _facing_direction if _facing_direction.length_squared() > 0.000001 else Vector2.RIGHT

	if _should_emit_spear_guard_feedback(incoming_hit):
		var coverage_width:float = maxf(_estimate_hit_effect_cross_section(incoming_hit,travel_direction),6.0)
		var raw_damage:float = float(attacker.Damage) if attacker != null and is_instance_valid(attacker) else maxf(float(Damage),8.0)
		var seed:int = Game.battle_rng_seed_or(
			"scripts/characters/我的世界/木矛.gd:block_feedback",
			int(Time.get_ticks_usec()) ^ int(get_instance_id()) ^ int(incoming_hit.get_instance_id())
		)
		notify_block_burst_feedback(impact_position,raw_damage,coverage_width,seed)
		_broadcast_block_feedback(impact_position)

	# 沿用公共规则：角色本体近战只被挡住；真正的投射物被矛头格挡后消失。
	if (
		attacker != null
		and is_instance_valid(attacker)
		and _is_ranged_hit_source(attacker)
		and should_destroy_projectile_on_rejected_hit(incoming_hit)
	):
		attacker.on_projectile_blocked_by(self,impact_position)


func can_receive_hit_from(incoming_hit:hitbox) -> bool:
	return can_receive_hit_contact(incoming_hit,null)


func _update_tip_hitbox_monitoring() -> void:
	if self_hitbox == null or not is_instance_valid(self_hitbox):
		return
	# 木矛矛头永远是有效攻击区；死亡时再关闭，避免尸体继续触发接触。
	self_hitbox.monitoring = health > 0


func _prepare_pass_collision_exception() -> void:
	if _attack_active or _pass_active or _speed_recovery_active:
		return
	if _current_move_speed < _pass_threshold_speed():
		return
	var move_dir:Vector2 = _current_move_direction()
	if move_dir.length_squared() <= 0.000001:
		return

	# 只在即将真正撞到的几像素前预先放行实体碰撞；这不是索敌/技能，也不会改方向或加速。
	var tip_front:float = _tip_front_world_distance(move_dir)
	var best:ball = null
	var best_forward:float = INF
	for candidate:ball in TOOLS.enemies_in_radius(self,global_position,tip_front + 48.0):
		var offset:Vector2 = combat_target_position(candidate) - global_position
		var forward:float = offset.dot(move_dir)
		if forward <= 0.0:
			continue
		var lateral:float = absf(offset.cross(move_dir))
		var target_extent:float = _target_hurt_extent_along(candidate,move_dir)
		var contact_forward:float = tip_front + target_extent + maxf(pass_prearm_margin,0.0)
		if forward > contact_forward:
			continue
		# 横向只允许目标真正处在矛头宽度附近。
		var lateral_limit:float = _target_hurt_extent_along(candidate,move_dir.orthogonal()) + maxf(_tip_world_width(move_dir) * 0.5,1.0)
		if lateral > lateral_limit:
			continue
		if forward < best_forward:
			best = candidate
			best_forward = forward
	if best != null:
		_start_pass_through(best)


func _start_pass_through(target:ball) -> void:
	if target == null or not is_instance_valid(target):
		return
	if _pass_active:
		return
	_cleanup_pass(false)
	_pass_active = true
	_pass_target = target
	_pass_hit_ids.clear()
	_begin_penetration_speed(true)
	_pass_direction = _current_move_direction()
	if _pass_direction.length_squared() <= 0.000001:
		_pass_direction = _facing_direction
	if _pass_direction.length_squared() <= 0.000001:
		_pass_direction = Vector2.RIGHT
	_pass_direction = _pass_direction.normalized()
	_pass_elapsed = 0.0
	_pass_hit = false
	_pass_afterimage_elapsed = 0.0
	_pass_target_start_forward = (combat_target_position(target) - global_position).dot(_pass_direction)
	_pass_last_tip_position = _spear_tip_world_position()
	add_collision_exception_with(target)


func _tick_pass_completion(delta:float) -> void:
	if not _pass_active:
		return
	_pass_elapsed += maxf(delta,0.0)
	if _pass_target == null or not is_instance_valid(_pass_target):
		_cleanup_pass(_pass_hit)
		return

	# 预放行可能发生在矛头真正 enter 的前一帧；高速下还可能整帧跨过 Hurtbox。
	_try_spear_hitbox_overlaps()
	_try_pass_swept_tip_hit()
	if not _pass_active: return
	if not is_instance_valid(_pass_target):
		_cleanup_pass(_pass_hit)
		return
	# 与转向穿刺一致：自身实体后缘完全离开目标后再结束，不在身体尚未穿出时扣速。
	var rear_forward:float = global_position.dot(_pass_direction)
	if is_instance_valid(collision_shape_2d) and collision_shape_2d.shape != null:
		rear_forward = collision_shape_2d.global_position.dot(_pass_direction)-_shape_extent_world(collision_shape_2d,_pass_direction)
	var passed:bool = rear_forward >= _target_body_front_forward(_pass_target,_pass_direction)+maxf(pass_clearance_distance,2.0)
	var timed_out:bool = _pass_elapsed >= maxf(pass_timeout,0.10)
	if passed:
		_cleanup_pass(_pass_hit)
	elif timed_out:
		_cleanup_pass(_pass_hit)


func _cleanup_pass(start_recovery:bool) -> void:
	if _pass_active:
		_end_penetration_speed(start_recovery or _pass_hit,true)
	_pass_hit_ids.clear()
	if _pass_target != null and is_instance_valid(_pass_target):
		remove_collision_exception_with(_pass_target)
	_pass_active = false
	_pass_target = null
	_pass_elapsed = 0.0
	_pass_hit = false
	_pass_afterimage_elapsed = 0.0
	_pass_target_start_forward = 0.0
	_pass_last_tip_position = Vector2.ZERO



func _penetration_damage_multiplier() -> float:
	if _pass_active or (_attack_pass_through and _attack_pass_trigger == ActiveThrustPassTrigger.FORWARD_PATH):
		return maxf(pass_damage_multiplier,1.0)
	return 1.0


func _start_speed_recovery(target_speed:float = -1.0) -> void:
	_thrust_boost_active = false
	_thrust_boost_elapsed = 0.0
	_clear_low_speed_recovery()
	_speed_recovery_active = true
	_speed_recovery_elapsed = 0.0
	_speed_recovery_start = maxf(_current_move_speed,0.0)
	_speed_recovery_target = _base_move_speed if target_speed < 0.0 else maxf(target_speed,0.0)


func _tick_speed_recovery(delta:float) -> void:
	if not _speed_recovery_active:
		return
	_speed_recovery_elapsed += maxf(delta,0.0)
	var duration:float = maxf(pass_speed_recovery_time,0.10)
	var t:float = clampf(_speed_recovery_elapsed / duration,0.0,1.0)
	_current_move_speed = lerpf(_speed_recovery_start,_speed_recovery_target,smoothstep(0.0,1.0,t))
	if t >= 1.0:
		_speed_recovery_active = false
		_current_move_speed = _speed_recovery_target
	Speed = _current_move_speed


func _schedule_low_speed_recovery(force_restart:bool = false) -> void:
	if _current_move_speed >= _base_move_speed - 0.001:
		_clear_low_speed_recovery()
		return
	if not force_restart and (_low_speed_recovery_wait > 0.0 or _low_speed_recovery_active): return
	_speed_recovery_active = false
	_low_speed_recovery_wait = maxf(knockback_low_speed_recovery_delay,0.0)
	_low_speed_recovery_active = false
	_low_speed_recovery_elapsed = 0.0
	_low_speed_recovery_start = clampf(_current_move_speed,0.0,_base_move_speed)


func _clear_low_speed_recovery() -> void:
	_low_speed_recovery_wait = 0.0
	_low_speed_recovery_active = false
	_low_speed_recovery_elapsed = 0.0
	_low_speed_recovery_start = _base_move_speed


func _tick_low_speed_recovery(delta:float) -> void:
	if _current_move_speed >= _base_move_speed - 0.001:
		_clear_low_speed_recovery()
		return
	if dizziness or _speed_recovery_active or _thrust_boost_active:
		return
	var dt:float = maxf(delta,0.0)
	if _low_speed_recovery_wait > 0.0:
		_low_speed_recovery_wait = maxf(_low_speed_recovery_wait - dt,0.0)
		return
	if not _low_speed_recovery_active:
		_low_speed_recovery_active = true
		_low_speed_recovery_elapsed = 0.0
		_low_speed_recovery_start = clampf(_current_move_speed,0.0,_base_move_speed)
	_low_speed_recovery_elapsed += dt
	var duration:float = maxf(knockback_low_speed_recovery_duration,0.05)
	_current_move_speed = move_toward(_current_move_speed,_base_move_speed,_base_move_speed/duration*dt)
	if _current_move_speed >= _base_move_speed-0.001:
		_current_move_speed = _base_move_speed
		_clear_low_speed_recovery()


func _reset_speed_to_base() -> void:
	_penetration_budget_active = false
	_thrust_boost_active = false
	_thrust_boost_elapsed = 0.0
	_thrust_boost_start_speed = 0.0
	_thrust_boost_return_speed = 0.0
	_current_move_speed = _base_move_speed
	_speed_recovery_active = false
	_speed_recovery_elapsed = 0.0
	_speed_recovery_start = _base_move_speed
	_clear_low_speed_recovery()
	Speed = _base_move_speed
	_use_speed_sfx_latched = false
	_update_tip_hitbox_monitoring()


func _spear_tip_world_position() -> Vector2:
	if self_hitbox != null and is_instance_valid(self_hitbox) and self_hitbox.is_inside_tree():
		return self_hitbox.global_position
	return global_position


func _target_primary_hurtbox(target:ball) -> hurtbox:
	if target == null or not is_instance_valid(target):
		return null
	if target.self_hurtbox != null and is_instance_valid(target.self_hurtbox):
		return target.self_hurtbox
	var node:= target.get_node_or_null("hurtbox")
	return node as hurtbox if node is hurtbox else null


func _distance_point_to_segment(point:Vector2,a:Vector2,b:Vector2) -> float:
	var ab:Vector2 = b - a
	var len_sq:float = ab.length_squared()
	if len_sq <= 0.000001:
		return point.distance_to(a)
	var t:float = clampf((point - a).dot(ab) / len_sq,0.0,1.0)
	return point.distance_to(a + ab * t)


func _swept_tip_reaches_target(target:ball,from_tip:Vector2,to_tip:Vector2) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var travel:Vector2 = to_tip - from_tip
	var axis:Vector2 = travel.normalized() if travel.length_squared() > 0.000001 else _facing_direction
	if axis.length_squared() <= 0.000001:
		axis = Vector2.RIGHT
	var perpendicular:Vector2 = axis.orthogonal()
	var hurt_extent_forward:float = _target_hurt_extent_along(target,axis)
	var hurt_extent_side:float = _target_hurt_extent_along(target,perpendicular)
	var tip_half_width:float = maxf(_tip_world_width(axis) * 0.5,0.5)
	# 用侧向外接半径做保守 swept 检测：只兜底“高速跳帧穿过”，不扩大正常攻击范围。
	var swept_radius:float = maxf(hurt_extent_side,2.0) + tip_half_width
	return _distance_point_to_segment(combat_target_position(target),from_tip,to_tip) <= swept_radius


func _swept_tip_reaches_moving_target(target:ball,from_tip:Vector2,to_tip:Vector2,from_target:Vector2,to_target:Vector2) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	# 在“目标自身移动的参考系”里检查矛尖轨迹。这样敌人横向移动时，不会因为两者都在动而漏掉同一物理帧内的真实交叉。
	var relative_from:Vector2 = from_tip - from_target
	var relative_to:Vector2 = to_tip - to_target
	var relative_travel:Vector2 = relative_to - relative_from
	var axis:Vector2 = relative_travel.normalized() if relative_travel.length_squared() > 0.000001 else _facing_direction
	if axis.length_squared() <= 0.000001:
		axis = Vector2.RIGHT
	var perpendicular:Vector2 = axis.orthogonal()
	var hurt_extent_side:float = _target_hurt_extent_along(target,perpendicular)
	var tip_half_width:float = maxf(_tip_world_width(axis) * 0.5,0.5)
	var swept_radius:float = maxf(hurt_extent_side,2.0) + tip_half_width
	return _distance_point_to_segment(Vector2.ZERO,relative_from,relative_to) <= swept_radius


func _try_attack_swept_tip_hit() -> void:
	# V115：所有主动刺都做连续矛尖轨迹检测，不再只给“高速主动刺穿”兜底。
	# 同时把目标上一帧/当前帧的位置纳入相对运动，移动敌人不会从窄矛尖旁边按离散帧漏过去。
	if not _attack_active or _attack_target == null or not is_instance_valid(_attack_target):
		_attack_last_tip_position = _spear_tip_world_position()
		_attack_last_target_position = Vector2.ZERO
		return
	var target_id:int = _attack_target.get_instance_id()
	if _attack_hit_ids.has(target_id):
		_attack_last_tip_position = _spear_tip_world_position()
		_attack_last_target_position = combat_target_position(_attack_target)
		return
	var now_tip:Vector2 = _spear_tip_world_position()
	var now_target:Vector2 = combat_target_position(_attack_target)
	if _attack_last_tip_position == Vector2.ZERO or _attack_last_target_position == Vector2.ZERO:
		_attack_last_tip_position = now_tip
		_attack_last_target_position = now_target
		return
	if _swept_tip_reaches_moving_target(
		_attack_target,
		_attack_last_tip_position,
		now_tip,
		_attack_last_target_position,
		now_target
	):
		var hurt:hurtbox = _target_primary_hurtbox(_attack_target)
		if hurt != null and self_hitbox != null:
			self_hitbox.try_hit_hurtbox(hurt)
	_attack_last_tip_position = now_tip
	_attack_last_target_position = now_target


func _try_pass_swept_tip_hit() -> void:
	if not _pass_active or _pass_hit or _pass_target == null or not is_instance_valid(_pass_target):
		_pass_last_tip_position = _spear_tip_world_position()
		return
	var now_tip:Vector2 = _spear_tip_world_position()
	if _pass_last_tip_position == Vector2.ZERO:
		_pass_last_tip_position = now_tip
		return
	if _swept_tip_reaches_target(_pass_target,_pass_last_tip_position,now_tip):
		var hurt:hurtbox = _target_primary_hurtbox(_pass_target)
		if hurt != null and self_hitbox != null:
			self_hitbox.try_hit_hurtbox(hurt)
	_pass_last_tip_position = now_tip


# 公共 ball.when_collide() 会先完成一次正常反弹。木矛只负责在“穿越状态撞墙”时立刻退出锁向状态，
# 避免下一帧又把 direction 强制改回原穿越方向，从而连续贴墙反弹。
func when_collide(speed:float,collision:KinematicCollision2D):
	super.when_collide(speed,collision)
	if not is_multiplayer_authority() or collision == null:
		return
	var collider = collision.get_collider()
	var bounced_direction:Vector2 = direction
	# 普通角色实体碰撞也要做短暂转向动画，但不触发下面“撞墙中断刺/穿越”的清理。
	if collider is ball:
		if bounced_direction.length_squared() > 0.000001:
			direction = bounced_direction.normalized()
			_start_collision_turn_animation(direction)
		return
	if _attack_active:
		_cleanup_attack(false)
		Attacking = false
	if _pass_active:
		_cleanup_pass(_pass_hit)
	_apply_obstacle_speed_loss()
	if bounced_direction.length_squared() > 0.000001:
		direction = bounced_direction.normalized()
		_start_collision_turn_animation(direction)


func _start_collision_turn_animation(target_direction:Vector2) -> void:
	if target_direction.length_squared() <= 0.000001:
		return
	var target_dir:Vector2 = target_direction.normalized()
	var start_angle:float = _facing_direction.angle()
	var target_angle:float = target_dir.angle()
	var delta_angle:float = absf(wrapf(target_angle - start_angle,-PI,PI))
	if delta_angle <= deg_to_rad(maxf(collision_turn_skip_below_degrees,0.0)):
		_collision_turn_active = false
		_collision_turn_elapsed = 0.0
		_set_facing_direction(target_dir)
		return
	_collision_turn_active = true
	_collision_turn_elapsed = 0.0
	_collision_turn_start_angle = start_angle
	_collision_turn_target_angle = target_angle


func _tick_collision_turn_animation(delta:float) -> void:
	if not _collision_turn_active:
		return
	var duration:float = maxf(collision_turn_duration,0.03)
	_collision_turn_elapsed = minf(_collision_turn_elapsed + maxf(delta,0.0),duration)
	var t:float = clampf(_collision_turn_elapsed / duration,0.0,1.0)
	var eased:float = smoothstep(0.0,1.0,t)
	var angle:float = lerp_angle(_collision_turn_start_angle,_collision_turn_target_angle,eased)
	_set_facing_direction(Vector2.RIGHT.rotated(angle))
	if t >= 1.0:
		_collision_turn_active = false
		_collision_turn_elapsed = 0.0
		_set_facing_direction(Vector2.RIGHT.rotated(_collision_turn_target_angle))


func _current_move_direction() -> Vector2:
	var value:Vector2 = player_control_direction if is_player_controlled() else direction
	if value.length_squared() <= 0.000001:
		value = _facing_direction
	return value.normalized() if value.length_squared() > 0.000001 else Vector2.RIGHT


func _set_facing_direction(value:Vector2) -> void:
	if value.length_squared() <= 0.000001:
		return
	_facing_direction = value.normalized()
	set_character_visual_flip_h(false)
	var angle:float = _facing_direction.angle()
	if spear_sprite != null:
		spear_sprite.rotation = angle + deg_to_rad(visual_rotation_offset_degrees)
	if self_hitbox != null:
		self_hitbox.position = _facing_direction * maxf(spear_tip_local_distance,0.0)
		self_hitbox.rotation = angle
	if spear_tip_guard != null:
		spear_tip_guard.position = _facing_direction * maxf(spear_tip_local_distance,0.0)
		spear_tip_guard.rotation = angle
	if self_hurtbox != null:
		self_hurtbox.position = _facing_direction * shaft_local_center_offset
		self_hurtbox.rotation = angle
	if collision_shape_2d != null:
		collision_shape_2d.position = _facing_direction * shaft_local_center_offset
		collision_shape_2d.rotation = angle


func _shape_extent_world(shape_node:CollisionShape2D,world_direction:Vector2) -> float:
	if shape_node == null or shape_node.shape == null:
		return 0.0
	var safe_dir:Vector2 = world_direction.normalized() if world_direction.length_squared() > 0.000001 else Vector2.RIGHT
	var local_dir:Vector2 = safe_dir.rotated(-shape_node.global_rotation)
	var sx:float = maxf(shape_node.global_transform.x.length(),0.0001)
	var sy:float = maxf(shape_node.global_transform.y.length(),0.0001)
	if shape_node.shape is RectangleShape2D:
		var rect:= shape_node.shape as RectangleShape2D
		var half:= Vector2(rect.size.x * 0.5 * sx,rect.size.y * 0.5 * sy)
		return absf(local_dir.x) * half.x + absf(local_dir.y) * half.y
	if shape_node.shape is CircleShape2D:
		return (shape_node.shape as CircleShape2D).radius * maxf(sx,sy)
	if shape_node.shape is CapsuleShape2D:
		var capsule:= shape_node.shape as CapsuleShape2D
		var half_width:float = capsule.radius * sx
		var half_height:float = maxf(capsule.height * 0.5,capsule.radius) * sy
		return absf(local_dir.x) * half_width + absf(local_dir.y) * half_height
	return 0.0


func _tip_front_world_distance(world_direction:Vector2) -> float:
	if self_hitbox == null or not is_instance_valid(self_hitbox):
		return 0.0
	var safe_dir:Vector2 = world_direction.normalized() if world_direction.length_squared() > 0.000001 else _facing_direction
	var center_distance:float = (self_hitbox.global_position - global_position).dot(safe_dir)
	var shape_node := self_hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	return maxf(center_distance + _shape_extent_world(shape_node,safe_dir),0.0)


func _tip_world_length(world_direction:Vector2) -> float:
	if self_hitbox == null:
		return 1.0
	var node := self_hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	return maxf(_shape_extent_world(node,world_direction) * 2.0,0.5)


func _tip_world_width(world_direction:Vector2) -> float:
	var perpendicular:Vector2 = world_direction.normalized().orthogonal()
	return _tip_world_length(perpendicular)


func _target_hurt_extent_along(target:ball,world_direction:Vector2) -> float:
	if target == null or not is_instance_valid(target):
		return 8.0
	var hurt_area:Area2D = target.get_node_or_null("hurtbox") as Area2D
	if hurt_area == null:
		return 8.0
	var best:float = 0.0
	for child:Node in hurt_area.get_children():
		if child is CollisionShape2D:
			var shape_node:= child as CollisionShape2D
			if not shape_node.disabled:
				best = maxf(best,_shape_extent_world(shape_node,world_direction))
	return maxf(best,2.0)


func _update_use_speed_sfx_state() -> void:
	var threshold:float = _pass_threshold_speed()
	if _current_move_speed >= threshold:
		if not _use_speed_sfx_latched:
			_use_speed_sfx_latched = true
			_broadcast_use_sfx()
	else:
		var margin:float = maxf(_base_move_speed * 0.05,3.0)
		if _current_move_speed <= threshold - margin:
			_use_speed_sfx_latched = false


func _random_sfx_pitch() -> float:
	var variation:float = clampf(sfx_pitch_variation,0.0,0.12)
	return _sfx_rng.randf_range(1.0 - variation,1.0 + variation)


func _broadcast_attack_sfx() -> void:
	if ATTACK_SFX.is_empty():
		return
	var index:int = _sfx_rng.randi_range(0,ATTACK_SFX.size() - 1)
	var pitch:float = _random_sfx_pitch()
	_play_wood_spear_sfx_local(0,index,global_position,pitch)
	if multiplayer.has_multiplayer_peer():
		_rpc_play_wood_spear_sfx.rpc(0,index,global_position,pitch)


func _broadcast_hit_sfx(world_position:Vector2) -> void:
	if HIT_SFX.is_empty():
		return
	var index:int = _sfx_rng.randi_range(0,HIT_SFX.size() - 1)
	var pitch:float = _random_sfx_pitch()
	_play_wood_spear_sfx_local(1,index,world_position,pitch)
	if multiplayer.has_multiplayer_peer():
		_rpc_play_wood_spear_sfx.rpc(1,index,world_position,pitch)


func _broadcast_use_sfx() -> void:
	var pitch:float = _random_sfx_pitch()
	_play_wood_spear_sfx_local(2,0,global_position,pitch)
	if multiplayer.has_multiplayer_peer():
		_rpc_play_wood_spear_sfx.rpc(2,0,global_position,pitch)


func _broadcast_block_feedback(world_position:Vector2) -> void:
	var pitch:float = _random_sfx_pitch()
	_play_spear_block_feedback_local(world_position,pitch)
	if multiplayer.has_multiplayer_peer():
		_rpc_play_spear_block_feedback.rpc(world_position,pitch)


@rpc("authority","call_remote","reliable")
func _rpc_play_spear_block_feedback(world_position:Vector2,pitch:float) -> void:
	_play_spear_block_feedback_local(world_position,pitch)


func _play_spear_block_feedback_local(world_position:Vector2,pitch:float) -> void:
	_play_world_sfx(BLOCK_SFX,world_position,block_sfx_volume_db,pitch)
	_spawn_spear_block_ring_local(world_position)


func _spawn_spear_block_ring_local(world_position:Vector2) -> void:
	if not is_inside_tree():
		return
	var parent:Node = get_tree().current_scene
	if parent == null:
		return
	var ring:= Line2D.new()
	ring.name = "木矛_矛头格挡白圈"
	ring.top_level = true
	ring.z_index = 520
	ring.width = 0.95
	ring.default_color = Color(1.0,1.0,1.0,0.96)
	ring.antialiased = true
	var segments:int = 20
	var points:= PackedVector2Array()
	points.resize(segments + 1)
	for i:int in range(segments + 1):
		var angle:float = TAU * float(i) / float(segments)
		points[i] = Vector2(cos(angle),sin(angle)) * 3.2
	ring.points = points
	parent.add_child(ring)
	ring.global_position = world_position
	ring.scale = Vector2(0.65,0.65)
	var tween:= ring.create_tween().set_parallel(true)
	tween.tween_property(ring,"scale",Vector2(2.15,2.15),0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring,"modulate",Color(1.0,1.0,1.0,0.0),0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(ring.queue_free)


@rpc("authority","call_remote","unreliable")
func _rpc_play_wood_spear_sfx(kind:int,index:int,world_position:Vector2,pitch:float) -> void:
	_play_wood_spear_sfx_local(kind,index,world_position,pitch)


func _play_wood_spear_sfx_local(kind:int,index:int,world_position:Vector2,pitch:float) -> void:
	var stream:AudioStream = null
	var volume_db:float = 0.0
	match kind:
		0:
			if index < 0 or index >= ATTACK_SFX.size():
				return
			stream = ATTACK_SFX[index]
			volume_db = attack_sfx_volume_db
		1:
			if index < 0 or index >= HIT_SFX.size():
				return
			stream = HIT_SFX[index]
			volume_db = hit_sfx_volume_db
		2:
			stream = USE_SFX
			volume_db = use_sfx_volume_db
		_:
			return
	_play_world_sfx(stream,world_position,volume_db,pitch)


func _play_world_sfx(stream:AudioStream,world_position:Vector2,volume_db:float = 0.0,pitch:float = 1.0) -> void:
	if stream == null or not is_inside_tree():
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.max_distance = maxf(sfx_max_distance,1.0)
	player.attenuation = 0.70
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	add_child(player)
	player.top_level = true
	player.global_position = world_position
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func Die() -> void:
	_cleanup_attack(true)
	_cleanup_pass(false)
	super.Die()
