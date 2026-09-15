extends "res://classes/ai_original_base.gd"
var _quiet_time:float = 0.0
var _block_fraction:float = 0.0
var _guard_left:float = 0.0
var _stored:float = 0.0
func _ready() -> void:
	super._ready()
	block = max_block
func take_damage(damage:float,ignore_block:bool = false) -> void:
	var old_health:float = health
	var old_block:float = block
	if _guard_left > 0.0 and damage > 0.0:
		_stored = minf(_stored + damage * 0.45 * (1.0 - Damage_reduction),80.0)
		damage *= 0.55
	super.take_damage(damage,ignore_block)
	if health < old_health or block < old_block:
		_quiet_time = 0.0
func _tick_trait(delta:float) -> void:
	_quiet_time += delta
	if _quiet_time >= 4.0 and block < max_block:
		_block_fraction += 18.0 * delta
		var gain:int = int(_block_fraction)
		if gain > 0:
			block += gain
			_block_fraction -= gain
	if _guard_left <= 0.0:
		return
	if dizziness or not Using_Skill:
		_guard_left = 0.0
		Using_Skill = false
		_stored = 0.0
		return
	_guard_left = maxf(_guard_left - delta,0.0)
	if _guard_left == 0.0:
		effect(1,global_position,global_position,105.0,0.35)
		for target:ball in enemies_near(global_position,105.0):
			if clear_line(target.global_position):
				deal(target,1.0 + _stored * 0.35 / maxf(float(Damage),1.0))
		_stored = 0.0
		Using_Skill = false
func Attack() -> void:
	super.Attack()
	if not is_multiplayer_authority() or not is_combat_runtime_active():
		return
	var target:ball = nearest_opponent()
	if target == null:
		return
	var point:Vector2 = target.global_position
	var generation:int = begin_action()
	effect(0,global_position,point,28.0,0.22)
	if await windup(0.22,generation):
		effect(1,point,point,32.0,0.22)
		if enemy_valid(target) and target.global_position.distance_to(point) <= 35.0 and global_position.distance_to(target.global_position) <= engagement_range and clear_line(target.global_position):
			deal(target)
	finish_action(generation)
func Skill() -> void:
	if not is_multiplayer_authority() or not is_combat_runtime_active() or is_damage_output_disabled():
		return
	begin_action(true)
	_guard_left = 0.9
	_stored = 0.0
	effect(4,global_position,global_position,48.0,0.9)

func skill_available() -> bool:
	return not enemies_near(global_position,130.0).is_empty()
