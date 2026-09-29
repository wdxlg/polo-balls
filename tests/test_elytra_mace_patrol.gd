extends SceneTree
class PatrolArena extends Node2D:
	var bounds:Rect2 = Rect2(-300,-200,600,400)
	func current_map_island_rects() -> Array[Rect2]:
		return [bounds]
var checks:int = 0
var failures:int = 0
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("PATROL_FAIL ",label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game:Node = root.get_node("Game")
	game.now_stop_state = false
	game.Game_Settings.Have_Team_Damage = false
	var arena:PatrolArena = PatrolArena.new()
	root.add_child(arena)
	current_scene = arena
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	var mace:Node2D = load("res://scenes/characters/我的世界/鞘翅重锤.tscn").instantiate()
	mace.Team = "Team0"
	arena.add_child(mace)
	mace.global_position = Vector2(0,210)
	mace._glide_velocity = Vector2(220,100)
	mace._rocket_cooldown = 0
	mace._step_glide(1.0/60.0)
	check(mace._patrol_recovering,"low altitude recovery")
	check(mace._rocket_remaining > 0 and mace._boost_direction.y < -0.10,"low altitude upward rocket")
	check(absf(mace._boost_direction.x) > 0.1,"diagonal recovery")
	var quadrants:Dictionary = {}
	var maximum_distance:float = 0
	var min_y:float = INF
	var left:float = INF
	var right:float = -INF
	for i:int in range(3600):
		mace._step_glide(1.0/60.0)
		maximum_distance = maxf(maximum_distance,mace.global_position.length())
		min_y = minf(min_y,mace.global_position.y)
		left = minf(left,mace.global_position.x)
		right = maxf(right,mace.global_position.x)
		quadrants[Vector2i(1 if mace.global_position.x > 0 else -1,1 if mace.global_position.y > 0 else -1)] = true
	check(quadrants.size() == 4,"circles all map sides")
	check(maximum_distance < 850.0,"stays around map for 60 seconds "+str(maximum_distance))
	check(min_y < -100,"regains height")
	check(left < -200 and right > 200,"patrol covers map width")
	arena.bounds = Rect2(1000,500,800,600)
	mace._patrol_rect_refresh = 0
	mace._patrol_aim(0.01)
	check(mace._patrol_rect == arena.bounds,"map switch updates orbit")
	var enemy:Node2D = load("res://scenes/characters/我的世界/重锤.tscn").instantiate()
	enemy.Team = "Team1"
	arena.add_child(enemy)
	enemy.global_position = mace.global_position+Vector2(100,100)
	mace._patrol_recovering = true
	mace._step_glide(0.016)
	check(mace._pvp_target == enemy and not mace._patrol_recovering,"enemy switches to combat")
	enemy.health = 0
	mace._airborne = false
	mace.Attacking = false
	mace._step_glide(0.016)
	check(mace._flight_target() == null and mace._flight_mode == mace.FlightMode.GLIDE,"no enemies resumes patrol")
	print("ELYTRA_PATROL_RESULT checks=",checks," failures=",failures)
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
