extends "res://scripts/training/live_sans_final.gd"
var hop_seen:bool = false
var arc_seen:bool = false
var group_seen:bool = false
func _process(delta:float) -> bool:
	if started and is_instance_valid(phase):
		if phase.elapsed > 1.5 and phase.elapsed < 7.5:
			for unit:Node2D in units:
				var gravity:Vector2 = unit.get_external_directional_gravity()
				if gravity.length_squared() > 0.0 and unit.get_external_directional_gravity_velocity().dot(gravity.normalized()) < -5.0:
					hop_seen = true
		if phase.elapsed >= 15.0 and not arc_seen:
			arc_seen = true
			print("FEEDBACK_ARC count=",phase.hazards.size()," VS=",world.versus_label.visible," graphics_z=",sans.graphics.z_index)
		if phase.elapsed >= 22.0 and not group_seen:
			group_seen = true
			print("FEEDBACK_GROUPS count=",phase.hazards.size()," opening_hop=",hop_seen)
	return super._process(delta)
func finish(code:int) -> void:
	print("FEEDBACK_PHYSICS jump=",hop_seen," arc=",arc_seen," groups=",group_seen)
	if started and not hop_seen:
		code = 1
	started = false
	if is_instance_valid(phase):
		phase.finish(false)
	if game != null:
		game.Game_Settings = saved
		game.now_stop_state = saved_stop
	# 让渲染/物理服务器先处理节点释放，再退出引擎，避免退出帧资源仍在使用。
	if is_instance_valid(world):
		world.queue_free()
	current_scene = null
	await process_frame
	await process_frame
	print("FEEDBACK_EXIT code=",code)
	quit(code)
