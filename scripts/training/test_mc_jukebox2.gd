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
func sound_count(event:String) -> int:
	return get_nodes_in_group("MCBlockActionSFX").filter(func(n:Node):return n.get_meta("mc_sound_event","")==event).size()
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
	for role:String in ["仙人掌","唱片机"]:
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
		var deflate_before:int=sound_count("entity.puffer_fish.blow_out")
		var sting_before:int=sound_count("entity.puffer_fish.sting")
		check(cactus.fire_thorns(),"side volley starts preparation")
		check(sound_count("entity.puffer_fish.blow_out")==deflate_before+1,"narrowing starts exactly one pufferfish deflate sound")
		var old_volleys:int=cactus.volleys
		cactus.advance_volley(0.13)
		cactus.visual_mob()
		check(cactus.image.scale.x<1 and cactus.volleys==old_volleys,"preparation narrows without firing")
		check(is_equal_approx(cactus.image.position.y+cactus.image.texture.get_height()*cactus.image.scale.y*0.5,bottom),"squash/stretch retains visual bottom")
		cactus.advance_volley(0.13)
		check(cactus.volleys==old_volleys,"end of narrowing still has no projectiles")
		check(sound_count("entity.puffer_fish.sting")==sting_before+1,"inflation starts exactly one pufferfish sting sound")
		cactus.advance_volley(0.08)
		cactus.visual_mob()
		check(cactus.volleys==old_volleys+1 and cactus.image.scale.x>1,"inflation fires exactly one volley")
		check(cactus.last_volley_count>=level*4 and cactus.last_volley_count<=level*4+2,"height scales volley with small bounded randomness")
		for thorn:Node2D in get_nodes_in_group("MCCactusThorn"):
			check(absf(thorn.global_position.x-cactus.global_position.x)>8,"thorn starts at expanded side, not center")
			check(absf(thorn._direction.y)<=sin(deg_to_rad(10.0))+0.00001,"active thorn spread is outward plus/minus ten degrees")
			var sprite:Sprite2D=thorn.get_node("ArrowSprite")
			check(sprite.texture.get_size()==Vector2(6,1) and sprite.rotation==0 and sprite.modulate==Color.WHITE,"thorn is native-color straight strip without arrow geometry")
		await purge_fx()
		cactus.advance_volley(0.32)
		cactus.visual_mob()
		check(cactus.image.scale.is_equal_approx(Vector2.ONE),"elastic recovery returns to normal")
		cactus.step_mob(8.0)
	check(cactus.levels==5,"growth caps at five")
	check(cactus._growth_players[-1].volume_db==3.0,"growth sound boosted eight dB from previous version")
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
	var note:Node2D=spawn("唱片机",Vector2.ZERO)
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
	check(note.streak==2 and note.music_volume_db>-10 and note.combo_damage_multiplier>1,"consecutive hits increase actual volume and damage")
	check(note.music.pitch_scale==1.0 and note.playback_rate==1.0,"combo never changes music tempo or pitch")
	note.resolve_wave(2,false)
	check(note.streak==0 and note.music_volume_db==-10 and note.combo_damage_multiplier==1,"one complete miss resets volume and damage")
	for id:int in range(3,50): note.resolve_wave(id,true)
	check(note.playback_rate==1 and is_equal_approx(note.combo_damage_multiplier,3.0) and is_equal_approx(note.music.volume_db,-2.0),"combo volume and damage have safe caps")
	note.emitted_peaks=50
	var weak_wave:Node2D=note.WAVE.new()
	world.add_child(weak_wave)
	weak_wave.configure(note,50,center,Vector2.RIGHT,0.1,5)
	var strong_wave:Node2D=note.WAVE.new()
	world.add_child(strong_wave)
	strong_wave.configure(note,51,center,Vector2.RIGHT,0.9,19)
	check(strong_wave.speed>weak_wave.speed and strong_wave.damage>weak_wave.damage,"higher peak has higher speed and damage")
	check(is_equal_approx(strong_wave.half_angle,weak_wave.half_angle) and strong_wave.trail_width>weak_wave.trail_width,"peak changes tail but not angular coverage")
	weak_wave.queue_free()
	strong_wave.queue_free()
	await process_frame
	note.streak=0
	note.refresh_combo_bonuses()
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
	var ring:Node2D=note.WAVE.new()
	world.add_child(ring)
	ring.set_physics_process(false)
	ring.configure(note,777,center,Vector2.RIGHT,0.8,10,0,360)
	var front_before:float=target.health
	var back_before:float=behind.health
	ring.advance(0.4)
	check(target.health==front_before-10 and behind.health==back_before-10,"full 360 arc hits front and back with real hurtbox sweeps")
	ring.advance(0.1)
	check(target.health==front_before-10 and behind.health==back_before-10,"full ring seam cannot double hit")
	ring.queue_free()
	for role:String in ["仙人掌","唱片机"]:
		var facing:Node2D=spawn(role,Vector2(0,160))
		facing.velocity=Vector2.LEFT*80
		facing.visual_mob()
		check(facing.is_character_visual_flipped_h() and is_zero_approx(facing.image.rotation),role+" mirrors left without rotating")
		facing.velocity=Vector2.UP*80
		facing.visual_mob()
		check(facing.is_character_visual_flipped_h(),role+" vertical movement preserves previous facing")
		facing.velocity=Vector2.RIGHT*80
		facing.visual_mob()
		check(not facing.is_character_visual_flipped_h(),role+" turns right again")
		facing.queue_free()
		await process_frame
	await purge_fx()
	var probe:Node2D=spawn("唱片机",Vector2.ZERO)
	probe.set_process(false)
	probe.music.stop()
	probe.track_index=0
	probe.emit_peak(0.8)
	var base_wave:Node2D=get_nodes_in_group("MCNoteWave")[-1]
	base_wave.set_physics_process(false)
	var base_damage:float=base_wave.damage
	var base_speed:float=base_wave.speed
	var hp_before:int=target.health
	base_wave.advance(0.4)
	var base_loss:int=hp_before-target.health
	base_wave.queue_free()
	probe.resolve_wave(0,true)
	probe.emit_peak(0.8)
	var combo_wave:Node2D=get_nodes_in_group("MCNoteWave")[-1]
	combo_wave.set_physics_process(false)
	hp_before=target.health
	combo_wave.advance(0.4)
	check(combo_wave.damage>base_damage and hp_before-target.health>base_loss,"combo boost changes emitted damage and actual HP loss")
	check(combo_wave.speed==base_speed and probe.music.pitch_scale==1,"combo does not change wave speed or music tempo")
	check(probe.music.volume_db>-10,"combo changes real player output volume")
	combo_wave.queue_free()
	probe.queue_free()
	await process_frame
	var colors:Array[Color]=[]
	for song:int in range(3):
		var themed:Node2D=note.WAVE.new()
		world.add_child(themed)
		themed.set_physics_process(false)
		themed.configure(note,100+song,center,Vector2.RIGHT,0.8,18,song)
		themed.radius=70
		themed.queue_redraw()
		colors.append(themed.theme_color())
		note.track_index=(song+1)%3
		check(themed.song_index==song,"flying wave retains its originating song across record changes")
		await process_frame
		themed.queue_free()
	check(colors[0]!=colors[1] and colors[1]!=colors[2] and colors[0]!=colors[2],"all three records have distinct wave palettes")
	var previous_gain:float=-100
	var previous_multiplier:float=0
	for count:int in range(16):
		note.streak=count
		note.refresh_combo_bonuses()
		check(note.combo_damage_multiplier>previous_multiplier and note.music.volume_db>previous_gain,"every damage increase has matching music-volume increase")
		previous_multiplier=note.combo_damage_multiplier
		previous_gain=note.music.volume_db
	check(is_equal_approx(note.music.volume_db,-2.0) and note.music.pitch_scale==1,"coupled bonus reaches new volume cap without speeding music")
	note.streak=0
	note.refresh_combo_bonuses()
	var audio_probe:Node2D=spawn("唱片机",Vector2(0,240))
	audio_probe.set_process(false)
	audio_probe.music.stop()
	var hit_gains:Array[float]=[]
	var hit_sequence:int=0
	for amount:float in [10.0,50.0,51.0,90.0]:
		var sound_target:Node2D=victim(Vector2(60,240))
		await physics_frame
		var sound_wave:Node2D=audio_probe.WAVE.new()
		world.add_child(sound_wave)
		sound_wave.set_physics_process(false)
		sound_wave.configure(audio_probe,hit_sequence,audio_probe.global_position,Vector2.RIGHT,1,amount)
		check(sound_wave.line_width<=0.55 and sound_wave.trail_width<=7,"wave front and trailing band are much thinner")
		var sound_before:int=audio_probe.impact_count
		sound_wave.advance(0.4)
		check(audio_probe.impact_count==sound_before+1 and audio_probe.last_impact_damage==amount,"one impact sound uses actual HP damage")
		var expected:String="entity.player.attack.crit" if amount>50 else "entity.player.hurt"
		check(audio_probe.last_impact_event==expected,"strict over-50 critical sound threshold")
		var sound:AudioStreamPlayer2D=get_nodes_in_group("MCBlockActionSFX")[-1]
		check(sound.get_meta("mc_sound_event","")==expected and sound.playing,"actual chosen hit/crit stream is playing")
		hit_gains.append(sound.volume_db)
		sound_wave.advance(0.1)
		check(audio_probe.impact_count==sound_before+1,"continued wave contact cannot duplicate impact sound")
		sound_wave.queue_free()
		sound_target.queue_free()
		hit_sequence+=1
		await process_frame
	check(hit_gains[0]<hit_gains[1] and hit_gains[1]<hit_gains[2] and hit_gains[2]<hit_gains[3],"higher real damage produces higher hit-sound output volume")
	check(audio_probe.IMPACT_AUDIO.impact_gain(10000)==4,"impact volume has an upper bound")
	print("IMPACT_GAINS ",hit_gains)
	audio_probe.queue_free()
	await process_frame
	var retaliator:Node2D=spawn("仙人掌",Vector2(0,-200))
	retaliator.set_process(false)
	retaliator.set_physics_process(false)
	for height:int in range(1,6):
		retaliator.levels=height
		for amount:float in [0.0,9.0,10.0,49.0,50.0,99.0,100.0,123.0]:
			check(retaliator.retaliation_count(amount)==int(floor(amount*height*0.4/5+0.000001)),"retaliation floor budget across heights and damage")
	retaliator.levels=5
	retaliator.Damage=999
	retaliator.default_properties["Damage"]=999
	retaliator.retaliation_pending=0
	retaliator.retaliation_age=-1
	await purge_fx()
	retaliator.health-=59
	check(retaliator.last_retaliation_count==23 and retaliator.retaliation_pending==23,"actual HP setter produces total 23, not 23 on each side")
	check(get_nodes_in_group("MCCactusThorn").is_empty(),"reaction first inflates before releasing thorns")
	retaliator.advance_retaliation(0.03)
	check(retaliator.presentation_scale().x>1,"retaliation rapidly widens body")
	retaliator.advance_retaliation(0.025)
	check(get_nodes_in_group("MCCactusThorn").size()==23,"exact floor count released at inflation peak")
	var left_count:int=0
	var right_count:int=0
	for needle:Node2D in get_nodes_in_group("MCCactusThorn"):
		needle.set_physics_process(false)
		check(needle.fixed_retaliation_damage and absf(needle._direction.y)<=sin(PI/4)+0.00001,"retaliation fixed damage flag and outward 45-degree cone")
		if needle._direction.x<0: left_count+=1
		else: right_count+=1
	check(absi(left_count-right_count)==1,"odd total balanced across both sides without doubling")
	var fixed_target:Node2D=victim(Vector2(-180,-200))
	var hp_fixed:float=fixed_target.health
	get_nodes_in_group("MCCactusThorn")[0]._apply_damage(fixed_target,999)
	check(fixed_target.health==hp_fixed-5,"retaliation remains five despite cactus Damage 999 and input 999")
	retaliator.advance_retaliation(0.10)
	check(retaliator.presentation_scale().x<1,"elastic return overshoots below normal width")
	retaliator.advance_retaliation(0.30)
	check(retaliator.presentation_scale()==Vector2.ONE,"reaction returns to normal shape")
	retaliator.queue_free()
	fixed_target.queue_free()
	await process_frame
	await purge_fx()
	var coverage_probe:Node2D=spawn("唱片机",Vector2(0,-160))
	coverage_probe.set_process(false)
	check(coverage_probe.Damage==6,"production base damage reduced to six")
	var old_angle:float=0
	for hits:int in range(16):
		coverage_probe.streak=hits
		coverage_probe.refresh_combo_bonuses()
		var expected:float=lerpf(15,360,float(hits)/15)
		check(is_equal_approx(coverage_probe.wave_angle_degrees,expected) and expected>old_angle,"volume raises angle monotonically to full circle")
		check(is_equal_approx(coverage_probe.combo_damage_multiplier,lerpf(1,3,float(hits)/15)),"volume raises damage to triple")
		old_angle=expected
		var frozen:Node2D=coverage_probe.WAVE.new()
		world.add_child(frozen)
		frozen.set_physics_process(false)
		frozen.configure(coverage_probe,800+hits,coverage_probe.global_position,Vector2.RIGHT,0.1,6)
		var fixed_angle:float=frozen.half_angle
		coverage_probe.streak=0
		coverage_probe.refresh_combo_bonuses()
		frozen.advance(0.2)
		frozen.advance(0.2)
		check(is_equal_approx(rad_to_deg(fixed_angle)*2,expected) and frozen.half_angle==fixed_angle,"expanding radius and later volume reset cannot alter emitted arc")
		frozen.queue_free()
	coverage_probe.streak=100
	coverage_probe.refresh_combo_bonuses()
	check(coverage_probe.wave_angle_degrees==360 and coverage_probe.combo_damage_multiplier==3,"angle and damage cap despite excess combo")
	coverage_probe.queue_free()
	await process_frame
	# Actual audio transport and complete disc lifecycle.
	note.playback_rate=1
	note.set_process(true)
	note.start_track(0)
	check(note.record_phase==0 and not note.music.playing and note._disc_sprite.visible,"insertion visible before any music")
	note.advance_record(0.30)
	check(not note.music.playing and note._disc_sprite.position.y< -36,"record approaches top slot silently")
	note.advance_record(0.35)
	await create_timer(0.4).timeout
	check(note.record_phase==1 and not note._disc_sprite.visible and note.music.playing and note.music.get_playback_position()>0.1,"record fully inserted before real playback")
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
	check(note.track_index==track and note.record_phase==2 and not note.music.playing,"song end ejects old disc without early next insertion")
	var record:Node2D=note._ejected_record
	record.set_physics_process(false)
	check(not record is CollisionObject2D and record.global_position.distance_to(note.image.get_parent().to_global(Vector2(0,-36)))<0.01,"ejected disc starts at slot without collision")
	record.advance(0.1)
	check(record.global_position.y<record.origin.y,"disc initially flies upwards")
	var p:Vector2=record.origin+record.launch*0.1+Vector2(0,0.5*record.gravity*0.01)
	check(record.global_position.distance_to(p)<0.01,"disc uses ballistic parabola")
	game.now_stop_state=true
	var frozen_age:float=record.age
	record._physics_process(0.4)
	check(record.age==frozen_age,"pause freezes flying record")
	game.now_stop_state=false
	record.advance(8)
	check(record.finished and note.track_index==(track+1)%3 and note.record_phase==0 and not note.music.playing,"only after falling out does the next disc begin insertion")
	note.advance_record(0.65)
	check(note.music.playing and note._disc_sprite.texture==note.DISCS[1],"different original disc inserted and next song starts")
	await clear_units()
	await purge_fx()
	while world._mc_prewarmer.finished.size()+world._mc_prewarmer.failed.size()<world._mc_prewarmer.CHARACTERS.size(): await process_frame
	print("JUKEBOX2_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
