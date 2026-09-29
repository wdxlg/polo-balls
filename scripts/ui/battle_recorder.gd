extends Node
## 对决录制器（顶部工具栏“录制”按钮的后端）。
##
## 两种模式都把原始像素直接喂给 ffmpeg 的 stdin 编码成 mp4，不在磁盘上留中间图片：
##   左键 LIVE —— 独立 1080×1920 / 60fps 纯对战画面 + 游戏总线音频；暂停不计入成片。
##   右键 SIM  —— 从点击瞬间的现有场景继续，以固定游戏时间步离线计算；不重打、不重建角色。
##                使用本项目独立引擎的固定帧时钟/离线音频接口，按机器能力尽快输出正常速度视频。
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

const LIVE_OUTPUT_FPS:float = 60.0
## Pace foreground rendering at the delivery rate so both encoders get CPU/GPU
## time. This is a temporary render budget, never a physics/time-scale change.
const LIVE_RENDER_MAX_FPS:int = 60
const OUTPUT_SIZE:Vector2i = Vector2i(1080, 1920)
const VIDEO_CRF:String = "14"
# NVENC still performs RGBA -> YUV preprocessing on CPU. Two auto-sized filter
# pools can starve each other/the editor; bound these separately from x264 threads.
const ENCODER_FILTER_THREADS:int = 2
const AudioCaptureScript = preload("res://scripts/ui/battle_record_audio.gd")
const EffectTooltipsScript = preload("res://scripts/ui/battle_record_effect_tooltips.gd")
const SIM_OUTPUT_FPS:float = 60.0
## 胜负分出后继续录制的秒数由设置 → 录制决定（preferences.tail_seconds，默认 5 秒）；两种模式共用。
const OUTPUT_ROOT:String = "user://recordings"
const OVERLAY_LAYER:int = 2000
## 两秒内卡顿保留帧时钟；更严重的阻塞明确停止，不静默缩短视频造成音画漂移。
const MAX_FRAMES_PER_DRAW:int = 120
const FFMPEG_CANDIDATES:Array = [
	"C:/ffmpeg/bin/ffmpeg.exe",
	"/usr/bin/ffmpeg",
	"/usr/local/bin/ffmpeg",
	"/opt/homebrew/bin/ffmpeg",
]

enum Mode { IDLE, LIVE, SIM }

signal mode_changed(mode:int)
## path 为最终产物（mp4，或降级后的 PNG 目录），frames 为写出的帧数。
signal recording_finished(path:String, frames:int)

const WriterScript = preload("res://scripts/ui/battle_record_writer.gd")
static var _nvenc_available:int = -1
var _writer:RefCounted
var _force_software:bool = false
var _video_codec:String = ""
var _physics_clock:float = 0.0
var _speed_real:float = 0.0
var _speed_physics_start:float = 0.0
var _speed_warmup:float = 1.0
var _timing_invalid:bool = false
const NamingScript = preload("res://scripts/ui/battle_record_naming.gd")
const LocaleScript = preload("res://scripts/ui/battle_record_locale.gd")
var _secondary:Node
var _locale_mirror:Node
var _effect_tooltips:Node
var _is_variant:bool = false
var _locale:String = "zh"
var _previous_secondary_image:PackedByteArray = PackedByteArray()
var last_outputs:Dictionary = {}
var _match_snapshot:Dictionary = {}
const PreferencesScript = preload("res://scripts/ui/battle_record_preferences.gd")
var preferences:RefCounted = PreferencesScript.new()
var _session_output_root:String = ""
var _last_pause_reason:String = ""
var _encoder_stderr:FileAccess
var _encoder_exit:int = -1
var _last_error:String = ""
var mode:int = Mode.IDLE
var _live_saved_max_fps:int = -1
var _live_applied_max_fps:int = -1

var _live_preparing:bool = false
var _session_active:bool = false
var _finalizing:bool = false
var _capture_viewport:Viewport = null
var _sim_viewport:SubViewport = null
var _resolve_viewport:SubViewport = null
var _readback_device:RenderingDevice = null
var _readback_texture:RID = RID()
var _readback_checked:bool = false
var _capture_vignette:ColorRect = null
var _composition:int = 0
var _follow_screen_center:Vector2 = Vector2.ZERO
var _follow_zoom:float = 1.0
var _camera_initialized:bool = false
var _overview_viewport:SubViewport = null
var _player_composition_mode:int = -1
var _player_camera:Camera2D = null
var _player_camera_center:Vector2 = Vector2.ZERO
var _player_camera_zoom:float = 1.0
var _player_camera_initialized:bool = false
var _player_composition_map:String = ""
var _last_player_capture_transform:Transform2D = Transform2D.IDENTITY
var _last_player_capture_frame:int = -1
var _player_overview_viewport:SubViewport = null
var _player_overview_layer:CanvasLayer = null
var _player_overview_root:Control = null
var _player_overview_label:Label = null
var _pause_boundary:bool = false
var _empty_sim_grabs:int = 0
var _capture_size:Vector2i = Vector2i.ZERO

var _frame_interval:float = 1.0 / LIVE_OUTPUT_FPS
var _output_fps:float = LIVE_OUTPUT_FPS
var _frame_index:int = 0
var _game_time:float = 0.0
var _accumulator:float = 0.0
var _last_tick_usec:int = 0

var _out_path:String = ""
var _video_path:String = ""
var _audio_path:String = ""
var _audio:RefCounted
var _last_capture_paused:bool = false
var _last_capture_scale:float = 1.0
var _previous_image:PackedByteArray = PackedByteArray()
var _live_pending:Array[Dictionary] = []
var _session_dir:String = ""
var _pipe:FileAccess = null
var _pipe_pid:int = 0
var _png_fallback:bool = false
var _resolved_ffmpeg:String = ""
var _last_mux_ok:bool = false

var _offline:RefCounted
var _offline_startup:bool = false
var _sim_tail_left:float = -1.0
var _sim_finished:bool = false
var _tail_seconds:float = 5.0
## 仅 LIVE：开始录制时上一局的胜负状态还残留（胜利铃已响 / 队列已结束），不能当成本局结束；
## 等世界重置（清空 / 重打 / 删人）后再次分出胜负才开始倒计时。SIM 保持原行为：已结束就直接录尾帧。
var _stale_match_over:bool = false
var _last_progress_push:float = -1.0
## Diagnostic only; set BATTLE_RECORD_PROFILE=1 to print 60-frame wall-clock breakdowns.
var _profile_enabled:bool = false
var _profile_buckets:PackedInt64Array = PackedInt64Array([0, 0, 0, 0, 0])
var _profile_frames:int = 0

var _overlay:CanvasLayer = null
var _overlay_backdrop:ColorRect = null
var _overlay_label:Label = null
var _overlay_abort:Button = null


func _ready() -> void:
	# 录制不能因为游戏暂停（esc）而停摆：遮罩、进度、中止按钮都要继续响应。
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Game autoload updates World.Camera2D at priority 0. Apply the shared framing
	# afterwards, including when no recording is active; never run on the EN variant.
	process_priority = 10
	set_process(not _is_variant)


func _process(delta:float) -> void:
	if not _is_variant: _sync_player_composition(delta)


func _wall_usec() -> int:
	return int(Time.call("get_wall_ticks_usec")) if Time.has_method("get_wall_ticks_usec") else Time.get_ticks_usec()


func _physics_process(delta:float) -> void:
	if _session_active and not _is_variant and not _capture_is_paused():
		_physics_clock += delta / maxf(Engine.time_scale, 0.000001)


func _input(event:InputEvent) -> void:
	# Latch Esc even if pause and resume both occur between two rendered frames.
	# Do not consume the event: Game remains responsible for actually pausing.
	if is_recording() and event.is_action_pressed("esc"):
		_pause_boundary = true


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


func _acquire_live_render_budget() -> void:
	if _is_variant or _live_saved_max_fps >= 0: return
	_live_saved_max_fps = Engine.max_fps
	_live_applied_max_fps = LIVE_RENDER_MAX_FPS if _live_saved_max_fps == 0 else mini(_live_saved_max_fps, LIVE_RENDER_MAX_FPS)
	Engine.max_fps = _live_applied_max_fps


func _release_live_render_budget() -> void:
	if _live_saved_max_fps < 0: return
	# Do not overwrite a deliberate runtime change made by another owner.
	if Engine.max_fps == _live_applied_max_fps: Engine.max_fps = _live_saved_max_fps
	_live_saved_max_fps = -1
	_live_applied_max_fps = -1


func start_live() -> bool:
	if mode != Mode.IDLE or is_busy():
		return _fail("录制正在进行或保存中，请稍后再试。")
	_acquire_live_render_budget()
	if not _begin_session(LIVE_OUTPUT_FPS, "live"):
		_release_live_render_budget()
		return false
	_setup_sim_capture_viewport()
	_enter_mode(Mode.LIVE)
	return true


## 右键：原地继续当前对局，固定时间步离线输出；绝不调用 rematch/reset。
func start_simulated() -> bool:
	if mode != Mode.IDLE or is_busy(): return _fail("录制正在进行或保存中，请稍后再试。")
	if Game.network_role != "offline" and Game.multiplayer.has_multiplayer_peer():
		return _fail("离线模拟仅支持本地对局；联网时请使用左键实时录制。")
	if not Game.can_local_manage_world(): return _fail("当前没有管理对局的权限。")
	if not Engine.has_method("set_recording_fixed_fps") or not AudioServer.has_method("render_offline_audio") or not Time.has_method("get_wall_ticks_usec"):
		return _fail("右键需要本项目的离线引擎。请使用“启动离线录制版.cmd”重新运行游戏，再从需要的当前状态开始模拟；原版引擎仍可左键实时录制。")
	var world:Node = _world()
	if world == null: return _fail("当前没有对局场景。")
	var actors:Array = get_tree().get_nodes_in_group("Ball")
	var queued:bool = world.has_method("_queue_battle_mode_active") and world._queue_battle_mode_active() and not world._rotation_finished
	if actors.is_empty() and not queued: return _fail("当前没有可继续的对局。请先放置角色；不会重新载入上一局布阵。")
	_offline = load("res://scripts/ui/battle_record_offline.gd").new()
	if not _offline.begin(self):
		var reason:String = _offline.error
		_offline = null
		return _fail(reason)
	_offline_startup = true
	if not _begin_session(SIM_OUTPUT_FPS, "sim"):
		_release_sim_world_state()
		return false
	_setup_sim_capture_viewport()
	_show_overlay()
	_offline.hide_preview()
	_enter_mode(Mode.SIM)
	return true


## 停止当前录制（两种模式通用）。真正的收尾在抓帧循环退出后执行。
func stop() -> void:
	if mode == Mode.IDLE:
		return
	if mode == Mode.SIM: Game.stop_game(false)
	mode = Mode.IDLE
	mode_changed.emit(mode)
	# 正常路径由 _capture_loop 收尾；树已经不再绘制时这里兜底，避免状态卡死。
	if not _session_active:
		_finish_session()


func get_output_directory() -> String:
	return preferences.get_directory()


func set_output_directory(path:String) -> bool:
	if is_busy(): return _fail("请先停止录制并等待保存完成，再修改目录。")
	if not preferences.save_directory(path): return _fail(preferences.last_error)
	_last_error = ""
	return true


func get_tail_seconds() -> float:
	return preferences.get_tail_seconds()

func get_composition() -> int:
	return preferences.get_composition()

func set_composition(value:int) -> bool:
	if is_busy(): return _fail("请先停止录制并等待保存完成，再修改取景。")
	if not preferences.save_composition(value): return _fail(preferences.last_error)
	_player_camera_initialized = false
	_player_composition_mode = -1
	_last_error = ""
	return true


func set_tail_seconds(seconds:float) -> bool:
	if is_busy(): return _fail("请先停止录制并等待保存完成，再修改续录时间。")
	if not preferences.save_tail_seconds(seconds): return _fail(preferences.last_error)
	_last_error = ""
	return true


func is_preparing() -> bool:
	return _live_preparing


func get_pause_reason() -> String:
	if _live_preparing: return "正在准备录制画面，准备完成后开始音画计时。"
	if get_tree().paused or Game.now_stop_state: return "对局暂停中，请按 Esc 继续。"
	if Game.stop_background.is_visible_in_tree() or Game.stop_text.is_visible_in_tree():
		return "暂停画面或恢复倒计时中，请等待对局继续。"
	if Engine.time_scale <= 0.000001: return "游戏速度为零，请调高速度。"
	var world:Node = _world()
	var team:CanvasItem = world.get_node_or_null("CanvasLayer/Control/Team") if world != null else null
	if team != null and team.is_visible_in_tree(): return "队伍布阵界面打开，请收起布阵界面。"
	return ""


func _enter_mode(next_mode:int) -> void:
	mode = next_mode
	_session_active = true
	_live_preparing = next_mode == Mode.LIVE
	_pause_boundary = false
	if _audio.effect != null: _audio.effect.clear_buffer()
	_last_capture_paused = _capture_is_paused()
	_last_capture_scale = Engine.time_scale if mode == Mode.SIM else 1.0
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
	var location:Dictionary = preferences.validate(get_output_directory())
	if not location.ok: return _fail("录制目录不可用：" + location.error + " 可在设置 → 录制中更改。")
	_session_output_root = location.directory
	_encoder_stderr = null
	_encoder_exit = -1
	_last_pause_reason = ""
	_capture_size = OUTPUT_SIZE
	_frame_index = 0
	_physics_clock = 0.0
	_speed_real = 0.0
	_speed_physics_start = 0.0
	_speed_warmup = 1.0
	_timing_invalid = false
	last_outputs.clear()
	_previous_secondary_image = PackedByteArray()
	_previous_image = PackedByteArray()
	_live_pending.clear()
	_game_time = 0.0
	_accumulator = 0.0
	_last_progress_push = -1.0
	_sim_tail_left = -1.0
	_sim_finished = false
	_tail_seconds = preferences.get_tail_seconds()
	_composition = preferences.get_composition()
	_camera_initialized = false
	_stale_match_over = tag == "live" and _match_over_now()
	_empty_sim_grabs = 0
	_pipe = null
	_pipe_pid = 0
	_png_fallback = false
	_session_dir = ""

	var stamp:String = Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_") + "_%d" % _wall_usec()
	_match_snapshot = NamingScript.snapshot(_world(), false)
	var zh_name:String = NamingScript.filename(_match_snapshot, "zh", stamp, _session_output_root)
	var en_name:String = NamingScript.filename(_match_snapshot, "en", stamp, _session_output_root)
	if zh_name.is_empty() or en_name.is_empty(): return _fail("保存目录路径过长，请选择更短的录制目录。")
	_out_path = _session_output_root.path_join(zh_name)
	_video_path = _out_path.get_basename() + ".video.mp4"
	_audio_path = _out_path.get_basename() + ".audio.f32"
	_secondary = get_script().new()
	_secondary._is_variant = true
	_secondary._locale = "en"
	_secondary.name = "EnglishRecording"
	add_child(_secondary)
	_secondary._force_software = _force_software
	_secondary._match_snapshot = _match_snapshot
	_secondary._capture_size = _capture_size
	_secondary._composition = _composition
	_secondary._output_fps = _output_fps
	_secondary._out_path = _session_output_root.path_join(en_name)
	_secondary._video_path = _secondary._out_path.get_basename() + ".video.mp4"
	_secondary._audio_path = _audio_path
	_audio = AudioCaptureScript.new()
	if not _audio.begin(_audio_path, tag == "sim"):
		_audio.finish()
		_secondary.queue_free()
		_secondary = null
		return _fail(_audio.error)

	_secondary._audio = _audio
	if _open_video_output() and _secondary._open_video_output(): return true
	# Clean up partial startup without leaving an encoder or audio tap behind.
	_session_active = true
	_fail("无法建立中英文双语编码输出，请检查编码器和目录空间。")
	_finish_session()
	return false


func _open_video_output() -> bool:
	if _open_pipe_encoder(): return true
	_session_dir = _out_path.get_basename() + "_frames"
	if DirAccess.make_dir_recursive_absolute(_session_dir) == OK:
		_png_fallback = true
		return true
	return false


func _open_pipe_encoder() -> bool:
	if not OS.has_method("execute_with_pipe"):
		return false
	var ffmpeg:String = _resolve_ffmpeg()
	if ffmpeg.is_empty():
		return false

	var args:Array = [
		"-y", "-hide_banner", "-loglevel", "error",
		"-filter_threads", str(ENCODER_FILTER_THREADS),
		"-f", "rawvideo", "-pix_fmt", "rgba",
		"-s", "%dx%d" % [_capture_size.x, _capture_size.y],
		"-r", "%.6f" % _output_fps,
		"-i", "-",
	]
	args.append_array([
		"-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2:out_color_matrix=bt709:out_range=tv",
		"-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709",
	])
	args.append("-an")
	args.append("-c:v")
	_video_codec = _select_video_codec(ffmpeg)
	args.append(_video_codec)
	if _video_codec == "h264_nvenc":
		args.append_array(["-preset", "p4", "-tune", "ull", "-zerolatency", "1", "-delay", "0", "-rc", "constqp", "-qp", "16", "-bf", "0"])
	else:
		# Bound CPU contention; two veryfast encoders used to starve game physics.
		args.append_array(["-preset", "ultrafast", "-threads", "2", "-crf", VIDEO_CRF])
	args.append("-pix_fmt")
	args.append("yuv420p")
	args.append("-movflags")
	args.append("+faststart")
	args.append_array(["-metadata", "title=" + NamingScript.title(_match_snapshot, _locale), "-metadata:s:v:0", "language=" + ("zho" if _locale == "zh" else "eng")])
	args.append(ProjectSettings.globalize_path(_video_path))

	var result:Variant = OS.execute_with_pipe(ffmpeg, args, true)
	if typeof(result) != TYPE_DICTIONARY:
		push_warning("battle_recorder: 启动 ffmpeg 失败（返回 %s）。" % str(result))
		return false
	var handles:Dictionary = result as Dictionary
	var stdio:Variant = handles.get("stdio")
	if not (stdio is FileAccess) or not (stdio as FileAccess).is_open():
		push_warning("battle_recorder: ffmpeg 管道不可写，回退到 PNG 序列。")
		return false
	_encoder_stderr = handles.get("stderr") as FileAccess
	_pipe = stdio as FileAccess
	_pipe_pid = int(handles.get("pid", 0))
	_writer = WriterScript.new()
	if not _writer.begin(_pipe):
		_pipe.close()
		OS.kill(_pipe_pid)
		_pipe = null
		_writer = null
		return false
	return true


func _select_video_codec(ffmpeg:String) -> String:
	if _force_software: return "libx264"
	if _nvenc_available < 0:
		var output:Array = []
		_nvenc_available = 1 if OS.execute(ffmpeg, ["-hide_banner", "-loglevel", "error",
			"-f", "lavfi", "-i", "color=s=1080x1920:r=60", "-frames:v", "1", "-an",
			"-c:v", "h264_nvenc", "-preset", "p4", "-f", "null", "-"], output, true) == 0 else 0
	return "h264_nvenc" if _nvenc_available == 1 else "libx264"


func _drain_writer() -> void:
	if _writer == null: return
	_writer.close_when_empty()
	var deadline:int = int(_wall_usec() / 1000) + 20000
	while _writer.is_running() and int(_wall_usec() / 1000) < deadline:
		await get_tree().create_timer(0.02, true, false, true).timeout
	if _writer.is_running():
		if OS.is_process_running(_pipe_pid): OS.kill(_pipe_pid)
		_fail("编码器收尾超时，已停止。")
	_writer.join()
	if not _writer.get_error().is_empty(): _fail(_writer.get_error())
	_writer = null


func _finish_session() -> void:
	if not _session_active: return
	_session_active = false
	_finalizing = true
	if mode != Mode.IDLE:
		mode = Mode.IDLE
		mode_changed.emit(mode)
	if _audio != null: _audio.finish()
	_release_sim_world_state()
	_free_sim_capture_viewport()
	if is_instance_valid(_locale_mirror):
		_locale_mirror.finish()
		_locale_mirror.queue_free()
	_locale_mirror = null
	_hide_overlay()
	if is_instance_valid(_secondary):
		# A rejected enqueue must not leave language variants with different lengths.
		var common_frames:int = mini(_frame_index, _secondary._frame_index)
		_frame_index = common_frames
		_secondary._frame_index = common_frames
		_secondary._timing_invalid = _timing_invalid
	var path:String = await _finish_video_output()
	if not path.is_empty(): last_outputs["zh"] = path
	if is_instance_valid(_secondary):
		var english:String = await _secondary._finish_video_output()
		if not english.is_empty(): last_outputs["en"] = english
		if not _secondary._last_error.is_empty():
			_fail((_last_error + "\n" if not _last_error.is_empty() else "") + "英文输出：" + _secondary._last_error)
		_secondary.queue_free()
	_secondary = null
	if _frame_index == 0 or (last_outputs.size() == 2 and str(last_outputs.zh).ends_with(".mp4") and str(last_outputs.en).ends_with(".mp4")):
		DirAccess.remove_absolute(_audio_path)
	_previous_image = PackedByteArray()
	_previous_secondary_image = PackedByteArray()
	_live_pending.clear()
	_release_live_render_budget()
	_finalizing = false
	recording_finished.emit(path, _frame_index)


func _finish_video_output() -> String:
	var finished_path:String = ""
	var frame_count:int = _frame_index

	if _pipe != null:
		await _drain_writer()
		if _pipe.is_open():
			_pipe.flush()
			_pipe.close()
		_pipe = null
		if _pipe_pid > 0:
			await _wait_for_process(_pipe_pid, 20.0)
		_encoder_exit = OS.get_process_exit_code(_pipe_pid)
		if frame_count > 0 and FileAccess.file_exists(_video_path) and _encoder_exit == 0:
			finished_path = _video_path
		_pipe_pid = 0
	elif _png_fallback and frame_count > 0:
		finished_path = _session_dir
		var ffmpeg:String = _resolve_ffmpeg()
		if not ffmpeg.is_empty():
			await _mux_png_sequence(ffmpeg, _session_dir, _video_path, _output_fps)
			if FileAccess.file_exists(_video_path) and _last_mux_ok:
				finished_path = _video_path

	if _timing_invalid:
		if _encoder_stderr != null and _encoder_stderr.is_open(): _encoder_stderr.close()
		_encoder_stderr = null
		return "" # Keep raw materials, do not advertise a slowed final video.
	if finished_path == _video_path:
		if await _mux_game_audio():
			finished_path = _out_path
			DirAccess.remove_absolute(_video_path)
		else:
			finished_path = ""
			_fail("音画合成失败。原始视频和音频已保留在输出目录，可恢复。")
	if finished_path.is_empty():
		if _last_error.is_empty():
			if frame_count == 0:
				_fail("没有录到有效画面：" + (_last_pause_reason if not _last_pause_reason.is_empty() else "开始后尚未生成首帧就停止了。") + " 本次未生成视频，并非目录权限或编码器故障。")
			else:
				var detail:String = ""
				if _encoder_stderr != null and _encoder_stderr.is_open():
					detail = _encoder_stderr.get_buffer(mini(8192, int(_encoder_stderr.get_length()))).get_string_from_utf8().strip_edges()
				_fail("编码器未正常完成（退出码 %d，已写入 %d 帧）。%s" % [_encoder_exit, frame_count, detail])
	else:
		print("battle_recorder: 录制完成 %d 帧 -> %s" % [frame_count, ProjectSettings.globalize_path(finished_path)])
	if _encoder_stderr != null and _encoder_stderr.is_open(): _encoder_stderr.close()
	_encoder_stderr = null
	if frame_count == 0:
		# Only remove this session's empty temporary files, never earlier user recordings.
		DirAccess.remove_absolute(_video_path)
	return finished_path


func _release_sim_world_state(keep_result:bool = true) -> void:
	if _offline != null:
		_offline.finish(keep_result)
		_offline = null
	_offline_startup = false


#========================================================
# 抓帧主循环
#========================================================

func _capture_is_paused() -> bool:
	return not get_pause_reason().is_empty()

func _prime_live_capture() -> bool:
	# D3D12's first bilingual viewport draw/readback may compile pipelines for
	# seconds. This is preparation, not recorded time: otherwise the first draw
	# fabricates ~100 repeated frames and overwhelms the bounded writer queues.
	_prepare_next_capture()
	await RenderingServer.frame_post_draw
	if mode != Mode.LIVE: return false # Stop during preparation remains valid.
	var zh:PackedByteArray = _grab_capture_rgba()
	var en:PackedByteArray = _secondary._grab_capture_rgba()
	var expected:int = _capture_size.x * _capture_size.y * 4
	if zh.size() != expected or en.size() != expected:
		return _fail("录制画面准备失败：中英文首帧不完整，本次未开始正式录制。")
	# Drop preparation audio too; audio, video and the end-tail share the new
	# epoch. Never reset these clocks or discard audio after recording starts.
	_audio.drain(1.0, true)
	if not _audio.error.is_empty(): return _fail(_audio.error)
	return true


func _capture_loop() -> void:
	if mode == Mode.SIM:
		_offline_capture_loop()
		return
	var ready:bool = await _prime_live_capture()
	_live_preparing = false
	if not ready:
		stop()
		_finish_session()
		return
	_last_capture_paused = _capture_is_paused()
	_last_capture_scale = 1.0
	_pause_boundary = false
	_speed_real = 0.0
	_speed_physics_start = _physics_clock
	_speed_warmup = 1.0
	_profile_enabled = OS.get_environment("BATTLE_RECORD_PROFILE") == "1"
	_profile_buckets.fill(0)
	_profile_frames = 0
	_last_tick_usec = _wall_usec()
	while mode != Mode.IDLE:
		var draw_begin:int = _wall_usec() if _profile_enabled else 0
		var capture_requested:bool = not _capture_is_paused()
		if capture_requested: _prepare_next_capture()
		await RenderingServer.frame_post_draw
		var draw_end:int = _wall_usec() if _profile_enabled else 0
		_flush_live_pending()
		if mode == Mode.IDLE: break
		for output:Node in [self, _secondary]:
			if output._writer != null and not output._writer.get_error().is_empty():
				_fail(output._writer.get_error())
				stop()
		if mode == Mode.IDLE: break
		var now_usec:int = _wall_usec()
		var real_delta:float = float(now_usec - _last_tick_usec) / 1000000.0
		_last_tick_usec = now_usec
		var paused_now:bool = _capture_is_paused()
		if paused_now: _last_pause_reason = get_pause_reason()
		var scale_now:float = Engine.time_scale if mode == Mode.SIM else 1.0
		var skip:bool = not capture_requested or paused_now or _last_capture_paused or _pause_boundary
		_pause_boundary = false
		_audio.drain(_last_capture_scale, skip)
		_last_capture_paused = paused_now
		_last_capture_scale = scale_now
		if not _audio.error.is_empty():
			_fail(_audio.error)
			stop()
			break
		if skip:
			if not _live_pending.is_empty(): await _drain_live_pending()
			_speed_real = 0.0
			_speed_physics_start = _physics_clock
			_previous_image = PackedByteArray()
			_previous_secondary_image = PackedByteArray()
			continue
		# Physics is the independent speed witness, not video FPS/container duration.
		# Never silently deliver a long slow-motion video under sustained overload.
		if _speed_warmup > 0.0:
			_speed_warmup -= real_delta
			_speed_physics_start = _physics_clock
		else:
			_speed_real += real_delta
			if _speed_real >= 2.0:
				var progress:float = (_physics_clock - _speed_physics_start) / _speed_real
				_speed_real = 0.0
				_speed_physics_start = _physics_clock
				if progress < 0.9:
					_timing_invalid = true
					_fail("当前负载已使对战明显减速，录制已停止且未生成正式成片。临时材料已保留，请减少人物或特效后重试。")
					stop()
					break
		var game_delta:float = real_delta * scale_now
		_game_time += game_delta
		_accumulator += game_delta
		var wanted:int = int(_accumulator / _frame_interval)
		if wanted > MAX_FRAMES_PER_DRAW:
			_fail("录制遇到超过两秒的渲染阻塞，已停止，避免产生音画不同步的视频。")
			stop()
			break
		if wanted > 0:
			var read_begin:int = _wall_usec() if _profile_enabled else 0
			# Preparation validated both RD textures; unsupported formats keep the
			# original synchronous path. Ready textures use asynchronous readback.
			var async_ready:bool = _writer != null and _secondary._writer != null and _readback_texture.is_valid() and _secondary._readback_texture.is_valid() and _readback_device.has_method("texture_get_data_async")
			if async_ready:
				if _live_pending.size() >= 8:
					_timing_invalid = true
					_fail("异步读回积压，录制已停止且未生成正式成片。")
					stop()
					break
				var record:Dictionary = {"zh":PackedByteArray(), "en":PackedByteArray(), "wanted":wanted}
				_live_pending.append(record)
				var zh_result:Error = _readback_device.texture_get_data_async(_readback_texture, 0, _on_live_readback.bind(record, "zh"))
				var en_result:Error = _secondary._readback_device.texture_get_data_async(_secondary._readback_texture, 0, _on_live_readback.bind(record, "en"))
				if zh_result != OK or en_result != OK:
					_timing_invalid = true
					_fail("异步读回请求失败，录制已停止且未生成正式成片。")
					stop()
					break
				# Expose the captured frame count now, not when callbacks return during
				# a later paused frame. The writer enqueues these reserved frames later.
				_frame_index += wanted
				_secondary._frame_index += wanted
			else:
				var image:PackedByteArray = _grab_capture_rgba()
				var english:PackedByteArray = _secondary._grab_capture_rgba()
				if image.size() != _capture_size.x * _capture_size.y * 4 or english.size() != _capture_size.x * _capture_size.y * 4: continue
				_write_live_pair(image, english, wanted)
			var read_end:int = _wall_usec() if _profile_enabled else 0
			_accumulator -= wanted * _frame_interval
			if _profile_enabled:
				var write_end:int = _wall_usec()
				_profile_buckets[0] += draw_end - draw_begin
				_profile_buckets[1] += read_end - read_begin
				_profile_buckets[2] += write_end - read_end
				_profile_frames += 1
				if _profile_frames == 60:
					print("RECORD_LIVE_PROFILE wall_ms_per_capture scene_draw=%.2f readback=%.2f enqueue=%.2f; codec=%s; queue_zh=%d; queue_en=%d" % [float(_profile_buckets[0]) / 60000.0, float(_profile_buckets[1]) / 60000.0, float(_profile_buckets[2]) / 60000.0, _video_codec, _writer.peak_bytes if _writer != null else 0, _secondary._writer.peak_bytes if _secondary._writer != null else 0])
					_profile_buckets.fill(0)
					_profile_frames = 0
		if mode == Mode.SIM:
			_update_sim_progress(game_delta)
			if _sim_finished: break
		elif mode == Mode.LIVE:
			# 实时录制同样在胜负分出后再录 N 秒游戏时间（暂停不计），然后自动停止收尾。
			_update_match_end_tail(game_delta)
			if _sim_finished:
				stop()
				break
	await _drain_live_pending()
	_finish_session()


func _on_live_readback(data:PackedByteArray, record:Dictionary, locale:String) -> void:
	# Both callbacks carry the texture's pixels at request time, not completion time.
	record[locale] = data


func _flush_live_pending() -> void:
	while not _live_pending.is_empty():
		var record:Dictionary = _live_pending[0]
		if (record.zh as PackedByteArray).is_empty() or (record.en as PackedByteArray).is_empty(): break
		_live_pending.pop_front()
		if _timing_invalid: continue
		if record.zh.size() != _capture_size.x * _capture_size.y * 4 or record.en.size() != _capture_size.x * _capture_size.y * 4:
			_timing_invalid = true
			_fail("异步读回帧大小错误，录制已停止且未生成正式成片。")
			stop()
			break
		_write_live_pair(record.zh, record.en, record.wanted, true)


func _write_live_pair(image:PackedByteArray, english:PackedByteArray, wanted:int, reserved:bool = false) -> void:
	# Repeats and both locale queues must preserve capture order and wall timing.
	var repeat_old:int = wanted - 1 if not _previous_image.is_empty() else 0
	if repeat_old > 0:
		_write_capture_rgba(_previous_image, repeat_old, not reserved)
		_secondary._write_capture_rgba(_previous_secondary_image, repeat_old, not reserved)
	_write_capture_rgba(image, wanted - repeat_old, not reserved)
	_secondary._write_capture_rgba(english, wanted - repeat_old, not reserved)
	if not _secondary._last_error.is_empty():
		_fail("英文编码失败：" + _secondary._last_error)
		stop()
	_previous_image = image
	_previous_secondary_image = english


func _drain_live_pending() -> void:
	var deadline:int = _wall_usec() + 1000000
	while not _live_pending.is_empty() and _wall_usec() < deadline:
		await RenderingServer.frame_post_draw
		_flush_live_pending()
	if not _live_pending.is_empty():
		_timing_invalid = true
		_fail("异步读回收尾超时，录制已停止且未生成正式成片。")
		_live_pending.clear()


func _offline_capture_loop() -> void:
	_profile_enabled = OS.get_environment("BATTLE_RECORD_PROFILE") == "1"
	_profile_buckets.fill(0)
	_profile_frames = 0
	while mode == Mode.SIM:
		var t0:int = _wall_usec() if _profile_enabled else 0
		var initial:bool = _offline_startup
		var requested:bool = initial or not _capture_is_paused()
		if requested: _prepare_next_capture()
		await RenderingServer.frame_post_draw
		var t1:int = _wall_usec() if _profile_enabled else 0
		if mode != Mode.SIM: break
		if not initial and (not requested or _capture_is_paused() or _pause_boundary):
			_pause_boundary = false
			continue
		var image:PackedByteArray = _grab_capture_rgba()
		var english:PackedByteArray = _secondary._grab_capture_rgba()
		var t2:int = _wall_usec() if _profile_enabled else 0
		if image.size() != _capture_size.x * _capture_size.y * 4 or english.size() != _capture_size.x * _capture_size.y * 4:
			_fail("离线帧读取失败，已停止；不会跳过物理过程后假装正常输出。")
			stop()
			break
		# OFFLINE may wait for encoding: the engine clock cannot advance during this wait.
		# LIVE never waits here. Handle window/abort events while applying backpressure.
		if not _wait_offline_capacity(): break
		var t3:int = _wall_usec() if _profile_enabled else 0
		_write_capture_rgba(image)
		_secondary._write_capture_rgba(english)
		var t4:int = _wall_usec() if _profile_enabled else 0
		if mode != Mode.SIM or not _secondary._last_error.is_empty():
			if not _secondary._last_error.is_empty(): _fail(_secondary._last_error)
			stop()
			break
		if initial:
			_offline.resume_current_world()
			_offline_startup = false
		_audio.render_offline(_frame_index, _output_fps)
		if _profile_enabled:
			var t5:int = _wall_usec()
			_profile_buckets[0] += t1 - t0
			_profile_buckets[1] += t2 - t1
			_profile_buckets[2] += t3 - t2
			_profile_buckets[3] += t4 - t3
			_profile_buckets[4] += t5 - t4
			_profile_frames += 1
			if _profile_frames == 60:
				print("RECORD_PROFILE wall_ms_per_frame scene_draw=%.2f readback=%.2f queue_wait=%.2f enqueue=%.2f audio=%.2f; codec=%s; queue_zh=%d; queue_en=%d" % [float(_profile_buckets[0]) / 60000.0, float(_profile_buckets[1]) / 60000.0, float(_profile_buckets[2]) / 60000.0, float(_profile_buckets[3]) / 60000.0, float(_profile_buckets[4]) / 60000.0, _video_codec, _writer.peak_bytes if _writer != null else 0, _secondary._writer.peak_bytes if _secondary._writer != null else 0])
				_profile_buckets.fill(0)
				_profile_frames = 0
		if not _audio.error.is_empty():
			_fail(_audio.error)
			stop()
			break
		_game_time = _frame_index / _output_fps
		_update_sim_progress(_frame_interval)
		if _sim_finished: break
	_finish_session()


func _wait_offline_capacity() -> bool:
	var deadline:int = int(_wall_usec() / 1000) + 20000
	while mode == Mode.SIM:
		var ready:bool = true
		for output:Node in [self, _secondary]:
			if output._writer == null: continue # PNG fallback is synchronous.
			var message:String = output._writer.get_error()
			if not message.is_empty():
				_fail(message)
				stop()
				return false
			ready = ready and output._writer.can_accept(_capture_size.x * _capture_size.y * 4)
		if ready: return true
		if int(_wall_usec() / 1000) >= deadline:
			_fail("离线编码器超过 20 秒无进展，已停止并保留已计算片段。")
			stop()
			return false
		DisplayServer.process_events()
		OS.delay_usec(1000)
	return false


func _prepare_next_capture() -> void:
	if not is_instance_valid(_sim_viewport):
		return
	# 共享 world_2d 的离屏视口不会自动跟随主相机，每帧手动同步画布变换。
	var main:Viewport = get_viewport()
	var logical_size:Vector2 = main.get_visible_rect().size
	var scale_to_output := Transform2D.IDENTITY.scaled(Vector2(_capture_size) / logical_size)
	var base:Transform2D = scale_to_output * main.global_canvas_transform * main.get_canvas_transform()
	if not _is_variant and is_instance_valid(_secondary):
		_secondary._player_composition_mode = _player_composition_mode
		_secondary._player_camera = _player_camera
	# A World battle now uses the same live Camera2D for play and both video languages.
	# Do not layer the old private tracking zoom on top of the already-composed view.
	var shared_view:bool = _player_composition_mode == _composition and is_instance_valid(_player_camera) and main.get_camera_2d() == _player_camera
	if not _is_variant:
		if not shared_view:
			_update_recording_camera(base)
			if is_instance_valid(_secondary):
				_secondary._follow_screen_center = _follow_screen_center
				_secondary._follow_zoom = _follow_zoom
				_secondary._camera_initialized = _camera_initialized
	if shared_view:
		_last_player_capture_transform = base
		_last_player_capture_frame = Engine.get_process_frames()
		_sim_viewport.canvas_transform = base
	else:
		var anchor:Vector2 = Vector2(_capture_size) * 0.5
		var camera := Transform2D.IDENTITY.scaled(Vector2.ONE * _follow_zoom)
		camera.origin = anchor - _follow_screen_center * _follow_zoom
		_sim_viewport.canvas_transform = camera * base
	if is_instance_valid(_overview_viewport):
		_update_overview_camera()
		_overview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_sync_capture_vignette()
	_sim_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if is_instance_valid(_resolve_viewport):
		_resolve_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if is_instance_valid(_secondary): _secondary._prepare_next_capture()


# For non-World / test-only recording scenes, preserve the original standalone
# framing. In World battles the player's Camera2D owns the framing instead.
func _sync_player_composition(delta:float) -> void:
	var world:Node = _world()
	var main:Viewport = get_viewport()
	if world == null or not world.is_ancestor_of(self) or not world.has_method("_current_map_node"):
		_player_composition_mode = -1
		_clear_player_overview()
		return
	var camera:Camera2D = world.get_node_or_null("Camera2D") as Camera2D
	if camera == null or main.get_camera_2d() != camera:
		_player_composition_mode = -1
		_clear_player_overview()
		return
	var rect:Rect2 = _map_visual_rect()
	var view:Vector2 = main.get_visible_rect().size
	if not rect.has_area() or view.x < 16.0 or view.y < 16.0:
		_player_composition_mode = -1
		_clear_player_overview()
		return
	var composition:int = preferences.get_composition()
	var map_name:String = str(world.get("now_choose_map"))
	# Story-driven camera locks and direct player control take priority over the
	# automatic composition. The video still mirrors the actual player view.
	if bool(world.get("_dead_save_force_non_follow_camera")) or (Game.should_follow_controlled_character() and Game.get_local_controlled_character() is Node2D):
		_player_camera_initialized = false
		_player_camera = camera
		_player_composition_mode = composition
		_sync_player_overview(composition, rect, view)
		return
	# Fit the map/actors at the stable manual zoom. Fitting against the effective
	# zoom would divide by the hit/cinematic multiplier and cancel its push-in.
	var base_zoom:float = maxf(float(world._base_camera_zoom_value()) * float(world.toolbar_zoom_multiplier), 0.001)
	var transient_zoom:float = maxf(float(world.get_effective_camera_zoom()), 0.001) / base_zoom
	var full_factor:float = clampf(minf(view.x * 0.87 / maxf(rect.size.x * base_zoom, 1.0), view.y * 0.55 / maxf(rect.size.y * base_zoom, 1.0)), 0.85, 1.55)
	var target_center:Vector2 = rect.get_center()
	var target_zoom:float = base_zoom * full_factor
	if composition != PreferencesScript.FULL:
		var bounds:Rect2 = Rect2()
		var found:bool = false
		for actor:Node in get_tree().get_nodes_in_group("Ball"):
			if not is_instance_valid(actor) or not actor is Node2D or not world.is_ancestor_of(actor) or not actor.is_inside_tree() or not actor.visible: continue
			var point:Vector2 = (actor as Node2D).global_position
			if not found:
				bounds = Rect2(point, Vector2.ZERO)
				found = true
			else:
				bounds = bounds.expand(point)
		if found:
			target_center = bounds.get_center()
			var span_x:float = maxf(bounds.size.x * base_zoom, 225.0 * view.x / 1080.0)
			var span_y:float = maxf(bounds.size.y * base_zoom, 245.0 * view.y / 1920.0)
			var follow_factor:float = minf(view.x * 0.62 / span_x, view.y * 0.44 / span_y)
			target_zoom = base_zoom * clampf(follow_factor, full_factor, 2.9 if composition == PreferencesScript.FOLLOW else 2.5)
	if not _player_camera_initialized or _player_camera != camera or _player_composition_mode != composition or _player_composition_map != map_name:
		_player_camera_center = target_center
		_player_camera_zoom = target_zoom
		_player_camera_initialized = true
	else:
		var alpha:float = 1.0 - exp(-5.0 * clampf(delta, 0.0, 0.1))
		_player_camera_center = _player_camera_center.lerp(target_center, alpha)
		_player_camera_zoom = lerpf(_player_camera_zoom, target_zoom, alpha)
	var offset:Variant = world.get("mouse_offset")
	var manual_offset:Vector2 = offset if offset is Vector2 else Vector2.ZERO
	var composed_center:Vector2 = _player_camera_center + manual_offset
	# Existing cinematic and hit reactions keep their center override.
	var focus:float = maxf(float(world.get("_cinematic_focus_weight")), float(world.get("_damage_focus_weight")))
	if focus > 0.0: composed_center = composed_center.lerp(camera.global_position, clampf(focus, 0.0, 1.0))
	# Apply short hit and cinematic zoom *after* smoothing the stable framing;
	# this camera is shared by the player and both recording viewports.
	camera.zoom = Vector2.ONE * (_player_camera_zoom * transient_zoom)
	camera.global_position = composed_center
	camera.force_update_scroll()
	_player_camera = camera
	_player_composition_mode = composition
	_player_composition_map = map_name
	_sync_player_overview(composition, rect, view)


func _map_visual_rect() -> Rect2:
	var world:Node = _world()
	if world != null and world.has_method("_current_map_node") and world.has_method("return_map_visual_rect"):
		var map_node:Node = world._current_map_node()
		if map_node != null: return world.return_map_visual_rect(map_node)
	return Rect2()

func _update_recording_camera(base:Transform2D) -> void:
	var anchor:Vector2 = Vector2(_capture_size) * 0.5
	var map_rect:Rect2 = _map_visual_rect()
	var map_center:Vector2 = base * map_rect.get_center() if map_rect.has_area() else anchor
	var map_span:Vector2 = base.basis_xform(map_rect.size).abs() if map_rect.has_area() else Vector2(_capture_size) * 0.75
	var full_zoom:float = clampf(minf(float(_capture_size.x) * 0.87 / maxf(map_span.x, 1.0), float(_capture_size.y) * 0.55 / maxf(map_span.y, 1.0)), 0.85, 1.55)
	var target_center:Vector2 = map_center
	var target_zoom:float = full_zoom
	if _composition != PreferencesScript.FULL:
		var bounds:Rect2 = Rect2()
		var found:bool = false
		for actor:Node in get_tree().get_nodes_in_group("Ball"):
			if not is_instance_valid(actor) or not actor is Node2D or not actor.is_inside_tree() or not actor.visible: continue
			var point:Vector2 = base * (actor as Node2D).global_position
			if not found:
				bounds = Rect2(point, Vector2.ZERO)
				found = true
			else:
				bounds = bounds.expand(point)
		if found:
			target_center = bounds.get_center()
			# Let a pair occupy ~62% of the frame, but ease back as they separate.
			var fighting_zoom:float = minf(float(_capture_size.x) * 0.62 / maxf(bounds.size.x, 225.0), float(_capture_size.y) * 0.44 / maxf(bounds.size.y, 245.0))
			target_zoom = clampf(fighting_zoom, full_zoom, 2.9 if _composition == PreferencesScript.FOLLOW else 2.5)
	if not _camera_initialized:
		_follow_screen_center = target_center
		_follow_zoom = target_zoom
		_camera_initialized = true
	else:
		# Fixed-step smoothing works for both deterministic SIM and live captures.
		var alpha:float = 1.0 - exp(-5.0 / _output_fps)
		_follow_screen_center = _follow_screen_center.lerp(target_center, alpha)
		_follow_zoom = lerpf(_follow_zoom, target_zoom, alpha)

func _update_overview_camera() -> void:
	var rect:Rect2 = _map_visual_rect()
	if not rect.has_area(): return
	var size:Vector2 = Vector2(_overview_viewport.size)
	var zoom:float = minf(size.x * 0.92 / rect.size.x, size.y * 0.92 / rect.size.y)
	var xform := Transform2D.IDENTITY.scaled(Vector2.ONE * zoom)
	xform.origin = size * 0.5 - rect.get_center() * zoom
	_overview_viewport.canvas_transform = xform


func _clear_player_overview() -> void:
	if is_instance_valid(_player_overview_layer): _player_overview_layer.queue_free()
	if is_instance_valid(_player_overview_viewport): _player_overview_viewport.queue_free()
	_player_overview_layer = null
	_player_overview_viewport = null
	_player_overview_root = null
	_player_overview_label = null


func _sync_player_overview(composition:int, rect:Rect2, view:Vector2) -> void:
	if composition != PreferencesScript.FOLLOW_OVERVIEW or DisplayServer.get_name() == "headless":
		_clear_player_overview()
		return
	if not is_instance_valid(_player_overview_viewport):
		var overview := SubViewport.new()
		overview.name = "PlayerBattleOverview"
		overview.disable_3d = true
		overview.gui_disable_input = true
		overview.size = Vector2i(400, 400)
		overview.world_2d = get_viewport().world_2d
		overview.canvas_cull_mask = 1 # Battle world only; not UI or recording overlays.
		overview.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(overview)
		_player_overview_viewport = overview
		var layer := CanvasLayer.new()
		layer.name = "PlayerCompositionOverview"
		layer.layer = OVERLAY_LAYER - 1 # Above game, below the offline progress mask.
		add_child(layer)
		_player_overview_layer = layer
		var frame := Control.new()
		frame.name = "OverviewFrame"
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.visibility_layer = CAPTURE_MASK_BIT
		layer.add_child(frame)
		_player_overview_root = frame
		var border := ColorRect.new()
		border.color = Color(0.03, 0.10, 0.17, 0.96)
		border.size = Vector2(414, 414)
		border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		border.visibility_layer = CAPTURE_MASK_BIT
		frame.add_child(border)
		var picture := TextureRect.new()
		picture.name = "PlayerFullMapInset"
		picture.position = Vector2(7, 7)
		picture.size = Vector2(400, 400)
		picture.texture = overview.get_texture()
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.visibility_layer = CAPTURE_MASK_BIT
		frame.add_child(picture)
		var tag := Label.new()
		tag.position = Vector2(16, 12)
		tag.size = Vector2(170, 39)
		tag.add_theme_color_override("font_color", Color.WHITE)
		tag.add_theme_color_override("font_outline_color", Color.BLACK)
		tag.add_theme_constant_override("outline_size", 5)
		tag.add_theme_font_size_override("font_size", 22)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.visibility_layer = CAPTURE_MASK_BIT
		frame.add_child(tag)
		_player_overview_label = tag
	var size:Vector2 = Vector2(_player_overview_viewport.size)
	var zoom:float = minf(size.x * 0.92 / rect.size.x, size.y * 0.92 / rect.size.y)
	var xform := Transform2D.IDENTITY.scaled(Vector2.ONE * zoom)
	xform.origin = size * 0.5 - rect.get_center() * zoom
	_player_overview_viewport.canvas_transform = xform
	_player_overview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var scale:float = minf(view.x / 1080.0, view.y / 1920.0)
	_player_overview_root.position = Vector2(view.x - 442.0 * scale, 292.0 * scale)
	_player_overview_root.scale = Vector2.ONE * scale
	_player_overview_label.text = "全图" if str(Game.current_locale).begins_with("zh") else "OVERVIEW"
	var world:Node = _world()
	var settings:CanvasItem = world.get_node_or_null("CanvasLayer/Control/Game_Setting") as CanvasItem if world != null else null
	_player_overview_layer.visible = settings == null or not settings.is_visible_in_tree()


func _grab_image() -> Image:
	var source:Viewport = _capture_viewport if is_instance_valid(_capture_viewport) else get_viewport()
	var image:Image = source.get_texture().get_image()
	if image == null or image.is_empty():
		if is_instance_valid(_sim_viewport) and (source == _sim_viewport or source == _resolve_viewport):
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
	return source.use_hdr_2d


func _grab_capture_rgba() -> PackedByteArray:
	# Both capture modes' GPU resolve is already 8-bit sRGB. Avoid creating an Image and
	# copying its pixels back into bytes before writing to ffmpeg.
	if not _readback_checked:
		_readback_checked = true
		if is_instance_valid(_capture_viewport) and not _viewport_uses_hdr(_capture_viewport):
			_readback_device = RenderingServer.get_rendering_device()
			if _readback_device != null:
				var texture:RID = RenderingServer.texture_get_rd_texture(_capture_viewport.get_texture().get_rid())
				if texture.is_valid():
					var fmt:RDTextureFormat = _readback_device.texture_get_format(texture)
					if fmt.format == RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM and fmt.width == _capture_size.x and fmt.height == _capture_size.y and (fmt.usage_bits & RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT) != 0:
						_readback_texture = texture
	if _readback_texture.is_valid():
		var raw:PackedByteArray = _readback_device.texture_get_data(_readback_texture, 0)
		if raw.size() == _capture_size.x * _capture_size.y * 4:
			return raw
	# Other rendering backends retain the original conversion path.
	var image:Image = _grab_image()
	if image == null or image.is_empty(): return PackedByteArray()
	if image.get_size() != _capture_size: image.resize(_capture_size.x, _capture_size.y, Image.INTERPOLATE_NEAREST)
	return image.get_data()


func _write_capture_rgba(data:PackedByteArray, count:int = 1, count_index:bool = true) -> void:
	if data.is_empty() or count <= 0: return
	if _writer != null:
		if not _writer.enqueue(data, count):
			_fail(_writer.get_error())
			stop()
			return
		if count_index: _frame_index += count
	elif _png_fallback:
		_write_frame(Image.create_from_data(_capture_size.x, _capture_size.y, false, Image.FORMAT_RGBA8, data), count)


func _write_frame(image:Image, count:int = 1) -> void:
	if image == null or image.is_empty() or count <= 0: return
	if image.get_size() != _capture_size:
		image.resize(_capture_size.x, _capture_size.y, Image.INTERPOLATE_NEAREST)
	if _writer != null:
		if not _writer.enqueue(image.get_data(), count):
			_fail(_writer.get_error())
			stop()
			return
		_frame_index += count
		return
	if _png_fallback:
		for index:int in range(count):
			if image.save_png("%s/frame_%05d.png" % [_session_dir, _frame_index]) == OK:
				_frame_index += 1
			else:
				_fail("写入录制图片失败，请检查磁盘空间。")
				stop()
				return


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
	# Match the player's linear-light blending and material rendering, not just
	# isolated opaque color swatches. Resolve to sRGB on GPU before 8-bit readback.
	sub.use_hdr_2d = _viewport_uses_hdr(main)
	sub.canvas_item_default_texture_filter = main.canvas_item_default_texture_filter
	sub.msaa_2d = main.msaa_2d
	sub.snap_2d_transforms_to_pixel = main.snap_2d_transforms_to_pixel
	sub.snap_2d_vertices_to_pixel = main.snap_2d_vertices_to_pixel
	# 与主视口共享 2D 世界，但把遮罩所在的可见层剔除掉。
	sub.world_2d = main.world_2d
	sub.canvas_cull_mask = CAPTURE_ALL_MASK & ~CAPTURE_MASK_BIT & ~(LocaleScript.EN_BIT if _locale == "zh" else LocaleScript.ZH_BIT)
	sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(sub)
	_sim_viewport = sub
	_capture_viewport = sub
	# Whitelist the permanent world vignette only; never clone Stop_Ui or toolbar.
	var layer := CanvasLayer.new()
	layer.name = "BattleVisualEffects"
	layer.layer = 99
	sub.add_child(layer)
	_capture_vignette = Game.vignette.duplicate(0) as ColorRect
	layer.add_child(_capture_vignette)
	_capture_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sync_capture_vignette()
	_setup_recording_composition(sub)
	if sub.use_hdr_2d:
		_setup_color_resolve(sub)
	if not _is_variant and is_instance_valid(_secondary):
		_secondary._setup_sim_capture_viewport()
		if not is_instance_valid(_locale_mirror):
			_locale_mirror = LocaleScript.new()
			add_child(_locale_mirror)
			# Put VS in each capture's own screen layer. The mirror stays visible
			# through FOLLOW/OVERVIEW zoom even when the arena fills the header.
			_locale_mirror.begin(_world(), main, {"zh":_sim_viewport, "en":_secondary._sim_viewport})
		# CanvasLayers belong to the player Viewport, not its shared World2D.
		# Add locale-specific copies to BOTH real video sources (LIVE and SIM).
		_effect_tooltips = EffectTooltipsScript.new()
		add_child(_effect_tooltips)
		_effect_tooltips.begin(_sim_viewport,_secondary._sim_viewport)


func _setup_recording_composition(sub:SubViewport) -> void:
	var overlay := CanvasLayer.new()
	overlay.name = "RecordingComposition"
	overlay.layer = 100
	sub.add_child(overlay)
	# FULL/FOLLOW show only the localized World VS above the map. Never draw a
	# second screen-space title or a dark header over the portrait footage.
	# FOLLOW_OVERVIEW keeps its separate, small-map inset below.
	if _composition != PreferencesScript.FOLLOW_OVERVIEW: return
	var overview := SubViewport.new()
	overview.name = "BattleOverview"
	overview.disable_3d = true
	overview.gui_disable_input = true
	overview.size = Vector2i(400, 400)
	overview.world_2d = sub.world_2d
	overview.use_hdr_2d = false
	overview.canvas_cull_mask = 1 # World only; exclude language text / recording mask.
	overview.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(overview)
	_overview_viewport = overview
	var border := ColorRect.new()
	border.position = Vector2(638, 292)
	border.size = Vector2(414, 414)
	border.color = Color(0.03, 0.10, 0.17, 0.96)
	overlay.add_child(border)
	var picture := TextureRect.new()
	picture.name = "FullMapInset"
	picture.position = Vector2(645, 299)
	picture.size = Vector2(400, 400)
	picture.texture = overview.get_texture()
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(picture)
	var tag_back := ColorRect.new()
	tag_back.position = Vector2(652, 304)
	tag_back.size = Vector2(166, 39)
	tag_back.color = Color(0.02, 0.09, 0.16, 0.88)
	overlay.add_child(tag_back)
	var tag := Label.new()
	tag.text = "全图" if _locale == "zh" else "OVERVIEW"
	tag.position = Vector2(660, 307)
	tag.size = Vector2(148, 36)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 22)
	tag.add_theme_color_override("font_color", Color.WHITE)
	tag.add_theme_color_override("font_outline_color", Color(0.03, 0.09, 0.14))
	tag.add_theme_constant_override("outline_size", 5)
	overlay.add_child(tag)


func _sync_capture_vignette() -> void:
	if not is_instance_valid(_capture_vignette): return
	_capture_vignette.visible = Game.vignette.is_visible_in_tree()
	_capture_vignette.material = Game.vignette.material
	_capture_vignette.modulate = Game.vignette.modulate
	_capture_vignette.self_modulate = Game.vignette.self_modulate
	# Pause/resume changes this parameter for the menu animation, not the battle.
	_capture_vignette.set_instance_shader_parameter("SCALE", Game.vignette_start)


func _setup_color_resolve(source:SubViewport) -> void:
	var target := SubViewport.new()
	target.name = "BattleRecordSRGB"
	target.disable_3d = true
	target.gui_disable_input = true
	target.use_hdr_2d = false
	target.size = _capture_size
	target.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(target)
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D frame_texture : filter_nearest;
void fragment() {
	vec3 linear_rgb = max(texture(frame_texture, UV).rgb, vec3(0.0));
	vec3 srgb = mix(12.92 * linear_rgb,
		1.055 * pow(linear_rgb, vec3(1.0 / 2.4)) - 0.055,
		step(vec3(0.0031308), linear_rgb));
	COLOR = vec4(srgb, 1.0);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("frame_texture", source.get_texture())
	var rect := ColorRect.new()
	rect.material = material
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_resolve_viewport = target
	_capture_viewport = target


func _free_sim_capture_viewport() -> void:
	if is_instance_valid(_effect_tooltips):
		_effect_tooltips.finish()
		_effect_tooltips.queue_free()
	_effect_tooltips = null
	if is_instance_valid(_secondary): _secondary._free_sim_capture_viewport()
	_readback_texture = RID()
	_readback_device = null
	_readback_checked = false
	_capture_vignette = null
	_camera_initialized = false
	if is_instance_valid(_overview_viewport):
		_overview_viewport.queue_free()
	_overview_viewport = null
	if is_instance_valid(_resolve_viewport):
		if _capture_viewport == _resolve_viewport: _capture_viewport = null
		_resolve_viewport.queue_free()
	_resolve_viewport = null
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
	var state_text:String = "从当前状态离线计算中（非重打）"
	if _sim_tail_left >= 0.0:
		state_text = "对局已结束，正在完成尾帧"
	_overlay_label.text = "%s\n已生成 %.1f 秒 / %d 帧\n按机器能力计算，成片为正常速度" % [state_text, _game_time, _frame_index]
	if _overlay_abort != null:
		_overlay_abort.text = Game.ui_t("UI_RECORD_ABORT")


func _on_overlay_abort_pressed() -> void:
	stop()


func _update_sim_progress(game_delta:float) -> void:
	_cancel_invalid_armor_tail()
	if _sim_tail_left < 0.0:
		if _sim_match_over():
			_sim_tail_left = _tail_seconds
	else:
		_sim_tail_left -= game_delta
		if _sim_tail_left <= 0.0:
			_sim_finished = true
			return
	if _game_time - _last_progress_push >= 0.1:
		_last_progress_push = _game_time
		_update_overlay_text()


## LIVE 和 SIM 均没有固定时长上限；只有实际终局后才按游戏时间续录。
func _update_match_end_tail(game_delta:float) -> void:
	_cancel_invalid_armor_tail()
	if _sim_tail_left < 0.0:
		# 没有对局场景时实时录制照常进行（例如录菜单），不把“无世界”当成胜负已分。
		var world:Node = _world()
		if world != null and is_instance_valid(world):
			if _stale_match_over:
				if not _match_over_now(): _stale_match_over = false
			elif _match_over_now():
				_sim_tail_left = _tail_seconds
	else:
		_sim_tail_left -= game_delta
		if _sim_tail_left <= 0.0:
			_sim_finished = true


## 胜负已分后剩余的续录秒数；未分出胜负时为 -1。
func get_tail_left() -> float:
	return _sim_tail_left


## 对局结束以世界正式结算为准；存活阵营短暂收敛不等于一场比赛结束。
func _sim_match_over() -> bool:
	var world:Node = _world()
	if world == null or not is_instance_valid(world):
		return true
	return _match_over_now()


## An old victory bell can survive adding a new armor-stand opponent. Only
## reject that finish signal while the existing World contender contract proves
## the armor demonstration is still contested. Never infer an ordinary match end.
func _armor_recording_still_contested(world:Node) -> bool:
	if world == null or not is_instance_valid(world): return false
	var armor_test:bool = bool(world.get("_armor_stand_test_hud_active"))
	if not armor_test and (mode != Mode.IDLE or _session_active):
		armor_test = bool(_match_snapshot.get("armor_test",false))
	if not armor_test: return false
	# Timed expiry / exhausted queue are real terminal events even with survivors.
	if Game.is_timed_training_mode() and bool(world.get("_timed_finished")): return false
	if world.has_method("_queue_battle_mode_active") and bool(world.call("_queue_battle_mode_active")) and bool(world.get("_rotation_finished")): return false
	if not world.has_method("_collect_alive_victory_sides"): return false
	var sides:Dictionary = world.call("_collect_alive_victory_sides")
	return sides.size() > 1


func _cancel_invalid_armor_tail() -> void:
	if not _armor_recording_still_contested(_world()): return
	# Re-entering an ongoing demonstration also cancels an already armed tail.
	_sim_tail_left = -1.0
	_sim_finished = false
	_stale_match_over = false


## 世界正式结算为准；盔甲架仍有对立存活阵营时不能沿用上一场的铃声。
func _match_over_now() -> bool:
	var world:Node = _world()
	if world == null or not is_instance_valid(world):
		return false
	if _armor_recording_still_contested(world): return false
	var played:Variant = world.get("_victory_bell_played")
	if played != null and bool(played):
		return true
	# 队列换人期间可能短暂无人，不能把它误判为整场结束。
	if world.has_method("_queue_battle_mode_active") and bool(world.call("_queue_battle_mode_active")):
		return bool(world.get("_rotation_finished"))
	return false


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
		"-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2:out_color_matrix=bt709:out_range=tv",
		"-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709",
		"-c:v", "libx264", "-preset", "veryfast", "-crf", VIDEO_CRF,
		"-pix_fmt", "yuv420p", "-movflags", "+faststart",
		ProjectSettings.globalize_path(out_path),
	])
	if pid <= 0:
		return
	await _wait_for_process(pid, 120.0)
	_last_mux_ok = OS.get_process_exit_code(pid) == 0


func _mux_game_audio() -> bool:
	var ffmpeg:String = _resolve_ffmpeg()
	if ffmpeg.is_empty() or _audio == null: return false
	var duration:float = float(_frame_index) / _output_fps
	var pid:int = OS.create_process(ffmpeg, [
		"-y", "-hide_banner", "-loglevel", "error",
		"-i", ProjectSettings.globalize_path(_video_path),
		"-f", "f32le", "-ar", str(_audio.sample_rate), "-ac", "2",
		"-i", ProjectSettings.globalize_path(_audio_path),
		"-map", "0:v:0", "-map", "1:a:0", "-c:v", "copy",
		"-c:a", "aac", "-ar", "48000", "-b:a", "320k", "-af", "apad",
		"-t", "%.6f" % duration, "-movflags", "+faststart",
		ProjectSettings.globalize_path(_out_path),
	])
	if pid <= 0: return false
	await _wait_for_process(pid, 120.0)
	return OS.get_process_exit_code(pid) == 0 and FileAccess.file_exists(_out_path)


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
	_release_live_render_budget()
	if _writer != null:
		_writer.close_when_empty()
		if OS.is_process_running(_pipe_pid): OS.kill(_pipe_pid)
		_writer.join()
		_writer = null
	if is_instance_valid(_locale_mirror): _locale_mirror.finish()
	if _audio != null: _audio.finish()
	if _pipe != null and _pipe.is_open():
		_pipe.close()
	if _session_active:
		_release_sim_world_state(false)
