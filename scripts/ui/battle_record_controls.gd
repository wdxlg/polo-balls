extends Node
## Toolbar glue stays separate from the large settings panel.
const RecorderScript = preload("res://scripts/ui/battle_recorder.gd")
var recorder:Node
var button:Button
var result_dialog:AcceptDialog
var english_path:LineEdit
var output_path:LineEdit
var message_label:Label
var last_message:String = ""
var last_output:String = ""
var _refresh_elapsed:float = 0.0

func setup(target:Button) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	button = target
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	button.button_mask = MOUSE_BUTTON_MASK_LEFT
	recorder = RecorderScript.new()
	recorder.name = "BattleRecorder"
	add_child(recorder)
	recorder.mode_changed.connect(func(_mode:int): refresh())
	recorder.recording_finished.connect(_on_finished)
	result_dialog = AcceptDialog.new()
	result_dialog.name = "RecordingResult"
	result_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	result_dialog.title = "录制 / Recording"
	var body := VBoxContainer.new()
	message_label = Label.new()
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.custom_minimum_size = Vector2(0, 85)
	body.add_child(message_label)
	# A read-only LineEdit is not translated by the global text scanner.
	# Never place filesystem paths in translated labels/tooltips ("Go" in "Godot" is a character name).
	output_path = LineEdit.new()
	output_path.editable = false
	body.add_child(output_path)
	english_path = LineEdit.new()
	english_path.editable = false
	body.add_child(english_path)
	result_dialog.add_child(body)
	result_dialog.get_label().hide()
	result_dialog.add_button("打开输出文件夹 / Open folder", false, "folder")
	result_dialog.custom_action.connect(func(action:StringName):
		if action == &"folder": OS.shell_open(last_output.get_base_dir() if last_output.ends_with(".mp4") else recorder.get_output_directory()))
	add_child(result_dialog)
	refresh()

func toggle_live() -> void:
	var starting:bool = recorder.is_idle()
	if starting:
		last_output = ""
		english_path.text = ""
	if not recorder.toggle_live():
		_show_message(recorder.get_last_error())
	elif starting:
		_close_setup_panels()
		if Game.can_local_manage_world() and (Game.now_stop_state or get_tree().paused):
			Game.continue_game()
	refresh()

func _close_setup_panels() -> void:
	for path:String in ["Team", "Map", "Game_Setting", "MultiPlayer"]:
		var panel:CanvasItem = get_parent().get_node_or_null(path)
		if panel != null: panel.hide()

func _process(delta:float) -> void:
	_refresh_elapsed += delta
	if _refresh_elapsed >= 0.2:
		_refresh_elapsed = 0.0
		refresh()

func start_simulated() -> void:
	if recorder.get_mode() == 0 and not recorder.is_busy():
		last_output = ""
		english_path.text = ""
	if not recorder.start_simulated(): _show_message(recorder.get_last_error())
	refresh()

func refresh() -> void:
	if not is_instance_valid(button) or not is_instance_valid(recorder): return
	var active:bool = recorder.is_recording()
	var saving:bool = not active and recorder.is_busy()
	button.text = "保存中…" if saving else Game.ui_t("UI_RECORD_STOP" if active else "UI_RECORD")
	button.modulate = Color(1.0, 0.35, 0.35) if active else Color.WHITE
	var reason:String = recorder.get_pause_reason() if active else ""
	if active and not reason.is_empty():
		button.text = "待录" if recorder._frame_index == 0 else "暂停"
		button.modulate = Color(1.0, 0.8, 0.3)
	button.disabled = saving
	button.tooltip_text = "左键：开始/停止高清对战录制；右键：从当前状态离线计算对局，不重打；尽快生成正常速度的有声视频。" + "\n默认：user://recordings；在设置 → 录制中选择保存目录" + "\n每次输出中文 + 英文两份视频 · 1080×1920 / 60fps · 仅对战画面和游戏声音 · 暂停不计入成片"

	if active:
		var tail_left:float = recorder.get_tail_left()
		var tail_text:String = "胜负已分，%.1f 秒后自动停止。" % maxf(tail_left, 0.0) if tail_left >= 0.0 else "分出胜负后再录 %.1f 秒自动停止；" % recorder.get_tail_seconds()
		button.tooltip_text += "\n已录 %d 帧。%s%s再点一次立即停止。" % [recorder._frame_index, reason, tail_text]

func _on_finished(path:String, frames:int) -> void:
	refresh()
	last_output = path
	english_path.text = str(recorder.last_outputs.get("en", ""))
	if path.is_empty():
		_show_message("录制未完成：" + recorder.get_last_error())
	else:
		var kind:String = "%d 个语言版本 MP4" % recorder.last_outputs.size() if path.ends_with(".mp4") else "PNG 图片序列（未找到可用的编码器）"
		_show_message(("已保存 %s，%d 帧（含游戏声音）。" if path.ends_with(".mp4") else "已保存 %s，%d 帧；音频保留为 .audio.f32 临时文件，尚未合成视频。") % [kind, frames])

func _show_message(message:String) -> void:
	last_message = message if not message.is_empty() else "录制正在收尾，请稍后再试。"
	if not recorder.get_last_error().is_empty() and not last_output.is_empty():
		last_message += "\n注意：" + recorder.get_last_error()
	message_label.text = last_message
	output_path.text = ProjectSettings.globalize_path(last_output) if not last_output.is_empty() else recorder.get_output_directory()
	result_dialog.popup_centered(Vector2i(clampi(get_window().size.x - 32, 320, 660), 260))
