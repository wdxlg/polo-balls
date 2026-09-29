extends Node2D

# 重锤落地视觉：保留原有白色范围圈/爆射线，同时加入 Minecraft 风格的地面方块碎屑。
# 方块碎屑先在真实攻击范围内选若干“地板采样点”，再从每个采样点附近喷出多块粒子。
# 每一组粒子的基色来自对应地板位置的像素颜色，再做轻微明暗扰动。

const FLOOR_SAMPLER:Script = preload("res://scripts/effects/地表渲染采样.gd")

@export_range(0.18,0.90,0.01) var lifetime:float = 0.46
@export_range(1.05,2.20,0.05) var ring_end_scale:float = 1.58
@export_range(6,28,1) var line_min_count:int = 10
@export_range(6,32,1) var line_max_count:int = 15

@export_category("重锤 / 地面方块粒子")
@export_range(3,12,1) var block_source_min_count:int = 5
@export_range(3,14,1) var block_source_max_count:int = 8
@export_range(3,16,1) var blocks_per_source_min:int = 6
@export_range(3,20,1) var blocks_per_source_max:int = 10
@export_range(1.0,12.0,0.5) var block_source_scatter:float = 5.0
@export_range(0.5,8.0,0.25) var block_min_size:float = 1.2
@export_range(0.5,10.0,0.25) var block_max_size:float = 3.6
@export_range(4.0,80.0,1.0) var block_min_height:float = 13.0
@export_range(4.0,100.0,1.0) var block_max_height:float = 42.0
@export_range(0.20,1.20,0.01) var block_min_flight_time:float = 0.34
@export_range(0.20,1.40,0.01) var block_max_flight_time:float = 0.68
@export_range(0.0,1.50,0.01) var block_min_ground_hold:float = 0.20
@export_range(0.0,1.80,0.01) var block_max_ground_hold:float = 0.72

@export_category("共用落地冲击 / 选装组件")
@export var show_impact_ring:bool = true
@export var show_impact_streaks:bool = true
@export_range(0.0,4.0,0.05) var block_source_center_bias_exponent:float = 0.0 # 0=沿用重锤均匀散布
@export var block_source_radius_min_scale:float = 0.48
@export var block_source_radius_max_scale:float = 0.88
@export var block_travel_min:float = 7.0
@export var block_travel_max:float = -1.0 # -1=根据影响半径自动选取
@export var block_travel_edge_factor:float = 1.0
@export var block_landing_jitter:float = 4.0
@export var block_delay_max:float = 0.065
@export var block_center_height:float = 0.0 # 0=沿用重锤随机高度
@export var block_edge_height:float = 12.0
@export var block_height_falloff:float = 1.35

var _ring_palette:PackedColorArray = PackedColorArray([Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE])

var _elapsed:float = 0.0
var _radius:float = 42.0
var _rng := RandomNumberGenerator.new()
var _streaks:Array[Dictionary] = []
var _blocks:Array[Dictionary] = []
var _effect_end_time:float = 0.46
var _floor_snapshot:Dictionary = {}


func setup(world_position:Vector2,radius:float) -> void:
	global_position = world_position
	_radius = maxf(radius,8.0)
	z_as_relative = false
	z_index = 98
	_rng.seed = Game.battle_rng_seed_or("scripts/effects/我的世界/重锤落地冲击.gd:_rng.seed",maxi(abs(int(world_position.x * 92821.0) ^ int(world_position.y * 68917.0) ^ int(Time.get_ticks_usec())),1))
	_build_streaks()
	queue_redraw()
	# 圈/射线立即显示，只有碎屑等待地表完成一帧渲染。
	set_process(false)
	await _prepare_floor_sampler()
	if not is_inside_tree(): return
	if not _floor_snapshot.is_empty(): _build_block_particles()
	set_process(true)
	queue_redraw()


func _prepare_floor_sampler() -> void:
	_floor_snapshot = {}
	var world:Node = get_tree().current_scene if get_tree() != null else null
	if world == null: return
	var sampler:Node = world.get_node_or_null("GroundSurfaceSampler")
	if sampler == null:
		sampler = FLOOR_SAMPLER.new()
		sampler.name = "GroundSurfaceSampler"
		world.add_child(sampler)
	_floor_snapshot = await sampler.capture(_current_map_rect())


func _build_streaks() -> void:
	_streaks.clear()
	if not show_impact_streaks: return
	var low:int = mini(line_min_count,line_max_count)
	var high:int = maxi(line_min_count,line_max_count)
	var count:int = _rng.randi_range(maxi(low,1),maxi(high,maxi(low,1)))
	for i:int in range(count):
		var angle:float = float(i) * 2.39996323 + _rng.randf_range(-0.52,0.52)
		var direction:Vector2 = Vector2.RIGHT.rotated(angle)
		_streaks.append({
			"direction": direction,
			"delay": _rng.randf_range(0.0,0.045),
			"start_radius": _radius * _rng.randf_range(0.08,0.30),
			"travel": _radius * _rng.randf_range(0.88,1.65),
			"length": _radius * _rng.randf_range(0.32,0.72),
			"width": _rng.randf_range(0.75,1.45),
		})


func _build_block_particles() -> void:
	_blocks.clear()
	_effect_end_time = maxf(lifetime,0.02)
	var source_low:int = mini(block_source_min_count,block_source_max_count)
	var source_high:int = maxi(block_source_min_count,block_source_max_count)
	var source_count:int = _rng.randi_range(maxi(source_low,1),maxi(source_high,maxi(source_low,1)))
	var per_low:int = mini(blocks_per_source_min,blocks_per_source_max)
	var per_high:int = maxi(blocks_per_source_min,blocks_per_source_max)
	var map_rect:Rect2 = _current_map_rect()

	for source_index:int in range(source_count):
		# sqrt(rand) 让采样点在面积上均匀，而不是全部挤在中心。
		var source_angle:float = TAU * (float(source_index) / float(maxi(source_count,1))) + _rng.randf_range(-0.52,0.52)
		var radial:float = pow(_rng.randf_range(0.0,1.0),block_source_center_bias_exponent) if block_source_center_bias_exponent>0.0 else sqrt(_rng.randf_range(0.05,1.0))
		var source_radius:float = radial * _radius * _rng.randf_range(block_source_radius_min_scale,block_source_radius_max_scale)
		var source_world:Vector2 = global_position + Vector2.RIGHT.rotated(source_angle) * source_radius
		if map_rect.size.x > 1.0 and map_rect.size.y > 1.0:
			source_world.x = clampf(source_world.x,map_rect.position.x + 1.0,map_rect.end.x - 1.0)
			source_world.y = clampf(source_world.y,map_rect.position.y + 1.0,map_rect.end.y - 1.0)
		var source_local:Vector2 = source_world - global_position
		var particle_count:int = _rng.randi_range(maxi(per_low,1),maxi(per_high,maxi(per_low,1)))

		for _particle_index:int in range(particle_count):
			var scatter:Vector2 = Vector2(
				_rng.randf_range(-block_source_scatter,block_source_scatter),
				_rng.randf_range(-block_source_scatter,block_source_scatter)
			)
			var start:Vector2 = source_local + scatter
			if map_rect.size.x > 1.0 and map_rect.size.y > 1.0:
				var start_world:Vector2 = (global_position+start).clamp(map_rect.position+Vector2.ONE,map_rect.end-Vector2.ONE)
				start = start_world-global_position
			var outward:Vector2 = start
			if outward.length_squared() <= 0.000001:
				outward = Vector2.RIGHT.rotated(_rng.randf_range(0.0,TAU))
			outward = outward.normalized().rotated(_rng.randf_range(-0.55,0.55))
			var center_weight:float = pow(1.0-clampf(start.length()/maxf(_radius,1.0),0.0,1.0),block_height_falloff)
			var travel:float = _rng.randf_range(block_travel_min,maxf(block_travel_min,block_travel_max if block_travel_max>=0.0 else maxf(12.0,_radius*0.36)))
			travel *= lerpf(block_travel_edge_factor,1.0,center_weight)
			var landing:Vector2 = start + outward * travel + Vector2(
				_rng.randf_range(-block_landing_jitter,block_landing_jitter),
				_rng.randf_range(-block_landing_jitter,block_landing_jitter)
			)
			var landing_world:Vector2 = global_position + landing
			if map_rect.size.x > 1.0 and map_rect.size.y > 1.0:
				landing_world.x = clampf(landing_world.x,map_rect.position.x + 1.0,map_rect.end.x - 1.0)
				landing_world.y = clampf(landing_world.y,map_rect.position.y + 1.0,map_rect.end.y - 1.0)
				landing = landing_world - global_position

			var size_value:float = _rng.randf_range(minf(block_min_size,block_max_size),maxf(block_min_size,block_max_size))
			var flight_time:float = _rng.randf_range(minf(block_min_flight_time,block_max_flight_time),maxf(block_min_flight_time,block_max_flight_time))
			var hold_time:float = _rng.randf_range(minf(block_min_ground_hold,block_max_ground_hold),maxf(block_min_ground_hold,block_max_ground_hold))
			var fade_time:float = _rng.randf_range(0.18,0.38)
			var delay:float = _rng.randf_range(0.0,block_delay_max)
			var height_value:float = lerpf(block_edge_height,block_center_height,center_weight)*_rng.randf_range(0.82,1.22) if block_center_height>0.0 else _rng.randf_range(minf(block_min_height,block_max_height),maxf(block_min_height,block_max_height))
			# 每一颗碎屑都按它自己的真实出生点重新取当前地板像素。
			# 这样来源点跨过蠹虫石砖/破洞边界时，同一簇里也能正确出现石砖色与原背景色。
			var sampled:Color = _sample_floor_color(global_position + start)
			if sampled.a <= 0.001: continue
			var color_value:Color = _vary_floor_color(sampled)
			var total_time:float = delay + flight_time + hold_time + fade_time
			_effect_end_time = maxf(_effect_end_time,total_time)
			_blocks.append({
				"start": start,
				"landing": landing,
				"size": size_value,
				"height": height_value,
				"delay": delay,
				"flight": flight_time,
				"rise_ratio": _rng.randf_range(0.42,0.50),
				"hold": hold_time,
				"fade": fade_time,
				"rotation": 0.0,
				"spin": 0.0,
				"color": color_value,
			})


func _current_map_rect() -> Rect2:
	var world:Node = get_tree().current_scene if get_tree() != null else null
	if world != null and world.has_method("_get_center_watermark_map_rect"):
		var value:Variant = world.call("_get_center_watermark_map_rect")
		if typeof(value) == TYPE_RECT2:
			return value
	return Rect2()


func _sample_floor_color(world_position:Vector2) -> Color:
	var image:Image = _floor_snapshot.get("image")
	var rect:Rect2 = _floor_snapshot.get("rect",Rect2())
	if image == null or rect.size.x <= 0.0 or rect.size.y <= 0.0: return Color.TRANSPARENT
	var uv:Vector2 = (world_position-rect.position)/rect.size
	var x:int = clampi(int(floor(uv.x*image.get_width())),0,image.get_width()-1)
	var y:int = clampi(int(floor(uv.y*image.get_height())),0,image.get_height()-1)
	return image.get_pixel(x,y)


func _vary_floor_color(base:Color) -> Color:
	var amount:float = _rng.randf_range(-0.22,0.22)
	var target:Color = Color.BLACK if amount < 0.0 else Color.WHITE
	var result:Color = base.lerp(target,absf(amount))
	result.a = 1.0
	return result


func _process(delta:float) -> void:
	_elapsed += maxf(delta,0.0)
	queue_redraw()
	if _elapsed >= maxf(_effect_end_time,0.02):
		queue_free()


func _draw() -> void:
	_draw_ring_and_streaks()
	_draw_block_particles()


func _ring_color(index:int,alpha:float) -> Color:
	var result:Color = _ring_palette[index] if index < _ring_palette.size() else Color.WHITE
	result.a *= alpha
	return result


func _draw_ring_and_streaks() -> void:
	var p:float = clampf(_elapsed / maxf(lifetime,0.02),0.0,1.0)
	if show_impact_ring and p < 1.0:
		var expand:float = 1.0 - pow(1.0 - p,3.1)
		var alpha:float = pow(1.0 - p,1.28)
		var radius_value:float = lerpf(_radius,_radius * maxf(ring_end_scale,1.0),expand)
		preload("res://scripts/effects/我的世界/pixel_arc.gd").draw_ring(self,Vector2.ZERO,radius_value,Color.WHITE,alpha,_ring_palette)

	if not show_impact_streaks: return
	for data:Dictionary in _streaks:
		var delay:float = float(data.get("delay",0.0))
		var local_elapsed:float = _elapsed - delay
		if local_elapsed <= 0.0:
			continue
		var line_life:float = maxf(lifetime - delay,0.04)
		var q:float = clampf(local_elapsed / line_life,0.0,1.0)
		if q >= 1.0:
			continue
		var move_t:float = 1.0 - pow(1.0 - q,2.8)
		var grow_t:float = clampf(q / 0.18,0.0,1.0)
		var fade:float = pow(1.0 - q,1.45)
		var direction:Vector2 = data.get("direction",Vector2.RIGHT)
		var start_radius:float = float(data.get("start_radius",0.0))
		var travel:float = float(data.get("travel",_radius))
		var line_length:float = float(data.get("length",_radius * 0.45)) * grow_t
		var start:Vector2 = direction * (start_radius + travel * move_t)
		var finish:Vector2 = start + direction * line_length
		var width:float = float(data.get("width",1.0))
		draw_line(start,finish,_ring_color(3,0.95 * fade),width,true)


func _draw_block_particles() -> void:
	for data:Dictionary in _blocks:
		var delay:float = float(data.get("delay",0.0))
		var age:float = _elapsed - delay
		if age < 0.0:
			continue
		var flight:float = maxf(float(data.get("flight",0.4)),0.05)
		var hold:float = maxf(float(data.get("hold",0.3)),0.0)
		var fade_time:float = maxf(float(data.get("fade",0.25)),0.02)
		if age >= flight + hold + fade_time:
			continue
		var start:Vector2 = data.get("start",Vector2.ZERO)
		var landing:Vector2 = data.get("landing",start)
		var center:Vector2 = landing
		var height_value:float = 0.0
		var rotation_value:float = 0.0
		var alpha:float = 1.0

		if age < flight:
			var t:float = clampf(age / flight,0.0,1.0)
			var ground_t:float = 1.0 - pow(1.0 - t,2.2)
			center = start.lerp(landing,ground_t)
			var rise_ratio:float = clampf(float(data.get("rise_ratio",0.46)),0.20,0.80)
			var max_height:float = maxf(float(data.get("height",20.0)),0.0)
			if t <= rise_ratio:
				var rise_t:float = clampf(t / maxf(rise_ratio,0.001),0.0,1.0)
				height_value = (1.0 - pow(1.0 - rise_t,3.0)) * max_height
			else:
				var fall_t:float = clampf((t - rise_ratio) / maxf(1.0 - rise_ratio,0.001),0.0,1.0)
				height_value = (1.0 - pow(fall_t,3.0)) * max_height
		else:
			var fade_age:float = age - flight - hold
			if fade_age > 0.0:
				alpha = 1.0 - clampf(fade_age / fade_time,0.0,1.0)

		center.y -= height_value
		var size_value:float = maxf(float(data.get("size",4.0)),1.0)
		var color_value:Color = data.get("color",Color.WHITE)
		color_value.a *= alpha
		_draw_rotated_block(center,size_value,rotation_value,color_value)


func _draw_rotated_block(center:Vector2,size_value:float,rotation_value:float,color_value:Color) -> void:
	var half:float = size_value * 0.5
	var axis_x:Vector2 = Vector2(cos(rotation_value),sin(rotation_value)) * half
	var axis_y:Vector2 = Vector2(-sin(rotation_value),cos(rotation_value)) * half
	var points:=PackedVector2Array([
		center - axis_x - axis_y,
		center + axis_x - axis_y,
		center + axis_x + axis_y,
		center - axis_x + axis_y,
	])
	draw_colored_polygon(points,color_value)
