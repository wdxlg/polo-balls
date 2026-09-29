extends "res://tests/test_mc_bat_transform.gd"
func run() -> void:
	var center:Vector2 = await setup_world()
	var b:Node2D = spawn(BAT.SCENE_PATH,center)
	b.state_machine.set_physics_process(false)
	var enemy:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(0,200),"Team1")
	enemy.state_machine.set_physics_process(false)
	enemy.Has_Collision_Damage = false
	enemy.self_hitbox.monitoring = false
	enemy.Max_health = 10000
	enemy.default_properties.Max_health = 10000
	enemy.health = 10000
	await physics_frame
	await process_frame
	pause_members(b)
	check(b.living_members().size() == 5 and totals(b) == Vector2i(225,225),"five starting bats total 225 current and maximum HP")
	var correct:bool = true
	for member:Node2D in b.living_members():
		correct = correct and member.health == 45 and member.Max_health == 45 and member.attack_damage() == 3.0
	check(correct,"every initial bat has 45 HP and 3 attack")
	var actual:int = b.drain_target(enemy)
	check(actual == 3 and b.health == 48 and b.Max_health == 48,"three actual damage heals and grows bat by three")
	b.restore_default_runtime_properties_fast()
	check(b.health == 48 and b.Max_health == 48 and b.attack_damage() == 3.0,"World refresh preserves growth and the new attack")
	settle_fusion(b)
	check(b.vampire and totals(b) == Vector2i(228,228),"fusion conserves updated starting health plus growth")
	check(b.vampire_health_per_damage == 30 and b.attack_damage() == 15.0,"vampire keeps 8 plus floor current HP over 30 attack formula")
	actual = b.drain_target(enemy)
	check(actual == 15 and totals(b) == Vector2i(243,243),"vampire still grows capacity and heals up to the new cap")
	b.split_swarm()
	pause_members(b)
	check(b.living_members().size() == 5 and totals(b) == Vector2i(243,243),"split uses divisor 45 and conserves integer totals")
	correct = true
	for member:Node2D in b.living_members():
		correct = correct and member.initial_bat_health == 45 and member.attack_damage() == 3.0
	check(correct,"all split offspring inherit 45 initial HP and 3 attack")
	check(BAT.split_count(89,45) == 1 and BAT.split_count(90,45) == 2 and BAT.split_count(1,45) == 1 and BAT.split_count(0,45) == 0,"45-HP division retains floor, living minimum one, and dead zero rules")
	finish(0 if failures == 0 else 1)
