extends VBoxContainer

signal preview_size_requested(preset_id:String)

# V72：设置 -> “特效”分类内的快速特效测试器。
# 目标：不用进战斗，也不用 F6 独立预览场景；在设置面板里直接选择、重播和观察特效。
# 快捷键只由 control.gd 在“特效”分类激活时转发，不会污染正常战斗输入。

const FORM2_TEXTURE:Texture2D = preload("res://Images/characters/游戏/战争女神/形态2.png")
const TRANSFORM_EFFECT:PackedScene = preload("res://scenes/effects/战争女神_变身火焰.tscn")
const IMMUNITY_SHADER:Shader = preload("res://shaders/战争女神_火焰免疫.gdshader")
const CIRCLE_TEXTURE:Texture2D = preload("res://Images/characters/游戏/战争女神/法阵.png")
const CIRCLE_SHADER:Shader = preload("res://shaders/战争女神_法阵发光.gdshader")
const SFX_TRANSFORM:AudioStream = preload("res://audio/characters/游戏/战争女神/变身.wav")
const SFX_IMMUNITY:AudioStream = preload("res://audio/characters/游戏/战争女神/火焰爆裂.wav")
const SFX_CIRCLE:AudioStream = preload("res://audio/characters/游戏/战争女神/火焰法阵.wav")
const VIOLA_PREVIEW_TEXTURE:Texture2D = preload("res://Images/characters/人物/薇欧拉/薇欧拉(4).png")
const VIOLA_FIRE_ARROW_TEXTURE:Texture2D = preload("res://Images/characters/人物/薇欧拉/01_箭形火焰箭.png")
const VIOLA_FIRE_FIELD_SCRIPT:Script = preload("res://scripts/effects/薇欧拉_火场.gd")
const SFX_VIOLA_FIRE_EXPLOSION:AudioStream = preload("res://audio/characters/薇欧拉/火焰爆炸_[cut_3sec].mp3")
const SFX_VIOLA_FIRE_LOOP:AudioStream = preload("res://audio/characters/薇欧拉/火焰燃烧_[cut_94sec].mp3")
const VIOLA_FIRE_IMPACT_TIME:float = 0.72

const PREVIEW_SIZE := Vector2i(246, 112)
const PREVIEW_SIZE_CATALOG:Array[Dictionary] = [
	{"id":"compact", "label_key":"EFFECT_PREVIEW_SIZE_COMPACT", "preview_height":112.0},
	{"id":"medium", "label_key":"EFFECT_PREVIEW_SIZE_MEDIUM", "preview_height":185.0},
	{"id":"large", "label_key":"EFFECT_PREVIEW_SIZE_LARGE", "preview_height":310.0},
	{"id":"maximum", "label_key":"EFFECT_PREVIEW_SIZE_MAXIMUM", "preview_height":400.0},
]
const EFFECT_CATALOG:Array[Dictionary] = [
	{"id":"war_transform", "label_key":"EFFECT_PREVIEW_WAR_TRANSFORM", "duration":2.30},
	{"id":"war_immunity", "label_key":"EFFECT_PREVIEW_WAR_IMMUNITY", "duration":1.25},
	{"id":"war_circle", "label_key":"EFFECT_PREVIEW_WAR_CIRCLE", "duration":3.05},
	{"id":"viola_fire", "label_key":"EFFECT_PREVIEW_VIOLA_FIRE", "duration":5.70},
]

var _active:bool = false
var _auto_loop:bool = true
var _show_character:bool = true
var _play_sound:bool = true
var _selected_index:int = 0
var _selected_size_index:int = 2
var _replay_left:float = 0.10
var _effect_elapsed:float = 0.0
var _effect_duration:float = 2.30
var _serial:int = 0

var _effect_option:OptionButton
var _size_option:OptionButton
var _play_button:Button
var _character_button:Button
var _auto_button:Button
var _sound_button:Button
var _hint_label:Label
var _preview_panel:PanelContainer
var _viewport_container:SubViewportContainer
var _preview_viewport:SubViewport
var _background:ColorRect
var _center_line_h:ColorRect
var _center_line_v:ColorRect
var _preview_host:Node2D
var _graphics:Node2D
var _preview_image:Sprite2D
var _audio_player:AudioStreamPlayer
var _loop_audio_player:AudioStreamPlayer

var _immunity_material:ShaderMaterial
var _circle_sprite:Sprite2D
var _circle_material:ShaderMaterial
var _viola_arrow_root:Node2D = null
var _viola_arrow_main:Sprite2D = null
var _viola_arrow_light:PointLight2D = null
var _viola_fire_field:Node2D = null
var _viola_fire_exploded:bool = false


func _ready() -> void:
	name = "EffectPreviewPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 3)
	_build_ui()
	_refresh_effect_options()
	_refresh_size_options()
	refresh_texts()
	_apply_size_preset(false)
	_reset_character_visual()
	set_process(true)


func _notification(what:int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready():
		if not is_visible_in_tree():
			if is_instance_valid(_audio_player):
				_audio_player.stop()
			if is_instance_valid(_loop_audio_player):
				_loop_audio_player.stop()


func _build_ui() -> void:
	var selector_row := HBoxContainer.new()
	selector_row.name = "EffectPreviewToolbar"
	selector_row.custom_minimum_size = Vector2(0, 24)
	selector_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector_row.add_theme_constant_override("separation", 3)
	add_child(selector_row)

	_effect_option = OptionButton.new()
	_effect_option.name = "EffectSelector"
	_effect_option.custom_minimum_size = Vector2(0, 24)
	_effect_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_effect_option.item_selected.connect(_on_effect_selected)
	selector_row.add_child(_effect_option)
	Game.Set_Ui_sfx(_effect_option)

	_size_option = OptionButton.new()
	_size_option.name = "PreviewSizeSelector"
	_size_option.custom_minimum_size = Vector2(82, 24)
	_size_option.size_flags_horizontal = Control.SIZE_FILL
	_size_option.fit_to_longest_item = false
	_size_option.item_selected.connect(_on_size_selected)
	selector_row.add_child(_size_option)
	Game.Set_Ui_sfx(_size_option)

	_preview_panel = PanelContainer.new()
	_preview_panel.name = "PreviewFrame"
	_preview_panel.custom_minimum_size = Vector2(0, float(PREVIEW_SIZE.y))
	_preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var preview_style := StyleBoxFlat.new()
	preview_style.bg_color = Color(0.045, 0.050, 0.065, 0.96)
	preview_style.border_width_left = 1
	preview_style.border_width_top = 1
	preview_style.border_width_right = 1
	preview_style.border_width_bottom = 1
	preview_style.border_color = Color(0.32, 0.34, 0.40, 0.92)
	preview_style.corner_radius_top_left = 2
	preview_style.corner_radius_top_right = 2
	preview_style.corner_radius_bottom_left = 2
	preview_style.corner_radius_bottom_right = 2
	_preview_panel.add_theme_stylebox_override("panel", preview_style)
	add_child(_preview_panel)

	_viewport_container = SubViewportContainer.new()
	_viewport_container.name = "PreviewViewportContainer"
	_viewport_container.custom_minimum_size = Vector2(0, float(PREVIEW_SIZE.y))
	_viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewport_container.stretch = true
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport_container.resized.connect(_sync_preview_viewport_geometry)
	_preview_panel.add_child(_viewport_container)

	_preview_viewport = SubViewport.new()
	_preview_viewport.name = "EffectPreviewViewport"
	_preview_viewport.size = PREVIEW_SIZE
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	_preview_viewport.transparent_bg = true
	_viewport_container.add_child(_preview_viewport)

	_background = ColorRect.new()
	_background.name = "PreviewBackground"
	_background.position = Vector2.ZERO
	_background.size = Vector2(float(PREVIEW_SIZE.x), float(PREVIEW_SIZE.y))
	_background.color = Color(0.050, 0.055, 0.070, 1.0)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_viewport.add_child(_background)

	# 十字参考线，方便判断位移/范围，但不会盖住特效。
	_center_line_h = ColorRect.new()
	_center_line_h.position = Vector2(0.0, float(PREVIEW_SIZE.y) * 0.66)
	_center_line_h.size = Vector2(float(PREVIEW_SIZE.x), 1.0)
	_center_line_h.color = Color(0.18, 0.20, 0.25, 0.52)
	_center_line_h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_viewport.add_child(_center_line_h)
	_center_line_v = ColorRect.new()
	_center_line_v.position = Vector2(float(PREVIEW_SIZE.x) * 0.5, 0.0)
	_center_line_v.size = Vector2(1.0, float(PREVIEW_SIZE.y))
	_center_line_v.color = Color(0.18, 0.20, 0.25, 0.38)
	_center_line_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_viewport.add_child(_center_line_v)

	_preview_host = Node2D.new()
	_preview_host.name = "PreviewHost"
	_preview_host.position = Vector2(float(PREVIEW_SIZE.x) * 0.5, float(PREVIEW_SIZE.y) * 0.68)
	_preview_viewport.add_child(_preview_host)

	_graphics = Node2D.new()
	_graphics.name = "Graphics"
	_preview_host.add_child(_graphics)

	_preview_image = Sprite2D.new()
	_preview_image.name = "Image"
	_preview_image.texture = FORM2_TEXTURE
	_preview_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview_image.scale = Vector2.ONE * 1.55
	_preview_image.z_index = 2
	_graphics.add_child(_preview_image)

	var control_row := HBoxContainer.new()
	control_row.name = "PreviewControls"
	control_row.custom_minimum_size = Vector2(0, 23)
	control_row.add_theme_constant_override("separation", 2)
	add_child(control_row)

	_play_button = _make_small_button("EffectPlayButton")
	_play_button.pressed.connect(replay_effect)
	control_row.add_child(_play_button)

	_character_button = _make_small_button("EffectCharacterButton", true)
	_character_button.set_pressed_no_signal(_show_character)
	_character_button.toggled.connect(_on_character_toggled)
	control_row.add_child(_character_button)

	_auto_button = _make_small_button("EffectAutoButton", true)
	_auto_button.set_pressed_no_signal(_auto_loop)
	_auto_button.toggled.connect(_on_auto_toggled)
	control_row.add_child(_auto_button)

	_sound_button = _make_small_button("EffectSoundButton", true)
	_sound_button.set_pressed_no_signal(_play_sound)
	_sound_button.toggled.connect(_on_sound_toggled)
	control_row.add_child(_sound_button)

	_hint_label = Label.new()
	_hint_label.name = "EffectShortcutHint"
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 8)
	_hint_label.modulate = Color(0.90, 0.90, 0.94, 0.78)
	add_child(_hint_label)

	_audio_player = AudioStreamPlayer.new()
	_audio_player.name = "EffectPreviewAudio"
	_audio_player.volume_db = -4.0
	add_child(_audio_player)

	_loop_audio_player = AudioStreamPlayer.new()
	_loop_audio_player.name = "EffectPreviewLoopAudio"
	_loop_audio_player.volume_db = -8.0
	add_child(_loop_audio_player)


func _make_small_button(node_name:String, toggle:bool = false) -> Button:
	var button := Button.new()
	button.name = node_name
	button.toggle_mode = toggle
	button.custom_minimum_size = Vector2(0, 23)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 9)
	Game.Set_Ui_sfx(button)
	return button


func _refresh_effect_options() -> void:
	if not is_instance_valid(_effect_option):
		return
	_effect_option.clear()
	var translation_sources:Array[String] = []
	for entry:Dictionary in EFFECT_CATALOG:
		var label_key:String = str(entry.get("label_key", ""))
		_effect_option.add_item(Game.ui_t(label_key))
		_effect_option.set_item_metadata(_effect_option.item_count - 1, str(entry.get("id", "")))
		translation_sources.append(label_key)
	_effect_option.set_meta("_translation_option_sources", translation_sources)
	_selected_index = clampi(_selected_index, 0, maxi(_effect_option.item_count - 1, 0))
	if _effect_option.item_count > 0:
		_effect_option.select(_selected_index)


func _refresh_size_options() -> void:
	if not is_instance_valid(_size_option):
		return
	_size_option.clear()
	var translation_sources:Array[String] = []
	for entry:Dictionary in PREVIEW_SIZE_CATALOG:
		var label_key:String = str(entry.get("label_key", ""))
		_size_option.add_item(Game.ui_t(label_key))
		_size_option.set_item_metadata(_size_option.item_count - 1, str(entry.get("id", "")))
		translation_sources.append(label_key)
	_size_option.set_meta("_translation_option_sources", translation_sources)
	_selected_size_index = clampi(_selected_size_index, 0, maxi(_size_option.item_count - 1, 0))
	if _size_option.item_count > 0:
		_size_option.select(_selected_size_index)


func _on_size_selected(index:int) -> void:
	_selected_size_index = clampi(index, 0, PREVIEW_SIZE_CATALOG.size() - 1)
	_apply_size_preset(true)


func _apply_size_preset(emit_request:bool = true) -> void:
	if PREVIEW_SIZE_CATALOG.is_empty():
		return
	_selected_size_index = clampi(_selected_size_index, 0, PREVIEW_SIZE_CATALOG.size() - 1)
	var entry:Dictionary = PREVIEW_SIZE_CATALOG[_selected_size_index]
	var preview_height:float = maxf(float(entry.get("preview_height", PREVIEW_SIZE.y)), float(PREVIEW_SIZE.y))
	if is_instance_valid(_preview_panel):
		_preview_panel.custom_minimum_size = Vector2(0, preview_height)
	if is_instance_valid(_viewport_container):
		_viewport_container.custom_minimum_size = Vector2(0, preview_height)
	custom_minimum_size = Vector2(0, preview_height + 82.0)
	update_minimum_size()
	call_deferred("_sync_preview_viewport_geometry")
	if emit_request:
		preview_size_requested.emit(str(entry.get("id", "large")))


func emit_current_size_request() -> void:
	_apply_size_preset(true)


func _sync_preview_viewport_geometry() -> void:
	if not is_instance_valid(_viewport_container) or not is_instance_valid(_preview_viewport):
		return
	var local_size:Vector2 = _viewport_container.size
	if local_size.x < 8.0 or local_size.y < 8.0:
		return
	var wanted := Vector2i(
		maxi(int(round(local_size.x)), PREVIEW_SIZE.x),
		maxi(int(round(local_size.y)), PREVIEW_SIZE.y)
	)
	if _preview_viewport.size != wanted:
		_preview_viewport.size = wanted
	if is_instance_valid(_background):
		_background.size = Vector2(wanted)
	if is_instance_valid(_center_line_h):
		_center_line_h.position = Vector2(0.0, float(wanted.y) * 0.66)
		_center_line_h.size = Vector2(float(wanted.x), 1.0)
	if is_instance_valid(_center_line_v):
		_center_line_v.position = Vector2(float(wanted.x) * 0.5, 0.0)
		_center_line_v.size = Vector2(1.0, float(wanted.y))
	if is_instance_valid(_preview_host):
		_preview_host.position = Vector2(float(wanted.x) * 0.5, float(wanted.y) * 0.68)


func refresh_texts() -> void:
	if not is_node_ready():
		return
	if is_instance_valid(_effect_option):
		for i:int in range(mini(_effect_option.item_count, EFFECT_CATALOG.size())):
			_effect_option.set_item_text(i, Game.ui_t(str(EFFECT_CATALOG[i].get("label_key", ""))))
	if is_instance_valid(_size_option):
		for i:int in range(mini(_size_option.item_count, PREVIEW_SIZE_CATALOG.size())):
			_size_option.set_item_text(i, Game.ui_t(str(PREVIEW_SIZE_CATALOG[i].get("label_key", ""))))
	if is_instance_valid(_play_button):
		_play_button.text = Game.ui_t("EFFECT_PREVIEW_PLAY")
	if is_instance_valid(_character_button):
		_character_button.text = Game.ui_t("EFFECT_PREVIEW_CHARACTER")
	if is_instance_valid(_auto_button):
		_auto_button.text = Game.ui_t("EFFECT_PREVIEW_AUTO")
	if is_instance_valid(_sound_button):
		_sound_button.text = Game.ui_t("EFFECT_PREVIEW_SOUND")
	if is_instance_valid(_hint_label):
		_hint_label.text = Game.ui_t("EFFECT_PREVIEW_SHORTCUT_HINT")


func set_preview_active(active:bool) -> void:
	_active = active
	if not _active:
		if is_instance_valid(_audio_player):
			_audio_player.stop()
		if is_instance_valid(_loop_audio_player):
			_loop_audio_player.stop()
		return
	_replay_left = 0.05
	_apply_size_preset(true)
	call_deferred("replay_effect")


func handle_shortcut(event:InputEvent) -> bool:
	if not _active or not is_visible_in_tree():
		return false
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return false
	if key_event.ctrl_pressed or key_event.alt_pressed or key_event.meta_pressed:
		return false

	match key_event.keycode:
		KEY_SPACE, KEY_ENTER:
			replay_effect()
			return true
		KEY_LEFT:
			_select_relative(-1)
			return true
		KEY_RIGHT:
			_select_relative(1)
			return true
		KEY_C:
			_show_character = not _show_character
			if is_instance_valid(_character_button):
				_character_button.set_pressed_no_signal(_show_character)
			_apply_character_visibility()
			return true
		KEY_A:
			_auto_loop = not _auto_loop
			if is_instance_valid(_auto_button):
				_auto_button.set_pressed_no_signal(_auto_loop)
			if _auto_loop:
				_replay_left = minf(_replay_left, 0.18)
			return true
		KEY_M:
			_play_sound = not _play_sound
			if is_instance_valid(_sound_button):
				_sound_button.set_pressed_no_signal(_play_sound)
			if not _play_sound and is_instance_valid(_audio_player):
				_audio_player.stop()
			return true
		KEY_BRACKETLEFT:
			_select_size_relative(-1)
			return true
		KEY_BRACKETRIGHT:
			_select_size_relative(1)
			return true
		KEY_1, KEY_2, KEY_3, KEY_4:
			var wanted:int = int(key_event.keycode - KEY_1)
			if wanted >= 0 and wanted < EFFECT_CATALOG.size():
				_select_effect(wanted, true)
			return true
	return false


func _process(delta:float) -> void:
	if not _active or not is_visible_in_tree():
		return
	var step:float = maxf(delta, 0.0)
	_effect_elapsed += step
	_update_current_visual()
	if _auto_loop:
		_replay_left -= step
		if _replay_left <= 0.0:
			replay_effect()


func _on_effect_selected(index:int) -> void:
	_select_effect(index, true)


func _select_relative(direction:int) -> void:
	if EFFECT_CATALOG.is_empty():
		return
	var next:int = wrapi(_selected_index + direction, 0, EFFECT_CATALOG.size())
	_select_effect(next, true)


func _select_size_relative(direction:int) -> void:
	if PREVIEW_SIZE_CATALOG.is_empty():
		return
	var next:int = clampi(_selected_size_index + direction, 0, PREVIEW_SIZE_CATALOG.size() - 1)
	if next == _selected_size_index:
		return
	_selected_size_index = next
	if is_instance_valid(_size_option):
		_size_option.select(_selected_size_index)
	_apply_size_preset(true)


func _select_effect(index:int, replay_now:bool) -> void:
	if EFFECT_CATALOG.is_empty():
		return
	_selected_index = clampi(index, 0, EFFECT_CATALOG.size() - 1)
	if is_instance_valid(_effect_option):
		_effect_option.select(_selected_index)
	if replay_now:
		replay_effect()


func _on_character_toggled(enabled:bool) -> void:
	_show_character = enabled
	_apply_character_visibility()


func _on_auto_toggled(enabled:bool) -> void:
	_auto_loop = enabled
	if _auto_loop:
		_replay_left = minf(_replay_left, 0.18)


func _on_sound_toggled(enabled:bool) -> void:
	_play_sound = enabled
	if not _play_sound:
		if is_instance_valid(_audio_player):
			_audio_player.stop()
		if is_instance_valid(_loop_audio_player):
			_loop_audio_player.stop()


func replay_effect() -> void:
	if not is_node_ready() or EFFECT_CATALOG.is_empty():
		return
	_clear_effect_visuals()
	_reset_character_visual()
	_effect_elapsed = 0.0
	var entry:Dictionary = EFFECT_CATALOG[_selected_index]
	_effect_duration = maxf(float(entry.get("duration", 2.0)), 0.25)
	_replay_left = _effect_duration
	var effect_id:String = str(entry.get("id", ""))
	match effect_id:
		"war_transform":
			_start_transform_preview()
			_play_preview_sound(SFX_TRANSFORM)
		"war_immunity":
			_start_immunity_preview()
			_play_preview_sound(SFX_IMMUNITY)
		"war_circle":
			_start_circle_preview()
			_play_preview_sound(SFX_CIRCLE)
		"viola_fire":
			_start_viola_fire_preview()
	_apply_character_visibility()


func _clear_effect_visuals() -> void:
	if is_instance_valid(_audio_player):
		_audio_player.stop()
	if is_instance_valid(_loop_audio_player):
		_loop_audio_player.stop()
	_immunity_material = null
	_circle_sprite = null
	_circle_material = null
	_viola_arrow_root = null
	_viola_arrow_main = null
	_viola_arrow_light = null
	_viola_fire_field = null
	_viola_fire_exploded = false
	if is_instance_valid(_preview_image):
		_preview_image.material = null
	if is_instance_valid(_preview_host):
		for child:Node in _preview_host.get_children():
			if child == _graphics:
				continue
			child.queue_free()


func _reset_character_visual() -> void:
	if not is_instance_valid(_preview_image):
		return
	_preview_image.texture = FORM2_TEXTURE
	_preview_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview_image.scale = Vector2.ONE * 1.55
	_preview_image.rotation = 0.0
	_preview_image.position = Vector2.ZERO
	_preview_image.self_modulate = Color.WHITE
	_preview_image.material = null
	_apply_character_visibility()


func _apply_character_visibility() -> void:
	if is_instance_valid(_preview_image):
		_preview_image.visible = _show_character


func _start_transform_preview() -> void:
	var effect := TRANSFORM_EFFECT.instantiate() as Node2D
	if effect == null:
		return
	_serial += 1
	effect.name = "SettingsEffectTransform_%d" % _serial
	effect.top_level = false
	effect.z_as_relative = true
	effect.z_index = 8
	_preview_host.add_child(effect)
	effect.position = Vector2.ZERO
	if effect.has_method("setup"):
		effect.call("setup", 96.0, 20)


func _start_immunity_preview() -> void:
	if not is_instance_valid(_preview_image):
		return
	_immunity_material = ShaderMaterial.new()
	_immunity_material.shader = IMMUNITY_SHADER
	_preview_image.material = _immunity_material
	_configure_immunity_material()


func _configure_immunity_material() -> void:
	if _immunity_material == null or not is_instance_valid(_preview_image) or _preview_image.texture == null:
		return
	var texture_size:Vector2 = _preview_image.texture.get_size()
	var content_rect := Rect2(Vector2.ZERO, texture_size)
	var source_image:Image = _preview_image.texture.get_image()
	if source_image != null and not source_image.is_empty():
		var used:Rect2i = source_image.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			content_rect = Rect2(Vector2(used.position), Vector2(used.size))
	var content_uv := Vector4(
		content_rect.position.x / maxf(texture_size.x, 1.0),
		content_rect.position.y / maxf(texture_size.y, 1.0),
		content_rect.size.x / maxf(texture_size.x, 1.0),
		content_rect.size.y / maxf(texture_size.y, 1.0)
	)
	_immunity_material.set_shader_parameter("immunity_content_rect", content_uv)
	_immunity_material.set_shader_parameter("immunity_radius", 0.50)
	_immunity_material.set_shader_parameter("immunity_global_flash", 1.0)
	_immunity_material.set_shader_parameter("immunity_quad_center", Vector2.ZERO)
	_immunity_material.set_shader_parameter("immunity_canvas_expand", 2.2)
	_immunity_material.set_shader_parameter("immunity_hit_uv_0", Vector2(0.63, 0.49))
	_immunity_material.set_shader_parameter("immunity_seed_0", float((_serial + 1) * 31 + 7))
	_immunity_material.set_shader_parameter("immunity_progress_0", 0.0)
	for i:int in range(1, 4):
		_immunity_material.set_shader_parameter("immunity_progress_%d" % i, 1.0)


func _start_circle_preview() -> void:
	_circle_sprite = Sprite2D.new()
	_circle_sprite.name = "SettingsEffectCircle"
	_circle_sprite.texture = CIRCLE_TEXTURE
	_circle_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_circle_sprite.position = Vector2(0.0, 18.0)
	_circle_sprite.z_index = -2
	_circle_material = ShaderMaterial.new()
	_circle_material.shader = CIRCLE_SHADER
	_circle_material.set_shader_parameter("glow_strength", 1.55)
	_circle_material.set_shader_parameter("glow_radius_px", 6.0)
	_circle_material.set_shader_parameter("pulse_speed", 3.2)
	_circle_material.set_shader_parameter("pulse_amount", 0.22)
	_circle_material.set_shader_parameter("opacity", 0.40)
	_circle_material.set_shader_parameter("visual_fade", 0.0)
	_circle_sprite.material = _circle_material
	var texture_size:Vector2 = CIRCLE_TEXTURE.get_size()
	var longest:float = maxf(texture_size.x, texture_size.y)
	var final_scale:float = 72.0 / maxf(longest, 1.0)
	_circle_sprite.scale = Vector2.ONE * final_scale * 0.56
	_preview_host.add_child(_circle_sprite)


func _update_current_visual() -> void:
	if EFFECT_CATALOG.is_empty():
		return
	var effect_id:String = str(EFFECT_CATALOG[_selected_index].get("id", ""))
	match effect_id:
		"war_immunity":
			_update_immunity_preview()
		"war_circle":
			_update_circle_preview()
		"viola_fire":
			_update_viola_fire_preview()


func _update_immunity_preview() -> void:
	if _immunity_material == null:
		return
	var p:float = clampf(_effect_elapsed / 0.95, 0.0, 1.0)
	_immunity_material.set_shader_parameter("immunity_progress_0", p)
	var flash:float = 1.0 - smoothstep(0.0, 0.16, _effect_elapsed)
	_immunity_material.set_shader_parameter("immunity_global_flash", clampf(flash, 0.0, 1.0))


func _update_circle_preview() -> void:
	if not is_instance_valid(_circle_sprite) or _circle_material == null:
		return
	_circle_sprite.rotation += get_process_delta_time() * 0.70
	var texture_size:Vector2 = CIRCLE_TEXTURE.get_size()
	var longest:float = maxf(texture_size.x, texture_size.y)
	var final_scale:float = 72.0 / maxf(longest, 1.0)
	var t:float = _effect_elapsed
	var scale_ratio:float = 1.0
	if t < 0.20:
		scale_ratio = lerpf(0.56, 1.10, 1.0 - pow(1.0 - clampf(t / 0.20, 0.0, 1.0), 3.0))
	elif t < 0.50:
		var back_t:float = clampf((t - 0.20) / 0.30, 0.0, 1.0)
		scale_ratio = lerpf(1.10, 1.0, back_t)
	_circle_sprite.scale = Vector2.ONE * final_scale * scale_ratio
	var fade_in:float = smoothstep(0.0, 0.42, t)
	var fade_out:float = 1.0 - smoothstep(_effect_duration - 0.62, _effect_duration, t)
	_circle_material.set_shader_parameter("visual_fade", clampf(minf(fade_in, fade_out), 0.0, 1.0))


func _make_viola_preview_light_texture() -> GradientTexture2D:
	var gradient:=Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0,0.40,0.78,1.0])
	gradient.colors = PackedColorArray([
		Color(1.0,1.0,1.0,1.0),
		Color(1.0,0.88,0.58,0.72),
		Color(1.0,0.34,0.04,0.22),
		Color(1.0,0.14,0.01,0.0)
	])
	var texture:=GradientTexture2D.new()
	texture.width = 96
	texture.height = 96
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5,0.5)
	texture.fill_to = Vector2(1.0,0.5)
	texture.gradient = gradient
	return texture


func _start_viola_fire_preview() -> void:
	_viola_fire_exploded = false
	if is_instance_valid(_preview_image) and VIOLA_PREVIEW_TEXTURE != null:
		_preview_image.texture = VIOLA_PREVIEW_TEXTURE
		_preview_image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var char_scale:float = 78.0 / maxf(float(VIOLA_PREVIEW_TEXTURE.get_height()),1.0)
		_preview_image.scale = Vector2.ONE * char_scale
		_preview_image.position = Vector2(-88.0,6.0)

	_viola_arrow_root = Node2D.new()
	_viola_arrow_root.name = "ViolaFireArrowPreview"
	_viola_arrow_root.position = Vector2(-56.0,-3.0)
	_viola_arrow_root.z_index = 9
	_preview_host.add_child(_viola_arrow_root)
	var base_scale:float = 50.0 / maxf(float(VIOLA_FIRE_ARROW_TEXTURE.get_width()),1.0)
	_viola_arrow_main = Sprite2D.new()
	_viola_arrow_main.texture = VIOLA_FIRE_ARROW_TEXTURE
	_viola_arrow_main.scale = Vector2.ONE * base_scale
	_viola_arrow_main.self_modulate = Color(1.0,0.96,0.86,0.78)
	_viola_arrow_root.add_child(_viola_arrow_main)

	_viola_arrow_light = PointLight2D.new()
	_viola_arrow_light.name = "ViolaFireArrowPreviewLight"
	_viola_arrow_light.texture = _make_viola_preview_light_texture()
	_viola_arrow_light.texture_scale = 0.60
	_viola_arrow_light.color = Color(1.0,0.31,0.045,1.0)
	_viola_arrow_light.energy = 1.20
	_viola_arrow_light.blend_mode = Light2D.BLEND_MODE_ADD
	_viola_arrow_light.shadow_enabled = false
	_viola_arrow_root.add_child(_viola_arrow_light)


func _update_viola_fire_preview() -> void:
	var impact_position:=Vector2(34.0,34.0)
	if _effect_elapsed < VIOLA_FIRE_IMPACT_TIME:
		if not is_instance_valid(_viola_arrow_root):
			return
		var t:float = clampf(_effect_elapsed / VIOLA_FIRE_IMPACT_TIME,0.0,1.0)
		var eased:float = 1.0 - pow(1.0-t,2.2)
		_viola_arrow_root.position = Vector2(-56.0,-3.0).lerp(impact_position,eased)
		var phase:float = _effect_elapsed * 13.0
		_viola_arrow_root.scale = Vector2(1.0 + sin(phase) * 0.065,1.0 + sin(phase*0.71+1.2) * 0.025)
		_viola_arrow_root.rotation = sin(phase*0.62) * 0.020
		if is_instance_valid(_viola_arrow_main):
			_viola_arrow_main.self_modulate.a = clampf(0.78 + sin(phase*0.82)*0.045,0.66,0.86)
		if is_instance_valid(_viola_arrow_light):
			_viola_arrow_light.energy = 1.20 + sin(phase*0.55+0.8)*0.10
		return
	if not _viola_fire_exploded:
		_spawn_viola_fire_field_preview(impact_position)


func _spawn_viola_fire_field_preview(impact_position:Vector2) -> void:
	_viola_fire_exploded = true
	if is_instance_valid(_viola_arrow_root):
		_viola_arrow_root.visible = false
	if _play_sound:
		_play_preview_sound(SFX_VIOLA_FIRE_EXPLOSION)
		_start_viola_fire_loop_preview()
	var field:Node2D = VIOLA_FIRE_FIELD_SCRIPT.new() as Node2D
	if field == null:
		return
	field.name = "SettingsViolaFireField"
	field.set("radius",28.0)
	field.set("duration",maxf(_effect_duration-VIOLA_FIRE_IMPACT_TIME,0.5))
	field.set("tick_damage",0.0)
	field.set("burn_tick_damage",0.0)
	_preview_host.add_child(field)
	field.position = impact_position
	_viola_fire_field = field


func _start_viola_fire_loop_preview() -> void:
	if not _play_sound or not is_instance_valid(_loop_audio_player) or SFX_VIOLA_FIRE_LOOP == null:
		return
	var stream_value:AudioStream = SFX_VIOLA_FIRE_LOOP.duplicate() as AudioStream
	if stream_value is AudioStreamMP3:
		(stream_value as AudioStreamMP3).loop = true
	_loop_audio_player.stop()
	_loop_audio_player.stream = stream_value if stream_value != null else SFX_VIOLA_FIRE_LOOP
	_loop_audio_player.play()


func _play_preview_sound(stream:AudioStream) -> void:
	if not _play_sound or stream == null or not is_instance_valid(_audio_player):
		return
	_audio_player.stop()
	_audio_player.stream = stream
	_audio_player.play()
