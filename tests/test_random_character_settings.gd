extends SceneTree
## Run with APPDATA isolated under _random_settings_userdata; exercises real UI saves.
var checks:int = 0
var failures:int = 0
var game:Node
var world:Node
var ui:Control
var draft:RefCounted
var visual:bool = false
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: "+label)
func settle() -> void:
	for i:int in range(5): await process_frame
func disable_spawners(node:Node) -> void:
	if node.has_method("is_character_spawn_layer"): node.spawning_enabled = false
	for child:Node in node.get_children(): disable_spawners(child)
func button_named(character_name:String) -> Button:
	for child:Node in ui.char_box.get_children():
		if child is Button and not child.is_queued_for_deletion() and str(child.get_meta("choice_value",""))==character_name: return child
	return null
func click_character(character_name:String) -> void:
	var button:Button = button_named(character_name)
	check(button!=null and not button.disabled,"character can be clicked: "+character_name)
	if button==null or button.disabled: return
	var point:Vector2 = button.get_global_transform_with_canvas()*(button.size*0.5)
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event,true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event,true)
	await settle()
func capture(name:String) -> void:
	if not visual: return
	await settle()
	await RenderingServer.frame_post_draw
	var image:Image = root.get_texture().get_image()
	if root.use_hdr_2d:
		image.convert(Image.FORMAT_RGBA8)
		image.linear_to_srgb()
	image.resize(540,960,Image.INTERPOLATE_LANCZOS)
	image.save_jpg("user://"+name+".jpg",0.92)
func run() -> void:
	visual = "--visual" in OS.get_cmdline_user_args()
	print("SETTINGS_TEST_USERDATA=",OS.get_user_data_dir())
	if not OS.get_user_data_dir().contains("_random_settings_userdata"):
		push_error("Refusing to modify real user settings; isolate APPDATA before this test")
		quit(2)
		return
	game = root.get_node("Game")
	game.Game_Settings.Character_Placement_Mode = "custom"
	game.Game_Settings.Random_Character_Categories = []
	game.Game_Settings.Random_Character_Excluded = []
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Map_Background = "blue"
	game.Game_Settings.Only_In_Game_Translation = false
	game.set_language("zh",false)
	world = load("res://scenes/world.tscn").instantiate()
	disable_spawners(world)
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	await settle()
	ui = world.control
	draft = world.random_character_draft
	world._char_folder_names = PackedStringArray(["人物","动物"])
	world._character_paths_by_folder = {
		"人物":{"剑客":"res://scenes/ball.tscn","保安":"res://scenes/ball.tscn","猎人":"res://scenes/ball.tscn","石头":"res://scenes/characters/默认/石头.tscn"},
		"动物":{"牛":"res://scenes/ball.tscn","剑客":"res://scenes/ball.tscn"}}
	world.now_char_folder_index = 0
	world.set_char_dic()
	world.now_choose_char = "猎人"
	ui.Create_char_buts()
	ui.show()
	ui.team.hide()
	ui.game_setting.show()
	ui._sync_character_mode_controls()
	await settle()
	var box:Node = ui.settings_category_boxes.training
	var method_row:Control = box.get_node("CharacterMethodRow")
	var mode_row:Control = box.get_node("TrainingModeRow")
	var gap:float = mode_row.position.y-method_row.get_rect().end.y
	check(gap>=0 and gap<=3.0,"custom method and mode have only the normal compact row gap")
	check(not ui.random_category_box.visible,"custom mode hides the entire random section")
	await capture("random_settings_compact")
	ui.character_mode_option.item_selected.emit(0)
	ui.random_category_buttons["人物"].button_pressed = true
	ui.random_category_buttons["动物"].button_pressed = true
	check(draft.pool().size()==5,"enabled categories include characters, not obstacles")
	ui.game_setting.hide()
	ui.team.show()
	await settle()
	check(ui.char_search.editable,"search stays enabled in random mode")
	check(button_named("石头").disabled,"terrain is not an excludable random character")
	check(button_named("石头").tooltip_text==game.ui_t("RANDOM_CHARACTER_OBSTACLE"),"disabled terrain is not described as eligible")
	await click_character("剑客")
	check(button_named("剑客").button_pressed and draft.is_excluded("人物/剑客"),"actual mouse click presses and excludes a character")
	check(button_named("剑客").text.begins_with("X ") and button_named("剑客").self_modulate.g<0.5,"excluded characters carry a persistent red cross, not just a pressed offset")
	check(button_named("剑客").tooltip_text==game.ui_t("RANDOM_CHARACTER_EXCLUDED"),"exclusion tooltip explains that this character cannot be drawn")
	check(world.now_choose_char=="猎人","excluding never changes the custom placement choice")
	check(draft.pool().size()==4,"exclusion immediately invalidates the cached pool")
	var duplicate_survives:bool = false
	for entry:Dictionary in draft.pool():
		if entry.category=="动物" and entry.char=="剑客": duplicate_survives = true
	check(duplicate_survives,"same name in a different category is not accidentally excluded")
	await click_character("保安")
	check(button_named("保安").button_pressed and button_named("剑客").button_pressed,"exclusion is multi-select, not a radio group")
	check(draft.pool().size()==3,"both exclusions reach the authoritative pool")
	await capture("random_settings_excluded")
	ui.character_mode_option.item_selected.emit(1)
	check(game.Game_Settings.Random_Character_Categories.size()==2 and game.Game_Settings.Random_Character_Excluded.size()==2,"switching to custom retains both independent settings")
	check(not button_named("剑客").toggle_mode and not button_named("剑客").button_pressed,"custom mode does not display exclusion press states")
	check(not button_named("剑客").text.begins_with("X ") and button_named("剑客").self_modulate==Color.WHITE,"custom mode removes exclusion marks and colors")
	await click_character("保安")
	check(world.now_choose_char=="保安","custom selection still works normally")
	check(game.Game_Settings.Random_Character_Excluded.size()==2,"custom selection does not edit exclusions")
	ui.character_mode_option.item_selected.emit(0)
	check(ui.random_category_buttons["人物"].button_pressed and ui.random_category_buttons["动物"].button_pressed,"category switches restore their selected state")
	check(button_named("剑客").button_pressed and button_named("保安").button_pressed,"returning to random restores the exclusion press states")
	ui.Create_char_buts()
	await settle()
	check(button_named("剑客").button_pressed,"rebuilding the character panel preserves exclusions")
	ui.char_search.text = "牛"
	ui._on_character_search_changed("牛")
	await settle()
	await click_character("牛")
	check(draft.is_excluded("动物/牛"),"cross-category search can exclude by stable identity")
	ui.char_search.text = ""
	ui._on_character_search_changed("")
	await settle()
	await click_character("剑客")
	check(not button_named("剑客").button_pressed and not draft.is_excluded("人物/剑客"),"second click restores eligibility")
	check(not button_named("剑客").text.begins_with("X ") and button_named("剑客").self_modulate==Color.WHITE,"unexcluding immediately restores the ordinary button appearance")
	ui.random_category_buttons["动物"].button_pressed = false
	ui.random_category_buttons["动物"].button_pressed = true
	check(draft.is_excluded("动物/牛"),"disabling a category does not erase its character exclusions")
	game.set_language("en",false)
	ui._sync_character_mode_controls()
	check(draft.is_excluded("动物/牛") and draft.is_excluded("人物/保安"),"language changes cannot change exclusion identity")
	check(ui.now_char.text==game.ui_t("RANDOM_EXCLUDE_PICKER") and not ui.now_char.text.begins_with("RANDOM_"),"picker explains pressed means excluded in the current language")
	check(button_named("保安").text.begins_with("X ") and button_named("保安").tooltip_text==game.ui_t("RANDOM_CHARACTER_EXCLUDED"),"language refresh preserves the exclusion cross and translates its explanation")
	await capture("random_settings_excluded_en")
	game.set_language("zh",false)
	game.save_persistent_settings()
	var expected_categories:Array = game.Game_Settings.Random_Character_Categories.duplicate()
	var expected_exclusions:Array = game.Game_Settings.Random_Character_Excluded.duplicate()
	var config := ConfigFile.new()
	check(config.load(game.SETTINGS_PATH)==OK,"random preferences save to the isolated real settings file")
	check(config.get_value("game_settings","Random_Character_Excluded",[])==expected_exclusions,"saved config contains exclusions")
	game.Game_Settings.Random_Character_Categories = []
	game.Game_Settings.Random_Character_Excluded = []
	game.load_persistent_settings()
	ui._sync_character_mode_controls()
	check(game.Game_Settings.Random_Character_Categories==expected_categories and game.Game_Settings.Random_Character_Excluded==expected_exclusions,"settings reload restores categories and exclusions")
	check(button_named("保安").button_pressed,"UI restores the persisted press state")
	check(game._shared_settings_snapshot().has("Random_Character_Excluded"),"exclusions participate in existing shared-setting synchronization")
	game._apply_runtime_game_setting_local("Random_Character_Excluded",["人物/保安","人物/保安",7,"",{}],false)
	check(game.Game_Settings.Random_Character_Excluded==["人物/保安"],"invalid and duplicate saved/network entries are sanitized")
	# Guest guard without contacting a remote game server.
	var previous_peer:MultiplayerPeer = world.multiplayer.multiplayer_peer
	var previous_role:String = game.network_role
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1",9)
	world.multiplayer.multiplayer_peer = peer
	game.network_role = "client"
	game.Game_Settings.Guest_Free_Permissions = false
	ui._sync_character_mode_controls()
	check(button_named("剑客").disabled,"restricted guests cannot change shared exclusions")
	ui._toggle_random_character_exclusion(button_named("剑客"))
	check(game.Game_Settings.Random_Character_Excluded==["人物/保安"],"handler also rejects a restricted guest even if called directly")
	world.multiplayer.multiplayer_peer = previous_peer
	game.network_role = previous_role
	peer.close()
	ui._sync_character_mode_controls()
	# All excluded means no fallback, and actual authority draws use only survivors.
	game.set_runtime_game_setting("Random_Character_Categories",["人物"],false)
	game.set_runtime_game_setting("Random_Character_Excluded",["人物/剑客","人物/保安","人物/猎人"],false)
	ui._sync_character_mode_controls()
	check(draft.pool().is_empty() and not draft.can_place(),"excluding every eligible character blocks placement without fallback")
	check(ui.random_category_hint.text.contains(game.ui_t("RANDOM_POOL_EMPTY")),"empty pool explains how to unexclude instead of saying all categories are off")
	game.set_runtime_game_setting("Random_Character_Excluded",["人物/剑客","人物/保安"],false)
	check(draft.pool().size()==1 and draft.pool()[0].char=="猎人","restoring one character updates the pool immediately")
	ui._sync_character_mode_controls()
	ui.team.hide()
	ui.game_setting.show()
	await capture("random_settings_saved")
	world.reset()
	await settle()
	ui.show()
	draft.animation_scale = 0.0
	var center:Vector2 = world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	for i:int in range(4): draft.place("Team0",center+Vector2(i*15,0))
	world.set_menu()
	var deadline:int = Time.get_ticks_msec()+7000
	while draft.playing and Time.get_ticks_msec()<deadline: await process_frame
	check(not draft.playing and world._battle_setup.size()==4,"authority creates all four non-excluded characters")
	for entry:Dictionary in world._battle_setup: check(entry.char=="猎人","excluded characters never spawn from the draw")
	check(game.Game_Settings.Random_Character_Excluded==["人物/剑客","人物/保安"],"reset and drawing do not clear preferences")
	world.reset()
	world.queue_free()
	await settle()
	print("RANDOM_CHARACTER_SETTINGS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
