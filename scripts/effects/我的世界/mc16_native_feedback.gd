extends Node
# Native source audio only. Per-character cue gating, shared 24-voice budget.
const BANK = preload("res://scripts/effects/我的世界/mc16_sound_bank.gd")
var unit:ball
var role:String = ""
var _clock:float = 0.0
var _last:Dictionary = {}
var played:Dictionary = {} # Actual emitted cues; useful for regression checks.
var _last_position:Vector2
var _step_next:float = 0.0
var _step_player:AudioStreamPlayer2D
var _rng := RandomNumberGenerator.new()
var _death_started:bool = false
var _voice_next:Dictionary = {}
var _players:Array[WeakRef] = []
static func attach(target:ball,kind:String) -> Node:
	var node:Node = load("res://scripts/effects/我的世界/mc16_native_feedback.gd").new()
	node.name = "MinecraftFeedback"
	node.unit = target
	node.role = kind
	target.add_child(node)
	return node
func _ready() -> void:
	_last_position = unit.global_position
	_rng.randomize()
func _physics_process(delta:float) -> void: advance(delta)
func advance(delta:float) -> void:
	if not is_instance_valid(unit): return
	var moved:float = _last_position.distance_to(unit.global_position)
	_last_position = unit.global_position
	var active:bool = not _death_started and unit.health>0 and unit.is_combat_runtime_active() and not Game.now_stop_state and not get_tree().paused
	for i:int in range(_players.size()-1,-1,-1):
		var player:Variant = _players[i].get_ref()
		if is_instance_valid(player) and str(player.get_meta("mc_sound_event","")).ends_with(".ambient"):
			player.global_position = unit.global_position
		if not is_instance_valid(player): _players.remove_at(i)
		elif not player.get_meta("mc16_death_voice",false): player.stream_paused = not active
		else: player.stream_paused = get_tree().paused
	if not active: return
	_clock += maxf(delta,0.0)
	if not unit.is_multiplayer_authority() or unit.dizziness: return
	if role=="spider" and float(unit.get("_lunge_left"))>0.0: return
	var walking:bool = moved>0.03 and moved<maxf(48.0,unit.Speed*delta*5.0)
	if not walking or _clock<_step_next: return
	if is_instance_valid(_step_player) and _step_player.playing: return
	_step_player = request("entity."+role+".step",unit.global_position,-17.0,0.0,false)
	if is_instance_valid(_step_player):
		var gap_min:float = maxf(unit.footstep_gap_min,0.05)
		var gap_max:float = maxf(unit.footstep_gap_max,gap_min)
		_step_next = _clock+_step_player.stream.get_length()+_rng.randf_range(gap_min,gap_max)
	else: _step_next = _clock+0.15
# Four creature categories are distinct from cobweb/trident item cues.
func voice(kind:String,volume:float) -> AudioStreamPlayer2D:
	if not is_instance_valid(unit) or not unit.is_multiplayer_authority(): return null
	if kind not in ["ambient","hurt","death"] or get_tree().paused: return null
	if kind!="death" and (unit.health<=0 or _death_started or not unit.is_combat_runtime_active() or Game.now_stop_state): return null
	var player:AudioStreamPlayer2D = _voice_local(kind,volume)
	if is_instance_valid(player) and multiplayer.has_multiplayer_peer(): _receive_voice.rpc(kind,volume)
	return player
@rpc("any_peer","call_remote","reliable")
func _receive_voice(kind:String,volume:float) -> void:
	if not is_instance_valid(unit) or multiplayer.get_remote_sender_id()!=unit.get_multiplayer_authority(): return
	if kind not in ["ambient","hurt","death"] or get_tree().paused: return
	if kind!="death" and (unit.health<=0 or _death_started or Game.now_stop_state): return
	_voice_local(kind,volume)
func _voice_local(kind:String,volume:float) -> AudioStreamPlayer2D:
	if _death_started: return null
	if kind=="death":
		_death_started = true
		for ref:WeakRef in _players:
			var previous:Variant = ref.get_ref()
			if is_instance_valid(previous):
				previous.stop()
				previous.remove_from_group("MCNativeSFX")
				previous.queue_free()
	elif _clock<float(_voice_next.get(kind,-1000.0)): return null
	var player:AudioStreamPlayer2D = _play_local("entity."+role+"."+kind,unit.global_position,volume,kind!="ambient")
	if is_instance_valid(player): _voice_next[kind] = _clock+player.stream.get_length()+0.05
	return player
func request(event:String,point:Vector2,volume:float = -8.0,min_gap:float = 0.12,priority:bool = true) -> AudioStreamPlayer2D:
	if _death_started or not is_instance_valid(unit) or not unit.mc_live() or Game.now_stop_state or get_tree().paused: return null
	if not BANK.EVENTS.has(event): return null
	if _clock-float(_last.get(event,-1000.0))<min_gap: return null
	_last[event] = _clock
	var player:AudioStreamPlayer2D = _play_local(event,point,volume,priority)
	if multiplayer.has_multiplayer_peer(): _receive_sound.rpc(event,point,volume,priority)
	return player
@rpc("any_peer","call_remote","unreliable_ordered")
func _receive_sound(event:String,point:Vector2,volume:float,priority:bool) -> void:
	if not is_instance_valid(unit) or multiplayer.get_remote_sender_id()!=unit.get_multiplayer_authority(): return
	if _death_started or unit.health<=0 or Game.now_stop_state or get_tree().paused: return
	_play_local(event,point,volume,priority)
func cobweb_step(target:ball) -> AudioStreamPlayer2D:
	if _death_started or not unit.mc_live() or Game.now_stop_state or get_tree().paused: return null
	if not is_instance_valid(target) or target.health<=0 or target.dizziness or not unit.mc_enemy(target): return null
	var path:NodePath = get_tree().current_scene.get_path_to(target)
	var player:AudioStreamPlayer2D = _cobweb_step_local(path,target.global_position)
	if multiplayer.has_multiplayer_peer(): _receive_cobweb_step.rpc(path,target.global_position)
	return player
@rpc("any_peer","call_remote","unreliable_ordered")
func _receive_cobweb_step(path:NodePath,point:Vector2) -> void:
	if not is_instance_valid(unit) or multiplayer.get_remote_sender_id()!=unit.get_multiplayer_authority(): return
	if _death_started or unit.health<=0 or Game.now_stop_state or get_tree().paused: return
	_cobweb_step_local(path,point)
func _cobweb_step_local(path:NodePath,point:Vector2) -> AudioStreamPlayer2D:
	if get_tree().current_scene==null: return null
	var target:Node = get_tree().current_scene.get_node_or_null(path)
	if not target is ball or target.health<=0 or not unit.mc_enemy(target): return null
	var previous:Variant = target.get_meta("mc_cobweb_step_player",false)
	var sound:Variant = previous.get_ref() if previous is WeakRef else null
	if is_instance_valid(sound) and sound.playing: return null
	var player:AudioStreamPlayer2D = _play_local("block.cobweb.step",point,-14.0,false)
	if is_instance_valid(player):
		target.set_meta("mc_cobweb_step_player",weakref(player))
		player.set_meta("mc16_web_walker",target.get_instance_id())
	return player
func _play_local(event:String,point:Vector2,volume:float,priority:bool) -> AudioStreamPlayer2D:
	if not BANK.EVENTS.has(event) or get_tree().current_scene==null: return null
	var active:Array[Node] = get_tree().get_nodes_in_group("MCNativeSFX")
	if active.size()>=24:
		if not priority: return null
		var victim:Node
		for candidate:Node in active:
			if not candidate.get_meta("mc_sound_priority",false):
				victim = candidate
				if str(candidate.get_meta("mc_sound_event","")).ends_with(".ambient"): break
		if victim==null and event.ends_with(".death"): victim = active[0]
		if victim==null: return null # Ordinary mechanic cues never steal protected damage/death voices.
		victim.call("stop")
		victim.remove_from_group("MCNativeSFX")
		victim.queue_free()
	var player := AudioStreamPlayer2D.new()
	player.stream = BANK.EVENTS[event].pick_random()
	player.pitch_scale = 1.0
	player.volume_db = clampf(volume,-24.0,2.0)
	player.max_distance = 1700.0
	player.attenuation = 0.65
	if AudioServer.get_bus_index(&"GameplayRecord")>=0: player.bus = &"GameplayRecord"
	get_tree().current_scene.add_child(player)
	player.global_position = point
	player.add_to_group("MCNativeSFX")
	player.add_to_group("MC16MechanicSFX")
	player.add_to_group("BattleTransient")
	player.set_meta("mc_sound_event",event)
	player.set_meta("mc_sound_priority",event.ends_with(".death") or event.ends_with(".hurt"))
	player.set_meta("mc16_death_voice",event.ends_with(".death"))
	player.set_meta("mc16_feedback_source",unit.get_instance_id())
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	_players.append(weakref(player))
	played[event] = int(played.get(event,0))+1
	player.play()
	return player
func _exit_tree() -> void:
	for ref:WeakRef in _players:
		var player:Variant = ref.get_ref()
		if is_instance_valid(player) and not player.get_meta("mc16_death_voice",false):
			player.stop()
			player.queue_free()
