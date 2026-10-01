extends Node

# 锻刀师烧钢阶段留下的单层燃烧。
# 同一目标同时只保留一个本状态；再次命中只刷新持续时间和伤害来源，绝不叠层。

var target:ball = null
var source:ball = null
var duration:float = 2.5
var remaining:float = 0.0
var tick_interval:float = 0.5
var tick_damage:float = 3.0
var _tick_left:float = 0.0
var _base_self_modulate:Color = Color.WHITE


func setup(
	new_target:ball,
	new_source:ball,
	new_duration:float = 2.5,
	new_tick_interval:float = 0.5,
	new_tick_damage:float = 3.0
) -> void:
	target = new_target
	source = new_source
	if target == null or not is_instance_valid(target) or not target.can_receive_fire_status():
		queue_free()
		return
	duration = maxf(new_duration,0.1)
	tick_interval = maxf(new_tick_interval,0.05)
	tick_damage = maxf(new_tick_damage,0.0)
	remaining = duration
	_tick_left = tick_interval
	if target != null and is_instance_valid(target) and target.image != null and is_instance_valid(target.image):
		_base_self_modulate = target.image.self_modulate
	_apply_visual()


func refresh(new_source:ball,new_duration:float = -1.0,new_tick_damage:float = -1.0) -> void:
	if target == null or not is_instance_valid(target) or not target.can_receive_fire_status():
		_finish()
		return
	if new_source != null and is_instance_valid(new_source):
		source = new_source
	if new_duration > 0.0:
		duration = new_duration
	if new_tick_damage >= 0.0:
		tick_damage = new_tick_damage
	remaining = duration
	_apply_visual()


func _physics_process(delta:float) -> void:
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion() or target.health <= 0:
		_finish()
		return
	if not target.can_receive_fire_status():
		_finish()
		return
	if source == null or not is_instance_valid(source):
		_finish()
		return
	if not source.is_multiplayer_authority():
		return
	if not source.is_combat_runtime_active():
		return

	remaining -= delta
	if remaining <= 0.0:
		_finish()
		return

	_tick_left -= delta
	while _tick_left <= 0.0:
		_tick_left += tick_interval
		_deal_tick()


func _deal_tick() -> void:
	if tick_damage <= 0.0 or target == null or not is_instance_valid(target):
		return
	var outgoing:float = source.effective_outgoing_damage(tick_damage)
	if outgoing <= 0.0:
		return
	var applied:bool = target.receive_fire_positional_damage(
		outgoing,
		target.global_position,
		false,
		source,
		{"focus_position":target.global_position}
	)
	if applied and source.has_method("play_bladesmith_burn_tick_sfx"):
		source.call("play_bladesmith_burn_tick_sfx",target.global_position)


func _apply_visual() -> void:
	if target == null or not is_instance_valid(target) or target.image == null or not is_instance_valid(target.image):
		return
	# 只做轻微暖色提示，避免持续伤害把人物整张染红。
	target.image.self_modulate = _base_self_modulate * Color(1.0,0.84,0.70,1.0)


func _finish() -> void:
	if target != null and is_instance_valid(target) and target.image != null and is_instance_valid(target.image):
		target.image.self_modulate = _base_self_modulate
	queue_free()
