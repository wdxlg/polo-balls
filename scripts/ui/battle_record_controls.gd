extends Node
## Toolbar glue stays separate from the large settings panel.
const RecorderScript = preload("res://scripts/ui/battle_recorder.gd")
var recorder:Node
var button:Button
var result_dialog:AcceptDialog
var english_path:LineEdit
var output_path:LineEdit
var result_heading:Label
var result_body:VBoxContainer
var result_scroll:ScrollContainer
var folder_button:Button
var path_labels:Array[Label] = []
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
	# The game normally renders 1080x1920 into a 540x960 window. Embedded
	# popup geometry/fonts must compensate for that scale, not become half-size.
	result_dialog.theme = Theme.new()
	result_scroll = ScrollContainer.new()
	result_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	result_body = VBoxContainer.new()
	result_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_scroll.add_child(result_body)
	result_heading = Label.new()
	result_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_body.add_child(result_heading)
	message_label = Label.new()
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_body.add_child(message_label)
	# Read-only LineEdits preserve literal paths (no localization scanner) and
	# retain selection/copy/horizontal scrolling for long output directories.
	output_path = LineEdit.new()
	english_path = LineEdit.new()
	for field:LineEdit in [output_path,english_path]:
		var label:=Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		path_labels.append(label)
		result_body.add_child(label)
		field.editable = false
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		result_body.add_child(field)
	result_dialog.add_child(result_scroll)
	result_dialog.get_label().hide()
	folder_button = result_dialog.add_button("打开文件夹", false, "folder")
	result_dialog.custom_action.connect(func(action:StringName):
		if action == &"folder": OS.shell_open(last_output.get_base_dir() if last_output.ends_with(".mp4") else recorder.get_output_directory()))
	add_child(result_dialog)
	get_window().size_changed.connect(_on_result_window_resized)
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
	if recorder.is_preparing(): button.text = "准备中…"
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
	var message:String
	if path.is_empty():
		message = "录制未完成：" + recorder.get_last_error()
	elif not recorder.get_last_error().is_empty():
		message = "录制中断，已保留部分录像（%d 帧），不是完整对局。" % frames
	else:
		var kind:String = "%d 个语言版本 MP4" % recorder.last_outputs.size() if path.ends_with(".mp4") else "PNG 图片序列（未找到可用的编码器）"
		message = ("已保存 %s，%d 帧（含游戏声音）。" if path.ends_with(".mp4") else "已保存 %s，%d 帧；音频保留为 .audio.f32 临时文件，尚未合成视频。") % [kind, frames]
	var warnings:String = recorder.get_recording_warnings()
	if not warnings.is_empty(): message += "\n\n本次录制提示（已尽力继续，成片质量可能受影响）：\n" + warnings
	_show_message(message)


func _show_message(message:String) -> void:
	last_message = message if not message.is_empty() else "录制正在收尾，请稍后再试。"
	if not recorder.get_last_error().is_empty() and not last_output.is_empty():
		last_message += "\n注意：" + recorder.get_last_error()
	message_label.text = last_message
	output_path.text = ProjectSettings.globalize_path(last_output) if not last_output.is_empty() else recorder.get_output_directory()
	_layout_result_dialog()
	output_path.caret_column = output_path.text.length()
	english_path.caret_column = english_path.text.length()

func _on_result_window_resized() -> void:
	if is_instance_valid(result_dialog) and result_dialog.visible:
		_refit_visible_result.call_deferred()

func _refit_visible_result() -> void:
	if is_instance_valid(result_dialog) and result_dialog.visible:
		_layout_result_dialog()

func _layout_result_dialog() -> void:
	var physical:Vector2 = Vector2(get_window().size)
	var units_per_pixel:float = 1.0
	if result_dialog.is_embedded():
		var stretch:Vector2 = get_viewport().get_stretch_transform().get_scale().abs()
		var pixel_scale:float = maxf(minf(stretch.x,stretch.y),0.01)
		units_per_pixel = 1.0/pixel_scale
		physical = get_viewport().get_visible_rect().size*pixel_scale
	var small:bool = physical.x<400.0
	var compact:bool = physical.x<700.0
	var body_font:int = ceili((20.0 if small else (24.0 if compact else 28.0))*units_per_pixel)
	var path_font:int = ceili((16.0 if small else (18.0 if compact else 22.0))*units_per_pixel)
	var button_font:int = ceili((18.0 if small else (22.0 if compact else 24.0))*units_per_pixel)
	var heading_font:int = ceili((24.0 if compact else 34.0)*units_per_pixel)
	var margin:int = ceili((12.0 if compact else 24.0)*units_per_pixel)
	var zh:bool = not str(Game.current_locale).begins_with("en")
	result_dialog.title = "录制结果" if zh else "Recording result"
	result_heading.text = "录制结果" if zh else "Recording result"
	result_heading.add_theme_font_size_override("font_size",heading_font)
	message_label.add_theme_font_size_override("font_size",body_font)
	message_label.add_theme_constant_override("line_spacing",ceili(6.0*units_per_pixel))
	message_label.custom_minimum_size = Vector2(0,80.0*units_per_pixel)
	result_body.add_theme_constant_override("separation",ceili(14.0*units_per_pixel))
	# ScrollContainer reserves the scrollbar's theme minimum, not its custom
	# minimum. Keep wide hit targets from covering the last text column.
	var scrollbar_style:=StyleBoxFlat.new()
	scrollbar_style.bg_color = Color(0.12,0.14,0.17,1.0)
	scrollbar_style.content_margin_left = 8.0*units_per_pixel
	scrollbar_style.content_margin_right = 8.0*units_per_pixel
	result_scroll.get_v_scroll_bar().add_theme_stylebox_override("scroll",scrollbar_style)
	var panel:=StyleBoxFlat.new()
	panel.bg_color = Color(0.07,0.08,0.10,1.0)
	panel.set_content_margin_all(margin)
	result_dialog.theme.set_stylebox("panel","AcceptDialog",panel)
	# AcceptDialog overwrites button custom_minimum_size on every layout;
	# use its actual theme constants instead of setting the Button property.
	result_dialog.theme.set_constant("buttons_min_height","AcceptDialog",ceili(48.0*units_per_pixel))
	for state:String in ["normal","hover","pressed"]:
		var style:=StyleBoxFlat.new()
		style.bg_color = Color(0.16,0.18,0.21,1.0) if state=="normal" else Color(0.26,0.29,0.34,1.0)
		style.set_content_margin_all(ceili(8.0*units_per_pixel))
		result_dialog.theme.set_stylebox(state,"Button",style)
	result_dialog.theme.set_constant("buttons_separation","AcceptDialog",ceili(16.0*units_per_pixel))
	result_dialog.theme.set_font_size("title_font_size","Window",button_font)
	result_dialog.theme.set_constant("title_height","Window",ceili(40.0*units_per_pixel))
	path_labels[0].text = ("输出目录（可选中复制）" if zh else "Output folder (select to copy)") if last_output.is_empty() else ("中文文件（可选中复制）" if zh else "Chinese file (select to copy)")
	path_labels[1].text = "英文文件（可选中复制）" if zh else "English file (select to copy)"
	for label:Label in path_labels: label.add_theme_font_size_override("font_size",path_font)
	for field:LineEdit in [output_path,english_path]:
		field.add_theme_font_size_override("font_size",path_font)
		field.add_theme_color_override("font_uneditable_color",Color(0.90,0.93,0.98,1.0))
		field.custom_minimum_size = Vector2(0,44.0*units_per_pixel)
	path_labels[1].visible = not english_path.text.is_empty()
	english_path.visible = path_labels[1].visible
	folder_button.text = "打开文件夹" if zh else "Open folder"
	result_dialog.get_ok_button().text = "确定" if zh else "OK"
	for action:Button in [folder_button,result_dialog.get_ok_button()]:
		action.add_theme_font_size_override("font_size",button_font)
	var pixels:Vector2 = Vector2(minf(960.0,maxf(physical.x-32.0,240.0)),minf(560.0,maxf(physical.y-80.0,180.0)))
	var target_size:Vector2i = Vector2i(pixels*units_per_pixel)
	result_dialog.popup_centered(target_size)
	if result_dialog.is_embedded():
		# popup_centered also applies physical desktop bounds to logical units.
		# Fit/center the embedded window explicitly in the stretched viewport.
		result_dialog.size = target_size
		result_dialog.position = Vector2i((get_viewport().get_visible_rect().size-Vector2(result_dialog.size))*0.5)
