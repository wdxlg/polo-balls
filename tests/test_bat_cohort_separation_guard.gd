extends SceneTree
## Exercise the real World spatial-grid path with two live ball instances.
## The runner must also assert that stderr contains no missing mc_bat_cohort error.

var world:Node
var game:Node
var checks:int = 0
var failures:int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool,description:String) -> void:
	checks += 1
	if ok:
		print("PASS: ",description)
	else:
		failures += 1
		push_error("FAIL: "+description)

func make_ball(team:String,point:Vector2) -> Node2D:
	var unit:Node2D = load("res://scenes/ball.tscn").instantiate() as Node2D
	unit.Team = team
	unit.Can_Attack = false
	unit.Can_Skill = false
	unit.position = point
	world.add_child(unit,true)
	unit.health = 100
	unit.set_physics_process(false)
	unit.state_machine.set_physics_process(false)
	return unit

func separation_push(left:Node2D,right:Node2D) -> Vector2:
	var pair:Array = [left,right]
	world._large_battle_separation_elapsed = 1.0
	world._rebuild_battle_spatial_grid(pair)
	world._update_large_battle_crowd_separation(pair,0.04)
	return world._battle_spatial_pushes[0]

func run() -> void:
	create_timer(35.0,true,false,true).timeout.connect(func(): print("BAT_META_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	var saved_stop:bool = game.now_stop_state
	game.now_stop_state = false
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.set_process(false)
	world.set_physics_process(false)
	var center:Vector2 = world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	var left:Node2D = make_ball("Team0",center)
	var right:Node2D = make_ball("Team1",center+Vector2(4,0))
	var pair:Array = [left,right]
	check(not left.has_meta("mc_bat_cohort") and not right.has_meta("mc_bat_cohort"),"normal fighters have no bat-cohort metadata")
	check(left.get_crowd_separation_radius_world() > 0.0 and right.get_crowd_separation_radius_world() > 0.0,"real ball collision shapes contribute to soft separation")
	world.large_battle_unit_threshold = 2
	world.large_battle_disable_below = 2
	world._update_large_battle_mode(pair)
	check(world._large_battle_mode_active,"World entered the same large-battle mode as the error report")
	var push:Vector2 = separation_push(left,right)
	check(push.length() > 0.01 and (push + (world._battle_spatial_pushes[1] as Vector2)).length() < 0.01,"two ordinary fighters still separate symmetrically")
	check(left._crowd_separation_velocity == push,"computed separation reaches the live fighter")
	left.set_meta("mc_bat_cohort",101)
	push = separation_push(left,right)
	check(push.length() > 0.01,"bat-cohort member still separates from fighter lacking metadata")
	right.set_meta("mc_bat_cohort",101)
	push = separation_push(left,right)
	check(push.is_zero_approx() and (world._battle_spatial_pushes[1] as Vector2).is_zero_approx(),"members of one cohort skip soft separation")
	check(left._crowd_separation_velocity.is_zero_approx(),"same-cohort exemption clears stale push velocity")
	right.set_meta("mc_bat_cohort",202)
	push = separation_push(left,right)
	check(push.length() > 0.01,"different bat cohorts keep ordinary separation")
	left.remove_meta("mc_bat_cohort")
	push = separation_push(left,right)
	check(push.length() > 0.01,"missing cohort after a morph/deletion is treated as an ordinary fighter")
	# Repeat the hot path to detect a per-pair logging flood, not just one lucky call.
	for i:int in range(12):
		push = separation_push(left,right)
	check(push.length() > 0.01,"repeated missing-metadata pairs continue to receive separation")
	# Match the actual default activation threshold rather than relying only on
	# the two-unit forced fixture above; most of these 40 fighters have no cohort.
	world.large_battle_unit_threshold = 40
	world.large_battle_disable_below = 30
	world._update_large_battle_mode(pair)
	check(not world._large_battle_mode_active,"large-battle mode exits below its normal hysteresis threshold")
	var crowd:Array = pair.duplicate()
	for i:int in range(38):
		crowd.append(make_ball("Team0" if i % 2 == 0 else "Team1",center+Vector2(float(i % 5)*6.0,float(i / 5)*6.0)))
	world._update_large_battle_mode(crowd)
	world._large_battle_separation_elapsed = 1.0
	world._rebuild_battle_spatial_grid(crowd)
	world._update_large_battle_crowd_separation(crowd,0.04)
	check(crowd.size() == 40 and world._large_battle_mode_active and world._battle_spatial_pushes.size() == 40,"40 real fighters activate and complete the normal crowd loop")
	check((world._battle_spatial_pushes[2] as Vector2).length() > 0.01,"unmarked fighters retain a nonzero push in the 40-unit crowd")
	world.queue_free()
	await process_frame
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	print("BAT_COHORT_SEPARATION: %d checks / %d failures" % [checks,failures])
	quit(1 if failures > 0 else 0)
