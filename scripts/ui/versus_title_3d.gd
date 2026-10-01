extends Control
## 顶部「XX VS XX」标题的我的世界 3D 立体字（2026-10-02 用户要求：不要开场文字，直接替换 VS 文字）。
##
## 挂在 world.versus_label 下（录像中/英文镜像副本由 battle_record_locale 各挂一个）：读父
## RichTextLabel 的 BBCode，按 build_versus_text 的格式解析出各方名字与颜色，用 mc_title_text
## 渲染；父标签自己的字形用透明材质隐藏，但文字、尺寸、可见性照旧——顶部布局、录像翻译、
## 1v1 对战 HUD 用 self_modulate 隐藏 VS 都继续以父标签为准。不是 VS 格式的文字（如死档提示）
## 就还原成普通文字。

const NODE_NAME:String = "VersusTitle3D"
const SELF_PATH:String = "res://scripts/ui/versus_title_3d.gd"
const TITLE_SCRIPT:GDScript = preload("res://scripts/ui/mc_title_text.gd")
const SEGMENT_PATTERN:String = "\\[color=#([0-9a-fA-F]{6,8})\\]\\[b\\](.*?)\\[/b\\]\\[/color\\]"
## 一行能放下的大致字宽（汉字 = 1，西文字符约 0.62）；超过就折到下一行。
const SINGLE_LINE_EM:float = 13.0
const VS_WIDTH_EM:float = 1.6
## 单行绘制高度 = 字号行高 × 这个倍数，且至少是宽度的 ROW_HEIGHT_PER_WIDTH——立体字比平面字大一号。
const HEIGHT_RATIO:float = 1.8
const ROW_HEIGHT_PER_WIDTH:float = 0.16
## 底边固定在单行标题的位置；人多折行时往上长，用掉顶部空白，最高到屏幕高度的这个比例
## （时钟下面；本体还会避开顶部工具栏）。放不下就整体缩小，绝不往下压到战场。
const TOP_SAFE_FRACTION:float = 0.04
const WRAP_CANDIDATES:Array[float] = [13.0,16.0,20.0,25.0,32.0,44.0,64.0]
const VS_INLINE_SCALE:float = 0.68

static var _hide_material:ShaderMaterial = null
var title:Control = null
var _source_text:String = "\u0001"
var _sides:Array = []
var _layout_key:Vector2 = Vector2.ZERO
## 可选：返回本体屏幕坐标里标题最高能到的 y（world 用它避开顶部工具栏）。
var top_limit_provider:Callable = Callable()


static func attach(label:RichTextLabel) -> Control:
	var existing:Control = label.get_node_or_null(NODE_NAME) as Control
	if existing != null: return existing
	var node:Control = (load(SELF_PATH) as GDScript).new()
	label.add_child(node)
	node.sync_now()
	return node


## 只隐藏父标签自己的字形；子节点不继承材质。
static func hide_material() -> ShaderMaterial:
	if _hide_material == null:
		var shader := Shader.new()
		shader.code = "shader_type canvas_item;\nvoid fragment() { COLOR.a = 0.0; }\n"
		_hide_material = ShaderMaterial.new()
		_hide_material.shader = shader
	return _hide_material


## VS 文字 → mc_title_text 的行（默认折行宽度）；不是 VS 格式返回 []。
static func parse(text:String) -> Array:
	var sides:Array = parse_sides(text)
	return [] if sides.is_empty() else pack(sides,SINGLE_LINE_EM)


## VS 文字 → 各方 [{text, style}]；不是 VS 格式返回 []。
static func parse_sides(text:String) -> Array:
	var pattern := RegEx.new()
	pattern.compile(SEGMENT_PATTERN)
	var found:Array[RegExMatch] = pattern.search_all(text)
	if found.is_empty(): return []
	var rest:String = pattern.sub(text,"",true).replace("[center]","").replace("[/center]","")
	if not rest.strip_edges().is_empty(): return []
	var sides:Array = []
	for item:RegExMatch in found:
		var name:String = item.get_string(2).replace("[lb]","[").replace("[rb]","]").strip_edges()
		if name.is_empty(): continue
		var color := Color(item.get_string(1))
		if name == "VS" and color.is_equal_approx(Color.WHITE): continue
		# 白色（中立/单方）用石头灰，其余用阵营色。
		var style:Variant = "stone" if color.s < 0.12 and color.v > 0.85 else color
		sides.append({"text":name,"style":style})
	return sides


## 按宽度贪心折行，续行以 VS 开头。
static func pack(sides:Array,wrap_em:float) -> Array:
	var lines:Array = []
	var segments:Array = []
	var width:float = 0.0
	for side:Dictionary in sides:
		var side_width:float = estimate_width(side.text)
		if not segments.is_empty() and width + VS_WIDTH_EM + side_width > wrap_em:
			lines.append({"segments":segments})
			segments = []
			width = 0.0
		if not lines.is_empty() or not segments.is_empty():
			segments.append({"text":"VS","style":"gold","scale":VS_INLINE_SCALE})
			width += VS_WIDTH_EM
		segments.append(side)
		width += side_width
	if not segments.is_empty(): lines.append({"segments":segments})
	return lines


## 在给定区域（宽 × 高，任意单位）里挑字最大的折行宽度；同样大时行数少的优先。
static func best_layout(sides:Array,area:Vector2,row_cap:float) -> Array:
	var best:Array = []
	var best_scale:float = -1.0
	for wrap_em:float in WRAP_CANDIDATES:
		var lines:Array = pack(sides,wrap_em)
		var widest:float = 0.0
		for line:Dictionary in lines:
			var width:float = 0.0
			for piece:Dictionary in line.segments:
				width += VS_WIDTH_EM if piece.text == "VS" and piece.style is String and piece.style == "gold" else estimate_width(piece.text)
			widest = maxf(widest,width)
		# 每 em 能给多大：受宽度、可用高度、单行上限三者约束（行高约 1.3 em，四周约 0.45 em 留白）。
		var per_em:float = minf(minf(area.x / (widest + 0.9),area.y / (float(lines.size()) * 1.3 + 0.35)),row_cap / 1.63)
		if per_em > best_scale * 1.03:
			best_scale = per_em
			best = lines
	return best


## 大致字宽（单位：一个汉字）。
static func estimate_width(text:String) -> float:
	var width:float = 0.0
	for character:String in text: width += 1.0 if character.unicode_at(0) >= 0x2E80 else 0.62
	return width


func _ready() -> void:
	name = NODE_NAME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	sync_now()


func _process(_delta:float) -> void:
	sync_now()


func sync_now() -> void:
	var label:RichTextLabel = get_parent() as RichTextLabel
	if label == null: return
	if label.text != _source_text:
		_source_text = label.text
		_sides = parse_sides(_source_text)
		_layout_key = Vector2.ZERO
	var active:bool = not _sides.is_empty()
	var wanted:Material = hide_material() if active else null
	if label.material != wanted: label.material = wanted
	visible = active
	if not active:
		if is_instance_valid(title):
			title.queue_free()
			title = null
		return
	# 区域：底边 = 单行标题底边（以一行字的中线为准上下外扩），顶边 = 屏幕安全线（换算到标签本地坐标）。
	var line_height:float = float(label.get_theme_font_size("bold_font_size")) * 1.4
	var row:float = maxf(line_height * HEIGHT_RATIO,label.size.x * ROW_HEIGHT_PER_WIDTH)
	var bottom:float = line_height * 0.5 + row * 0.5
	var screen_top:float = label.get_viewport_rect().size.y * TOP_SAFE_FRACTION
	if top_limit_provider.is_valid(): screen_top = maxf(screen_top,float(top_limit_provider.call()))
	var canvas:Transform2D = label.get_global_transform_with_canvas()
	var top:float = minf((canvas.affine_inverse() * Vector2(0.0,screen_top)).y,bottom - row)
	var area := Vector2(label.size.x,bottom - top)
	# 文字或区域明显变化才重新生成网格（区域按 4% 粒度比较，避免每帧抖动重建）。
	var key := Vector2(roundf(area.x / maxf(row,0.001) * 25.0),roundf(area.y / maxf(row,0.001) * 25.0))
	if key != _layout_key or not is_instance_valid(title):
		_layout_key = key
		if is_instance_valid(title): title.queue_free()
		title = TITLE_SCRIPT.new()
		title.name = "Title"
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.valign = 1.0
		title.setup(best_layout(_sides,area,row))
		add_child(title)
	position = Vector2(0.0,top)
	size = area
	title.position = Vector2.ZERO
	title.size = size
	# 1v1 对战 HUD 只把父标签 self_modulate 透明度置 0；子节点不受 self_modulate 影响，这里跟随。
	modulate = Color(1.0,1.0,1.0,label.self_modulate.a)
	visibility_layer = label.visibility_layer
	title.visibility_layer = label.visibility_layer

