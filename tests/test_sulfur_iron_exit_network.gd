extends "res://tests/test_sulfur_cube_dual_network.gd"
## Real ENet endpoints: only the authority draws an exit angle; replicas mirror direction.
var _iron_checks_running:bool = false

func finish(code:int) -> void:
	if done or _iron_checks_running: return
	if code != 0:
		super.finish(code)
		return
	_iron_checks_running = true
	var host:Node2D = host_root.get_node("NetworkSulfurCube")
	var guest:Node2D = guest_root.get_node("NetworkSulfurCube")
	host.player_control_peer_id = 0
	host.fuse_left = 0.0
	host.set_block(host.Block.IRON)
	host.direction = Vector2.RIGHT
	check(await until(func(): return guest.has_block(guest.Block.IRON) and guest.direction==Vector2.RIGHT),"iron state and authority heading both replicate")
	var rng_state:int = guest._iron_exit_random.state
	host.acquire_block(host.Block.ICE)
	check(await until(func(): return guest.block_slots==host.block_slots),"retained iron with newest ICE arrives as one slot snapshot")
	check(host.has_block(host.Block.IRON) and host.direction==Vector2.RIGHT and guest.direction==Vector2.RIGHT,"changing the inner appearance while iron remains causes no extra turn on either peer")
	host.acquire_block(host.Block.HONEY)
	check(await until(func(): return not guest.has_block(guest.Block.IRON) and guest.direction.is_equal_approx(host.direction)),"actual iron eviction replicates the chosen upward direction")
	check(host.direction.y< -0.49 and host.direction.x>0.49 and guest._iron_exit_random.state==rng_state,"only authority chooses the random angle; replica does not consume direction RNG")
	var chosen:Vector2 = host.direction
	guest.set_block(guest.Block.IRON)
	check(not guest.has_block(guest.Block.IRON) and host.direction==chosen,"replica cannot initiate another iron transition or reroll")
	host.set_block(host.Block.IRON)
	host.player_control_peer_id = 1
	host.player_control_direction = Vector2.LEFT
	host.direction = Vector2.RIGHT
	rng_state = host._iron_exit_random.state
	host.set_block(host.Block.ICE)
	check(await until(func(): return guest.has_block(guest.Block.ICE) and not guest.has_block(guest.Block.IRON)),"manual mode still replicates the new block state")
	check(host.player_control_direction==Vector2.LEFT and host.direction==Vector2.RIGHT and host._iron_exit_random.state==rng_state,"direct control is not hijacked by the automatic exit rule")

	var late:Node2D = load(SCENE_PATH).instantiate()
	late.name = "IronExitLateHeading"
	late.Team = "Team0"
	late.block_slots = PackedInt32Array([host.Block.ICE,host.Block.HONEY])
	host_root.add_child(late)
	late.state_machine.set_physics_process(false)
	late.set_physics_process(false)
	late.direction = chosen
	check(await until(func(): return guest_root.has_node("IronExitLateHeading") and guest_root.get_node("IronExitLateHeading").direction.is_equal_approx(chosen)),"spawn/current direction snapshot reaches a newly created replica without rerolling")
	late.queue_free()
	check(await until(func(): return not guest_root.has_node("IronExitLateHeading")),"heading-synchronized actor despawns without a second movement controller")
	check(host.ICE_TRAIL.SLIDE_ACCELERATION==240.0 and guest.ICE_TRAIL.SLIDE_ACCELERATION==240.0 and host.ICE_STEERING_ACCELERATION==420.0,"both peers use the halved surface acceleration with unchanged steering")
	print("SULFUR_IRON_EXIT_NETWORK checks=",checks," failures=",failures)
	super.finish(0 if failures==0 else 1)
