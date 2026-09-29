extends "res://scripts/creatures/火车长_列车.gd"
## Keep the real waiting/coal calculation; intercept only the train departure visual.
var test_launches:int = 0
func _launch_from_current_coal() -> void:
	test_launches += 1
	_launch_elapsed = 0.0
	_state = STATE_DEPARTING
