extends "res://scripts/training/live_sans_feedback.gd"
var killed:bool = false
var black_seen:bool = false
var returned_under_black:bool = false
func _process(delta:float) -> bool:
	if not started:
		return false
	elapsed += delta
	if elapsed >= 3.0 and not killed:
		killed = true
		for unit:Node2D in units:
			unit.take_damage(10000000.0,true)
	if killed and is_instance_valid(phase):
		if phase.black.color.a >= 0.99:
			black_seen = true
			if not phase.in_temp:
				returned_under_black = true
	if killed and elapsed >= 5.0:
		var ok:bool = black_seen and returned_under_black and world.now_choose_map == "Map50x50" and not sans._last_trial_active
		print("DEATH_REAL black=",black_seen," return_under_black=",returned_under_black," restored=",world.now_choose_map," immune=",sans._last_trial_active)
		hop_seen = true # 此测试不评估跳跃；由 live_sans_feedback 独立验证。
		finish(0 if ok else 1)
	return false
