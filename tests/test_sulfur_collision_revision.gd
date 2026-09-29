extends "res://tests/test_sulfur_cube_balance.gd"
## Exercise actual shared Move/Stand collisions and motion on the production ice controller.
var victim:Node2D
var origin:Vector2
const DT:float = 1.0/60.0

func real_ice_hit(heading:Vector2,speed:float,standing:bool = false,glance:float = 0.0) -> Dictionary:
	source.set_block(source.Block.ICE)
	source._next_hit_at.clear()
	source._slide_velocity = Vector2.ZERO
	source._actual_speed = 0.0
	source._ice_bounce_hold = 0.0
	source.surface_motion_velocity = Vector2.ZERO
	source.clear_external_directional_gravity_velocity()
	source.global_position = origin
	source.player_control_direction = -heading # Facing/aim must not gate body contacts.
	source.Speed = 0.0
	source.Repel = heading*speed
	var reach:float = source.get_crowd_separation_radius_world()+15.0
	var side:float = reach*glance
	victim.global_position = origin+heading*(sqrt(reach*reach-side*side)+0.5)+heading.orthogonal()*side
	source.force_update_transform()
	victim.force_update_transform()
	await physics_frame
	var hp:float = victim.health
	if standing: source.stand(DT)
	else: source.move(0.0,DT)
	return {"damage":hp-victim.health,"contacts":source.get_slide_collision_count(),"speed":source._last_requested_velocity.length()}

func run() -> void:
	create_timer(120.0,true,false,true).timeout.connect(func(): print("COLLISION_REVISION_TIMEOUT"); quit(2))
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
	source = fighter("CollisionRevisionCube",origin,true)
	source.set_process(false)
	source.Damage = 48.0
	source.default_properties.Damage = 48.0
	victim = fighter("CollisionRevisionVictim",origin+Vector2(45,0))
	victim.scale = Vector2.ONE
	victim.Damage_reduction = 0.0
	victim.block = 0.0
	victim.fire_effect_ratio = 0.0
	victim.cold_effect_ratio = 0.0
	await physics_frame
	for i:int in range(8):
		var result:Dictionary = await real_ice_hit(Vector2.RIGHT.rotated(float(i)*TAU/8.0),170.0)
		check(result.contacts>0,"ice makes a genuine body collision at direction %d" % i)
		check(result.damage==30.0,"ice body collision immediately deals 30 from direction %d regardless of aim" % i)
	for values:Vector2 in [Vector2(85,15),Vector2(170,30),Vector2(340,60),Vector2(680,120)]:
		var result:Dictionary = await real_ice_hit(Vector2.RIGHT,values.x)
		check(result.contacts>0 and result.damage==values.y,"actual incoming speed %s yields ordinary damage %s, not a 90 cap" % [values.x,values.y])
		var info:Array = source.get_ai_attack_threats(victim)
		check(info.size()==1 and is_equal_approx(info[0].damage,values.y),"ice threat reads the same pre-impact speed and formula as physical damage")
		print("ICE_REAL_IMPACT speed=",result.speed," damage=",result.damage)
		var hp:float = victim.health
		source._process_physical_contact_hits()
		source._pulse_contact()
		check(victim.health==hp,"physical fallback and polling do not double-hit one contact interval")
	check((await real_ice_hit(Vector2.DOWN,170.0,true)).damage==30.0,"shared Stand/external movement uses the same all-direction collision damage")
	var glancing:Dictionary = await real_ice_hit(Vector2.RIGHT,170.0,false,0.8)
	check(glancing.contacts>0,"grazing approach makes a real non-head-on body collision")
	check(glancing.damage==30.0,"glancing ice contact uses full speed rather than an angle/normal projection gate")
	source.Damage = 96.0
	check((await real_ice_hit(Vector2.RIGHT,170.0)).damage==60.0,"ice reads the attacker's current damage rather than hard-coding 30")
	source.Damage = 48.0
	victim.Damage_reduction = 0.5
	check((await real_ice_hit(Vector2.RIGHT,170.0)).damage==15.0,"ordinary ice collision still respects target reduction despite fire/cold immunity")
	victim.Damage_reduction = 0.0
	for gate:String in ["pause","replica","friendly","stun","attack_disabled"]:
		if gate=="pause": game.now_stop_state = true
		if gate=="replica": source.set_multiplayer_authority(2)
		if gate=="friendly": victim.Team = source.Team
		if gate=="stun": source.dizziness = true
		if gate=="attack_disabled": source.Can_Attack = false
		var result:Dictionary = await real_ice_hit(Vector2.RIGHT,170.0)
		check(result.damage==0.0,gate+" cannot settle ice collision damage")
		game.now_stop_state = false
		source.set_multiplayer_authority(1)
		victim.Team = "Team1"
		source.dizziness = false
		source.Can_Attack = true
	source.set_block(source.Block.ICE)
	source._actual_speed = 0.0
	source._next_hit_at.clear()
	victim.global_position = source.global_position+Vector2(source.get_crowd_separation_radius_world()+14.9,0)
	var hp:float = victim.health
	source._pulse_contact()
	check(victim.health==hp and source._mode_damage(source.Block.ICE)==0.0,"zero real speed cannot retain stale 90 damage on stationary overlap")
	check(not source.Has_Collision_Damage and is_equal_approx(source.AMETHYST_CONTACT_MULT,0.35) and is_equal_approx(source.SHARD.DAMAGE_MULT,0.23625),"generic shell hits stay disabled and the approved purple reduction remains intact")
	await check_turning()
	world.queue_free()
	await process_frame
	await create_timer(0.3,true,false,true).timeout
	game.Game_Settings = saved
	game.now_stop_state = stopped
	print("SULFUR_COLLISION_REVISION checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)

func check_turning() -> void:
	victim.global_position = origin-Vector2(1000,1000)
	source.set_block(source.Block.ICE)
	source.global_position = origin
	source.collision_mask = 2 # Isolate steering from walls; real body motion is unchanged.
	source.Repel = Vector2.ZERO
	source.Speed = 130.0
	source.default_properties.Speed = 130.0
	source._slide_velocity = Vector2.RIGHT*130.0
	source.player_control_direction = Vector2.RIGHT
	source._ice_bounce_hold = 0.0
	SURFACE = load("res://scripts/effects/surface_acceleration.gd")
	var tile:Node2D = floor_tile(Rect2(origin-Vector2(3000,3000),Vector2(6000,6000)))
	var effect:Node = SURFACE.touch(source,tile)
	effect.set_physics_process(false)
	for i:int in range(35):
		await physics_frame
		effect._physics_process(DT)
		source.move(source.Speed,DT)
	var boost:float = effect.momentum.length()
	check(boost>source.Speed*source.CHARACTER_BASE_MOVE_SPEED_MULTIPLIER*1.5 and source.Speed==130.0,"ice-form real movement now grows past the ordinary visitor cap without changing Speed")
	for heading:Vector2 in [Vector2.DOWN,Vector2.UP,Vector2.LEFT]:
		source.player_control_direction = heading
		var min_drive:float = INF
		var min_boost:float = INF
		var min_travel:float = INF
		for i:int in range(65):
			await physics_frame
			effect._physics_process(DT)
			var before:Vector2 = source.global_position
			source.move(source.Speed,DT)
			min_drive = minf(min_drive,source._slide_velocity.length())
			min_boost = minf(min_boost,effect.momentum.length())
			min_travel = minf(min_travel,source.global_position.distance_to(before)/DT)
		check(min_drive>129.99,"changing direction does not cancel accumulated intrinsic ice speed")
		check(min_boost>boost-0.01 and min_travel>190.0,"turning retains both surface boost and actual travel speed")
		check(source._slide_velocity.normalized().dot(heading)>0.99 and source.player_control_direction==heading,"ice can complete 90/180-degree turns without replacing player input")
		print("ICE_TURN heading=",heading," min_drive=",min_drive," min_boost=",min_boost," min_travel=",min_travel)
	# Reflecting resets the displacement origin; that one missing sample is not a stop.
	effect._physics_process(DT) # Consume the last real move before testing a no-motion reflection.
	effect.reflect_momentum(-effect.momentum.normalized())
	var reflected:Vector2 = effect.momentum
	effect._physics_process(DT)
	check(effect.momentum.is_equal_approx(reflected),"first post-reflection sample preserves the bounced boost rather than clearing it")
	var held:Vector2 = effect.momentum
	game.now_stop_state = true
	effect._physics_process(2.0)
	check(effect.momentum==held,"pause freezes the preserved ice momentum")
	game.now_stop_state = false
	effect._physics_process(DT)
	check(effect.momentum.is_zero_approx(),"a genuinely stopped body still cannot bank thrust indefinitely")
	tile.free()
	effect.free()
	source.collision_mask = 3
