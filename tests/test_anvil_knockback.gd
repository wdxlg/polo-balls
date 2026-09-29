extends "res://tests/test_anvil_bounce_audio.gd"
## Uses the real public knockback controller and normal target physics, not a position mock.
func knockbacks(target:Node) -> Array[Node]:
	var effects:Array[Node] = []
	for child:Node in target.get_children():
		if child.get_script()==target.KNOCKBACK_EFFECT_SCRIPT and child.is_active_effect(): effects.append(child)
	return effects
func prepare_drop(unit:Node2D,target:Node2D,speed:float) -> void:
	unit._active_slam = false
	unit._drop_connected = false
	unit.slam_phase = unit.SlamPhase.FALLING
	unit.global_position = target.global_position+Vector2(0,-85)
	unit.fall_speed = speed
	unit._fall_hits.clear()
	unit.cooldown_left = 0.0
	unit.Can_Attack = true
	unit.Can_Skill = true
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(90.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.3).timeout
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"knockback preloads complete")
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var unit:Node2D = anvil(center+Vector2(0,-85))
	var target:Node2D = dummy(center)
	target.default_properties.Speed = 0.0
	target.Has_Collision_Damage = false
	target.set_process(true)
	target.state_machine.set_physics_process(true)
	var friend:Node2D = dummy(center+Vector2(-130,0),"Team0")
	await physics_frame
	await process_frame
	prepare_drop(unit,target,600.0)
	clear_cues()
	var before:Vector2 = target.global_position
	advance_until(unit,func(): return unit.hit_count==1,1.0)
	var effects:Array[Node] = knockbacks(target)
	check(effects.size()==1,"real anvil damage creates exactly one public knockback controller")
	if not effects.is_empty():
		var effect:Node = effects[0]
		check(effect.source==unit and effect.direction.is_equal_approx(Vector2.DOWN) and target.Repel.y>0.0,"slam pushes downward through the real physics impulse channel")
		check(is_equal_approx(effect.distance,unit.impact_knockback_distance(unit.last_impact_speed)),"knockback strength uses the confirmed pre-impact fall speed")
		check(effect.collision_damage==0.0 and effect.stun_duration==0.0 and effect.wall_bounce_strength==0.0,"push adds no hidden collision damage, extra stun or wall launch")
	check(clangs(unit).is_empty() and unit.obstacle_impact_count==0,"enemy knockback does not ring the anvil")
	check(unit.slam_phase==unit.SlamPhase.FALLING and unit.fall_speed>0.0 and unit._drop_connected,"knockback preserves the uninterrupted fall and landing-time repeat eligibility")
	var hp:float = target.health
	await create_timer(0.4).timeout
	check(target.global_position.y>before.y+10.0 and absf(target.global_position.x-before.x)<0.2,"normal engine ticks really displace the struck enemy downward")
	check(target.health==hp,"knockback movement does not duplicate slam damage")
	check(knockbacks(target).is_empty() and not target.dizziness,"knockback finishes and releases its real control lock")
	check(knockbacks(friend).is_empty(),"nearby friendly units receive no incidental knockback")
	check(unit.impact_knockback_distance(600)>unit.impact_knockback_distance(200) and unit.impact_knockback_distance(100000)<=unit.maximum_knockback_distance,"fall-speed knockback increases but has a finite cap")

	# The same impact near a platform must stop at it, not teleport through terrain.
	target.global_position = center+Vector2(120,0)
	var half_height:float = target.get_node("CollisionShape2D").shape.get_rect().size.y*target.global_scale.y*0.5
	var wall:StaticBody2D = obstacle(target.global_position+Vector2(0,half_height+8),Vector2(100,4))
	prepare_drop(unit,target,600.0)
	await physics_frame
	await process_frame
	before = target.global_position
	var old_hits:int = unit.hit_count
	advance_until(unit,func(): return unit.hit_count>old_hits,1.0)
	hp = target.health
	await create_timer(0.4).timeout
	check(absf(target.global_position.x-before.x)>5.0 and target.global_position.y+half_height<=wall.global_position.y-2.0+0.2,"blocked-downward pressure redirects sideways without crossing the real platform")
	check(target.health==hp and knockbacks(target).is_empty(),"wall stopping adds no second damage and leaves no stuck knockback controller")
	wall.queue_free()
	await process_frame

	# Fully blocked damage does not create a displacement effect.
	target.global_position = center+Vector2(120,0)
	target.Damage_reduction = 1.0
	# This fixture uses real target physics, including normal stat refreshes.
	target.default_properties.Damage_reduction = 1.0
	prepare_drop(unit,target,600.0)
	await physics_frame
	await process_frame
	before = target.global_position
	hp = target.health
	old_hits = unit.hit_count
	check(is_equal_approx(target.Damage_reduction,1.0),"immune fixture survives normal engine property refresh")
	unit.step_mob(0.18)
	await create_timer(0.12).timeout
	check(target.health==hp and unit.hit_count==old_hits,"immune contact registers no damage or successful impact")
	check(knockbacks(target).is_empty(),"immune contact creates no knockback controller")
	check(target.global_position.is_equal_approx(before),"immune target is not displaced")
	check(unit._apply_impact_knockback(friend,600.0)==null and knockbacks(friend).is_empty(),"friendly target cannot be pushed by the impact helper")
	var replica:Node2D = anvil(center+Vector2(250,-50))
	replica.set_multiplayer_authority(2)
	target.Damage_reduction = 0.0
	target.default_properties.Damage_reduction = 0.0
	check(replica._apply_impact_knockback(target,600.0)==null and knockbacks(target).is_empty(),"non-authority replica cannot originate a duplicate push")
	unit.health = 0
	check(unit._apply_impact_knockback(target,600.0)==null,"dead caster cannot apply another impact push")
	print("ANVIL_KNOCKBACK checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
