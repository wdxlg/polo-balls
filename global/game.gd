extends Control

#设定
# V126：多人端口固定为 27018。UI 中的输入框是“服务器地址/IP”，不是端口输入框。
const port := 27018
const max_player := 10

#========================================================
# 持久化设置 / 语言
#========================================================
signal language_changed(locale:String)
signal game_setting_changed(setting:String, value:Variant)
# V126：统一给多人 UI 的连接状态/玩家列表/双向 RPC 自检使用。
signal network_state_changed()
# V127：局域网 / EasyTier / 蒲公英等虚拟局域网房间发现列表变化。
signal room_list_changed()
# 训练奖励只关心“真正结算掉的生命”，而不是 Hitbox 理论伤害。
# source 是实际归属角色（投射物会归因给 Master），target 是受击人物。
signal training_damage_resolved(source:Node, target:Node, actual_health_damage:float)
# 月计角色等通用战斗系统使用：普通对局也广播真实生命伤害与实际死亡。
signal combat_damage_resolved(source:Node, target:Node, actual_health_damage:float, target_health_before:float)
signal combatant_died(victim:Node, killer:Node, health_before_lethal:float)

const SETTINGS_PATH := "user://settings.cfg"
const TRANSLATION_CSV_PATH := "res://translations.csv"
const TRANSLATION_CATALOG_SCRIPT = preload("res://global/translation_catalog.gd")
const MISSING_TRANSLATIONS_PATH := "user://missing_translations.csv"
const SUPPORTED_LOCALES := ["zh", "en"]

# 长按左键框选放置：覆盖层只画屏幕空间矩形，实际生成点仍使用世界坐标。
const PLACEMENT_BOX_OVERLAY_SCRIPT = preload("res://scripts/ui/placement_box_overlay.gd")
const KILL_BLOOD_SCRIPT:Script = preload("res://scripts/effects/若叶睦_击杀血液.gd")
# V39：批量击杀时，通用击杀血的玩法结算仍立即完成，但视觉实例分帧创建，避免同一帧几十/上百个节点分配造成卡顿。
const KILL_BLOOD_VISUAL_SPAWN_BUDGET_PER_FRAME:int = 2
const WILD_DOG_OLD_AGE_REMAINS_SCENE:PackedScene = preload("res://scenes/effects/野生狗奶老死残骸.tscn")
const WILD_DOG_OLD_AGE_DEADLINE_META:StringName = &"wild_dog_milk_old_age_death_deadline_msec"
const WILD_DOG_OLD_AGE_HEALTH_META:StringName = &"wild_dog_milk_old_age_death_health_before"
const WILD_DOG_OLD_AGE_AUDIO_PLAYED_META:StringName = &"wild_dog_milk_old_age_death_audio_played"
const WILD_DOG_OLD_AGE_BASE_BODY_WIDTH_WORLD:float = 36.0
const WILD_DOG_OLD_AGE_MIN_SIZE_MULTIPLIER:float = 0.90
const WILD_DOG_OLD_AGE_REMAINS_CONTAINER_NAME:StringName = &"野生狗奶老死残骸容器"
const PLACEMENT_BOX_HOLD_TIME:float = 0.30
const PLACEMENT_BOX_GRID_SPACING:float = 30.0
const PLACEMENT_BOX_MIN_MULTI_SPAN:float = 20.0
const PLACEMENT_BOX_MAX_CHARACTERS:int = 256
const WILD_DOG_TIME_MUSIC:AudioStream = preload("res://audio/characters/meme/野生狗奶/古风音乐 P1 《吹梦到西洲dj(0.8x)》《野生狗奶の小曲》黄诗扶、王敬轩丨“忘你不舍 寻你不休 画外人易朽 似浓淡相间色相构”.mp3")
const BLOOD_JACKPOT_AUDIO:AudioStream = preload("res://audio/system/血液爆炸.mp3")

var _pending_kill_blood_visuals:Array[Dictionary] = []
var _kill_blood_visual_drain_running:bool = false


# V96：掷骰子点数7与占卜师“四命运之轮”共用的全局大奖反馈。
# 这里只负责本机视觉/声音；调用者本身已有 call_local RPC，因此不会二次广播。
func play_blood_jackpot_flash_local() -> void:
	var scene_root:Node = get_tree().current_scene
	if scene_root == null or not is_instance_valid(scene_root):
		return

	var flash_layer := CanvasLayer.new()
	flash_layer.name = "BloodJackpotFlash"
	flash_layer.layer = 190
	scene_root.add_child(flash_layer)

	var flash := ColorRect.new()
	flash.name = "RedFlash"
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.position = Vector2.ZERO
	flash.size = get_viewport_rect().size
	flash.color = Color(0.92,0.0,0.025,0.0)
	flash_layer.add_child(flash)

	var flash_tween:Tween = flash.create_tween()
	flash_tween.tween_property(flash,"color:a",0.48,0.055).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	flash_tween.tween_property(flash,"color:a",0.0,0.19).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	flash_tween.finished.connect(flash_layer.queue_free)

	var player := AudioStreamPlayer.new()
	player.name = "BloodJackpotAudio"
	player.stream = BLOOD_JACKPOT_AUDIO
	player.volume_db = 9.0
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	scene_root.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

#========================================================
# V126 多人连接诊断状态
#========================================================
var network_role:String = "offline" # offline / host / client
var network_target_address:String = ""
var network_last_error:String = ""
var network_rpc_verified:bool = false
var network_ping_ms:int = -1
var _network_ping_token:int = 0
var _network_ping_elapsed:float = 0.0
const NETWORK_PING_INTERVAL:float = 2.0

#========================================================
# V127 房间发现：只负责“同一局域网 / 虚拟局域网里谁正在开房”
#========================================================
# 游戏 ENet 仍固定 UDP 27018；房间发现使用独立 UDP 27019，避免和 ENet 争用同一端口。
const ROOM_DISCOVERY_PORT:int = 27019
const ROOM_DISCOVERY_MAGIC:String = "POLO_BALLS_ROOM_DISCOVERY"
const ROOM_DISCOVERY_PROTOCOL:int = 1
const ROOM_DISCOVERY_INTERVAL:float = 2.5
const ROOM_DISCOVERY_EXPIRE_SECONDS:float = 6.0

var discovered_rooms:Dictionary = {}
var _room_host_socket:PacketPeerUDP = null
var _room_browser_socket:PacketPeerUDP = null
var _room_discovery_elapsed:float = 0.0
var _room_scan_token:int = 0
var _room_last_signature:String = ""

#========================================================
# V128 多人权限 / C 键直接控制角色
#========================================================
# 本机只保存“我正在控制谁”；服务器保存 peer -> NodePath，所有玩法输入仍由服务器 authority 执行。
const MULTIPLAYER_CONTROL_RING_SCRIPT = preload("res://scripts/ui/multiplayer_control_ring.gd")

var controlled_character_local:Node = null
var _control_rings_by_peer:Dictionary = {}
var _remote_control_assignments:Dictionary = {}
var _controlled_ring:Node2D = null # 旧字段仅兼容旧调用；V277 起不再是唯一控制圈。
var _controlled_peer_paths:Dictionary = {}
var _controlled_path_peers:Dictionary = {}
var _last_control_move_sent:Vector2 = Vector2(999,999)
# V380：直接控制动作键支持“按住 = 连续点击”。本机只记录鼠标键保持状态；
# 客户端仅在按下/松开时可靠通知服务器，持续连发由 authority 在物理帧本地重试，
# 避免把 60Hz 长按变成 60 个 reliable RPC/秒。
const CONTROL_ACTION_HOLD_INITIAL_REPEAT_DELAY_MSEC:int = 45
var _local_control_action_hold_mask:int = 0
var _local_control_action_repeat_ready_msec:Array[int] = [0,0,0]
var _remote_control_action_hold_masks:Dictionary = {}
var _remote_control_action_repeat_ready_msec:Dictionary = {}
var _runtime_localization_sweep_left:float = 0.0
const RUNTIME_LOCALIZATION_SWEEP_INTERVAL:float = 0.35

func is_network_guest() -> bool:
	return network_role == "client" and multiplayer.has_multiplayer_peer()

func guest_has_free_permissions() -> bool:
	return bool(Game_Settings.get("Guest_Free_Permissions",false))

func can_local_manage_world() -> bool:
	return not is_network_guest() or guest_has_free_permissions()

func can_local_change_settings() -> bool:
	return can_local_manage_world()

func can_local_delete_characters() -> bool:
	return can_local_manage_world()

func can_local_edit_team_structure() -> bool:
	return can_local_manage_world()

func _remote_guest_admin_allowed(sender_id:int) -> bool:
	return sender_id > 0 and (sender_id == 1 or guest_has_free_permissions())

func request_world_reset() -> void:
	if not can_local_manage_world():
		return
	if network_role == "client":
		_request_world_reset.rpc_id(Server_Id)
		return
	var world:Node = get_tree().current_scene
	if world != null and world.has_method("reset"):
		world.call("reset")

@rpc("any_peer","call_remote","reliable")
func _request_world_reset() -> void:
	if not multiplayer.is_server():
		return
	var sender_id:int = multiplayer.get_remote_sender_id()
	if not _remote_guest_admin_allowed(sender_id):
		return
	var world:Node = get_tree().current_scene
	if world != null and world.has_method("reset"):
		world.call("reset")

func request_world_rematch(exact_replay:bool) -> void:
	if not can_local_manage_world():
		return
	if network_role == "client":
		_request_world_rematch.rpc_id(Server_Id,exact_replay)
		return
	var world:Node = get_tree().current_scene
	if world != null and world.has_method("rematch_last_battle"):
		world.call("rematch_last_battle",exact_replay)


@rpc("any_peer","call_remote","reliable")
func _request_world_rematch(exact_replay:bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_id:int = multiplayer.get_remote_sender_id()
	if not _remote_guest_admin_allowed(sender_id):
		return
	var world:Node = get_tree().current_scene
	if world != null and world.has_method("rematch_last_battle"):
		world.call("rematch_last_battle",exact_replay)


func request_map_choice(map_name:String) -> void:
	if not can_local_manage_world():
		return
	if network_role == "client":
		_request_map_choice.rpc_id(Server_Id,map_name)
		return
	_apply_map_choice_local(map_name)
	if multiplayer.is_server() and multiplayer.has_multiplayer_peer():
		_apply_map_choice_remote.rpc(_current_world_map_name())

func _current_world_map_name() -> String:
	var world:Node = get_tree().current_scene
	if world != null and "now_choose_map" in world:
		return str(world.get("now_choose_map"))
	return ""

func _apply_map_choice_local(map_name:String) -> void:
	var world:Node = get_tree().current_scene
	if world == null or not ("now_choose_map" in world):
		return
	var target:String = map_name
	if target.is_empty() and "default_map" in world:
		target = str(world.get("default_map"))
	if "map_group" in world:
		var maps:Variant = world.get("map_group")
		if maps is Dictionary and not (maps as Dictionary).has(target):
			return
	world.set("now_choose_map",target)
	if world.has_method("refresh_map_presentation"):
		world.call("refresh_map_presentation")

@rpc("any_peer","call_remote","reliable")
func _request_map_choice(map_name:String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id:int = multiplayer.get_remote_sender_id()
	if not _remote_guest_admin_allowed(sender_id):
		return
	_apply_map_choice_local(map_name)
	_apply_map_choice_remote.rpc(_current_world_map_name())

@rpc("authority","call_remote","reliable")
func _apply_map_choice_remote(map_name:String) -> void:
	_apply_map_choice_local(map_name)

func get_local_controlled_character() -> Node:
	if controlled_character_local != null and is_instance_valid(controlled_character_local):
		return controlled_character_local
	controlled_character_local = null
	return null

func is_controlling_character() -> bool:
	return get_local_controlled_character() != null

func should_follow_controlled_character() -> bool:
	return is_controlling_character() and bool(Game_Settings.get("Follow_Controlled_Character",false))


func release_character_control_for_death(target:Node) -> void:
	# V94：自定义死亡动画可能让 0HP 角色继续留在场景树几秒。
	# “留在树里播放动画”不能等同于“仍被玩家控制”：死亡瞬间就清掉本机跟随与服务器控制映射。
	if target == null or not is_instance_valid(target):
		return
	var target_path_string:String = str(target.get_path()) if target.is_inside_tree() else ""
	var was_local_target:bool = get_local_controlled_character() == target
	if was_local_target:
		_set_local_control_target(null)
		if network_role == "client" and multiplayer.has_multiplayer_peer():
			_request_release_control.rpc_id(Server_Id)

	if multiplayer.is_server():
		var peers_to_release:Array[int] = []
		for peer_key:Variant in _controlled_peer_paths.keys():
			if str(_controlled_peer_paths[peer_key]) == target_path_string:
				peers_to_release.append(int(peer_key))
		for peer_id:int in peers_to_release:
			_release_control_for_peer(peer_id)
	elif not multiplayer.has_multiplayer_peer() and target.has_method("set_player_control_peer"):
		target.call("set_player_control_peer",0)

func _is_network_shared_setting(setting:String) -> bool:
	# 语言显示域、水印和“跟随我控制的角色”属于每台机器自己的表现设置；其它玩法设置跟随房主房间。
	return setting not in ["Only_In_Game_Translation","Show_Center_Watermark","Follow_Controlled_Character","Map_Background"]

func _shared_settings_snapshot() -> Dictionary:
	var snapshot:Dictionary = {}
	for raw_key:Variant in Game_Settings.keys():
		var key:String = str(raw_key)
		if _is_network_shared_setting(key):
			snapshot[key] = Game_Settings[key]
	return snapshot

func _apply_runtime_game_setting_local(setting:String,value:Variant,save_after:bool) -> void:
	if not Game_Settings.has(setting):
		return
	if setting == "Training_Mode":
		set_training_mode(bool(value))
	elif setting == "Training_Mode_Type":
		var mode:String = str(value)
		if mode not in ["manual","rotation","timed","boss"]:
			mode = "manual"
		Game_Settings[setting] = mode
		game_setting_changed.emit(setting,mode)
	else:
		Game_Settings[setting] = value
		game_setting_changed.emit(setting,value)
		if setting == "Only_In_Game_Translation":
			_apply_translation_server_locale()
			_refresh_localized_game_ui()
			language_changed.emit(current_locale)
	if save_after:
		save_persistent_settings()

@rpc("any_peer","call_remote","reliable")
func _request_runtime_game_setting(setting:String,value:Variant) -> void:
	if not multiplayer.is_server() or not Game_Settings.has(setting) or not _is_network_shared_setting(setting):
		return
	var sender_id:int = multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	# Guest_Free_Permissions 关闭时，任何房客都不能靠 RPC 自己提权。
	if not guest_has_free_permissions():
		return
	_apply_runtime_game_setting_local(setting,value,false)
	_receive_shared_setting.rpc(setting,Game_Settings[setting])

@rpc("authority","call_remote","reliable")
func _receive_shared_setting(setting:String,value:Variant) -> void:
	if not _is_network_shared_setting(setting):
		return
	_apply_runtime_game_setting_local(setting,value,false)
	network_state_changed.emit()

@rpc("authority","call_remote","reliable")
func _receive_shared_settings(snapshot:Dictionary) -> void:
	for raw_key:Variant in snapshot.keys():
		var key:String = str(raw_key)
		if Game_Settings.has(key) and _is_network_shared_setting(key):
			_apply_runtime_game_setting_local(key,snapshot[raw_key],false)
	# V276：房间玩法设置来自房主，但语言永远是每台机器自己的本地表现设置。
	# 客户端接收完整 snapshot 后重新应用本机 locale，并刷新运行时创建的 UI，
	# 防止加入房间后部分 Control 沿用连接瞬间/房主侧的英文显示。
	_apply_translation_server_locale()
	_refresh_localized_game_ui()
	language_changed.emit(current_locale)
	network_state_changed.emit()

var current_locale:String = "zh"
var _saved_speed_slider_value:Variant = null
var _runtime_translations:Array[Translation] = []
var _translation_table:Dictionary = {}
var _translation_reverse:Dictionary = {}
var _translation_reverse_any:Dictionary = {}
var _translation_fragments:Array = []
var _missing_translation_keys:Dictionary = {}
var _missing_translation_dirty:bool = false
var _missing_translation_flush_scheduled:bool = false

#========================================================
# 对局可复现随机源
#========================================================
# “重打”左键会重新使用同一个对局种子；右键会生成新种子。
# 全局 rand* 由 seed() 复现；项目里自行创建 RandomNumberGenerator 的脚本
# 通过 battle_rng_seed_or() 获得同一对局下稳定的子种子，避免 Time/get_instance_id 打破重现。
var _battle_random_active:bool = false
var _battle_random_seed:int = 1
var _battle_random_counters:Dictionary = {}


func _normalize_battle_seed(value:int) -> int:
	var normalized:int = posmod(value,2147483646) + 1
	return normalized


func make_battle_random_seed() -> int:
	var ticks:int = int(Time.get_ticks_usec())
	var unix_part:int = int(Time.get_unix_time_from_system() * 1000000.0)
	return _normalize_battle_seed(ticks ^ unix_part ^ int(randi()))


func begin_battle_random(seed_value:int) -> int:
	_battle_random_seed = _normalize_battle_seed(seed_value)
	_battle_random_active = true
	_battle_random_counters.clear()
	seed(_battle_random_seed)
	return _battle_random_seed


func end_battle_random() -> void:
	_battle_random_active = false
	_battle_random_counters.clear()


func is_battle_random_active() -> bool:
	return _battle_random_active


func current_battle_random_seed() -> int:
	return _battle_random_seed if _battle_random_active else 0


func derive_battle_random_seed(tag:String, ordinal:int = 0) -> int:
	# 使用固定整数混合，不依赖对象 instance_id，也不消耗全局 rand* 序列。
	var mixed:int = _normalize_battle_seed(_battle_random_seed)
	for byte_value:int in tag.to_utf8_buffer():
		mixed = int((mixed * 48271 + int(byte_value) + 1) % 2147483647)
	mixed = int((mixed + (ordinal + 1) * 104729) % 2147483647)
	return maxi(mixed,1)


func next_battle_rng_seed(tag:String) -> int:
	if not _battle_random_active:
		return make_battle_random_seed()
	var ordinal:int = int(_battle_random_counters.get(tag,0))
	_battle_random_counters[tag] = ordinal + 1
	return derive_battle_random_seed(tag,ordinal)


func battle_rng_seed_or(tag:String, fallback_seed:int) -> int:
	if _battle_random_active:
		return next_battle_rng_seed(tag)
	return _normalize_battle_seed(fallback_seed)


func reseed_battle_global(tag:String, ordinal:int = 0) -> void:
	if not _battle_random_active:
		return
	seed(derive_battle_random_seed(tag,ordinal))


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
	if config.load(SETTINGS_PATH) == OK:
		var saved_locale:String = str(config.get_value("ui","locale","zh"))
		if SUPPORTED_LOCALES.has(saved_locale):
			current_locale = saved_locale
		if Game_Settings.has("Only_In_Game_Translation"):
			Game_Settings["Only_In_Game_Translation"] = bool(
				config.get_value(
					"game_settings",
					"Only_In_Game_Translation",
					Game_Settings["Only_In_Game_Translation"]
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
	return bool(Game_Settings.get("Only_In_Game_Translation", false))


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

	# 处理 "当前角色：牛"、"端口: 27018" 等组合文本。
	# 片段表在 CSV 加载时一次性构建，切换语言时不再做 O(节点数×翻译数) 的嵌套扫描。
	var result:String = source
	for fragment in _translation_fragments:
		var part:String = str(fragment[0])
		if result.contains(part):
			result = result.replace(part, ui_t(str(fragment[1])))
	return result


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


func load_persistent_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_PATH)

	if err == OK:
		for setting in Game_Settings.keys():
			if str(setting) in ["Training_Mode", "Training_Mode_Type", "Manual_Training", "Manual_Collision_Damage", "Training_Debug_Mode"]:
				continue

			Game_Settings[setting] = config.get_value(
				"game_settings",
				str(setting),
				Game_Settings[setting]
			)

		current_locale = str(
			config.get_value(
				"ui",
				"locale",
				current_locale
			)
		)


	# 关键：
	# 不再恢复旧的 speed_slider。
	# 速度倍率直接影响 physics delta，高倍率会降低高速投射物碰撞可靠性。
	_saved_speed_slider_value = null
	# 训练模式不跨启动持久化，避免下次打开普通场景时误用 9999 生命和高速物理。
	Game_Settings["Training_Mode"] = false
	Game_Settings["Training_Mode_Type"] = "manual"
	Game_Settings["Manual_Training"] = false
	Game_Settings["Manual_Collision_Damage"] = false
	Game_Settings["Training_Debug_Mode"] = false
	set_manual_training_attack_interval(float(Game_Settings.get("Manual_Attack_Interval", 0.15)), false)
	if not SUPPORTED_LOCALES.has(current_locale):
		current_locale = "zh"

	_apply_translation_server_locale()


func save_persistent_settings() -> void:
	var config := ConfigFile.new()
	# 先加载旧文件，方便以后增加其他 section 时不被覆盖。
	config.load(SETTINGS_PATH)

	for setting in Game_Settings.keys():
		if str(setting) in ["Training_Mode", "Training_Mode_Type", "Manual_Training", "Manual_Collision_Damage", "Training_Debug_Mode"]:
			continue
		config.set_value(
			"game_settings",
			str(setting),
			Game_Settings[setting]
		)

	config.set_value("ui", "locale", current_locale)

	# 不保存速度滑条。
	# 速度仍然可以在本次运行中正常调整，只是不带到下一次启动。
	var err := config.save(SETTINGS_PATH)
	if err != OK:
		push_warning("无法保存设置: " + str(err))


func set_language(locale:String, save_after:bool = true) -> void:
	if not SUPPORTED_LOCALES.has(locale):
		return

	# 如果 CSV 曾被替换/热更新而运行时表为空，则重新加载。
	if _runtime_translations.is_empty():
		load_runtime_translations()

	current_locale = locale
	_apply_translation_server_locale()

	if save_after:
		save_persistent_settings()

	_refresh_localized_game_ui()
	_refresh_runtime_localized_texts()
	language_changed.emit(locale)


func _refresh_localized_game_ui() -> void:
	if not is_node_ready():
		return

	if is_instance_valid(speed_text):
		speed_text.text = ui_t("UI_SPEED") + ":" + str(_base_game_time_scale) + "x"
	if now_stop_state and is_instance_valid(stop_text):
		stop_text.text = ui_t("UI_STOP")


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
	var scene:Node = get_tree().current_scene
	var translation_cache:Dictionary = {}
	# SceneTree groups are returned in scene order and remove freed/exited nodes
	# automatically. Scan controls, not every projectile/timer/snapshot in battle.
	for node:Node in get_tree().get_nodes_in_group(RUNTIME_LOCALIZATION_GROUP):
		if not is_instance_valid(node) or not node.is_inside_tree():
			continue
		if not ((scene != null and (node == scene or scene.is_ancestor_of(node))) or node == self or is_ancestor_of(node)):
			continue
		_localize_runtime_control(node as Control,translation_cache)



const RUNTIME_LOCALIZATION_GROUP:StringName = &"_runtime_localization_controls"
var _runtime_localization_index_ready:bool = false

func _ensure_runtime_localization_index() -> void:
	if _runtime_localization_index_ready:
		return
	_runtime_localization_index_ready = true
	get_tree().node_added.connect(_on_runtime_localization_node_added)
	_seed_runtime_localization_index(get_tree().root)

func _seed_runtime_localization_index(node:Node) -> void:
	if node is Control:
		node.add_to_group(RUNTIME_LOCALIZATION_GROUP)
	for child:Node in node.get_children():
		_seed_runtime_localization_index(child)

func _on_runtime_localization_node_added(node:Node) -> void:
	if not node is Control:
		return
	if node.is_in_group(RUNTIME_LOCALIZATION_GROUP):
		node.remove_from_group(RUNTIME_LOCALIZATION_GROUP)
	# Match get_children() from the old traversal: internal UI implementation
	# nodes (and their descendants) must not acquire automatic localization.
	var ancestor:Node = node
	while ancestor.get_parent() != null:
		var parent_node:Node = ancestor.get_parent()
		if parent_node.get_child_count(true) != parent_node.get_child_count() and not parent_node.get_children().has(ancestor):
			return
		ancestor = parent_node
	node.add_to_group(RUNTIME_LOCALIZATION_GROUP)

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


func _on_speed_slider_drag_ended(value_changed:bool) -> void:
	if value_changed:
		save_persistent_settings()

#var normal_mouse_image = preload("res://Images/鼠标/鼠标默认.png")
#var click_mouse_image = preload("res://Images/鼠标/鼠标点击.png")

@export var Game_Settings:Dictionary = {
	Have_Team_Damage = true,
	Shaking_Camera = true,
	Camera_Move = true,
	Creating = true,
	Same_Ball_Change_Color = false,
	Set_Random_Char_When_Didnt_Choose = true,
	Ball_Can_Move = true,
	# V128：房主权限开关。关闭时房客只能放置角色/选择现有队伍/使用多人面板；
	# 不能删除角色、重置、换地图、创建/删除队伍或修改设置。
	Guest_Free_Permissions = false,
	# V128：控制角色时是否让本地 Camera2D 强制以该角色为中心。
	Follow_Controlled_Character = false,
	# 英文模式下只翻译战斗内文本；工具栏、设置和选人面板继续保持中文。
	Only_In_Game_Translation = false,
	# 地图中央创作者水印显示开关；属于普通参数并跨启动保存。
	Show_Center_Watermark = true,
	# 仅影响本机地图外观，旧存档缺少此项时仍使用原蓝色背景。
	Map_Background = "blue",
	# V184：全局击杀血液。关闭时若叶睦/墨提斯自身的击杀血仍保留；开启时其它人物击杀也会生成血液。
	Blood_Effects = false,
	# 角色对话总开关。开启后，支持对话的角色会把台词显示在地图下方的阵营槽位。
	Enable_Dialogue = false,
	# 训练玩法类型：manual / rotation / timed / boss。
	Training_Mode_Type = "manual",
	# 轮放模式：false=任一方死亡后双方都换下一位；true=胜者留场，只补死亡方。
	Training_Wheel_Battle = false,
	# 计时模式时长（秒）。SpinBox 可自由输入。
	Training_Timed_Duration = 60.0,
	# Boss 模式固定为左右两队；其中一侧按倍率强化。
	Training_Boss_Side = "right",
	Training_Boss_Multiplier = 3.0,
	# 开启后，Boss 角色除数值倍率外，还允许进入角色脚本定义的专属 Boss 形态。
	Training_Boss_Specialization = true,
	# Boss 车轮战：开启后每边只让队首上场，死亡后下一位再从地图外入场。
	Training_Boss_Wheel_Battle = false,
	# Boss 模式开场动画。关闭后仍正常应用 Boss 倍率/特殊化，只跳过出场演出直接开战。
	Training_Boss_Intro = true,
	# 训练模式是运行时开关：训练场会自动开启，普通场景默认关闭。
	# 开启后人物会使用训练生命规则，并扩展 ESC 速度滑条上限。
	Training_Mode = false,
	# 手动训练由所有 World 场景统一提供控制器；默认关闭，不跨启动保存。
	Manual_Training = false,
	Manual_Collision_Damage = false,
	# 显示 AI 真正读到的抽象威胁区域：低伤害白，高伤害红。
	Training_Debug_Mode = false,
	# 按住右键时的手动训练攻击间隔（游戏模拟秒）。
	Manual_Attack_Interval = 0.15,
}

const NORMAL_SPEED_SLIDER_MAX_VALUE:float = 19.0 # 原版最高 10x
const TRAINING_SPEED_SLIDER_MAX_VALUE:float = 41.0 # 映射后最高 32x
const TRAINING_MAX_PHYSICS_TICKS:int = 1920 # 32x * 60Hz
const MANUAL_ATTACK_INTERVAL_MIN:float = 0.02
const MANUAL_ATTACK_INTERVAL_MAX:float = 2.0
const MANUAL_ATTACK_INTERVAL_STEP:float = 0.01
var _normal_max_physics_steps_per_frame:int = 8

# 把投射物/召唤物的伤害归属递归收束到真正主人。
# 这样角色系统只需要关心“这笔伤害最终属于谁”，不必逐个适配武器。
func resolve_combat_source(source:Variant) -> Node:
	# source / Master 可能仍保存着 <Freed Object>。Godot 不会把所有旧引用自动变成 null，
	# 因此必须先 is_instance_valid()，再做 `is Node` / `as Node` 类型判断。
	if not is_instance_valid(source):
		return null
	if not (source is Node):
		return null
	var current:Node = source as Node
	var visited:Dictionary = {}
	for _i:int in range(8):
		if not is_instance_valid(current):
			return null
		var id:int = current.get_instance_id()
		if visited.has(id):
			break
		visited[id] = true

		# 不是所有伤害来源都一定声明 Master；先查属性，避免动态来源产生无意义报错。
		if not ("Master" in current):
			break
		var next_master:Variant = current.get("Master")
		# 顺序不能交换：已释放对象做类型判断/强转时本身就可能报
		# "Trying to assign invalid previously freed instance"。
		if not is_instance_valid(next_master):
			break
		if not (next_master is Node):
			break
		current = next_master as Node
	return current


# 普通对局也会调用。先广播通用真实伤害，再按原规则兼容训练统计。
func report_combat_damage(
	source:Variant,
	target:Variant,
	actual_health_damage:float,
	target_health_before:float
) -> void:
	# 延迟投射物/持续伤害结算时，攻击者或目标可能已经离树并释放。
	# 参数先保持 Variant，验证有效后才转换成 Node，避免函数入参阶段就触发悬空引用类型错误。
	if actual_health_damage <= 0.0:
		return
	if not is_instance_valid(source) or not is_instance_valid(target):
		return
	if not (target is Node):
		return
	var target_node:Node = target as Node
	if source is Node:
		_capture_kill_blood_context(source,target_node,actual_health_damage,target_health_before)
	var effective_source:Node = resolve_combat_source(source)
	if effective_source == null:
		return
	if target_node.has_method("record_combat_damage_source"):
		target_node.call("record_combat_damage_source", effective_source, target_health_before)
	combat_damage_resolved.emit(
		effective_source,
		target_node,
		actual_health_damage,
		target_health_before
	)
	report_training_damage(effective_source, target_node, actual_health_damage)


func report_combatant_death(
	victim:Variant,
	killer:Variant,
	health_before_lethal:float
) -> void:
	# killer 很可能在“致死伤害 -> 真正死亡状态结算”之间已经被删除。
	# 保持 Variant 并验证后再转型，已释放 killer 直接按无击杀者处理。
	if not is_instance_valid(victim) or not (victim is Node):
		return
	var victim_node:Node = victim as Node
	var effective_killer:Node = resolve_combat_source(killer)
	var is_wild_dog_old_age:bool = _is_wild_dog_old_age_death(
		victim_node,
		effective_killer,
		health_before_lethal
	)
	if is_wild_dog_old_age:
		# 老死是真正死亡：先按受害者自己的死亡音规则播放一次，再生成骨骸；但不生成攻击死亡血。
		_play_wild_dog_old_age_death_audio(victim_node)
		_spawn_wild_dog_old_age_remains(victim_node)
	else:
		# 野生狗奶自己的低额时间伤害如果先把人打死，仍属于普通伤害击杀；开启血液时照常喷血。
		_spawn_global_kill_blood(victim_node,effective_killer)
	_clear_wild_dog_old_age_marker(victim_node)
	combatant_died.emit(victim_node, effective_killer, maxf(health_before_lethal, 0.0))


func _play_wild_dog_old_age_death_audio(victim:Node) -> void:
	if victim == null or not is_instance_valid(victim):
		return
	victim.set_meta(WILD_DOG_OLD_AGE_AUDIO_PLAYED_META,true)
	var unique_stream:Variant = victim.get("Unique_Death_Audio")
	if unique_stream is AudioStream and unique_stream != null and victim.has_method("play_unique_audio"):
		# ball.Character_Audio_Slot.Death == 5
		victim.call("play_unique_audio",5,true)
		return
	var dead_audio_name:String = str(victim.get("Dead_Audio"))
	if not dead_audio_name.is_empty():
		Audios.play_sfx(dead_audio_name,{},true)


func _is_wild_dog_old_age_death(victim:Node,killer:Node,health_before_lethal:float) -> bool:
	if victim == null or killer == null or not is_instance_valid(victim) or not is_instance_valid(killer):
		return false
	if not killer.is_in_group("WildDogMilkCharacter"):
		return false
	if not victim.has_meta(WILD_DOG_OLD_AGE_DEADLINE_META) or not victim.has_meta(WILD_DOG_OLD_AGE_HEALTH_META):
		return false
	var deadline_msec:int = int(victim.get_meta(WILD_DOG_OLD_AGE_DEADLINE_META,0))
	if deadline_msec <= 0 or Time.get_ticks_msec() > deadline_msec:
		return false
	var marked_health_before:float = float(victim.get_meta(WILD_DOG_OLD_AGE_HEALTH_META,-INF))
	return absf(marked_health_before - maxf(health_before_lethal,0.0)) <= 1.1


func _clear_wild_dog_old_age_marker(victim:Node) -> void:
	if victim == null or not is_instance_valid(victim):
		return
	if victim.has_meta(WILD_DOG_OLD_AGE_DEADLINE_META):
		victim.remove_meta(WILD_DOG_OLD_AGE_DEADLINE_META)
	if victim.has_meta(WILD_DOG_OLD_AGE_HEALTH_META):
		victim.remove_meta(WILD_DOG_OLD_AGE_HEALTH_META)


func _spawn_wild_dog_old_age_remains(victim:Node) -> void:
	if victim == null or not is_instance_valid(victim) or not (victim is Node2D):
		return
	var origin:Vector2 = (victim as Node2D).global_position
	var seed_value:int = Game.battle_rng_seed_or("global/game.gd:seed_value",int(Time.get_ticks_usec()) ^ int(victim.get_instance_id()))
	var victim_body_width:float = _resolve_character_body_collision_world_width(victim)
	var remains_size_multiplier:float = maxf(
		victim_body_width / maxf(WILD_DOG_OLD_AGE_BASE_BODY_WIDTH_WORLD,0.001),
		WILD_DOG_OLD_AGE_MIN_SIZE_MULTIPLIER
	)
	if multiplayer.has_multiplayer_peer():
		_rpc_spawn_wild_dog_old_age_remains.rpc(origin,seed_value,remains_size_multiplier)
	else:
		_rpc_spawn_wild_dog_old_age_remains(origin,seed_value,remains_size_multiplier)


func _resolve_character_body_collision_world_width(victim:Node) -> float:
	# V281：骨架实际尺寸只看人物“本体” CollisionShape2D 的横向世界宽度。
	# 用 Shape2D.get_rect() 的四个角经过 CollisionShape2D 全局变换后的 X 包围宽度，
	# 因此会自动包含角色根 scale / collision node scale / rotation 等真实变换。
	if victim == null or not is_instance_valid(victim):
		return WILD_DOG_OLD_AGE_BASE_BODY_WIDTH_WORLD
	var body_collision:CollisionShape2D = victim.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body_collision == null or not is_instance_valid(body_collision) or body_collision.shape == null:
		return WILD_DOG_OLD_AGE_BASE_BODY_WIDTH_WORLD
	var local_rect:Rect2 = body_collision.shape.get_rect()
	if local_rect.size.x <= 0.001:
		return WILD_DOG_OLD_AGE_BASE_BODY_WIDTH_WORLD
	var local_corners:Array[Vector2] = [
		local_rect.position,
		Vector2(local_rect.end.x,local_rect.position.y),
		local_rect.end,
		Vector2(local_rect.position.x,local_rect.end.y)
	]
	var min_x:float = INF
	var max_x:float = -INF
	for local_point:Vector2 in local_corners:
		var world_point:Vector2 = body_collision.to_global(local_point)
		min_x = minf(min_x,world_point.x)
		max_x = maxf(max_x,world_point.x)
	var world_width:float = max_x - min_x
	if not is_finite(world_width) or world_width <= 0.001:
		return WILD_DOG_OLD_AGE_BASE_BODY_WIDTH_WORLD
	return world_width


func _ensure_wild_dog_old_age_remains_container(scene_root:Node) -> Node:
	# V309：World 根节点是 MultiplayerSpawner.spawn_path。老死残骸已经由本函数的 RPC 在各 peer
	# 使用同一 seed/size 手动创建，不能再作为 World 的直接子节点触发一次自动 Spawn。
	# 放进稳定的二级运行时容器后，残骸不再属于 spawn_path 的“直接子节点”；同时所有 add_child
	# 都使用 force_readable_name=true，避免同名节点被 Godot 改成 @StaticBody2D@xxxx 保留名称。
	if scene_root == null or not is_instance_valid(scene_root):
		return null
	var existing:Node = scene_root.get_node_or_null(NodePath(str(WILD_DOG_OLD_AGE_REMAINS_CONTAINER_NAME)))
	if existing != null and is_instance_valid(existing):
		return existing
	var container := Node2D.new()
	container.name = WILD_DOG_OLD_AGE_REMAINS_CONTAINER_NAME
	scene_root.add_child(container,true)
	return container


@rpc("authority","call_local","reliable")
func _rpc_spawn_wild_dog_old_age_remains(origin:Vector2,seed_value:int,size_multiplier:float = 1.0) -> void:
	if not is_inside_tree() or WILD_DOG_OLD_AGE_REMAINS_SCENE == null:
		return
	var scene_root:Node = get_tree().current_scene
	if scene_root == null:
		return
	var remains_parent:Node = _ensure_wild_dog_old_age_remains_container(scene_root)
	if remains_parent == null:
		return
	var remains:Node = WILD_DOG_OLD_AGE_REMAINS_SCENE.instantiate()
	if remains == null:
		return
	if remains.has_method("configure"):
		remains.call("configure",seed_value,maxf(size_multiplier,WILD_DOG_OLD_AGE_MIN_SIZE_MULTIPLIER))
	remains_parent.add_child(remains,true)
	if remains is Node2D:
		(remains as Node2D).global_position = origin


# 训练模式统计入口保持兼容。
func report_training_damage(source:Node, target:Node, actual_health_damage:float) -> void:
	# 轮放/计时/Boss 现在可以独立于 Training_Mode 运行。
	# 计时模式仍依赖这条信号累计实际生命伤害，因此不能只检查 is_training_mode()。
	if not is_training_mode() and not is_timed_training_mode():
		return
	if source == null or target == null or actual_health_damage <= 0.0:
		return
	training_damage_resolved.emit(source, target, actual_health_damage)


# 手动训练攻击选择。目录扫描只做一次并缓存；UI 和训练控制器共用同一份目录。
var manual_training_attack_id:String = "res://scenes/shooter/子弹.tscn"
var _manual_attack_catalog_cache:Array[Dictionary] = []

func is_training_mode() -> bool:
	return bool(Game_Settings.get("Training_Mode", false))


func set_training_mode(enabled:bool, apply_existing_characters:bool = true) -> void:
	Game_Settings["Training_Mode"] = enabled
	game_setting_changed.emit("Training_Mode", enabled)

	if not enabled:
		# 手动训练现在可以独立用于普通 World，因此关闭训练模式时不再强制关闭它。
		# 只有 AI 威胁调试覆盖仍严格属于训练模式。
		Game_Settings["Training_Debug_Mode"] = false
		game_setting_changed.emit("Training_Debug_Mode",false)

	# 训练模式下扩展 ESC 倍速上限；关闭后恢复普通游戏的 10x 上限。
	if is_instance_valid(speed_slider):
		speed_slider.max_value = (
			TRAINING_SPEED_SLIDER_MAX_VALUE
			if enabled
			else NORMAL_SPEED_SLIDER_MAX_VALUE
		)
		speed_slider.tick_count = int(speed_slider.max_value) + 1
		if speed_slider.value > speed_slider.max_value:
			speed_slider.value = speed_slider.max_value

	# 对已经放在场上的人物立即生效。新生成的人物会在 ball._ready() 再应用一次。
	if apply_existing_characters and get_tree() != null:
		for node:Node in get_tree().get_nodes_in_group("Ball"):
			if node != null and is_instance_valid(node) and node.has_method("apply_training_mode"):
				node.call("apply_training_mode", enabled)

	_apply_time_scale_overrides()


func set_runtime_game_setting(setting:String, value:Variant, save_after:bool = true) -> void:
	if not Game_Settings.has(setting):
		return

	# 联机共享玩法设置以服务器为唯一真值。房客未获得自由权限时，UI/脚本请求都拒绝。
	if _is_network_shared_setting(setting) and network_role == "client":
		if not guest_has_free_permissions():
			return
		_request_runtime_game_setting.rpc_id(Server_Id,setting,value)
		return

	_apply_runtime_game_setting_local(setting,value,save_after)
	if _is_network_shared_setting(setting) and multiplayer.is_server() and multiplayer.has_multiplayer_peer():
		_receive_shared_setting.rpc(setting,Game_Settings[setting])


func get_training_mode_type() -> String:
	var mode:String = str(Game_Settings.get("Training_Mode_Type", "manual"))
	return mode if mode in ["manual", "rotation", "timed", "boss"] else "manual"


func is_rotation_training_mode() -> bool:
	return get_training_mode_type() == "rotation"


func is_timed_training_mode() -> bool:
	return get_training_mode_type() == "timed"


func is_boss_training_mode() -> bool:
	return get_training_mode_type() == "boss"


func get_training_timed_duration() -> float:
	# 计时模式不再限制在固定预设；只保留 1 秒的安全下限。
	return maxf(float(Game_Settings.get("Training_Timed_Duration", 60.0)), 1.0)


func get_training_boss_side() -> String:
	var side:String = str(Game_Settings.get("Training_Boss_Side", "right"))
	return side if side in ["left","right"] else "right"


func get_training_boss_multiplier() -> float:
	return maxf(float(Game_Settings.get("Training_Boss_Multiplier", 3.0)), 1.0)


func is_training_boss_specialization_enabled() -> bool:
	return bool(Game_Settings.get("Training_Boss_Specialization", true))


func is_training_boss_wheel_battle_enabled() -> bool:
	return bool(Game_Settings.get("Training_Boss_Wheel_Battle", false))


func is_training_boss_intro_enabled() -> bool:
	return bool(Game_Settings.get("Training_Boss_Intro", true))


func is_global_blood_effects_enabled() -> bool:
	return bool(Game_Settings.get("Blood_Effects", false))


func _should_spawn_global_kill_blood(victim:Node, killer:Node) -> bool:
	if not is_global_blood_effects_enabled():
		return false
	if victim == null or killer == null or not is_instance_valid(victim) or not is_instance_valid(killer):
		return false
	if not (victim is Node2D) or not (killer is Node2D):
		return false

	# V262：全局“血液”开关只允许真正角色死亡生成击杀血。
	# ball 的 Shooter / Shooter_with_Health / Creature 也会进入 State.Die；
	# 高频投射物在互相碰撞、被攻击或正常销毁时，绝不能被当作“人物死亡”喷出通用击杀血。
	if not (victim is ball):
		return false
	var victim_ball:ball = victim as ball
	if victim_ball.Type != ball.Ball_Type.Ball:
		return false

	# 若叶睦/墨提斯的拳头或吉他已经按武器力度生成专属血液时，禁止再叠一层通用血。
	if bool(victim.get_meta("_wakaba_specific_kill_blood_spawned", false)):
		return false
	return true


func _capture_kill_blood_context(source:Node,target:Node,damage:float,health_before:float) -> void:
	# 在 Master 归因之前保存真实命中物的运动；只在已确认掉血后调用。
	var context:Dictionary = {"kind":"generic","speed":180.0,"damage":damage,"reference_health":health_before}
	if source is Node2D and target is Node2D:
		context["direction"] = ((target as Node2D).global_position - (source as Node2D).global_position).normalized()
	var motion:Vector2 = source.velocity if source is CharacterBody2D else Vector2.ZERO
	var explicit_motion:Variant = source.get_meta("blood_attack_velocity",motion)
	if explicit_motion is Vector2: motion = explicit_motion
	if motion.is_finite() and motion.length_squared() > 1.0:
		context["speed"] = minf(motion.length(),1600.0)
		if source.has_method("_is_projectile_motion_object") and bool(source.call("_is_projectile_motion_object")):
			context["kind"] = "pierce"
			context["direction"] = motion.normalized()
	var explicit_kind:String = str(source.get_meta("blood_damage_kind",""))
	if explicit_kind in ["pierce","slash","crush","blast","burn"]:
		context["kind"] = explicit_kind
		if explicit_kind == "pierce" and motion.length_squared() > 1.0:
			context["direction"] = motion.normalized()
	if str(target.get_meta("_blood_damage_element","")) == "fire":
		context["kind"] = "burn"
	target.set_meta("_kill_blood_context",context)


func _spawn_global_kill_blood(victim:Node, killer:Node) -> void:
	if not _should_spawn_global_kill_blood(victim,killer):
		return
	var victim_2d:Node2D = victim as Node2D
	var killer_2d:Node2D = killer as Node2D
	var direction_value:Vector2 = victim_2d.global_position - killer_2d.global_position
	if direction_value.length_squared() <= 0.000001:
		direction_value = Vector2.RIGHT
	else:
		direction_value = direction_value.normalized()
	var seed_value:int = int(randi())
	var context:Dictionary = victim.get_meta("_kill_blood_context",{})
	if multiplayer.has_multiplayer_peer():
		_rpc_spawn_global_kill_blood.rpc(victim_2d.global_position,direction_value,seed_value,context)
	else:
		_rpc_spawn_global_kill_blood(victim_2d.global_position,direction_value,seed_value,context)


@rpc("authority","call_local","unreliable")
func _rpc_spawn_global_kill_blood(origin:Vector2,base_direction:Vector2,seed_value:int,context:Dictionary = {}) -> void:
	if not is_inside_tree():
		return
	# V39：这里只登记视觉请求，不在死亡回调当帧立刻创建整套血液节点。
	# 多杀时伤害/死亡/击杀统计仍已同步完成；只有纯视觉被摊到后续几帧。
	_pending_kill_blood_visuals.append({
		"origin": origin,
		"direction": base_direction,
		"seed": seed_value,
		"context": context.duplicate(),
	})
	if not _kill_blood_visual_drain_running:
		call_deferred("_drain_kill_blood_visual_queue")


func _drain_kill_blood_visual_queue() -> void:
	if _kill_blood_visual_drain_running or not is_inside_tree():
		return
	_kill_blood_visual_drain_running = true
	while is_inside_tree() and not _pending_kill_blood_visuals.is_empty():
		var budget:int = maxi(KILL_BLOOD_VISUAL_SPAWN_BUDGET_PER_FRAME,1)
		while budget > 0 and not _pending_kill_blood_visuals.is_empty():
			var request:Dictionary = _pending_kill_blood_visuals.pop_front()
			_spawn_global_kill_blood_visual_now(
				request.get("origin",Vector2.ZERO),
				request.get("direction",Vector2.RIGHT),
				int(request.get("seed",0)),
				request.get("context",{})
			)
			budget -= 1
		if not _pending_kill_blood_visuals.is_empty():
			await get_tree().process_frame
	_kill_blood_visual_drain_running = false


func _spawn_global_kill_blood_visual_now(origin:Vector2,base_direction:Vector2,seed_value:int,context:Dictionary = {}) -> void:
	if not is_inside_tree():
		return
	var scene_root:Node = get_tree().current_scene
	if scene_root == null:
		return
	var effect:Node2D = KILL_BLOOD_SCRIPT.new() as Node2D
	if effect == null:
		return
	effect.name = "GlobalKillBloodBurst"
	scene_root.add_child(effect)
	# 通用人物击杀使用中等力度。若叶睦拳头/吉他会走角色自己的两个专属 profile。
	effect.call("configure",origin,base_direction,2,seed_value,7,10.0,220.0,context)


func set_manual_training_attack_interval(value:float, save_after:bool = false) -> void:
	var clamped_value:float = snappedf(
		clampf(value, MANUAL_ATTACK_INTERVAL_MIN, MANUAL_ATTACK_INTERVAL_MAX),
		MANUAL_ATTACK_INTERVAL_STEP
	)
	set_runtime_game_setting("Manual_Attack_Interval",clamped_value,save_after)


func get_manual_training_attack_interval() -> float:
	return clampf(
		float(Game_Settings.get("Manual_Attack_Interval", 0.15)),
		MANUAL_ATTACK_INTERVAL_MIN,
		MANUAL_ATTACK_INTERVAL_MAX
	)


func set_manual_training_attack(attack_id:String) -> void:
	var wanted:String = attack_id.strip_edges()
	if wanted.is_empty():
		return
	manual_training_attack_id = wanted
	game_setting_changed.emit("Manual_Training_Attack", wanted)


func get_manual_training_attack() -> String:
	return manual_training_attack_id


func get_manual_attack_catalog(force_refresh:bool = false) -> Array[Dictionary]:
	if not force_refresh and not _manual_attack_catalog_cache.is_empty():
		return _manual_attack_catalog_cache.duplicate(true)

	var catalog:Array[Dictionary] = []
	_collect_manual_attack_scenes("res://scenes/shooter", catalog)

	# 拳击手的拳头不是独立 PackedScene，因此作为一个特殊攻击显式加入。
	catalog.append({
		"id": "special://boxer_fist",
		"label": "拳击手：拳头",
		"kind": "boxer_fist",
		"path": "",
	})

	# V175：用于手动测试血液落地/贴墙表现的特殊攻击。当前飞行体先使用红色小方块占位。
	catalog.append({
		"id": "special://blood",
		"label": "血",
		"kind": "blood",
		"path": "",
	})

	catalog.sort_custom(func(a:Dictionary, b:Dictionary) -> bool:
		return str(a.get("label", "")) < str(b.get("label", ""))
	)
	_manual_attack_catalog_cache = catalog.duplicate(true)

	var found_selected:bool = false
	for entry:Dictionary in _manual_attack_catalog_cache:
		if str(entry.get("id", "")) == manual_training_attack_id:
			found_selected = true
			break
	if not found_selected and not _manual_attack_catalog_cache.is_empty():
		manual_training_attack_id = str(_manual_attack_catalog_cache[0].get("id", ""))

	return _manual_attack_catalog_cache.duplicate(true)


func _collect_manual_attack_scenes(directory_path:String, out:Array[Dictionary]) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry_name:String = directory.get_next()
	while not entry_name.is_empty():
		if entry_name != "." and entry_name != "..":
			var full_path:String = directory_path.path_join(entry_name)
			if directory.current_is_dir():
				_collect_manual_attack_scenes(full_path, out)
			elif entry_name.to_lower().ends_with(".tscn"):
				var packed:PackedScene = ResourceLoader.load(full_path) as PackedScene
				if packed != null:
					var probe:Node = packed.instantiate()
					if probe is Node2D:
						out.append({
							"id": full_path,
							"label": str(probe.name),
							"kind": "scene",
							"path": full_path,
						})
					probe.free()
		entry_name = directory.get_next()
	directory.list_dir_end()


@export var mouse_in_map:bool = false
#引用
@onready var stop_background: ColorRect = $Stop_Ui/Stop_background
@onready var stop_text: Label = $Stop_Ui/Stop_Text
var Stop_Override_Tween:Tween

@onready var vignette: ColorRect = $Vignette/Vignette
const vignette_stop := 0.9
const vignette_start := 1.2
var Vignette_Tween:Tween

@onready var speed_control: Control = $Stop_Ui/Speed_Control
@onready var speed_slider: HSlider = $Stop_Ui/Speed_Control/Speed_Slider
@onready var speed_text: Label = $Stop_Ui/Speed_Control/Speed_Text

@onready var now_stop_state:bool = false
var mouse_drag := false
# V34：区分“中键当前按住”和“这次中键拖动是否由战场相机拥有”。
# 按下发生在 UI 上时，mouse_drag 仍供已有 UI 拖动逻辑使用，但相机不会接管。
var world_middle_drag := false

# V378：比 V132 的 _enter_tree 更早，在对象 _init 阶段就恢复保存语言并安装翻译。
# 这一步专门覆盖“编辑器正常、导出后大量中文先被系统英文 locale 翻走”的启动时序。
func _init() -> void:
	_bootstrap_localization_before_tree()


func _enter_tree() -> void:
	# _init 已确定本机保存语言。进入树时只重申最终 UI locale，
	# 不再无条件先写 zh，避免 English 用户和“仅局内翻译”产生一次错误首帧。
	_apply_translation_server_locale()

func _ready() -> void:
	# _init 已先装入编译翻译表保证导出首帧；这里优先用原始 CSV 刷新到最新内容。
	# 导出 PCK 没有 CSV 原文件时，load_runtime_translations() 会自动继续使用编译表。
	load_runtime_translations()
	load_persistent_settings()
	_normal_max_physics_steps_per_frame = Engine.max_physics_steps_per_frame

	#Input.set_custom_mouse_cursor(normal_mouse_image,Input.CURSOR_ARROW,Vector2(5,10))
	#
	# 像素风 UI：禁用线性过滤，避免字体/图标因为缩放发糊。
	# Speed_Control 本身不再使用 2.005 之类的小数缩放。
	speed_control.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	speed_slider.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	speed_text.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stop_text.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	
	init_game()
	
	speed_slider.value_changed.connect(set_speed)
	speed_slider.drag_ended.connect(_on_speed_slider_drag_ended)
	# 普通场景保持原来的 10x 上限；训练场调用 set_training_mode(true) 后会扩到 32x。
	speed_slider.max_value = (
		TRAINING_SPEED_SLIDER_MAX_VALUE
		if is_training_mode()
		else NORMAL_SPEED_SLIDER_MAX_VALUE
	)
	speed_slider.tick_count = int(speed_slider.max_value) + 1
	set_speed(speed_slider.value,false)
	
	if not multiplayer.peer_connected.is_connected(when_connect):
		multiplayer.peer_connected.connect(when_connect)
	if not multiplayer.peer_disconnected.is_connected(when_disconnect):
		multiplayer.peer_disconnected.connect(when_disconnect)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

	# 房间浏览器始终使用独立的临时 UDP 端口监听回复；开房后才额外占用 27019 响应发现请求。
	_setup_room_browser_socket()
	request_room_scan(true)


func _exit_tree() -> void:
	# 再保存一次最终状态，覆盖键盘/手柄调节速度等没有 drag_ended 的情况。
	save_persistent_settings()
	_close_room_host_socket()
	if _room_browser_socket != null:
		_room_browser_socket.close()
		_room_browser_socket = null

#多人
const Server_Id:int = 1

#--------------------------------------------------------
# V127 房间发现
#--------------------------------------------------------
func _setup_room_browser_socket() -> void:
	if _room_browser_socket != null and _room_browser_socket.is_bound():
		return
	_room_browser_socket = PacketPeerUDP.new()
	_room_browser_socket.set_broadcast_enabled(true)
	var error:Error = _room_browser_socket.bind(0,"0.0.0.0")
	if error != OK:
		push_warning("房间发现浏览器 UDP 绑定失败: " + error_string(error))
		_room_browser_socket = null


func _start_room_host_socket() -> void:
	_close_room_host_socket()
	_room_host_socket = PacketPeerUDP.new()
	_room_host_socket.set_broadcast_enabled(true)
	var error:Error = _room_host_socket.bind(ROOM_DISCOVERY_PORT,"0.0.0.0")
	if error != OK:
		push_warning("房间发现主机 UDP 端口 " + str(ROOM_DISCOVERY_PORT) + " 绑定失败: " + error_string(error))
		_room_host_socket = null


func _close_room_host_socket() -> void:
	if _room_host_socket != null:
		_room_host_socket.close()
		_room_host_socket = null


func _room_packet_to_dictionary(packet:PackedByteArray) -> Dictionary:
	if packet.is_empty():
		return {}
	var parsed:Variant = JSON.parse_string(packet.get_string_from_utf8())
	if parsed is not Dictionary:
		return {}
	return parsed as Dictionary


func _room_discovery_packet(packet_type:String, sent_ms:int, scan_token:int) -> PackedByteArray:
	return JSON.stringify({
		"magic": ROOM_DISCOVERY_MAGIC,
		"protocol": ROOM_DISCOVERY_PROTOCOL,
		"type": packet_type,
		"game_port": port,
		"sent_ms": sent_ms,
		"scan_token": scan_token,
	}).to_utf8_buffer()


func _room_info_packet(sent_ms:int, scan_token:int) -> PackedByteArray:
	var player_count:int = get_network_peer_ids().size()
	if player_count <= 0 and network_role == "host":
		player_count = 1
	return JSON.stringify({
		"magic": ROOM_DISCOVERY_MAGIC,
		"protocol": ROOM_DISCOVERY_PROTOCOL,
		"type": "room",
		"game_port": port,
		"players": player_count,
		"max_players": max_player,
		"sent_ms": sent_ms,
		"scan_token": scan_token,
	}).to_utf8_buffer()


func _is_valid_room_packet(data:Dictionary, expected_type:String) -> bool:
	return (
		str(data.get("magic","")) == ROOM_DISCOVERY_MAGIC
		and int(data.get("protocol",0)) == ROOM_DISCOVERY_PROTOCOL
		and str(data.get("type","")) == expected_type
	)


func _directed_broadcast_for_ipv4(address:String) -> String:
	var parts:PackedStringArray = address.split(".")
	if parts.size() != 4:
		return ""
	for part:String in parts:
		if not part.is_valid_int():
			return ""
		var value:int = int(part)
		if value < 0 or value > 255:
			return ""
	# 项目只需要局域网/虚拟局域网找房；EasyTier 默认本身就是 /24。
	return parts[0] + "." + parts[1] + "." + parts[2] + ".255"


func _room_discovery_targets() -> Array[String]:
	var targets:Array[String] = ["127.0.0.1","255.255.255.255"]
	for address:String in get_local_ipv4_addresses():
		var broadcast:String = _directed_broadcast_for_ipv4(address)
		if not broadcast.is_empty() and not targets.has(broadcast):
			targets.append(broadcast)
	return targets


func _is_virtual_lan_interface(interface_data:Dictionary) -> bool:
	var description:String = (
		str(interface_data.get("name","")) + " "
		+ str(interface_data.get("friendly",""))
	).to_lower()
	return (
		description.contains("easytier")
		or description.contains("oray")
		or description.contains("pgy")
		or description.contains("蒲公英")
	)


func _virtual_lan_scan_prefixes() -> Array[String]:
	var prefixes:Array[String] = []
	# EasyTier 默认 DHCP 网段为 10.126.126.0/24。即使其 UDP broadcast relay 没开，
	# 也对这一 /24 做少量单播探测，避免“能直连 IP 却搜不到房间”。
	for address:String in get_local_ipv4_addresses():
		var parts:PackedStringArray = address.split(".")
		if parts.size() == 4 and address.begins_with("10.126.126."):
			var prefix:String = parts[0] + "." + parts[1] + "." + parts[2] + "."
			if not prefixes.has(prefix):
				prefixes.append(prefix)

	# 自定义 EasyTier / 蒲公英虚拟网段：若系统网卡名称能识别，则同样扫描该适配器所在 /24。
	for interface_variant:Variant in IP.get_local_interfaces():
		if interface_variant is not Dictionary:
			continue
		var interface_data:Dictionary = interface_variant as Dictionary
		if not _is_virtual_lan_interface(interface_data):
			continue
		var addresses:Variant = interface_data.get("addresses",interface_data.get("address",[]))
		for raw_address:Variant in addresses:
			var address:String = str(raw_address)
			if address.contains(":"):
				continue
			var parts:PackedStringArray = address.split(".")
			if parts.size() != 4:
				continue
			var prefix:String = parts[0] + "." + parts[1] + "." + parts[2] + "."
			if not prefixes.has(prefix):
				prefixes.append(prefix)
	return prefixes


func request_room_scan(force:bool = false) -> void:
	_setup_room_browser_socket()
	if _room_browser_socket == null:
		return
	if not force and _room_discovery_elapsed < ROOM_DISCOVERY_INTERVAL:
		return
	_room_discovery_elapsed = 0.0
	_room_scan_token += 1
	var sent_ms:int = Time.get_ticks_msec()
	var packet:PackedByteArray = _room_discovery_packet("discover",sent_ms,_room_scan_token)

	# 普通 LAN 与支持广播转发的虚拟 LAN（EasyTier Game 的 WinIPBroadcast / UDP broadcast relay）走这里。
	for target:String in _room_discovery_targets():
		if _room_browser_socket.set_dest_address(target,ROOM_DISCOVERY_PORT) == OK:
			_room_browser_socket.put_packet(packet)

	# EasyTier 默认网段与可识别虚拟网卡提供单播 /24 fallback，不要求广播转发功能必须开启。
	var self_addresses:Array[String] = get_local_ipv4_addresses()
	for prefix:String in _virtual_lan_scan_prefixes():
		for host:int in range(1,255):
			var target:String = prefix + str(host)
			if self_addresses.has(target):
				continue
			if _room_browser_socket.set_dest_address(target,ROOM_DISCOVERY_PORT) == OK:
				_room_browser_socket.put_packet(packet)


func _process_room_host_requests() -> void:
	if _room_host_socket == null or network_role != "host":
		return
	while _room_host_socket.get_available_packet_count() > 0:
		var packet:PackedByteArray = _room_host_socket.get_packet()
		var sender_ip:String = _room_host_socket.get_packet_ip()
		var sender_port:int = _room_host_socket.get_packet_port()
		var data:Dictionary = _room_packet_to_dictionary(packet)
		if not _is_valid_room_packet(data,"discover"):
			continue
		if sender_ip.is_empty() or sender_port <= 0:
			continue
		var sent_ms:int = int(data.get("sent_ms",0))
		var scan_token:int = int(data.get("scan_token",0))
		if _room_host_socket.set_dest_address(sender_ip,sender_port) == OK:
			_room_host_socket.put_packet(_room_info_packet(sent_ms,scan_token))


func _process_room_browser_replies() -> void:
	if _room_browser_socket == null:
		return
	var changed:bool = false
	while _room_browser_socket.get_available_packet_count() > 0:
		var packet:PackedByteArray = _room_browser_socket.get_packet()
		var sender_ip:String = _room_browser_socket.get_packet_ip()
		var data:Dictionary = _room_packet_to_dictionary(packet)
		if not _is_valid_room_packet(data,"room"):
			continue
		if sender_ip.is_empty():
			continue
		var game_port:int = int(data.get("game_port",port))
		if game_port <= 0 or game_port > 65535:
			continue
		var sent_ms:int = int(data.get("sent_ms",0))
		var now_ms:int = Time.get_ticks_msec()
		var ping_ms:int = maxi(now_ms - sent_ms,0) if sent_ms > 0 else -1
		var room_key:String = sender_ip + ":" + str(game_port)
		var room:Dictionary = {
			"address": sender_ip,
			"port": game_port,
			"players": clampi(int(data.get("players",1)),0,max_player),
			"max_players": maxi(int(data.get("max_players",max_player)),1),
			"ping_ms": ping_ms,
			"last_seen_ms": now_ms,
		}
		discovered_rooms[room_key] = room
		changed = true
	if changed:
		_emit_room_list_if_changed()


func _expire_discovered_rooms() -> void:
	var now_ms:int = Time.get_ticks_msec()
	var expire_ms:int = int(ROOM_DISCOVERY_EXPIRE_SECONDS * 1000.0)
	var removed:bool = false
	for room_key:Variant in discovered_rooms.keys():
		var room:Dictionary = discovered_rooms[room_key] as Dictionary
		if now_ms - int(room.get("last_seen_ms",0)) > expire_ms:
			discovered_rooms.erase(room_key)
			removed = true
	if removed:
		_emit_room_list_if_changed()


func _emit_room_list_if_changed() -> void:
	var signature_parts:PackedStringArray = PackedStringArray()
	for room:Dictionary in get_discovered_rooms():
		signature_parts.append(
			str(room.get("address","")) + ":" + str(room.get("port",0))
			+ ":" + str(room.get("players",0))
			+ ":" + str(room.get("ping_ms",-1))
		)
	var signature:String = "|".join(signature_parts)
	if signature == _room_last_signature:
		return
	_room_last_signature = signature
	room_list_changed.emit()


func get_discovered_rooms() -> Array[Dictionary]:
	var result:Array[Dictionary] = []
	for room_variant:Variant in discovered_rooms.values():
		if room_variant is Dictionary:
			result.append((room_variant as Dictionary).duplicate())
	result.sort_custom(func(a:Dictionary,b:Dictionary) -> bool:
		var ap:int = int(a.get("ping_ms",999999))
		var bp:int = int(b.get("ping_ms",999999))
		if ap == bp:
			return str(a.get("address","")) < str(b.get("address",""))
		return ap < bp
	)
	return result


func _process_room_discovery(delta:float) -> void:
	_room_discovery_elapsed += maxf(delta,0.0)
	_process_room_host_requests()
	_process_room_browser_replies()
	_expire_discovered_rooms()
	if _room_discovery_elapsed >= ROOM_DISCOVERY_INTERVAL:
		request_room_scan(true)


func _reset_network_diagnostics() -> void:
	network_last_error = ""
	network_rpc_verified = false
	network_ping_ms = -1
	_network_ping_token = 0
	_network_ping_elapsed = 0.0


func disconnect_game(reason:String = "") -> void:
	if is_controlling_character():
		var old_target:Node = get_local_controlled_character()
		if old_target != null and old_target.has_method("set_player_control_peer") and multiplayer.is_server():
			old_target.call("set_player_control_peer",0)
		_set_local_control_target(null)
	_close_room_host_socket()
	# Godot 官方建议通过 OfflineMultiplayerPeer 结束当前高层多人连接。
	# 先切离旧 peer，避免连续点击“创建/加入”得到 ERR_ALREADY_IN_USE。
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	network_role = "offline"
	network_target_address = ""
	_reset_network_diagnostics()
	if not reason.is_empty():
		network_last_error = reason
	network_state_changed.emit()


func host_game() -> Error:
	# 新建主机前先干净断开旧连接。
	if multiplayer.has_multiplayer_peer():
		disconnect_game()
	var peer := ENetMultiplayerPeer.new()
	var error:Error = peer.create_server(port,max_player)
	if error != OK:
		network_role = "offline"
		network_last_error = "create_server: " + error_string(error)
		network_state_changed.emit()
		OS.alert(Game.ui_t("ERR_SERVER_START"))
		return error

	multiplayer.multiplayer_peer = peer
	network_role = "host"
	network_target_address = ""
	_reset_network_diagnostics()
	# 主机本地无需经过网络往返；真正有客户端连入后仍会收到 peer_connected。
	network_rpc_verified = true
	network_ping_ms = 0
	_start_room_host_socket()
	# 立即让本机浏览器刷新；其它设备会在下一轮发现扫描中看到这个房间。
	request_room_scan(true)
	network_state_changed.emit()
	return OK


func join_game(address:String) -> Error:
	var target:String = address.strip_edges()
	if target.is_empty():
		target = "127.0.0.1"
	if multiplayer.has_multiplayer_peer():
		disconnect_game()

	var peer := ENetMultiplayerPeer.new()
	var error:Error = peer.create_client(target,port)
	if error != OK:
		network_role = "offline"
		network_target_address = target
		network_last_error = "create_client: " + error_string(error)
		network_state_changed.emit()
		return error

	multiplayer.multiplayer_peer = peer
	network_role = "client"
	network_target_address = target
	_reset_network_diagnostics()
	network_state_changed.emit()
	return OK


func get_network_port() -> int:
	return port


func get_local_ipv4_addresses() -> Array[String]:
	var result:Array[String] = []
	for raw_address:String in IP.get_local_addresses():
		var address:String = raw_address.strip_edges()
		if address.is_empty() or address.contains(":"):
			continue
		if address == "127.0.0.1" or address.begins_with("169.254."):
			continue
		if not result.has(address):
			result.append(address)
	return result


func get_preferred_lan_address() -> String:
	var addresses:Array[String] = get_local_ipv4_addresses()
	# 优先常见私网地址，方便同一 Wi-Fi/局域网直接联机。
	for address:String in addresses:
		if address.begins_with("192.168.") or address.begins_with("10."):
			return address
		if address.begins_with("172."):
			var parts:PackedStringArray = address.split(".")
			if parts.size() >= 2 and parts[1].is_valid_int():
				var second:int = int(parts[1])
				if second >= 16 and second <= 31:
					return address
	return addresses[0] if not addresses.is_empty() else "127.0.0.1"


func get_network_peer_ids() -> Array[int]:
	var result:Array[int] = []
	if not multiplayer.has_multiplayer_peer():
		return result
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return result
	var local_id:int = multiplayer.get_unique_id()
	if local_id > 0:
		result.append(local_id)
	for peer_id:int in multiplayer.get_peers():
		if not result.has(peer_id):
			result.append(peer_id)
	result.sort()
	return result


func _on_connected_to_server() -> void:
	network_role = "client"
	network_last_error = ""
	# 连接建立本身不能改变本机语言。立即重套本地 locale，动态 UI 也同步刷新。
	_apply_translation_server_locale()
	_refresh_localized_game_ui()
	language_changed.emit(current_locale)
	network_state_changed.emit()
	_request_network_ping()


func _on_connection_failed() -> void:
	network_rpc_verified = false
	network_ping_ms = -1
	network_last_error = "connection_failed"
	network_state_changed.emit()


func _on_server_disconnected() -> void:
	_set_local_control_target(null)
	_remote_control_assignments.clear()
	_clear_all_control_rings()
	network_rpc_verified = false
	network_ping_ms = -1
	network_last_error = "server_disconnected"
	network_role = "offline"
	network_state_changed.emit()


func when_connect(id:int) -> void:
	print("玩家加入" + str(id))
	if multiplayer.is_server() and id != multiplayer.get_unique_id():
		_receive_shared_settings.rpc_id(id,_shared_settings_snapshot())
		_sync_control_assignments.rpc_id(id,_controlled_peer_paths.duplicate(true))
	network_state_changed.emit()


func when_disconnect(id:int) -> void:
	print("玩家退出" + str(id))
	if multiplayer.is_server():
		_release_control_for_peer(id)
	network_state_changed.emit()


func _request_network_ping() -> void:
	if network_role != "client" or not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_network_ping_token += 1
	var token:int = _network_ping_token
	var sent_ms:int = Time.get_ticks_msec()
	_network_ping_elapsed = 0.0
	_network_ping_request.rpc_id(Server_Id,token,sent_ms)


func _process_network_ping(delta:float) -> void:
	if network_role != "client" or not multiplayer.has_multiplayer_peer():
		_network_ping_elapsed = 0.0
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_network_ping_elapsed += maxf(delta,0.0)
	if _network_ping_elapsed >= NETWORK_PING_INTERVAL:
		_request_network_ping()


@rpc("any_peer","call_remote","reliable")
func _network_ping_request(token:int,client_sent_ms:int) -> void:
	# 只允许服务器回答。这个往返同时验证：客户端 RPC -> 服务器 -> 客户端 RPC。
	if not multiplayer.is_server():
		return
	var sender_id:int = multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	_network_ping_reply.rpc_id(sender_id,token,client_sent_ms)


@rpc("authority","call_remote","reliable")
func _network_ping_reply(token:int,client_sent_ms:int) -> void:
	if network_role != "client" or token != _network_ping_token:
		return
	network_ping_ms = maxi(Time.get_ticks_msec() - client_sent_ms,0)
	network_rpc_verified = true
	network_last_error = ""
	network_state_changed.emit()


@rpc("any_peer")
func create_ball_in_server(team_value:String,character_name:String,poi:Vector2) -> void:
	var tree := get_tree()
	var world := tree.current_scene
	if world is not World:
		return
	
	world.create_char(
				team_value,
				character_name,
				poi
			)

func _find_ball_ancestor(node:Node) -> Node:
	var current:Node = node
	while current != null:
		if current.is_in_group("Ball"):
			return current
		current = current.get_parent()
	return null


func _ball_visual_contains_world_point(character:Node,world_point:Vector2) -> bool:
	if character == null or not is_instance_valid(character):
		return false
	var visual_variant:Variant = character.get("image")
	var visual:Node2D = null
	if visual_variant is Node2D:
		visual = visual_variant as Node2D
	if visual == null:
		visual = character.get_node_or_null("Graphics/Image") as Node2D
	if visual == null:
		visual = character.get_node_or_null("Graphics/AnimatedSprite2D") as Node2D
	if visual == null or not is_instance_valid(visual) or not visual.visible:
		return false

	var local_point:Vector2 = visual.to_local(world_point)
	if visual is Sprite2D:
		var sprite:Sprite2D = visual as Sprite2D
		if sprite.texture == null:
			return false
		return sprite.get_rect().grow(2.0).has_point(local_point)
	if visual is AnimatedSprite2D:
		var animated:AnimatedSprite2D = visual as AnimatedSprite2D
		if animated.sprite_frames == null or not animated.sprite_frames.has_animation(animated.animation):
			return false
		var texture:Texture2D = animated.sprite_frames.get_frame_texture(animated.animation,animated.frame)
		if texture == null:
			return false
		var size:Vector2 = Vector2(texture.get_size())
		var rect_pos:Vector2 = animated.offset
		if animated.centered:
			rect_pos -= size * 0.5
		return Rect2(rect_pos,size).grow(2.0).has_point(local_point)
	return false


func _delete_char_at_authority(position:Vector2) -> void:
	if not is_multiplayer_authority():
		return

	var world_node:Node = get_tree().current_scene
	if world_node is not World:
		return

	# V82：删除查询同时看 CharacterBody2D 与 Area2D，而且不再限定旧的 2/4/8 层。
	# 角色的根碰撞、hurtbox/hitbox 只要任意一个真实 Shape 位于点击点，都可以找到 Ball 根节点。
	var params := PhysicsPointQueryParameters2D.new()
	params.position = position
	params.collide_with_areas = true
	params.collide_with_bodies = true
	params.collision_mask = 0xFFFFFFFF

	var space_state := (world_node as World).get_world_2d().direct_space_state
	var result:Array[Dictionary] = space_state.intersect_point(params,64)
	var candidates:Dictionary = {}

	for hit:Dictionary in result:
		var collider_variant:Variant = hit.get("collider",null)
		if not collider_variant is Node:
			continue
		var target:Node = _find_ball_ancestor(collider_variant as Node)
		if target == null or not is_instance_valid(target):
			continue
		candidates[target.get_instance_id()] = target

	# V83：很多角色的手调碰撞箱会明显小于人物图片，轮放预览还可能完全叠在一起。
	# 物理点查询没命中时，再按实际显示 Sprite 的矩形做一次视觉点击兜底。
	# 这里只决定“鼠标指的是谁”，真正删除的仍是 Ball 根节点，不修改任何战斗碰撞规则。
	if candidates.is_empty():
		for node:Node in get_tree().get_nodes_in_group("Ball"):
			if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
				continue
			if _ball_visual_contains_world_point(node,position):
				candidates[node.get_instance_id()] = node

	if candidates.is_empty():
		return

	# 多个人物重叠时只删除离点击位置最近的一名，避免一次右键误删整团人物。
	var chosen:Node = null
	var best_distance_sq:float = INF
	for candidate_variant:Variant in candidates.values():
		if not candidate_variant is Node2D:
			continue
		var candidate:Node2D = candidate_variant as Node2D
		var distance_sq:float = candidate.global_position.distance_squared_to(position)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			chosen = candidate

	if chosen == null or not is_instance_valid(chosen):
		return

	if world_node.has_method("forget_battle_setup_node"):
		world_node.call("forget_battle_setup_node",chosen)
	Game.free_node(chosen)


@rpc("any_peer","call_remote","reliable")
func delete_char_in_server(position:Vector2) -> void:
	# 客户端只提交点击世界坐标，真正的物理查询与删除始终由 authority 执行。
	if not is_multiplayer_authority():
		return
	var sender_id:int = multiplayer.get_remote_sender_id()
	if sender_id > 0 and sender_id != multiplayer.get_unique_id() and not guest_has_free_permissions():
		return
	_delete_char_at_authority(position)


func delete_char_at(position:Vector2) -> void:
	if not can_local_delete_characters():
		return
	if is_multiplayer_authority():
		_delete_char_at_authority(position)
	else:
		delete_char_in_server.rpc_id(Server_Id,position)


# 兼容旧调用：仍保留 delete_char()，但不再使用可能落后一帧的 mouse_poi 做唯一入口。
func delete_char() -> void:
	var world_node:Node = get_tree().current_scene
	if world_node is World:
		delete_char_at((world_node as World).get_global_mouse_position())


func _manual_training_owns_right_click() -> bool:
	return get_training_mode_type() == "manual" and bool(Game_Settings.get("Manual_Training",false))


func _control_has_ancestor_named(control:Control,wanted_name:String) -> bool:
	var cursor:Node = control
	while cursor != null:
		if cursor.name == wanted_name:
			return true
		cursor = cursor.get_parent()
	return false


func _right_click_is_over_blocking_gui() -> bool:
	# V82 的“只要有 hovered Control 就禁止删除”过于宽泛：项目里存在覆盖战场的
	# 通用 Control，因此地图空白处也可能永远被判成 UI，导致右键删除完全进不去。
	# V83 只拦真正需要鼠标交互的控件/面板。轮放名字 HUD 单独交给它自己的 _gui_input。
	var hovered:Control = get_viewport().gui_get_hovered_control()
	if hovered == null:
		return false
	if _control_has_ancestor_named(hovered,"RotationVersusHUD"):
		return true

	var cursor:Node = hovered
	while cursor != null:
		if (
			cursor is BaseButton
			or cursor is LineEdit
			or cursor is TextEdit
			or cursor is SpinBox
			or cursor is Slider
			or cursor is ScrollBar
			or cursor is ScrollContainer
			or cursor is ItemList
			or cursor is Tree
		):
			return true
		# 这些是项目现有的大面板根节点；右键它们的空白处也不能误删后面的角色。
		if str(cursor.name) in ["Settings","Team","Game_Setting","MultiPlayer","Map","Stop_Ui"]:
			return true
		cursor = cursor.get_parent()
	return false


func _try_world_right_click_delete(world:World) -> bool:
	if world == null or not is_instance_valid(world):
		return false
	if _manual_training_owns_right_click() or not can_local_delete_characters() or is_controlling_character():
		return false
	if _right_click_is_over_blocking_gui():
		return false

	delete_char_at(world.get_global_mouse_position())
	return true

func _find_control_candidate(world:World) -> Node:
	if world == null or not is_instance_valid(world):
		return null
	var point:Vector2 = world.get_global_mouse_position()
	var chosen:Node = null
	var best_distance:float = INF
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not (node is ball) or not is_instance_valid(node):
			continue
		var candidate:ball = node as ball
		if candidate.Type != ball.Ball_Type.Ball or candidate.health <= 0:
			continue
		if candidate.has_method("is_combat_targetable") and not bool(candidate.call("is_combat_targetable")):
			continue
		if not _ball_visual_contains_world_point(candidate,point):
			continue
		var distance:float = candidate.global_position.distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			chosen = candidate
	return chosen

func _local_control_peer_id() -> int:
	if multiplayer.has_multiplayer_peer():
		return maxi(multiplayer.get_unique_id(),1)
	return 1


func _clear_control_ring() -> void:
	var peer_id:int = _local_control_peer_id()
	var ring:Node = _control_rings_by_peer.get(peer_id) as Node
	if ring != null and is_instance_valid(ring):
		ring.queue_free()
	_control_rings_by_peer.erase(peer_id)
	_controlled_ring = null


func _clear_all_control_rings() -> void:
	for ring_value:Variant in _control_rings_by_peer.values():
		var ring:Node = ring_value as Node
		if ring != null and is_instance_valid(ring):
			ring.queue_free()
	_control_rings_by_peer.clear()
	_controlled_ring = null


func _current_control_assignments_for_display() -> Dictionary:
	var result:Dictionary = {}
	if multiplayer.has_multiplayer_peer():
		var source:Dictionary = _controlled_peer_paths if multiplayer.is_server() else _remote_control_assignments
		for peer_key:Variant in source.keys():
			var peer_id:int = int(peer_key)
			var path_string:String = str(source[peer_key])
			if peer_id > 0 and not path_string.is_empty():
				result[peer_id] = path_string
	else:
		var local_target:Node = get_local_controlled_character()
		if local_target != null:
			result[1] = str(local_target.get_path())

	var local_target:Node = get_local_controlled_character()
	var local_peer:int = _local_control_peer_id()
	if local_target != null and not result.has(local_peer):
		result[local_peer] = str(local_target.get_path())
	return result


func _ensure_control_ring_for_peer(world:World,peer_id:int,target:Node2D) -> Node2D:
	var existing:Node2D = _control_rings_by_peer.get(peer_id) as Node2D
	if existing == null or not is_instance_valid(existing):
		if world == null or target == null or not is_instance_valid(target):
			return null
		existing = MULTIPLAYER_CONTROL_RING_SCRIPT.new() as Node2D
		if existing == null:
			return null
		existing.name = "PlayerControlRing_%d" % peer_id
		world.add_child(existing)
		_control_rings_by_peer[peer_id] = existing
		if peer_id == _local_control_peer_id():
			_controlled_ring = existing

	_place_control_ring_behind_target(existing,target,world)
	return existing


func _place_control_ring_behind_target(ring:Node2D,target:Node2D,world:World) -> void:
	if ring == null or target == null or not is_instance_valid(ring) or not is_instance_valid(target):
		return

	# V278 使用 z_as_relative=false / z_index=-1，但 World 自身就是 z=-2：
	# 人物通常继承 World 得到最终 z=-2，旧圈反而是最终 z=-1，必然压在人物上面。
	# V279 不再靠“猜一个更小 Z”解决，否则又可能掉到 TileMap 后面。
	# 圈与人物使用同一个父节点、同一 z 设置，并把圈的树顺序放到人物正前面：
	# 同 Z 时地图（更早） -> 控制圈 -> 人物整棵子树，人物图片即可真正遮住圈。
	var desired_parent:Node = target.get_parent()
	if desired_parent == null:
		desired_parent = world
	if ring.get_parent() != desired_parent:
		ring.reparent(desired_parent,true)

	ring.z_as_relative = target.z_as_relative
	ring.z_index = target.z_index

	if ring.get_parent() == target.get_parent() and ring.get_parent() != null:
		var parent_node:Node = ring.get_parent()
		var target_index:int = target.get_index()
		var ring_index:int = ring.get_index()
		if ring_index < target_index:
			target_index -= 1
		parent_node.move_child(ring,maxi(target_index,0))


func _control_ring_data_for_target(target:Node) -> Dictionary:
	if target is ball and target.has_method("get_character_ground_shadow_ring_data"):
		var shadow_data:Variant = target.call("get_character_ground_shadow_ring_data",3.0)
		if shadow_data is Dictionary and not (shadow_data as Dictionary).is_empty():
			return shadow_data

	if target is ball:
		var controlled_ball:ball = target as ball
		var collision:CollisionShape2D = controlled_ball.collision_shape_2d
		if collision != null and is_instance_valid(collision) and collision.shape != null:
			var local_bounds:Rect2 = collision.shape.get_rect().abs()
			var shape_scale:Vector2 = collision.global_scale.abs()
			var world_width:float = local_bounds.size.x * maxf(shape_scale.x,0.0001)
			var world_height:float = local_bounds.size.y * maxf(shape_scale.y,0.0001)
			return {
				"center": collision.global_position,
				"radii": Vector2(
					maxf(world_width*0.5 + 3.0,8.0),
					maxf(world_height*0.5 + 3.0,8.0)
				),
			}
	return {}


func _update_control_ring(world:World) -> void:
	var assignments:Dictionary = _current_control_assignments_for_display()
	var active_peers:Dictionary = {}
	for peer_key:Variant in assignments.keys():
		var peer_id:int = int(peer_key)
		var target_path:NodePath = NodePath(str(assignments[peer_key]))
		var target:Node = get_node_or_null(target_path)
		if target == null or not is_instance_valid(target) or not (target is Node2D):
			continue
		var data:Dictionary = _control_ring_data_for_target(target)
		if data.is_empty():
			continue
		var target_2d:Node2D = target as Node2D
		var ring:Node2D = _ensure_control_ring_for_peer(world,peer_id,target_2d)
		if ring == null:
			continue
		ring.global_position = Vector2(data.get("center",target_2d.global_position))
		if ring.has_method("configure"):
			var radii:Vector2 = data.get("radii",Vector2(18.0,10.0))
			ring.call("configure",radii,peer_id == _local_control_peer_id())
		active_peers[peer_id] = true

	for peer_key:Variant in _control_rings_by_peer.keys().duplicate():
		var peer_id:int = int(peer_key)
		if active_peers.has(peer_id):
			continue
		var stale:Node = _control_rings_by_peer.get(peer_id) as Node
		if stale != null and is_instance_valid(stale):
			stale.queue_free()
		_control_rings_by_peer.erase(peer_id)
	if not _control_rings_by_peer.has(_local_control_peer_id()):
		_controlled_ring = null


func _broadcast_control_assignments() -> void:
	if not multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		return
	_sync_control_assignments.rpc(_controlled_peer_paths.duplicate(true))


@rpc("authority","call_remote","reliable")
func _sync_control_assignments(assignments:Dictionary) -> void:
	_remote_control_assignments.clear()
	for peer_key:Variant in assignments.keys():
		var peer_id:int = int(peer_key)
		var path_string:String = str(assignments[peer_key])
		if peer_id > 0 and not path_string.is_empty():
			_remote_control_assignments[peer_id] = path_string


func _release_control_for_peer(peer_id:int) -> void:
	# V380：解除控制必须先清掉服务器保存的长按状态，防止角色换人/玩家掉线后继续自动出招。
	_remote_control_action_hold_masks.erase(peer_id)
	_remote_control_action_repeat_ready_msec.erase(peer_id)
	if not _controlled_peer_paths.has(peer_id):
		return
	var path:NodePath = NodePath(str(_controlled_peer_paths[peer_id]))
	var node:Node = get_node_or_null(path)
	if node != null and node.has_method("set_player_control_peer"):
		node.call("set_player_control_peer",0)
	_controlled_peer_paths.erase(peer_id)
	_controlled_path_peers.erase(str(path))
	_broadcast_control_assignments()

func _grant_control_server(peer_id:int,target:Node) -> bool:
	if not multiplayer.is_server() or target == null or not is_instance_valid(target) or not target.is_in_group("Ball"):
		return false
	var path_string:String = str(target.get_path())
	if _controlled_path_peers.has(path_string) and int(_controlled_path_peers[path_string]) != peer_id:
		return false
	_release_control_for_peer(peer_id)
	_controlled_peer_paths[peer_id] = path_string
	_controlled_path_peers[path_string] = peer_id
	if target.has_method("set_player_control_peer"):
		target.call("set_player_control_peer",peer_id)
	_broadcast_control_assignments()
	return true

func _set_local_control_target(target:Node) -> void:
	var next_target:Node = target if target != null and is_instance_valid(target) else null
	if controlled_character_local != next_target:
		_clear_local_control_action_holds(true)
	controlled_character_local = next_target
	_last_control_move_sent = Vector2(999,999)
	if controlled_character_local == null:
		_clear_control_ring()

func _toggle_character_control(world:World) -> void:
	if is_controlling_character():
		var old_target:Node = get_local_controlled_character()
		if network_role == "client":
			_request_release_control.rpc_id(Server_Id)
		elif multiplayer.is_server():
			_release_control_for_peer(multiplayer.get_unique_id())
		elif old_target != null and old_target.has_method("set_player_control_peer"):
			old_target.call("set_player_control_peer",0)
		_set_local_control_target(null)
		return
	var target:Node = _find_control_candidate(world)
	if target == null:
		return
	if network_role == "client":
		_request_control_character.rpc_id(Server_Id,target.get_path())
	else:
		var peer_id:int = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
		if not multiplayer.has_multiplayer_peer() or _grant_control_server(peer_id,target):
			if target.has_method("set_player_control_peer"):
				target.call("set_player_control_peer",peer_id)
			_set_local_control_target(target)

@rpc("any_peer","call_remote","reliable")
func _request_control_character(target_path:NodePath) -> void:
	if not multiplayer.is_server():
		return
	var sender_id:int = multiplayer.get_remote_sender_id()
	var target:Node = get_node_or_null(target_path)
	if sender_id <= 0:
		return
	if target == null or not (target is ball) or (target as ball).Type != ball.Ball_Type.Ball:
		_control_character_result.rpc_id(sender_id,NodePath())
		return
	if _grant_control_server(sender_id,target):
		_control_character_result.rpc_id(sender_id,target.get_path())
	else:
		_control_character_result.rpc_id(sender_id,NodePath())

@rpc("any_peer","call_remote","reliable")
func _request_release_control() -> void:
	if multiplayer.is_server():
		_release_control_for_peer(multiplayer.get_remote_sender_id())

@rpc("authority","call_remote","reliable")
func _control_character_result(target_path:NodePath) -> void:
	var target:Node = get_node_or_null(target_path) if not str(target_path).is_empty() else null
	_set_local_control_target(target)

@rpc("any_peer","call_remote","unreliable_ordered",1)
func _controlled_move_request(target_path:NodePath,input_direction:Vector2,aim_position:Vector2) -> void:
	if not multiplayer.is_server():
		return
	var sender_id:int = multiplayer.get_remote_sender_id()
	if not _controlled_peer_paths.has(sender_id) or str(_controlled_peer_paths[sender_id]) != str(target_path):
		return
	var target:Node = get_node_or_null(target_path)
	if target != null and target.has_method("set_player_control_direction"):
		target.call("set_player_control_direction",input_direction.limit_length(1.0))
	if target != null and target.has_method("set_player_control_aim_position"):
		target.call("set_player_control_aim_position",aim_position)

@rpc("any_peer","call_remote","reliable")
func _controlled_action_request(target_path:NodePath,action_index:int,aim_position:Vector2) -> void:
	if not multiplayer.is_server():
		return
	var sender_id:int = multiplayer.get_remote_sender_id()
	if not _controlled_peer_paths.has(sender_id) or str(_controlled_peer_paths[sender_id]) != str(target_path):
		return
	var target:Node = get_node_or_null(target_path)
	if target != null and target.has_method("set_player_control_aim_position"):
		target.call("set_player_control_aim_position",aim_position)
	if target != null and target.has_method("player_control_action"):
		target.call("player_control_action",clampi(action_index,0,2))

# V380：远端玩家只在“按下/松开”时发送一次状态变化；服务器保存 hold mask。
# pressed=true 同包携带当前瞄准点并立即触发第一下，随后由服务器物理循环继续尝试，
# pressed=false 可靠清除。这样连发手感不依赖客户端系统按键 echo，也不会产生高频 reliable RPC。
@rpc("any_peer","call_remote","reliable")
func _controlled_action_hold_request(target_path:NodePath,action_index:int,pressed:bool,aim_position:Vector2) -> void:
	if not multiplayer.is_server():
		return
	var sender_id:int = multiplayer.get_remote_sender_id()
	if sender_id <= 0 or not _controlled_peer_paths.has(sender_id):
		return
	if str(_controlled_peer_paths[sender_id]) != str(target_path):
		return
	var target:Node = get_node_or_null(target_path)
	if target == null or not is_instance_valid(target):
		_remote_control_action_hold_masks.erase(sender_id)
		_remote_control_action_repeat_ready_msec.erase(sender_id)
		return
	var index:int = clampi(action_index,0,2)
	var bit:int = 1 << index
	var mask:int = int(_remote_control_action_hold_masks.get(sender_id,0))
	var repeat_ready:Dictionary = _remote_control_action_repeat_ready_msec.get(sender_id,{})
	if target.has_method("set_player_control_aim_position"):
		target.call("set_player_control_aim_position",aim_position)
	if pressed:
		# 同一物理按住只接受一次 press；重复网络包不能重复制造“第一下”。
		if (mask & bit) != 0:
			return
		mask |= bit
		repeat_ready[index] = Time.get_ticks_msec() + CONTROL_ACTION_HOLD_INITIAL_REPEAT_DELAY_MSEC
		_remote_control_action_hold_masks[sender_id] = mask
		_remote_control_action_repeat_ready_msec[sender_id] = repeat_ready
		if target.has_method("player_control_action"):
			target.call("player_control_action",index)
	else:
		mask = mask & ~bit
		repeat_ready.erase(index)
		if mask == 0:
			_remote_control_action_hold_masks.erase(sender_id)
			_remote_control_action_repeat_ready_msec.erase(sender_id)
		else:
			_remote_control_action_hold_masks[sender_id] = mask
			_remote_control_action_repeat_ready_msec[sender_id] = repeat_ready

func _control_action_repeat_allowed(target:Node,action_index:int) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.has_method("player_control_action_hold_repeat_allowed"):
		return bool(target.call("player_control_action_hold_repeat_allowed",action_index))
	return true

func _set_local_control_action_hold(action_index:int,pressed:bool) -> void:
	var index:int = clampi(action_index,0,2)
	var bit:int = 1 << index
	var already_held:bool = (_local_control_action_hold_mask & bit) != 0
	if pressed == already_held:
		return
	var target:Node = get_local_controlled_character()
	if pressed and target == null:
		return
	var aim_position:Vector2 = _current_control_aim_position()
	if pressed:
		_local_control_action_hold_mask |= bit
		_local_control_action_repeat_ready_msec[index] = Time.get_ticks_msec() + CONTROL_ACTION_HOLD_INITIAL_REPEAT_DELAY_MSEC
		if network_role == "client":
			_controlled_action_hold_request.rpc_id(Server_Id,target.get_path(),index,true,aim_position)
		else:
			# 单机/主机第一下仍在按下瞬间触发，不等下一 physics tick。
			_send_control_action(index)
	else:
		_local_control_action_hold_mask = _local_control_action_hold_mask & ~bit
		_local_control_action_repeat_ready_msec[index] = 0
		if network_role == "client" and target != null:
			_controlled_action_hold_request.rpc_id(Server_Id,target.get_path(),index,false,aim_position)

func _clear_local_control_action_holds(notify_server:bool = true) -> void:
	if _local_control_action_hold_mask == 0:
		return
	var target:Node = get_local_controlled_character()
	if notify_server and network_role == "client" and target != null:
		var aim_position:Vector2 = _current_control_aim_position()
		for index:int in range(3):
			if (_local_control_action_hold_mask & (1 << index)) != 0:
				_controlled_action_hold_request.rpc_id(Server_Id,target.get_path(),index,false,aim_position)
	_local_control_action_hold_mask = 0
	for index:int in range(3):
		_local_control_action_repeat_ready_msec[index] = 0

func _process_local_control_action_holds() -> void:
	if network_role == "client" or _local_control_action_hold_mask == 0:
		return
	var target:Node = get_local_controlled_character()
	if target == null:
		_clear_local_control_action_holds(false)
		return
	var now_msec:int = Time.get_ticks_msec()
	for index:int in range(3):
		var bit:int = 1 << index
		if (_local_control_action_hold_mask & bit) == 0:
			continue
		if now_msec < int(_local_control_action_repeat_ready_msec[index]):
			continue
		if not _control_action_repeat_allowed(target,index):
			continue
		if target.has_method("player_control_action"):
			target.call("player_control_action",index)

func _process_remote_control_action_holds() -> void:
	if not multiplayer.is_server() or _remote_control_action_hold_masks.is_empty():
		return
	var now_msec:int = Time.get_ticks_msec()
	for peer_key:Variant in _remote_control_action_hold_masks.keys().duplicate():
		var peer_id:int = int(peer_key)
		if not _controlled_peer_paths.has(peer_id):
			_remote_control_action_hold_masks.erase(peer_id)
			_remote_control_action_repeat_ready_msec.erase(peer_id)
			continue
		var target:Node = get_node_or_null(NodePath(str(_controlled_peer_paths[peer_id])))
		if target == null or not is_instance_valid(target):
			_remote_control_action_hold_masks.erase(peer_id)
			_remote_control_action_repeat_ready_msec.erase(peer_id)
			continue
		var mask:int = int(_remote_control_action_hold_masks.get(peer_id,0))
		var repeat_ready:Dictionary = _remote_control_action_repeat_ready_msec.get(peer_id,{})
		for index:int in range(3):
			if (mask & (1 << index)) == 0:
				continue
			if now_msec < int(repeat_ready.get(index,0)):
				continue
			if not _control_action_repeat_allowed(target,index):
				continue
			if target.has_method("player_control_action"):
				target.call("player_control_action",index)

func _current_control_aim_position() -> Vector2:
	var world:Node = get_tree().current_scene
	if world is CanvasItem:
		return (world as CanvasItem).get_global_mouse_position()
	return mouse_poi

func _send_control_action(action_index:int) -> void:
	var target:Node = get_local_controlled_character()
	if target == null:
		return
	var aim_position:Vector2 = _current_control_aim_position()
	if network_role == "client":
		_controlled_action_request.rpc_id(Server_Id,target.get_path(),action_index,aim_position)
	else:
		if target.has_method("set_player_control_aim_position"):
			target.call("set_player_control_aim_position",aim_position)
		if target.has_method("player_control_action"):
			target.call("player_control_action",action_index)

func _current_wasd_direction() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A): dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_W): dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S): dir.y += 1.0
	return dir.normalized() if dir.length_squared() > 1.0 else dir

func _process_control_movement() -> void:
	var target:Node = get_local_controlled_character()
	if target == null:
		return
	var move_dir:Vector2 = _current_wasd_direction()
	var aim_position:Vector2 = _current_control_aim_position()
	if network_role == "client":
		# V130：同一个高频 unreliable_ordered 包同时同步 WASD + 鼠标世界坐标；
		# 服务器只接收“输入意图”，仍不接受客户端直接上报角色位置。
		_controlled_move_request.rpc_id(Server_Id,target.get_path(),move_dir,aim_position)
		_last_control_move_sent = move_dir
	else:
		if target.has_method("set_player_control_direction"):
			target.call("set_player_control_direction",move_dir)
		if target.has_method("set_player_control_aim_position"):
			target.call("set_player_control_aim_position",aim_position)

###
func _input(event: InputEvent) -> void:
	if event.is_echo():return
	var tree := get_tree()
	var world := tree.current_scene
	# 训练场等独立场景不是 World；全局 Game UI 不应在这些场景里处理战场输入。
	if world is not World:
		_clear_local_control_action_holds(true)
		mouse_drag = false
		world_middle_drag = false
		_cancel_placement_press()
		return

	# C：鼠标指向一名普通角色后进入/退出直接控制。输入框正在编辑时不抢 C 键。
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_C:
		var focus:Control = get_viewport().gui_get_focus_owner()
		if not (focus is LineEdit) and not (focus is TextEdit):
			_toggle_character_control(world as World)
			get_viewport().set_input_as_handled()
			return

	# 一旦左键是在地图里开始的，松开事件即使落在 UI 上也必须在这里收尾，
	# 否则 GUI 抢走 release 后会把框选状态卡住。
	if is_controlling_character():
		_cancel_placement_press()
		if ghost_ball and is_instance_valid(ghost_ball):
			ghost_ball.queue_free()
			ghost_ball = null

	if _placement_press_active:
		if event is InputEventMouseMotion:
			_placement_current_screen = event.position
			_placement_current_world = (world as World).get_global_mouse_position()
			if _placement_box_mode:
				_update_placement_box_overlay(world as World)
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.is_pressed():
			_placement_current_screen = event.position
			_placement_current_world = (world as World).get_global_mouse_position()
			_finalize_placement_press(world as World)
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("esc"):
		_cancel_placement_press()
		if now_stop_state:
			continue_game()
		else:
			stop_game()
	elif event.is_action_pressed("menu"):
		_cancel_placement_press()
		(world as World).set_menu()
	elif event is InputEventMouseButton:
		# 控制角色时，战场鼠标只服务角色能力：左=普攻、右=技能、中=扩展动作。
		# UI 上的点击继续留给 UI；中键绝不再启动地图拖动。Alt+滚轮缩放在后面仍可使用。
		if is_controlling_character():
			mouse_drag = false
			world_middle_drag = false
			if event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
				var action_index:int = 0 if event.button_index == MOUSE_BUTTON_LEFT else (1 if event.button_index == MOUSE_BUTTON_RIGHT else 2)
				if event.is_pressed():
					var hovered:Control = get_viewport().gui_get_hovered_control()
					if hovered == null:
						_set_local_control_action_hold(action_index,true)
						get_viewport().set_input_as_handled()
						return
				else:
					# 松开无论发生在战场还是 UI 上都要收尾，否则拖着鼠标经过 UI 后会留下“卡住连发”。
					if (_local_control_action_hold_mask & (1 << action_index)) != 0:
						_set_local_control_action_hold(action_index,false)
						get_viewport().set_input_as_handled()
						return

		# V82：右键删除必须在 _input() 阶段截获。Godot 的 GUI 会先于
		# _unhandled_input() 消费鼠标事件，因此只放在 _unhandled_input() 会导致
		# 轮放/计时/Boss 等界面开启后“右键完全没反应”。有真实 UI 在鼠标下时仍留给 UI。
		if event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
			if _try_world_right_click_delete(world as World):
				get_viewport().set_input_as_handled()
				return

		# V224：Alt + 滚轮缩放战场画面与顶部工具栏的显示状态彻底解耦。
		# 工具栏关闭后仍可继续调缩放；滚轮上 = 放大，滚轮下 = 缩小。
		# 高精度滚轮/触控板继续使用 factor 调整步幅。
		if (
			event.is_pressed()
			and event.alt_pressed
			and world != null
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]
		):
			var wheel_direction:int = 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
			(world as World).toolbar_zoom_at_screen_position(
				event.position,
				wheel_direction,
				event.factor
			)
			# 不让同一次 Alt+滚轮继续滚动工具栏里的 ScrollContainer/Panel。
			get_viewport().set_input_as_handled()
			return

		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if is_controlling_character():
				mouse_drag = false
				world_middle_drag = false
				return
			# V34：中键按下的“起点”决定这次拖动属于 UI 还是地图。
			# _input() 发生在 GUI 之前，因此这里绝不能直接 set_input_as_handled()，
			# 否则 Control._gui_input() 根本收不到中键，设置/角色列表等 UI 就无法拖动。
			if event.is_pressed():
				mouse_drag = true
				world_middle_drag = false
				if mouse_drag:
					# Viewport 返回当前最深层、实际声明鼠标 hover 的 Control。
					# 有 UI 在鼠标下方时，把这次中键完整留给 UI；没有 UI 才交给战场相机。
					var hovered_control:Control = get_viewport().gui_get_hovered_control()
					world_middle_drag = hovered_control == null
			else:
				mouse_drag = false
				world_middle_drag = false
			# 不消费按钮事件，让 UI 的 gui_input/accept_event 正常工作。
			return

	elif event is InputEventMouseMotion and world_middle_drag:
		# 只有“从地图空白处开始”的中键拖动才由相机接管。
		# 一旦地图已经拥有这次拖动，即使随后鼠标滑过 UI 也保持连续平移，
		# 直到中键释放；反过来，从 UI 开始的拖动永远不会误带动地图。
		(world as World).pan_toolbar_view_by_screen_delta(event.screen_relative)
		get_viewport().set_input_as_handled()
		return


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():return
	var tree := get_tree()
	var world := tree.current_scene
	# 训练场等独立场景不是 World，直接忽略正式战场的鼠标逻辑。
	if world is not World:
		mouse_drag = false
		world_middle_drag = false
		_cancel_placement_press()
		return

	# 直接控制角色期间禁用放置、删除和地图中键拖动；能力鼠标已在 _input() 处理。
	if is_controlling_character():
		_cancel_placement_press()
		mouse_drag = false
		world_middle_drag = false
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		# 不再按下瞬间直接生成人物：先进入“待确认”状态。
		# 短按在 release 时仍只放 1 个；按住约 0.3s 后切换成蓝色框选。
		if (world as World).return_can_create_char() and _position_inside_character_placement_area(world as World,(world as World).get_global_mouse_position()):
			_begin_placement_press(world as World,event.position)
			get_viewport().set_input_as_handled()
			return

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
		# _input() 是主入口；这里仅作为没有被 GUI 消费时的兼容兜底。
		if _manual_training_owns_right_click():
			return
		if _try_world_right_click_delete(world as World):
			get_viewport().set_input_as_handled()
			return

var mouse_poi:Vector2 = Vector2.ZERO
var ghost_ball

# 单击放置现在在“松开左键”时确认；按住超过阈值后切换为框选模式。
var _placement_press_active:bool = false
var _placement_box_mode:bool = false
var _placement_hold_elapsed:float = 0.0
var _placement_press_screen:Vector2 = Vector2.ZERO
var _placement_current_screen:Vector2 = Vector2.ZERO
var _placement_press_world:Vector2 = Vector2.ZERO
var _placement_current_world:Vector2 = Vector2.ZERO
var _placement_team:String = ""
var _placement_character:String = ""
var _placement_overlay:Control = null


func _position_inside_current_map(world:World,position:Vector2) -> bool:
	if world == null or not is_instance_valid(world):
		return false
	var border:Dictionary = world.return_now_map_border()
	var start:Vector2 = border.get("start",Vector2.ZERO)
	var end:Vector2 = border.get("end",Vector2.ZERO)
	return position.x > start.x and position.x < end.x and position.y > start.y and position.y < end.y


func _position_inside_character_placement_area(world:World,position:Vector2) -> bool:
	if world == null or not is_instance_valid(world):
		return false
	# World 提供一个专门的“地图外自动回拉测试带”。它与 mouse_in_map 分离，
	# 因此手动攻击、地图内判定等系统仍只认黑线内部。
	if world.has_method("can_place_character_at"):
		return bool(world.call("can_place_character_at",position))
	return _position_inside_current_map(world,position)


func _begin_placement_press(world:World,screen_position:Vector2) -> void:
	_cancel_placement_press()
	if world == null or not is_instance_valid(world):
		return
	var character_name:String = (
		"random"
		if world.now_choose_char == "" and bool(Game_Settings.get("Set_Random_Char_When_Didnt_Choose",true))
		else world.now_choose_char
	)
	if character_name.is_empty():
		return
	_placement_press_active = true
	_placement_box_mode = false
	_placement_hold_elapsed = 0.0
	_placement_press_screen = screen_position
	_placement_current_screen = screen_position
	_placement_press_world = world.get_global_mouse_position()
	_placement_current_world = _placement_press_world
	_placement_team = world.now_choose_team
	_placement_character = character_name


func _ensure_placement_box_overlay(world:World) -> void:
	if is_instance_valid(_placement_overlay):
		return
	if world == null or not is_instance_valid(world):
		return
	var canvas_layer:Node = world.get_node_or_null("CanvasLayer")
	if canvas_layer == null:
		return
	var overlay_variant:Variant = PLACEMENT_BOX_OVERLAY_SCRIPT.new()
	if overlay_variant is not Control:
		return
	_placement_overlay = overlay_variant as Control
	_placement_overlay.name = "CharacterPlacementSelection"
	canvas_layer.add_child(_placement_overlay)


func _update_placement_box_overlay(world:World) -> void:
	if not _placement_press_active or not _placement_box_mode:
		return
	_ensure_placement_box_overlay(world)
	if is_instance_valid(_placement_overlay) and _placement_overlay.has_method("set_selection_points"):
		_placement_overlay.call("set_selection_points",_placement_press_screen,_placement_current_screen)


func _cancel_placement_press() -> void:
	_placement_press_active = false
	_placement_box_mode = false
	_placement_hold_elapsed = 0.0
	_placement_team = ""
	_placement_character = ""
	if is_instance_valid(_placement_overlay) and _placement_overlay.has_method("clear_selection"):
		_placement_overlay.call("clear_selection")


func _spawn_placed_character(world:World,team_name:String,character_name:String,position:Vector2) -> void:
	if world == null or not is_instance_valid(world) or character_name.is_empty():
		return
	if not is_multiplayer_authority():
		create_ball_in_server.rpc_id(Server_Id,team_name,character_name,position)
	else:
		create_ball_in_server(team_name,character_name,position)


func _box_placement_points(world:World,from_world:Vector2,to_world:Vector2) -> Array[Vector2]:
	var points:Array[Vector2] = []
	if world == null or not is_instance_valid(world):
		return points

	# 框选放置也允许进入地图外测试带，但不会无限扩到整个屏幕。
	# 优先使用 World 给出的扩展 bounds；老版本 World 则退回黑线内部。
	var placement_bounds:Rect2 = Rect2()
	if world.has_method("return_character_placement_test_bounds"):
		var bounds_variant:Variant = world.call("return_character_placement_test_bounds")
		if bounds_variant is Rect2:
			placement_bounds = bounds_variant
	if placement_bounds.size.x <= 0.0 or placement_bounds.size.y <= 0.0:
		var border:Dictionary = world.return_now_map_border()
		var fallback_start:Vector2 = border.get("start",Vector2.ZERO)
		var fallback_end:Vector2 = border.get("end",Vector2.ZERO)
		placement_bounds = Rect2(fallback_start,fallback_end - fallback_start)
	var map_start:Vector2 = placement_bounds.position
	var map_end:Vector2 = placement_bounds.end
	var min_x:float = clampf(minf(from_world.x,to_world.x),map_start.x,map_end.x)
	var max_x:float = clampf(maxf(from_world.x,to_world.x),map_start.x,map_end.x)
	var min_y:float = clampf(minf(from_world.y,to_world.y),map_start.y,map_end.y)
	var max_y:float = clampf(maxf(from_world.y,to_world.y),map_start.y,map_end.y)
	if max_x < min_x:
		var swap_x:float = min_x
		min_x = max_x
		max_x = swap_x
	if max_y < min_y:
		var swap_y:float = min_y
		min_y = max_y
		max_y = swap_y

	var span_x:float = max_x - min_x
	var span_y:float = max_y - min_y
	var count_x:int = 1
	var count_y:int = 1
	if span_x >= PLACEMENT_BOX_MIN_MULTI_SPAN:
		count_x = maxi(2,roundi(span_x / PLACEMENT_BOX_GRID_SPACING) + 1)
	if span_y >= PLACEMENT_BOX_MIN_MULTI_SPAN:
		count_y = maxi(2,roundi(span_y / PLACEMENT_BOX_GRID_SPACING) + 1)

	# 极大的框仍然保持规则网格，但限制一次性实例化数量，避免误拖把主线程卡死。
	while count_x * count_y > PLACEMENT_BOX_MAX_CHARACTERS:
		if count_x >= count_y and count_x > 1:
			count_x -= 1
		elif count_y > 1:
			count_y -= 1
		else:
			break

	for row:int in range(count_y):
		var y:float = (min_y + max_y) * 0.5 if count_y == 1 else lerpf(min_y,max_y,float(row) / float(count_y - 1))
		for column:int in range(count_x):
			var x:float = (min_x + max_x) * 0.5 if count_x == 1 else lerpf(min_x,max_x,float(column) / float(count_x - 1))
			var point := Vector2(x,y)
			# grow() 的四个角可能超过真实救援半径，最终再按 World 的
			# can_place_character_at() 过滤，确保每个地图外点都能自动拉回。
			if _position_inside_character_placement_area(world,point):
				points.append(point)
	return points


func _finalize_placement_press(world:World) -> void:
	if not _placement_press_active:
		return
	var was_box_mode:bool = _placement_box_mode
	var team_name:String = _placement_team
	var character_name:String = _placement_character
	var start_world:Vector2 = _placement_press_world
	var end_world:Vector2 = _placement_current_world
	_cancel_placement_press()

	if world == null or not is_instance_valid(world) or not world.return_can_create_char():
		return
	if was_box_mode:
		for point:Vector2 in _box_placement_points(world,start_world,end_world):
			_spawn_placed_character(world,team_name,character_name,point)
	elif _position_inside_character_placement_area(world,end_world):
		_spawn_placed_character(world,team_name,character_name,end_world)


func _process(delta: float) -> void:
	_process_network_ping(delta)
	_process_room_discovery(delta)

	# V277：中文兜底翻译不能只在 World 战斗场景运行。
	# 主菜单、联机面板、训练场等非 World 场景也可能在运行时创建英文 Control。
	_runtime_localization_sweep_left -= maxf(delta,0.0)
	if _runtime_localization_sweep_left <= 0.0:
		_runtime_localization_sweep_left = RUNTIME_LOCALIZATION_SWEEP_INTERVAL
		_refresh_runtime_localized_texts()

	var current_scene:Node = get_tree().current_scene
	# Game 是全局节点，但训练场根节点不是 World。原来的强类型赋值会在训练场直接报错。
	if current_scene is not World:
		_cancel_placement_press()
		if ghost_ball and is_instance_valid(ghost_ball):
			ghost_ball.queue_free()
			ghost_ball = null
		return
	var world:World = current_scene as World
	_update_control_ring(world)
	world.process_always(delta)
	_update_wild_dog_time_visual(delta,world)

	# 用 World 的 CanvasItem 坐标获取真实战场鼠标位置，和角色生成坐标保持一致。
	mouse_poi = world.get_global_mouse_position()
	var map_border:Dictionary = world.return_now_map_border()
	mouse_in_map = (mouse_poi.x > map_border.start.x and
	mouse_poi.x < map_border.end.x and
	mouse_poi.y > map_border.start.y and
	mouse_poi.y < map_border.end.y
	)

	if _placement_press_active:
		_placement_current_screen = get_viewport().get_mouse_position()
		_placement_current_world = mouse_poi
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or not world.return_can_create_char():
			_cancel_placement_press()
		else:
			_placement_hold_elapsed += maxf(delta,0.0)
			if not _placement_box_mode and _placement_hold_elapsed >= PLACEMENT_BOX_HOLD_TIME:
				_placement_box_mode = true
			if _placement_box_mode:
				_update_placement_box_overlay(world)

	# 框选期间不再显示单个人物 Ghost，避免它和蓝色矩形互相遮挡。
	if _placement_box_mode:
		if ghost_ball and is_instance_valid(ghost_ball):
			ghost_ball.queue_free()
			ghost_ball = null
	elif not is_controlling_character() and _position_inside_character_placement_area(world,mouse_poi) and world.now_choose_char != "" and world.return_can_create_char():
		if ghost_ball and is_instance_valid(ghost_ball) and ghost_ball.name == world.now_choose_char:
			ghost_ball.global_position = mouse_poi
		else:
			if ghost_ball and is_instance_valid(ghost_ball):
				ghost_ball.queue_free()
			ghost_ball = world.create_ghost_ball()
	elif ghost_ball and is_instance_valid(ghost_ball):
		ghost_ball.queue_free()
		ghost_ball = null

func _physics_process(_delta:float) -> void:
	# WASD 以物理频率发送；客户端用 unreliable_ordered 连续刷新输入意图。
	_process_control_movement()
	# V380：长按动作由 authority 本地重试。客户端只发 hold 状态变化，主机/服务器不接收高频动作 RPC。
	_process_local_control_action_holds()
	_process_remote_control_action_holds()

func init_game() -> void:
	vignette.show()
	# V80：正常游戏阶段也固定保留清晰的全屏暗角，不再等暂停时才明显。
	vignette_tween(vignette_start)
	stop_text.hide()
	stop_background.hide()
	speed_text.hide()
	speed_slider.hide()
func stop_game(play_sfx:bool = true) -> void:
	now_stop_state = true
	
	var tree = get_tree()
	# V415：必须在 SceneTree 真正暂停前保存所有游戏播放器当前的 stream_paused 状态。
	# UI 总线不进入这条暂停链，因此暂停菜单的按钮/滑条声音仍可正常播放。
	if Audios != null and Audios.has_method("set_gameplay_paused"):
		Audios.set_gameplay_paused(true)
	tree.paused = true
	
	if play_sfx:Audios.play_sfx("StopGame",{pitch=0.8,position=1.1})
	
	if Stop_Override_Tween:Stop_Override_Tween.kill()
	if Vignette_Tween:Vignette_Tween.kill()
	
	if not Game_Settings.Creating:
		Vignette_Tween = create_tween()
		Vignette_Tween.set_pause_mode(Tween.TWEEN_PAUSE_BOUND)
		Vignette_Tween.set_ease(Tween.EASE_OUT)
		Vignette_Tween.set_trans(Tween.TRANS_EXPO)
		Vignette_Tween.tween_method(vignette_tween,vignette_start,vignette_stop,2)
	
		stop_text.add_theme_font_size_override("font_size",300)
		stop_text.text = ui_t("UI_STOP")
		stop_text.show()
		
		stop_background.show()
		
		speed_text.add_theme_font_size_override("font_size",64)
	else:
		speed_text.add_theme_font_size_override("font_size",56)
	
	speed_slider.show()
	speed_text.show()
	speed_slider.grab_focus()
func continue_game() -> void:
	now_stop_state = false
	
	var tree = get_tree()
	
	if Stop_Override_Tween:Stop_Override_Tween.kill()

	speed_text.hide()
	speed_slider.hide()
	
	if Vignette_Tween:Vignette_Tween.kill()
	Vignette_Tween = create_tween()
	Vignette_Tween.set_pause_mode(Tween.TWEEN_PAUSE_BOUND)
	Vignette_Tween.set_ease(Tween.EASE_OUT)
	Vignette_Tween.set_trans(Tween.TRANS_QUAD)
	Vignette_Tween.tween_method(vignette_tween,vignette_start if Game_Settings.Creating else vignette_stop,vignette_start,1)
	
	if not Game_Settings.Creating:
		var i := 3
		while i>0:
			Audios.play_sfx("StopTextClick",{pitch = (1.6 - float(i) / 5.0),volume = (1.6 - float(i) / 5.0)})
		
			stop_text.text = str(i)
			stop_text.add_theme_font_size_override("font_size",400)
		
			Stop_Override_Tween = create_tween()
			Stop_Override_Tween.set_pause_mode(Tween.TWEEN_PAUSE_BOUND)
			Stop_Override_Tween.set_ease(Tween.EASE_OUT)
			Stop_Override_Tween.set_trans(Tween.TRANS_EXPO)
			Stop_Override_Tween.tween_property(stop_text,"theme_override_font_sizes/font_size",200,0.3)
		
			i-=1
			await  Stop_Override_Tween.finished
		
	stop_background.hide()
	stop_text.hide()

	tree.paused = false
	# 倒计时结束、SceneTree 恢复后再恢复游戏声音；这样游戏声不会在 3/2/1 UI 倒计时期间提前继续。
	if Audios != null and Audios.has_method("set_gameplay_paused"):
		Audios.set_gameplay_paused(false)
	
#
func should_connect(sig:Signal,callback:Callable) -> void:
	if sig.is_connected(callback):
		return
	else:
		sig.connect(callback)
#动画
	#Ui
func Set_Ui_sfx(node:Node) -> void:
	var button = node as BaseButton
	if button:
		should_connect(button.button_down,Audios.play_sfx.bind("ButtonDown1",{},true))
		should_connect(button.button_up,Audios.play_sfx.bind("ButtonUpMouseOut",{},true))
		should_connect(button.mouse_exited,Audios.play_sfx.bind("ButtonUpMouseOut",{},true))
		should_connect(button.mouse_entered,Audios.play_sfx.bind("MouseEnterButton1",{},true))
	
	for c in node.get_children():
		Set_Ui_sfx(c)
		
func drag(event:InputEvent,panel:Panel,box:VBoxContainer) -> void:
	if event is InputEventMouseMotion and mouse_drag:
		box.position.y = clampf(box.position.y + event.relative.y,-(2.5 + clampf(box.size.y - panel.size.y,0,INF)),2.5)
func Set_Ui_drager(node:Node) -> void:
	var panel = node as Panel
	if panel:
		var box = panel.get_node_or_null("VBoxContainer")
		if box:
			should_connect(panel.gui_input,drag.bind(panel,box))
			
	for c in node.get_children():
		Set_Ui_drager(c)
	#暗角
func vignette_tween(amount:float) -> void:
	vignette.set_instance_shader_parameter("SCALE",amount)


# ========================================================
# 可叠加的世界流速覆写
#
# 速度滑条仍然保存“玩家设置的基础流速”。角色技能只提供一个 0~1 的
# 临时倍率；多个来源同时存在时取最慢的那个。这样极速者退出后不会把
# 玩家原本设置的 0.8x / 1.5x 等速度错误恢复成 1.0x。
# ========================================================
var _base_game_time_scale:float = 1.0
var _time_scale_overrides:Dictionary = {}
var _time_scale_override_tints:Dictionary = {}
var _world_slow_tint_layer:CanvasLayer = null
var _world_slow_tint_rect:ColorRect = null
var _world_slow_tint_tween:Tween = null

# 野生狗奶的“时间加速”使用独立的世界背景昼夜视觉：
# 只改变 World/Background 的 self_modulate，并在背景上方、人物下方绘制太阳/月亮。
# 不使用全屏 CanvasModulate/ColorRect，避免把人物、伤害字和 UI 一起染黑。
var _wild_dog_time_visual_sources:Dictionary = {}
var _wild_dog_time_visual_phase:float = 0.0
var _wild_dog_time_visual_rate:float = 0.0
var _wild_dog_time_visual_root:Node2D = null
var _wild_dog_time_visual_sun:Node2D = null
var _wild_dog_time_visual_moon:Node2D = null
var _wild_dog_time_visual_background:Sprite2D = null
var _wild_dog_time_visual_background_base_modulate:Color = Color.WHITE
var _wild_dog_time_visual_world_id:int = 0
var _wild_dog_time_music_player:AudioStreamPlayer = null
# V270：跨“加速结束 -> 冷却 -> 下一轮加速”保存音乐进度。
# 只保存全局单播放器的位置，因此多只狗奶不会各自维护一套进度。
var _wild_dog_time_music_resume_position:float = 0.0


func _ensure_wild_dog_time_music_player() -> AudioStreamPlayer:
	if _wild_dog_time_music_player != null and is_instance_valid(_wild_dog_time_music_player):
		return _wild_dog_time_music_player
	var player := AudioStreamPlayer.new()
	player.name = "WildDogMilkTimeMusic"
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.max_polyphony = 1
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	else:
		player.bus = &"Master"
	var playback_stream:AudioStream = WILD_DOG_TIME_MUSIC.duplicate(true) as AudioStream
	if playback_stream is AudioStreamMP3:
		(playback_stream as AudioStreamMP3).loop = true
	player.stream = playback_stream
	add_child(player)
	_wild_dog_time_music_player = player
	return player


func _start_wild_dog_time_music() -> void:
	var player:AudioStreamPlayer = _ensure_wild_dog_time_music_player()
	if player == null or player.playing:
		return

	var resume_position:float = maxf(_wild_dog_time_music_resume_position,0.0)
	if player.stream != null:
		var stream_length:float = player.stream.get_length()
		if stream_length > 0.001:
			resume_position = fmod(resume_position,stream_length)
	player.play(resume_position)


func _stop_wild_dog_time_music() -> void:
	if _wild_dog_time_music_player == null or not is_instance_valid(_wild_dog_time_music_player):
		return
	if _wild_dog_time_music_player.playing:
		_wild_dog_time_music_resume_position = maxf(
			_wild_dog_time_music_player.get_playback_position(),
			0.0
		)
	_wild_dog_time_music_player.stop()


func request_wild_dog_time_visual(
	source_key:String,
	factor:float,
	factor_start:float,
	factor_end:float,
	cycle_rate_start:float,
	cycle_rate_end:float
) -> void:
	if source_key.is_empty():
		return
	_wild_dog_time_visual_sources[source_key] = {
		"factor": clampf(factor,0.05,1.0),
		"factor_start": clampf(factor_start,0.05,1.0),
		"factor_end": clampf(factor_end,0.05,1.0),
		"cycle_rate_start": maxf(cycle_rate_start,0.05),
		"cycle_rate_end": maxf(cycle_rate_end,cycle_rate_start),
	}
	_start_wild_dog_time_music()


func release_wild_dog_time_visual(source_key:String) -> void:
	if source_key.is_empty():
		return
	_wild_dog_time_visual_sources.erase(source_key)
	if _wild_dog_time_visual_sources.is_empty():
		_stop_wild_dog_time_music()
		_clear_wild_dog_time_visual_nodes()


func _wild_dog_time_circle_polygon(radius:float,segments:int = 40) -> PackedVector2Array:
	var points := PackedVector2Array()
	var safe_segments:int = maxi(segments,8)
	for i:int in range(safe_segments):
		points.append(Vector2.from_angle(TAU * float(i) / float(safe_segments)) * radius)
	return points


func _create_wild_dog_time_sun() -> Node2D:
	var sun := Node2D.new()
	sun.name = "Sun"

	var body := Polygon2D.new()
	body.name = "Body"
	body.polygon = _wild_dog_time_circle_polygon(28.0,40)
	body.color = Color(1.0,0.82,0.20,1.0)
	sun.add_child(body)

	var core := Polygon2D.new()
	core.name = "Core"
	core.polygon = _wild_dog_time_circle_polygon(19.0,36)
	core.color = Color(1.0,0.95,0.55,1.0)
	sun.add_child(core)

	for i:int in range(8):
		var angle:float = TAU * float(i) / 8.0
		var ray := Line2D.new()
		ray.width = 4.0
		ray.default_color = Color(1.0,0.72,0.12,0.95)
		ray.antialiased = true
		ray.points = PackedVector2Array([
			Vector2.from_angle(angle) * 35.0,
			Vector2.from_angle(angle) * 48.0,
		])
		sun.add_child(ray)
	return sun


func _create_wild_dog_time_moon() -> Node2D:
	var moon := Node2D.new()
	moon.name = "Moon"

	var body := Polygon2D.new()
	body.name = "Body"
	body.polygon = _wild_dog_time_circle_polygon(27.0,40)
	body.color = Color(0.82,0.90,1.0,1.0)
	moon.add_child(body)

	# 用一个偏移的深色圆盖出月牙，不需要新增图片资源。
	var cutout := Polygon2D.new()
	cutout.name = "CrescentCutout"
	cutout.polygon = _wild_dog_time_circle_polygon(23.0,40)
	cutout.position = Vector2(10.0,-5.0)
	cutout.color = Color(0.035,0.055,0.11,1.0)
	moon.add_child(cutout)
	return moon


func _clear_wild_dog_time_visual_nodes() -> void:
	if _wild_dog_time_visual_background != null and is_instance_valid(_wild_dog_time_visual_background):
		_wild_dog_time_visual_background.self_modulate = _wild_dog_time_visual_background_base_modulate
	if _wild_dog_time_visual_root != null and is_instance_valid(_wild_dog_time_visual_root):
		_wild_dog_time_visual_root.queue_free()
	_wild_dog_time_visual_root = null
	_wild_dog_time_visual_sun = null
	_wild_dog_time_visual_moon = null
	_wild_dog_time_visual_background = null
	_wild_dog_time_visual_background_base_modulate = Color.WHITE
	_wild_dog_time_visual_world_id = 0
	_wild_dog_time_visual_phase = 0.0
	_wild_dog_time_visual_rate = 0.0


func _ensure_wild_dog_time_visual_nodes(world:World) -> void:
	if world == null or not is_instance_valid(world):
		return
	var world_id:int = world.get_instance_id()
	if _wild_dog_time_visual_root != null and is_instance_valid(_wild_dog_time_visual_root) and _wild_dog_time_visual_world_id == world_id:
		return

	_clear_wild_dog_time_visual_nodes()
	var background:Sprite2D = world.get_node_or_null("Background") as Sprite2D
	if background == null:
		return

	_wild_dog_time_visual_world_id = world_id
	_wild_dog_time_visual_background = background
	_wild_dog_time_visual_background_base_modulate = background.self_modulate

	_wild_dog_time_visual_root = Node2D.new()
	_wild_dog_time_visual_root.name = "WildDogMilkTimeSky"
	# World 自身 z=-2；Background 子节点 z=-3。这里 z=-2，最终位于背景之上、普通人物之下。
	_wild_dog_time_visual_root.z_index = -2
	_wild_dog_time_visual_root.process_mode = Node.PROCESS_MODE_ALWAYS
	world.add_child(_wild_dog_time_visual_root)

	_wild_dog_time_visual_sun = _create_wild_dog_time_sun()
	_wild_dog_time_visual_moon = _create_wild_dog_time_moon()
	_wild_dog_time_visual_root.add_child(_wild_dog_time_visual_sun)
	_wild_dog_time_visual_root.add_child(_wild_dog_time_visual_moon)


func _update_wild_dog_time_visual(delta:float,world:World) -> void:
	if _wild_dog_time_visual_sources.is_empty():
		if _wild_dog_time_visual_root != null or _wild_dog_time_visual_background != null:
			_clear_wild_dog_time_visual_nodes()
		return

	_ensure_wild_dog_time_visual_nodes(world)
	if (_wild_dog_time_visual_root == null or not is_instance_valid(_wild_dog_time_visual_root)
		or _wild_dog_time_visual_background == null or not is_instance_valid(_wild_dog_time_visual_background)):
		return

	# 多只狗奶同时加速时，选择“时间推进最深”的来源驱动共同天空；来源结束后自动切到剩余来源。
	var best_progress:float = -1.0
	var best_rate_start:float = 0.45
	var best_rate_end:float = 4.25
	for raw_key:Variant in _wild_dog_time_visual_sources.keys():
		var raw_data:Variant = _wild_dog_time_visual_sources[raw_key]
		if not raw_data is Dictionary:
			continue
		var data:Dictionary = raw_data as Dictionary
		var factor:float = clampf(float(data.get("factor",1.0)),0.05,1.0)
		var factor_start:float = clampf(float(data.get("factor_start",0.78)),0.05,1.0)
		var factor_end:float = clampf(float(data.get("factor_end",0.24)),0.05,1.0)
		var span:float = maxf(absf(factor_start - factor_end),0.001)
		var progress:float = (factor_start - factor) / span if factor_start >= factor_end else (factor - factor_start) / span
		progress = clampf(progress,0.0,1.0)
		if progress > best_progress:
			best_progress = progress
			best_rate_start = maxf(float(data.get("cycle_rate_start",0.45)),0.05)
			best_rate_end = maxf(float(data.get("cycle_rate_end",4.25)),best_rate_start)

	if best_progress < 0.0:
		return

	var target_rate:float = lerpf(best_rate_start,best_rate_end,pow(best_progress,1.20))
	# delta 已乘 Engine.time_scale；除掉当前临时时间覆写，让天空循环不被狗奶自己的减速拖慢。
	# 玩家主动设置的基础速度仍然保留，因此 2x/0.5x 游戏速度下视觉仍与整场战斗同步。
	var visual_delta:float = maxf(delta,0.0) / maxf(get_time_scale_override_factor(),0.05)
	if _wild_dog_time_visual_rate <= 0.0:
		_wild_dog_time_visual_rate = target_rate
	else:
		var response:float = 1.0 - exp(-visual_delta * 5.0)
		_wild_dog_time_visual_rate = lerpf(_wild_dog_time_visual_rate,target_rate,clampf(response,0.0,1.0))
	_wild_dog_time_visual_phase = fmod(
		_wild_dog_time_visual_phase + visual_delta * _wild_dog_time_visual_rate * TAU,
		TAU
	)

	# phase=0 为原本蓝色；半圈达到纯黑；一整圈回到原本蓝色。循环频率会随加速阶段越来越快。
	var darkness:float = 0.5 - 0.5 * cos(_wild_dog_time_visual_phase)
	var base_color:Color = _wild_dog_time_visual_background_base_modulate
	var black_color := Color(0.0,0.0,0.0,base_color.a)
	_wild_dog_time_visual_background.self_modulate = base_color.lerp(black_color,darkness)

	# 日月必须始终在“真实地图矩形”外侧，而不是围绕镜头中心在地图内部转。
	# 位置按当前地图世界 Rect2 计算；相机只负责反向缩放日月本体，让视觉尺寸不因工具栏缩放而忽大忽小。
	var camera:Camera2D = world.camera_2d
	if camera == null or not is_instance_valid(camera):
		camera = world.get_viewport().get_camera_2d()
	var inverse_zoom_x:float = 1.0
	var inverse_zoom_y:float = 1.0
	if camera != null and is_instance_valid(camera):
		inverse_zoom_x = 1.0 / maxf(absf(camera.zoom.x),0.001)
		inverse_zoom_y = 1.0 / maxf(absf(camera.zoom.y),0.001)

	var map_rect := Rect2()
	if world.map_group.has(world.now_choose_map):
		var map_node:Variant = world.map_group[world.now_choose_map]
		if map_node is TileMapLayer:
			map_rect = world.return_map_world_rect(map_node as TileMapLayer)

	# 没有有效地图时宁可暂时隐藏日月，也不回退到镜头中心，避免再次出现在地图内部。
	if map_rect.size.x <= 0.0 or map_rect.size.y <= 0.0:
		if _wild_dog_time_visual_sun != null and is_instance_valid(_wild_dog_time_visual_sun):
			_wild_dog_time_visual_sun.visible = false
		if _wild_dog_time_visual_moon != null and is_instance_valid(_wild_dog_time_visual_moon):
			_wild_dog_time_visual_moon.visible = false
		return

	var map_center:Vector2 = map_rect.get_center()
	var half_size:Vector2 = map_rect.size * 0.5
	var sun_angle:float = _wild_dog_time_visual_phase - PI * 0.5
	var orbit_direction:Vector2 = Vector2.from_angle(sun_angle)

	# 从地图中心沿当前角度求射线与地图外框的交点距离，再额外推出“日月半径 + 缓冲距离”。
	# 这样无论角度怎么转，太阳和月亮的整个图形都不会进入地图矩形。
	var border_distance_x:float = INF if absf(orbit_direction.x) < 0.0001 else half_size.x / absf(orbit_direction.x)
	var border_distance_y:float = INF if absf(orbit_direction.y) < 0.0001 else half_size.y / absf(orbit_direction.y)
	var border_distance:float = minf(border_distance_x,border_distance_y)
	var visual_world_radius:float = 52.0 * maxf(inverse_zoom_x,inverse_zoom_y)
	var outside_gap:float = 14.0 * maxf(inverse_zoom_x,inverse_zoom_y)
	var orbit_distance:float = border_distance + visual_world_radius + outside_gap

	_wild_dog_time_visual_root.global_position = map_center
	_wild_dog_time_visual_root.global_rotation = 0.0
	_wild_dog_time_visual_root.scale = Vector2.ONE

	if _wild_dog_time_visual_sun != null and is_instance_valid(_wild_dog_time_visual_sun):
		_wild_dog_time_visual_sun.visible = true
		_wild_dog_time_visual_sun.position = orbit_direction * orbit_distance
		_wild_dog_time_visual_sun.scale = Vector2(inverse_zoom_x,inverse_zoom_y)
		_wild_dog_time_visual_sun.rotation = _wild_dog_time_visual_phase * 0.45
		_wild_dog_time_visual_sun.modulate.a = lerpf(1.0,0.28,darkness)
	if _wild_dog_time_visual_moon != null and is_instance_valid(_wild_dog_time_visual_moon):
		_wild_dog_time_visual_moon.visible = true
		_wild_dog_time_visual_moon.position = -orbit_direction * orbit_distance
		_wild_dog_time_visual_moon.scale = Vector2(inverse_zoom_x,inverse_zoom_y)
		_wild_dog_time_visual_moon.rotation = -_wild_dog_time_visual_phase * 0.18
		_wild_dog_time_visual_moon.modulate.a = lerpf(0.32,1.0,darkness)


func request_time_scale_override(source_key:String,factor:float,tint:Color = Color(0.20,0.55,1.0,0.14)) -> void:
	if source_key.is_empty():
		return
	_time_scale_overrides[source_key] = clampf(factor,0.05,1.0)
	_time_scale_override_tints[source_key] = tint
	_apply_time_scale_overrides()


func release_time_scale_override(source_key:String) -> void:
	if source_key.is_empty():
		return
	_time_scale_overrides.erase(source_key)
	_time_scale_override_tints.erase(source_key)
	_apply_time_scale_overrides()


func get_time_scale_override_factor() -> float:
	var result:float = 1.0
	for raw_factor in _time_scale_overrides.values():
		result = minf(result,clampf(float(raw_factor),0.05,1.0))
	return result


func get_base_game_time_scale() -> float:
	return _base_game_time_scale


func _apply_time_scale_overrides() -> void:
	var factor:float = get_time_scale_override_factor()
	var effective_scale:float = _base_game_time_scale * factor
	Engine.time_scale = effective_scale
	# V415：Engine.time_scale 不会自动改变音频播放速度。把同一有效倍率立即交给 Audios，
	# 游戏声会按该倍率播放；UI 声音由 Audios 做反向补偿，始终维持正常 1x。
	if Audios != null and Audios.has_method("set_game_time_scale"):
		Audios.set_game_time_scale(effective_scale)

	# Godot 文档指出：单独把 time_scale 拉高会降低物理精度。
	# 训练模式同步提高 physics_ticks_per_second，使高速投射物/极速闪避在高倍速下仍有足够采样。
	# 32x 时最多 1920 physics ticks/s；普通游戏仍维持 60Hz，避免无谓 CPU 开销。
	if is_training_mode():
		var target_ticks:int = int(round(60.0 * maxf(effective_scale, 1.0)))
		Engine.physics_ticks_per_second = clampi(target_ticks, 60, TRAINING_MAX_PHYSICS_TICKS)
		# 高 physics tick 时，Godot 还受“每个渲染帧最多模拟多少物理步”限制。
		# 32x 理论上需要约 32 个 physics step / render frame；留少量余量并封顶 64。
		Engine.max_physics_steps_per_frame = clampi(
			maxi(_normal_max_physics_steps_per_frame, int(ceil(maxf(effective_scale, 1.0))) + 2),
			_normal_max_physics_steps_per_frame,
			64
		)
	else:
		Engine.physics_ticks_per_second = 60
		Engine.max_physics_steps_per_frame = _normal_max_physics_steps_per_frame

	_update_world_slow_tint(factor)


func _ensure_world_slow_tint() -> void:
	if _world_slow_tint_rect != null and is_instance_valid(_world_slow_tint_rect):
		return

	_world_slow_tint_layer = CanvasLayer.new()
	_world_slow_tint_layer.name = "WorldSlowTintLayer"
	_world_slow_tint_layer.layer = 110
	_world_slow_tint_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_world_slow_tint_layer)

	_world_slow_tint_rect = ColorRect.new()
	_world_slow_tint_rect.name = "WorldSlowTint"
	_world_slow_tint_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world_slow_tint_rect.color = Color(0.0,0.0,0.0,0.0)
	_world_slow_tint_layer.add_child(_world_slow_tint_rect)
	_world_slow_tint_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _strongest_time_scale_tint(factor:float) -> Color:
	if _time_scale_overrides.is_empty():
		return Color(0.0,0.0,0.0,0.0)

	var best_key:String = ""
	var best_factor:float = 2.0
	for raw_key in _time_scale_overrides.keys():
		var key:String = str(raw_key)
		var candidate:float = clampf(float(_time_scale_overrides[raw_key]),0.05,1.0)
		if candidate < best_factor:
			best_factor = candidate
			best_key = key

	if best_key.is_empty() or not _time_scale_override_tints.has(best_key):
		return Color(0.20,0.55,1.0,0.14)

	var result:Color = _time_scale_override_tints[best_key]
	# 越慢颜色越明显，但始终尊重角色给出的 alpha 上限。
	var strength:float = clampf((1.0 - factor) / 0.75,0.0,1.0)
	result.a *= strength
	return result


func _update_world_slow_tint(factor:float) -> void:
	_ensure_world_slow_tint()
	if _world_slow_tint_rect == null or not is_instance_valid(_world_slow_tint_rect):
		return

	if _world_slow_tint_tween != null and _world_slow_tint_tween.is_valid():
		_world_slow_tint_tween.kill()

	var target:Color = _strongest_time_scale_tint(factor)
	_world_slow_tint_tween = create_tween()
	_world_slow_tint_tween.set_ignore_time_scale(true)
	_world_slow_tint_tween.set_trans(Tween.TRANS_QUAD)
	_world_slow_tint_tween.set_ease(Tween.EASE_OUT)
	_world_slow_tint_tween.tween_property(
		_world_slow_tint_rect,
		"color",
		target,
		0.10 if factor < 1.0 else 0.16
	)


#速度
func set_speed(value:float,sfx:bool = true) -> void:
	if sfx:Audios.play_sfx("Slider1")
	
	var timescale:float = value - 9.0 if value >= 11.0 else value / 10.0
	_base_game_time_scale = maxf(timescale,0.0)
	_apply_time_scale_overrides()
	speed_text.text = Game.ui_t("UI_SPEED") + ":" + str(_base_game_time_scale) + "x"


#全局
func return_random_name(node:Node) -> String:
	return node.name + "_" + str(node.get_instance_id()) + "_" + str(Time.get_ticks_usec()) 

@rpc("any_peer")
func free_node(node) -> void:
	if not is_multiplayer_authority():return
	
	node.queue_free()
