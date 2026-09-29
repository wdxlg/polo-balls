extends Node2D

const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")

var master:ball
var text_value:String = "..."
var is_red:bool = false
var reveal_duration:float = 3.6
var min_damage:float = 5.0
var max_damage:float = 55.0
var drift_velocity:Vector2 = Vector2.ZERO
var lifetime:float = 11.0
var collision_radius:float = 20.0
var elapsed:float = 0.0
var absorbed:bool = false
var pull_target:ball = null
var pull_radius:float = 0.0
var visual_only:bool = false

# 文字由独立字形 Label 组成。每个字单独抖动，判定节点本身不抖。
var _glyph_root:Node2D
var _glyphs:Array[Label] = []
var _glyph_base_positions:Array[Vector2] = []
var _shake_elapsed:float = 0.0
var _next_shake_step:float = 0.14
var _font_size:int = 10
var _glyph_advance:float = 10.0
var _shake_strength:float = 0.72
var _rotation_strength_degrees:float = 5.0

func setup(p_master:ball,p_text:String,p_red:bool,p_position:Vector2,p_seed:int = 0,p_visual_only:bool = false) -> void:
	master = p_master
	# 原始文本在每个 peer 本地翻译，不能把房主已经翻译后的字符串复制给客户端。
	text_value = Game.t(p_text)
	is_red = p_red
	global_position = p_position
	visual_only = p_visual_only
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed if p_seed != 0 else Game.battle_rng_seed_or("scripts/effects/重女文字.gd:fallback_seed",int(Time.get_ticks_usec()))
	drift_velocity = Vector2(rng.randf_range(-18.0,18.0),rng.randf_range(-12.0,12.0))

func _ready() -> void:
	add_to_group("HeavyGirlText")
	_font_size = randi_range(9,12)
	_glyph_advance = float(_font_size) * 0.92
	_glyph_root = Node2D.new()
	_glyph_root.z_index = 9
	add_child(_glyph_root)
	_build_glyphs()
	_randomize_glyph_offsets()

func _build_glyphs() -> void:
	_glyphs.clear()
	_glyph_base_positions.clear()
	var count:int = text_value.length()
	if count <= 0:
		return
	var total_width:float = float(count) * _glyph_advance
	var start_x:float = -total_width * 0.5
	for i:int in range(count):
		var glyph:Label = Label.new()
		glyph.text = text_value.substr(i,1)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.add_theme_font_size_override("font_size",_font_size)
		glyph.modulate = Color(1.0,0.16,0.16,0.95) if is_red else Color(1.0,1.0,1.0,0.92)
		glyph.size = Vector2(_glyph_advance + 3.0,float(_font_size) + 8.0)
		# 围绕单个字符自己的中心做轻微旋转，而不是绕左上角摆动。
		glyph.pivot_offset = glyph.size * 0.5
		var base_pos:Vector2 = Vector2(start_x + float(i) * _glyph_advance,-float(_font_size) * 0.65)
		glyph.position = base_pos
		glyph.visible = false
		_glyph_root.add_child(glyph)
		_glyphs.append(glyph)
		_glyph_base_positions.append(base_pos)

func set_pull_target(target:ball,p_radius:float = 0.0) -> void:
	pull_target = target
	pull_radius = maxf(p_radius,0.0)

func _physics_process(delta:float) -> void:
	if master == null or not is_instance_valid(master):
		queue_free()
		return
	elapsed += delta
	_update_reveal()
	_update_text_shake(delta)
	var pulled_this_frame:bool = false
	if pull_target != null and is_instance_valid(pull_target) and pull_target.health > 0:
		var to_target:Vector2 = pull_target.global_position - global_position
		var distance:float = to_target.length()
		# 黑洞吸力有明确范围；范围外文字保持原来的漂移，不会跨整张地图被强拉过去。
		if pull_radius > 0.0 and distance <= pull_radius and distance > 1.0:
			var proximity:float = clampf(1.0 - distance / pull_radius,0.0,1.0)
			var speed:float = lerpf(30.0,240.0,pow(proximity,1.25))
			global_position += to_target.normalized() * speed * delta
			pulled_this_frame = true
			if distance < 18.0:
				absorbed = true
				queue_free()
				return
	if not pulled_this_frame:
		global_position += drift_velocity * delta
	if not visual_only:
		_damage_enemies()
	if elapsed >= lifetime:
		queue_free()

func _update_reveal() -> void:
	if _glyphs.is_empty():
		return
	var progress:float = clampf(elapsed / maxf(reveal_duration,0.1),0.0,1.0)
	var visible_count:int = ceili(progress * float(_glyphs.size()))
	for i:int in range(_glyphs.size()):
		_glyphs[i].visible = i < visible_count

func _update_text_shake(delta:float) -> void:
	# 故意用低频、离散的位置跳变，不做逐帧插值，形成“抽帧”式颤抖。
	_shake_elapsed += delta
	if _shake_elapsed < _next_shake_step:
		return
	_shake_elapsed = 0.0
	_next_shake_step = randf_range(0.12,0.18)
	_randomize_glyph_offsets()

func _randomize_glyph_offsets() -> void:
	for i:int in range(_glyphs.size()):
		var glyph:Label = _glyphs[i]
		# 位置只做很小的离散跳动，并且不少拍保持原位，避免整行看起来乱窜。
		if randf() >= 0.42:
			var offset := Vector2(
				randf_range(-_shake_strength,_shake_strength),
				randf_range(-_shake_strength,_shake_strength)
			)
			# 保留像素级抽帧感：实际只会落在 -1 / 0 / 1 像素附近。
			offset.x = roundf(offset.x)
			offset.y = roundf(offset.y)
			glyph.position = _glyph_base_positions[i] + offset

		# 旋转比位移更明显，而且独立更新；这样能清楚看到单个字一拍一拍地轻微歪斜。
		if randf() >= 0.12:
			var angle:float = randf_range(-_rotation_strength_degrees,_rotation_strength_degrees)
			glyph.rotation_degrees = snappedf(angle,0.75)

func current_damage() -> float:
	var progress:float = clampf(elapsed / maxf(reveal_duration,0.1),0.0,1.0)
	var value:float = lerpf(min_damage,max_damage,progress)
	return value * (2.0 if is_red else 1.0)

func _damage_enemies() -> void:
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var target:ball = raw as ball
		if target.Type == ball.Ball_Type.Shooter or target.Type == ball.Ball_Type.Shooter_with_Health:
			continue
		if not TOOLS.is_enemy(master,target):
			continue
		if global_position.distance_to(target.global_position) > collision_radius:
			continue
		if target.has_method("try_full_projectile_dodge") and bool(target.call("try_full_projectile_dodge",self)): continue
		var dealt_damage:float = current_damage()
		var did_damage:bool = target.receive_positional_damage(dealt_damage,global_position,false,master)
		if did_damage:
			_play_character_hit_sfx(dealt_damage)
		queue_free()
		return

func _play_character_hit_sfx(dealt_damage:float) -> void:
	# 与人物正常碰撞/命中使用同一套 balls_hit1 音效。
	var hit_volume:float = clampf(maxf(dealt_damage,0.0) - 12.0,-100.0,0.0)
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc("balls_hit1",{volume = hit_volume},true,true)
	else:
		Audios.play_sfx("balls_hit1",{volume = hit_volume},true,true)
