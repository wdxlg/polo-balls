extends SceneTree
## 普通 VS 的屏幕锚点与中立/队伍分色；不更改 Boss 轮换名单 HUD。

var world:Node
var game:Node
var checks:int = 0
var failures:int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("VS_SCREEN_FAIL " + label)

func screen_box(label:Control) -> Rect2:
	var transform:Transform2D = label.get_global_transform_with_canvas()
	var top_left:Vector2 = transform * Vector2.ZERO
	return Rect2(top_left,transform * label.size - top_left)

func spawn_named(name:String,team:String) -> Node2D:
	var actor:Node2D = (load("res://scenes/ball.tscn") as PackedScene).instantiate() as Node2D
	actor.Team = team
	actor.set_meta("morph_display_name",name)
	actor.position = Vector2(100.0 + float(world._battle_units_cache.size()) * 9.0,110.0)
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(actor,true)
	actor.set_physics_process(false)
	return actor

func run() -> void:
	create_timer(55.0,true,false,true).timeout.connect(func(): push_error("VS_SCREEN_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	var old_settings:Dictionary = game.Game_Settings.duplicate(true)
	var old_locale:String = game.current_locale
	game.Game_Settings.Development_Mode = false
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Map_Background = "blue"
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
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	world.camera_2d.global_position = world.return_map_world_rect(world.map_group["Map10x10"]).get_center()
	world.camera_2d.reset_smoothing()
	world.camera_2d.force_update_scroll()

	var neutral:Node2D = spawn_named("中立甲","")
	var blue:Node2D = spawn_named("钻石剑","A")
	var single_title:String = world.build_versus_text()
	check(single_title.contains("[color=#ffffff][b]"),"VS and single team are white on black outline")
	check(world._next_versus_team_color_index == 0,"neutral and lone team use no color slot")
	var red:Node2D = spawn_named("木剑","B")
	var text:String = world.build_versus_text()
	var first:String = Color(0.25,0.65,1.0).to_html(false)
	var second:String = Color(1.0,0.26,0.26).to_html(false)
	check(text.contains("[color=#"+first+"][b]钻石剑[/b][/color]"),"first named team fills blue")
	check(text.contains("[color=#"+second+"][b]木剑[/b][/color]"),"second named team fills red")
	check(text.contains("[color=#ffffff][b]中立甲[/b][/color]"),"neutral text stays white before two named teams")
	check(world._next_versus_team_color_index == 0 and world._versus_team_colors.is_empty(),"neutral and the first two teams do not consume random color slots")
	check(world._versus_side_color("team:中立",3,0) == Color.WHITE and world._versus_side_color("team:Neutral",3,0) == Color.WHITE,"explicit neutral labels also do not count")
	check(world._versus_side_color("solo:987",3,0) == Color.WHITE,"independent no-Team participants remain white")
	check(world.versus_label.get_theme_color("font_outline_color") == Color.BLACK and world.versus_label.get_theme_constant("outline_size") == 2 and world.versus_label.get_theme_color("default_color") == Color.WHITE,"all title glyphs have a thicker black outline and white default fill")
	check(text.contains("[color=#FFFFFF][b]VS[/b][/color]"),"VS separator remains white regardless of teams")

	spawn_named("国王","C")
	var random_color:Color = world._versus_side_color("team:C",3,2)
	check(random_color != Color.WHITE and random_color != Color(0.25,0.65,1.0) and random_color != Color(1.0,0.26,0.26),"third team has a distinct random color")
	check(world._versus_side_color("team:C",3,2) == random_color and world._next_versus_team_color_index == 1,"random color stays stable on subsequent refreshes")
	check(world.build_versus_text().contains("[color=#"+random_color.to_html(false)+"][b]国王[/b][/color]"),"third color appears in the real VS text")
	world.refresh_versus_text()
	world._anchor_versus_to_screen()
	var before:Rect2 = screen_box(world.versus_label)
	print("VS_SCREEN_METRIC initial logical=",world.get_viewport_rect().size," physical=",root.size," canvas=",root.get_canvas_transform()," final=",root.get_final_transform()," title=",before)
	check(before.position.distance_to(Vector2(24,240)) < 1.0 and absf(before.size.x - (world.get_viewport_rect().size.x - 48.0)) < 1.0,"title keeps 24px side safety inside the logical viewport")
	world.camera_2d.global_position += Vector2(70.0,-45.0)
	world.toolbar_zoom_multiplier = 1.55
	world._apply_camera_zoom()
	world.camera_2d.force_update_scroll()
	world._anchor_versus_to_screen()
	var after:Rect2 = screen_box(world.versus_label)
	check(after.position.distance_to(before.position) < 1.0 and absf(after.size.x-before.size.x) < 1.0,"camera pan and manual zoom do not move or resize the title")
	world.camera_2d.offset = Vector2(8,-7)
	world.camera_2d.force_update_scroll()
	world._anchor_versus_to_screen()
	check(screen_box(world.versus_label).position.distance_to(before.position) < 1.0,"camera shake does not move title")
	root.size = Vector2i(680,960)
	await process_frame
	world._anchor_versus_to_screen()
	print("VS_SCREEN_METRIC resized logical=",world.get_viewport_rect().size," physical=",root.size," final=",root.get_final_transform()," title=",screen_box(world.versus_label))
	var resized:Rect2 = screen_box(world.versus_label)
	check(resized.position.distance_to(before.position) < 1.0 and absf(resized.size.x - (world.get_viewport_rect().size.x - 48.0)) < 1.0,"window resize keeps the new side safety inside the portrait viewport")

	var mirror:Node = load("res://scripts/ui/battle_record_locale.gd").new()
	world.add_child(mirror)
	mirror.begin(world,root)
	mirror.sync()
	var copies:Dictionary = mirror.copies.get(world.versus_label.get_instance_id(),{})
	check(copies.has("zh") and copies.has("en"),"bilingual recorder still mirrors the fixed title")
	for locale:String in ["zh","en"]:
		if copies.has(locale):
			var copy:RichTextLabel = copies[locale].text
			var rect:Rect2 = screen_box(copy)
			check(rect.position.y >= 0.0 and absf(rect.end.y-before.end.y) < 1.0 and rect.end.y < world.get_viewport_rect().size.y*0.30 and rect.position.x >= 0.0,"recording "+locale+" VS keeps its bottom edge within the lowered viewport header")
			check(rect.position.x >= before.position.x - 0.5 and rect.end.x <= before.end.x + 0.5,"recording "+locale+" VS respects both side safety margins")
			check(copy.get_theme_color("font_outline_color") == Color.BLACK and copy.get_theme_constant("outline_size") == world.versus_label.get_theme_constant("outline_size") and copy.text.contains("[b]VS[/b]"),"recording "+locale+" retains the thicker black outline and VS")
	mirror.finish()
	mirror.queue_free()
	blue.free()
	var promoted:String = world.build_versus_text()
	check(promoted.contains("[color=#"+first+"][b]木剑[/b][/color]"),"removing first team promotes the next team to blue")
	check(promoted.contains("[color=#"+second+"][b]国王[/b][/color]"),"after reordering the second current team becomes red")
	check(world._versus_team_colors.get("team:C") == random_color,"a later team retains its cached random color if promoted")
	world.queue_free()
	await process_frame
	game.Game_Settings = old_settings
	game.set_language(old_locale,false)
	print("VS_SCREEN_RESULT checks=%d failures=%d" % [checks,failures])
	quit(1 if failures>0 else 0)
