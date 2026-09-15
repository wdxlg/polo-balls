extends Node2D
class_name HitBurstEffect

# ========================================================
# 通用受击爆射线视觉
#
# 人物受击沿用原来的快速冲击动画。
# 墙面撞击（anchored_origin_motion=true）使用一条连续、单调的运动曲线：
# 1. 尾端固定在接触点，线从 0 平滑长到峰值；
# 2. 峰值后头部继续向外走，尾部平滑追上；
# 3. 长度收至 0 并渐隐。
#
# 墙面动画使用 Time.get_ticks_usec() 的单调真实时间，不受 Engine.time_scale 影响。
# ========================================================

var _origin:Vector2 = Vector2.ZERO
var _streaks:Array = []
var _elapsed:float = 0.0
var _end_time:float = 0.0
var _use_real_time:bool = false
var _start_ticks_usec:int = 0
# V420 性能：Line2D 的 width / default_color 每次赋值都会触发 Line2D 重建网格。
# 记住上次写入的值，只有真正变化时才写回，同帧内多条线共用一份判定。
const _WIDTH_EPSILON:float = 0.004
const _ALPHA_EPSILON:float = 0.006


func _smootherstep01(value:float) -> float:
	var t:float = clampf(value,0.0,1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


func setup(origin:Vector2,streaks:Array) -> void:
	_origin = origin
	_streaks = streaks
	_use_real_time = false
	for raw:Variant in _streaks:
		if not raw is Dictionary:
			continue
		var streak_data:Dictionary = raw
		if bool(streak_data.get("use_real_time",false)):
			_use_real_time = true
			break
	_start_ticks_usec = Time.get_ticks_usec()


func _ready() -> void:
	top_level = true
	z_as_relative = false
	# V109：受击/格挡/撞墙白线属于战斗反馈，允许跨出地图边界显示。
	# World 地图外视觉遮罩为 z=90、地图黑边为 z=100。
	z_index = 98
	global_position = _origin
	global_rotation = 0.0
	global_scale = Vector2.ONE

	if _streaks.is_empty():
		queue_free()
		return

	for index:int in range(_streaks.size()):
		var data:Dictionary = _streaks[index]
		var line := Line2D.new()
		line.name = "HitBurstStreak_%d" % index
		line.width = maxf(float(data.get("width",0.65)),0.22)
		var initial_color:Color = data.get("color",Color.WHITE)
		line.default_color = Color(initial_color.r,initial_color.g,initial_color.b,0.0)
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.antialiased = true
		line.points = PackedVector2Array([Vector2.ZERO,Vector2.ZERO])
		line.visible = false
		add_child(line)

		data["line"] = line
		_streaks[index] = data
		_end_time = maxf(
			_end_time,
			float(data.get("delay",0.0)) + maxf(float(data.get("duration",0.28)),0.05)
		)


func _process(delta:float) -> void:
	if _use_real_time:
		# 微秒级单调计时避免高刷新率下毫秒取整带来的细小阶梯，
		# 同时完全绕开 Engine.time_scale。
		_elapsed = maxf(float(Time.get_ticks_usec() - _start_ticks_usec) / 1000000.0,0.0)
	else:
		_elapsed += delta

	for data:Dictionary in _streaks:
		var line:Line2D = data.get("line",null) as Line2D
		if line == null or not is_instance_valid(line):
			continue

		var delay:float = maxf(float(data.get("delay",0.0)),0.0)
		var local_time:float = _elapsed - delay
		if local_time < 0.0:
			line.visible = false
			continue

		var duration:float = maxf(float(data.get("duration",0.28)),0.05)
		var progress:float = clampf(local_time / duration,0.0,1.0)
		if progress >= 1.0:
			line.visible = false
			continue

		line.visible = true

		var direction:Vector2 = data.get("direction",Vector2.RIGHT)
		if direction.length_squared() <= 0.000001:
			direction = Vector2.RIGHT
		direction = direction.normalized()

		var spawn_offset:Vector2 = data.get("spawn_offset",Vector2.ZERO)
		var max_distance:float = maxf(float(data.get("distance",100.0)),1.0)
		var peak_length:float = maxf(float(data.get("length",28.0)),1.0)
		var grow_end:float = clampf(float(data.get("grow_end",0.30)),0.08,0.55)
		var current_length:float = 0.0
		var head_distance:float = 0.0
		var tail_distance:float = 0.0

		if bool(data.get("anchored_origin_motion",false)):
			# 墙面版本：两段曲线在 grow_end 处位置与速度都连续。
			# 旧版在 grow_end 之后会先“缩回去”再重新飞出，肉眼看就是顿一下。
			if progress <= grow_end:
				var grow_t:float = progress / maxf(grow_end,0.001)
				var grow_curve:float = _smootherstep01(grow_t)
				current_length = peak_length * grow_curve
				tail_distance = 0.0
				head_distance = current_length
			else:
				var travel_t:float = (progress - grow_end) / maxf(1.0 - grow_end,0.001)
				var travel_curve:float = _smootherstep01(travel_t)
				var shrink_curve:float = _smootherstep01(travel_t)
				current_length = peak_length * (1.0 - shrink_curve)
				var extra_travel:float = maxf(max_distance - peak_length,0.0)
				head_distance = peak_length + extra_travel * travel_curve
				tail_distance = maxf(head_distance - current_length,0.0)
		else:
			# 人物受击保留原动画，不因为墙面手感调整而变化。
			var head_ratio:float = 1.0 - pow(1.0 - progress,3.0)
			head_distance = max_distance * head_ratio
			if progress <= grow_end:
				var grow_t:float = clampf(progress / grow_end,0.0,1.0)
				var length_ratio:float = 1.0 - pow(1.0 - grow_t,2.0)
				current_length = peak_length * length_ratio
			else:
				var shrink_t:float = clampf((progress - grow_end) / (1.0 - grow_end),0.0,1.0)
				current_length = peak_length * pow(1.0 - shrink_t,1.35)
			tail_distance = maxf(head_distance - current_length,0.0)

		var line_start:Vector2 = spawn_offset + direction * tail_distance
		var line_end:Vector2 = spawn_offset + direction * head_distance
		line.points = PackedVector2Array([line_start,line_end])

		var fade_in_end:float = clampf(float(data.get("fade_in_end",0.14)),0.02,0.45)
		var fade_out_start:float = clampf(float(data.get("fade_out_start",0.50)),fade_in_end,0.92)
		var alpha_ratio:float = 1.0
		if progress < fade_in_end:
			alpha_ratio = _smootherstep01(progress / maxf(fade_in_end,0.001))
		elif progress > fade_out_start:
			var fade_out_t:float = (progress - fade_out_start) / maxf(1.0 - fade_out_start,0.001)
			alpha_ratio = 1.0 - _smootherstep01(fade_out_t)

		var base_color:Color = data.get("color",Color.WHITE)
		var next_alpha:float = base_color.a * alpha_ratio
		if absf(line.default_color.a - next_alpha) > _ALPHA_EPSILON or line.default_color.r != base_color.r or line.default_color.g != base_color.g or line.default_color.b != base_color.b:
			line.default_color = Color(
				base_color.r,
				base_color.g,
				base_color.b,
				next_alpha
			)

		var width_fade_t:float = clampf((progress - 0.52) / 0.48,0.0,1.0)
		var width_fade:float = _smootherstep01(width_fade_t)
		var base_width:float = maxf(float(data.get("width",0.65)),0.22)
		var next_width:float = maxf(base_width * lerpf(1.0,0.55,width_fade),0.16)
		if absf(line.width - next_width) > _WIDTH_EPSILON:
			line.width = next_width

	if _elapsed >= _end_time + 0.02:
		queue_free()
