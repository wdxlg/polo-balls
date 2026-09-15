extends CanvasLayer

signal finished

const INTRO_LENGTH:float = 2.65
const PUSH_TIME:float = 1.72
const HOLD_TIME:float = 0.56
const FADE_TIME:float = 0.32

const BOSS_BG_1:Texture2D = preload("res://Images/UI/BossIntro/星空1.jpg")
const BOSS_BG_2:Texture2D = preload("res://Images/UI/BossIntro/星空2.jpg")
const BOSS_WHIP_1:AudioStream = preload("res://audio/sfx/boss/鞭子1.mp3")
const BOSS_WHIP_2:AudioStream = preload("res://audio/sfx/boss/鞭子2.mp3")
const BOSS_WHIP_3:AudioStream = preload("res://audio/sfx/boss/鞭子3.mp3")
const BOSS_BLOOD_1:Texture2D = preload("res://Images/UI/BossIntro/Blood/黑血1.png")
const BOSS_BLOOD_2:Texture2D = preload("res://Images/UI/BossIntro/Blood/黑血2.png")
const BOSS_BLOOD_3:Texture2D = preload("res://Images/UI/BossIntro/Blood/黑血3.png")
const BOSS_BLOOD_4:Texture2D = preload("res://Images/UI/BossIntro/Blood/黑血4.png")

var _screen_root:Control
var _camera_layer:Node2D
var _far_layer:Node2D
var _ink_layer:Node2D
var _portrait_layer:Node2D
var _text_layer:Node2D
var _rng := RandomNumberGenerator.new()
var _layout:Dictionary = {}
var _intro_volume_db:float = -3.0
var _blood_bounds_cache:Dictionary = {}

func _ready() -> void:
	# v17：保证 Boss 开场位于工具栏/设置面板之上，不会出现“其实播放了但被 UI 盖住”的情况。
	layer = 1000
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = Game.battle_rng_seed_or("scripts/ui/boss_intro_overlay.gd:_rng",int(Time.get_ticks_usec()) ^ int(get_instance_id()))


func play_intro(boss:Node, boss_name:String, multiplier:float, specialized:bool, intro_volume_db:float = -3.0) -> void:
	_intro_volume_db = intro_volume_db
	_build_visuals(boss,boss_name,multiplier,specialized)
	_play_random_boss_whip()
	_start_animation()


func _build_visuals(boss:Node, boss_name:String, multiplier:float, specialized:bool) -> void:
	var viewport_size:Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.x < 64.0 or viewport_size.y < 64.0:
		viewport_size = Vector2(1280.0,720.0)

	_layout = _make_layout(_rng.randi_range(0,5),viewport_size)

	_screen_root = Control.new()
	_screen_root.name = "BossIntroScreen"
	_screen_root.anchor_right = 1.0
	_screen_root.anchor_bottom = 1.0
	_screen_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_screen_root.clip_contents = true
	_screen_root.modulate = Color(1.0,1.0,1.0,0.0)
	add_child(_screen_root)

	var base := ColorRect.new()
	base.anchor_right = 1.0
	base.anchor_bottom = 1.0
	base.color = Color(0.008,0.016,0.045,1.0)
	base.z_index = -1000
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_root.add_child(base)

	_camera_layer = Node2D.new()
	_camera_layer.name = "IntroCamera"
	_screen_root.add_child(_camera_layer)

	_far_layer = Node2D.new()
	_far_layer.name = "FarBackground"
	_far_layer.z_index = -900
	_screen_root.add_child(_far_layer)
	_build_star_background(_far_layer,viewport_size)

	_ink_layer = Node2D.new()
	_ink_layer.name = "BlackBlood"
	_ink_layer.z_index = 10
	_camera_layer.add_child(_ink_layer)
	_build_black_blood(_ink_layer,viewport_size,_layout.text_rect,int(_layout.id),specialized)

	_portrait_layer = Node2D.new()
	_portrait_layer.name = "BossPortrait"
	_portrait_layer.z_index = 20
	_camera_layer.add_child(_portrait_layer)
	_build_portrait(_portrait_layer,_layout.portrait_rect,_extract_boss_texture(boss))

	_text_layer = Node2D.new()
	_text_layer.name = "BossText"
	_text_layer.z_index = 30
	_camera_layer.add_child(_text_layer)
	_build_text(_text_layer,viewport_size,_layout.text_rect,boss_name,multiplier,specialized)

	var focus:Vector2 = _layout.focus
	var start_scale:float = float(_layout.start_scale)
	_camera_layer.scale = Vector2.ONE * start_scale
	_camera_layer.position = focus * (1.0 - start_scale)

	_far_layer.position = Vector2(_layout.far_start) * 0.12
	_ink_layer.position = _layout.ink_start
	_portrait_layer.position = _layout.portrait_start
	_text_layer.position = _layout.text_start


func _make_layout(id:int,size:Vector2) -> Dictionary:
	var aspect:float = size.x / maxf(size.y,1.0)
	var v:int = posmod(id,6)

	# v24：按宽高比分成两组布局，每组都有 6 个真正不同的构图。
	# 窄屏不是简单镜像：既有顶部横幅，也有左上/右上文字块和不同人物裁切位置。
	if aspect < 0.92:
		var text_rect:Rect2
		var portrait_rect:Rect2
		var focus:Vector2
		var far_start:=Vector2.ZERO
		var ink_start:=Vector2.ZERO
		var portrait_start:=Vector2.ZERO
		var text_start:=Vector2.ZERO
		match v:
			0:
				# 海报式：超大标题在上，人物正中偏下。
				text_rect = Rect2(size.x * 0.045,size.y * 0.045,size.x * 0.91,size.y * 0.34)
				portrait_rect = Rect2(size.x * 0.045,size.y * 0.325,size.x * 0.91,size.y * 0.84)
				far_start = Vector2(-20.0,9.0)
				ink_start = Vector2(0.0,-42.0)
				portrait_start = Vector2(-26.0,54.0)
				text_start = Vector2(18.0,-30.0)
			1:
				# 海报式镜像移动，但人物偏右，给标题留下更多左侧呼吸区。
				text_rect = Rect2(size.x * 0.055,size.y * 0.065,size.x * 0.87,size.y * 0.33)
				portrait_rect = Rect2(size.x * 0.115,size.y * 0.34,size.x * 0.86,size.y * 0.82)
				far_start = Vector2(22.0,8.0)
				ink_start = Vector2(18.0,-32.0)
				portrait_start = Vector2(40.0,48.0)
				text_start = Vector2(-28.0,-24.0)
			2:
				# 左上标题、人物右下。
				text_rect = Rect2(size.x * 0.035,size.y * 0.075,size.x * 0.73,size.y * 0.34)
				portrait_rect = Rect2(size.x * 0.20,size.y * 0.39,size.x * 0.79,size.y * 0.76)
				far_start = Vector2(-30.0,12.0)
				ink_start = Vector2(-24.0,-18.0)
				portrait_start = Vector2(54.0,46.0)
				text_start = Vector2(-50.0,-18.0)
			3:
				# 右上标题、人物左下。
				text_rect = Rect2(size.x * 0.235,size.y * 0.075,size.x * 0.73,size.y * 0.34)
				portrait_rect = Rect2(size.x * 0.01,size.y * 0.39,size.x * 0.79,size.y * 0.76)
				far_start = Vector2(30.0,12.0)
				ink_start = Vector2(24.0,-18.0)
				portrait_start = Vector2(-54.0,46.0)
				text_start = Vector2(50.0,-18.0)
			4:
				# 标题略低、人物偏左，形成杂志封面式错位。
				text_rect = Rect2(size.x * 0.30,size.y * 0.105,size.x * 0.66,size.y * 0.36)
				portrait_rect = Rect2(size.x * 0.00,size.y * 0.355,size.x * 0.76,size.y * 0.80)
				far_start = Vector2(-18.0,-8.0)
				ink_start = Vector2(38.0,-12.0)
				portrait_start = Vector2(-46.0,52.0)
				text_start = Vector2(58.0,-14.0)
			_:
				# 标题略低、人物偏右。
				text_rect = Rect2(size.x * 0.04,size.y * 0.105,size.x * 0.66,size.y * 0.36)
				portrait_rect = Rect2(size.x * 0.24,size.y * 0.355,size.x * 0.76,size.y * 0.80)
				far_start = Vector2(18.0,-8.0)
				ink_start = Vector2(-38.0,-12.0)
				portrait_start = Vector2(46.0,52.0)
				text_start = Vector2(-58.0,-14.0)
		focus = text_rect.get_center()
		return {
			"id": v,
			"portrait_rect": portrait_rect,
			"text_rect": text_rect,
			"focus": focus,
			"start_scale": 0.945 if v < 2 else 0.955,
			"end_scale": 1.032 if v < 2 else 1.042,
			"far_start": far_start,
			"ink_start": ink_start,
			"portrait_start": portrait_start,
			"text_start": text_start,
		}

	# 横屏：6 种分栏/错位构图。所有版本都让 portrait_rect 与 text_rect 主区域分离，
	# 允许人物下半身出框，但不让人物脸部挡住标题。
	var text_rect:Rect2
	var portrait_rect:Rect2
	var portrait_left:bool = v in [0,2,4]
	match v:
		0:
			portrait_rect = Rect2(size.x * 0.015,size.y * 0.025,size.x * 0.47,size.y * 1.09)
			text_rect = Rect2(size.x * 0.50,size.y * 0.115,size.x * 0.47,size.y * 0.50)
		1:
			portrait_rect = Rect2(size.x * 0.515,size.y * 0.025,size.x * 0.47,size.y * 1.09)
			text_rect = Rect2(size.x * 0.03,size.y * 0.115,size.x * 0.47,size.y * 0.50)
		2:
			portrait_rect = Rect2(size.x * 0.00,size.y * 0.00,size.x * 0.50,size.y * 1.14)
			text_rect = Rect2(size.x * 0.50,size.y * 0.315,size.x * 0.46,size.y * 0.49)
		3:
			portrait_rect = Rect2(size.x * 0.50,size.y * 0.00,size.x * 0.50,size.y * 1.14)
			text_rect = Rect2(size.x * 0.04,size.y * 0.315,size.x * 0.46,size.y * 0.49)
		4:
			portrait_rect = Rect2(size.x * 0.035,size.y * 0.075,size.x * 0.43,size.y * 1.04)
			text_rect = Rect2(size.x * 0.455,size.y * 0.055,size.x * 0.52,size.y * 0.55)
		_:
			portrait_rect = Rect2(size.x * 0.535,size.y * 0.075,size.x * 0.43,size.y * 1.04)
			text_rect = Rect2(size.x * 0.025,size.y * 0.055,size.x * 0.52,size.y * 0.55)

	var text_high:bool = v in [0,1,4,5]
	return {
		"id": v,
		"portrait_rect": portrait_rect,
		"text_rect": text_rect,
		"focus": text_rect.get_center(),
		"start_scale": 0.92 if v < 4 else 0.935,
		"end_scale": 1.052 if v < 4 else 1.045,
		"far_start": Vector2(-40.0 if portrait_left else 40.0,12.0 if text_high else -8.0),
		"ink_start": Vector2(46.0 if portrait_left else -46.0,-20.0 if text_high else 22.0),
		"portrait_start": Vector2(-78.0 if portrait_left else 78.0,24.0),
		"text_start": Vector2(82.0 if portrait_left else -82.0,-20.0 if text_high else 24.0),
	}


func _build_star_background(parent:Node2D,size:Vector2) -> void:
	var texture:Texture2D = BOSS_BG_1 if _rng.randi_range(0,1) == 0 else BOSS_BG_2
	if texture == null:
		texture = BOSS_BG_1 if BOSS_BG_1 != null else BOSS_BG_2
	if texture == null:
		push_error("BossIntro: 两张星空背景都未加载")
		return
	var tex_size:Vector2 = texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return

	# 按用户要求：保持原比例，以“图片高度 = 窗口高度”为基准，主图始终居中。
	# 额外增加 4% overscan，给轻微视差留余量；若横向仍不够宽，只在左右补同图，
	# 主画面始终是原图中间区域，不会因为镜头推进露出纯黑底。
	var scale_by_height:float = (size.y / tex_size.y) * 1.04
	var scaled_width:float = tex_size.x * scale_by_height
	var tiles_each_side:int = maxi(1,ceili((size.x * 0.5 + 64.0) / maxf(scaled_width,1.0)))
	for tile_x:int in range(-tiles_each_side,tiles_each_side + 1):
		var bg := Sprite2D.new()
		bg.name = "Starfield_%d" % tile_x
		bg.texture = texture
		bg.centered = true
		bg.position = Vector2(size.x * 0.5 + float(tile_x) * scaled_width,size.y * 0.5)
		bg.scale = Vector2.ONE * scale_by_height
		bg.z_index = 0
		parent.add_child(bg)

	# 只做很轻的压暗，提高白字/黑血可读性；不是黑色遮罩。
	var dim := ColorRect.new()
	dim.name = "StarfieldDim"
	dim.position = Vector2.ZERO
	dim.size = size
	dim.color = Color(0.01,0.015,0.04,0.14)
	dim.z_index = 1
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(dim)


func _build_black_blood(parent:Node2D,_size:Vector2,text_rect:Rect2,layout_id:int,_specialized:bool) -> void:
	# 每次只使用一张投稿血迹作为文字底板，避免多张叠加把版面弄乱。
	# 关键：按 PNG 的“实际非透明血迹边界”居中，而不是按整张图片画布居中。
	var blood_textures:Array[Texture2D] = [BOSS_BLOOD_1,BOSS_BLOOD_2,BOSS_BLOOD_3,BOSS_BLOOD_4]
	var texture:Texture2D = blood_textures[_rng.randi_range(0,blood_textures.size() - 1)]
	var target_size:Vector2 = Vector2(text_rect.size.x * 1.02,text_rect.size.y * 1.06)
	_add_blood_texture_centered_on_alpha(parent,texture,text_rect.get_center(),target_size,layout_id)


func _get_texture_alpha_bounds(texture:Texture2D) -> Rect2:
	if texture == null:
		return Rect2()
	var key:String = texture.resource_path
	if _blood_bounds_cache.has(key):
		return _blood_bounds_cache[key]
	var image:Image = texture.get_image()
	if image == null or image.is_empty():
		var fallback := Rect2(Vector2.ZERO,texture.get_size())
		_blood_bounds_cache[key] = fallback
		return fallback
	var min_x:int = image.get_width()
	var min_y:int = image.get_height()
	var max_x:int = -1
	var max_y:int = -1
	for y:int in range(image.get_height()):
		for x:int in range(image.get_width()):
			if image.get_pixel(x,y).a > 0.035:
				min_x = mini(min_x,x)
				min_y = mini(min_y,y)
				max_x = maxi(max_x,x)
				max_y = maxi(max_y,y)
	var bounds:Rect2
	if max_x < min_x or max_y < min_y:
		bounds = Rect2(Vector2.ZERO,texture.get_size())
	else:
		bounds = Rect2(Vector2(min_x,min_y),Vector2(max_x - min_x + 1,max_y - min_y + 1))
	_blood_bounds_cache[key] = bounds
	return bounds


func _add_blood_texture_centered_on_alpha(parent:Node2D,texture:Texture2D,target_center:Vector2,target_size:Vector2,variant:int) -> void:
	if texture == null:
		return
	var tex_size:Vector2 = texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	var alpha_bounds:Rect2 = _get_texture_alpha_bounds(texture)
	if alpha_bounds.size.x <= 0.0 or alpha_bounds.size.y <= 0.0:
		alpha_bounds = Rect2(Vector2.ZERO,tex_size)

	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = true
	# 用实际血迹包围盒覆盖文字区；不会因为 PNG 周围透明留白造成“文字没在血中心”。
	var uniform_scale:float = maxf(target_size.x / alpha_bounds.size.x,target_size.y / alpha_bounds.size.y)
	sprite.scale = Vector2.ONE * uniform_scale
	# 只做水平镜像产生少量变化，不旋转，避免血迹正文区倾斜导致排版失衡。
	sprite.flip_h = (variant % 2) == 1
	var texture_center:Vector2 = tex_size * 0.5
	var visible_center:Vector2 = alpha_bounds.position + alpha_bounds.size * 0.5
	var visible_offset:Vector2 = visible_center - texture_center
	if sprite.flip_h:
		visible_offset.x = -visible_offset.x
	sprite.position = target_center - visible_offset * uniform_scale
	sprite.modulate = Color(0.0,0.0,0.0,1.0)
	sprite.z_index = 0
	parent.add_child(sprite)


func _build_portrait(parent:Node2D,rect:Rect2,texture:Texture2D) -> void:
	if texture == null:
		var fallback := PackedVector2Array([
			Vector2(rect.position.x + rect.size.x * 0.12,rect.end.y),
			Vector2(rect.position.x + rect.size.x * 0.18,rect.position.y + rect.size.y * 0.28),
			Vector2(rect.position.x + rect.size.x * 0.42,rect.position.y + rect.size.y * 0.06),
			Vector2(rect.position.x + rect.size.x * 0.72,rect.position.y + rect.size.y * 0.26),
			Vector2(rect.position.x + rect.size.x * 0.88,rect.end.y),
		])
		_add_polygon(parent,fallback,Color(0.82,0.82,0.84,0.92))
		return

	# 和血迹一样按“人物实际非透明区域”计算大小，避免原图透明留白导致 Boss 看起来太小。
	# portrait rect 会延伸到窗口底部之外，因此人物下半身可以自然被裁掉，但头部/上半身保持足够大。
	var tex_size:Vector2 = texture.get_size()
	var visible_bounds:Rect2 = _get_texture_alpha_bounds(texture)
	if visible_bounds.size.x <= 0.0 or visible_bounds.size.y <= 0.0:
		visible_bounds = Rect2(Vector2.ZERO,tex_size)
	var fit_scale:float = minf((rect.size.x * 0.94) / visible_bounds.size.x,rect.size.y / visible_bounds.size.y)
	fit_scale = maxf(fit_scale,0.001)
	var texture_center:Vector2 = tex_size * 0.5
	var visible_center:Vector2 = visible_bounds.position + visible_bounds.size * 0.5
	var visible_offset:Vector2 = visible_center - texture_center
	var target_center:Vector2 = rect.get_center() + Vector2(0.0,rect.size.y * 0.025)

	var shadow := Sprite2D.new()
	shadow.texture = texture
	shadow.centered = true
	shadow.scale = Vector2.ONE * fit_scale
	shadow.position = target_center - visible_offset * fit_scale + Vector2(12.0,10.0)
	shadow.modulate = Color(0.0,0.0,0.0,0.52)
	parent.add_child(shadow)

	var portrait := Sprite2D.new()
	portrait.texture = texture
	portrait.centered = true
	portrait.scale = Vector2.ONE * fit_scale
	portrait.position = target_center - visible_offset * fit_scale
	parent.add_child(portrait)


func _build_text(parent:Node2D,size:Vector2,text_rect:Rect2,boss_name:String,_multiplier:float,_specialized:bool) -> void:
	var chinese_ui:bool = not str(Game.current_locale).begins_with("en")
	var inset_x:float = text_rect.size.x * 0.075
	var inner_x:float = text_rect.position.x + inset_x
	var inner_w:float = text_rect.size.x - inset_x * 2.0

	# 只保留两级信息：BOSS 来袭 + 角色名。
	# 全部以血迹实际中心所在的 text_rect 为基准居中，不再显示倍率条。
	var kicker := Label.new()
	kicker.text = "BOSS 来袭" if chinese_ui else "BOSS ENCOUNTER"
	kicker.position = Vector2(inner_x,text_rect.position.y + text_rect.size.y * 0.12)
	kicker.size = Vector2(inner_w,text_rect.size.y * 0.24)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kicker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	kicker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kicker.add_theme_font_size_override("font_size",clampi(roundi(size.y * 0.052),30,68))
	kicker.add_theme_color_override("font_color",Color(1.0,0.27,0.34,1.0))
	kicker.add_theme_color_override("font_outline_color",Color(0.0,0.0,0.0,1.0))
	kicker.add_theme_constant_override("outline_size",4)
	parent.add_child(kicker)

	var title := Label.new()
	title.text = boss_name
	title.position = Vector2(inner_x,text_rect.position.y + text_rect.size.y * 0.34)
	title.size = Vector2(inner_w,text_rect.size.y * 0.48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title_size:int = roundi(size.y * 0.145)
	if boss_name.length() >= 10:
		title_size = roundi(size.y * 0.082)
	elif boss_name.length() >= 8:
		title_size = roundi(size.y * 0.094)
	elif boss_name.length() >= 6:
		title_size = roundi(size.y * 0.108)
	elif boss_name.length() >= 4:
		title_size = roundi(size.y * 0.126)
	title.add_theme_font_size_override("font_size",clampi(title_size,58,138))
	title.add_theme_color_override("font_color",Color(0.99,0.99,0.99,1.0))
	title.add_theme_color_override("font_outline_color",Color(0.0,0.0,0.0,1.0))
	title.add_theme_constant_override("outline_size",8)
	parent.add_child(title)


func _start_animation() -> void:
	if _screen_root == null or _camera_layer == null or _layout.is_empty():
		_complete()
		return

	var focus:Vector2 = _layout.focus
	var end_scale:float = float(_layout.end_scale)
	var end_camera_position:Vector2 = focus * (1.0 - end_scale)

	var push := create_tween()
	push.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	push.set_parallel(true)
	push.tween_property(_screen_root,"modulate:a",1.0,0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	push.tween_property(_camera_layer,"scale",Vector2.ONE * end_scale,PUSH_TIME).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	push.tween_property(_camera_layer,"position",end_camera_position,PUSH_TIME).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	push.tween_property(_far_layer,"position",Vector2.ZERO,PUSH_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	push.tween_property(_ink_layer,"position",Vector2.ZERO,PUSH_TIME).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	push.tween_property(_portrait_layer,"position",Vector2.ZERO,PUSH_TIME * 0.92).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	push.tween_property(_text_layer,"position",Vector2.ZERO,PUSH_TIME * 0.78).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	var life := create_tween()
	life.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	life.tween_interval(PUSH_TIME + HOLD_TIME)
	life.tween_property(_screen_root,"modulate:a",0.0,FADE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	life.tween_callback(_complete)


func _play_random_boss_whip() -> void:
	var choices:Array[AudioStream] = [BOSS_WHIP_1,BOSS_WHIP_2,BOSS_WHIP_3]
	# 三个投稿音源本身响度差异较大；按实测峰值/RMS做轻量补偿，
	# 避免随机到某一条时 Boss 开场忽然特别响或特别轻。
	var gain_offsets:Array[float] = [-7.0,-1.0,2.0]
	var index:int = _rng.randi_range(0,choices.size() - 1)
	var stream:AudioStream = choices[index]
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.name = "BossWhip"
	player.stream = stream
	player.volume_db = _intro_volume_db + gain_offsets[index]
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	add_child(player)
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _extract_boss_texture(boss:Node) -> Texture2D:
	if boss == null or not is_instance_valid(boss):
		return null
	var image_node:Variant = boss.get("image")
	if image_node is Sprite2D:
		return (image_node as Sprite2D).texture
	if image_node is AnimatedSprite2D:
		var animated := image_node as AnimatedSprite2D
		if animated.sprite_frames != null and animated.sprite_frames.has_animation(animated.animation):
			return animated.sprite_frames.get_frame_texture(animated.animation,animated.frame)
	var graphics := boss.get_node_or_null("Graphics")
	if graphics != null:
		var sprite := graphics.get_node_or_null("Image") as Sprite2D
		if sprite != null and sprite.texture != null:
			return sprite.texture
		var animated_fallback := graphics.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if animated_fallback != null and animated_fallback.sprite_frames != null and animated_fallback.sprite_frames.has_animation(animated_fallback.animation):
			return animated_fallback.sprite_frames.get_frame_texture(animated_fallback.animation,animated_fallback.frame)
	return null


func _add_polygon(parent:Node,points:PackedVector2Array,color:Color) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.polygon = points
	poly.color = color
	parent.add_child(poly)
	return poly


func _add_circle(parent:Node,center:Vector2,radius:float,color:Color,sides:int = 16) -> Polygon2D:
	var points := PackedVector2Array()
	var count:int = maxi(sides,8)
	for i:int in range(count):
		var angle:float = TAU * float(i) / float(count)
		points.append(center + Vector2(cos(angle),sin(angle)) * radius)
	return _add_polygon(parent,points,color)


func _complete() -> void:
	if is_queued_for_deletion():
		return
	finished.emit()
	queue_free()
