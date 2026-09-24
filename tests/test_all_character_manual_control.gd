extends SceneTree
## Input routing regression; full role inventory is documented separately.

var checks:int = 0
var failures:int = 0
var game:Node
var arena:Node2D
var previous_scene:Node
var previous_target:Node
var previous_stop:bool

func _initialize() -> void:
	call_deferred("run")

func check(condition:bool,label:String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("ALL_CHARACTER_CONTROL_FAIL " + label)

func spawn(scene:String,script_path:String = "") -> Node2D:
	var actor:Node2D = (load(scene) as PackedScene).instantiate() as Node2D
	if not script_path.is_empty():
		actor.set_script(load(script_path))
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	arena.add_child(actor,true)
	actor.set_physics_process(false)
	return actor

func finish() -> void:
	game._clear_local_control_action_holds(false)
	game.controlled_character_local = previous_target
	game.now_stop_state = previous_stop
	current_scene = previous_scene
	arena.queue_free()
	print("ALL_CHARACTER_CONTROL_RESULT checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)

func run() -> void:
	create_timer(40.0).timeout.connect(func(): quit(2))
	game = root.get_node("Game")
	previous_stop = game.now_stop_state
	previous_target = game.controlled_character_local
	previous_scene = current_scene
	game.now_stop_state = false
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	for number:int in range(1,10):
		check(game._control_action_index_for_keycode(KEY_1 + number - 1) == number + 2,"physical digit %d maps to index %d" % [number,number+2])
		check(game._control_action_index_for_keycode(KEY_KP_1 + number - 1) == number + 2,"keypad digit %d matches top row" % number)
	check(game._control_action_index_for_keycode(KEY_0) == 12 and game._control_action_index_for_keycode(KEY_KP_0) == 12,"zero binds thirteenth action")
	check(game._control_action_index_for_keycode(KEY_C) == -1,"C is not mistaken for an ability")

	var plain:Node2D = spawn("res://scenes/ball.tscn")
	plain.health = 100
	check(plain.player_control_action_ids().is_empty(),"ball's placeholder Attack/Skill do not consume keys")
	plain.Type = 3 # ball.Ball_Type.Creature
	check(not plain.can_player_control(),"ordinary Creature is not selectable as a fighter")
	plain.manual_controllable_subentity = true
	check(plain.can_player_control() and game._can_control_candidate(plain),"opted-in independent Creature may be controlled")
	plain.Type = 1 # ball.Ball_Type.Shooter
	check(not plain.can_player_control(),"projectile cannot be controlled even with opt-in")

	var ai:Node2D = spawn("res://scenes/characters/AI/时砂司祭.tscn")
	check(ai.player_control_action_ids() == [&"Attack",&"Skill"],"two real state actions map left then right with no middle fallback")

	var probe:Node2D = spawn("res://scenes/ball.tscn","res://tests/manual_action_probe.gd")
	probe.health = 100
	var ids:Array[StringName] = probe.player_control_action_ids()
	var unique:Dictionary = {}
	for name:StringName in ids: unique[name] = true
	check(ids.size() == 13 and unique.size() == 13,"three mouse plus ten number keys are distinct")
	probe.set_player_control_peer(1)
	game.controlled_character_local = probe
	for index:int in range(13):
		game._set_local_control_action_hold(index,true)
		game._set_local_control_action_hold(index,false)
	check(probe.called == [0,1,2,3,4,5,6,7,8,9,10,11,12],"every index dispatches its own ability")
	check(probe.released.size() == 13 and probe.released[0] == 0 and probe.released[12] == 12,"all keys deliver release on authority")
	game._set_local_control_action_hold(13,true)
	check(game._local_control_action_hold_mask == 0 and probe.called.size() == 13,"out-of-range action is ignored rather than clamped")
	game._set_local_control_action_hold(3,true)
	game._local_control_action_repeat_ready_msec[3] = 0
	game._process_local_control_action_holds()
	check(probe.called.size() == 14 and probe.called[-1] == 3,"numeric toggle remains single-shot while held")
	game._clear_local_control_action_holds(false)
	check(probe.cancelled.size() == 1 and probe.cancelled[0] == 3,"switching targets cancels a held action")
	probe.set_player_control_peer(0)
	finish()
