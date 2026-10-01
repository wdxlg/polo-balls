extends Control
## 我的世界标题大字（像 MINECRAFT / JAVA EDITION 那样）：渐变正面 + 朝下方消失点挤出的深色立体面 + 粗黑描边，像素风放大。
## 配色方案参照 cube-3d-text（MIT, EaseCation）：正面上亮下暗渐变，侧面由浅到深。
## 每个字单独用字体画（任何语言都行），立体面是一层层往消失点偏移的深色字，所以不会有三角化破面。
## 不注册 class_name，用 load() 取脚本：
##   var title = load(PATH).new()
##   title.setup([{"text":"烈焰人","style":Color.RED},{"text":"VS","style":"gold","scale":0.7}])
##   parent.add_child(title)   # 在自己的 size 里按比例居中绘制
## 行 style："stone"（原版标题灰石）/ "gold"（JAVA EDITION 金）/ Color（按颜色生成整套渐变）。
## 选项：font、pixel_scale（像素化倍数，默认 2）、render_width（渲染宽度，默认 1280）。

const DEFAULT_FONT:String = "res://fonts/SmileySans-Oblique.ttf"
const STONE:Dictionary = {"top":Color("f2f2f2"),"bottom":Color("8c8c8c"),"near":Color("5a5a5a"),"far":Color("2a2a2a")}
const GOLD:Dictionary = {"top":Color("ffe08a"),"bottom":Color("ffaa00"),"near":Color("a56c00"),"far":Color("4a3000")}
## 立体面厚度 / 描边粗细 / 行距（按字号比例）。
const DEPTH_RATIO:float = 0.17
const OUTLINE_RATIO:float = 0.075
const LINE_GAP_RATIO:float = 0.06
const OUTLINE_COLOR:Color = Color(0.06,0.05,0.05)

const FACE_SHADER:String = """
shader_type canvas_item;
uniform vec4 top_color : source_color;
uniform vec4 bottom_color : source_color;
uniform float top_y;
uniform float bottom_y;
uniform float cell = 4.0;
varying vec2 local_pos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() { local_pos = VERTEX; }
void fragment() {
	float t = clamp((local_pos.y - top_y) / max(bottom_y - top_y, 0.001), 0.0, 1.0);
	vec3 c = mix(top_color.rgb, bottom_color.rgb, t);
	// 原版标题石头的像素颗粒。
	c *= 0.9 + 0.12 * hash(floor(local_pos / cell));
	COLOR = vec4(c, texture(TEXTURE, UV).a * COLOR.a);
}
"""

## 一行字分三层画：描边（深色字在每一层四周偏移铺开）→ 立体面 → 正面（渐变 shader）。
class Line extends Node2D:
	var font:Font
	var text:String
	var font_size:int
	var depth:int
	var colors:Dictionary
	var vanish:Vector2
	var face:bool = false
	var outline:float = 0.0
	func _dir(center_x:float, ascent:float) -> Vector2:
		return (vanish - (global_position + Vector2(center_x,ascent * 0.6))).normalized()
	func _draw() -> void:
		var x:float = 0.0
		var glyphs:Array = []
		for ch:String in text:
			var advance:float = font.get_char_size(ch.unicode_at(0),font_size).x
			glyphs.append([ch.unicode_at(0),x,advance])
			x += advance
		var ascent:float = font.get_ascent(font_size)
		if face:
			for g:Array in glyphs: font.draw_char(get_canvas_item(),Vector2(g[1],ascent),g[0],font_size,Color.WHITE)
			return
		if outline > 0.0:
			var ring:Array[Vector2] = []
			for i:int in range(24): ring.append(Vector2.from_angle(TAU * i / 24.0) * outline)
			for i:int in range(12): ring.append(Vector2.from_angle(TAU * (i + 0.5) / 12.0) * outline * 0.5)
			var layers:Array[int] = []
			for k:int in range(0,depth + 1,2): layers.append(k)
			if layers[-1] != depth: layers.append(depth)
			for g:Array in glyphs:
				var dir:Vector2 = _dir(float(g[1]) + float(g[2]) * 0.5,ascent)
				for k:int in layers:
					for offset:Vector2 in ring: font.draw_char(get_canvas_item(),Vector2(g[1],ascent) + dir * float(k) + offset,g[0],font_size,OUTLINE_COLOR)
			return
		# 从最深一层往前画，每个字往消失点方向偏移，越深越暗。
		for k:int in range(depth,0,-1):
			var shade:Color = (colors.near as Color).lerp(colors.far,float(k) / float(depth))
			for g:Array in glyphs:
				var dir:Vector2 = _dir(float(g[1]) + float(g[2]) * 0.5,ascent)
				font.draw_char(get_canvas_item(),Vector2(g[1],ascent) + dir * float(k),g[0],font_size,shade)

var lines:Array = []
var font:Font
var pixel_scale:int = 2
var render_width:int = 1280
var viewport:SubViewport
## 渲染图宽高比（宽/高），布局用。
var aspect:float = 3.0

static func style_colors(style:Variant) -> Dictionary:
	if style is Color:
		var c:Color = style
		return {"top":c.lerp(Color.WHITE,0.6),"bottom":c,"near":c.darkened(0.3),"far":c.darkened(0.62)}
	return GOLD if str(style) == "gold" else STONE

func setup(title_lines:Array, options:Dictionary = {}) -> void:
	lines = title_lines
	font = options.get("font",load(DEFAULT_FONT))
	pixel_scale = maxi(int(options.get("pixel_scale",pixel_scale)),1)
	render_width = maxi(int(options.get("render_width",render_width)),64)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build()

func _build() -> void:
	viewport = SubViewport.new()
	viewport.name = "TitleRender"
	viewport.disable_3d = true
	viewport.transparent_bg = true
	# 和所在视口一致：项目开了 hdr_2d，非 HDR 的子视口贴进来会整体发暗。
	viewport.use_hdr_2d = get_viewport().use_hdr_2d if is_inside_tree() else false
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	var width:int = render_width / pixel_scale
	var base_size:int = int(width * 0.2)
	var margin:float = base_size * (0.08 + OUTLINE_RATIO)
	var usable:float = width - margin * 2.0
	# 先量每行：字号按 scale，超宽就缩到放得下（给立体面留出余量）。
	var plans:Array = []
	var y:float = margin
	for line:Dictionary in lines:
		var text:String = str(line.get("text",""))
		var size_px:int = maxi(int(base_size * float(line.get("scale",1.0))),8)
		var text_w:float = font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x
		if text_w > usable:
			size_px = maxi(int(size_px * usable / text_w),8)
			text_w = font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x
		var depth:int = maxi(int(round(size_px * DEPTH_RATIO)),2)
		plans.append({"text":text,"size":size_px,"width":text_w,"depth":depth,"y":y,"colors":style_colors(line.get("style","stone"))})
		y += font.get_ascent(size_px) + font.get_descent(size_px) * 0.35 + depth + size_px * LINE_GAP_RATIO
	var height:float = y + margin
	viewport.size = Vector2i(width,maxi(int(ceil(height)),8))
	aspect = float(viewport.size.x) / float(viewport.size.y)
	var vanish:Vector2 = Vector2(width * 0.5,height + width * 1.6)
	var face_shader := Shader.new()
	face_shader.code = FACE_SHADER
	for plan:Dictionary in plans:
		var origin:Vector2 = Vector2((width - float(plan.width)) * 0.5,float(plan.y))
		var ascent:float = font.get_ascent(int(plan.size))
		for layer:int in range(3):
			var face:bool = layer == 2
			var node := Line.new()
			node.font = font; node.text = plan.text; node.font_size = plan.size; node.depth = plan.depth
			node.colors = plan.colors; node.vanish = vanish; node.face = face
			node.outline = maxf(base_size * OUTLINE_RATIO,1.5) if layer == 0 else 0.0
			node.position = origin
			if face:
				var mat := ShaderMaterial.new()
				mat.shader = face_shader
				mat.set_shader_parameter("top_color",plan.colors.top)
				mat.set_shader_parameter("bottom_color",plan.colors.bottom)
				mat.set_shader_parameter("top_y",ascent * 0.18)
				mat.set_shader_parameter("bottom_y",ascent * 1.02)
				mat.set_shader_parameter("cell",maxf(float(plan.size) / 16.0,1.0))
				node.material = mat
			viewport.add_child(node)
	queue_redraw()

func texture() -> Texture2D:
	return viewport.get_texture() if is_instance_valid(viewport) else null

## 在 area 里按比例居中的绘制区域。
func draw_rect_for(area:Vector2) -> Rect2:
	var w:float = minf(area.x,area.y * aspect)
	var h:float = w / aspect
	return Rect2((area - Vector2(w,h)) * 0.5,Vector2(w,h))

func _draw() -> void:
	var tex:Texture2D = texture()
	if tex != null: draw_texture_rect(tex,draw_rect_for(size),false)

