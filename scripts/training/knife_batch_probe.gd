extends "res://scripts/shooter/knife.gd"
const Batch = preload("res://classes/after_image_render_batch.gd")
func _spawn_after_image_at_transform(t:Transform2D,d:Vector2) -> void:
	if Batch.try_spawn(self,t,d,AFTER_IMAGE_MATERIAL):
		return
	super._spawn_after_image_at_transform(t,d)
