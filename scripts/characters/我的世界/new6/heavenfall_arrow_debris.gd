extends "res://scripts/effects/我的世界/重锤落地冲击.gd"
## 天堂陨落箭矢：同一套真实地板采样、方块生成和抛物绘制；只换可调参数。
## 不另外实现采样/方块运动；无冲击圈和放射线。
func _init() -> void:
	show_impact_ring = false
	show_impact_streaks = false
	lifetime = 0.45
	block_source_min_count = 4
	block_source_max_count = 6
	blocks_per_source_min = 4
	blocks_per_source_max = 7
	block_source_scatter = 2.2
	block_source_center_bias_exponent = 1.7
	block_source_radius_min_scale = 1.0
	block_source_radius_max_scale = 1.0
	block_min_size = 1.0
	block_max_size = 3.0
	block_min_flight_time = 0.34
	block_max_flight_time = 0.62
	block_min_ground_hold = 0.18
	block_max_ground_hold = 0.60
	block_travel_min = 1.5
	block_travel_max = 4.5
	block_travel_edge_factor = 0.55
	block_landing_jitter = 2.0
	block_delay_max = 0.055
	block_center_height = 66.0
	block_edge_height = 12.0
	block_height_falloff = 1.35

func setup(world_position:Vector2,radius:float) -> void:
	await super.setup(world_position,maxf(radius,6.0))
