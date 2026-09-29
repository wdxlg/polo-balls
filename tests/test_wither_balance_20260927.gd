extends "res://tests/test_skull_trail_combo.gd"
## Production Wither/skull damage and real controls, with isolated passive fixtures.
class BalanceArena extends FlightArena:
	var _mc_placement_generation:int = 0

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	arena = BalanceArena.new()
	root.add_child(arena)
	current_scene = arena
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	evidence = OS.get_environment("ELYTRA_EVIDENCE_DIR")
	if evidence.is_empty(): evidence = "user://wither_balance"
	DirAccess.make_dir_recursive_absolute(evidence)
	create_timer(80,true,false,true).timeout.connect(func(): failures+=1; finish())
	var source:Node2D = actor("凋灵",Vector2(-180,0))
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
		check(is_equal_approx(skull.get_ai_hazard_info().damage,50.0*factor),"head threat reads live 50-base damage at attack "+str(attack))
		skull._physics_process(0.5)
		check(skull.exploded and is_equal_approx(hp-direct.health,50.0*factor),"physical head collision settles 50 direct, not direct plus splash, at attack "+str(attack))
		check(is_equal_approx(splash_hp-splash.health,25.0*factor),"same actual explosion settles 25 splash at attack "+str(attack))
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
		check(is_equal_approx(source.get_ai_attack_threats(direct)[0].damage,100.0*factor),"charge threat uses current 100-base damage at attack "+str(attack))
		source.tick_physics(source.State.Stand,0.4)
		check(is_equal_approx(hp-direct.health,100.0*factor),"real swept charge deals 100 base at attack "+str(attack))
		hp = direct.health
		source.tick_physics(source.State.Stand,0.04)
		check(direct.health==hp,"charge retains per-target hit de-duplication")
		source._charge_remaining = 0.0
		source.global_position = Vector2(-180,0)
		direct.global_position = Vector2.ZERO
		splash.global_position = Vector2(0,48)
		await physics_frame
	source.Damage = 75
	direct.Damage_reduction = 1.0
	var hp:float = direct.health
	source._blast(direct.global_position,64.0,25.0,direct,true)
	check(direct.health==hp,"head still respects recipient damage reduction")
	direct.Damage_reduction = 0.0
	hp = direct.health
	source._blast(direct.global_position,source.AWAKENING_BLAST_RADIUS,45.0,null,false)
	check(is_equal_approx(hp-direct.health,45.0),"awakening blast is a separate unchanged 45-base ability")
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
			check(summary.contains("50") and summary.contains("25") and summary.contains("100") and not summary.to_lower().contains("rose") and not summary.contains("玫瑰"),"current "+locale+" skill description has new values and no flower")
		game.current_locale = old_locale
	else: check(false,"Wither supplies current bilingual ability descriptions")
	print("WITHER_BALANCE_RESULT checks=",checks," failures=",failures)
	finish()
