extends "res://tests/test_battle_recording.gd"
var Naming:Script
func run() -> void:
	create_timer(100.0,true,false,true).timeout.connect(func(): print("BILINGUAL_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	Naming = load("res://scripts/ui/battle_record_naming.gd")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	var original_locale:String = game.current_locale
	var server_locale:String = TranslationServer.get_locale()
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Mode = false
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world, CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	root.size = Vector2i(540,960)
	await settle(1.0)
	controls = world.control._battle_record_controls
	recorder = controls.recorder
	DirAccess.remove_absolute("user://test_bilingual.cfg")
	recorder.preferences = recorder.PreferencesScript.new("user://test_bilingual.cfg")
	recorder.preferences.directory = "user://recordings/bilingual_test"
	world.control.team.hide()
	world.control.hide()
	var mask:int = root.canvas_cull_mask
	# Exercise actual random creation and its provenance, not just guessed names.
	world.Characters_Dic = {"钻石剑":load("res://scenes/ball.tscn")}
	world._character_scene_cache[world.character_scene_path("钻石剑")] = load("res://scenes/ball.tscn")
	world.create_char("Team0", "random", Vector2.ZERO)
	check(not world._battle_setup.is_empty() and world._battle_setup[-1].get("random_choice",false), "actual random placement records its random provenance")
	world.reset()
	await settle()
	game.Game_Settings.Training_Mode_Type = "rotation"
	world.control.team.show()
	world.create_char("Team0","random",world._rotation_spawn_position("left"))
	check(not world._rotation_rosters.left.is_empty() and world._rotation_rosters.left[-1].get("random_choice",false), "actual random queue placement preserves provenance for special modes")
	world.reset()
	world.control.team.hide()
	game.Game_Settings.Training_Mode_Type = "manual"
	await settle()
	# Freeze an explicit initial matchup for names; all rendering below is a shared World.
	world._battle_setup.assign([{"id":1,"team":"Team0","char":"钻石剑"},{"id":2,"team":"Team1","char":"木剑"},{"id":3,"team":"Team2","char":"牛"}])
	var data:Dictionary = Naming.snapshot(world,false)
	check(Naming.title(data,"zh") == "钻石剑 vs 木剑 vs 牛", "three ordinary sides keep ordered Chinese vs names")
	check(Naming.title(data,"en").contains("Diamond Sword") and Naming.title(data,"en").count(" vs ") == 2, "English matchup uses translated character names")
	var random_data:Dictionary = data.duplicate(true)
	random_data.groups = [{"team":"Team0","members":[{"char":"牛","random_choice":true},{"char":"木剑","random_choice":true},{"char":"钻石剑","random_choice":true}]},{"team":"Team1","members":[{"char":"牛","random_choice":true},{"char":"木剑","random_choice":true},{"char":"钻石剑","random_choice":true}]}]
	check(Naming.title(random_data,"zh") == "3人随机队伍 vs 3人随机队伍", "random 3v3 filenames describe teams, not sampled names")
	check(Naming.title(random_data,"en") == "3-Person Random Team vs 3-Person Random Team", "random team English naming")
	for mode_name:String in ["rotation","timed","boss"]:
		var special:Dictionary = random_data.duplicate(true)
		special.settings.Training_Mode_Type = mode_name
		special.settings.Rotation_Match_Type = "challenge"
		special.settings.Training_Boss_Wheel_Battle = true
		check(Naming.title(special,"zh") != Naming.title(random_data,"zh") and Naming.title(special,"en") != Naming.title(random_data,"en"), "special mode has its own bilingual name: " + mode_name)
	var timed:Dictionary = random_data.duplicate(true)
	timed.settings.Training_Mode_Type = "timed"
	timed.settings.Training_Timed_Duration = 60.0
	print("TIMED_TITLE=",Naming.title(timed,"zh")," / ",Naming.title(timed,"en"))
	check(Naming.title(timed,"zh").begins_with("计时60秒_") and Naming.title(timed,"en").begins_with("Timed 60s_"), "timed filenames contain actual duration")
	var boss:Dictionary = random_data.duplicate(true)
	boss.settings.Training_Mode_Type = "boss"
	boss.settings.Training_Boss_Multiplier = 3.0
	boss.settings.Training_Boss_Wheel_Battle = true
	print("BOSS_TITLE=",Naming.title(boss,"zh")," / ",Naming.title(boss,"en"))
	check(Naming.title(boss,"zh").begins_with("Boss车轮战 x3_") and Naming.title(boss,"en").begins_with("Boss Wheel Battle x3_"), "Boss filenames contain wheel battle and multiplier")
	var unsafe:Dictionary = data.duplicate(true)
	unsafe.groups[0].members[0].char = "A:B/Bad*Name?"
	var safe:String = Naming.filename(unsafe,"en","STAMP","C:/videos")
	check(not safe.contains(":") and not safe.contains("/") and not safe.contains("*") and not safe.contains("?"), "Windows-invalid filename characters sanitized")
	var text := Label.new()
	text.text = "钻石剑 vs 木剑"
	text.position = world.camera_2d.get_screen_center_position() + Vector2(-100,-125)
	text.size = Vector2(200,30)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_theme_font_size_override("font_size",18)
	text.z_index = 150
	world.add_child(text)
	var original_text:String = text.text
	var original_visibility:int = text.visibility_layer
	var marker := ColorRect.new()
	marker.color = Color(0.9,0.5,0.15)
	marker.size = Vector2(10,10)
	marker.position = world.camera_2d.get_screen_center_position() - Vector2(20,5)
	marker.z_index = 900
	world.add_child(marker)
	var tween:Tween = marker.create_tween().set_loops()
	tween.tween_property(marker,"position:x",marker.position.x + 30,0.3)
	tween.tween_property(marker,"position:x",marker.position.x,0.3)
	var tone:AudioStreamPlayer = make_tone(440,&"GameplayRecord")
	check(recorder.start_live(), "one LIVE capture starts two localized outputs")
	await settle(0.6)
	check(is_instance_valid(recorder._secondary) and recorder._frame_index == recorder._secondary._frame_index, "two encoders share the same frame count")
	check(recorder._sim_viewport.world_2d == recorder._secondary._sim_viewport.world_2d, "both variants render the exact same World2D simulation")
	var mirror:Node = recorder._locale_mirror
	check(mirror.translate("[color=#ABCDEF][b]钻石剑[/b][/color]","en",true) == "[color=#ABCDEF][b]Diamond Sword[/b][/color]", "rich text formatting survives translation unchanged")
	check(mirror.translate("Diamond Sword vs Wooden Sword","zh") == "钻石剑 vs 木剑", "English source text also produces a real Chinese version")
	var copies:Dictionary = mirror.copies[text.get_instance_id()]
	check(copies.zh.text.text.contains("钻石剑") and copies.en.text.text.contains("Diamond Sword"), "same on-screen matchup has real Chinese and English text")
	var marks:Dictionary = mirror.copies[world._center_watermark_name.get_instance_id()]
	check(marks.zh.text.text == "@丁某人睡觉" and marks.en.text.text == "@Gameking", "creator watermark is truly localized in each variant")
	check(game.current_locale == original_locale and TranslationServer.get_locale() == server_locale and text.text == original_text, "recording never switches user language or source text")
	await RenderingServer.frame_post_draw
	var zh:Image = recorder._grab_image()
	var en:Image = recorder._secondary._grab_image()
	check(zh.get_region(Rect2i(348,768,384,384)).get_data() == en.get_region(Rect2i(348,768,384,384)).get_data(), "moving battlefield pixels are bit-identical between variants")
	check(zh.get_data() != en.get_data(), "localized text changes actual rendered frames, not just filenames")
	zh.save_png("user://recordings/bilingual_test/zh.png")
	en.save_png("user://recordings/bilingual_test/en.png")
	var clip := Control.new()
	clip.position = Vector2(12,12)
	clip.size = Vector2(20,10)
	clip.clip_contents = true
	world.add_child(clip)
	var clipped_label := Label.new()
	clipped_label.text = "钻石剑"
	clipped_label.size = Vector2(60,15)
	clip.add_child(clipped_label)
	var wasted:Control = load("res://scripts/effects/wasted_overlay.gd").new()
	wasted.name = "WastedOverlay"
	text.add_child(wasted)
	wasted.size = Vector2(120,25)
	await settle(0.1)
	await RenderingServer.frame_post_draw
	check(mirror.copies.has(clipped_label.get_instance_id()) and mirror.copies[clipped_label.get_instance_id()].en.clips.size() == 1, "translated world text retains ancestor clipping")
	check(mirror.copies.has(wasted.get_instance_id()) and mirror.copies[wasted.get_instance_id()].en.text.label().text.length() > 0, "death overlay decoration survives text isolation")
	clip.queue_free()
	wasted.queue_free()
	await settle(0.1)
	var before:int = recorder._frame_index
	game.stop_game(false)
	await settle(0.4)
	check(recorder._frame_index == before and recorder._secondary._frame_index == before, "pause excludes frames from both languages together")
	game.continue_game()
	await settle(0.5)
	text.text = "牛 vs 木剑"
	await settle(0.2)
	check(copies.en.text.text.contains("Cow"), "dynamic translated names update without touching combat")
	recorder.stop()
	await wait_idle()
	check(recorder.last_outputs.size() == 2, "one session saves two final localized MP4 files")
	check(str(recorder.last_outputs.zh).get_file().begins_with("中文_钻石剑 vs 木剑 vs 牛_") and str(recorder.last_outputs.en).get_file().begins_with("English_Diamond Sword vs Wooden Sword vs Cow_"), "both final filenames contain language and initial matchup")
	check(text.visibility_layer == original_visibility and root.canvas_cull_mask == mask, "source visibility and window restored after recording")
	check(game.current_locale == original_locale and TranslationServer.get_locale() == server_locale, "user language still unchanged after finalization")
	check(controls.english_path.text == recorder.last_outputs.en, "result dialog exposes both saved paths")
	var manifest := FileAccess.open("user://recordings/bilingual_test/manifest.json",FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"outputs":recorder.last_outputs,"frames":recorder._frame_index,"checks":checks,"failures":failures},"\t"))
	manifest.close()
	tone.queue_free()
	world.queue_free()
	await process_frame
	await process_frame
	game.Game_Settings = saved
	print("BILINGUAL: %d checks / %d failures" % [checks,failures])
	quit(1 if failures else 0)
