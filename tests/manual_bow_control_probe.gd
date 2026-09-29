extends "res://scripts/characters/我的世界/new6/bow.gd"
## Isolate existing charge/cancel semantics without spawning projectiles in the fixture.
var shots:int = 0
var shot_ratio:float = -1.0
func can_act() -> bool: return true
func _set_draw_audio_stage(_stage:int) -> void: pass
func _fire(ratio:float,_full:bool) -> void:
	shots += 1
	shot_ratio = ratio
	drawing = 0.0
	_cool = cooldown
