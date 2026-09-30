extends CanvasLayer
## 全屏后处理（纯视觉）。整个场景只有一个实例：新请求作为条目加入，连续参数取所有条目的最大值。
## 条目: {life, t, center, peak, env}；env 为 [淡入, 保持到, 淡出结束] 占生命的比例。
## peak 键：blur / aberration / desat / tint / vignette / flash / flash_time / lines / lines_color /
##   frames = [[时长, dark, light], ...] 冲击帧序列（按顺序播放，dark/light 为 null 表示这一段回到正常画面）。
const SHADER = preload("res://scripts/characters/动漫/咒术回战/jjk_screen.gdshader")
const MAX_BLUR:float = 0.06
const MAX_ABERRATION:float = 0.015
var entries:Array = []
var _rect:ColorRect
var _mat:ShaderMaterial
var _clock:float = 0.0

func _ready() -> void:
	layer = 90
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect.material = _mat
	_apply()

func add_entry(life:float,center:Vector2,peak:Dictionary,env:Vector3) -> void:
	entries.append({"life":maxf(life,0.05),"t":0.0,"center":center,"peak":peak,"env":env})
	if entries.size() > 8: entries.pop_front()
	if is_inside_tree(): _apply()

func _process(delta:float) -> void:
	_clock += delta
	for e:Dictionary in entries: e["t"] = float(e["t"]) + delta
	entries = entries.filter(func(e:Dictionary) -> bool: return float(e["t"]) < float(e["life"]))
	if entries.is_empty():
		queue_free()
		return
	_apply()

static func _envelope(e:Dictionary) -> float:
	var k:float = clampf(float(e["t"]) / float(e["life"]),0.0,1.0)
	var env:Vector3 = e["env"]
	if k < env.x: return k / maxf(env.x,0.0001)
	if k > env.y: return 1.0 - clampf((k - env.y) / maxf(env.z - env.y,0.0001),0.0,1.0)
	return 1.0

## 当前冲击帧：返回 [dark, light, threshold] 或空数组。
static func _frame(e:Dictionary) -> Array:
	var seq:Array = (e["peak"] as Dictionary).get("frames",[])
	var t:float = float(e["t"])
	for f:Variant in seq:
		var fa:Array = f
		if t < float(fa[0]):
			if fa[1] == null: return []
			return [fa[1],fa[2],float(fa[3]) if fa.size() > 3 else 0.42]
		t -= float(fa[0])
	return []

func _apply() -> void:
	var blur:float = 0.0
	var ab:float = 0.0
	var desat:float = 0.0
	var vig:float = 0.0
	var lines:float = 0.0
	var lines_col:Color = Color(0,0,0,1)
	var tint:Color = Color(1,1,1,0)
	var flash:Color = Color(1,1,1,0)
	var best_w:float = -1.0
	var center_w:Vector2 = Vector2.ZERO
	var fr:Array = []
	for e:Dictionary in entries:
		var a:float = _envelope(e)
		var p:Dictionary = e["peak"]
		var t:float = float(e["t"])
		var eb:float = float(p.get("blur",0.0)) * a
		var ea:float = float(p.get("aberration",0.0)) * a
		var el:float = float(p.get("lines",0.0)) * a
		var ff:Array = _frame(e)
		var w:float = eb + ea + el + (10.0 if not ff.is_empty() else 0.0)
		if w > best_w:
			best_w = w
			center_w = e["center"]
		if not ff.is_empty(): fr = ff
		blur = maxf(blur,eb)
		ab = maxf(ab,ea)
		if el > lines:
			lines = el
			lines_col = p.get("lines_color",Color(0,0,0,1))
		desat = maxf(desat,float(p.get("desat",0.0)) * a)
		vig = maxf(vig,float(p.get("vignette",0.0)) * a)
		var tc:Color = p.get("tint",Color(1,1,1,0))
		if tc.a * a > tint.a: tint = Color(tc,tc.a * a)
		var fl:Color = p.get("flash",Color(1,1,1,0))
		# 闪光按 1/24 秒跳变（动画的硬切），不做平滑淡出。
		var ft:float = maxf(float(p.get("flash_time",0.08)),0.01)
		var fk:float = 1.0 - floorf(clampf(t / ft,0.0,1.0) * 3.0) / 3.0
		if fl.a * fk > flash.a: flash = Color(fl,fl.a * fk)
	var vp:Viewport = get_viewport()
	var size:Vector2 = vp.get_visible_rect().size if vp != null else Vector2(800,600)
	var screen:Vector2 = vp.get_canvas_transform() * center_w if vp != null else size * 0.5
	_mat.set_shader_parameter("center",(screen / size).clamp(Vector2.ZERO,Vector2.ONE))
	_mat.set_shader_parameter("aspect",Vector2(size.x / maxf(size.y,1.0),1.0))
	_mat.set_shader_parameter("time",_clock)
	_mat.set_shader_parameter("blur",minf(blur,MAX_BLUR))
	_mat.set_shader_parameter("aberration",minf(ab,MAX_ABERRATION))
	_mat.set_shader_parameter("desat",desat)
	_mat.set_shader_parameter("tint",tint)
	_mat.set_shader_parameter("vignette",vig)
	_mat.set_shader_parameter("flash_color",flash)
	_mat.set_shader_parameter("lines",clampf(lines,0.0,1.0))
	_mat.set_shader_parameter("lines_color",lines_col)
	if fr.is_empty():
		_mat.set_shader_parameter("impact",0.0)
	else:
		_mat.set_shader_parameter("impact",1.0)
		_mat.set_shader_parameter("dark",fr[0])
		_mat.set_shader_parameter("light",fr[1])
		_mat.set_shader_parameter("threshold",fr[2])
