extends RefCounted
class_name WallHitBurst

const HIT_BURST_EFFECT_SCRIPT = preload("res://scripts/effects/hit_burst_effect.gd")

# 墙面撞击白线：
# - 数量、长度、射出速度主要由撞墙速度决定；高速更多、更长、更快，但都有上限。
# - 起点覆盖范围主要由撞击物体的碰撞横截面决定。
# - 小横截面（子弹）：速度越高，角度扩散越收紧，保持集中。
# - 大横截面（人物/大型物体）：速度越高，角度与墙面覆盖会适度放大，但封顶。
static func spawn(
	parent:Node,
	impact_position:Vector2,
	surface_normal:Vector2,
	impact_speed:float,
	impact_width:float,
	seed:int,
	incoming_direction:Vector2 = Vector2.ZERO
) -> void:
	if parent == null or not is_instance_valid(parent):
		return

	var outward:Vector2 = surface_normal
	if outward.length_squared() <= 0.000001:
		outward = Vector2.RIGHT
	outward = outward.normalized()
	var tangent:Vector2 = Vector2(-outward.y,outward.x)

	# 白线主轴跟随真正的入射方向，而不是永远沿墙法线喷出。
	# 例如子弹向右上撞到水平墙：incoming=右上，burst_axis=左下。
	# surface_normal 只负责保证结果位于墙外侧，以及计算沿墙面的覆盖范围。
	var incoming:Vector2 = incoming_direction
	if incoming.length_squared() <= 0.000001:
		incoming = -outward
	incoming = incoming.normalized()
	var burst_axis:Vector2 = -incoming

	# 正常物理碰撞时 -incoming 应该天然朝墙外；这里仅为异常/穿透查询做保险。
	# 保留入射方向的切向分量，只补足一个很小的向外分量，不退回“平行法线”的旧效果。
	var outward_component:float = burst_axis.dot(outward)
	if outward_component <= 0.02:
		var tangential_component:Vector2 = burst_axis - outward * outward_component
		burst_axis = tangential_component + outward * 0.12
	if burst_axis.length_squared() <= 0.000001:
		burst_axis = outward
	burst_axis = burst_axis.normalized()

	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	# 速度曲线故意比较缓：普通人物撞墙通常只有 2~3 条，高速弹丸约 4 条，
	# 极高速冲刺/投射物才逐渐接近上限 6 条，明显少于旧版。
	var safe_speed:float = maxf(impact_speed,0.0)
	var speed_ratio:float = clampf(safe_speed / 1200.0,0.0,1.0)
	var speed_curve:float = sqrt(speed_ratio)
	var count:int = clampi(1 + int(round(speed_curve * 5.0)),2,6)

	# impact_width 是撞击物体沿墙面切线方向的碰撞横截面宽度。
	# 约 6px 视为小弹丸，约 42px 及以上视为大型撞击物。
	var width:float = clampf(impact_width,2.0,80.0)
	var size_ratio:float = clampf((width - 6.0) / 36.0,0.0,1.0)

	# 小物体：越快越集中；大物体：越快扩散越明显，但最大限制在 56 度。
	var small_spread_degrees:float = lerpf(22.0,6.0,speed_curve)
	var large_spread_degrees:float = lerpf(28.0,56.0,speed_curve)
	var spread_degrees:float = clampf(
		lerpf(small_spread_degrees,large_spread_degrees,size_ratio),
		5.0,
		56.0
	)

	# 起点沿墙面的覆盖也由体积控制。
	# 小弹丸高速时进一步收紧；大体积高速时会铺得更开，但最多覆盖约 48px 宽。
	var small_range_scale:float = lerpf(0.82,0.48,speed_curve)
	var large_range_scale:float = lerpf(0.90,1.20,speed_curve)
	var range_scale:float = lerpf(small_range_scale,large_range_scale,size_ratio)
	var spawn_half_range:float = clampf(width * 0.45 * range_scale,0.45,24.0)

	# 高速撞击：线更长、飞得更远，持续时间仅小幅缩短。
	# 动画包络与人物受击统一：明显渐入 -> 变长 -> 变短 -> 渐隐；同时仍使用真实时间。
	var base_distance:float = lerpf(10.0,44.0,speed_curve)
	var base_length:float = lerpf(3.8,17.0,speed_curve)
	var base_duration:float = lerpf(0.34,0.26,speed_curve)

	var streaks:Array = []
	for _index:int in range(count):
		var angle_offset:float = deg_to_rad(rng.randf_range(-spread_degrees,spread_degrees))
		var streak_direction:Vector2 = burst_axis.rotated(angle_offset).normalized()
		# 极端随机角度也不允许把线重新转进墙体内部。
		if streak_direction.dot(outward) <= 0.0:
			var tangent_part:Vector2 = streak_direction - outward * streak_direction.dot(outward)
			streak_direction = (tangent_part + outward * 0.04).normalized()
		var distance:float = base_distance * rng.randf_range(0.82,1.12)
		var length:float = base_length * rng.randf_range(0.72,1.16)
		var line_width:float = rng.randf_range(0.34,0.66) * lerpf(0.92,1.08,speed_curve)
		var duration:float = base_duration * rng.randf_range(0.90,1.10)
		var delay:float = rng.randf_range(0.0,lerpf(0.004,0.001,speed_curve))

		# 白线仍按碰撞横截面沿墙面铺开，但不能让少量线条随机全部落到同一侧。
		# 使用对称槽位 + 很小的槽内抖动：2 条一左一右，3 条会有一条靠近中心，
		# 因此整个白线簇的视觉中心始终贴着真实撞击位置。
		var slot_ratio:float = 0.0
		if count > 1:
			slot_ratio = lerpf(-1.0,1.0,float(_index) / float(count - 1))
		var slot_step:float = (spawn_half_range * 2.0) / maxf(float(count - 1),1.0)
		var jitter:float = rng.randf_range(-0.10,0.10) * slot_step
		var tangent_offset:float = clampf(
			spawn_half_range * slot_ratio + jitter,
			-spawn_half_range,
			spawn_half_range
		)
		var spawn_offset:Vector2 = tangent * tangent_offset

		streaks.append({
			"spawn_offset": spawn_offset,
			"direction": streak_direction,
			"distance": distance,
			"length": length,
			"width": line_width,
			"duration": duration,
			"delay": delay,
			"grow_end": 0.32,
			"fade_in_end": 0.12,
			"fade_out_start": 0.52,
			"anchored_origin_motion": true,
			"use_real_time": true,
			"color": Color.WHITE,
		})

	var effect = HIT_BURST_EFFECT_SCRIPT.new()
	effect.name = "WallHitBurst_%d" % seed
	effect.setup(impact_position,streaks)
	parent.add_child(effect)
