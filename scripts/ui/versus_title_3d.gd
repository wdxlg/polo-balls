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
## 每行绘制高度 = 文字框高度 × 这个倍数（第一行以文字框中线上下对称外扩），立体字比平面字大一号；
## 至少是宽度的 ROW_HEIGHT_PER_WIDTH。折行时往下逐行加高，不往上顶到工具栏/时钟。
const HEIGHT_RATIO:float = 1.8
const ROW_HEIGHT_PER_WIDTH:float = 0.16
const VS_INLINE_SCALE:float = 0.68

static var _hide_material:ShaderMaterial = null
var title:Control = null
var _source_text:String = "\u0001"
var _active:bool = false
var _rows:int = 1


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


## VS 文字 → mc_title_text 的行；不是 VS 格式返回 []。
static func parse(text:String) -> Array:
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
	# 一行放不下就按宽度贪心折行，续行以 VS 开头。
	var lines:Array = []
	var segments:Array = []
	var width:float = 0.0
	for side:Dictionary in sides:
		var side_width:float = estimate_width(side.text)
		if not segments.is_empty() and width + VS_WIDTH_EM + side_width > SINGLE_LINE_EM:
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
		var lines:Array = parse(_source_text)
		_active = not lines.is_empty()
		_rows = maxi(lines.size(),1)
		if is_instance_valid(title):
			title.queue_free()
			title = null
		if _active:
			title = TITLE_SCRIPT.new()
			title.name = "Title"
			title.mouse_filter = Control.MOUSE_FILTER_IGNORE
			title.setup(lines)
			add_child(title)
	var wanted:Material = hide_material() if _active else null
	if label.material != wanted: label.material = wanted
	visible = _active
	if not _active: return
	var row:float = maxf(label.size.y * HEIGHT_RATIO,label.size.x * ROW_HEIGHT_PER_WIDTH)
	if _rows > 1: row = maxf(label.size.x * ROW_HEIGHT_PER_WIDTH,label.size.y * HEIGHT_RATIO / float(_rows))
	position = Vector2(0.0,(label.size.y - row) * 0.5)
	size = Vector2(label.size.x,row * float(_rows))
	title.position = Vector2.ZERO
	title.size = size
	# 1v1 对战 HUD 只把父标签 self_modulate 透明度置 0；子节点不受 self_modulate 影响，这里跟随。
	modulate = Color(1.0,1.0,1.0,label.self_modulate.a)
	visibility_layer = label.visibility_layer
	title.visibility_layer = label.visibility_layer

