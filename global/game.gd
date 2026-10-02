extends Control
const BATTLE_CONDITIONS_CATALOG = preload("res://scripts/training/battle_conditions_catalog.gd")
const BATTLE_MUSIC_MODULE = preload("res://global/battle_music.gd")
const FEEDBACK_SETTINGS = preload("res://global/feedback_settings.gd")

#设定
# V126：多人端口固定为 27018。UI 中的输入框是“服务器地址/IP”，不是端口输入框。
const port := 27018
const max_player := 10

#========================================================
# 持久化设置 / 语言
#========================================================
signal language_changed(locale:String)
signal game_setting_changed(setting:String, value:Variant)
# 一场战斗的随机会话结束：重置、重打、轮放系列重开（仅房主/离线端触发）。
signal battle_session_ended()
# V126：统一给多人 UI 的连接状态/玩家列表/双向 RPC 自检使用。
signal network_state_changed()
# V127：局域网 / EasyTier / 蒲公英等虚拟局域网房间发现列表变化。
@warning_ignore("unused_signal")
signal room_list_changed()
# 训练奖励只关心“真正结算掉的生命”，而不是 Hitbox 理论伤害。
# source 是实际归属角色（投射物会归因给 Master），target 是受击人物。
signal training_damage_resolved(source:Node, target:Node, actual_health_damage:float)
# 月计角色等通用战斗系统使用：普通对局也广播真实生命伤害与实际死亡。
signal combat_damage_resolved(source:Node, target:Node, actual_health_damage:float, target_health_before:float)
signal combatant_died(victim:Node, killer:Node, health_before_lethal:float)

const SETTINGS_PATH := "user://settings.cfg"
var _settings_storage_path:String = SETTINGS_PATH


#########################################################################
# Game 门面（Facade）
# game.gd 曾是 3900 行的“上帝对象”。现在内聚的子系统各自拆成 RefCounted 模块
# 放在 res://global/game_*.gd，由下面的 *_MODULE 常量实例化并持有。
# 规则：
#   1) 外部代码继续只调用 Game.xxx；下面的函数/属性都是 1 行转发壳。
#   2) 所有 @rpc 函数保留在 game.gd 上，RPC 路径与联机协议不变。
#   3) 模块通过 _game 访问仍留在 Game 上的成员（Game_Settings、信号、RPC、场景树）。
#   4) 新增子系统时：先写 game_<name>.gd，再在这里加模块常量与需要的转发壳。
#########################################################################

#========================================================
# 持久化语言 / 翻译表 / 运行时 UI 兜底翻译 —— 已拆分到 res://global/game_localization.gd
# 下面的成员只是转发壳，保持 Game.xxx 对外接口与 RPC 路径不变。
#========================================================
const LOCALIZATION_MODULE := preload("res://global/game_localization.gd")
var _localization = LOCALIZATION_MODULE.new(self)

var current_locale:String:
	get: return _localization.current_locale
	set(value): _localization.current_locale = value

func _load_compiled_translation_catalog() -> bool:
	return _localization._load_compiled_translation_catalog()

func load_runtime_translations() -> bool:
	return _localization.load_runtime_translations()

func has_translation_key(key:String) -> bool:
	return _localization.has_translation_key(key)

func resolve_translation_key(source:String) -> String:
	return _localization.resolve_translation_key(source)

func is_only_in_game_translation_enabled() -> bool:
	return _localization.is_only_in_game_translation_enabled()

func get_ui_locale() -> String:
	return _localization.get_ui_locale()

func _apply_translation_server_locale() -> void:
	_localization._apply_translation_server_locale()

func translate_ui_text(source:String) -> String:
	return _localization.translate_ui_text(source)

func translate_game_text(source:String) -> String:
	return _localization.translate_game_text(source)

func t(key:String) -> String:
	return _localization.t(key)

func ui_t(key:String) -> String:
	return _localization.ui_t(key)

func _contains_cjk(text:String) -> bool:
	return _localization._contains_cjk(text)

func set_language(locale:String, save_after:bool = true) -> void:
	_localization.set_language(locale, save_after)

func _localize_runtime_control_tree(root:Node,translation_cache:Dictionary = {}) -> void:
	_localization._localize_runtime_control_tree(root, translation_cache)

func _refresh_runtime_localized_texts() -> void:
	_localization._refresh_runtime_localized_texts()

const RUNTIME_LOCALIZATION_GROUP = LOCALIZATION_MODULE.RUNTIME_LOCALIZATION_GROUP

func _ensure_runtime_localization_index() -> void:
	_localization._ensure_runtime_localization_index()

func toggle_language() -> void:
	_localization.toggle_language()

func get_language_display_name() -> String:
	return _localization.get_language_display_name()


#========================================================
# 左键放置 / 长按框选批量放置人物与 Ghost 预览 —— 已拆分到 res://global/game_character_placement.gd
# 下面的成员只是转发壳，保持 Game.xxx 对外接口与 RPC 路径不变。
#========================================================
const PLACEMENT_MODULE := preload("res://global/game_character_placement.gd")
var _placement = PLACEMENT_MODULE.new(self)


#========================================================
# 通用击杀血液视觉与大奖红闪（非 RPC 部分） —— 已拆分到 res://global/game_kill_blood.gd
# 下面的成员只是转发壳，保持 Game.xxx 对外接口与 RPC 路径不变。
#========================================================
const KILL_BLOOD_MODULE := preload("res://global/game_kill_blood.gd")
var _kill_blood = KILL_BLOOD_MODULE.new(self)

func play_blood_jackpot_flash_local() -> void:
	_kill_blood.play_blood_jackpot_flash_local()

func is_global_blood_effects_enabled() -> bool:
	return _kill_blood.is_global_blood_effects_enabled()


#========================================================
# 野生狗奶“老死”残骸结算（非 RPC 部分） —— 已拆分到 res://global/game_wild_dog_old_age.gd
# 下面的成员只是转发壳，保持 Game.xxx 对外接口与 RPC 路径不变。
#========================================================
const WILD_DOG_OLD_AGE_MODULE := preload("res://global/game_wild_dog_old_age.gd")
var _wild_dog_old_age = WILD_DOG_OLD_AGE_MODULE.new(self)


#========================================================
# 野生狗奶“时间流逝”日月视觉与配乐（角色专属全局效果） —— 已拆分到 res://global/game_wild_dog_time_visual.gd
# 下面的成员只是转发壳，保持 Game.xxx 对外接口与 RPC 路径不变。
#========================================================
const WILD_DOG_TIME_MODULE := preload("res://global/game_wild_dog_time_visual.gd")
var _wild_dog_time = WILD_DOG_TIME_MODULE.new(self)

func request_wild_dog_time_visual(source_key:String, factor:float, factor_start:float, factor_end:float, cycle_rate_start:float, cycle_rate_end:float) -> void:
	_wild_dog_time.request_wild_dog_time_visual(source_key, factor, factor_start, factor_end, cycle_rate_start, cycle_rate_end)

func release_wild_dog_time_visual(source_key:String) -> void:
	_wild_dog_time.release_wild_dog_time_visual(source_key)


#========================================================
# V127 局域网 / 虚拟局域网房间发现（UDP 27019） —— 已拆分到 res://global/game_room_discovery.gd
# 下面的成员只是转发壳，保持 Game.xxx 对外接口与 RPC 路径不变。
#========================================================
const ROOM_DISCOVERY_MODULE := preload("res://global/game_room_discovery.gd")
var _room_discovery = ROOM_DISCOVERY_MODULE.new(self)

var discovered_rooms:Dictionary:
	get: return _room_discovery.discovered_rooms
	set(value): _room_discovery.discovered_rooms = value

func request_room_scan(force:bool = false) -> void:
	_room_discovery.request_room_scan(force)

func get_discovered_rooms() -> Array[Dictionary]:
	return _room_discovery.get_discovered_rooms()


#========================================================
# 训练模式设置查询 / 手动训练攻击目录 —— 已拆分到 res://global/game_training_mode.gd
# 下面的成员只是转发壳，保持 Game.xxx 对外接口与 RPC 路径不变。
#========================================================
const TRAINING_MODULE := preload("res://global/game_training_mode.gd")
var _training = TRAINING_MODULE.new(self)

const MANUAL_ATTACK_INTERVAL_MIN = TRAINING_MODULE.MANUAL_ATTACK_INTERVAL_MIN

const MANUAL_ATTACK_INTERVAL_MAX = TRAINING_MODULE.MANUAL_ATTACK_INTERVAL_MAX

const MANUAL_ATTACK_INTERVAL_STEP = TRAINING_MODULE.MANUAL_ATTACK_INTERVAL_STEP

func is_training_mode() -> bool:
	return _training.is_training_mode()

func set_training_mode(enabled:bool, apply_existing_characters:bool = true) -> void:
	_training.set_training_mode(enabled, apply_existing_characters)

func get_training_mode_type() -> String:
	return _training.get_training_mode_type()

func get_rotation_match_type() -> String:
	if is_rotation_wheel_enabled(): return "wheel"
	return "challenge" if str(Game_Settings.get("Rotation_Match_Type","duel"))=="challenge" else "duel"

func is_rotation_wheel_enabled() -> bool:
	return bool(Game_Settings.get("Training_Wheel_Battle",false)) or str(Game_Settings.get("Rotation_Match_Type","duel"))=="wheel"

func rotation_multi_enabled() -> bool:
	return bool(Game_Settings.get("Rotation_Multi_Characters",false))

func rotation_team_count(side:String) -> int:
	return clampi(int(Game_Settings.get("Rotation_Blue_Count" if side=="left" else "Rotation_Red_Count",1)),1,100)


func is_rotation_training_mode() -> bool:
	return _training.is_rotation_training_mode()

func is_timed_training_mode() -> bool:
	return _training.is_timed_training_mode()

func is_boss_training_mode() -> bool:
	return _training.is_boss_training_mode()

func get_training_timed_duration() -> float:
	return _training.get_training_timed_duration()

func get_training_boss_side() -> String:
	return _training.get_training_boss_side()

func get_training_boss_multiplier() -> float:
	return _training.get_training_boss_multiplier()

func is_training_boss_specialization_enabled() -> bool:
	return _training.is_training_boss_specialization_enabled()

func is_training_boss_wheel_battle_enabled() -> bool:
	return _training.is_training_boss_wheel_battle_enabled()

func is_training_boss_intro_enabled() -> bool:
	return _training.is_training_boss_intro_enabled()

func set_manual_training_attack_interval(value:float, save_after:bool = false) -> void:
	_training.set_manual_training_attack_interval(value, save_after)

func get_manual_training_attack_interval() -> float:
	return _training.get_manual_training_attack_interval()

func set_manual_training_attack(attack_id:String) -> void:
	_training.set_manual_training_attack(attack_id)

func get_manual_training_attack() -> String:
	return _training.get_manual_training_attack()

func get_manual_attack_catalog(force_refresh:bool = false) -> Array[Dictionary]:
	return _training.get_manual_attack_catalog(force_refresh)

var _normal_max_physics_steps_per_frame:int = 8


#========================================================
# 可叠加的世界流速覆写与慢动作着色 —— 已拆分到 res://global/game_time_scale.gd
# 下面的成员只是转发壳，保持 Game.xxx 对外接口与 RPC 路径不变。
#========================================================
const TIME_SCALE_MODULE := preload("res://global/game_time_scale.gd")
var _time_scale = TIME_SCALE_MODULE.new(self)

func request_time_scale_override(source_key:String,factor:float,tint:Color = Color(0.20,0.55,1.0,0.14),affect_audio:bool = true) -> void:
	_time_scale.request_time_scale_override(source_key, factor, tint, affect_audio)

func release_time_scale_override(source_key:String) -> void:
	_time_scale.release_time_scale_override(source_key)

func get_time_scale_override_factor() -> float:
	return _time_scale.get_time_scale_override_factor()

func get_base_game_time_scale() -> float:
	return _time_scale.get_base_game_time_scale()

# 发育期倍率独立于玩家速度滑条；合并时设为 0 冻结游戏时间，结束后恢复 1。
func set_development_time_multiplier(multiplier:float) -> void:
	_time_scale.set_development_time_multiplier(multiplier)

func _apply_time_scale_overrides() -> void:
	_time_scale._apply_time_scale_overrides()


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


#========================================================
# V128 多人权限 / C 键直接控制角色
#========================================================
# 本机只保存“我正在控制谁”；服务器保存 peer -> NodePath，所有玩法输入仍由服务器 authority 执行。
const MULTIPLAYER_CONTROL_RING_SCRIPT = preload("res://scripts/ui/multiplayer_control_ring.gd")

var controlled_character_local:Node = null
var _control_rings_by_peer:Dictionary = {}
var _remote_control_assignments:Dictionary = {}
var _local_control_release_requested:bool = false
var _controlled_ring:Node2D = null # 旧字段仅兼容旧调用；V277 起不再是唯一控制圈。
var _controlled_peer_paths:Dictionary = {}
var _controlled_path_peers:Dictionary = {}
var _last_control_move_sent:Vector2 = Vector2(999,999)
# 直接控制动作键支持“按住 = 连续点击”。本机记录三个鼠标键和十个数字键的保持状态；
# 客户端仅在按下/松开时可靠通知服务器，持续连发由 authority 在物理帧本地重试，
# 避免把 60Hz 长按变成 60 个 reliable RPC/秒。
const CONTROL_ACTION_COUNT:int = 13 # 左/右/中、1～9、0
# 首击立即执行；留出正常单击窗口后才开始长按重试。本地与服务端共用。
const CONTROL_ACTION_HOLD_INITIAL_REPEAT_DELAY_MSEC:int = 400
var _local_control_action_hold_mask:int = 0
var _local_control_action_repeat_ready_msec:Array[int] = [0,0,0,0,0,0,0,0,0,0,0,0,0]
var _remote_control_action_hold_masks:Dictionary = {}
var _remote_control_action_repeat_ready_msec:Dictionary = {}

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
	if get_local_controlled_character() != null:
		return true
	# 形态节点未复制过来时仍可按 C 取消控制，不会误当成重新选择。
	return network_role == "client" and multiplayer.has_multiplayer_peer() and not _local_control_release_requested and not str(_remote_control_assignments.get(_local_control_peer_id(),"")).is_empty()

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
	return not FEEDBACK_SETTINGS.SPECS.has(setting) and setting not in ["Only_In_Game_Translation","Show_Center_Watermark","Follow_Controlled_Character","Map_Background","Minecraft_Clouds","Day_Night_Cycle","Show_Armor_Stand_Intro","Battle_Music","Battle_Music_Volume","High_Damage_Feedback","Local_Hitstop"]

func _shared_settings_snapshot() -> Dictionary:
	var snapshot:Dictionary = {}
	for raw_key:Variant in Game_Settings.keys():
		var key:String = str(raw_key)
		if _is_network_shared_setting(key):
			snapshot[key] = Game_Settings[key]
	return snapshot

func _normalize_character_setting(setting:String,value:Variant) -> Variant:
	if setting == "Character_Placement_Mode": return "random" if str(value)=="random" else "custom"
	var result:Array[String] = []
	if value is Array or value is PackedStringArray:
		for item:Variant in value:
			if item is String and not item.is_empty() and not result.has(item): result.append(item)
	return result


func _apply_runtime_game_setting_local(setting:String,value:Variant,save_after:bool) -> void:
	if not Game_Settings.has(setting):
		return
	if FEEDBACK_SETTINGS.SPECS.has(setting):
		Game_Settings[setting] = value
		FEEDBACK_SETTINGS.normalize(Game_Settings)
		game_setting_changed.emit(setting,Game_Settings[setting])
		if save_after: save_persistent_settings()
		return
	if setting in ["Character_Placement_Mode","Random_Character_Categories","Random_Character_Excluded"]:
		value = _normalize_character_setting(setting,value)
	if BATTLE_CONDITIONS_CATALOG.SETTING_KEYS.has(setting):
		value = BATTLE_CONDITIONS_CATALOG.normalize_setting(setting,value)
	if setting == BATTLE_MUSIC_MODULE.VOLUME_KEY:
		value = BATTLE_MUSIC_MODULE.normalize_volume(value)
	if setting == "Rotation_Match_Type":
		var match_type:String = str(value)
		if match_type not in ["duel","wheel","challenge"]: match_type = "duel"
		if match_type=="wheel": Game_Settings["Training_Wheel_Battle"]=true
		Game_Settings[setting] = "duel" if match_type=="wheel" else match_type
		game_setting_changed.emit(setting,match_type)
	elif setting == "Training_Wheel_Battle":
		Game_Settings[setting] = bool(value)
		if str(Game_Settings["Rotation_Match_Type"])=="wheel": Game_Settings["Rotation_Match_Type"]="duel"
		game_setting_changed.emit(setting,bool(value))
	elif setting in ["Rotation_Blue_Count","Rotation_Red_Count"]:
		Game_Settings[setting]=clampi(int(value),1,100)
		game_setting_changed.emit(setting,Game_Settings[setting])
	elif setting == "Training_Mode":
		_training.set_training_mode(bool(value))
	elif setting == "Training_Mode_Type":
		var mode:String = str(value)
		if mode not in ["manual","rotation","timed","boss"]:
			mode = "manual"
		Game_Settings[setting] = mode
		game_setting_changed.emit(setting,mode)
	elif setting == "Development_Duration":
		Game_Settings[setting] = clampf(float(value),1.0,86400.0)
		game_setting_changed.emit(setting,Game_Settings[setting])
	elif setting == "Development_Speed":
		Game_Settings[setting] = clampf(float(value),1.0,32.0)
		game_setting_changed.emit(setting,Game_Settings[setting])
	else:
		Game_Settings[setting] = value
		game_setting_changed.emit(setting,value)
		if setting == "Only_In_Game_Translation":
			_localization._apply_translation_server_locale()
			_localization._refresh_localized_game_ui()
			language_changed.emit(_localization.current_locale)
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
	if setting == "Show_Center_Watermark":
		Game_Settings.erase(setting)
		return
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
	_localization._apply_translation_server_locale()
	_localization._refresh_localized_game_ui()
	language_changed.emit(_localization.current_locale)
	network_state_changed.emit()

var _saved_speed_slider_value:Variant = null

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
	# A recorded seed is already normalized. Normalizing it again increments it
	# and changes every deterministic stream on an allegedly exact rematch.
	_battle_random_seed = seed_value if seed_value>=1 and seed_value<=2147483646 else _normalize_battle_seed(seed_value)
	_battle_random_active = true
	_battle_random_counters.clear()
	seed(_battle_random_seed)
	return _battle_random_seed


func end_battle_random() -> void:
	_battle_random_active = false
	_battle_random_counters.clear()
	battle_session_ended.emit()


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


func load_persistent_settings(path:String = "") -> void:
	if path.is_empty(): path = _settings_storage_path
	FEEDBACK_SETTINGS.normalize(Game_Settings)
	var config := ConfigFile.new()
	var err := config.load(path)

	if err == OK:
		for setting in Game_Settings.keys():
			if str(setting) in ["Training_Mode", "Training_Mode_Type", "Manual_Training", "Manual_Collision_Damage", "Training_Debug_Mode"]:
				continue

			Game_Settings[setting] = config.get_value(
				"game_settings",
				str(setting),
				Game_Settings[setting]
			)

		_localization.current_locale = str(
			config.get_value(
				"ui",
				"locale",
				_localization.current_locale
			)
		)


	FEEDBACK_SETTINGS.normalize(Game_Settings)
	for key:String in ["Character_Placement_Mode","Random_Character_Categories","Random_Character_Excluded"]:
		Game_Settings[key] = _normalize_character_setting(key,Game_Settings[key])
	for key:String in BATTLE_CONDITIONS_CATALOG.SETTING_KEYS:
		Game_Settings[key] = BATTLE_CONDITIONS_CATALOG.normalize_setting(key,Game_Settings.get(key))
	# 登记表里已删除的曲目回落到“无”。
	Game_Settings["Battle_Music"] = BATTLE_MUSIC_MODULE.normalize(Game_Settings.get("Battle_Music",BATTLE_MUSIC_MODULE.NONE))
	Game_Settings[BATTLE_MUSIC_MODULE.VOLUME_KEY] = BATTLE_MUSIC_MODULE.normalize_volume(Game_Settings.get(BATTLE_MUSIC_MODULE.VOLUME_KEY,BATTLE_MUSIC_MODULE.DEFAULT_VOLUME))
	# Migrate the old winner-stays checkbox once, without overriding a saved challenge choice.
	if not config.has_section_key("game_settings","Rotation_Match_Type"):
		Game_Settings["Rotation_Match_Type"] = "wheel" if bool(Game_Settings.get("Training_Wheel_Battle",false)) else "duel"
	if str(Game_Settings["Rotation_Match_Type"])=="wheel":
		Game_Settings["Training_Wheel_Battle"]=true
		Game_Settings["Rotation_Match_Type"]="duel"
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
	_training.set_manual_training_attack_interval(float(Game_Settings.get("Manual_Attack_Interval", 0.15)), false)
	# 水印开关已删除。旧配置和旧内存值都不再恢复。
	Game_Settings.erase("Show_Center_Watermark")
	if not _localization.SUPPORTED_LOCALES.has(_localization.current_locale):
		_localization.current_locale = "zh"

	_localization._apply_translation_server_locale()


func set_simple_feedback_setting(key:String,value:Variant,save_after:bool = true) -> void:
	if not FEEDBACK_SETTINGS.SIMPLE_LABELS.has(key): return
	FEEDBACK_SETTINGS.apply_simple(Game_Settings,key,value)
	game_setting_changed.emit("Feedback_Reset",str(FEEDBACK_SETTINGS.SPECS[key].group))
	if save_after: save_persistent_settings()


func reset_feedback_settings(group:String,save_after:bool = true) -> void:
	if group not in ["Shaking_Camera","High_Damage_Feedback"]: return
	FEEDBACK_SETTINGS.reset_group(Game_Settings,group)
	game_setting_changed.emit("Feedback_Reset",group)
	if save_after: save_persistent_settings()


func save_persistent_settings(path:String = "") -> void:
	if path.is_empty(): path = _settings_storage_path
	var config := ConfigFile.new()
	# 先加载旧文件，方便以后增加其他 section 时不被覆盖。
	config.load(path)

	Game_Settings.erase("Show_Center_Watermark")
	if config.has_section_key("game_settings","Show_Center_Watermark"):
		config.erase_section_key("game_settings","Show_Center_Watermark")
	for setting in Game_Settings.keys():
		if str(setting) in ["Training_Mode", "Training_Mode_Type", "Manual_Training", "Manual_Collision_Damage", "Training_Debug_Mode"]:
			continue
		config.set_value(
			"game_settings",
			str(setting),
			Game_Settings[setting]
		)

	config.set_value("ui", "locale", _localization.current_locale)

	# 不保存速度滑条。
	# 速度仍然可以在本次运行中正常调整，只是不带到下一次启动。
	var err := config.save(path)
	if err != OK:
		push_warning("无法保存设置: " + str(err))


func _on_speed_slider_drag_ended(value_changed:bool) -> void:
	if value_changed:
		save_persistent_settings()

#var normal_mouse_image = preload("res://Images/鼠标/鼠标默认.png")
#var click_mouse_image = preload("res://Images/鼠标/鼠标点击.png")

@export var Game_Settings:Dictionary = {
	Have_Team_Damage = true,
	Shaking_Camera = true,
	# Local presentation preference; skill cinematics and time abilities are separate.
	High_Damage_Feedback = true,
	# 本机偏好：重击顿帧只冻结受击者与攻击者，不放慢整个画面。
	Local_Hitstop = false,
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
	# 仅影响本机地图外观，旧存档缺少此项时仍使用原蓝色背景。
	Map_Background = "blue",
	# Local visual preference, persisted by the existing settings path.
	Minecraft_Clouds = true,
	# 本机表现：右上角时间与昼夜变化。关闭后固定正午并隐藏时间。
	Day_Night_Cycle = true,
	# 本机战斗音乐：曲目登记在 res://global/battle_music.gd，默认“无”。
	Battle_Music = "none",
	Battle_Music_Volume = 100.0,
	# V184：全局击杀血液。关闭时若叶睦/墨提斯自身的击杀血仍保留；开启时其它人物击杀也会生成血液。
	Blood_Effects = false,
	# 角色对话总开关。开启后，支持对话的角色会把台词显示在地图下方的阵营槽位。
	Enable_Dialogue = false,
	# 本机显示偏好；旧存档默认保留盔甲架对战的人物介绍。
	Show_Armor_Stand_Intro = true,
	# 训练玩法类型：manual / rotation / timed / boss。
	Character_Placement_Mode = "custom",
	Random_Character_Categories = [],
	Random_Character_Excluded = [],
	Training_Mode_Type = "manual",
	Random_Events = false,
	Random_Event_Selection = [],
	Environment = "none",
	# 赛前分别在左右两张完整地图发育；设置时长按游戏秒计算，倍率不改玩家滑条。
	Development_Mode = false,
	Development_Duration = 60.0,
	Development_Speed = 2.0,
	# 轮放模式：false=任一方死亡后双方都换下一位；true=胜者留场，只补死亡方。
	Training_Wheel_Battle = false, # Legacy compatibility; UI uses Rotation_Match_Type.
	Rotation_Match_Type = "duel",
	Rotation_Multi_Characters = false,
	Rotation_Blue_Count = 1,
	Rotation_Red_Count = 1,
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
		_kill_blood._capture_kill_blood_context(source,target_node,actual_health_damage,target_health_before)
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
	var is_wild_dog_old_age:bool = _wild_dog_old_age._is_wild_dog_old_age_death(
		victim_node,
		effective_killer,
		health_before_lethal
	)
	if is_wild_dog_old_age:
		# 老死是真正死亡：先按受害者自己的死亡音规则播放一次，再生成骨骸；但不生成攻击死亡血。
		_wild_dog_old_age._play_wild_dog_old_age_death_audio(victim_node)
		_wild_dog_old_age._spawn_wild_dog_old_age_remains(victim_node)
	else:
		# 野生狗奶自己的低额时间伤害如果先把人打死，仍属于普通伤害击杀；开启血液时照常喷血。
		_kill_blood._spawn_global_kill_blood(victim_node,effective_killer)
	_wild_dog_old_age._clear_wild_dog_old_age_marker(victim_node)
	combatant_died.emit(victim_node, effective_killer, maxf(health_before_lethal, 0.0))


@rpc("authority","call_local","reliable")
func _rpc_spawn_wild_dog_old_age_remains(origin:Vector2,seed_value:int,size_multiplier:float = 1.0) -> void:
	if not is_inside_tree() or _wild_dog_old_age.WILD_DOG_OLD_AGE_REMAINS_SCENE == null:
		return
	var scene_root:Node = get_tree().current_scene
	if scene_root == null:
		return
	var remains_parent:Node = _wild_dog_old_age._ensure_wild_dog_old_age_remains_container(scene_root)
	if remains_parent == null:
		return
	var remains:Node = _wild_dog_old_age.WILD_DOG_OLD_AGE_REMAINS_SCENE.instantiate()
	if remains == null:
		return
	if remains.has_method("configure"):
		remains.call("configure",seed_value,maxf(size_multiplier,_wild_dog_old_age.WILD_DOG_OLD_AGE_MIN_SIZE_MULTIPLIER))
	remains_parent.add_child(remains,true)
	if remains is Node2D:
		(remains as Node2D).global_position = origin


# 训练模式统计入口保持兼容。
func report_training_damage(source:Node, target:Node, actual_health_damage:float) -> void:
	# 轮放/计时/Boss 现在可以独立于 Training_Mode 运行。
	# 计时模式仍依赖这条信号累计实际生命伤害，因此不能只检查 is_training_mode()。
	if not _training.is_training_mode() and not _training.is_timed_training_mode():
		return
	if source == null or target == null or actual_health_damage <= 0.0:
		return
	training_damage_resolved.emit(source, target, actual_health_damage)


func set_runtime_game_setting(setting:String, value:Variant, save_after:bool = true) -> void:
	if setting == "Show_Center_Watermark":
		Game_Settings.erase(setting)
		return
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


@rpc("authority","call_local","unreliable")
func _rpc_spawn_global_kill_blood(origin:Vector2,base_direction:Vector2,seed_value:int,context:Dictionary = {}) -> void:
	if not is_inside_tree():
		return
	# V39：这里只登记视觉请求，不在死亡回调当帧立刻创建整套血液节点。
	# 多杀时伤害/死亡/击杀统计仍已同步完成；只有纯视觉被摊到后续几帧。
	_kill_blood._pending_kill_blood_visuals.append({
		"origin": origin,
		"direction": base_direction,
		"seed": seed_value,
		"context": context.duplicate(),
	})
	if not _kill_blood._kill_blood_visual_drain_running:
		_kill_blood.call_deferred("_drain_kill_blood_visual_queue")


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
	FEEDBACK_SETTINGS.normalize(Game_Settings)
	_localization._bootstrap_localization_before_tree()


func _enter_tree() -> void:
	# _init 已确定本机保存语言。进入树时只重申最终 UI locale，
	# 不再无条件先写 zh，避免 English 用户和“仅局内翻译”产生一次错误首帧。
	_localization._apply_translation_server_locale()

func _ready() -> void:
	# _init 已先装入编译翻译表保证导出首帧；这里优先用原始 CSV 刷新到最新内容。
	# 导出 PCK 没有 CSV 原文件时，load_runtime_translations() 会自动继续使用编译表。
	_localization.load_runtime_translations()
	load_persistent_settings()
	var battle_music:Node = BATTLE_MUSIC_MODULE.new()
	battle_music.name = "BattleMusic"
	add_child(battle_music)
	_normal_max_physics_steps_per_frame = Engine.max_physics_steps_per_frame
	# V420 性能：项目启动即应用普通对局的物理补步上限，不必等第一次流速变化。
	_time_scale._apply_time_scale_overrides()

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
		if _training.is_training_mode()
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
	_room_discovery._setup_room_browser_socket()
	_room_discovery.request_room_scan(true)


func _exit_tree() -> void:
	# 再保存一次最终状态，覆盖键盘/手柄调节速度等没有 drag_ended 的情况。
	save_persistent_settings()
	_room_discovery._close_room_host_socket()
	if _room_discovery._room_browser_socket != null:
		_room_discovery._room_browser_socket.close()
		_room_discovery._room_browser_socket = null

#多人
const Server_Id:int = 1

#--------------------------------------------------------
# V127 房间发现
#--------------------------------------------------------


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
	_room_discovery._close_room_host_socket()
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
	_room_discovery._start_room_host_socket()
	# 立即让本机浏览器刷新；其它设备会在下一轮发现扫描中看到这个房间。
	_room_discovery.request_room_scan(true)
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
	_localization._apply_translation_server_locale()
	_localization._refresh_localized_game_ui()
	language_changed.emit(_localization.current_locale)
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
		var world:Node = get_tree().current_scene
		if world is World:
			var draft:RefCounted = world.random_character_draft
			random_character_state.rpc_id(id,"draw" if draft.playing else "slots",draft.active_results if draft.playing else draft.pending,draft._serial)
			if draft.playing and draft._authority_finished: random_character_state.rpc_id(id,"finish",[],draft._serial)
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
func create_ball_in_server(team_value:String,character_name:String,poi:Vector2,rotation_round:int=0) -> void:
	if not multiplayer.is_server(): return
	var tree := get_tree()
	var world := tree.current_scene
	if world is not World:
		return
	
	if world.random_character_draft.is_enabled():
		world.random_character_draft.place(team_value,poi,rotation_round)
		return
	world.create_char(
				team_value,
				character_name,
				poi,
				rotation_round
			)

func _find_ball_ancestor(node:Node) -> Node:
	var current:Node = node
	while current != null:
		if current.is_in_group("Ball"):
			return current
		current = current.get_parent()
	return null

func _find_deletable_ancestor(node:Node) -> Node:
	var current:Node = node
	while current != null:
		if current.is_in_group("Ball") or current.is_in_group("PlaceableObstacle"):
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

	if world_node.random_character_draft.playing: return
	if world_node.random_character_draft.remove_at(position): return

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
		var target:Node = _find_deletable_ancestor(collider_variant as Node)
		if target == null or not is_instance_valid(target):
			continue
		candidates[target.get_instance_id()] = target

	# V83：很多角色的手调碰撞箱会明显小于人物图片，轮放预览还可能完全叠在一起。
	# 物理点查询没命中时，再按实际显示 Sprite 的矩形做一次视觉点击兜底。
	# 这里只决定“鼠标指的是谁”，删除人物或地形根节点，不修改任何战斗碰撞规则。
	if candidates.is_empty():
		for group_name:String in ["Ball","PlaceableObstacle"]:
			for node:Node in get_tree().get_nodes_in_group(group_name):
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
	return _training.get_training_mode_type() == "manual" and bool(Game_Settings.get("Manual_Training",false))


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

func _can_control_candidate(node:Node) -> bool:
	# A few autonomous companions intentionally avoid the combat "Ball" group.
	if node == null or not is_instance_valid(node) or not (node is ball) or (not node.is_in_group("Ball") and not node.is_in_group("ManualControlSubentity")):
		return false
	var candidate:ball = node as ball
	if not candidate.can_player_control():
		return false
	if candidate.Type == ball.Ball_Type.Ball and candidate.has_method("is_combat_targetable") and not candidate.is_combat_targetable():
		return false
	return true

func _find_control_candidate(world:World) -> Node:
	if world == null or not is_instance_valid(world):
		return null
	var point:Vector2 = world.get_global_mouse_position()
	var chosen:Node = null
	var best_distance:float = INF
	var candidates:Array[Node] = get_tree().get_nodes_in_group("Ball")
	candidates.append_array(get_tree().get_nodes_in_group("ManualControlSubentity"))
	for node:Node in candidates:
		if not (node is ball) or not is_instance_valid(node):
			continue
		var candidate:ball = node as ball
		if not _can_control_candidate(candidate):
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
	var local_path:String = str(_remote_control_assignments.get(_local_control_peer_id(),""))
	var current:Node = get_local_controlled_character()
	if local_path.is_empty():
		_local_control_release_requested = false
		if current != null:
			_set_local_control_target(null)
	elif not _local_control_release_requested and (current == null or str(current.get_path()) != local_path):
		_resolve_assigned_local_control_target(local_path)


func _resolve_assigned_local_control_target(target_path:String) -> void:
	# 同步分配可能早于目标球在客户端出现；每帧复核映射，避免过期等待重新接管控制。
	for frame:int in range(300):
		if _local_control_release_requested or str(_remote_control_assignments.get(_local_control_peer_id(),"")) != target_path:
			return
		var target:Node = get_node_or_null(NodePath(target_path))
		if target != null and _can_control_candidate(target):
			_set_local_control_target(target)
			return
		await get_tree().process_frame
	push_warning("手控形态同步超时：" + target_path)


func transfer_character_control_for_replacement(old_target:Node,new_target:Node) -> void:
	# 只有服务器可以迁移控制；实体死亡/按 C 退出仍走原有释放流程。
	if not multiplayer.is_server() or old_target == null or not is_instance_valid(old_target):
		return
	if new_target == null or not _can_control_candidate(new_target):
		return
	var old_path:String = str(old_target.get_path())
	var peer_id:int = int(_controlled_path_peers.get(old_path,0))
	if peer_id <= 0:
		# 离线单人不使用服务器映射，仍须将本机跟随和 WASD/鼠标输入切到新形态。
		if not multiplayer.has_multiplayer_peer() and get_local_controlled_character() == old_target:
			_copy_control_input_for_replacement(old_target,new_target)
			_set_local_control_target(new_target)
			old_target.call("set_player_control_peer",0)
			new_target.call("set_player_control_peer",1)
		return
	var new_path:String = str(new_target.get_path())
	if _controlled_path_peers.has(new_path) and int(_controlled_path_peers[new_path]) != peer_id:
		_release_control_for_peer(peer_id)
		return
	# 释放旧形态的长按/蓄力和服务器复读计时，新形态必须等下一次按下才会出招。
	var held_mask:int = int(_remote_control_action_hold_masks.get(peer_id,0))
	if old_target.has_method("player_control_action_cancelled"):
		for index:int in range(CONTROL_ACTION_COUNT):
			if (held_mask & (1 << index)) != 0:
				old_target.call("player_control_action_cancelled",index)
	_remote_control_action_hold_masks.erase(peer_id)
	_remote_control_action_repeat_ready_msec.erase(peer_id)
	_copy_control_input_for_replacement(old_target,new_target)
	_controlled_path_peers.erase(old_path)
	_controlled_path_peers[new_path] = peer_id
	_controlled_peer_paths[peer_id] = new_path
	if get_local_controlled_character() == old_target:
		_set_local_control_target(new_target)
	old_target.call("set_player_control_peer",0)
	new_target.call("set_player_control_peer",peer_id)
	_broadcast_control_assignments()


func _copy_control_input_for_replacement(old_target:Node,new_target:Node) -> void:
	if not old_target is ball or not new_target is ball:
		return
	var previous:ball = old_target as ball
	var successor:ball = new_target as ball
	successor.set_player_control_direction(previous.player_control_direction)
	if previous.has_player_control_aim():
		successor.set_player_control_aim_position(previous.player_control_aim_position)


func _release_control_for_peer(peer_id:int) -> void:
	# V380：解除控制必须先清掉服务器保存的长按状态，防止角色换人/玩家掉线后继续自动出招。
	if _controlled_peer_paths.has(peer_id):
		var held_target:Node = get_node_or_null(NodePath(str(_controlled_peer_paths[peer_id])))
		var held_mask:int = int(_remote_control_action_hold_masks.get(peer_id,0))
		if held_target != null and held_target.has_method("player_control_action_cancelled"):
			for index:int in range(CONTROL_ACTION_COUNT):
				if (held_mask & (1 << index)) != 0:
					held_target.call("player_control_action_cancelled",index)
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
	if not multiplayer.is_server() or not _can_control_candidate(target):
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
			_local_control_release_requested = true
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
		_local_control_release_requested = false
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
	if not _can_control_candidate(target):
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
	if _local_control_release_requested:
		return
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
	if action_index >= 0 and action_index < CONTROL_ACTION_COUNT and target != null and target.has_method("player_control_action"):
		target.call("player_control_action",action_index)

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
	if action_index < 0 or action_index >= CONTROL_ACTION_COUNT:
		return
	var index:int = action_index
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
		if (int(_remote_control_action_hold_masks.get(sender_id,0)) & bit) != 0 and target.has_method("player_control_action_released"):
			target.call("player_control_action_released",index)
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
	if action_index < 0 or action_index >= CONTROL_ACTION_COUNT:
		return
	var index:int = action_index
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
		elif target != null and target.has_method("player_control_action_released"):
			target.call("player_control_action_released",index)

func _clear_local_control_action_holds(notify_server:bool = true) -> void:
	if _local_control_action_hold_mask == 0:
		return
	var target:Node = get_local_controlled_character()
	if notify_server and network_role == "client" and target != null:
		var aim_position:Vector2 = _current_control_aim_position()
		for index:int in range(CONTROL_ACTION_COUNT):
			if (_local_control_action_hold_mask & (1 << index)) != 0:
				_controlled_action_hold_request.rpc_id(Server_Id,target.get_path(),index,false,aim_position)
	elif target != null and target.has_method("player_control_action_cancelled"):
		for index:int in range(CONTROL_ACTION_COUNT):
			if (_local_control_action_hold_mask & (1 << index)) != 0:
				target.call("player_control_action_cancelled",index)
	_local_control_action_hold_mask = 0
	for index:int in range(CONTROL_ACTION_COUNT):
		_local_control_action_repeat_ready_msec[index] = 0

func _process_local_control_action_holds() -> void:
	if network_role == "client" or _local_control_action_hold_mask == 0:
		return
	var target:Node = get_local_controlled_character()
	if target == null:
		_clear_local_control_action_holds(false)
		return
	var now_msec:int = Time.get_ticks_msec()
	for index:int in range(CONTROL_ACTION_COUNT):
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
		for index:int in range(CONTROL_ACTION_COUNT):
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
	return _placement.mouse_poi

func _send_control_action(action_index:int) -> void:
	var target:Node = get_local_controlled_character()
	if target == null or action_index < 0 or action_index >= CONTROL_ACTION_COUNT:
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

func _control_action_index_for_keycode(keycode:int) -> int:
	if keycode >= KEY_1 and keycode <= KEY_9:
		return 3 + keycode - KEY_1
	if keycode >= KEY_KP_1 and keycode <= KEY_KP_9:
		return 3 + keycode - KEY_KP_1
	return 12 if keycode == KEY_0 or keycode == KEY_KP_0 else -1

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
		_placement._cancel_placement_press()
		return

	if world.random_character_draft.playing:
		_placement._cancel_placement_press()
		return

	# C：鼠标指向一名普通角色后进入/退出直接控制。输入框正在编辑时不抢 C 键。
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_C:
		var focus:Control = get_viewport().gui_get_focus_owner()
		if not (focus is LineEdit) and not (focus is TextEdit):
			_toggle_character_control(world as World)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and is_controlling_character():
		var action_key:InputEventKey = event as InputEventKey
		var number_action:int = _control_action_index_for_keycode(action_key.physical_keycode)
		if number_action >= 3:
			var focus:Control = get_viewport().gui_get_focus_owner()
			var hovered:Control = get_viewport().gui_get_hovered_control()
			if action_key.pressed and (focus is LineEdit or focus is TextEdit or hovered != null):
				return
			if action_key.pressed or (_local_control_action_hold_mask & (1 << number_action)) != 0:
				_set_local_control_action_hold(number_action,action_key.pressed)
				get_viewport().set_input_as_handled()
				return

	# 一旦左键是在地图里开始的，松开事件即使落在 UI 上也必须在这里收尾，
	# 否则 GUI 抢走 release 后会把框选状态卡住。
	if is_controlling_character():
		_placement._cancel_placement_press()
		if _placement.ghost_ball and is_instance_valid(_placement.ghost_ball):
			_placement.ghost_ball.queue_free()
			_placement.ghost_ball = null

	if _placement._placement_press_active:
		if event is InputEventMouseMotion:
			_placement._placement_current_screen = event.position
			_placement._placement_current_world = (world as World).get_global_mouse_position()
			if _placement._placement_box_mode:
				_placement._update_placement_box_overlay(world as World)
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.is_pressed():
			_placement._placement_current_screen = event.position
			_placement._placement_current_world = (world as World).get_global_mouse_position()
			_placement._finalize_placement_press(world as World)
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("esc"):
		_placement._cancel_placement_press()
		if now_stop_state:
			continue_game()
		else:
			stop_game()
	elif event.is_action_pressed("menu"):
		_placement._cancel_placement_press()
		(world as World).set_menu()
	elif event is InputEventMouseButton:
		# 控制角色时，战场鼠标按顺序绑定第 1/2/3 个真实主动动作。
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
		_placement._cancel_placement_press()
		return

	# 直接控制角色期间禁用放置、删除和地图中键拖动；能力鼠标已在 _input() 处理。
	if is_controlling_character():
		_placement._cancel_placement_press()
		mouse_drag = false
		world_middle_drag = false
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		# 不再按下瞬间直接生成人物：先进入“待确认”状态。
		# 短按在 release 时仍只放 1 个；按住约 0.3s 后切换成蓝色框选。
		if (world as World).return_can_create_char() and _placement._position_inside_character_placement_area(world as World,(world as World).get_global_mouse_position()):
			_placement._begin_placement_press(world as World,event.position)
			get_viewport().set_input_as_handled()
			return

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
		# _input() 是主入口；这里仅作为没有被 GUI 消费时的兼容兜底。
		if _manual_training_owns_right_click():
			return
		if _try_world_right_click_delete(world as World):
			get_viewport().set_input_as_handled()
			return


func _process(delta: float) -> void:
	_process_network_ping(delta)
	_room_discovery._process_room_discovery(delta)

	# V277：中文兜底翻译不能只在 World 战斗场景运行。
	# 主菜单、联机面板、训练场等非 World 场景也可能在运行时创建英文 Control。
	_localization._runtime_localization_sweep_left -= maxf(delta,0.0)
	if _localization._runtime_localization_sweep_left <= 0.0:
		_localization._runtime_localization_sweep_left = _localization.RUNTIME_LOCALIZATION_SWEEP_INTERVAL
		_localization._refresh_runtime_localized_texts()

	var current_scene:Node = get_tree().current_scene
	# Game 是全局节点，但训练场根节点不是 World。原来的强类型赋值会在训练场直接报错。
	if current_scene is not World:
		_placement._cancel_placement_press()
		if _placement.ghost_ball and is_instance_valid(_placement.ghost_ball):
			_placement.ghost_ball.queue_free()
			_placement.ghost_ball = null
		return
	var world:World = current_scene as World
	# 用 World 的 CanvasItem 坐标获取真实战场鼠标位置，和角色生成坐标保持一致。
	# 必须在 process_always() 之前取样：它会立即改写 Camera2D 缩放并刷新画布变换，而录像构图镜头
	# 随后又在本帧覆盖回实际显示的镜头。夹在中间取样会让放置预览偏离松手时（输入事件）的真实落点，
	# 且视野越大偏差越大。这里取到的正是玩家上一帧看到、输入事件同样使用的变换。
	_placement.mouse_poi = world.get_global_mouse_position()
	_update_control_ring(world)
	world.process_always(delta)
	_wild_dog_time._update_wild_dog_time_visual(delta,world)

	var map_border:Dictionary = world.return_now_map_border()
	mouse_in_map = (_placement.mouse_poi.x > map_border.start.x and
	_placement.mouse_poi.x < map_border.end.x and
	_placement.mouse_poi.y > map_border.start.y and
	_placement.mouse_poi.y < map_border.end.y
	)

	if _placement._placement_press_active:
		_placement._placement_current_screen = get_viewport().get_mouse_position()
		_placement._placement_current_world = _placement.mouse_poi
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or not world.return_can_create_char():
			_placement._cancel_placement_press()
		else:
			_placement._placement_hold_elapsed += maxf(delta,0.0)
			if not _placement._placement_box_mode and _placement._placement_hold_elapsed >= _placement.PLACEMENT_BOX_HOLD_TIME:
				_placement._placement_box_mode = true
			if _placement._placement_box_mode:
				_placement._update_placement_box_overlay(world)

	# 框选期间不再显示单个人物 Ghost，避免它和蓝色矩形互相遮挡。
	if _placement._placement_box_mode:
		if _placement.ghost_ball and is_instance_valid(_placement.ghost_ball):
			_placement.ghost_ball.queue_free()
			_placement.ghost_ball = null
	elif not is_controlling_character() and _placement._position_inside_character_placement_area(world,_placement.mouse_poi) and (world.now_choose_char != "" or world.random_character_draft.is_enabled()) and world.return_can_create_char():
		var cursor_name:String = "RandomCharacterCursor" if world.random_character_draft.is_enabled() else world.now_choose_char
		if _placement.ghost_ball and is_instance_valid(_placement.ghost_ball) and _placement.ghost_ball.name == cursor_name:
			_placement.ghost_ball.global_position = _placement.mouse_poi
		else:
			if _placement.ghost_ball and is_instance_valid(_placement.ghost_ball):
				_placement.ghost_ball.queue_free()
			_placement.ghost_ball = world.random_character_draft.create_cursor() if world.random_character_draft.is_enabled() else world.create_ghost_ball()
	elif _placement.ghost_ball and is_instance_valid(_placement.ghost_ball):
		_placement.ghost_ball.queue_free()
		_placement.ghost_ball = null

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
		stop_text.text = _localization.ui_t("UI_STOP")
		stop_text.show()
		
		stop_background.show()
		
		speed_text.add_theme_font_size_override("font_size",64)
	else:
		speed_text.add_theme_font_size_override("font_size",56)
	
	speed_slider.show()
	speed_text.show()
	speed_slider.grab_focus()
func continue_game() -> void:
	var world:Node = get_tree().current_scene
	if world is World and world.random_character_draft.playing: return
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


#速度
func set_speed(value:float,sfx:bool = true) -> void:
	if sfx:Audios.play_sfx("Slider1")
	
	var timescale:float = value - 9.0 if value >= 11.0 else value / 10.0
	_time_scale._base_game_time_scale = maxf(timescale,0.0)
	_time_scale._apply_time_scale_overrides()
	speed_text.text = Game.ui_t("UI_SPEED") + ":" + str(_time_scale._base_game_time_scale) + "x"


#全局
func return_random_name(node:Node) -> String:
	return node.name + "_" + str(node.get_instance_id()) + "_" + str(Time.get_ticks_usec()) 

@rpc("any_peer")
func free_node(node) -> void:
	if not is_multiplayer_authority():return
	
	node.queue_free()


@rpc("authority","call_remote","reliable")
func random_character_state(action:String,data:Array,serial:int) -> void:
	var world:Node = get_tree().current_scene
	if world is not World: return
	var draft:RefCounted = world.random_character_draft
	if serial < draft.network_serial: return
	draft.network_serial = serial
	match action:
		"slots": draft.receive_slots(data)
		"draw": draft.play(data,serial)
		"finish": draft.finish_from_authority(serial)
		"cancel":
			draft.cancel(false)
			draft._serial = serial


@rpc("any_peer","call_remote","reliable")
func request_random_character_draw() -> void:
	if not multiplayer.is_server() or not _remote_guest_admin_allowed(multiplayer.get_remote_sender_id()): return
	var world:Node = get_tree().current_scene
	if world is World: world.random_character_draft.start()
