extends RefCounted
## Original Java 1.21.5 OGGs, content-addressed and verified by assets.lock.json.
const CUES:PackedStringArray = ["probe_fire","summon_shriek","shrieker","emerge","sonic_charge","sonic_boom","warden_hit","warden_hurt","warden_dig","moss","bonemeal","compost","break","craft","minecart"]
static var _streams:Dictionary = {}
static var _last:Dictionary = {}
static func play(context:Node,event:String,point:Vector2,volume_db:float = -7.0) -> AudioStreamPlayer2D:
	if not is_instance_valid(context) or not context.is_inside_tree() or event not in CUES: return null
	var tree:SceneTree = context.get_tree()
	if tree.paused or Game.now_stop_state or tree.current_scene == null: return null
	if context.has_method("is_combat_runtime_active") and not context.is_combat_runtime_active(): return null
	var now:int = Time.get_ticks_msec()
	var priority:bool=event in ["probe_fire","summon_shriek","shrieker","emerge","sonic_charge","sonic_boom","warden_hit","warden_hurt","warden_dig"]
	var key:String=str(context.get_instance_id())+":"+event if priority else event
	# Each successfully emitted probe has its own sound; other Wardens cannot suppress it.
	if event!="probe_fire" and now-int(_last.get(key,-10000)) < 120: return null
	var voices:Array[Node]=tree.get_nodes_in_group("MCNativeSFX")
	if voices.size()>=24:
		if not priority: return null
		var oldest:Node=voices[0]
		oldest.remove_from_group("MCNativeSFX")
		if oldest is AudioStreamPlayer2D: oldest.stop()
		oldest.queue_free()
	var asset:String="shrieker" if event=="summon_shriek" else "sonic_boom" if event=="probe_fire" else event
	if not _streams.has(event): _streams[event] = load("res://audio/characters/我的世界/frontier/"+asset+".ogg")
	var stream:AudioStream = _streams[event] as AudioStream
	if stream == null: return null
	_last[key] = now
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = clampf(volume_db,-24.0,2.0 if priority else 0.0)
	player.max_distance = 1300.0
	player.attenuation = 0.7
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0: player.bus = &"GameplayRecord"
	context.add_child(player)
	player.top_level = true
	player.global_position = point
	player.add_to_group("MCNativeSFX")
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()
	return player
