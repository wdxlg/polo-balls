extends "res://tests/test_armor_intro_readability.gd"
## Real translation/HUD text paths for every MC scene, without simulating combat.

func run() -> void:
	create_timer(120.0,true,false,true).timeout.connect(func(): push_error("MC_INTRO_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	var old_settings:Dictionary = game.Game_Settings.duplicate(true)
	var old_locale:String = game.current_locale
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Development_Mode = false
	game.Game_Settings.Camera_Move = false
	game.set_language("zh",false)
	root.size = Vector2i(540,960)
	world = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	await create_timer(0.15,true,false,true).timeout
	world.set_process(false)
	world.set_physics_process(false)
	world.control.get_parent().hide()
	var mirror:Node = load("res://scripts/ui/battle_record_locale.gd").new()
	world.add_child(mirror)
	mirror._build_dictionary()
	var han := RegEx.new()
	han.compile("[\u3400-\u9fff]")
	var summaries:Dictionary = world.get_script().get_script_constant_map()["ARMOR_TEST_ROLE_SUMMARIES"]
	var count:int = 0
	var maximum_height:float = 0.0
	var files:PackedStringArray = DirAccess.get_files_at("res://scenes/characters/我的世界")
	files.sort()
	for filename:String in files:
		if not filename.ends_with(".tscn"): continue
		var role:String = filename.get_basename()
		var packed:PackedScene = load("res://scenes/characters/我的世界/"+filename)
		var actor:Node = packed.instantiate()
		var path:String = actor.get_script().resource_path
		world._armor_stand_test_primary_script_path = path
		check(summaries.has(path),role+" has registered introduction key")
		var key:String = str(summaries.get(path,""))
		check(key.begins_with("MC_ARMOR_INTRO_"),role+" uses stable localization key")
		var translated:Dictionary = {}
		for locale:String in ["zh","en"]:
			game.set_language(locale,false)
			var text:String = world._armor_test_special_effect_summary(actor,PackedStringArray())
			translated[locale] = text
			check(not text.is_empty() and text != key,role+" "+locale+" resolves actual summary path")
			check(text == game.t(key),role+" "+locale+" custom/fallback agrees with catalog")
			if locale == "en":
				check(han.search(text) == null,role+" fully English description")
				check(han.search(game.t(role)) == null and not game.t(role).is_empty(),role+" English name")
			world.armor_intro_label.text = "[center][b]"+game.t(role)+"[/b]\n"+text+"[/center]"
			world.armor_intro_label.show()
			world._layout_armor_intro_to_screen()
			await drawn_frame()
			var height:float = world.armor_intro_label.get_content_height()
			maximum_height = maxf(maximum_height,height)
			check(height <= world.armor_intro_label.size.y,role+" "+locale+" text is not clipped")
			check(height+48 < 960,role+" "+locale+" fits upper half of logical screen")
			if role in ["铁砧","硫方怪","凋灵骷髅","流浪商人"]:
				save_capture(root,"mc-intro-"+str(count)+"-"+locale)
		check(mirror.translate(translated.zh,"en") == translated.en,role+" recording translates whole paragraph")
		check(mirror.translate(translated.en,"zh") == translated.zh,role+" recording reverse translation")
		actor.free()
		count += 1
	check(count >= 46,"all current MC character scenes covered")
	print("MC_INTRO_ALL_RESULT roles=",count," checks=",checks," failures=",failures," max_text_height=",maximum_height)
	game.Game_Settings = old_settings
	game.set_language(old_locale,false)
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
