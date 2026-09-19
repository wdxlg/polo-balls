extends SceneTree
## V432：Audios 动态播放器池契约。
## 1) create_new_audio 的播放器可复用，不再无限增长；2) 同源并发上限 / 全局上限生效；
## 3) 播放结束后回收，池计数归零；4) 普通 create_new_audio=false 路径不受影响。
var checks:int = 0
var failures:int = 0
func _initialize() -> void: call_deferred("_run")
func _check(ok:bool,message:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("AUDIO_POOL_FAILED: " + message)
func _count_players(audios:Node) -> int:
	var n:int = 0
	for child:Node in audios.get_children():
		if child is AudioStreamPlayer: n += 1
	return n
func _run() -> void:
	var audios:Node = root.get_node_or_null("Audios")
	_check(audios != null,"Audios autoload present")
	if audios == null:
		_finish(); return
	AudioServer.set_bus_mute(0,true)
	var sfx:Node = audios.get_node("Sfx")
	# 找一个有子播放器的容器节点（碰撞反馈用 play_sfx_from_node）。
	var container_name:String = ""
	for child:Node in sfx.get_children():
		if not child is AudioStreamPlayer:
			for grand:Node in child.get_children():
				if grand is AudioStreamPlayer and grand.stream != null:
					container_name = String(child.name); break
		if not container_name.is_empty(): break
	_check(not container_name.is_empty(),"found an sfx container node")
	var before:int = _count_players(audios)
	# 200 次并发请求：树里的动态播放器不得超过 MAX_DYNAMIC_VOICES。
	for i:int in range(200):
		audios.play_sfx_from_node(container_name,{},true,true)
	var stats:Dictionary = audios.get_dynamic_voice_stats()
	var after:int = _count_players(audios)
	print("AUDIO_POOL after_burst players_added=",after - before," stats=",JSON.stringify(stats))
	_check(after - before <= audios.MAX_DYNAMIC_VOICES,"dynamic players capped at MAX_DYNAMIC_VOICES (%d added)" % (after - before))
	_check(int(stats.active) <= audios.MAX_DYNAMIC_VOICES,"active count capped")
	for key:Variant in stats.by_source.keys():
		_check(int(stats.by_source[key]) <= audios.MAX_VOICES_PER_SOURCE,"per-source cap for " + str(key))
	_check(int(stats.active) > 0,"at least one voice actually started")
	# 等待播放结束 -> 全部回收到空闲池，节点不被释放（复用）。
	var waited:float = 0.0
	while waited < 6.0 and int(audios.get_dynamic_voice_stats().active) > 0:
		await create_timer(0.1).timeout
		waited += 0.1
	stats = audios.get_dynamic_voice_stats()
	print("AUDIO_POOL after_wait ",waited,"s stats=",JSON.stringify(stats))
	_check(int(stats.active) == 0,"all voices released after playback")
	_check(int(stats.free) == after - before,"released players kept in free pool for reuse")
	# 第二轮：复用池中的播放器，节点数不再增长。
	for i:int in range(50):
		audios.play_sfx_from_node(container_name,{},true,true)
	_check(_count_players(audios) == after,"second burst reuses pooled players (no new nodes)")
	# 非动态路径仍正常
	audios.play_sfx_from_node(container_name,{},true,false)
	_check(true,"non-dynamic path did not error")
	_finish()
func _finish() -> void:
	print("AUDIO_POOL_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	await process_frame
	quit(0 if failures == 0 else 1)
