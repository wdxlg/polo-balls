extends SceneTree
var checks:int = 0
var failures:int = 0
var arena:Node2D
var game:Node
func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ",label)
	if not ok: failures += 1
func victim(point:Vector2,team:String="Team1") -> Node2D:
	var node:Node2D = load("res://scenes/ball.tscn").instantiate()
	node.Team = team
	node.Max_health = 10000
	node.Health_Restore = 0
	node.Has_Collision_Damage = false
	arena.add_child(node)
	node.global_position = point
	return node
func prepare(spear:Node2D,point:Vector2,motion:Vector2) -> void:
	spear.Can_Skill = false # Isolate the original contact/flight contracts from the newly added active dash.
	spear.global_position = point
	spear._glide_velocity = motion
	spear.velocity = motion
	spear.Repel = Vector2.ZERO
	spear.glide_gravity = 0.0
	spear.glide_drag = 0.0
	spear._rocket_cooldown = 100.0
	spear._rocket_remaining = 0.0
	spear._poke_retreat_left = 0.0
	spear._spear_contacts.clear()
	spear._flight_tactic = spear.FlightTactic.INTERCEPT
	spear._tactic_hold = 100.0
	spear.Can_Attack = true
	spear._face_flight_direction()
func run() -> void:
	create_timer(60.0).timeout.connect(func(): push_error("ELYTRA_SPEAR_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	game.now_stop_state = false
	game.Game_Settings.Have_Team_Damage = false
	AudioServer.set_bus_mute(0,true)
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	var scene:PackedScene = load("res://scenes/characters/我的世界/鞘翅长矛.tscn")
	check(scene!=null,"new scene loads")
	var spear:Node2D = scene.instantiate()
	spear.Team = "Team0"
	arena.add_child(spear)
	check(spear.Max_health==200 and spear.health==200,"200 health")
	check(spear.get_preview_texture()==spear.SPEAR_TEXTURE and spear.image.texture==spear.SPEAR_TEXTURE,"netherite spear in selector and gameplay")
	check(spear.collision_layer==0 and spear.collision_mask==0,"same wall-free flight contract as elytra mace")
	check(spear.self_hurtbox.collision_layer!=0,"flight remains damageable")
	check(bool(spear.get_meta("submission_allow_map_escape",false)),"map escape exemption inherited")
	check(spear.get_node_or_null("CharacterGroundShadow")==null,"no ground shadow")
	check(spear.has_node("Graphics/Elytra/Left") and spear.has_node("Graphics/Elytra/Right"),"animated elytra wings inherited")
	check(spear.has_node("FireworkAudio") and spear.has_node("GlideAudio"),"flight and firework audio inherited")
	check(not spear.is_in_group("MinecraftMace") and spear.is_in_group("MinecraftElytraSpear"),"not registered as a mace")
	check(spear.get("_current_move_speed")==null and spear.get("move_acceleration_per_second")==null,"no wooden spear acceleration or stored speed state")
	check(spear.get_next_state(spear.State.Stand)==spear.State.Move,"uses continuous flight state rather than mace attack state")

	var enemy:Node2D = victim(Vector2.ZERO)
	spear._pvp_target = enemy
	prepare(spear,Vector2(0,-50),Vector2.DOWN*120.0)
	var before:int = enemy.health
	spear._step_glide(0.5)
	var slow_damage:int = before-enemy.health
	check(slow_damage>0 and spear.last_contact_mode==&"poke","low speed makes a real jab")
	check(spear.global_position.y<enemy.global_position.y and spear._glide_velocity.y<0,"low speed turns away without passing through")
	check(absf(spear._glide_velocity.length()-180.0)<0.01,"jab adds 60 speed and retains it after turning away")
	check(enemy.Repel.length()>0.0,"low-speed jab nudges the enemy")
	check(not spear._airborne and spear._chain_damage_multiplier==0,"jab does not start a mace rebound/combo")

	enemy.Repel = Vector2.ZERO
	prepare(spear,Vector2(0,-100),Vector2.DOWN*600.0)
	before = enemy.health
	var flight_start:Vector2 = spear.global_position
	var tip_start:Vector2 = spear.spear_tip_world_position()
	spear._step_glide(0.3)
	var fast_damage:int = before-enemy.health
	check(fast_damage>slow_damage and spear.last_contact_mode==&"pierce","higher speed increases damage and enables piercing")
	check(spear.global_position.y>enemy.global_position.y+30,"high-speed spear physically passes the target")
	check(absf(spear._glide_velocity.length()-750.0)<0.01,"piercing adds 150 speed without changing heading")
	check(enemy.Repel.is_zero_approx(),"piercing does not carry or drag the target")
	before = enemy.health
	spear._sweep_spear_contacts(flight_start,spear.global_position,tip_start,spear.spear_tip_world_position())
	check(enemy.health==before,"same pass cannot deal duplicate damage")
	check(absf(spear._glide_velocity.length()-750.0)<0.01,"same pass cannot grant duplicate speed rewards")
	check(spear.last_contact_speed==600.0 and is_equal_approx(spear.last_contact_damage,spear.flight_damage_at_speed(600.0,true)),"current hit damage uses pre-reward speed")
	check(spear.velocity.is_equal_approx(spear._glide_velocity+spear.Repel),"public velocity immediately matches boosted flight")
	check(not spear._airborne and not spear.Attacking,"piercing never starts mace animations")
	check(spear.flight_damage_at_speed(900,true)>spear.flight_damage_at_speed(600,true),"damage keeps increasing above the wooden spear speed cap")
	prepare(spear,Vector2(0,-36),Vector2.DOWN*400)
	before = enemy.health
	spear._step_glide(0.016)
	var initial_pass_damage:int = before-enemy.health
	var heading_held:bool = true
	for i:int in range(5):
		spear._step_glide(0.016)
		heading_held = heading_held and spear._glide_velocity.y>399.0
	check(initial_pass_damage>0 and heading_held,"high-speed contact holds forward heading until clear")
	check(before-enemy.health==initial_pass_damage,"multi-frame overlap hits once, not every tick")
	check(absf(spear._glide_velocity.length()-550.0)<0.01,"multi-frame overlap boosts once and never adds post-pass braking")

	var second:Node2D = victim(Vector2(0,50))
	prepare(spear,Vector2(0,-100),Vector2.DOWN*500.0)
	before = enemy.health
	var second_before:int = second.health
	spear._step_glide(0.4)
	check(enemy.health<before and second.health<second_before,"one fast sweep can pierce multiple aligned enemies")
	check(absf(spear._glide_velocity.length()-800)<0.01,"two different targets each grant a 150 speed reward")
	second.free()
	prepare(spear,Vector2(0,-100),Vector2.DOWN*850)
	spear._step_glide(0.2)
	check(is_equal_approx(spear._glide_velocity.length(),900.0),"hit reward respects inherited 900 speed cap")
	prepare(spear,Vector2(0,-100),Vector2.DOWN*900)
	spear._step_glide(0.2)
	check(is_equal_approx(spear._glide_velocity.length(),900.0),"a hit at the cap never slows flight")
	prepare(spear,Vector2(0,-50),Vector2.DOWN*330)
	spear._step_glide(0.2)
	check(spear.last_contact_mode==&"poke" and spear._glide_velocity.y<0 and is_equal_approx(spear._glide_velocity.length(),390.0),"threshold-crossing jab keeps its poke behavior and gains speed")
	check(spear._glide_velocity.length()>spear.AfterImage_Speed,"jab acceleration can enter the high-speed trail range")
	enemy.Damage_reduction = 1.0
	prepare(spear,Vector2(0,-100),Vector2.DOWN*600)
	before = enemy.health
	spear._step_glide(0.3)
	check(enemy.health==before and is_equal_approx(spear._glide_velocity.length(),600.0),"rejected damage grants no speed reward")
	enemy.Damage_reduction = 0.0
	enemy.health = 1
	prepare(spear,Vector2(0,-50),Vector2.DOWN*120)
	spear._step_glide(0.5)
	check(enemy.health<=0 and is_equal_approx(spear._glide_velocity.length(),180.0),"lethal jab still grants a single speed reward")
	enemy.health = 10000
	prepare(spear,Vector2(0,-100),Vector2.DOWN*600)
	spear.set_multiplayer_authority(2)
	before = enemy.health
	check(not spear._apply_spear_contact(enemy,Vector2.ZERO,Vector2.DOWN,600,true) and enemy.health==before and is_equal_approx(spear._glide_velocity.length(),600.0),"remote replica cannot award damage or speed")
	spear.set_multiplayer_authority(1)

	var ally:Node2D = victim(Vector2(0,0),"Team0")
	enemy.global_position = Vector2(1000,0)
	spear._pvp_target = null
	prepare(spear,Vector2(0,-100),Vector2.DOWN*600)
	before = ally.health
	spear._sweep_spear_contacts(Vector2(0,-100),Vector2(0,100),Vector2(0,-85),Vector2(0,115))
	check(ally.health==before,"friendly fire off protects allies")
	check(is_equal_approx(spear._glide_velocity.length(),600.0),"allies grant no speed reward")
	ally.free()
	enemy.global_position = Vector2.ZERO
	spear._pvp_target = enemy
	prepare(spear,Vector2(0,-100),Vector2.DOWN*600)
	spear.Can_Attack = false
	before = enemy.health
	spear._step_glide(0.3)
	check(enemy.health==before,"attack-disabled flight does not hurt enemies")
	check(is_equal_approx(spear._glide_velocity.length(),600.0),"attack-disabled flight grants no hit acceleration")
	prepare(spear,Vector2(0,-100),Vector2.DOWN*600)
	spear.dizziness = true
	spear._step_glide(0.3)
	check(enemy.health==before,"stun disables tip damage")
	check(is_equal_approx(spear._glide_velocity.length(),600.0),"stun grants no hit acceleration")
	spear.dizziness = false
	prepare(spear,Vector2(0,-100),Vector2.DOWN*600)
	var pos:Vector2 = spear.global_position
	game.now_stop_state = true
	spear._step_glide(0.3)
	check(spear.global_position==pos and enemy.health==before,"paused battle freezes flight and attacks")
	game.now_stop_state = false

	# Natural inherited flight AI, not only a pre-aligned synthetic sweep.
	for moving:bool in [false,true]:
		for offset:Vector2 in [Vector2(20,0),Vector2(-300,0),Vector2(300,0),Vector2(0,-300),Vector2(0,300)]:
			enemy.global_position = Vector2.ZERO
			enemy.velocity = Vector2(45,0) if moving else Vector2.ZERO
			enemy.Repel = Vector2.ZERO
			enemy.health = 10000
			prepare(spear,offset,Vector2(280,0))
			spear.glide_gravity = 135.0
			spear.glide_drag = 0.12
			spear._tactic_hold = 0.0
			spear._rocket_cooldown = 0.0
			spear._pvp_target = enemy
			for frame:int in range(900):
				enemy.global_position += enemy.velocity/60.0
				spear._step_glide(1.0/60.0)
				if enemy.health < 10000: break
			check(enemy.health<10000,"flight AI finds a spear-tip hit from %s moving=%s" % [offset,moving])
	enemy.free()
	spear._pvp_target = null
	prepare(spear,Vector2.ZERO,Vector2.RIGHT*200)
	spear.glide_drag = 0.12
	spear._step_glide(0.1)
	check(spear._glide_velocity.length()<200,"inherited flight drag remains")
	spear.glide_gravity = 135
	spear._glide_velocity = Vector2.ZERO
	spear._step_glide(0.1)
	check(spear._glide_velocity.y>0,"inherited gravity remains")
	spear._glide_velocity = Vector2.UP*200
	spear._use_firework(Vector2.UP)
	spear._step_glide(0.1)
	check(spear._glide_velocity.length()>200 and spear._rocket_remaining>0,"inherited firework propulsion still accelerates alongside hit rewards")
	spear._update_flight_media()
	check(spear.get_node("Graphics/Firework").visible,"inherited rocket visual plays")
	spear._update_wing_animation(0.1)
	check(spear.get_node("Graphics/Elytra/Left").rotation!=0,"inherited wings bank and spread")
	prepare(spear,Vector2(-2000,-2000),Vector2.UP*200)
	spear._step_glide(0.1)
	check(spear.global_position.y< -2000,"out-of-map flight remains allowed")
	check(spear.spear_tip_world_position().y<spear.global_position.y,"native spear tip faces the flight direction")
	before = spear.health
	spear.receive_positional_damage(10,spear.global_position,false,null)
	check(spear.health<before,"new flyer can actually take damage")
	spear._begin_flight(1)
	spear._finish_landing()
	spear.Attack()
	check(not spear._airborne and not spear.Attacking,"mace attack entry points are disabled")
	check(spear.get_debug_attack_regions()[0].kind=="elytra_spear_tip","debug threat shows spear tip instead of mace landing area")

	var catalog:Node = load("res://scripts/world.gd").new()
	check(catalog.return_all_character_names().has("鞘翅长矛"),"new character appears in real roster index")
	check(catalog._get_character_scene_any("鞘翅长矛")!=null,"roster resolves new scene")
	catalog.free()
	var mace:Node2D = load("res://scenes/characters/我的世界/鞘翅重锤.tscn").instantiate()
	arena.add_child(mace)
	check(mace.Max_health==200 and mace.image.texture!=spear.image.texture,"original elytra mace remains independent")
	print("ELYTRA_SPEAR_RESULT checks=",checks," failures=",failures)
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
