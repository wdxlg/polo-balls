extends "res://scripts/training/test_mc_new5.gd"
func stationary(role:String,offset:Vector2,team:String="Team0") -> Node2D:
	var actor:Node2D=spawn(role,offset,team)
	actor.Speed=0
	actor.default_properties["Speed"]=0
	actor.velocity=Vector2.ZERO
	actor.Repel=Vector2.ZERO
	actor.state_machine.set_physics_process(true)
	return actor
func dummy(offset:Vector2) -> Node2D:
	var actor:Node2D=stationary("",offset,"Team1")
	actor.Max_health=10000
	actor.default_properties["Max_health"]=10000
	actor.health=10000
	actor.Can_Attack=false
	actor.Can_Skill=false
	actor.collision_layer=0
	actor.collision_mask=0
	return actor
func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(95).timeout.connect(func():finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	while world._mc_prewarmer.finished.size()+world._mc_prewarmer.failed.size()<world._mc_prewarmer.CHARACTERS.size(): await process_frame
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var camera:=Camera2D.new()
	world.add_child(camera)
	camera.global_position=center+Vector2(0,-25)
	camera.zoom=Vector2(3,3)
	camera.make_current()
	camera.force_update_scroll()
	var cactus:Node2D=stationary("仙人掌",Vector2(-55,40))
	var note:Node2D=stationary("唱片机",Vector2(50,-40))
	note.start_track(0)
	note.Damage=32
	note.default_properties["Damage"]=32
	var cactus_target:Node2D=dummy(Vector2(-70,40))
	var note_target:Node2D=dummy(Vector2(93,-40))
	var anchor:Vector2=cactus.global_position
	cactus.growth_elapsed=7.5
	var heard:Dictionary={}
	var highest_rate:float=1
	var highest_volume:float=-10
	var highest_damage:float=1
	var most_thorns:int=0
	var most_waves:int=0
	var live_features:Dictionary={}
	var seen_left:bool=false
	var seen_right:bool=false
	for tick:int in range(51):
		await create_timer(0.2).timeout
		for sound:Node in get_nodes_in_group("MCBlockActionSFX"):
			heard[str(sound.get_meta("mc_sound_event",""))]=true
		for channel_wave:Node2D in get_nodes_in_group("MCNoteWave"):
			if channel_wave.has_music_profile:
				live_features["profile"]=true
				if channel_wave.kick_strength>=0.55: live_features["kick"]=true
				if channel_wave.hat_strength>=0.55: live_features["hat"]=true
				if channel_wave.pitch_confidence>=0.45: live_features["pitch"]=true
				if channel_wave.sustain_seconds>=0.22: live_features["hold"]=true
			if channel_wave.heading==Vector2.LEFT: seen_left=true
			if channel_wave.heading==Vector2.RIGHT: seen_right=true
		highest_rate=maxf(highest_rate,note.playback_rate)
		highest_volume=maxf(highest_volume,note.music.volume_db)
		highest_damage=maxf(highest_damage,note.combo_damage_multiplier)
		most_thorns=maxi(most_thorns,get_nodes_in_group("MCCactusThorn").size())
		most_waves=maxi(most_waves,get_nodes_in_group("MCNoteWave").size())
		if tick==3: cactus.health-=100
		if tick==20:
			var old_clock:float=cactus.clock
			game.now_stop_state=true
			await create_timer(0.1).timeout
			var music_time:float=note.music.get_playback_position()
			await create_timer(0.3).timeout
			check(cactus.clock==old_clock,"live pause freezes growth/combat clocks")
			check(absf(note.music.get_playback_position()-music_time)<0.03,"live pause freezes actual record")
			game.now_stop_state=false
		if tick in [48]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("user://mc_jukebox_%d.png"%tick)
	check(cactus.levels==3 and cactus.growth_count==2,"live cactus grows with placement audio")
	check(cactus.global_position.distance_to(anchor)<0.1,"stationary cactus retains bottom world anchor while growing")
	check(cactus.get_node("CollisionShape2D").shape.size.y==288,"live physical height tracks new growth")
	check(heard.has("entity.puffer_fish.blow_out") and heard.has("entity.puffer_fish.sting"),"live narrowing/inflation play their pufferfish sounds")
	check(heard.has("entity.player.hurt") and heard.has("entity.player.attack.crit"),"live musical waves play normal and over-50 critical impacts")
	check(cactus.growth_sounds==2,"live growth emits one placement sound per new level")
	check(cactus.hit_sounds>0,"live side contacts emit MC hurt sound")
	check(cactus.volleys>=2 and most_thorns>0,"live automatic side volleys fire")
	check(cactus_target.health<10000,"live thorns/contact damage real targets")
	check(note.emitted_peaks>15 and most_waves>0,"real music clock drives repeated waves")
	check(note_target.health<10000,"live audio waves damage actual enemy")
	check(highest_rate==1 and highest_volume>-10 and highest_damage>1,"live hits boost volume/damage but keep original tempo")
	check(live_features.has("profile") and live_features.has("kick") and live_features.has("hat") and live_features.has("pitch"),"live decoded music drives percussion and pitch wave profiles")
	check(note.musical_events>0,"real music transport consumes analyzed feature rows")
	check(seen_left and seen_right,"live music generates both fixed world channels")
	check(note.streak<=note.emitted_peaks,"stereo attacks cannot double combo count")
	check(note.wave_angle_degrees<=180,"live per-channel half circle cap")
	check(most_thorns<=256 and most_waves<=64,"live effects remain bounded")
	print("CACTUS_NOTE_LIVE_METRICS growth=",cactus.growth_count," volleys=",cactus.volleys," cactus_damage=",10000-cactus_target.health," note_damage=",10000-note_target.health," peaks=",note.emitted_peaks," max_volume=",highest_volume," max_damage_multiplier=",highest_damage," max_rate=",highest_rate," max_thorns=",most_thorns," max_waves=",most_waves)
	cactus_target.queue_free()
	note_target.queue_free()
	await create_timer(6.0).timeout
	check(note.streak==0 and note.playback_rate==1 and note.music.volume_db==-10 and note.combo_damage_multiplier==1,"live misses decay volume and damage to baseline after enemies leave")
	check(cactus.retaliation_bursts>=1 and cactus.retaliation_spawned==16,"real health damage at two levels releases exactly sixteen reactive thorns")
	check(note.inserted_records>=1 and note.record_phase==1,"live animation inserted initial disc before music playback")
	# Seek transport near EOF, allowing the real AudioStreamPlayer finished signal.
	note.peak_index=note.peak_data[note.TRACKS[note.track_index]].peaks.size()
	note.music.seek(note.music.stream.get_length()-0.15)
	await create_timer(0.45).timeout
	check(note.record_phase==2 and note.ejected_records==1,"actual audio EOF ejects exactly one disc")
	var elapsed:float=0
	while note.record_phase==2 and elapsed<8.5:
		await create_timer(0.05).timeout
		elapsed+=0.05
	check(note.record_phase==0 and note.track_index==1 and not note.music.playing,"live parabola exits map before next insertion")
	await create_timer(0.8).timeout
	check(note.record_phase==1 and note.music.playing and note.track_index==1,"live second insertion completes and Otherside starts at normal speed")
	await clear_units()
	print("MUSIC5_LIVE_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
