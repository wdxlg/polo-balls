extends Node2D

# 纯视觉：从攻击点向前扩散的圆弧声波。
# 真正的命中检测由“影子.gd”在权威端完成，这里只负责显示。

var wave_direction:Vector2 = Vector2.RIGHT
var max_range:float = 100.0
var half_angle_radians:float = deg_to_rad(55.0)
var duration:float = 0.34
var wave_thickness:float = 16.0
var wave_color:Color = Color(0.88,0.93,1.0,0.72)
var _elapsed:float = 0.0


func configure(
	origin:Vector2,
	attack_direction:Vector2,
	range_value:float,
	half_angle_degrees:float,
	duration_value:float,
	thickness_value:float,
	color_value:Color
) -> void:
	global_position = origin
	wave_direction = attack_direction.normalized() if attack_direction.length_squared() > 0.000001 else Vector2.RIGHT
	max_range = maxf(range_value,1.0)
	half_angle_radians = deg_to_rad(clampf(half_angle_degrees,5.0,175.0))
	duration = maxf(duration_value,0.05)
	wave_thickness = maxf(thickness_value,1.0)
	wave_color = color_value
	_elapsed = 0.0
	queue_redraw()


func _process(delta:float) -> void:
	_elapsed += delta
	queue_redraw()
	if _elapsed >= duration:
		queue_free()


func _draw() -> void:
	var progress:float = clampf(_elapsed / maxf(duration,0.001),0.0,1.0)
	# 开始时就有一个很小的弧，随后快速向外扩散。
	var radius:float = lerpf(5.0,max_range,progress)
	var facing_angle:float = wave_direction.angle()
	var begin_angle:float = facing_angle - half_angle_radians
	var end_angle:float = facing_angle + half_angle_radians
	var fade:float = 1.0 - progress

	# 外层柔和声波 + 内层亮边，形成明显但不遮挡战斗的吼叫弧。
	var glow_color:Color = wave_color
	glow_color.a *= fade * 0.32
	var core_color:Color = wave_color
	core_color.a *= fade

	draw_arc(
		Vector2.ZERO,
		radius,
		begin_angle,
		end_angle,
		44,
		glow_color,
		wave_thickness * 1.75,
		true
	)
	draw_arc(
		Vector2.ZERO,
		radius,
		begin_angle,
		end_angle,
		44,
		core_color,
		maxf(wave_thickness * 0.34,1.2),
		true
	)
