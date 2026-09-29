extends SceneTree
var checks:int = 0
var failures:int = 0
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("ELYTRA_PVP_FAIL ",label)
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
	mace.global_position = Vector2(20,0)
	mace._rocket_cooldown = 0.0
	mace._step_glide(1.0/60.0)
	check(mace._rocket_remaining > 0,"near enemy uses rocket")
	check(mace._boost_direction.y < 0 and absf(mace._boost_direction.x) > 0.1,"near rocket diagonal loft")
	check(mace.get_node("FireworkAudio").playing,"near rocket sound")
	var wings:Node2D = mace.get_node("Graphics/Elytra")
	check(wings.z_index > mace.image.z_index,"wings above hammer")
	mace.velocity = Vector2.UP * 450
	for i:int in range(30): mace._update_wing_animation(1.0/60.0)
	var open_angle:float = wings.get_node("Left").rotation
	mace.velocity = Vector2.DOWN * 450
	for i:int in range(30): mace._update_wing_animation(1.0/60.0)
	var dive_angle:float = wings.get_node("Left").rotation
	check(open_angle - dive_angle > 0.8,"climb opens and dive folds wings")
	check(absf(wings.get_node("Left").rotation+wings.get_node("Right").rotation) < 0.1,"symmetric wing pose")
	var starts:Array[Vector2] = [Vector2(20,0),Vector2(-300,0),Vector2(300,0),Vector2(0,-300),Vector2(0,300)]
	for moving:bool in [false,true]:
		for offset:Vector2 in starts:
			mace.global_position = offset
			target.global_position = Vector2.ZERO
			target.velocity = Vector2(45,0) if moving else Vector2.ZERO
			target.health = 1000000
			mace._airborne = false
			mace.Attacking = false
			mace._tactic_hold = 0.0
			mace._flight_mode = mace.FlightMode.GLIDE
			mace._rocket_remaining = 0.0
			mace._rocket_cooldown = 0.0
			mace._glide_velocity = Vector2(280,0)
			var hit:bool = false
			var dive_speed:float = 0.0
			var elapsed:float = 0.0
			for i:int in range(900):
				target.global_position += target.velocity/60.0
				if mace._flight_mode == mace.FlightMode.DIVE: dive_speed = mace._glide_velocity.length()
				mace._step_glide(1.0/60.0)
				elapsed += 1.0/60.0
				if target.health < 1000000:
					hit = true
					break
			check(hit,"dive actually hits "+str(offset)+" moving="+str(moving))
			check(dive_speed > 200,"fast impact "+str(dive_speed))
			check(mace._airborne and mace.velocity.y < 0,"hit rebounds into combo")
			print("PVP_CASE ",offset," moving=",moving," hit_time=",elapsed," speed=",dive_speed)
	mace._airborne = false
	mace.Attacking = false
	mace._flight_mode = mace.FlightMode.DIVE
	mace._mode_elapsed = 0.0
	mace._rocket_remaining = 0
	mace._glide_velocity = Vector2(0,500)
	mace.global_position = target.global_position - Vector2(0,80)
	mace._step_glide(0.01)
	check(mace._glide_velocity.length() > 450,"no near enemy braking")
	mace._tactic_hold = 0.0
	mace._rocket_remaining = 0.0
	mace._rocket_cooldown = 0.0
	mace.global_position = target.global_position + Vector2(0,100)
	mace._glide_velocity = Vector2(120,0)
	mace._step_glide(0.01)
	check(mace._tactical_aim.y < 0,"miss plans reposition above target")
	check(mace._rocket_remaining > 0 and mace._boost_direction.y < 0,"miss supports directional rocket reposition")
	check(mace.image.scale.is_equal_approx(mace._air_visual_base_scale),"no enlargement")
	print("ELYTRA_PVP_RESULT checks=",checks," failures=",failures)
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
