extends Node
# 战斗音乐：设置“音乐”选择曲目（本机偏好，不随房间同步）。
# - 战斗实际开始时从头播放：与 World 开场问候同一套条件（结构性开局 + 战斗运行时真的在跑），
#   时间静止 / SceneTree 暂停只会推迟开始，不会被当成新的一局。
# - 重置 / 重打 / 轮放系列重开（Game.battle_session_ended）、战场被清空、离开 World 时停止并回到开头。
# - 播放器走 GameplayRecord 总线：Audios 按 Engine.time_scale 统一调整播放速度（受时间流速影响），
#   播放器本身可暂停，SceneTree 暂停时随游戏声一起暂停；录像同样会录到音乐。

const SETTING_KEY: String = "Battle_Music"
const VOLUME_KEY: String = "Battle_Music_Volume"
const DEFAULT_VOLUME: float = 100.0
const NONE: String = "none"
const BUS: StringName = &"GameplayRecord"
# 曲目登记表：新增音乐只需在这里加一项，并补翻译键 BATTLE_MUSIC_<KEY 大写>。
#   "path"      音频资源路径（.ogg/.mp3/.wav）
#   "loop"      播放完是否从头循环（缺省 true）
#   "volume_db" 可选音量（缺省 0）
const TRACKS: Dictionary = {
	NONE: {},
	"the_king": {"path":"res://audio/music/the_king.mp3","loop":true},
}
# 下拉框顺序。
const OPTIONS: Array[String] = [NONE,"the_king"]

var _game: Node
var _player: AudioStreamPlayer
var _track_key: String = NONE
var _track_loop: bool = true
var _volume_percent: float = DEFAULT_VOLUME
var _world_id: int = 0
# 当前这一局音乐是否已经开始（已开始就不再重复从头播放，直到被停止）。
var _round_active: bool = false


static func normalize(key: Variant) -> String:
	var text: String = str(key)
	return text if TRACKS.has(text) else NONE


static func normalize_volume(value: Variant) -> float:
	if typeof(value) not in [TYPE_INT,TYPE_FLOAT]:
		return DEFAULT_VOLUME
	var amount: float = float(value)
	return clampf(amount,0.0,100.0) if is_finite(amount) else DEFAULT_VOLUME


static func track_stream(key: String) -> AudioStream:
	var entry: Dictionary = TRACKS.get(normalize(key), {})
	var path: String = str(entry.get("path", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream


func _ready() -> void:
	# 控制器需要在暂停时也能处理“重置”；真正出声的播放器随游戏暂停。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_game = get_parent() if get_parent() != null and get_parent().has_signal("game_setting_changed") else get_node_or_null("/root/Game")
	_player = AudioStreamPlayer.new()
	_player.name = "BattleMusicPlayer"
	_player.bus = BUS
	_player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_player)
	_player.finished.connect(_on_player_finished)
	if _game != null:
		_game.game_setting_changed.connect(_on_game_setting_changed)
		if _game.has_signal("battle_session_ended"):
			_game.battle_session_ended.connect(stop_and_rewind)
		_apply_volume(_game.Game_Settings.get(VOLUME_KEY,DEFAULT_VOLUME))
		_apply_track(normalize(_game.Game_Settings.get(SETTING_KEY, NONE)))


func current_track() -> String:
	return _track_key


func is_round_active() -> bool:
	return _round_active


func is_music_playing() -> bool:
	return _player != null and _player.playing


func playback_position() -> float:
	return _player.get_playback_position() if _player != null and _player.playing else 0.0


func player() -> AudioStreamPlayer:
	return _player


# 停止并回到开头；下一次战斗实际开始时重新从头播放。
func stop_and_rewind() -> void:
	_round_active = false
	if _player != null:
		_player.stop()


func _process(_delta: float) -> void:
	_poll_world()


func _poll_world() -> void:
	var world: Node = get_tree().current_scene if is_inside_tree() else null
	if world == null or not world.has_method("is_character_dialogue_battle_active"):
		if _world_id != 0:
			_world_id = 0
			stop_and_rewind()
		return
	var id: int = world.get_instance_id()
	if id != _world_id:
		# 换地图场景 / 重新进入 World：上一场的音乐不带过来。
		_world_id = id
		stop_and_rewind()
	if not _round_started_structurally(world):
		# 战场被清空（联机房客收不到房主的重置调用，也靠这里停下）。
		if _round_active or _player.playing:
			stop_and_rewind()
		return
	if _round_active:
		return
	if not bool(world.call("is_character_dialogue_battle_active")):
		return
	_round_active = true
	_play_from_start()


func _round_started_structurally(world: Node) -> bool:
	# 与 World 开场问候边沿同一个结构判定：手动模式有主战角色，轮放/计时/Boss 已正式开战。
	if world.has_method("_character_dialogue_round_started_structurally"):
		return bool(world.call("_character_dialogue_round_started_structurally"))
	return true


func _play_from_start() -> void:
	if _player == null or _player.stream == null:
		return
	_player.play(0.0)


func _on_player_finished() -> void:
	if _round_active and _track_loop:
		_play_from_start()


func _on_game_setting_changed(setting: String, value: Variant) -> void:
	if setting == VOLUME_KEY:
		_apply_volume(value)
		return
	if setting != SETTING_KEY:
		return
	_apply_track(normalize(value))


func _apply_volume(value: Variant) -> void:
	_volume_percent = normalize_volume(value)
	if _player == null: return
	var entry: Dictionary = TRACKS.get(_track_key,{})
	# Only this player changes; the shared gameplay bus and playback clock stay intact.
	_player.volume_linear = db_to_linear(float(entry.get("volume_db",0.0))) * _volume_percent / 100.0


func _apply_track(key: String) -> void:
	if key == _track_key and _player.stream == track_stream(key):
		return
	_track_key = key
	var entry: Dictionary = TRACKS.get(key, {})
	_track_loop = bool(entry.get("loop", true))
	_player.stop()
	_player.stream = track_stream(key)
	_apply_volume(_volume_percent)
	# 战斗进行中切歌：新曲目从头播放；切到“无”则安静。
	if _round_active:
		_play_from_start()


# 仅供测试：不改登记表，直接给当前曲目换一个流，验证播放/停止/重置流程。
func debug_set_stream(stream: AudioStream, loop: bool = true) -> void:
	_player.stop()
	_player.stream = stream
	_track_loop = loop
	if _round_active:
		_play_from_start()
