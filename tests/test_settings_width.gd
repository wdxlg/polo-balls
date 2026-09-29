extends SceneTree
var checks:int = 0
var failures:int = 0
func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures += 1
func settle() -> void:
	for i:int in range(8): await process_frame
func run() -> void:
	create_timer(90).timeout.connect(func():quit(2))
	var game:Node = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	var locale:String = game.current_locale
	game.Game_Settings.Map_Background = "summit"
	game.Game_Settings.Only_In_Game_Translation = false
	AudioServer.set_bus_mute(0,true)
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	var ui:Control = world.control
	ui.game_setting.show()
	await settle()
	for lang:String in ["zh","en"]:
		game.set_language(lang,false)
		await settle()
		for category:String in ["training","parameters","recording","parameters"]:
			ui._show_settings_category(category)
			await settle()
			var panel:Control = ui.game_setting.get_node("Panel")
			var frame:Rect2 = panel.get_global_rect()
			var tabs:Rect2 = ui.settings_tab_bar.get_global_rect()
			var content:Rect2 = ui.settings_stack.get_global_rect()
			var scroll:Rect2 = ui.settings_scroll.get_global_rect()
			print("WIDTH ",lang," ",category," frame=",frame.size.x," tabs=",tabs.size.x," content=",content.size.x," scroll=",scroll.size.x)
			check(tabs.end.x <= frame.end.x+1.0 and tabs.position.x>=frame.position.x-1.0,lang+" "+category+" tabs fit panel")
			check(scroll.end.x<=frame.end.x+1.0,lang+" "+category+" scroll fits panel")
			check(content.end.x<=scroll.end.x+1.0,lang+" "+category+" content fits scroll horizontally")
			if category == "parameters":
				var box:Node = ui.settings_category_boxes.parameters
				var option:OptionButton = box.get_node("CompositionRow/RecordingComposition")
				check(option.get_global_rect().end.x <= scroll.end.x+1.0,lang+" composition dropdown fits")
				check(ui.map_background_option.get_global_rect().end.x <= scroll.end.x+1.0,lang+" background dropdown fits")
				check(option.item_count==3 and ui.map_background_option.item_count==7,"all selections preserved")
				if DisplayServer.get_name() != "headless":
					await RenderingServer.frame_post_draw
					var img:Image = root.get_texture().get_image()
					img.resize(360,640)
					img.save_jpg("res://.git/settings-width-20260926/"+lang+".jpg",0.7)
	game.set_language(locale,false)
	game.Game_Settings=saved
	world.queue_free()
	await process_frame
	print("SETTINGS_WIDTH checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
