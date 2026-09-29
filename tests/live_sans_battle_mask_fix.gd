extends "res://scripts/training/live_sans_final.gd"
func _process(delta:float) -> bool:
	for i:int in range(units.size()-1,-1,-1):
		if not is_instance_valid(units[i]): units.remove_at(i)
	return super._process(delta)
func capture(index:int) -> void:
	await RenderingServer.frame_post_draw
	if not is_instance_valid(phase): return
	if world.versus_label.visible or world.interaction_label.visible or world._center_watermark_root.visible:
		failures+=1
		print("HUD_VISIBILITY_FAIL stage=",index)
	if phase.in_temp:
		if world.map_island_rects(phase.temp_map).is_empty():
			failures+=1
			print("ARENA_REGION_FAIL stage=",index)
		for mask:Polygon2D in world.map_outside_mask_parts:
			if mask.visible and Geometry2D.is_point_in_polygon(mask.to_local(phase.arena_rect.get_center()),mask.polygon):
				failures+=1
				print("MASK_OVERLAP_FAIL stage=",index)
	root.get_texture().get_image().save_png("res://scripts/training/sans_battle_mask_fix_%d.png"%index)
