extends Node2D

var _anchor:Node2D = null
var _origin_local:Vector2 = Vector2.ZERO
var _normal_local:Vector2 = Vector2.UP
var _streaks:Array = []
var _start_ticks_usec:int = 0
var _end_time:float = 0.0

func _smootherstep01(value:float) -> float:
	var t:float = clampf(value,0.0,1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)

func setup(
	anchor:Node2D,
	world_origin:Vector2,
	world_normal:Vector2,
	impact_speed:float,
	seed:int
) -> void:
	_anchor = anchor
	_origin_local = anchor.to_local(world_origin)
	var safe_world_normal:Vector2 = world_normal.normalized()
	if safe_world_normal.length_squared() <= 0.000001:
		safe_world_normal = Vector2.UP
	# 用两个局部点换算方向，避免角色 scale/rotation 导致法线失真。
	_normal_local = (anchor.to_local(world_origin + safe_world_normal) - _origin_local).normalized()
	if _normal_local.length_squared() <= 0.000001:
		_normal_local = Vector2.UP

	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var speed_ratio:float = clampf(maxf(impact_speed,0.0) / 900.0,0.0,1.0)
	var count:int = 2 + int(round(speed_ratio))
	for i:int in range(count):
		var slot:float = 0.0
		if count > 1:
			slot = lerpf(-1.0,1.0,float(i) / float(count - 1))
		_streaks.append({
			"angle": deg_to_rad(rng.randf_range(-20.0,20.0)),
			"slot": slot * rng.randf_range(0.45,1.35),
			"distance": rng.randf_range(3.0,5.6),
			"length": rng.randf_range(1.4,3.0),
			"width": rng.randf_range(0.28,0.46),
			"duration": rng.randf_range(0.060,0.090),
			"delay": rng.randf_range(0.0,0.004),
		})

func _ready() -> void:
	top_level = true
	z_as_relative = false
	z_index = 46
	global_rotation = 0.0
	global_scale = Vector2.ONE
	_start_ticks_usec = Time.get_ticks_usec()
	if _streaks.is_empty():
		queue_free()
		return
	for index:int in range(_streaks.size()):
		var data:Dictionary = _streaks[index]
		var line := Line2D.new()
		line.name = "UmbrellaHitStreak_%d" % index
		line.width = maxf(float(data.get("width",0.36)),0.18)
		line.default_color = Color(1.0,1.0,1.0,0.0)
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.antialiased = true
		line.points = PackedVector2Array([Vector2.ZERO,Vector2.ZERO])
		line.visible = false
		add_child(line)
		data["line"] = line
		_streaks[index] = data
		_end_time = maxf(_end_time,float(data.get("delay",0.0)) + float(data.get("duration",0.075)))

func _current_world_frame() -> Dictionary:
	if _anchor == null or not is_instance_valid(_anchor):
		return {}
	var origin_world:Vector2 = _anchor.to_global(_origin_local)
	var normal_world:Vector2 = (
		_anchor.to_global(_origin_local + _normal_local) - origin_world
	).normalized()
	if normal_world.length_squared() <= 0.000001:
		normal_world = Vector2.UP
	return {
		"origin": origin_world,
		"normal": normal_world,
		"tangent": Vector2(-normal_world.y,normal_world.x),
	}

func _process(_delta:float) -> void:
	var frame:Dictionary = _current_world_frame()
	if frame.is_empty():
		queue_free()
		return
	global_position = frame["origin"]
	global_rotation = 0.0
	global_scale = Vector2.ONE
	var outward:Vector2 = frame["normal"]
	var tangent:Vector2 = frame["tangent"]
	var elapsed:float = maxf(float(Time.get_ticks_usec() - _start_ticks_usec) / 1000000.0,0.0)

	for data:Dictionary in _streaks:
		var line:Line2D = data.get("line",null) as Line2D
		if line == null or not is_instance_valid(line):
			continue
		var local_time:float = elapsed - float(data.get("delay",0.0))
		var duration:float = maxf(float(data.get("duration",0.075)),0.04)
		if local_time < 0.0 or local_time >= duration:
			line.visible = false
			continue
		line.visible = true
		var progress:float = clampf(local_time / duration,0.0,1.0)
		var direction:Vector2 = outward.rotated(float(data.get("angle",0.0))).normalized()
		if direction.dot(outward) < 0.05:
			direction = (direction + outward * 0.5).normalized()
		var peak_length:float = maxf(float(data.get("length",2.0)),0.8)
		var max_distance:float = maxf(float(data.get("distance",4.0)),peak_length)
		var grow_end:float = 0.24
		var current_length:float = 0.0
		var head_distance:float = 0.0
		var tail_distance:float = 0.0
		if progress <= grow_end:
			var grow_t:float = progress / grow_end
			current_length = peak_length * _smootherstep01(grow_t)
			head_distance = current_length
		else:
			var travel_t:float = (progress - grow_end) / (1.0 - grow_end)
			var curve:float = _smootherstep01(travel_t)
			current_length = peak_length * (1.0 - curve)
			head_distance = peak_length + maxf(max_distance - peak_length,0.0) * curve
			tail_distance = maxf(head_distance - current_length,0.0)
		var spawn_offset:Vector2 = tangent * float(data.get("slot",0.0))
		line.points = PackedVector2Array([
			spawn_offset + direction * tail_distance,
			spawn_offset + direction * head_distance,
		])
		var alpha:float = 1.0
		if progress < 0.10:
			alpha = _smootherstep01(progress / 0.10)
		elif progress > 0.42:
			alpha = 1.0 - _smootherstep01((progress - 0.42) / 0.58)
		line.default_color = Color(1.0,1.0,1.0,alpha)

	if elapsed >= _end_time + 0.01:
		queue_free()
