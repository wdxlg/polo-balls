extends "res://tests/test_mc_warden_sound.gd"
func run() -> void:
	var o:Vector2=await setup_world()
	create_timer(60).timeout.connect(func(): finish(2))
	var w:Node2D=actor("监守者",o)
	var enemy:Node2D=dummy(o+Vector2(120,0))
	await physics_frame
	await process_frame
	world.get_node("MCBattleNoise").set_physics_process(false)
	w.alert_level=100
	check(w.begin_probe() and w.probes_remaining==5,"full alert budgets exactly five shots")
	var sounds_before:int=w._cue_players.size()
	for i:int in range(5):
		check(w.emit_probe(),"budgeted probe can launch")
		halt_waves(w)
	check(w.probe_casts==5 and w.probes_remaining==0 and w.probe_left==0,"fifth shot ends burst without deleting its projectiles")
	check(not w.emit_probe(),"sixth shot is rejected until another full alert")
	check(w._cue_players.size()==sounds_before+5,"every emitted shot creates its own native sound even in the same frame")
	var wave:Node2D=latest(w,"probe")
	var hp:float=enemy.health
	wave.advance(0.62); halt_waves(w)
	check(enemy.health<hp and latest(w,"return")!=null,"last bullet damages and creates echo after burst already ended")
	check(w.signals_received==0,"contact is not credited before the echo travels back")
	var echo:Node2D=latest(w,"return")
	# Ordinary movement lock used by real knockback must not erase the pending return.
	var knock:Node=w.apply_knockback(Vector2.DOWN,24.0,260.0,0.0,0.0,{"source":enemy,"stop_on_character":false,"collision_damage":0.0})
	check(is_instance_valid(knock) and knock._lock_acquired and w.dizziness and w.can_act(),"ordinary knockback does not invalidate shrieker echoes")
	w.step_mob(0.01)
	check(not echo.is_queued_for_deletion() and not w._pending_echoes.is_empty(),"normal knockback keeps registered in-flight progress")
	echo.advance(0.5)
	check(w.signals_received==1,"echo returns and credits while owner is knocked back")
	# Physical contact still echoes against a fully damage-reducing enemy.
	w._cancel_attacks(true)
	w.sounds.clear(); w.alert_level=100; w.begin_probe(); w.listen_heading=Vector2.RIGHT
	enemy.Damage_reduction=1.0
	w.emit_probe(); halt_waves(w)
	wave=latest(w,"probe"); hp=enemy.health
	wave.advance(0.62); halt_waves(w)
	check(enemy.health==hp and latest(w,"return")!=null,"armor-absorbed real contact still generates an echo")
	echo=latest(w,"return"); echo.advance(0.5)
	check(w.signals_received==2,"zero-health-damage contact contributes after actual return")
	var signals:int=w.signals_received
	wave.advance(0.05); halt_waves(w)
	check(w.signals_received==signals and w._pending_echoes.is_empty(),"same projectile cannot repeatedly credit one enemy")
	# Shared audio saturation and another actor must not swallow probe cues.
	var other:Node2D=actor("监守者",o+Vector2(0,150))
	for i:int in range(28): w.cue("probe_fire",-10.0)
	var count:int=other._cue_players.size()
	other.cue("probe_fire",-10.0)
	check(other._cue_players.size()==count+1,"another shrieker receives its own audible shot even at voice capacity")
	check(get_nodes_in_group("MCNativeSFX").size()<=24,"priority audio remains bounded")
	print("WARDEN BURST CONTRACTS: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
