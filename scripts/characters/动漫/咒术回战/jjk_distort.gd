extends Node2D
## 空间扭曲节点（纯视觉）：在世界坐标画一个正方形/长条，用屏幕纹理做折射。
## mode 0 冲击波环（radius 0→0.45 扩散）、1 漩涡（跟随 follow 回调）、2 空间错位（沿线段）。
const SHADER = preload("res://scripts/characters/动漫/咒术回战/jjk_distort.gdshader")
var mode:int = 0
var life:float = 0.5
var t:float = 0.0
var size:Vector2 = Vector2(200,200)
var strength:float = 20.0
var thickness:float = 0.08
var aberration:float = 1.0
var persistent:bool = false
var follow:Callable
var rot_angle:float = 0.0
var fixed_radius:float = -1.0 ## >=0 时 mode 0 使用固定环半径（常驻透镜边缘）
var _mat:ShaderMaterial

func _ready() -> void:
	top_level = true
	z_as_relative = false
	if z_index == 0: z_index = 87
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material = _mat
	_update(0.0)

func _process(delta:float) -> void:
	if Game.now_stop_state: return
	t += delta
	if not persistent and t >= life:
		queue_free()
		return
	_update(delta)

func _update(_delta:float) -> void:
	if not follow.is_null():
		if not follow.is_valid():
			queue_free()
			return
		var r:Variant = follow.call(self)
		if r is bool and r == false:
			queue_free()
			return
	var k:float = clampf(t / maxf(life,0.001),0.0,1.0)
	var fade:float = 1.0
	match mode:
		0:
			if fixed_radius >= 0.0:
				_mat.set_shader_parameter("radius",fixed_radius)
				fade = 1.0 if persistent else 1.0 - smoothstep(0.7,1.0,k)
			else:
				_mat.set_shader_parameter("radius",0.45 * (1.0 - pow(1.0 - k,3.0)))
				fade = 1.0 - k
		2:
			fade = 1.0 - smoothstep(0.35,1.0,k)
		_:
			fade = 1.0 if persistent else 1.0 - smoothstep(0.7,1.0,k)
	var zoom:Vector2 = get_viewport().get_canvas_transform().get_scale().abs() if get_viewport() != null else Vector2.ONE
	_mat.set_shader_parameter("mode",mode)
	_mat.set_shader_parameter("thickness",thickness)
	_mat.set_shader_parameter("strength",strength * zoom.x)
	_mat.set_shader_parameter("aberration",aberration)
	_mat.set_shader_parameter("fade",fade)
	_mat.set_shader_parameter("rot",rot_angle)
	_mat.set_shader_parameter("px_per_uv",size * zoom)
	queue_redraw()

func _draw() -> void:
	var tex:Texture2D = load("res://scripts/characters/动漫/咒术回战/jjk_vfx.gd").call("glow_tex")
	draw_set_transform(Vector2.ZERO,rot_angle,Vector2.ONE)
	draw_texture_rect(tex,Rect2(-size * 0.5,size),false)
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
