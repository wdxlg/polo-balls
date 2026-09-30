extends SceneTree
## C-control hold timing plus real fishing-rod toggle regression.
## Remote assertions exercise the authority loop with accepted hold state, not an ENet pair.

class ActionProbe extends Node2D:
	var called:Array[int] = []
	var released:Array[int] = []
	var cancelled:Array[int] = []
	func player_control_action(index:int) -> void: called.append(index)
	func player_control_action_released(index:int) -> void: released.append(index)
	func player_control_action_cancelled(index:int) -> void: cancelled.append(index)
	func player_control_action_hold_repeat_allowed(index:int) -> bool: return index >= 0 and index < 3

var checks:int = 0
var failures:int = 0
var game:Node
var arena:Node2D

func _initialize() -> void: call_deferred("run")

func check(condition:bool,label:String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("CONTROL_HOLD_FAIL " + label)

func run() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))
	game = root.get_node("Game")
	var previous_scene:Node = current_scene
	var previous_mode:int = game.process_mode
	var previous_stop:bool = game.now_stop_state
	var previous_role:String = game.network_role
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.now_stop_state = false
	game.network_role = "offline"
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var probe:ActionProbe = ActionProbe.new()
	arena.add_child(probe,true)
	game.controlled_character_local = probe
	check(game.CONTROL_ACTION_HOLD_INITIAL_REPEAT_DELAY_MSEC == 400,"normal-click window is 400 ms, not 45 ms")
	var before:int = Time.get_ticks_msec()
	game._set_local_control_action_hold(0,true)
	var after:int = Time.get_ticks_msec()
	var deadline:int = game._local_control_action_repeat_ready_msec[0]
	check(probe.called == [0],"first press acts immediately")
	check(deadline >= before+400 and deadline <= after+400,"local first deadline uses shared threshold")
	game._set_local_control_action_hold(0,true)
	check(probe.called == [0] and game._local_control_action_repeat_ready_msec[0] == deadline,"duplicate press is ignored without extending deadline")
	await create_timer(0.20).timeout
	game._process_local_control_action_holds()
	check(probe.called == [0],"a normal 200 ms click does not repeat")
	game._set_local_control_action_hold(0,false)
	check(probe.released == [0] and game._local_control_action_hold_mask == 0 and game._local_control_action_repeat_ready_msec[0] == 0,"release dispatches and clears held slot/deadline")
	game._set_local_control_action_hold(0,false)
	check(probe.released == [0],"duplicate release is ignored")
	await create_timer(0.25).timeout
	game._process_local_control_action_holds()
	check(probe.called == [0],"released click never becomes a delayed second action")

	probe.called.clear()
	game._set_local_control_action_hold(0,true)
	check(probe.called == [0] and game._local_control_action_repeat_ready_msec[0] > Time.get_ticks_msec(),"repress is immediate and gets a fresh hold window")
	game._process_local_control_action_holds()
	check(probe.called == [0],"new hold does not inherit old expiry")
	await create_timer(0.45).timeout
	game._process_local_control_action_holds()
	check(probe.called == [0,0],"a genuine 450 ms hold repeats")
	game._process_local_control_action_holds()
	check(probe.called == [0,0,0],"after threshold, original per-tick attempts remain")
	game._clear_local_control_action_holds(false)
	check(probe.cancelled == [0] and game._local_control_action_hold_mask == 0,"control cancellation clears hold without a release action")
	for slot:int in range(13):
		check(game._local_control_action_repeat_ready_msec[slot] == 0,"cancel clears deadline %d" % slot)
	probe.called.clear()
	game._set_local_control_action_hold(3,true)
	game._local_control_action_repeat_ready_msec[3] = 0
	game._process_local_control_action_holds()
	check(probe.called == [3],"numeric edge-only action remains single-shot")
	game._clear_local_control_action_holds(false)
	game._set_local_control_action_hold(-1,true)
	game._set_local_control_action_hold(13,true)
	check(game._local_control_action_hold_mask == 0,"invalid slots never acquire a held bit")

	probe.called.clear()
	game._controlled_peer_paths[22] = probe.get_path()
	game._remote_control_action_hold_masks[22] = 1
	game._remote_control_action_repeat_ready_msec[22] = {0:Time.get_ticks_msec()+400}
	game._process_remote_control_action_holds()
	check(probe.called.is_empty(),"authority does not repeat before remote deadline")
	game._remote_control_action_repeat_ready_msec[22] = {0:0}
	game._process_remote_control_action_holds()
	check(probe.called == [0],"authority repeats a valid remote hold after deadline")
	game._remote_control_action_hold_masks[22] = 1 << 3
	game._remote_control_action_repeat_ready_msec[22] = {3:0}
	game._process_remote_control_action_holds()
	check(probe.called == [0],"remote numeric action is edge-only too")
	game._controlled_peer_paths.erase(22)
	game._process_remote_control_action_holds()
	check(not game._remote_control_action_hold_masks.has(22) and not game._remote_control_action_repeat_ready_msec.has(22),"unassigned remote peer loses held state")
	game._controlled_peer_paths[23] = NodePath("/root/MissingControlTarget")
	game._remote_control_action_hold_masks[23] = 1
	game._remote_control_action_repeat_ready_msec[23] = {0:0}
	game._process_remote_control_action_holds()
	check(not game._remote_control_action_hold_masks.has(23) and not game._remote_control_action_repeat_ready_msec.has(23),"missing remote target loses held state")
	game._controlled_peer_paths.erase(23)

	var rod:Node2D = (load("res://scenes/characters/我的世界/钓鱼竿.tscn") as PackedScene).instantiate() as Node2D
	rod.process_mode = Node.PROCESS_MODE_DISABLED
	arena.add_child(rod,true)
	rod.set_physics_process(false)
	rod.set_player_control_peer(1)
	rod._cast_left = 0.0
	game.controlled_character_local = rod
	check(rod.player_control_action_hold_repeat_allowed(0),"fishing sword retains hold repeat")
	check(not rod.player_control_action_hold_repeat_allowed(1),"fishing cast/reel is edge-only")
	check(not rod.player_control_action_hold_repeat_allowed(3),"rod retains inherited numeric repeat restriction")
	game._set_local_control_action_hold(1,true)
	check(rod.hook_mode == 1,"right press really casts the hook immediately")
	game._local_control_action_repeat_ready_msec[1] = 0
	for frame:int in range(60): game._process_local_control_action_holds()
	check(rod.hook_mode == 1,"holding right beyond threshold does not reel a flying hook")
	game._set_local_control_action_hold(1,true)
	check(rod.hook_mode == 1,"duplicate right press does not cancel a cast")
	game._set_local_control_action_hold(1,false)
	check(rod.hook_mode == 1,"right release alone does not reel")
	game._set_local_control_action_hold(1,true)
	check(rod.hook_mode == 4,"release then right press retrieves immediately")
	game._clear_local_control_action_holds(false)
	for mode:int in [2,3]:
		rod.hook_mode = mode
		game._local_control_action_hold_mask = 2
		game._local_control_action_repeat_ready_msec[1] = 0
		game._process_local_control_action_holds()
		check(rod.hook_mode == mode,"held right leaves committed hook phase %d alone" % mode)
		game._set_local_control_action_hold(1,false)
		game._set_local_control_action_hold(1,true)
		check(rod.hook_mode == 4,"next right press retrieves phase %d" % mode)
		game._clear_local_control_action_holds(false)
	game._controlled_peer_paths[24] = rod.get_path()
	game._remote_control_action_hold_masks[24] = 2
	game._remote_control_action_repeat_ready_msec[24] = {1:0}
	for mode:int in [1,2,3]:
		rod.hook_mode = mode
		game._process_remote_control_action_holds()
		check(rod.hook_mode == mode,"authority respects rod edge-only phase %d" % mode)
	game._controlled_peer_paths.erase(24)
	game._process_remote_control_action_holds()
	game.controlled_character_local = probe
	probe.called.clear()
	game._local_control_action_hold_mask = 1
	game._local_control_action_repeat_ready_msec[0] = 0
	game.network_role = "client"
	game._process_local_control_action_holds()
	check(probe.called.is_empty(),"client never executes local hold repeats")
	game.network_role = previous_role
	game._clear_local_control_action_holds(false)
	game.controlled_character_local = null
	rod.set_player_control_peer(0)
	game.now_stop_state = previous_stop
	game.process_mode = previous_mode as Node.ProcessMode
	current_scene = previous_scene
	arena.queue_free()
	print("CONTROL_HOLD_RESULT checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)
