extends RefCounted
## Streaming stereo float PCM; memory bounded by AudioEffectCapture's ring buffer.
## The existing Audios autoload makes game audio follow Engine.time_scale.
## SIM reverses that slowdown by resampling with exactly the same timeline scale.
const BUS:StringName = &"GameplayRecord"
var effect:AudioEffectCapture
var file:FileAccess
var sample_rate:int = 48000
var samples_written:int = 0
var peak:float = 0.0
var error:String = ""
var dropped_frames:int = 0
var _last_discarded:int = 0
var _position:float = 0.0
var _path:String = ""

func begin(path:String, offline:bool = false) -> bool:
	var bus:int = AudioServer.get_bus_index(BUS)
	if bus < 0:
		error = "找不到 GameplayRecord 游戏音频总线。"
		return false
	sample_rate = int(AudioServer.get_mix_rate())
	_path = path
	file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		error = "无法创建录制音频临时文件。"
		return false
	if offline: return true
	effect = AudioEffectCapture.new()
	effect.buffer_length = 5.0
	AudioServer.add_bus_effect(bus, effect)
	effect.clear_buffer()
	return true

func drain(timeline_scale:float, discard:bool = false, recover_overflow:bool = false) -> void:
	if effect == null or file == null: return
	var count:int = effect.get_frames_available()
	var input:PackedVector2Array = effect.get_buffer(count)
	var discarded:int = effect.get_discarded_frames()
	var missing:int = maxi(0, discarded - _last_discarded)
	_last_discarded = discarded
	if missing > 0 and not recover_overflow:
		error = "音频采集缓冲溢出，已停止录制；请降低对战负载后重试。"
		return
	if discard or timeline_scale <= 0.000001:
		_position = 0.0
		return
	var bus:int = AudioServer.get_bus_index(BUS)
	var gain:float = 1.0
	# Capture effects run before bus volume/mute. Respect the user's output mix.
	for index:int in [bus, 0]:
		if AudioServer.is_bus_mute(index): gain = 0.0
		gain *= db_to_linear(AudioServer.get_bus_volume_db(index))
	var step:float = 1.0 / timeline_scale
	var output := PackedVector2Array()
	output.resize(maxi(0, int(ceil((float(input.size()) - _position) / step))))
	var written:int = 0
	while _position < input.size():
		var first:int = int(_position)
		var last:int = mini(first + 1, input.size() - 1)
		var value:Vector2 = input[first].lerp(input[last], _position - first) * gain
		value = value.clamp(Vector2(-1, -1), Vector2(1, 1))
		peak = maxf(peak, maxf(absf(value.x), absf(value.y)))
		output[written] = value
		written += 1
		_position += step
	_position -= input.size()
	if written > 0:
		output.resize(written)
		file.store_buffer(output.to_byte_array())
		samples_written += written
		if file.get_error() != OK: error = "写入录制音频失败，请检查磁盘空间。"
	if missing > 0:
		dropped_frames += missing
		# Capture keeps the oldest buffered samples; the lost interval follows them.
		write_silence(int(round(missing * timeline_scale)))

func write_silence(count:int) -> void:
	var silence:PackedByteArray = PackedByteArray()
	silence.resize(4096 * 8)
	while count > 0 and error.is_empty():
		var chunk:int = mini(count, 4096)
		file.store_buffer(silence if chunk == 4096 else silence.slice(0, chunk * 8))
		samples_written += chunk
		count -= chunk
		if file.get_error() != OK: error = "写入录制音频失败，请检查磁盘空间。"

func render_offline(frame_number:int, fps:float) -> void:
	if file == null: return
	# Integer cumulative target also supports 44.1kHz without per-frame rounding drift.
	var target:int = int(round(frame_number * sample_rate / fps))
	var count:int = target - samples_written
	if count <= 0: return
	var pcm:PackedVector2Array = AudioServer.call("render_offline_audio", count, BUS)
	if pcm.size() != count:
		error = "离线音频混合未返回完整采样，已停止。"
		return
	for sample:Vector2 in pcm: peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	file.store_buffer(pcm.to_byte_array())
	samples_written += count
	if file.get_error() != OK: error = "写入离线音频失败，请检查磁盘空间。"


func finish() -> void:
	if effect != null:
		var bus:int = AudioServer.get_bus_index(BUS)
		if bus >= 0:
			for index:int in range(AudioServer.get_bus_effect_count(bus) - 1, -1, -1):
				if AudioServer.get_bus_effect(bus, index) == effect:
					AudioServer.remove_bus_effect(bus, index)
		effect = null
	if file != null:
		# A completely silent match still gets a valid AAC silence track.
		if samples_written == 0:
			file.store_float(0.0)
			file.store_float(0.0)
		file.flush()
		if file.get_error() != OK: error = "保存录制音频失败，请检查磁盘空间。"
		file.close()
		file = null
