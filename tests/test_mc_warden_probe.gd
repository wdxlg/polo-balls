extends "res://tests/test_mc_warden_sound.gd"
func run() -> void:
	var o:Vector2=await setup_world()
	create_timer(60).timeout.connect(func(): finish(2))
	var w:Node2D=actor("监守者",o)
	var enemy:Node2D=dummy(o+Vector2(120,0))
	await physics_frame
	await process_frame
	world.get_node("MCBattleNoise").set_physics_process(false)
	w.alert_level=100; w.begin_probe()
	check(is_equal_approx(w.attack_damage(0.35),33.6),"shrieker probe damage remains unchanged after awakened damage nerf")
	w._cancel_attacks(true)
	check(w.form==0 and w.Speed==54 and w.shrieker_speed==54,"shrieker starts with slow nonzero movement speed")
	w.set_player_control_peer(0)
	w.direction=Vector2.RIGHT
	var from:Vector2=w.global_position
	w.move(w.Speed,0.016)
	check(w.global_position.distance_to(from)>0.01 and is_equal_approx(w.velocity.length(),54*0.6),"initial form moves its actual body using ordinary movement logic")
	w._form_stats(true)
	check(w.Speed==66,"awake base speed is reduced to 66")
	w.form=w.Form.AWAKE
	w.rage_left=2.8
	w.direction=Vector2.RIGHT
	w.move(w.Speed,0.016)
	check(is_equal_approx(w.rage_speed_multiplier,1.6) and is_equal_approx(w.Speed*w.rage_speed_multiplier,105.6),"rage speed is reduced to 105.6 before shared movement scaling")
	check(is_equal_approx(w.velocity.length(),105.6*0.6),"actual rage movement uses the reduced speed through the common pipeline")
	w.rage_left=0.0
	w.form=w.Form.DORMANT
	w._form_stats(false)
	check(w.Speed==54,"returning to shrieker restores slow movement, not immobility")
	w.global_position=o
	w.set_player_control_peer(1)
	w.alert_level=100
	w.begin_probe()
	w.listen_heading=Vector2.RIGHT
	var before:int=w.waves.size()
	check(w.emit_probe(),"one probe shot can launch")
	halt_waves(w)
	check(w.waves.size()==before+1,"each firing event creates exactly one outward projectile")
	var wave:Node2D=latest(w,"probe")
	check(wave.speed==320 and wave.probe_final_speed==100,"probe starts at 320 and ends at 100")
	check(is_equal_approx(wave.probe_diameter(),15),"projectile starts small")
	var hp:float=enemy.health
	wave.advance(0.1)
	check(wave.distance>30 and wave.distance<32 and wave.speed<320 and wave.speed>100 and enemy.health==hp,"decelerating bullet travels about 31 units per tenth second, not an instant beam")
	var small:float=wave.probe_diameter()
	var early_speed:float=wave.speed
	wave.advance(0.2)
	check(wave.speed<early_speed and wave.probe_diameter()>small,"bullet steadily grows with flight distance")
	check(is_instance_valid(wave._ground_shadow) and wave._ground_shadow.z_index<wave.z_index,"pseudo-3D bullet has a lower-layer ground shadow")
	check(wave._ground_shadow.scale.x>wave._ground_shadow.scale.y,"ground shadow is flattened by perspective")
	wave.advance(0.3)
	halt_waves(w)
	check(enemy.health<hp and latest(w,"return")!=null,"slow growing projectile still causes damage and a return signal")
	var echo:Node2D=latest(w,"return")
	echo.advance(0.4)
	check(w.signals_received==1,"return signal still credits only after travelling back")
	check(w.emit_probe(),"another independent shot can launch while earlier projectile is still flying")
	halt_waves(w)
	check(latest(w,"probe")!=wave,"continuous fire uses separate single projectiles")
	wave.distance=wave.reach
	check(is_equal_approx(wave.probe_diameter(),57),"bullet grows to final diameter 57 without unbounded scaling")
	# Shape query must use the growing width, not the old fixed 8-unit strip.
	var source:String=wave.get_script().source_code
	check(source.contains('else probe_diameter()*0.5'),"swept collision width grows together with the visible projectile")
	check(source.contains('if kind=="probe":\n\t\t_draw_probe()\n\t\treturn'),"probe draws one rimmed body rather than the sonic beam's spaced ring train")
	w._cancel_attacks(true)
	w.alert_level=100; w.begin_probe(); w.emit_probe(); halt_waves(w)
	wave=latest(w,"probe")
	wave.heading=Vector2.LEFT
	wave.advance(1.55)
	check(not wave.is_queued_for_deletion() and wave.distance>280,"slow projectile lives long enough to reach its full range")
	wave.advance(0.1)
	check(wave.is_queued_for_deletion(),"projectile despawns at maximum range")
	w._cancel_attacks(true); w.sounds.clear()
	w.global_position=o; w.direction=Vector2.RIGHT
	var sound_point:Vector2=o+Vector2(0,-100)
	check(w.hear_noise(enemy,sound_point,"attack",120),"shrieker hears a sound perpendicular to its travel")
	check(w.direction==Vector2.RIGHT and w.listen_heading.dot(Vector2.UP)>0.99,"sound changes attack aim, not movement direction")
	w.step_mob(0.05)
	check(w.direction==Vector2.RIGHT,"normal update does not steer shrieker toward recorded sound")
	w.global_position=o+Vector2(40,0)
	enemy.global_position=o+Vector2(200,120)
	w.alert_level=100; w.begin_probe(); w.emit_probe(); halt_waves(w)
	wave=latest(w,"probe")
	check(wave.heading.dot(w.global_position.direction_to(sound_point))>0.999,"shot aims from moved shrieker to the sound's recorded world position")
	check(wave.heading.dot(w.global_position.direction_to(enemy.global_position))<0.5,"shot does not track an enemy that silently moved elsewhere")
	w.direction=Vector2.LEFT; w._bounce_hold=0.35
	w.hear_noise(enemy,o+Vector2(0,100),"collision",64)
	check(w.direction==Vector2.LEFT,"new sound preserves the normal bounced movement direction")
	w._cancel_attacks(true); w.sounds.clear(); w.alert_level=100; w.begin_probe()
	w.listen_heading=Vector2.LEFT; w.emit_probe(); halt_waves(w)
	var a:Node2D=latest(w,"probe")
	w.emit_probe(); halt_waves(w)
	var b:Node2D=latest(w,"probe")
	a.advance(0.2); b.advance(0.1); b.advance(0.1)
	check(is_equal_approx(a.distance,b.distance) and is_equal_approx(a.speed,b.speed),"decelerating travel is independent of frame subdivision")
	a.advance(1.5)
	check(a.is_queued_for_deletion() and is_equal_approx(a.distance,300) and is_equal_approx(a.speed,100),"probe reaches full range with final speed 100 instead of stopping early")
	w._cancel_attacks(true); w.form=w.Form.AWAKE; w._form_stats(true)
	w.global_position=o; w.direction=Vector2.RIGHT; w._attack_cooldown=0
	w.sounds.clear(); w.hear_noise(enemy,o+Vector2(40,0),"attack",120)
	check(w.melee_range==50 and w.begin_melee(),"reduced melee starts only from nearby sound")
	var region:Dictionary=w.get_debug_attack_regions()[0]
	check(is_equal_approx(region.radius,25) and region.position==o+Vector2(25,0),"melee threat preview shrinks together with reach")
	enemy.global_position=o+Vector2(51+w.U.radius(enemy),0)
	var far_hp:float=enemy.health
	w.release_melee()
	check(enemy.health==far_hp,"target beyond new reach plus hurtbox radius is not hit")
	w._attack_cooldown=0; w.melee_left=0; enemy.global_position=o+Vector2(40,0)
	w.begin_melee(); far_hp=enemy.health; w.release_melee()
	check(is_equal_approx(far_hp-enemy.health,96),"close melee still lands for unchanged 96 damage")
	print("WARDEN PROBE CONTRACTS: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
