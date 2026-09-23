extends RefCounted
const DEFAULT_DIRECTORY:String = "user://recordings"
const CONFIG_PATH:String = "user://battle_recording.cfg"
var config_path:String
var directory:String = ""
var last_error:String = ""

func _init(path:String = CONFIG_PATH) -> void:
	config_path = path
	var config := ConfigFile.new()
	if config.load(config_path) == OK:
		directory = str(config.get_value("recording", "output_directory", ""))

func get_directory() -> String:
	return ProjectSettings.globalize_path(directory if not directory.is_empty() else DEFAULT_DIRECTORY)

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
	config.set_value("recording", "output_directory", result.directory)
	var error:int = config.save(config_path)
	if error != OK:
		last_error = "无法保存录制设置：" + error_string(error)
		return false
	directory = result.directory
	return true
