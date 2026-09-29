extends "res://scripts/characters/面包车.gd"
## Preserve real gear/speed/cooldown checks while avoiding extra combatants.
var test_spawns:int = 0
func _spawn_random_van_minion() -> bool:
	test_spawns += 1
	return true
