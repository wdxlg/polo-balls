class_name MoonSanityBar
extends Control

const MIN_SANITY:float = -45.0
const MAX_SANITY:float = 45.0
const FLOW_SHADER:Shader = preload("res://shaders/ui/月计理智流动.gdshader")

# 上一版 420x64 太抢画面；这版缩到约 57% 长度、50% 高度。
@export var bar_size:Vector2 = Vector2(240.0, 32.0)
@export_range(0.0,12.0,0.5) var center_overhang:float = 6.0
@export_range(0.0,2.0,0.01) var fractal_flow_speed:float = 0.22
@export_range(0.5,4.0,0.05) var fractal_noise_scale:float = 1.0
@export_range(0.0,1.0,0.01) var fractal_dark_strength:float = 0.86
@export_range(0.0,1.0,0.01) var fractal_dark_coverage:float = 0.70
@export_range(0.15,2.0,0.05) var overdrive_transition_time:float = 0.75
@export_range(18,40,1) var sanity_number_font_size:int = 30

var sanity:float = 0.0
var _display_sanity:float = 0.0
var _number:Label = null
var _left_fill:ColorRect = null
var _right_fill:ColorRect = null
var _center_glow_outer:ColorRect = null
var _center_glow_inner:ColorRect = null
var _center_line_outer:ColorRect = null
var _center_line_core:ColorRect = null
var _overdrive:bool = false
var _overdrive_progress:float = 0.0
var _overdrive_tween:Tween = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = bar_size
	size = bar_size
	clip_contents = false

	_left_fill = _make_flow_fill(
		"NegativeSanityFill",
		Color(0.72, 0.035, 0.065, 0.97),
		Color(0.10, 0.003, 0.012, 0.98),
		-1.0
	)
	_right_fill = _make_flow_fill(
		"PositiveSanityFill",
		Color(0.035, 0.22, 0.82, 0.97),
		Color(0.004, 0.025, 0.12, 0.98),
		1.0
	)

	_create_center_line()

	_number = Label.new()
	_number.name = "SanityNumber"
	_number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_number.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_number.add_theme_font_size_override("font_size", sanity_number_font_size)
	_number.add_theme_constant_override("outline_size", 5)
	_number.add_theme_color_override("font_outline_color", Color(0.015,0.015,0.02,0.96))
	_number.z_index = 10
	add_child(_number)

	_update_number()
	_update_fill_geometry()
	queue_redraw()

func _make_flow_fill(node_name:String, base:Color, deep:Color, direction:float) -> ColorRect:
	var fill := ColorRect.new()
	fill.name = node_name
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.color = Color.WHITE
	fill.z_index = 1
	var mat := ShaderMaterial.new()
	mat.shader = FLOW_SHADER
	mat.set_shader_parameter("base_color", base)
	mat.set_shader_parameter("deep_color", deep)
	mat.set_shader_parameter("flow_direction", direction)
	mat.set_shader_parameter("flow_speed", fractal_flow_speed)
	mat.set_shader_parameter("noise_scale", fractal_noise_scale)
	mat.set_shader_parameter("dark_strength", fractal_dark_strength)
	mat.set_shader_parameter("dark_coverage", fractal_dark_coverage)
	fill.material = mat
	add_child(fill)
	return fill

func _create_center_line() -> void:
	_center_glow_outer = _make_center_rect("CenterGlowOuter", Color(1.0,0.72,0.04,0.09), 14.0, 2)
	_center_glow_inner = _make_center_rect("CenterGlowInner", Color(1.0,0.82,0.10,0.16), 10.0, 3)
	_center_line_outer = _make_center_rect("CenterLineOuter", Color(1.0,0.68,0.015,1.0), 6.0, 4)
	_center_line_core = _make_center_rect("CenterLineCore", Color(1.0,0.975,0.80,1.0), 2.5, 5)
	_update_center_line_geometry()

func _make_center_rect(node_name:String, color:Color, width:float, z:int) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = node_name
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = color
	rect.set_meta("sanity_line_width", width)
	rect.z_index = z
	add_child(rect)
	return rect

func set_sanity(value:float, instant:bool = false) -> void:
	sanity = clampf(value, MIN_SANITY, MAX_SANITY)
	if instant:
		_display_sanity = sanity
		_update_number()
		_update_fill_geometry()
	queue_redraw()

func set_overdrive(active:bool, instant:bool = false) -> void:
	if _overdrive_tween != null and _overdrive_tween.is_valid():
		_overdrive_tween.kill()
	_overdrive_tween = null
	_overdrive = active

	if not active:
		_set_overdrive_progress(0.0)
		return

	if instant or not is_inside_tree():
		_set_overdrive_progress(1.0)
		return

	# 触发 E.G.O 时，从“当前真实理智条的形状”平滑扩张成红蓝双满。
	# 不改真实 sanity，只动画显示层，所以不会干扰战斗数值。
	_overdrive_progress = 0.0
	_update_number()
	_update_fill_geometry()
	queue_redraw()
	_overdrive_tween = create_tween().bind_node(self)
	_overdrive_tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_overdrive_tween.tween_method(_set_overdrive_progress,0.0,1.0,overdrive_transition_time)

func _set_overdrive_progress(value:float) -> void:
	_overdrive_progress = clampf(value,0.0,1.0)
	_update_number()
	_update_fill_geometry()
	queue_redraw()

func _process(delta:float) -> void:
	if not is_equal_approx(_display_sanity, sanity):
		_display_sanity = move_toward(_display_sanity, sanity, delta * 90.0)
		_update_number()
		_update_fill_geometry()
		queue_redraw()

func _notification(what:int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_update_fill_geometry()
		_update_center_line_geometry()

func _update_number() -> void:
	if _number == null:
		return

	# E.G.O 过渡前段仍显示触发时的 ±45；红蓝条接近完全展开后才切成 ∞，
	# 避免触发瞬间直接跳成最终状态。
	if _overdrive and _overdrive_progress >= 0.72:
		_number.text = "∞"
		var infinity_t:float = smoothstep(0.72,1.0,_overdrive_progress)
		_number.add_theme_color_override(
			"font_color",
			Color.WHITE.lerp(Color(1.0,0.93,0.62,1.0), infinity_t)
		)
		return

	var shown:int = clampi(roundi(_display_sanity), int(MIN_SANITY), int(MAX_SANITY))
	_number.text = str(shown)
	var strength:float = clampf(absf(_display_sanity) / MAX_SANITY, 0.0, 1.0)
	var target:Color = Color(0.25,0.57,1.0,1.0) if _display_sanity > 0.0 else Color(1.0,0.20,0.24,1.0)
	if is_zero_approx(_display_sanity):
		target = Color.WHITE
	_number.add_theme_color_override("font_color", Color.WHITE.lerp(target, strength))

func _update_fill_geometry() -> void:
	if _left_fill == null or _right_fill == null:
		return
	var w:float = maxf(size.x, 1.0)
	var h:float = maxf(size.y, 1.0)
	var center_x:float = w * 0.5
	var inset:float = 3.0
	var half_fill:float = maxf(center_x - inset, 0.0)
	var normal_ratio:float = clampf(absf(_display_sanity) / MAX_SANITY, 0.0, 1.0)
	var left_ratio:float = normal_ratio if _display_sanity < -0.01 else 0.0
	var right_ratio:float = normal_ratio if _display_sanity > 0.01 else 0.0

	if _overdrive:
		# 红/蓝两边从触发前的实际长度分别向满格补齐。
		# 用 smoothstep 让开头和收尾都没有突兀速度变化。
		var t:float = smoothstep(0.0,1.0,_overdrive_progress)
		left_ratio = lerpf(left_ratio,1.0,t)
		right_ratio = lerpf(right_ratio,1.0,t)

	var left_w:float = half_fill * left_ratio
	var right_w:float = half_fill * right_ratio
	var fill_h:float = maxf(h - inset * 2.0, 0.0)

	_left_fill.visible = left_w > 0.01
	_right_fill.visible = right_w > 0.01

	_left_fill.position = Vector2(center_x - left_w, inset)
	_left_fill.size = Vector2(left_w, fill_h)
	_right_fill.position = Vector2(center_x, inset)
	_right_fill.size = Vector2(right_w, fill_h)

	# 把噪声坐标固定在整个理智条空间里。理智增长/减少时只是“揭开”更多噪声，
	# 不会因为填充宽度变化而把纹理拉伸，流动因此保持连续。
	for fill_variant in [_left_fill, _right_fill]:
		var fill := fill_variant as ColorRect
		var mat := fill.material as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("local_origin", fill.position)
			mat.set_shader_parameter("rect_size", fill.size)

func _update_center_line_geometry() -> void:
	if _center_line_core == null:
		return
	var center_x:float = size.x * 0.5
	# 只向背景上方突破，不再向下额外伸出。
	var top:float = -center_overhang
	var line_h:float = size.y + center_overhang
	for rect_variant in [_center_glow_outer, _center_glow_inner, _center_line_outer, _center_line_core]:
		var rect := rect_variant as ColorRect
		var width:float = float(rect.get_meta("sanity_line_width", 2.0))
		rect.position = Vector2(center_x - width * 0.5, top)
		rect.size = Vector2(width, line_h)

func _draw() -> void:
	var w:float = maxf(size.x, 1.0)
	var h:float = maxf(size.y, 1.0)
	# 0 理智时左右完全无色，只保留深色底板。
	draw_rect(Rect2(0.0,0.0,w,h), Color(0.03,0.035,0.05,0.92), true)
	draw_rect(Rect2(0.0,0.0,w,h), Color(0.70,0.72,0.79,0.72), false, 2.0, true)
