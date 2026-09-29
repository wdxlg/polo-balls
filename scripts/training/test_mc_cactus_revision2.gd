extends "res://scripts/training/test_mc_new5.gd"
func victim(offset:Vector2) -> Node2D:
	var actor:Node2D=spawn("",offset,"Team1")
	actor.Max_health=10000
	actor.default_properties["Max_health"]=10000
	actor.health=10000
	actor.collision_layer=0
	actor.collision_mask=0
	return actor
func purge_fx() -> void:
	for group:String in ["MCNoteWave","MCCactusThorn"]:
		for n:Node in get_nodes_in_group(group): n.queue_free()
	await process_frame
func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(90).timeout.connect(func():finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.5).timeout
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	for role:String in ["仙人掌","音符盒"]:
		var unit:Node2D=spawn(role,Vector2.ZERO)
		check(unit.active() and unit.image.texture!=null,role+" instantiates with native texture")
		check(world._mc_prewarmer.handles(role),role+" prewarm registered")
		unit.queue_free()
		await process_frame
	var cactus:Node2D=spawn("仙人掌",Vector2.ZERO)
	cactus.set_player_control_peer(1)
	var bottom:float=cactus.get_node("CollisionShape2D").position.y+cactus.get_node("CollisionShape2D").shape.size.y*0.5
	var health_y:float=cactus.get_node("Health_Bar").position.y
	for level:int in range(1,6):
		check(cactus.levels==level,"growth has expected level")
		var body:CollisionShape2D=cactus.get_node("CollisionShape2D")
		check(is_equal_approx(body.position.y+body.shape.size.y*0.5,bottom),"growth anchors physical bottom")
		check(is_equal_approx(cactus.image.position.y+cactus.image.texture.get_height()*cactus.image.scale.y*0.5,bottom),"growth anchors visual bottom")
		check(body.shape.size.y==96*level and cactus.get_node("hurtbox/CollisionShape2D").shape.size.y==96*level,"body and hurtbox really grow")
		check(cactus.get_node("Health_Bar").position.y==health_y-96*(level-1),"health UI rises with top")
		cactus.volley_left=0
		check(cactus.fire_thorns(),"side volley starts preparation")
		var old_volleys:int=cactus.volleys
		cactus.advance_volley(0.13)
		cactus.visual_mob()
		check(cactus.image.scale.x<1 and cactus.volleys==old_volleys,"preparation narrows without firing")
		check(is_equal_approx(cactus.image.position.y+cactus.image.texture.get_height()*cactus.image.scale.y*0.5,bottom),"squash/stretch retains visual bottom")
		cactus.advance_volley(0.13)
		check(cactus.volleys==old_volleys,"end of narrowing still has no projectiles")
		cactus.advance_volley(0.08)
		cactus.visual_mob()
		check(cactus.volleys==old_volleys+1 and cactus.image.scale.x>1,"inflation fires exactly one volley")
		check(cactus.last_volley_count>=level*4 and cactus.last_volley_count<=level*4+2,"height scales volley with small bounded randomness")
		for thorn:Node2D in get_nodes_in_group("MCCactusThorn"):
			check(absf(thorn.global_position.x-cactus.global_position.x)>8,"thorn starts at expanded side, not center")
			var sprite:Sprite2D=thorn.get_node("ArrowSprite")
			check(sprite.texture.get_size()==Vector2(6,1) and sprite.rotation==0 and sprite.modulate==Color.WHITE,"thorn is native-color straight strip without arrow geometry")
		await purge_fx()
		cactus.advance_volley(0.32)
		cactus.visual_mob()
		check(cactus.image.scale.is_equal_approx(Vector2.ONE),"elastic recovery returns to normal")
		cactus.step_mob(8.0)
	check(cactus.levels==5,"growth caps at five")
	check(cactus.growth_sounds==4,"each real growth plays one placement sound")
	check(cactus._growth_players.size()>0 and cactus._growth_players[-1].stream in cactus.PLACE_SOUNDS and is_equal_approx(cactus._growth_players[-1].pitch_scale,0.8),"growth uses Minecraft cactus placement sound and pitch")
	cactus.levels=1
	cactus.apply_height()
	var target:Node2D=victim(Vector2(12,0))
	await physics_frame
	cactus.clock=100
	cactus.check_side_contact()
	check(target.health<10000,"right side has real contact damage")
	check(cactus.hit_sounds==1,"successful side contact plays MC hurt sound")
	var hp:int=target.health
	cactus.check_side_contact()
	check(target.health==hp,"side contact has per-target cooldown")
	target.global_position=center+Vector2(-12,0)
	await physics_frame
	cactus.clock+=1
	cactus.check_side_contact()
	check(target.health<hp,"left side has contact damage")
	for vertical:float in [-1.0,1.0]:
		target.global_position=center+Vector2(0,vertical*19)
		await physics_frame
		hp=target.health
		cactus.clock+=1
		cactus.check_side_contact()
		check(target.health==hp,"top/bottom cannot contact-damage")
	# A real inherited skeleton ray hits and embeds, but no wound/execute logic.
	target.global_position=center+Vector2(45,0)
	await physics_frame
	var thorn:Area2D=cactus.THORN.instantiate()
	world.add_child(thorn)
	thorn.global_position=center+Vector2(10,0)
	thorn.configure_plain(cactus,cactus.Team,Vector2.RIGHT,180,10,0,90,3)
	thorn.set_physics_process(false)
	hp=target.health
	var sounds_before:int=world.get_children().filter(func(n:Node):return n is AudioStreamPlayer2D and n.stream in cactus.HIT_SFX.DAMAGE_SFX).size()
	thorn._physics_process(0.3)
	check(world.get_children().filter(func(n:Node):return n is AudioStreamPlayer2D and n.stream in cactus.HIT_SFX.DAMAGE_SFX).size()==sounds_before+1,"thorn hit plays exactly one MC hurt sound")
	await process_frame
	check(thorn.stuck and target.health<hp,"thorn hits once and embeds")
	check(thorn.get_parent()!=world and thorn._sensor_shape.disabled,"embedded thorn follows actual attachment without pickup collision")
	hp=target.health
	thorn._physics_process(1.0)
	check(target.health==hp,"embedded thorn has no damage over time")
	var left:float=thorn.decorative_left
	game.now_stop_state=true
	thorn._physics_process(1.0)
	check(thorn.decorative_left==left,"pause freezes embedded thorn lifetime")
	game.now_stop_state=false
	thorn._physics_process(3.0)
	check(thorn.is_queued_for_deletion(),"embedded thorn expires")
	await process_frame
	var wall:StaticBody2D=obstacle(Vector2(35,70),true)
	await physics_frame
	thorn=cactus.THORN.instantiate()
	world.add_child(thorn)
	thorn.global_position=center+Vector2(0,70)
	thorn.configure_plain(cactus,cactus.Team,Vector2.RIGHT,180,10,0,90,3)
	thorn.set_physics_process(false)
	thorn._physics_process(0.3)
	await process_frame
	check(thorn.stuck and thorn.get_parent()==wall,"thorn embeds in wall")
	wall.queue_free()
	await clear_units()
	await purge_fx()
	var note:Node2D=spawn("音符盒",Vector2.ZERO)
	note.set_process(false)
	note.music.stop()
	for name:String in note.TRACKS:
		check(note.peak_data[name].peaks.size()>400,"real waveform contains hundreds of local peaks: "+name)
	for stream:AudioStream in note.MUSIC: check(stream.get_length()>140,"full original record audio loaded")
	var first:Array=note.peak_data[note.TRACKS[note.track_index]].peaks[0]
	note.process_audio_peaks(float(first[0])-0.001)
	check(note.emitted_peaks==0,"no fabricated attack before first actual peak")
	note.process_audio_peaks(float(first[0])+0.001)
	check(note.emitted_peaks==1,"first actual audio peak emits one wave")
	note.process_audio_peaks(float(first[0])+0.001)
	check(note.emitted_peaks==1,"audio peak is not processed twice")
	await purge_fx()
	note.emitted_peaks=0
	note._next_resolution=0
	note._outcomes.clear()
	note.resolve_wave(1,true)
	check(note.streak==0,"out-of-order impact waits for prior musical attack")
	note.resolve_wave(0,true)
	check(note.streak==2 and note.playback_rate>1,"consecutive hit waves accelerate music")
	check(is_equal_approx(note.music.pitch_scale,note.playback_rate),"music itself speeds up, not only attack timer")
	note.resolve_wave(2,false)
	check(note.streak==0 and note.playback_rate==1,"one complete miss resets music speed")
	for id:int in range(3,50): note.resolve_wave(id,true)
	check(is_equal_approx(note.playback_rate,1.8),"combo speed is bounded")
	note.emitted_peaks=50
	var weak_wave:Node2D=note.WAVE.new()
	world.add_child(weak_wave)
	weak_wave.configure(note,50,center,Vector2.RIGHT,0.1,5)
	var strong_wave:Node2D=note.WAVE.new()
	world.add_child(strong_wave)
	strong_wave.configure(note,51,center,Vector2.RIGHT,0.9,19)
	check(strong_wave.speed>weak_wave.speed and strong_wave.damage>weak_wave.damage,"higher peak has higher speed and damage")
	check(strong_wave.half_angle>weak_wave.half_angle and strong_wave.trail_width>weak_wave.trail_width,"higher peak has larger arc and inward tail")
	weak_wave.queue_free()
	strong_wave.queue_free()
	await process_frame
	target=victim(Vector2(60,0))
	var behind:Node2D=victim(Vector2(-60,0))
	await physics_frame
	var wave:Node2D=note.WAVE.new()
	world.add_child(wave)
	wave.set_physics_process(false)
	wave.configure(note,50,center,Vector2.RIGHT,0.8,18)
	wave.advance(0.4)
	check(target.health<10000 and behind.health==10000,"directed white arc hits forward hurtbox, not full disk")
	hp=target.health
	wave.advance(0.1)
	check(target.health==hp,"one wave cannot repeatedly damage same victim")
	check(wave.heading==Vector2.RIGHT,"wave does not retarget in flight")
	wave.advance(2.0)
	check(wave.finished and wave.any_hit,"wave resolves successful hit on completion")
	await process_frame
	# Actual audio transport / pause / restart, not merely a synthetic clock.
	note.playback_rate=1
	note.set_process(true)
	note.start_track(0)
	await create_timer(0.4).timeout
	check(note.music.playing and note.music.get_playback_position()>0.1,"real record playback clock advances")
	game.now_stop_state=true
	await create_timer(0.1).timeout
	var paused_at:float=note.music.get_playback_position()
	await create_timer(0.2).timeout
	check(note.music.stream_paused and absf(note.music.get_playback_position()-paused_at)<0.03,"combat pause freezes actual music")
	game.now_stop_state=false
	await create_timer(0.2).timeout
	check(note.music.get_playback_position()>paused_at,"unpause resumes music")
	var track:int=note.track_index
	note._track_finished()
	check(note.track_index==(track+1)%3,"records rotate after finishing")
	await clear_units()
	await purge_fx()
	while world._mc_prewarmer.finished.size()+world._mc_prewarmer.failed.size()<world._mc_prewarmer.CHARACTERS.size(): await process_frame
	print("CACTUS_REV2_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
