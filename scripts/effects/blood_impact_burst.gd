extends Node2D
# Legacy adapter: visual emission now belongs exclusively to the collision-aware emitter.
func configure(_direction:Vector2,_seed_value:int,_scale_value:float) -> void:
	queue_free()
