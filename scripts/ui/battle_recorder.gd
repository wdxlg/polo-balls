extends Node
## 对决录制器（顶部工具栏“录制”按钮的后端）。
##
## 两种模式都把原始像素直接喂给 ffmpeg 的 stdin 编码成 mp4，不在磁盘上留中间图片：
##   左键 LIVE —— 实时录制当前画面。按固定 30fps 定帧率重采样，卡顿/暂停时重复上一帧，
##                保证成片时长与真实时间一致。
##   右键 SIM  —— 模拟录制：把世界时间压到 0.25 倍重打上一把，抓帧永远跟得上物理步进，
##                对局只画进离屏 SubViewport（玩家看到的是全屏遮罩 + 中止按钮），
##                分出胜负后自动收尾并直接输出 mp4。
## 找不到 ffmpeg（或引擎没有管道接口）时降级为 PNG 序列，结束时再尽力补一次合成；
## 任何情况都会把最终产物路径打到控制台，不会静默失败。
##
## 输出目录：user://recordings/
## （Windows 上等价于 %APPDATA%\Godot\app_userdata\<项目名>\recordings）

# 遮罩只挂在这个可见层；抓帧视口的 canvas_cull_mask 会把它剔除，
# 于是“遮罩给玩家看、对局给录像看”，两边互不干扰。
# 与 scripts/effects/地表渲染采样.gd 的 CAPTURE_LAYER 复用同一位。
const CAPTURE_MASK_BIT:int = 1 << 19
const CAPTURE_ALL_MASK:int = (1 << 20) - 1

const LIVE_OUTPUT_FPS:float = 30.0
const SIM_OUTPUT_FPS:float = 60.0
## 模拟录制的世界倍率：0.25 = 4 倍慢放。每帧抓帧预算约 66ms，读回 + H264 都跟得上。
const SIM_TIME_SCALE:float = 0.25
const SIM_MAX_GAME_SECONDS:float = 300.0
const SIM_MIN_GAME_SECONDS:float = 3.0
const SIM_TAIL_GAME_SECONDS:float = 1.5
const TIME_SCALE_KEY:String = "battle_record_sim"
const OUTPUT_ROOT:String = "user://recordings"
const OVERLAY_LAYER:int = 2000
## 单个绘制帧最多补几张重复帧；超过说明是断点/长时间卡顿，丢掉积压而不是灌一堆静止帧。
const MAX_FRAMES_PER_DRAW:int = 4
const FFMPEG_CANDIDATES:Array = [
	"C:/ffmpeg/bin/ffmpeg.exe",
	"/usr/bin/ffmpeg",
	"/usr/local/bin/ffmpeg",
	"/opt/homebrew/bin/ffmpeg",
]
## 见 global/audios.gd 的 GAMEPLAY_BUS：只有游戏声走这条总线。
const GAMEPLAY_BUS_NAME:StringName = &"GameplayRecord"

enum Mode { IDLE, LIVE, SIM }

signal mode_changed(mode:int)
## path 为最终产物（mp4，或降级后的 PNG 目录），frames 为写出的帧数。
signal recording_finished(path:String, frames:int)

var _last_error:String = ""
var mode:int = Mode.IDLE

var _session_active:bool = false
var _finalizing:bool = false
var _capture_viewport:Viewport = null
var _sim_viewport:SubViewport = null
var _empty_sim_grabs:int = 0
var _capture_size:Vector2i = Vector2i.ZERO

var _frame_interval:float = 1.0 / LIVE_OUTPUT_FPS
var _output_fps:float = LIVE_OUTPUT_FPS
var _frame_index:int = 0
var _game_time:float = 0.0
var _accumulator:float = 0.0
var _last_tick_usec:int = 0

var _out_path:String = ""
var _session_dir:String = ""
var _pipe:FileAccess = null
var _pipe_pid:int = 0
var _png_fallback:bool = false
var _resolved_ffmpeg:String = ""
var _last_mux_ok:bool = false

var _sim_tail_left:float = -1.0
var _sim_saw_two_sides:bool = false
var _sim_finished:bool = false
var _last_progress_push:float = -1.0

var _audio_muted_by_us:bool = false
var _audio_bus_was_muted:bool = false

var _overlay:CanvasLayer = null
var _overlay_backdrop:ColorRect = null
var _overlay_label:Label = null
var _overlay_abort:Button = null


func _ready() -> void:
	# 录制不能因为游戏暂停（esc）而停摆：遮罩、进度、中止按钮都要继续响应。
	process_mode = Node.PROCESS_MODE_ALWAYS


#========================================================
# 对外接口
#========================================================

func get_mode() -> int:
	return mode


func is_busy() -> bool:
	return _session_active or _finalizing


func get_last_error() -> String:
	return _last_error


func _fail(message:String) -> bool:
	_last_error = message
	push_warning("battle_recorder: " + message)
	return false


func is_idle() -> bool:
	return mode == Mode.IDLE and not is_busy()


func is_recording() -> bool:
	return mode != Mode.IDLE


## 左键：开始 / 停止实时录制。模拟录制进行中时忽略（它自己会在胜负后收尾）。
func toggle_live() -> bool:
	if mode == Mode.SIM:
		return _fail("正在模拟录制，请使用遮罩上的中止按钮。")
	if mode == Mode.LIVE:
		stop()
		return true
	return start_live()


func start_live() -> bool:
	if mode != Mode.IDLE or is_busy():
		return _fail("录制正在进行或保存中，请稍后再试。")
	if not _begin_session(LIVE_OUTPUT_FPS, "live"):
		return false
	_capture_viewport = get_viewport()
	_enter_mode(Mode.LIVE)
	return true


## 右键：低倍速模拟重打上一把并直接输出。需要有可重打的布阵。
func start_simulated() -> bool:
	if mode != Mode.IDLE or is_busy():
		return _fail("录制正在进行或保存中，请稍后再试。")
	if Game.network_role != "offline" and Game.multiplayer.has_multiplayer_peer():
		return _fail("模拟录制仅支持本地对局；联网时请使用左键实时录制。")
	if not Game.can_local_manage_world():
		return _fail("当前没有管理对局的权限；请使用左键实时录制。")
	var world:Node = _world()
	if world == null or not world.has_method("has_rematch_setup") or not bool(world.call("has_rematch_setup")):
		return _fail("没有可重打的布阵。请先放置对战角色，再右键模拟录制；左键可直接录当前画面。")
	if not _begin_session(SIM_OUTPUT_FPS, "sim"):
		return false

	_setup_sim_capture_viewport()
	_show_overlay()
	_mute_gameplay_audio(true)
	# 先压时间倍率再重打，重置与出场演出也在慢放里进行，抓帧不会漏。
	if bool(Game.now_stop_state):
		Game.continue_game()
	Game.request_time_scale_override(TIME_SCALE_KEY, SIM_TIME_SCALE, Color(0, 0, 0, 0))
	Game.request_world_rematch(true)
	_enter_mode(Mode.SIM)
	return true


## 停止当前录制（两种模式通用）。真正的收尾在抓帧循环退出后执行。
func stop() -> void:
	if mode == Mode.IDLE:
		return
	mode = Mode.IDLE
	mode_changed.emit(mode)
	# 正常路径由 _capture_loop 收尾；树已经不再绘制时这里兜底，避免状态卡死。
	if not _session_active:
		_finish_session()


func get_output_directory() -> String:
	return ProjectSettings.globalize_path(OUTPUT_ROOT)


func _enter_mode(next_mode:int) -> void:
	mode = next_mode
	_session_active = true
	mode_changed.emit(mode)
	_capture_loop()


#========================================================
# 会话建立 / 收尾
#========================================================

func _begin_session(output_fps:float, tag:String) -> bool:
	_last_error = ""
	if DisplayServer.get_name() == "headless":
		return _fail("无渲染环境不能录制画面。")
	var source:Viewport = get_viewport()
	var size:Vector2i = Vector2i(source.get_texture().get_size())
	if size.x < 16 or size.y < 16:
		return _fail("视口尺寸异常（%s），取消录制。" % str(size))

	_output_fps = maxf(output_fps, 1.0)
	_frame_interval = 1.0 / _output_fps
	_capture_size = size
	_frame_index = 0
	_game_time = 0.0
	_accumulator = 0.0
	_last_progress_push = -1.0
	_sim_tail_left = -1.0
	_sim_saw_two_sides = false
	_sim_finished = false
	_empty_sim_grabs = 0
	_pipe = null
	_pipe_pid = 0
	_png_fallback = false
	_session_dir = ""

	var stamp:String = Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_") + "_%d" % Time.get_ticks_usec()
	_out_path = "%s/%s_%s.mp4" % [OUTPUT_ROOT, tag, stamp]
	DirAccess.make_dir_recursive_absolute(OUTPUT_ROOT)

	if _open_pipe_encoder():
		return true

	# 降级路线：先把帧存成 PNG 序列，结束时再尝试合成 mp4。
	_session_dir = "%s/%s_%s" % [OUTPUT_ROOT, tag, stamp]
	if DirAccess.make_dir_recursive_absolute(_session_dir) == OK:
		_png_fallback = true
		push_warning("battle_recorder: 没有可用的 ffmpeg 管道，改为输出 PNG 序列：%s" % ProjectSettings.globalize_path(_session_dir))
		return true

	return _fail("无法创建录制输出目录，录制取消。")


func _open_pipe_encoder() -> bool:
	if not OS.has_method("execute_with_pipe"):
		return false
	var ffmpeg:String = _resolve_ffmpeg()
	if ffmpeg.is_empty():
		return false

	var args:Array = [
		"-y", "-hide_banner", "-loglevel", "error",
		"-f", "rawvideo", "-pix_fmt", "rgba",
		"-s", "%dx%d" % [_capture_size.x, _capture_size.y],
		"-r", "%.6f" % _output_fps,
		"-i", "-",
	]
	if _capture_size.x % 2 != 0 or _capture_size.y % 2 != 0:
		# libx264 只接受偶数尺寸。
		args.append("-vf")
		args.append("scale=trunc(iw/2)*2:trunc(ih/2)*2")
	args.append("-an")
	args.append("-c:v")
	args.append("libx264")
	args.append("-preset")
	args.append("veryfast")
	args.append("-crf")
	args.append("20")
	args.append("-pix_fmt")
	args.append("yuv420p")
	args.append("-movflags")
	args.append("+faststart")
	args.append(ProjectSettings.globalize_path(_out_path))

	var result:Variant = OS.execute_with_pipe(ffmpeg, args, true)
	if typeof(result) != TYPE_DICTIONARY:
		push_warning("battle_recorder: 启动 ffmpeg 失败（返回 %s）。" % str(result))
		return false
	var handles:Dictionary = result as Dictionary
	var stdio:Variant = handles.get("stdio")
	if not (stdio is FileAccess) or not (stdio as FileAccess).is_open():
		push_warning("battle_recorder: ffmpeg 管道不可写，回退到 PNG 序列。")
		return false
	_pipe = stdio as FileAccess
	_pipe_pid = int(handles.get("pid", 0))
	return true


func _finish_session() -> void:
	if not _session_active:
		return
	_session_active = false
	_finalizing = true
	if mode != Mode.IDLE:
		mode = Mode.IDLE
		mode_changed.emit(mode)
	_release_sim_world_state()
	_free_sim_capture_viewport()
	_hide_overlay()

	var finished_path:String = ""
	var frame_count:int = _frame_index

	if _pipe != null:
		if _pipe.is_open():
			_pipe.flush()
			_pipe.close()
		_pipe = null
		if _pipe_pid > 0:
			await _wait_for_process(_pipe_pid, 20.0)
		if frame_count > 0 and FileAccess.file_exists(_out_path) and OS.get_process_exit_code(_pipe_pid) == 0:
			finished_path = _out_path
		_pipe_pid = 0
	elif _png_fallback and frame_count > 0:
		finished_path = _session_dir
		var ffmpeg:String = _resolve_ffmpeg()
		if not ffmpeg.is_empty():
			await _mux_png_sequence(ffmpeg, _session_dir, _out_path, _output_fps)
			if FileAccess.file_exists(_out_path) and _last_mux_ok:
				finished_path = _out_path

	if finished_path.is_empty():
		if _last_error.is_empty():
			_fail("编码失败或没有有效画面，请检查 ffmpeg 和输出目录权限。")
	else:
		print("battle_recorder: 录制完成 %d 帧 -> %s" % [frame_count, ProjectSettings.globalize_path(finished_path)])
	_finalizing = false
	recording_finished.emit(finished_path, frame_count)


func _release_sim_world_state() -> void:
	Game.release_time_scale_override(TIME_SCALE_KEY)
	_mute_gameplay_audio(false)


#========================================================
# 抓帧主循环
#========================================================

func _capture_loop() -> void:
	_last_tick_usec = Time.get_ticks_usec()
	while mode != Mode.IDLE:
		_prepare_next_capture()
		await RenderingServer.frame_post_draw
		if mode == Mode.IDLE:
			break

		var now_usec:int = Time.get_ticks_usec()
		var real_delta:float = clampf(float(now_usec - _last_tick_usec) / 1000000.0, 0.0, 0.25)
		_last_tick_usec = now_usec
		# 模拟模式下世界按 Engine.time_scale 推进，成片仍按正常速度播放。
		var game_delta:float = real_delta * Engine.time_scale if mode == Mode.SIM else real_delta
		_game_time += game_delta
		_accumulator += game_delta

		var image:Image = _grab_image()
		var guard:int = 0
		while mode != Mode.IDLE and _accumulator >= _frame_interval and guard < MAX_FRAMES_PER_DRAW:
			_accumulator -= _frame_interval
			_write_frame(image)
			guard += 1
		if _accumulator > _frame_interval * 2.0:
			# 长时间卡顿（断点 / 切后台）：丢掉积压，别在停止时一次性灌入几十张静止帧。
			_accumulator = 0.0

		if mode == Mode.SIM:
			_update_sim_progress(game_delta)
			if _sim_finished:
				break
	_finish_session()


func _prepare_next_capture() -> void:
	if not is_instance_valid(_sim_viewport):
		return
	# 共享 world_2d 的离屏视口不会自动跟随主相机，每帧手动同步画布变换。
	_sim_viewport.canvas_transform = get_viewport().get_canvas_transform()
	_sim_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _grab_image() -> Image:
	var source:Viewport = _capture_viewport if is_instance_valid(_capture_viewport) else get_viewport()
	var image:Image = source.get_texture().get_image()
	if image == null or image.is_empty():
		if is_instance_valid(_sim_viewport) and source == _sim_viewport:
			_empty_sim_grabs += 1
			if _empty_sim_grabs == 3:
				_fail("离屏抓帧失败，已停止录制以免输出遮罩画面。")
				stop()
		return null

	var use_hdr:bool = _viewport_uses_hdr(source)
	if image.is_compressed():
		image.decompress()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	# 项目开启了 rendering/viewport/hdr_2d，读回的是线性值，
	# 必须转成 sRGB 才不偏色（与引擎 MovieWriter 的处理一致）。
	if use_hdr:
		image.linear_to_srgb()
	return image


func _viewport_uses_hdr(source:Viewport) -> bool:
	if RenderingServer.has_method("viewport_is_using_hdr_2d"):
		return bool(RenderingServer.call("viewport_is_using_hdr_2d", source.get_viewport_rid()))
	return bool(ProjectSettings.get_setting("rendering/viewport/hdr_2d", false))


func _write_frame(image:Image) -> void:
	if image == null or image.is_empty():
		return
	if image.get_size() != _capture_size:
		image.resize(_capture_size.x, _capture_size.y)
	if _pipe != null and _pipe.is_open():
		if _pipe_pid > 0 and not OS.is_process_running(_pipe_pid):
			_fail("编码器意外退出，录制已停止。请检查输出目录空间及 ffmpeg。")
			stop()
			return
		_pipe.store_buffer(image.get_data())
		if _pipe.get_error() != OK:
			_fail("写入录像失败，录制已停止。请检查磁盘空间。")
			stop()
			return
		_frame_index += 1
		return
	if _png_fallback and image.save_png("%s/frame_%05d.png" % [_session_dir, _frame_index]) == OK:
		_frame_index += 1


#========================================================
# 模拟模式：离屏视口 / 遮罩 / 结束判定
#========================================================

func _setup_sim_capture_viewport() -> void:
	_free_sim_capture_viewport()
	var main:Viewport = get_viewport()
	var sub := SubViewport.new()
	sub.name = "BattleRecordCapture"
	sub.disable_3d = true
	sub.transparent_bg = false
	sub.gui_disable_input = true
	sub.size = _capture_size
	sub.use_hdr_2d = main.use_hdr_2d
	# 与主视口共享 2D 世界，但把遮罩所在的可见层剔除掉。
	sub.world_2d = main.world_2d
	sub.canvas_cull_mask = CAPTURE_ALL_MASK & ~CAPTURE_MASK_BIT
	sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(sub)
	_sim_viewport = sub
	_capture_viewport = sub


func _free_sim_capture_viewport() -> void:
	if not is_instance_valid(_sim_viewport):
		_sim_viewport = null
		return
	var dying:SubViewport = _sim_viewport
	_sim_viewport = null
	if _capture_viewport == dying:
		_capture_viewport = null
	dying.queue_free()


func _show_overlay() -> void:
	if _overlay == null:
		_overlay = CanvasLayer.new()
		_overlay.name = "BattleRecordOverlay"
		_overlay.layer = OVERLAY_LAYER
		_overlay.process_mode = Node.PROCESS_MODE_ALWAYS

		# 遮罩自身不在 Control 的 3 倍缩放下（CanvasLayer 不吃父节点变换），
		# 所以字号/按钮尺寸直接按屏幕像素给。
		_overlay_backdrop = ColorRect.new()
		_overlay_backdrop.name = "Backdrop"
		_overlay_backdrop.color = Color(0.02, 0.02, 0.03, 1.0)
		_overlay_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_overlay_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
		_overlay_backdrop.visibility_layer = CAPTURE_MASK_BIT

		_overlay_label = Label.new()
		_overlay_label.name = "Progress"
		_overlay_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_overlay_label.offset_bottom = -160.0
		_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_overlay_label.add_theme_font_size_override("font_size", 48)
		_overlay_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.9, 1.0))
		_overlay_label.visibility_layer = CAPTURE_MASK_BIT

		_overlay_abort = Button.new()
		_overlay_abort.name = "Abort"
		_overlay_abort.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_overlay_abort.offset_left = -180.0
		_overlay_abort.offset_right = 180.0
		_overlay_abort.offset_top = -150.0
		_overlay_abort.offset_bottom = -80.0
		_overlay_abort.visibility_layer = CAPTURE_MASK_BIT
		_overlay_abort.pressed.connect(_on_overlay_abort_pressed)

		_overlay_backdrop.add_child(_overlay_label)
		_overlay_backdrop.add_child(_overlay_abort)
		_overlay.add_child(_overlay_backdrop)
		add_child(_overlay)

	_update_overlay_text()
	_overlay_backdrop.show()


func _hide_overlay() -> void:
	if _overlay_backdrop != null:
		_overlay_backdrop.hide()


func _update_overlay_text() -> void:
	if _overlay_label == null:
		return
	var state_text:String = Game.ui_t("UI_RECORD_SIM_BUSY")
	if _sim_tail_left >= 0.0:
		state_text = Game.ui_t("UI_RECORD_SIM_WRAPPING")
	_overlay_label.text = "%s\n%.1fs / %d" % [state_text, _game_time, _frame_index]
	if _overlay_abort != null:
		_overlay_abort.text = Game.ui_t("UI_RECORD_ABORT")


func _on_overlay_abort_pressed() -> void:
	stop()


func _update_sim_progress(game_delta:float) -> void:
	if _sim_tail_left < 0.0:
		if _sim_match_over() or _game_time >= SIM_MAX_GAME_SECONDS:
			_sim_tail_left = SIM_TAIL_GAME_SECONDS
	else:
		_sim_tail_left -= game_delta
		if _sim_tail_left <= 0.0:
			_sim_finished = true
			return
	if _game_time - _last_progress_push >= 0.1:
		_last_progress_push = _game_time
		_update_overlay_text()


## 对局是否已经分出胜负：优先用世界自己的胜利铃，其次看存活阵营收敛到一个。
func _sim_match_over() -> bool:
	var world:Node = _world()
	if world == null or not is_instance_valid(world):
		return true
	var played:Variant = world.get("_victory_bell_played")
	if played != null and bool(played):
		return true
	# 队列换人期间可能短暂无人，不能把它误判为整场结束。
	if world.has_method("_queue_battle_mode_active") and bool(world.call("_queue_battle_mode_active")):
		return bool(world.get("_rotation_finished"))
	if _game_time < SIM_MIN_GAME_SECONDS:
		return false
	if not world.has_method("_collect_alive_victory_sides"):
		return false
	var sides:Variant = world.call("_collect_alive_victory_sides")
	if sides is Dictionary:
		var count:int = (sides as Dictionary).size()
		if count >= 2:
			_sim_saw_two_sides = true
		elif _sim_saw_two_sides and count <= 1:
			return true
	return false


## 模拟录制期间静音游戏声：整场都在 0.25 倍慢放，原声只会是一长串怪响。
func _mute_gameplay_audio(mute:bool) -> void:
	var bus:int = AudioServer.get_bus_index(GAMEPLAY_BUS_NAME)
	if bus < 0:
		return
	if mute:
		if not _audio_muted_by_us:
			_audio_bus_was_muted = AudioServer.is_bus_mute(bus)
			_audio_muted_by_us = true
		AudioServer.set_bus_mute(bus, true)
		return
	if _audio_muted_by_us:
		AudioServer.set_bus_mute(bus, _audio_bus_was_muted)
	_audio_muted_by_us = false
	_audio_bus_was_muted = false


#========================================================
# ffmpeg 定位 / 降级合成 / 进程等待
#========================================================

func _resolve_ffmpeg() -> String:
	if not _resolved_ffmpeg.is_empty():
		return _resolved_ffmpeg
	for candidate:String in FFMPEG_CANDIDATES:
		if FileAccess.file_exists(candidate):
			_resolved_ffmpeg = candidate
			return _resolved_ffmpeg
	if _ffmpeg_on_path():
		_resolved_ffmpeg = "ffmpeg"
	return _resolved_ffmpeg


func _ffmpeg_on_path() -> bool:
	var output:Array = []
	var code:int = OS.execute("ffmpeg", ["-version"], output, false, false)
	return code == 0


func _mux_png_sequence(ffmpeg:String, dir_path:String, out_path:String, fps:float) -> void:
	_last_mux_ok = false
	var pid:int = OS.create_process(ffmpeg, [
		"-y", "-hide_banner", "-loglevel", "error",
		"-framerate", "%.6f" % fps,
		"-i", ProjectSettings.globalize_path(dir_path) + "/frame_%05d.png",
		"-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
		"-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
		"-pix_fmt", "yuv420p", "-movflags", "+faststart",
		ProjectSettings.globalize_path(out_path),
	])
	if pid <= 0:
		return
	await _wait_for_process(pid, 120.0)
	_last_mux_ok = OS.get_process_exit_code(pid) == 0


func _wait_for_process(pid:int, timeout_seconds:float) -> void:
	var waited:float = 0.0
	while waited < timeout_seconds and OS.is_process_running(pid):
		# process_always=true：即使场景树处于暂停，也要能等到 ffmpeg 收尾。
		await get_tree().create_timer(0.1, true, false, true).timeout
		waited += 0.1
	if OS.is_process_running(pid):
		OS.kill(pid)
		_fail("编码器保存超时，已终止该录制进程。")


func _world() -> Node:
	var tree:SceneTree = get_tree()
	if tree == null:
		return null
	return tree.current_scene


func _exit_tree() -> void:
	if _pipe != null and _pipe.is_open():
		_pipe.close()
	if _session_active:
		_release_sim_world_state()
