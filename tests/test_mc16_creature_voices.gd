extends "res://tests/test_mc16_native_feedback.gd"
func last_voice(actor:Node,event:String) -> AudioStreamPlayer2D:
	var result:AudioStreamPlayer2D
	for player:Node in get_nodes_in_group("MCNativeSFX"):
		if player.get_meta("mc16_feedback_source",0)==actor.get_instance_id() and player.get_meta("mc_sound_event","")==event: result = player
	return result
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(55.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	if not await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self):
		finish(1)
		return
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	geometry = load("res://scripts/effects/我的世界/mc16_geometry.gd")
	var enemy:Node = dummy(center+Vector2(300,300))
	for pair:Array in [["蜘蛛","spider"],["溺尸","drowned"]]:
		var actor:Node = spawn("res://scenes/characters/我的世界/"+pair[0]+".tscn",center)
		var role:String = pair[1]
		var f:Node = actor.native_feedback
		f.set_physics_process(false)
		f._rng.seed = 314159
		actor._mc_voice_rng.seed = 314159
		await process_frame
		await process_frame
		fresh(actor)
		var breath:String = "entity."+role+".ambient"
		var step:String = "entity."+role+".step"
		var hurt:String = "entity."+role+".hurt"
		var death:String = "entity."+role+".death"
		actor._mc_ambient_wait = 0.0
		actor.mc_tick_ambient(0.0)
		var breathing:AudioStreamPlayer2D = actor._mc_ambient_player
		check(is_instance_valid(breathing) and count(actor,breath)==1,role+" breath uses its original ambient bank")
		var duration:float = breathing.stream.get_length()
		var wait:float = actor._mc_ambient_wait
		check(wait>=duration+actor.ambient_gap_min and wait<=duration+actor.ambient_gap_max,role+" next breath = previous clip duration + random gap")
		actor.mc_tick_ambient(duration*0.5)
		check(count(actor,breath)==1,role+" breathing cannot overlap its preceding clip")
		var intervals:Array[float] = []
		for i:int in range(6):
			actor.mc_stop_ambient()
			fresh(actor)
			f._clock += 20.0
			actor._mc_ambient_wait = 0.0
			actor.mc_tick_ambient(0.0)
			intervals.append(actor._mc_ambient_wait-actor._mc_ambient_player.stream.get_length())
		check(intervals.max()-intervals.min()>0.1,role+" breathing interval is genuinely randomized")
		wait = actor._mc_ambient_wait
		game.now_stop_state = true
		actor.mc_tick_ambient(10.0)
		check(is_equal_approx(wait,actor._mc_ambient_wait),role+" pause freezes breathing countdown")
		game.now_stop_state = false
		actor.mc_stop_ambient()
		fresh(actor)
		f._last_position = actor.global_position
		f.advance(1.0)
		check(count(actor,step)==0,role+" standing does not trigger footsteps")
		actor.global_position += Vector2(2,0)
		f.advance(0.05)
		var foot:AudioStreamPlayer2D = last_voice(actor,step)
		check(is_instance_valid(foot),role+" walking even a short distance can trigger a footstep")
		var stride:float = f.FOOTSTEP.base_speed(actor)*(f._step_length+(actor.footstep_gap_min+actor.footstep_gap_max)*0.5)
		actor.global_position += Vector2(2,0)
		f.advance(0.01)
		check(count(actor,step)==1,role+" less than one stride adds no footstep")
		var walked:float = 2.0
		while count(actor,step)==1 and walked<stride*2.0:
			actor.global_position += Vector2(10,0)
			walked += 10.0
			f.advance(0.1)
		check(count(actor,step)==2 and walked>=stride*0.9,role+" the next footstep comes after one stride, even while the previous may still play")
		var before:int = count(actor,step)
		fresh(actor)
		f._clock += 20.0
		actor.dizziness = true
		actor.global_position += Vector2(2,0)
		f.advance(0.016)
		check(count(actor,step)==before,role+" stunned displacement is not walking")
		actor.dizziness = false
		actor.global_position += Vector2(400,0)
		f.advance(0.016)
		check(count(actor,step)==before,role+" teleport does not trigger a footstep")
		actor.global_position = center
		actor.hurt_voice_chance = 0.0
		actor.on_actual_health_damage_received(1.0,100.0)
		check(count(actor,hurt)==0,role+" zero hurt chance stays silent")
		actor.hurt_voice_chance = 1.0
		actor.on_actual_health_damage_received(0.0,100.0)
		check(count(actor,hurt)==0,role+" no actual HP loss has no hurt voice")
		var hp:float = actor.health
		actor.receive_positional_damage(2.0,actor.global_position,false,enemy)
		check(actor.health<hp and count(actor,hurt)==1,role+" actual received damage triggers original hurt voice")
		actor.on_actual_health_damage_received(1.0,100.0)
		check(count(actor,hurt)==1,role+" rapid hits do not overlap the same hurt clip")
		before = count(actor,hurt)
		actor.hurt_voice_chance = 0.45
		for i:int in range(20):
			fresh(actor)
			f._clock += 10.0
			actor.on_actual_health_damage_received(1.0,100.0)
		var hits:int = count(actor,hurt)-before
		check(hits>0 and hits<20,role+" default hurt chance produces both voice and silence")
		actor.set_multiplayer_authority(2)
		check(f.voice("ambient",-8.0)==null and f.voice("hurt",-5.0)==null,role+" clients cannot originate duplicate creature voices")
		actor.set_multiplayer_authority(1)
		if role=="drowned":
			check(actor._trident.DRAW_SIZE==18.0,"flying and lodged trident is reduced from 24 to 18")
			var manifest:Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Images/characters/我的世界/native_frames/hand_pounce/manifest.json"))
			check(is_equal_approx(float(manifest.hand_scale),0.5),"independent held native layer is another 25 percent smaller")
			fresh(actor)
			enemy.global_position = center+Vector2(100,0)
			check(actor.throw_trident(enemy) and count(actor,"item.trident.throw")==1,"drowned throw retains original trident throw sound")
		fresh(actor)
		actor.health = 0
		actor.Die()
		var final_voice:AudioStreamPlayer2D = last_voice(actor,death)
		check(is_instance_valid(final_voice) and count(actor,death)==1,role+" zero-HP death emits native death sound")
		actor.Die()
		check(count(actor,death)==1,role+" death sound triggers once only")
		f.advance(0.016)
		check(not final_voice.stream_paused,role+" dying does not pause its own death sound")
		check(f.voice("hurt",-5.0)==null and f.voice("ambient",-8.0)==null,role+" dead actor cannot breathe or grunt")
		actor.queue_free()
		await physics_frame
		await process_frame
		check(is_instance_valid(final_voice) and not final_voice.is_queued_for_deletion(),role+" death clip survives removal of the actor")
	clear_voices()
	print("MC16_CREATURE_VOICES_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
