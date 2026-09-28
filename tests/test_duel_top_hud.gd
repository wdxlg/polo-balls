extends SceneTree
## 1v1 顶部对战 HUD：显示条件、左右信息、游戏时间计时、结果保留、与原 VS 不重叠、
## 双语录制镜像，以及玩家画面/录制视口的真实 GPU 截图。
var world:Node
var game:Node
var checks:int = 0
var failures:int = 0
const SHOT_DIR:String = "user://duel_top_hud"

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("DUEL_HUD_FAIL " + label)
	else:
		print("DUEL_HUD_OK " + label)

func screen_box(item:Control) -> Rect2:
	var transform:Transform2D = item.get_global_transform_with_canvas()
	var top_left:Vector2 = transform * Vector2.ZERO
	return Rect2(top_left,transform * item.size - top_left)

func spawn_real(char_name:String,team:String,x:float) -> Node2D:
	var path:String = world.character_scene_path(char_name)
	var actor:Node2D = (load(path) as PackedScene).instantiate() as Node2D
	actor.Team = team
	actor.position = Vector2(x,110.0)
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(actor,true)
	actor.set_physics_process(false)
	return actor

func settle(frames:int = 8) -> void:
	for _i:int in range(frames):
		await physics_frame
	await process_frame

func hud() -> Control:
	return world.duel_top_hud

func save_shot(viewport:Viewport,file_name:String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image:Image = viewport.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	image.save_png(SHOT_DIR + "/" + file_name)
	return image

func region_difference(a:Image,b:Image,rect:Rect2i) -> float:
	var total:float = 0.0
	var count:int = 0
	for y:int in range(rect.position.y,rect.end.y,2):
		for x:int in range(rect.position.x,rect.end.x,2):
			var ca:Color = a.get_pixel(x,y)
			var cb:Color = b.get_pixel(x,y)
			total += absf(ca.r-cb.r) + absf(ca.g-cb.g) + absf(ca.b-cb.b)
			count += 1
	return total / maxf(float(count),1.0)

func run() -> void:
	create_timer(90.0,true,false,true).timeout.connect(func(): push_error("DUEL_HUD_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	var old_settings:Dictionary = game.Game_Settings.duplicate(true)
	var old_locale:String = game.current_locale
	var old_stop:bool = game.now_stop_state
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
	game.now_stop_state = false

	check(is_instance_valid(hud()) and hud().get_parent() == world.versus_screen_layer,"HUD lives on the fixed screen-space VS layer")
	check(float(hud().format_elapsed(0.0).length()) == 5.0 and hud().format_elapsed(65.9) == "01:05" and hud().format_elapsed(3725.0) == "1:02:05","elapsed time formats mm:ss and h:mm:ss")

	var blue:Node2D = spawn_real("苦力怕","A",100.0)
	world.refresh_versus_text()
	await settle()
	check(not hud().visible,"a single character does not show the duel HUD")

	var red:Node2D = spawn_real("骷髅","B",180.0)
	world.refresh_versus_text()
	await settle()
	check(hud().visible,"exactly two primary characters on two sides show the HUD")
	check(hud().sides.size() == 2 and hud().sides[0].raw_name == "苦力怕" and hud().sides[1].raw_name == "骷髅","left/right follow the ordinary VS order")
	check(hud().sides[0].color == Color(0.25,0.65,1.0) and hud().sides[1].color == Color(1.0,0.26,0.26),"names reuse the VS blue/red team colors")
	check(hud().sides[0].texture != null and hud().sides[1].texture != null,"both portraits resolve through the rotation portrait source")
	check(is_equal_approx(float(hud().sides[0].max_hp),float(blue.Max_health)) and is_equal_approx(float(hud().sides[1].hp),float(red.health)),"HP values come from the live characters")
	check(world.versus_label.visible,"the original text VS stays visible")

	# 布局：HUD 在视口顶部，底边高于原 VS 标题，不重叠。
	world._anchor_versus_to_screen()
	var hud_box:Rect2 = screen_box(hud())
	var title_box:Rect2 = screen_box(world.versus_label)
	print("DUEL_HUD_METRIC hud=",hud_box," title=",title_box," logical=",world.get_viewport_rect().size)
	check(hud_box.position.y >= 0.0 and hud_box.end.y <= title_box.position.y + 0.5,"HUD bottom stays above the ordinary VS title")
	check(absf(hud_box.size.x - world.get_viewport_rect().size.x) < 1.0,"HUD spans the logical viewport width")

	# 生命同步
	red.health = 37
	await settle(2)
	check(is_equal_approx(float(hud().sides[1].hp),37.0) and not bool(hud().sides[1].dead),"HP text/bar track damage")

	# 计时：运行中累加，时间停止时冻结。
	var t0:float = hud().elapsed
	await settle(30)
	var t1:float = hud().elapsed
	check(t1 > t0 + 0.2,"game time accumulates while combat runs")
	game.now_stop_state = true
	await settle(20)
	check(is_equal_approx(hud().elapsed,t1) or absf(hud().elapsed - t1) < 0.02,"time stop freezes the elapsed clock")
	game.now_stop_state = false

	var shown_shot:Image = await save_shot(root,"main_duel.png")

	# 三方：不再是 1v1。
	var third:Node2D = spawn_real("骷髅","C",260.0)
	world.refresh_versus_text()
	await settle()
	check(not hud().visible,"three sides hide the HUD")
	third.free()
	world.refresh_versus_text()
	await settle()
	check(hud().visible,"returning to two sides shows the HUD again")

	# 同队两人：不显示。
	var mate:Node2D = spawn_real("骷髅","A",300.0)
	red.Team = "A"
	world.refresh_versus_text()
	await settle()
	check(not hud().visible,"two characters on the same side do not count as a duel")
	mate.free()
	red.Team = "B"
	world.refresh_versus_text()
	await settle()
	check(hud().visible,"two opposing characters show again")

	# 录制镜像：真实 SubViewport + battle_record_locale 的屏幕层。
	var captures:Dictionary = {}
	var locale_script:GDScript = load("res://scripts/ui/battle_record_locale.gd")
	for locale:String in ["zh","en"]:
		var capture := SubViewport.new()
		# 与 battle_recorder 相同：每份录像剔除另一种语言的可见层。
		capture.canvas_cull_mask = 0xFFFFFFFF & ~(locale_script.EN_BIT if locale == "zh" else locale_script.ZH_BIT)
		capture.size = Vector2i(1080,1920)
		capture.world_2d = root.world_2d
		capture.transparent_bg = false
		capture.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(capture)
		captures[locale] = capture
	var mirror:Node = locale_script.new()
	world.add_child(mirror)
	mirror.begin(world,root,captures)
	await settle(3)
	for locale:String in ["zh","en"]:
		var layer:CanvasLayer = mirror.screen_roots.get(locale)
		var copy:Control = null
		if layer != null:
			for child:Node in layer.get_children():
				if child.name == "DuelTopHud_" + locale:
					copy = child
		check(copy != null and copy.is_mirror() and copy.visible,"recording " + locale + " has a visible HUD mirror")
		if copy != null:
			check(copy.visibility_layer == (mirror.ZH_BIT if locale == "zh" else mirror.EN_BIT),"recording " + locale + " mirror uses its language layer")
			var translated:String = copy._display_name("苦力怕")
			check((translated == "苦力怕") == (locale == "zh"),"recording " + locale + " mirror translates names (" + translated + ")")
	var zh_shot:Image = await save_shot(captures.zh,"recording_zh.png")
	var en_shot:Image = await save_shot(captures.en,"recording_en.png")
	check(region_difference(zh_shot,en_shot,Rect2i(560,40,480,160)) > 0.001,"zh/en recordings render different localized right-side names")

	# 决出胜负：保留最后一对的结果；胜利铃后计时冻结；重置归零并隐藏。
	red.health = 0
	red.free()
	world.refresh_versus_text()
	await settle()
	check(hud().visible and hud().sides.size() == 2 and bool(hud().sides[1].dead) and float(hud().sides[1].hp) == 0.0,"after a death the final duel result stays on screen")
	world._victory_bell_played = true
	var frozen:float = hud().elapsed
	await settle(20)
	check(absf(hud().elapsed - frozen) < 0.0001,"victory freezes the clock")
	var result_shot:Image = await save_shot(root,"main_result.png")
	world._reset_victory_bell_state()
	await settle()
	# 手动模式下剩余角色仍在场，重置后立即重新计时；8 个物理帧约 0.13 秒。
	check(hud().elapsed < 0.2 and hud().elapsed < frozen and not hud().visible,"reset clears the result and restarts the clock from zero")

	# GPU：显示 HUD 时顶部区域明显变化，地图区域不变。
	blue.free()
	world.refresh_versus_text()
	await settle()
	var hidden_shot:Image = await save_shot(root,"main_hidden.png")
	var scale:float = float(shown_shot.get_width()) / 1080.0
	var top:Rect2i = Rect2i(Vector2i(Vector2(24,32) * scale),Vector2i(Vector2(1032,176) * scale))
	var below:Rect2i = Rect2i(Vector2i(Vector2(24,560) * scale),Vector2i(Vector2(1032,300) * scale))
	var top_diff:float = region_difference(shown_shot,hidden_shot,top)
	print("DUEL_HUD_METRIC top_diff=",top_diff," shot=",shown_shot.get_size())
	check(top_diff > 0.05,"GPU frame shows the HUD in the top area")
	var panel_pixel:Color = shown_shot.get_pixel(int(34.0 * scale),int(200.0 * scale))
	check(panel_pixel.r < 0.15 and panel_pixel.g < 0.08 and panel_pixel.b < 0.15,"left panel uses the dark Minecraft tooltip background (" + str(panel_pixel) + ")")

	mirror.finish()
	mirror.queue_free()
	for capture:SubViewport in captures.values(): capture.queue_free()
	print("DUEL_HUD_SHOTS ",ProjectSettings.globalize_path(SHOT_DIR))
	world.queue_free()
	await process_frame
	game.now_stop_state = old_stop
	game.Game_Settings = old_settings
	game.set_language(old_locale,false)
	print("DUEL_HUD_RESULT checks=%d failures=%d" % [checks,failures])
	quit(1 if failures>0 else 0)
