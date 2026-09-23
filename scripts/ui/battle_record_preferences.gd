extends RefCounted
const DEFAULT_DIRECTORY:String = "user://recordings"
const CONFIG_PATH:String = "user://battle_recording.cfg"
## 对局分出胜负后继续录制的秒数（游戏时间）。两种模式共用；0 表示胜负一出立即收尾。
const DEFAULT_TAIL_SECONDS:float = 5.0
const MIN_TAIL_SECONDS:float = 0.0
const MAX_TAIL_SECONDS:float = 600.0
# Persisted capture-only layout. Never changes the player's camera.
const FULL:int = 0
const FOLLOW:int = 1
const FOLLOW_OVERVIEW:int = 2
const DEFAULT_COMPOSITION:int = FULL
var config_path:String
var directory:String = ""
var tail_seconds:float = DEFAULT_TAIL_SECONDS
var composition:int = DEFAULT_COMPOSITION
var last_error:String = ""

func _init(path:String = CONFIG_PATH) -> void:
	config_path = path
	var config := ConfigFile.new()
	if config.load(config_path) == OK:
		directory = str(config.get_value("recording", "output_directory", ""))
		tail_seconds = clamp_tail(float(config.get_value("recording", "tail_seconds", DEFAULT_TAIL_SECONDS)))
		composition = clamp_composition(int(config.get_value("recording", "composition", DEFAULT_COMPOSITION)))

func get_directory() -> String:
	return ProjectSettings.globalize_path(directory if not directory.is_empty() else DEFAULT_DIRECTORY)

func get_tail_seconds() -> float:
	return tail_seconds

func get_composition() -> int:
	return composition

static func clamp_composition(value:int) -> int:
	return value if value >= FULL and value <= FOLLOW_OVERVIEW else DEFAULT_COMPOSITION

func save_composition(value:int) -> bool:
	if value < FULL or value > FOLLOW_OVERVIEW:
		last_error = "未知的录制构图模式。"
		return false
	var config := ConfigFile.new()
	config.load(config_path)
	config.set_value("recording", "composition", value)
	var error:int = config.save(config_path)
	if error != OK:
		last_error = "无法保存录制设置：" + error_string(error)
		return false
	composition = value
	return true

static func clamp_tail(value:float) -> float:
	if is_nan(value) or is_inf(value): return DEFAULT_TAIL_SECONDS
	return clampf(value, MIN_TAIL_SECONDS, MAX_TAIL_SECONDS)

func save_tail_seconds(value:float) -> bool:
	var clamped:float = clamp_tail(value)
	var config := ConfigFile.new()
	config.load(config_path) # 保留已保存的目录；文件不存在时从空配置开始。
	config.set_value("recording", "tail_seconds", clamped)
	var error:int = config.save(config_path)
	if error != OK:
		last_error = "无法保存录制设置：" + error_string(error)
		return false
	tail_seconds = clamped
	return true

func validate(candidate:String) -> Dictionary:
	last_error = ""
	var path:String = candidate.strip_edges().replace("\\", "/")
	if path.begins_with('"') and path.ends_with('"'): path = path.substr(1, path.length() - 2)
	if path.is_empty(): path = DEFAULT_DIRECTORY
	if path.begins_with("res://") or not path.is_absolute_path():
		return _invalid("请选择完整的文件夹路径，例如 D:/对战录像，不能使用相对路径或项目资源路径。")
	path = ProjectSettings.globalize_path(path).simplify_path()
	if FileAccess.file_exists(path): return _invalid("该路径是文件，不是文件夹。")
	var error:int = DirAccess.make_dir_recursive_absolute(path)
	if error != OK: return _invalid("无法创建或访问文件夹：" + error_string(error))
	var probe:String = path.path_join(".polo_record_probe_%d_%d.tmp" % [OS.get_process_id(), Time.get_ticks_usec()])
	var handle := FileAccess.open(probe, FileAccess.WRITE)
	if handle == null: return _invalid("文件夹不可写：" + error_string(FileAccess.get_open_error()))
	handle.store_string("recording write test")
	handle.flush()
	error = handle.get_error()
	handle.close()
	var removed:int = DirAccess.remove_absolute(probe)
	if error != OK or removed != OK: return _invalid("文件夹写入或清理测试失败，请检查权限和磁盘空间。")
	return {"ok":true, "directory":path}

func _invalid(message:String) -> Dictionary:
	last_error = message
	return {"ok":false, "error":message}

func save_directory(candidate:String) -> bool:
	var result:Dictionary = validate(candidate)
	if not result.ok: return false
	var config := ConfigFile.new()
	config.load(config_path) # 目录与续录秒数同文件保存，互不覆盖。
	config.set_value("recording", "output_directory", result.directory)
	var error:int = config.save(config_path)
	if error != OK:
		last_error = "无法保存录制设置：" + error_string(error)
		return false
	directory = result.directory
	return true
