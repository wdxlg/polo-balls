extends "res://tests/test_drowned_trident_aim_stick.gd"
var caster:Node2D
var script_trident:Script
func setup_probe() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.35).timeout
	await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self)
	arena = world.return_map_world_rect(world.map_group["Map50x50"])
	center = arena.get_center()
	script_trident = load("res://scripts/effects/我的世界/三叉戟.gd")
	caster = spawn("res://scenes/characters/我的世界/溺尸.tscn",center+Vector2(-260,-180))
	caster.mc_native_animation.set_process(false)
func make_wall(point:Vector2,size_value:Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var collision := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size_value
	collision.shape = rect
	wall.add_child(collision)
	world.add_child(wall)
	wall.global_position = point
	return wall
func new_spear(id:int) -> Node2D:
	var spear:Node2D = caster._create_trident(id)
	spear.set_physics_process(false)
	return spear
func run() -> void:
	await setup_probe()
	create_timer(40.0).timeout.connect(func(): finish(2))
	var wall:StaticBody2D = make_wall(center+Vector2(120,-100),Vector2(12,140))
	await physics_frame
	var spear:Node2D = new_spear(801)
	var start:Vector2 = center+Vector2(-80,-100)
	var aim:Vector2 = center+Vector2(98,-100) # 16px in front of the real wall face, clear of a 6px placement radius.
	spear.launch(Vector2.RIGHT,start,aim)
	check(spear._plant_ground_ok(aim),"fixture endpoint is clear ground but close to the wall ahead")
	advance_until_stuck(spear)
	check(spear.flight_state == 3 and not spear.planted and spear.wall_ref != null and spear.wall_ref.get_ref() == wall,"a clear nearby endpoint facing the wall lodges in that wall instead of the ground")
	print("DROWNED_NEAR_WALL planted=",spear.planted," traveled=",spear.traveled," point=",spear.global_position)
	wall.queue_free()
	spear.retire()
	await physics_frame
	var ground:Node2D = new_spear(802)
	ground.launch(Vector2.RIGHT,center-Vector2(100,0),center)
	ground.stick_ground(center)
	ground.charged = true
	var escaped:int = 0
	for i:int in range(80):
		ground.charge_visual._reroute_left = 0.0
		ground.charge_visual.advance(0.07)
		for arc:PackedVector2Array in ground.charge_visual._arcs:
			for p:Vector2 in arc:
				if ground.charge_visual.to_global(p).y > ground.plant_clip_y(): escaped += 1
	print("DROWNED_ARC_BELOW_GROUND samples=",escaped)
	check(escaped == 0,"actual randomized arc/fork points never re-expose the underground section")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(900,620)
		root.content_scale_size = Vector2i(900,620)
		for ui:Node in world.find_children("*","CanvasLayer",true,false): ui.visible = false
		world.versus_label.hide()
		var camera := Camera2D.new()
		world.add_child(camera)
		camera.global_position = center+Vector2(0,-6)
		camera.zoom = Vector2(12,12)
		camera.make_current()
		for i:int in range(5):
			await process_frame
			await RenderingServer.frame_post_draw
		var count:int = 0
		for node:Node in get_nodes_in_group("MCTridentGroundDebris"):
			count += node._blocks.size()
			print("DROWNED_DEBRIS node=",node.name," blocks=",node._blocks.size()," snapshot=",not node._floor_snapshot.is_empty()," position=",node.global_position," contact=",ground.plant_contact_point()," rotation=",node.global_rotation)
		check(count > 0,"GPU ground plant creates real sampled mace-style block particles, not only an empty FX node")
		root.get_texture().get_image().save_png("res://tests/drowned_surface_probe.png")
	print("DROWNED_SURFACE_PROBE checks=",checks," failures=",failures)
	finish(0 if failures == 0 else 1)
