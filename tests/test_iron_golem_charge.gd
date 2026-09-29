extends "res://tests/test_iron_golem_pair.gd"
func reset_attack(g:Node2D) -> void:
	g.cancel_swing()
	g._attack_wait = 0.0
	g.global_position = Vector2.ZERO
	g.direction = Vector2.ZERO
	g.velocity = Vector2.ZERO
	g.image.rotation = 0.0
	g.get_node("Graphics").rotation = 0.0
	g.set_character_visual_flip_h(true)
func control_for(target:Node2D) -> Node:
	for child:Node in target.get_children():
		if str(child.name).begins_with("KnockbackEffect"): return child
	return null
func run() -> void:
	create_timer(55.0).timeout.connect(func(): push_error("GOLEM_CHARGE_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	game.now_stop_state = false
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	AudioServer.set_bus_mute(0,true)
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	var g:Node2D = golem(Vector2.ZERO)
	g.companion.global_position = Vector2(500,300)
	var target:Node2D = enemy(Vector2(30,0))
	var rear:Node2D = enemy(Vector2(-30,0))
	var side:Node2D = enemy(Vector2(0,30))
	var far:Node2D = enemy(Vector2(75,0))
	var ally:Node2D = enemy(Vector2(30,5),"Team0")
	await physics_frame
	await process_frame
	reset_attack(g)
	check(g.current_attack_heading().is_equal_approx(Vector2.RIGHT),"live shader-facing reports right")
	check(not g.begin_swing(rear),"cannot initiate an attack at an enemy behind")
	check(g.begin_swing(target),"front enemy starts charge")
	g.set_character_visual_flip_h(false)
	g.release_swing()
	var before:int = target.health
	g.step_attack(0.10)
	check(target.health<before and g.is_character_visual_flipped_h(),"turn during charge is ignored and impact keeps its original front")
	check(rear.health==10000,"ignored turn cannot redirect the swing into enemies behind")
	check(side.health==10000 and ally.health==10000,"side plane and allies excluded")
	clear_control(target)
	reset_attack(g)
	check(g.begin_swing(target),"second front windup starts")
	g.release_swing()
	g.set_character_visual_flip_h(false)
	before = target.health
	g.step_attack(0.10)
	check(target.health<before and g.is_character_visual_flipped_h(),"turn during upswing is ignored through the impact frame")
	clear_control(target)
	reset_attack(g)
	g.image.rotation = PI/2.0
	check(g.current_attack_heading().is_equal_approx(Vector2.DOWN),"Image rotation included in live heading")
	before = target.health
	var rear_before:int = rear.health
	g.resolve_upswing()
	check(rear.health==rear_before,"perpendicular enemy remains excluded despite rotation rounding")
	check(target.health==before and side.health<10000,"rotated visual hits new front not old right")
	clear_control(side)
	reset_attack(g)
	g.get_node("Graphics").rotation = PI
	check(g.current_attack_heading().is_equal_approx(Vector2.LEFT),"Graphics rotation included in heading")
	reset_attack(g)
	g.rotation = PI/2.0
	check(g.current_attack_heading().is_equal_approx(Vector2.DOWN),"root rotation included in heading")
	g.rotation = 0.0
	reset_attack(g)
	g.image.scale.x = -absf(g.image.scale.x)
	check(g.current_attack_heading().is_equal_approx(Vector2.LEFT),"negative Image scale included in heading")
	g.image.scale.x = absf(g.image.scale.x)
	reset_attack(g)
	g.begin_swing(target)
	before = target.health
	g.step_attack(0.5)
	check(g._phase==1 and target.health==before,"stationary nearby target holds charge beyond old fixed 0.38 seconds")
	g.step_attack(0.69)
	check(g._phase==1,"holds until maximum charge when no escape threat")
	g.step_attack(0.02)
	check(g._phase==2 and is_equal_approx(g._released_charge,1.0),"maximum charge automatically releases")
	g.step_attack(0.10)
	check(before-target.health==96,"full charge doubles base damage")
	var control:Node = control_for(target)
	check(control!=null and is_equal_approx(control.distance,121.0),"full charge raises launch distance to 121")
	check(control!=null and is_equal_approx(control.speed,390.0),"full charge raises launch speed to 390")
	check(control!=null and is_equal_approx(control.stun_duration,0.65),"charge keeps established stun duration")
	var damaged:int = target.health
	g.step_attack(0.2)
	g.step_attack(0.2)
	check(target.health==damaged,"enlarged arms and recovery cannot deal repeated hits")
	check(g._phase==0 and is_equal_approx(g.current_arm_scale(),1.0),"end of recovery restores normal arm size")
	clear_control(target)
	clear_control(far)
	reset_attack(g)
	target.global_position = Vector2(38,0)
	target.velocity = Vector2(80,0)
	g.begin_swing(target)
	g.step_attack(g.minimum_charge)
	check(g._phase==2 and is_zero_approx(g._released_charge),"outbound velocity predicts escape and releases at minimum charge")
	before = target.health
	g.step_attack(0.10)
	check(before-target.health==48,"minimum-charge attack keeps 48 base damage")
	control = control_for(target)
	check(control!=null and is_equal_approx(control.distance,55.0) and is_equal_approx(control.speed,260.0),"minimum charge uses baseline launch")
	clear_control(target)
	clear_control(far)
	reset_attack(g)
	target.global_position = Vector2(30,0)
	target.velocity = Vector2.ZERO
	g.begin_swing(target)
	g.step_attack(0.15)
	target.global_position = Vector2(35,0)
	g.step_attack(0.02)
	check(g._phase==2 and g._charge_elapsed<g.windup_duration,"measured relative motion predicts escape before edge")
	reset_attack(g)
	target.global_position = Vector2(38,0)
	g.begin_swing(target)
	g.step_attack(0.2)
	check(g._phase==1,"near edge but stationary inside safe margin keeps charging")
	target.global_position = Vector2(40,0)
	g.step_attack(0.02)
	check(g._phase==2,"edge crossing triggers release without waiting for full charge")
	reset_attack(g)
	target.global_position = Vector2(30,0)
	g.begin_swing(target)
	g.step_attack(0.6)
	g.release_swing()
	before = target.health
	g.step_attack(0.10)
	check(before-target.health>48 and before-target.health<96,"intermediate charge has intermediate damage")
	control = control_for(target)
	check(control!=null and control.distance>55 and control.distance<121,"intermediate charge has intermediate height")
	clear_control(target)
	clear_control(far)
	reset_attack(g)
	var far_health:int = far.health
	g.resolve_upswing()
	check(far.health==far_health,"normal hands cannot reach distant enemy")
	clear_control(target)
	g.set_pair_clip("swing")
	g.visual_clock = g.IMPACT_TIME
	check(g.current_arm_scale()>2.0,"hands rapidly enlarge before impact")
	g.resolve_upswing()
	check(far.health<far_health,"enlarged hands expand actual hit range")
	clear_control(target)
	clear_control(far)
	far_health = far.health
	g.visual_clock = g.swing_duration
	g.resolve_upswing()
	check(far.health==far_health,"retracted hands lose expanded range")
	check(g.arm_scale_at(0.0)<g.arm_scale_at(0.04) and g.arm_scale_at(0.04)<g.arm_scale_at(0.09),"arm growth curve increases rapidly")
	check(g.arm_scale_at(0.18)>g.arm_scale_at(0.3) and g.arm_scale_at(0.3)>g.arm_scale_at(0.42) and is_equal_approx(g.arm_scale_at(0.48),1.0),"recovery shrinks arms progressively back to one")
	for frames:SpriteFrames in g.GOLEM_FRAMES:
		check(frames.get_frame_count("swing")==g.SWING_FRAMES and is_equal_approx(frames.get_animation_speed("swing"),g.SWING_FRAMES/g.swing_duration),"crack variant frame cadence matches size curve")
		var tex:Texture2D = frames.get_frame_texture("swing",4)
		check(tex.get_size()==Vector2(448,384),"expanded arm canvas keeps world anchor without clipping")
	reset_attack(g)
	g.begin_swing(target)
	g.step_attack(0.3)
	var elapsed:float = g._charge_elapsed
	game.now_stop_state = true
	g.step_attack(0.5)
	check(is_equal_approx(elapsed,g._charge_elapsed),"pause cannot accumulate charge even via direct attack update")
	game.now_stop_state = false
	g.set_multiplayer_authority(2)
	before = target.health
	g.step_attack(0.5)
	g.resolve_upswing()
	check(target.health==before and is_equal_approx(elapsed,g._charge_elapsed),"remote replica cannot charge or deal damage")
	g.set_multiplayer_authority(1)
	g.dizziness = true
	g.tick_physics(g.State.Move,0.02)
	check(g._phase==0 and is_zero_approx(g._released_charge) and is_equal_approx(g.current_arm_scale(),1.0),"stun cancels charge and clears enlarged arms")
	g.dizziness = false
	reset_attack(g)
	g.enraged = true
	g._released_charge = 1.0
	before = target.health
	clear_control(target)
	g.resolve_upswing()
	check(before-target.health==144,"rage multiplies fully charged damage once")
	clear_control(target)
	reset_attack(g)
	g.enraged = false
	g.set_pair_clip("swing")
	g.visual_clock = g.IMPACT_TIME
	var barrier:StaticBody2D = wall_at(Vector2(20,0))
	await physics_frame
	await process_frame
	before = target.health
	g.resolve_upswing()
	check(target.health==before,"enlarged hands still cannot hit through walls")
	barrier.free()
	reset_attack(g)
	g.begin_swing(target)
	g.direction = Vector2.LEFT
	g.release_swing()
	g._phase_time = 0.085
	before = target.health
	g.tick_physics(g.State.Move,0.02)
	check(g.current_attack_heading().x>0 and target.health<before and g.direction==Vector2.ZERO,"real physics tick discards turn before impact instead of storing it")
	clear_control(target)
	reset_attack(g)
	rear.global_position = Vector2(-10,0)
	check(g.nearest_front_enemy()==target,"closer enemy behind does not hide eligible front target")
	var temporary:Node2D = enemy(Vector2(35,0))
	g.begin_swing(temporary)
	temporary.free()
	g.step_attack(0.2)
	check(g._phase==2,"freed charge target safely releases instead of accessing stale object")
	print("GOLEM_CHARGE_RESULT checks=",checks," failures=",failures)
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
