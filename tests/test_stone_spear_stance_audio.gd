extends "res://tests/test_stone_spear.gd"
var switch_count:int=0
var last_player:AudioStreamPlayer2D
func heard(node:Node) -> void:
	if node is AudioStreamPlayer2D and node.get_meta("mc_sound_event","")=="minecraft:item.spear.use":
		switch_count+=1
		last_player=node
func flush() -> void:
	await process_frame
	await process_frame
func clear_sounds() -> void:
	for node:Node in get_nodes_in_group("MCNativeSFX"):
		node.stop()
		node.queue_free()
	await flush()
func run() -> void:
	create_timer(40.0).timeout.connect(func(): quit(2))
	game=root.get_node("Game")
	game.now_stop_state=false
	arena=Node2D.new()
	root.add_child(arena)
	current_scene=arena
	var camera:=Camera2D.new()
	arena.add_child(camera)
	node_added.connect(heard)
	spear=load("res://scenes/characters/我的世界/石矛.tscn").instantiate()
	arena.add_child(spear)
	spear.state_machine.set_physics_process(false)
	spear.direction=Vector2.ZERO
	await flush()
	check(switch_count==0,"spawn does not play a stance-change sound")
	var rng_state:int=spear._rng.state
	for form:int in [1,2,0]:
		var count:int=switch_count
		check(spear.set_formation(form),"accepted stance transition")
		await flush()
		check(switch_count==count+1,"exactly one sound per successful switch")
		check(last_player.global_position==spear.global_position,"sound originates at body")
		check(last_player.volume_db==0.0 and last_player.pitch_scale==1.0,"native sound at unattenuated 0dB base gain and natural pitch")
		check(last_player.bus==&"GameplayRecord" and not last_player.get_meta("mc_sound_priority"),"shared recording bus and non-damage priority")
	check(spear._rng.state==rng_state,"sound selection does not consume gameplay RNG")
	var count:int=switch_count
	check(not spear.set_formation(0) and not spear.set_formation(-1) and not spear.set_formation(3),"same or invalid stance rejected")
	check(not spear.choose_formation(),"cooldown attempt rejected")
	spear.dizziness=true
	check(not spear.set_formation(1),"stunned switch rejected")
	spear.dizziness=false
	spear.Can_Skill=false
	check(not spear.set_formation(1),"skill-disabled switch rejected")
	spear.Can_Skill=true
	spear.Can_Attack=false
	check(not spear.set_formation(1),"attack-disabled switch rejected")
	spear.Can_Attack=true
	game.now_stop_state=true
	check(not spear.set_formation(1),"paused switch rejected")
	game.now_stop_state=false
	spear.health=0
	check(not spear.set_formation(1),"dead switch rejected")
	spear.health=600
	await flush()
	check(switch_count==count,"all rejected transitions remain silent")
	spear.player_control_peer_id=1
	spear._switch_wait=0.0
	spear.controlled_formation()
	await flush()
	check(switch_count==count+1,"manual right-click action plays once")
	spear.controlled_formation()
	await flush()
	check(switch_count==count+1,"repeated manual input during cooldown remains silent")
	spear.player_control_peer_id=0
	spear._switch_wait=0.01
	spear.tick_physics(spear.State.Stand,0.02)
	await flush()
	check(switch_count==count+2,"automatic timer-driven switch plays once")
	for i:int in range(10): spear._process(0.0)
	await flush()
	check(switch_count==count+2,"pose application never replays switch sound")
	await clear_sounds()
	spear._play_audio("minecraft:item.spear.use",0,spear.global_position,0.0)
	await flush()
	check(last_player.stream==spear.FORMATION_SFX,"stance sound is the exact native item.spear.use, not a substitute click")
	check(last_player.stream.get_length()>0.0,"exact native spear-use clip is nonempty; do not trim the requested event")
	print("SPEAR_USE_DURATION seconds=%f" % last_player.stream.get_length())
	await clear_sounds()
	count=switch_count
	var cancelled:Variant=load("res://scenes/characters/我的世界/石矛.tscn").instantiate()
	arena.add_child(cancelled)
	cancelled.state_machine.set_physics_process(false)
	cancelled.set_formation(1)
	cancelled.queue_free()
	await flush()
	check(switch_count==count,"deleted source cancels a queued stance sound")
	for i:int in range(40): spear._play_audio("minecraft:item.spear.use",0,spear.global_position,0.0)
	await flush()
	check(get_nodes_in_group("MCNativeSFX").size()<=24,"stance audio respects global 24-voice budget")
	await clear_sounds()
	if DisplayServer.get_name()!="headless":
		var bus:int=AudioServer.get_bus_index("GameplayRecord")
		check(bus>=0,"recording bus exists for real PCM capture")
		var capture:=AudioEffectCapture.new()
		AudioServer.add_bus_effect(bus,capture)
		check(spear.set_formation((spear.formation+1)%3),"PCM test uses a real stance change, not a synthetic playback")
		await create_timer(0.5).timeout
		var pcm:PackedVector2Array=capture.get_buffer(capture.get_frames_available())
		var peak:float=0.0
		for sample:Vector2 in pcm: peak=maxf(peak,maxf(absf(sample.x),absf(sample.y)))
		check(peak>0.00001,"real switch produces nonzero recorded PCM")
		print("STANCE_AUDIO_PCM frames=%d peak=%f" % [pcm.size(),peak])
		AudioServer.remove_bus_effect(bus,AudioServer.get_bus_effect_count(bus)-1)
	await clear_sounds()
	print("STONE_STANCE_AUDIO_RESULT checks=%d failures=%d" % [checks,failures])
	arena.queue_free()
	await flush()
	quit(0 if failures==0 else 1)
