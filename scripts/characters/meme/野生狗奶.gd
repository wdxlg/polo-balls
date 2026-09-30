extends ball

# 野生狗奶：周期性让“世界时间”越来越慢，从自身视角等价于时间不断加速。
# 自己按本次时间倍率补偿移动与阶段计时，因此不会被自己的时间场拖慢。
# 敌人的衰老跨多次时间场永久累计，属性按百分比衰退；到阈值后直接老死。

const AGE_META:StringName = &"wild_dog_milk_age_percent"
const AGE_BASE_SPEED_META:StringName = &"wild_dog_milk_age_base_speed"
const AGE_BUFF_SOURCE_ID:int = -256001
const AGE_STATUS_KEY:String = "wild_dog_milk_age"
const OLD_AGE_DEATH_DEADLINE_META:StringName = &"wild_dog_milk_old_age_death_deadline_msec"
const OLD_AGE_DEATH_HEALTH_META:StringName = &"wild_dog_milk_old_age_death_health_before"
const AGE_VISUAL_NODE_NAME:StringName = &"野生狗奶_衰老骷髅_V307"
const AGE_VISUAL_SCRIPT = preload("res://scripts/effects/野生狗奶衰老骷髅.gd")
const WILD_DOG_MILK_MAX_HEALTH:int = 400

@export_category("野生狗奶 - 时间加速")
@export_range(0.5,20.0,0.1) var first_time_acceleration_delay:float = 4.0
@export_range(0.5,30.0,0.1) var time_acceleration_cooldown:float = 15.0
@export_range(0.5,20.0,0.1) var time_acceleration_duration:float = 12.0
@export_range(0.10,1.0,0.01) var world_factor_start:float = 0.78
@export_range(0.05,1.0,0.01) var world_factor_end:float = 0.24
@export_range(0.2,4.0,0.05) var acceleration_curve_power:float = 1.65
@export var time_acceleration_tint:Color = Color(0.0,0.0,0.0,0.0)
@export_range(0.10,8.0,0.05) var time_visual_cycle_rate_start:float = 0.45
@export_range(0.50,16.0,0.05) var time_visual_cycle_rate_end:float = 4.25
@export_range(0.0,20.0,0.1) var time_acceleration_heal_max_health_percent_per_second:float = 2.5

@export_category("野生狗奶 - 衰老")
@export_range(0.05,2.0,0.01) var aging_pulse_interval_start:float = 0.48
@export_range(0.03,1.0,0.01) var aging_pulse_interval_end:float = 0.09
# V310：基础衰老在 V308 基础上小幅提速；残血的 32x 强非线性倍率保持不变。
# 满血时仍按较低基础每秒率累计；随着缺血比例上升，通过强非线性倍率快速加速。
@export_range(0.05,20.0,0.05) var aging_gain_percent_start:float = 0.60
@export_range(0.05,20.0,0.05) var aging_gain_percent_end:float = 1.20
@export_range(1.0,60.0,0.1) var aging_low_health_max_multiplier:float = 32.0
@export_range(0.2,6.0,0.05) var aging_low_health_curve_power:float = 2.40
@export_range(0.0,2.0,0.01) var aging_damage_multiplier:float = 0.08
@export_range(0.05,1.0,0.01) var aging_min_stat_multiplier:float = 0.32
@export_range(1.0,100.0,1.0) var old_age_death_percent:float = 100.0
@export_range(1,16,1) var max_aging_pulses_per_physics_tick:int = 8

@export_category("野生狗奶 - 衰老视觉")
@export_range(8.0,160.0,1.0) var aging_skull_world_size:float = 28.0
@export_range(0.0,0.99,0.01) var aging_skull_shake_start_opacity:float = 0.95
@export_range(0.0,24.0,0.1) var aging_skull_shake_max_offset:float = 5.0
@export_range(0.0,15.0,0.1) var aging_skull_shake_rotation_deg:float = 3.0

var _time_active:bool = false
var _time_elapsed:float = 0.0
var _cycle_left:float = 0.0
var _aging_pulse_elapsed:float = 0.0
var _current_world_factor:float = 1.0
var _time_source_key:String = ""
var _last_synced_factor:float = -1.0
var _visual_base_scale:Vector2 = Vector2.ONE
var _time_heal_accumulator:float = 0.0

# V269：时间加速期间正式视为无敌窗口。伤害入口在本角色脚本内统一拒绝；
# 血条表现由 Health_bar.set_invincible_display() 在所有客户端切换为金色 INF。
var _time_invincible_visual_active:bool = false


func _ready() -> void:
	Has_Collision_Damage = false
	Can_Attack = false
	Can_Skill = false
	Health_Restore = 0
	# V307：场景本身保存 400 Max_health，同时运行时再强制一次。
	# 即使旧实例/旧 Inspector 仍保存 760，也会在进入战斗时纠正为 400。
	_enforce_wild_dog_max_health()
	super._ready()
	# default_properties 是 @onready 快照；运行时修正后同步它的基础上限。
	default_properties["Max_health"] = WILD_DOG_MILK_MAX_HEALTH
	add_to_group("WildDogMilkCharacter")
	_time_source_key = "wild_dog_milk:%s" % str(get_path())
	_cycle_left = maxf(first_time_acceleration_delay,0.1)
	if image != null and is_instance_valid(image):
		_visual_base_scale = image.scale
	_refresh_time_side_status()


func _enforce_wild_dog_max_health() -> void:
	var desired:int = WILD_DOG_MILK_MAX_HEALTH
	if Max_health == desired and health == desired:
		return
	# HealthBar 子节点先于角色 _ready()；旧场景值被纠正时暂时禁止受伤跳字。
	if health_bar != null and is_instance_valid(health_bar):
		health_bar.suppress_floating_text = true
	Max_health = desired
	if health != desired:
		health = desired
	if health_bar != null and is_instance_valid(health_bar):
		health_bar.suppress_floating_text = false
		health_bar.health_changed.emit(desired,desired,desired,false)


func _exit_tree() -> void:
	_set_time_invincible_visual(false)
	_release_time_override_local()


func Die() -> void:
	_stop_time_acceleration()
	super.Die()


func tick_physics(state:State,delta:float) -> void:
	if not is_multiplayer_authority():
		super.tick_physics(state,delta)
		return

	if health <= 0 or state == State.Die:
		_stop_time_acceleration()
		super.tick_physics(state,delta)
		return

	if _time_active:
		# delta 已经被 Engine.time_scale 乘过。本角色只除掉“自己请求的倍率”，
		# 因此玩家基础速度滑条仍然生效，而自己的时间场不会拖慢自身机制。
		var own_time_delta:float = delta / maxf(_current_world_factor,0.05)
		_time_elapsed += own_time_delta
		_apply_time_acceleration_heal(own_time_delta)
		var progress:float = clampf(_time_elapsed / maxf(time_acceleration_duration,0.05),0.0,1.0)
		var curved:float = pow(progress,maxf(acceleration_curve_power,0.05))
		_current_world_factor = lerpf(
			clampf(world_factor_start,0.05,1.0),
			clampf(world_factor_end,0.05,1.0),
			curved
		)
		_apply_time_override(_current_world_factor)

		# 角色自身移动速度做同倍率补偿。world.gd 本帧已经把 Buff 结算到 Speed，
		# 所以这里直接除倍率，不会吃掉其他速度 Buff/Debuff。
		Speed = Speed / maxf(_current_world_factor,0.05)

		_aging_pulse_elapsed += own_time_delta
		var pulse_interval:float = lerpf(
			maxf(aging_pulse_interval_start,0.03),
			maxf(aging_pulse_interval_end,0.03),
			curved
		)
		var emitted:int = 0
		while _aging_pulse_elapsed >= pulse_interval and emitted < maxi(max_aging_pulses_per_physics_tick,1):
			_aging_pulse_elapsed -= pulse_interval
			_apply_aging_pulse(curved,pulse_interval)
			emitted += 1

		_refresh_time_side_status()
		_update_time_visual(curved)

		if _time_elapsed >= maxf(time_acceleration_duration,0.05):
			_finish_time_acceleration()
	else:
		_cycle_left = maxf(_cycle_left - maxf(delta,0.0),0.0)
		if _cycle_left <= 0.0 and is_combat_runtime_active() and not is_player_controlled():
			_begin_time_acceleration()

	super.tick_physics(state,delta)


func controlled_attack_action() -> void:
	# 加速期内的回血、衰老脉冲和倍率仍按原逻辑运行；仅由玩家决定下一轮何时开始。
	if not is_player_controlled() or not is_multiplayer_authority() or health <= 0 or not is_combat_runtime_active():
		return
	if _time_active or _cycle_left > 0.0 or dizziness or is_damage_output_disabled():
		return
	_begin_time_acceleration()

func _begin_time_acceleration() -> void:
	if _time_active or health <= 0:
		return
	_time_active = true
	_time_elapsed = 0.0
	_aging_pulse_elapsed = 0.0
	_time_heal_accumulator = 0.0
	_current_world_factor = clampf(world_factor_start,0.05,1.0)
	_apply_time_override(_current_world_factor,true)
	_refresh_time_side_status()
	_update_time_visual(0.0)


func _finish_time_acceleration() -> void:
	if not _time_active:
		return
	_time_active = false
	_time_elapsed = 0.0
	_aging_pulse_elapsed = 0.0
	_time_heal_accumulator = 0.0
	_current_world_factor = 1.0
	_cycle_left = maxf(time_acceleration_cooldown,0.1)
	_release_time_override()
	_refresh_time_side_status()
	_update_time_visual(0.0)


func _stop_time_acceleration() -> void:
	if _time_active:
		_time_active = false
	_current_world_factor = 1.0
	_time_elapsed = 0.0
	_aging_pulse_elapsed = 0.0
	_time_heal_accumulator = 0.0
	_release_time_override()
	_update_time_visual(0.0)



func _apply_time_acceleration_heal(own_time_delta:float) -> void:
	if own_time_delta <= 0.0 or health <= 0 or health >= Max_health:
		if health >= Max_health:
			_time_heal_accumulator = 0.0
		return
	var heal_per_second:float = (
		float(Max_health)
		* maxf(time_acceleration_heal_max_health_percent_per_second,0.0)
		/ 100.0
	)
	_time_heal_accumulator += heal_per_second * own_time_delta
	var whole_heal:int = int(floor(_time_heal_accumulator))
	if whole_heal <= 0:
		return
	_time_heal_accumulator -= float(whole_heal)
	heal(float(whole_heal))

func _apply_time_override(factor:float,force_sync:bool = false) -> void:
	var safe_factor:float = clampf(factor,0.05,1.0)
	if multiplayer.has_multiplayer_peer():
		if force_sync or _last_synced_factor < 0.0 or absf(_last_synced_factor - safe_factor) >= 0.025:
			_last_synced_factor = safe_factor
			_sync_time_override.rpc(safe_factor)
	else:
		_last_synced_factor = safe_factor
		_sync_time_override(safe_factor)


func _release_time_override() -> void:
	_last_synced_factor = -1.0
	if multiplayer.has_multiplayer_peer():
		_sync_time_release.rpc()
	else:
		_sync_time_release()


@rpc("authority","call_local","unreliable")
func _sync_time_override(factor:float) -> void:
	_set_time_invincible_visual(true)
	if _time_source_key.is_empty():
		_time_source_key = "wild_dog_milk:%s" % str(get_path())
	var safe_factor:float = clampf(factor,0.05,1.0)
	Game.request_time_scale_override(_time_source_key,safe_factor,time_acceleration_tint)
	Game.request_wild_dog_time_visual(
		_time_source_key,
		safe_factor,
		clampf(world_factor_start,0.05,1.0),
		clampf(world_factor_end,0.05,1.0),
		maxf(time_visual_cycle_rate_start,0.05),
		maxf(time_visual_cycle_rate_end,time_visual_cycle_rate_start)
	)


@rpc("authority","call_local","reliable")
func _sync_time_release() -> void:
	_release_time_override_local()


func _release_time_override_local() -> void:
	_set_time_invincible_visual(false)
	if _time_source_key.is_empty():
		_time_source_key = "wild_dog_milk:%s" % str(get_path())
	Game.release_time_scale_override(_time_source_key)
	Game.release_wild_dog_time_visual(_time_source_key)



func _is_time_acceleration_invincible() -> bool:
	return _time_active and health > 0 and state_machine != null and state_machine.current_state != State.Die


# 与项目已有薇欧拉“完整无敌窗口”保持同一层级：
# Hitbox 前置、旧 can_receive_hit_from、positional/spatial、take_damage 全部拒绝。
func can_receive_hit_contact(_incoming_hit:hitbox,_contact_hurtbox:hurtbox) -> bool:
	return not _is_time_acceleration_invincible()


func can_receive_hit_from(_incoming_hit:hitbox) -> bool:
	return not _is_time_acceleration_invincible()


func receive_positional_damage(
	damage:float,
	impact_position:Vector2,
	ignore_block:bool = false,
	source:Node = null
) -> bool:
	if _is_time_acceleration_invincible():
		return false
	return super.receive_positional_damage(damage,impact_position,ignore_block,source)


func receive_spatial_damage(
	damage:float,
	damage_space:Variant,
	ignore_block:bool = false,
	raw_health:bool = false
) -> bool:
	if _is_time_acceleration_invincible():
		return false
	return super.receive_spatial_damage(damage,damage_space,ignore_block,raw_health)


func take_damage(damage:float,ignore_block:bool = false) -> void:
	if _is_time_acceleration_invincible():
		return
	super.take_damage(damage,ignore_block)


func on_actual_health_damage_received(actual_health_damage:float,health_before:float) -> void:
	# 兜底旧脚本直接写 health 的情况。公共伤害入口都已拒绝；若仍有旧代码绕过，
	# 同一 setter 回调内立刻恢复到受伤前生命，并且 Health_bar 在 INF 模式下不生成跳字。
	if _is_time_acceleration_invincible() and actual_health_damage > 0.0:
		health = maxi(int(ceil(health_before)),int(health))


func _set_time_invincible_visual(enabled:bool) -> void:
	if _time_invincible_visual_active == enabled:
		return
	_time_invincible_visual_active = enabled
	if health_bar != null and is_instance_valid(health_bar) and health_bar.has_method("set_invincible_display"):
		health_bar.call("set_invincible_display",enabled)


func _apply_aging_pulse(curved_progress:float,pulse_interval:float) -> void:
	if is_damage_output_disabled() or not is_combat_runtime_active():
		return
	# V308：aging_gain_percent_* 仍表示“每秒基础衰老率”，基础值不提高；只提高残血倍率。
	# pulse_interval 越短只让持续伤害更密；真正的大幅衰老加速只来自目标缺血比例。
	# 缺血比例经 aging_low_health_curve_power 非线性放大后，最高可达到
	# aging_low_health_max_multiplier 倍，因此满血很慢、残血非常快。
	var age_gain_per_second:float = lerpf(
		maxf(aging_gain_percent_start,0.0),
		maxf(aging_gain_percent_end,0.0),
		clampf(curved_progress,0.0,1.0)
	)
	var age_gain:float = age_gain_per_second * maxf(pulse_interval,0.0)
	var low_damage:float = maxf(attack_damage(maxf(aging_damage_multiplier,0.0)),0.0)

	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if not _is_hostile_character(target):
			continue

		var previous_age_percent:float = clampf(float(target.get_meta(AGE_META,0.0)),0.0,old_age_death_percent)
		if previous_age_percent <= 0.0001:
			target.set_meta(
				AGE_BASE_SPEED_META,
				float(target.default_properties.get("Speed",target.Speed))
			)
		var health_ratio:float = clampf(float(target.health) / float(maxi(target.Max_health,1)),0.0,1.0)
		var missing_health_ratio:float = 1.0 - health_ratio
		var low_health_factor:float = pow(
			missing_health_ratio,
			maxf(aging_low_health_curve_power,0.05)
		)
		var target_age_gain:float = age_gain * lerpf(
			1.0,
			maxf(aging_low_health_max_multiplier,1.0),
			low_health_factor
		)
		var age_percent:float = clampf(
			previous_age_percent + target_age_gain,
			0.0,
			old_age_death_percent
		)
		target.set_meta(AGE_META,age_percent)
		_apply_aging_stat_penalty(target,age_percent)
		_update_target_age_status(target,age_percent)
		_sync_target_age_visual_state(target,age_percent)

		# V305：100% 衰老必须由“老死”处决完成。
		# 之前每个 pulse 的低额 raw health damage 仍保留，但在 100% 之前最多把目标压到 1 HP，
		# 避免目标在骷髅完整显现前被普通时间伤害抢先击杀。
		if target.health > 1 and low_damage > 0.0 and age_percent < old_age_death_percent:
			var nonlethal_damage:float = minf(low_damage,maxf(float(target.health) - 1.0,0.0))
			if nonlethal_damage > 0.0:
				target.receive_spatial_raw_health_damage(
					nonlethal_damage,
					{"shape":"all","source":self}
				)

		if age_percent >= old_age_death_percent and target.health > 0:
			# V305：100% 衰老阈值由这一发处决统一标记为老死。
			# 100% 之前的低额时间伤害已经限制为非致死，因此骷髅可以完整走到 100% 再消失。
			# 标记同时保存致死前生命与一个很短的真实时间窗口，避免复活角色之后被别的伤害击杀时误判成旧的老死。
			target.set_meta(OLD_AGE_DEATH_DEADLINE_META,Time.get_ticks_msec() + 750)
			target.set_meta(OLD_AGE_DEATH_HEALTH_META,float(target.health))
			_clear_target_age_visual_state(target)
			target.receive_spatial_raw_health_damage(
				float(target.health) + 1.0,
				{"shape":"all","source":self}
			)


func _sync_target_age_visual_state(target:ball,age_percent:float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var target_path:NodePath = target.get_path()
	if multiplayer.has_multiplayer_peer():
		_sync_aging_skull_visual.rpc(target_path,age_percent)
	else:
		_sync_aging_skull_visual(target_path,age_percent)


func _clear_target_age_visual_state(target:ball) -> void:
	if target == null or not is_instance_valid(target):
		return
	var target_path:NodePath = target.get_path()
	if multiplayer.has_multiplayer_peer():
		_clear_aging_skull_visual.rpc(target_path)
	else:
		_clear_aging_skull_visual(target_path)


@rpc("authority","call_local","unreliable")
func _sync_aging_skull_visual(target_path:NodePath,age_percent:float) -> void:
	var target_node:Node = get_node_or_null(target_path)
	if target_node == null or not target_node is ball:
		return
	var target:ball = target_node as ball
	if target.health <= 0:
		_remove_aging_skull_visual_local(target)
		return

	var effect:Node = target.get_node_or_null(NodePath(str(AGE_VISUAL_NODE_NAME)))
	if effect == null or not is_instance_valid(effect):
		effect = AGE_VISUAL_SCRIPT.new()
		effect.name = str(AGE_VISUAL_NODE_NAME)
		target.add_child(effect)
		if effect.has_method("setup"):
			effect.call(
				"setup",
				target,
				aging_skull_world_size,
				aging_skull_shake_start_opacity,
				aging_skull_shake_max_offset,
				aging_skull_shake_rotation_deg
			)
	if effect != null and is_instance_valid(effect) and effect.has_method("set_age_percent"):
		effect.call("set_age_percent",age_percent,old_age_death_percent)


@rpc("authority","call_local","reliable")
func _clear_aging_skull_visual(target_path:NodePath) -> void:
	var target_node:Node = get_node_or_null(target_path)
	if target_node == null or not target_node is ball:
		return
	_remove_aging_skull_visual_local(target_node as ball)


func _remove_aging_skull_visual_local(target:ball) -> void:
	if target == null or not is_instance_valid(target):
		return
	var effect:Node = target.get_node_or_null(NodePath(str(AGE_VISUAL_NODE_NAME)))
	if effect != null and is_instance_valid(effect):
		if effect is CanvasItem:
			(effect as CanvasItem).visible = false
		effect.queue_free()


func _apply_aging_stat_penalty(target:ball,age_percent:float) -> void:
	var world:Node = get_tree().current_scene
	if world == null or not world.has_method("new_buff"):
		return
	var ratio:float = clampf(age_percent / maxf(old_age_death_percent,1.0),0.0,1.0)
	var stat_multiplier:float = lerpf(1.0,clampf(aging_min_stat_multiplier,0.05,1.0),ratio)
	var cooldown_multiplier:float = 1.0 / maxf(stat_multiplier,0.05)

	world.call("new_buff",target,AGE_BUFF_SOURCE_ID,"野生狗奶_衰老_伤害",
		Buff.new(2,INF,Buff.Buff_types.Damage,stat_multiplier,Buff.Algorithms.mul),"cover")

	# V304：速度衰老改为直接削弱 default_properties["Speed"] 的基础速度，
	# 不再叠一层 Speed Buff，避免“基础速度没变、只是临时倍率变化”。
	if target.Buff_Dic.has(AGE_BUFF_SOURCE_ID):
		var source_buffs:Dictionary = target.Buff_Dic[AGE_BUFF_SOURCE_ID]
		source_buffs.erase("野生狗奶_衰老_速度")
	var base_speed:float = float(target.get_meta(
		AGE_BASE_SPEED_META,
		target.default_properties.get("Speed",target.Speed)
	))
	var aged_base_speed:float = maxf(base_speed * stat_multiplier,0.0)
	var previous_default_speed:float = float(target.default_properties.get("Speed",target.Speed))
	target.default_properties["Speed"] = aged_base_speed
	# 同一帧按“新基础 / 旧基础”修正当前 Speed，保留其它 Speed Buff 已经结算出的倍率。
	if previous_default_speed > 0.0001:
		target.Speed *= aged_base_speed / previous_default_speed
	else:
		target.Speed = aged_base_speed

	world.call("new_buff",target,AGE_BUFF_SOURCE_ID,"野生狗奶_衰老_攻击冷却",
		Buff.new(2,INF,Buff.Buff_types.Attack_Cooling,cooldown_multiplier,Buff.Algorithms.mul),"cover")
	world.call("new_buff",target,AGE_BUFF_SOURCE_ID,"野生狗奶_衰老_技能冷却",
		Buff.new(2,INF,Buff.Buff_types.Skill_Cooling,cooldown_multiplier,Buff.Algorithms.mul),"cover")


func _update_target_age_status(target:ball,_age_percent:float) -> void:
	# V280：衰老仍正常累计/生效，但删除目标旁的“衰老 N%”文字。
	if target == null or not is_instance_valid(target):
		return
	target.side_status_remove_permanent("right",AGE_STATUS_KEY)


func _is_hostile_character(target:ball) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(self,target): return false # 皓宸复制品及其产物不把己方选为目标
	if target == null or not is_instance_valid(target) or target == self:
		return false
	if target.Type != Ball_Type.Ball or target.health <= 0:
		return false
	if target.has_method("is_combat_targetable") and not bool(target.call("is_combat_targetable")):
		return false
	# “敌人”不受全局友伤设置影响：真实同队永远不衰老。
	if Team != "" and target.Team != "" and target.Team == Team:
		return false
	return true


func _refresh_time_side_status() -> void:
	# V280：删除野生狗奶自身“时间 x倍 / 时间蓄积”文字，只保留实际时间机制与视觉。
	side_status_remove_permanent("left","wild_dog_milk_time")


func _update_time_visual(curved_progress:float) -> void:
	if image == null or not is_instance_valid(image):
		return
	if _time_active:
		var pulse:float = sin(_time_elapsed * 8.0) * 0.018
		image.scale = _visual_base_scale * (1.0 + pulse + curved_progress * 0.04)
		if image is CanvasItem:
			(image as CanvasItem).self_modulate = Color(1.0,1.0 - curved_progress * 0.12,1.0 - curved_progress * 0.28,1.0)
	else:
		image.scale = _visual_base_scale
		if image is CanvasItem:
			(image as CanvasItem).self_modulate = Color.WHITE
