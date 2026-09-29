extends "res://tests/test_mc_bat_transform.gd"
func wait_return(s:Node2D) -> void:
	for i:int in range(240):
		await process_frame
		if not s._returning: return
	check(false,"death return completed within 240 frames")
func run() -> void:
	create_timer(45.0).timeout.connect(func(): print("SUBARU_TEST_TIMEOUT"); quit(2))
	var center:Vector2 = await setup_world()
	var s:Node2D = spawn("res://scenes/characters/动漫/菜月昴.tscn",center)
	s.state_machine.set_physics_process(false)
	var e:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(100,0),"Team1")
	e.state_machine.set_physics_process(false)
	e.Has_Collision_Damage = false
	e.self_hitbox.monitoring = false
	await physics_frame
	await process_frame
	var t:Node = s._timeline
	t.set_physics_process(false)
	# Use the real lethal-health callback and real deferred restore pipeline.
	t._combat_started = true
	t._loop_elapsed = 8.0
	t._initial_snapshot = t._capture_world_snapshot()
	var opening_position:Vector2 = s.global_position
	var opening_health:int = e.health
	e.health -= 5
	s.global_position += Vector2(20,0)
	s.take_damage(1000,true)
	await wait_return(s)
	check(s.health == 67 and s.global_position.is_equal_approx(opening_position),"real first lethal hit restores Subaru to opening health and position")
	check(e.health == opening_health and t.return_count() == 1 and t._loop_elapsed == 0.0,"real first return restores opponent and resets battle clock")
	var probe:Node2D = load("res://tests/subaru_snapshot_probe.gd").new()
	probe.name = "RuntimeSnapshotProbe"
	world.add_child(probe)
	probe.set_process(false)
	probe.owner_ref = s
	probe.weak_target = weakref(e)
	probe.rng.seed = 23456
	var rng_state:int = probe.rng.state
	var wire := Line2D.new()
	wire.name = "RestoredWire"
	wire.points = PackedVector2Array([Vector2.ZERO,Vector2(20,10)])
	probe.add_child(wire)
	var callback_timer := Timer.new()
	callback_timer.name = "CallbackTimer"
	callback_timer.one_shot = true
	probe.add_child(callback_timer)
	callback_timer.timeout.connect(probe.on_timer_finished)
	callback_timer.start(0.8)
	var probe_key:int = t._ensure_rewind_key(probe)
	s.Target_Enemy = e
	e.health = 40
	var at_six:Dictionary = t._capture_world_snapshot()
	t._history.assign([{"t":0.0,"snapshot":t._initial_snapshot},{"t":6.0,"snapshot":at_six}])
	t._loop_elapsed = 10.0
	var e_key:int = t._ensure_rewind_key(e)
	e.queue_free()
	probe.queue_free()
	var future_child := Node2D.new()
	future_child.name = "FutureChild"
	s.add_child(future_child)
	await process_frame
	s.take_damage(1000,true)
	await wait_return(s)
	check(t.return_count() == 2 and t.current_max_rewind_seconds() == 4.0 and t._loop_elapsed == 6.0,"real second death selects four seconds back")
	var restored_probe:Node = null
	var restored_enemy:Node = null
	for n:Node in world.get_children():
		if n.get_meta("v323_rewind_key",0) == probe_key: restored_probe = n
		if n.get_meta("v323_rewind_key",0) == e_key: restored_enemy = n
	check(restored_enemy != null and restored_enemy.health == 40,"second return recreates a removed opponent at the selected time")
	check(restored_probe != null and restored_probe.payload.phase == 2 and restored_probe.elapsed == 1.25,"script.new runtime effect restores without a scene path")
	check(restored_probe != null and restored_probe.owner_ref == s and restored_probe.weak_target.get_ref() == restored_enemy,"strong and weak references rebind to restored objects")
	check(s.Target_Enemy == restored_enemy,"character target reference does not retain a freed old object")
	check(restored_probe != null and restored_probe.rng.state == rng_state,"random generator state is restored")
	check(restored_probe != null and restored_probe.get_node("RestoredWire").points == PackedVector2Array([Vector2.ZERO,Vector2(20,10)]),"runtime child geometry is reconstructed")
	check(s.get_node_or_null("FutureChild") == null,"future children inside existing actors are also removed")
	await create_timer(0.9).timeout
	check(restored_probe != null and restored_probe.payload.phase == 99,"recreated dynamic timer retains and executes its callback")
	check(not paused and not game.now_stop_state and not s._returning,"no pause or returning lock remains after repeated deaths")
	# Ensure the opening checkpoint cannot be replaced by a later larger summon count.
	var opening:Dictionary = t._initial_snapshot
	t._first_death_elapsed = -1.0
	t._sample_accumulator = 1.0
	spawn("res://scenes/ball.tscn",center+Vector2(180,0),"Team1").state_machine.set_physics_process(false)
	t._physics_process(0.1)
	check(is_same(t._initial_snapshot,opening),"later spawns never overwrite the opening checkpoint")
	finish(0 if failures == 0 else 1)
