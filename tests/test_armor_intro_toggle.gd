extends "res://tests/test_armor_intro_readability.gd"
const KEY:String="Show_Armor_Stand_Intro"
func run() -> void:
	create_timer(70.0,true,false,true).timeout.connect(func():push_error("ARMOR_TOGGLE_TIMEOUT");quit(2))
	game=root.get_node("Game")
	var saved:Dictionary=game.Game_Settings.duplicate(true)
	# 设置读写全部走临时文件，不改玩家自己的 settings.cfg。
	var saved_settings_path:String=game._settings_storage_path
	game._settings_storage_path="user://test_armor_intro_toggle_settings.cfg"
	game.save_persistent_settings()
	var locale_before:String=game.current_locale
	check(game.Game_Settings.get(KEY,false)==true,"new preference defaults on")
	check(not game._is_network_shared_setting(KEY) and not game._shared_settings_snapshot().has(KEY),"local display preference is not sent as a room gameplay setting")
	game.Game_Settings.Development_Mode=false;game.Game_Settings.Training_Mode=false;game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Map_Background="blue";game.Game_Settings.Minecraft_Clouds=false;game.Game_Settings.Only_In_Game_Translation=false
	game.set_language("zh",false)
	root.size=Vector2i(540,960)
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT);root.add_child(world)
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.free()
	world._mc_prewarmer=null
	world.set_process(false);world.set_physics_process(false)
	world.now_choose_map="Map10x10";world.refresh_map_presentation()
	var center:Vector2=world.return_map_world_rect(world.map_group["Map10x10"]).get_center()
	world.camera_2d.global_position=center;world.camera_2d.force_update_scroll()
	var ui:Control=world.control
	var toggle:TextureButton
	var count:int=0
	for node:Node in ui._collect_descendants(ui.settings_category_boxes.parameters):
		if node is TextureButton and node.get_meta("game_setting_key","")==KEY:toggle=node;count+=1
	check(count==1,"generic parameters page creates exactly one working toggle")
	if toggle==null:quit(1);return
	var row:Control=toggle.get_parent().get_parent()
	for lang:String in ["zh","en"]:
		game.set_language(lang,false);ui.game_setting.show();ui._show_settings_category("parameters")
		await drawn_frame();ui.settings_scroll.ensure_control_visible(row);await drawn_frame()
		var label:Label=row.get_node("Text/Label")
		check(label.text==game.ui_t("SETTING_SHOW_ARMOR_STAND_INTRO") and not label.text.begins_with("SETTING_"),lang+" settings label translated")
		check(row.get_global_rect().end.x<=ui.settings_scroll.get_global_rect().end.x+1,lang+" toggle stays within settings width")
		check(preload("res://global/translation_catalog.gd").TABLE[lang].get("SETTING_SHOW_ARMOR_STAND_INTRO","")==game.t("SETTING_SHOW_ARMOR_STAND_INTRO"),lang+" compiled export catalog matches runtime text")
		save_capture(root,"armor-toggle-settings-"+lang)
	game.set_language("zh",false);ui.game_setting.hide();ui.get_parent().hide()
	var stand:Node2D=load("res://scenes/characters/默认/虚无盔甲架.tscn").instantiate()
	stand.Team="A";stand.position=center-Vector2(30,0);world.add_child(stand,true);stand.process_mode=Node.PROCESS_MODE_DISABLED
	world.refresh_versus_text();check(not world.armor_intro_label.visible,"stand alone has no empty introduction")
	var actor:Node2D=load("res://scenes/characters/我的世界/烈焰人.tscn").instantiate()
	actor.Team="B";actor.position=center+Vector2(30,0);world.add_child(actor,true);actor.process_mode=Node.PROCESS_MODE_DISABLED
	world.refresh_versus_text();await drawn_frame()
	var actor_id:int=actor.get_instance_id();var health:float=actor.health
	check(world.armor_intro_label.visible and not world.versus_label.visible,"default shows actual character introduction without VS")
	var mirror:Node=load("res://scripts/ui/battle_record_locale.gd").new();world.add_child(mirror)
	var views:Dictionary={}
	for lang:String in ["zh","en"]:
		var view:=SubViewport.new();view.size=Vector2i(1080,1920);view.world_2d=root.world_2d
		view.canvas_cull_mask=1|((1<<17) if lang=="zh" else (1<<18));view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		root.add_child(view);view.canvas_transform=root.canvas_transform;views[lang]=view
	mirror.begin(world,root,views);mirror.sync();await drawn_frame()
	var intro_id:int=world.armor_intro_label.get_instance_id()
	for value:bool in [false,true,false,true]:
		# Exercise the actual TextureButton signal and existing save/settings-signal path.
		toggle.button_up.emit()
		check(game.Game_Settings[KEY]==value and world.armor_intro_label.visible==value,"button changes live visibility immediately: "+str(value))
		mirror.sync();await drawn_frame()
		for lang:String in ["zh","en"]:
			check(mirror.copies[intro_id][lang].holder.visible==value,lang+" recording mirror follows setting: "+str(value))
		check(not world.versus_label.visible and world._armor_stand_test_hud_active,"hiding prose does not restore VS or change armor-test rules")
		save_capture(root,"armor-toggle-"+str(value))
	check(actor.get_instance_id()==actor_id and actor.health==health,"toggle neither resets nor heals the character")
	game.set_runtime_game_setting(KEY,false)
	var config:=ConfigFile.new();var err:Error=config.load(game._settings_storage_path)
	check(err==OK and config.get_value("game_settings",KEY,true)==false,"off choice saved via standard settings file")
	game.Game_Settings[KEY]=true;game.load_persistent_settings();world.refresh_versus_text()
	check(game.Game_Settings[KEY]==false and not world.armor_intro_label.visible,"saved off choice survives settings reload")
	# Missing preference in an old save retains the declared default.
	config.erase_section_key("game_settings",KEY);config.save(game._settings_storage_path)
	game.Game_Settings[KEY]=true;game.load_persistent_settings();world.refresh_versus_text()
	check(game.Game_Settings[KEY]==true and world.armor_intro_label.visible,"old save missing the new key remains enabled")
	game.set_runtime_game_setting(KEY,false,false)
	var late_mirror:Node=load("res://scripts/ui/battle_record_locale.gd").new();world.add_child(late_mirror)
	late_mirror.begin(world,root,{})
	late_mirror.sync();check(not late_mirror.copies.has(intro_id),"recording started with setting off does not discover a visible intro")
	late_mirror.finish();late_mirror.queue_free()
	game.set_runtime_game_setting(KEY,true,false)
	world._dead_save_ui_override_active=true;world.refresh_versus_text()
	check(not world.armor_intro_label.visible,"enabled setting does not bypass death-save suppression")
	world._dead_save_ui_override_active=false
	game.set_runtime_game_setting(KEY,false,false)
	stand.free();var _opponent:Node=spawn_named("钻石剑","A");world.refresh_versus_text();mirror.sync()
	check(world.versus_label.visible and not world.armor_intro_label.visible,"disabled setting does not suppress ordinary matchup")
	var before_text:String=world.versus_label.text
	game.set_runtime_game_setting(KEY,true,false)
	check(world.versus_label.text==before_text and world.versus_label.visible,"ordinary matchup unchanged when toggled on")
	mirror.finish();mirror.queue_free()
	for view:SubViewport in views.values():view.queue_free()
	world.queue_free();await process_frame
	game.Game_Settings=saved;game.set_language(locale_before,false)
	game._settings_storage_path=saved_settings_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_armor_intro_toggle_settings.cfg"))
	print("ARMOR_INTRO_TOGGLE checks=%d failures=%d"%[checks,failures]);quit(1 if failures else 0)
