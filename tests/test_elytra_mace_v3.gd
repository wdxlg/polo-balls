extends SceneTree
var checks:int = 0
var failures:int = 0
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("ELYTRA_V3_FAIL ",label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game:Node = root.get_node("Game")
	game.now_stop_state = false
	game.Game_Settings.Have_Team_Damage = false
	var arena:Node2D = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	arena.process_mode = Node.PROCESS_MODE_PAUSABLE
	var mace:Node2D = load("res://scenes/characters/我的世界/鞘翅重锤.tscn").instantiate()
	mace.Team = "Team0"
	arena.add_child(mace)
	mace.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	mace.set_physics_process(false)
	var target:Node2D = load("res://scenes/characters/我的世界/重锤.tscn").instantiate()
	target.Team = "Team1"
	arena.add_child(target)
	target.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	target.set_physics_process(false)
	target.global_position = Vector2(350,230)
	var starts:Array[Vector2] = [Vector2(-300,0),Vector2(300,0),Vector2(0,-300),Vector2(0,300),Vector2(-80,-50)]
	for offset:Vector2 in starts:
		mace.global_position = target.global_position + offset
		mace._glide_velocity = Vector2(0,-250)
		mace._rocket_remaining = 0.0
		mace._rocket_cooldown = 0.8
		var minimum:float = INF
		for i:int in range(1200):
			mace._step_glide(1.0/60.0)
			minimum = minf(minimum,mace.global_position.distance_to(target.global_position))
		check(minimum < 29.0,"single enemy converges "+str(offset)+" min="+str(minimum))
	mace.global_position = Vector2(290,200)
	mace._begin_flight(1)
	mace._flight_elapsed = 0.2
	mace.velocity = Vector2(100,-80)
	mace._face_flight_direction()
	check(is_equal_approx(mace.graphics.rotation,mace.velocity.angle()+PI*0.5),"facing on parent")
	check(absf(mace.image.rotation) > 0.5,"smash spin on image")
	check(absf(angle_difference(mace.image.global_rotation,mace.graphics.global_rotation+mace.image.rotation)) < 0.001,"spin plus facing")
	check(mace.image.scale.is_equal_approx(mace._air_visual_base_scale),"no smash enlargement")
	check(mace._swing_scale_multiplier(0.5) == 1.0,"no opening enlargement")
	mace._flight_elapsed = 0.4
	mace._face_flight_direction()
	check(mace.image.rotation > 3.0,"spin advances")
	var wings:Node2D = mace.get_node("Graphics/Elytra")
	var left:Sprite2D = wings.get_node("Left")
	var right:Sprite2D = wings.get_node("Right")
	check(left.texture.get_image().get_used_rect().size.x > 0,"wing has real pixels")
	check(left.global_position.distance_to(right.global_position) > 14.0,"wings spread outside hammer")
	check(left.texture.get_size().y * left.global_scale.y > 12.0,"wing visible world size")
	mace._show_firework()
	var rocket:Sprite2D = mace.get_node("Graphics/Firework")
	check(rocket.visible,"rocket visible")
	check(rocket.global_position.x > mace.global_position.x and rocket.global_position.y > mace.global_position.y,"rocket world lower right")
	check(rocket.texture.get_size().x * rocket.global_scale.x > 8.0,"rocket readable world size")
	check(absf(rocket.global_rotation) < 0.001,"rocket upright independent of flight")
	# 真正的Area命中检测：检验叠加朝向后挥锤视觉与伤害轨迹仍一致。
	mace._airborne = false
	mace.Attacking = true
	mace.global_position = target.global_position - Vector2(20,0)
	mace.velocity = Vector2(100,-80)
	mace._face_flight_direction()
	await physics_frame
	await physics_frame
	var previous_health:int = target.health
	var opening_hits:int = await mace._perform_opening_swing(Vector2.RIGHT)
	check(opening_hits > 0 and target.health < previous_health,"rotated opening swing really hits")
	check(mace.image.scale.is_equal_approx(mace._air_visual_base_scale),"opening finishes at unchanged scale")
	# Render an enlarged view of the actual scene, not a mock-up.
	mace._airborne = false
	mace.Attacking = false
	mace.velocity = Vector2(160,-40)
	mace._face_flight_direction()
	mace._show_firework()
	target.visible = false
	var camera:Camera2D = Camera2D.new()
	arena.add_child(camera)
	camera.position = mace.position + Vector2(8,3)
	camera.zoom = Vector2(5,5)
	camera.make_current()
	print("ELYTRA_V3_RESULT checks=",checks," failures=",failures)
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/elytra_v3_actual.png")
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
