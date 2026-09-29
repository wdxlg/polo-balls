extends "res://scripts/characters/我的世界/frontier/warden.gd"
## Exercise the four-slot dispatcher without the world-dependent ritual setup.
var actions:Array[int] = []
func _ready() -> void: pass
func begin_melee() -> bool:
	actions.append(0)
	return true
func begin_sonic() -> bool:
	actions.append(1)
	return true
func begin_probe() -> bool:
	actions.append(2)
	return true
func begin_burrow() -> void:
	actions.append(3)
