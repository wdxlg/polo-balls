extends "res://classes/ball.gd"
func receive_spatial_raw_health_damage(damage:float,damage_space:Variant) -> bool:
	get_tree().current_scene.set_meta("mc14_execution_amount",damage)
	return super.receive_spatial_raw_health_damage(damage,damage_space)
