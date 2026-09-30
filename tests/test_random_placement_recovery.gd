extends "res://tests/test_random_character_draft.gd"

func settle() -> void:
	for i:int in range(6): await process_frame

func click_at(point:Vector2,button:int = MOUSE_BUTTON_LEFT) -> void:
	var window:Window = root.get_window()
	var canvas:Vector2 = world.get_canvas_transform()*point
	window.grab_focus()
	# Window-local warp, not OS-absolute Input.warp_mouse. The latter misses this
	# borderless stretched window and leaves placement reading the old cursor.
	window.warp_mouse(canvas)
	for i:int in range(8):
		await process_frame
		if world.get_global_mouse_position().distance_to(point) < 3.0:
			break
	var motion := InputEventMouseMotion.new()
	motion.position = root.get_mouse_position()
	motion.global_position = motion.position
	root.push_input(motion,true)
	var event := InputEventMouseButton.new()
	event.position = root.get_mouse_position()
	event.global_position = event.position
	event.button_index = button as MouseButton
	event.pressed = true
	root.push_input(event,true)
	# push_input does not hold the OS mouse button; dispatch release in the same
	# frame so the production lost-button safety check does not cancel the fixture.
	event = event.duplicate()
	event.pressed = false
	root.push_input(event,true)
	await settle()

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	game.Game_Settings.Character_Placement_Mode = "custom"
	game.Game_Settings.Random_Character_Categories = []
	game.Game_Settings.Random_Character_Excluded = []
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Creating = true
	game.Game_Settings.Ball_Can_Move = false
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	await settle()
	world._char_folder_names = PackedStringArray(["Fixture"])
	world._character_paths_by_folder = {"Fixture":{"ClickProbe":"res://scenes/ball.tscn"}}
	world.Characters_Dic = world._character_paths_by_folder.Fixture.duplicate()
	world.now_choose_char = "ClickProbe"
	world.now_choose_team = "Team0"
	world.control.show()
	world.control.team.show()
	# Leave placement mode open but hide picker panels so test clicks target the map.
	world.control.team.get_node("Team").hide()
	world.control.team.get_node("Char").hide()
	await settle()
	var center:Vector2 = world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	await click_at(center)
	check(world._battle_setup.size()==1,"actual mouse press/release in custom mode creates one character without missing draft property")
	world.reset()
	await settle()
	game.set_runtime_game_setting("Character_Placement_Mode","random",false)
	await click_at(center)
	check(world.random_character_draft.pending.is_empty() and world._battle_setup.is_empty(),"actual click with empty random pool creates nothing")
	game.set_runtime_game_setting("Random_Character_Categories",["Fixture"],false)
	world.now_choose_char = ""
	await click_at(center)
	check(world.random_character_draft.pending.size()==1 and world._battle_setup.is_empty(),"actual click with no selected character creates one random silhouette")
	check(is_instance_valid(game._placement.ghost_ball) and game._placement.ghost_ball.name=="RandomCharacterCursor","random cursor appears with no custom character selected")
	await click_at(center,MOUSE_BUTTON_RIGHT)
	check(world.random_character_draft.pending.is_empty(),"actual right click removes the silhouette")
	var placement:RefCounted = game._placement
	placement._begin_placement_press(world,Vector2.ZERO)
	placement._placement_press_world = center-Vector2(30,30)
	placement._placement_current_world = center+Vector2(30,30)
	placement._placement_box_mode = true
	placement._finalize_placement_press(world)
	check(world.random_character_draft.pending.size()==9,"production box finalization places nine random slots")
	world.random_character_draft.animation_scale = 0.0
	var menu := InputEventAction.new()
	menu.action = "menu"
	menu.pressed = true
	root.push_input(menu,true)
	check(world.random_character_draft.playing,"actual menu input starts the reveal from placed slots")
	var escape := InputEventAction.new()
	escape.action = "esc"
	escape.pressed = true
	root.push_input(escape,true)
	check(paused and world.random_character_draft.playing and not game.now_stop_state,"ESC input cannot steal the draw-owned pause")
	await wait_draw()
	check(world._battle_setup.size()==9 and world.random_character_draft.pending.is_empty(),"all mouse/box slots resolve into real battle characters")
	world.reset()
	await settle()
	check(not paused and world._battle_setup.is_empty(),"reset releases draft and clears battle")
	game.Game_Settings = saved
	world.queue_free()
	await settle()
	print("RANDOM_PLACEMENT_RECOVERY checks=",checks," failures=",failures)
	quit(1 if failures else 0)
