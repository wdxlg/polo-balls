extends Node2D

# 殷红迷雾血肉刀光类型；全部只负责视觉，不参与伤害、攻击检测或威胁区域。
enum BladeLightKind {
	THRUST, # 突刺：一开始粗，后面逐步收成尖端。
	SLASH, # 斩击：一开始较窄，后面越来越厚，并保留破洞与撕裂尾缘。
	HORIZONTAL, # 尸横遍野：使用加长版斩击刀幕。
	EXECUTION, # 血雾弥漫：围绕处决目标生成短促血肉斩光。
}

const MASK_SLASH:Texture2D = preload("res://Images/characters/月计/殷红迷雾/刀光斩击遮罩.png")
const MASK_THRUST:Texture2D = preload("res://Images/characters/月计/殷红迷雾/刀光突刺遮罩.png")
const BLOOD_TRAIL_SHADER:Shader = preload("res://shaders/殷红迷雾_血肉拖尾.gdshader")

var _lifetime:float = 0.72
var _elapsed:float = 0.0
var _kind:int = BladeLightKind.SLASH
var _effect_size:Vector2 = Vector2(180.0,140.0)
var _visual_width:float = 72.0
var _sweep_sign:float = 1.0
var _character_local_position:Vector2 = Vector2(-64.0,0.0)
var _ego_variant:bool = false
var _tint:Color = Color(0.95,0.0,0.012,1.0)
var _sprite:Sprite2D = null
var _material:ShaderMaterial = null

# 配置一次 GPU 血肉刀光；主体、深红流动与眼睛全部由单个 Sprite2D Shader 完成。
func configure(
	kind:int,
	attack_size:Vector2,
	visual_width:float,
	tint:Color,
	lifetime:float,
	sweep_sign:float = 1.0,
	character_local_position:Vector2 = Vector2(-64.0,0.0),
	ego_variant:bool = false
) -> void:
	_kind = kind
	_effect_size = Vector2(maxf(attack_size.x,1.0),maxf(attack_size.y,1.0))
	_visual_width = maxf(visual_width,18.0)
	_tint = tint
	_lifetime = maxf(lifetime,0.28)
	_elapsed = 0.0
	_sweep_sign = -1.0 if sweep_sign < 0.0 else 1.0
	_character_local_position = character_local_position
	_ego_variant = ego_variant
	z_as_relative = false
	z_index = 92 # 地图外遮罩=90；刀光允许越出地图，仍低于血条/边框。
	_build_sprite() # 重要：只创建 1 个实际刀光 Sprite，不再每帧生成上千个三角形和眼睛节点。
	_update_material(0.0)
	set_process(true)

# 创建刀光 Sprite 与独立 ShaderMaterial，并让遮罩起点贴近角色/武器侧。
func _build_sprite() -> void:
	var mask:Texture2D = MASK_THRUST if _kind == BladeLightKind.THRUST else MASK_SLASH
	if mask == null or BLOOD_TRAIL_SHADER == null:
		queue_free()
		return
	_sprite = Sprite2D.new()
	_sprite.name = "GPU血肉刀光"
	_sprite.texture = mask
	_sprite.centered = true
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_sprite)

	var target_height:float = _target_height()
	var tex_size:Vector2 = mask.get_size()
	var safe_tex_width:float = maxf(tex_size.x,1.0)
	var safe_tex_height:float = maxf(tex_size.y,1.0)
	_sprite.scale = Vector2(_effect_size.x / safe_tex_width,target_height / safe_tex_height)
	_sprite.scale.y *= _sweep_sign # 重要：E.G.O 第二斩只翻转刀幕上下方向，不改变真实攻击 Transform。
	_sprite.position = Vector2.ZERO # 攻击框已包含前伸偏移，不再二次叠加人物位置。

	_material = ShaderMaterial.new()
	_material.shader = BLOOD_TRAIL_SHADER
	_material.set_shader_parameter("tint",_tint)
	_material.set_shader_parameter("ego_strength",1.0 if _ego_variant else 0.0)
	_material.set_shader_parameter("seed",_visual_seed())
	_material.set_shader_parameter("eye_density",0.28 if _ego_variant else 0.0)
	_material.set_shader_parameter("blade_kind",_kind)
	_material.set_shader_parameter("flow_speed",1.28 if _ego_variant else 1.0)
	_sprite.material = _material

# 返回不同攻击类型的视觉刀幕高度；只影响画面，不改变真实碰撞范围。
func _target_height() -> float:
	return _effect_size.y # 完整世界尺寸；不再按固定像素高度拉宽小比例角色的刀光。

# 生成多人端一致的视觉 seed；不使用本机随机时间，确保相同攻击参数得到同一套内部纹理。
func _visual_seed() -> float:
	var raw:float = absf(_effect_size.x * 0.013 + _effect_size.y * 0.029 + float(_kind) * 1.73 + _sweep_sign * 0.41)
	return fmod(raw,17.0)

# 每帧只更新少量 Shader 参数；不调用 queue_redraw，不创建任何网格/眼睛节点。
func _process(delta:float) -> void:
	if Game.now_stop_state:
		return
	_elapsed += maxf(delta,0.0)
	_update_material(_elapsed / maxf(_lifetime,0.001))
	if _elapsed >= _lifetime:
		queue_free()

# 更新刀光头尾、透明度和内部动画时间；所有像素动画由 GPU 完成。
func _update_material(normalized_time:float) -> void:
	if _material == null:
		return
	var t:float = clampf(normalized_time,0.0,1.0)
	var head:float = smoothstep(0.0,0.16,t)
	var tail:float = 0.0 if t < 0.22 else smoothstep(0.22,0.98,t) * 0.985
	tail = minf(tail,maxf(head - 0.16,0.0))
	var opacity:float = smoothstep(0.0,0.02,t) * (1.0 - smoothstep(0.18,1.0,t))
	_material.set_shader_parameter("head_progress",head)
	_material.set_shader_parameter("tail_progress",tail)
	_material.set_shader_parameter("opacity",opacity)
	_material.set_shader_parameter("anim_time",_elapsed)
