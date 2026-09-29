extends "res://tests/test_mc_new6_load.gd"

func make_arrow(point:Vector2,dir:Vector2,speed:float,ballistic:bool=true,gravity:float=700.0) -> Node2D:
	# Load after SceneTree autoload initialization (the arrow references Game).
	var arrow:Node2D = load("res://scenes/shooter/我的世界/骷髅箭.tscn").instantiate()
	world.add_child(arrow,true)
	arrow.global_position = point
	arrow.configure_plain(null,"Team0",dir,speed,10.0,0.0,220.0,0.25)
	if ballistic:
		arrow.configure_ballistics(gravity,0.05,780.0)
		arrow._new6_max_dist = 240.0
	arrow.set_physics_process(false)
	return arrow

func _bow_arrows(bow:Node2D) -> Array[Node]:
	var out:Array[Node]=[]
	for candidate:Node in get_nodes_in_group("MinecraftSkeletonArrow"):
		if not candidate.is_queued_for_deletion() and candidate._source_ball()==bow: out.append(candidate)
	return out

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(90.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var point:Vector2 = center

	var low:Node2D = make_arrow(point,Vector2.RIGHT,280.0)
	low._physics_process(0.1)
	check(low.global_position.distance_to(point+Vector2(28,3.5))<0.02,"gravity follows x=v*t, y=0.5*g*t*t")
	check(is_equal_approx(low._direction.y*low._speed,70.0),"gravity changes vertical velocity by g*t")
	check(is_equal_approx(low.rotation,low._direction.angle()),"arrow rotates along instantaneous velocity")
	check(get_nodes_in_group("BowArrowAfterimage").is_empty(),"slow arrows have no afterimages")
	low.queue_free()

	var fast:Node2D = make_arrow(point,Vector2.RIGHT,1000.0)
	fast._physics_process(0.1)
	check(get_nodes_in_group("BowArrowAfterimage").size()>=3,"fast arrows leave multiple texture afterimages")
	check(is_equal_approx(fast._direct_damage,fast._speed*0.05),"flight damage tracks actual speed")
	var ghosts:int = get_nodes_in_group("BowArrowAfterimage").size()
	fast._direction = Vector2.RIGHT
	fast._speed = 280.0
	fast._physics_process(0.05)
	check(get_nodes_in_group("BowArrowAfterimage").size()==ghosts,"falling below threshold stops new afterimages")
	fast.queue_free()
	await create_timer(0.25).timeout
	check(get_nodes_in_group("BowArrowAfterimage").is_empty(),"afterimages fade and clean up after their arrow dies")

	var rising:Node2D = make_arrow(point,Vector2.UP,500.0)
	rising._physics_process(0.2)
	check(absf(rising._speed-360.0)<0.02,"upward arrow slows under gravity (speed=%s, mode=%s)" % [rising._speed,rising._mode])
	check(absf(rising._direct_damage-18.0)<0.02,"slowing while rising reduces damage")
	rising.queue_free()
	var falling:Node2D = make_arrow(point,Vector2.DOWN,500.0)
	falling._physics_process(0.2)
	check(absf(falling._speed-640.0)<0.02,"downward arrow accelerates under gravity")
	check(absf(falling._direct_damage-32.0)<0.02,"falling acceleration increases damage")
	falling.queue_free()
	var apex:Node2D = make_arrow(point,Vector2.UP,35.0)
	apex._physics_process(0.1)
	check(apex._direction.y>0.99 and absf(apex._speed-35.0)<0.02,"vertical arrow passes apex and falls instead of freezing")
	apex.queue_free()

	var whole:Node2D = make_arrow(point,Vector2.RIGHT,800.0)
	var split:Node2D = make_arrow(point,Vector2.RIGHT,800.0)
	whole._physics_process(0.2)
	for i:int in range(20): split._physics_process(0.01)
	check(whole.global_position.distance_to(split.global_position)<0.03,"trajectory is stable across timestep sizes")
	check(absf(whole._speed-split._speed)<0.03,"speed is stable across timestep sizes")
	whole.queue_free()
	split.queue_free()
	var ranged:Node2D = make_arrow(point,Vector2.RIGHT,1000.0)
	ranged._physics_process(0.5)
	check(ranged.is_queued_for_deletion(),"ballistic arrow expires at shortened range")
	check(absf(ranged._new6_travelled-240.0)<0.03,"range counts curved path without overshooting")
	check(ranged.global_position.distance_to(point)<=240.01,"range cannot exceed cap even with a large timestep")

	var plain:Node2D = make_arrow(point,Vector2.RIGHT,520.0,false)
	plain._physics_process(0.1)
	check(plain.global_position.distance_to(point+Vector2(52,0))<0.02,"ordinary arrows still fly straight")
	check(is_equal_approx(plain._direct_damage,10.0) and not plain._ballistic_enabled,"ordinary arrows retain fixed damage without opting in")
	plain.configure(null,"Team0",Vector2.RIGHT,520.0,8.0,3.0,0.0,90.0,5.5)
	check(not plain._plain_arrow_mode and not plain._ballistic_enabled,"skeleton wound-arrow mode remains unchanged")
	plain.queue_free()
	await physics_frame
	await process_frame

	var wall:StaticBody2D = _mk_wall(point+Vector2(25,0))
	await physics_frame
	var edge:Node2D = make_arrow(point,Vector2.RIGHT,1000.0,true,0.0)
	edge._new6_max_dist = 12.0
	edge._physics_process(0.05)
	check(edge._mode==edge.ArrowMode.STUCK_TERRAIN,"last in-range segment can still strike terrain")
	check(not get_nodes_in_group("MCArrowTerrainSFX").is_empty(),"source-less arrow retains skeleton terrain-hit sound fallback")
	check(absf(edge.global_position.x-point.x-10.0)<0.1,"high-speed sweep stops at the wall surface")
	ghosts = get_nodes_in_group("BowArrowAfterimage").size()
	edge._physics_process(0.1)
	check(get_nodes_in_group("BowArrowAfterimage").size()==ghosts,"stuck arrows stop emitting afterimages")
	edge.queue_free()
	wall.queue_free()
	await physics_frame
	await process_frame
	wall = _mk_wall(point+Vector2(40,0))
	await physics_frame
	var beyond:Node2D = make_arrow(point,Vector2.RIGHT,1000.0,true,0.0)
	beyond._new6_max_dist = 12.0
	beyond._physics_process(0.05)
	check(beyond.is_queued_for_deletion() and beyond._mode==beyond.ArrowMode.FLYING,"out-of-range wall cannot be hit by the final sweep")
	wall.queue_free()
	await physics_frame
	await process_frame

	var enemy:Node2D = _mk_enemy(point+Vector2(0,100))
	await physics_frame
	var slow_hit:Node2D = make_arrow(point,Vector2.DOWN,280.0)
	var hp:float = enemy.health
	slow_hit._physics_process(0.3)
	var low_damage:float = hp-enemy.health
	check(low_damage>0.0 and slow_hit.is_queued_for_deletion(),"slow ballistic arrow hits a real enemy (damage=%s, pos=%s)" % [low_damage,slow_hit.global_position-point])
	check(absf(low_damage-slow_hit._direct_damage)<1.1,"actual hit uses impact-speed damage")
	var fast_hit:Node2D = make_arrow(point,Vector2.DOWN,1000.0)
	hp = enemy.health
	fast_hit._physics_process(0.2)
	check(hp-enemy.health>low_damage and fast_hit.is_queued_for_deletion(),"faster impact removes more health on the same enemy")
	enemy.queue_free()
	await process_frame

	var bow:Node2D = spawn("res://scenes/characters/我的世界/弓.tscn",center)
	bow.Can_Attack = true
	bow.state_machine.set_physics_process(false)
	enemy = _mk_enemy(center+Vector2(400,0))
	await physics_frame
	check(bow.Max_health==450 and bow.health==450,"bow starts with 450 health")
	check(bow.shoot_range==200.0 and bow.arrow_max_dist==240.0,"bow uses reduced acquisition and projectile ranges")
	bow.step_mob(0.1)
	check(is_zero_approx(bow.drawing),"bow does not start drawing at distant targets")
	enemy.global_position = center+Vector2(150,0)
	await physics_frame
	bow.step_mob(0.1)
	check(bow.drawing>0.0,"bow still draws at targets inside the reduced range")
	check(is_instance_valid(bow._draw_player) and bow._draw_player.playing,"drawing starts the official Minecraft loading sound")
	check(bow._draw_player.get_meta("mc_sound_event","")=="item.crossbow.loading_start","draw start uses vanilla crossbow loading_start event")
	var first_draw:AudioStreamPlayer2D = bow._draw_player
	bow.step_mob(0.1)
	check(bow._draw_player==first_draw,"draw sound does not restart every physics tick")
	bow.step_mob(0.7)
	check(bow._draw_player!=first_draw and not first_draw.playing,"half charge stops first clip before the next one")
	check(bow._draw_player.get_meta("mc_sound_event","")=="item.crossbow.loading_middle","half charge plays vanilla loading_middle")
	var second_draw:AudioStreamPlayer2D = bow._draw_player
	bow.global_position += Vector2(3,0)
	bow._process(0.0)
	check(second_draw.global_position.is_equal_approx(bow.global_position),"draw audio follows the moving bow")
	bow.Can_Attack = false
	bow.step_mob(0.01)
	check(bow._draw_audio_stage==0 and bow._draw_player==null and not second_draw.playing,"cancelling draw stops its sound")
	bow.global_position = center
	bow.Can_Attack = true
	bow.drawing = 0.0
	bow.step_mob(0.1)
	var released_draw:AudioStreamPlayer2D = bow._draw_player
	bow._fire(0.1,false)
	check(bow._draw_player==null and not released_draw.playing,"early release stops draw audio")
	for candidate:Node in get_nodes_in_group("MinecraftSkeletonArrow"):
		if candidate._source_ball()==bow: candidate.queue_free()
	# Muzzle regression: must follow the rendered bow, not an unscaled world offset.
	var graphics:Node2D = bow.get_node("Graphics")
	for factor:float in [0.2,0.4]:
		bow.scale = Vector2.ONE * factor
		graphics.position = Vector2(7,-3)
		graphics.scale = Vector2.ONE * 0.8
		for aim:Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(1,1).normalized()]:
			bow.facing = aim
			# Deliberately stale visual direction to exercise the pre-spawn refresh.
			bow.image.rotation = 0.0
			bow._fire(1.0,true)
			var born:Node2D = null
			for candidate:Node in get_nodes_in_group("MinecraftSkeletonArrow"):
				if not candidate.is_queued_for_deletion() and candidate._source_ball()==bow:
					born = candidate
			var expected:Vector2 = graphics.to_global(aim*58.0)
			check(born!=null and born.global_position.distance_to(expected)<0.01,"muzzle follows visual transform scale=%s aim=%s" % [factor,aim])
			if born!=null: born.queue_free()
	bow.scale = Vector2.ONE * 0.2
	graphics.position = Vector2.ZERO
	graphics.scale = Vector2.ONE
	bow.facing = Vector2.RIGHT
	bow.visual_mob()
	check(absf(bow.arrow_muzzle_world_position().distance_to(bow.global_position)-11.6)<0.01,"default muzzle is 11.6 world pixels ahead, not 58")

	# --- final hold: the drawn bow trembles harder the longer it is held ---
	bow.drawing = 0.0
	bow._recoil_power = 0.0
	bow.clock = 1.92
	bow._view_clock = 1.92
	bow.visual_mob()
	var rest:Vector2 = bow.image.position
	var rest_angle:float = bow.image.rotation
	check(is_equal_approx(bow.total_draw_time(),bow.draw_time+bow.full_hold_time) and bow.full_hold_time>0.0,"full draw is followed by a final hold")
	bow.drawing = bow.draw_time
	bow.visual_mob()
	check(bow.image.texture==bow.TEX_PULL2 and is_zero_approx(bow.hold_ratio()),"reaching full draw starts the final hold at zero")
	check(bow.image.position.is_equal_approx(rest) and is_equal_approx(bow.image.rotation,rest_angle),"bow is still steady the instant it reaches full draw")
	bow.drawing = bow.draw_time+bow.full_hold_time*0.5
	bow.visual_mob()
	var half_shake:float = bow.image.position.distance_to(rest)
	var half_tilt:float = absf(angle_difference(rest_angle,bow.image.rotation))
	check(half_shake>0.01 and half_tilt>0.001,"final hold trembles the bow (shift=%s tilt=%s)" % [half_shake,half_tilt])
	check(bow.image.texture==bow.TEX_PULL2,"final hold keeps the fully drawn frame")
	bow.drawing = bow.draw_time+bow.full_hold_time
	bow.visual_mob()
	var full_shake:float = bow.image.position.distance_to(rest)
	var full_tilt:float = absf(angle_difference(rest_angle,bow.image.rotation))
	check(full_shake>half_shake*1.5 and full_tilt>half_tilt*1.5,"tremble grows with the final hold (%s -> %s)" % [half_shake,full_shake])
	check(full_shake<=bow.tremble_shift*1.2 and full_tilt<=bow.tremble_tilt*1.2,"tremble stays within its configured amplitude")
	bow.drawing = 0.0
	bow.visual_mob()
	check(bow.image.position.is_equal_approx(rest) and is_equal_approx(bow.image.rotation,rest_angle),"releasing the string removes the tremble")

	# --- the final hold delays the automatic release ---
	bow._cool = 0.0
	var before:int = _bow_arrows(bow).size()
	bow.step_mob(bow.draw_time+0.01)
	check(bow.drawing>bow.draw_time and _bow_arrows(bow).size()==before,"full draw enters the final hold instead of firing at once")
	bow.step_mob(bow.full_hold_time*0.5)
	check(_bow_arrows(bow).size()==before,"bow keeps holding halfway through the final hold")
	bow.step_mob(bow.full_hold_time*0.5+0.01)
	check(_bow_arrows(bow).size()==before+1 and is_zero_approx(bow.drawing),"final hold ends with the automatic full-power release")
	check(_heard("entity.player.attack.crit"),"release after the final hold counts as a full shot")
	check(bow.image.position.is_equal_approx(rest),"the arrow leaves before the recoil moves the bow")

	# --- release recoil: kick straight back against the aim, then spring back ---
	bow._view_clock = bow.clock+0.032
	bow.visual_mob()
	var kick:Vector2 = bow.image.position-rest
	check(kick.length()>bow.recoil_shift*0.9 and kick.normalized().dot(-bow.facing)>0.99,"full-hold release kicks the bow straight back (%s)" % kick)
	check(absf(angle_difference(rest_angle,bow.image.rotation))>bow.recoil_tilt*0.9,"recoil also tilts the bow")
	bow._view_clock = bow.clock+0.115
	bow.visual_mob()
	var rebound:Vector2 = bow.image.position-rest
	check(rebound.dot(bow.facing)>0.0 and rebound.length()<kick.length()*0.5,"the spring overshoots forward with less energy")
	bow._view_clock = bow.clock+bow.RECOIL_LIFETIME+0.01
	bow.visual_mob()
	check(bow.image.position.is_equal_approx(rest) and is_equal_approx(bow.image.rotation,rest_angle),"recoil settles back to the rest pose")
	bow._cool = 0.0
	bow.drawing = 0.3
	bow.clock = 5.0
	bow._view_clock = 5.0
	bow._fire(bow.charge_ratio(),false)
	bow._view_clock = 5.032
	bow.visual_mob()
	var weak:Vector2 = bow.image.position-rest
	check(weak.length()>0.5 and weak.length()<kick.length()*0.6,"a quick release kicks back much less than a full hold (%s vs %s)" % [weak.length(),kick.length()])
	check(weak.normalized().dot(-bow.facing)>0.99,"weak recoil still points against the aim")
	var sync:Dictionary = bow.visual_state()
	check(int(sync.get("shot",0))==bow._shot_seq and sync.get("shot",0)>=2 and is_equal_approx(float(sync.get("kick",0.0)),bow._recoil_power),"visual sync carries the shot counter and recoil strength")
	for candidate:Node in _bow_arrows(bow): candidate.queue_free()
	bow._view_clock = 6.0
	bow.visual_mob()
	enemy.queue_free()
	await process_frame
	wall = _mk_wall(center+Vector2(70,0))
	await physics_frame
	bow._fire(1.0,false)
	var impact_arrow:Node2D = null
	for candidate:Node in get_nodes_in_group("MinecraftSkeletonArrow"):
		if not candidate.is_queued_for_deletion() and candidate._source_ball()==bow: impact_arrow=candidate
	impact_arrow.set_physics_process(false)
	var hit_before:int = 0
	for sound:Node in get_nodes_in_group("MCNativeSFX"):
		if sound.get_meta("mc_sound_event","")=="entity.arrow.hit": hit_before+=1
	impact_arrow._physics_process(0.1)
	var hits:Array[Node] = []
	for sound:Node in get_nodes_in_group("MCNativeSFX"):
		if sound.get_meta("mc_sound_event","")=="entity.arrow.hit": hits.append(sound)
	check(impact_arrow._mode==impact_arrow.ArrowMode.STUCK_TERRAIN and hits.size()==hit_before+1,"bow arrow emits exactly one terrain impact audio event")
	if not hits.is_empty():
		var impact_sound:AudioStreamPlayer2D = hits.back() as AudioStreamPlayer2D
		check(impact_arrow.TERRAIN_HIT_SFX.has(impact_sound.stream),"bow impact uses the exact skeleton arrow sound pool")
		check(impact_sound.global_position.distance_to(impact_arrow.global_position)<0.01,"impact sound plays at the obstacle contact point")
	impact_arrow._physics_process(0.1)
	var after_hits:int = 0
	for sound:Node in get_nodes_in_group("MCNativeSFX"):
		if sound.get_meta("mc_sound_event","")=="entity.arrow.hit": after_hits+=1
	check(after_hits==hits.size(),"stuck arrow does not repeat impact sound")
	impact_arrow.queue_free()
	wall.queue_free()
	bow._set_draw_audio_stage(1)
	var death_draw:AudioStreamPlayer2D = bow._draw_player
	bow.Die()
	check(bow._draw_player==null and not death_draw.playing,"death stops draw audio")
	bow.queue_free()
	await process_frame
	finish(0 if failures==0 else 1)
