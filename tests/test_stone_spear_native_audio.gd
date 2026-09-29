extends "res://tests/test_stone_spear.gd"
var audio_counts:Dictionary={}
var last_player:AudioStreamPlayer2D
func heard(node:Node) -> void:
	if node is AudioStreamPlayer2D and node.has_meta("mc_sound_event"):
		var event:String=node.get_meta("mc_sound_event")
		audio_counts[event]=int(audio_counts.get(event,0))+1
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
	create_timer(60.0).timeout.connect(func(): quit(2))
	game=root.get_node("Game")
	game.now_stop_state=false
	game.Game_Settings.Have_Team_Damage=false
	arena=Node2D.new()
	root.add_child(arena)
	current_scene=arena
	var camera:=Camera2D.new()
	arena.add_child(camera)
	node_added.connect(heard)
	spear=load("res://scenes/characters/我的世界/石矛.tscn").instantiate()
	spear.Team="Team0"
	arena.add_child(spear)
	spear.state_machine.set_physics_process(false)
	spear.direction=Vector2.ZERO
	var asset_root:String="res://audio/characters/我的世界/stone_spear/"
	check(spear.FORMATION_SFX.resource_path==asset_root+"use.ogg","use event uses exact non-wood spear asset")
	for i:int in range(3):
		check(spear.STAB_SOUNDS[i].resource_path==asset_root+"attack%d.ogg" % (i+1),"attack event uses non-wood spear variant")
		check(spear.HIT_SOUNDS[i].resource_path==asset_root+"hit%d.ogg" % (i+1),"hit event uses non-wood spear variant")
	check(spear.set_formation(2),"real stance switch accepted")
	await flush()
	check(spear.last_sound_event=="minecraft:item.spear.use" and last_player.stream==spear.FORMATION_SFX,"real switch emits exact use event")
	spear._transition_left=0.0
	spear._stab_wait=0.0
	check(spear.begin_stab(),"real thrust accepted")
	await flush()
	check(spear.last_sound_event=="minecraft:item.spear.attack" and last_player.stream in spear.STAB_SOUNDS,"real thrust emits exact attack event")
	var count:int=audio_counts.get("minecraft:item.spear.attack",0)
	check(not spear.begin_stab(),"active thrust cannot retrigger attack sound")
	spear._stab_time=spear.stab_out_time+0.01
	for i:int in range(4): spear._process(0.0)
	await flush()
	check(audio_counts.get("minecraft:item.spear.attack",0)==count,"return animation does not retrigger attack audio")
	await clear_sounds()
	for event:String in ["minecraft:item.spear.attack","minecraft:item.spear.hit"]:
		for variant:int in range(3):
			spear._play_audio(event,variant,Vector2.ZERO,0.0)
			await flush()
			var streams:Array=spear.STAB_SOUNDS if event.ends_with("attack") else spear.HIT_SOUNDS
			check(last_player.stream==streams[variant] and last_player.stream.get_length()>0.0,"authority-selected native variant is preserved")
			check(last_player.get_meta("mc_sound_priority")==event.ends_with("hit"),"hit retains combat priority while attack does not")
	await clear_sounds()
	for value:float in [0.1,49.0,49.999,50.0,50.001,80.0]:
		spear._emit_audio(true,Vector2.ZERO,value)
		await flush()
		var event:String="minecraft:item.spear.hit" if value<50.0 else "entity.player.hurt" if value==50.0 else "entity.player.attack.crit"
		check(spear.last_sound_event==event,"strict below-50 boundary at %s" % value)
		check(is_equal_approx(last_player.volume_db,spear.HIT_GAIN.damage_gain(value)),"actual-damage gain unchanged")
	await clear_sounds()
	var previous:Dictionary=audio_counts.duplicate()
	spear._emit_audio(true,Vector2.ZERO,0.0)
	spear._emit_audio(true,Vector2.ZERO,-1.0)
	await flush()
	check(audio_counts==previous,"zero or negative effective damage is silent")
	var target:Node2D=victim(Vector2(25,0))
	target.state_machine.set_physics_process(false)
	await physics_frame
	for form:int in range(3):
		for index:int in range(5):
			for damage:int in [49,50,51]:
				reset_pose(form)
				spear.direction=Vector2.ZERO
				if form==2: spear._stab_time=0.01
				spear.Damage=damage
				var hp:int=target.health
				spear._sweep_tip(index,Vector2.ZERO,Vector2(25.5,0),0.0,0.0,0.0625,Vector2.ZERO)
				check(hp-target.health==damage,"real 408-speed collision produces exact %d damage" % damage)
				var expected:String="minecraft:item.spear.hit" if damage<50 else "entity.player.hurt" if damage==50 else "entity.player.attack.crit"
				check(spear.last_sound_event==expected,"actual health loss selects sound in form %d tip %d" % [form,index])
				await clear_sounds()
	target.queue_free()
	spear.Damage=20
	reset_pose()
	spear.direction=Vector2.ZERO
	await flush()
	if DisplayServer.get_name()!="headless":
		await create_timer(0.6).timeout
		var bus:int=AudioServer.get_bus_index("GameplayRecord")
		check(bus>=0,"production recording bus exists")
		var capture:=AudioEffectCapture.new()
		AudioServer.add_bus_effect(bus,capture)
		for event:String in ["minecraft:item.spear.use","minecraft:item.spear.attack","minecraft:item.spear.hit"]:
			await clear_sounds()
			capture.clear_buffer()
			if event.ends_with("use"): spear.set_formation(2)
			elif event.ends_with("attack"):
				spear._transition_left=0.0
				spear._stab_wait=0.0
				spear.begin_stab()
			else: spear._emit_audio(true,Vector2.ZERO,49.0)
			await create_timer(0.4).timeout
			var pcm:PackedVector2Array=capture.get_buffer(capture.get_frames_available())
			var peak:float=0.0
			for sample:Vector2 in pcm: peak=maxf(peak,maxf(absf(sample.x),absf(sample.y)))
			check(peak>0.00001,"native event produces real recorded PCM: "+event)
			print("NATIVE_SPEAR_PCM event=%s frames=%d peak=%f" % [event,pcm.size(),peak])
		AudioServer.remove_bus_effect(bus,AudioServer.get_bus_effect_count(bus)-1)
	await clear_sounds()
	print("STONE_NATIVE_AUDIO_RESULT checks=%d failures=%d" % [checks,failures])
	arena.queue_free()
	await flush()
	quit(0 if failures==0 else 1)
