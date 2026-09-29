extends "res://tests/test_sulfur_cube_balance.gd"
## Actual trait removal, native movement and shared-surface release momentum.
var origin:Vector2

func prepare_iron(side:float = 1.0) -> void:
	source.player_control_peer_id = 1 # Fixture reset must not consume an AI exit event.
	source.fuse_left = 0.0
	source.dizziness = false
	source.set_block(source.Block.EMPTY)
	source.set_block(source.Block.IRON)
	source.player_control_peer_id = 0
	source.direction = Vector2(side,0)
	source.Repel = Vector2.ZERO
	source._recoil_velocity = Vector2.ZERO
	source.global_position = origin
	source._last_move_direction = Vector2(side,0)
	source.clear_external_directional_gravity_velocity()

func upward(heading:Vector2,side:float) -> bool:
	return is_equal_approx(heading.length(),1.0) and heading.y <= -0.4999 and heading.y >= -0.8662 and heading.x*side > 0.49

func run() -> void:
	create_timer(120.0,true,false,true).timeout.connect(func(): print("IRON_EXIT_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	var stopped:bool = game.now_stop_state
	var old_rate:int = Engine.physics_ticks_per_second
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
	source = fighter("IronExitCube",origin,true)
	source.set_process(false)
	source.collision_mask = 0
	source.Speed = 130.0
	source.default_properties.Speed = 130.0
	SURFACE = load("res://scripts/effects/surface_acceleration.gd")
	await physics_frame

	var directions:Array[Vector2] = []
	var distinct:Dictionary = {}
	for i:int in range(24):
		var side:float = -1.0 if i%2==0 else 1.0
		prepare_iron(side)
		var rng_state:int = source._random.state
		source.acquire_block(source.Block.ICE)
		check(source.has_block(source.Block.IRON) and source.block_mode==source.Block.ICE and source.direction==Vector2(side,0),"new inner appearance does not redirect while IRON is still retained")
		source._slide_velocity = Vector2(side,0)*130.0
		source._ice_bounce_hold = 0.18
		var before:Vector2 = source.global_position
		source.acquire_block(source.Block.HONEY) # FIFO removes the last IRON effect.
		check(not source.has_block(source.Block.IRON) and upward(source.direction,side),"actual IRON removal chooses a normalized30–60 degree upward deflection on the original side")
		check(source.global_position==before and source._random.state==rng_state,"exit direction neither teleports nor consumes block/crystal gameplay randomness")
		check(source._slide_velocity.normalized().dot(source.direction)>0.999 and is_equal_approx(source._slide_velocity.length(),130.0) and source._ice_bounce_hold==0.0,"retained ICE redirects its drive immediately without losing speed or retaining the horizontal bounce hold")
		directions.append(source.direction)
		distinct[roundi(source.direction.angle()*10000.0)] = true
		await process_frame
	check(distinct.size()>12,"successive exits use varied random angles rather than one fixed upward diagonal")
	print("IRON_EXIT_DIRECTIONS ",directions)
	var chosen:Vector2 = source.direction
	source.set_block(source.Block.HONEY)
	source.set_block(source.Block.HONEY)
	check(source.direction==chosen,"subsequent non-IRON changes and unchanged snapshots do not reroll the exit")

	prepare_iron(1.0)
	source.set_block(source.Block.ICE)
	var before:Vector2 = source.global_position
	await physics_frame
	source.move(source.Speed,1.0/60.0)
	check(source.global_position.y<before.y and source.global_position.x>before.x,"ordinary IRON-to-ICE exit genuinely moves upward-right on the first physical step")
	prepare_iron(-1.0)
	source.set_block(source.Block.MAGMA)
	before = source.global_position
	await physics_frame
	source.move(source.Speed,1.0/60.0)
	check(source.global_position.y<before.y and source.global_position.x<before.x,"IRON-to-non-ICE exit also genuinely leaves a horizontal-only path")

	# Direction change is not a new kick. Existing surface magnitude and foreign
	# knockback are preserved, including inertia already decaying off the ice.
	for on_ice:bool in [true,false]:
		prepare_iron(1.0)
		source.acquire_block(source.Block.ICE)
		source._slide_velocity = Vector2.RIGHT*130.0
		var tile:Node2D = floor_tile(Rect2(origin-Vector2(1000,1000),Vector2(2000,2000)))
		var effect:Node = SURFACE.touch(source,tile)
		effect.set_physics_process(false)
		effect.momentum = Vector2.RIGHT*200.0
		source.surface_motion_velocity = effect.momentum
		if not on_ice: effect.surfaces.clear()
		source.Repel = Vector2(37,-11)
		source._recoil_velocity = Vector2(20,8)
		source.acquire_block(source.Block.HONEY)
		check(is_equal_approx(effect.momentum.length(),200.0) and effect.momentum.normalized().dot(source.direction)>0.999,"exit redirects existing ice inertia without adding or erasing magnitude; on_ice="+str(on_ice))
		check(source.Repel==Vector2(37,-11) and source._recoil_velocity==Vector2(20,8),"unrelated knockback and TNT recoil are never overwritten by the exit heading")
		source.Repel = Vector2.ZERO
		source._recoil_velocity = Vector2.ZERO
		before = source.global_position
		await physics_frame
		source.move(source.Speed,1.0/60.0)
		check(source.global_position.y<before.y,"boosted physical movement actually turns upward; on_ice="+str(on_ice))
		effect.free()
		tile.free()

	prepare_iron(1.0)
	source._start_single_slam()
	source._slam_time = 0.81
	source._step_single_slam(0.02)
	check(source.has_block(source.Block.IRON) and source.direction==Vector2.RIGHT,"ending a jump-slam is NOT the iron-effect removal trigger")
	prepare_iron(-1.0)
	source._start_single_slam()
	source.set_block(source.Block.ICE)
	check(source._slam_time<0.0 and not source.is_external_directional_gravity_locomotion_enabled() and upward(source.direction,-1.0),"real iron eviction cleans slam/gravity and then redirects once")

	prepare_iron(1.0)
	source.player_control_peer_id = 1
	source.player_control_direction = Vector2.LEFT
	var input_before:Vector2 = source.player_control_direction
	var gameplay_state:int = source._random.state
	source.set_block(source.Block.ICE)
	check(source.direction==Vector2.RIGHT and source.player_control_direction==input_before and source._random.state==gameplay_state,"direct control retains WASD and does not get an automatic exit turn")

	prepare_iron(1.0)
	game.now_stop_state = true
	source.set_block(source.Block.ICE)
	check(source.direction==Vector2.RIGHT,"pause defers the new gameplay turn")
	game.now_stop_state = false
	source.tick_physics(source.State.Stand,0.0)
	check(upward(source.direction,1.0),"one deferred exit is applied when combat resumes")
	chosen = source.direction
	source.tick_physics(source.State.Stand,0.0)
	check(source.direction==chosen,"resume cannot repeatedly reroll one exit")
	prepare_iron(1.0)
	source.dizziness = true
	source.set_block(source.Block.ICE)
	check(source.direction==Vector2.RIGHT,"stun prevents a forced gameplay turn")
	source.dizziness = false
	source.tick_physics(source.State.Stand,0.0)
	check(upward(source.direction,1.0),"stun recovery applies the pending iron exit once")
	prepare_iron(-1.0)
	game.now_stop_state = true
	source.set_block(source.Block.ICE)
	source.set_block(source.Block.IRON)
	game.now_stop_state = false
	source.tick_physics(source.State.Stand,0.0)
	check(source.direction==Vector2.LEFT and source.has_block(source.Block.IRON),"regaining IRON cancels a stale deferred exit")

	check(source.get("_iron_exit_random") != null,"direction randomness is isolated from block and crystal random streams")
	if source.get("_iron_exit_random") != null:
		prepare_iron(1.0)
		source._iron_exit_random.seed = 12345
		source.set_block(source.Block.ICE)
		chosen = source.direction
		prepare_iron(1.0)
		source._iron_exit_random.seed = 12345
		source.set_block(source.Block.ICE)
		check(source.direction.is_equal_approx(chosen),"the same gameplay direction seed reproduces the same exit angle")

	# Real integration confirms the requested HALF acceleration, not a cap.
	for rate:int in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		await physics_frame
		source.player_control_peer_id = 1
		source.set_block(source.Block.ICE)
		source.Speed = 130.0
		source._slide_velocity = Vector2.RIGHT*130.0
		source._ice_bounce_hold = 0.0
		source.Repel = Vector2.ZERO
		source._recoil_velocity = Vector2.ZERO
		source.global_position = origin
		source.player_control_direction = Vector2.RIGHT
		var tile:Node2D = floor_tile(Rect2(origin-Vector2(2000,2000),Vector2(4000,4000)))
		var effect:Node = SURFACE.touch(source,tile)
		effect.set_physics_process(false)
		for i:int in range(rate+1):
			await physics_frame
			effect._physics_process(1.0/float(rate))
			source.move(source.Speed,1.0/float(rate))
		check(is_equal_approx(effect.momentum.length(),240.0),"real ice travel adds240 per second at %d Hz, half of480" % rate)
		check(effect.momentum.length()>source.Speed*source.CHARACTER_BASE_MOVE_SPEED_MULTIPLIER*1.5 and source.ICE_STEERING_ACCELERATION==420.0,"half acceleration does not restore the old ice cap or alter steering")
		print("IRON_EXIT_ICE_RATE hz=",rate," bonus=",effect.momentum.length())
		effect.free()
		tile.free()
	Engine.physics_ticks_per_second = old_rate
	prepare_iron(1.0)
	source.set_multiplayer_authority(2)
	source.set_block(source.Block.ICE)
	check(source.has_block(source.Block.IRON) and source.direction==Vector2.RIGHT,"replica cannot originate an effect transition or random direction")
	source.block_slots = PackedInt32Array([source.Block.ICE])
	check(source.direction==Vector2.RIGHT,"replicated block snapshots do not independently reroll a client heading")
	source.set_multiplayer_authority(1)
	world.queue_free()
	await process_frame
	await create_timer(0.3,true,false,true).timeout
	game.Game_Settings = saved
	game.now_stop_state = stopped
	print("SULFUR_IRON_EXIT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
