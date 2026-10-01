extends SceneTree
## 诊断工具（不是自动测试，测试运行器不会加载它）：
## 测量 Godot 侧把 1080×1920 RGBA 帧写进 ffmpeg stdin 的真实吞吐，
## 给 scripts/ui/battle_record_writer.gd 的缓冲上限与 LIVE 背压策略定标。
## 运行：.\godot.exe --headless --path . --script res://tests/bench_recording_pipe.gd

const RecorderScript = preload("res://scripts/ui/battle_recorder.gd")
const WriterScript = preload("res://scripts/ui/battle_record_writer.gd")

const SIZE:Vector2i = Vector2i(1080, 1920)
const FPS:float = 60.0
const FRAMES:int = 48

var _noise:PackedByteArray
var _codec:String = ""
var _ffmpeg:String = ""
var _log_handle:FileAccess
var _started_ms:int = 0


func _init() -> void:
	create_timer(240.0, true, false, true).timeout.connect(func(): quit(2))
	_run.call_deferred()


func _run() -> void:
	_started_ms = Time.get_ticks_msec()
	_log_handle = FileAccess.open("user://bench_recording_pipe.txt", FileAccess.WRITE)
	_log(_stamp() + "BENCH: 开始测量")
	_ffmpeg = _resolve_ffmpeg()
	if _ffmpeg.is_empty():
		_log(_stamp() + "BENCH: 找不到 ffmpeg，无法测量")
		quit(1)
		return
	_noise = _make_noise()
	_codec = _select_codec()
	var needed:float = _noise.size() * FPS / 1048576.0
	_log(_stamp() + "BENCH: ffmpeg=%s codec=%s 帧=%dx%d 单帧=%.2fMB 每路 60fps 需要=%.0fMB/s" % [_ffmpeg, _codec, SIZE.x, SIZE.y, _noise.size() / 1048576.0, needed])
	var probe:RefCounted = WriterScript.new()
	if probe.get("max_bytes") != null:
		_log(_stamp() + "BENCH: 写缓冲配置 max_bytes=%.0fMB(约 %d 帧) max_frames=%s" % [int(probe.get("max_bytes")) / 1048576.0, int(probe.get("max_bytes")) / _noise.size(), str(probe.get("max_frames"))])
	_bench_raw_single()
	_bench_raw_dual()
	_bench_writer_burst()
	_bench_writer_sustained()
	_log(_stamp() + "BENCH: done")
	quit(0)


#========================================================
# 1) 主线程直接 store_buffer：Godot 管道写入上限
#========================================================

func _bench_raw_single() -> void:
	var out:String = _temp_output("raw_single")
	var handles:Dictionary = _spawn(_codec, out)
	if handles.is_empty():
		_log(_stamp() + "BENCH raw single: ffmpeg 启动失败")
		_remove(out)
		return
	var pipe:FileAccess = handles.get("stdio")
	var started:int = Time.get_ticks_usec()
	var first_usec:int = 0
	for index:int in range(FRAMES):
		pipe.store_buffer(_noise)
		if index == 0: first_usec = Time.get_ticks_usec() - started
	var pushed_usec:int = Time.get_ticks_usec() - started
	pipe.flush()
	pipe.close()
	var code:int = _wait_exit(int(handles.get("pid", 0)))
	_summary("raw single  ", FRAMES, first_usec, pushed_usec, Time.get_ticks_usec() - started, code)
	_remove(out)


func _bench_raw_dual() -> void:
	var out_a:String = _temp_output("raw_dual_a")
	var out_b:String = _temp_output("raw_dual_b")
	var handles_a:Dictionary = _spawn(_codec, out_a)
	var handles_b:Dictionary = _spawn(_codec, out_b)
	if handles_a.is_empty() or handles_b.is_empty():
		_log(_stamp() + "BENCH raw dual: ffmpeg 启动失败")
		_remove(out_a)
		_remove(out_b)
		return
	var pipe_a:FileAccess = handles_a.get("stdio")
	var pipe_b:FileAccess = handles_b.get("stdio")
	var started:int = Time.get_ticks_usec()
	var first_usec:int = 0
	for index:int in range(FRAMES):
		pipe_a.store_buffer(_noise)
		pipe_b.store_buffer(_noise)
		if index == 0: first_usec = Time.get_ticks_usec() - started
	var pushed_usec:int = Time.get_ticks_usec() - started
	pipe_a.flush()
	pipe_a.close()
	pipe_b.flush()
	pipe_b.close()
	var code_a:int = _wait_exit(int(handles_a.get("pid", 0)))
	var code_b:int = _wait_exit(int(handles_b.get("pid", 0)))
	var mb:float = 2.0 * FRAMES * _noise.size() / 1048576.0
	var seconds:float = maxf(pushed_usec / 1000000.0, 0.000001)
	_log(_stamp() + "BENCH raw dual   : 帧=2x%d 数据=%.0fMB 首帧=%dms 推入=%dms 合计=%.0fMB/s 每路=%.0fMB/s 退出码=%d,%d" % [FRAMES, mb, first_usec / 1000, pushed_usec / 1000, mb / seconds, mb / 2.0 / seconds, code_a, code_b])
	_remove(out_a)
	_remove(out_b)


#========================================================
# 2) 经 battle_record_writer 线程：复现溢出 / 测量背压后的持续吞吐
#========================================================

func _bench_writer_burst() -> void:
	var out:String = _temp_output("writer_burst")
	var handles:Dictionary = _spawn(_codec, out)
	if handles.is_empty():
		_log(_stamp() + "BENCH writer burst: ffmpeg 启动失败")
		_remove(out)
		return
	var writer:RefCounted = WriterScript.new()
	if not writer.begin(handles.get("stdio")):
		_log(_stamp() + "BENCH writer burst: 写线程启动失败")
		_kill(int(handles.get("pid", 0)))
		_remove(out)
		return
	var started:int = Time.get_ticks_usec()
	var accepted:int = 0
	for index:int in range(FRAMES):
		if not writer.enqueue(_noise, 1): break
		accepted += 1
	var pushed_usec:int = Time.get_ticks_usec() - started
	var message:String = str(writer.get_error())
	writer.close_when_empty()
	var drained_usec:int = _join(writer, int(handles.get("pid", 0)))
	_log(_stamp() + "BENCH writer burst : 不等待时只接受 %d/%d 帧就被拒绝（相当于 %.2f 秒画面）峰值=%.0fMB 推入=%dms 排空=%dms 错误=%s" % [accepted, FRAMES, accepted / FPS, int(writer.get("peak_bytes")) / 1048576.0, pushed_usec / 1000, drained_usec / 1000, message])
	_wait_exit(int(handles.get("pid", 0)))
	_remove(out)


func _bench_writer_sustained() -> void:
	var out:String = _temp_output("writer_sustained")
	var handles:Dictionary = _spawn(_codec, out)
	if handles.is_empty():
		_log(_stamp() + "BENCH writer sustained: ffmpeg 启动失败")
		_remove(out)
		return
	var writer:RefCounted = WriterScript.new()
	if not writer.begin(handles.get("stdio")):
		_log(_stamp() + "BENCH writer sustained: 写线程启动失败")
		_kill(int(handles.get("pid", 0)))
		_remove(out)
		return
	var started:int = Time.get_ticks_usec()
	var stall_usec:int = 0
	var accepted:int = 0
	for index:int in range(FRAMES):
		var wait_started:int = Time.get_ticks_usec()
		while Time.get_ticks_usec() - wait_started < 10000000 and writer.get_error().is_empty() and not writer.can_accept(_noise.size(), 1):
			OS.delay_usec(2000)
		stall_usec += Time.get_ticks_usec() - wait_started
		if not writer.enqueue(_noise, 1): break
		accepted += 1
	var pushed_usec:int = Time.get_ticks_usec() - started
	writer.close_when_empty()
	var drained_usec:int = _join(writer, int(handles.get("pid", 0)))
	var code:int = _wait_exit(int(handles.get("pid", 0)))
	var mb:float = accepted * _noise.size() / 1048576.0
	var seconds:float = maxf(pushed_usec / 1000000.0, 0.000001)
	_log(_stamp() + "BENCH writer cont  : 接受=%d/%d 等空间累计=%dms 推入=%dms(%.0fMB/s) 排空=%dms 峰值=%.0fMB 退出码=%d 实时预算=%dms" % [accepted, FRAMES, stall_usec / 1000, pushed_usec / 1000, mb / seconds, drained_usec / 1000, int(writer.get("peak_bytes")) / 1048576.0, code, int(FRAMES / FPS * 1000.0)])
	_remove(out)


#========================================================
# 支撑函数
#========================================================

func _log(line:String) -> void:
	# 先落盘再打印：无头运行时 stdout 可能是已经关闭的管道，print 会永久阻塞。
	if _log_handle != null and _log_handle.is_open():
		_log_handle.store_line(line)
		_log_handle.flush()


func _stamp() -> String:
	return "[%6.1fs] " % ((Time.get_ticks_msec() - _started_ms) / 1000.0)


func _summary(label:String, frames:int, first_usec:int, pushed_usec:int, total_usec:int, code:int) -> void:
	var mb:float = frames * _noise.size() / 1048576.0
	var seconds:float = maxf(pushed_usec / 1000000.0, 0.000001)
	_log(_stamp() + "BENCH %s: 帧=%d 数据=%.0fMB 首帧=%dms 推入=%dms(%.0fMB/s) 收尾=%dms 退出码=%d 实时预算=%dms" % [label, frames, mb, first_usec / 1000, pushed_usec / 1000, mb / seconds, (total_usec - pushed_usec) / 1000, code, int(frames / FPS * 1000.0)])


func _spawn(codec:String, out_path:String) -> Dictionary:
	if not OS.has_method("execute_with_pipe"): return {}
	var args:Array = [
		"-y", "-hide_banner", "-loglevel", "error",
		"-f", "rawvideo", "-pix_fmt", "rgba",
		"-s", "%dx%d" % [SIZE.x, SIZE.y],
		"-r", "%.6f" % FPS,
		"-i", "-",
		"-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2:out_color_matrix=bt709:out_range=tv",
		"-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709",
		"-an", "-c:v", codec,
	]
	if codec == "h264_nvenc":
		args.append_array(["-preset", "p4", "-tune", "ll", "-zerolatency", "1", "-delay", "0", "-rc", "vbr", "-cq", RecorderScript.VIDEO_NVENC_CQ, "-b:v", "0", "-maxrate", RecorderScript.VIDEO_MAXRATE, "-bufsize", RecorderScript.VIDEO_BUFSIZE, "-spatial-aq", "1", "-bf", "0"])
	else:
		args.append_array(["-preset", "ultrafast", "-threads", "2", "-crf", RecorderScript.VIDEO_CRF, "-maxrate", RecorderScript.VIDEO_MAXRATE, "-bufsize", RecorderScript.VIDEO_BUFSIZE])
	args.append_array(["-pix_fmt", "yuv420p", "-movflags", "+faststart", out_path])
	var result:Variant = OS.execute_with_pipe(_ffmpeg, args, true)
	if typeof(result) != TYPE_DICTIONARY: return {}
	var handles:Dictionary = result as Dictionary
	var stdio:Variant = handles.get("stdio")
	if not (stdio is FileAccess) or not (stdio as FileAccess).is_open(): return {}
	return handles


func _select_codec() -> String:
	var output:Array = []
	var ok:bool = OS.execute(_ffmpeg, ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "color=s=1080x1920:r=60", "-frames:v", "1", "-an", "-c:v", "h264_nvenc", "-preset", "p4", "-f", "null", "-"], output, true) == 0
	return "h264_nvenc" if ok else "libx264"


func _resolve_ffmpeg() -> String:
	for candidate:String in RecorderScript.FFMPEG_CANDIDATES:
		if FileAccess.file_exists(candidate): return candidate
	return ""


func _make_noise() -> PackedByteArray:
	var image:Image = Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.3, 0.4))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260923
	var block:int = 8
	for y:int in range(0, SIZE.y, block):
		for x:int in range(0, SIZE.x, block):
			image.fill_rect(Rect2i(x, y, block, block), Color8(rng.randi_range(0, 255), rng.randi_range(0, 255), rng.randi_range(0, 255), 255))
	return image.get_data()


func _temp_output(tag:String) -> String:
	return ProjectSettings.globalize_path("user://bench_%s_%d.mp4" % [tag, Time.get_ticks_usec()])


func _remove(path:String) -> void:
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)


func _kill(pid:int) -> void:
	if pid > 0 and OS.is_process_running(pid): OS.kill(pid)


func _wait_exit(pid:int) -> int:
	var deadline:int = Time.get_ticks_usec() + 15000000
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_usec() < deadline:
		OS.delay_usec(5000)
	_kill(pid)
	return OS.get_process_exit_code(pid)


func _join(writer:RefCounted, pid:int) -> int:
	var started:int = Time.get_ticks_usec()
	var deadline:int = started + 15000000
	while writer.is_running() and Time.get_ticks_usec() < deadline:
		OS.delay_usec(5000)
	if writer.is_running(): _kill(pid)
	writer.join()
	return Time.get_ticks_usec() - started
