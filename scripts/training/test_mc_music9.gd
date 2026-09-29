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
	check(note.streak==2 and note.combo_decaying,"complete miss starts decay without clearing stacks")
	note.advance_combo_decay(0.4)
	check(note.streak==0 and note.music_volume_db==-10,"five stacks per second reaches base smoothly")
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
	check(strong_wave.half_angle>weak_wave.half_angle and strong_wave.trail_width>weak_wave.trail_width,"instant loudness changes tail and emission angle")
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
	check(target.health==front_before-10 and behind.health==back_before,"requested 360 is capped to 180 and only hits the forward half")
	ring.advance(0.1)
	check(target.health==front_before-10 and behind.health==back_before,"half-circle wave cannot double hit")
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
	for count:int in range(21):
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
	for hits:int in range(21):
		coverage_probe.streak=hits
		coverage_probe.refresh_combo_bonuses()
		var expected:float=lerpf(15,180,float(hits)/20)
		check(is_equal_approx(coverage_probe.wave_angle_degrees,expected) and expected>old_angle,"volume raises angle monotonically to half circle")
		check(is_equal_approx(coverage_probe.combo_damage_multiplier,lerpf(1,3,float(hits)/20)),"volume raises damage to triple")
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
		check(is_equal_approx(rad_to_deg(fixed_angle)*2,lerpf(lerpf(3,90,float(hits)/20),expected,0.1)) and frozen.half_angle==fixed_angle,"expanding radius and later volume reset cannot alter emitted arc")
		frozen.queue_free()
	coverage_probe.streak=100
	coverage_probe.refresh_combo_bonuses()
	check(coverage_probe.wave_angle_degrees==180 and coverage_probe.combo_damage_multiplier==3,"angle and damage cap despite excess combo")
	coverage_probe.queue_free()
	await process_frame
	await purge_fx()
	var stereo:Node2D=spawn("唱片机",Vector2(0,-240))
	stereo.set_process(false)
	stereo.music.stop()
	stereo.direction=Vector2.UP
	stereo.emit_peak(0.8)
	var pair:Array=get_nodes_in_group("MCNoteWave")
	check(pair.size()==2,"mono peak emits exactly one wave per side")
	for side_wave:Node2D in pair: side_wave.set_physics_process(false)
	check(pair[0].heading==Vector2.LEFT and pair[1].heading==Vector2.RIGHT,"world left/right emission ignores facing and enemy aim")
	check(pair[0].global_position.x<stereo.global_position.x and pair[1].global_position.x>stereo.global_position.x,"waves originate on corresponding body side")
	check(pair[0].amplitude==pair[1].amplitude and pair[0].damage==pair[1].damage,"mono source yields equal channels without fake pan")
	stereo.resolve_channel(0,0,false)
	check(stereo.streak==0 and stereo._next_resolution==0,"one missed side waits for sibling outcome")
	stereo.resolve_channel(0,1,true)
	check(stereo.streak==1,"other side hit resolves pair as one success")
	stereo.resolve_channel(0,1,true)
	check(stereo.streak==1,"duplicate channel completion never stacks twice")
	await purge_fx()
	stereo.emit_peak(0.9,0.2)
	pair=get_nodes_in_group("MCNoteWave")
	for side_wave:Node2D in pair: side_wave.set_physics_process(false)
	check(pair.size()==2 and pair[0].damage>pair[1].damage and pair[0].amplitude>pair[1].amplitude,"stereo fixture preserves stronger left channel")
	stereo.resolve_channel(1,0,true)
	stereo.resolve_channel(1,1,true)
	check(stereo.streak==2,"two channel hits together add only one stack")
	await purge_fx()
	stereo.emit_peak(-1,0.7)
	pair=get_nodes_in_group("MCNoteWave")
	for side_wave:Node2D in pair: side_wave.set_physics_process(false)
	check(pair.size()==1 and pair[0].heading==Vector2.RIGHT,"right-only peak produces no invented left event")
	stereo.resolve_channel(2,1,false)
	check(stereo.streak==2 and stereo.combo_decaying,"all active channels missed begins gradual decay")
	stereo.advance_combo_decay(0.4)
	for success:int in range(20):
		var group_id:int=100+success
		stereo._next_resolution=group_id
		stereo._channel_groups[group_id]={"expected":2,"done":{}}
		stereo.resolve_channel(group_id,0,true)
		stereo.resolve_channel(group_id,1,true)
		check(stereo.streak==success+1,"one stereo pair counts once throughout ramp")
		if success==18: check(stereo.wave_angle_degrees<180 and stereo.combo_damage_multiplier<3,"nineteen hits are not full volume")
	check(stereo.wave_angle_degrees==180 and stereo.combo_damage_multiplier==3 and stereo.music_volume_db==-2,"twentieth hit reaches all caps together")
	for track_name:String in stereo.TRACKS:
		check(stereo.peak_data[track_name].channels==1,"verified official record source is mono")
		for event:Array in stereo.peak_data[track_name].peaks:
			if event[1]!=event[2]: check(false,"mono peak channels must match")
	stereo.queue_free()
	await process_frame
	await purge_fx()
	var decay:Node2D=spawn("唱片机",Vector2(0,-240))
	decay.set_process(false)
	decay.streak=20
	decay.refresh_combo_bonuses()
	decay.resolve_wave(0,false)
	check(decay.streak==20 and decay.combo_decaying,"miss preserves full stacks at first instant")
	decay.advance_combo_decay(0.1)
	check(is_equal_approx(decay.streak,19.5) and decay.music_volume_db< -2,"fractional decay is smooth at exactly five per second")
	game.now_stop_state=true
	decay.advance_combo_decay(1)
	check(is_equal_approx(decay.streak,19.5),"pause freezes decay")
	game.now_stop_state=false
	decay.resolve_wave(2,true)
	check(not decay.combo_decaying and is_equal_approx(decay.streak,19.5),"new hit stops decay immediately even before ordered stack resolution")
	decay.advance_combo_decay(1)
	check(is_equal_approx(decay.streak,19.5),"hit stops ongoing decay")
	decay.resolve_wave(1,false)
	check(not decay.combo_decaying and decay.streak==20,"older delayed miss cannot restart decay after newer hit")
	decay.resolve_wave(3,false)
	decay.advance_combo_decay(1)
	check(decay.streak==15 and decay.combo_decaying,"fresh miss restarts decay")
	decay.register_music_hit(1)
	check(not decay.combo_decaying and decay.streak==15,"any actual late hit stops decay without awarding another stack")
	decay.resolve_wave(4,false)
	decay.advance_combo_decay(4)
	check(decay.streak==0 and not decay.combo_decaying,"decay clamps to zero")
	decay.streak=20
	decay.refresh_combo_bonuses()
	await purge_fx()
	decay.emit_peak(0.1)
	var quiet:Node2D=get_nodes_in_group("MCNoteWave")[-1]
	quiet.set_physics_process(false)
	decay.emit_peak(1.0)
	var loud:Node2D=get_nodes_in_group("MCNoteWave")[-1]
	loud.set_physics_process(false)
	check(loud.damage>quiet.damage and loud.max_radius>quiet.max_radius and loud.trail_width>quiet.trail_width and loud.half_angle>quiet.half_angle,"same stacks: instantaneous energy controls damage radius tail and angle together")
	check(is_equal_approx(rad_to_deg(loud.half_angle)*2,180) and is_equal_approx(rad_to_deg(quiet.half_angle)*2,99.0),"loud peak reaches angle cap while quiet peak remains narrow")
	decay.queue_free()
	await process_frame
	await purge_fx()
	var musician:Node2D=spawn("唱片机",Vector2(0,-250))
	musician.set_process(false)
	musician.music.stop()
	musician.visual_mob()
	var base_scale:Vector2=musician.image.scale
	var base_bottom:Vector2=musician.image.to_global(Vector2(musician.image.offset.x,musician.image.offset.y+musician.image.texture.get_height()*0.5))
	var base_collision:Vector2=musician.get_node("CollisionShape2D").shape.size
	var profile_low:Array=[0.95,0.75,0.0,0.15,0.8,0.3,0.95,false]
	var profile_high:Array=[0.0,0.05,0.10,0.95,0.95,0.8,0.4,false]
	var old_peak_count:int=musician.emitted_peaks
	var old_wave_count:int=get_nodes_in_group("MCNoteWave").size()
	var old_streak:float=musician.streak
	musician.update_music_shape(profile_low,profile_low)
	check(musician.music_shape_target<0,"low music targets squat body shape")
	check(musician.emitted_peaks==old_peak_count and get_nodes_in_group("MCNoteWave").size()==old_wave_count and musician.streak==old_streak,"body music shape does not emit attack or touch combo result")
	musician.advance_music_shape(0.5)
	musician.visual_mob()
	var low_scale:Vector2=musician.image.scale
	check(low_scale.y<base_scale.y*0.70 and low_scale.x>base_scale.x*1.16,"low pitch makes body clearly flatter and fatter")
	var low_bottom:Vector2=musician.image.to_global(Vector2(musician.image.offset.x,musician.image.offset.y+musician.image.texture.get_height()*0.5))
	check(low_bottom.distance_to(base_bottom)<0.01 and musician.get_node("CollisionShape2D").shape.size==base_collision,"low squash anchors bottom and preserves collision")
	musician.update_music_shape(profile_high,profile_high)
	check(musician.music_shape_target>0,"high music targets tall body shape")
	musician.advance_music_shape(0.7)
	musician.visual_mob()
	var high_scale:Vector2=musician.image.scale
	check(high_scale.y>base_scale.y*1.24 and high_scale.x<base_scale.x*0.84,"high pitch makes body clearly taller and thinner")
	check(high_scale.y>low_scale.y*1.6 and high_scale.x<low_scale.x*0.72,"pitch crosses a clearly visible squash axis, not proportional scaling")
	var high_bottom:Vector2=musician.image.to_global(Vector2(musician.image.offset.x,musician.image.offset.y+musician.image.texture.get_height()*0.5))
	check(high_bottom.distance_to(base_bottom)<0.01 and musician.get_node("CollisionShape2D").shape.size==base_collision,"high stretch anchors bottom and preserves collision")
	musician.update_music_shape([],[])
	musician.advance_music_shape(3.0)
	musician.visual_mob()
	check(musician.image.scale.distance_to(base_scale)<0.05,"neutral/rest music relaxes body to original shape")
	check(musician.image.to_global(Vector2(musician.image.offset.x,musician.image.offset.y+musician.image.texture.get_height()*0.5)).distance_to(base_bottom)<0.01,"body relaxation keeps same bottom center")
	var profile_long:Array=[0.0,0.1,0.1,0.85,0.9,0.9,0.4,false]
	var profile_short:Array=[0.9,0.85,0.8,0.2,0.75,0.06,0.95,false]
	var rests:Array=[0,0,0,0.5,0,0.04,0,true]
	await purge_fx()
	var emitted_before:int=musician.emitted_peaks
	musician.emit_peak(0.1,0.1,rests,rests)
	check(musician.emitted_peaks==emitted_before and get_nodes_in_group("MCNoteWave").is_empty(),"rest produces no artificial attack or miss group")
	musician.emit_peak(0.8,0.8,profile_long,profile_short)
	var musical_pair:Array=get_nodes_in_group("MCNoteWave")
	for w:Node2D in musical_pair: w.set_physics_process(false)
	var sustained:Node2D=musical_pair[0]
	var struck:Node2D=musical_pair[1]
	check(sustained.has_music_profile and struck.has_music_profile,"channel music descriptors reach real wave instances")
	check(sustained.trail_width>struck.trail_width and sustained.sustain_seconds>0.8,"held note has continuous longer tail than staccato")
	check(sustained.musical_pitch>struck.musical_pitch and sustained.pitch_confidence>=0.45,"pitch and confidence survive emission snapshot")
	check(struck.kick_strength>0.55 and struck.hat_strength>0.55 and struck.snare_strength>0.6,"low mid and high transients retained independently")
	check(struck.beat_strength>sustained.beat_strength and musician.body_punch>0,"strong beat drives greater impact feedback and body pulse")
	check(struck.line_width<=0.55 and sustained.line_width<=0.55,"music ornaments do not thicken main wave")
	var drum_target:Node2D=victim(Vector2(50,-250))
	struck.apply_music_impact(drum_target,musician)
	check(struck.music_knockbacks==1,"low transient supplies light knockback")
	var effects:Array=drum_target.get_children().filter(func(n:Node):return n.get_script()==drum_target.KNOCKBACK_EFFECT_SCRIPT)
	check(effects.size()==1 and effects[0].distance<=10 and effects[0].stun_duration==0 and not effects[0].lock_control_during_knockback,"drum kick has bounded distance and no stun/control lock")
	sustained.apply_music_impact(drum_target,musician)
	check(sustained.music_knockbacks==0,"non-drum sustained note adds no kick")
	var old_age:float=struck.age
	game.now_stop_state=true
	struck._physics_process(0.4)
	check(struck.age==old_age,"pause freezes music ornament timeline")
	game.now_stop_state=false
	for song_name:String in musician.TRACKS:
		var song:Dictionary=musician.peak_data[song_name]
		check(song.analysis=="mixed_audio_bands_autocorrelation_v1","original track has offline music feature analysis")
		var kicks:int=0
		var highs:int=0
		var holds:int=0
		var pitches:int=0
		for event:Array in song.peaks:
			var f:Array=event[3]
			if f[0]>=0.55: kicks+=1
			if f[2]>=0.55: highs+=1
			if f[5]>=0.22: holds+=1
			if f[4]>=0.45: pitches+=1
		check(kicks>0 and highs>0 and holds>0 and pitches>0,"each actual song supplies percussion pitch and sustain features")
	musician.queue_free()
	drum_target.queue_free()
	await process_frame
	await purge_fx()
	var library:Node2D=spawn("唱片机",Vector2(0,-240))
	library.set_process(false)
	check(library.TRACKS.size()==6 and library.MUSIC.size()==6 and library.DISCS.size()==6 and library.peak_data.size()==6,"six complete music/texture/feature entries")
	var palette:Array=[]
	for song:int in range(6):
		library.start_track(song)
		check(library.track_index==song and library._disc_sprite.texture==library.DISCS[song] and not library.music.playing,"each original disc is shown before playback")
		library.advance_record(0.65)
		check(library.music.stream==library.MUSIC[song] and library.music.playing and library.music.pitch_scale==1,"all six songs use their own real original-speed stream")
		var theme:Node2D=library.WAVE.new()
		world.add_child(theme)
		theme.set_physics_process(false)
		theme.configure(library,900+song,library.global_position,Vector2.RIGHT,0.8,6,song,90)
		theme.radius=60
		theme.queue_redraw()
		check(theme.song_index==song and not palette.has(theme.theme_color()),"each song retains a distinct theme without modulo-three alias")
		palette.append(theme.theme_color())
		var old_sound_count:int=library.eject_sound_count
		library._track_finished()
		check(library.eject_sound_count==old_sound_count+1,"eject plays one click per transition")
		var click:AudioStreamPlayer2D=get_nodes_in_group("MCBlockActionSFX")[-1]
		check(click.stream==library.IMPACT_AUDIO.DISPENSE[0] and click.get_meta("mc_sound_event")=="block.dispenser.dispense" and click.playing,"actual approved vanilla dispenser sound is playing")
		check(library._ejected_record.texture==library.DISCS[song],"ejected visual matches exact record index")
		library._track_finished()
		check(library.eject_sound_count==old_sound_count+1,"duplicate finish cannot duplicate eject click")
		library._ejected_record.set_physics_process(false)
		library._ejected_record.advance(8)
		check(library.track_index==(song+1)%6 and library.record_phase==0,"six-track lifecycle including index-five wrap")
		theme.queue_free()
		await process_frame
	library.queue_free()
	await process_frame
	await purge_fx()
	var floor_probe:Node2D=spawn("唱片机",Vector2(0,-200))
	floor_probe.set_process(false)
	floor_probe.streak=20
	floor_probe.refresh_combo_bonuses()
	for amp:float in [0.0,0.01,0.1,0.25,0.5,0.75,1.0]:
		var bounded:Node2D=floor_probe.WAVE.new()
		world.add_child(bounded)
		bounded.set_physics_process(false)
		bounded.configure(floor_probe,1000,floor_probe.global_position,Vector2.RIGHT,amp,6)
		var degrees:float=rad_to_deg(bounded.half_angle)*2
		check(is_equal_approx(degrees,lerpf(90,180,amp)),"full-stack loudness maps continuously from ninety to 180 degrees")
		check(degrees>=90-0.0001 and degrees<=180+0.0001,"every full-stack attack respects ninety-degree floor")
		floor_probe.streak=0
		floor_probe.refresh_combo_bonuses()
		bounded.advance(0.1)
		check(is_equal_approx(rad_to_deg(bounded.half_angle)*2,degrees),"later stack decay does not shrink an emitted wave")
		bounded.queue_free()
		floor_probe.streak=20
		floor_probe.refresh_combo_bonuses()
	floor_probe.queue_free()
	await process_frame
	await purge_fx()
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
	print("MUSIC9_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
