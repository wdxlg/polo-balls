extends "res://tests/test_heavenfall_tuning_audio.gd"
# Real GameplayRecord mixer output after an actual arrival. No source-file proxy.
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Camera_Move = false
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	Engine.time_scale = 1.0
	AudioServer.set_bus_mute(0, true) # Capture upstream of Master, avoid desktop playback.
	create_timer(50.0, true, false, true).timeout.connect(func(): finish(2))
	sounds = load("res://scripts/characters/我的世界/new5/audio.gd")
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world, CONNECT_ONE_SHOT)
	root.add_child(world)
	world.control.hide()
	await create_timer(0.6).timeout
	var center: Vector2 = world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	world.camera_2d.global_position = center
	world.camera_2d.position_smoothing_enabled = false
	world.camera_2d.force_update_scroll()
	for node: Node in get_nodes_in_group("Ball"):
		node.process_mode = Node.PROCESS_MODE_DISABLED
		node.remove_from_group("Ball")
		(node as Node2D).global_position = Vector2(-4000,-4000)
	bow = spawn("res://scenes/characters/我的世界/天堂陨落长弓.tscn", center + Vector2(-40,0))
	bow.state_machine.set_physics_process(false)
	bow.set_process(false)
	var bus: int = AudioServer.get_bus_index("GameplayRecord")
	AudioServer.set_bus_mute(bus,false)
	AudioServer.set_bus_volume_db(bus,0.0)
	var cap := AudioEffectCapture.new()
	cap.buffer_length = 2.0
	AudioServer.add_bus_effect(bus,cap)
	var effect_index: int = AudioServer.get_bus_effect_count(bus)-1
	clear_sounds()
	_mature_rift_fixture(bow,center,801)
	bow._apply_rift_dodge(bow.global_position,center,801,center)
	clear_sounds() # Isolate arrival output, not the preceding teleport.
	await create_timer(0.08).timeout
	cap.clear_buffer()
	bow._advance_rift_transit(bow.TRANSIT.EXIT_AT+0.001)
	var waves: Array[Node] = event_nodes("entity.heavenfall.wave")
	check(waves.size()==1,"actual arrival creates one wave player")
	if not waves.is_empty():
		var p: Node = waves[0]
		print("WAVE_PLAYER: bus=",p.bus," gain=",p.volume_db," playing=",p.playing," position=",p.global_position," stream=",p.stream.resource_path," seconds=",p.stream.get_length()," audio_driver=",AudioServer.get_driver_name())
	await create_timer(0.65).timeout
	var frames: PackedVector2Array = cap.get_buffer(cap.get_frames_available())
	var peak: float = 0.0
	var energy: float = 0.0
	var active_frames: int = 0
	var pcm := PackedByteArray()
	pcm.resize(frames.size()*4)
	for i in range(frames.size()):
		var value: Vector2 = frames[i]
		peak = maxf(peak,maxf(absf(value.x),absf(value.y)))
		energy += value.length_squared()*0.5
		if maxf(absf(value.x),absf(value.y))>0.003: active_frames+=1
		pcm.encode_s16(i*4,int(clampf(value.x,-1,1)*32767))
		pcm.encode_s16(i*4+2,int(clampf(value.y,-1,1)*32767))
	var rms: float = sqrt(energy/maxi(frames.size(),1))
	print("WAVE_MIX: frames=",frames.size()," peak=",peak," rms=",rms," active_frames=",active_frames)
	check(frames.size()>1000 and peak>0.15 and rms>0.06 and active_frames>2000,"arrival produces a strong sustained signal through the actual game bus, not just a silent player")
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = int(AudioServer.get_mix_rate())
	wav.data = pcm
	check(wav.save_to_wav("res://tests/heavenfall_wave_game_capture.wav")==OK,"actual mixed arrival PCM saved")
	AudioServer.remove_bus_effect(bus,effect_index)
	bow._cancel_rift_transit()
	print("HEAVENFALL WAVE MIX RESULT: %d/%d passed" % [checks-failures,checks])
	finish(0 if failures==0 else 1)
