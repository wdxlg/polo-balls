extends "res://tests/test_mc_frontier.gd"
func prepare(moss:Node2D,point:Vector2) -> void:
	moss.cancel_burrow()
	moss.patches.clear()
	moss.global_position = point
	moss.burrow_wait = 0.0
	moss.health = 300
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(60.0).timeout.connect(func(): finish(2))
	var moss:Node2D = actor("苔藓",center)
	var point:Vector2 = Vector2(moss.cell_at(center))*moss.CELL
	moss.global_position = point
	var target:Node2D = dummy(point)
	await physics_frame
	prepare(moss,point)
	for x:int in range(-1,2):
		for y:int in range(-1,2):
			for layer:int in range(3): moss.plant(point+Vector2(x,y)*moss.CELL)
	moss.plant(point+Vector2(48,0))
	check(moss.begin_burrow(),"dense 3x3 fixture starts burrow")
	check(not moss.finish_burrow() and moss.health==300,"early completion cannot consume or heal")
	moss.burrow_left = 0.0
	check(moss.finish_burrow() and moss.health==336,"nine occupied cells heal 36 HP, not 27 layers worth")
	for x:int in range(-1,2):
		for y:int in range(-1,2):
			check(moss.patch_at(point+Vector2(x,y)*moss.CELL).layers==2,"each 3x3 cell loses exactly one layer, including corners")
	check(moss.patch_at(point+Vector2(48,0)).layers==1,"cell outside 3x3 stays unchanged")
	check(not moss.finish_burrow() and moss.health==336,"repeat resolution cannot consume or heal twice")
	prepare(moss,point)
	moss.plant(point)
	moss.plant(point+Vector2(24,24))
	moss.plant(point+Vector2(-24,0))
	moss.plant(point+Vector2(-24,0))
	check(moss.begin_burrow(),"sparse field starts burrow")
	moss.burrow_left = 0.0
	check(moss.finish_burrow() and moss.health==312,"three occupied cells heal 12 HP; empty cells give no credit")
	check(moss.patch_at(point).is_empty() and moss.patch_at(point+Vector2(24,24)).is_empty(),"one-layer cells disappear, disconnected diagonal still included in square consumption")
	check(moss.patch_at(point+Vector2(-24,0)).layers==1,"two-layer cell retains one layer")
	prepare(moss,point)
	moss.plant(point)
	moss.health = moss.Max_health-1
	moss.begin_burrow()
	moss.burrow_left = 0.0
	moss.finish_burrow()
	check(moss.health==moss.Max_health,"consumption healing respects maximum health")
	prepare(moss,point)
	moss.plant(point)
	moss.plant(point+Vector2(24,0))
	moss.begin_burrow()
	moss.destroy_moss_obstacle(point+Vector2(24,0),moss.patch_at(point+Vector2(24,0)).serial)
	moss.burrow_left = 0.0
	check(moss.finish_burrow() and moss.health==304,"neighbor destroyed during windup is not counted for healing")
	prepare(moss,point)
	moss.plant(point)
	moss.plant(point+Vector2(24,0))
	moss.begin_burrow()
	moss.destroy_moss_obstacle(point,moss.patch_at(point).serial)
	moss.burrow_left = 0.0
	check(not moss.finish_burrow() and moss.health==300 and moss.patch_at(point+Vector2(24,0)).layers==1,"destroyed exit cancels without consuming neighbors or healing")
	prepare(moss,point)
	moss.plant(point)
	moss.clock = 100.0
	var hp:int = target.health
	moss.check_trampling()
	check(target.health==hp-10,"one-layer tick reduced to 10 base damage")
	moss.clock += 0.79
	moss.check_trampling()
	check(target.health==hp-10,"cannot tick before 0.8 second cooldown")
	moss.clock += 0.02
	moss.check_trampling()
	check(target.health==hp-20,"second tick lands after 0.8 seconds rather than one second")
	check(moss.attack_damage(moss.burrow_damage_multiplier)==60.0,"DOT reduction does not accidentally weaken burrow strike")
	print("MOSS CONSUMPTION CONTRACTS: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
