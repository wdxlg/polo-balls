extends RefCounted
## 持久化语言 / 翻译表 / 运行时 UI 兜底翻译
## 从 res://global/game.gd 拆出的内聚模块。Game 仍是唯一的 Autoload 门面：
## 外部继续调用 Game.xxx；本模块通过 _game 访问仍留在 Game 上的成员（设置、信号、RPC、场景树）。

var _game: Node


func _init(game: Node) -> void:
	_game = game


const TRANSLATION_CSV_PATH := "res://translations.csv"

const TRANSLATION_CATALOG_SCRIPT = preload("res://global/translation_catalog.gd")

const MISSING_TRANSLATIONS_PATH := "user://missing_translations.csv"

const SUPPORTED_LOCALES := ["zh", "en"]

@warning_ignore("unused_private_class_variable")
var _runtime_localization_sweep_left:float = 0.0

const RUNTIME_LOCALIZATION_SWEEP_INTERVAL:float = 0.35

var current_locale:String = "zh"

var _runtime_translations:Array[Translation] = []

var _translation_table:Dictionary = {}

var _translation_reverse:Dictionary = {}

var _translation_reverse_any:Dictionary = {}

var _translation_fragments:Array = []

var _missing_translation_keys:Dictionary = {}

var _missing_translation_dirty:bool = false

var _missing_translation_flush_scheduled:bool = false


func _load_missing_translation_cache() -> void:
	_missing_translation_keys.clear()
	if not FileAccess.file_exists(MISSING_TRANSLATIONS_PATH):
		return
	var file := FileAccess.open(MISSING_TRANSLATIONS_PATH, FileAccess.READ)
	if file == null:
		return
	if file.get_position() < file.get_length():
		file.get_csv_line() # header
	while file.get_position() < file.get_length():
		var row:PackedStringArray = file.get_csv_line()
		if not row.is_empty() and not row[0].is_empty():
			_missing_translation_keys[row[0]] = true
	file.close()


# V378：导出版本不能假定被导入资源的原始 CSV 仍然存在于 PCK。
# Godot 官方建议导出后通过资源机制使用导入结果；这里进一步把当前 CSV 的
# 中/英文消息编译进 translation_catalog.gd，保证最早启动阶段也有完整翻译表可用。
func _load_compiled_translation_catalog() -> bool:
	var catalog_variant:Variant = TRANSLATION_CATALOG_SCRIPT.TABLE
	if not (catalog_variant is Dictionary):
		push_warning("编译翻译表不可用: res://global/translation_catalog.gd")
		return false
	var catalog:Dictionary = catalog_variant as Dictionary
	var translations_by_locale:Dictionary = {}

	for raw_locale:Variant in catalog.keys():
		var locale:String = TranslationServer.standardize_locale(str(raw_locale))
		var messages_variant:Variant = catalog[raw_locale]
		if not (messages_variant is Dictionary):
			continue
		var messages:Dictionary = messages_variant as Dictionary
		var translation := Translation.new()
		translation.locale = locale
		translations_by_locale[locale] = translation
		_translation_table[locale] = {}
		_translation_reverse[locale] = {}

		for raw_key:Variant in messages.keys():
			var key:String = str(raw_key)
			var value:String = str(messages[raw_key])
			if key.is_empty() or value.is_empty():
				continue
			translation.add_message(key,value)
			_translation_table[locale][key] = value
			_translation_reverse[locale][value] = key
			if not _translation_reverse_any.has(value):
				_translation_reverse_any[value] = key

	for display_text:Variant in _translation_reverse_any.keys():
		var part:String = str(display_text)
		if part.length() >= 2:
			_translation_fragments.append([part,str(_translation_reverse_any[display_text])])
	_translation_fragments.sort_custom(func(a:Variant,b:Variant) -> bool:
		return str(a[0]).length() > str(b[0]).length()
	)

	for raw_locale:Variant in translations_by_locale.keys():
		var translation:Translation = translations_by_locale[raw_locale] as Translation
		TranslationServer.add_translation(translation)
		_runtime_translations.append(translation)

	return not _runtime_translations.is_empty()


# 在节点进入 SceneTree 之前读取“上次保存的语言”，并提前安装编译翻译表。
# 这样导出程序不会先按操作系统语言把 Control 的中文源文本翻成英文，
# 也不会等到 _ready() 才发现 translations.csv 原文件在 PCK 中不存在。
func _bootstrap_localization_before_tree() -> void:
	current_locale = "zh"
	var config := ConfigFile.new()
	if config.load(_game.SETTINGS_PATH) == OK:
		var saved_locale:String = str(config.get_value("ui","locale","zh"))
		if SUPPORTED_LOCALES.has(saved_locale):
			current_locale = saved_locale
		if _game.Game_Settings.has("Only_In_Game_Translation"):
			_game.Game_Settings["Only_In_Game_Translation"] = bool(
				config.get_value(
					"game_settings",
					"Only_In_Game_Translation",
					_game.Game_Settings["Only_In_Game_Translation"]
				)
			)

	_load_compiled_translation_catalog()
	_apply_translation_server_locale()


# 直接从 res://translations.csv 建立 Translation 资源。
# 编辑器/保留原始 CSV 的导出包继续使用 CSV 作为最新源；
# 若导出 PCK 不含原始 CSV，则自动退回编译翻译表。
func load_runtime_translations() -> bool:
	_load_missing_translation_cache()
	_translation_table.clear()
	_translation_reverse.clear()
	_translation_reverse_any.clear()
	_translation_fragments.clear()
	_ui_fragment_translation_cache.clear()

	for translation in _runtime_translations:
		if is_instance_valid(translation):
			TranslationServer.remove_translation(translation)
	_runtime_translations.clear()

	if not FileAccess.file_exists(TRANSLATION_CSV_PATH):
		push_warning("导出包中找不到原始翻译 CSV，改用编译翻译表: " + TRANSLATION_CSV_PATH)
		return _load_compiled_translation_catalog()

	var file := FileAccess.open(TRANSLATION_CSV_PATH, FileAccess.READ)
	if file == null:
		push_warning("无法直接打开翻译 CSV，改用编译翻译表: " + TRANSLATION_CSV_PATH)
		return _load_compiled_translation_catalog()

	if file.get_length() <= 0:
		file.close()
		push_warning("翻译 CSV 为空，改用编译翻译表")
		return _load_compiled_translation_catalog()

	var headers:PackedStringArray = file.get_csv_line()
	if headers.size() < 2:
		file.close()
		push_warning("translations.csv 至少需要 keys,zh,en 三列；改用编译翻译表")
		return _load_compiled_translation_catalog()

	headers[0] = headers[0].trim_prefix("\ufeff").strip_edges()
	var locale_columns:Dictionary = {}
	var translations_by_locale:Dictionary = {}

	for column in range(1, headers.size()):
		var locale:String = headers[column].strip_edges()
		if locale.is_empty():
			continue
		locale = TranslationServer.standardize_locale(locale)
		locale_columns[column] = locale
		var translation := Translation.new()
		translation.locale = locale
		translations_by_locale[locale] = translation
		_translation_table[locale] = {}
		_translation_reverse[locale] = {}

	while file.get_position() < file.get_length():
		var row:PackedStringArray = file.get_csv_line()
		if row.is_empty():
			continue

		var key:String = row[0].strip_edges()
		if key.is_empty():
			continue

		for column in locale_columns.keys():
			var col:int = int(column)
			if col >= row.size():
				continue
			var value:String = row[col]
			if value.is_empty():
				continue
			var locale:String = str(locale_columns[col])
			var translation := translations_by_locale[locale] as Translation
			translation.add_message(key, value)
			_translation_table[locale][key] = value
			# 反向表让已经被 Godot 自动翻成中文/英文的 Label，
			# 仍能找回原始 key，再切换到另一种语言。
			_translation_reverse[locale][value] = key
			if not _translation_reverse_any.has(value):
				_translation_reverse_any[value] = key

	file.close()

	# 预先建立组合文本替换表，避免每翻译一个 Label 都遍历整张 CSV。
	# 长字符串优先，防止 "角色" 先吃掉 "当前角色：" 这类更完整的片段。
	for display_text in _translation_reverse_any.keys():
		var part:String = str(display_text)
		if part.length() >= 2:
			_translation_fragments.append([part, str(_translation_reverse_any[display_text])])
	_translation_fragments.sort_custom(func(a:Variant, b:Variant) -> bool:
		return str(a[0]).length() > str(b[0]).length()
	)

	for locale in translations_by_locale.keys():
		var translation := translations_by_locale[locale] as Translation
		TranslationServer.add_translation(translation)
		_runtime_translations.append(translation)

	return not _runtime_translations.is_empty()


func has_translation_key(key:String) -> bool:
	for locale in _translation_table.keys():
		if _translation_table[locale].has(key):
			return true
	return false


func resolve_translation_key(source:String) -> String:
	if source.is_empty():
		return ""

	if has_translation_key(source):
		return source

	# O(1) 反向查找：控件即使已被 Godot 自动翻译，也能找回原 key。
	if _translation_reverse_any.has(source):
		return str(_translation_reverse_any[source])

	return ""


func is_only_in_game_translation_enabled() -> bool:
	return bool(_game.Game_Settings.get("Only_In_Game_Translation", false))


func get_ui_locale() -> String:
	# “仅局内翻译”：逻辑语言仍然保持 English，战斗内 Game.t() 继续输出英文；
	# 工具栏/设置/选人等外层 UI 则强制使用中文。
	if current_locale.begins_with("en") and is_only_in_game_translation_enabled():
		return "zh"
	return current_locale


func _apply_translation_server_locale() -> void:
	# Godot 会自动翻译场景中 Control 的 text。仅局内翻译开启时让 TranslationServer
	# 停在中文，防止工具栏等自动变英文；战斗文字仍由 Game.t() 按 current_locale 手动翻译。
	TranslationServer.set_locale(get_ui_locale())


func translate_ui_text(source:String) -> String:
	if source.is_empty():
		return source

	var exact_key:String = resolve_translation_key(source)
	if not exact_key.is_empty():
		return ui_t(exact_key)

	# V420 性能：伤害跳字 "-12"、"暴击 37" 这类文本每 0.35s 扫一遍，
	# 每个新字符串都要过一遍几百条片段的 contains()。翻译表与语言不变时结果是确定的，
	# 因此跨 sweep 缓存片段替换结果；load_runtime_translations / set_language 时清空。
	var cache_key:String = get_ui_locale() + "\u001f" + source
	if _ui_fragment_translation_cache.has(cache_key):
		return _ui_fragment_translation_cache[cache_key]
	# 处理 "当前角色：牛"、"端口: 27018" 等组合文本。
	# 片段表在 CSV 加载时一次性构建，切换语言时不再做 O(节点数×翻译数) 的嵌套扫描。
	var result:String = source
	for fragment in _translation_fragments:
		var part:String = str(fragment[0])
		if result.contains(part):
			result = result.replace(part, ui_t(str(fragment[1])))
	if _ui_fragment_translation_cache.size() >= _UI_FRAGMENT_TRANSLATION_CACHE_MAX:
		_ui_fragment_translation_cache.clear()
	_ui_fragment_translation_cache[cache_key] = result
	return result


var _ui_fragment_translation_cache:Dictionary = {}
const _UI_FRAGMENT_TRANSLATION_CACHE_MAX:int = 4096


func translate_game_text(source:String) -> String:
	if source.is_empty():
		return source

	var exact_key:String = resolve_translation_key(source)
	if not exact_key.is_empty():
		return t(exact_key)

	var result:String = source
	for fragment in _translation_fragments:
		var part:String = str(fragment[0])
		if result.contains(part):
			result = result.replace(part, t(str(fragment[1])))
	return result


func _strip_numeric_copy_suffix(key:String) -> String:
	# 角色包里常见 "角色(1)" / "角色（1）"。
	# 基础角色已有翻译时，副本自动复用，不必为每个副本重复写 CSV。
	var close_char:String = ""
	var open_char:String = ""
	if key.ends_with(")"):
		open_char = "("
		close_char = ")"
	elif key.ends_with("）"):
		open_char = "（"
		close_char = "）"
	else:
		return key

	var open_pos:int = key.rfind(open_char)
	if open_pos <= 0:
		return key
	var suffix:String = key.substr(
		open_pos + open_char.length(),
		key.length() - open_pos - open_char.length() - close_char.length()
	)
	if suffix.is_valid_int():
		return key.substr(0, open_pos)
	return key


func _append_translation_candidate(candidates:Array[String], value:String) -> void:
	if not value.is_empty() and not candidates.has(value):
		candidates.append(value)


func t(key:String) -> String:
	return _t_for_locale(key, current_locale, true)


func ui_t(key:String) -> String:
	return _t_for_locale(key, get_ui_locale(), false)


# Immutable fallback labels: do not allocate the same table for every translation.
const RUNTIME_LABELS:Dictionary = {
	# 角色显示别名：只改玩家看到的名称，内部资源/文件名保持不变。
	"影子": ["懦夫", "Coward"],
	"SETTING_TRAINING_MODE": ["训练模式", "Training Mode"],
	"SETTING_MANUAL_TRAINING": ["手动训练", "Manual Training"],
	"SETTING_MANUAL_COLLISION_DAMAGE": ["鼠标碰撞伤害", "Mouse Collision Damage"],
	"SETTING_MANUAL_ATTACK_INTERVAL": ["发射间隔", "Fire Interval"],
	"SETTING_BLOOD_EFFECTS": ["血液", "Blood"],
	"SETTING_TRAINING_DEBUG_MODE": ["威胁调试显示", "Threat Debug Overlay"],
	"SETTINGS_CATEGORY_TRAINING": ["训练", "Training"],
	"SETTINGS_CATEGORY_PARAMETERS": ["参数", "Parameters"],
	"SETTINGS_CATEGORY_EFFECTS": ["特效", "Effects"],
	"EFFECT_PREVIEW_WAR_TRANSFORM": ["战争女神·变身", "War Goddess · Transform"],
	"EFFECT_PREVIEW_WAR_IMMUNITY": ["战争女神·免疫", "War Goddess · Immunity"],
	"EFFECT_PREVIEW_WAR_CIRCLE": ["战争女神·法阵", "War Goddess · Magic Circle"],
	"EFFECT_PREVIEW_VIOLA_FIRE": ["薇欧拉·完整火焰", "Viola · Full Fire"],
	"EFFECT_PREVIEW_PLAY": ["重播", "Replay"],
	"EFFECT_PREVIEW_CHARACTER": ["人物", "Character"],
	"EFFECT_PREVIEW_AUTO": ["循环", "Loop"],
	"EFFECT_PREVIEW_SOUND": ["音效", "Sound"],
	"EFFECT_PREVIEW_SHORTCUT_HINT": ["快捷键：空格重播  ←/→切换  C人物  A循环  M音效  1/2/3/4直选", "Shortcuts: Space replay  ←/→ switch  C character  A loop  M sound  1/2/3/4 select"],
	"MANUAL_ATTACK_LABEL": ["攻击", "Attack"],
	"MANUAL_ATTACK_HINT": ["按住右键连续发射；有角色时自动瞄准最近角色，无角色时按鼠标移动方向自由瞄准", "Hold right click to fire; aims at the nearest character, or follows mouse movement when no target exists"],
	"MANUAL_NO_ATTACKS": ["没有可用攻击", "No attacks found"],
	"SETTING_ONLY_IN_GAME_TRANSLATION": ["仅局内翻译", "In-game Translation Only"],
	"SETTING_ENABLE_DIALOGUE": ["开启对话", "Enable Dialogue"],
	"SETTING_TRAINING_MODE_TYPE": ["模式", "Mode"],
	"TRAINING_MODE_MANUAL": ["手动模式", "Manual"],
	"TRAINING_MODE_ROTATION": ["轮放模式", "Rotation"],
	"TRAINING_MODE_TIMED": ["计时模式", "Timed"],
	"TRAINING_MODE_BOSS": ["Boss模式", "Boss"],
	"SETTING_TRAINING_WHEEL_BATTLE": ["车轮战", "Winner Stays"],
	"SETTING_TRAINING_BOSS_WHEEL_BATTLE": ["车轮战", "Wheel Battle"],
	"SETTING_TRAINING_TIME": ["时间", "Time"],
	"SETTING_TRAINING_BOSS_SIDE": ["Boss队伍", "Boss Side"],
	"SETTING_TRAINING_BOSS_MULTIPLIER": ["Boss倍率", "Boss Multiplier"],
	"SETTING_TRAINING_BOSS_SPECIALIZATION": ["Boss特殊化", "Boss Specialization"],
	"SETTING_TRAINING_BOSS_INTRO": ["Boss开场动画", "Boss Intro"],
	"TRAINING_SIDE_LEFT": ["左队", "Left"],
	"TRAINING_SIDE_RIGHT": ["右队", "Right"],
	"UI_SEARCH_CHARACTER": ["搜索人物", "Search characters"],
	"TRAINING_TIME_LEFT": ["剩余时间", "Time Left"],
	"TRAINING_TIME_UP": ["时间到", "Time Up"],
	"TRAINING_DAMAGE": ["伤害", "Damage"],
	"TRAINING_WINNER": ["胜者", "Winner"],
	"TRAINING_DRAW": ["平局", "Draw"],
}


func _t_for_locale(key:String, locale:String, record_missing:bool = true) -> String:
	var standardized:String = TranslationServer.standardize_locale(locale)
	var base_locale:String = standardized.split("_")[0]

	# 后加入的训练/设置界面文本。即使 translations.csv 还没有更新，
	# 也保证运行时创建的控件不会显示裸 key。

	if RUNTIME_LABELS.has(key):
		var pair:Array = RUNTIME_LABELS[key]
		return str(pair[1] if base_locale == "en" else pair[0])

	# 角色文件名可能带 (1)/(2)、全角（1），也可能用下划线。
	# 统一生成少量候选 key，既不扫描整张翻译表，也能兼容角色包常见命名方式。
	var candidates:Array[String] = []
	var stripped:String = _strip_numeric_copy_suffix(key)
	_append_translation_candidate(candidates, key)
	_append_translation_candidate(candidates, stripped)
	_append_translation_candidate(candidates, key.replace("_", " "))
	_append_translation_candidate(candidates, stripped.replace("_", " "))
	_append_translation_candidate(candidates, key.replace(" ", "_"))
	_append_translation_candidate(candidates, stripped.replace(" ", "_"))

	for candidate:String in candidates:
		if _translation_table.has(standardized) and _translation_table[standardized].has(candidate):
			return str(_translation_table[standardized][candidate])
		if _translation_table.has(base_locale) and _translation_table[base_locale].has(candidate):
			return str(_translation_table[base_locale][candidate])

	for candidate:String in candidates:
		var translated:String = str(TranslationServer.translate(candidate))
		if translated != candidate:
			return translated

	if record_missing and base_locale == "en" and _contains_cjk(key):
		_record_missing_translation(stripped)
	return key


func _contains_cjk(text:String) -> bool:
	for index in range(text.length()):
		var codepoint:int = text.unicode_at(index)
		if codepoint >= 0x3400 and codepoint <= 0x9FFF:
			return true
	return false


func _record_missing_translation(key:String) -> void:
	if key.is_empty() or _missing_translation_keys.has(key):
		return

	_missing_translation_keys[key] = true
	_missing_translation_dirty = true

	# 不要每发现一个角色名就同步打开/写入/关闭磁盘文件。
	# 合并到当前帧结束后一次性写，切 English 时不会因为几十个角色造成卡顿。
	if not _missing_translation_flush_scheduled:
		_missing_translation_flush_scheduled = true
		call_deferred("_flush_missing_translations_file")


func _flush_missing_translations_file() -> void:
	_missing_translation_flush_scheduled = false
	if not _missing_translation_dirty:
		return
	_missing_translation_dirty = false

	var keys:Array = _missing_translation_keys.keys()
	keys.sort()

	var file := FileAccess.open(MISSING_TRANSLATIONS_PATH, FileAccess.WRITE)
	if file == null:
		return

	file.store_csv_line(PackedStringArray(["keys", "zh", "en"]))
	for key_var in keys:
		var key:String = str(key_var)
		file.store_csv_line(PackedStringArray([key, key, ""]))
	file.close()


func set_language(locale:String, save_after:bool = true) -> void:
	if not SUPPORTED_LOCALES.has(locale):
		return

	# 如果 CSV 曾被替换/热更新而运行时表为空，则重新加载。
	if _runtime_translations.is_empty():
		load_runtime_translations()

	current_locale = locale
	_apply_translation_server_locale()
	_ui_fragment_translation_cache.clear()

	if save_after:
		_game.save_persistent_settings()

	_refresh_localized_game_ui()
	_refresh_runtime_localized_texts()
	_game.language_changed.emit(locale)


func _refresh_localized_game_ui() -> void:
	if not _game.is_node_ready():
		return

	if is_instance_valid(_game.speed_text):
		_game.speed_text.text = ui_t("UI_SPEED") + ":" + str(_game.get_base_game_time_scale()) + "x"
	if _game.now_stop_state and is_instance_valid(_game.stop_text):
		_game.stop_text.text = ui_t("UI_STOP")


func _runtime_localization_property(control:Control,property_name:String,meta_prefix:String,translation_cache:Dictionary = {}) -> void:
	var current_value:String = str(control.get(property_name))
	if current_value.is_empty():
		return
	var source_meta:StringName = StringName("_v277_locale_source_" + meta_prefix)
	var output_meta:StringName = StringName("_v277_locale_output_" + meta_prefix)
	var source:String = str(control.get_meta(source_meta,current_value))
	var last_output:String = str(control.get_meta(output_meta,""))
	if not last_output.is_empty() and current_value != last_output:
		source = current_value
	elif not control.has_meta(source_meta):
		source = current_value
	# Same text appears in many cloned health bars/tooltips. Reuse the translation
	# only within this sweep; dynamic text and subsequent sweeps are never stale.
	var locale_key:String = get_ui_locale() + "\u001f" + TranslationServer.get_locale()
	if not translation_cache.has(locale_key):
		translation_cache[locale_key] = {}
	var locale_cache:Dictionary = translation_cache[locale_key]
	var translated:String
	if locale_cache.has(source):
		translated = locale_cache[source]
	else:
		translated = translate_ui_text(source)
		locale_cache[source] = translated
	control.set_meta(source_meta,source)
	control.set_meta(output_meta,translated)
	if translated != current_value:
		control.set(property_name,translated)


func _localize_runtime_control_tree(root:Node,translation_cache:Dictionary = {}) -> void:
	if root == null:
		return
	if root is Control:
		var control:Control = root as Control
		if control is Label or control is Button or control is RichTextLabel:
			_runtime_localization_property(control,"text","text",translation_cache)
		if control is LineEdit:
			_runtime_localization_property(control,"placeholder_text","placeholder",translation_cache)
		if not control.tooltip_text.is_empty():
			_runtime_localization_property(control,"tooltip_text","tooltip",translation_cache)
	for child:Node in root.get_children():
		_localize_runtime_control_tree(child,translation_cache)


func _refresh_runtime_localized_texts() -> void:
	# 中文模式兜底：处理旧场景和运行时动态创建但没有显式调用 Game.ui_t/Game.t 的文本。
	if not current_locale.begins_with("zh"):
		return
	_ensure_runtime_localization_index()
	var scene:Node = _game.get_tree().current_scene
	var translation_cache:Dictionary = {}
	# SceneTree groups are returned in scene order and remove freed/exited nodes
	# automatically. Scan controls, not every projectile/timer/snapshot in battle.
	for node:Node in _game.get_tree().get_nodes_in_group(RUNTIME_LOCALIZATION_GROUP):
		if not is_instance_valid(node) or not node.is_inside_tree():
			continue
		if not ((scene != null and (node == scene or scene.is_ancestor_of(node))) or node == _game or _game.is_ancestor_of(node)):
			continue
		_localize_runtime_control(node as Control,translation_cache)


const RUNTIME_LOCALIZATION_GROUP:StringName = &"_runtime_localization_controls"

var _runtime_localization_index_ready:bool = false


func _ensure_runtime_localization_index() -> void:
	if _runtime_localization_index_ready:
		return
	_runtime_localization_index_ready = true
	_game.get_tree().node_added.connect(_on_runtime_localization_node_added)
	_seed_runtime_localization_index(_game.get_tree().root)


func _seed_runtime_localization_index(node:Node) -> void:
	if node is Control:
		node.add_to_group(RUNTIME_LOCALIZATION_GROUP)
	for child:Node in node.get_children():
		_seed_runtime_localization_index(child)


func _on_runtime_localization_node_added(node:Node) -> void:
	if not node is Control:
		return
	# V420 性能：战斗中每帧入树的绝大多数 Control 是伤害跳字/血条克隆。
	# 它们的祖先链稳定，用父节点实例 ID 记住“是否位于内部 UI 子树”，避免每个节点都爬到根。
	var parent:Node = node.get_parent()
	if parent != null:
		var parent_id:int = parent.get_instance_id()
		if _runtime_localization_parent_verdict.has(parent_id):
			if _runtime_localization_parent_verdict[parent_id]:
				node.add_to_group(RUNTIME_LOCALIZATION_GROUP)
			return
	if node.is_in_group(RUNTIME_LOCALIZATION_GROUP):
		node.remove_from_group(RUNTIME_LOCALIZATION_GROUP)
	# Match get_children() from the old traversal: internal UI implementation
	# nodes (and their descendants) must not acquire automatic localization.
	var ancestor:Node = node
	while ancestor.get_parent() != null:
		var parent_node:Node = ancestor.get_parent()
		if parent_node.get_child_count(true) != parent_node.get_child_count() and not parent_node.get_children().has(ancestor):
			_remember_localization_parent_verdict(node,false)
			return
		ancestor = parent_node
	_remember_localization_parent_verdict(node,true)
	node.add_to_group(RUNTIME_LOCALIZATION_GROUP)


# 父节点 → 其直接子 Control 是否允许自动本地化。只缓存“父节点自身不是内部节点”的结论；
# 一个节点是不是内部节点由它的 parent 决定，所以按父节点缓存是安全的。
var _runtime_localization_parent_verdict:Dictionary = {}
const _RUNTIME_LOCALIZATION_VERDICT_CACHE_MAX:int = 2048


func _remember_localization_parent_verdict(node:Node,allowed:bool) -> void:
	var parent:Node = node.get_parent()
	if parent == null:
		return
	# 只有当 node 本身不是 parent 的内部子节点时，这个结论才对 parent 的其它普通子节点同样成立。
	if parent.get_child_count(true) != parent.get_child_count() and not parent.get_children().has(node):
		return
	if _runtime_localization_parent_verdict.size() >= _RUNTIME_LOCALIZATION_VERDICT_CACHE_MAX:
		_runtime_localization_parent_verdict.clear()
	_runtime_localization_parent_verdict[parent.get_instance_id()] = allowed


func _localize_runtime_control(control:Control,translation_cache:Dictionary) -> void:
	if control is Label or control is Button or control is RichTextLabel:
		_runtime_localization_property(control,"text","text",translation_cache)
	if control is LineEdit:
		_runtime_localization_property(control,"placeholder_text","placeholder",translation_cache)
	if not control.tooltip_text.is_empty():
		_runtime_localization_property(control,"tooltip_text","tooltip",translation_cache)


func toggle_language() -> void:
	set_language("en" if current_locale.begins_with("zh") else "zh")


func get_language_display_name() -> String:
	return "中文" if current_locale.begins_with("zh") else "English"
