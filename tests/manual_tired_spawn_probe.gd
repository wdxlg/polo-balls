extends "res://scripts/characters/人物/疲倦的人.gd"
## Preserve the volley target gate and direction; intercept projectile creation.
var test_directions:Array[Vector2] = []
func _spawn_z(direction_value:Vector2) -> void:
	test_directions.append(direction_value)
