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
	var correct:bool = true
	for member:Node2D in b.living_members():
		correct = correct and member.image.scale == Vector2(0.55,0.55) and member.collision_shape_2d.shape.size == Vector2(49,34)
	check(correct,"all five starting bats have enlarged image and matching collision geometry")
	check(BAT.GATHER_NAV.clearance_radius(b) >= (b.collision_shape_2d.shape.size*b.collision_shape_2d.global_scale*0.5).length(),"gather route clearance covers the larger body corners")
	settle_fusion(b)
	check(b.image.scale == Vector2(0.6,0.6),"vampire size remains unchanged")
	b.assign_vitals(150,150)
	var actual:int = b.drain_target(enemy)
	check(actual == 15 and b.Max_health == 165 and b.health == 165,"full-health vampire grows by actual damage before capped healing")
	await process_frame
	check(b.default_properties.Max_health == 165 and b.Max_health == 165,"vampire growth persists through World property resets")
	b.assign_vitals(100,150)
	actual = b.drain_target(enemy)
	check(actual == 13 and b.Max_health == 163 and b.health == 126,"injured vampire gains one damage worth of capacity and two of healing")
	var before:Vector2i = totals(b)
	enemy.max_block = 1000
	enemy.default_properties.max_block = 1000
	enemy.block = 1000
	actual = b.drain_target(enemy)
	check(actual == 0 and totals(b) == before,"fully shielded hit cannot grant vampire health or capacity")
	enemy.block = 0
	enemy.health = 1
	actual = b.drain_target(enemy)
	check(actual == 1 and b.Max_health == before.y+1 and b.health == before.x+2,"overkill grants capacity only for the one actual enemy HP")
	before = totals(b)
	b.split_swarm()
	pause_members(b)
	await physics_frame
	await process_frame
	check(totals(b) == before,"new vampire capacity and current health both survive integer split")
	correct = true
	for member:Node2D in b.living_members():
		correct = correct and member.image.scale == Vector2(0.55,0.55) and member.collision_shape_2d.shape.size == Vector2(49,34)
	check(correct,"retained and newly spawned split bats both use enlarged geometry")
	settle_fusion(b)
	check(totals(b) == before,"grown vampire capacity survives the following fusion too")
	finish(0 if failures == 0 else 1)
