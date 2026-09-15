extends RefCounted
## 训练模式设置查询 / 手动训练攻击目录
## 从 res://global/game.gd 拆出的内聚模块。Game 仍是唯一的 Autoload 门面：
## 外部继续调用 Game.xxx；本模块通过 _game 访问仍留在 Game 上的成员（设置、信号、RPC、场景树）。

var _game: Node


func _init(game: Node) -> void:
	_game = game


const MANUAL_ATTACK_INTERVAL_MIN:float = 0.02

const MANUAL_ATTACK_INTERVAL_MAX:float = 2.0

const MANUAL_ATTACK_INTERVAL_STEP:float = 0.01

# 手动训练攻击选择。目录扫描只做一次并缓存；UI 和训练控制器共用同一份目录。
var manual_training_attack_id:String = "res://scenes/shooter/子弹.tscn"

var _manual_attack_catalog_cache:Array[Dictionary] = []


func is_training_mode() -> bool:
	return bool(_game.Game_Settings.get("Training_Mode", false))


func set_training_mode(enabled:bool, apply_existing_characters:bool = true) -> void:
	_game.Game_Settings["Training_Mode"] = enabled
	_game.game_setting_changed.emit("Training_Mode", enabled)

	if not enabled:
		# 手动训练现在可以独立用于普通 World，因此关闭训练模式时不再强制关闭它。
		# 只有 AI 威胁调试覆盖仍严格属于训练模式。
		_game.Game_Settings["Training_Debug_Mode"] = false
		_game.game_setting_changed.emit("Training_Debug_Mode",false)

	# 训练模式下扩展 ESC 倍速上限；关闭后恢复普通游戏的 10x 上限。
	if is_instance_valid(_game.speed_slider):
		_game.speed_slider.max_value = (
			_game.TRAINING_SPEED_SLIDER_MAX_VALUE
			if enabled
			else _game.NORMAL_SPEED_SLIDER_MAX_VALUE
		)
		_game.speed_slider.tick_count = int(_game.speed_slider.max_value) + 1
		if _game.speed_slider.value > _game.speed_slider.max_value:
			_game.speed_slider.value = _game.speed_slider.max_value

	# 对已经放在场上的人物立即生效。新生成的人物会在 ball._ready() 再应用一次。
	if apply_existing_characters and _game.get_tree() != null:
		for node:Node in _game.get_tree().get_nodes_in_group("Ball"):
			if node != null and is_instance_valid(node) and node.has_method("apply_training_mode"):
				node.call("apply_training_mode", enabled)

	_game._apply_time_scale_overrides()


func get_training_mode_type() -> String:
	var mode:String = str(_game.Game_Settings.get("Training_Mode_Type", "manual"))
	return mode if mode in ["manual", "rotation", "timed", "boss"] else "manual"


func is_rotation_training_mode() -> bool:
	return get_training_mode_type() == "rotation"


func is_timed_training_mode() -> bool:
	return get_training_mode_type() == "timed"


func is_boss_training_mode() -> bool:
	return get_training_mode_type() == "boss"


func get_training_timed_duration() -> float:
	# 计时模式不再限制在固定预设；只保留 1 秒的安全下限。
	return maxf(float(_game.Game_Settings.get("Training_Timed_Duration", 60.0)), 1.0)


func get_training_boss_side() -> String:
	var side:String = str(_game.Game_Settings.get("Training_Boss_Side", "right"))
	return side if side in ["left","right"] else "right"


func get_training_boss_multiplier() -> float:
	return maxf(float(_game.Game_Settings.get("Training_Boss_Multiplier", 3.0)), 1.0)


func is_training_boss_specialization_enabled() -> bool:
	return bool(_game.Game_Settings.get("Training_Boss_Specialization", true))


func is_training_boss_wheel_battle_enabled() -> bool:
	return bool(_game.Game_Settings.get("Training_Boss_Wheel_Battle", false))


func is_training_boss_intro_enabled() -> bool:
	return bool(_game.Game_Settings.get("Training_Boss_Intro", true))


func set_manual_training_attack_interval(value:float, save_after:bool = false) -> void:
	var clamped_value:float = snappedf(
		clampf(value, MANUAL_ATTACK_INTERVAL_MIN, MANUAL_ATTACK_INTERVAL_MAX),
		MANUAL_ATTACK_INTERVAL_STEP
	)
	_game.set_runtime_game_setting("Manual_Attack_Interval",clamped_value,save_after)


func get_manual_training_attack_interval() -> float:
	return clampf(
		float(_game.Game_Settings.get("Manual_Attack_Interval", 0.15)),
		MANUAL_ATTACK_INTERVAL_MIN,
		MANUAL_ATTACK_INTERVAL_MAX
	)


func set_manual_training_attack(attack_id:String) -> void:
	var wanted:String = attack_id.strip_edges()
	if wanted.is_empty():
		return
	manual_training_attack_id = wanted
	_game.game_setting_changed.emit("Manual_Training_Attack", wanted)


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
