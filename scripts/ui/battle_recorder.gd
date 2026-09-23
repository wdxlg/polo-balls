extends Node
## 对决录制器（顶部工具栏“录制”按钮的后端）。
##
## 两种模式都把原始像素直接喂给 ffmpeg 的 stdin 编码成 mp4，不在磁盘上留中间图片：
##   左键 LIVE —— 独立 1080×1920 / 60fps 纯对战画面 + 游戏总线音频；暂停不计入成片。
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

const LIVE_OUTPUT_FPS:float = 60.0
const OUTPUT_SIZE:Vector2i = Vector2i(1080, 1920)
const VIDEO_CRF:String = "14"
const AudioCaptureScript = preload("res://scripts/ui/battle_record_audio.gd")
const SIM_OUTPUT_FPS:float = 60.0
## 0.25 倍慢放降低模拟抓帧压力；音频与画面按同一时间倍率还原。
const SIM_TIME_SCALE:float = 0.25
const SIM_MAX_GAME_SECONDS:float = 300.0
const SIM_MIN_GAME_SECONDS:float = 3.0
const SIM_TAIL_GAME_SECONDS:float = 1.5
const TIME_SCALE_KEY:String = "battle_record_sim"
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

const PreferencesScript = preload("res://scripts/ui/battle_record_preferences.gd")
var preferences:RefCounted = PreferencesScript.new()
var _session_output_root:String = ""
var _last_pause_reason:String = ""
var _encoder_stderr:FileAccess
var _encoder_exit:int = -1
var _last_error:String = ""
var mode:int = Mode.IDLE

var _session_active:bool = false
var _finalizing:bool = false
var _capture_viewport:Viewport = null
var _sim_viewport:SubViewport = null
var _resolve_viewport:SubViewport = null
var _capture_vignette:ColorRect = null
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
var _previous_image:Image
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

var _overlay:CanvasLayer = null
var _overlay_backdrop:ColorRect = null
var _overlay_label:Label = null
var _overlay_abort:Button = null


func _ready() -> void:
	# 录制不能因为游戏暂停（esc）而停摆：遮罩、进度、中止按钮都要继续响应。
	process_mode = Node.PROCESS_MODE_ALWAYS


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


func start_live() -> bool:
	if mode != Mode.IDLE or is_busy():
		return _fail("录制正在进行或保存中，请稍后再试。")
	if not _begin_session(LIVE_OUTPUT_FPS, "live"):
		return false
	_setup_sim_capture_viewport()
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
	return preferences.get_directory()


func set_output_directory(path:String) -> bool:
	if is_busy(): return _fail("请先停止录制并等待保存完成，再修改目录。")
	if not preferences.save_directory(path): return _fail(preferences.last_error)
	_last_error = ""
	return true


func get_pause_reason() -> String:
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
	_pause_boundary = false
	_audio.effect.clear_buffer()
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
	_previous_image = null
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
	_out_path = "%s/%s_%s.mp4" % [_session_output_root, tag, stamp]
	_video_path = _out_path.get_basename() + ".video.mp4"
	_audio_path = _out_path.get_basename() + ".audio.f32"
	_audio = AudioCaptureScript.new()
	if not _audio.begin(_audio_path):
		_audio.finish()
		return _fail(_audio.error)

	if _open_pipe_encoder():
		return true

	# 降级路线：先把帧存成 PNG 序列，结束时再尝试合成 mp4。
	_session_dir = "%s/%s_%s" % [_session_output_root, tag, stamp]
	if DirAccess.make_dir_recursive_absolute(_session_dir) == OK:
		_png_fallback = true
		push_warning("battle_recorder: 没有可用的 ffmpeg 管道，改为输出 PNG 序列：%s" % ProjectSettings.globalize_path(_session_dir))
		return true

	_audio.finish()
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
	args.append_array([
		"-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2:out_color_matrix=bt709:out_range=tv",
		"-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709",
	])
	args.append("-an")
	args.append("-c:v")
	args.append("libx264")
	args.append("-preset")
	args.append("veryfast")
	args.append("-crf")
	args.append(VIDEO_CRF)
	args.append("-pix_fmt")
	args.append("yuv420p")
	args.append("-movflags")
	args.append("+faststart")
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
	return true


func _finish_session() -> void:
	if not _session_active:
		return
	_session_active = false
	_finalizing = true
	if mode != Mode.IDLE:
		mode = Mode.IDLE
		mode_changed.emit(mode)
	if _audio != null:
		_audio.finish()
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

	if finished_path == _video_path:
		if await _mux_game_audio():
			finished_path = _out_path
			DirAccess.remove_absolute(_video_path)
			DirAccess.remove_absolute(_audio_path)
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
		DirAccess.remove_absolute(_audio_path)
	_previous_image = null
	_finalizing = false
	recording_finished.emit(finished_path, frame_count)


func _release_sim_world_state() -> void:
	Game.release_time_scale_override(TIME_SCALE_KEY)


#========================================================
# 抓帧主循环
#========================================================

func _capture_is_paused() -> bool:
	return not get_pause_reason().is_empty()

func _capture_loop() -> void:
	_last_tick_usec = Time.get_ticks_usec()
	while mode != Mode.IDLE:
		var capture_requested:bool = not _capture_is_paused()
		if capture_requested: _prepare_next_capture()
		await RenderingServer.frame_post_draw
		if mode == Mode.IDLE: break
		var now_usec:int = Time.get_ticks_usec()
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
			_previous_image = null
			continue
		var game_delta:float = real_delta * scale_now
		_game_time += game_delta
		_accumulator += game_delta
		var wanted:int = int(_accumulator / _frame_interval)
		if wanted > MAX_FRAMES_PER_DRAW:
			_fail("录制遇到超过两秒的渲染阻塞，已停止，避免产生音画不同步的视频。")
			stop()
			break
		if wanted > 0:
			var image:Image = _grab_image()
			for index:int in range(wanted):
				if mode == Mode.IDLE: break
				# Fill elapsed gaps with the OLD image, not a future hit/flash.
				# Otherwise a delayed render makes visual events precede their audio.
				_write_frame(_previous_image if index < wanted - 1 and _previous_image != null else image)
				_accumulator -= _frame_interval
			_previous_image = image
		if mode == Mode.SIM:
			_update_sim_progress(game_delta)
			if _sim_finished: break
	_finish_session()


func _prepare_next_capture() -> void:
	if not is_instance_valid(_sim_viewport):
		return
	# 共享 world_2d 的离屏视口不会自动跟随主相机，每帧手动同步画布变换。
	var main:Viewport = get_viewport()
	var logical_size:Vector2 = main.get_visible_rect().size
	var scale_to_output := Transform2D.IDENTITY.scaled(Vector2(_capture_size) / logical_size)
	_sim_viewport.canvas_transform = scale_to_output * main.global_canvas_transform * main.get_canvas_transform()
	_sync_capture_vignette()
	_sim_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if is_instance_valid(_resolve_viewport):
		_resolve_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


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


func _write_frame(image:Image) -> void:
	if image == null or image.is_empty():
		return
	if image.get_size() != _capture_size:
		image.resize(_capture_size.x, _capture_size.y, Image.INTERPOLATE_NEAREST)
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
	if _png_fallback:
		if image.save_png("%s/frame_%05d.png" % [_session_dir, _frame_index]) == OK:
			_frame_index += 1
		else:
			_fail("写入录制图片失败，请检查磁盘空间。")
			stop()


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
	sub.canvas_cull_mask = CAPTURE_ALL_MASK & ~CAPTURE_MASK_BIT
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
	if sub.use_hdr_2d:
		_setup_color_resolve(sub)


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
	_capture_vignette = null
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
	if _audio != null: _audio.finish()
	if _pipe != null and _pipe.is_open():
		_pipe.close()
	if _session_active:
		_release_sim_world_state()
