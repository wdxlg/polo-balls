extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var source:AudioStream = load("res://audio/sfx/shooter/Knife_throw.ogg")
	var cache:AudioStream = load("res://classes/prewarmed_audio_stream.gd").new()
	cache.configure(source,2)
	var failures:int = 0
	var checks:int = 0
	for repeat:int in range(12):
		var fresh:AudioStreamPlayback = source.instantiate_playback()
		var reused:AudioStreamPlayback = cache.instantiate_playback()
		var position:float = 0.04 if repeat % 3 == 1 else 0.0
		fresh.start(position)
		reused.start(position)
		for block:int in range(32):
			var rate:float = 0.7 + float(repeat) * 0.09
			var a:PackedVector2Array = fresh.mix_audio(rate,256)
			var b:PackedVector2Array = reused.mix_audio(rate,256)
			checks += 1
			if a.to_byte_array() != b.to_byte_array():
				failures += 1
				if failures <= 3:
					print("AUDIO_DIFFERENCE repeat=",repeat," block=",block)
		fresh.stop()
		# Intentionally do not stop reused. The pool must reset an unowned,
		# interrupted native playback without touching any externally held one.
		fresh = null
		reused = null
	var held:AudioStreamPlayback = cache.instantiate_playback()
	held.start()
	var second:AudioStreamPlayback = cache.instantiate_playback()
	checks += 1
	if held == second:
		failures += 1
	held.stop()
	second.stop()
	held = null
	second = null
	print("AUDIO_POOL_TEST ",JSON.stringify({"checks":checks,"failures":failures,"hits":cache.hits,"misses":cache.misses,"pool":cache.pool.size()}))
	quit(0 if failures == 0 else 1)
