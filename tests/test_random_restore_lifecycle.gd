extends "res://tests/test_random_character_draft.gd"

func settle() -> void:
	for i:int in range(5): await process_frame

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	game.Game_Settings.Character_Placement_Mode = "custom"
	game.Game_Settings.Random_Character_Categories = []
	game.Game_Settings.Random_Character_Excluded = []
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Boss_Intro = false
	game.Game_Settings.Development_Mode = false
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	await settle()
	world._char_folder_names = PackedStringArray(["Fixture"])
	world._character_paths_by_folder = {"Fixture":{"Probe":"res://scenes/ball.tscn"}}
	world.Characters_Dic = world._character_paths_by_folder.Fixture.duplicate()
	var draft:RefCounted = world.random_character_draft
	draft.animation_scale = 0.0
	var center:Vector2 = world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	game._apply_runtime_game_setting_local("Character_Placement_Mode",false,false)
	check(game.Game_Settings.Character_Placement_Mode=="custom","invalid placement mode normalizes to custom")
	game._apply_runtime_game_setting_local("Random_Character_Categories",["Fixture",7,"",{},"Fixture"],false)
	check(game.Game_Settings.Random_Character_Categories==["Fixture"],"category settings sanitize duplicate and malformed entries")
	check(world.is_placeable_obstacle("石头","res://scenes/characters/默认/石头.tscn"),"random eligibility uses the obstacle registry")
	game.set_runtime_game_setting("Character_Placement_Mode","random",false)
	draft.place("Team0",center)
	world.set_menu()
	await wait_draw()
	check(world._battle_setup.size()==1,"draw creates initial rematch setup")
	world.reset()
	await settle()
	await world.rematch_last_battle(true)
	check(world._battle_setup.size()==1 and world._battle_setup[0].scene_path=="res://scenes/ball.tscn","exact rematch preserves the drawn scene path")
	check(get_nodes_in_group("Ball").size()==1,"rematch creates a real unit rather than a new random slot")
	await world.rematch_last_battle(false)
	check(world._battle_setup.size()==1 and world._battle_setup[0].char=="Probe","fresh-seed rematch retains the revealed identity")
	world.reset()
	await settle()
	world.control.show()
	draft.place("Team0",center)
	game.set_runtime_game_setting("Character_Placement_Mode","custom",false)
	check(draft.pending.is_empty() and not draft.playing,"switching to custom cancels pending silhouettes")
	check(game.Game_Settings.Random_Character_Categories==["Fixture"],"mode switching retains the selected pool")
	game.set_runtime_game_setting("Character_Placement_Mode","random",false)
	draft.place("Team0",center)
	var original_map:String = world.now_choose_map
	for map_name:Variant in world.map_group:
		if str(map_name)!=original_map:
			world.now_choose_map = str(map_name)
			world.refresh_map_presentation()
			break
	check(draft.pending.is_empty(),"map changes clear pending silhouettes immediately")
	world.now_choose_map = original_map
	world.refresh_map_presentation()
	game.set_runtime_game_setting("Training_Mode_Type","rotation",false)
	game.Game_Settings.Rotation_Multi_Characters = true
	world.reset()
	await settle()
	world.control.show()
	draft.place("Team0",center-Vector2(24,0),3)
	draft.place("Team1",center+Vector2(24,0),3)
	world.rotation_selected_round = 9
	world.set_menu()
	await wait_draw()
	check(world._rotation_rosters.left.size()==1 and world._rotation_rosters.right.size()==1,"rotation keeps both drawn contestants")
	check(world._rotation_rosters.left[0].round==3 and world._rotation_rosters.right[0].round==3,"draw preserves the round selected at placement time")
	check(world._rotation_rosters.left[0].scene_path=="res://scenes/ball.tscn","rotation roster retains the precise scene path")
	game.set_runtime_game_setting("Training_Mode_Type","manual",false)
	world.reset()
	await settle()
	# Local cancellations and authoritative message sequence numbers are independent.
	draft.network_serial = -1
	draft._serial = 100
	game.random_character_state("slots",[{"id":1,"team":"Team0","x":center.x,"y":center.y}],40)
	check(draft.pending.size()==1,"host slot snapshot survives local cancellation counters")
	game.random_character_state("cancel",[],41)
	game.random_character_state("slots",[{"id":1,"team":"Team0","x":center.x,"y":center.y}],40)
	check(draft.pending.is_empty(),"stale network slots cannot resurrect a canceled draft")
	draft.network_serial = -1
	world.reset()
	world.queue_free()
	await settle()
	game.Game_Settings = saved
	print("RANDOM_RESTORE_LIFECYCLE checks=",checks," failures=",failures)
	quit(1 if failures else 0)
