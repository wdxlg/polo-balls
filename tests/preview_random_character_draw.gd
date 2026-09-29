extends SceneTree
## GPU-only visual capture; this is NOT a replacement for the two regression suites.
func _initialize() -> void: call_deferred("run")
func capture(name:String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image:Image = root.get_texture().get_image()
	if image != null and not image.is_empty():
		if root.use_hdr_2d:
			image.convert(Image.FORMAT_RGBA8)
			image.linear_to_srgb()
		image.resize(540,960,Image.INTERPOLATE_LANCZOS)
		image.save_jpg("res://tests/"+name+".jpg",0.88)
		print("CAPTURE: ",name)
func run() -> void:
	var game:Node = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Character_Placement_Mode = "random"
	game.Game_Settings.Random_Character_Categories = ["人物"]
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Map_Background = "blue"
	game.set_language("zh",false)
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	for frame:int in range(5): await process_frame
	world.control.game_setting.show()
	world.control._sync_character_mode_controls()
	await capture("random_character_settings_preview")
	world.control.game_setting.hide()
	world.control.team.show()
	world._character_paths_by_folder["人物"] = {}
	for character:String in ["剑客","保安","猎人","军官","矿工"]:
		world._character_paths_by_folder["人物"][character] = "res://scenes/characters/人物/"+character+".tscn"
	world.random_character_draft.rng.seed = 46
	var rect:Rect2 = world.return_map_world_rect(world.map_group[world.now_choose_map])
	for index:int in range(4):
		world.random_character_draft.place("Team0" if index<2 else "Team1",rect.get_center()+Vector2(-28+float(index%2)*56,-25+float(index/2)*50))
	await capture("random_character_slots_preview")
	world.random_character_draft.animation_scale = 2.5
	world.set_menu()
	var frames:int = 0
	var reveal_tick:int = -1
	for frame:int in range(60):
		if not is_instance_valid(world.random_character_draft.overlay): break
		await capture("random_character_roll_%02d" % frame)
		frames += 1
		if world.random_character_draft.overlay.revealed:
			if reveal_tick<0: reveal_tick = Time.get_ticks_msec()
			if Time.get_ticks_msec()-reveal_tick>=680: break
		await create_timer(0.06).timeout
	print("ROLL_FRAMES=",frames)
	var until:int = Time.get_ticks_msec()+8000
	while world.random_character_draft.playing and Time.get_ticks_msec()<until:
		if is_instance_valid(world.random_character_draft.overlay) and world.random_character_draft.overlay.revealed: break
		await process_frame
	await capture("random_character_draw_preview")
	world.reset()
	game.Game_Settings = saved
	world.queue_free()
	await process_frame
	print("RANDOM_DRAW_VISUAL_CAPTURE complete")
	quit()
