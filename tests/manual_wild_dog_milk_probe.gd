extends "res://scripts/characters/meme/野生狗奶.gd"
## Keep cooldown/AI selection intact; do not alter Engine.time_scale in tests.
var test_starts:int = 0
func _begin_time_acceleration() -> void:
	test_starts += 1
	_time_active = true
