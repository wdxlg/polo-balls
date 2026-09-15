extends RefCounted

const WHISTLE_1:AudioStream = preload("res://audio/sfx/战斗/DM_20260829194753_001_[cut_0sec].mp3")
const WHISTLE_2:AudioStream = preload("res://audio/sfx/战斗/DM_20260829194753_001_[cut_0sec] (2).mp3")

static func random_index() -> int:
	return randi_range(0,1)

static func stream_for_index(index:int) -> AudioStream:
	return WHISTLE_2 if index == 1 else WHISTLE_1

static func play_at(host:Node,index:int,position_value:Vector2,volume_db:float = -1.0,pitch_scale:float = 1.0) -> void:
	if host == null or not is_instance_valid(host):
		return
	var world:Node = host.get_tree().current_scene
	if world == null:
		return
	var stream:AudioStream = stream_for_index(index)
	if stream == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.max_distance = 1500.0
	player.attenuation = 0.45
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	world.add_child(player)
	player.global_position = position_value
	player.finished.connect(player.queue_free)
	player.play()
