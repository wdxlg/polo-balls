extends "res://tests/test_mc_bat_transform.gd"
var effects:Script
var projectiles:Script
func unit(path:String,point:Vector2,team:String) -> Node2D:
	var node:Node2D = spawn(path,point,team)
	node.state_machine.set_physics_process(false)
	node.Has_Collision_Damage = false
	return node
func wall(point:Vector2) -> StaticBody2D:
	var node := StaticBody2D.new()
	node.collision_layer = 1
	node.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(4,100)
	shape.shape = rect
	node.add_child(shape)
	world.add_child(node)
	node.global_position = point
	return node
func run() -> void:
	var center:Vector2 = await setup_world()
	game._settings_storage_path = "user://zombie_fixture_settings.cfg"
	create_timer(60.0).timeout.connect(func(): finish(2))
	effects = load("res://scripts/effects/我的世界/mc_status_effects.gd")
	projectiles = load("res://classes/projectile_interactions.gd")
	var zombie:Node2D = unit("res://scenes/characters/我的世界/僵尸.tscn",center,"Team0")
	var target:Node2D = unit("res://scenes/ball.tscn",center+Vector2(27,0),"Team1")
	target.Max_health = 10000
	target.default_properties.Max_health = 10000
	target.health = 10000
	target.block = 0
	target.max_block = 0
	target.Damage_reduction = 0
	target.default_properties.Damage_reduction = 0
	await physics_frame
	await process_frame
	check(zombie.Max_health == 100 and zombie.health == 100,"zombie has exactly 100 health")
	check(zombie.Damage == 18 and zombie.Speed == 72,"zombie moderate bite and moderately slow speed")
	check(not zombie.Has_Collision_Damage and not zombie.self_hitbox.monitoring,"no accidental contact damage")
	check(zombie.voice.events.has_all(["ambient","step","hurt","death"]),"four original zombie voice categories")
	check(zombie.player_control_action_ids() == [&"controlled_attack_action"],"zombie exposes one manual bite")
	zombie.direction = Vector2.LEFT
	zombie.step_zombie(0.0)
	check(zombie.direction.x > 0.9,"nearby enemy faces the bite target")
	check(zombie.bite_left >= 0.0,"AI starts bite at close enemy")
	check(zombie._hold_distance,"zombie holds biting distance rather than pushing forward")
	var hold_position:Vector2 = zombie.global_position
	zombie.move(zombie.Speed,1.0/60.0)
	check(zombie.global_position.distance_to(hold_position) < 0.01,"holding preserves collision without forward pressure")
	var jaw:Node2D = zombie._bite_fx
	jaw.set_physics_process(false)
	jaw._age = 0.0
	check(jaw.jaw_gap() == 8.0,"bite starts with separated upper and lower teeth")
	jaw._age = zombie.BITE_WINDUP
	check(jaw.jaw_gap() == 0.0 and not jaw.is_in_group("MCEvokerFang"),"two jaws meet exactly when bite damage settles, without evoker fangs")
	check(target.health == 10000,"windup does not apply early damage")
	check(zombie.get_ai_attack_threats().size() == 1,"windup exposes actual bite circle")
	var fixed:Vector2 = zombie.bite_point
	zombie.step_zombie(0.15)
	check(target.health == 9982,"bite settles current 18 attack through common defense")
	check(zombie.get_debug_attack_regions().size() == 1,"actual bite has matching debug geometry")
	zombie.step_zombie(0.01)
	check(target.health == 9982,"bite settles once, not once per frame")
	zombie.bite_cooldown = 0.0
	zombie.Damage = 30
	check(zombie.begin_bite(target),"next bite can start after cooldown")
	zombie.Damage = 40
	zombie.step_zombie(0.15)
	check(target.health == 9942,"bite samples live attack at closure rather than launch")
	zombie.bite_cooldown = 0.0
	zombie.begin_bite(target)
	target.global_position = center+Vector2(130,0)
	await physics_frame
	var before:float = target.health
	zombie.step_zombie(0.15)
	check(target.health == before and zombie.bite_point == fixed,"moving away dodges fixed-position bite")
	zombie.cancel_bite()
	zombie.bite_cooldown = 3.0
	target.global_position = center+Vector2(350,0)
	zombie._mc_target_wait = 0.0
	zombie.direction = Vector2.UP
	zombie.step_zombie(0.1)
	check(zombie.direction == Vector2.UP,"far enemy does not replace normal roaming")
	game.now_stop_state = true
	var clock:float = zombie.bite_cooldown
	zombie.tick_physics(0,1.0)
	check(zombie.bite_cooldown == clock,"pause freezes cooldown")
	game.now_stop_state = false
	target.global_position = center+Vector2(24,0)
	zombie.bite_cooldown = 0.0
	var barrier:StaticBody2D = wall(center+Vector2(12,0))
	await physics_frame
	check(not zombie.begin_bite(target),"bite cannot begin through wall")
	barrier.queue_free()
	await physics_frame
	var king:Node2D = unit("res://scenes/characters/我的世界/僵尸王.tscn",center+Vector2(-90,0),"Team0")
	check(king.Max_health == 420 and king.attack_damage() == 0,"king is medium-health support with zero direct damage")
	check(not king.begin_bite(target),"king cannot inherit zombie bite")
	check(king.player_control_action_ids().size() == 2,"king binds summon then throw")
	king.direction = Vector2.UP
	king.step_zombie(0.01)
	check(king.direction == Vector2.UP,"king never steers normal movement toward enemy")
	king.summon_cooldown = 0.0
	check(king.summon_zombies() == 2,"one cast summons two zombies")
	check(king.summon_zombies() == 0,"summoning obeys cooldown")
	for i:int in range(4):
		king.summon_cooldown = 0.0
		king.summon_zombies()
	check(king.living_summons().size() == 6,"summons capped at six living zombies")
	for child:Node2D in king.living_summons():
		child.state_machine.set_physics_process(false)
		check(child.Max_health == 100 and child.attack_damage() == 18,"summon owns its attack despite zero-damage master")
		check(child.Master == king and child.Team == king.Team,"summon ownership and team initialized before entry")
		check(child.has_meta("battle_lifecycle_identity"),"summon participates in shared battle lifecycle")
	var entrant:Node2D = king.living_summons()[0]
	await process_frame
	check(entrant.entry_left > 0.0 and entrant.has_meta("map_rescue_animating"),"summons use the shared wall-entry motion phase")
	check(is_instance_valid(entrant._entry_clip) and entrant._entry_clip.active,"wall emergence uses real half-plane body clipping")
	check(not entrant.can_act(),"summon cannot bite while emerging from the wall")
	var outer:Rect2 = king.mc_arena_rect()
	var face:Vector2 = entrant.entry_face
	check(minf(minf(absf(face.x-outer.position.x),absf(face.x-outer.end.x)),minf(absf(face.y-outer.position.y),absf(face.y-outer.end.y))) < 0.01,"summons originate only on the outer arena wall")
	check((entrant.entry_target-face).dot(entrant.entry_normal) > 0.0,"entry moves inward, not away from the wall")
	check(not zombie.mc_enemy(king.living_summons()[0]),"same-team summons are never bite targets")
	king.throw_cooldown = 0.0
	check(king.throw_slime(center+Vector2(120,0)),"king throws slime")
	check(not king.throw_slime(center),"throw obeys attack cooldown")
	var shot:Node2D = get_nodes_in_group("MCZombieSlimeBall")[0]
	shot.set_physics_process(false)
	check(projectiles.is_projectile(shot) and projectiles.damage_of(shot) == 0.0,"slime is classified zero-damage projectile")
	check(shot.point_at(0.5).y < shot._from.lerp(shot._to,0.5).y,"slime has a genuine upward arc")
	check(shot.point_at(1.0).distance_to(shot._to) < 0.01,"aim point lies on ballistic trajectory but is not a lifetime limit")
	check(shot.get_projectile_velocity().y < 0.0,"slime initially rises")
	shot._age = shot._flight*0.9
	check(shot.get_projectile_velocity().y > 0.0,"slime descends in second half")
	shot.global_position = target.global_position+Vector2(-30,0)
	shot.set_projectile_velocity(Vector2(210,0))
	before = target.health
	await physics_frame
	shot._physics_process(0.2)
	check(effects.active(target,"slowness") and effects.level_of(target,"slowness") == 2,"slime contact applies exactly Slowness II")
	check(target.health == before,"slime inflicts no direct damage")
	check(shot._spent,"slime retires after first valid contact")
	check(target.cleanse_negative_effects(),"slowness participates in common cleanse")
	await physics_frame
	check(not effects.active(target,"slowness"),"cleanse removes slow")
	zombie.bite_cooldown = 0.0
	zombie.player_control_peer_id = 1
	zombie.direction = Vector2.UP
	zombie.step_zombie(0.1)
	check(zombie.bite_left < 0.0 and zombie.direction == Vector2.UP,"manual zombie does not auto-bite or auto-chase")
	zombie.player_control_aim_valid = true
	zombie.player_control_aim_position = target.global_position
	zombie.controlled_attack_action()
	check(zombie.bite_left >= 0.0,"manual left action starts a legal nearby bite")
	zombie.Can_Attack = false
	before = target.health
	zombie.step_zombie(0.2)
	check(zombie.bite_left < 0.0 and target.health == before,"disabled attacks cancel pending bite without damage")
	zombie.Can_Attack = true
	zombie.player_control_peer_id = 0
	king.player_control_peer_id = 1
	king.summon_cooldown = 0.0
	king.throw_cooldown = 0.0
	var shots_before:int = king._shot_serial
	king.step_zombie(0.2)
	check(king._shot_serial == shots_before,"manual king does not throw automatically")
	king.player_control_peer_id = 0
	var packed:PackedScene = load(king.SLIME_SCENE)
	var slow_shot:Node2D = packed.instantiate()
	slow_shot.configure(king,target.global_position+Vector2(-30,0),target.global_position)
	slow_shot.position = target.global_position+Vector2(-30,0)
	world.add_child(slow_shot,true)
	slow_shot.set_physics_process(false)
	slow_shot.set_projectile_velocity(Vector2(210,0))
	await physics_frame
	slow_shot._physics_process(0.2)
	check(effects.level_of(target,"slowness") == 2,"repeated slime hit starts at level II")
	var again:Node2D = packed.instantiate()
	again.configure(king,target.global_position+Vector2(-30,0),target.global_position)
	again.position = target.global_position+Vector2(-30,0)
	world.add_child(again,true)
	again.set_physics_process(false)
	again.set_projectile_velocity(Vector2(210,0))
	await physics_frame
	again._physics_process(0.2)
	check(effects.level_of(target,"slowness") == 2,"repeated slime refreshes without stacking to level IV")
	var blocked:Node2D = packed.instantiate()
	blocked.configure(king,center+Vector2(0,-70),center+Vector2(130,-70))
	blocked.position = center+Vector2(0,-70)
	world.add_child(blocked,true)
	blocked.set_physics_process(false)
	blocked.set_projectile_velocity(Vector2(210,0))
	barrier = wall(center+Vector2(35,-70))
	await physics_frame
	blocked._physics_process(0.3)
	check(not blocked._spent and blocked.global_position.x > center.x+60,"slime crosses terrain instead of retiring at the wall")
	blocked.queue_free()
	barrier.queue_free()
	await physics_frame
	var falling:Node2D = packed.instantiate()
	falling.configure(king,center+Vector2(0,-140),center+Vector2(80,-140))
	falling.position = falling._from
	world.add_child(falling,true)
	falling.set_physics_process(false)
	falling._physics_process(falling._flight)
	check(not falling._spent and falling.global_position.distance_to(falling._to)<0.01,"slime remains alive after reaching its original aim point")
	var down_speed:float = falling.get_projectile_velocity().y
	falling._physics_process(0.1)
	check(not falling._spent and falling.global_position.y > falling._to.y and falling.get_projectile_velocity().y > down_speed,"slime continues downward with increasing gravity speed")
	game.now_stop_state = true
	var frozen_point:Vector2 = falling.global_position
	falling._physics_process(0.5)
	check(falling.global_position == frozen_point,"pause freezes continuing free fall")
	game.now_stop_state = false
	falling._physics_process(4.0)
	check(falling._spent,"falling slime cleans up only after leaving arena bounds")
	var high:Node2D = packed.instantiate()
	high.configure(king,center+Vector2(0,-100),center+Vector2(0,-220))
	high.position = high._from
	world.add_child(high,true)
	high.set_physics_process(false)
	high._arena_bounds = Rect2(center+Vector2(-100,-150),Vector2(200,400))
	high.global_position = high._arena_bounds.position+Vector2(100,-100)
	high.set_projectile_velocity(Vector2(0,1))
	high._physics_process(0.01)
	check(not high._spent,"a high lob above the top wall can fall back into the arena")
	high.queue_free()
	var through:Node2D = packed.instantiate()
	through.configure(king,target.global_position+Vector2(-60,0),target.global_position)
	through.position = through._from
	world.add_child(through,true)
	through.set_physics_process(false)
	through._arc = 0.0
	through.set_projectile_velocity(Vector2(210,0))
	target.cleanse_negative_effects()
	barrier = wall(target.global_position+Vector2(-30,0))
	await physics_frame
	before = target.health
	through._physics_process(0.3)
	check(through._spent and effects.level_of(target,"slowness")==2 and target.health==before,"a single sweep crosses a wall and slows the target behind it without damage")
	barrier.queue_free()
	target.global_position = zombie.global_position+Vector2(15,0)
	zombie._mc_target_wait = 0.0
	zombie.step_zombie(0.0)
	check(zombie._hold_distance,"over-close zombie stops propulsion and delegates separation to the shared solver")
	target.global_position = center+Vector2(24,0)
	var enchants:Script = load("res://scripts/effects/我的世界/mc_enchantments.gd")
	var support:Script = load("res://scripts/effects/我的世界/mc_enchant_support.gd")
	check(enchants.target_tags_for(zombie).has("undead") and enchants.target_tags_for(king).has("undead"),"both new undead roles participate in Smite targeting")
	check(support.capabilities(zombie).has("efficiency") and support.capabilities(king).has("multishot"),"audited enchantment abilities registered")
	check(enchants.apply(king,"piercing",1),"king accepts shared Piercing")
	await process_frame
	await process_frame
	var pierce:Node2D = packed.instantiate()
	pierce.configure(king,target.global_position+Vector2(-30,0),target.global_position+Vector2(100,0))
	pierce.position = target.global_position+Vector2(-30,0)
	world.add_child(pierce,true)
	pierce.set_physics_process(false)
	pierce.set_projectile_velocity(Vector2(210,0))
	await process_frame
	await physics_frame
	pierce._physics_process(0.2)
	await process_frame
	await process_frame
	var continuations:Array = get_nodes_in_group("MCZombieSlimeBall").filter(func(n:Node): return target.get_instance_id() in n.get_meta("mc_pierce_ignore",[]))
	check(not continuations.is_empty(),"zero-damage slow contact feeds shared Piercing continuation")
	for continuation:Node in continuations: continuation.queue_free()
	enchants.remove(king,"piercing")
	target.cleanse_negative_effects()
	await process_frame
	var fizzled:Node2D = packed.instantiate()
	fizzled.configure(king,target.global_position+Vector2(-30,0),target.global_position+Vector2(100,0))
	fizzled.position = target.global_position+Vector2(-30,0)
	fizzled.set_meta("mc_fizzle_chance",1.0)
	world.add_child(fizzled,true)
	fizzled.set_physics_process(false)
	fizzled.set_projectile_velocity(Vector2(210,0))
	await physics_frame
	fizzled._physics_process(0.2)
	check(fizzled._spent and not effects.active(target,"slowness"),"inverse Piercing can retire slime without applying slow")
	await verify_wall_escape(zombie,target,center)
	var summons:Array = king.living_summons()
	king.queue_free()
	await physics_frame
	check(summons.all(func(n:Node2D): return is_instance_valid(n) and n.health > 0),"king death/exit does not delete surviving zombies")
	check(game.t("僵尸") != "" and not zombie.get_armor_test_effect_summary().is_empty(),"names and armor introduction are present")
	finish(0 if failures == 0 else 1)

func verify_wall_escape(zombie:Node2D,target:Node2D,center:Vector2) -> void:
	target.cleanse_negative_effects()
	zombie.cancel_bite()
	zombie.bite_cooldown = 100.0
	zombie.player_control_peer_id = 0
	target.player_control_peer_id = 1
	target.player_control_direction = Vector2.LEFT
	target.global_position = center+Vector2(130,170)
	zombie.global_position = target.global_position+Vector2(-25,0)
	var extent:Rect2 = world._body_extents_from_origin(target)
	var barrier:StaticBody2D = wall(target.global_position+Vector2(extent.end.x+2.5,0))
	barrier.get_child(0).shape.size = Vector2(4,300)
	var start:Vector2 = target.global_position
	var mask:int = zombie.collision_mask
	await physics_frame
	for i:int in range(100):
		zombie._mc_target_ref = weakref(target)
		zombie._mc_target_wait = 1.0
		zombie.tick_physics(0,1.0/60.0)
		target.move(target.Speed,1.0/60.0)
		await physics_frame
	check(target.global_position.x < start.x-25.0,"real colliding victim can move away from the wall by pushing the zombie through the shared body response")
	check(zombie.collision_mask == mask and (mask & 2) != 0,"escape fix retains physical character collisions")
	barrier.queue_free()
	target.player_control_peer_id = 0
	target.global_position = zombie.global_position+Vector2(0,35)
	zombie.bite_cooldown = 0.0
	zombie._mc_target_wait = 0.0
	zombie.step_zombie(0.0)
	check(zombie._hold_distance and zombie.bite_left >= 0.0,"vertical approach can bite while leaving room for the taller physical body")
	var before:float = target.health
	zombie.step_zombie(0.15)
	check(target.health < before,"holding outside vertical contact still allows real bite damage")
