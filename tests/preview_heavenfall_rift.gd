extends SceneTree
## GPU-only visual capture for heavenfall muzzle + rift; NOT a regression test.
func _initialize() -> void: call_deferred("run")
func capture(nm: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image != null and not image.is_empty():
		image.save_jpg("res://tests/" + nm + ".jpg", 0.9)
		print("CAPTURE: ", nm)
func pv_spawn(path: String, point: Vector2, team: String, world: Node) -> Node2D:
	var unit: Node2D = load(path).instantiate() as Node2D
	unit.Team = team
	unit.Can_Attack = false
	unit.Can_Skill = false
	unit.Health_Restore = 0
	unit.position = point
	world.add_child(unit, true)
	return unit
func run() -> void:
	var game: Node = root.get_node("Game")
	var saved: Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0, true)
	create_timer(60.0).timeout.connect(func(): quit(2))
	var world: Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world, CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	var center: Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var cam := Camera2D.new()
	world.add_child(cam)
	cam.position = center
	cam.make_current()
	var longbow: Node2D = pv_spawn("res://scenes/characters/我的世界/天堂陨落长弓.tscn", center, "Team0", world)
	longbow.Can_Attack = true
	longbow.state_machine.set_physics_process(false)
	var enemy: Node2D = pv_spawn("res://scenes/ball.tscn", center + Vector2(200, 0), "Team1", world)
	enemy.state_machine.set_physics_process(false)
	enemy.Has_Collision_Damage = false
	enemy.self_hitbox.monitoring = false
	enemy.Max_health = 10000
	enemy.default_properties.Max_health = 10000
	enemy.health = 10000
	await physics_frame
	await process_frame
	longbow.facing = Vector2.RIGHT
	longbow.visual_mob()
	longbow._fire()
	await capture("rift_muzzle_preview")
	cam.position = center + Vector2(140, 0)
	await create_timer(0.55).timeout
	await capture("rift_open_preview")
	var rifts: Array = []
	for child: Node in world.get_children():
		if child.has_method("configure") and str(child.get_script().resource_path).ends_with("heavenfall_rift.gd"):
			rifts.append(child)
	if not rifts.is_empty():
		enemy.global_position = rifts[0].landing + Vector2(40, 0)
	await physics_frame
	longbow.receive_positional_damage(50.0, longbow.global_position, false, enemy)
	await process_frame
	await process_frame
	await capture("rift_dodge_preview")
	longbow._rift_cool = 0.0
	longbow._rift_grace = 0.0
	longbow._fire()
	await create_timer(0.7).timeout
	for child: Node in world.get_children():
		if child.has_method("is_open") and child.call("is_open"):
			child.set("_age", 4.8)
	await process_frame
	await process_frame
	await capture("rift_closing_preview")
	game.Game_Settings = saved
	print("RIFT_VISUAL_CAPTURE complete")
	quit()
