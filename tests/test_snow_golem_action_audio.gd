extends "res://tests/test_mc_snow_golem.gd"
## Real World movement/collision, original streams and actual AudioEffectCapture output.
var unit:Node2D
var target:Node2D
var capture:AudioEffectCapture
var probe_bus:int = -1
var probe_name:StringName = &"SnowGolemActionProbe"
var selected_event:String = ""
var seen:Array[Dictionary] = []
var evidence:String
var metrics:Array = []
var bank:Script

func settle() -> void:
	await process_frame
	await physics_frame
	await process_frame

func select_event(event:String) -> void:
	selected_event = event
	capture.clear_buffer()

func trace_player(node:Node) -> void:
	if not node is AudioStreamPlayer2D: return
	var records:Array = bank.NATIVE.EVENTS.get(selected_event,bank.PHASES.EVENTS.get(selected_event,[]))
	for record:Dictionary in records:
		if node.stream==record.stream:
			node.bus = probe_name
			seen.append({"event":selected_event,"point":node.global_position,"started":Time.get_ticks_msec(),"stream":node.stream.resource_path,"length":node.stream.get_length()/maxf(node.pitch_scale,0.01),"gain":node.volume_db,"reason":node.get_meta("mc_snow_action_reason","")})
			break

func pcm(event:String) -> float:
	var tail:float = 0.18
	if event=="burst_launch":
		# Keep the complete last native tail in the listenable recording.
		for record:Dictionary in bank.NATIVE.EVENTS["entity.snow_golem.shoot"]:
			tail = maxf(tail,record.stream.get_length()/maxf(float(record.pitch)*AudioServer.playback_speed_scale,0.01)+0.15)
	await create_timer(tail,true,false,true).timeout
	var data:PackedVector2Array = capture.get_buffer(capture.get_frames_available())
	var peak:float = 0.0
	for sample:Vector2 in data: peak=maxf(peak,maxf(absf(sample.x),absf(sample.y)))
	check(data.size()>128 and peak>0.00001,"real mixed PCM is audible for "+event)
	if event=="burst_launch":
		var wav:=AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = int(AudioServer.get_mix_rate())
		wav.stereo = true
		var bytes:=PackedByteArray(); bytes.resize(data.size()*4)
		for i:int in range(data.size()):
			bytes.encode_s16(i*4,int(clampf(data[i].x,-1.0,1.0)*32767.0))
			bytes.encode_s16(i*4+2,int(clampf(data[i].y,-1.0,1.0)*32767.0))
		wav.data = bytes
		check(wav.save_to_wav(evidence.path_join("twenty_shots.wav"))==OK,"actual mixed twenty-shot PCM saved as listenable evidence")
	metrics.append({"event":event,"frames":data.size(),"peak":peak})
	print("GOLEM_ACTION_PCM event=",event," frames=",data.size()," peak=",peak)
	return peak

func quiet() -> void:
	await settle()
	for sound:Node in get_nodes_in_group("MCNativeSFX"):
		if sound is AudioStreamPlayer2D: sound.stop(); sound.free()
	await process_frame
	capture.clear_buffer()

func finish(code:int) -> void:
	if done: return
	if node_added.is_connected(trace_player): node_added.disconnect(trace_player)
	if probe_bus>=0: AudioServer.remove_bus(probe_bus)
	if not evidence.is_empty():
		var f:=FileAccess.open(evidence.path_join("metrics.json"),FileAccess.WRITE)
		f.store_string(JSON.stringify({"checks":checks,"failures":failures,"metrics":metrics,"sounds":seen},"\t"));f.close()
	print("GOLEM_ACTION_AUDIO_RESULT checks=",checks," failures=",failures)
	await super.finish(code)

func run() -> void:
	game = root.get_node("Game")
	var original:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Environment = "none"
	var center:Vector2 = await setup_world()
	saved = original
	create_timer(120,true,false,true).timeout.connect(func():finish(2))
	evidence = OS.get_environment("GOLEM_ACTION_EVIDENCE_DIR")
	if evidence.is_empty(): evidence = "user://golem_action_audio"
	DirAccess.make_dir_recursive_absolute(evidence)
	bank = load("res://scripts/characters/我的世界/snow_golem/audio.gd")
	unit = spawn(GOLEM_PATH,center)
	unit.set_physics_process(false)
	unit.hurt_voice_chance = 0.0
	unit._field.set_physics_process(false)
	unit.burst_probability = 0.0
	unit.Can_Attack = false
	target = dummy(center+Vector2(120,0))
	target.set_physics_process(false)
	world.set_process(false)
	world.set_physics_process(false)
	var camera:=Camera2D.new()
	world.add_child(camera)
	camera.global_position = center
	camera.make_current()
	camera.force_update_scroll()
	probe_bus = AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(probe_bus,probe_name)
	capture = AudioEffectCapture.new()
	capture.buffer_length = 8.0
	AudioServer.add_bus_effect(probe_bus,capture)
	node_added.connect(trace_player)
	await settle()
	await quiet()
	unit._aim_hold_left = 0.0
	unit.direction = Vector2.RIGHT
	unit.move(0.0,1.0/60.0)
	check(unit._aim_pose==2,"normal rightward heading uses the front-right diagonal view")
	unit.direction = Vector2.LEFT
	unit.move(0.0,1.0/60.0)
	check(unit._aim_pose==6,"normal leftward heading uses the front-left diagonal view")
	unit.direction = Vector2.UP
	unit.move(0.0,1.0/60.0)
	check(unit._aim_pose==6,"vertical walking retains the previous horizontal side rather than showing the back")
	unit.direction = Vector2.RIGHT
	select_event("block.snow.step")
	var count:int = seen.size()
	var gameplay_rng:int = unit.rng.state
	for frame:int in range(48):
		unit.move(unit.Speed,1.0/60.0)
		await physics_frame
	check(seen.size()>count,"actual ordinary movement starts native snow footsteps")
	await pcm("walking")
	await quiet()
	# A real wall contact, not a manually emitted sound callback.
	var wall:=StaticBody2D.new()
	wall.collision_layer = 1
	var shape:=RectangleShape2D.new()
	shape.size = Vector2(6,120)
	var collider:=CollisionShape2D.new()
	collider.shape = shape
	wall.add_child(collider)
	world.add_child(wall)
	wall.global_position = unit.global_position+Vector2(35,0)
	unit.direction = Vector2.RIGHT
	await physics_frame
	var bounced:bool = false
	count = seen.size()
	select_event("block.snow.step")
	for frame:int in range(95):
		unit.move(unit.Speed,1.0/60.0)
		bounced = bounced or unit.direction.x<0
		await physics_frame
	check(bounced,"fixture produces a real shared-physics wall rebound")
	check(seen.size()>count,"footstep channel remains audible through a real wall rebound")
	check(unit._aim_pose==6,"rebound changes the walking side without a rear-facing pose")
	check(seen.any(func(s):return s.reason=="wall"),"real contact requests one cadence-limited snow impact cue")
	await pcm("wall_rebound")
	check(unit.rng.state==gameplay_rng,"movement variants do not consume the volley gameplay RNG")
	var previous:Dictionary = {}
	var spaced:bool = true
	for sound:Dictionary in seen:
		if sound.event!="block.snow.step" or sound.reason!="walk": continue
		if not previous.is_empty(): spaced = spaced and float(sound.started-previous.started)>=unit.FOOTSTEP.MIN_INTERVAL*1000.0-3.0
		previous = sound
	check(spaced,"walking footsteps never come faster than the minimum cadence interval")
	wall.queue_free()
	await quiet()
	count = seen.size()
	unit.Repel = Vector2.ZERO
	unit.direction = Vector2.ZERO
	for frame:int in range(25):
		unit.stand(1.0/60.0)
		await physics_frame
	check(seen.size()==count,"stationary actor has no synthetic footstep loop")
	unit.Can_Attack = true
	target.global_position = unit.global_position+Vector2(0,-120)
	select_event("entity.snow_golem.shoot")
	unit._shot_left = 0.0
	check(unit.fire_at(target.global_position,target),"one ordinary attack really emits a snowball")
	check(unit._aim_pose==12,"firing temporarily uses the true target heading, including upward aim")
	await settle()
	check(seen.any(func(s):return s.event=="entity.snow_golem.shoot" and s.gain>=0.0),"launch cue has a clear zero-dB baseline rather than an extra quiet offset")
	await pcm("snowball_launch")
	unit._aim_hold_left = 0.0
	unit.direction = Vector2.RIGHT
	unit.move(0.0,1.0/60.0)
	check(unit._aim_pose==2,"after attack recovery normal facing returns to the right diagonal")
	await quiet()
	select_event("block.wood.break")
	unit.take_damage(ceilf(unit.Max_health*0.5),true)
	await settle()
	check(not unit.has_pumpkin and unit.force_next_burst,"real half-health transition preserves the guaranteed-next-volley mechanic")
	await pcm("pumpkin_break")
	await check_channels_and_lifetime()
	await finish(0 if failures==0 else 1)

func check_channels_and_lifetime() -> void:
	await quiet()
	unit._shot_left = 0.0
	unit.burst_probability = 1.0
	unit.set_player_control_peer(1)
	unit.set_player_control_aim_position(target.global_position)
	select_event("entity.snow_golem.shoot")
	var old:int = unit.shots_fired
	var first_sound:int = seen.size()
	check(unit.fire_at(target.global_position,target),"audible burst starts from the production attack entry")
	while unit._burst_remaining>0:
		unit.step_mob(1.0/60.0)
		await physics_frame
	await settle()
	check(unit.shots_fired-old==20,"audibility changes do not add or discard burst projectiles")
	var launches:Array = seen.slice(first_sound)
	check(launches.size()==20,"every one of the twenty actual projectiles starts its own native launch sound")
	var overlap:bool = false
	for i:int in range(1,launches.size()): overlap = overlap or float(launches[i].started-launches[i-1].started)<float(launches[i-1].length)*1000.0
	check(overlap,"rapid launch sounds overlap naturally instead of waiting for the previous clip")
	await pcm("burst_launch")
	await check_overlapping_launch_lifecycle()
	# Retire real projectiles/cold before a controlled voice-budget probe; their
	# later impacts must not be confused with deliberately inserted filler voices.
	for shot:Node in get_nodes_in_group("MCSnowball"):
		if shot.Master==unit: shot.queue_free()
	clear_cold(target)
	await quiet()
	await create_timer(bank.NATIVE.EVENTS["entity.snow_golem.shoot"][0].stream.get_length()+0.05,true,false,true).timeout
	await quiet()
	var fillers:Array[AudioStreamPlayer2D] = []
	for i:int in range(24-get_nodes_in_group("MCNativeSFX").size()):
		var filler:=AudioStreamPlayer2D.new()
		world.add_child(filler)
		filler.add_to_group("MCNativeSFX")
		filler.set_meta("mc_sound_priority",false)
		fillers.append(filler)
	check(get_nodes_in_group("MCNativeSFX").size()==24,"voice-budget fixture starts at exactly 24, not an already-overfull mixer")
	check(unit._request_action_sound("entity.snow_golem.shoot","budget_probe",0.0),"launch remains accepted when low-priority voices fill the common budget")
	await settle()
	var player:AudioStreamPlayer2D = bank.action_player(unit._shoot_audio)
	check(is_instance_valid(player) and player.playing and get_nodes_in_group("MCNativeSFX").size()<=24,"important launch replaces low-priority chatter without bypassing the 24-voice budget")
	check(player.bus==probe_name or player.bus==&"GameplayRecord","native action retains the standard recording route")
	await pcm("crowded_launch")
	await quiet()
	await create_timer(0.30,true,false,true).timeout
	game.now_stop_state = true
	check(not unit._request_action_sound("block.snow.step","walk",-3.0) and not unit._request_action_sound("entity.snow_golem.shoot","shot",0.0),"paused battle starts neither footstep nor launch cues")
	game.now_stop_state = false
	# No source deletion is required to cancel an unflushed action request.
	check(unit._request_action_sound("block.snow.step","queued_cancel",-3.0),"real common queue accepts a pending movement cue")
	var ticket:Dictionary = unit._step_audio
	unit._stop_movement_and_launch_audio()
	await settle()
	check(ticket.get("state","")=="cancelled" and not is_instance_valid(bank.action_player(ticket)),"cancelled queued action does not allocate or play a late ghost voice")
	var no_parent:=Node2D.new()
	world.add_child(no_parent)
	var native:Script = bank.ACTION_PLAYER
	var options:Dictionary = {"audio_parent":no_parent,"groups":[&"MCSnowSound"],"metadata":{"mc_sound_event":"parent_cancel_probe"}}
	ticket = native.queue_stream(unit,bank.NATIVE.EVENTS["block.snow.step"][0].stream,unit.global_position,options)
	no_parent.queue_free()
	await settle()
	check(ticket.get("state","")=="cancelled" and not is_instance_valid(bank.action_player(ticket)),"deleting an opt-in sound parent safely cancels the queued voice")
	var dying:Node2D = spawn(GOLEM_PATH,unit.global_position+Vector2(35,0))
	dying.state_machine.set_physics_process(false)
	dying.set_physics_process(false)
	dying.hurt_voice_chance = 0.0
	select_event("block.wood.break")
	dying.take_damage(ceilf(dying.Max_health*0.5),true)
	ticket = dying._break_audio
	dying.free()
	await settle()
	check(is_instance_valid(bank.action_player(ticket)),"already-triggered pumpkin break survives source removal without an orphan player")
	await pcm("break_after_source_removal")

func check_overlapping_launch_lifecycle() -> void:
	await quiet()
	var first:int = seen.size()
	var pending:Array[Dictionary] = []
	for i:int in range(4):
		check(unit._request_action_sound("entity.snow_golem.shoot","overlap_probe",0.0),"busy launch channel accepts another shot "+str(i))
		pending.append(unit._shoot_audio)
	await settle()
	check(seen.size()-first==4,"four requests become four real audio players, not merely accepted tickets")
	var all_playing:bool = true
	for ticket:Dictionary in pending:
		var voice:AudioStreamPlayer2D = bank.action_player(ticket)
		all_playing = all_playing and is_instance_valid(voice) and voice.playing
	check(all_playing,"earlier launch tails are not restarted or stopped by subsequent shots")
	game.now_stop_state = true; unit._process(0.0)
	var all_paused:bool = true
	for ticket:Dictionary in pending: all_paused = all_paused and bank.action_player(ticket).stream_paused
	check(all_paused,"pause freezes ALL overlapping launch voices, not only the newest")
	game.now_stop_state = false; unit._process(0.0)
	var all_resumed:bool = true
	for ticket:Dictionary in pending: all_resumed = all_resumed and not bank.action_player(ticket).stream_paused
	check(all_resumed,"resume restores every overlapping launch voice")
	unit._stop_movement_and_launch_audio()
	check(unit._shoot_voices.is_empty(),"explicit retirement releases the whole launch ticket collection")
	await settle()
	var all_gone:bool = true
	for ticket:Dictionary in pending: all_gone = all_gone and not is_instance_valid(bank.action_player(ticket))
	check(all_gone,"retirement leaves no older orphaned launch players")
	pending.clear()
	first = seen.size()
	for i:int in range(4):
		unit._request_action_sound("entity.snow_golem.shoot","queued_overlap_cancel",0.0)
		pending.append(unit._shoot_audio)
	unit._stop_movement_and_launch_audio()
	await settle()
	check(seen.size()==first and pending.all(func(t):return t.get("state","")=="cancelled"),"all unflushed overlapping launches cancel before allocation")
	check(unit._request_action_sound("block.snow.step","walk",-3.0),"first actual movement cue accepted")
	check(unit._request_action_sound("block.snow.step","walk",-3.0),"a second footstep may start before the previous one ends")
	unit._stop_movement_and_launch_audio()
	await settle()

	# Source lifecycle must retire every voice, even without a subsequent attack.
	var removed:Node2D = spawn(GOLEM_PATH,unit.global_position+Vector2(50,0))
	removed.set_physics_process(false)
	pending.clear()
	for i:int in range(3):
		removed._request_action_sound("entity.snow_golem.shoot","exit_probe",0.0)
		pending.append(removed._shoot_audio)
	removed.free()
	await settle()
	check(pending.all(func(t):return t.get("state","")=="cancelled" and not is_instance_valid(bank.action_player(t))),"source exit cancels ALL queued shot voices")
	var dying:Node2D = spawn(GOLEM_PATH,unit.global_position+Vector2(70,0))
	dying.set_physics_process(false)
	pending.clear()
	for i:int in range(3):
		dying._request_action_sound("entity.snow_golem.shoot","death_probe",0.0)
		pending.append(dying._shoot_audio)
	await settle()
	dying.health = 0
	dying._process(0.0)
	await settle()
	check((not is_instance_valid(dying) or dying._shoot_voices.is_empty()) and pending.all(func(t):return not is_instance_valid(bank.action_player(t))),"death retires ALL already-playing shot voices before source removal")
	if is_instance_valid(dying): dying.queue_free()
