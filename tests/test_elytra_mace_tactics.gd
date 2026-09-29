extends SceneTree
var checks:int = 0
var failures:int = 0
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("ELYTRA_TACTIC_FAIL ",label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game:Node = root.get_node("Game")
	game.now_stop_state = false
	game.Game_Settings.Have_Team_Damage = false
	var arena:Node2D = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	var mace:Node2D = load("res://scenes/characters/我的世界/鞘翅重锤.tscn").instantiate()
	mace.Team = "Team0"
	arena.add_child(mace)
	var target:Node2D = load("res://scenes/characters/我的世界/重锤.tscn").instantiate()
	target.Team = "Team1"
	target.Max_health = 1000000
	arena.add_child(target)
	# Four geometry-driven choices, no cyclic/random attack pattern.
	mace.global_position = Vector2(0,-200)
	mace._glide_velocity = Vector2(100,200)
	mace._tactic_hold = 0
	var aim:Vector2 = mace._choose_flight_tactic(target,0.016)
	check(aim.y > 0.8,"aim at enemy below")
	mace._use_firework(aim)
	check(mace._boost_direction.y > 0.8,"rocket can boost toward enemy downward")
	mace.global_position = Vector2(-300,0)
	mace._glide_velocity = Vector2(280,0)
	mace._tactic_hold = 0
	aim = mace._choose_flight_tactic(target,0.016)
	check(aim.x > 0.8 and absf(aim.y) < 0.4,"forward chase not vertical climb")
	mace._use_firework(aim)
	check(mace._boost_direction.x > 0.8,"horizontal chase rocket")
	mace.global_position = Vector2(20,20)
	mace._glide_velocity = Vector2(0,-150)
	mace._tactic_hold = 0
	aim = mace._choose_flight_tactic(target,0.016)
	check(aim.y < -0.5 and absf(aim.x) > 0.3,"close-range diagonal loft")
	mace._rocket_remaining = 0
	mace._rocket_cooldown = 0
	check(mace._wants_tactical_firework(target,aim),"close loft permits boost")
	mace.global_position = Vector2(-200,0)
	target.velocity = Vector2(60,0)
	mace._glide_velocity = Vector2(250,0)
	mace._tactic_hold = 0
	mace._choose_flight_tactic(target,0.016)
	check(mace._flight_tactic == mace.FlightTactic.FLANK,"moving enemy prompts side cut")
	mace.global_position = Vector2(35,0)
	mace._glide_velocity = Vector2(400,0)
	mace._tactic_hold = 0
	mace._choose_flight_tactic(target,0.016)
	check(mace._flight_tactic == mace.FlightTactic.EXTEND,"overshoot extends rather than instant U turn")
	mace.global_position = Vector2(0,-50)
	mace._glide_velocity = Vector2(0,600)
	mace._tactic_hold = 0
	aim = mace._choose_flight_tactic(target,0.016)
	mace._rocket_cooldown = 0
	check(not mace._wants_tactical_firework(target,aim),"ready cooldown does not force rocket on good attack line")
	mace._glide_velocity = Vector2(280,200)
	mace._begin_flight(1)
	check(mace._glide_velocity.x > 150.0 and mace.velocity.y < 0,"rebound keeps horizontal momentum")
	var starts:Array[Vector2] = [Vector2(20,0),Vector2(-300,0),Vector2(300,0),Vector2(0,-300),Vector2(0,300)]
	var all_tactics:Dictionary = {}
	var all_boosts:Dictionary = {}
	for moving:bool in [false,true]:
		for offset:Vector2 in starts:
			mace.global_position = offset
			target.global_position = Vector2.ZERO
			target.velocity = Vector2(45,0) if moving else Vector2.ZERO
			target.health = 1000000
			mace._airborne = false
			mace.Attacking = false
			mace._flight_mode = mace.FlightMode.GLIDE
			mace._tactic_hold = 0.0
			mace._rocket_remaining = 0.0
			mace._rocket_cooldown = 0.0
			mace._glide_velocity = Vector2(280,0)
			var hit:bool = false
			var impact_speed:float = 0.0
			var elapsed:float = 0.0
			for i:int in range(900):
				# Alternate moving enemy direction to exercise replanning, not just static aim.
				if moving and i > 0 and i % 120 == 0: target.velocity.x = -target.velocity.x
				target.global_position += target.velocity/60.0
				impact_speed = mace._glide_velocity.length()
				mace._step_glide(1.0/60.0)
				all_tactics[mace._flight_tactic] = true
				if mace._rocket_remaining > 0:
					all_boosts[int(round(mace._boost_direction.angle()*2.0))] = true
				elapsed += 1.0/60.0
				if target.health < 1000000:
					hit = true
					break
			check(hit,"actual hit "+str(offset)+" moving="+str(moving))
			check(impact_speed > 150,"retains combat speed "+str(impact_speed))
			check(mace._airborne and mace.velocity.y < 0,"hit continues combo")
			print("TACTIC_CASE ",offset," moving=",moving," t=",elapsed," impact_speed=",impact_speed)
	check(all_tactics.size() >= 3,"uses multiple tactical choices")
	check(all_boosts.size() >= 4,"boost has varied directions")
	print("ELYTRA_TACTIC_RESULT checks=",checks," failures=",failures)
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
