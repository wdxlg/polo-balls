extends "res://tests/test_sulfur_tuning.gd"
## Real Move/Stand and real wall-contact signals, plus deterministic combat-time boundaries.
const DT:float = 1.0/60.0
var PULL:Script
var PAIRS:Script

func held() -> bool:
	return source.honey_target_paths.has(str(source.get_path_to(victim)))

func grab(companion:int = 0,offset:Vector2 = Vector2(5,0)) -> void:
	source.set_block(source.Block.EMPTY)
	source.set_block(source.Block.HONEY)
	if companion != source.Block.EMPTY: source.acquire_block(companion)
	source.global_position = origin
	source._actual_speed = 0.0
	source._iron_down_speed = 0.0
	source.Damage = 48.0
	source.Can_Attack = true
	source.dizziness = false
	victim.global_position = origin+offset
	victim.Repel = Vector2.ZERO
	victim.surface_motion_velocity = Vector2.ZERO
	victim.clear_external_directional_gravity_velocity()
	victim.player_control_direction = Vector2.RIGHT
	victim.Damage_reduction = 0.0
	victim.block = 0.0
	source._pull_touching_enemies(0.0)

func run() -> void:
	create_timer(120.0,true,false,true).timeout.connect(func(): print("HONEY_GRAB_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	var stopped:bool = game.now_stop_state
	game.now_stop_state = false
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	AudioServer.set_bus_mute(0,true)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.set_process(false)
	world.set_physics_process(false)
	origin = world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	source = fighter("TimedHoneySource",origin,true)
	source.set_process(false)
	source.Damage = 48.0
	source.default_properties.Damage = 48.0
	victim = fighter("TimedHoneyVictim",origin+Vector2(5,0))
	victim.scale = Vector2.ONE
	victim.collision_mask = 1
	victim.fire_effect_ratio = 0.0
	victim.cold_effect_ratio = 0.0
	PULL = source.KNOCKBACK_EFFECT_SCRIPT
	PAIRS = source.BODY_PAIRS
	wall = StaticBody2D.new()
	wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10,180)
	shape.shape = rect
	wall.add_child(shape)
	world.add_child(wall)
	wall.global_position = origin+Vector2(100,0)
	await physics_frame

	grab()
	check(held() and PAIRS.are_excluded(source,victim),"fresh enemy contact acquires one pair-only honey grab")
	check(victim.Repel.is_zero_approx() and not victim.has_meta("generic_motion_lock_count"),"capture neither accumulates Repel nor locks voluntary controls")
	source._pull_touching_enemies(0.99)
	check(held(),"grab remains active before one combat second")
	source._pull_touching_enemies(0.01)
	check(not held(),"grab expires at one second even when the enemy is still touching")
	check(not PAIRS.are_excluded(source,victim) and not victim.wall_contact_impact.is_connected(source._on_honey_wall_impact.bind(victim)),"expiry releases collision lease and wall callback together")
	for i:int in range(20): source._pull_touching_enemies(DT)
	check(not held(),"continuous contact cannot instantly reattach after expiry")
	victim.global_position = origin+Vector2(100,0)
	source._pull_touching_enemies(DT)
	victim.global_position = origin+Vector2(5,0)
	source._pull_touching_enemies(DT)
	check(held(),"leaving and re-entering contact rearms a fresh grab")
	grab()
	source._pull_touching_enemies(0.6)
	game.now_stop_state = true
	source._pull_touching_enemies(5.0)
	game.now_stop_state = false
	source._pull_touching_enemies(0.39)
	check(held(),"pause does not consume the grab's combat-time budget")
	source._pull_touching_enemies(0.011)
	check(not held(),"the same paused grab still expires after its remaining combat time")
	grab()
	source._pull_touching_enemies(0.75)
	source.acquire_block(source.Block.ICE)
	source._pull_touching_enemies(0.25)
	check(not held() and source.has_block(source.Block.HONEY),"moving honey to the retained slot does not reset an active grab timer")
	grab()
	source.set_multiplayer_authority(2)
	source._pull_touching_enemies(2.0)
	source.set_multiplayer_authority(1)
	source._pull_touching_enemies(0.99)
	check(held(),"replica execution cannot advance authoritative grab duration")
	source._pull_touching_enemies(0.01)
	check(not held(),"authority resumes and releases its own timed grab")

	for rate:int in [30,60,120]:
		grab()
		for i:int in range(rate-1): source._pull_touching_enemies(1.0/float(rate))
		check(held(),"grab remains active on the last subsecond tick at %d Hz" % rate)
		source._pull_touching_enemies(1.0/float(rate))
		check(not held(),"one-second deadline is independent of %d Hz refresh frequency" % rate)
	grab()
	source._pull_touching_enemies(0.6)
	var late:Node2D = fighter("LaterHoneyVictim",origin+Vector2(-5,0))
	source._pull_touching_enemies(0.0)
	var late_path:String = str(source.get_path_to(late))
	source._pull_touching_enemies(0.4)
	check(not held() and source.honey_target_paths.has(late_path),"staggered victims have independent one-second capture clocks")
	late.free()
	source._sync_honey_collision_pairs()
	check(source.honey_target_paths.is_empty(),"removed victim is pruned from authoritative replicated membership immediately")

	# Actual voluntary movement must overcome the pull, not just a single Repel assertion.
	var radius:float = source.get_crowd_separation_radius_world()+victim.get_crowd_separation_radius_world()
	grab(0,Vector2(radius-2.0,0))
	var start:Vector2 = victim.global_position
	var first_velocity:float = 0.0
	var escaped_at:float = -1.0
	for i:int in range(18):
		await physics_frame
		source._pull_touching_enemies(DT)
		victim.move(300.0/victim.CHARACTER_BASE_MOVE_SPEED_MULTIPLIER,DT)
		if i==0: first_velocity = victim._last_requested_velocity.x
		source._pull_touching_enemies(0.0)
		if not held():
			escaped_at = float(i+1)*DT
			break
	print("HONEY_ESCAPE requested_first=",first_velocity," seconds=",escaped_at," dx=",victim.global_position.x-start.x)
	check(first_velocity > 0.0 and victim.global_position.x > start.x,"300 world-speed voluntary movement really moves outward against the 170 pull")
	check(escaped_at > 0.0 and escaped_at < 1.0 and victim.global_position.x > start.x and not PAIRS.are_excluded(source,victim),"a faster enemy escapes and loses the pair lease before the deadline")
	check(victim.Repel.is_zero_approx(),"successive pulls never build up hidden residual knockback")
	grab()
	var hp:float = victim.health
	for i:int in range(30):
		await physics_frame
		source._pull_touching_enemies(DT)
		victim.move(70.0/victim.CHARACTER_BASE_MOVE_SPEED_MULTIPLIER,DT)
	check(held() and source.global_position.distance_to(victim.global_position)<radius,"slower voluntary movement stays within a live grab without a position lock")
	check(victim.health==hp and victim.player_control_direction==Vector2.RIGHT and not victim.dizziness and not victim.has_meta("generic_motion_lock_count"),"pure honey remains harmless and never disables the victim's controls")
	grab(0,Vector2(10,0))
	await physics_frame
	source._pull_touching_enemies(DT)
	start = victim.global_position
	victim.stand(DT)
	check(victim.global_position.x < start.x and is_equal_approx(victim._last_requested_velocity.x,-170.0),"shared Stand motion also applies one bounded pull through actual physics")

	grab()
	var push:Node = victim.apply_knockback(Vector2.RIGHT,200.0,500.0,0.0,0.0,{"source":source,"lock_control":false,"smooth_motion":false,"control_recovery_time":0.0})
	push.set_physics_process(false)
	var independent:Vector2 = victim.Repel
	for i:int in range(10): source._pull_touching_enemies(0.02)
	check(victim.Repel==independent and knockback(victim)==push and push.is_active_effect(),"honey refresh never replaces or overwrites an unrelated shared knockback")
	source.set_block(source.Block.EMPTY)
	check(victim.Repel==independent and push.is_active_effect(),"releasing honey preserves the existing knockback controller")
	push.queue_free()
	await process_frame
	await test_shared_pull()

	# A fast victim may separate and hit terrain within its own physical step,
	# before the caster has another chance to poll contacts.
	wall.global_position = origin+Vector2(50,0)
	grab(source.Block.ICE,Vector2(radius-2.0,0))
	await physics_frame
	source._pull_touching_enemies(DT)
	hp = victim.health
	victim.move(680.0/victim.CHARACTER_BASE_MOVE_SPEED_MULTIPLIER,DT)
	check(victim.get_slide_collision_count()>0 and source.global_position.distance_to(victim.global_position)>radius+0.5,"victim really separates and hits a wall in the same Move step")
	check(victim.health==hp and not held() and not PAIRS.are_excluded(source,victim),"same-step escape releases the stale grab before its wall signal can cause damage")
	wall.global_position = origin+Vector2(100,0)

	# Each case is a genuine wall collision with the common normal-speed event.
	for companion:int in [source.Block.EMPTY,source.Block.MAGMA,source.Block.AMETHYST,source.Block.ICE,source.Block.IRON]:
		grab(companion)
		for speed:float in [85.0,170.0,340.0]:
			var expected:float = 0.0
			if companion==source.Block.ICE: expected = 30.0*speed/170.0
			if companion==source.Block.IRON: expected = floorf(48.0*1.2075*speed/170.0)
			var loss:float = await wall_hit(speed)
			check(loss==expected,"wall carrier trait %d at speed %s damages the plain grabbed victim by %s" % [companion,speed,expected])
			var threats:Array = source.get_ai_attack_threats(victim).filter(func(t:Dictionary): return t.get("kind","")=="sulfur_honey_wall_impact")
			check((threats.is_empty() if expected==0.0 else threats.size()==1 and is_equal_approx(threats[0].damage,expected)),"wall threat uses only the active retained trait's real impact formula")
		print("HONEY_WALL_VERIFIED trait=",companion," speeds=85,170,340")
	grab(source.Block.IRON)
	source.Damage = 96.0
	check(await wall_hit(170.0)==115.0,"carried iron wall hit reads current attacker damage and floors before settlement")
	source.Damage = 48.0
	victim.Damage_reduction = 0.5
	check(await wall_hit(170.0)==29.0,"carried iron remains ordinary damage with normal target reduction and rounding")
	grab(source.Block.ICE)
	source.Damage = 96.0
	check(await wall_hit(170.0)==60.0,"carried ice reads current attacker damage")
	source.Damage = 48.0
	victim.Damage_reduction = 0.5
	check(await wall_hit(170.0)==15.0,"carried ice is ordinary physical damage even against fire/cold immunity")
	victim.Damage_reduction = 0.0
	check(await wall_hit(85.0,170.0)==15.0,"tangential sliding does not inflate the wall's inward collision speed")
	hp = victim.health
	for i:int in range(5):
		await physics_frame
		victim._last_requested_velocity = Vector2(170,0)
		victim.velocity = Vector2(170,0)
		victim.move_and_slide()
		victim._process_wall_hit_bursts_from_slide_collisions(170)
	check(victim.health==hp,"retained-trait wall damage cannot repeat during uninterrupted wall pressure")
	for gate:String in ["pause","replica","friendly","stun","attack_disabled","expiry","escape","form_loss"]:
		grab(source.Block.ICE)
		if gate=="pause": game.now_stop_state = true
		if gate=="replica": source.set_multiplayer_authority(2)
		if gate=="friendly": victim.Team = source.Team
		if gate=="stun": source.dizziness = true
		if gate=="attack_disabled": source.Can_Attack = false
		if gate=="expiry": source._pull_touching_enemies(1.0)
		if gate=="escape":
			victim.global_position = origin+Vector2(100,0)
			source._pull_touching_enemies(DT)
		if gate=="form_loss": source.set_block(source.Block.ICE)
		hp = victim.health
		source._on_honey_wall_impact(170.0,victim.global_position,victim)
		check(victim.health==hp,gate+" blocks retained-trait wall settlement")
		game.now_stop_state = false
		source.set_multiplayer_authority(1)
		victim.Team = "Team1"
	grab(source.Block.IRON)
	source._iron_down_speed = 0.0
	hp = victim.health
	source._iron_bottom_contacts()
	check(victim.health==hp,"carried iron wall damage does not restore stationary underside crush")
	source.acquire_block(source.Block.ICE)
	check(not held() and not PAIRS.are_excluded(source,victim),"FIFO eviction of honey clears the grab while preserving both combat traits")
	grab()
	victim.health = 0.0
	source._pull_touching_enemies(DT)
	check(not held() and not PAIRS.are_excluded(source,victim),"victim death releases its active pair and replicated membership")
	victim.health = 4000.0
	grab()
	source.health = 0.0
	source._sync_honey_collision_pairs()
	check(not PAIRS.are_excluded(source,victim) and not victim.wall_contact_impact.is_connected(source._on_honey_wall_impact.bind(victim)),"source death releases both collision and callback resources")
	source.health = 4000.0
	grab()
	source.free()
	check(not victim.has_meta(PAIRS.META),"source deletion leaves no collision lease metadata on the victim")
	if PULL.has_method("pull_velocity"):
		check(PULL.pull_velocity(victim).is_zero_approx() and not victim.has_meta(PULL.PULL_META),"source deletion leaves no pull contribution on the victim")
	world.queue_free()
	await process_frame
	await create_timer(0.3,true,false,true).timeout
	game.Game_Settings = saved
	game.now_stop_state = stopped
	print("SULFUR_HONEY_GRAB checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)

func test_shared_pull() -> void:
	check(PULL.has_method("set_pull"),"shared movement library exposes a non-exclusive pull lease rather than a second knockback algorithm")
	if not PULL.has_method("set_pull"): return
	grab()
	source.set_block(source.Block.EMPTY)
	var a := Node.new()
	var b := Node.new()
	world.add_child(a)
	world.add_child(b)
	PULL.set_pull(victim,a,Vector2(30,0))
	PULL.set_pull(victim,a,Vector2(40,0))
	check(PULL.pull_velocity(victim)==Vector2(40,0),"refreshing one source replaces its bounded contribution rather than accumulating it")
	PULL.set_pull(victim,b,Vector2(0,20))
	check(PULL.pull_velocity(victim)==Vector2(40,20),"independent holders retain independent contributions")
	PULL.release_pull(victim,a)
	check(PULL.pull_velocity(victim)==Vector2(0,20),"one holder cannot cancel another holder's force")
	b.free()
	check(PULL.pull_velocity(victim).is_zero_approx() and not victim.has_meta(PULL.PULL_META),"deleted holder is pruned without residual force or metadata")
	PULL.set_pull(victim,a,Vector2(30,0))
	for i:int in range(4): await physics_frame
	check(PULL.pull_velocity(victim).is_zero_approx(),"unrefreshed pull cannot outlive a stopped producer")
	victim.set_multiplayer_authority(2)
	check(not PULL.set_pull(victim,a,Vector2(30,0)),"shared pull cannot drive a non-authoritative body")
	victim.set_multiplayer_authority(1)
	game.now_stop_state = true
	check(not PULL.set_pull(victim,a,Vector2(30,0)) and PULL.pull_velocity(victim).is_zero_approx(),"pause suppresses pull without applying extra motion")
	game.now_stop_state = false
	var immune:Node2D = load("res://scenes/characters/我的世界/蝙蝠.tscn").instantiate()
	immune.Team = "Team1"
	immune.initial_count = 1
	immune.position = origin+Vector2(1000,0)
	world.add_child(immune)
	immune.state_machine.set_physics_process(false)
	immune.set_physics_process(false)
	immune._attached_ref = weakref(source)
	source.block = 0.0
	check(immune.is_knockback_displacement_immune() and not PULL.set_pull(immune,source,Vector2(30,0)),"shared pull respects the real feeding bat's displacement immunity")
	immune.queue_free()
	PULL.set_pull(victim,source,Vector2(30,0))
	source.set_multiplayer_authority(2)
	check(PULL.pull_velocity(victim).is_zero_approx(),"losing source authority invalidates an outstanding pull before the next refresh")
	source.set_multiplayer_authority(1)
	a.free()
