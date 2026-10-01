extends SceneTree
## 顶部 VS 用我的世界 3D 立体字：解析/折行、隐藏原字形、跟随对战 HUD 隐藏、死档文字回退、中英录像副本；开场标题已移除。

var world:Node
var checks:int = 0
var failures:int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("VERSUS_3D FAIL: " + label)

func spawn_named(name:String,team:String) -> Node2D:
	var actor:Node2D = (load("res://scenes/ball.tscn") as PackedScene).instantiate() as Node2D
	actor.Team = team
	actor.set_meta("morph_display_name",name)
	actor.position = Vector2(100.0 + float(world._battle_units_cache.size()) * 30.0,110.0)
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(actor,true)
	actor.set_physics_process(false)
	return actor

func count_opaque(adaptor:Control) -> int:
	if adaptor == null or not is_instance_valid(adaptor.title): return 0
	var tex:Texture2D = adaptor.title.texture()
	if tex == null: return 0
	var image:Image = tex.get_image()
	if image == null: return 0
	var count:int = 0
	for y:int in range(0,image.get_height(),4):
		for x:int in range(0,image.get_width(),4):
			if image.get_pixel(x,y).a > 0.5: count += 1
	return count

## 等后台网格生成完成、新画面换上并渲染。
func settle(adaptors:Array) -> void:
	for i:int in range(400):
		var busy:bool = false
		for item:Variant in adaptors:
			if item != null and is_instance_valid(item) and is_instance_valid(item.title) and item.title.is_busy(): busy = true
		if not busy: break
		await process_frame
	await frames(3)

func frames(n:int) -> void:
	for i:int in range(n): await process_frame

func run() -> void:
	create_timer(60.0,true,false,true).timeout.connect(func(): print("VERSUS_3D TIMEOUT"); quit(2))
	var Adaptor:GDScript = load("res://scripts/ui/versus_title_3d.gd")
	var vs:String = "  [color=#FFFFFF][b]VS[/b][/color]  "
	var one:Array = Adaptor.parse("[center][color=#40a6ff][b]烈焰人[/b][/color]" + vs + "[color=#ff4242][b]骷髅[/b][/color]" + vs + "[color=#ffffff][b]苦力怕[/b][/color][/center]")
	check(one.size() == 1 and (one[0].segments as Array).size() == 5,"three short sides share one line with two VS pieces")
	if one.size() == 1 and (one[0].segments as Array).size() == 5:
		check(one[0].segments[1].text == "VS" and one[0].segments[1].style == "gold","VS is gold")
		check(one[0].segments[0].style is Color and one[0].segments[4].style == "stone","team colour kept, white side uses stone")
	var long:Array = Adaptor.parse("[center][color=#40a6ff][b]钻石剑 * 2 + 木剑[/b][/color]" + vs + "[color=#ff4242][b]苦力怕[/b][/color]" + vs + "[color=#28f370][b]末影人[/b][/color][/center]")
	check(long.size() == 2 and long[1].segments[0].text == "VS","long roster wraps; the continued row starts with VS")
	check(Adaptor.parse("[center][color=#ffffff][b]a[lb]1]b[/b][/color][/center]")[0].segments[0].text == "a[1]b","escaped brackets are restored")
	check(Adaptor.parse("[center]存档已损坏[/center]").is_empty() and Adaptor.parse("").is_empty(),"non-VS text is not converted")

	var game:Node = root.get_node("Game")
	var old_settings:Dictionary = game.Game_Settings.duplicate(true)
	var old_locale:String = game.current_locale
	game.Game_Settings.Development_Mode = false
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Map_Background = "blue"
	game.Game_Settings.Camera_Move = false
	game.set_language("zh",false)
	world = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	await create_timer(0.15,true,false,true).timeout
	world.control.get_parent().hide()
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	check(not ResourceLoader.exists("res://scripts/ui/battle_intro_title.gd") and not world.has_method("_present_battle_intro_title"),"battle intro title popup removed")
	check(world.has_method("_start_intro_camera") and world.has_method("_play_battle_start_bell"),"start bell and intro camera stay")
	var label:RichTextLabel = world.versus_label
	var adaptor:Control = label.get_node_or_null(Adaptor.NODE_NAME)
	check(adaptor != null and adaptor.get_script() == Adaptor,"VS label carries the 3D adaptor")
	check(world.armor_intro_label.get_node_or_null(Adaptor.NODE_NAME) == null,"armor intro copy has no adaptor")
	spawn_named("烈焰人","A"); spawn_named("骷髅","B"); spawn_named("苦力怕","C")
	await frames(20)
	world.refresh_versus_text()
	await frames(8)
	await settle([adaptor])
	check(label.visible and adaptor.visible and label.material == Adaptor.hide_material(),"3D shown and flat glyphs hidden")
	check(adaptor.size.x > 0.0 and adaptor.size.y >= label.size.y,"3D area covers the label width")
	check(count_opaque(adaptor) > 400,"3D title rendered (%d)" % count_opaque(adaptor))
	check(get_nodes_in_group("BattleIntroTitle").is_empty(),"no intro popup after the battle starts")

	# 人多时往上长：底边不低于单行标题，顶边不越过屏幕安全线，字仍然够大。
	var canvas:Transform2D = label.get_global_transform_with_canvas()
	var single_bottom:float = (canvas * (adaptor.position + adaptor.title.content_rect().end)).y
	var single_top:float = (canvas * (adaptor.position + adaptor.title.content_rect().position)).y
	for extra:Array in [["钻石剑","D"],["木剑","E"],["末影人","F"],["僵尸","G"],["蜘蛛","H"],["史莱姆","I"],["女巫","J"]]: spawn_named(extra[0],extra[1])
	await frames(2)
	world.refresh_versus_text()
	await frames(8)
	await settle([adaptor])
	canvas = label.get_global_transform_with_canvas()
	var crowd_top:float = (canvas * (adaptor.position + adaptor.title.content_rect().position)).y
	var crowd_bottom:float = (canvas * (adaptor.position + adaptor.title.content_rect().end)).y
	var screen_h:float = label.get_viewport_rect().size.y
	print("VERSUS_3D_METRIC single=",single_top,"..",single_bottom," crowd=",crowd_top,"..",crowd_bottom," rows=",adaptor.title._lines.size())
	check(crowd_bottom <= single_bottom + 1.0,"crowded title does not push down into the battle")
	check(crowd_top < single_top - 20.0 and crowd_top >= screen_h * 0.04 - 1.0,"crowded title grows upward into the empty header, below the safe line")
	check(adaptor.title._lines.size() >= 2 and count_opaque(adaptor) > 400,"crowded title wraps and renders")
	root.get_texture().get_image().save_png(OS.get_environment("TEMP") + "/versus3d_crowd.png")
	# 卡顿回归：人多时某一方数量变化，主线程只做排版/组装，网格在后台生成（旧画面继续显示）。
	var crowd_text:String = label.text
	var t0:int = Time.get_ticks_usec()
	label.text = crowd_text.replace("[b]女巫[/b]","[b]女巫 * 2[/b]")
	adaptor.sync_now()
	var main_ms:float = (Time.get_ticks_usec() - t0) / 1000.0
	check(main_ms < 20.0,"one roster change costs %.1f ms on the main thread" % main_ms)
	await settle([adaptor])
	t0 = Time.get_ticks_usec()
	label.text = crowd_text
	adaptor.sync_now()
	main_ms = (Time.get_ticks_usec() - t0) / 1000.0
	check(main_ms < 10.0 and not adaptor.title.is_busy(),"returning to a cached roster reuses meshes (%.1f ms)" % main_ms)
	await settle([adaptor])
	label.self_modulate.a = 0.0
	await process_frame
	check(is_zero_approx(adaptor.modulate.a),"duel HUD self_modulate hide also hides the 3D title")
	label.self_modulate.a = 1.0

	# 中/英录像：真实抓帧视口里的副本各自生成 3D。
	var captures:Dictionary = {}
	for locale:String in ["zh","en"]:
		var sub := SubViewport.new()
		sub.size = Vector2i(540,960)
		sub.transparent_bg = true
		sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		sub.disable_3d = true
		sub.canvas_cull_mask = 0xFFFFFFFF & ~((1 << 18) if locale == "zh" else (1 << 17))
		root.add_child(sub)
		captures[locale] = sub
	var mirror:Node = load("res://scripts/ui/battle_record_locale.gd").new()
	world.add_child(mirror)
	mirror.begin(world,root,captures)
	mirror.sync()
	await frames(8)
	var copies:Dictionary = mirror.copies.get(label.get_instance_id(),{})
	check(copies.has("zh") and copies.has("en"),"recording mirrors exist")
	var pending:Array = []
	for locale:String in copies: pending.append((copies[locale].text as Node).get_node_or_null(Adaptor.NODE_NAME))
	await settle(pending)
	var copy_adaptors:Dictionary = {}
	for locale:String in ["zh","en"]:
		if not copies.has(locale): continue
		var copy:RichTextLabel = copies[locale].text
		var copy_adaptor:Control = copy.get_node_or_null(Adaptor.NODE_NAME)
		copy_adaptors[locale] = copy_adaptor
		check(copy_adaptor != null and copy_adaptor.visible and copy.material == Adaptor.hide_material(),locale + " copy shows 3D with hidden glyphs")
		check(count_opaque(copy_adaptor) > 400,locale + " copy 3D rendered")
	if copy_adaptors.has("en") and copy_adaptors.en != null:
		check(copy_adaptors.en._source_text != label.text and not copy_adaptors.en._source_text.contains("烈焰人"),"English copy builds from translated names")
		var shot:Image = (captures.en as SubViewport).get_texture().get_image()
		var zh_shot:Image = (captures.zh as SubViewport).get_texture().get_image()
		var differ:int = 0
		for y:int in range(90,170,2):
			for x:int in range(0,540,2):
				var a:Color = shot.get_pixel(x,y)
				var b:Color = zh_shot.get_pixel(x,y)
				if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.3: differ += 1
		check(differ > 300,"zh / en captures draw their own title (%d px differ)" % differ)
		shot.save_png(OS.get_environment("TEMP") + "/versus3d_en.png")
	label.self_modulate.a = 0.0
	mirror.sync()
	await process_frame
	for locale:String in copy_adaptors:
		if copy_adaptors[locale] != null: check(is_zero_approx(copy_adaptors[locale].modulate.a),locale + " copy follows the duel hide")
	label.self_modulate.a = 1.0

	label.text = "[center]存档已损坏[/center]"
	await process_frame
	check(not adaptor.visible and label.material == null,"non-VS text falls back to the flat label")
	label.text = world.build_versus_text()
	await process_frame
	check(adaptor.visible and label.material == Adaptor.hide_material(),"VS text switches back to 3D")
	root.get_texture().get_image().save_png(OS.get_environment("TEMP") + "/versus3d_main.png")
	mirror.finish()
	mirror.queue_free()
	for sub:SubViewport in captures.values(): sub.queue_free()
	world.queue_free()
	await frames(2)
	game.Game_Settings = old_settings
	game.set_language(old_locale,false)
	print("VERSUS_3D_RESULT checks=%d failures=%d" % [checks,failures])
	quit(1 if failures > 0 else 0)

