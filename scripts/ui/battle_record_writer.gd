extends RefCounted
## Only this worker owns FileAccess writes/closes. Never block the game on ffmpeg stdin.
## Two 1080x1920 encoders can briefly queue more than 16 raw frames during NVENC
## startup. Keep a bounded half-second cushion per language, not an unbounded queue.
const MAX_BYTES:int = 256 * 1024 * 1024
const MAX_FRAMES:int = 120
var _thread := Thread.new()
var _mutex := Mutex.new()
var _wake := Semaphore.new()
var _jobs:Array = []
var _bytes:int = 0
var _frames:int = 0
var _closing:bool = false
var _error:String = ""
var _pipe:FileAccess
var frames_written:int = 0
var peak_bytes:int = 0

func begin(pipe:FileAccess) -> bool:
	_pipe = pipe
	return _thread.start(_run) == OK

func enqueue(data:PackedByteArray, count:int) -> bool:
	_mutex.lock()
	if _closing or not _error.is_empty():
		_mutex.unlock()
		return false
	if _bytes + data.size() > MAX_BYTES or _frames + count > MAX_FRAMES:
		_error = "编码速度跟不上：录制缓存已满，已停止本次录制，避免拖慢游戏或丢帧。"
		_mutex.unlock()
		return false
	_jobs.append({"data":data, "count":count})
	_bytes += data.size()
	_frames += count
	peak_bytes = maxi(peak_bytes, _bytes)
	_mutex.unlock()
	_wake.post()
	return true

func can_accept(data_bytes:int, count:int = 1) -> bool:
	_mutex.lock()
	var ready:bool = not _closing and _error.is_empty() and _bytes + data_bytes <= MAX_BYTES and _frames + count <= MAX_FRAMES
	_mutex.unlock()
	return ready

func get_error() -> String:
	_mutex.lock()
	var message:String = _error
	_mutex.unlock()
	return message

func close_when_empty() -> void:
	_mutex.lock()
	_closing = true
	_mutex.unlock()
	_wake.post()

func is_running() -> bool:
	return _thread.is_started() and _thread.is_alive()

func join() -> void:
	if _thread.is_started(): _thread.wait_to_finish()

func _run() -> void:
	while true:
		_wake.wait()
		_mutex.lock()
		if _jobs.is_empty():
			var finished:bool = _closing
			_mutex.unlock()
			if finished: break
			continue
		var job:Dictionary = _jobs.pop_front()
		_mutex.unlock()
		var failed:bool = false
		for index:int in range(job.count):
			_pipe.store_buffer(job.data)
			if _pipe.get_error() != OK:
				failed = true
				break
			frames_written += 1
		_mutex.lock()
		_bytes -= job.data.size()
		_frames -= job.count
		if failed:
			_error = "写入编码器失败，请检查编码器、磁盘空间和输出目录。"
			_jobs.clear()
			_bytes = 0
			_frames = 0
		_mutex.unlock()
		if failed: break
	_pipe.flush()
	_pipe.close()
