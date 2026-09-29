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
	var max_bias:float = 0.0
	for orbit:float in [-1.0,1.0]:
		mace._patrol_initialized = true
		mace._patrol_clockwise = orbit
		mace.global_position = Vector2(330,-24)
		mace._glide_velocity = Vector2(0,280*orbit)
		mace._rocket_remaining = 0.0
		mace._rocket_cooldown = 0.0
		mace._patrol_recovering = false
		var quadrants:Dictionary = {}
		var maximum_distance:float = 0.0
		var left:float = INF
		var right:float = -INF
		var mean_x:float = 0.0
		var left_frames:int = 0
		var samples:int = 0
		for i:int in range(7200):
			mace._step_glide(1.0/60.0)
			if i < 600: continue
			samples += 1
			mean_x += mace.global_position.x
			if mace.global_position.x < 0: left_frames += 1
			maximum_distance = maxf(maximum_distance,mace.global_position.length())
			left = minf(left,mace.global_position.x)
			right = maxf(right,mace.global_position.x)
			quadrants[Vector2i(1 if mace.global_position.x > 0 else -1,1 if mace.global_position.y > 0 else -1)] = true
		mean_x /= samples
		var occupancy:float = float(left_frames)/samples
		max_bias = maxf(max_bias,absf(mean_x))
		check(quadrants.size() == 4,"complete orbit "+str(orbit))
		check(maximum_distance < 700,"bounded orbit")
		check(absf(mean_x) < 45,"center bias <45px "+str(mean_x))
		check(occupancy > 0.40 and occupancy < 0.60,"balanced left occupancy "+str(occupancy))
		check(absf(absf(left)-right) < 70,"balanced extents")
		print("ORBIT_BALANCE dir=",orbit," mean_x=",mean_x," left_ratio=",occupancy," edges=",left,",",right)
	# Original vanilla textures, world-space trail, delayed emission and lifetime.
	mace._show_firework()
	var trail:Node2D = mace._firework_trail
	trail.advance(0.02)
	check(trail.particles.size() > 0,"firework emits spark particles")
	check(trail.frames.size() == 8 and trail.frames[0] != null,"vanilla spark frames loaded")
	var retained:Vector2 = trail.particles[0].position
	mace.global_position += Vector2(80,0)
	trail.advance(0.02)
	check((trail.particles[0].position as Vector2).distance_to(retained) < 2,"old spark stays behind")
	check(trail.particles.size() > 2,"motion is sampled along path")
	trail.advance(0.40)
	check(trail.emit_left > 0,"emission persists after rocket burn")
	check(trail.particles.size() <= trail.MAX_PARTICLES,"particle budget bounded")
	var remaining:float = trail.emit_left
	game.now_stop_state = true
	trail.advance(0.3)
	check(trail.emit_left == remaining,"pause freezes trail")
	game.now_stop_state = false
	trail.advance(0.6)
	check(trail.emit_left == 0,"emission stops")
	trail.advance(0.8)
	check(trail.is_queued_for_deletion(),"trail expires and cleans itself")
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
	print("ELYTRA_ORBIT_TRAIL_RESULT checks=",checks," failures=",failures)
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
