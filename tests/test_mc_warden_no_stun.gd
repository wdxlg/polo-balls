extends "res://tests/test_mc_warden_sound.gd"
func check_push(target:Node2D,label:String) -> void:
	var found:bool=false
	for effect:Node in target.get_children():
		if effect.get_script()!=target.KNOCKBACK_EFFECT_SCRIPT: continue
		found=true
		check(effect.stun_duration==0.0 and not effect.lock_control_during_knockback and not effect._lock_acquired,label+": no stun or control lock")
	check(found,label+": ordinary knockback effect remains")
	check(not target.dizziness and int(target.get_meta("generic_motion_lock_count",0))==0,label+": victim remains able to act")
func run() -> void:
	var o:Vector2=await setup_world()
	create_timer(60).timeout.connect(func(): finish(2))
	var w:Node2D=actor("监守者",o)
	var probe_target:Node2D=dummy(o+Vector2(120,0))
	await physics_frame
	await process_frame
	world.get_node("MCBattleNoise").set_physics_process(false)
	w.alert_level=100; w.begin_probe(); w.listen_heading=Vector2.RIGHT; w.emit_probe(); halt_waves(w)
	var hp:float=probe_target.health
	latest(w,"probe").advance(0.62); halt_waves(w)
	check(probe_target.health<hp and latest(w,"return")!=null,"probe still damages and generates return")
	check_push(probe_target,"probe")
	w._cancel_attacks(true); w.form=w.Form.AWAKE; w._form_stats(true)
	var melee_target:Node2D=dummy(o+Vector2(40,0))
	await physics_frame
	await process_frame
	w.sounds.clear(); w.hear_noise(melee_target,melee_target.global_position,"attack",120)
	w.begin_melee(); hp=melee_target.health; w.release_melee()
	check(is_equal_approx(hp-melee_target.health,96),"melee retains 96 damage")
	check_push(melee_target,"melee")
	w._cancel_attacks(true)
	var sonic_target:Node2D=dummy(o+Vector2(0,170))
	await physics_frame
	await process_frame
	w.sounds.clear(); w.hear_noise(sonic_target,sonic_target.global_position,"attack",120)
	w.begin_sonic(); w.sonic_left=0; w.release_sonic(); halt_waves(w)
	hp=sonic_target.health; latest(w,"sonic").advance(0.25)
	check(is_equal_approx(hp-sonic_target.health,144),"sonic retains 144 damage")
	check_push(sonic_target,"sonic")
	print("WARDEN NO STUN: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
