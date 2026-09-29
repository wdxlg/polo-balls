extends "res://tests/test_sulfur_cube_balance.gd"
## Real shared Move/Stand contacts, not a velocity-only mock.
var victim:Node2D
var origin:Vector2
func reset_mode(mode:int) -> void:
	source.fuse_left = 0.0
	source.set_block(mode)
	source._slam_time = -1.0
	source._restore_slam_collision()
	source._slam_hits.clear()
	source._next_hit_at.clear()
	source._top_hit_at.clear()
	source._iron_down_speed = 0.0
	source.clear_external_directional_gravity_velocity()
	source.surface_motion_velocity = Vector2.ZERO
	source.Repel = Vector2.ZERO
	source.player_control_direction = Vector2.ZERO
	source.global_position = origin
	var push:Node = knockback(victim)
	if push != null: push.free()
	victim.Repel = Vector2.ZERO
func fall_hit(speed:float,standing:bool = false,horizontal:float = 0.0) -> float:
	reset_mode(source.Block.IRON)
	victim.global_position = origin+Vector2(0,source.get_crowd_separation_radius_world()+15.5)
	await physics_frame
	source.Repel = Vector2(horizontal,speed)
	var hp:float = victim.health
	if standing: source.stand(1.0/60.0)
	else: source.move(0.0,1.0/60.0)
	var push:Node = knockback(victim)
	if push != null: push.set_physics_process(false)
	if speed > 0.0 and horizontal == 0.0:
		check(source.get_slide_collision_count()>0,"descent reaches a real body collision")
		check(is_equal_approx(source._iron_down_speed,speed),"iron uses incoming downward speed before the collision stops it")
	return hp-victim.health
func run() -> void:
	create_timer(90.0,true,false,true).timeout.connect(func(): print("SULFUR_IMPACT_TIMEOUT"); quit(2))
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
	source = load("res://scenes/characters/我的世界/硫方怪.tscn").instantiate()
	source.Team = "Team0"
	source.position = origin
	world.add_child(source)
	source.state_machine.set_physics_process(false)
	source.set_physics_process(false)
	source.player_control_peer_id = 1
	source.Damage = 48
	source.Speed = 0.0
	victim = fighter("ImpactVictim",origin+Vector2(100,0))
	victim.scale = Vector2.ONE
	victim.Damage_reduction = 0.0
	victim.block = 0.0
	await process_frame
	await physics_frame
	check(not source.Has_Collision_Damage,"original sulfur scene disables the inherited generic body hitbox")
	# All non-contact modes: a real side collision, then the normal contact scanner.
	for mode:int in [source.Block.EMPTY,source.Block.HONEY,source.Block.IRON,source.Block.TNT,source.Block.AMETHYST]:
		reset_mode(mode)
		if mode == source.Block.AMETHYST: source.crystals_out = true
		victim.global_position = origin+Vector2(source.get_crowd_separation_radius_world()+15.5,0)
		await physics_frame
		source.Repel = Vector2.RIGHT*170.0
		var hp:float = victim.health
		source.move(0.0,1.0/60.0)
		check(source.get_slide_collision_count()>0,"mode %d has real side contact" % mode)
		source._pulse_contact()
		source._pulse_block_contact(mode)
		check(victim.health==hp and source._mode_damage(mode)==0.0,"mode %d has no shell collision damage" % mode)
	var slow:float = await fall_hit(85.0)
	reset_mode(source.Block.AMETHYST)
	source.crystals_out = false
	source.crystal_layout = PackedVector3Array([Vector3(-0.4,0,0.4),Vector3(-1.70,0,1.1)])
	source._native_model.animate(0.0,0.3,true,0.0)
	victim.global_position = origin+Vector2(source.get_crowd_separation_radius_world()+14.9,0)
	var crystal_hp:float = victim.health
	source._pulse_contact()
	check(victim.health==crystal_hp,"attached amethyst does not turn a bare shell-side touch into damage")
	victim.global_position = source._crystal_tip_points()[0]
	source._pulse_contact()
	check(crystal_hp-victim.health==ceilf(source.attack_damage(source.AMETHYST_CONTACT_MULT)),"attached crystal tip itself still pierces the enemy")
	reset_mode(source.Block.IRON)
	victim.global_position = origin+Vector2(0,50) # Stay inside the real map's lower boundary.
	var gravity_hp:float = victim.health
	source.Speed = 130.0
	for i:int in range(40):
		await physics_frame
		source.tick_physics(source.State.Move,1.0/60.0)
		if victim.health<gravity_hp: break
	check(victim.health<gravity_hp and source._iron_down_speed>170.0,"native gravity acceleration reaches a real speed-scaled underside hit")
	check(gravity_hp-victim.health==floorf(source.attack_damage(source.IRON_IMPACT_MULT*source._iron_down_speed/170.0)),"natural gravity and externally supplied downward motion share one damage formula")
	source.Speed = 0.0
	var fast:float = await fall_hit(170.0)
	var faster:float = await fall_hit(340.0)
	print("IRON_REAL_IMPACTS ",slow," / ",fast," / ",faster)
	check(slow==28 and fast==57 and faster==115,"iron damage is tripled and grows with actual downward impact speed")
	check(await fall_hit(170.0,true)==57,"Stand movement uses the same real descent settlement")
	check(await fall_hit(170.0,false,80.0)==57,"horizontal motion does not inflate iron damage")
	check(await fall_hit(0.0,false,80.0)==0,"pure horizontal motion cannot crush")
	check(await fall_hit(-170.0)==0,"upward movement cannot crush")
	source.Damage = 96
	check(await fall_hit(170.0)==115,"live attacker damage scales iron impact")
	source.Damage = 48
	victim.Damage_reduction = 0.5
	var defended:float = await fall_hit(170.0)
	check(defended>0 and defended<57,"victim defenses apply to speed-based iron damage")
	victim.Damage_reduction = 0.0
	await fall_hit(170.0)
	var hp:float = victim.health
	for i:int in range(20):
		source._clock += 0.25
		source._iron_bottom_contacts()
	check(victim.health==hp,"continuous contact has no repeat hit or crush ticks")
	source.Repel = Vector2.ZERO
	source.stand(1.0/60.0)
	check(source._iron_down_speed==0 and source.get_ai_attack_threats(victim).is_empty(),"stationary iron has no damage or persistent damage threat")
	victim.global_position += Vector2(100,0)
	source._iron_bottom_contacts()
	check(source._slam_hits.is_empty(),"leaving the underside releases contact history")
	victim.global_position = source._iron_bottom_rect().get_center()+Vector2(0,2)
	source._iron_bottom_contacts()
	check(victim.health==hp,"walking underneath a stationary iron block causes no damage")
	check(await fall_hit(170.0)==57,"a genuinely new fall can hit the same target again")
	reset_mode(source.Block.IRON)
	victim.global_position = source._iron_bottom_rect().get_center()+Vector2(0,2)
	source._iron_down_speed = 170.0
	hp = victim.health
	game.now_stop_state = true
	source._iron_bottom_contacts()
	check(victim.health==hp,"paused iron cannot settle impact")
	game.now_stop_state = false
	source.dizziness = true
	source._iron_bottom_contacts()
	check(victim.health==hp,"stunned iron cannot attack")
	source.dizziness = false
	victim.Team = source.Team
	source._iron_bottom_contacts()
	check(victim.health==hp,"iron respects friendly protection")
	victim.Team = "Team1"
	source.set_multiplayer_authority(2)
	source._iron_bottom_contacts()
	check(victim.health==hp,"non-authority iron cannot damage")
	source.set_multiplayer_authority(1)
	# Actual special-slam arc also captures pre-impact downward speed.
	reset_mode(source.Block.IRON)
	source._slam_start = origin
	source._slam_end = origin+Vector2(0,60)
	source._slam_time = 0.5
	var t:float = 0.5/0.82
	source.global_position = source._slam_start.lerp(source._slam_end,t)-Vector2.DOWN*56.0*4.0*t*(1.0-t)
	var next_t:float = (0.5+1.0/60.0)/0.82
	var next_position:Vector2 = source._slam_start.lerp(source._slam_end,next_t)-Vector2.DOWN*56.0*4.0*next_t*(1.0-next_t)
	victim.global_position = next_position+Vector2(0,source.get_crowd_separation_radius_world()+14.9)
	source._slam_saved_mask = source.collision_mask
	source.collision_mask &= ~2
	hp = victim.health
	await physics_frame
	source._step_single_slam(1.0/60.0)
	check(source._iron_down_speed>0 and hp-victim.health==floorf(source.attack_damage(source.IRON_IMPACT_MULT*source._iron_down_speed/170.0)),"special slam uses its real arc descent speed, not a fixed phase damage")
	# Magma body contact and faster TOP-only ticks are independent.
	reset_mode(source.Block.MAGMA)
	var radius:float = source.get_crowd_separation_radius_world()
	victim.global_position = origin+Vector2(0,-radius-14.9)
	var side:Node2D = fighter("MagmaSide",origin+Vector2(radius+14.9,0))
	var below:Node2D = fighter("MagmaBelow",origin+Vector2(0,radius+14.9))
	side.scale = Vector2.ONE
	below.scale = Vector2.ONE
	await physics_frame
	source._clock = 0.0
	hp = victim.health
	var side_hp:float = side.health
	var below_hp:float = below.health
	source._pulse_contact()
	check(victim.health<hp and side.health<side_hp and below.health<below_hp,"magma retains ordinary body contact in every direction")
	check(source._top_hit_at.has(victim.get_instance_id()) and not source._top_hit_at.has(side.get_instance_id()) and not source._top_hit_at.has(below.get_instance_id()),"only real top contact acquires high-frequency damage")
	hp = victim.health
	side_hp = side.health
	below_hp = below.health
	for i:int in range(1,4):
		source._clock = float(i)*0.17
		source._pulse_contact()
	check(hp-victim.health>=24 and side.health==side_hp and below.health==below_hp,"three extra top ticks occur before the next ordinary body hit")
	var threats:Array = source.get_ai_attack_threats(victim)
	var top_matches:bool = false
	for info:Dictionary in threats:
		if info.kind=="sulfur_magma_top": top_matches = info.position==source._magma_top_rect().get_center() and info.half_extents==source._magma_top_rect().size*0.5 and info.danger_duration==source.HOT_INTERVAL
	check(top_matches,"top damage and threat display share identical strip geometry and frequency")
	source.acquire_block(source.Block.HONEY)
	hp = victim.health
	source._clock += 0.17
	source._pulse_contact()
	check(victim.health<hp and source.has_block(source.Block.MAGMA),"retained magma keeps its top damage when honey becomes the newer block")
	source.set_block(source.Block.ICE)
	check(source._top_hit_at.is_empty(),"removing magma clears top contact cooldowns")
	source._actual_speed = 170.0 # Ice body contact now scales linearly from real motion.
	source._next_hit_at.clear()
	hp = victim.health
	source._pulse_contact()
	check(victim.health<hp,"ice retains its explicit body contact damage")
	reset_mode(source.Block.MAGMA)
	victim.global_position = origin+Vector2(0,-radius-14.9)
	victim.fire_effect_ratio = 0.0
	hp = victim.health
	source._pulse_contact()
	source._clock += 0.17
	source._pulse_contact()
	check(victim.health==hp,"magma body and high-frequency top hits both honor shared fire immunity")
	victim.fire_effect_ratio = 1.0
	world.queue_free()
	await process_frame
	await create_timer(0.3,true,false,true).timeout
	game.Game_Settings = saved
	game.now_stop_state = stopped
	print("SULFUR_IMPACT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
