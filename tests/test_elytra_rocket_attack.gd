extends "res://tests/test_elytra_return_dash.gd"
## Real shared rocket integration + production swept spear contacts.
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	arena = FlightArena.new()
	root.add_child(arena)
	current_scene = arena
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	create_timer(90,true,false,true).timeout.connect(func(): failures+=1; finish())
	for role:String in ["鞘翅长矛","鞘翅重锤长矛"]:
		var unit:Node2D = actor(role,Vector2(-140,0))
		var enemy:Node2D = victim(Vector2(20,0))
		unit._pvp_target = enemy
		prime(unit,Vector2(-140,0),Vector2.RIGHT*240)
		unit._rocket_cooldown = 0.0
		var hp:float = enemy.health
		unit._step_glide(1.0/60.0)
		check(unit._pierce_dashing and unit._rocket_remaining>0.0,role+": aligned AI attack ignites actual rocket fuel")
		check(unit._glide_velocity.length()>unit.pierce_dash_min_speed,role+": rocket acceleration increases speed beyond the dash impulse")
		check(unit._rocket_cooldown>0.0 and unit._boost_direction.dot(Vector2.RIGHT)>0.99,role+": real rocket cooldown and enemy-facing propulsion are active")
		check(is_instance_valid(unit._firework_trail),role+": same native rocket trail is retained")
		for frame:int in range(35):
			unit._step_glide(1.0/60.0)
			if enemy.health<hp: break
		check(enemy.health<hp and unit.last_contact_speed>unit.pierce_dash_min_speed,role+": faster real flight reaches and pierces the enemy")
		check(is_equal_approx(unit.last_contact_damage,unit.flight_damage_at_speed(unit.last_contact_speed,true)),role+": damage uses actual rocket-boosted contact speed")
		check(unit._glide_velocity.length()<=unit.maximum_flight_speed+0.01,role+": rocket plus hit reward still respects the shared speed cap")
		check(not unit._airborne,role+": boosted pass is not replaced by an immediate mace rebound")
		var hp_after:float = enemy.health
		unit._sweep_spear_contacts(unit.global_position,unit.global_position,unit.spear_tip_world_position(),unit.spear_tip_world_position())
		check(enemy.health==hp_after,role+": rocket does not add a second damage layer to an existing contact")
		var fuel:float = unit._rocket_remaining
		var point:Vector2 = unit.global_position
		game.now_stop_state = true
		unit._step_glide(0.1)
		check(unit._rocket_remaining==fuel and unit.global_position==point,role+": pause freezes fuel and movement")
		game.now_stop_state = false
		unit.dizziness = true
		unit._step_glide(0.01)
		check(not unit._pierce_dashing and unit._rocket_remaining==0.0,role+": interrupted attack stops its remaining rocket thrust")
		unit.free()
		enemy.free()
		await process_frame
		unit = actor(role,Vector2(-140,0))
		enemy = victim(Vector2(20,0))
		prime(unit,Vector2(-140,0),Vector2.RIGHT*240)
		unit._pvp_target = enemy
		unit._rocket_cooldown = 0.04
		check(unit.try_pierce_dash(enemy) and unit._rocket_remaining==0.0,role+": dash cannot bypass an existing rocket cooldown")
		for i:int in range(4): unit._step_glide(1.0/60.0)
		check(unit._rocket_remaining>0 and unit._glide_velocity.length()>560,role+": AI can ignite when the rocket becomes ready during an attack")
		unit._finish_pierce_dash(false)
		prime(unit,Vector2(-140,0),Vector2.RIGHT*240)
		unit.player_control_peer_id = 1
		unit.player_control_direction = Vector2.UP
		unit.player_control_aim_valid = true
		unit.player_control_aim_position = Vector2(100,0)
		unit._rocket_cooldown = 0.5
		unit.player_control_action(0)
		check(unit._pierce_dashing and unit._rocket_remaining==0.0,role+": manual dash preserves separate rocket cooldown")
		unit.player_control_action(1)
		check(unit._rocket_remaining==0.0,role+": RMB cannot spam fuel while cooling down")
		unit._rocket_cooldown = 0.0
		check(not unit._wants_tactical_firework(enemy,Vector2.RIGHT),role+": AI never presses the manual player's firework button")
		unit.player_control_aim_position = unit.global_position+Vector2.UP*100
		unit.player_control_action(1)
		check(unit._rocket_remaining>0 and unit._boost_direction.dot(Vector2.RIGHT)>0.99,role+": RMB can ignite mid-pass along the committed attack heading")
		check(unit.player_control_direction==Vector2.UP,role+": rocket ignition does not overwrite WASD")
		unit._finish_pierce_dash(false)
		unit._rocket_cooldown = 0.0
		unit.Can_Skill = false
		unit.player_control_action(1)
		check(unit._rocket_remaining==0.0,role+": disabled skill cannot ignite")
		unit.Can_Skill = true
		unit.set_multiplayer_authority(2)
		unit.player_control_action(1)
		check(unit._rocket_remaining==0.0,role+": non-authority cannot ignite or integrate propulsion")
		unit.free()
		enemy.free()
		await process_frame
	print("ELYTRA_ROCKET_ATTACK checks=",checks," failures=",failures)
	await finish()
