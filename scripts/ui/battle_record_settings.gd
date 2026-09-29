extends VBoxContainer
var recorder:Node
var path_edit:LineEdit
var feedback:Label
var folder_dialog:FileDialog
var choose_button:Button
var open_button:Button
var tail_spin:SpinBox
var tail_label:Label
var composition_select:OptionButton
var composition_feedback:Label

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
	# 只保留两个按钮：打开（打开保存文件夹）、设置（选择保存路径）。手输路径按回车即保存。
	open_button = _button(row, "打开", _open)
	open_button.name = "OpenFolder"
	open_button.tooltip_text = "打开当前录制保存文件夹"
	choose_button = _button(row, "设置", _choose)
	choose_button.name = "ChooseFolder"
	choose_button.tooltip_text = "选择录制保存文件夹"
	var tail_row := HBoxContainer.new()
	tail_row.name = "TailRow"
	tail_row.add_theme_constant_override("separation", 6)
	add_child(tail_row)
	tail_label = Label.new()
	tail_label.text = "对局结束后续录（秒）"
	tail_label.add_theme_font_size_override("font_size", 9)
	tail_row.add_child(tail_label)
	tail_spin = SpinBox.new()
	tail_spin.name = "TailSeconds"
	tail_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tail_spin.custom_minimum_size = Vector2(0, 24)
	tail_spin.min_value = recorder.preferences.MIN_TAIL_SECONDS
	tail_spin.max_value = recorder.preferences.MAX_TAIL_SECONDS
	tail_spin.step = 0.5
	tail_spin.rounded = false
	tail_spin.select_all_on_focus = true
	tail_spin.tooltip_text = "分出胜负后再继续录制多少秒游戏时间，然后自动停止并保存；左键实时和右键模拟都适用。默认 5 秒。"
	tail_spin.set_value_no_signal(recorder.preferences.get_tail_seconds())
	tail_spin.value_changed.connect(_tail_changed)
	tail_spin.get_line_edit().add_theme_font_size_override("font_size", 9)
	tail_row.add_child(tail_spin)
	# Camera framing belongs in Parameters, directly below the background selector,
	# not at the end of the page or among recording-only directory/tail options.
	var parameter_box:VBoxContainer = null
	var recording_box:Node = get_parent()
	if recording_box != null and recording_box.get_parent() != null:
		parameter_box = recording_box.get_parent().get_node_or_null("CategoryBox_parameters") as VBoxContainer
	var composition_container:VBoxContainer = parameter_box if parameter_box != null else self
	var layout_row := HBoxContainer.new()
	layout_row.name = "CompositionRow"
	layout_row.add_theme_constant_override("separation", 6)
	composition_container.add_child(layout_row)
	var layout_label := Label.new()
	layout_label.text = "画面取景"
	layout_label.add_theme_font_size_override("font_size", 9)
	layout_row.add_child(layout_label)
	composition_select = OptionButton.new()
	composition_select.name = "RecordingComposition"
	# Match the compact parameter rows; popup entries retain their full text.
	composition_select.fit_to_longest_item = false
	composition_select.clip_text = true
	composition_select.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	composition_select.custom_minimum_size = Vector2(0,24)
	composition_select.add_theme_font_size_override("font_size",9)
	composition_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	composition_select.add_item("完整地图 · 竖屏排版", recorder.preferences.FULL)
	composition_select.add_item("交战跟拍 · 自动推拉", recorder.preferences.FOLLOW)
	composition_select.add_item("交战跟拍 + 小全图", recorder.preferences.FOLLOW_OVERVIEW)
	composition_select.select(recorder.get_composition())
	composition_select.tooltip_text = "立即改变游戏内的实际镜头；中英文录像沿用相同视野。小全图也会显示在游戏画面中；录制中锁定。"
	composition_select.item_selected.connect(_composition_changed)
	layout_row.add_child(composition_select)
	composition_feedback = Label.new()
	composition_feedback.name = "CompositionFeedback"
	composition_feedback.add_theme_font_size_override("font_size",9)
	composition_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	composition_feedback.text = "选择后立即改变游戏内画面；录像沿用同一取景。"
	composition_container.add_child(composition_feedback)
	if parameter_box != null:
		var background_row:Node = parameter_box.get_node_or_null("MapBackgroundRow")
		if background_row != null:
			parameter_box.move_child(layout_row,background_row.get_index() + 1)
			parameter_box.move_child(composition_feedback,layout_row.get_index() + 1)
	feedback = Label.new()
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.text = "「设置」选择文件夹，或直接输入路径后按回车。设置会记住；录制中不能更改。"
	add_child(feedback)
	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "1080×1920 / 60fps，含游戏声音。\n左键开始会收起布阵并恢复对战；Esc 可暂停，暂停期间不写入成片。\n分出胜负后按上方秒数继续录制，然后自动停止保存。"
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
	composition_select.disabled = busy
	tail_spin.editable = not busy
	path_edit.editable = not busy

func _choose() -> void:
	if recorder.is_busy(): return
	folder_dialog.current_dir = recorder.get_output_directory()
	folder_dialog.popup_centered(Vector2i(800, 560))

func _directory_selected(path:String) -> void:
	path_edit.text = path
	_save()

func _save() -> void:
	if recorder.is_busy():
		feedback.text = "录制中不能更改保存位置。"
		return
	if recorder.set_output_directory(path_edit.text):
		path_edit.text = recorder.get_output_directory()
		feedback.text = "已保存并通过写入检查，下次录像使用此文件夹。"
	else:
		feedback.text = recorder.get_last_error()

func _tail_changed(value:float) -> void:
	if recorder.is_busy():
		tail_spin.set_value_no_signal(recorder.preferences.get_tail_seconds())
		feedback.text = "录制中不能更改续录时间。"
		return
	if recorder.set_tail_seconds(value):
		tail_spin.set_value_no_signal(recorder.preferences.get_tail_seconds())
		feedback.text = "已保存：分出胜负后继续录制 %s 秒。" % _fmt(recorder.preferences.get_tail_seconds())
	else:
		feedback.text = recorder.get_last_error()

func _composition_changed(index:int) -> void:
	if recorder.is_busy():
		composition_select.select(recorder.get_composition())
		composition_feedback.text = "录制中不能更改画面取景。"
		return
	if recorder.set_composition(composition_select.get_item_id(index)):
		composition_feedback.text = "已切换画面取景：%s；游戏画面立即生效，录像同步。" % composition_select.get_item_text(index)
	else:
		composition_select.select(recorder.get_composition())
		composition_feedback.text = recorder.get_last_error()

func _fmt(value:float) -> String:
	return str(int(value)) if is_equal_approx(value, floorf(value)) else "%.1f" % value

func _open() -> void:
	var result:Dictionary = recorder.preferences.validate(recorder.get_output_directory())
	if result.ok: OS.shell_open(result.directory)
	else: feedback.text = result.error
