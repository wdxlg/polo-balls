extends Node
## Three independent finish-before-replay channels. Chosen variants replicate from the authority.
var actor:Node2D
var rng:=RandomNumberGenerator.new()
var waits:Dictionary={"breath":1.2,"tendril":0.0,"step":0.0}
var players:Dictionary={}
var last_duration:Dictionary={}
var counts:Dictionary={}
var tendril_chance:float=0.35
var step_chance:float=0.35
var _step_sample:float=0.0
var _previous_position:Vector2
var _serial:int=0
var _received:int=0
var _streams:Dictionary={}
func _ready() -> void:
	rng.randomize()
	_previous_position=actor.global_position
	waits.breath=rng.randf_range(1.0,2.0)
func running() -> bool:
	return is_instance_valid(actor) and actor.health>0 and actor.is_combat_runtime_active() and not Game.now_stop_state and not get_tree().paused
func stream_for(event:String,index:int) -> AudioStream:
	var key:String=event+"_"+str(index)
	if not _streams.has(key): _streams[key]=load("res://audio/characters/我的世界/warden_voice/"+key+".ogg")
	return _streams[key]
func _process(delta:float) -> void:
	var live:bool=running()
	for p:Variant in players.values():
		if is_instance_valid(p):
			p.stream_paused=not live
			p.global_position=actor.global_position
	if not live: return
	var moved:bool=actor.global_position.distance_squared_to(_previous_position)>0.04
	_previous_position=actor.global_position
	if not actor.is_multiplayer_authority(): return
	for key:Variant in waits: waits[key]=maxf(0.0,float(waits[key])-delta)
	if actor.form!=actor.Form.AWAKE: return
	if float(waits.breath)<=0.0: play_channel("breath","angry" if actor.rage_left>0.0 else "ambient",-4.0)
	_step_sample=maxf(0.0,_step_sample-delta)
	if moved and actor.velocity.length_squared()>4.0 and not actor.dizziness and _step_sample<=0.0:
		_step_sample=0.25
		if rng.randf()<step_chance: play_channel("step","step",-4.0)
func heard() -> void:
	if running() and actor.is_multiplayer_authority() and actor.form in [actor.Form.DORMANT,actor.Form.AWAKE] and rng.randf()<tendril_chance:
		play_channel("tendril","tendril",-2.0)
func roar() -> void:
	if running() and actor.is_multiplayer_authority(): play_channel("roar","roar",0.0)
func play_channel(channel:String,event:String,volume:float) -> bool:
	if not running() or not actor.is_multiplayer_authority() or float(waits.get(channel,0.0))>0.0: return false
	var previous:Variant=players.get(channel)
	if is_instance_valid(previous) and previous.playing: return false
	var index:int=rng.randi_range(1,2)
	var stream:AudioStream=stream_for(event,index)
	if stream==null: return false
	var gap:float=rng.randf_range(0.8,2.0) if channel=="breath" else rng.randf_range(0.3,0.9)
	last_duration[channel]=stream.get_length()
	waits[channel]=stream.get_length()+gap
	_serial+=1
	if multiplayer.has_multiplayer_peer(): _voice_event.rpc(_serial,channel,event,index,volume)
	_voice_event(_serial,channel,event,index,volume)
	return true
@rpc("authority","call_remote","reliable")
func _voice_event(serial:int,channel:String,event:String,index:int,volume:float) -> void:
	if serial<=_received or not is_instance_valid(actor) or actor.health<=0: return
	_received=serial
	var stream:AudioStream=stream_for(event,index)
	if stream==null: return
	var previous:Variant=players.get(channel)
	if is_instance_valid(previous): previous.stop(); previous.queue_free()
	var voices:Array[Node]=get_tree().get_nodes_in_group("MCNativeSFX")
	if voices.size()>=24:
		var oldest:Node=voices[0]
		for candidate:Node in voices:
			if not candidate.get_meta("mc_sound_priority",false): oldest=candidate; break
		oldest.remove_from_group("MCNativeSFX")
		oldest.call("stop"); oldest.queue_free()
	var p:=AudioStreamPlayer2D.new()
	p.stream=stream; p.volume_db=volume; p.max_distance=1300.0; p.attenuation=0.7
	if AudioServer.get_bus_index(&"GameplayRecord")>=0: p.bus=&"GameplayRecord"
	add_child(p); p.top_level=true; p.global_position=actor.global_position
	p.add_to_group("MCNativeSFX"); p.set_meta("warden_voice",event)
	p.set_meta("mc_sound_priority",channel=="roar")
	players[channel]=p; counts[channel]=int(counts.get(channel,0))+1
	p.finished.connect(p.queue_free,CONNECT_ONE_SHOT)
	p.play()
