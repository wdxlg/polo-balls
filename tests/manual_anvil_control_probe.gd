extends "res://scripts/characters/我的世界/铁砧.gd"
## The original anvil _ready needs its exact world setup; dispatch alone is under test.
func _ready() -> void: pass
var manual_slams:int = 0
func begin_slam(_target:ball = null,_chained:bool = false) -> bool:
	manual_slams += 1
	return true
