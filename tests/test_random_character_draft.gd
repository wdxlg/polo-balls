extends SceneTree
## Deterministic integration test. Uses tiny ball fixtures instead of unrelated cold Minecraft assets.
var failures:int = 0
var checks:int = 0
var game:Node
var world:Node
var saved:Dictionary

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func wait_draw() -> void:
	var until:int = Time.get_ticks_msec()+6000
	while world.random_character_draft.playing and Time.get_ticks_msec()<until:
		await process_frame
	check(not world.random_character_draft.playing,"draw sequence terminates")
	if world.random_character_draft.playing: world.random_character_draft.cancel(false)
	await process_frame
	await physics_frame

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	check(game.ui_t("SETTING_CHARACTER_METHOD")!="SETTING_CHARACTER_METHOD","new labels exist in runtime CSV translations")
	check("%d" in game.ui_t("RANDOM_CATEGORY_READY"),"pool count translation retains its format placeholder")
	var fresh:Node = load("res://global/game.gd").new()
	check(fresh.Game_Settings.Character_Placement_Mode=="custom","new installations default to custom")
	check(fresh.Game_Settings.Random_Character_Categories.is_empty(),"all random categories default off")
	fresh.free()
	game.Game_Settings.Character_Placement_Mode = "custom"
	game.Game_Settings.Random_Character_Categories = []
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Boss_Intro = false
	game.Game_Settings.Map_Background = "blue"
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	# Its deferred _begin has not run yet. Avoid unrelated asynchronous native-resource jobs in this unit fixture.
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	await process_frame
	await process_frame
	var ui:Control = world.control
	ui._sync_character_mode_controls()
	check(ui.character_mode_option.selected==1,"custom is selected in settings")
	var box:Node = ui.settings_category_boxes.training
	check(box.get_node("CharacterMethodRow").get_index()<box.get_node("TrainingModeRow").get_index(),"character method appears above Mode")
	check(not ui.random_category_box.visible,"category options hidden in custom mode")
	for button:Button in ui.random_category_buttons.values():
		check(not button.button_pressed,"category starts off: "+button.text)
	var folder_names:PackedStringArray = world.random_character_draft.categories()
	check(folder_names.size()>=2,"existing category index available")
	if folder_names.size()<2:
		quit(1)
		return
	var first:String = folder_names[0]
	var second:String = folder_names[1]
	world._char_folder_names = PackedStringArray([first,second])
	world._character_paths_by_folder = {first:{"DraftProbeA":"res://scenes/ball.tscn"},second:{"DraftProbeB":"res://scenes/ball.tscn"}}
	world.Characters_Dic = world._character_paths_by_folder[first].duplicate()
	var draft:RefCounted = world.random_character_draft
	draft.animation_scale = 0.0
	var map_rect:Rect2 = world.return_map_world_rect(world.map_group[world.now_choose_map])
	var left:Vector2 = map_rect.get_center()-Vector2(24,0)
	var right:Vector2 = map_rect.get_center()+Vector2(24,0)
	game.set_runtime_game_setting("Character_Placement_Mode","random",false)
	ui._sync_character_mode_controls()
	check(ui.random_category_box.visible,"random mode exposes categories")
	check(not draft.can_place() and not draft.place("",left),"empty pool does not fall back to all characters")
	game.set_runtime_game_setting("Random_Character_Categories",[second],false)
	check(draft.pool().size()==1 and draft.pool()[0].char=="DraftProbeB","pool strictly respects enabled categories")
	game.create_ball_in_server("Team0","DraftProbeA",left)
	game.create_ball_in_server("Team1","DraftProbeA",right)
	check(draft.pending.size()==2,"server placement creates pending slots, not the selected custom character")
	check(get_nodes_in_group("Ball").is_empty(),"placeholders are not combat units")
	check(not world.is_combat_runtime_active(),"pending draft blocks combat")
	check(draft._visuals.values()[0].get_script()==draft._visuals.values()[1].get_script(),"all slots share one fixed silhouette")
	game._delete_char_at_authority(left)
	check(draft.pending.size()==1,"right-click path deletes exactly one placeholder")
	game.create_ball_in_server("Team0","DraftProbeA",left)
	game.set_runtime_game_setting("Random_Character_Categories",[],false)
	ui.show()
	world.set_menu()
	check(ui.visible and not draft.playing and draft.pending.size()==2,"closing with an emptied pool keeps placement and opens settings")
	game.set_runtime_game_setting("Random_Character_Categories",[second],false)
	world.set_menu()
	check(draft.playing and paused,"closing toolbar begins a paused reveal sequence")
	check(not ui.visible and not world.is_combat_runtime_active(),"battle remains locked during the reveal")
	var serial:int = draft._serial
	world.set_menu()
	check(draft._serial==serial and draft.playing,"repeated toolbar input cannot launch a duplicate draw")
	await wait_draw()
	check(not paused and draft.pending.is_empty(),"completion restores time and consumes all slots")
	check(world._battle_setup.size()==2,"every revealed slot becomes a recorded character")
	for entry:Dictionary in world._battle_setup:
		check(entry.char=="DraftProbeB" and entry.scene_path=="res://scenes/ball.tscn","revealed identity and path retained for rematch")
	check(world.is_combat_runtime_active(),"manual battle starts only after all reveals")
	world.reset()
	await process_frame
	ui.show()
	game.create_ball_in_server("Team0","",left)
	check(draft.pending.size()==1,"random mode does not require a selected character")
	world.set_menu()
	world.reset()
	await process_frame
	await process_frame
	check(not draft.playing and not paused and draft.pending.is_empty(),"reset cancels an in-flight draw and releases pause")
	check(world._battle_setup.is_empty(),"canceled coroutines do not create late characters")

	for mode:String in ["timed","rotation","boss"]:
		game.Game_Settings.Training_Mode_Type = mode
		world.reset()
		await process_frame
		ui.show()
		ui.team.show()
		game.create_ball_in_server("Team0","",left)
		game.create_ball_in_server("Team1","",right)
		check(draft.pending.size()==2,mode+": both sides accept random slots")
		world.set_menu()
		check(not world.is_combat_runtime_active(),mode+": does not begin mid-reveal")
		await wait_draw()
		await process_frame
		check(world.is_combat_runtime_active(),mode+": original start flow resumes after draw")

	game.Game_Settings.Training_Mode_Type = "manual"
	world.reset()
	await process_frame
	ui.show()
	game.create_ball_in_server("","",left)
	paused = true
	world.set_menu()
	await wait_draw()
	check(paused,"a pre-existing user pause is preserved after drawing")
	paused = false
	world.reset()
	await process_frame
	# Normal-speed exit must keep the battle paused; cancel during exit must
	# invalidate the waiter rather than resuming the old draw after a reset.
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Character_Placement_Mode = "random"
	game.Game_Settings.Random_Character_Categories = [second]
	draft.animation_scale = 0.05
	for cancel_exit:bool in [false,true]:
		world.reset()
		await process_frame
		ui.show()
		game.create_ball_in_server("Team0","",left)
		world.set_menu()
		var exit_deadline:int = Time.get_ticks_msec()+6000
		while draft.playing and is_instance_valid(draft.overlay) and draft.overlay._exit_started_at<0 and Time.get_ticks_msec()<exit_deadline:
			await process_frame
		check(is_instance_valid(draft.overlay) and draft.overlay._exit_started_at>=0,"normal draw reaches animated exit")
		check(draft.playing and paused and not world.is_combat_runtime_active(),"battle remains locked through exit")
		if cancel_exit:
			world.reset()
			var settle_until:int = Time.get_ticks_msec()+550
			while Time.get_ticks_msec()<settle_until: await process_frame
			check(not draft.playing and not paused and draft.overlay==null,"reset during exit releases the layer and pause")
			check(world._battle_setup.is_empty(),"canceled exit cannot resume the old battle")
		else:
			await wait_draw()
			check(not paused and draft.overlay==null and world.is_combat_runtime_active(),"battle resumes only after exit completes")
	game.Game_Settings = saved
	world.queue_free()
	await process_frame
	print("RANDOM_CHARACTER_DRAFT checks=",checks," failures=",failures)
	quit(1 if failures else 0)
