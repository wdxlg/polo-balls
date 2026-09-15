extends Node2D

# 重女第二形态视觉。
# 黑洞外形恢复早期版本：同一圈 32 段轮廓持续扭曲变化；内部跟随轮廓实时填成纯黑。
# 白线从地图边界之外出生，保持现有长度/粗细，只减少数量，然后一路被吸进黑洞并切碎消失。

var active:bool = false
var shape_radius:float = 105.0
var _spawn_accumulator:float = 0.0
var _segments:Array[Dictionary] = []
var _map_rect_world:Rect2 = Rect2()

const OUTLINE_COLOR := Color(0.15,0.05,0.22,0.85)
const OUTLINE_WIDTH:float = 3.0
const WOBBLE_AMOUNT:float = 5.0
const WOBBLE_TIME_SCALE:float = 0.006
const WOBBLE_LOBES:float = 5.0

# 数量比上一版进一步降低，但不改每根线本身的长度和粗细。
const LINE_SPAWN_INTERVAL:float = 0.34
const MAX_LINES:int = 12

func configure(p_shape_radius:float,_unused_outer_radius:float = 0.0) -> void:
	shape_radius = maxf(p_shape_radius,20.0)
	queue_redraw()

func set_map_rect(rect:Rect2) -> void:
	_map_rect_world = rect

func set_active(enabled:bool) -> void:
	active = enabled
	visible = enabled
	set_process(enabled)
	if not enabled:
		_segments.clear()
		_spawn_accumulator = 0.0
	queue_redraw()

func _ready() -> void:
	z_index = 0
	z_as_relative = true
	set_process(false)
	visible = false

func _process(delta:float) -> void:
	if not active:
		return

	_spawn_accumulator += delta
	if _map_rect_world.size.x > 1.0 and _map_rect_world.size.y > 1.0:
		var spawned:int = 0
		while _spawn_accumulator >= LINE_SPAWN_INTERVAL and spawned < 2:
			_spawn_accumulator -= LINE_SPAWN_INTERVAL
			_spawn_segment_from_outside_map()
			spawned += 1

	_update_segments(delta)
	queue_redraw()

func _spawn_segment_from_outside_map() -> void:
	if _segments.size() >= MAX_LINES:
		return
	if _map_rect_world.size.x <= 1.0 or _map_rect_world.size.y <= 1.0:
		return

	var rect:Rect2 = _map_rect_world
	var margin:float = randf_range(18.0,42.0)
	var spawn_world:Vector2
	match randi() % 4:
		0:
			spawn_world = Vector2(randf_range(rect.position.x,rect.end.x),rect.position.y - margin)
		1:
			spawn_world = Vector2(randf_range(rect.position.x,rect.end.x),rect.end.y + margin)
		2:
			spawn_world = Vector2(rect.position.x - margin,randf_range(rect.position.y,rect.end.y))
		_:
			spawn_world = Vector2(rect.end.x + margin,randf_range(rect.position.y,rect.end.y))

	_segments.append({
		"world_position": spawn_world,
		"speed": randf_range(150.0,235.0),
		"curve_phase": randf_range(0.0,TAU),
		"curve_speed": randf_range(1.4,3.1) * (-1.0 if randf() < 0.5 else 1.0),
		# 保持 V11 的白线尺寸，不再缩短/变细基础尺寸。
		"length": randf_range(5.0,16.0),
		"width": randf_range(0.45,0.90),
		"alpha": randf_range(0.50,0.88),
		"pulse": randf_range(0.0,TAU),
		"pulse_speed": randf_range(2.0,4.8),
	})

func _update_segments(delta:float) -> void:
	var center_world:Vector2 = global_position
	var map_span:float = maxf(maxf(_map_rect_world.size.x,_map_rect_world.size.y),shape_radius * 4.0)

	for index:int in range(_segments.size() - 1,-1,-1):
		var item:Dictionary = _segments[index]
		var pos:Vector2 = item["world_position"]
		var to_center:Vector2 = center_world - pos
		var distance:float = to_center.length()
		var local_distance:float = to_local(pos).length()
		if local_distance <= shape_radius * 0.08:
			_segments.remove_at(index)
			continue

		var inward:Vector2 = to_center / maxf(distance,0.001)
		var tangent:Vector2 = inward.orthogonal()
		var phase:float = float(item["curve_phase"]) + float(item["curve_speed"]) * delta
		item["curve_phase"] = phase
		item["pulse"] = float(item["pulse"]) + float(item["pulse_speed"]) * delta

		# 从地图外一路弯向黑洞；越接近黑洞，吸入速度和弯曲感稍微增强。
		var proximity:float = clampf(1.0 - distance / maxf(map_span,1.0),0.0,1.0)
		var curved_dir:Vector2 = (inward + tangent * sin(phase) * (0.07 + proximity * 0.12)).normalized()
		var move_speed:float = float(item["speed"]) * (0.88 + proximity * 0.58)
		item["world_position"] = pos + curved_dir * move_speed * delta
		_segments[index] = item

func _shape_points(include_closing_point:bool) -> PackedVector2Array:
	var result := PackedVector2Array()
	var point_count:int = 33 if include_closing_point else 32
	var time_value:float = float(Time.get_ticks_msec()) * WOBBLE_TIME_SCALE
	for i:int in range(point_count):
		var a:float = TAU * float(i) / 32.0
		# 与早期版本相同的轮廓动画：整体持续扭曲/起伏，而不是固定圆。
		var wobble:float = WOBBLE_AMOUNT * sin(time_value + a * WOBBLE_LOBES)
		result.append(Vector2.from_angle(a) * (shape_radius + wobble))
	return result

func _draw() -> void:
	if not active:
		return

	# 使用同一组不断变化的点：先填黑，再画原来的紫色扭曲边缘。
	# 因此黑洞形状/动画和早期版本一致，只补上了内部填充。
	var fill_points:PackedVector2Array = _shape_points(false)
	var outline_points:PackedVector2Array = _shape_points(true)
	draw_colored_polygon(fill_points,Color(0.0,0.0,0.0,1.0))
	draw_polyline(outline_points,OUTLINE_COLOR,OUTLINE_WIDTH,true)

	for item:Dictionary in _segments:
		_draw_absorbed_segment(item)

func _draw_absorbed_segment(item:Dictionary) -> void:
	var pos_world:Vector2 = item["world_position"]
	var center_world:Vector2 = global_position
	var to_center:Vector2 = center_world - pos_world
	var distance_world:float = to_center.length()
	if distance_world <= 0.001:
		return

	var inward_world:Vector2 = to_center / distance_world
	var tangent_world:Vector2 = inward_world.orthogonal()
	var phase:float = float(item["curve_phase"])
	var direction_world:Vector2 = (inward_world + tangent_world * sin(phase) * 0.16).normalized()
	var pos_local:Vector2 = to_local(pos_world)
	var direction_local:Vector2 = (to_local(pos_world + direction_world) - pos_local).normalized()
	var pulse:float = float(item["pulse"])
	# 长度/粗细继续按 V11 的本地绘制单位，避免因为改成地图外生成而把线视觉放大。
	var base_length:float = float(item["length"]) * (0.84 + 0.16 * sin(pulse * 1.7))
	var alpha:float = float(item["alpha"])
	var width:float = float(item["width"])

	# 只有真正进入黑洞后才开始切割、缩短、淡出；地图外到黑洞之间保持原有基础尺寸。
	var inner_ratio:float = pos_local.length() / maxf(shape_radius,1.0)
	var fragment_count:int = 1
	var shrink:float = 1.0
	if inner_ratio < 1.10:
		fragment_count = 2
		shrink = clampf((inner_ratio - 0.10) / 1.00,0.08,1.0)
	if inner_ratio < 0.62:
		fragment_count = 3
		shrink *= clampf(inner_ratio / 0.62,0.08,1.0)

	var total_length:float = maxf(base_length * shrink,0.8)
	alpha *= clampf(shrink * 1.25,0.0,1.0)
	var color := Color(1.0,1.0,1.0,alpha)

	if fragment_count == 1:
		draw_line(pos_local - direction_local * total_length * 0.5,pos_local + direction_local * total_length * 0.5,color,width,true)
		return

	var gap:float = maxf(0.8,total_length * 0.13)
	var usable:float = maxf(total_length - gap * float(fragment_count - 1),0.6)
	var part_length:float = usable / float(fragment_count)
	var start_offset:float = -total_length * 0.5
	for i:int in range(fragment_count):
		var from_offset:float = start_offset + float(i) * (part_length + gap)
		var to_offset:float = from_offset + part_length
		draw_line(pos_local + direction_local * from_offset,pos_local + direction_local * to_offset,color,width,true)
