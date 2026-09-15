extends AudioStream
## Reuses only completely unreferenced native playback objects. Audio decoding,
## seek, mixing, resampling, looping and pitch remain the original engine code.
var source:AudioStream
var pool:Array[AudioStreamPlayback] = []
var hits:int = 0
var misses:int = 0
func configure(original:AudioStream,count:int) -> void:
	source = original
	for i:int in range(count):
		pool.append(source.instantiate_playback())
func _instantiate_playback() -> AudioStreamPlayback:
	for i:int in range(pool.size()):
		var candidate:AudioStreamPlayback = pool[i]
		# One reference in pool and one in this local variable. A player, mixer,
		# fade-out voice or external get_stream_playback() reference prevents reuse.
		if candidate.get_reference_count() == 2:
			candidate.stop()
			hits += 1
			return candidate
	misses += 1
	var created:AudioStreamPlayback = source.instantiate_playback()
	if pool.size() < 256:
		pool.append(created)
	return created
func _get_length() -> float:
	return source.get_length() if source != null else 0.0
func _get_stream_name() -> String:
	return source.get_stream_name() if source != null else ""
func _is_monophonic() -> bool:
	return source.is_monophonic() if source != null else false
