extends CanvasLayer
## 全屏后处理（纯视觉）：径向模糊/色差/反色/去色/色调/暗角/闪光。
## 整个场景只有一个实例：新请求作为条目加入，每个参数取所有条目的最大值（不会层层叠加糊成一片）。
## 条目: {life, t, center, peak, env}；env 为 [淡入, 保持到, 淡出结束] 占生命的比例。
const SHADER = preload("res://scripts/characters/动漫/咒术回战/jjk_screen.gdshader")
const MAX_BLUR:float = 0.07
const MAX_ABERRATION:float = 0.02
var entries:Array = []
var _rect:ColorRect
var _mat:ShaderMaterial

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
	if entries.size() > 6: entries.pop_front()
	if is_inside_tree(): _apply()

func _process(delta:float) -> void:
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

func _apply() -> void:
	var blur:float = 0.0
	var ab:float = 0.0
	var inv:float = 0.0
	var desat:float = 0.0
	var vig:float = 0.0
	var tint:Color = Color(1,1,1,0)
	var flash:Color = Color(1,1,1,0)
	var best_w:float = -1.0
	var center_w:Vector2 = Vector2.ZERO
	for e:Dictionary in entries:
		var a:float = _envelope(e)
		var p:Dictionary = e["peak"]
		var t:float = float(e["t"])
		var eb:float = float(p.get("blur",0.0)) * a
		var ea:float = float(p.get("aberration",0.0)) * a
		if eb + ea > best_w:
			best_w = eb + ea
			center_w = e["center"]
		blur = maxf(blur,eb)
		ab = maxf(ab,ea)
		desat = maxf(desat,float(p.get("desat",0.0)) * a)
		vig = maxf(vig,float(p.get("vignette",0.0)) * a)
		var tc:Color = p.get("tint",Color(1,1,1,0))
		if tc.a * a > tint.a: tint = Color(tc,tc.a * a)
		# 反色是“一闪”：只在最前面的 invert_time 秒内生效，中间夹一帧回正增加冲击。
		var inv_time:float = float(p.get("invert_time",0.0))
		if inv_time > 0.0 and t < inv_time and not (t > inv_time * 0.45 and t < inv_time * 0.6):
			inv = maxf(inv,float(p.get("invert",1.0)))
		var fl:Color = p.get("flash",Color(1,1,1,0))
		var fk:float = clampf(1.0 - t / maxf(float(p.get("flash_time",0.12)),0.01),0.0,1.0)
		if fl.a * fk > flash.a: flash = Color(fl,fl.a * fk)
	var vp:Viewport = get_viewport()
	var size:Vector2 = vp.get_visible_rect().size if vp != null else Vector2(800,600)
	var screen:Vector2 = vp.get_canvas_transform() * center_w if vp != null else size * 0.5
	_mat.set_shader_parameter("center",(screen / size).clamp(Vector2.ZERO,Vector2.ONE))
	_mat.set_shader_parameter("blur",minf(blur,MAX_BLUR))
	_mat.set_shader_parameter("aberration",minf(ab,MAX_ABERRATION))
	_mat.set_shader_parameter("invert",inv)
	_mat.set_shader_parameter("desat",desat)
	_mat.set_shader_parameter("tint",tint)
	_mat.set_shader_parameter("vignette",vig)
	_mat.set_shader_parameter("flash_color",flash)
