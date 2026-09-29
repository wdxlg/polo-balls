extends SceneTree
## 一次性核对出手点
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game: Node = root.get_node("Game")
	var saved: Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	var world: Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world, CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	await create_timer(0.4).timeout
	var center: Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var longbow: Node2D = load("res://scenes/characters/我的世界/天堂陨落长弓.tscn").instantiate()
	longbow.Team = "Team0"
	longbow.Can_Attack = false
	longbow.Can_Skill = false
	longbow.image = longbow.get_node("Sprite2D")
	longbow.position = center
	world.add_child(longbow, true)
	await physics_frame
	longbow.facing = Vector2.RIGHT
	longbow.visual_mob()
	await process_frame
	var sprite: Sprite2D = longbow.image
	print("sprite size=", sprite.texture.get_size(), " scale=", sprite.scale, " rot=", sprite.rotation, " offset=", sprite.offset)
	var head_tex := Vector2(13.0, 1.5)
	print("sprite.position=", sprite.position, " char scale=", longbow.scale)
	print("HEAD_WORLD_OFFSET=", sprite.to_global(head_tex + Vector2(0.5, 0.5) - sprite.texture.get_size() * 0.5) - longbow.global_position)
	longbow._fire()
	await process_frame
	for child: Node in world.get_children():
		if child.has_method("configure") and str(child.get_script().resource_path).ends_with("heavenfall_bolt.gd"):
			print("BOLT_OFFSET=", child.global_position - longbow.global_position)
	game.Game_Settings = saved
	quit()
