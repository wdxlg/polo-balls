extends "res://scripts/characters/默认/虚无盔甲架.gd"
## A test-only spy on the virtual feedback API; actual contact code remains inherited.
var block_bursts:int = 0
func notify_block_burst_feedback(_impact_position:Vector2,_raw_damage:float,_coverage_width:float,_seed:int) -> void:
	block_bursts += 1
