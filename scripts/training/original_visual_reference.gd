extends RefCounted

func sample(
	unit:Node,
	rng:RandomNumberGenerator,
	force_white:bool,
	outward:Vector2,
	character_radius:float,
	coverage_ratio:float
) -> Dictionary:
	var visual_rect:Rect2 = unit._hit_effect_visual_rect()
	var chosen_color:Color = Color.WHITE if force_white else unit._fallback_hit_effect_color()
	var chosen_world:Vector2 = unit.global_position + outward * maxf(character_radius * 0.72,5.0)

	# 起点始终在“攻击穿过人物后的背面”。
	# 同时让覆盖范围影响背面出生点的横向分布：
	# - 小范围命中集中在背面中心附近；
	# - 大范围命中可以铺到更宽的背侧轮廓。
	if visual_rect.size.x > 0.001 and visual_rect.size.y > 0.001:
		var tangent:Vector2 = Vector2(-outward.y,outward.x).normalized()
		var lateral_extent:float = character_radius * lerpf(0.18,0.92,coverage_ratio)
		var target_lateral:float = rng.randf_range(-lateral_extent,lateral_extent)
		var best_score:float = -INF
		var rear_threshold:float = maxf(character_radius * 0.12,1.5)
		var lateral_weight:float = lerpf(1.65,0.52,coverage_ratio)

		for _attempt:int in range(44):
			var local_point := Vector2(
				rng.randf_range(visual_rect.position.x,visual_rect.end.x),
				rng.randf_range(visual_rect.position.y,visual_rect.end.y)
			)
			var sampled:Color = unit._sample_current_visual_pixel(local_point)
			if sampled.a <= 0.10:
				continue

			var world_point:Vector2 = unit.image.to_global(local_point)
			var relative_point:Vector2 = world_point - unit.global_position
			var rear_projection:float = relative_point.dot(outward)
			if rear_projection < rear_threshold:
				continue

			var lateral_projection:float = relative_point.dot(tangent)
			var lateral_error:float = absf(lateral_projection - target_lateral)
			var score:float = (
				rear_projection
				- lateral_error * lateral_weight
				+ rng.randf_range(0.0,maxf(character_radius * 0.18,1.5))
			)
			if score <= best_score:
				continue

			best_score = score
			chosen_world = world_point
			chosen_color = Color.WHITE if force_white else sampled

	return {
		"spawn_offset": chosen_world - unit.global_position,
		"color": chosen_color,
	}


