extends "res://tests/test_skull_trail_combo.gd"
## Production Wither/skull damage and real controls, with isolated passive fixtures.
class BalanceArena extends FlightArena:
	@warning_ignore("unused_private_class_variable")
	var _mc_placement_generation:int = 0

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	arena = BalanceArena.new()
	root.add_child(arena)
	current_scene = arena
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	create_timer(80,true,false,true).timeout.connect(func(): failures+=1; finish())
	for specialized:bool in [false,true]:
		var source:Node2D = load("res://scenes/characters/我的世界/凋灵.tscn").instantiate()
		if specialized: source.prepare_training_boss_specialization(1.0)
		source.Team = "Team0"
		arena.add_child(source,true)
		source.global_position = Vector2(-180,0)
		await verify_profile(source,specialized)
	print("WITHER_BALANCE_RESULT checks=",checks," failures=",failures)
	finish()

func verify_profile(source:Node2D,specialized:bool) -> void:
	var direct_base:float = 50.0 if specialized else 30.0
	var splash_base:float = 25.0 if specialized else 20.0
	var charge_base:float = 100.0 if specialized else 80.0
	var awakening_base:float = 120.0 if specialized else 80.0
	check(source.Type_Tags.has("Boss") and source.has_training_boss_specialization(),"Wither is tagged Boss and implements specialization")
	check(source.Max_health==(1000 if specialized else 500) and source.health==source.Max_health,"profile initializes full health before ready")
	source.summoned = true
	source._head_shot_left.fill(999.0)
	source._global_shot_left = 999.0
	source._charge_left = 999.0
	var direct:Node2D = victim(Vector2.ZERO)
	var splash:Node2D = victim(Vector2(0,48))
	var ally:Node2D = victim(Vector2(0,-40))
	ally.Team = source.Team
	var outside:Node2D = victim(Vector2(0,180))
	for target:Node2D in [direct,splash,ally,outside]: target.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	await physics_frame
	for attack:int in [75,150]:
		source.Damage = attack
		var factor:float = float(attack)/75.0
		var hp:float = direct.health
		var splash_hp:float = splash.health
		var ally_hp:float = ally.health
		var outside_hp:float = outside.health
		var skull:Node2D = new_skull(source,Vector2(-80,0))
		check(is_equal_approx(skull.get_ai_hazard_info().damage,direct_base*factor),"head threat reads profile damage at attack "+str(attack))
		skull._physics_process(0.5)
		check(skull.exploded and is_equal_approx(hp-direct.health,direct_base*factor),"physical head collision settles profile direct damage, not direct plus splash, at attack "+str(attack))
		check(is_equal_approx(splash_hp-splash.health,splash_base*factor),"same actual explosion settles profile splash at attack "+str(attack))
		check(ally.health==ally_hp and outside.health==outside_hp,"splash still excludes teammates and out-of-range bodies")
		check(direct.get_node_or_null("WitherStatus")!=null and splash.get_node_or_null("WitherStatus")!=null,"accepted skull hits retain original Wither status")
		check(not get_nodes_in_group("MCSmokeTrail").is_empty(),"actual balanced head retains native smoke trail")
		hp = direct.health
		skull._physics_process(0.1)
		check(direct.health==hp,"exploded projectile cannot repeat settlement")
		skull.free()
		source.global_position = Vector2(-140,80)
		direct.global_position = Vector2(-20,80)
		splash.global_position = Vector2(900,900)
		source._charge_dir = Vector2.RIGHT
		source._charge_remaining = 250.0
		source._charge_total_dist = 250.0
		source._charge_hits.clear()
		hp = direct.health
		check(is_equal_approx(source.get_ai_attack_threats(direct)[0].damage,charge_base*factor),"charge threat uses profile damage at attack "+str(attack))
		source.tick_physics(source.State.Stand,0.4)
		check(is_equal_approx(hp-direct.health,charge_base*factor),"real swept charge deals profile damage at attack "+str(attack))
		hp = direct.health
		source.tick_physics(source.State.Stand,0.04)
		check(direct.health==hp,"charge retains per-target hit de-duplication")
		source._charge_remaining = 0.0
		source._charge_left = 999.0
		source.global_position = direct.global_position-Vector2(40,0)
		source.summoned = false
		source.summon_time = 2.9
		hp = direct.health
		check(is_equal_approx(source.get_ai_attack_threats(direct)[0].damage,awakening_base*factor),"awakening threat uses profile and live attack")
		source.tick_physics(source.State.Stand,0.11)
		check(source.summoned and is_equal_approx(hp-direct.health,awakening_base*factor),"real awakening settles profile damage exactly once")
		hp = direct.health
		source.tick_physics(source.State.Stand,0.01)
		check(direct.health==hp,"awakening cannot repeat on following tick")
		source.global_position = Vector2(-180,0)
		direct.global_position = Vector2.ZERO
		splash.global_position = Vector2(0,48)
		await physics_frame
	source.Damage = 75
	direct.Damage_reduction = 1.0
	var hp:float = direct.health
	source._blast(direct.global_position,64.0,splash_base,direct,true)
	check(direct.health==hp,"head still respects recipient damage reduction")
	direct.Damage_reduction = 0.0
	hp = direct.health
	source._blast(direct.global_position,source.AWAKENING_BLAST_RADIUS,awakening_base,null,false)
	check(is_equal_approx(hp-direct.health,awakening_base),"awakening is separate from skull direct and splash damage")
	for cycle:int in range(8): source.tick_physics(source.State.Stand,4.0)
	check(get_nodes_in_group("WitherFlower").is_empty(),"32 seconds of autonomous ticking never grows removed roses")
	check(not source.has_method("_grow_rose") and not source.has_method("_try_grow_rose"),"rose spawning entry points are removed")
	check(source.player_control_action_ids()==[&"controlled_attack_action",&"controlled_skill_action"],"exactly two actions remain: skull then charge, no duplicate middle action")
	source.player_control_peer_id = 1
	source.player_control_direction = Vector2.UP
	source.player_control_aim_valid = true
	source.player_control_aim_position = source.global_position+Vector2(100,0)
	source._charge_left = 0.0
	source.player_control_action(1)
	check(source._charge_windup>0.0 and source._charge_dir==Vector2.RIGHT and source.player_control_direction==Vector2.UP,"right click starts aimed charge without changing WASD")
	source._charge_windup = 0.0
	source.player_control_action(1)
	check(source._charge_windup==0.0,"right click still respects charge cooldown")
	source._charge_left = 0.0
	game.now_stop_state = true
	source.player_control_action(1)
	check(source._charge_windup==0.0,"pause blocks manual charge")
	game.now_stop_state = false
	source.dizziness = true
	source.player_control_action(1)
	check(source._charge_windup==0.0,"stun blocks manual charge")
	source.dizziness = false
	source._head_shot_left.fill(0.0)
	source._global_shot_left = 0.0
	source.player_control_action(0)
	check(source._windup_head>=0 and source._manual_skull_windup,"left click retains original manual skull windup")
	if source.has_method("get_armor_test_effect_summary"):
		var old_locale:String = game.current_locale
		for locale:String in ["zh","en"]:
			game.current_locale = locale
			var summary:String = source.get_armor_test_effect_summary()
			check(summary.contains("30") and summary.contains("20") and summary.contains("80") and summary.contains("120") and summary.contains("350") and summary.contains("1000") and summary.contains("Boss") and not summary.to_lower().contains("rose") and not summary.contains("玫瑰"),"current "+locale+" skill description has new values and no flower")
		game.current_locale = old_locale
	else: check(false,"Wither supplies current bilingual ability descriptions")
	source.health = source.Max_health
	source.take_damage(source.Max_health*0.5-1.0)
	check(not source.heart_dropped and not is_instance_valid(source.beacon),"no beacon above half health")
	source.take_damage(1.0)
	check(source.heart_dropped==specialized and is_instance_valid(source.beacon)==specialized,"only specialized Wither summons at exact half health")
	if specialized:
		var beacon:Node2D = source.beacon
		check(beacon.Max_health==350 and beacon.health==350 and beacon.Master==source and beacon.Team==source.Team,"beacon starts with 350 health and correct ownership")
		source.health = source.Max_health
		source.take_damage(source.Max_health*0.5)
		check(source.beacon==beacon,"healing then crossing half health cannot summon twice")
		beacon.free()
	for target:Node2D in [direct,splash,ally,outside]: target.free()
	source.free()
	await process_frame
