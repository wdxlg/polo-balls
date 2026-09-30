extends "res://tests/test_diamond_spear_audio.gd"
func weapon_sounds(event:String="") -> Array[AudioStreamPlayer2D]:
	var found:Array[AudioStreamPlayer2D] = []
	for node:Node in get_nodes_in_group("DiamondSpearSFX"):
		if node.is_queued_for_deletion() or node.get_meta("diamond_spear_source",-1)!=spear.get_instance_id(): continue
		if event.is_empty() or node.get_meta("diamond_spear_sfx_event","")==event: found.append(node)
	return found
func clear_sounds() -> void:
	for node:Node in weapon_sounds(): node.free()
	clear_impacts()
func run() -> void:
	create_timer(60.0).timeout.connect(func(): push_error("DIAMOND_SFX_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	saved_settings = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.now_stop_state = false
	game.Game_Settings.Have_Team_Damage = false
	AudioServer.set_bus_mute(0,true)
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	spear = load("res://scenes/characters/我的世界/钻石长矛.tscn").instantiate()
	spear.Team = "Team0"
	spear.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	arena.add_child(spear)
	enemy = victim(Vector2(21,0))
	await physics_frame
	await physics_frame
	reset(Vector2.ZERO,600.0)
	check(spear.STAB_SOUNDS.size()==3 and spear.SPEAR_HIT_SOUNDS.size()==3 and spear.SWEEP_SOUNDS.size()==7,"complete existing stab, spear hit and sweep variants are registered")
	# Deterministically audition every registered stream in the playback layer.
	for kind:int in range(spear.SFX_NAMES.size()):
		var pool:Array = spear._sfx_pool(kind)
		for i:int in range(pool.size()):
			clear_sounds()
			var point:Vector2 = Vector2(37,19)
			spear._play_audio(kind,i,point,1.02)
			var players:Array[AudioStreamPlayer2D] = weapon_sounds()
			check(players.size()==1 and players[0].stream==pool[i] and players[0].stream.get_length()>0.0,"native stream mapping "+spear.SFX_NAMES[kind]+" variant "+str(i))
			if players.is_empty(): continue
			check(players[0].volume_db==0.0 and is_equal_approx(players[0].pitch_scale,1.02) and players[0].global_position==point,"default volume, synchronized pitch and origin "+spear.SFX_NAMES[kind]+" "+str(i))
	clear_sounds()
	var last:AudioStream = null
	var no_repeat:bool = true
	for i:int in range(16):
		spear._emit_audio(spear.Sfx.STAB)
		var sound:AudioStreamPlayer2D = weapon_sounds("stab").back()
		if last!=null and sound.stream==last: no_repeat = false
		last = sound.stream
	check(no_repeat,"successive attacks do not repeat the same sample immediately")
	clear_sounds()
	spear.Attack()
	check(weapon_sounds("stab").size()==1,"real thrust plays one native attack cue")
	check(weapon_sounds("echo").size()==1,"only the first echo sounds at the start of the volley")
	for i:int in range(3): spear._tick_echo_queue(spear._echo_spawn_wait)
	check(weapon_sounds("echo").size()==4,"each real attacking echo gets its own spatial stab cue")
	var anchors_ok:bool = true
	for ghost:Node2D in spear._visual_nodes:
		var found:bool = false
		for sound:AudioStreamPlayer2D in weapon_sounds("echo"):
			if sound.global_position.distance_to(ghost.anchor)<0.001: found = true
		anchors_ok = anchors_ok and found
	check(anchors_ok,"echo attack cues originate at their individual world anchors")
	var sound_anchor:Vector2 = weapon_sounds("stab")[0].global_position
	spear.global_position += Vector2(50,35)
	check(weapon_sounds("stab")[0].global_position==sound_anchor,"playing attack sound does not follow a moving or teleporting caster")
	var echo_cues:int = weapon_sounds("echo").size()
	spear._emit_echo(Vector2.ZERO,Vector2.RIGHT,0.24,false,0.0)
	check(weapon_sounds("echo").size()==echo_cues,"cosmetic sweep and teleport trails do not spam extra attack sounds")
	clear_sounds()
	reset()
	enemy.global_position = Vector2(21,0)
	hit_for(50)
	check(weapon_sounds("hit").size()==1 and impact_players().size()==1,"native spear hit is layered with rather than replacing hurt feedback")
	check(impact_players()[0].get_meta("mc_sound_event","")=="entity.player.hurt","fifty damage still uses the existing hurt threshold")
	check(is_equal_approx(weapon_sounds("hit")[0].volume_db,spear.HIT_GAIN.damage_gain(50.0)),"native hit loudness also grows from the default baseline with actual damage")
	check(weapon_sounds("hit")[0].global_position==enemy.global_position,"native hit cue originates at the victim")
	clear_sounds()
	hit_for(51)
	check(weapon_sounds("hit").size()==1 and impact_players()[0].get_meta("mc_sound_event","")=="entity.player.attack.crit","higher damage preserves crit feedback plus native spear contact")
	clear_sounds()
	var hits:Dictionary = {}
	spear.damage_segment(Vector2(14,0),Vector2(27,0),3.0,1.0,hits,0.0)
	spear.damage_segment(Vector2(14,0),Vector2(27,0),3.0,1.0,hits,0.0)
	check(weapon_sounds("hit").size()==1,"same attack contact cannot double-play spear hit")
	spear.damage_segment(Vector2(14,0),Vector2(27,0),3.0,1.0,{},0.0)
	check(weapon_sounds("hit").size()==2,"independent rapid impacts are not swallowed")
	clear_sounds()
	enemy.max_block = 1000
	enemy.block = 1000
	spear.damage_segment(Vector2(14,0),Vector2(27,0),3.0,1.0,{},0.0)
	check(weapon_sounds("hit").is_empty() and impact_players().is_empty(),"fully blocked damage produces neither false spear hit nor hurt audio")
	enemy.block = 0
	spear.damage_segment(Vector2(-100,100),Vector2(-90,100),3.0,1.0,{},0.0)
	check(weapon_sounds("hit").is_empty(),"miss has no fake contact sound")
	enemy.Team = "Team0"
	spear.damage_segment(Vector2(14,0),Vector2(27,0),3.0,1.0,{},0.0)
	check(weapon_sounds("hit").is_empty(),"friendly exclusion has no contact sound")
	enemy.Team = "Team1"
	reset()
	enemy.global_position = Vector2(0,15)
	check(spear._begin_sweep(enemy),"sweep sound fixture starts")
	check(weapon_sounds("sweep").size()==1,"sweep has a distinct native swing cue")
	spear._tick_action(spear.sweep_duration*0.5)
	check(weapon_sounds("sweep").size()==1 and weapon_sounds("echo").is_empty(),"sweep frames and afterimages do not repeatedly retrigger the whoosh")
	clear_sounds()
	reset()
	enemy.global_position = Vector2(80,0)
	await physics_frame
	await physics_frame
	check(spear._begin_blink(enemy),"blink sound fixture starts")
	check(weapon_sounds("windup").size()==1 and weapon_sounds("windup")[0].stream==spear.USE_SOUNDS[0],"blink preparation uses native spear use sound")
	spear._tick_action(spear.blink_windup)
	check(weapon_sounds("blink").size()==1 and weapon_sounds("hit").size()==1,"successful crossing has a distinct thrust and actual-contact sound")
	check(weapon_sounds("blink")[0].global_position.distance_to(spear.last_blink_to)<0.001,"crossing cue records the actual landing position")
	clear_sounds()
	reset()
	enemy.global_position = Vector2(80,0)
	check(spear._begin_blink(enemy),"cancelled blink sound fixture starts")
	enemy.global_position = Vector2(0,80)
	spear._tick_action(spear.blink_windup)
	check(weapon_sounds("windup").size()==1 and weapon_sounds("blink").is_empty(),"failed blink may prepare but cannot play a fake crossing cue")
	clear_sounds()
	reset()
	spear._speed_sound_armed = true
	spear._momentum = spear.echo_upgrade_speed
	spear._update_speed_audio()
	for i:int in range(20): spear._update_speed_audio()
	check(weapon_sounds("ready").size()==1,"entering high speed plays one readiness cue instead of spamming each frame")
	spear._momentum = spear.echo_upgrade_speed*0.85
	spear._update_speed_audio()
	spear._momentum = spear.echo_upgrade_speed
	spear._update_speed_audio()
	check(weapon_sounds("ready").size()==2,"speed cue rearms only after dropping through the lower threshold")
	clear_sounds()
	game.now_stop_state = true
	spear._speed_sound_armed = true
	spear._emit_audio(spear.Sfx.STAB)
	spear._update_speed_audio()
	check(weapon_sounds().is_empty() and spear._speed_sound_armed,"pause emits no weapon sounds and does not consume readiness cue")
	game.now_stop_state = false
	spear._play_audio(999,0,Vector2.ZERO,1.0)
	spear._play_audio(spear.Sfx.STAB,99,Vector2.ZERO,1.0)
	check(weapon_sounds().is_empty(),"invalid sound kind and variant are safely ignored")
	spear._emit_audio(spear.Sfx.STAB)
	var cleanup:AudioStreamPlayer2D = weapon_sounds()[0]
	check(cleanup.is_in_group("BattleTransient"),"weapon sounds participate in battle cleanup")
	if AudioServer.get_bus_index(&"GameplayRecord")>=0:
		check(cleanup.bus==&"GameplayRecord","weapon sounds respect the gameplay audio bus")
	cleanup.finished.emit()
	check(cleanup.is_queued_for_deletion(),"finished voice cleans itself up")
	clear_sounds()
	for i:int in range(60): spear._emit_audio(spear.Sfx.STAB)
	check(get_nodes_in_group("DiamondSpearSFX").size()<=48,"weapon sound voice count remains globally bounded")
	clear_sounds()
	arena.queue_free()
	await process_frame
	game.Game_Settings = saved_settings
	game.now_stop_state = saved_stop
	print("DIAMOND_SFX_RESULT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
