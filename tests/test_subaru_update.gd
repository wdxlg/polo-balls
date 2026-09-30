extends "res://tests/test_mc_bat_transform.gd"
func run() -> void:
	var center:Vector2 = await setup_world()
	var s:Node2D = spawn("res://scenes/characters/动漫/菜月昴.tscn",center)
	s.state_machine.set_physics_process(false)
	var enemy:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(60,0),"Team1")
	enemy.state_machine.set_physics_process(false)
	enemy.Has_Collision_Damage = false
	enemy.self_hitbox.monitoring = false
	enemy.Max_health = 1000
	enemy.default_properties.Max_health = 1000
	enemy.health = 1000
	var t:Node = s._timeline
	t.set_physics_process(false)
	await physics_frame
	await process_frame
	check(not s._hand_window_active and not s._fist_root.visible,"shadow hand starts hidden")
	check(s.whip_damage == 5.0 and s.whip_damage < s.Damage,"whip is a low-damage normal attack")
	for i:int in range(100):
		s._whip.advance(1.0/120.0)
		await physics_frame
	check(enemy.health <= 995,"visible whip physically damages an enemy")
	check(enemy.Repel.length() > 0.0,"whip hit applies knockback")
	check(s._whip.points.size() == 12 and s._whip.velocities[-1].length() > 0.0,"whip is a simulated delayed spring chain")
	var before_hand:int = enemy.health
	s._hand_window_active = true
	s._fist_busy = true
	s._perform_fist_attack(enemy)
	for i:int in range(96):
		if s._fist_busy: s._advance_fist_attack(1.0/120.0)
	check(before_hand-enemy.health == 67,"intermittent hand uses its strong hit once, with a simulated delayed reach")
	s._hand_window_active = false
	var _hand_state:bool = s._hand_window_active
	s._hand_window_left = 0.001
	s.tick_physics(0,0.01)
	check(s._hand_window_active and s._fist_root.visible,"hand opens for an intermittent attack window")
	s._hand_window_left = 0.001
	s.tick_physics(0,0.01)
	check(not s._hand_window_active and not s._fist_strike_active and not s._fist_root.visible,"closed hand window cannot retain active hitbox")
	# Capture an actual opening graph, then mutate/delete/spawn battle entities.
	t._combat_started = true
	t._first_death_elapsed = -1.0
	t._loop_elapsed = 8.0
	var hp:int = enemy.health
	var enemy_key:int = t._ensure_rewind_key(enemy)
	enemy.default_properties["graph_test"] = {"nested":[1,2,3]}
	var timer := Timer.new()
	timer.name = "RollbackTimer"
	timer.one_shot = true
	enemy.add_child(timer)
	timer.start(20.0)
	t._initial_snapshot = t._capture_world_snapshot()
	print("SUBARU_CAPTURE_US ",t.last_capture_usec," unsupported ",t.last_unsupported)
	var warm_us:Array = []
	for i:int in range(5):
		t._capture_world_snapshot()
		warm_us.append(t.last_capture_usec)
	print("SUBARU_WARM_CAPTURE_US ",warm_us)
	var initial_count:int = t._initial_snapshot.nodes.size()
	enemy.default_properties.graph_test.nested[0] = 999
	enemy.health = 1
	timer.start(1.0)
	var extra := Node2D.new()
	world.add_child(extra)
	var extra_ref:WeakRef = weakref(extra)
	var result:Dictionary = await t.perform_death_return()
	check(result.first_return and is_equal_approx(result.rewound_seconds,8.0),"first death uses simulated battle time and returns to opening")
	check(enemy.health == hp,"opening restores exact enemy HP")
	check(enemy.default_properties.graph_test.nested[0] == 1,"nested dictionary and array values are deep-restored")
	check(timer.time_left > 19.0,"native Timer remaining time is restored")
	check(extra_ref.get_ref() == null,"unsampled ungrouped future effect is removed")
	check(not paused and not game.now_stop_state,"restore releases both pause gates")
	t._return_count = 2
	check(t.current_max_rewind_seconds() == 4.0,"second maximum is half the original duration")
	t._return_count = 3
	check(t.current_max_rewind_seconds() == 2.0,"third maximum halves again")
	t._return_count = 4
	check(t.current_max_rewind_seconds() == 1.0,"fourth maximum halves again")
	t._return_count = 8
	check(t.current_max_rewind_seconds() == 0.5,"rewind duration bottoms out at half a second")
	check(s.dead_save_trigger_deaths == 5,"requested fifth-death dead-save stage remains configured")
	# Recreate a freed actor from captured factory; no PackedScene path is needed for runtime nodes.
	enemy.queue_free()
	await process_frame
	await t._restore_world_snapshot(t._initial_snapshot)
	var found:Node = null
	for node:Node in get_nodes_in_group("Ball"):
		if node.get_meta("v323_rewind_key",0) == enemy_key: found = node
	check(found != null and found.health == hp,"deleted fighter is reconstructed with its exact snapshot health")
	print("SUBARU_RESTORE_SLICES ",t.last_restore_slices," roots ",initial_count)
	finish(0 if failures == 0 else 1)
