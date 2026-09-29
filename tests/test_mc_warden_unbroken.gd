extends "res://tests/test_mc_warden_sound.gd"
func impact(w:Node2D) -> AudioStreamPlayer2D:
	for i:int in range(w._cue_players.size()-1,-1,-1):
		var p:AudioStreamPlayer2D=w._cue_players[i]
		if is_instance_valid(p) and p.has_meta("mc_sound_event"): return p
	return null
func run() -> void:
	var o:Vector2=await setup_world()
	create_timer(60).timeout.connect(func(): finish(2))
	var w:Node2D=actor("监守者",o)
	var enemy:Node2D=dummy(o+Vector2(170,0))
	await physics_frame
	await process_frame
	world.get_node("MCBattleNoise").set_physics_process(false)
	check(w.impact_event(50)=="entity.player.hurt" and w.impact_event(51)=="entity.player.attack.crit","strict threshold: 50 normal, above 50 critical")
	check(w.impact_volume(10)<w.impact_volume(33) and w.impact_volume(33)<w.impact_volume(50) and w.impact_volume(96)<w.impact_volume(144),"volume increases across actual damage levels including melee and sonic")
	w.damage_with_sound(enemy,50,enemy.global_position)
	var p:AudioStreamPlayer2D=impact(w)
	check(is_instance_valid(p) and p.playing and p.get_meta("mc_sound_event")=="entity.player.hurt","actual 50-damage hit plays MC hurt audio")
	var volume:float=p.volume_db
	w.damage_with_sound(enemy,51,enemy.global_position)
	p=impact(w)
	check(p.get_meta("mc_sound_event")=="entity.player.attack.crit" and p.volume_db>volume,"actual 51-damage hit plays louder MC critical audio")
	enemy.Damage_reduction=0.9
	w.damage_with_sound(enemy,100,enemy.global_position)
	check(impact(w).get_meta("mc_sound_event")=="entity.player.hurt","sound is chosen after damage reduction, not from nominal attack")
	enemy.Damage_reduction=1.0
	var count:int=w._cue_players.size()
	w.damage_with_sound(enemy,100,enemy.global_position)
	check(w._cue_players.size()==count,"zero actual damage emits no false hurt sound")
	enemy.Damage_reduction=0.0
	w.alert_level=100; w.begin_probe(); w.listen_heading=Vector2.RIGHT; w.emit_probe(); halt_waves(w)
	var wave:Node2D=latest(w,"probe")
	wave.advance(0.85); halt_waves(w)
	check(impact(w).get_meta("mc_sound_event")=="entity.player.hurt","real probe swept hit uses MC normal hurt sound")
	w._cancel_attacks(true); w.sounds.clear(); w.form=w.Form.AWAKE; w._form_stats(true)
	w.hear_noise(enemy,o+Vector2(170,0),"attack",120)
	check(w.begin_sonic(),"normal audible sound starts a sonic charge")
	var locked:Vector2=w._sonic_heading
	var left:float=w.sonic_left
	w.receive_positional_damage(20,o,true,enemy)
	check(w._sonic_pending and w.sonic_left==left,"taking damage cannot cancel or restart sonic charge")
	w.dizziness=true
	w.step_mob(0.3)
	check(w._sonic_pending and is_equal_approx(w.sonic_left,left-0.3),"real stun cannot interrupt or stall committed windup")
	var pause_left:float=w.sonic_left
	game.now_stop_state=true; w.step_mob(2)
	check(w.sonic_left==pause_left,"game pause still freezes uninterruptible windup")
	game.now_stop_state=false
	w.step_mob(1.0); halt_waves(w)
	wave=latest(w,"sonic")
	check(w.sonic_casts==1 and wave!=null and wave.heading==locked,"charge completes once while still stunned along original sound direction")
	var hp:float=enemy.health
	wave.advance(0.25)
	check(not wave.is_queued_for_deletion() and enemy.health<hp,"fired sonic wave keeps travelling and damaging during stun")
	check(impact(w).get_meta("mc_sound_event")=="entity.player.attack.crit","real awakened sonic hit plays MC critical sound")
	check(not w.begin_sonic() and not w.begin_melee(),"stun still prevents starting new attacks")
	w.dizziness=false
	# This case starts a fresh cast; retire the previous frozen test projectile/recovery.
	w._cancel_attacks(true)
	w.sounds.clear(); w._sonic_cooldown=0
	w.hear_noise(enemy,o+Vector2(170,0),"attack",120); w.begin_sonic()
	var knock:Node=w.apply_knockback(Vector2.DOWN,24,260,0,0,{"source":enemy,"stop_on_character":false,"collision_damage":0.0})
	check(is_instance_valid(knock) and knock._lock_acquired,"test uses a real knockback motion lock")
	w.step_mob(1.2); halt_waves(w)
	check(w.sonic_casts==2,"real knockback also cannot cancel a committed charge")
	w.Die()
	check(w.waves.is_empty() and not w._sonic_pending,"death still clears all sonic attacks")
	print("WARDEN IMPACT/UNBROKEN: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
