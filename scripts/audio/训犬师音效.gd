extends RefCounted

const SUMMON_WHISTLE:AudioStream = preload("res://audio/characters/训犬师/吹哨.mp3")
const DOG_1:AudioStream = preload("res://audio/characters/训犬师/狗_[cut_0sec].mp3")
const DOG_2:AudioStream = preload("res://audio/characters/训犬师/狗_[cut_0sec] (1).mp3")
const DOG_3:AudioStream = preload("res://audio/characters/训犬师/狗_[cut_0sec] (2).mp3")
const BITE:AudioStream = preload("res://audio/characters/训犬师/DM_20260829214458_001_[cut_0sec].mp3")

static func random_dog_index() -> int:
	return randi_range(0,2)

static func dog_stream_for_index(index:int) -> AudioStream:
	match index:
		1:
			return DOG_2
		2:
			return DOG_3
		_:
			return DOG_1

static func play_summon_whistle_at(host:Node,position_value:Vector2,volume_db:float = -1.0,pitch_scale:float = 1.0) -> void:
	_play_stream_at(host,SUMMON_WHISTLE,position_value,volume_db,pitch_scale)

static func play_dog_at(host:Node,index:int,position_value:Vector2,volume_db:float = -1.0,pitch_scale:float = 1.0) -> void:
	_play_stream_at(host,dog_stream_for_index(index),position_value,volume_db,pitch_scale)

static func play_bite_at(host:Node,position_value:Vector2,volume_db:float = -1.0,pitch_scale:float = 1.0) -> void:
	_play_stream_at(host,BITE,position_value,volume_db,pitch_scale)

static func _play_stream_at(host:Node,stream:AudioStream,position_value:Vector2,volume_db:float,pitch_scale:float) -> void:
	if host == null or not is_instance_valid(host) or stream == null:
		return
	var world:Node = host.get_tree().current_scene
	if world == null:
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
