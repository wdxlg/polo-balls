extends SceneTree
## Headless contract checks for the exact-existence optimization.
var checks:int = 0
var failures:int = 0
var subject:Node
var pool:Array[Node] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(message:String) -> void:
	checks += 1
	var expected:bool = subject._count_primary_battle_characters() >= 1
	var actual:bool = subject._has_alive_primary_battle_character()
	if expected != actual:
		failures += 1
		push_error("CONTRACT FAILED: " + message)

func _make_unit() -> Node:
	var unit:Node = load("res://scenes/ball.tscn").instantiate()
	root.add_child(unit)
	root.remove_child(unit)
	unit.health_bar = null
	return unit

func _run() -> void:
	subject = load("res://scripts/world.gd").new()
	_check("empty")
	for i:int in range(100):
		var unit:Node = _make_unit()
		unit.health = 100
		pool.append(unit)
	subject._battle_units_cache = pool.duplicate()
	_check("100 alive")
	var start:int = Time.get_ticks_usec()
	for i:int in range(10000):
		subject._count_primary_battle_characters()
	var full_count_us:int = Time.get_ticks_usec() - start
	start = Time.get_ticks_usec()
	for i:int in range(10000):
		subject._has_alive_primary_battle_character()
	var existence_us:int = Time.get_ticks_usec() - start
	for unit:Node in pool:
		unit.health = 0
	_check("all dead")
	pool[99].health = 100
	_check("only last is alive")
	pool[99].Master_name = "summoner"
	_check("only living unit is a summon")
	pool[99].set_meta("battle_continuation_victory_side_key","team:one")
	_check("continuation counts")
	pool[99].set_meta("pig_outside_guest_exempt",true)
	_check("outside guest does not count")
	pool[99].set_meta("pig_outside_guest_exempt",false)
	pool[99].remove_meta("battle_continuation_victory_side_key")
	pool[99].Master_name = ""
	var rng:RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20260914
	for scenario:int in range(200):
		for unit:Node in pool:
			unit.Type = rng.randi_range(0,3)
			unit.health = 100 if rng.randf() < 0.4 else 0
			unit.Master_name = "master" if rng.randf() < 0.5 else ""
			unit.set_meta("pig_outside_guest_exempt",rng.randf() < 0.1)
			unit.set_meta("battle_continuation_victory_side_key","team:one" if rng.randf() < 0.1 else "")
		_check("random scenario " + str(scenario))
	var queued:Node = _make_unit()
	queued.health = 100
	subject._battle_units_cache = [null,queued]
	queued.queue_free()
	_check("queued for deletion and null")
	subject._battle_units_cache.clear()
	for unit:Node in pool:
		unit.queue_free()
	pool.clear()
	subject.queue_free()
	print("CONTRACT_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"full_count_10000_us":full_count_us,"existence_10000_us":existence_us}))
	await process_frame
	quit(0 if failures == 0 else 1)
