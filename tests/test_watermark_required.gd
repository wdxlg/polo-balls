extends "res://tests/test_watermark_follow.gd"

func count_setting(node:Node,key:String) -> int:
	var count:int = 1 if str(node.get_meta("game_setting_key",""))==key else 0
	for child:Node in node.get_children(): count += count_setting(child,key)
	return count

func run() -> void:
	if not OS.get_user_data_dir().contains("_watermark_settings_userdata"):
		push_error("Refusing to touch real settings; isolate APPDATA for this test")
		quit(2)
		return
	original_locale = root.get_node("Game").current_locale
	await setup_world()
	create_timer(60.0,true,false,true).timeout.connect(func(): finish(2))
	check(not game.Game_Settings.has("Show_Center_Watermark"),"watermark switch is absent from live default settings")
	var ui:Control = world.control
	check(is_instance_valid(ui.settings_stack),"actual settings UI is built")
	for locale:String in ["zh","en"]:
		set_test_language(locale)
		await process_frame
		check(count_setting(ui.settings_stack,"Show_Center_Watermark")==0,"no watermark toggle exists in actual settings: "+locale)
		check(count_setting(ui.settings_stack,"Only_In_Game_Translation")==1,"other parameter toggle is preserved: "+locale)
		world._refresh_center_watermark()
		check(world._center_watermark_root.visible and world._center_watermark_follow.visible,"watermark remains visible in "+locale)
	# Write legacy false only into the isolated test profile.
	var config := ConfigFile.new()
	config.set_value("game_settings","Show_Center_Watermark",false)
	config.set_value("game_settings","Camera_Move",false)
	config.set_value("ui","locale","zh")
	config.set_value("fixture_keep","sentinel","preserved")
	check(config.save(game.SETTINGS_PATH)==OK,"isolated legacy-off settings file created")
	game.Game_Settings["Show_Center_Watermark"] = false
	game.Game_Settings.Camera_Move = true
	game.load_persistent_settings()
	check(not game.Game_Settings.has("Show_Center_Watermark"),"loading clears the retired key rather than restoring legacy false")
	check(not game.Game_Settings.Camera_Move,"unrelated old setting still loads normally")
	world._refresh_center_watermark()
	check(world._is_center_watermark_enabled() and world._center_watermark_root.visible,"legacy-off file cannot hide the watermark")
	game.set_runtime_game_setting("Show_Center_Watermark",false,false)
	game._receive_shared_setting("Show_Center_Watermark",false)
	check(not game.Game_Settings.has("Show_Center_Watermark") and world._is_center_watermark_enabled(),"stale local or shared setting requests cannot restore the removed feature")
	# Even an old dictionary injected by scene state cannot rebuild the UI toggle.
	game.Game_Settings["Show_Center_Watermark"] = false
	var rebuilt := VBoxContainer.new()
	ui.add_child(rebuilt)
	ui._build_parameter_settings(rebuilt)
	check(count_setting(rebuilt,"Show_Center_Watermark")==0,"parameter rebuild excludes a legacy injected key")
	check(count_setting(rebuilt,"Only_In_Game_Translation")==1,"rebuild retains remaining controls")
	world._refresh_center_watermark()
	check(world._center_watermark_root.visible and world._center_watermark_follow.visible,"runtime legacy dictionary also cannot hide either line")
	check(not game._shared_settings_snapshot().has("Show_Center_Watermark"),"retired key is never advertised to multiplayer peers")
	game.save_persistent_settings()
	var reloaded := ConfigFile.new()
	check(reloaded.load(game.SETTINGS_PATH)==OK,"settings save remains readable")
	check(not reloaded.has_section_key("game_settings","Show_Center_Watermark") and not game.Game_Settings.has("Show_Center_Watermark"),"next save removes the obsolete key from disk and memory")
	check(reloaded.get_value("fixture_keep","sentinel","")=="preserved" and reloaded.get_value("game_settings","Camera_Move",true)==false,"save preserves unrelated sections and settings")
	game.load_persistent_settings()
	check(not game.Game_Settings.has("Show_Center_Watermark") and world._is_center_watermark_enabled(),"reload after save cannot resurrect the switch")
	world.set_dead_save_ui_override(true)
	check(world._dead_save_watermark_name.visible and not world._center_watermark_follow.visible,"special dead-save presentation is not broken by mandatory watermark")
	world.set_dead_save_ui_override(false)
	check(world._center_watermark_follow.visible and world._center_watermark_root.visible,"normal watermark returns after the special presentation")
	print("WATERMARK_REQUIRED_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
