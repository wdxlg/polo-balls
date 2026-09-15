extends Node2D

# V69：战争女神变身火焰重新组织成“方块火焰轮廓”。
# - 方块尺寸明显随机，不再像统一像素块。
# - 出生位置按宽底、窄顶、多火舌的火焰包络分布，整体先形成火焰形状再向上升腾。
# - 不向下喷射；运动仍以前快后慢、黄->橙、旋转、缩放、渐隐为主。
# - 效果作为战争女神子节点跟随人物。

@export_range(72,220,1) var cover_block_count:int = 132
@export_range(16,96,1) var crest_block_count:int = 54
@export_range(12,80,1) var rising_block_count:int = 38
@export_range(0.60,2.00,0.01) var min_lifetime:float = 0.84
@export_range(0.60,2.20,0.01) var max_lifetime:float = 1.34
@export_range(0.45,1.80,0.01) var min_rise_body_ratio:float = 0.48
@export_range(0.60,2.40,0.01) var max_rise_body_ratio:float = 1.34
@export_range(1.10,2.20,0.01) var flame_height_ratio:float = 1.58
@export_range(0.50,1.20,0.01) var flame_base_width_ratio:float = 0.90

var _spawned:bool = false
var _elapsed:float = 0.0
var _finish_time:float = 1.45
var _blocks:Array[Dictionary] = []
var _host:Node2D = null
var _host_sprite:Sprite2D = null
var _original_sprite_modulate:Color = Color.WHITE
var _rng := RandomNumberGenerator.new()


func setup(_spread_radius:float = 96.0, amount:int = 20) -> void:
	# 兼容旧调用。amount 只影响密度下限，不再决定火焰轮廓本身。
	cover_block_count = clampi(maxi(116,amount * 5 + 32),72,220)
	crest_block_count = clampi(maxi(46,int(round(float(cover_block_count) * 0.40))),16,96)
	rising_block_count = clampi(maxi(32,int(round(float(cover_block_count) * 0.28))),12,80)
	top_level = false
	position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE


func _ready() -> void:
	add_to_group("BattleTransient")
	top_level = false
	z_as_relative = true
	z_index = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = Game.battle_rng_seed_or("scripts/effects/战争女神_变身火焰.gd:_rng.seed",int(Time.get_ticks_usec()) ^ int(get_instance_id()))
	call_deferred("_spawn_effect")


func _process(delta:float) -> void:
	if not _spawned:
		return
	_elapsed += maxf(delta,0.0)
	_update_character_orange()
	queue_redraw()
	if _elapsed >= _finish_time:
		_restore_character_color()
		queue_free()


func _draw() -> void:
	if not _spawned:
		return
	for block:Dictionary in _blocks:
		var delay:float = float(block.get("delay",0.0))
		var life:float = maxf(float(block.get("life",1.0)),0.01)
		var p:float = (_elapsed - delay) / life
		if p <= 0.0 or p >= 1.0:
			continue
		p = clampf(p,0.0,1.0)

		# 前快后慢：三次 ease-out。所有块只向上移动，水平只允许小幅火苗摆动。
		var move_p:float = 1.0 - pow(1.0 - p,3.0)
		var start:Vector2 = block.get("start",Vector2.ZERO)
		var rise:float = float(block.get("rise",100.0))
		var drift:float = float(block.get("drift",0.0))
		var wiggle_amp:float = float(block.get("wiggle",0.0))
		var phase:float = float(block.get("phase",0.0))
		var wiggle:float = sin(p * PI * 2.2 + phase) * wiggle_amp * (0.25 + p * 0.75)
		var draw_pos := start + Vector2(drift * move_p + wiggle,-rise * move_p)

		# 每块尺寸独立随机；出现时长大，中段轻微呼吸，末段缩小熄灭。
		var size_base:float = float(block.get("size",8.0))
		var appear:float = smoothstep(0.0,0.11,p)
		var vanish:float = 1.0 - smoothstep(0.70,1.0,p)
		var pulse:float = 1.0 + sin(p * PI * 1.35 + phase) * 0.08
		var size_factor:float = lerpf(0.34,1.0,appear) * lerpf(0.38,1.0,vanish) * pulse
		var half:float = maxf(size_base * size_factor * 0.5,0.35)

		# 透明度：很快点燃 -> 中段保持 -> 后段完整渐隐。
		var alpha_in:float = smoothstep(0.0,0.08,p)
		var alpha_out:float = 1.0 - smoothstep(0.60,1.0,p)
		var alpha:float = alpha_in * alpha_out * float(block.get("alpha",0.92))

		# 明黄核心逐渐烧成橙色，越靠近末段越深。
		var hot:Color = block.get("hot",Color(1.0,0.92,0.16,1.0))
		var orange:Color = block.get("orange",Color(1.0,0.30,0.035,1.0))
		var burn_p:float = smoothstep(0.06,0.88,p)
		var color:Color = hot.lerp(orange,burn_p)
		color.a = alpha

		var angle:float = float(block.get("rotation",0.0)) + float(block.get("spin",0.0)) * move_p
		draw_set_transform(draw_pos,angle,Vector2.ONE)
		draw_rect(Rect2(Vector2(-half,-half),Vector2(half * 2.0,half * 2.0)),color,true)

	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)


func _spawn_effect() -> void:
	if _spawned:
		return
	# 形态2切图与 AutoFit 都可能 deferred；多等一帧，使用最终人物实际尺寸。
	await get_tree().process_frame
	if not is_inside_tree() or _spawned:
		return
	_spawned = true
	_host = get_parent() as Node2D
	_host_sprite = _resolve_host_sprite()
	if _host_sprite != null:
		_original_sprite_modulate = _host_sprite.self_modulate

	var visual:Dictionary = _build_visual_sampling_data()
	var body_bounds:Rect2 = visual.get("bounds",Rect2(-70.0,-92.0,140.0,184.0))
	var pixel_scale:float = maxf(float(visual.get("pixel_scale",3.0)),0.6)
	var body_height:float = maxf(body_bounds.size.y,80.0)
	var body_width:float = maxf(body_bounds.size.x,60.0)
	var flame_height:float = body_height * flame_height_ratio
	var flame_bottom_y:float = body_bounds.end.y
	var longest:float = 0.0

	# 主火焰：宽底 -> 窄顶。大部分方块覆盖人物，并在人物上方继续收尖。
	for index:int in range(cover_block_count):
		var h:float = pow(_rng.randf(),1.36) * 0.78
		var start:Vector2 = _sample_flame_envelope(body_bounds,flame_bottom_y,flame_height,h,0)
		var life:float = _rng.randf_range(min_lifetime,max_lifetime)
		var delay:float = _rng.randf_range(0.025,0.16)
		var top_shrink:float = lerpf(1.0,0.66,h)
		var size_px:float = pixel_scale * _rng.randf_range(0.55,2.85) * top_shrink
		var block:Dictionary = _make_block_data(
			start,
			size_px,
			body_height * _rng.randf_range(min_rise_body_ratio,max_rise_body_ratio),
			body_width * _rng.randf_range(-0.055,0.055),
			life,
			delay,
			_rng.randf_range(0.82,0.98)
		)
		_blocks.append(block)
		longest = maxf(longest,delay + life)

	# 火舌尖：中央高火舌 + 左右较矮火舌。让整体轮廓明确像火，而不是人物外形的方块云。
	for index:int in range(crest_block_count):
		var tongue:int = _choose_tongue()
		var max_h:float = 1.0
		if tongue == 1:
			max_h = 0.80
		elif tongue == 2:
			max_h = 0.88
		var h:float = lerpf(0.48,max_h,pow(_rng.randf(),0.82))
		var start:Vector2 = _sample_flame_envelope(body_bounds,flame_bottom_y,flame_height,h,tongue)
		var life:float = _rng.randf_range(0.78,1.22)
		var delay:float = _rng.randf_range(0.05,0.24)
		var size_px:float = pixel_scale * _rng.randf_range(0.45,2.05) * lerpf(0.92,0.58,h)
		var block:Dictionary = _make_block_data(
			start,
			size_px,
			body_height * _rng.randf_range(0.42,1.06),
			body_width * _rng.randf_range(-0.045,0.045),
			life,
			delay,
			_rng.randf_range(0.76,0.94)
		)
		_blocks.append(block)
		longest = maxf(longest,delay + life)

	# 持续升腾的小火苗：从火焰下半部陆续产生，体积更小、上升更远。
	for index:int in range(rising_block_count):
		var h:float = _rng.randf_range(0.02,0.48)
		var start:Vector2 = _sample_flame_envelope(body_bounds,flame_bottom_y,flame_height,h,0)
		var life:float = _rng.randf_range(0.92,1.46)
		var delay:float = _rng.randf_range(0.18,0.58)
		var size_px:float = pixel_scale * _rng.randf_range(0.42,1.78)
		var block:Dictionary = _make_block_data(
			start,
			size_px,
			body_height * _rng.randf_range(0.82,1.62),
			body_width * _rng.randf_range(-0.06,0.06),
			life,
			delay,
			_rng.randf_range(0.66,0.88)
		)
		_blocks.append(block)
		longest = maxf(longest,delay + life)

	_finish_time = maxf(longest + 0.08,1.36)
	queue_redraw()


func _choose_tongue() -> int:
	var roll:float = _rng.randf()
	if roll < 0.52:
		return 0
	if roll < 0.76:
		return 1
	return 2


func _sample_flame_envelope(body_bounds:Rect2,flame_bottom_y:float,flame_height:float,h:float,tongue:int) -> Vector2:
	h = clampf(h,0.0,1.0)
	var body_width:float = maxf(body_bounds.size.x,60.0)
	var center_x:float = body_bounds.get_center().x
	var tongue_offset:float = 0.0
	var tongue_width_scale:float = 1.0
	if tongue == 1:
		tongue_offset = -body_width * 0.19
		tongue_width_scale = 0.57
	elif tongue == 2:
		tongue_offset = body_width * 0.18
		tongue_width_scale = 0.61

	# 主轮廓底部最宽，顶部迅速收尖；轻微左右弯曲形成自然火焰，而不是直三角。
	var taper:float = pow(maxf(1.0 - h,0.02),0.62)
	var half_width:float = body_width * 0.5 * flame_base_width_ratio * (0.10 + taper * 0.90) * tongue_width_scale
	var bend:float = sin(h * 7.4 + float(tongue) * 1.8) * body_width * (0.025 + h * 0.035)
	var x:float = center_x + tongue_offset + bend + _rng.randf_range(-half_width,half_width)
	var y:float = flame_bottom_y - h * flame_height
	return Vector2(x,y)


func _make_block_data(start:Vector2,size_px:float,rise:float,drift:float,life:float,delay:float,alpha:float) -> Dictionary:
	return {
		"start": start,
		"size": maxf(size_px,0.8),
		"rise": rise,
		"drift": drift,
		"life": life,
		"delay": delay,
		"alpha": alpha,
		"rotation": _rng.randf_range(-0.75,0.75),
		"spin": _rng.randf_range(-2.8,2.8),
		"phase": _rng.randf_range(0.0,TAU),
		"wiggle": _rng.randf_range(0.8,4.8),
		"hot": Color(1.0,_rng.randf_range(0.80,0.98),_rng.randf_range(0.06,0.20),1.0),
		"orange": Color(1.0,_rng.randf_range(0.25,0.44),_rng.randf_range(0.01,0.065),1.0)
	}


func _resolve_host_sprite() -> Sprite2D:
	if _host == null:
		return null
	var image_value:Variant = _host.get("image")
	if image_value is Sprite2D:
		return image_value as Sprite2D
	return _host.get_node_or_null("Graphics/Image") as Sprite2D


func _build_visual_sampling_data() -> Dictionary:
	if _host == null or _host_sprite == null or _host_sprite.texture == null:
		return {
			"bounds": Rect2(-70.0,-92.0,140.0,184.0),
			"pixel_scale": 3.0
		}

	var source_image:Image = _host_sprite.texture.get_image()
	if source_image == null or source_image.is_empty():
		return {
			"bounds": Rect2(-70.0,-92.0,140.0,184.0),
			"pixel_scale": 3.0
		}

	var used:Rect2i = source_image.get_used_rect()
	var texture_size:Vector2 = _host_sprite.texture.get_size()
	var full_rect:Rect2 = _host_sprite.get_rect()
	var body_bounds := Rect2()
	var first:bool = true
	if used.size.x > 0 and used.size.y > 0:
		var used_corners := PackedVector2Array([
			Vector2(float(used.position.x),float(used.position.y)),
			Vector2(float(used.end.x),float(used.position.y)),
			Vector2(float(used.end.x),float(used.end.y)),
			Vector2(float(used.position.x),float(used.end.y))
		])
		for pixel:Vector2 in used_corners:
			var local_point:Vector2 = _texture_pixel_to_host_local(pixel,full_rect,texture_size)
			if first:
				body_bounds = Rect2(local_point,Vector2.ZERO)
				first = false
			else:
				body_bounds = body_bounds.expand(local_point)

	var p0:Vector2 = _texture_pixel_to_host_local(Vector2(0.0,0.0),full_rect,texture_size)
	var px:Vector2 = _texture_pixel_to_host_local(Vector2(1.0,0.0),full_rect,texture_size)
	var py:Vector2 = _texture_pixel_to_host_local(Vector2(0.0,1.0),full_rect,texture_size)
	var pixel_scale:float = maxf(p0.distance_to(px),p0.distance_to(py))
	if body_bounds.size.x <= 0.1 or body_bounds.size.y <= 0.1:
		body_bounds = Rect2(-70.0,-92.0,140.0,184.0)

	return {
		"bounds": body_bounds,
		"pixel_scale": pixel_scale
	}


func _texture_pixel_to_host_local(pixel:Vector2,full_rect:Rect2,texture_size:Vector2) -> Vector2:
	if _host == null or _host_sprite == null or texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return Vector2.ZERO
	var ratio := Vector2(pixel.x / texture_size.x,pixel.y / texture_size.y)
	var sprite_local := full_rect.position + full_rect.size * ratio
	return _host.to_local(_host_sprite.to_global(sprite_local))


func _update_character_orange() -> void:
	if _host_sprite == null or not is_instance_valid(_host_sprite):
		return
	# 人物先整体燃成橙色，再逐渐恢复；方块火焰同时覆盖并升腾。
	var intensity:float = 0.0
	if _elapsed < 0.10:
		intensity = smoothstep(0.0,0.10,_elapsed) * 0.72
	elif _elapsed < 0.34:
		intensity = 0.72
	elif _elapsed < 0.86:
		intensity = (1.0 - smoothstep(0.34,0.86,_elapsed)) * 0.72
	var orange := Color(1.0,0.38,0.055,_original_sprite_modulate.a)
	var mixed:Color = _original_sprite_modulate.lerp(orange,intensity)
	mixed.a = _original_sprite_modulate.a
	_host_sprite.self_modulate = mixed


func _restore_character_color() -> void:
	if _host_sprite != null and is_instance_valid(_host_sprite):
		_host_sprite.self_modulate = _original_sprite_modulate


func _exit_tree() -> void:
	_restore_character_color()
