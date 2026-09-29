extends Node
## Decoded original Minecraft sounds on the UI bus. Four owned voices, no global RNG/timers.
signal sound_played(event:String)
const STREAMS:Dictionary = {
	"tick":preload("res://audio/ui/random_draft/click.tres"),
	"confirm":preload("res://audio/ui/random_draft/orb.tres"),
	"arrival":preload("res://audio/ui/random_draft/pop.tres"),
	"complete":preload("res://audio/ui/random_draft/levelup.tres"),
}
# Stronger local gains; keep the reel softer without changing user bus volume/mute.
const VOLUMES:Dictionary = {"tick":-8.0,"confirm":-3.0,"arrival":-6.0,"complete":-3.0}
const COOLDOWNS:Dictionary = {"tick":100,"confirm":220,"arrival":170}
var _players:Dictionary = {}
var _last_played:Dictionary = {}
var played_counts:Dictionary = {}
var _ticks_enabled:bool = false
var _closed:bool = false
var _completed:bool = false
var _quiet_until:int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Audios._ensure_audio_bus(Audios.UI_BUS)
	for event:String in STREAMS:
		var player := AudioStreamPlayer.new()
		player.name = "Draft_"+event
		player.stream = STREAMS[event]
		player.bus = Audios.UI_BUS
		player.volume_db = VOLUMES[event]
		player.max_polyphony = 1
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		# Use the existing clock compensation: UI pitch stays normal at game 0x/2x.
		Audios._set_logical_pitch(player,1.0)
		_players[event] = player

func reset_round() -> void:
	stop_all()
	_closed = false
	_completed = false
	_last_played.clear()
	played_counts.clear()
	_quiet_until = 0

func begin_ticket() -> void:
	if not _closed and not _completed: _ticks_enabled = true

func stop_ticks() -> void:
	_ticks_enabled = false
	if _players.has("tick"): _players.tick.stop()

func play_tick() -> bool:
	if not _ticks_enabled or Time.get_ticks_msec()<_quiet_until: return false
	return _play("tick")

func play_confirmation() -> bool:
	stop_ticks()
	_quiet_until = Time.get_ticks_msec()+160
	return _play("confirm")

func play_arrival() -> bool:
	return _play("arrival")

func play_complete() -> bool:
	if _closed or _completed: return false
	stop_ticks()
	_players.confirm.stop()
	_players.arrival.stop()
	var played:bool = _play("complete")
	_completed = true
	return played

func completion_duration() -> float:
	return float(STREAMS.complete.get_length())+0.06

func _play(event:String) -> bool:
	if _closed or _completed or not _players.has(event): return false
	var now:int = Time.get_ticks_msec()
	if now-int(_last_played.get(event,-100000))<int(COOLDOWNS.get(event,0)): return false
	_last_played[event] = now
	var player:AudioStreamPlayer = _players[event]
	# Each role reuses a single voice, so dense drafts cannot accumulate audio nodes.
	player.stop()
	Audios._set_logical_pitch(player,1.0)
	player.play()
	played_counts[event] = int(played_counts.get(event,0))+1
	sound_played.emit(event)
	return true

func stop_all() -> void:
	_closed = true
	_ticks_enabled = false
	for player:AudioStreamPlayer in _players.values(): player.stop()

func _exit_tree() -> void:
	stop_all()
