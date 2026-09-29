extends "res://tests/test_mc_warden_sound.gd"
func reset_focus() -> void:
	world._damage_focus_pending_strength=-1.0
	world._damage_focus_started_usec=0
	world._damage_focus_next_usec=0
	world._heavy_hit_pending_strength=-1.0
	world._heavy_hit_next_allowed_usec=0
	world._release_heavy_hitstop()
func close_sound(w:Node,enemy:Node) -> void:
	w.sounds.clear();enemy.global_position=w.global_position+Vector2(30,0)
	w.hear_noise(enemy,enemy.global_position,"attack",120)
func run() -> void:
	var o:Vector2=await setup_world()
	create_timer(60).timeout.connect(func():finish(2))
	var w:Node=actor("监守者",o)
	var enemy:Node=dummy(o+Vector2(170,0))
	await physics_frame;await process_frame
	world.get_node("MCBattleNoise").set_physics_process(false)
	w.form=w.Form.AWAKE;w._form_stats(true)
	w.hear_noise(enemy,enemy.global_position,"attack",120)
	check(w.begin_sonic(),"sonic charge begins normally")
	close_sound(w,enemy)
	check(not w.begin_melee(),"close enemy cannot start melee during charge")
	var hp:float=enemy.health
	w._melee_pending=true;w.melee_left=0.01;w.release_melee()
	check(enemy.health==hp and not w._melee_pending,"stale melee callback cannot deal invisible charge damage")
	w.release_sonic();halt_waves(w)
	var wave:Node=latest(w,"sonic")
	check(w.sonic_recover>0 and w.sonic_attack_busy(),"sonic release keeps the melee lock active")
	check(not w.begin_melee(),"manual melee input is rejected during sonic recovery")
	w.Attack();w.player_control_action(0)
	check(not w._melee_pending and w.melee_left==0,"both ordinary attack entry points obey sonic lock")
	w._melee_pending=true;w.melee_left=0.01;w.release_melee()
	check(enemy.health==hp and not w._melee_pending,"stale melee callback cannot deal invisible recovery damage")
	game.now_stop_state=true;var left:float=w.sonic_recover;w.step_mob(1)
	check(w.sonic_recover==left and not w.begin_melee(),"pause cannot expire the sonic lock")
	game.now_stop_state=false
	w.sonic_recover=0
	check(not w.begin_melee(),"live sonic projectile still prevents melee even if recovery was externally cleared")
	wave.queue_free();w._attack_cooldown=0
	# Noise heard during attack is intentionally not buffered for a post-attack turn.
	close_sound(w,enemy)
	check(w.begin_melee(),"melee becomes available once sonic flight and recovery both finish")
	reset_focus()
	w.melee_left=0;w.release_melee()
	check(enemy.health<hp,"normal melee damage resumes after sonic finishes")
	check(world._damage_focus_pending_strength>=0.0,"real melee against high HP target requests shared focus")
	var weak_strength:float=world._damage_focus_pending_strength
	reset_focus();w.damage_with_sound(enemy,144,enemy.global_position,true)
	check(world._damage_focus_pending_strength>weak_strength,"higher actual sonic-level damage requests stronger bounded focus")
	check(world._damage_focus_pending_position.distance_to(enemy.global_position)<0.01,"focus anchors to the actual victim rather than caster")
	world._update_damage_focus()
	check(world._damage_focus_peak_zoom>1.0 and world._damage_focus_peak_zoom<=world.damage_focus_max_zoom,"shared focus produces a zoom without exceeding global cap")
	var started:int=world._damage_focus_started_usec
	w.damage_with_sound(enemy,288,enemy.global_position,true)
	check(world._damage_focus_started_usec==started and world._damage_focus_pending_strength<0,"repeated hits respect common focus cooldown and do not restart camera")
	reset_focus();enemy.Damage_reduction=1.0
	w.damage_with_sound(enemy,500,enemy.global_position,true)
	check(world._damage_focus_pending_strength<0,"immune target cannot trigger fake high-damage focus")
	enemy.Damage_reduction=0.9;reset_focus()
	w.damage_with_sound(enemy,100,enemy.global_position,true)
	check(world._damage_focus_pending_strength<0,"low actual damage after reduction cannot trigger strong-hit supplement")
	enemy.Damage_reduction=0;reset_focus()
	w.damage_with_sound(enemy,50,enemy.global_position,true)
	check(world._damage_focus_pending_strength<0,"50-damage boundary does not activate supplemental focus")
	w.damage_with_sound(enemy,51,enemy.global_position,true)
	check(world._damage_focus_pending_strength>=0,"damage above 50 activates high-hit feedback on high HP victims")
	reset_focus();world.damage_focus_enabled=false
	w.damage_with_sound(enemy,200,enemy.global_position,true)
	check(world._damage_focus_pending_strength<0,"global camera focus opt-out is respected")
	world.damage_focus_enabled=true
	w._cancel_attacks(true);w._sonic_cooldown=0;w._attack_cooldown=0
	enemy.global_position=o+Vector2(170,0);w.sounds.clear();w.hear_noise(enemy,enemy.global_position,"attack",120)
	check(w.begin_sonic(),"next real sonic attack may start after the previous one")
	w.dizziness=true;w.step_mob(1.2);halt_waves(w)
	check(latest(w,"sonic")!=null and not w.begin_melee(),"committed sonic remains uninterruptible but cannot enable melee while stunned")
	await physics_frame
	reset_focus()
	var actual_wave:Node=latest(w,"sonic")
	hp=enemy.health
	actual_wave.advance(0.25)
	check(enemy.health<hp and world._damage_focus_pending_strength>=0,"real swept sonic hit also triggers confirmed high-damage focus")
	w.dizziness=false;w._cancel_attacks(true)
	print("WARDEN_FOCUS_LOCK checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
