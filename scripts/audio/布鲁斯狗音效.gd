extends RefCounted

# 训犬师只“借用”布鲁斯原项目里的声音，不复制布鲁斯音频。
# V91：不能再假设素材文件名一定包含“狗叫/咬人”。优先按布鲁斯目录+关键词匹配；
# 如果布鲁斯目录里的文件是数字名/原素材名，则按实际 AudioStream 长度做稳定兜底配对；
# 最后才在整个 audio/ 树按狗叫/咬击关键词兜底，避免训犬师再次完全静音。

static var _resolved:bool = false
static var _bark_stream:AudioStream = null
static var _bite_stream:AudioStream = null

static func get_bark_stream() -> AudioStream:
	_resolve_once()
	# 第一次调用时如果资源导入/文件系统尚未完全就绪，允许下一次重新扫描。
	if _bark_stream == null:
		_resolved = false
		_resolve_once()
	return _bark_stream

static func get_bite_stream() -> AudioStream:
	_resolve_once()
	if _bite_stream == null:
		_resolved = false
		_resolve_once()
	return _bite_stream

static func _resolve_once() -> void:
	if _resolved:
		return
	_resolved = true

	var all_files:Array[String] = []
	_collect_audio_files("res://audio",all_files,8)
	all_files = _unique_sorted(all_files)

	var bruce_files:Array[String] = []
	for path:String in all_files:
		var lower:String = path.to_lower()
		if "布鲁斯" in path or "bruce" in lower:
			bruce_files.append(path)

	# 仍然优先使用明确命名的布鲁斯音频。
	_bite_stream = _first_matching_stream(bruce_files,["咬人","狗咬","咬","bite","attack","hit"])
	_bark_stream = _first_matching_stream(bruce_files,["狗叫","犬吠","汪","bark","woof","叫"],[_bite_stream])

	# V91 关键修复：布鲁斯素材若使用数字/原素材文件名，不能因为没有关键词就静音。
	_fallback_bruce_streams(bruce_files)

	# 如果完整项目里布鲁斯音频并不放在布鲁斯目录，最后才按全 audio 文件名查找。
	if _bite_stream == null:
		_bite_stream = _first_matching_stream(all_files,["布鲁斯咬","狗咬","咬人","dog_bite","dog bite","bite"])
	if _bark_stream == null:
		_bark_stream = _first_matching_stream(all_files,["布鲁斯叫","狗叫","犬吠","汪","dog_bark","dog bark","bark","woof"],[_bite_stream])

	# 最后的“可听见”兜底只使用项目里已经确认存在的狗叫素材；布鲁斯资源一旦找到始终优先。
	if _bark_stream == null:
		_bark_stream = _load_audio_if_exists("res://audio/characters/meme/大狗叫/大狗短叫.wav")

static func _fallback_bruce_streams(bruce_files:Array[String]) -> void:
	if bruce_files.is_empty() or (_bark_stream != null and _bite_stream != null):
		return
	var candidates:Array[Dictionary] = []
	for path:String in bruce_files:
		var stream:AudioStream = _load_audio_if_exists(path)
		if stream == null:
			continue
		candidates.append({"stream":stream,"path":path,"length":maxf(stream.get_length(),0.0)})
	if candidates.is_empty():
		return

	# 文件名没有任何语义时：较长的一般更像完整狗叫，较短的一般更像短促咬击。
	# 这是布鲁斯目录内部的兜底，不会拿其它角色的声音优先覆盖它。
	if _bark_stream == null:
		var longest:Dictionary = candidates[0]
		for entry:Dictionary in candidates:
			if float(entry.get("length",0.0)) > float(longest.get("length",0.0)):
				longest = entry
		_bark_stream = longest.get("stream") as AudioStream

	if _bite_stream == null:
		var shortest:Dictionary = candidates[0]
		for entry:Dictionary in candidates:
			var stream:AudioStream = entry.get("stream") as AudioStream
			if candidates.size() > 1 and stream == _bark_stream:
				continue
			var shortest_stream:AudioStream = shortest.get("stream") as AudioStream
			if candidates.size() > 1 and shortest_stream == _bark_stream:
				shortest = entry
				continue
			if float(entry.get("length",0.0)) < float(shortest.get("length",0.0)):
				shortest = entry
		_bite_stream = shortest.get("stream") as AudioStream

static func _unique_sorted(files:Array[String]) -> Array[String]:
	var seen:Dictionary = {}
	var result:Array[String] = []
	for path:String in files:
		if seen.has(path):
			continue
		seen[path] = true
		result.append(path)
	result.sort()
	return result

static func _collect_audio_files(base:String,out:Array[String],depth:int) -> void:
	if depth < 0:
		return
	var dir := DirAccess.open(base)
	if dir == null:
		return
	for file_name:String in dir.get_files():
		var ext:String = file_name.get_extension().to_lower()
		if ext in ["mp3","wav","ogg","sfxr"]:
			out.append(base.path_join(file_name))
	if depth == 0:
		return
	for child:String in dir.get_directories():
		_collect_audio_files(base.path_join(child),out,depth - 1)

static func _first_matching_stream(files:Array[String],keywords:Array[String],excluded_streams:Array = []) -> AudioStream:
	for path:String in files:
		var name_lower:String = path.get_file().to_lower()
		var matched:bool = false
		for keyword:String in keywords:
			if keyword.to_lower() in name_lower:
				matched = true
				break
		if not matched:
			continue
		var stream:AudioStream = _load_audio_if_exists(path)
		if stream != null and not excluded_streams.has(stream):
			return stream
	return null

static func _load_audio_if_exists(path:String) -> AudioStream:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var resource:Resource = ResourceLoader.load(path)
	if resource is AudioStream:
		return resource as AudioStream
	return null

static func play_at(host:Node,stream:AudioStream,position_value:Vector2,volume_db:float = 0.0,pitch_scale:float = 1.0) -> void:
	if host == null or not is_instance_valid(host) or stream == null:
		return
	var world:Node = host.get_tree().current_scene
	if world == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.max_distance = 1300.0
	player.attenuation = 0.5
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	world.add_child(player)
	player.global_position = position_value
	player.finished.connect(player.queue_free)
	player.play()
