extends SceneTree
## 探针：AudioStreamPlayback.mix_audio 是否可用；OGG 首帧解码成本；WAV 与 OGG 启动成本对比。
func _initialize() -> void: call_deferred("run")
func _us(t0:int,n:int) -> String: return "%.1f us" % (float(Time.get_ticks_usec()-t0)/float(n))
func run() -> void:
	await create_timer(0.3).timeout
	print("has mix_audio=",ClassDB.class_has_method("AudioStreamPlayback","mix_audio")," has start=",ClassDB.class_has_method("AudioStreamPlayback","start")," mix_rate=",AudioServer.get_mix_rate())
	var audios:Node = root.get_node("Audios")
	var player:AudioStreamPlayer = audios.Sfx.get_node("KnifeThrow1")
	var stream:AudioStream = player.stream
	print("KnifeThrow1 stream=",stream.get_class()," length=",stream.get_length()," script=",stream.get_script())
	var N:int = 100
	var t0:int = Time.get_ticks_usec()
	for i in range(N): player.play()
	print("OGG player.play() x100 (restart): ",_us(t0,N))
	var pb:AudioStreamPlayback = stream.instantiate_playback()
	t0 = Time.get_ticks_usec()
	for i in range(N):
		pb.start(0.0)
		pb.stop()
	print("OGG playback.start+stop: ",_us(t0,N))
	if ClassDB.class_has_method("AudioStreamPlayback","mix_audio"):
		pb.start(0.0)
		t0 = Time.get_ticks_usec()
		var all:PackedVector2Array = PackedVector2Array()
		var chunk:PackedVector2Array = pb.mix_audio(1.0,4096)
		while chunk.size() > 0:
			all.append_array(chunk)
			if chunk.size() < 4096: break
			chunk = pb.mix_audio(1.0,4096)
		print("decoded frames=",all.size()," (",float(all.size())/AudioServer.get_mix_rate()," s) in ",_us(t0,1)," playing=",pb.is_playing())
		var peak:float = 0.0
		for v in all: peak = maxf(peak,maxf(absf(v.x),absf(v.y)))
		print("peak=",peak)
		var wav:AudioStreamWAV = AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.stereo = true
		wav.mix_rate = int(AudioServer.get_mix_rate())
		var bytes:PackedByteArray = PackedByteArray()
		bytes.resize(all.size()*4)
		for i in range(all.size()):
			bytes.encode_s16(i*4,int(clampf(all[i].x,-1.0,1.0)*32767.0))
			bytes.encode_s16(i*4+2,int(clampf(all[i].y,-1.0,1.0)*32767.0))
		wav.data = bytes
		var p2:AudioStreamPlayer = AudioStreamPlayer.new()
		p2.stream = wav
		p2.bus = player.bus
		root.add_child(p2)
		t0 = Time.get_ticks_usec()
		for i in range(N): p2.play()
		print("WAV(decoded) player.play() x100 (restart): ",_us(t0,N))
		p2.pitch_scale = 1.07
		t0 = Time.get_ticks_usec()
		for i in range(N): p2.play()
		print("WAV(decoded) player.play() pitch 1.07: ",_us(t0,N))
	var hit:AudioStreamPlayer = audios.Sfx.get_node("balls_hit1")
	print("balls_hit1 stream=",hit.stream.get_class()," fmt=",hit.stream.format," rate=",hit.stream.mix_rate," stereo=",hit.stream.stereo," len=",hit.stream.get_length())
	t0 = Time.get_ticks_usec()
	for i in range(N): hit.play()
	print("balls_hit1 play x100: ",_us(t0,N))
	quit()
