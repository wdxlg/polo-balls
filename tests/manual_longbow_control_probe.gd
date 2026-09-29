extends "res://scripts/characters/我的世界/new6/heavenfall_longbow.gd"
## Count windup completions without creating networked bolts/rifts.
var shots:int = 0
func can_act() -> bool: return true
func _fire() -> void: shots += 1
