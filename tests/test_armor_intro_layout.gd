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

	var center:Vector2 = world.return_map_world_rect(world.map_group["Map10x10"]).get_center()
	var stand:Node2D = load("res://scenes/characters/默认/虚无盔甲架.tscn").instantiate()
	stand.Team = "A"
	stand.position = center-Vector2(30,0)
	world.add_child(stand,true)
	stand.process_mode = Node.PROCESS_MODE_DISABLED
	var blaze:Node2D = load("res://scenes/characters/我的世界/烈焰人.tscn").instantiate()
	blaze.Team = "B"
	blaze.position = center+Vector2(30,0)
	world.add_child(blaze,true)
	blaze.process_mode = Node.PROCESS_MODE_DISABLED
	world.refresh_versus_text()
	await RenderingServer.frame_post_draw
	check(world.armor_intro_label != world.versus_label,"separate text controls")
	check(world.armor_intro_label.visible and world.versus_label.visible,"introduction and VS both visible in armor test")
	check(world.armor_intro_label.text.contains("灼烧") and world.armor_intro_label.text.contains("烈焰棒"),"real Blaze explanation retained")
	check(world.versus_label.text.contains("VS") and not world.versus_label.text.contains("灼烧"),"VS contains matchup, not introduction")
	for locale:String in ["zh","en"]:
		game.set_language(locale,false)
		world.refresh_versus_text()
		world.refresh_top_text_layout()
		await RenderingServer.frame_post_draw
		var intro:Rect2 = screen_box(world.armor_intro_label)
		var vs:Rect2 = screen_box(world.versus_label)
		check(intro.position.y <= 120.0 and intro.position.y >=24.0,locale+" intro moved higher")
		check(intro.end.y+15.9 <= vs.position.y,locale+" long introduction does not overlap VS")
		check(world.armor_intro_label.get_content_height() <= world.armor_intro_label.size.y,locale+" full text fits height")
		check(intro.end.x <= root.size.x and intro.position.x>=0,locale+" text fits screen width")
		root.get_texture().get_image().save_png("res://.git/armor-intro-layout/"+locale+".png")
		world.camera_2d.position += Vector2(13.3,-7.6)
		world.camera_2d.zoom *= 1.25
		world.camera_2d.force_update_scroll()
		world._anchor_versus_to_screen()
		check(screen_box(world.armor_intro_label)==intro and screen_box(world.versus_label)==vs,locale+" pan and zoom do not move text")
	game.set_language("zh",false)
	world.refresh_versus_text()
	var mirror:Node = load("res://scripts/ui/battle_record_locale.gd").new()
	world.add_child(mirror)
	var views:Dictionary = {}
	for locale:String in ["zh","en"]:
		var viewport := SubViewport.new()
		viewport.size = root.size
		viewport.world_2d = root.world_2d
		viewport.canvas_cull_mask = 1 | ((1 << 17) if locale=="zh" else (1 << 18))
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		views[locale] = viewport
	mirror.begin(world,root,views)
	mirror.sync()
	await RenderingServer.frame_post_draw
	check(mirror.copies.has(world.armor_intro_label.get_instance_id()),"recording discovers independent introduction")
	check(mirror.copies.has(world.versus_label.get_instance_id()),"recording also keeps separate VS")
	for locale:String in ["zh","en"]:
		var copy:RichTextLabel = mirror.copies[world.armor_intro_label.get_instance_id()][locale].text
		var vs:RichTextLabel = mirror.copies[world.versus_label.get_instance_id()][locale].text
		check(copy.is_visible_in_tree() and vs.is_visible_in_tree(),locale+" both recording blocks visible")
		check(screen_box(copy).end.y+15.9<=screen_box(vs).position.y,locale+" recording blocks do not overlap")
		check(copy.get_content_height()<=copy.size.y,locale+" recording intro not clipped")
		views[locale].get_texture().get_image().save_png("res://.git/armor-intro-layout/record_"+locale+".png")
	world._dead_save_ui_override_active = true
	world.refresh_versus_text()
	check(not world.armor_intro_label.visible,"dead-save override hides introduction")
	world._dead_save_ui_override_active = false
	stand.free()
	world.refresh_versus_text()
	world.refresh_top_text_layout()
	mirror.sync()
	check(not world.armor_intro_label.visible,"leaving armor test hides introduction")
	check(world.versus_label.position.y == 240.0,"ordinary VS returns to original screen anchor")
	for locale:String in ["zh","en"]:
		check(not mirror.copies[world.armor_intro_label.get_instance_id()][locale].holder.visible,locale+" recording hides old intro on exit")
	mirror.finish()
	mirror.queue_free()
	for view:SubViewport in views.values(): view.queue_free()
	world.queue_free()
	await process_frame
	game.Game_Settings = old_settings
	game.set_language(old_locale,false)
	print("ARMOR_INTRO_LAYOUT checks=%d failures=%d" % [checks,failures])
	quit(1 if failures>0 else 0)
