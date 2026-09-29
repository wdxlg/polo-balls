extends "res://tests/test_iron_golem_pair.gd"
func run() -> void:
	create_timer(55.0).timeout.connect(func(): push_error("IRON_GOLEM_LIVE_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	game.now_stop_state = false
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	AudioServer.set_bus_mute(0,true)
	Engine.time_scale = 4.0
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var g:Node2D = golem(Vector2.ZERO)
	var v:Node2D = g.companion
	var target:Node2D = enemy(Vector2(300,300))
	target.Speed = 0.0
	target.Can_Attack = false
	target.Can_Skill = false
	var world:Node = load("res://scripts/world.gd").new()
	world._apply_or_record_initial_battle_direction(g)
	world._apply_or_record_initial_battle_direction(v)
	check(is_equal_approx(g.direction.length(),1.0) and is_equal_approx(v.direction.length(),1.0),"World initializes both with normal movement directions")
	world.free()
	g.direction = Vector2.RIGHT
	v.direction = Vector2.RIGHT
	v.global_position = Vector2(500,0)
	wall_at(Vector2(100,0))
	wall_at(Vector2(600,0))
	var golem_bounced:bool = false
	var villager_bounced:bool = false
	for frame:int in range(90):
		await physics_frame
		golem_bounced = golem_bounced or g.direction.x<0
		villager_bounced = villager_bounced or v.direction.x<0
	check(golem_bounced,"golem uses real default wall collision reflection")
	check(villager_bounced,"villager uses real default wall collision reflection")
	check(g.direction.x<0 and v.direction.x<0,"AI does not overwrite reflected movement with pursuit or follow")
	check(absf(g.global_position.y)<0.1 and absf(v.global_position.y)<0.1,"neither steers toward enemy or partner off the movement line")
	check(not v.get_collision_exceptions().has(g) and not g.get_collision_exceptions().has(v),"partners also keep ordinary body collisions")
	g.health = 100
	g.global_position = Vector2.ZERO
	g.direction = Vector2.RIGHT
	v.global_position = Vector2(50,0)
	v.direction = Vector2.LEFT
	var repaired:bool = false
	for frame:int in range(40):
		await physics_frame
		if g.health>=200:
			repaired = true
			break
	check(repaired,"normal movement contact still repairs one crack tier")
	check(g.health==200,"contact repair remains one tier rather than full health")
	for i:int in range(5): await physics_frame
	check(g.direction.x<0 and v.direction.x>0,"pair bounces apart normally instead of following each other")
	g.global_position = Vector2.ZERO
	g.direction = Vector2.RIGHT
	g._attack_wait = 0.0
	g._phase = 0
	v.global_position = Vector2(500,250)
	v.direction = Vector2.RIGHT
	target.global_position = Vector2(35,0)
	var saw_charge:bool = false
	var saw_swing:bool = false
	var saw_launch:bool = false
	for frame:int in range(35):
		await physics_frame
		saw_charge = saw_charge or g.visual_clip=="charge"
		saw_swing = saw_swing or g.visual_clip=="swing"
		saw_launch = saw_launch or float(target.get_meta("golem_air_height",0.0))>0.01
		if saw_charge and saw_swing and saw_launch and target.health<10000: break
	check(saw_charge and saw_swing,"encounter during normal movement plays charge and upswing")
	check(target.health<10000 and saw_launch,"normal movement encounter still damages and launches")
	clear_control(target)
	var key:String = str(v.get_meta("battle_continuation_victory_side_key"))
	g.receive_positional_damage(2000,g.global_position,false,target)
	await physics_frame
	await process_frame
	check(is_instance_valid(v) and v.orphaned,"actual golem removal leaves orphan running")
	check(v.get_meta("battle_continuation_victory_side_key")==key,"orphan retains original victory side")
	v.global_position = Vector2(400,0)
	v.direction = Vector2.UP
	target.global_position = Vector2(470,0)
	var before:int = target.health
	var saw_throw:bool = false
	var saw_projectile:bool = false
	for frame:int in range(95):
		await physics_frame
		saw_throw = saw_throw or v.visual_clip=="throw"
		saw_projectile = saw_projectile or not get_nodes_in_group("GolemIronProjectile").is_empty()
		if target.health<before: break
	check(saw_throw and saw_projectile,"orphan throws during normal movement")
	check(target.health<before,"moving orphan's iron projectile reaches enemy")
	check(v.direction==Vector2.UP and absf(v.global_position.x-400.0)<0.1 and v.global_position.y < -5.0,"throwing never stops, chases, retreats, or steers the villager")
	check(get_nodes_in_group("MinecraftGolemVillager").size()==1,"no duplicate companions")
	print("IRON_GOLEM_LIVE_RESULT checks=",checks," failures=",failures)
	Engine.time_scale = 1.0
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
