extends VBoxContainer
## Uses the existing settings row/title theme and the authoritative Game settings path.
const CATALOG = preload("res://scripts/training/battle_conditions_catalog.gd")
var ui:Control
var event_box:VBoxContainer
var event_hint:Label
var event_empty:Label
var event_checks:Dictionary = {}
var event_definitions:Array = CATALOG.EVENTS
var event_toggle:TextureButton
var environment_option:OptionButton
var environment_label:Label

func _init(owner_control:Control = null) -> void:
	ui = owner_control
	name = "BattleConditionsSettings"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",2)

func _ready() -> void:
	var event_row:Control = ui._create_bool_setting_row(self,"Random_Events")
	event_row.name = "RandomEventsRow"
	event_toggle = event_row.get_node("Set/TextureButton")
	event_box = VBoxContainer.new()
	event_box.name = "EventChoices"
	event_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	event_box.add_theme_constant_override("separation",2)
	add_child(event_box)
	event_hint = _hint("EVENT_SELECTION_HINT")
	event_empty = _hint("EVENT_SELECTION_EMPTY")
	_build_event_checks()
	var row:=HBoxContainer.new()
	row.name = "EnvironmentRow"
	row.custom_minimum_size = Vector2(0,24)
	row.add_theme_constant_override("separation",3)
	add_child(row)
	var title:Dictionary = ui._create_setting_title_from_template("SETTING_ENVIRONMENT",64.0)
	row.add_child(title.panel)
	environment_label = title.label
	environment_option = OptionButton.new()
	environment_option.name = "EnvironmentOption"
	environment_option.fit_to_longest_item = false
	environment_option.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	environment_option.custom_minimum_size = Vector2(0,24)
	environment_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	environment_option.add_theme_font_size_override("font_size",10)
	environment_option.get_popup().add_theme_font_size_override("font_size",10)
	for key:String in CATALOG.ENVIRONMENTS:
		environment_option.add_item(Game.ui_t("ENVIRONMENT_"+key.to_upper()))
		environment_option.set_item_metadata(environment_option.item_count-1,key)
	environment_option.item_selected.connect(_on_environment_selected)
	row.add_child(environment_option)
	Game.Set_Ui_sfx(environment_option)
	Game.game_setting_changed.connect(_on_setting_changed)
	Game.language_changed.connect(_on_language_changed)
	Game.network_state_changed.connect(refresh)
	refresh()

func _hint(key:String) -> Label:
	var label:=Label.new()
	label.set_meta("_translation_source_text",key)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",9)
	label.modulate = Color(1,1,1,0.76)
	event_box.add_child(label)
	return label

func _build_event_checks() -> void:
	for check:CheckBox in event_checks.values():
		check.queue_free()
	event_checks.clear()
	for definition:Dictionary in event_definitions:
		var id:String = str(definition.get("id",""))
		if id.is_empty() or event_checks.has(id): continue
		var check:=CheckBox.new()
		check.name = "Event_"+id.validate_node_name()
		check.set_meta("event_id",id)
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		check.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		check.add_theme_font_size_override("font_size",10)
		check.toggled.connect(_on_event_toggled.bind(id))
		event_box.add_child(check)
		Game.Set_Ui_sfx(check)
		event_checks[id] = check

func refresh() -> void:
	if not is_instance_valid(environment_option): return
	var allowed:bool = Game.can_local_change_settings()
	event_toggle.disabled = not allowed
	event_box.visible = bool(Game.Game_Settings.get("Random_Events",false))
	event_hint.text = Game.ui_t("EVENT_SELECTION_HINT")
	event_empty.text = Game.ui_t("EVENT_SELECTION_EMPTY")
	event_empty.visible = event_checks.is_empty()
	var selected:Array[String] = CATALOG.normalize_selection(Game.Game_Settings.get("Random_Event_Selection",[]))
	for definition:Dictionary in event_definitions:
		var id:String = str(definition.get("id",""))
		if not event_checks.has(id): continue
		var check:CheckBox = event_checks[id]
		check.text = Game.ui_t(str(definition.get("label_key",id)))
		check.set_pressed_no_signal(selected.has(id))
		check.disabled = not allowed
	environment_label.text = Game.ui_t("SETTING_ENVIRONMENT")
	var environment:String = CATALOG.normalize_environment(Game.Game_Settings.get("Environment","none"))
	for index:int in range(environment_option.item_count):
		var key:String = str(environment_option.get_item_metadata(index))
		environment_option.set_item_text(index,Game.ui_t("ENVIRONMENT_"+key.to_upper()))
		if key==environment: environment_option.select(index)
	environment_option.disabled = not allowed
	environment_option.tooltip_text = Game.ui_t("ENVIRONMENT_SNOW_HINT") if environment=="snow" else ""
	ui.call_deferred("_refresh_settings_scroll_layout")

func _on_environment_selected(index:int) -> void:
	if Game.can_local_change_settings(): Game.set_runtime_game_setting("Environment",environment_option.get_item_metadata(index))
	refresh()

func _on_event_toggled(pressed:bool,id:String) -> void:
	if not Game.can_local_change_settings():
		refresh()
		return
	var selected:Array[String] = CATALOG.normalize_selection(Game.Game_Settings.get("Random_Event_Selection",[]))
	if pressed and not selected.has(id): selected.append(id)
	elif not pressed: selected.erase(id)
	Game.set_runtime_game_setting("Random_Event_Selection",selected)
	refresh()

func _on_setting_changed(key:String,_value:Variant) -> void:
	if CATALOG.SETTING_KEYS.has(key) or key=="Guest_Free_Permissions": refresh()
func _on_language_changed(_locale:String) -> void: refresh()
