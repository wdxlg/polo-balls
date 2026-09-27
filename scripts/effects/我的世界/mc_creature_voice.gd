extends Node
## Configurable creature/action cues. Selection is authoritative; allocation,
## bus, priority, global voice budget and scene safety belong to MCNativeAudio.
const QUEUE = preload("res://scripts/effects/我的世界/mc_native_audio.gd")
var unit:ball
var events:Dictionary = {}
var played:Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _serial:int = 0
var _received:int = 0
var _tickets:Array[Dictionary] = []
var _channels:Dictionary = {}
var _ambient_left:float = 3.0
var _step_left:float = 0.0
var _previous:Vector2
var _dying:bool = false

func _ready() -> void:
	set_multiplayer_authority(unit.get_multiplayer_authority())
	process_mode = Node.PROCESS_MODE_ALWAYS
	_previous = unit.global_position
	_rng.randomize() # Audio never consumes combat RNG.

func request(kind:String,point:Vector2,gain:float = 0.0) -> bool:
	if not is_instance_valid(unit) or not unit.is_multiplayer_authority() or not events.has(kind): return false
	if _dying or get_tree().paused or Game.now_stop_state: return false
	if kind != "death" and (unit.health <= 0 or not unit.is_combat_runtime_active()): return false
	if kind in ["ambient","step"] and QUEUE.channel_busy(_channels.get(kind,{})): return false
	var records:Array = events[kind]
	if records.is_empty(): return false
	_serial += 1
	var variant:int = _rng.randi_range(0,records.size()-1)
	_receive(_serial,kind,variant,point,gain)
	if multiplayer.has_multiplayer_peer(): _receive.rpc(_serial,kind,variant,point,gain)
	return true

@rpc("authority","call_remote","reliable")
func _receive(serial:int,kind:String,variant:int,point:Vector2,gain:float) -> void:
	if serial <= _received or not events.has(kind): return
	_received = serial
	var records:Array = events[kind]
	if variant < 0 or variant >= records.size() or _dying: return
	if kind == "death":
		cancel(false)
		_dying = true
	var record:Variant = records[variant]
	var stream:AudioStream = record.get("stream") if record is Dictionary else record
	var pitch:float = float(record.get("pitch",1.0)) if record is Dictionary else 1.0
	var parent:Node = get_tree().current_scene
	if parent is Node2D and unit.get_world_2d() != parent.get_world_2d():
		parent = unit
		while parent.get_parent() is Node2D and parent.get_parent().get_world_2d() == unit.get_world_2d(): parent = parent.get_parent()
	var ticket:Dictionary = QUEUE.queue_stream(unit,stream,point,{
		"audio_parent":parent,"volume_db":gain,"pitch":pitch,
		"priority":kind in ["death","hurt","hit","crit"],"keep_after_source":kind == "death",
		"metadata":{"mc_sound_event":kind,"mc_creature_role":str(unit.name),"mc_creature_variant":variant,"mc_creature_serial":serial}})
	if ticket.is_empty(): return
	ticket["kind"] = kind
	_tickets.append(ticket)
	_channels[kind] = ticket
	played[kind] = int(played.get(kind,0))+1

func _physics_process(delta:float) -> void:
	if not is_instance_valid(unit): return
	var moved:float = unit.global_position.distance_to(_previous)
	_previous = unit.global_position
	var running:bool = not get_tree().paused and not Game.now_stop_state and unit.is_combat_runtime_active()
	for i:int in range(_tickets.size()-1,-1,-1):
		var ticket:Dictionary = _tickets[i]
		var ref:WeakRef = ticket.get("player") as WeakRef
		var player:AudioStreamPlayer2D = ref.get_ref() as AudioStreamPlayer2D if ref != null else null
		if is_instance_valid(player):
			player.stream_paused = not running
			if ticket.kind == "ambient": player.global_position = unit.global_position
		elif ticket.get("state","") != "queued": _tickets.remove_at(i)
	if not running or _dying or unit.health <= 0 or not unit.is_multiplayer_authority(): return
	_ambient_left = maxf(0.0,_ambient_left-delta)
	_step_left = maxf(0.0,_step_left-delta)
	if _ambient_left <= 0.0 and request("ambient",unit.global_position,-5.0): _ambient_left = _rng.randf_range(3.0,7.0)
	if not unit.dizziness and moved > 0.03 and moved < maxf(48.0,unit.Speed*delta*5.0) and _step_left <= 0.0:
		if request("step",unit.global_position,-5.0): _step_left = 0.3

func cancel(keep_death:bool = true) -> void:
	for ticket:Dictionary in _tickets:
		if keep_death and ticket.kind == "death": continue
		ticket["cancel_requested"] = true
		var ref:WeakRef = ticket.get("player") as WeakRef
		var player:AudioStreamPlayer2D = ref.get_ref() as AudioStreamPlayer2D if ref != null else null
		if is_instance_valid(player):
			player.stop()
			player.queue_free()

func _exit_tree() -> void:
	cancel(true)
