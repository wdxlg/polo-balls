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

## HUD 设计坐标中某个原版 9×9 图标的源像素 (sx,sy) → 截图像素颜色。
func icon_pixel(shot:Image,side_index:int,row_top:float,index:int,sx:float,sy:float) -> Color:
	var panel:Rect2 = hud()._panel_rects()[0 if side_index == 0 else 2]
	var rect:Rect2 = hud()._icon_rect(panel,side_index == 1,row_top,index)
	var local:Vector2 = rect.position + Vector2(sx + 0.5,sy + 0.5) * hud().ICON_PIXEL
	var screen:Vector2 = hud().get_global_transform_with_canvas() * local
	var ratio:float = float(shot.get_width()) / hud().get_viewport_rect().size.x
	var px:Vector2i = Vector2i(screen * ratio)
	return shot.get_pixel(clampi(px.x,0,shot.get_width() - 1),clampi(px.y,0,shot.get_height() - 1))

## 视口截图读回的是线性色值：期望色按 sRGB → linear 换算；游戏全屏暗角会把屏幕边缘整体压暗
## （实测约 0.8 倍），所以比较“同一色相 + 亮度倍率在 0.65–1.1 之间”。
func color_near(a:Color,b:Color,tolerance:float = 0.035) -> bool:
	var e:Color = b.srgb_to_linear()
	var k:float = (a.r + a.g + a.b) / maxf(e.r + e.g + e.b,0.0001)
	if k < 0.65 or k > 1.1:
		return false
	return absf(a.r - e.r * k) < tolerance and absf(a.g - e.g * k) < tolerance and absf(a.b - e.b * k) < tolerance

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
	check(is_equal_approx(hud().layout_fit_scale,1.0),"without the toolbar the HUD keeps its full-size layout")

	# 生命同步
	red.health = 37
	await settle(2)
	check(is_equal_approx(float(hud().sides[1].hp),37.0) and not bool(hud().sides[1].dead),"HP text/bar track damage")

	# 红心 / 护盾 / 伤害吸收 / 盔甲值：换算与实时读数。
	var h37:float = hud().heart_amount(37.0,420.0)
	check(absf(h37 - 37.0 / 42.0) < 0.0001 and is_equal_approx(hud().heart_fill(h37,0),37.0 / 42.0) and hud().heart_fill(h37,1) == 0.0,"hearts follow the exact HP percentage (37/420 = 0.88 of one heart, no half-heart rounding)")
	check(is_equal_approx(hud().heart_amount(430.0,430.0),10.0) and is_equal_approx(hud().heart_amount(1.0,430.0),10.0 / 430.0) and hud().heart_amount(0.0,430.0) == 0.0,"heart amount is continuous: full = 10, 1 HP is a tiny sliver, 0 is empty")
	check(is_equal_approx(hud().heart_fill_from_high(2.5,9),1.0) and is_equal_approx(hud().heart_fill_from_high(2.5,7),0.5) and hud().heart_fill_from_high(2.5,6) == 0.0,"absorption fills from the high-HP end by exact fraction")
	check(hud().armor_half_units(0.4) == 8 and hud().armor_half_units(0.02) == 1 and hud().armor_half_units(0.0) == 0 and hud().armor_half_units(-0.5) == 0 and hud().armor_half_units(1.0) == 20,"armor icons: 10 = 100% reduction, 5% per half")
	var status_script:GDScript = load("res://scripts/effects/我的世界/mc_status_effects.gd")
	blue.max_block = 200
	blue.block = 86 # 86 / 430 = 20% → 两颗盔甲色心
	blue.Damage_reduction = 0.4 # 例：抗性提升 II
	var absorbed:bool = status_script.apply_effect(blue,"absorption",5,30.0,null) # 100 吸收 → 2.5 颗金心
	await settle(4)
	var blue_side:Dictionary = hud().sides[0]
	print("DUEL_HUD_METRIC blue block=",blue_side.block," absorption=",blue_side.absorption," reduction=",blue_side.reduction," applied=",absorbed)
	check(is_equal_approx(float(blue_side.block),86.0),"shield value comes from the live block")
	check(is_equal_approx(float(blue_side.absorption),100.0),"absorption comes from the real Minecraft absorption effect")
	check(is_equal_approx(float(blue_side.reduction),0.4) and is_equal_approx(float(hud().sides[1].reduction),0.0),"armor value is the live damage reduction; zero on the other side")
	var heart_shot:Image = await save_shot(root,"main_hearts.png")
	var hud_script:GDScript = hud().get_script()
	var red_heart:Color = Color("ff1313")
	var shield_heart:Color = Color("b8b9c4")
	var gold_heart:Color = Color("d4af37")
	var empty_heart:Color = Color("282828")
	var row:float = hud().HEART_ROW_TOP
	var armor_row:float = hud().ARMOR_ROW_TOP
	var c_shield:Color = icon_pixel(heart_shot,0,row,0,4,3)
	var c_red:Color = icon_pixel(heart_shot,0,row,4,4,3)
	var c_gold:Color = icon_pixel(heart_shot,0,row,9,4,3)
	# 100/430 = 2.33 颗金心：第 7 颗只有远端 0.33（源像素第 6、7 列），第 3、4 列仍是红心。
	var c_gold_half:Color = icon_pixel(heart_shot,0,row,7,6,3)
	var c_red_half:Color = icon_pixel(heart_shot,0,row,7,4,3)
	print("DUEL_HUD_METRIC hearts shield=",c_shield," red=",c_red," gold=",c_gold," h7L=",c_red_half," h7R=",c_gold_half)
	check(color_near(c_shield,shield_heart),"left: shield tints hearts from the low-HP end in the armor palette")
	check(color_near(c_red,red_heart),"left: full HP shows vanilla red hearts")
	check(color_near(c_gold,gold_heart),"left: absorption paints golden hearts from the high-HP end")
	check(color_near(c_red_half,red_heart) and color_near(c_gold_half,gold_heart),"left: a partial gold heart covers only its exact fraction from the high-HP side")
	var c_armor_full:Color = icon_pixel(heart_shot,0,armor_row,3,4,4)
	var c_armor_empty:Color = icon_pixel(heart_shot,0,armor_row,4,4,4)
	check(color_near(c_armor_full,Color("b8b9c4")) and color_near(c_armor_empty,Color("3d3d3d")),"left: 40% reduction shows 4 full armor icons from the low-HP end")
	# 右侧 37/420 = 0.88 颗红心，从靠头像的右端按比例填：右侧列是红、最左列（未填的 12%）为空槽。
	var r_first:Color = icon_pixel(heart_shot,1,row,0,4,3)
	var r_first_edge:Color = icon_pixel(heart_shot,1,row,0,1,3)
	var r_second:Color = icon_pixel(heart_shot,1,row,1,4,3)
	var r_armor:Color = icon_pixel(heart_shot,1,armor_row,0,4,4)
	print("DUEL_HUD_METRIC right first=",r_first," second=",r_second," armor=",r_armor)
	check(color_near(r_first,red_heart) and color_near(r_second,empty_heart),"right: hearts are mirrored (low-HP end next to the portrait)")
	check(color_near(r_first_edge,empty_heart),"right: 0.88 of a heart leaves its far edge empty (exact fraction, not rounded up)")
	check(not color_near(r_armor,Color("3d3d3d")) and not color_near(r_armor,Color("b8b9c4")),"right: no damage reduction hides the armor row")
	check(hud_script != null,"HUD script available for mirrors")

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

	# 真实游玩时顶部工具栏（游戏设置/队伍/重置…）可见：HUD 必须排到工具栏下方、原 VS 标题上方，
	# 计时数字不能被遮住；录制镜像没有工具栏，保持原布局。
	var ui_layer:Node = world.control.get_parent()
	ui_layer.show()
	var toolbar:Control = world.control.get_node("Settings")
	await settle(3)
	var bar_box:Rect2 = screen_box(toolbar)
	var fit_box:Rect2 = screen_box(hud())
	var fit_title:Rect2 = screen_box(world.versus_label)
	var logical:Vector2 = world.get_viewport_rect().size
	var panel_top:float = fit_box.position.y + hud().TOP * hud().scale.y
	var panel_bottom:float = fit_box.position.y + (hud().TOP + hud().PANEL_HEIGHT) * hud().scale.y
	print("DUEL_HUD_METRIC toolbar=",bar_box," panels_y=",panel_top,"..",panel_bottom," title=",fit_title," fit=",hud().layout_fit_scale)
	check(toolbar.is_visible_in_tree() and hud().layout_fit_scale < 1.0,"visible toolbar makes the HUD shrink to fit")
	check(panel_top >= bar_box.end.y - 0.5,"HUD panels start below the top toolbar (timer not covered)")
	check(panel_bottom <= fit_title.position.y + 0.5,"shrunken HUD still stays above the ordinary VS title")
	check(absf((fit_box.position.x + fit_box.size.x * 0.5) - logical.x * 0.5) < 1.0,"shrunken HUD stays horizontally centered")
	var tick0:String = hud().format_elapsed(hud().elapsed)
	var clock_a:float = hud().elapsed
	await settle(70)
	check(hud().elapsed > clock_a + 1.0 and hud().format_elapsed(hud().elapsed) != tick0,"timer text advances while the toolbar is visible")
	await save_shot(root,"main_duel_toolbar.png")
	for locale:String in ["zh","en"]:
		var layer_copy:CanvasLayer = mirror.screen_roots.get(locale)
		for child:Node in layer_copy.get_children():
			if child.name == "DuelTopHud_" + locale:
				check(child.position == Vector2.ZERO and is_equal_approx(child.scale.x,hud().layout_base_scale),"recording " + locale + " mirror keeps the full layout (no toolbar there)")
	ui_layer.hide()
	await settle(3)
	check(is_equal_approx(hud().layout_fit_scale,1.0) and hud().position == Vector2.ZERO,"hiding the toolbar restores the full-size layout")

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
