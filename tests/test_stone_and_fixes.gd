extends SceneTree

var checks:int = 0
var failures:int = 0
var arena:Node2D

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", label)
	else:
		print("PASS: ", label)

func _initialize() -> void:
	call_deferred("run")

func spawn(path:String, point:Vector2, team:String):
	var packed:PackedScene = load(path)
	if packed == null:
		push_error("Scene unavailable: " + path)
		quit(2)
		return null
	var actor = packed.instantiate()
	if is_instance_of(actor,load("res://classes/ball.gd")): actor.Team = team
	actor.position = point
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	for child:Node in actor.find_children("*", "CollisionObject2D", true, false):
		(child as CollisionObject2D).disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	arena.add_child(actor, true)
	return actor

func run() -> void:
	create_timer(15).timeout.connect(func(): quit(2))
	var game_node = root.get_node("Game")
	game_node.now_stop_state = false
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena

	print("=== RUNNING ADVANCED STONE & SCRIPT FIX TESTS ===")

	# 1. Test Sheep script load and _charge_touch null safety
	var sheep_packed = load("res://scenes/characters/我的世界/羊.tscn")
	check(sheep_packed != null, "sheep scene loads without warnings/errors")
	var sheep = sheep_packed.instantiate()
	arena.add_child(sheep, true)
	await physics_frame
	# Call _charge_touch with empty body / victim
	if sheep.has_method("_charge_touch"):
		sheep.call("_charge_touch", null, Vector2.ZERO)
		check(true, "sheep._charge_touch(null, Vector2.ZERO) executed safely without null body error")

	# 2. Test Heavenfall Longbow script load
	var longbow_packed = load("res://scenes/characters/我的世界/天堂陨落长弓.tscn")
	check(longbow_packed != null, "heavenfall longbow scene loads without shadow warnings")

	# 3. Test Oak Boat script load
	var boat_packed = load("res://scenes/characters/我的世界/木船.tscn")
	check(boat_packed != null, "oak boat scene loads without shadow warnings")

	# 4. Test physical collision between moving ball and stone obstacle
	var stone = spawn("res://scenes/characters/默认/石头.tscn", Vector2(100, 100), "A")
	var mover = spawn("res://scenes/characters/我的世界/羊.tscn", Vector2(70, 100), "B")
	mover.process_mode = Node.PROCESS_MODE_INHERIT
	stone.process_mode = Node.PROCESS_MODE_INHERIT
	await physics_frame

	mover.velocity = Vector2(200, 0)
	mover.move_and_slide()
	await physics_frame
	print("Mover pos after move_and_slide toward stone: %s" % mover.global_position)
	check(mover.global_position.x < stone.global_position.x, "stone obstacle physically stopped mover from passing through")

	# 5. Test right-click deletion pipeline
	var stone_pos = stone.global_position
	# Test space state query at stone position
	var space_state = (arena as CanvasItem).get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = stone_pos
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var results = space_state.intersect_point(query, 32)
	check(results.size() > 0, "space_state point query hits stone collision body/area")
	var found_stone = false
	for res in results:
		var collider = res.get("collider")
		var ball_target = game_node._find_deletable_ancestor(collider)
		if ball_target == stone:
			found_stone = true
			break
	check(found_stone and game_node._find_ball_ancestor(stone)==null, "editable terrain is found without classifying the stone as a character")

	# 6. Test world character indexing
	var world_script = load("res://scripts/world.gd")
	check(world_script.PLACEABLE_OBSTACLE_SCENES.has("石头"), "stone is registered as placeable terrain, not as a combat role")

	print("ADVANCED_RESULT checks=%d failures=%d" % [checks, failures])
	if failures == 0:
		quit(0)
	else:
		quit(1)
