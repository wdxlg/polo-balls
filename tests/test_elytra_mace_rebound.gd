extends SceneTree
var checks:int = 0
var failures:int = 0
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("ELYTRA_TACTIC_FAIL ",label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game:Node = root.get_node("Game")
	game.now_stop_state = false
	game.Game_Settings.Have_Team_Damage = false
	var arena:Node2D = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	var mace:Node2D = load("res://scenes/characters/我的世界/鞘翅重锤.tscn").instantiate()
	mace.Team = "Team0"
	arena.add_child(mace)
	var target:Node2D = load("res://scenes/characters/我的世界/重锤.tscn").instantiate()
	target.Team = "Team1"
	target.Max_health = 1000000
	arena.add_child(target)
	for moving:bool in [false,true]:
		mace.global_position = Vector2.ZERO
		target.global_position = Vector2.ZERO
		target.health = 1000000
		target.velocity = Vector2(60,0) if moving else Vector2.ZERO
		mace._glide_velocity = Vector2(0,400)
		mace._airborne = false
		mace._rocket_cooldown = 0.0
		mace._begin_flight(1)
		check(absf(mace.velocity.x) >= 100,"vertical impact gets lateral rebound")
		var min_x:float = mace.global_position.x
		var max_x:float = min_x
		var hits:int = 0
		var last_hp:int = target.health
		for i:int in range(1200):
			target.global_position += target.velocity/60.0
			if moving and i > 0 and i % 120 == 0: target.velocity.x = -target.velocity.x
			if mace._airborne: mace._update_flight(1.0/60.0)
			else: break
			min_x = minf(min_x,mace.global_position.x)
			max_x = maxf(max_x,mace.global_position.x)
			if target.health < last_hp:
				hits += 1
				last_hp = target.health
				if hits >= 3: break
		check(hits >= 3,"three uninterrupted mobile smashes moving="+str(moving)+" hits="+str(hits))
		check(max_x-min_x > 25,"real lateral arc "+str(max_x-min_x))
		print("REBOUND_CASE moving=",moving," hits=",hits," lateral=",max_x-min_x)
	mace.global_position = Vector2.ZERO
	target.global_position = Vector2(120,150)
	target.velocity = Vector2.ZERO
	target.health = 1000000
	mace._airborne = false
	mace._glide_velocity = Vector2(180,200)
	mace._rocket_cooldown = 0
	mace._begin_flight(1)
	var was_below:bool = false
	var used_rocket:bool = false
	for i:int in range(240):
		if not mace._airborne: break
		mace._update_flight(1.0/60.0)
		was_below = was_below or mace.global_position.y > 10
		used_rocket = used_rocket or mace._rocket_remaining > 0
		if target.health < 1000000: break
	check(was_below,"can cross below old launch plane")
	check(target.health < 1000000,"hits opponent below launch plane")
	check(used_rocket,"rocket corrects position during combo")
	check(mace._airborne,"successful correction retains combo")
	check(mace.image.scale.is_equal_approx(mace._air_visual_base_scale),"unchanged hammer size")
	print("ELYTRA_REBOUND_RESULT checks=",checks," failures=",failures)
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
