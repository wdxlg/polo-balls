extends ball

const LOCAL_SFX = preload("res://scripts/audio/local_positional_sfx.gd")
const PUNCH_SWING_SFX:AudioStream = preload("res://audio/characters/拳击手/拳击手_挥拳.mp3")
const PUNCH_HIT_SFX:AudioStream = preload("res://audio/characters/拳击手/拳击手_命中.mp3")

const BOXER_SFX_SWING:int = 0
const BOXER_SFX_HIT:int = 1

# ============================================================
# 拳击手
# - 身体只负责实体碰撞/反弹，不再产生碰撞伤害。
# - 每次真正撞到敌人时触发一次近战拳击：只结算拳头伤害，不产生击退。
#   同时额外生成一张“拳头.png”从拳击手位置向目标伸长，再缩回并阶梯淡出。
# - 每次拳击都是独立视觉实例，因此连续出拳时可以同时看到多个拳头。
# - 技能：敌人超过两倍拳程时才使用；锁定起手方向并冲固定距离，不因接近目标提前停。
# ============================================================

@export_category("拳击手 - 外观")
@export var normal_texture:Texture2D
@export var attack_texture:Texture2D
@export_range(0.05,1.0,0.01) var punch_visual_duration:float = 0.18

@export_category("拳击手 - 拳头特效")
@export var fist_texture:Texture2D
@export_range(8.0,80.0,1.0) var fist_visual_height:float = 25.0
@export_range(6.0,60.0,1.0) var fist_rest_length:float = 15.0
@export_range(16.0,120.0,1.0) var fist_max_length:float = 45.0
@export_range(0.02,0.5,0.01) var fist_extend_time:float = 0.07
@export_range(0.02,0.5,0.01) var fist_retract_time:float = 0.06
@export_range(1,8,1) var fist_fade_steps:int = 3
@export_range(0.01,0.2,0.005) var fist_fade_step_time:float = 0.022
@export_range(-50,100,1) var fist_z_index:int = 32
@export_range(0.0,18.0,0.5) var fist_position_jitter:float = 7.0
@export_range(4.0,60.0,1.0) var fist_hit_half_width:float = 20.0
@export_range(0.0,20.0,0.5) var fist_hit_back_margin:float = 7.0
# V84：AI 不再等身体撞上目标才出拳；目标 Hurtbox 一进入拳头实际可达走廊就起手。
@export_range(0.6,1.5,0.05) var ai_punch_trigger_reach_multiplier:float = 1.0

@export_category("拳击手 - 近战拳击")
# 身体没有碰撞伤害；真正的伤害全部来自这里的拳头。
# 这次整体降伤：每拳默认只造成 Damage 的 0.50 倍。
@export_range(0.0,5.0,0.05) var extra_punch_damage_multiplier:float = 0.50
# 兼容旧场景保留这两个导出项，但拳头逻辑已硬禁用击退。
@export_range(0.0,300.0,5.0) var extra_punch_knockback_distance:float = 0.0
@export_range(50.0,1800.0,10.0) var extra_punch_knockback_speed:float = 520.0
@export_range(0.0,0.5,0.01) var punch_same_target_guard:float = 0.28

@export_category("拳击手 - Combo")
# 第一次攻击 1 拳；在窗口内再次进行“基础攻击”时，下次依次变为 2/3/4 拳。
# Combo 自动追加出来的拳头不会再次增加层数。
@export_range(0.3,4.0,0.05) var combo_window:float = 1.75
@export_range(1,4,1) var combo_max_punches:int = 4
@export_range(0.02,0.30,0.01) var combo_extra_punch_interval:float = 0.07
# 连击后续拳允许略微追上实体碰撞后被弹开的目标；不是跨屏锁定，只补偿角色反弹距离。
@export_range(1.0,2.0,0.05) var combo_extra_reach_multiplier:float = 1.35
@export_range(1.0,1.6,0.05) var combo_extra_width_multiplier:float = 1.15
# 兼容旧 Inspector；Combo 额外拳同样不会击退。
@export_range(0.0,1.0,0.05) var combo_extra_knockback_multiplier:float = 0.0

@export_category("拳击手 - 冲刺技能")
# V85：AI 只有在敌人中心距离超过“当前拳头攻击范围 × 该倍率”时才允许突刺。
# 默认 2.0，即拳头实际攻击长度约 45px 时，敌人超过约 90px 才会使用。
@export_range(1.0,5.0,0.1) var dash_trigger_attack_range_multiplier:float = 2.0
# 兼容旧场景保留这两个导出项；V85 AI 触发不再使用固定 55~120 距离带。
@export_range(0.0,600.0,1.0) var dash_trigger_min_distance:float = 55.0
@export_range(0.0,600.0,1.0) var dash_trigger_max_distance:float = 120.0
# V86：突刺距离改为“当前拳头攻击距离 × 1.2”。
# dash_distance 只为旧场景 Inspector 兼容保留，不再决定实际突刺长度。
@export_range(20.0,800.0,5.0) var dash_distance:float = 360.0
@export_range(0.2,3.0,0.05) var dash_distance_attack_range_multiplier:float = 1.2
@export_range(50.0,2500.0,10.0) var dash_speed:float = 920.0
# V84：突刺由瞬间满速改为加速/刹车曲线，减少起步和收尾的生硬跳变。
@export_range(200.0,20000.0,100.0) var dash_acceleration:float = 9000.0
@export_range(200.0,20000.0,100.0) var dash_deceleration:float = 7600.0
@export_range(1.0,40.0,1.0) var dash_finish_epsilon:float = 6.0

const VISUAL_NORMAL:int = 0
const VISUAL_ATTACK:int = 1

var _dash_active:bool = false
var _dash_direction:Vector2 = Vector2.RIGHT
var _dash_remaining:float = 0.0
var _dash_current_speed:float = 0.0
var _dash_added_collision_exceptions:Array[PhysicsBody2D] = []
var _next_ai_punch_msec:int = 0
var _last_punch_msec_by_target:Dictionary = {}
var _last_base_attack_msec:int = -1000000
var _next_combo_punch_count:int = 1
var _visual_token:int = 0
var _default_texture:Texture2D = null
# 给极速者/其它高级 AI 读取的短时拳路。每一拳只记录到命中判定后的极短时间，
# 不参与真实碰撞，也不会改变拳击手自己的攻击逻辑。
var _active_ai_punch_threats:Array[Dictionary] = []


func _ready() -> void:
	# 必须在 super._ready() 前关闭，否则基类会把身体 Hitbox 设置成自动监听。
	Has_Collision_Damage = false
	super._ready()
	_auto_load_textures()
	if image is Sprite2D:
		_default_texture = (image as Sprite2D).texture
	_set_visual_state_local(VISUAL_NORMAL)
func has_collision_damage() -> bool:
	# 硬规则：拳击手身体永远没有自然碰撞伤害。
	return false


func _auto_load_textures() -> void:
	if normal_texture == null:
		normal_texture = _try_load_texture("res://Images/characters/人物/拳击手/拳击手_正常.png")
	if attack_texture == null:
		attack_texture = _try_load_texture("res://Images/characters/人物/拳击手/拳击手_攻击.png")
	if fist_texture == null:
		fist_texture = _try_load_texture("res://Images/characters/人物/拳击手/拳头.png")


func _try_load_texture(path:String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var resource:Resource = ResourceLoader.load(path)
	return resource as Texture2D if resource is Texture2D else null


func _ai_punch_reach() -> float:
	return maxf(fist_max_length,maxf(fist_rest_length,8.0)) * maxf(ai_punch_trigger_reach_multiplier,0.6)


func _dash_trigger_distance() -> float:
	return _ai_punch_reach() * maxf(dash_trigger_attack_range_multiplier,1.0)


func _dash_travel_distance() -> float:
	# 当前默认拳程 45px，因此默认突刺严格为 45 * 1.2 = 54px。
	return _ai_punch_reach() * maxf(dash_distance_attack_range_multiplier,0.2)


func _dash_finish_threshold() -> float:
	# 原 6px epsilon 对 54px 短突刺占比过大；保留 Inspector 字段但实际最多提前 1px 收尾。
	return minf(maxf(dash_finish_epsilon,0.25),1.0)


func _dash_target_is_in_trigger_band() -> bool:
	var target:Node = return_reusable_combat_target()
	if not (target is Node2D) or not is_instance_valid(target):
		return false
	var target_distance:float = global_position.distance_to(combat_target_position(target))
	# V85：没有额外“最大触发距离”；只要敌人超过两倍拳程，就允许用突刺接近。
	return target_distance > _dash_trigger_distance()


func get_next_state(state:State) -> int:
	# Skill 冷却好了但敌人没有超过“两倍拳头攻击范围”时，不让状态机进入 Skill。
	# V85 不再使用固定 55～120 距离带，也没有因为敌人太远而禁止突刺的上限。
	# 临时把冷却读数压到阈值下调用基类，再恢复原值，因此不会白白消耗一次冲刺冷却；
	# 敌人超过动态两倍拳程阈值的下一帧即可正常触发冲刺。
	if (
		is_multiplayer_authority()
		and Can_Skill
		and not Using_Skill
		and state_machine != null
		and float(state_machine.last_state_dis.get("Skill",0.0)) >= Skill_Cooling
		and not _dash_target_is_in_trigger_band()
	):
		var saved_skill_distance:float = float(state_machine.last_state_dis.get("Skill",0.0))
		state_machine.last_state_dis["Skill"] = maxf(Skill_Cooling - 0.001,0.0)
		var next_state:int = super.get_next_state(state)
		state_machine.last_state_dis["Skill"] = saved_skill_distance
		return next_state
	return super.get_next_state(state)


func Attack() -> void:
	# AI 拳击手基础攻击由物理帧的拳路范围检测触发；直接控制时左键必须是真正的手动出拳。
	if not has_player_control_aim():
		super()
		Attacking = false
		return
	if state_machine.current_state == State.Die or not is_multiplayer_authority() or is_damage_output_disabled():
		Attacking = false
		return

	var attack_dir:Vector2 = player_control_aim_direction(direction)
	Attacking = true
	var now_msec:int = Time.get_ticks_msec()
	var punch_count:int = _consume_combo_punch_count(now_msec)
	_perform_manual_direction_punch(attack_dir,false)
	for extra_index:int in range(1,punch_count):
		var delay:float = maxf(combo_extra_punch_interval,0.02) * float(extra_index)
		var timer:SceneTreeTimer = get_tree().create_timer(delay,false,true)
		timer.timeout.connect(_perform_manual_direction_punch.bind(attack_dir,true),CONNECT_ONE_SHOT)

	var finish_delay:float = maxf(fist_extend_time + fist_retract_time,0.08) + maxf(combo_extra_punch_interval,0.02) * float(maxi(punch_count - 1,0))
	await get_tree().create_timer(finish_delay,false,true).timeout
	if is_instance_valid(self):
		Attacking = false


func _perform_manual_direction_punch(attack_dir:Vector2,is_combo_extra:bool) -> void:
	if not is_inside_tree() or health <= 0 or state_machine.current_state == State.Die or is_damage_output_disabled():
		return
	if attack_dir.length_squared() <= 0.000001:
		attack_dir = player_control_aim_direction(direction)
	attack_dir = attack_dir.normalized()
	_show_punch_visual()
	var hit_origin:Vector2 = global_position
	var side:Vector2 = Vector2(-attack_dir.y,attack_dir.x)
	var side_offset:float = randf_range(-maxf(fist_position_jitter,0.0),maxf(fist_position_jitter,0.0))
	var forward_offset:float = randf_range(-maxf(fist_position_jitter,0.0) * 0.25,maxf(fist_position_jitter,0.0) * 0.25)
	_broadcast_fist_visual(hit_origin + side * side_offset + attack_dir * forward_offset,attack_dir)
	_play_boxer_sfx_everywhere(BOXER_SFX_SWING,hit_origin,0.0,randf_range(0.97,1.04))
	var hit_delay:float = maxf(fist_extend_time * 0.88,0.02)
	_register_ai_punch_threat(hit_origin,attack_dir,hit_delay,is_combo_extra)
	var timer:SceneTreeTimer = get_tree().create_timer(hit_delay,false,true)
	timer.timeout.connect(_resolve_manual_direction_punch.bind(hit_origin,attack_dir,is_combo_extra),CONNECT_ONE_SHOT)


func _resolve_manual_direction_punch(hit_origin:Vector2,attack_dir:Vector2,is_combo_extra:bool) -> void:
	if not is_inside_tree() or health <= 0 or state_machine.current_state == State.Die:
		return
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if not _is_valid_enemy(target):
			continue
		_resolve_fixed_range_punch(target.get_instance_id(),hit_origin,attack_dir,is_combo_extra)


func Skill() -> void:
	if state_machine.current_state == State.Die or not is_multiplayer_authority():
		return
	if is_damage_output_disabled():
		Using_Skill = false
		return

	var target:Node = return_reusable_combat_target()
	var to_target:Vector2 = Vector2.ZERO
	if has_player_control_aim():
		to_target = player_control_aim_world_position(global_position) - global_position
	elif target is Node2D and is_instance_valid(target):
		to_target = combat_target_position(target) - global_position
	if not has_player_control_aim():
		var target_distance:float = to_target.length()
		if target_distance <= _dash_trigger_distance():
			Using_Skill = false
			return

	if to_target.length_squared() > 0.000001:
		_dash_direction = to_target.normalized()
	elif direction.length_squared() > 0.000001:
		_dash_direction = direction.normalized()
	else:
		_dash_direction = Vector2.RIGHT

	Using_Skill = true
	_dash_active = true
	_dash_remaining = maxf(_dash_travel_distance(),0.0)
	_dash_current_speed = 0.0
	_begin_dash_ball_collision_exceptions()
	direction = _dash_direction
	_visual_token += 1
	_broadcast_visual_state(VISUAL_ATTACK)
	_reset_after_image_sampling()
	_play_local_sfx_everywhere("throw",global_position,-10.0,1.12,520.0)


func tick_physics(state:State,delta:float) -> void:
	if _dash_active and is_multiplayer_authority():
		if dizziness or health <= 0 or _dash_remaining <= _dash_finish_threshold():
			_finish_dash()
			super.tick_physics(state,delta)
			return

		var safe_delta:float = maxf(delta,0.000001)
		var safe_accel:float = maxf(dash_acceleration,1.0)
		var safe_decel:float = maxf(dash_deceleration,1.0)
		# 剩余距离不足以维持满速时提前刹车；速度连续变化，突刺起步/收尾不再瞬切。
		var braking_speed:float = sqrt(maxf(2.0 * safe_decel * maxf(_dash_remaining,0.0),0.0))
		var wanted_speed:float = minf(maxf(dash_speed,0.0),braking_speed)
		var change_rate:float = safe_accel if wanted_speed > _dash_current_speed else safe_decel
		_dash_current_speed = move_toward(_dash_current_speed,wanted_speed,change_rate * safe_delta)
		if _dash_current_speed <= 0.5 and _dash_remaining <= _dash_finish_threshold() * 2.0:
			_finish_dash()
			return

		direction = _dash_direction
		var before:Vector2 = global_position
		# 公共 move() 对 Ball 会再乘 0.60；这里反向补偿，使 dash_speed 表示真正的世界速度。
		# 同时暂时关闭人群分离横向速度，并锁定玩家控制方向，避免突刺过程左右摆动/发涩。
		var saved_crowd_velocity:Vector2 = _crowd_separation_velocity
		var saved_player_direction:Vector2 = player_control_direction
		_crowd_separation_velocity = Vector2.ZERO
		if is_player_controlled():
			player_control_direction = _dash_direction
		var move_input_speed:float = _dash_current_speed / maxf(CHARACTER_BASE_MOVE_SPEED_MULTIPLIER,0.001)
		move(move_input_speed,delta)
		_crowd_separation_velocity = saved_crowd_velocity
		if is_player_controlled():
			player_control_direction = saved_player_direction

		var moved:float = before.distance_to(global_position)
		_dash_remaining = maxf(_dash_remaining - moved,0.0)
		_process_auto_after_image(delta)
		Repel = Vector2.ZERO

		if moved <= 0.05 and _dash_current_speed > 1.0:
			_finish_dash()
			return
		if _dash_remaining <= _dash_finish_threshold():
			_finish_dash()
		return

	# 普通 AI 移动阶段同样实时检测拳头攻击范围。
	if is_multiplayer_authority():
		_try_ai_range_punch()
	super.tick_physics(state,delta)


func when_collide(speed:float,collision:KinematicCollision2D) -> void:
	var collider = collision.get_collider() if collision != null else null
	# 普通移动时，身体碰撞仍只是范围检测遗漏时的兜底。
	# 突刺期间不靠“撞到敌人”触发拳击，避免技能再次退化成突刺到脸上就停。
	if not _dash_active and is_multiplayer_authority() and collider is ball and not has_player_control_aim():
		var target:ball = collider as ball
		_try_start_ai_punch(target,false)

	var was_dashing:bool = _dash_active
	super.when_collide(speed,collision)
	# V85 突刺期间 Ball 已加入临时碰撞例外；这里实际遇到的通常是墙/地形。
	# 墙体仍可阻断技能，避免穿出地图；敌人本身不再决定突刺长度。
	if was_dashing and _dash_active and not (collider is ball):
		_finish_dash()


func _try_ai_range_punch() -> bool:
	if has_player_control_aim() or not is_multiplayer_authority():
		return false
	if health <= 0 or dizziness or is_damage_output_disabled() or not is_combat_runtime_active():
		return false
	var raw_target:Node = return_reusable_combat_target()
	if not (raw_target is ball):
		return false
	var target:ball = raw_target as ball
	if not _is_valid_enemy(target):
		return false

	var attack_dir:Vector2 = combat_target_position(target) - global_position
	if attack_dir.length_squared() <= 0.000001:
		return false
	var reach:float = _ai_punch_reach()
	var width:float = maxf(fist_hit_half_width,4.0)
	if not _punch_corridor_overlaps_target(target,global_position,attack_dir,reach,width):
		return false
	return _try_start_ai_punch(target,true)


func _try_start_ai_punch(target:ball,require_range:bool = true) -> bool:
	if has_player_control_aim() or not is_multiplayer_authority():
		return false
	if not _is_valid_enemy(target):
		return false
	if health <= 0 or dizziness or is_damage_output_disabled() or not is_combat_runtime_active():
		return false

	if require_range:
		var attack_dir:Vector2 = combat_target_position(target) - global_position
		if attack_dir.length_squared() <= 0.000001:
			return false
		var reach:float = _ai_punch_reach()
		if not _punch_corridor_overlaps_target(target,global_position,attack_dir,reach,maxf(fist_hit_half_width,4.0)):
			return false

	var now_msec:int = Time.get_ticks_msec()
	if now_msec < _next_ai_punch_msec:
		return false
	_next_ai_punch_msec = now_msec + int(round(maxf(Attack_Cooling,0.05) * 1000.0))
	_extra_punch(target)
	return true


func _extra_punch(target:ball) -> void:
	# 这里代表一次“真正的基础攻击”。只有这里会推进 Combo。
	# 后面定时追加的第 2/3/4 拳只调用 _perform_single_punch()，不会反过来叠 Combo。
	var now_msec:int = Time.get_ticks_msec()
	var target_id:int = target.get_instance_id()
	var guard_msec:int = int(round(maxf(punch_same_target_guard,0.0) * 1000.0))
	if _last_punch_msec_by_target.has(target_id):
		if now_msec - int(_last_punch_msec_by_target[target_id]) < guard_msec:
			return
	_last_punch_msec_by_target[target_id] = now_msec

	var punch_count:int = _consume_combo_punch_count(now_msec)
	_perform_single_punch(target,false)

	# Combo 的额外拳头分开排程，形成连续出拳，而不是同一帧把 4 次伤害一起结算。
	for extra_index in range(1,punch_count):
		var delay:float = maxf(combo_extra_punch_interval,0.02) * float(extra_index)
		var timer:SceneTreeTimer = get_tree().create_timer(delay,false,true)
		timer.timeout.connect(_on_combo_extra_punch_timeout.bind(target_id),CONNECT_ONE_SHOT)


func _consume_combo_punch_count(now_msec:int) -> int:
	var combo_window_msec:int = int(round(maxf(combo_window,0.0) * 1000.0))
	if now_msec - _last_base_attack_msec > combo_window_msec:
		_next_combo_punch_count = 1

	var max_punches:int = clampi(combo_max_punches,1,4)
	var current_count:int = clampi(_next_combo_punch_count,1,max_punches)
	_next_combo_punch_count = mini(current_count + 1,max_punches)
	_last_base_attack_msec = now_msec
	return current_count


func _on_combo_extra_punch_timeout(target_id:int) -> void:
	if not is_inside_tree() or health <= 0 or state_machine.current_state == State.Die:
		return
	if not is_instance_id_valid(target_id):
		return
	var object:Object = instance_from_id(target_id)
	if not (object is ball):
		return
	var target:ball = object as ball
	if not _is_valid_enemy(target):
		return
	_perform_single_punch(target,true)


func _perform_single_punch(target:ball,is_combo_extra:bool) -> void:
	if not _is_valid_enemy(target):
		return

	_show_punch_visual()

	# 每拳先锁定“这一拳”的方向，拳头最大长度固定为较短的 fist_max_length。
	# Combo 后续拳不会因为目标被上一拳打远，就把手臂无限拉长追过去。
	var attack_dir:Vector2 = target.global_position - global_position
	if attack_dir.length_squared() <= 0.000001:
		attack_dir = direction.normalized() if direction.length_squared() > 0.000001 else Vector2.RIGHT
	else:
		attack_dir = attack_dir.normalized()

	# 真实命中判定始终从角色中心出拳。视觉可以抖动，但视觉随机偏移不能再影响命中。
	var hit_origin:Vector2 = global_position

	# 连续拳的图片仍从身体附近略微不同的位置打出，避免所有拳头完全叠在同一点。
	var side:Vector2 = Vector2(-attack_dir.y,attack_dir.x)
	var side_offset:float = randf_range(-maxf(fist_position_jitter,0.0),maxf(fist_position_jitter,0.0))
	var forward_offset:float = randf_range(-maxf(fist_position_jitter,0.0) * 0.25,maxf(fist_position_jitter,0.0) * 0.25)
	var visual_origin:Vector2 = hit_origin + side * side_offset + attack_dir * forward_offset

	_broadcast_fist_visual(visual_origin,attack_dir)
	_play_boxer_sfx_everywhere(BOXER_SFX_SWING,visual_origin,0.0,randf_range(0.97,1.04))

	# 伤害在拳头接近伸到最远处时结算。真实判定使用一块有宽度的拳路去查询 Hurtbox，
	# 而不是只拿目标中心点比较距离，避免角色碰撞框较大时“拳头碰到了边缘但中心超距”。
	var target_id:int = target.get_instance_id()
	var hit_delay:float = maxf(fist_extend_time * 0.88,0.02)
	_register_ai_punch_threat(hit_origin,attack_dir,hit_delay,is_combo_extra)
	var timer:SceneTreeTimer = get_tree().create_timer(hit_delay,false,true)
	timer.timeout.connect(_resolve_fixed_range_punch.bind(target_id,hit_origin,attack_dir,is_combo_extra),CONNECT_ONE_SHOT)


func _resolve_fixed_range_punch(target_id:int,fist_origin:Vector2,attack_dir:Vector2,is_combo_extra:bool) -> void:
	if not is_inside_tree() or health <= 0 or state_machine.current_state == State.Die:
		return
	if not is_instance_id_valid(target_id):
		return
	var object:Object = instance_from_id(target_id)
	if not (object is ball):
		return
	var target:ball = object as ball
	if not _is_valid_enemy(target):
		return

	# 用实际的矩形拳路和目标 Hurtbox 做空间查询。
	# Combo 后续拳给一点额外长度/宽度，只补偿实体碰撞反弹造成的短距离分离。
	var fixed_reach:float = maxf(fist_max_length,maxf(fist_rest_length,8.0))
	var hit_half_width:float = maxf(fist_hit_half_width,4.0)
	if is_combo_extra:
		fixed_reach *= maxf(combo_extra_reach_multiplier,1.0)
		hit_half_width *= maxf(combo_extra_width_multiplier,1.0)

	if not _punch_corridor_overlaps_target(target,fist_origin,attack_dir,fixed_reach,hit_half_width):
		return

	var hit_volume:float = -1.5 if is_combo_extra else 0.5
	_play_boxer_sfx_everywhere(BOXER_SFX_HIT,target.global_position,hit_volume,randf_range(0.97,1.035))

	var punch_damage:float = attack_damage(extra_punch_damage_multiplier)
	if punch_damage > 0.0:
		var punch_dir:Vector2 = attack_dir.normalized() if attack_dir.length_squared() > 0.000001 else Vector2.RIGHT
		var punch_start:Vector2 = fist_origin - punch_dir * maxf(fist_hit_back_margin,0.0)
		var punch_end:Vector2 = fist_origin + punch_dir * fixed_reach
		target.receive_spatial_damage(
			punch_damage,
			{
				"shape":"capsule",
				"from":punch_start,
				"to":punch_end,
				"half_width":hit_half_width,
				"source":self,
				"blocked_by_body":true,
				"source_position":fist_origin,
			},
			false
		)

	# 拳击手的拳头只造成伤害，不对目标施加任何击退/Repel。


func _punch_corridor_overlaps_target(target:ball,origin:Vector2,attack_dir:Vector2,reach:float,half_width:float) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if attack_dir.length_squared() <= 0.000001:
		return false

	var dir:Vector2 = attack_dir.normalized()
	var back_margin:float = maxf(fist_hit_back_margin,0.0)
	var safe_reach:float = maxf(reach,1.0)
	var safe_half_width:float = maxf(half_width,1.0)

	# 优先使用物理空间里的真实 Hurtbox。这样大体型目标只要边缘进入拳路就算命中，
	# 不再要求“目标中心点”必须落进 45px 的拳长内。
	if target.self_hurtbox != null and is_instance_valid(target.self_hurtbox):
		var world_2d:World2D = get_world_2d()
		if world_2d != null:
			var rect := RectangleShape2D.new()
			var total_length:float = safe_reach + back_margin
			rect.size = Vector2(total_length,safe_half_width * 2.0)

			var params := PhysicsShapeQueryParameters2D.new()
			params.shape = rect
			params.transform = Transform2D(dir.angle(),origin + dir * ((safe_reach - back_margin) * 0.5))
			params.collide_with_areas = true
			params.collide_with_bodies = false
			params.margin = 1.5
			var hurt_layer:int = target.self_hurtbox.collision_layer
			params.collision_mask = hurt_layer if hurt_layer != 0 else 0x7fffffff

			var results:Array[Dictionary] = world_2d.direct_space_state.intersect_shape(params,32)
			for result in results:
				var collider:Object = result.get("collider",null)
				if collider == target.self_hurtbox:
					return true

	# 极端情况下 Hurtbox 尚未进入物理空间时保留中心点兜底，避免刚生成角色首拳失效。
	var to_target:Vector2 = target.global_position - origin
	var forward_distance:float = to_target.dot(dir)
	var lateral_distance:float = absf(to_target.cross(dir))
	return (
		forward_distance >= -back_margin
		and forward_distance <= safe_reach
		and lateral_distance <= safe_half_width
	)


func _register_ai_punch_threat(origin:Vector2,attack_dir:Vector2,hit_delay:float,is_combo_extra:bool = false) -> void:
	if attack_dir.length_squared() <= 0.000001:
		return
	var now_msec:int = Time.get_ticks_msec()
	var hit_msec:int = now_msec + int(round(maxf(hit_delay,0.0) * 1000.0))
	var threat_reach:float = maxf(fist_max_length,maxf(fist_rest_length,8.0))
	var threat_half_width:float = maxf(fist_hit_half_width,4.0)
	if is_combo_extra:
		threat_reach *= maxf(combo_extra_reach_multiplier,1.0)
		threat_half_width *= maxf(combo_extra_width_multiplier,1.0)
	_active_ai_punch_threats.append({
		"origin":origin,
		"direction":attack_dir.normalized(),
		"reach":threat_reach,
		"half_width":threat_half_width,
		"hit_msec":hit_msec,
		"expire_msec":hit_msec + 90,
	})
	_cleanup_ai_punch_threats(now_msec)


func _cleanup_ai_punch_threats(now_msec:int = -1) -> void:
	if now_msec < 0:
		now_msec = Time.get_ticks_msec()
	for index in range(_active_ai_punch_threats.size() - 1,-1,-1):
		var info:Dictionary = _active_ai_punch_threats[index]
		if int(info.get("expire_msec",0)) < now_msec:
			_active_ai_punch_threats.remove_at(index)


# 高级 AI 可选接口：返回真正即将命中的拳路，而不是只告诉 AI “拳击手正在攻击”。
# 这样极速者会躲固定长度的拳头，但不会因为拳击手在附近就无脑开极速。
func get_ai_attack_threats(receiver:ball) -> Array:
	var result:Array = []
	if receiver == null or not is_instance_valid(receiver) or not _is_valid_enemy(receiver):
		return result
	var now_msec:int = Time.get_ticks_msec()
	_cleanup_ai_punch_threats(now_msec)
	for raw_info in _active_ai_punch_threats:
		if not raw_info is Dictionary:
			continue
		var info:Dictionary = raw_info
		var origin:Vector2 = info.get("origin",global_position)
		var attack_dir:Vector2 = info.get("direction",Vector2.RIGHT)
		if attack_dir.length_squared() <= 0.000001:
			continue
		attack_dir = attack_dir.normalized()
		var reach:float = maxf(float(info.get("reach",fist_max_length)),8.0)
		var hit_msec:int = int(info.get("hit_msec",now_msec))
		result.append({
			"shape":"segment",
			"start":origin - attack_dir * maxf(fist_hit_back_margin,0.0),
			"end":origin + attack_dir * reach,
			"radius":maxf(float(info.get("half_width",fist_hit_half_width)),4.0),
			"danger_in":maxf(float(hit_msec - now_msec) / 1000.0,0.0),
			"danger_duration":0.10,
			"kind":"boxer_fist",
			"damage":attack_damage(extra_punch_damage_multiplier),
			"source":self,
		})
	return result


func _broadcast_fist_visual(start_position:Vector2,attack_dir:Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_spawn_fist_visual.rpc(start_position,attack_dir)
	else:
		_rpc_spawn_fist_visual(start_position,attack_dir)


@rpc("authority","call_local","unreliable")
func _rpc_spawn_fist_visual(start_position:Vector2,attack_dir:Vector2) -> void:
	_spawn_fist_visual_local(start_position,attack_dir)


func _spawn_fist_visual_local(start_position:Vector2,attack_dir:Vector2) -> void:
	if fist_texture == null or not is_inside_tree():
		return
	var scene_root:Node = get_tree().current_scene
	if scene_root == null:
		return

	var fist := Sprite2D.new()
	fist.name = "BoxerFist_%d" % Time.get_ticks_usec()
	fist.texture = fist_texture
	fist.centered = true
	fist.z_as_relative = false
	fist.z_index = fist_z_index
	scene_root.add_child(fist)

	if attack_dir.length_squared() <= 0.000001:
		attack_dir = Vector2.RIGHT
	else:
		attack_dir = attack_dir.normalized()

	var texture_size:Vector2 = fist_texture.get_size()
	if texture_size.x <= 0.001 or texture_size.y <= 0.001:
		fist.queue_free()
		return

	var rest_length:float = maxf(fist_rest_length,8.0)
	# 视觉最大长度固定，不再根据敌人距离自动伸到目标身上。
	var attack_length:float = maxf(fist_max_length,rest_length)
	var visual_height:float = maxf(fist_visual_height,2.0)
	var rest_position:Vector2 = start_position + attack_dir * (rest_length * 0.5)
	var attack_position:Vector2 = start_position + attack_dir * (attack_length * 0.5)
	var rest_scale:Vector2 = Vector2(rest_length / texture_size.x,visual_height / texture_size.y)
	var attack_scale:Vector2 = Vector2(attack_length / texture_size.x,visual_height / texture_size.y)

	fist.global_position = rest_position
	fist.global_rotation = attack_dir.angle()
	fist.scale = rest_scale
	fist.modulate = Color(1.0,1.0,1.0,1.0)

	# 前伸阶段：拳头中心向前，同时只拉长 X，形成“手臂伸长”的效果。
	var tween:Tween = fist.create_tween()
	tween.tween_property(fist,"global_position",attack_position,maxf(fist_extend_time,0.02)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(fist,"scale",attack_scale,maxf(fist_extend_time,0.02)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 收拳：回到正常长度。
	tween.tween_property(fist,"global_position",rest_position,maxf(fist_retract_time,0.02)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(fist,"scale",rest_scale,maxf(fist_retract_time,0.02)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	# 用户要求“不透明度逐级隐藏”，这里故意用多个极短 Alpha 阶段制造阶梯消失。
	var steps:int = maxi(fist_fade_steps,1)
	for index in range(1,steps + 1):
		var alpha_value:float = 1.0 - float(index) / float(steps)
		tween.tween_property(fist,"modulate:a",alpha_value,0.001)
		tween.tween_interval(maxf(fist_fade_step_time,0.01))
	tween.tween_callback(fist.queue_free)


func _show_punch_visual() -> void:
	_visual_token += 1
	var token:int = _visual_token
	_broadcast_visual_state(VISUAL_ATTACK)
	if _dash_active:
		return
	_restore_normal_visual_after(maxf(punch_visual_duration,0.05),token)


func _restore_normal_visual_after(delay:float,token:int) -> void:
	await get_tree().create_timer(delay).timeout
	if not is_instance_valid(self) or token != _visual_token or _dash_active:
		return
	_broadcast_visual_state(VISUAL_NORMAL)


func _begin_dash_ball_collision_exceptions() -> void:
	_clear_dash_ball_collision_exceptions()
	var existing:Array = get_collision_exceptions()
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if raw == self or not (raw is PhysicsBody2D) or not is_instance_valid(raw):
			continue
		var body:PhysicsBody2D = raw as PhysicsBody2D
		# 不移除其它系统原本就建立的碰撞例外，只记录本次突刺新加的项。
		if body in existing:
			continue
		add_collision_exception_with(body)
		_dash_added_collision_exceptions.append(body)


func _clear_dash_ball_collision_exceptions() -> void:
	for body:PhysicsBody2D in _dash_added_collision_exceptions:
		if body != null and is_instance_valid(body):
			remove_collision_exception_with(body)
	_dash_added_collision_exceptions.clear()


func _finish_dash() -> void:
	var was_active:bool = _dash_active
	_dash_active = false
	_dash_remaining = 0.0
	_dash_current_speed = 0.0
	_clear_dash_ball_collision_exceptions()
	Using_Skill = false
	_reset_after_image_sampling()
	if was_active and is_multiplayer_authority():
		_visual_token += 1
		_broadcast_visual_state(VISUAL_NORMAL)


func _broadcast_visual_state(state_value:int) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_set_visual_state.rpc(state_value)
	else:
		_rpc_set_visual_state(state_value)


@rpc("authority","call_local","unreliable")
func _rpc_set_visual_state(state_value:int) -> void:
	_set_visual_state_local(state_value)


func _set_visual_state_local(state_value:int) -> void:
	if not (image is Sprite2D):
		return
	var fallback_normal:Texture2D = normal_texture if normal_texture != null else _default_texture
	var wanted:Texture2D = fallback_normal
	if state_value == VISUAL_ATTACK and attack_texture != null:
		wanted = attack_texture
	if wanted != null:
		(image as Sprite2D).texture = wanted
		_refit_visual_only()


func _refit_visual_only() -> void:
	var auto_fit:Node = get_node_or_null("CharacterAutoFit")
	if auto_fit != null and auto_fit.has_method("apply_visual_fit_only"):
		auto_fit.call_deferred("apply_visual_fit_only")


func _is_valid_enemy(target:ball) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(self,target): return false # 皓宸复制品及其产物不把己方选为目标
	if target == null or not is_instance_valid(target) or target == self:
		return false
	if not target.is_combat_targetable():
		return false
	if Team != "" and target.Team == Team:
		return false
	return true


func _play_boxer_sfx_everywhere(kind:int,position_value:Vector2,volume_db:float,pitch:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_boxer_sfx.rpc(kind,position_value,volume_db,pitch)
	else:
		_rpc_play_boxer_sfx(kind,position_value,volume_db,pitch)


@rpc("authority","call_local","unreliable")
func _rpc_play_boxer_sfx(kind:int,position_value:Vector2,volume_db:float,pitch:float) -> void:
	if not is_inside_tree():
		return
	var stream:AudioStream = PUNCH_SWING_SFX if kind == BOXER_SFX_SWING else PUNCH_HIT_SFX
	if stream == null:
		return
	var scene_root:Node = get_tree().current_scene
	if scene_root == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.global_position = position_value
	player.volume_db = volume_db
	player.pitch_scale = clampf(pitch,0.75,1.30)
	player.max_distance = 1250.0
	player.attenuation = 0.35
	player.max_polyphony = 6
	scene_root.add_child(player)
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _play_local_sfx_everywhere(key:String,position_value:Vector2,volume_db:float,pitch:float,max_distance:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_local_sfx.rpc(key,position_value,volume_db,pitch,max_distance)
	else:
		_rpc_play_local_sfx(key,position_value,volume_db,pitch,max_distance)


@rpc("authority","call_local","unreliable")
func _rpc_play_local_sfx(key:String,position_value:Vector2,volume_db:float,pitch:float,max_distance:float) -> void:
	LOCAL_SFX.play(self,key,position_value,volume_db,pitch,max_distance)


func Die() -> void:
	_finish_dash()
	_next_combo_punch_count = 1
	_last_base_attack_msec = -1000000
	_active_ai_punch_threats.clear()
	super()
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(self):
		Game.free_node(self)
