extends Node2D

# 菜月昴死档背景“愛してる”（V395 起全部固定红色）。
# 视觉节奏直接复刻 scripts/effects/重女文字.gd：逐字显现、0.12~0.18 秒离散抽帧、
# 每字独立约 ±1px 位移与 ±5° 旋转；但这是纯背景视觉，不参与伤害/碰撞。

const TEXT_VALUE:String = "愛してる"

var reveal_duration:float = 1.65
var lifetime:float = 8.5
var elapsed:float = 0.0
var drift_velocity:Vector2 = Vector2.ZERO
var is_red:bool = true

var _glyph_root:Node2D = null
var _glyphs:Array[Label] = []
var _glyph_base_positions:Array[Vector2] = []
var _shake_elapsed:float = 0.0
var _next_shake_step:float = 0.14
var _font_size:int = 10
var _glyph_advance:float = 10.0
var _shake_strength:float = 0.72
var _rotation_strength_degrees:float = 5.0
var _rng := RandomNumberGenerator.new()

func configure(p_position:Vector2,p_seed:int,p_red:bool = true) -> void:
	global_position = p_position
	is_red = p_red
	_rng.seed = p_seed if p_seed != 0 else Game.battle_rng_seed_or("scripts/effects/动漫/菜月昴背景爱字.gd:fallback_seed",int(Time.get_ticks_usec()))
	drift_velocity = Vector2(_rng.randf_range(-10.0,10.0),_rng.randf_range(-7.0,7.0))
	lifetime = _rng.randf_range(7.4,10.8)
	reveal_duration = _rng.randf_range(1.35,2.15)
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	add_to_group("DeadSaveLoveBackgroundText")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font_size = _rng.randi_range(9,13)
	_glyph_advance = float(_font_size) * 0.92
	_glyph_root = Node2D.new()
	_glyph_root.z_index = 0
	add_child(_glyph_root)
	_build_glyphs()
	_randomize_glyph_offsets()

func _process(delta:float) -> void:
	var dt:float = maxf(delta,0.0)
	elapsed += dt
	_update_reveal()
	_update_text_shake(dt)
	global_position += drift_velocity * dt
	if elapsed >= lifetime:
		queue_free()

func _build_glyphs() -> void:
	_glyphs.clear()
	_glyph_base_positions.clear()
	var count:int = TEXT_VALUE.length()
	var total_width:float = float(count) * _glyph_advance
	var start_x:float = -total_width * 0.5
	for i:int in range(count):
		var glyph := Label.new()
		glyph.text = TEXT_VALUE.substr(i,1)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glyph.add_theme_font_size_override("font_size",_font_size)
		glyph.add_theme_color_override("font_outline_color",Color(0.0,0.0,0.0,0.72))
		glyph.add_theme_constant_override("outline_size",2)
		# V395：死档背景爱字全部固定为红色；保留参数只为兼容旧 configure 调用。
		glyph.modulate = Color(1.0,0.055,0.075,0.86)
		glyph.size = Vector2(_glyph_advance + 3.0,float(_font_size) + 8.0)
		glyph.pivot_offset = glyph.size * 0.5
		var base_pos := Vector2(start_x + float(i) * _glyph_advance,-float(_font_size) * 0.65)
		glyph.position = base_pos
		glyph.visible = false
		_glyph_root.add_child(glyph)
		_glyphs.append(glyph)
		_glyph_base_positions.append(base_pos)

func _update_reveal() -> void:
	if _glyphs.is_empty():
		return
	var progress:float = clampf(elapsed / maxf(reveal_duration,0.1),0.0,1.0)
	var visible_count:int = ceili(progress * float(_glyphs.size()))
	for i:int in range(_glyphs.size()):
		_glyphs[i].visible = i < visible_count

func _update_text_shake(delta:float) -> void:
	_shake_elapsed += delta
	if _shake_elapsed < _next_shake_step:
		return
	_shake_elapsed = 0.0
	_next_shake_step = _rng.randf_range(0.12,0.18)
	_randomize_glyph_offsets()

func _randomize_glyph_offsets() -> void:
	for i:int in range(_glyphs.size()):
		var glyph:Label = _glyphs[i]
		if _rng.randf() >= 0.42:
			var offset := Vector2(
				_rng.randf_range(-_shake_strength,_shake_strength),
				_rng.randf_range(-_shake_strength,_shake_strength)
			)
			offset.x = roundf(offset.x)
			offset.y = roundf(offset.y)
			glyph.position = _glyph_base_positions[i] + offset
		if _rng.randf() >= 0.12:
			var angle:float = _rng.randf_range(-_rotation_strength_degrees,_rotation_strength_degrees)
			glyph.rotation_degrees = snappedf(angle,0.75)
