extends "res://scripts/effects/knockback_effect.gd"
var impact_damage_per_speed:float=0.055
var impact_stun_per_speed:float=0.002
func _handle_wall_collision(normal:Vector2,impact_position:Vector2) -> bool:
	# Read actual remaining velocity, not the initial launch velocity.
	collision_damage=maxf(_current_speed,0.0)*impact_damage_per_speed
	stun_duration=clampf(_current_speed*impact_stun_per_speed,0.08,0.75)
	return super._handle_wall_collision(normal,impact_position)
