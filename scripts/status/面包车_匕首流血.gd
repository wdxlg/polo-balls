extends Node

# 面包车匕首混混的单层流血。
# 设计与剑客流血接近：目标移动或开始攻击/技能时会产生少量内部伤害，
# 但这个状态永远只有 1 层；再次被匕首命中只刷新持续时间。

var target:ball = null
var source:ball = null
var duration:float = 6.0
var remaining:float = 0.0
var action_damage:float = 2.0
var move_tick_interval:float = 0.60
var move_damage:float = 0.60

var _move_tick_left:float = 0.0
var _move_distance_accum:float = 0.0
var _last_position:Vector2 = Vector2.ZERO
var _action_was_active:bool = false
var _base_self_modulate:Color = Color.WHITE

func setup(new_target:ball,new_source:ball,new_duration:float = 6.0,new_action_damage:float = 2.0,new_move_damage:float = 0.60) -> void:
	target = new_target
	source = new_source
	duration = maxf(new_duration,0.1)
	action_damage = maxf(new_action_damage,0.0)
	move_damage = maxf(new_move_damage,0.0)
	remaining = duration
	_move_tick_left = move_tick_interval
	if target != null and is_instance_valid(target):
		_last_position = target.global_position
		if target.image != null and is_instance_valid(target.image):
			_base_self_modulate = target.image.self_modulate
	_apply_tint()

func refresh(new_source:ball,new_action_damage:float = -1.0,new_move_damage:float = -1.0) -> void:
	if new_source != null and is_instance_valid(new_source):
		source = new_source
	if new_action_damage >= 0.0:
		action_damage = new_action_damage
	if new_move_damage >= 0.0:
		move_damage = new_move_damage
	remaining = duration
	_apply_tint()

func _physics_process(delta:float) -> void:
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion() or target.health <= 0:
		_finish()
		return

	remaining -= delta
	if remaining <= 0.0:
		_finish()
		return

	var now_position:Vector2 = target.global_position
	_move_distance_accum += now_position.distance_to(_last_position)
	_last_position = now_position

	_move_tick_left -= delta
	if _move_tick_left <= 0.0:
		_move_tick_left += move_tick_interval
		if _move_distance_accum >= 4.0:
			_deal_internal_bleed(maxi(int(ceil(move_damage)),1))
		_move_distance_accum = 0.0

	var action_active:bool = false
	if target.state_machine != null:
		var state:int = int(target.state_machine.current_state)
		action_active = state == ball.State.Attack or state == ball.State.Skill
	action_active = action_active or target.Attacking or target.Using_Skill
	if action_active and not _action_was_active:
		_deal_internal_bleed(maxi(int(round(action_damage)),1))
	_action_was_active = action_active

func _deal_internal_bleed(amount:int) -> void:
	if amount <= 0 or target == null or not is_instance_valid(target) or target.health <= 0:
		return
	var before:float = float(target.health)
	# 和剑客一样属于体内伤害：不再触发一次格挡/闪白。
	target.receive_internal_status_damage(amount,&"bleed",source)
	var actual:float = maxf(before - float(target.health),0.0)
	if actual <= 0.0:
		return
	if source != null and is_instance_valid(source) and Game.has_method("report_training_damage"):
		Game.report_training_damage(source,target,actual)
	_play_bleed_hit_sound(actual)

func _play_bleed_hit_sound(actual_damage:float) -> void:
	if source == null or not is_instance_valid(source) or not source.is_multiplayer_authority():
		return
	var params:Dictionary = {"volume":clampf(-18.0 + actual_damage * 0.55,-18.0,-9.0)}
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc("balls_hit1",params,true,true)
	else:
		Audios.play_sfx("balls_hit1",params,true,true)

func _apply_tint() -> void:
	if target == null or not is_instance_valid(target) or target.image == null or not is_instance_valid(target.image):
		return
	# 单层只做很轻的红色提示。
	target.image.self_modulate = _base_self_modulate * Color(1.0,0.88,0.88,1.0)

func _finish() -> void:
	if target != null and is_instance_valid(target) and target.image != null and is_instance_valid(target.image):
		target.image.self_modulate = _base_self_modulate
	queue_free()
