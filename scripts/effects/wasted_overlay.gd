extends Control
# 轮放 / Boss 模式里死亡角色名字上的 "WASTED" 叠层：
# 一条从中间向两边逐渐变细、变透明的黑色横带，上面压紧凑的粗体红字（黑描边）。
const TEXT:String = "WASTED"
const BAND_ALPHA:float = 0.92
const FONT_SIZE:int = 10
var _label:Label
# 红字的水平中心（overlay 局部坐标）。横带可能因为最小宽度/贴边裁剪而不对称，
# 但红字必须始终压在名字文字正中间，否则会看起来"偏了"。
var _text_center_x:float = -1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.name = "WastedText"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.text = TEXT
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var base:Font = get_theme_default_font()
	var bold := FontVariation.new()
	bold.base_font = base
	bold.variation_embolden = 0.9 # 粗体
	bold.spacing_glyph = 0 # 略微放开字距，粗体描边下不再互相粘连
	_label.add_theme_font_override("font",bold)
	_label.add_theme_font_size_override("font_size",FONT_SIZE)
	_label.add_theme_color_override("font_color",Color(0.93,0.08,0.08,1.0))
	_label.add_theme_color_override("font_outline_color",Color.BLACK)
	_label.add_theme_constant_override("outline_size",2)
	add_child(_label)
	resized.connect(_on_resized)
	_layout_text()

func _on_resized() -> void:
	_layout_text()
	queue_redraw()

# 指定红字中心应对齐到 overlay 局部坐标的哪个 x（通常是名字文字中心）。
# 传负数表示回退为横带居中。
func set_text_center(x:float) -> void:
	_text_center_x = x
	_layout_text()

func _layout_text() -> void:
	if _label == null:
		return
	var text_size:Vector2 = _label.get_minimum_size()
	var cx:float = size.x * 0.5 if _text_center_x < 0.0 else _text_center_x
	_label.size = text_size
	_label.position = Vector2(cx - text_size.x * 0.5,(size.y - text_size.y) * 0.5)

func _draw() -> void:
	var w:float = size.x
	var h:float = size.y
	if w <= 2.0 or h <= 2.0:
		return
	# 中间最厚（整行高），两端收成一条线；用多段梯形近似，alpha 随距中心距离线性衰减。
	var half:float = w * 0.5
	var steps:int = 14
	var cy:float = h * 0.5
	for i:int in range(steps):
		var t0:float = float(i) / float(steps)
		var t1:float = float(i + 1) / float(steps)
		var alpha0:float = BAND_ALPHA * (1.0 - t0)
		var alpha1:float = BAND_ALPHA * (1.0 - t1)
		var half_h0:float = cy * (1.0 - t0 * 0.85)
		var half_h1:float = cy * (1.0 - t1 * 0.85)
		for direction:float in [-1.0,1.0]:
			var x0:float = half + direction * half * t0
			var x1:float = half + direction * half * t1
			var points := PackedVector2Array([
				Vector2(x0,cy - half_h0),Vector2(x1,cy - half_h1),
				Vector2(x1,cy + half_h1),Vector2(x0,cy + half_h0),
			])
			var colors := PackedColorArray([
				Color(0,0,0,alpha0),Color(0,0,0,alpha1),Color(0,0,0,alpha1),Color(0,0,0,alpha0),
			])
			draw_polygon(points,colors)

func label() -> Label:
	return _label
