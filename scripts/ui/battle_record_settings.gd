extends VBoxContainer
var recorder:Node
var path_edit:LineEdit
var feedback:Label
var folder_dialog:FileDialog
var choose_button:Button
var save_button:Button
var reset_button:Button

func setup(target:Node) -> void:
	recorder = target
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "录制保存位置"
	add_child(title)
	path_edit = LineEdit.new()
	path_edit.name = "RecordingDirectory"
	path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_edit.custom_minimum_size.x = 0
	path_edit.add_theme_font_size_override("font_size", 9)
	path_edit.expand_to_text_length = false
	path_edit.text = recorder.get_output_directory()
	path_edit.text_submitted.connect(func(_value:String): _save())
	add_child(path_edit)
	var row := HBoxContainer.new()
	add_child(row)
	choose_button = _button(row, "选择文件夹", _choose)
	save_button = _button(row, "保存路径", _save)
	var row2 := HBoxContainer.new()
	add_child(row2)
	_button(row2, "打开文件夹", _open)
	reset_button = _button(row2, "恢复默认", _reset)
	feedback = Label.new()
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.text = "选择或输入路径后保存。设置会记住；录制中不能更改。"
	add_child(feedback)
	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "1080×1920 / 60fps，含游戏声音。\n左键开始会收起布阵并恢复对战；Esc 可暂停，暂停期间不写入成片。"
	add_child(hint)
	folder_dialog = FileDialog.new()
	folder_dialog.name = "RecordingFolderPicker"
	folder_dialog.title = "选择录制保存文件夹"
	folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
	folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	folder_dialog.use_native_dialog = true
	folder_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	folder_dialog.dir_selected.connect(_directory_selected)
	add_child(folder_dialog)

func _button(parent:Node, text:String, action:Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _process(_delta:float) -> void:
	if recorder == null: return
	var busy:bool = recorder.is_busy()
	choose_button.disabled = busy
	save_button.disabled = busy
	reset_button.disabled = busy
	path_edit.editable = not busy

func _choose() -> void:
	if recorder.is_busy(): return
	folder_dialog.current_dir = recorder.get_output_directory()
	folder_dialog.popup_centered(Vector2i(800, 560))

func _directory_selected(path:String) -> void:
	path_edit.text = path
	_save()

func _save() -> void:
	if recorder.set_output_directory(path_edit.text):
		path_edit.text = recorder.get_output_directory()
		feedback.text = "已保存并通过写入检查，下次录像使用此文件夹。"
	else:
		feedback.text = recorder.get_last_error()

func _reset() -> void:
	path_edit.text = recorder.preferences.DEFAULT_DIRECTORY
	_save()

func _open() -> void:
	var result:Dictionary = recorder.preferences.validate(recorder.get_output_directory())
	if result.ok: OS.shell_open(result.directory)
	else: feedback.text = result.error
