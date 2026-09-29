extends Node

var target:ball = null
var source:ball = null
var stacks:int = 0
var max_stacks:int = 5
var duration:float = 6.0
var remaining:float = 0.0
var action_damage_per_stack:float = 2.0
var move_tick_interval:float = 0.60
var move_damage_per_stack:float = 0.60

var _move_tick_left:float = 0.0
var _move_distance_accum:float = 0.0
var _last_position:Vector2 = Vector2.ZERO
var _action_was_active:bool = false
var _base_self_modulate:Color = Color.WHITE


func setup(
	new_target:ball,
	new_source:ball,
	added_stacks:int,
	new_max_stacks:int,
	new_duration:float,
	new_action_damage_per_stack:float,
	new_move_tick_interval:float,
	new_move_damage_per_stack:float
) -> void:
	target = new_target
	source = new_source
	max_stacks = maxi(new_max_stacks,1)
	duration = maxf(new_duration,0.1)
	action_damage_per_stack = maxf(new_action_damage_per_stack,0.0)
	move_tick_interval = maxf(new_move_tick_interval,0.1)
	move_damage_per_stack = maxf(new_move_damage_per_stack,0.0)
	remaining = duration
	_move_tick_left = move_tick_interval
	if target != null and is_instance_valid(target):
		_last_position = target.global_position
		if target.image != null and is_instance_valid(target.image):
			_base_self_modulate = target.image.self_modulate
	add_stacks(added_stacks,new_source)


func add_stacks(amount:int,new_source:ball = null) -> void:
	if new_source != null and is_instance_valid(new_source):
		source = new_source
	stacks = clampi(stacks + maxi(amount,0),0,max_stacks)
	remaining = duration
	_apply_red_tint()


func _physics_process(delta:float) -> void:
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion() or target.health <= 0:
		_finish()
		return

	remaining -= delta
	if remaining <= 0.0 or stacks <= 0:
		_finish()
		return

	var now_position:Vector2 = target.global_position
	_move_distance_accum += now_position.distance_to(_last_position)
	_last_position = now_position

	_move_tick_left -= delta
	if _move_tick_left <= 0.0:
		_move_tick_left += move_tick_interval
		# 位移流血很低：只有这一段时间内确实移动了一小段距离才结算。
		if _move_distance_accum >= 4.0:
			var move_damage:int = maxi(int(ceil(float(stacks) * move_damage_per_stack)),1)
			_deal_internal_bleed(move_damage)
		_move_distance_accum = 0.0

	var action_active:bool = false
	if target.state_machine != null:
		var state:int = int(target.state_machine.current_state)
		action_active = state == ball.State.Attack or state == ball.State.Skill
	action_active = action_active or target.Attacking or target.Using_Skill
	if action_active and not _action_was_active:
		var action_damage:int = maxi(int(round(float(stacks) * action_damage_per_stack)),1)
		_deal_internal_bleed(action_damage)
	_action_was_active = action_active


func _deal_internal_bleed(amount:int) -> void:
	if amount <= 0 or target == null or not is_instance_valid(target) or target.health <= 0:
		return
	var before:float = float(target.health)
	# 流血属于体内持续伤害：不触发格挡/闪避，也不反复闪白。
	target.receive_internal_status_damage(amount,&"bleed",source)
	var actual:float = maxf(before - float(target.health),0.0)
	if actual > 0.0:
		_play_bleed_damage_audio(actual)
		if source != null and is_instance_valid(source) and Game.has_method("report_training_damage"):
			Game.report_training_damage(source,target,actual)


func _play_bleed_damage_audio(actual_damage:float) -> void:
	if actual_damage <= 0.0:
		return
	# 与普通碰撞造成生命伤害时使用同一套命中音；每次流血结算都新建 voice，
	# 避免连续流血 tick 互相截断。
	var params:Dictionary = {
		"volume": clampf(-18.0 + actual_damage * 0.55,-18.0,-8.0)
	}
	var authority_node:ball = source if source != null and is_instance_valid(source) else target
	if authority_node == null or not is_instance_valid(authority_node) or not authority_node.is_multiplayer_authority():
		return
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc("balls_hit1",params,true,true)
	else:
		Audios.play_sfx("balls_hit1",params,true,true)


func _apply_red_tint() -> void:
	if target == null or not is_instance_valid(target) or target.image == null or not is_instance_valid(target.image):
		return
	var stack_ratio:float = clampf(float(stacks) / float(maxi(max_stacks,1)),0.0,1.0)
	# 第一层只给很轻的红色提示，随后按层数非线性增强；满层也不再染成深红。
	var visual_strength:float = pow(stack_ratio,1.55)
	var green_blue:float = lerpf(1.0,0.68,visual_strength)
	var bleed_tint := Color(1.0,green_blue,green_blue,1.0)
	target.image.self_modulate = _base_self_modulate * bleed_tint


func _finish() -> void:
	if target != null and is_instance_valid(target) and target.image != null and is_instance_valid(target.image):
		target.image.self_modulate = _base_self_modulate
	queue_free()
