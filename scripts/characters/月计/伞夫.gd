extends MoonSanityCharacter

const OPENING_GREETING_AUDIO:AudioStream = preload("res://audio/characters/月计/伞夫/开场问候.ogg")
const OPENING_GREETING_TEXT:String = "UMBRELLA_MAN_OPENING_GREETING"

# V73：攻击音效拆成“挥舞”和“打到”两层。
# 挥舞声在该段攻击动作执行时播放；打到声只有真实伤害结算成功后才播放。
# create_new_audio=true，确保长尾、连续多段和多个伞夫同时攻击时不会互相截断。
const ATTACK1_STAGE1_SWING_SFX:String = "伞夫攻击1第一段挥舞"
const ATTACK1_STAGE1_HIT_SFX:String = "伞夫攻击1第一段打到"
const ATTACK1_STAGE2_SWING_SFX:String = "伞夫攻击1第二段挥舞"
# 用户指定：攻击1第二段（2_3）挥舞用自己的声音，但命中复用 2_2 的打到声。
const ATTACK1_STAGE2_HIT_SFX:String = "伞夫攻击1第二段打到"
const ATTACK1_STAGE3_SWING_SFX:String = "伞夫攻击1第三段挥舞"
const ATTACK1_STAGE3_HIT_SFX:String = "伞夫攻击1第三段打到"
const ATTACK2_STAGE1_SWING_SFX:String = "伞夫攻击2第一段挥舞"
const ATTACK2_STAGE1_HIT_SFX:String = "伞夫攻击2第一段打到"
const ATTACK2_STAGE2_SWING_SFX:String = "伞夫攻击2第二段挥舞"
const ATTACK2_STAGE2_HIT_SFX:String = "伞夫攻击2第二段打到"

# V77：攻击1 / 攻击2起手语音。一次完整攻击（包含负理智追加段）只在序列起手时判定一次。
# 三种结果等概率：哈1 / 哈2 / 不播放。攻击3不触发。
const ATTACK_VOICE_HA1_SFX:String = "伞夫攻击语音哈1"
const ATTACK_VOICE_HA2_SFX:String = "伞夫攻击语音哈2"

@onready var umbrella_sprite:AnimatedSprite2D = $Graphics/AnimatedSprite2D
@onready var umbrella_visual:Sprite2D = $Graphics/Image

# V75：攻击范围节点不再用带版本号的硬编码 $NodePath；攻击 Shape 同时是起手检测 Shape。
# 运行时会优先读取稳定目录“伞夫攻击范围_直接调整”，并兼容 V61 / V60 旧场景名。
# 这样即使编辑器暂时保留旧场景实例，也不会因为路径版本不一致让整套攻击失效。
var attack1_first_hit_area:Area2D = null
var attack1_first_hit_shape:CollisionShape2D = null
var attack1_second_hit_area:Area2D = null
var attack1_second_hit_shape:CollisionShape2D = null
var attack1_third_hit_area:Area2D = null
var attack1_third_hit_shape:CollisionShape2D = null
var attack2_first_hit_area:Area2D = null
var attack2_first_hit_shape:CollisionShape2D = null
var attack2_second_hit_area:Area2D = null
var attack2_second_hit_shape:CollisionShape2D = null
var attack3_hit_area:Area2D = null
var attack3_hit_shape:CollisionShape2D = null
# V83：编辑器可直接拖拽的攻击3挂人目标点。Marker2D 只定义“想挂的位置”，
# 运行时仍会根据双方真实身体 CollisionShape2D 自动推出重叠区。
var attack3_pin_marker:Marker2D = null
var attack_range_root:Node2D = null

@export_category("伞夫 - V79 攻速 / 攻击范围 / 智能选招")
# 攻击范围本身同时是起手检测与真实伤害范围，所以这里只整体放大真实攻击根节点。
@export_range(1.0,1.5,0.01) var attack_range_scale_multiplier:float = 1.18
# 起手检测允许把整套真实攻击范围在当前左右朝向基础上小幅旋转。
# 会选择能够命中目标 hurtbox 的最小绝对转角，并在本次攻击期间锁定。
@export_range(0.0,30.0,0.5) var attack_turn_max_degrees:float = 15.0
@export_range(1.0,10.0,0.5) var attack_turn_step_degrees:float = 3.0

@export_category("伞夫 - 开场问候")
@export_range(0.5,8.0,0.05) var greeting_text_reveal_duration:float = 3.25
@export_range(0.0,5.0,0.05) var greeting_text_hold_duration:float = 1.35
@export_range(0.1,3.0,0.05) var greeting_text_fade_duration:float = 0.70
@export_range(-24.0,12.0,0.5) var greeting_voice_volume_db:float = 0.0


@export_category("伞夫 - 寻敌")
# target_search_range 只决定平时多远开始追人；能不能出招完全由对应攻击 Shape 是否覆盖敌方 hurtbox 决定。
@export_range(100.0,800.0,5.0) var target_search_range:float = 520.0

# V61：不使用脚本里的半径/尺寸/偏移代理参数。
# 请直接在场景树“伞夫攻击范围_直接调整”下编辑真实 CollisionShape2D。
# Position / Rotation / Scale / Shape 资源本身都会直接参与实际命中和威胁显示。

@export_category("攻击1 - 负理智追加段数")
# V66：
# - sanity >= -10：只结算第一段。
# - sanity < -10：结算第一、第二段。
# - sanity < -20：结算第一、第二、第三段。
# 段数在攻击起手时锁定，避免前一段命中后理智变化导致连段中途改变。
# 三个命中范围完全由场景里的三个真实 CollisionShape2D 决定，不在脚本里写死半径。
@export_range(0.0,10.0,0.05) var attack1_damage_multiplier:float = 1.0967742
@export_range(0,21,1) var attack1_first_hit_frame:int = 3
@export_range(0,21,1) var attack1_second_hit_frame:int = 7
@export_range(0,21,1) var attack1_third_hit_frame:int = 16
# V74：动作分段边界由用户确认：0-5 / 6-13 / 14-21。
# 理智只允许 1/2 段时，要把当前段完整播到对应末帧，再停留一下后回 Idle。
@export_range(0,21,1) var attack1_first_segment_end_frame:int = 5
@export_range(0,21,1) var attack1_second_segment_end_frame:int = 13
@export_range(0,21,1) var attack1_third_segment_end_frame:int = 21

@export_category("攻击2 - 负理智追加第二段")
# V66：sanity >= -10 只结算第一段；sanity < -10 才追加第二段。
@export_range(0.0,10.0,0.05) var attack2_damage_multiplier_per_hit:float = 1.0
@export_range(0,4,1) var attack2_first_hit_frame:int = 1
@export_range(0,4,1) var attack2_second_hit_frame:int = 3
# V74：攻击2动作分段边界由用户确认：0-1 / 2-4。
@export_range(0,4,1) var attack2_first_segment_end_frame:int = 1
@export_range(0,4,1) var attack2_second_segment_end_frame:int = 4

@export_category("伞夫 - 攻击结束姿势")
# 最后一段播到自己的末帧后短暂停留，避免命中后瞬间跳回 Idle。
@export_range(0.0,0.8,0.01) var attack_end_hold_seconds:float = 0.10

@export_category("伞夫 - V66 连段理智门槛")
# “低于”使用严格 <：恰好 -10 仍是一段，恰好 -20 仍是两段。
@export_range(-45.0,0.0,1.0) var second_hit_sanity_threshold:float = -10.0
@export_range(-45.0,0.0,1.0) var attack1_third_hit_sanity_threshold:float = -20.0

@export_category("攻击3 - 跑过去叉起")
# V79：攻击3是位移技，起手检测不能再等同于最终红色伤害框。
# 蓝色 engage_range 表示“允许开始冲刺”的真实技能检测距离；最终伤害仍只由攻击3范围 CollisionShape2D 结算。
@export_range(100.0,600.0,5.0) var attack3_engage_range:float = 340.0
@export_range(100.0,1200.0,10.0) var attack3_dash_speed:float = 760.0
@export_range(10.0,100.0,1.0) var attack3_stop_distance:float = 42.0
@export_range(0.1,1.0,0.01) var attack3_dash_max_seconds:float = 0.42
# SpriteFrames 的 Attack3 只有 10 帧（索引 0~9）；旧值 17 永远达不到，会把动作拖到 watchdog。
# 这里的 3 对应素材序列里的 frame_0017，作为叉起动作进入有效姿势的参考帧。
@export_range(0,9,1) var attack3_hit_frame:int = 3
@export_range(0.0,10.0,0.05) var attack3_damage_multiplier:float = 2.9677419
# V80：攻击3命中后先把敌人固定在伞上；只有 Attack3 动画真正结束后才释放并开始这段眩晕。
@export_range(0.0,2.0,0.05) var attack3_stun_duration:float = 0.45
# V83：优先使用场景里的 Marker2D：
# 伞夫攻击范围_直接调整/攻击3敌人固定点_编辑器拖这里
# 以后在 2D 编辑器里直接拖这个十字即可改挂人位置，不再需要猜 Vector2。
# attack3_pin_offset 只作为旧场景没有 Marker2D 时的兼容后备。
@export var attack3_pin_offset:Vector2 = Vector2(75.0, -20.0)
# 如果编辑器 Marker 放得过近导致目标身体碰撞框与伞夫身体碰撞框相交，运行时沿 Marker 方向自动向外调整。
@export_range(0.0,48.0,1.0) var attack3_pin_safe_margin:float = 10.0
@export_range(1.0,12.0,1.0) var attack3_pin_adjust_step:float = 3.0
@export_range(40.0,360.0,5.0) var attack3_pin_adjust_max_distance:float = 240.0

@export_category("伞夫 - V57 防卡死")
# 攻击动画如果被外部状态/动画异常打断，不允许协程永久等待导致 Attacking 一直为 true。
@export_range(1.0,12.0,0.25) var attack_action_watchdog_seconds:float = 6.0

@export_category("伞夫 - 沉沦与负理智")
@export_range(1,20,1) var self_sinking_max:int = 10
@export_range(1,10,1) var attack3_self_sinking:int = 6
@export_range(0.0,10.0,0.5) var self_sinking_sp_loss:float = 2.0
@export_range(0.2,4.0,0.05) var self_sinking_tick:float = 1.25

@export_category("伞夫 - V56 理智伤害机制")
# 用户指定的离散规则：
# - 0 ~ +45 理智：造成伤害 -20%，受到伤害 +20%。
# - -45 理智：造成伤害 +100%（即最终 x2）。
# - (-45, 0) 不额外修改伤害；这里不擅自做线性插值。
@export_range(0.0,45.0,1.0) var positive_sanity_upper:float = 45.0
@export_range(0.0,1.0,0.05) var positive_sanity_damage_reduction:float = 0.20
@export_range(0.0,1.0,0.05) var positive_sanity_incoming_increase:float = 0.20
@export_range(-45.0,0.0,1.0) var max_negative_sanity_trigger:float = -45.0
@export_range(0.0,3.0,0.05) var max_negative_sanity_damage_bonus:float = 1.00

# 原作技能袋比例：S1×3 / S2×2 / S3×1。
var _skill_bag:Array[int] = [1,1,1,2,2,3]
var _skill_index:int = 0
var _self_sinking:int = 0
var _sinking_elapsed:float = 0.0
var _opening_greeting_handled:bool = false
var _action_serial:int = 0

# V80：攻击3“叉在伞上”的控制锁。
# 复用通用 KnockbackEffect 的 motion-lock metadata 名称，确保和其他击退/眩晕锁能正确叠加，
# 但固定期间不显示眩晕星星；只有攻击结束释放后才调用 apply_stun()。
const ATTACK3_CONTROL_LOCK_META:StringName = &"generic_motion_lock_count"
const ATTACK3_CONTROL_BASELINE_META:StringName = &"generic_motion_lock_baseline"
var _attack3_pinned_target:ball = null
var _attack3_pin_serial:int = -1
var _attack3_pin_lock_acquired:bool = false
# V81：保存真实命中瞬间在 Attack3 Area 本地空间里的位置，避免吸到伤害框中心。
# 固定期间暂时让目标 CharacterBody2D 不参与实体碰撞，避免目标把伞夫挤向墙。
# Hurtbox 是独立 Area2D，不受这里的 CharacterBody2D layer/mask 影响。
var _attack3_saved_collision_layer:int = 0
var _attack3_saved_collision_mask:int = 0
var _attack3_collision_filter_saved:bool = false

# V61：每个攻击动作/段使用独立 Area2D + CollisionShape2D。
# Attack1 现在有三段独立 Area2D，默认范围逐段变大。
# 场景里的真实 Shape 是唯一真值：脚本不回写位置、尺寸、旋转或缩放。
# 威胁显示与真实伤害判定都读取同一批 Shape。
var _attack_hit_active:bool = false
var _active_attack_area:Area2D = null
var _attack_hit_serial:int = 0
var _attack_hit_damage:float = 0.0
var _attack_hit_stun_duration:float = 0.0
# V73：每个真实命中窗口只允许播放一次“打到”音效。
# 即使一段范围同时扫到多名敌人，也不会叠加成爆音。
var _attack_hit_success_sfx:String = ""
var _attack_hit_success_sfx_played:bool = false
var _attack_hit_target_filter_id:int = 0
var _attack_hit_target_ids:Dictionary = {}
# V58：攻击一开始标记本次技能对应的场景碰撞框，让威胁显示高亮真实 Shape。
var _attack_debug_preview_kind:int = 0
var _attack_debug_preview_damage:float = 0.0
var _attack_debug_preview_hit_count:int = 0
var _attack_range_authored_transforms:Dictionary = {}
# V65：攻击范围朝向必须跟随角色“实际视觉朝向”，而不是只在技能锁敌时更新。
# ball.move() 会在普通移动中直接调用 set_character_visual_flip_h()，因此这里记录上次同步状态，
# 让正常移动转身、攻击锁敌转身以及其他系统触发的转身都使用同一套镜像入口。
var _attack_range_facing_initialized:bool = false
var _attack_range_last_face_left:bool = false

# V75：攻击起手检测不再使用独立蓝圈。
# 冷却完成时先查看技能袋“下一招”，再直接用该招本次会启用的真实攻击 Shape 检测目标。
# 只有对应攻击范围真的覆盖敌方 hurtbox 才会进入 Attack，因此检测范围 = 实际攻击范围。
var _pending_attack_skill:int = 0
var _pending_attack_hit_count:int = 1
var _pending_attack_target_id:int = 0
var _pending_attack_aim_rotation:float = 0.0
var _pending_skill_bag_advance:int = 1
var _attack_aim_rotation:float = 0.0
var _attack_range_root_authored_transform:Transform2D = Transform2D.IDENTITY



func _ready() -> void:
	# V70：和殷红迷雾 / 堇紫泪滴一样，ball 的主 image 固定使用 Graphics/Image(Sprite2D)。
	# AnimatedSprite2D 只作为隐藏动画时钟，避免它自己的 offset / 绘制矩形进入公共视觉链。
	image = umbrella_visual
	if umbrella_sprite != null:
		umbrella_sprite.visible = false
	Has_Collision_Damage = false
	Can_Attack = true
	Can_Skill = false
	Health_Restore = 0

	super._ready()

	if umbrella_sprite != null:
		if not umbrella_sprite.frame_changed.is_connected(_on_umbrella_driver_frame_changed):
			umbrella_sprite.frame_changed.connect(_on_umbrella_driver_frame_changed)
		if not umbrella_sprite.animation_changed.is_connected(_on_umbrella_driver_animation_changed):
			umbrella_sprite.animation_changed.connect(_on_umbrella_driver_animation_changed)

	if umbrella_sprite.sprite_frames == null:
		push_error("伞夫：Graphics/AnimatedSprite2D 没有 SpriteFrames。")
	elif not umbrella_sprite.sprite_frames.has_animation(&"Idle"):
		push_error("伞夫：SpriteFrames 缺少 Idle 动画。")
	else:
		_play_anim(&"Idle")

	if self_hitbox != null:
		self_hitbox.monitoring = false

	_resolve_attack_range_nodes()
	_setup_attack_ranges()
	_setup_opening_greeting_trigger()


# V79：冷却完成后按技能袋顺序寻找“当前站位真正可用”的攻击。
# - 攻击1/2：只用第一实际命中段的真实 Shape 判断能否起手，避免后续段能覆盖却第一段打空。
# - 攻击3：属于位移技，使用真实冲刺 engage_range 起手；最终伤害仍只看红色 Attack3 Shape。
# 当前技能袋格子打不到时会向后跳过，直到找到能用的攻击；若全部不能用则保留已蓄满冷却。
func get_next_state(state:State) -> int:
	if is_player_controlled():
		_clear_pending_attack()
		return super.get_next_state(state)
	if (
		is_multiplayer_authority()
		and is_combat_runtime_active()
		and not Attacking
		and Can_Attack
		and not is_damage_output_disabled()
		and state_machine != null
		and state_machine.last_state_dis.Attack >= Attack_Cooling
	):
		# V79：不再强迫“技能袋下一格”在当前站位硬出招。
		# 从当前技能袋位置向后扫描，跳过此刻第一实际命中段无法覆盖任何敌人的攻击。
		# 攻击1/2只用第一段真实伤害 Shape 判断能否起手；攻击3则用真实冲刺 engage_range。
		var selection:Dictionary = _select_reachable_skill_target()
		if selection.is_empty():
			_clear_pending_attack()
			var saved_attack_timer:float = float(state_machine.last_state_dis.Attack)
			Can_Attack = false
			var next_state:int = super.get_next_state(state)
			Can_Attack = true
			state_machine.last_state_dis.Attack = saved_attack_timer
			return next_state

		_pending_attack_skill = int(selection.get("skill",0))
		_pending_attack_hit_count = int(selection.get("hit_count",1))
		_pending_attack_target_id = int(selection.get("target_id",0))
		_pending_attack_aim_rotation = float(selection.get("aim_rotation",0.0))
		_pending_skill_bag_advance = maxi(int(selection.get("bag_advance",1)),1)
		var next_state:int = super.get_next_state(state)
		if next_state != State.Attack:
			_clear_pending_attack()
		return next_state

	return super.get_next_state(state)


# 与项目已有的 战士.gd 同一思路：
# 状态切换时直接控制 ball 自带的 AnimatedSprite2D。
func transition_state(from:State,to:State) -> void:
	super(from,to)

	if umbrella_sprite == null or umbrella_sprite.sprite_frames == null:
		return

	match to:
		State.Move, State.Stand:
			if not Attacking:
				_play_anim(&"Idle")
		State.Hurt:
			if not Attacking:
				_play_anim(&"Idle")
		State.Die:
			umbrella_sprite.stop()


# V64：非攻击移动完全回归项目公共 ball/world 逻辑。
# 伞夫不在角色脚本里持续追踪 Nearest_Enemy；冷却完成时才用下一招的真实攻击 Shape 做起手检测。
# World 负责与其他普通角色相同的随机移动方向；ball.move() 负责正常实体碰撞和反弹。
# 这里仅保留伞夫自己的沉沦计时，不改 direction / Speed / velocity。
func tick_physics(state:State,delta:float) -> void:
	_tick_self_sinking(delta)
	# V81：已经叉住敌人后，伞夫自己也必须停止普通 AI 位移。
	# 否则父类 Attack 状态仍可能沿旧 direction 调用 move_and_slide()，把“挂在伞上的目标”一起挤向墙。
	if _attack3_pinned_target != null and is_instance_valid(_attack3_pinned_target):
		direction = Vector2.ZERO
		velocity = Vector2.ZERO
		Repel = Vector2.ZERO
	super(state,delta)
	# V65 兜底：公共 ball.move() 会根据 direction 更新人物左右朝向。
	# 无论父类内部的方法分派顺序如何，本物理帧结束前都再次确认真实碰撞框与视觉朝向一致。
	_sync_attack_range_facing_if_needed()
	_sync_umbrella_visual_from_driver()
	# V82：固定点使用攻击3真实 Shape 上的固定“伞上锚点”，命中后敌人会被直接移过去。
	_update_attack3_pinned_target()


func Attack() -> void:
	super()

	if (
		not is_multiplayer_authority()
		or health <= 0
		or is_damage_output_disabled()
		or not is_combat_runtime_active()
	):
		Attacking = false
		_clear_pending_attack()
		return

	# V130：直接控制不经过 AI 的“技能 + 目标”选择器。技能袋顺序仍保留，
	# 但方向完全由鼠标决定，而且没有敌人也允许把当前攻击打向空地。
	if has_player_control_aim():
		var manual_skill:int = _peek_next_skill()
		var manual_hit_count:int = _attack_hit_count_for_skill(manual_skill)
		_consume_next_skill(1)
		_clear_pending_attack()
		Attacking = true
		var manual_aim:Vector2 = player_control_aim_direction(direction)
		_set_manual_attack_aim_direction(manual_aim)
		direction = Vector2.ZERO
		_action_serial += 1
		var manual_serial:int = _action_serial
		_prepare_attack_debug_preview(manual_skill,null,manual_hit_count)
		match manual_skill:
			1:
				_attack1_sequence(manual_serial,manual_hit_count)
			2:
				_attack2_sequence(null,manual_serial,manual_hit_count)
			3:
				_attack3_sequence_manual(manual_serial,manual_aim)
		return

	# V79：优先复用 get_next_state() 已验证的“技能 + 目标”。
	# 如果状态切换这一瞬间目标已经离开该招真实可用范围，就重新智能选招，不硬放一个注定打空的动作。
	var skill:int = _pending_attack_skill
	var hit_count:int = _pending_attack_hit_count
	var bag_advance:int = _pending_skill_bag_advance
	var target:ball = null
	if _pending_attack_target_id != 0:
		var pending_instance:Object = instance_from_id(_pending_attack_target_id)
		if pending_instance is ball:
			target = pending_instance as ball

	var pending_still_valid:bool = (
		skill > 0
		and target != null
		and _is_enemy(target)
		and _can_skill_start_on_target(skill,target)
	)
	if pending_still_valid:
		# _can_skill_start_on_target() 已为攻击1/2留下当前帧真正能命中的最小转角；
		# 不再用上一状态帧缓存的旧转角覆盖它。
		if skill == 3:
			_set_attack_aim_rotation(0.0)
	else:
		var selection:Dictionary = _select_reachable_skill_target()
		if selection.is_empty():
			if state_machine != null:
				state_machine.last_state_dis.Attack = Attack_Cooling
			Attacking = false
			_clear_pending_attack()
			_set_attack_aim_rotation(0.0)
			return
		skill = int(selection.get("skill",0))
		hit_count = int(selection.get("hit_count",1))
		bag_advance = maxi(int(selection.get("bag_advance",1)),1)
		var selected_target_id:int = int(selection.get("target_id",0))
		var selected_instance:Object = instance_from_id(selected_target_id) if selected_target_id != 0 else null
		if selected_instance is ball:
			target = selected_instance as ball
		_set_attack_aim_rotation(float(selection.get("aim_rotation",0.0)))

	if skill <= 0 or target == null or not _is_enemy(target):
		if state_machine != null:
			state_machine.last_state_dis.Attack = Attack_Cooling
		Attacking = false
		_clear_pending_attack()
		_set_attack_aim_rotation(0.0)
		return

	# 真正开始攻击时才消耗技能袋；被跳过的“当前站位打不到”的格子一起跨过去，
	# 避免下一帧又反复尝试同一个无效攻击。
	_consume_next_skill(bag_advance)
	_clear_pending_attack()

	Attacking = true
	direction = Vector2.ZERO
	_action_serial += 1
	var serial:int = _action_serial
	_prepare_attack_debug_preview(skill,target,hit_count)

	match skill:
		1:
			_attack1_sequence(serial,hit_count)
		2:
			_attack2_sequence(target,serial,hit_count)
		3:
			_attack3_sequence(target,serial)


func _peek_next_skill() -> int:
	return _skill_bag[_skill_index % _skill_bag.size()]


func _consume_next_skill(advance:int = 1) -> void:
	_skill_index += maxi(advance,1)


func _clear_pending_attack() -> void:
	_pending_attack_skill = 0
	_pending_attack_hit_count = 1
	_pending_attack_target_id = 0
	_pending_attack_aim_rotation = 0.0
	_pending_skill_bag_advance = 1


# V79：按技能袋顺序扫描“此刻真正能用的攻击”。
# 攻击1/2依然用第一段实际 CollisionShape2D 与敌方 hurtbox 做 Shape2D.collide；攻击3用真实冲刺起手距离。
func _select_reachable_skill_target() -> Dictionary:
	if _skill_bag.is_empty():
		return {}

	var original_flip:bool = is_character_visual_flipped_h()
	var original_aim:float = _attack_aim_rotation
	for offset:int in range(_skill_bag.size()):
		var skill:int = _skill_bag[(_skill_index + offset) % _skill_bag.size()]
		var hit_count:int = _attack_hit_count_for_skill(skill)
		var target:ball = _nearest_enemy_for_skill_start(skill)
		if target == null:
			continue
		return {
			"skill":skill,
			"hit_count":hit_count,
			"target_id":target.get_instance_id(),
			"aim_rotation":_attack_aim_rotation,
			"bag_advance":offset + 1,
		}

	set_character_visual_flip_h(original_flip)
	_set_attack_aim_rotation(original_aim)
	return {}


func _nearest_enemy_for_skill_start(skill:int) -> ball:
	if skill == 3:
		return _nearest_enemy_for_attack3_engage()
	var first_area:Area2D = null
	match skill:
		1:
			first_area = attack1_first_hit_area
		2:
			first_area = attack2_first_hit_area
	if first_area == null:
		return null
	var start_areas:Array[Area2D] = [first_area]
	return _nearest_enemy_overlapping_attack_areas(start_areas)


func _can_skill_start_on_target(skill:int,candidate:ball) -> bool:
	if not _is_enemy(candidate):
		return false
	if skill == 3:
		return global_position.distance_to(candidate.global_position) <= maxf(attack3_engage_range,1.0)

	var first_area:Area2D = null
	match skill:
		1:
			first_area = attack1_first_hit_area
		2:
			first_area = attack2_first_hit_area
	if first_area == null:
		return false

	var original_flip:bool = is_character_visual_flipped_h()
	var original_aim:float = _attack_aim_rotation
	var face_left:bool = candidate.global_position.x < global_position.x
	_set_umbrella_facing_left(face_left)
	for aim:float in _attack_turn_candidates_radians():
		_set_attack_aim_rotation(aim)
		if _attack_area_overlaps_candidate_hurtbox(first_area,candidate):
			return true
	set_character_visual_flip_h(original_flip)
	_set_attack_aim_rotation(original_aim)
	return false


func _nearest_enemy_for_attack3_engage() -> ball:
	var best:ball = null
	var best_d2:float = INF
	var engage:float = maxf(attack3_engage_range,1.0)
	var max_d2:float = engage * engage
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var candidate:ball = raw as ball
		if not _is_enemy(candidate):
			continue
		var d2:float = global_position.distance_squared_to(candidate.global_position)
		if d2 > max_d2 or d2 >= best_d2:
			continue
		best = candidate
		best_d2 = d2
	if best != null:
		_set_umbrella_facing_left(best.global_position.x < global_position.x)
		_set_attack_aim_rotation(0.0)
	return best


func _attack_hit_count_for_skill(skill:int) -> int:
	match skill:
		1:
			if sanity < attack1_third_hit_sanity_threshold:
				return 3
			if sanity < second_hit_sanity_threshold:
				return 2
			return 1
		2:
			return 2 if sanity < second_hit_sanity_threshold else 1
		3:
			return 1
	return 1


func _attack1_sequence(serial:int,hit_count:int) -> void:
	_play_anim(&"Attack1")
	_try_play_attack_voice_once()

	# V66：攻击1最多三段独立伤害。实际启用段数已在起手时按理智锁定；
	# 每一段仍使用自己的真实 Area2D，因此三段范围与实际伤害几何保持一致。
	if not await _wait_for_animation_frame(&"Attack1",attack1_first_hit_frame,serial):
		_finish_action(serial)
		return
	_play_attack_sfx_everywhere(ATTACK1_STAGE1_SWING_SFX)
	await _perform_attack_hit_window(
		attack1_first_hit_area,
		attack1_damage_multiplier,
		serial,
		null,
		0.0,
		ATTACK1_STAGE1_HIT_SFX
	)

	# V74：攻击1第一段是 0-5 帧。理智只允许一段时，
	# 不在命中帧 3 立刻切 Idle，而是把第一段完整播到 5 帧，
	# 在 5 帧停留 attack_end_hold_seconds 后再结束。
	if hit_count <= 1:
		await _finish_attack_on_segment_end(&"Attack1",attack1_first_segment_end_frame,serial)
		return

	if hit_count >= 2:
		if not await _wait_for_animation_frame(&"Attack1",attack1_second_hit_frame,serial):
			_finish_action(serial)
			return
		_play_attack_sfx_everywhere(ATTACK1_STAGE2_SWING_SFX)
		await _perform_attack_hit_window(
			attack1_second_hit_area,
			attack1_damage_multiplier,
			serial,
			null,
			0.0,
			ATTACK1_STAGE2_HIT_SFX
		)

		# V74：攻击1第二段是 6-13 帧。只允许两段时完整播到 13 帧，
		# 再在末帧停留一下，不进入 14-21 的第三段。
		if hit_count <= 2:
			await _finish_attack_on_segment_end(&"Attack1",attack1_second_segment_end_frame,serial)
			return

	if hit_count >= 3:
		if not await _wait_for_animation_frame(&"Attack1",attack1_third_hit_frame,serial):
			_finish_action(serial)
			return
		_play_attack_sfx_everywhere(ATTACK1_STAGE3_SWING_SFX)
		await _perform_attack_hit_window(
			attack1_third_hit_area,
			attack1_damage_multiplier,
			serial,
			null,
			0.0,
			ATTACK1_STAGE3_HIT_SFX
		)

	# V74：三段完整攻击的最后一段是 14-21 帧，同样在 21 帧停留后结束。
	await _finish_attack_on_segment_end(&"Attack1",attack1_third_segment_end_frame,serial)


func _attack2_sequence(target:ball,serial:int,hit_count:int) -> void:
	_face_target(target)
	_play_anim(&"Attack2")
	_try_play_attack_voice_once()

	if not await _wait_for_animation_frame(&"Attack2",attack2_first_hit_frame,serial):
		_finish_action(serial)
		return
	# 第一段的命中帧就是该段末帧 1。若本次只允许一段，先冻结在 1 帧，
	# 再打开一个 physics frame 的真实命中窗口，防止命中结算期间闪到第二段的帧 2。
	if hit_count <= 1:
		_pause_attack_animation_at_frame(&"Attack2",attack2_first_segment_end_frame)
	_play_attack_sfx_everywhere(ATTACK2_STAGE1_SWING_SFX)
	await _deal_attack2_rectangle(
		target,
		serial,
		false,
		ATTACK2_STAGE1_HIT_SFX
	)

	# V74：攻击2第一段是 0-1 帧。未低于 -10 时，在帧 1 直接冻结，
	# 既不进入 2-4 的第二段，也不会命中后瞬间跳回 Idle。
	if hit_count <= 1:
		await _finish_attack_on_segment_end(&"Attack2",attack2_first_segment_end_frame,serial)
		return

	if hit_count >= 2:
		if not await _wait_for_animation_frame(&"Attack2",attack2_second_hit_frame,serial):
			_finish_action(serial)
			return
		_play_attack_sfx_everywhere(ATTACK2_STAGE2_SWING_SFX)
		await _deal_attack2_rectangle(
			target,
			serial,
			true,
			ATTACK2_STAGE2_HIT_SFX
		)

	# V74：完整攻击2的第二段是 2-4 帧，在 4 帧停留后结束。
	await _finish_attack_on_segment_end(&"Attack2",attack2_second_segment_end_frame,serial)


func _attack3_sequence_manual(serial:int,aim_direction:Vector2) -> void:
	_add_self_sinking(attack3_self_sinking)
	_set_manual_attack_aim_direction(aim_direction)
	_play_anim(&"Attack3")
	var dash_dir:Vector2 = aim_direction.normalized() if aim_direction.length_squared() > 0.000001 else Vector2.RIGHT
	var dash_elapsed:float = 0.0
	var blocked_by_character:bool = false
	while _is_action_valid(serial) and dash_elapsed < maxf(attack3_dash_max_seconds,0.1):
		if not is_combat_runtime_active():
			await get_tree().physics_frame
			continue
		var reached_hit_pose:bool = (
			umbrella_sprite != null
			and umbrella_sprite.animation == &"Attack3"
			and umbrella_sprite.frame >= attack3_hit_frame
		)
		if blocked_by_character and reached_hit_pose:
			break
		await get_tree().physics_frame
		if not _is_action_valid(serial):
			break
		var physics_delta:float = maxf(get_physics_process_delta_time(),0.000001)
		dash_elapsed += physics_delta
		velocity = dash_dir * maxf(attack3_dash_speed,0.0)
		move_and_slide()
		for collision_index:int in range(get_slide_collision_count()):
			var dash_collision:KinematicCollision2D = get_slide_collision(collision_index)
			if dash_collision != null and dash_collision.get_collider() is ball:
				blocked_by_character = true
				break
		velocity = Vector2.ZERO

	if _is_action_valid(serial):
		await _perform_attack_hit_window(attack3_hit_area,attack3_damage_multiplier,serial,null,0.0)
	if umbrella_sprite != null and umbrella_sprite.sprite_frames != null and umbrella_sprite.sprite_frames.has_animation(&"Attack3"):
		var last_frame:int = umbrella_sprite.sprite_frames.get_frame_count(&"Attack3") - 1
		await _finish_attack3_with_release(maxi(last_frame,0),serial)
	else:
		_release_attack3_pin(serial,false)
		_finish_action(serial)


func _attack3_sequence(target:ball,serial:int) -> void:
	_add_self_sinking(attack3_self_sinking)
	_face_target(target)
	_play_anim(&"Attack3")

	# V79：旧实现把 attack3_hit_frame 设成 17，但当前 Attack3 只有 10 帧（0~9），
	# 因而循环永远等不到命中帧，只能拖到 watchdog；这是攻击3慢且基本打不到的核心原因。
	# 现在冲刺只受明确最大时长控制，并持续朝锁定目标靠近。
	var dash_elapsed:float = 0.0
	var dash_blocked_by_character:bool = false
	while _is_action_valid(serial):
		if target == null or not is_instance_valid(target) or target.health <= 0:
			break
		if not is_combat_runtime_active():
			await get_tree().physics_frame
			continue

		_face_target(target)
		var to_target:Vector2 = target.global_position - global_position
		var target_distance:float = to_target.length()
		var reached_hit_pose:bool = (
			umbrella_sprite != null
			and umbrella_sprite.animation == &"Attack3"
			and umbrella_sprite.frame >= attack3_hit_frame
		)
		if (target_distance <= attack3_stop_distance or dash_blocked_by_character) and reached_hit_pose:
			break
		if dash_elapsed >= maxf(attack3_dash_max_seconds,0.1):
			break

		await get_tree().physics_frame
		if not _is_action_valid(serial):
			break
		var physics_delta:float = maxf(get_physics_process_delta_time(),0.000001)
		dash_elapsed += physics_delta

		if target == null or not is_instance_valid(target) or target.health <= 0:
			break
		to_target = target.global_position - global_position
		target_distance = to_target.length()
		if not dash_blocked_by_character and target_distance > attack3_stop_distance and target_distance > 0.0001:
			var max_motion:float = minf(
				attack3_dash_speed * physics_delta,
				maxf(target_distance - attack3_stop_distance,0.0)
			)
			if max_motion > 0.0:
				velocity = to_target.normalized() * (max_motion / physics_delta)
				move_and_slide()
				for collision_index:int in range(get_slide_collision_count()):
					var dash_collision:KinematicCollision2D = get_slide_collision(collision_index)
					if dash_collision != null and dash_collision.get_collider() is ball:
						dash_blocked_by_character = true
						break
				velocity = Vector2.ZERO

	if _is_action_valid(serial) and target != null and is_instance_valid(target) and target.health > 0:
		_face_target(target)
		# V80：攻击3命中时不立刻眩晕。真实伤害成功后会在 _try_damage_attack_overlap()
		# 里进入“固定在伞上”阶段；眩晕延后到 Attack3 动画完整结束并释放时。
		await _perform_attack_hit_window(
			attack3_hit_area,
			attack3_damage_multiplier,
			serial,
			target,
			0.0
		)

	# V80：Attack3 使用专门的收尾：完整播放到末帧 -> 末帧停留 -> 放开敌人 -> 再眩晕。
	if umbrella_sprite != null and umbrella_sprite.sprite_frames != null and umbrella_sprite.sprite_frames.has_animation(&"Attack3"):
		var last_frame:int = umbrella_sprite.sprite_frames.get_frame_count(&"Attack3") - 1
		await _finish_attack3_with_release(maxi(last_frame,0),serial)
	else:
		_release_attack3_pin(serial,false)
		_finish_action(serial)


func _wait_for_animation_frame(
	anim_name:StringName,
	target_frame:int,
	serial:int
) -> bool:
	if umbrella_sprite == null or umbrella_sprite.sprite_frames == null:
		return false
	if not umbrella_sprite.sprite_frames.has_animation(anim_name):
		return false

	var last_frame:int = umbrella_sprite.sprite_frames.get_frame_count(anim_name) - 1
	target_frame = clampi(target_frame,0,maxi(last_frame,0))
	var elapsed:float = 0.0

	# V57：不要 await frame_changed。动画被 stop()/切换后可能永远不再发 frame_changed，
	# 原协程就会永久挂起，Attacking 也永远无法复位。按 physics frame 轮询可稳定退出。
	while _is_action_valid(serial):
		if umbrella_sprite.animation != anim_name:
			return false
		if umbrella_sprite.frame >= target_frame:
			return true
		if not umbrella_sprite.is_playing():
			return false
		await get_tree().physics_frame
		if is_combat_runtime_active():
			elapsed += get_physics_process_delta_time()
			if elapsed >= maxf(attack_action_watchdog_seconds,1.0):
				return false

	return false


func _wait_for_animation_end(anim_name:StringName,serial:int) -> bool:
	var elapsed:float = 0.0
	while _is_action_valid(serial):
		if umbrella_sprite.animation != anim_name:
			return false
		if not umbrella_sprite.is_playing():
			return true
		await get_tree().physics_frame
		if is_combat_runtime_active():
			elapsed += get_physics_process_delta_time()
			if elapsed >= maxf(attack_action_watchdog_seconds,1.0):
				return false
	return false


func _pause_attack_animation_at_frame(anim_name:StringName,target_frame:int) -> void:
	if umbrella_sprite == null or umbrella_sprite.sprite_frames == null:
		return
	if umbrella_sprite.animation != anim_name:
		return
	if not umbrella_sprite.sprite_frames.has_animation(anim_name):
		return
	var last_frame:int = umbrella_sprite.sprite_frames.get_frame_count(anim_name) - 1
	var clamped_frame:int = clampi(target_frame,0,maxi(last_frame,0))
	umbrella_sprite.set_frame_and_progress(clamped_frame,0.0)
	umbrella_sprite.pause()
	_sync_umbrella_visual_from_driver()


# V80：攻击3专用收尾。敌人被叉住以后必须一直固定到整段动画真正结束。
# 正常结束：释放后才开始 attack3_stun_duration。
# 动画异常/伞夫死亡/动作失效：立即释放，但不奖励“正常收尾眩晕”。
func _finish_attack3_with_release(last_frame:int,serial:int) -> void:
	if not await _wait_for_animation_frame(&"Attack3",last_frame,serial):
		_release_attack3_pin(serial,false)
		_finish_action(serial)
		return

	if not _is_action_valid(serial):
		_release_attack3_pin(serial,false)
		_finish_action(serial)
		return
	if umbrella_sprite == null or umbrella_sprite.sprite_frames == null or umbrella_sprite.animation != &"Attack3":
		_release_attack3_pin(serial,false)
		_finish_action(serial)
		return

	var hold_frame:int = clampi(last_frame,0,maxi(umbrella_sprite.sprite_frames.get_frame_count(&"Attack3") - 1,0))
	umbrella_sprite.set_frame_and_progress(hold_frame,0.0)
	umbrella_sprite.pause()
	_sync_umbrella_visual_from_driver()

	var elapsed:float = 0.0
	var hold_seconds:float = maxf(attack_end_hold_seconds,0.0)
	while _is_action_valid(serial) and elapsed < hold_seconds:
		if umbrella_sprite.animation != &"Attack3" or umbrella_sprite.frame != hold_frame:
			break
		await get_tree().physics_frame
		elapsed += maxf(get_physics_process_delta_time(),0.0)

	var normal_finish:bool = (
		_is_action_valid(serial)
		and health > 0
		and umbrella_sprite != null
		and umbrella_sprite.animation == &"Attack3"
		and umbrella_sprite.frame == hold_frame
	)
	_release_attack3_pin(serial,normal_finish)
	_finish_action(serial)


# V74：把当前攻击完整播放到“本次允许的最后一段”的末帧，
# 冻结在该帧短暂停留，再统一回 Idle。
# 这同时解决：
# 1) 低理智门槛未到时不能看到下一段动作；
# 2) 最后一击命中后不应瞬间切回 Idle。
func _finish_attack_on_segment_end(
	anim_name:StringName,
	segment_end_frame:int,
	serial:int
) -> void:
	if not await _wait_for_animation_frame(anim_name,segment_end_frame,serial):
		_finish_action(serial)
		return

	if not _is_action_valid(serial):
		return
	if umbrella_sprite == null or umbrella_sprite.sprite_frames == null:
		_finish_action(serial)
		return
	if umbrella_sprite.animation != anim_name:
		_finish_action(serial)
		return

	var last_frame:int = umbrella_sprite.sprite_frames.get_frame_count(anim_name) - 1
	var hold_frame:int = clampi(segment_end_frame,0,maxi(last_frame,0))
	umbrella_sprite.set_frame_and_progress(hold_frame,0.0)
	umbrella_sprite.pause()
	_sync_umbrella_visual_from_driver()

	var elapsed:float = 0.0
	var hold_seconds:float = maxf(attack_end_hold_seconds,0.0)
	while _is_action_valid(serial) and elapsed < hold_seconds:
		if umbrella_sprite.animation != anim_name or umbrella_sprite.frame != hold_frame:
			break
		await get_tree().physics_frame
		elapsed += maxf(get_physics_process_delta_time(),0.0)

	_finish_action(serial)


func _finish_action(serial:int) -> void:
	if serial != _action_serial:
		return
	# V80 安全兜底：任何非正常收尾都不能把敌人永久留在伞上。
	# 正常 Attack3 已在 _finish_attack3_with_release() 中先释放并施加后置眩晕。
	_release_attack3_pin(serial,false)
	_end_attack_hit_window(serial)
	Attacking = false
	_clear_attack_debug_preview()
	_set_attack_aim_rotation(0.0)
	direction = Vector2.ZERO
	if health > 0:
		_play_anim(&"Idle")


func _is_action_valid(serial:int) -> bool:
	return (
		serial == _action_serial
		and is_inside_tree()
		and health > 0
		and state_machine.current_state != State.Die
	)


func _play_anim(anim_name:StringName) -> void:
	if umbrella_sprite == null or umbrella_sprite.sprite_frames == null:
		return
	if not umbrella_sprite.sprite_frames.has_animation(anim_name):
		return
	umbrella_sprite.play(anim_name)
	_sync_umbrella_visual_from_driver()


# ============================================================
# V70：动画时钟与 Sprite2D 主视觉同步
# ============================================================
# AnimatedSprite2D 只负责 animation/frame；Graphics/Image 才是真正显示节点。
func _on_umbrella_driver_frame_changed() -> void:
	_sync_umbrella_visual_from_driver()


func _on_umbrella_driver_animation_changed() -> void:
	_sync_umbrella_visual_from_driver()


func _sync_umbrella_visual_from_driver() -> void:
	if umbrella_sprite == null or umbrella_visual == null:
		return
	if umbrella_visual.has_method("sync_from_animation"):
		umbrella_visual.call(
			"sync_from_animation",
			umbrella_sprite.animation,
			umbrella_sprite.frame,
			is_character_visual_flipped_h()
		)


func apply_character_visual_adjustment() -> void:
	_sync_umbrella_visual_from_driver()


# ============================================================
# V62 稳定攻击范围节点解析
# ============================================================
func _resolve_attack_range_nodes() -> void:
	var root:Node = null
	for root_name:String in [
		"伞夫攻击范围_直接调整",
		"伞夫攻击范围_V61_直接拖",
		"伞夫攻击范围_V60_直接拖",
	]:
		root = get_node_or_null(NodePath(root_name))
		if root != null:
			break

	if root == null:
		push_error("伞夫：找不到攻击范围根节点。请使用 V62 场景文件；脚本已兼容 V61/V60 旧名。")
		return

	attack_range_root = root as Node2D

	# V62/V61：三段独立范围。
	attack1_first_hit_area = root.get_node_or_null("攻击1第一段范围") as Area2D
	attack1_second_hit_area = root.get_node_or_null("攻击1第二段范围") as Area2D
	attack1_third_hit_area = root.get_node_or_null("攻击1第三段范围") as Area2D

	# V60 兼容：旧场景只有一个“攻击1范围”。
	# 在编辑器尚未重新载入 V62 场景时，至少让三段攻击继续工作，而不是整个人贴脸不攻击。
	var legacy_attack1:Area2D = root.get_node_or_null("攻击1范围") as Area2D
	if attack1_first_hit_area == null:
		attack1_first_hit_area = legacy_attack1
	if attack1_second_hit_area == null:
		attack1_second_hit_area = legacy_attack1
	if attack1_third_hit_area == null:
		attack1_third_hit_area = legacy_attack1

	attack1_first_hit_shape = _first_collision_shape(attack1_first_hit_area)
	attack1_second_hit_shape = _first_collision_shape(attack1_second_hit_area)
	attack1_third_hit_shape = _first_collision_shape(attack1_third_hit_area)

	attack2_first_hit_area = root.get_node_or_null("攻击2第一段范围") as Area2D
	attack2_second_hit_area = root.get_node_or_null("攻击2第二段范围") as Area2D
	attack2_first_hit_shape = _first_collision_shape(attack2_first_hit_area)
	attack2_second_hit_shape = _first_collision_shape(attack2_second_hit_area)

	attack3_hit_area = root.get_node_or_null("攻击3范围") as Area2D
	attack3_hit_shape = _first_collision_shape(attack3_hit_area)
	attack3_pin_marker = root.get_node_or_null("攻击3敌人固定点_编辑器拖这里") as Marker2D


func _first_collision_shape(area:Area2D) -> CollisionShape2D:
	if area == null or not is_instance_valid(area):
		return null
	return area.get_node_or_null("CollisionShape2D") as CollisionShape2D


# ============================================================
# V75 真实攻击 Shape = 起手检测 Shape
# ============================================================
# 检测与命中共用同一批 CollisionShape2D，不再维护额外“敌人检测范围”。
# 为了与真正攻击一致，只把敌方 hurtbox 的 Shape 当成可命中目标；
# 身体碰撞框、hitbox、角色中心点都不再作为攻击起手的替代检测。

func _attack_areas_for_skill(skill:int,_hit_count:int) -> Array[Area2D]:
	# V79：起手检测只检查第一实际命中段。
	# 旧版把后续连段 Shape 也并进起手检测，会出现“后续段覆盖目标，所以允许起手，但第一段根本打不到”。
	var result:Array[Area2D] = []
	match skill:
		1:
			if attack1_first_hit_area != null:
				result.append(attack1_first_hit_area)
		2:
			if attack2_first_hit_area != null:
				result.append(attack2_first_hit_area)
		3:
			pass
	return result


func _nearest_enemy_overlapping_skill_attack_ranges(skill:int,hit_count:int) -> ball:
	if skill == 3:
		return _nearest_enemy_for_attack3_engage()
	return _nearest_enemy_overlapping_attack_areas(_attack_areas_for_skill(skill,hit_count))


func _nearest_enemy_overlapping_attack_areas(attack_areas:Array[Area2D]) -> ball:
	if attack_areas.is_empty():
		return null

	var original_flip:bool = is_character_visual_flipped_h()
	var original_aim:float = _attack_aim_rotation
	var best:ball = null
	var best_d2:float = INF
	var best_face_left:bool = original_flip
	var best_aim:float = 0.0
	var aim_candidates:Array[float] = _attack_turn_candidates_radians()

	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var candidate:ball = raw as ball
		if not _is_enemy(candidate):
			continue

		var face_left:bool = candidate.global_position.x < global_position.x
		_set_umbrella_facing_left(face_left)
		var candidate_found:bool = false
		var candidate_aim:float = 0.0
		for aim:float in aim_candidates:
			_set_attack_aim_rotation(aim)
			if _candidate_hurtbox_overlaps_any_attack_area(candidate,attack_areas):
				candidate_found = true
				candidate_aim = aim
				break
		if not candidate_found:
			continue

		var d2:float = global_position.distance_squared_to(candidate.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = candidate
			best_face_left = face_left
			best_aim = candidate_aim

	if best != null:
		_set_umbrella_facing_left(best_face_left)
		_set_attack_aim_rotation(best_aim)
	else:
		set_character_visual_flip_h(original_flip)
		_set_attack_aim_rotation(original_aim)
	return best


func _attack_turn_candidates_radians() -> Array[float]:
	var result:Array[float] = [0.0]
	var max_angle:float = deg_to_rad(clampf(attack_turn_max_degrees,0.0,30.0))
	if max_angle <= 0.00001:
		return result
	var step:float = deg_to_rad(clampf(attack_turn_step_degrees,1.0,maxf(attack_turn_max_degrees,1.0)))
	var angle:float = step
	while angle < max_angle - 0.00001:
		result.append(angle)
		result.append(-angle)
		angle += step
	result.append(max_angle)
	result.append(-max_angle)
	return result


func _set_manual_attack_aim_direction(aim_direction:Vector2) -> void:
	if aim_direction.length_squared() <= 0.000001:
		aim_direction = Vector2.RIGHT
	var aim_angle:float = aim_direction.angle()
	var face_left:bool = aim_direction.x < 0.0
	_set_umbrella_facing_left(face_left)
	# 攻击素材按“面朝右”创作；左半平面先镜像，再用相对 PI 的角度旋转。
	# 这里不套 AI 的 ±30° 限制，玩家可以完整覆盖 360°。
	_attack_aim_rotation = wrapf(aim_angle - (PI if face_left else 0.0),-PI,PI)
	_sync_attack_range_facing()


func _set_attack_aim_rotation(angle_radians:float) -> void:
	var max_angle:float = deg_to_rad(clampf(attack_turn_max_degrees,0.0,30.0))
	_attack_aim_rotation = clampf(angle_radians,-max_angle,max_angle)
	_sync_attack_range_facing()


func _candidate_hurtbox_overlaps_any_attack_area(candidate:ball,attack_areas:Array[Area2D]) -> bool:
	for area:Area2D in attack_areas:
		if _attack_area_overlaps_candidate_hurtbox(area,candidate):
			return true
	return false


func _attack_area_overlaps_candidate_hurtbox(attack_area:Area2D,candidate:ball) -> bool:
	if not _is_enemy(candidate):
		return false
	var attack_shape:CollisionShape2D = _shape_for_attack_area(attack_area)
	if (
		attack_shape == null
		or not is_instance_valid(attack_shape)
		or attack_shape.disabled
		or attack_shape.shape == null
	):
		return false

	for raw_shape:Node in candidate.find_children("*","CollisionShape2D",true,false):
		if not raw_shape is CollisionShape2D:
			continue
		var hurt_shape:CollisionShape2D = raw_shape as CollisionShape2D
		if hurt_shape.disabled or hurt_shape.shape == null:
			continue
		if not _collision_shape_belongs_to_hurtbox(hurt_shape,candidate):
			continue
		if attack_shape.shape.collide(
			attack_shape.global_transform,
			hurt_shape.shape,
			hurt_shape.global_transform
		):
			return true
	return false


func _collision_shape_belongs_to_hurtbox(shape_node:CollisionShape2D,owner_ball:ball) -> bool:
	var node:Node = shape_node.get_parent()
	while node != null and node != owner_ball:
		if node is hurtbox:
			return true
		if node is hitbox:
			return false
		node = node.get_parent()
	return false


# CombatThreatAnalyzer 看到空数组后会认为本角色已经提供自定义检测信息，
# 不再猜 target_search_range 等圆形范围。真实检测范围就是攻击 Area 本身，由红色攻击框显示。
func get_debug_detection_regions() -> Array[Dictionary]:
	# 攻击1/2继续直接使用真实红色攻击 Shape 起手；攻击3蓝圈只表示真实冲刺起手距离。
	return [{
		"shape":"circle",
		"position":global_position,
		"radius":maxf(attack3_engage_range,1.0),
		"kind":"umbrella_attack3_engage_detection",
	}]


func uses_attack_areas_as_detection() -> bool:
	return true


func _collision_shape_belongs_to_outgoing_hitbox(shape_node:CollisionShape2D,owner_ball:ball) -> bool:
	var node:Node = shape_node.get_parent()
	while node != null and node != owner_ball:
		if node is hurtbox:
			return false
		if node is hitbox:
			return true
		node = node.get_parent()
	return false


func _current_enemy() -> ball:
	if is_instance_valid(Target_Enemy) and Target_Enemy is ball:
		var forced:ball = Target_Enemy as ball
		if _is_enemy(forced):
			return forced

	if is_instance_valid(Nearest_Enemy) and Nearest_Enemy is ball:
		var nearest:ball = Nearest_Enemy as ball
		if _is_enemy(nearest):
			return nearest

	# World 一般每个 physics tick 会维护 Nearest_Enemy。
	# 这里只做一次安全兜底，避免角色刚生成的第一帧没有目标。
	var best:ball = null
	var best_dist_sq:float = target_search_range * target_search_range
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var candidate:ball = raw as ball
		if not _is_enemy(candidate):
			continue
		var dist_sq:float = global_position.distance_squared_to(candidate.global_position)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = candidate
	return best


func _is_enemy(candidate:ball) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(self,candidate): return false # 皓宸复制品及其产物不把己方选为目标
	if candidate == null or not is_instance_valid(candidate) or candidate == self:
		return false
	if candidate.health <= 0:
		return false
	if candidate.Type != Ball_Type.Ball and candidate.Type != Ball_Type.Creature:
		return false

	var my_team:String = str(Team).strip_edges()
	var other_team:String = str(candidate.Team).strip_edges()
	if my_team.is_empty() or other_team.is_empty():
		return true
	return my_team != other_team


func _face_target(target:ball) -> void:
	if target == null or not is_instance_valid(target):
		return
	_set_umbrella_facing_left(target.global_position.x < global_position.x)


func _deal_attack2_rectangle(
	target:ball,
	serial:int,
	second_hit:bool,
	hit_sfx_name:String
) -> void:
	# V58：Attack2 两段各自拥有独立的场景碰撞框。
	# target 只用于保持现有朝向语义；两段仍可扫到范围内多个敌人。
	_face_target(target)
	var area:Area2D = attack2_second_hit_area if second_hit else attack2_first_hit_area
	await _perform_attack_hit_window(
		area,
		attack2_damage_multiplier_per_hit,
		serial,
		null,
		0.0,
		hit_sfx_name
	)


# ============================================================
# V61 场景直接编辑 + 真实攻击碰撞
# ============================================================
func _attack_areas() -> Array[Area2D]:
	return [
		attack1_first_hit_area,
		attack1_second_hit_area,
		attack1_third_hit_area,
		attack2_first_hit_area,
		attack2_second_hit_area,
		attack3_hit_area,
	]


# V61：不提供“Inspector 代理数值 -> 碰撞框”的同步函数。
# 用户在场景编辑器中直接编辑 CollisionShape2D，脚本只读取，不覆盖。
func _setup_attack_ranges() -> void:
	# V78：没有独立检测圈；真实攻击根节点会整体按 attack_range_scale_multiplier 放大，
	# 因此“检测变远”和“实际伤害变远”永远同步。
	_attack_range_authored_transforms.clear()
	if attack_range_root != null and is_instance_valid(attack_range_root):
		_attack_range_root_authored_transform = attack_range_root.transform
	for node:Node2D in _range_authoring_nodes():
		if node != null and is_instance_valid(node):
			_attack_range_authored_transforms[node.get_instance_id()] = node.transform

	for area:Area2D in _attack_areas():
		if area == null or not is_instance_valid(area):
			push_error("伞夫：V62 伞夫攻击范围_直接调整 中存在缺失的攻击 Area2D。")
			continue
		var shape_node:CollisionShape2D = _shape_for_attack_area(area)
		if shape_node == null or shape_node.shape == null:
			push_error("伞夫：%s 缺少有效 CollisionShape2D。" % str(area.name))
			continue

		area.collision_layer = 0
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = false
		area.set_meta("threat_debug_kind","attack")
		area.set_meta("threat_debug_damage",0.0)
		# 威胁显示开启时，非当前攻击也用较淡的红框显示，方便用户现场校准。
		area.set_meta("threat_debug_tuning",true)

	_attack_range_facing_initialized = false
	_sync_attack_range_facing()


func _range_authoring_nodes() -> Array[Node2D]:
	return [
		attack1_first_hit_area,attack1_first_hit_shape,
		attack1_second_hit_area,attack1_second_hit_shape,
		attack1_third_hit_area,attack1_third_hit_shape,
		attack2_first_hit_area,attack2_first_hit_shape,
		attack2_second_hit_area,attack2_second_hit_shape,
		attack3_hit_area,attack3_hit_shape,attack3_pin_marker,
	]


func _shape_for_attack_area(area:Area2D) -> CollisionShape2D:
	if area == attack1_first_hit_area:
		return attack1_first_hit_shape
	if area == attack1_second_hit_area:
		return attack1_second_hit_shape
	if area == attack1_third_hit_area:
		return attack1_third_hit_shape
	if area == attack2_first_hit_area:
		return attack2_first_hit_shape
	if area == attack2_second_hit_area:
		return attack2_second_hit_shape
	if area == attack3_hit_area:
		return attack3_hit_shape
	return null


# V65：统一接管角色视觉左右翻转入口。
# 父类 ball.move() 在普通移动时就是调用这个方法，所以不能只在 _face_target() 里同步攻击框。
# 先让父类完成 Shader / Sprite 的正常翻转，再让真实 CollisionShape2D 镜像到同一方向。
func set_character_visual_flip_h(flipped:bool) -> void:
	super.set_character_visual_flip_h(flipped)
	_sync_attack_range_facing_if_needed()
	# V75：父类只负责 Shader 水平翻纹理；伞夫构图脚本只记录朝向，
	# 不再修改动作保存的 position.x。
	if umbrella_visual != null and umbrella_visual.has_method("apply_runtime_flip"):
		umbrella_visual.call("apply_runtime_flip",flipped)


func _set_umbrella_facing_left(face_left:bool) -> void:
	set_character_visual_flip_h(face_left)


func _sync_attack_range_facing_if_needed() -> void:
	if _attack_range_authored_transforms.is_empty():
		return
	var face_left:bool = is_character_visual_flipped_h()
	if _attack_range_facing_initialized and face_left == _attack_range_last_face_left:
		return
	_sync_attack_range_facing()


func _sync_attack_range_facing() -> void:
	if _attack_range_authored_transforms.is_empty():
		return
	# V78：整体倍率与小幅转向施加在攻击范围根节点上。所有子 CollisionShape2D 的 authored 数据保持原样，
	# 用户仍只需在场景里编辑一套范围；检测、威胁显示、真实命中都会继承同一个根 Transform。
	if attack_range_root != null and is_instance_valid(attack_range_root):
		attack_range_root.position = _attack_range_root_authored_transform.origin
		attack_range_root.rotation = _attack_range_root_authored_transform.get_rotation() + _attack_aim_rotation
		attack_range_root.scale = _attack_range_root_authored_transform.get_scale() * maxf(attack_range_scale_multiplier,1.0)
	var face_left:bool = is_character_visual_flipped_h()
	for node:Node2D in _range_authoring_nodes():
		if node == null or not is_instance_valid(node):
			continue
		var key:int = node.get_instance_id()
		if not _attack_range_authored_transforms.has(key):
			continue
		var authored:Transform2D = _attack_range_authored_transforms[key]
		if not face_left:
			node.transform = authored
			continue

		# 用户只需要编辑“面朝右”的一套真实碰撞框。
		# V61 不从脚本参数覆盖 authored transform；位置/旋转/缩放都来自场景。
		node.position = Vector2(-authored.origin.x,authored.origin.y)
		node.rotation = -authored.get_rotation()
		node.scale = authored.get_scale()

	_attack_range_last_face_left = face_left
	_attack_range_facing_initialized = true


func _attack_area_for_kind(attack_kind:int) -> Area2D:
	match attack_kind:
		1:
			return attack1_first_hit_area
		2:
			return attack2_first_hit_area
		3:
			return attack3_hit_area
	return null


func _prepare_attack_debug_preview(
	attack_kind:int,
	locked_target:ball = null,
	hit_count:int = 1
) -> void:
	if locked_target != null and is_instance_valid(locked_target):
		_face_target(locked_target)
	_clear_attack_debug_preview()
	_attack_debug_preview_kind = attack_kind
	_attack_debug_preview_hit_count = maxi(hit_count,1)

	var raw_damage:float = 0.0
	match attack_kind:
		1:
			raw_damage = attack_damage(attack1_damage_multiplier)
		2:
			raw_damage = attack_damage(attack2_damage_multiplier_per_hit)
		3:
			raw_damage = attack_damage(attack3_damage_multiplier)
	_attack_debug_preview_damage = _apply_sanity_outgoing_damage(raw_damage)

	var preview_areas:Array[Area2D] = []
	match attack_kind:
		1:
			preview_areas = [attack1_first_hit_area]
			if _attack_debug_preview_hit_count >= 2:
				preview_areas.append(attack1_second_hit_area)
			if _attack_debug_preview_hit_count >= 3:
				preview_areas.append(attack1_third_hit_area)
		2:
			preview_areas = [attack2_first_hit_area]
			if _attack_debug_preview_hit_count >= 2:
				preview_areas.append(attack2_second_hit_area)
		3:
			preview_areas = [attack3_hit_area]
	for area:Area2D in preview_areas:
		if area != null and is_instance_valid(area):
			area.set_meta("threat_debug_damage",_attack_debug_preview_damage)


func _restore_attack_debug_preview_meta() -> void:
	for area:Area2D in _attack_areas():
		if area == null or not is_instance_valid(area):
			continue
		var active_preview:bool = false
		match _attack_debug_preview_kind:
			1:
				active_preview = area == attack1_first_hit_area
				if _attack_debug_preview_hit_count >= 2 and area == attack1_second_hit_area:
					active_preview = true
				if _attack_debug_preview_hit_count >= 3 and area == attack1_third_hit_area:
					active_preview = true
			2:
				active_preview = area == attack2_first_hit_area
				if _attack_debug_preview_hit_count >= 2 and area == attack2_second_hit_area:
					active_preview = true
			3:
				active_preview = area == attack3_hit_area
		area.set_meta("threat_debug_damage",_attack_debug_preview_damage if Attacking and active_preview else 0.0)


func _clear_attack_debug_preview() -> void:
	_attack_debug_preview_kind = 0
	_attack_debug_preview_damage = 0.0
	_attack_debug_preview_hit_count = 0
	for area:Area2D in _attack_areas():
		if area != null and is_instance_valid(area):
			area.set_meta("threat_debug_damage",0.0)


func _perform_attack_hit_window(
	attack_area:Area2D,
	damage_multiplier:float,
	serial:int,
	locked_target:ball = null,
	stun_duration:float = 0.0,
	hit_sfx_name:String = ""
) -> void:
	if not _is_action_valid(serial):
		return
	if attack_area == null or not is_instance_valid(attack_area):
		return
	var attack_shape:CollisionShape2D = _shape_for_attack_area(attack_area)
	if attack_shape == null or attack_shape.disabled or attack_shape.shape == null:
		return

	_sync_attack_range_facing()
	_attack_hit_active = true
	_active_attack_area = attack_area
	_attack_hit_serial = serial
	_attack_hit_damage = _apply_sanity_outgoing_damage(attack_damage(damage_multiplier))
	_attack_hit_stun_duration = maxf(stun_duration,0.0)
	_attack_hit_success_sfx = hit_sfx_name
	_attack_hit_success_sfx_played = false
	_attack_hit_target_filter_id = locked_target.get_instance_id() if locked_target != null and is_instance_valid(locked_target) and attack_area == attack3_hit_area else 0
	_attack_hit_target_ids.clear()

	attack_area.set_meta("threat_debug_damage",_attack_hit_damage)
	attack_area.collision_mask = 2
	attack_area.monitoring = true

	# Area2D 重叠列表在 physics step 更新；保留一个真实物理帧命中窗口。
	await get_tree().physics_frame
	if _attack_hit_active and _attack_hit_serial == serial and _is_action_valid(serial):
		_collect_current_attack_hits()

	_end_attack_hit_window(serial)


func _collect_current_attack_hits() -> void:
	if not _attack_hit_active or _active_attack_area == null:
		return
	if not is_instance_valid(_active_attack_area) or not _active_attack_area.monitoring:
		return
	for area:Area2D in _active_attack_area.get_overlapping_areas():
		_try_damage_attack_overlap(area)


func _try_damage_attack_overlap(area:Area2D) -> void:
	if not _attack_hit_active or not Attacking:
		return
	if _attack_hit_serial != _action_serial:
		return
	if area == null or not is_instance_valid(area) or not area is hurtbox:
		return

	var target:ball = area.get_parent() as ball
	if target == null or not is_instance_valid(target) or not _is_enemy(target):
		return

	var target_id:int = target.get_instance_id()
	if _attack_hit_target_filter_id != 0 and target_id != _attack_hit_target_filter_id:
		return
	if _attack_hit_target_ids.has(target_id):
		return

	_attack_hit_target_ids[target_id] = true
	if _attack_hit_damage <= 0.0:
		return

	var did_hit:bool = target.receive_positional_damage(
		_attack_hit_damage,
		target.global_position,
		_attack_hit_stun_duration > 0.0,
		self
	)
	if did_hit:
		# V80：攻击3真实伤害成功后，立刻把这个锁定目标叉在伞上。
		# 这里只固定，不眩晕；Attack3 动画结束释放时才开始眩晕。
		if _active_attack_area == attack3_hit_area:
			_begin_attack3_pin(target,_attack_hit_serial)
		# V73：只有真实伤害结算成功才播放命中声。
		# 一段攻击可能扫到多人，但该段命中声只播一次。
		if not _attack_hit_success_sfx_played and not _attack_hit_success_sfx.is_empty():
			_attack_hit_success_sfx_played = true
			_play_attack_sfx_everywhere(_attack_hit_success_sfx)
		if _attack_hit_stun_duration > 0.0 and target.has_method("apply_stun"):
			target.call("apply_stun",_attack_hit_stun_duration)


func _begin_attack3_pin(target:ball,serial:int) -> void:
	if serial != _action_serial or target == null or not is_instance_valid(target) or target.health <= 0:
		return

	# Attack3 一次只锁定起手时验证的目标；若已经锁住同一个目标，不重复叠加控制锁。
	if _attack3_pinned_target != null and is_instance_valid(_attack3_pinned_target):
		if _attack3_pinned_target == target and _attack3_pin_serial == serial:
			_update_attack3_pinned_target()
		return

	# 防御性清理旧引用；旧动作遗留时绝不能把两个目标同时挂在伞上。
	_release_attack3_pin(-1,false)

	_attack3_pinned_target = target
	_attack3_pin_serial = serial
	_attack3_pin_lock_acquired = false
	_attack3_collision_filter_saved = false

	# V83：命中后把敌人直接移动到“攻击3敌人固定点_编辑器拖这里”。
	# 如果该编辑器点会让目标身体 Shape 与伞夫身体 Shape 重叠，运行时只沿该点方向做最小外推。
	# 因此用户以后只需要在 2D 编辑器拖 Marker2D，不需要反复改脚本 Vector2。

	# 与通用 KnockbackEffect 使用同一套可叠加 motion lock metadata。
	var old_count:int = int(target.get_meta(ATTACK3_CONTROL_LOCK_META,0))
	if old_count <= 0:
		target.set_meta(ATTACK3_CONTROL_BASELINE_META,target.dizziness)
	target.set_meta(ATTACK3_CONTROL_LOCK_META,old_count + 1)
	target.dizziness = true
	_attack3_pin_lock_acquired = true

	# V81：被挂住期间关闭目标 CharacterBody2D 的实体碰撞参与。
	# 这只改目标本体的 layer/mask；它的 hurtbox 是独立 Area2D，所以仍然能被技能/攻击识别。
	_attack3_saved_collision_layer = target.collision_layer
	_attack3_saved_collision_mask = target.collision_mask
	_attack3_collision_filter_saved = true
	target.collision_layer = 0
	target.collision_mask = 0

	# 被叉起时中断目标当前自主攻击/技能，并清掉自主运动与击退速度。
	target.Attacking = false
	target.Using_Skill = false
	target.direction = Vector2.ZERO
	target.velocity = Vector2.ZERO
	target.Repel = Vector2.ZERO
	# 伞夫本体也停止普通移动，Attack3 后半段只播放动作，不再推着目标挤墙。
	direction = Vector2.ZERO
	velocity = Vector2.ZERO
	Repel = Vector2.ZERO
	_update_attack3_pinned_target()


func _attack3_pin_desired_global_position() -> Vector2:
	# V83：首选编辑器里可直接拖拽的 Marker2D。它属于攻击范围 authored 节点，
	# 会与真实攻击 Shape 一样继承左右镜像、攻击范围整体倍率和本次攻击的小角度瞄准旋转。
	if attack3_pin_marker != null and is_instance_valid(attack3_pin_marker):
		return attack3_pin_marker.global_position

	# 兼容旧场景：没有 Marker2D 时仍沿用 V82 的脚本偏移。
	var pin_offset:Vector2 = attack3_pin_offset
	if is_character_visual_flipped_h():
		pin_offset.x = -pin_offset.x
	if attack3_hit_shape != null and is_instance_valid(attack3_hit_shape):
		return attack3_hit_shape.to_global(pin_offset)
	if attack3_hit_area != null and is_instance_valid(attack3_hit_area):
		return attack3_hit_area.to_global(pin_offset)
	if attack_range_root != null and is_instance_valid(attack_range_root):
		return attack_range_root.to_global(pin_offset)
	return to_global(pin_offset)


func _attack3_pin_global_position(target:ball) -> Vector2:
	var desired:Vector2 = _attack3_pin_desired_global_position()
	if target == null or not is_instance_valid(target):
		return desired
	return _attack3_resolve_non_overlapping_pin_position(target,desired)


func _body_collision_shapes_for_ball(owner_ball:ball) -> Array[CollisionShape2D]:
	var result:Array[CollisionShape2D] = []
	if owner_ball == null or not is_instance_valid(owner_ball):
		return result
	# ball.tscn 的实体身体 Shape 是 CharacterBody2D 的直接子节点；hitbox / hurtbox 下的 Shape 不属于实体碰撞。
	for child:Node in owner_ball.get_children():
		if child is CollisionShape2D:
			var shape_node:CollisionShape2D = child as CollisionShape2D
			if not shape_node.disabled and shape_node.shape != null:
				result.append(shape_node)
	return result


func _attack3_target_body_overlaps_self_at(
	target:ball,
	target_position:Vector2,
	target_shapes:Array[CollisionShape2D],
	self_shapes:Array[CollisionShape2D]
) -> bool:
	var delta:Vector2 = target_position - target.global_position
	for target_shape:CollisionShape2D in target_shapes:
		if target_shape == null or not is_instance_valid(target_shape) or target_shape.shape == null:
			continue
		var target_test_transform:Transform2D = target_shape.global_transform
		target_test_transform.origin += delta
		for own_shape:CollisionShape2D in self_shapes:
			if own_shape == null or not is_instance_valid(own_shape) or own_shape.shape == null:
				continue
			if target_shape.shape.collide(
				target_test_transform,
				own_shape.shape,
				own_shape.global_transform
			):
				return true
	return false


func _attack3_resolve_non_overlapping_pin_position(target:ball,desired:Vector2) -> Vector2:
	# 用户在编辑器中拖的是“期望点”。这里只做最小必要修正：如果真实身体 Shape 会与伞夫身体 Shape 重叠，
	# 就沿伞夫身体中心 -> Marker 的方向向外推，直到完全分离，再留 safe_margin。
	var target_shapes:Array[CollisionShape2D] = _body_collision_shapes_for_ball(target)
	var self_shapes:Array[CollisionShape2D] = _body_collision_shapes_for_ball(self)
	if target_shapes.is_empty() or self_shapes.is_empty():
		return desired

	var self_center:Vector2 = global_position
	if not self_shapes.is_empty():
		self_center = self_shapes[0].global_position
	var push_direction:Vector2 = desired - self_center
	if push_direction.length_squared() <= 0.0001:
		push_direction = Vector2.LEFT if is_character_visual_flipped_h() else Vector2.RIGHT
	else:
		push_direction = push_direction.normalized()

	# Marker 本身已经安全时严格使用用户拖出的原位置，不做任何额外偏移。
	if not _attack3_target_body_overlaps_self_at(target,desired,target_shapes,self_shapes):
		return desired

	var candidate:Vector2 = desired
	var step:float = maxf(attack3_pin_adjust_step,1.0)
	var moved:float = 0.0
	var max_distance:float = maxf(attack3_pin_adjust_max_distance,step)
	while moved <= max_distance:
		candidate += push_direction * step
		moved += step
		if not _attack3_target_body_overlaps_self_at(target,candidate,target_shapes,self_shapes):
			# 只有 Marker 原位置确实发生重叠时，才在刚好分离后继续留一点安全缝。
			return candidate + push_direction * maxf(attack3_pin_safe_margin,0.0)

	# 极端超大碰撞体时，至少返回已经向外推到上限的位置，不退回会重叠的 Marker 原点。
	return candidate


func _update_attack3_pinned_target() -> void:
	if _attack3_pinned_target == null or not is_instance_valid(_attack3_pinned_target):
		_attack3_pinned_target = null
		_attack3_pin_serial = -1
		_attack3_pin_lock_acquired = false
		_attack3_collision_filter_saved = false
		return
	if _attack3_pinned_target.health <= 0:
		_release_attack3_pin(_attack3_pin_serial,false)
		return
	if _attack3_pin_serial != _action_serial:
		_release_attack3_pin(_attack3_pin_serial,false)
		return

	# 固定期间双方都不执行自主位移；目标 CharacterBody2D 的实体碰撞也已暂时关闭，
	# 所以不会再出现“敌人作为实体把伞夫顶着卡进墙”的情况。
	direction = Vector2.ZERO
	velocity = Vector2.ZERO
	Repel = Vector2.ZERO
	_attack3_pinned_target.direction = Vector2.ZERO
	_attack3_pinned_target.velocity = Vector2.ZERO
	_attack3_pinned_target.Repel = Vector2.ZERO
	_attack3_pinned_target.global_position = _attack3_pin_global_position(_attack3_pinned_target)


func _release_attack3_pin(serial:int = -1,apply_release_stun:bool = false) -> void:
	if _attack3_pinned_target == null or not is_instance_valid(_attack3_pinned_target):
		_attack3_pinned_target = null
		_attack3_pin_serial = -1
		_attack3_pin_lock_acquired = false
		_attack3_collision_filter_saved = false
		return
	if serial >= 0 and _attack3_pin_serial != serial:
		return

	var target:ball = _attack3_pinned_target
	var had_lock:bool = _attack3_pin_lock_acquired
	var restore_collision_filter:bool = _attack3_collision_filter_saved
	var saved_collision_layer:int = _attack3_saved_collision_layer
	var saved_collision_mask:int = _attack3_saved_collision_mask
	_attack3_pinned_target = null
	_attack3_pin_serial = -1
	_attack3_pin_lock_acquired = false
	_attack3_collision_filter_saved = false

	target.Repel = Vector2.ZERO
	target.velocity = Vector2.ZERO

	# V81：先完整恢复目标进入固定前的 CharacterBody2D 碰撞配置，再交回正常控制/眩晕。
	if restore_collision_filter:
		target.collision_layer = saved_collision_layer
		target.collision_mask = saved_collision_mask

	if had_lock:
		var old_count:int = int(target.get_meta(ATTACK3_CONTROL_LOCK_META,0))
		var new_count:int = maxi(old_count - 1,0)
		if new_count > 0:
			target.set_meta(ATTACK3_CONTROL_LOCK_META,new_count)
		else:
			var baseline:bool = bool(target.get_meta(ATTACK3_CONTROL_BASELINE_META,false))
			target.dizziness = baseline
			target.remove_meta(ATTACK3_CONTROL_LOCK_META)
			target.remove_meta(ATTACK3_CONTROL_BASELINE_META)

	# 只有正常播放到攻击结束才追加后置眩晕；被打断/死亡时只负责放人，避免永久控制。
	if apply_release_stun and target.health > 0 and attack3_stun_duration > 0.0:
		target.apply_stun(attack3_stun_duration)


func _end_attack_hit_window(serial:int = -1) -> void:
	if serial >= 0 and _attack_hit_serial != serial:
		return
	if _active_attack_area != null and is_instance_valid(_active_attack_area):
		_active_attack_area.monitoring = false
		_active_attack_area.collision_mask = 0
	_active_attack_area = null
	_restore_attack_debug_preview_meta()

	_attack_hit_active = false
	_attack_hit_damage = 0.0
	_attack_hit_stun_duration = 0.0
	_attack_hit_success_sfx = ""
	_attack_hit_success_sfx_played = false
	_attack_hit_target_filter_id = 0
	_attack_hit_target_ids.clear()


func _tick_self_sinking(delta:float) -> void:
	if not is_combat_runtime_active():
		return
	if _self_sinking <= 0:
		_sinking_elapsed = 0.0
		return

	_sinking_elapsed += delta
	if _sinking_elapsed < self_sinking_tick:
		return

	_sinking_elapsed = 0.0
	_self_sinking = maxi(_self_sinking - 1,0)
	change_sanity(-self_sinking_sp_loss)


func _add_self_sinking(amount:int) -> void:
	_self_sinking = clampi(
		_self_sinking + amount,
		0,
		self_sinking_max
	)


# ============================================================
# V56 理智伤害倍率
# ============================================================
func _sanity_outgoing_multiplier() -> float:
	if sanity >= 0.0 and sanity <= positive_sanity_upper:
		return 1.0 - positive_sanity_damage_reduction
	if sanity <= max_negative_sanity_trigger:
		return 1.0 + max_negative_sanity_damage_bonus
	return 1.0


func _sanity_incoming_multiplier() -> float:
	if sanity >= 0.0 and sanity <= positive_sanity_upper:
		return 1.0 + positive_sanity_incoming_increase
	return 1.0


func _apply_sanity_outgoing_damage(raw_damage:float) -> float:
	return maxf(raw_damage,0.0) * _sanity_outgoing_multiplier()


# ball.receive_positional_damage()、碰撞伤害等常规伤害路径最终都会调用 take_damage()。
# 在这里统一乘正理智易伤，避免只给某一个技能/某一种来源做 +20%。
func take_damage(damage:float,ignore_block:bool = false) -> void:
	super.take_damage(damage * _sanity_incoming_multiplier(),ignore_block)



# ============================================================
# V77 攻击1 / 攻击2随机起手语音
# ============================================================
func _try_play_attack_voice_once() -> void:
	# 只从攻击1/2序列入口调用一次，因此后续追加第二/第三段不会重复抽取。
	# 0 = 不播放，1 = 哈1，2 = 哈2；三种结果等概率。
	match randi_range(0,2):
		1:
			_play_attack_sfx_everywhere(ATTACK_VOICE_HA1_SFX)
		2:
			_play_attack_sfx_everywhere(ATTACK_VOICE_HA2_SFX)
		_:
			pass


# ============================================================
# V73 挥舞 / 命中分层攻击音效
# ============================================================
func _play_attack_sfx_everywhere(sfx_name:String) -> void:
	if sfx_name.is_empty():
		return
	if Audios == null or Audios.Sfx == null or not Audios.Sfx.has_node(sfx_name):
		push_warning("伞夫：找不到攻击音效 Sfx/%s。" % sfx_name)
		return

	# 战斗逻辑只在角色权威端执行；联网时交给 Audios 的 call_local RPC，
	# 让本机与所有远端各播放一次。离线模式直接本地播放。
	# create_new_audio=true：每段使用独立 voice，长尾不会被下一段截断。
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc(sfx_name,{},false,true)
	else:
		Audios.play_sfx(sfx_name,{},false,true)


func _setup_opening_greeting_trigger() -> void:
	var world:Node = get_tree().current_scene if get_tree() != null else null
	if world == null or not is_instance_valid(world):
		return

	if world.has_signal("character_dialogue_battle_started"):
		var callable := Callable(
			self,
			"_on_character_dialogue_battle_started"
		)
		if not world.is_connected(
			"character_dialogue_battle_started",
			callable
		):
			world.connect(
				"character_dialogue_battle_started",
				callable
			)


func _on_character_dialogue_battle_started(_serial:int) -> void:
	if _opening_greeting_handled or health <= 0:
		return

	_opening_greeting_handled = true
	if not bool(Game.Game_Settings.get("Enable_Dialogue",false)):
		return

	var world:Node = get_tree().current_scene if get_tree() != null else null
	if world == null or not is_instance_valid(world):
		return

	say_dialogue_animated(
		OPENING_GREETING_TEXT,
		greeting_text_reveal_duration,
		greeting_text_hold_duration,
		greeting_text_fade_duration
	)
	_play_opening_greeting_voice(world)


func _play_opening_greeting_voice(world:Node) -> void:
	if world == null or not is_instance_valid(world) or OPENING_GREETING_AUDIO == null:
		return

	var player := AudioStreamPlayer.new()
	player.name = "UmbrellaOpeningGreeting"
	player.stream = OPENING_GREETING_AUDIO
	player.volume_db = greeting_voice_volume_db
	player.bus = "Master"
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.add_child(player)
	player.finished.connect(
		player.queue_free,
		CONNECT_ONE_SHOT
	)
	player.call_deferred("play")
