extends SceneTree
## 连续命中不能因旧音效占满动态池而成段无声；保留并发上限和同帧合并。
var checks:int = 0
var failures:int = 0
var _test_sources:Array[AudioStreamPlayer] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok:bool,message:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("AUDIO_CONTINUITY_FAILED: " + message)

func _voices(audios:Node) -> Dictionary:
	var result:Dictionary = {}
	for child:Node in audios.get_children():
		if child is AudioStreamPlayer and child.has_meta(audios.META_DYNAMIC_SOURCE_KEY):
			var player:AudioStreamPlayer = child as AudioStreamPlayer
			if player.playing or player.stream_paused:
				# 保留 playback 引用，比较真正的新播放，不能只检查池计数。
				result[player.get_instance_id()] = player.get_stream_playback()
	return result

func _new_playbacks(before:Dictionary,after:Dictionary) -> int:
	var count:int = 0
	for id:Variant in after:
		if not before.has(id) or before[id] != after[id]:
			count += 1
	return count

func _stop_voices(audios:Node) -> void:
	for child:Node in audios.get_children():
		if child is AudioStreamPlayer and child.has_meta(audios.META_DYNAMIC_SOURCE_KEY):
			(child as AudioStreamPlayer).stop()
			audios._release_dynamic_player(child)

func _check_budget(audios:Node,label:String) -> void:
	var stats:Dictionary = audios.get_dynamic_voice_stats()
	var total:int = 0
	for key:Variant in stats.by_source:
		var count:int = int(stats.by_source[key])
		_check(count > 0 and count <= audios.MAX_VOICES_PER_SOURCE,label + " per-source budget: " + str(key))
		total += count
	_check(total == int(stats.active),label + " source counts match active count")
	_check(int(stats.active) <= audios.MAX_DYNAMIC_VOICES,label + " global budget")
	var players:int = 0
	for child:Node in audios.get_children():
		if child is AudioStreamPlayer:
			players += 1
	_check(players == int(stats.active) + int(stats.free),label + " every pooled player is counted exactly once")
	_check(players <= audios.MAX_DYNAMIC_VOICES,label + " node count remains bounded")

func _test_continuous_hits(audios:Node,sfx_name:String) -> void:
	_stop_voices(audios)
	await process_frame
	var source:AudioStreamPlayer = audios.get_node("Sfx").get_node_or_null(sfx_name) as AudioStreamPlayer
	_check(source != null and source.stream != null,"real impact source exists: " + sfx_name)
	if source == null or source.stream == null:
		return
	var started:int = 0
	var missed:Array[int] = []
	for shot:int in range(24):
		var before:Dictionary = _voices(audios)
		audios.play_sfx(sfx_name,{"pitch":1.0},false,true)
		if _new_playbacks(before,_voices(audios)) == 1:
			started += 1
		else:
			missed.append(shot + 1)
		await create_timer(0.02,true,false,true).timeout
	print("AUDIO_CONTINUITY source=",sfx_name," length=",source.stream.get_length()," started=",started,"/24 missed=",missed)
	_check(started == 24,"continuous " + sfx_name + " must start every new-frame impact (%d/24)" % started)
	_check_budget(audios,"continuous " + sfx_name)
	var deadline:int = Time.get_ticks_msec() + int(ceil((source.stream.get_length() + 1.0) * 1000.0))
	while int(audios.get_dynamic_voice_stats().active) > 0 and Time.get_ticks_msec() < deadline:
		await create_timer(0.05,true,false,true).timeout
	_check(int(audios.get_dynamic_voice_stats().active) == 0,"replaced " + sfx_name + " voices finish and release naturally")
	_check_budget(audios,"finished " + sfx_name)

func _make_source(audios:Node,source_name:String,stream:AudioStream) -> AudioStreamPlayer:
	var source:AudioStreamPlayer = AudioStreamPlayer.new()
	source.name = source_name
	source.stream = stream
	source.bus = audios.GAMEPLAY_BUS
	audios.get_node("Sfx").add_child(source)
	_test_sources.append(source)
	return source

func _test_saturation(audios:Node) -> void:
	_stop_voices(audios)
	var stream:AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = 8000
	var silence:PackedByteArray = PackedByteArray()
	silence.resize(80000) # 10 秒，确保测试中不会自然结束。
	stream.data = silence
	var source:AudioStreamPlayer = _make_source(audios,"ContinuitySameSource",stream)
	for i:int in range(audios.MAX_VOICES_PER_SOURCE):
		audios.play_sfx(String(source.name),{},false,true)
	var before:Dictionary = _voices(audios)
	for i:int in range(200):
		audios.play_sfx(String(source.name),{},false,true)
	_check(_new_playbacks(before,_voices(audios)) == 0,"same-frame overflow is coalesced, not repeatedly restarted")
	_check_budget(audios,"same-frame burst")
	await process_frame
	before = _voices(audios)
	audios.play_sfx(String(source.name),{},false,true)
	_check(_new_playbacks(before,_voices(audios)) == 1,"next-frame hit replaces an old same-source voice")
	_check_budget(audios,"same-source replacement")
	# 被手动暂停的声音仍保留原来的播放对象，不能当成可抢占的旧尾音。
	for id:Variant in _voices(audios):
		(instance_from_id(int(id)) as AudioStreamPlayer).stream_paused = true
	await process_frame
	before = _voices(audios)
	_check(before.size() == audios.MAX_VOICES_PER_SOURCE,"paused voices retain their playback objects")
	audios.play_sfx(String(source.name),{},false,true)
	_check(_new_playbacks(before,_voices(audios)) == 0,"paused voices are not stolen")
	for id:Variant in _voices(audios):
		(instance_from_id(int(id)) as AudioStreamPlayer).stream_paused = false
	await process_frame
	before = _voices(audios)
	audios.play_sfx(String(source.name),{},false,true)
	_check(_new_playbacks(before,_voices(audios)) == 1,"replacement resumes after unpausing")
	_stop_voices(audios)
	await process_frame

	# 填满全局池：每个来源只占一路，不能靠扩大单源上限掩盖问题。
	for i:int in range(audios.MAX_DYNAMIC_VOICES + 1):
		_make_source(audios,"ContinuityGlobal%d" % i,stream)
	for i:int in range(audios.MAX_DYNAMIC_VOICES):
		audios.play_sfx("ContinuityGlobal%d" % i,{},false,true)
	_check(int(audios.get_dynamic_voice_stats().active) == audios.MAX_DYNAMIC_VOICES,"global pool filled")
	before = _voices(audios)
	audios.play_sfx("ContinuityGlobal%d" % audios.MAX_DYNAMIC_VOICES,{},false,true)
	_check(_new_playbacks(before,_voices(audios)) == 0,"global overflow cannot erase voices that just started this frame")
	await process_frame
	var prior_sources:Dictionary = audios.get_dynamic_voice_stats().by_source
	before = _voices(audios)
	audios.play_sfx("ContinuityGlobal10",{},false,true)
	_check(_new_playbacks(before,_voices(audios)) == 1,"global saturation still accepts a fresh hit")
	_check(audios.get_dynamic_voice_stats().by_source == prior_sources,"prefer replacing the same source instead of cutting unrelated sounds")
	await process_frame
	before = _voices(audios)
	audios.play_sfx("ContinuityGlobal%d" % audios.MAX_DYNAMIC_VOICES,{},false,true)
	_check(_new_playbacks(before,_voices(audios)) == 1,"a new source is not starved by a full pool")
	_check(not audios.get_dynamic_voice_stats().by_source.has("ContinuityGlobal0"),"oldest eligible global voice is replaced first")
	_check_budget(audios,"global replacement")
	# 外部 stop/free 不会发 finished，仍需在饱和路径正确回收，不能留下虚假满池。
	var stopped:AudioStreamPlayer = instance_from_id(int(_voices(audios).keys()[0])) as AudioStreamPlayer
	stopped.stop()
	await process_frame
	before = _voices(audios)
	audios.play_sfx("ContinuityGlobal%d" % audios.MAX_DYNAMIC_VOICES,{},false,true)
	_check(_new_playbacks(before,_voices(audios)) == 1,"externally stopped voice is reclaimed")
	_check_budget(audios,"stopped voice recovery")
	var freed:AudioStreamPlayer = instance_from_id(int(_voices(audios).keys()[0])) as AudioStreamPlayer
	freed.free()
	await process_frame
	before = _voices(audios)
	audios.play_sfx("ContinuityGlobal%d" % audios.MAX_DYNAMIC_VOICES,{},false,true)
	_check(_new_playbacks(before,_voices(audios)) == 1,"externally freed voice does not leave a stale full pool")
	_check_budget(audios,"freed voice recovery")
	_stop_voices(audios)
	_check(int(audios.get_dynamic_voice_stats().active) == 0,"replacement voices release without leaking counts")
	_check(audios.get("_dynamic_last_start_frame_by_source").is_empty(),"per-source frame tracking is released with the voices")
	_check_budget(audios,"released pool")

func _run() -> void:
	Engine.max_fps = 120
	AudioServer.set_bus_mute(0,true)
	var audios:Node = root.get_node_or_null("Audios")
	_check(audios != null,"Audios autoload present")
	if audios != null:
		await _test_continuous_hits(audios,"子弹打人")
		await _test_continuous_hits(audios,"子弹打墙")
		await _test_saturation(audios)
		_stop_voices(audios)
	for source:AudioStreamPlayer in _test_sources:
		source.queue_free()
	print("AUDIO_CONTINUITY_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	await process_frame
	quit(0 if failures == 0 else 1)
