extends SceneTree
## Reproduce the real 30 Hz World target snapshot holding a freed fighter.
## A typed `for node:Node in array` assigns the dead object BEFORE the loop body.
var checks:int = 0
var failures:int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool,message:String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ",message)

func run() -> void:
	var game:Node = root.get_node("Game")
	var old_settings:Dictionary = game.Game_Settings.duplicate(true)
	var old_stop:bool = game.now_stop_state
	game.now_stop_state = false
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.set_process(false)
	world.set_physics_process(false)
	var hunter:Node2D = load("res://scenes/characters/我的世界/末影人.tscn").instantiate()
	hunter.Team = "Team0"
	world.add_child(hunter,true)
	hunter.set_physics_process(false)
	hunter.state_machine.set_physics_process(false)
	var victim:Node2D = load("res://scenes/ball.tscn").instantiate()
	victim.Team = "Team1"
	world.add_child(victim,true)
	victim.set_physics_process(false)
	victim.state_machine.set_physics_process(false)
	victim.global_position = hunter.global_position + Vector2(18,0)
	var living:Node2D = load("res://scenes/ball.tscn").instantiate()
	living.Team = "Team1"
	world.add_child(living,true)
	living.set_physics_process(false)
	living.state_machine.set_physics_process(false)
	living.global_position = hunter.global_position + Vector2(32,0)
	await physics_frame
	var stale:Variant = victim
	victim.free()
	check(not is_instance_valid(stale),"one target was genuinely freed before snapshot refresh")
	world._battle_targetable_units.clear()
	world._battle_targetable_units.append(stale)
	world._battle_targetable_units.append(living)
	hunter._mc_target_wait = 0.0
	hunter._mc_target_ref = null
	check(hunter.mc_enemy(living) and living.is_combat_lockable(),"live control target is a valid enemy")
	check(hunter.mc_nearest(0.2) == living,"nearest skips freed snapshot entry and finds live target")
	living.free()
	world._battle_targetable_units.clear()
	world._battle_targetable_units.append(stale)
	hunter._mc_target_wait = 0.0
	hunter._mc_target_ref = null
	check(hunter.mc_nearest(0.2) == null,"all freed candidates return null without editor debugger errors")
	world.queue_free()
	await process_frame
	game.Game_Settings = old_settings
	game.now_stop_state = old_stop
	print("MC_MOB_FREED_TARGET: %d checks / %d failures" % [checks,failures])
	quit(1 if failures > 0 else 0)
