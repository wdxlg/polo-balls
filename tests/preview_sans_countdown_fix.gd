extends "res://scripts/training/live_sans_final.gd"
func run() -> void:
	screenshots=[0.25,1.65,2.35]
	await super.run()
func _process(delta:float) -> bool:
	for i:int in range(units.size()-1,-1,-1):
		if not is_instance_valid(units[i]): units.remove_at(i)
	var result:bool=super._process(delta)
	if started and elapsed>3.0: finish(0)
	return result
func capture(index:int) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://scripts/training/sans_countdown_fix_%d.png"%index)
