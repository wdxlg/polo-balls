@tool
extends EditorPlugin

# The stock editor remains untouched. Only the game started by this button
# uses the project's separate engine, which provides the offline clock/audio.
const ENGINE_RELATIVE_PATH := "../polo-balls-tools/offline-engine/runtime/Godot.4.7.2.offline.exe"

var _button:Button
var _dialog:AcceptDialog
var _game_pid:int = -1


func _enter_tree() -> void:
	_button = Button.new()
	_button.name = "RunOfflineRecording"
	_button.text = "▶ 运行右键录制版"
	_button.tooltip_text = "在当前原版编辑器中保存修改，然后用项目配套引擎运行游戏；普通 F5 不会启用右键离线录制。"
	_button.flat = true
	_button.focus_mode = Control.FOCUS_NONE
	_button.pressed.connect(_run_offline_game)
	add_control_to_container(CONTAINER_TOOLBAR, _button)
	_dialog = AcceptDialog.new()
	_dialog.title = "运行右键录制版"
	EditorInterface.get_base_control().add_child(_dialog)


func _exit_tree() -> void:
	if is_instance_valid(_button):
		remove_control_from_container(CONTAINER_TOOLBAR, _button)
		_button.queue_free()
	if is_instance_valid(_dialog): _dialog.queue_free()
	# This plugin never kills a running battle or changes the editor executable.


func _engine_path() -> String:
	return ProjectSettings.globalize_path("res://").path_join(ENGINE_RELATIVE_PATH).simplify_path()


func _show_message(message:String) -> void:
	_dialog.dialog_text = message
	_dialog.popup_centered()


func _run_offline_game() -> void:
	if OS.get_name() != "Windows":
		_show_message("当前离线录制引擎只构建了 Windows 版本。")
		return
	var engine_path:String = _engine_path()
	if not FileAccess.file_exists(engine_path):
		_show_message("找不到项目配套的离线录制引擎：\n" + engine_path + "\n请查看 tools/offline_engine/README.md；不会退回原版运行。")
		return
	if _game_pid > 0 and OS.is_process_running(_game_pid):
		_show_message("右键录制版游戏仍在运行（PID %d）。请切换到现有游戏窗口，或先关闭它再启动新对局。" % _game_pid)
		return
	# Mirror F5's save-before-run behavior, so the separate process loads the
	# current project from disk instead of silently using stale scripts/scenes.
	EditorInterface.get_script_editor().save_all_scripts()
	EditorInterface.save_all_scenes()
	if not EditorInterface.get_unsaved_scenes().is_empty():
		_show_message("仍有未保存的场景。请先保存场景，再运行右键录制版。")
		return
	var project_dir:String = ProjectSettings.globalize_path("res://").simplify_path()
	_game_pid = OS.create_process(engine_path, PackedStringArray(["--path", project_dir]))
	if _game_pid <= 0:
		_game_pid = -1
		_show_message("启动离线录制引擎失败：\n" + engine_path)
		return
	print("右键录制版游戏已启动（PID %d）；原版编辑器与 F5 行为不变。" % _game_pid)
