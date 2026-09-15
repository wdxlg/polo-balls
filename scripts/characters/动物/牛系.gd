extends ball

# ========================================================
# 牛 / 牛犊子共用脚本 v5
#
# 修正重点：
# 1. 伤害不再依赖“上一帧 Damage 属性有没有被 World 覆盖”。
#    命中瞬间直接按照当前 Speed 计算本次冲撞伤害。
# 2. 伤害真正“随速度变化”：
#       速度下降 -> 伤害下降
#       速度上升 -> 伤害上升
#       吃草静止 -> 速度和冲撞伤害归零
#       Speed Buff / Debuff -> 伤害跟着变化
# 3. base_run_speed 时 = Damage × 1.0
#    max_run_speed 时 = Damage × max_charge_damage_multiplier
#    两者之间默认线性变化。
# 4. 继续保留 v4：
#    撞到角色结束当前冲撞并重新蓄力；
#    低受伤阈值 = 撞完后吃草；
#    高受伤阈值 = 直接打断并吃草。
# ========================================================


@export_category("冲刺成长")
@export var base_run_speed:float = 120.0
@export var speed_growth_rate:float = 0.18
@export var max_run_speed:float = 1600.0


@export_category("速度决定伤害")
@export_range(1.0,30.0,0.05) var max_charge_damage_multiplier:float = 18.75

# 1.0 = 速度和伤害完全线性对应。
# < 1.0 = 中段伤害成长更快。
# > 1.0 = 前期成长较慢，后期成长更快。
@export_range(0.1, 4.0, 0.05) var damage_speed_exponent:float = 0.75


@export_category("受伤触发吃草")

# 低阈值：
# 本次冲撞继续，等撞到角色结束后再吃草。
@export var graze_after_charge_damage_threshold:float = 120.0

# 高阈值：
# 立即终止当前冲撞并吃草。
@export var graze_interrupt_damage_threshold:float = 220.0

# 累计受伤值会持续向 0 衰减。
# 单位：每秒衰减多少累计伤害。
@export var graze_damage_decay_per_second:float = 12.0

# 冲撞刚结束的一小段时间内受到的伤害仍算作本次冲撞伤害，
# 避免同一碰撞帧里物理回调顺序导致伤害漏记。
@export var charge_damage_grace_time:float = 0.10


@export_category("吃草")
@export var graze_duration:float = 3.0
# 兼容旧场景保留；当前版本吃草期间强制静止，因此该倍率不再参与移动。
@export_range(0.0, 1.0, 0.05) var graze_speed_multiplier:float = 0.0
@export var graze_heal_per_second:float = 40.0
# 持续回血按小段结算，避免每帧 +1 产生几十个绿色跳字。
@export var graze_heal_tick_interval:float = 0.5


@export_category("速度文字")
@export var display_meters_per_world_unit:float = 1.0
@export var switch_to_km_per_second_at:float = 1000.0


@export_category("吃草动画")
# AnimatedSprite2D 中的动画名。
# 当前行为：
# - 吃草期间：只显示第 1 帧，保持静止。
# - 吃草结束：从第 1 帧播放到第 17 帧一次，播完自动隐藏。
@export var graze_animation_name:StringName = &"graze"

# 嘴前方的基础本地坐标。X 为前后，Y 为上下。
# 一般不用频繁改；牛和牛犊子可以各自保留自己的基础嘴位置。
@export var graze_animation_mouth_offset:Vector2 = Vector2(110.0, 18.0)

# 【常用调节】草动画额外偏移。
# Inspector 里直接调 X / Y：
# X：沿嘴朝向前后移动；Y：上下移动。
# 左右翻转时 X 会自动跟着嘴换边。
@export var graze_animation_offset:Vector2 = Vector2.ZERO

# 【常用调节】草动画缩放。
# X / Y 可以分别调；保持比例时两个值填一样。
# 例如 Vector2(0.25, 0.25) = 原尺寸的四分之一。
@export var graze_animation_scale:Vector2 = Vector2(0.333333, 0.333333)

# 跟随角色图片的 flip_h 自动镜像到另一侧嘴前。
@export var graze_animation_follow_flip_h:bool = true

# 动画整体播放倍率。1.0 = SpriteFrames 中设置的原速度。
@export_range(0.05, 5.0, 0.05) var graze_animation_speed_scale:float = 1.0


#========================================================
# 图片接口
#
# 现在 tscn 里先放了项目中已有的随机图片作为占位。
# 后续直接在 Inspector 替换这三个 Texture2D 即可。
#========================================================
@export_category("形态图片接口")
@export var slow_texture:Texture2D
@export var fast_texture:Texture2D
@export var graze_texture:Texture2D

# 速度达到这里后：
# 1. 切 fast_texture
# 2. 开始持续播放 fast_sound
@export var fast_state_speed_threshold:float = 400.0


#========================================================
# 声音接口
#
# 使用你项目现有 Audios.play_sfx 的“声音名”接口。
# 后续只需要在 Inspector 修改字符串。
#========================================================
@export_category("声音接口")
@export var fast_sound:String = "balls_collide1"
@export var fast_sound_repeat_interval:float = 0.55

@export var graze_start_sound:String = "BlockAtk1"
@export var graze_end_sound:String = "DefenseBreak"


@onready var speed_label:Label = $SpeedLabel
@onready var graze_animated_sprite:AnimatedSprite2D = (
	get_node_or_null("Graphics/GrazeAnimatedSprite2D")
	as AnimatedSprite2D
)


enum CowVisualState {
	SLOW,
	FAST,
	GRAZE
}

var _visual_state:int = -1
var _fast_sound_elapsed:float = 0.0


# 当前这一趟冲撞蓄力时间。
var running_time:float = 0.0

# 累计受伤槽：
# - 多次受伤会叠加。
# - 普通撞人结束冲撞时不会清零。
# - 会随时间慢慢衰减。
# - 真正进入吃草时才清零。
var accumulated_charge_damage:float = 0.0

# 当前累计值是否已经达到“本次冲撞结束后吃草”的低阈值。
# 这是一个随累计值衰减动态变化的状态，不是永久标记。
var graze_after_current_charge:bool = false

# 最近一次处于冲刺状态后的短暂宽限计时。
# 用来避免同一碰撞帧中先结束冲撞、后收到伤害时漏记累计值。
var charge_damage_grace_left:float = 0.0

var sprinting:bool = false

var grazing:bool = false
var graze_time_left:float = 0.0
var _graze_heal_carry:float = 0.0
var _graze_heal_tick_elapsed:float = 0.0

var _last_display_position:Vector2


func _ready() -> void:
	super._ready()

	base_run_speed = maxf(base_run_speed, 0.0)
	max_run_speed = maxf(max_run_speed, base_run_speed)

	max_charge_damage_multiplier = maxf(max_charge_damage_multiplier,1.0)

	graze_after_charge_damage_threshold = maxf(
		graze_after_charge_damage_threshold,
		1.0
	)

	graze_interrupt_damage_threshold = maxf(
		graze_interrupt_damage_threshold,
		graze_after_charge_damage_threshold + 1.0
	)

	graze_duration = maxf(graze_duration, 0.05)
	graze_heal_per_second = maxf(graze_heal_per_second, 0.0)
	graze_heal_tick_interval = maxf(graze_heal_tick_interval, 0.05)
	graze_damage_decay_per_second = maxf(graze_damage_decay_per_second, 0.0)
	charge_damage_grace_time = maxf(charge_damage_grace_time, 0.0)

	default_properties["Speed"] = base_run_speed
	Speed = base_run_speed

	_last_display_position = global_position

	if speed_label:
		# 速度文字跟随角色和 Camera 缩放；使用最近邻过滤，避免像素字体/描边发糊。
		speed_label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		speed_label.hide()

	if graze_animated_sprite:
		# 动画层默认隐藏。吃草时只停在第 1 帧；吃完后才完整播放一次。
		graze_animated_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		graze_animated_sprite.speed_scale = graze_animation_speed_scale
		graze_animated_sprite.stop()
		graze_animated_sprite.hide()
		_update_graze_animation_transform()

		if not graze_animated_sprite.animation_finished.is_connected(
			_on_graze_animation_finished
		):
			graze_animated_sprite.animation_finished.connect(
				_on_graze_animation_finished
			)

	# 初始状态固定为慢速图片。
	_set_visual_state(CowVisualState.SLOW, false)


# ========================================================
# 物理更新
# ========================================================

func tick_physics(state:State, delta:float) -> void:
	if is_multiplayer_authority():
		_update_cow_stats(delta)

	super.tick_physics(state, delta)


func _update_cow_stats(delta:float) -> void:
	var natural_speed:float = base_run_speed

	# ----------------------------------------------------
	# 累计受伤槽
	#
	# 不吃草时会慢慢衰减，而不是一旦受伤就永久保留。
	# move_toward 不会越过 0。
	# ----------------------------------------------------
	if not grazing:
		accumulated_charge_damage = move_toward(
			accumulated_charge_damage,
			0.0,
			graze_damage_decay_per_second * delta
		)

		graze_after_current_charge = (
			accumulated_charge_damage
			>= graze_after_charge_damage_threshold
		)

	if charge_damage_grace_left > 0.0:
		charge_damage_grace_left = maxf(
			charge_damage_grace_left - delta,
			0.0
		)

	# ----------------------------------------------------
	# 吃草
	# ----------------------------------------------------
	if grazing:
		sprinting = false

		_heal_while_grazing(delta)

		graze_time_left -= delta

		if graze_time_left <= 0.0:
			_finish_grazing()

		if grazing:
			# 吃草期间完全静止。
			# 不走 _set_natural_speed()，避免 Speed 的 add / Set Buff 把 0 再抬高。
			natural_speed = 0.0
			default_properties["Speed"] = 0.0
			Speed = 0.0
			velocity = Vector2.ZERO

		else:
			natural_speed = base_run_speed
			_set_natural_speed(natural_speed)

	# ----------------------------------------------------
	# 正常冲刺
	# ----------------------------------------------------
	else:
		sprinting = (
			direction.length_squared()
			> 0.0001
		)

		if sprinting:
			running_time += delta
			charge_damage_grace_left = charge_damage_grace_time

		natural_speed = minf(
			base_run_speed
				* exp(
					speed_growth_rate
					* running_time
				),
			max_run_speed
		)

		_set_natural_speed(natural_speed)

	# ----------------------------------------------------
	# V107：速度只改变“冲撞倍率”，不再改写整体攻击力 Damage。
	# Damage Buff / Boss 倍率仍由 World 统一维护。

	# 根据当前状态/速度更新图片与声音。
	_update_visual_and_audio(delta)


func _set_natural_speed(
	natural_speed:float
) -> void:
	# World 每个物理帧都会先从 default_properties 恢复属性，
	# 然后再应用 Buff。
	#
	# 牛自己也在物理帧内改变“自然冲刺速度”，所以这里不能在
	# 存在 Speed Buff 时继续沿用上一帧的 Speed；
	# 否则高速成长和减速 Buff 会出现一帧甚至更久的不同步。
	default_properties["Speed"] = natural_speed

	# 本帧立刻重新计算“真正有效速度”：
	#
	# effective Speed =
	#     当前自然冲刺速度
	#     -> Speed add/mul/Set Buff
	#
	# 这样：
	# - 牛加速后，伤害本帧就跟着涨。
	# - 敌人减速后，伤害本帧就跟着降。
	# - Speed Set / mul / add 都与 World 的规则一致。
	Speed = _return_property_after_buffs(
		natural_speed,
		Buff.Buff_types.Speed
	)


#========================================================
# 按 World.figure_buffs() 的规则，把某一种属性 Buff
# 重新作用到给定基础值上。
#
# 顺序：
# index 0 -> 1 -> 2 -> 3
#
# 算法：
# add / mul / Set
#========================================================
func _return_property_after_buffs(
	base_value:float,
	buff_type:Buff.Buff_types
) -> float:
	var result:float = base_value

	for buff_index in 4:
		for source_id in Buff_Dic:
			for buff_name in Buff_Dic[source_id]:
				var active_buff = (
					Buff_Dic[source_id][buff_name]
				)

				if not active_buff is Buff:
					continue

				if active_buff.duration <= 0.0:
					continue

				if active_buff.buff_type != buff_type:
					continue

				if active_buff.index != buff_index:
					continue

				match active_buff.algorithm:
					Buff.Algorithms.add:
						result += float(
							active_buff.amount
						)

					Buff.Algorithms.mul:
						result *= float(
							active_buff.amount
						)

					Buff.Algorithms.Set:
						result = float(
							active_buff.amount
						)

	return maxf(result, 0.0)



# ========================================================
# 速度 -> 伤害
#
# 这里是真正的角色核心。
#
# 速度为 0：
#     伤害 = 0
#
# 速度为初速：
#     伤害 = 基础伤害
#
# 速度为最高速：
#     伤害 = 最高伤害
#
# 如果速度因为减速 Buff 低于初速：
#     伤害也按比例下降。
# ========================================================

func return_damage_multiplier_from_speed(world_speed:float) -> float:
	var current_speed:float = maxf(world_speed,0.0)
	if current_speed <= 0.001:
		return 0.0
	if current_speed <= base_run_speed:
		if base_run_speed <= 0.001:
			return 0.0
		return clampf(current_speed / base_run_speed,0.0,1.0)
	var speed_range:float = maxf(max_run_speed - base_run_speed,0.001)
	var t:float = clampf((current_speed - base_run_speed) / speed_range,0.0,1.0)
	t = pow(t,damage_speed_exponent)
	return lerpf(1.0,maxf(max_charge_damage_multiplier,1.0),t)


func current_hit_damage_multiplier() -> float:
	return return_damage_multiplier_from_speed(Speed)


func return_current_impact_damage() -> int:
	return maxi(int(round(attack_damage(current_hit_damage_multiplier()))),0)


# ========================================================
# 命中
#
# 基础 ball 的信号连接本来就是：
# hitbox.on_hit -> _on_hitbox_on_hit
#
# 这里覆盖这个方法。
#
# 最重要：
# 不再信任“之前保存的 Damage 值”，
# 而是在命中这一刻从当前 Speed 重新计算。
# ========================================================

func _on_hitbox_on_hit(
	hurt:hurtbox
) -> void:
	if not is_multiplayer_authority():
		return

	if (
		state_machine.current_state
		== State.Die
		or dizziness
	):
		return

	var impact_damage:int = (
		return_current_impact_damage()
	)

	if impact_damage <= 0:
		return

	var target:ball = _hurtbox_target_ball(hurt)
	if target == null:
		return

	if (
		target.block < impact_damage
		or ignore_block
	):
		Audios.play_sfx.rpc(
			Hit_Audio,
			{
				volume = clampf(
					float(impact_damage) - 12.0,
					-100.0,
					0.0
				)
			},
			true
		)

		# V88：牛系冲撞原本手动 hit_white + take_damage，绕过了公共受击爆射线。
		# 改走统一位置伤害入口，伤害/格挡语义不变，同时获得命中方向对应的受击线。
		target.receive_positional_damage(
			float(impact_damage),
			global_position,
			ignore_block,
			self
		)

		get_tree().current_scene.camera_shake_amount += (
			float(impact_damage)
		)


# ========================================================
# 吃草回血
# ========================================================

func _heal_while_grazing(
	delta:float
) -> void:
	if (
		graze_heal_per_second <= 0.0
		or health <= 0
		or health >= Max_health
	):
		return

	_graze_heal_tick_elapsed += delta

	if (
		_graze_heal_tick_elapsed
		< graze_heal_tick_interval
	):
		return

	var elapsed:float = _graze_heal_tick_elapsed
	_graze_heal_tick_elapsed = fmod(
		_graze_heal_tick_elapsed,
		graze_heal_tick_interval
	)

	var heal_float:float = (
		graze_heal_per_second
		* elapsed
		+ _graze_heal_carry
	)

	var whole_heal:int = int(
		floor(heal_float)
	)

	_graze_heal_carry = (
		heal_float
		- float(whole_heal)
	)

	if whole_heal > 0:
		# 使用 ball 的统一回血接口。
		# health setter 会先真正修改生命，
		# 然后 HealthBar 再生成绿色跳字。
		heal(
			whole_heal
		)


func _has_active_buff_type(
	buff_type:Buff.Buff_types
) -> bool:
	for source_id in Buff_Dic:
		for buff_name in Buff_Dic[source_id]:
			var active_buff = (
				Buff_Dic[source_id][buff_name]
			)

			if (
				active_buff is Buff
				and active_buff.buff_type
				== buff_type
				and active_buff.duration > 0.0
			):
				return true

	return false


# ========================================================
# 图片 / 声音状态
# ========================================================

func _update_visual_and_audio(delta:float) -> void:
	if grazing:
		if _visual_state != CowVisualState.GRAZE:
			_set_visual_state(CowVisualState.GRAZE, true)

		_fast_sound_elapsed = 0.0
		return

	var is_fast:bool = (
		sprinting
		and Speed >= fast_state_speed_threshold
	)

	if is_fast:
		if _visual_state != CowVisualState.FAST:
			_set_visual_state(CowVisualState.FAST, true)
			_fast_sound_elapsed = 0.0
		else:
			_fast_sound_elapsed += delta

			if (
				fast_sound_repeat_interval > 0.0
				and _fast_sound_elapsed
				>= fast_sound_repeat_interval
			):
				_fast_sound_elapsed = fmod(
					_fast_sound_elapsed,
					fast_sound_repeat_interval
				)
				_play_cow_sound(fast_sound)

	else:
		_fast_sound_elapsed = 0.0

		if _visual_state != CowVisualState.SLOW:
			_set_visual_state(CowVisualState.SLOW, false)


func _set_visual_state(
	new_state:int,
	play_state_sound:bool = true
) -> void:
	if _visual_state == new_state:
		return

	_visual_state = new_state

	# Texture 不在你原 ball.tscn 的 MultiplayerSynchronizer 列表中，
	# 因此这里主动同步视觉状态。
	if multiplayer.has_multiplayer_peer():
		_sync_cow_visual_state.rpc(
			new_state
		)
	else:
		_sync_cow_visual_state(
			new_state
		)

	if not play_state_sound:
		return

	match new_state:
		CowVisualState.FAST:
			_play_cow_sound(fast_sound)

		CowVisualState.GRAZE:
			_play_cow_sound(graze_start_sound)


@rpc("authority","call_local")
func _sync_cow_visual_state(
	new_state:int
) -> void:
	_visual_state = new_state

	match new_state:
		CowVisualState.SLOW:
			_stop_graze_animation()
			_set_character_texture(
				slow_texture
			)

		CowVisualState.FAST:
			_stop_graze_animation()
			_set_character_texture(
				fast_texture
			)

		CowVisualState.GRAZE:
			_set_character_texture(
				graze_texture
			)
			_show_graze_animation_still()


# ========================================================
# 嘴前吃草 AnimatedSprite2D
#
# 节点挂在 Graphics 下，所以会自动跟随角色本体的位置/旋转/缩放。
# 这里额外跟随 Image.flip_h，把动画层镜像到当前嘴朝向的一侧。
# ========================================================
func _show_graze_animation_still() -> void:
	if graze_animated_sprite == null:
		return

	_update_graze_animation_transform()

	var frames:SpriteFrames = graze_animated_sprite.sprite_frames
	if (
		frames == null
		or not frames.has_animation(graze_animation_name)
	):
		graze_animated_sprite.hide()
		return

	# 吃草期间只显示第 1 帧，不播放。
	graze_animated_sprite.stop()
	graze_animated_sprite.animation = graze_animation_name
	graze_animated_sprite.frame = 0
	graze_animated_sprite.show()


func _play_graze_finish_animation() -> void:
	if graze_animated_sprite == null:
		return

	_update_graze_animation_transform()

	var frames:SpriteFrames = graze_animated_sprite.sprite_frames
	if (
		frames == null
		or not frames.has_animation(graze_animation_name)
	):
		graze_animated_sprite.hide()
		return

	graze_animated_sprite.speed_scale = maxf(
		graze_animation_speed_scale,
		0.05
	)

	# stop() 会把播放位置重置到第 1 帧，然后完整播放一次。
	graze_animated_sprite.stop()
	graze_animated_sprite.animation = graze_animation_name
	graze_animated_sprite.frame = 0
	graze_animated_sprite.show()
	graze_animated_sprite.play(graze_animation_name)


func _broadcast_graze_finish_animation() -> void:
	if multiplayer.has_multiplayer_peer():
		_sync_play_graze_finish_animation.rpc()
	else:
		_sync_play_graze_finish_animation()


@rpc("authority","call_local")
func _sync_play_graze_finish_animation() -> void:
	_play_graze_finish_animation()


func _on_graze_animation_finished() -> void:
	if graze_animated_sprite == null:
		return

	# graze 在场景中被设为非循环，所以第 17 帧结束时会进这里。
	if graze_animated_sprite.animation == graze_animation_name:
		graze_animated_sprite.hide()


func _stop_graze_animation() -> void:
	if graze_animated_sprite == null:
		return

	graze_animated_sprite.stop()
	graze_animated_sprite.hide()


func _update_graze_animation_transform() -> void:
	if graze_animated_sprite == null:
		return

	# 基础嘴位置 + 用户微调偏移。
	# 先相加再处理左右朝向，这样额外 X 偏移也会跟着嘴自动换边。
	var mouth_offset:Vector2 = (
		graze_animation_mouth_offset
		+ graze_animation_offset
	)

	if (
		graze_animation_follow_flip_h
		and image is Sprite2D
	):
		var facing_flipped:bool = is_character_visual_flipped_h()
		mouth_offset.x *= (-1.0 if facing_flipped else 1.0)
		graze_animated_sprite.flip_h = facing_flipped
	else:
		graze_animated_sprite.flip_h = false

	# 缩放也由牛根节点的 Inspector 导出属性统一控制。
	# 防止误填 0 或负数导致动画完全消失/镜像混乱。
	graze_animated_sprite.scale = Vector2(
		maxf(absf(graze_animation_scale.x), 0.01),
		maxf(absf(graze_animation_scale.y), 0.01)
	)

	graze_animated_sprite.position = mouth_offset


func _set_character_texture(texture:Texture2D) -> void:
	if texture == null:
		return

	# 牛/牛犊子现在继承基础 ball.tscn 的 Sprite2D Image。
	if image is Sprite2D:
		image.texture = texture
		_refit_character_visual_only()


func _refit_character_visual_only() -> void:
	var auto_fit := get_node_or_null("CharacterAutoFit")
	if auto_fit != null and auto_fit.has_method("apply_visual_fit_only"):
		auto_fit.call("apply_visual_fit_only")


func _play_cow_sound(sound_name:String) -> void:
	if sound_name.is_empty():
		return

	if not is_multiplayer_authority():
		return

	# 沿用你项目现有的 Audios autoload。
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc(
			sound_name,
			{},
			true
		)
	else:
		Audios.play_sfx(
			sound_name,
			{},
			true
		)


# ========================================================
# 撞到角色 -> 当前冲撞结束
# ========================================================

func when_collide(
	speed:float,
	collision:KinematicCollision2D
):
	var was_sprinting:bool = (
		sprinting
		and not grazing
	)
	var direction_before_collision:Vector2 = direction

	var collider = (
		collision.get_collider()
	)

	# 保留 ball 原本的碰撞音效 / 形变。普通碰撞仍会反弹；
	# 如果这一撞直接击杀敌人，下面会把方向恢复为撞击前方向，形成真正的“撞穿”。
	super.when_collide(
		speed,
		collision
	)

	if not is_multiplayer_authority():
		return

	if not was_sprinting:
		return

	# 撞墙不清蓄力。
	# 撞到友方角色也不结束冲刺：
	# 仍保留 ball 原本的实体碰撞 / 反弹，但不清速度蓄力、不进入吃草。
	# 只有撞到敌方的真正角色 Ball 才结束本轮冲刺。
	if _is_character_ball(collider):
		if _is_friendly_character_ball(collider):
			return

		# 实体接触命中会在 when_collide() 之前结算。
		# 如果这一撞已经把敌人击杀，就继续保持当前冲撞蓄力：
		# 不重置 running_time、不降回基础速度，也不因为这次击杀进入吃草。
		# 这样牛可以真正“撞穿”残血敌人继续冲。
		if collider.health <= 0:
			if direction_before_collision.length_squared() > 0.000001:
				direction = direction_before_collision.normalized()
			return

		_end_charge_after_character_hit()


func _is_friendly_character_ball(
	collider
) -> bool:
	if not _is_character_ball(collider):
		return false

	# 空队伍不视为友方，避免“未选队伍”的角色全部互相判成队友。
	if Team == "" or collider.Team == "":
		return false

	return collider.Team == Team


func _is_character_ball(
	collider
) -> bool:
	if collider == null:
		return false

	if collider is ball:
		return (
			collider.Type
			== Ball_Type.Ball
		)

	return false


func _end_charge_after_character_hit() -> void:
	# 使用“此刻仍剩下多少累计受伤”来判断。
	# 如果之前超过低阈值、但已经衰减到阈值以下，
	# 就不会再强制吃草。
	var should_graze_after_hit:bool = (
		accumulated_charge_damage
		>= graze_after_charge_damage_threshold
	)

	sprinting = false
	charge_damage_grace_left = charge_damage_grace_time

	# 撞人只清空“速度蓄力”，不清空累计受伤槽。
	running_time = 0.0

	_reset_charge_stats()

	if speed_label:
		speed_label.hide()

	if should_graze_after_hit:
		_begin_grazing()


func _reset_charge_stats() -> void:
	default_properties["Speed"] = (
		base_run_speed
	)

	if not _has_active_buff_type(
		Buff.Buff_types.Speed
	):
		Speed = base_run_speed

	# V111：Damage 始终保留“整体基础攻击力”，这里不能再按速度回写 Damage。
	# 真正的冲撞伤害会在命中瞬间通过
	# attack_damage(return_damage_multiplier_from_speed(Speed)) 计算。


# ========================================================
# 受伤：两档吃草
# ========================================================

func take_damage(
	damage:float,
	ignore_block:bool = false
) -> void:
	# 正在冲刺，或者刚结束冲撞还处于极短宽限期，
	# 都算作“冲撞期间受到的伤害”。
	var counts_as_charge_damage:bool = (
		not grazing
		and (
			sprinting
			or charge_damage_grace_left > 0.0
		)
	)

	var old_health:float = float(
		health
	)

	super.take_damage(
		damage,
		ignore_block
	)

	# 吃草时不累计；
	# 非冲撞阶段受到伤害也不累计。
	if (
		grazing
		or not counts_as_charge_damage
		or health <= 0
	):
		return

	# 只累计实际扣掉的 HP。
	# 被盾完全挡掉的伤害不进入累计槽。
	var actual_health_damage:float = maxf(
		old_health - float(health),
		0.0
	)

	if actual_health_damage <= 0.0:
		return

	# ----------------------------------------------------
	# 核心：
	# 每一次伤害都加进同一个累计槽。
	#
	# 例如：
	# 40 + 35 + 50 = 125
	#
	# 中间撞到角色、重新蓄力，也不会自动清零。
	# 只有时间衰减，或者真正进入吃草才会清零。
	# ----------------------------------------------------
	accumulated_charge_damage += (
		actual_health_damage
	)

	# 高阈值：
	# 累计槽达到高阈值，立即打断冲撞并吃草。
	if (
		accumulated_charge_damage
		>= graze_interrupt_damage_threshold
	):
		_begin_grazing()
		return

	# 低阈值：
	# 不立即打断。
	# 只要累计槽此刻仍 >= 低阈值，
	# 下一次撞到角色结束冲撞时就吃草。
	graze_after_current_charge = (
		accumulated_charge_damage
		>= graze_after_charge_damage_threshold
	)



# ========================================================
# 吃草
# ========================================================

func _begin_grazing() -> void:
	if grazing:
		return

	grazing = true
	sprinting = false

	graze_time_left = (
		graze_duration
	)

	_graze_heal_carry = 0.0
	_graze_heal_tick_elapsed = 0.0

	running_time = 0.0

	# 真正开始吃草后，才清空累计受伤槽。
	accumulated_charge_damage = 0.0
	graze_after_current_charge = false
	charge_damage_grace_left = 0.0

	# 吃草期间强制完全静止，不允许 Speed Buff 把速度抬起来。
	default_properties["Speed"] = 0.0
	Speed = 0.0
	velocity = Vector2.ZERO

	# V111：吃草时只把 Speed 置 0，不改写整体基础攻击力 Damage。
	# return_current_impact_damage() 会读取当前 Speed，因此静止时冲撞伤害自然为 0。

	if speed_label:
		speed_label.hide()

	_set_visual_state(
		CowVisualState.GRAZE,
		true
	)


func _finish_grazing() -> void:
	grazing = false
	sprinting = false

	graze_time_left = 0.0
	_graze_heal_carry = 0.0
	_graze_heal_tick_elapsed = 0.0

	running_time = 0.0
	accumulated_charge_damage = 0.0
	graze_after_current_charge = false
	charge_damage_grace_left = 0.0

	_reset_charge_stats()

	# 吃完草：
	# 1. 发出结束声音并恢复慢速图片；
	# 2. 再从第 1 帧到第 17 帧播放一次嘴前动画。
	_play_cow_sound(
		graze_end_sound
	)

	_set_visual_state(
		CowVisualState.SLOW,
		false
	)

	_broadcast_graze_finish_animation()



# ========================================================
# 死亡
#
# 牛 / 牛犊子不播放尸体动画、不保留尸体。
# 进入 Ball.State.Die 后立即从场景树删除。
# ========================================================

func Die() -> void:
	# 保留 ball 原本的死亡音效。
	super.Die()

	# transition_state(State.Die) 本身只会在 authority 上调用 Die()。
	# 对 MultiplayerSpawner 管理的角色，authority 删除节点后会同步 despawn。
	if not is_multiplayer_authority():
		return

	if not is_queued_for_deletion():
		queue_free()


# ========================================================
# 速度文字
# ========================================================

func _process(
	delta:float
) -> void:
	# flip_h 可能在移动时由基础 ball 逻辑改变。
	# 动画层显示期间每帧跟一下，保证一直待在嘴前。
	if (
		graze_animated_sprite != null
		and graze_animated_sprite.visible
	):
		_update_graze_animation_transform()

	if speed_label == null:
		return

	var shown_speed:float = Speed

	var show_speed:bool = (
		sprinting
		and not grazing
	)

	if (
		not is_multiplayer_authority()
		and delta > 0.0
	):
		shown_speed = (
			global_position.distance_to(
				_last_display_position
			)
			/ delta
		)

		show_speed = (
			shown_speed
			>= base_run_speed * 0.75
		)

	_last_display_position = (
		global_position
	)

	speed_label.visible = (
		show_speed
	)

	if show_speed:
		_update_speed_label(
			shown_speed
		)


func _update_speed_label(
	world_speed:float
) -> void:
	var meters_per_second:float = (
		maxf(world_speed, 0.0)
		* display_meters_per_world_unit
	)

	if (
		meters_per_second
		>= switch_to_km_per_second_at
	):
		speed_label.text = (
			"%.2f km/s"
			% (
				meters_per_second
				/ 1000.0
			)
		)

	elif meters_per_second >= 100.0:
		speed_label.text = (
			"%.0f m/s"
			% meters_per_second
		)

	else:
		speed_label.text = (
			"%.1f m/s"
			% meters_per_second
		)
