extends Button
## Settings-only preview. Does not reset the battle, change settings, or switch maps.
const TRANSITION = preload("res://scripts/ui/dark_oak_transition.gd")

func _ready() -> void:
	name = "TestDarkOakTransition"
	process_mode = Node.PROCESS_MODE_ALWAYS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0,24)
	clip_text = true
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_theme_font_size_override("font_size",9)
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	pressed.connect(_play_preview)
	_refresh()

func _process(_delta:float) -> void:
	_refresh()

func _refresh() -> void:
	var game:Node = get_tree().root.get_node_or_null("Game")
	var english:bool = game != null and game.get_ui_locale()=="en"
	var label:String = "Test door transition" if english else "测试双门转场"
	if text!=label: text=label
	# Cooperate with Control's source-text cache without modifying shared translation files.
	set_meta("_translation_source_text",label)
	tooltip_text = "Dark oak doors close, then open. Preview only; the battle is unchanged." if english else "左右深色橡木门关闭后再打开。仅测试动画，不重置对局、不更改地图。"
	var overlay:Node = get_tree().root.get_node_or_null("DarkOakDoorTransition")
	disabled = overlay != null and overlay.is_busy()

func _play_preview() -> void:
	var overlay:Node = TRANSITION.ensure(get_tree())
	overlay.play()
	_refresh()
