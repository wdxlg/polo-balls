extends "res://tests/test_mc_bat_transform.gd"

func pause_unit(unit:Node2D) -> void:
	unit.state_machine.set_physics_process(false)
	unit.Has_Collision_Damage = false
	unit.self_hitbox.monitoring = false

func check_cohort_collisions(b:Node2D,label:String) -> void:
	var members:Array = b.living_members()
	var correct:bool = members.size() >= 2
	for a:Node2D in members:
		for other:Node2D in members:
			if a != other: correct = correct and a.get_collision_exceptions().has(other)
	check(correct,label)

func crowd_pair(a:Node2D,b:Node2D) -> Vector2:
	a.set_large_battle_performance_mode(true)
	b.set_large_battle_performance_mode(true)
	await physics_frame
	var before:Vector2 = a.global_position
	a.get_body_motion().separate_overlaps()
	var push:Vector2 = a.global_position-before
	a.set_large_battle_performance_mode(false)
	b.set_large_battle_performance_mode(false)
	world._large_battle_mode_active = false
	world._rebuild_battle_spatial_grid(world._battle_units_cache)
	return push

func step_bite(b:Node2D,enemy:Node2D,delta:float) -> void:
	# Manual clock stepping, but production target selection, range and damage paths.
	b.global_position = enemy.global_position+Vector2(-20,0)
	b.direction = Vector2.ZERO
	b.Repel = Vector2.ZERO
	b.tick_physics(0,delta)

func reset_encounter(b:Node2D,enemy:Node2D) -> void:
	b.detach()
	b.cohort.left = 10000.0
	b.assign_vitals(150 if b.vampire else 50,150 if b.vampire else 50)
	enemy.block = 0
	enemy.health = 10000
	b._mc_target_ref = weakref(enemy)
	b._mc_target_wait = 1000.0
	b._cooldown = 0.0
	b.global_position = enemy.global_position+Vector2(-20,0)

func exercise_shields(b:Node2D,enemy:Node2D,label:String) -> void:
	reset_encounter(b,enemy)
	var damage:int = int(b.attack_damage())
	enemy.block = 1000
	var initial:Vector2i = totals(b)
	b.begin_bite(enemy)
	check(enemy.block == 1000-damage and enemy.health == 10000,label+" first bite damages only shield")
	check(b.attached_target() == null and not b.feeding_guard_active() and totals(b) == initial,label+" shield-only hit grants no latch, guard, healing or capacity")
	step_bite(b,enemy,0.24)
	check(enemy.block == 1000-damage,label+" cannot repeat a shield bite before 0.25 seconds")
	step_bite(b,enemy,0.011)
	check(enemy.block == 1000-2*damage,label+" retries shield bite at 0.25 seconds instead of waiting 3 seconds")
	for i:int in range(3): step_bite(b,enemy,0.251)
	check(enemy.block == 1000-5*damage and totals(b) == initial,label+" repeated shield bites preserve zero lifesteal")
	enemy.block = 0
	step_bite(b,enemy,0.11)
	check(enemy.health == 10000 and not b._bite_ready(enemy),label+" removing shield externally immediately restores normal retry cooldown")
	enemy.block = 1000
	step_bite(b,enemy,0.251)
	check(enemy.block == 1000-damage,label+" gaining a shield during normal cooldown enables quick attacks")
	var waiting:float = b._shield_bite_wait
	var before_block:int = enemy.block
	game.now_stop_state = true
	step_bite(b,enemy,1.0)
	check(enemy.block == before_block and b._shield_bite_wait == waiting,label+" pause freezes quick retries")
	game.now_stop_state = false
	b.detach()
	b._cooldown = 0.0
	b.global_position = enemy.global_position+Vector2(-200,0)
	b.begin_bite(enemy)
	check(enemy.block == before_block,label+" shield does not bypass bite range")

	reset_encounter(b,enemy)
	enemy.block = damage
	b.begin_bite(enemy)
	check(enemy.block == 0 and enemy.health == 10000,label+" exact shield break deals no fabricated health damage")
	step_bite(b,enemy,0.11)
	check(enemy.health == 10000,label+" exact shield break does not leave a fast follow-up against health")
	step_bite(b,enemy,2.90)
	check(enemy.health == 10000-damage and b.attached_target() == enemy,label+" failed bite recovers after normal 3-second cooldown, not an extra attachment duration")

	reset_encounter(b,enemy)
	b.begin_bite(enemy)
	check(b.attached_target() == enemy,label+" normal health bite still attaches")
	var health_before:int = enemy.health
	initial = totals(b)
	enemy.block = 1000
	step_bite(b,enemy,0.24)
	check(b.attached_target() == null and not b.feeding_guard_active() and enemy.block == 1000,label+" gaining shield immediately releases latch and guard, without an extra attack")
	step_bite(b,enemy,0.011)
	check(enemy.block == 1000,label+" released bat cannot bypass the shield retry clock")
	var attached_damage:int = int(b.attack_damage())
	step_bite(b,enemy,0.24)
	check(enemy.block == 1000-attached_damage and enemy.health == health_before and totals(b) == initial,label+" detached shield attack resumes after quarter second without lifesteal")
	step_bite(b,enemy,0.251)
	check(enemy.block == 1000-2*attached_damage and b.attached_target() == null,label+" shield retry cadence is retained without attachment")
	enemy.block = 0
	step_bite(b,enemy,0.51)
	check(enemy.health == health_before,label+" removing shield does not bypass normal reattachment cooldown")
	step_bite(b,enemy,2.50)
	check(enemy.health == health_before-attached_damage and b.attached_target() == enemy,label+" normal health bite can reattach once its cooldown expires")

	reset_encounter(b,enemy)
	b.begin_bite(enemy)
	health_before = enemy.health
	enemy.block = int(b.attack_damage())
	step_bite(b,enemy,0.001)
	check(b.attached_target() == null,label+" even a small shield interrupts feeding")
	step_bite(b,enemy,0.251)
	check(enemy.block == 0 and enemy.health == health_before,label+" detached shield attack can break shield without stealing health")
	step_bite(b,enemy,0.49)
	check(enemy.health == health_before,label+" shield break cannot preserve the old attachment half-second timer")
	step_bite(b,enemy,2.52)
	check(enemy.health < health_before and b.attached_target() == enemy,label+" post-shield latch waits normal cooldown")

	reset_encounter(b,enemy)
	b.begin_bite(enemy)
	enemy.block = 1000
	waiting = b._drain_wait
	before_block = enemy.block
	game.now_stop_state = true
	step_bite(b,enemy,1.0)
	check(enemy.block == before_block and b._drain_wait == waiting,label+" pause freezes drain and defense processing")
	game.now_stop_state = false
	b.detach()
	step_bite(b,enemy,0.24)
	check(enemy.block == before_block,label+" detach retains a minimum 0.25-second shield retry")
	step_bite(b,enemy,0.011)
	check(enemy.block < before_block,label+" detach permits fast retry only against a shielded target")
	b.detach()

func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(90.0).timeout.connect(func(): finish(2))
	var b:Node2D = spawn(BAT.SCENE_PATH,center)
	var other:Node2D = spawn(BAT.SCENE_PATH,center+Vector2(180,0))
	var enemy:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(0,200),"Team1")
	pause_unit(b)
	pause_unit(other)
	pause_unit(enemy)
	enemy.Max_health = 10000
	enemy.default_properties.Max_health = 10000
	enemy.health = 10000
	enemy.max_block = 10000
	enemy.default_properties.max_block = 10000
	await physics_frame
	await process_frame
	pause_members(b)
	pause_members(other)
	check_cohort_collisions(b,"all five initial bats have symmetric same-cohort body exceptions")
	var peers:Array = b.living_members()
	var sibling:Node2D = peers[1]
	check(not b.get_collision_exceptions().has(other) and not other.get_collision_exceptions().has(b),"different cohorts on the SAME team retain collision")
	check(not b.get_collision_exceptions().has(enemy),"ordinary enemy bodies retain collision")
	for member:Node2D in peers: member.global_position = center+Vector2(-200,0)
	b.global_position = center
	sibling.global_position = center+Vector2(90,0)
	await physics_frame
	var contact:KinematicCollision2D = b.move_and_collide(Vector2(130,0),true)
	check(contact == null,"production body sweep passes through a same-cohort bat")
	sibling.global_position = center+Vector2(-200,0)
	other.global_position = center+Vector2(90,0)
	await physics_frame
	contact = b.move_and_collide(Vector2(130,0),true)
	check(contact != null and contact.get_collider() == other,"production body sweep still hits a different cohort")
	other.global_position = center+Vector2(180,0)
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(8,80)
	shape.shape = box
	wall.add_child(shape)
	world.add_child(wall)
	wall.global_position = center+Vector2(45,0)
	await physics_frame
	contact = b.move_and_collide(Vector2(70,0),true)
	check(contact != null and contact.get_collider() == wall,"terrain remains solid after same-cohort exclusions")
	wall.free()
	sibling.global_position = center+Vector2(1,0)
	check((await crowd_pair(b,sibling)).is_zero_approx(),"crowd mode also skips same-cohort position correction")
	other.global_position = center+Vector2(1,0)
	check(not (await crowd_pair(b,other)).is_zero_approx(),"crowd mode still separates different cohorts")
	other.global_position = center+Vector2(180,0)
	settle_fusion(b)
	b.assign_vitals(250,250)
	b.shield_attack_interval = 0.12
	b.split_swarm()
	pause_members(b)
	check_cohort_collisions(b,"new split members inherit all same-cohort body exceptions")
	var inherited:bool = true
	for member:Node2D in b.living_members():
		inherited = inherited and is_equal_approx(member.shield_attack_interval,0.12)
		member.shield_attack_interval = 0.25
	check(inherited,"custom shield attack interval propagates to split offspring")
	var survivor:Node2D = b.living_members()[1]
	b.health = 0
	b.queue_free()
	await process_frame
	b = survivor
	pause_members(b)
	check_cohort_collisions(b,"same-cohort collision exclusions survive original leader death")
	for member:Node2D in b.living_members(): member.global_position = center+Vector2(-200,0)
	exercise_shields(b,enemy,"bat")
	check_cohort_collisions(b,"attaching and detaching never remove cohort exceptions")
	settle_fusion(b)
	check(b.vampire,"surviving cohort still fuses after leader loss")
	exercise_shields(b,enemy,"vampire")
	check(b.vampire_damage == 10 and is_equal_approx(b.shield_attack_interval,0.25),"vampire damage buff and shield cadence remain intact")
	finish(0 if failures == 0 else 1)
