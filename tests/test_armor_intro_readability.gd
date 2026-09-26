extends SceneTree
## Introduction-only armor battles: readable text, no VS, main and bilingual captures.

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
		push_error("ARMOR_READABILITY_FAIL " + label)

func drawn_frame() -> void:
	await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	RenderingServer.force_draw(false)

func save_capture(view:Viewport,file_name:String) -> void:
	if OS.get_cmdline_user_args().is_empty(): return
	var image:Image = view.get_texture().get_image()
	if view is SubViewport and view.use_hdr_2d:
		image.convert(Image.FORMAT_RGBA8)
		image.linear_to_srgb()
	image.save_png(OS.get_cmdline_user_args()[0]+"/"+file_name+".png")

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
	create_timer(80.0,true,false,true).timeout.connect(func(): push_error("ARMOR_READABILITY_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	var old_settings:Dictionary = game.Game_Settings.duplicate(true)
	var old_locale:String = game.current_locale
	game.Game_Settings.Development_Mode = false
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Map_Background = "grass"
	game.Game_Settings.Training_Environment = "none"
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

	var center:Vector2 = world.return_map_world_rect(world.map_group["Map10x10"]).get_center()
	var stand:Node2D = load("res://scenes/characters/默认/虚无盔甲架.tscn").instantiate()
	stand.Team = "A"
	stand.position = center-Vector2(30,0)
	world.add_child(stand,true)
	stand.process_mode = Node.PROCESS_MODE_DISABLED
	world.refresh_versus_text()
	check(not world.armor_intro_label.visible and not world.versus_label.visible,"only armor stand has neither empty intro nor VS")
	var blaze:Node2D = load("res://scenes/characters/我的世界/烈焰人.tscn").instantiate()
	blaze.Team = "B"
	blaze.position = center+Vector2(30,0)
	world.add_child(blaze,true)
	blaze.process_mode = Node.PROCESS_MODE_DISABLED
	world.refresh_versus_text()
	await drawn_frame()
	var actor_scale:Vector2 = blaze.scale
	var visual_scale:Vector2 = blaze.get_node("Sprite2D").scale if blaze.has_node("Sprite2D") else Vector2.ONE
	check(world.armor_intro_label != world.versus_label,"separate text controls")
	check(world.armor_intro_label.visible and not world.versus_label.visible,"introduction is visible but VS is hidden in armor test")
	check(world.armor_intro_label.text.contains("灼烧") and world.armor_intro_label.text.contains("烈焰棒"),"real Blaze explanation retained")
	check(world.versus_label.text.is_empty() and not world.armor_intro_label.text.contains("VS"),"armor introduction clears the whole matchup instead of retaining VS text")
	check(world.armor_intro_label.text.contains("[b]烈焰人[/b]"),"selected original character keeps its own bold name without the dummy name")
	check(world.armor_intro_font_size==32,"default introduction doubles from 16 to 32 logical pixels")
	var camera_position:Vector2 = world.camera_2d.position
	var camera_zoom:Vector2 = world.camera_2d.zoom
	for locale:String in ["zh","en"]:
		game.set_language(locale,false)
		world.refresh_versus_text()
		world.refresh_top_text_layout()
		await drawn_frame()
		var intro:Rect2 = screen_box(world.armor_intro_label)
		var vs:Rect2 = screen_box(world.versus_label)
		check(intro.position.y <= 120.0 and intro.position.y >=24.0,locale+" intro moved higher")
		check(not world.versus_label.visible and world.versus_label.text.is_empty(),locale+" language refresh cannot restore VS")
		check(world.armor_intro_label.get_theme_font_size("normal_font_size")==32 and world.armor_intro_label.get_theme_font_size("bold_font_size")==32,locale+" name and prose use the larger font without auto-shrink")
		check(world.armor_intro_label.get_content_height() <= world.armor_intro_label.size.y,locale+" full text fits height")
		check(world.armor_intro_label.get_theme_constant("outline_size")==4 and world.armor_intro_label.get_theme_constant("line_separation")==6,locale+" readable spacing and dark outline are intro-only")
		check(intro.end.x <= world.get_viewport_rect().size.x and intro.position.x>=0,locale+" text fits screen width")
		check(intro.end.y < world.get_viewport_rect().size.y*0.5,locale+" real three-paragraph introduction stays in the screen header")
		print("ARMOR_READABILITY_METRIC ",locale," logical=",world.get_viewport_rect().size," physical=",root.size," font=",world.armor_intro_label.get_theme_font_size("normal_font_size")," box=",intro)
		save_capture(root,"armor-intro-"+locale)
		world.camera_2d.position += Vector2(13.3,-7.6)
		world.camera_2d.zoom *= 1.25
		world.camera_2d.force_update_scroll()
		world._anchor_versus_to_screen()
		check(screen_box(world.armor_intro_label)==intro and screen_box(world.versus_label)==vs,locale+" pan and zoom do not move text")
		world.camera_2d.position = camera_position
		world.camera_2d.zoom = camera_zoom
		world.camera_2d.force_update_scroll()
	game.set_language("zh",false)
	world.refresh_versus_text()
	var mirror:Node = load("res://scripts/ui/battle_record_locale.gd").new()
	world.add_child(mirror)
	var views:Dictionary = {}
	for locale:String in ["zh","en"]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1080,1920)
		viewport.use_hdr_2d = root.use_hdr_2d
		viewport.world_2d = root.world_2d
		viewport.canvas_cull_mask = 1 | ((1 << 17) if locale=="zh" else (1 << 18))
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		viewport.canvas_transform = root.canvas_transform
		views[locale] = viewport
	mirror.begin(world,root,views)
	mirror.sync()
	await drawn_frame()
	check(mirror.copies.has(world.armor_intro_label.get_instance_id()),"recording discovers independent introduction")
	check(not mirror.copies.has(world.versus_label.get_instance_id()),"recording does not create a visible VS from an initially hidden source")
	for locale:String in ["zh","en"]:
		var copy:RichTextLabel = mirror.copies[world.armor_intro_label.get_instance_id()][locale].text
		check(copy.is_visible_in_tree() and not copy.text.contains("VS"),locale+" recording contains introduction only")
		check(copy.get_theme_font_size("normal_font_size")==32 and copy.get_theme_font_size("bold_font_size")==32,locale+" recording retains larger name and prose")
		check(screen_box(copy).position.y==48.0,locale+" recording no longer reserves space for hidden VS")
		check(copy.get_content_height()<=copy.size.y,locale+" recording intro not clipped")
		check(copy.get_theme_constant("outline_size")==4 and copy.get_theme_constant("line_separation")==6,locale+" recording copies readable outline and spacing")
		save_capture(views[locale],"armor-intro-record-"+locale)
	check(blaze.scale==actor_scale and (not blaze.has_node("Sprite2D") or blaze.get_node("Sprite2D").scale==visual_scale),"text refresh, language and recording do not resize the actor")
	world._dead_save_ui_override_active = true
	world.refresh_versus_text()
	check(not world.armor_intro_label.visible,"dead-save override hides introduction")
	world._dead_save_ui_override_active = false
	var other:Node2D = spawn_named("钻石剑","C")
	stand.free()
	world.refresh_versus_text()
	world.refresh_top_text_layout()
	mirror.sync()
	check(not world.armor_intro_label.visible,"leaving armor test hides introduction")
	check(world.versus_label.position.y == 240.0,"ordinary VS returns to original screen anchor")
	check(world.versus_label.visible and world.versus_label.text.contains("VS"),"ordinary two-character battle restores VS")
	for locale:String in ["zh","en"]:
		check(not mirror.copies[world.armor_intro_label.get_instance_id()][locale].holder.visible,locale+" recording hides old intro on exit")
	for locale:String in ["zh","en"]:
		check(mirror.copies.has(world.versus_label.get_instance_id()) and mirror.copies[world.versus_label.get_instance_id()][locale].holder.visible,locale+" ordinary recording restores VS")
	# Existing recording copies must disappear when a dummy is added again.
	var second_stand:Node2D = load("res://scenes/characters/默认/盔甲架.tscn").instantiate()
	second_stand.Team = "A"
	second_stand.position = center-Vector2(30,0)
	world.add_child(second_stand,true)
	second_stand.process_mode = Node.PROCESS_MODE_DISABLED
	world.refresh_versus_text()
	world.refresh_top_text_layout()
	mirror.sync()
	await drawn_frame()
	check(not world.versus_label.visible and world.armor_intro_label.visible,"ordinary armor stand also restores intro-only mode")
	for locale:String in ["zh","en"]:
		check(not mirror.copies[world.versus_label.get_instance_id()][locale].holder.visible,locale+" previously visible VS copy hides on armor re-entry")
	# Resize/follow must not shrink the font or re-enable the matchup.
	root.size = Vector2i(680,960)
	await drawn_frame()
	world.refresh_top_text_layout()
	world.refresh_versus_text()
	check(world.armor_intro_label.get_theme_font_size("normal_font_size")==32 and not world.versus_label.visible,"window resize retains readable font and no VS")
	mirror.finish()
	mirror.queue_free()
	for view:SubViewport in views.values(): view.queue_free()
	world.queue_free()
	await process_frame
	game.Game_Settings = old_settings
	game.set_language(old_locale,false)
	print("ARMOR_INTRO_READABILITY checks=%d failures=%d" % [checks,failures])
	quit(1 if failures>0 else 0)
