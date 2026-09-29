extends "res://tests/test_mc_frontier.gd"
## Real engine ticks; one explicit fragment-contact fixture at 8s, no forced attack or repair completion.
func live_actor(role:String,point:Vector2) -> Node2D:
	var unit:Node2D = spawn("res://scenes/characters/我的世界/"+role+".tscn",point)
	unit.Can_Attack = true
	unit.Can_Skill = true
	unit.default_properties["Can_Attack"] = true
	unit.default_properties["Can_Skill"] = true
	return unit
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(70.0).timeout.connect(func(): finish(2))
	var moss:Node2D = live_actor("苔藓",center+Vector2(-220,-150))
	var moss_target:Node2D = dummy(moss.global_position+Vector2(55,0))
	var sword:Node2D = live_actor("木剑",center+Vector2(-170,200))
	var sword_target:Node2D = dummy(sword.global_position+Vector2(48,0))
	sword.durability = 1 # One worn attack tests breakage without requiring pursuit.
	sword.direction = Vector2.RIGHT
	var w:Node2D = live_actor("监守者",center+Vector2(180,170))
	var runner:Node2D = spawn("res://scenes/ball.tscn",w.global_position+Vector2(145,0),"Team1")
	runner.Has_Collision_Damage = false
	runner.self_hitbox.monitoring = false
	runner.Max_health = 10000
	runner.default_properties.Max_health = 10000
	runner.health = 10000
	runner.Speed = 155.0
	runner.default_properties.Speed = 155.0
	runner.set_player_control_peer(1)
	runner.Can_Skill=true
	runner.Skill_Cooling=1.0
	var next_runner_action:float=1.2
	var cart:Node2D = live_actor("矿车",center+Vector2(160,-170))
	cart.direction = Vector2.RIGHT
	var cart_target:Node2D = dummy(cart.global_position+Vector2(150,0))
	var cart_ledger:Dictionary = {"damage":0.0}
	game.combat_damage_resolved.connect(func(source:Node,_victim:Node,amount:float,_before:float) -> void:
		if is_instance_valid(cart) and source == cart: cart_ledger.damage += amount)
	var cart_origin:Vector2 = cart.global_position
	var saw_warning:bool = false
	var saw_emerge:bool = false
	var saw_awake:bool = false
	var saw_broken:bool = false
	var saw_repair:bool = false
	var contact_staged:bool = false
	var saw_rail:bool = false
	var peak_speed:float = 0.0
	var elapsed:float = 0.0
	while elapsed < 19.0:
		if elapsed>=next_runner_action:
			runner.player_control_action(1) # An actual enemy action start, not a direct Warden trigger.
			next_runner_action+=1.2
		# Keep the audible runner in range of the freely roaming shrieker, not its old spawn point.
		var desired:Vector2 = w.global_position+Vector2.RIGHT.rotated(elapsed*0.42)*145.0
		runner.set_player_control_direction(Vector2.ZERO if w.sonic_left > 0.0 else runner.global_position.direction_to(desired))
		await create_timer(0.1).timeout
		elapsed += 0.1
		saw_warning = saw_warning or ((w.alert_level > 0 or w.probe_left > 0) and w.form == 0)
		saw_emerge = saw_emerge or w.form == 1
		saw_awake = saw_awake or w.form == 2
		saw_broken = saw_broken or sword.is_broken()
		saw_repair = saw_repair or sword.repairing
		if elapsed > 8.0 and sword.is_broken() and not contact_staged:
			contact_staged = true
			# A staging teleport must not compete with an existing map-rescue tween.
			var contacts:Array = sword.workbench.living_pieces()
			for piece:Node2D in contacts: piece.state_machine.set_physics_process(false)
			print("WOOD_FIXTURE_RESCUE ",sword.get_meta("map_rescue_animating",false))
			for settle:int in range(20):
				if not contacts.any(func(p:Node2D): return bool(p.get_meta("map_rescue_animating",false))): break
				await create_timer(0.05).timeout
			for piece:Node2D in sword.workbench.living_pieces():
				piece.dock_delay = 0.0
				piece.global_position = sword.workbench.global_position+Vector2(-10 if piece == sword else 10,0)
				piece.velocity = Vector2.ZERO
				piece.Repel = Vector2.ZERO
				piece.state_machine.set_physics_process(true)
		saw_rail = saw_rail or (is_instance_valid(cart.rails) and not cart.rails.rails.is_empty())
		peak_speed = maxf(peak_speed,cart.drive_speed)
		if elapsed > 5.0 and elapsed < 5.11:
			var clocks:Vector3 = Vector3(moss.clock,sword.clock,w.clock)
			game.now_stop_state = true
			await create_timer(0.3).timeout
			check(clocks == Vector3(moss.clock,sword.clock,w.clock),"real runtime combat pause freezes all new character clocks")
			game.now_stop_state = false
	check(moss.growth_count > 0 and moss.patches.size() <= moss.growth_count*6,"live moss autonomously cultivates bounded terrain")
	check(moss_target.health < 10000,"live stacked moss damages the actual nearby target")
	check(sword_target.health < 10000,"live wooden sword autonomously charges and strikes")
	check(saw_broken and saw_repair and sword.successful_repairs > 0,"live worn sword breaks; staged natural contact then channels and recrafts on real physics ticks")
	check(saw_warning and saw_emerge and saw_awake and w.summons > 0,"actual enemy motion/actions produce alert, five returning probe signals, and emergence")
	check(w.sonic_casts > 0 and runner.health < 10000,"live awakened Warden uses a real damaging sonic cast")
	check(saw_rail and peak_speed > 250 and cart.global_position.distance_to(cart_origin)>20,"live minecart builds lanes and gains momentum through real motion")
	check(cart_ledger.damage > 0.0 and cart.completed_routes > 0,"live cart damages its chosen enemy and finishes routes")
	check(cart.rails.rails.size() <= cart.RAILS.MAX_EDGES and moss.patches.size() <= moss.growth_count*6,"live arena resource counts stay bounded")
	print("FRONTIER LIVE: moss_damage=",10000-moss_target.health," sword_damage=",10000-sword_target.health," repairs=",sword.successful_repairs," signals=",w.signals_received," summons=",w.summons," sonic=",w.sonic_casts," runner_damage=",10000-runner.health," cart_damage=",cart_ledger.damage," peak_speed=",peak_speed)
	finish(0 if failures == 0 else 1)
