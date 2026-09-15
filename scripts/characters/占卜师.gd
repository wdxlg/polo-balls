extends ball

const CARD_VISUAL_SCRIPT:Script = preload("res://scripts/effects/占卜师卡牌.gd")

const CARD_ATTACK:int = 0
const CARD_DEFENSE:int = 1
const CARD_RECOVERY:int = 2
const CARD_WHEEL:int = 3
const CARD_COUNT:int = 4

const SFX_SHUFFLE:String = "占卜师洗牌"
const SFX_DRAW:String = "占卜师出牌"
const SFX_DECIDE:String = "占卜师决定牌"
const SFX_THROW:String = "占卜师扔牌"
const SFX_HIT:String = "balls_hit1"

@export_category("占卜师 - 抽卡")
@export_range(0.1,2.0,0.05) var draw_move_duration:float = 0.72
@export_range(0.0,0.5,0.01) var draw_stagger:float = 0.12
@export_range(0.1,1.5,0.05) var reveal_pause:float = 0.34
@export_range(0.1,1.5,0.05) var confirm_duration:float = 0.62
@export_range(0.1,1.5,0.05) var reorder_duration:float = 0.42
@export_range(8.0,80.0,1.0) var card_slot_y:float = 29.0
@export_range(8.0,40.0,1.0) var card_spacing:float = 13.0

@export_category("占卜师 - 抽卡概率")
@export_range(0.0,100.0,1.0,"suffix:%") var attack_card_chance:float = 30.0
@export_range(0.0,100.0,1.0,"suffix:%") var defense_card_chance:float = 30.0
@export_range(0.0,100.0,1.0,"suffix:%") var recovery_card_chance:float = 30.0

@export_category("占卜师 - 攻击牌")
@export_range(0.1,5.0,0.05) var attack_multiplier_one:float = 0.90
@export_range(0.1,5.0,0.05) var attack_multiplier_two:float = 1.15
@export_range(0.1,5.0,0.05) var attack_multiplier_three:float = 1.45
@export_range(0.1,5.0,0.05) var attack_multiplier_four:float = 1.80
@export_range(0.2,2.5,0.05) var attack_card_flight_duration:float = 1.45
@export_range(0.0,180.0,1.0) var attack_curve_height:float = 62.0
@export_range(0.0,8.0,0.1) var attack_homing_strength:float = 2.3
@export_range(0.0,0.5,0.01) var attack_launch_stagger:float = 0.11

@export_category("占卜师 - 防御 / 恢复")
@export_range(1.0,300.0,1.0) var defense_base_per_card:float = 55.0
@export_range(1.0,350.0,1.0) var recovery_base_per_card:float = 65.0
@export_range(0.0,1.0,0.01) var same_card_growth_per_extra:float = 0.18
@export_range(0.5,8.0,0.1) var recovery_duration:float = 3.2
@export_range(0.05,0.8,0.01) var recovery_tick_interval:float = 0.20
@export_range(0.1,1.5,0.05) var utility_consume_duration:float = 0.56

var _rng := RandomNumberGenerator.new()
var _card_layer:Node2D = null
var _visual_cards:Array[Node] = []
var _current_initial_types:Array[int] = []
var _current_resolved_types:Array[int] = []
var _sequence_serial:int = 0
var _recovery_serial:int = 0
var _visual_audio_serial:int = 0


func _ready() -> void:
	Has_Collision_Damage = false
	Can_Attack = true
	Can_Skill = false
	super._ready()
	_rng.seed = Game.battle_rng_seed_or("scripts/characters/占卜师.gd:_rng",int(Time.get_ticks_usec()) ^ int(get_instance_id()))
	_setup_card_layer()


func _process(_delta:float) -> void:
	# 卡牌排列层固定使用世界尺寸，不继承人物根节点约 0.2 的缩放；
	# 但它的世界中心始终跟随占卜师。
	if _card_layer != null and is_instance_valid(_card_layer):
		_card_layer.global_position = global_position


func has_collision_damage() -> bool:
	return false


func Attack() -> void:
	if not is_multiplayer_authority() or Attacking:
		return
	if health <= 0 or state_machine == null or state_machine.current_state == State.Die:
		return
	if is_damage_output_disabled() or not is_combat_runtime_active():
		return
	Attacking = true
	_sequence_serial += 1
	var serial:int = _sequence_serial
	call_deferred("_run_card_sequence",serial)


func controlled_attack_action() -> void:
	if not is_multiplayer_authority() or not is_player_controlled():
		return
	if Attacking or health <= 0 or is_damage_output_disabled() or not is_combat_runtime_active():
		return
	if state_machine == null:
		return
	var elapsed:float = float(state_machine.last_state_dis.get("Attack",0.0))
	if elapsed < Attack_Cooling:
		return
	state_machine.last_state_dis["Attack"] = 0.0
	Attack()


func controlled_skill_action() -> void:
	# 右键也允许触发同一套占卜流程，避免直接控制时只有左键可用。
	controlled_attack_action()


func _run_card_sequence(serial:int) -> void:
	if not _sequence_valid(serial):
		_finish_sequence(serial)
		return

	_current_initial_types = _draw_four_cards()
	_current_resolved_types = _current_initial_types.duplicate()
	_broadcast_begin_draw(_current_initial_types)
	await get_tree().create_timer(
		maxf(draw_move_duration,0.2) + maxf(draw_stagger,0.0) * float(CARD_COUNT - 1) + maxf(reveal_pause,0.0)
	).timeout
	if not _sequence_valid(serial):
		_finish_sequence(serial)
		return

	# 四张命运之轮是独立大奖：不再转换为普通牌，直接执行全敌人致死。
	if _all_wheels(_current_initial_types):
		_broadcast_jackpot()
		await get_tree().create_timer(0.46).timeout
		if _sequence_valid(serial):
			_instant_kill_all_enemies()
		await get_tree().create_timer(0.56).timeout
		_finish_sequence(serial)
		return

	var wheel_target:int = _resolve_wheel_target(_current_initial_types)
	for i:int in range(_current_resolved_types.size()):
		if _current_resolved_types[i] == CARD_WHEEL:
			_current_resolved_types[i] = wheel_target

	# 命运之轮先完成“填补数量最多牌”的转换；随后所有牌一起高亮确认颜色。
	_broadcast_confirm_and_reorder(_current_resolved_types)
	await get_tree().create_timer(maxf(confirm_duration,0.2) + maxf(reorder_duration,0.12) + 0.16).timeout
	if not _sequence_valid(serial):
		_finish_sequence(serial)
		return

	var attack_count:int = _count_type(_current_resolved_types,CARD_ATTACK)
	var defense_count:int = _count_type(_current_resolved_types,CARD_DEFENSE)
	var recovery_count:int = _count_type(_current_resolved_types,CARD_RECOVERY)

	# 同类牌已经排到一起。按排序后的从左到右顺序结算：攻击 -> 防御 -> 恢复。
	if attack_count > 0:
		await _use_attack_cards(serial,attack_count)
		if not _sequence_valid(serial):
			_finish_sequence(serial)
			return

	if defense_count > 0:
		# V386：牌一进入“使用/消耗”动作就立即生效，不再等整段消失动画播完。
		_broadcast_consume_utility(CARD_DEFENSE)
		_apply_defense_cards(defense_count)
		await get_tree().create_timer(_utility_animation_wait(defense_count)).timeout
		if not _sequence_valid(serial):
			_finish_sequence(serial)
			return

	if recovery_count > 0:
		# V386：恢复牌同样在“使用”的第一帧启动治疗；持续治疗本身仍按原来的 tick 节奏完成。
		_broadcast_consume_utility(CARD_RECOVERY)
		_start_recovery_over_time(_recovery_total_for_count(recovery_count),recovery_duration)
		await get_tree().create_timer(_utility_animation_wait(recovery_count)).timeout
		if not _sequence_valid(serial):
			_finish_sequence(serial)
			return

	_finish_sequence(serial)


func _draw_four_cards() -> Array[int]:
	var result:Array[int] = []
	for _i:int in range(CARD_COUNT):
		result.append(_draw_one_card())
	return result


func _draw_one_card() -> int:
	# 三个 Inspector 参数直接表示三种普通牌的实际百分比。
	# 命运之轮自动使用剩余概率：
	# 30/30/30 -> 命运10%；0/0/0 -> 命运100%；20/20/20 -> 命运40%。
	var attack_weight:float = maxf(attack_card_chance,0.0)
	var defense_weight:float = maxf(defense_card_chance,0.0)
	var recovery_weight:float = maxf(recovery_card_chance,0.0)
	var normal_total:float = attack_weight + defense_weight + recovery_weight

	# 普通牌总和超过100%时，只在三种普通牌之间按原比例归一化，
	# 此时命运之轮概率为0，避免出现大于100%的非法总概率。
	if normal_total > 100.0:
		var normalize_scale:float = 100.0 / normal_total
		attack_weight *= normalize_scale
		defense_weight *= normalize_scale
		recovery_weight *= normalize_scale
		normal_total = 100.0

	var wheel_weight:float = maxf(100.0 - normal_total,0.0)
	var weights := PackedFloat32Array([
		attack_weight,
		defense_weight,
		recovery_weight,
		wheel_weight
	])
	var index:int = _rng.rand_weighted(weights)
	match index:
		0:
			return CARD_ATTACK
		1:
			return CARD_DEFENSE
		2:
			return CARD_RECOVERY
		3:
			return CARD_WHEEL
	return CARD_WHEEL


func _resolve_wheel_target(types:Array[int]) -> int:
	var counts:Array[int] = [0,0,0]
	for card_type:int in types:
		if card_type >= CARD_ATTACK and card_type <= CARD_RECOVERY:
			counts[card_type] += 1
	var highest:int = maxi(counts[0],maxi(counts[1],counts[2]))

	# 平票时按本次抽卡从左到右遇到的第一种并列最高牌决定，
	# 不暗中偏向攻击/防御/恢复中的任何一种。
	for card_type:int in types:
		if card_type >= CARD_ATTACK and card_type <= CARD_RECOVERY and counts[card_type] == highest:
			return card_type
	return CARD_ATTACK


func _all_wheels(types:Array[int]) -> bool:
	if types.size() != CARD_COUNT:
		return false
	for card_type:int in types:
		if card_type != CARD_WHEEL:
			return false
	return true


func _count_type(types:Array[int],wanted:int) -> int:
	var count:int = 0
	for card_type:int in types:
		if card_type == wanted:
			count += 1
	return count


func _attack_multiplier_for_count(count:int) -> float:
	match clampi(count,1,4):
		1:
			return attack_multiplier_one
		2:
			return attack_multiplier_two
		3:
			return attack_multiplier_three
		4:
			return attack_multiplier_four
	return attack_multiplier_one


func _same_card_total(base_per_card:float,count:int) -> float:
	var safe_count:int = clampi(count,0,4)
	if safe_count <= 0:
		return 0.0
	var synergy:float = 1.0 + same_card_growth_per_extra * float(safe_count - 1)
	return maxf(base_per_card,0.0) * float(safe_count) * maxf(synergy,0.0)


func _defense_total_for_count(count:int) -> float:
	return _same_card_total(defense_base_per_card,count)


func _recovery_total_for_count(count:int) -> float:
	return _same_card_total(recovery_base_per_card,count)


func _utility_animation_wait(count:int) -> float:
	return (
		maxf(utility_consume_duration,0.2)
		+ 0.06 * float(maxi(count - 1,0))
		+ 0.08
	)


func _apply_defense_cards(count:int) -> void:
	var amount:int = maxi(int(round(_defense_total_for_count(count))),0)
	if amount <= 0:
		return
	block = mini(block + amount,max_block)
	# V385：防御牌结算统一使用扔牌音效。
	_play_sfx_everywhere(SFX_THROW,false,true)


func _start_recovery_over_time(total_amount:float,duration:float) -> void:
	var total:int = maxi(int(round(total_amount)),0)
	if total <= 0:
		return
	# V385：治疗牌结算统一使用扔牌音效。
	_play_sfx_everywhere(SFX_THROW,false,true)
	_recovery_serial += 1
	var serial:int = _recovery_serial
	call_deferred("_run_recovery_ticks",serial,total,maxf(duration,0.1))


func _run_recovery_ticks(serial:int,total:int,duration:float) -> void:
	var interval:float = maxf(recovery_tick_interval,0.05)
	var steps:int = maxi(int(ceil(duration / interval)),1)
	var scheduled:int = 0
	for step:int in range(steps):
		if not is_instance_valid(self) or health <= 0 or state_machine == null or state_machine.current_state == State.Die:
			return
		# 每一跳按照累计目标值分配，最终所有跳合计恰好等于 total。
		var target_scheduled:int = int(round(float(total) * float(step + 1) / float(steps)))
		var this_tick:int = maxi(target_scheduled - scheduled,0)
		scheduled = target_scheduled
		if this_tick > 0:
			heal(float(this_tick))
		if step < steps - 1:
			await get_tree().create_timer(interval).timeout
		if serial != _recovery_serial:
			return


func _use_attack_cards(serial:int,count:int) -> void:
	var target_paths:Array[String] = []
	var fallback_positions:Array[Vector2] = []
	var actual_targets:Array[ball] = []
	for i:int in range(count):
		var target:ball = _select_enemy_target()
		if target == null:
			break
		actual_targets.append(target)
		target_paths.append(str(target.get_path()))
		fallback_positions.append(target.global_position)

	if actual_targets.is_empty():
		# 场上没有敌人时攻击牌仍会做一次消散，避免牌永久挂在人物下面。
		_broadcast_consume_utility(CARD_ATTACK)
		await get_tree().create_timer(_utility_animation_wait(count)).timeout
		return

	# V92：伤害仍跟着红牌真实碰撞帧结算；运动保持 V91 的长时间低速缓慢追踪。
	# 发射出去的攻击牌会从 _visual_cards 管理列表中摘除，避免本轮攻击序列收尾时 _local_clear_cards() 把仍在飞的牌误删。
	var damage_per_card:float = attack_damage(_attack_multiplier_for_count(count))
	_broadcast_launch_attack_cards(target_paths,fallback_positions,serial,damage_per_card)

	await get_tree().create_timer(
		maxf(attack_card_flight_duration,0.25) + maxf(attack_launch_stagger,0.0) * float(maxi(actual_targets.size() - 1,0)) + 0.08
	).timeout


func _on_attack_card_contact(target_node:Node2D,serial:int,damage_amount:float) -> void:
	# 每个客户端都有自己的红牌视觉，但只有占卜师 authority 负责伤害。
	if not is_multiplayer_authority() or not _sequence_valid(serial):
		return
	if not (target_node is ball):
		return
	var target:ball = target_node as ball
	if not _is_enemy(target) or damage_amount <= 0.0:
		return
	var dealt_damage:bool = target.receive_spatial_damage(
		damage_amount,
		{
			"shape":"point",
			"point":target.global_position,
			"source":self,
		},
		false,
		false
	)
	if dealt_damage:
		_play_sfx_everywhere(SFX_HIT,true,true)


func _instant_kill_all_enemies() -> void:
	if not is_multiplayer_authority():
		return
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var target:ball = raw as ball
		if not _is_enemy(target):
			continue
		# 使用公共 raw-health 入口保证真正越过护盾；特殊角色自带的死亡回归/复活被动仍可按其规则处理。
		var lethal:float = maxf(float(target.Max_health),float(target.health)) * 12.0 + 9999.0
		target.receive_spatial_raw_health_damage(
			lethal,
			{
				"shape":"global_fate",
				"point":target.global_position,
				"source":self,
			}
		)


func _select_enemy_target() -> ball:
	var nearest:ball = null
	var nearest_distance_sq:float = INF
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var candidate:ball = raw as ball
		if not _is_enemy(candidate):
			continue
		var distance_sq:float = global_position.distance_squared_to(candidate.global_position)
		if distance_sq < nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest = candidate
	return nearest


func _is_enemy(target:ball) -> bool:
	if target == null or not is_instance_valid(target) or target == self:
		return false
	if target.Type != Ball_Type.Ball or target.health <= 0:
		return false
	if not target.is_combat_targetable():
		return false
	# “敌人”按阵营判断；即使全局开启友伤，四轮大奖也不会把同队单位算作敌人。
	if not Team.is_empty() and not target.Team.is_empty() and Team == target.Team:
		return false
	return true


func _sequence_valid(serial:int) -> bool:
	return (
		is_instance_valid(self)
		and serial == _sequence_serial
		and health > 0
		and state_machine != null
		and state_machine.current_state != State.Die
		and is_combat_runtime_active()
	)


func _finish_sequence(serial:int) -> void:
	if serial != _sequence_serial:
		return
	Attacking = false
	_current_initial_types.clear()
	_current_resolved_types.clear()
	_broadcast_clear_cards()


func _setup_card_layer() -> void:
	if _card_layer != null and is_instance_valid(_card_layer):
		return
	_card_layer = Node2D.new()
	_card_layer.name = "TarotCardLayer"
	add_child(_card_layer)
	_card_layer.set_as_top_level(true)
	_card_layer.global_position = global_position
	_card_layer.z_index = 90


func _slot_position(index:int) -> Vector2:
	var center_offset:float = float(CARD_COUNT - 1) * 0.5
	return Vector2((float(index) - center_offset) * card_spacing,card_slot_y)


func _sorted_visual_cards() -> Array[Node]:
	var result:Array[Node] = []
	for wanted:int in [CARD_ATTACK,CARD_DEFENSE,CARD_RECOVERY,CARD_WHEEL]:
		for card:Node in _visual_cards:
			if card == null or not is_instance_valid(card):
				continue
			if int(card.get("resolved_type")) == wanted:
				result.append(card)
	return result


func _local_clear_cards() -> void:
	_visual_audio_serial += 1
	for card:Node in _visual_cards:
		if card != null and is_instance_valid(card):
			card.queue_free()
	_visual_cards.clear()


func _local_begin_draw(initial_types:Array) -> void:
	_setup_card_layer()
	_local_clear_cards()
	var audio_serial:int = _visual_audio_serial
	_play_sfx_local(SFX_SHUFFLE,false,true)
	for i:int in range(mini(initial_types.size(),CARD_COUNT)):
		var card:Node2D = CARD_VISUAL_SCRIPT.new() as Node2D
		_card_layer.add_child(card)
		card.call("setup",int(initial_types[i]),i,false)
		card.position = Vector2.ZERO
		var appear_delay:float = draw_stagger * float(i)
		card.call("animate_draw",_slot_position(i),appear_delay,draw_move_duration)
		_play_sfx_local_after_delay(SFX_DRAW,appear_delay,audio_serial,false,true)
		_visual_cards.append(card)


func _local_confirm_and_reorder(resolved_types:Array) -> void:
	var audio_serial:int = _visual_audio_serial
	# 牌面在确认动画峰值处真正切换颜色，决定牌音效与该帧对齐。
	_play_sfx_local_after_delay(SFX_DECIDE,maxf(confirm_duration,0.20) * 0.34,audio_serial,false,true)
	for i:int in range(mini(_visual_cards.size(),resolved_types.size())):
		var card:Node = _visual_cards[i]
		if card == null or not is_instance_valid(card):
			continue
		card.call("animate_confirm",int(resolved_types[i]),0.0,confirm_duration)

	# 等确认弹性开始回落后再重排，同种卡最终相邻。
	var ordered:Array[Node] = []
	for wanted:int in [CARD_ATTACK,CARD_DEFENSE,CARD_RECOVERY]:
		for i:int in range(mini(_visual_cards.size(),resolved_types.size())):
			if int(resolved_types[i]) == wanted:
				ordered.append(_visual_cards[i])
	for index:int in range(ordered.size()):
		var card:Node = ordered[index]
		if card != null and is_instance_valid(card):
			card.call("animate_reorder",_slot_position(index),confirm_duration * 0.46,reorder_duration)


func _local_consume_utility(card_type:int) -> void:
	var ordered:Array[Node] = _sorted_visual_cards()
	var matched_index:int = 0
	for card:Node in ordered:
		if card == null or not is_instance_valid(card):
			continue
		if int(card.get("resolved_type")) != card_type:
			continue
		card.call("animate_consume",card_type,float(matched_index) * 0.06,utility_consume_duration)
		matched_index += 1


func _local_launch_attack_cards(target_paths:Array,fallback_positions:Array,serial:int,damage_amount:float) -> void:
	var attack_cards:Array[Node] = []
	for card:Node in _sorted_visual_cards():
		if card != null and is_instance_valid(card) and int(card.get("resolved_type")) == CARD_ATTACK:
			attack_cards.append(card)

	var launch_count:int = mini(attack_cards.size(),mini(target_paths.size(),fallback_positions.size()))
	var audio_serial:int = _visual_audio_serial
	for i:int in range(launch_count):
		var card:Node = attack_cards[i]
		if card == null or not is_instance_valid(card):
			continue
		var launch_delay:float = attack_launch_stagger * float(i)
		var side:float = -1.0 if (i % 2) == 0 else 1.0
		_play_sfx_local_after_delay(SFX_THROW,launch_delay,audio_serial,false,true)
		if card.has_signal("attack_contact"):
			card.connect("attack_contact",Callable(self,"_on_attack_card_contact").bind(serial,damage_amount),CONNECT_ONE_SHOT)
		card.call_deferred(
			"start_attack_flight",
			NodePath(str(target_paths[i])),
			fallback_positions[i],
			launch_delay,
			attack_card_flight_duration,
			side,
			attack_curve_height + float(i) * 8.0,
			attack_homing_strength
		)
		# V92：一旦交给独立飞行逻辑，攻击牌就不再属于“牌组 UI 清理”的生命周期。
		# 否则 _finish_sequence() -> _broadcast_clear_cards() 会在固定等待结束时 queue_free 仍在慢速追踪的红牌，
		# 视觉上很像“碰到占卜师自己突然消失”。
		_visual_cards.erase(card)


func _local_jackpot() -> void:
	_play_sfx_local(SFX_DECIDE,false,true)
	if Game.has_method("play_blood_jackpot_flash_local"):
		Game.play_blood_jackpot_flash_local()
	for i:int in range(_visual_cards.size()):
		var card:Node = _visual_cards[i]
		if card != null and is_instance_valid(card):
			card.call("animate_jackpot",float(i) * 0.05,0.82)


func _play_sfx_local(sfx_name:String,randomize:bool = false,create_new_audio:bool = true) -> void:
	if sfx_name.is_empty():
		return
	Audios.play_sfx(sfx_name,{},randomize,create_new_audio)


func _play_sfx_local_after_delay(
	sfx_name:String,
	delay:float,
	audio_serial:int,
	randomize:bool = false,
	create_new_audio:bool = true
) -> void:
	if maxf(delay,0.0) > 0.0:
		await get_tree().create_timer(maxf(delay,0.0)).timeout
	if not is_instance_valid(self) or audio_serial != _visual_audio_serial:
		return
	_play_sfx_local(sfx_name,randomize,create_new_audio)


func _play_sfx_everywhere(sfx_name:String,randomize:bool = false,create_new_audio:bool = true) -> void:
	if sfx_name.is_empty():
		return
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc(sfx_name,{},randomize,create_new_audio)
	else:
		Audios.play_sfx(sfx_name,{},randomize,create_new_audio)


func _broadcast_begin_draw(initial_types:Array[int]) -> void:
	var payload:Array = []
	for value:int in initial_types:
		payload.append(value)
	if multiplayer.has_multiplayer_peer():
		_rpc_begin_draw.rpc(payload)
	else:
		_rpc_begin_draw(payload)


func _broadcast_confirm_and_reorder(resolved_types:Array[int]) -> void:
	var payload:Array = []
	for value:int in resolved_types:
		payload.append(value)
	if multiplayer.has_multiplayer_peer():
		_rpc_confirm_and_reorder.rpc(payload)
	else:
		_rpc_confirm_and_reorder(payload)


func _broadcast_consume_utility(card_type:int) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_consume_utility.rpc(card_type)
	else:
		_rpc_consume_utility(card_type)


func _broadcast_launch_attack_cards(target_paths:Array[String],fallback_positions:Array[Vector2],serial:int,damage_amount:float) -> void:
	var paths_payload:Array = []
	for path:String in target_paths:
		paths_payload.append(path)
	var pos_payload:Array = []
	for point:Vector2 in fallback_positions:
		pos_payload.append(point)
	if multiplayer.has_multiplayer_peer():
		_rpc_launch_attack_cards.rpc(paths_payload,pos_payload,serial,damage_amount)
	else:
		_rpc_launch_attack_cards(paths_payload,pos_payload,serial,damage_amount)


func _broadcast_jackpot() -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_jackpot.rpc()
	else:
		_rpc_jackpot()


func _broadcast_clear_cards() -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_clear_cards.rpc()
	else:
		_rpc_clear_cards()


@rpc("authority","call_local","reliable")
func _rpc_begin_draw(initial_types:Array) -> void:
	_local_begin_draw(initial_types)


@rpc("authority","call_local","reliable")
func _rpc_confirm_and_reorder(resolved_types:Array) -> void:
	_local_confirm_and_reorder(resolved_types)


@rpc("authority","call_local","reliable")
func _rpc_consume_utility(card_type:int) -> void:
	_local_consume_utility(card_type)


@rpc("authority","call_local","reliable")
func _rpc_launch_attack_cards(target_paths:Array,fallback_positions:Array,serial:int,damage_amount:float) -> void:
	_local_launch_attack_cards(target_paths,fallback_positions,serial,damage_amount)


@rpc("authority","call_local","reliable")
func _rpc_jackpot() -> void:
	_local_jackpot()


@rpc("authority","call_local","reliable")
func _rpc_clear_cards() -> void:
	_local_clear_cards()


func Die() -> void:
	_sequence_serial += 1
	_recovery_serial += 1
	Attacking = false
	if is_multiplayer_authority():
		_broadcast_clear_cards()
	super.Die()
