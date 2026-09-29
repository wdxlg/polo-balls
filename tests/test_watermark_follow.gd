extends "res://tests/test_mc_bat_transform.gd"

var original_locale:String = "zh"

func set_test_language(locale:String,ui_only:bool = false) -> void:
	game.current_locale = locale
	game.Game_Settings.Only_In_Game_Translation = ui_only
	game._apply_translation_server_locale()
	# Use the same handler that the language-change signal calls in production.
	world._on_language_changed(locale)

func verify_layout(rect:Rect2,label:String) -> void:
	world._refresh_center_watermark_layout(rect)
	var row:Control = world._center_watermark_row
	var follow:Label = world._center_watermark_follow
	var marker:Control = world._center_watermark_root
	check(follow.position.y >= row.position.y+row.size.y+3.9,label+" second row is below the creator name")
	check(is_zero_approx(follow.position.x+follow.size.x*0.5),label+" second row is horizontally centered")
	check(is_equal_approx(marker.global_position.x,rect.get_center().x),label+" both rows track map center")
	var width_ratio:float = world.center_watermark_english_map_width_ratio if not str(game.current_locale).begins_with("zh") else world.center_watermark_map_width_ratio
	check(follow.size.x*marker.scale.x <= rect.size.x*width_ratio+0.1,label+" text fits its language width budget")
	var top:float = marker.global_position.y+row.position.y*marker.scale.y
	check(is_equal_approx(top,rect.end.y+world.center_watermark_bottom_gap),label+" creator row keeps its original gap below the map")
	check(marker.scale.x > 0.0 and marker.scale.x <= 1.0,label+" scale remains positive and never enlarges")

func run() -> void:
	original_locale = root.get_node("Game").current_locale
	await setup_world()
	create_timer(60.0).timeout.connect(func(): finish(2))
	check(not game.Game_Settings.has("Show_Center_Watermark"),"retired watermark switch is absent from defaults")
	set_test_language("zh")
	await process_frame
	var follow:Label = world._center_watermark_follow
	check(is_instance_valid(follow),"watermark follow label exists")
	check(follow.text == "点赞加关注！","Chinese CTA matches requested punctuation")
	check(world._center_watermark_name.text == "@丁某人睡觉","Chinese creator name remains unchanged")
	check(follow.get_parent() == world._center_watermark_root,"CTA moves and scales with the original watermark")
	check(follow.mouse_filter == Control.MOUSE_FILTER_IGNORE,"CTA does not intercept game input")
	check(is_equal_approx(follow.modulate.a,world.center_watermark_opacity),"CTA inherits watermark opacity")
	verify_layout(Rect2(100,200,1000,1000),"Chinese")
	set_test_language("en")
	await process_frame
	check(follow.text == "Like and Subscribe!","English CTA is exact")
	check(world._center_watermark_name.text == "@Gameking","English creator name remains unchanged")
	verify_layout(Rect2(100,200,1000,1000),"English")
	check(world._center_watermark_root.scale.x >= 0.9,"English watermark stays near full size on a large map")
	verify_layout(Rect2(-80,50,240,500),"Small map")
	verify_layout(Rect2(0,0,1600,800),"Wide map")
	set_test_language("en",true)
	await process_frame
	check(game.get_ui_locale() == "zh" and follow.text == "Like and Subscribe!","in-game-only English keeps both watermark lines in game language")
	check(follow.auto_translate_mode == Node.AUTO_TRANSLATE_MODE_DISABLED,"automatic UI translation cannot overwrite the in-game CTA")
	game.Game_Settings.Show_Center_Watermark = false
	world._refresh_center_watermark()
	check(world._center_watermark_root.visible and follow.is_visible_in_tree(),"legacy false value cannot hide either watermark line")
	game.Game_Settings.erase("Show_Center_Watermark")
	world._refresh_center_watermark()
	check(world._center_watermark_root.visible and follow.is_visible_in_tree(),"watermark remains visible without an optional key")
	world.set_dead_save_ui_override(true)
	check(not follow.visible and world._dead_save_watermark_name.visible,"special dead-save presentation still replaces the normal watermark")
	world.set_dead_save_ui_override(false)
	check(follow.visible and follow.text == "Like and Subscribe!","CTA returns after special presentation")
	var children:int = world._center_watermark_root.get_child_count()
	world._setup_center_watermark()
	check(world._center_watermark_root.get_child_count() == children,"reinitializing watermark does not duplicate CTA")
	set_test_language("zh")
	await process_frame
	check(follow.text == "点赞加关注！","switching back restores Chinese CTA")
	check(game._load_compiled_translation_catalog(),"export-safe translation catalog loads")
	set_test_language("en")
	check(follow.text == "Like and Subscribe!","compiled catalog also supplies English CTA")
	finish(0 if failures == 0 else 1)

func finish(code:int) -> void:
	if game != null:
		game.current_locale = original_locale
		game.Game_Settings.Only_In_Game_Translation = saved.get("Only_In_Game_Translation",false)
		game._apply_translation_server_locale()
	super.finish(code)
