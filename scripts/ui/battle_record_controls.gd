extends Node
## Toolbar glue stays separate from the large settings panel.
const RecorderScript = preload("res://scripts/ui/battle_recorder.gd")
var recorder:Node
var button:Button
var result_dialog:AcceptDialog
var output_path:LineEdit
var message_label:Label
var last_message:String = ""
var last_output:String = ""

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
	message_label.custom_minimum_size = Vector2(600, 85)
	body.add_child(message_label)
	# A read-only LineEdit is not translated by the global text scanner.
	# Never place filesystem paths in translated labels/tooltips ("Go" in "Godot" is a character name).
	output_path = LineEdit.new()
	output_path.editable = false
	body.add_child(output_path)
	result_dialog.add_child(body)
	result_dialog.get_label().hide()
	result_dialog.add_button("打开输出文件夹 / Open folder", false, "folder")
	result_dialog.custom_action.connect(func(action:StringName):
		if action == &"folder": OS.shell_open(recorder.get_output_directory()))
	add_child(result_dialog)
	refresh()

func toggle_live() -> void:
	if not recorder.toggle_live(): _show_message(recorder.get_last_error())
	refresh()

func start_simulated() -> void:
	# Close setup panels before rematch, otherwise the world stays in placement mode.
	if recorder.get_mode() == 0 and not recorder.is_busy():
		if Game.can_local_manage_world() and recorder._world() != null and recorder._world().has_rematch_setup():
			for path:String in ["Team", "Map", "Game_Setting", "MultiPlayer"]:
				var panel:CanvasItem = get_parent().get_node_or_null(path)
				if panel != null: panel.hide()
	if not recorder.start_simulated(): _show_message(recorder.get_last_error())
	refresh()

func refresh() -> void:
	if not is_instance_valid(button) or not is_instance_valid(recorder): return
	var active:bool = recorder.is_recording()
	var saving:bool = not active and recorder.is_busy()
	button.text = "保存中…" if saving else Game.ui_t("UI_RECORD_STOP" if active else "UI_RECORD")
	button.modulate = Color(1.0, 0.35, 0.35) if active else Color.WHITE
	button.disabled = saving
	button.tooltip_text = "左键：开始/停止高清对战录制；右键：慢速重打并生成正常速度的有声对战视频。" + "\n输出：user://recordings（保存后可打开文件夹）" + "\n1080×1920 / 60fps · 仅对战画面和游戏声音 · 暂停不计入成片"

func _on_finished(path:String, frames:int) -> void:
	refresh()
	last_output = path
	if path.is_empty():
		_show_message("录制未完成：" + recorder.get_last_error())
	else:
		var kind:String = "MP4" if path.ends_with(".mp4") else "PNG 图片序列（未找到可用的编码器）"
		_show_message(("已保存 %s，%d 帧（含游戏声音）。" if path.ends_with(".mp4") else "已保存 %s，%d 帧；音频保留为 .audio.f32 临时文件，尚未合成视频。") % [kind, frames])

func _show_message(message:String) -> void:
	last_message = message if not message.is_empty() else "录制正在收尾，请稍后再试。"
	if not recorder.get_last_error().is_empty() and not last_output.is_empty():
		last_message += "\n注意：" + recorder.get_last_error()
	message_label.text = last_message
	output_path.text = ProjectSettings.globalize_path(last_output) if not last_output.is_empty() else recorder.get_output_directory()
	result_dialog.popup_centered(Vector2i(660, 220))
