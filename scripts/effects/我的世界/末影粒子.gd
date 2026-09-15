extends Sprite2D
# 原版 portal 粒子使用的 generic_0..7，不再借用药水旋涡。
const FRAMES = [
	preload("res://Images/effects/我的世界/通用粒子/generic_0.png"),
	preload("res://Images/effects/我的世界/通用粒子/generic_1.png"),
	preload("res://Images/effects/我的世界/通用粒子/generic_2.png"),
	preload("res://Images/effects/我的世界/通用粒子/generic_3.png"),
	preload("res://Images/effects/我的世界/通用粒子/generic_4.png"),
	preload("res://Images/effects/我的世界/通用粒子/generic_5.png"),
	preload("res://Images/effects/我的世界/通用粒子/generic_6.png"),
	preload("res://Images/effects/我的世界/通用粒子/generic_7.png"),
]
var frames:Array = FRAMES
var _age:float = 0.0
var _life:float = 0.6
var _start:Vector2
var _motion:Vector2
var _pixel_width:float = 1.1
func setup(point:Vector2,motion:Vector2,lifetime:float = 0.6,size:float = 0.55) -> void:
	global_transform = Transform2D(0.0,point)
	_start = point
	_motion = motion
	_life = lifetime
	texture = frames[0]
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 项目里的原版纹理为 1024px 放大图，必须按世界像素归一化，不能直接乘纹理尺寸。
	_pixel_width = clampf(size*2.0,0.5,5.0)
	scale = Vector2.ONE * (_pixel_width/float(texture.get_width()))
	self_modulate = Color(0.72,0.22,0.95,0.9)
	z_index = 2
	add_to_group("BattleTransient")
	add_to_group("MCEnderParticle")
func _process(delta:float) -> void:
	if Game.now_stop_state or get_tree().paused: return
	_age += delta
	var t:float = clampf(_age/_life,0.0,1.0)
	texture = frames[mini(int(t*frames.size()),frames.size()-1)]
	scale = Vector2.ONE * (_pixel_width/float(texture.get_width()))
	global_position = _start + _motion * (t*t) + Vector2.UP * sin(t*PI)*2.0
	self_modulate.a = 0.9 * (1.0-smoothstep(0.65,1.0,t))
	if t >= 1.0: queue_free()
