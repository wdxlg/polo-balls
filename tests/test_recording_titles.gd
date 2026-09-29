extends "res://tests/test_battle_recording.gd"

var actors:Array[Node2D] = []
var evidence:Array[Dictionary] = []
var output_dir:String

func set_matchup(names:Array[String]) -> void:
	for actor:Node2D in actors:
		world.remove_child(actor)
		actor.queue_free()
	actors.clear()
	world._battle_setup.clear()
	var center:Vector2 = world.return_map_world_rect(world._current_map_node()).get_center()
	for i:int in range(names.size()):
		var actor:Node2D = load("res://scenes/ball.tscn").instantiate()
		actor.Team = "Team0" if i % 2 == 0 else "Team1"
		actor.set_meta("morph_display_name",names[i])
		actor.position = center + Vector2(-28 if i%2 == 0 else 28, float(i/2)*14-14)
		world.add_child(actor,true)
		actor.Can_Attack = false
		actor.Can_Skill = false
		actor.set_physics_process(false)
		actor.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
		actors.append(actor)
		world._battle_setup.append({"id":i+1,"team":actor.Team,"char":names[i]})
	world._last_versus_text = ""
	world.refresh_versus_text()
	world.refresh_top_text_layout()

func check_frame(label:String) -> void:
	var mirror:Node = recorder._locale_mirror
	mirror.sync()
	await RenderingServer.frame_post_draw
	var source:RichTextLabel = world.versus_label
	check(source.visible and mirror.copies.has(source.get_instance_id()),label+": actual World VS is mirrored")
	if not mirror.copies.has(source.get_instance_id()): return
	var rect:Rect2 = world.return_map_visual_rect(world._current_map_node())
	var before_text:String = source.text
	var before_rect:Rect2 = source.get_rect()
	for language:String in ["zh","en"]:
		var variant:Node = recorder if language == "zh" else recorder._secondary
		var viewport:SubViewport = variant._sim_viewport as SubViewport
		var composition:CanvasLayer = viewport.get_node("RecordingComposition") as CanvasLayer
		var unwanted_chrome:bool = false
		for node:Node in composition.get_children():
			if node is Label and (node.name == "MatchTitle" or node.text == "BATTLE REPLAY" or node.text == "对战实况"):
				unwanted_chrome = true
			if node is ColorRect:
				var panel:ColorRect = node as ColorRect
				if panel.size.x > viewport.size.x*0.85: unwanted_chrome = true
		check(not unwanted_chrome,label+" "+language+": no replay caption, match title or full-width dark header")
		if recorder._composition != recorder.preferences.FOLLOW_OVERVIEW:
			check(composition.get_child_count() == 0,label+" "+language+": full/follow export has no screen-space title or banner")
		var copy:RichTextLabel = mirror.copies[source.get_instance_id()][language].text
		# 副本固定于录制屏幕；跟拍取景没有顶部留白时应隐藏，避免遮住战斗。
		var to_record_screen:Transform2D = copy.get_global_transform_with_canvas()
		var bottom:Vector2 = to_record_screen*Vector2(0,copy.get_content_height())
		var box_bottom:Vector2 = to_record_screen*Vector2(0,copy.size.y)
		check(copy.get_content_height() <= copy.size.y+0.01,label+" "+language+": all translated VS lines fit their allocated height")
		var wall_top:float = (viewport.canvas_transform * rect.position).y
		check(not copy.is_visible_in_tree() or bottom.y <= wall_top-0.5,label+" "+language+": visible VS lines stay above the arena wall")
		if recorder._composition == recorder.preferences.FULL:
			check(copy.is_visible_in_tree(),label+" "+language+": FULL recording shows the stable VS title")
		else:
			check(copy.is_visible_in_tree() or wall_top < box_bottom.y + maxf(world.map_border_width*0.5,12.0),label+" "+language+": FOLLOW hides VS only when the arena fills its header")
		if recorder._composition == recorder.preferences.FULL:
			var source_bottom:Vector2 = source.get_global_transform_with_canvas()*Vector2(0,source.size.y)
			check(absf(box_bottom.y-source_bottom.y) < 0.05,label+" "+language+": translated VS keeps the screen-space bottom anchor")
		check(copy.text.contains("[color=") and copy.text.contains("VS"),label+" "+language+": team colors and VS preserved")
		if label == "zh_long_duel_live" or label == "en_overview_live":
			check(copy.text.contains("Longbow of the Heavens") and copy.text.contains("Elytra Spear") if language == "en" else copy.text.contains("天堂陨落长弓") and copy.text.contains("鞘翅长矛"),label+" "+language+": world VS uses the requested language's character names")
		if recorder._composition == recorder.preferences.FULL:
			var screen_left:Vector2 = to_record_screen*Vector2.ZERO
			var screen_right:Vector2 = to_record_screen*Vector2(copy.size.x,0.0)
			check(screen_left.x >= -0.5 and screen_right.x <= viewport.size.x+0.5,label+" "+language+": full-screen VS box remains inside both portrait-frame edges")
		var image:Image = variant._grab_image()
		check(image.get_size() == Vector2i(1080,1920),label+" "+language+": native full-HD output")
		image.save_png(output_dir.path_join(label+"_"+language+".png"))
		evidence.append({"case":label,"locale":language,"font":copy.get_theme_font_size("normal_font_size"),"box":[copy.size.x,copy.size.y],"content_height":copy.get_content_height(),"text_bottom":bottom.y,"wall_top":wall_top,"text":copy.text})
	check(source.text == before_text and source.get_rect() == before_rect,label+": recorder does not modify the source VS text or layout")

func capture_case(label:String,simulated:bool) -> void:
	var source_text:String = world.versus_label.text
	var source_rect:Rect2 = world.versus_label.get_rect()
	var locale:String = game.current_locale
	check(recorder.start_simulated() if simulated else recorder.start_live(),label+": starts a real bilingual recording")
	await settle(0.65)
	if recorder.is_idle():
		check(false,label+": recording must remain active")
		return
	await check_frame(label)
	check(game.current_locale == locale and source_text == world.versus_label.text and source_rect == world.versus_label.get_rect(),label+": recording does not switch the game language or VS layout")
	if label == "zh_long_duel_live" and OS.get_environment("TITLE_TEST_PHASE") != "before" and OS.get_environment("TITLE_TEST_CASE") != "duel_only":
		var mirror:Node = recorder._locale_mirror
		var translated:RichTextLabel = mirror.copies[world.versus_label.get_instance_id()].en.text
		var stable_rect:Rect2 = translated.get_rect()
		var stable_font:int = translated.get_theme_font_size("normal_font_size")
		for i:int in range(20): mirror.sync()
		check(translated.get_rect() == stable_rect and translated.get_theme_font_size("normal_font_size") == stable_font,"repeated frame sync keeps translated layout stable")
		set_matchup(["牛","木剑"])
		await settle(0.1)
		await check_frame("zh_dynamic_short")
		set_matchup(["天堂陨落长弓","鞘翅长矛"])
		await settle(0.1)
		await check_frame("zh_dynamic_long")
	recorder.stop()
	await wait_idle()
	check(recorder.last_outputs.size() == 2,label+": writes both actual MP4 variants")
	outputs.append({"case":label,"files":recorder.last_outputs.duplicate(),"frames":recorder._frame_index})
	game.now_stop_state = false
	if game.has_method("continue_game"): game.continue_game()
	await settle(0.08)

func run() -> void:
	create_timer(110.0,true,false,true).timeout.connect(func(): print("TITLE_TEST_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	var saved_locale:String = game.current_locale
	game.set_language("zh",false)
	game.Game_Settings.Development_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Camera_Move = false
	game.Game_Settings.Shaking_Camera = false
	game.Game_Settings.Map_Background = "blue"
	game.now_stop_state = false
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	root.size = Vector2i(540,960)
	await settle(0.5)
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	world.control.team.hide()
	world.control.hide()
	controls = world.control._battle_record_controls
	recorder = controls.recorder
	recorder.preferences = recorder.PreferencesScript.new("user://recording_titles_test.cfg")
	var phase:String = OS.get_environment("TITLE_TEST_PHASE")
	if phase.is_empty(): phase = "after"
	output_dir = "user://recordings/title_layout_"+phase
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	recorder.preferences.directory = output_dir
	recorder.preferences.tail_seconds = 60.0
	recorder.set_composition(recorder.preferences.FULL)
	set_matchup(["天堂陨落长弓","鞘翅长矛"])
	await settle(0.1)
	await capture_case("zh_long_duel_live",false)
	if phase != "before" and OS.get_environment("TITLE_TEST_CASE") != "duel_only":
		set_matchup(["天堂陨落长弓","鞘翅长矛","下界合金剑","钻石剑","木剑","兔子"])
		await settle(0.1)
		await capture_case("zh_long_teams_live",false)
		set_matchup(["牛","木剑"])
		await settle(0.1)
		await capture_case("zh_short_live",false)
		set_matchup(["天堂陨落长弓","鞘翅长矛"])
		await settle(0.1)
		recorder.set_composition(recorder.preferences.FOLLOW)
		await capture_case("zh_follow_sim",true)
		game.set_language("en",false)
		world._last_versus_text = ""
		world.refresh_versus_text()
		world.refresh_top_text_layout()
		recorder.set_composition(recorder.preferences.FOLLOW_OVERVIEW)
		await settle(0.1)
		await capture_case("en_overview_live",false)
	var report:FileAccess = FileAccess.open(output_dir.path_join("manifest.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"evidence":evidence,"outputs":outputs},"\t"))
	report.close()
	world.queue_free()
	await process_frame
	game.Game_Settings = saved
	game.set_language(saved_locale,false)
	print("RECORDING_TITLES: %d checks / %d failures"%[checks,failures])
	quit(1 if failures > 0 else 0)
