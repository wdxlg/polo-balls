extends "res://tests/test_mc_frontier.gd"
func halt_waves(w:Node2D) -> void:
	for wave:Variant in w.waves:
		if is_instance_valid(wave): wave.set_physics_process(false)
func latest(w:Node2D,kind:String) -> Node2D:
	for i:int in range(w.waves.size()-1,-1,-1):
		var wave:Variant=w.waves[i]
		if is_instance_valid(wave) and not wave.is_queued_for_deletion() and wave.kind==kind: return wave
	return null
func silent(w:Node2D) -> void:
	w.sounds.clear(); w.heard_strength=0; w.quiet_time=0
	w._cancel_attacks(true)
func run() -> void:
	var o:Vector2=await setup_world()
	create_timer(90).timeout.connect(func(): finish(2))
	var w:Node2D=actor("监守者",o)
	var enemy:Node2D=dummy(o+Vector2(120,0))
	var other:Node2D=dummy(o+Vector2(200,120))
	var ally:Node2D=dummy(o+Vector2(0,120),"Team0")
	await physics_frame
	await process_frame
	var bus:Node=world.get_node("MCBattleNoise")
	bus.set_physics_process(false)
	check(w.form==0 and w.Max_health==600 and w.signals_received==0,"starts as vulnerable shrieker with no echo credits")
	check(not w.begin_probe() and not w.begin_emergence() and not w.receive_echo(0,"fake"),"cannot bypass alert, real-hit echo or summon requirements")
	check(is_equal_approx(w.sound_at(o+Vector2(180,0),120),60) and w.sound_at(o+Vector2(360,0),120)==0,"sound fades with distance and is zero at hearing boundary")
	check(not w.hear_noise(ally,ally.global_position,"attack",120) and not w.hear_noise(enemy,o+Vector2(361,0),"attack",120),"allies and inaudible far enemies cannot raise alert")
	var gains:Array[float]=[]
	for kind:String in ["move","collision","attack"]:
		w.alert_level=0
		w.hear_noise(enemy,enemy.global_position,kind,bus.POWER[kind])
		gains.append(w.alert_level)
	check(gains[2]>gains[1] and gains[1]>gains[0] and gains[0]>0,"attack alert gain is largest, collision medium, movement smallest")
	w.direction=Vector2.RIGHT
	w.hear_noise(other,o+Vector2(0,-80),"move",24)
	check(w.listen_heading.dot(Vector2.UP)>0.99 and w.direction.dot(Vector2.RIGHT)>0.99,"hearing aims the shrieker without redirecting its movement")
	w.alert_level=0; w.sounds.clear()
	bus._positions.clear(); bus._next_event.clear()
	bus.sample_actions()
	var initial:float=w.alert_level
	enemy.velocity=Vector2(300,0)
	bus.sample_actions()
	check(w.alert_level==initial,"first observation and fake velocity without displacement are silent")
	enemy.global_position+=Vector2(2,0)
	bus.clock+=0.3; bus.sample_actions()
	check(w.alert_level>initial,"actual enemy displacement produces a small noise event")
	bus.clock+=0.3; bus._next_event.clear(); w.alert_level=0
	var enemy_hp:float=enemy.health
	enemy.transition_state(enemy.State.Move,enemy.State.Skill)
	check(w.alert_level>0 and enemy.health==enemy_hp,"shared attack/skill start is audible before any damage or hit")
	bus.clock+=0.3; bus._next_event.clear(); w.alert_level=0
	enemy._last_collision_feedback_physics_frame=-1
	enemy.notify_bounce_feedback(Vector2.LEFT,100)
	check(w.alert_level>0,"real common collision feedback emits medium noise")
	bus.clock+=0.3; bus._next_event.clear(); w.alert_level=0
	var projectile:Node2D=dummy(o+Vector2(500,0))
	projectile.Master=enemy
	bus.sample_actions()
	check(w.alert_level>0,"projectile emission is heard at its owner even before a missed shot hits anything")
	var after_emission:float=w.alert_level
	bus.sample_actions()
	check(w.alert_level==after_emission,"one existing projectile is not repeatedly counted as new attack emission")
	projectile.queue_free()
	await process_frame
	# Five pulses may hit the same enemy, but each pulse credits it only once and only after return.
	silent(w); w.alert_level=w.alert_max
	check(w.begin_probe() and w.probes_remaining==5 and w.form==0,"full alert opens a timed stream instead of immediately summoning")
	enemy.global_position=o+Vector2(120,0)
	other.global_position=o+Vector2(300,160)
	ally.global_position=o+Vector2(60,0)
	await physics_frame
	await process_frame
	w.listen_heading=Vector2.RIGHT
	var ally_hp:float=ally.health
	for round_index:int in range(5):
		check(w.emit_probe(),"continuous probe may emit another round")
		halt_waves(w)
		var wave:Node2D=latest(w,"probe")
		var hp:float=enemy.health
		wave.advance(0.01)
		check(enemy.health==hp,"probe has real travel time, not instant full-lane damage")
		wave.advance(0.62)
		halt_waves(w)
		var pushed:bool=false
		for child:Node in enemy.get_children():
			if child.get_script()==enemy.KNOCKBACK_EFFECT_SCRIPT and child.is_active_effect(): pushed=true
		check(pushed,"probe contact uses the shared real knockback controller")
		check(enemy.health<hp and w.signals_received==round_index,"probe hit deals damage but does not credit an unreturned echo")
		var echo:Node2D=latest(w,"return")
		check(is_instance_valid(echo),"accepted probe hit emits a returning native sonic signal")
		var hit_hp:float=enemy.health
		wave._sweep(o,o+Vector2(180,0))
		check(enemy.health==hit_hp,"same wave cannot repeatedly damage or signal from one victim")
		if round_index==4: w.health=300
		var token:String=echo.token
		echo.advance(0.4)
		check(w.signals_received==round_index+1 and not w.receive_echo(w.ritual_epoch,token),"returned echo credits once; replay is rejected")
	check(ally.health==ally_hp,"probe respects teams even when friend stands on the ray")
	check(w.form==1 and w.summons==0,"five actual returning signals start emergence, not instant awakening")
	var left:float=w.form_left
	game.now_stop_state=true
	w.tick_physics(0,3)
	check(w.form_left==left,"combat pause freezes summon")
	game.now_stop_state=false
	w.tick_physics(0,w.emerge_duration+0.01)
	check(w.form==2 and w.Max_health==1200 and w.health==600,"awakening preserves health percentage")
	check(not w.finish_emergence() and w.summons==1,"duplicate emergence cannot resummon")
	# Only immutable sound locations, never target identity/current position, drive actions.
	silent(w)
	enemy.global_position=o+Vector2(20,0)
	other.global_position=o+Vector2(0,180)
	w.hear_noise(enemy,enemy.global_position,"move",24)
	w.hear_noise(other,other.global_position,"attack",120)
	check(w._best_sound().point==other.global_position,"louder far attack wins over a quiet nearby movement")
	var fixed:Vector2=other.global_position
	other.global_position=o+Vector2(-180,0)
	check(w._best_sound().point==fixed,"silent enemy relocation does not move the stored sound or lock a target")
	silent(w); w.set_player_control_peer(0); w.direction=Vector2.RIGHT
	var pos:Vector2=w.global_position
	w.move(w.Speed,0.016)
	check(w.global_position.distance_to(pos)>0.01,"awake Warden moves normally even with no remembered enemy")
	w.global_position=o
	w.hear_noise(enemy,o+Vector2(10,0),"attack",120)
	check(w.rage_left>0,"very loud perceived sound triggers angry running")
	var normal_velocity:float=w.Speed*0.6
	w.direction=Vector2.RIGHT
	w.move(w.Speed,0.016)
	check(is_equal_approx(w.velocity.length(),normal_velocity*1.6),"rage accelerates normal movement rather than teleporting or bypassing movement")
	w.global_position=o; w.set_player_control_peer(1)
	# Close directional swing hits a different enemy standing in the lane, not the original sound source.
	silent(w); w._attack_cooldown=0
	enemy.global_position=o+Vector2(40,0)
	w.hear_noise(enemy,enemy.global_position,"move",24)
	check(w.begin_melee(),"nearby movement sound can trigger a melee strike")
	enemy.global_position=o+Vector2(0,120)
	other.global_position=o+Vector2(40,0)
	await physics_frame
	var old_enemy_hp:float=enemy.health
	var other_hp:float=other.health
	w.release_melee()
	check(enemy.health==old_enemy_hp and other.health<other_hp,"melee strikes sound direction and can hit a different occupant")
	check(is_equal_approx(other_hp-other.health,96),"awakened melee is halved to 96 base damage")
	# A loud far sound is a slowed, fixed-direction charge. Moving away can dodge it.
	silent(w); w._sonic_cooldown=0
	enemy.global_position=o+Vector2(170,0)
	other.global_position=o+Vector2(250,150)
	w.hear_noise(enemy,enemy.global_position,"attack",120)
	check(w.begin_sonic(),"far loud sound starts sonic windup")
	var heading:Vector2=w._sonic_heading
	w.set_player_control_peer(0); w.direction=Vector2.RIGHT; w.move(w.Speed,0.016)
	check(w.velocity.length()>0 and w.velocity.length()<normal_velocity*0.3,"sonic windup slows movement instead of freezing normal locomotion")
	w.set_player_control_peer(1)
	enemy.global_position=o+Vector2(170,100)
	var hp:float=enemy.health
	w.sonic_left=0; w.release_sonic(); halt_waves(w)
	var beam:Node2D=latest(w,"sonic")
	beam.advance(0.4)
	check(enemy.health==hp and beam.heading==heading,"moving silently off the locked sound direction dodges the sonic attack")
	# Terrain/shield piercing and stronger damage plus knockback on real swept contacts.
	silent(w); w.global_position=o; w._sonic_cooldown=0
	enemy.global_position=o+Vector2(170,0)
	var barrier:StaticBody2D=wall(o+Vector2(100,0),Vector2(12,100))
	enemy.max_block=300; enemy.default_properties.max_block=300; enemy.block=300
	await physics_frame
	await process_frame
	w.hear_noise(enemy,enemy.global_position,"attack",120); w.begin_sonic()
	w.sonic_left=0; w.release_sonic(); halt_waves(w)
	beam=latest(w,"sonic")
	hp=enemy.health
	beam.advance(0.3)
	check(is_equal_approx(hp-enemy.health,144) and enemy.block==300,"awakened sonic is halved to 144 while still piercing wall and shield")
	barrier.queue_free()
	silent(w); w._sonic_cooldown=0
	w.hear_noise(enemy,enemy.global_position,"attack",120); w.begin_sonic()
	var casts:int=w.sonic_casts
	w.dizziness=true; w.step_mob(1.2); w.dizziness=false; halt_waves(w)
	check(w.sonic_casts==casts+1 and w.sonic_left==0,"stun does not interrupt the committed sonic attack")
	silent(w); w.quiet_time=0
	w.step_mob(8.1)
	check(w.form==3,"sustained silence triggers burrowing")
	w.step_mob(1.81)
	check(w.form==0 and w.signals_received==0 and w.alert_level==0 and w.Max_health==600,"burrowing resets both alert and echo ritual")
	check(not w.receive_echo(w.ritual_epoch-1,"old"),"old-ritual return signals cannot affect a new ritual")
	var ghost:Node2D=actor("监守者",o+Vector2(-240,-120))
	ghost.set_multiplayer_authority(2)
	ghost.accept_visual(w.visual_state())
	check(ghost.form==w.form and ghost.signals_received==w.signals_received and not ghost.begin_probe(),"client snapshot reproduces state without granting gameplay authority")
	ghost.queue_free()
	var quiet:Node2D=actor("监守者",o+Vector2(-260,-180))
	quiet.listen_heading=Vector2.LEFT
	quiet.alert_level=100
	quiet.begin_probe()
	for i:int in range(40):
		quiet.step_mob(0.16)
		halt_waves(quiet)
	check(quiet.probe_casts==5 and quiet.probe_left==0,"full alert produces exactly five independent shots, then stops")
	check(quiet.form==0 and quiet.signals_received==0,"firing without returned hits never summons a Warden")
	quiet.alert_level=100; quiet.begin_probe(); quiet.emit_probe(); halt_waves(quiet)
	var frozen_wave:Node2D=latest(quiet,"probe")
	var frozen_position:Vector2=frozen_wave.global_position
	var frozen_probe:float=quiet.probe_left
	game.now_stop_state=true
	quiet.tick_physics(0,2); frozen_wave.advance(2)
	check(quiet.probe_left==frozen_probe and frozen_wave.global_position==frozen_position,"pause freezes both probe timer and flying sound particles")
	game.now_stop_state=false
	quiet.health=0; quiet.step_mob(0.01)
	check(quiet.waves.is_empty(),"death cancels outstanding probe and return-signal objects")
	quiet.queue_free()
	check(w.WARDEN.get_animation_names().size()==7,"all native Warden model animations remain available")
	print("WARDEN SOUND CONTRACTS: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
