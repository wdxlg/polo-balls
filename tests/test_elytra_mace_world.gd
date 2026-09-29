extends SceneTree
var checks:int = 0
var failures:int = 0
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("ELYTRA_WORLD_FAIL ",label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	create_timer(40.0).timeout.connect(func(): quit(2))
	var game:Node = root.get_node("Game")
	game.now_stop_state = false
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.set_process(false)
	world.set_physics_process(false)
	var rect:Rect2 = world.return_map_world_rect(world.map_group["Map50x50"])
	var center:Vector2 = rect.get_center()
	var mace:Node2D = load("res://scenes/characters/我的世界/鞘翅重锤.tscn").instantiate()
	mace.Team = "Team0"
	mace.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	mace.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(mace)
	mace.glide_drag = 0.0
	mace.glide_gravity = 0.0
	mace._rocket_cooldown = 9999.0
	mace.global_position = center
	await physics_frame
	check(mace.get_node("CollisionShape2D").disabled,"body collision disabled")
	check(not mace.self_hurtbox.get_node("CollisionShape2D").disabled,"hurtbox remains enabled")
	var dirs:Array[Vector2] = [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]
	for dir:Vector2 in dirs:
		var edge:Vector2 = center
		if dir.x < 0: edge.x = rect.position.x
		if dir.x > 0: edge.x = rect.end.x
		if dir.y < 0: edge.y = rect.position.y
		if dir.y > 0: edge.y = rect.end.y
		mace.global_position = edge - dir * 20.0
		mace._glide_velocity = dir * 200.0
		for step:int in range(12):
			mace._step_glide(1.0/60.0)
			world._process_map_squeeze_protection([mace])
		check(not rect.has_point(mace.global_position),"cross map wall "+str(dir))
		check(not mace.get_meta("map_rescue_animating",false),"no rescue tween "+str(dir))
		var before:Vector2 = mace.global_position
		world._process_out_of_bounds_rule(4.0,[mace])
		world._process_out_of_bounds_rule(4.0,[mace])
		check(mace.health == 200,"outside >3s survives "+str(dir))
		check(mace.global_position == before,"no forced return "+str(dir))
	# Real physics obstacles on every layer, including generated-terrain registration.
	var manager:Node = load("res://scripts/terrain/生成地形安全管理器.gd").new()
	world.add_child(manager)
	for moving:bool in [false,true]:
		var obstacle:PhysicsBody2D = AnimatableBody2D.new() if moving else StaticBody2D.new()
		obstacle.collision_layer = 1048575
		obstacle.collision_mask = 1048575
		var shape:CollisionShape2D = CollisionShape2D.new()
		var box:RectangleShape2D = RectangleShape2D.new()
		box.size = Vector2(40,200)
		shape.shape = box
		obstacle.add_child(shape)
		world.add_child(obstacle)
		obstacle.global_position = center
		manager.register_terrain(obstacle,shape,null)
		await physics_frame
		# Control body proves that this is a blocking physical wall.
		var probe:CharacterBody2D = CharacterBody2D.new()
		var probe_shape:CollisionShape2D = CollisionShape2D.new()
		var circle:CircleShape2D = CircleShape2D.new()
		circle.radius = 5
		probe_shape.shape = circle
		probe.add_child(probe_shape)
		probe.collision_mask = 1048575
		world.add_child(probe)
		probe.global_position = center - Vector2(100,0)
		await physics_frame
		check(probe.move_and_collide(Vector2(200,0)) != null,"fixture really blocks "+str(moving))
		probe.queue_free()
		mace.global_position = center - Vector2(100,0)
		mace._glide_velocity = Vector2(200,0)
		for step:int in range(60):
			mace._step_glide(1.0/60.0)
			manager._scan(1.0/60.0)
			world._process_map_squeeze_protection([mace])
		check(mace.global_position.x > center.x + 90,"cross generated obstacle "+str(moving))
		obstacle.queue_free()
		await physics_frame
	mace.global_position = center
	mace._use_firework()
	mace._update_flight_media()
	var rocket:Sprite2D = mace.get_node("Graphics/Firework")
	check(rocket.visible and rocket.global_position.x > mace.global_position.x and rocket.global_position.y > mace.global_position.y,"rocket lower right")
	check(rocket.texture.resource_path.ends_with("fireworks.png"),"vanilla rocket texture")
	var wing:Sprite2D = mace.get_node("Graphics/Elytra/Left")
	check(wing.texture is AtlasTexture,"vanilla worn wing atlas")
	check((wing.texture as AtlasTexture).atlas.resource_path.ends_with("elytra.png"),"vanilla armor texture")
	check(mace.get_node("FireworkAudio").playing,"launch sound plays")
	check(mace.get_node("GlideAudio").playing,"glide sound plays")
	mace._rocket_display_left = 0
	mace._update_flight_media()
	check(not rocket.visible,"rocket hides after use")
	mace.health = 0
	mace._update_flight_media()
	check(not mace.get_node("GlideAudio").playing,"death stops loop")
	print("ELYTRA_WORLD_RESULT checks=",checks," failures=",failures)
	# Let asynchronous world prewarm finish before teardown.
	await create_timer(3.0).timeout
	current_scene = null
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
