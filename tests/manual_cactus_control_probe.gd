extends "res://scripts/characters/我的世界/cactus_note/cactus.gd"
var manual_volleys:int = 0
func fire_thorns() -> bool:
	manual_volleys += 1
	return true
