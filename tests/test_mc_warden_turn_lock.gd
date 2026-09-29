extends "res://tests/test_mc_warden_sound.gd"

func prepare(w:Node2D,o:Vector2) -> void:
	w._cancel_attacks(true)
	w.sounds.clear()
	w.heard_strength=0.0
	w.quiet_time=0.0
	w.dizziness=false
	w.form=w.Form.AWAKE
	w.global_position=o
	w.direction=Vector2.RIGHT
	w.velocity=Vector2.ZERO
	w.Repel=Vector2.ZERO
	w._attack_cooldown=0.0
	w._sonic_cooldown=0.0
	w._turn_wait=0.0
	w._bounce_hold=0.0
	w.set_player_control_peer(1)
	w.set_player_control_direction(Vector2.RIGHT)
	w.face_horizontal(Vector2.RIGHT,true)

func clear_knock(unit:Node2D) -> void:
	for child:Node in unit.get_children():
		if str(child.name).begins_with("KnockbackEffect"): child.free()
	unit.Repel=Vector2.ZERO
	unit.velocity=Vector2.ZERO
	unit.dizziness=false

func run() -> void:
	var o:Vector2=await setup_world()
	create_timer(70,true,false,true).timeout.connect(func():finish(2))
	var w:Node2D=actor("监守者",o)
	var enemy:Node2D=dummy(o+Vector2(40,0))
	var rear:Node2D=dummy(o+Vector2(-140,0))
	await physics_frame
	await process_frame
	world.get_node("MCBattleNoise").set_physics_process(false)
	w.form=w.Form.AWAKE
	w._form_stats(true)
	w.update_form_collider(true)
	await physics_frame
	prepare(w,o)
	w.hear_noise(enemy,enemy.global_position,"attack",120)
	check(w.begin_melee() and w.is_direction_change_locked(),"melee locks turns as soon as its windup starts")
	var heading:Vector2=w._melee_heading
	var hp:float=enemy.health
	var heard:Vector2=w.listen_heading
	var records:int=w.sounds.size()
	w.direction=Vector2.LEFT
	w.direction.x=-1.0
	w.set_player_control_direction(Vector2.LEFT)
	w.set_character_visual_flip_h(false)
	w.face_horizontal(Vector2.LEFT,true)
	w.visual_mob()
	check(w.direction==Vector2.RIGHT and w.player_control_direction==Vector2.RIGHT and w.is_character_visual_flipped_h() and w._face_right,"movement, component writes, player turns and both visual-facing paths reject melee turns")
	w.hear_noise(rear,rear.global_position,"attack",400)
	check(w.sounds.size()==records and w.listen_heading==heard and w.rage_left>0.0,"attack-time noise has hearing/rage feedback but cannot queue a future steering position")
	w.step_mob(0.19)
	check(enemy.health==hp and w._melee_pending,"melee damage is not moved earlier than its normal windup")
	w.step_mob(0.02)
	check(hp-enemy.health==96.0 and rear.health==10000 and w._melee_heading==heading,"melee hits the original direction for unchanged damage at its normal impact time")
	clear_knock(enemy)
	check(w.is_direction_change_locked() and w.melee_visual_left>0.0,"melee turn immunity continues through recovery")
	w._attack_cooldown=0.0
	check(not w.begin_melee() and not w.begin_sonic(),"another attack cannot turn the body by replacing unfinished melee recovery")
	w.direction=Vector2.LEFT
	w.set_player_control_direction(Vector2.LEFT)
	hp=enemy.health
	w.step_mob(0.20)
	w.visual_mob()
	check(not w.is_direction_change_locked() and enemy.health==hp,"recovery ends without deferred damage")
	check(w.direction==Vector2.RIGHT and w.player_control_direction==Vector2.RIGHT and w.is_character_visual_flipped_h(),"recovery never replays discarded direction or visual requests")
	w.set_player_control_peer(0)
	w._attack_cooldown=5.0
	w.step_mob(0.01)
	check(w.direction.x>0.0,"ignored rear sound is not replayed as AI steering after recovery")
	w.hear_noise(rear,rear.global_position,"attack",400)
	w._turn_wait=0.0
	w.step_mob(0.01)
	check(w.direction.x<0.0,"new sound after recovery can steer normally")
	prepare(w,o)
	enemy.global_position=o+Vector2(170,0)
	w.hear_noise(enemy,enemy.global_position,"attack",120)
	check(w.begin_sonic() and w.is_direction_change_locked(),"sonic windup also locks turns immediately")
	heading=w._sonic_heading
	w.direction=Vector2.LEFT
	w.set_player_control_direction(Vector2.LEFT)
	w.face_horizontal(Vector2.LEFT,true)
	w.step_mob(0.3)
	check(w._sonic_pending and w._sonic_heading==heading and w.direction==Vector2.RIGHT and w.is_character_visual_flipped_h(),"sonic windup preserves movement and cast facing")
	var left:float=w.sonic_left
	game.now_stop_state=true
	w.step_mob(3.0)
	check(w.sonic_left==left and w.is_direction_change_locked(),"pause freezes the sonic clock without releasing turn immunity")
	game.now_stop_state=false
	w.dizziness=true
	w.step_mob(w.sonic_windup)
	halt_waves(w)
	var wave:Node2D=latest(w,"sonic")
	check(wave!=null and wave.heading==heading and w.sonic_recover>0.0 and w.is_direction_change_locked(),"stun still cannot interrupt the committed sonic and its recovery stays direction-locked")
	hp=enemy.health
	wave.advance(0.25)
	check(hp-enemy.health==144.0,"real swept sonic damage remains 144")
	clear_knock(enemy)
	w.direction=Vector2.LEFT
	w.face_horizontal(Vector2.LEFT,true)
	w.step_mob(0.51)
	w.visual_mob()
	check(not w.is_direction_change_locked() and w.direction==Vector2.RIGHT and w.is_character_visual_flipped_h(),"sonic recovery ends without applying discarded turns")
	check(wave.heading==heading,"body unlocking cannot redirect an already emitted sonic wave")
	w.dizziness=false
	w.direction=Vector2.LEFT
	w.set_player_control_direction(Vector2.LEFT)
	check(w.direction==Vector2.LEFT and w.player_control_direction==Vector2.LEFT,"fresh directions work after sonic recovery")
	# True wall contacts: still block the body, but never enqueue bounce direction/hold.
	for kind:String in ["melee","sonic"]:
		prepare(w,o)
		enemy.global_position=o+Vector2(40 if kind=="melee" else 170,0)
		w.hear_noise(enemy,enemy.global_position,"attack",120)
		check(w.begin_melee() if kind=="melee" else w.begin_sonic(),kind+" collision fixture starts")
		var barrier:StaticBody2D=wall(o+Vector2(15,0),Vector2(2,100))
		await physics_frame
		await process_frame
		var collision:KinematicCollision2D=w.move_and_collide(Vector2(8,0))
		check(collision!=null and w.global_position.x-o.x<3.0,kind+" keeps actual wall blocking")
		if collision!=null: w.when_collide(w.Speed,collision)
		check(w.direction==Vector2.RIGHT and w._bounce_hold==0.0,kind+" discards both collision reflection and delayed bounce hold")
		barrier.free()
		w._cancel_attacks(true)
		w.visual_mob()
		check(w.direction==Vector2.RIGHT and w.is_character_visual_flipped_h(),kind+" cancellation cannot replay the discarded collision turn")
	prepare(w,o)
	enemy.global_position=o+Vector2(40,0)
	w.hear_noise(enemy,enemy.global_position,"attack",120)
	w.begin_melee()
	w.set_player_control_direction(Vector2.ZERO)
	check(w.player_control_direction==Vector2.ZERO,"releasing movement still stops a player during attack")
	w.set_player_control_direction(Vector2.LEFT)
	w.dizziness=true
	w.step_mob(0.01)
	check(not w.is_direction_change_locked() and w.direction==Vector2.RIGHT and w.player_control_direction==Vector2.ZERO,"interrupted melee drops turns rather than applying them on cancellation")
	prepare(w,o)
	enemy.global_position=o+Vector2(170,0)
	w.hear_noise(enemy,enemy.global_position,"attack",120)
	w.begin_sonic()
	var state:Dictionary=w.network_visual_state()
	check(state.turn_lock and state.attack_flip,"existing visual snapshot carries authoritative turn lock and facing")
	var mirror:Node2D=actor("监守者",o+Vector2(0,230))
	mirror.set_multiplayer_authority(2)
	state.direction=Vector2.LEFT
	state.attack_flip=false
	state.face_right=false
	mirror.accept_visual(state)
	mirror.direction=Vector2.RIGHT
	mirror.face_horizontal(Vector2.RIGHT,true)
	check(mirror.direction==Vector2.LEFT and not mirror.is_character_visual_flipped_h(),"replica accepts the authority pose and ignores local position-derived flips")
	mirror.client_visual_step(5.0)
	check(mirror.is_direction_change_locked(),"replica cannot unlock early just because extrapolated animation timers reach zero")
	state.direction=Vector2.RIGHT
	state.attack_flip=true
	state.face_right=true
	mirror.accept_visual(state)
	check(mirror.direction==Vector2.RIGHT and mirror.is_character_visual_flipped_h(),"a new authority snapshot can update the pose despite a previous local turn lock")
	state.turn_lock=false
	state.sonic=0.0
	state.recover=0.0
	state.melee=0.0
	mirror.accept_visual(state)
	mirror.direction=Vector2.LEFT
	check(not mirror.is_direction_change_locked() and mirror.direction==Vector2.LEFT,"authoritative recovery completion unlocks replicas")
	w.health=0
	w.step_mob(0.01)
	check(not w.is_direction_change_locked() and w.waves.is_empty(),"death clears turn immunity and all pending sonic attacks")
	enemy.direction=Vector2.LEFT
	check(enemy.direction==Vector2.LEFT,"other characters retain normal direction behavior")
	print("WARDEN_TURN_LOCK checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
