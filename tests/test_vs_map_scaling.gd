extends SceneTree
## Real World scene: small/reference/large titles, bilingual mirror and Boss roster HUD.

var world:Node
var game:Node
var checks:int = 0
var failures:int = 0
var snapshots:String = "user://recordings/vs_map_scaling"
const LONG_TITLE:String = "[center][color=#66aaff][b]天堂陨落长弓[/b][/color]  [color=#FFFFFF][b]VS[/b][/color]  [color=#ff6666][b]鞘翅长矛[/b][/color][/center]"
const SHORT_TITLE:String = "[center][color=#66aaff][b]牛[/b][/color]  [color=#FFFFFF][b]VS[/b][/color]  [color=#ff6666][b]木剑[/b][/color][/center]"

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool,description:String) -> void:
	checks += 1
	if ok:
		print("PASS: ",description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func point_camera(map_name:String) -> void:
	# A normal running World updates this in _process. The test freezes gameplay
	# so manually move the real Camera2D before checking GPU pixels.
	world.camera_2d.global_position = world.return_map_world_rect(world.map_group[map_name]).get_center()
	world.camera_2d.reset_smoothing()
	world._apply_camera_zoom()
	world.camera_2d.force_update_scroll()

func select_map(map_name:String,title:String) -> Dictionary:
	world.now_choose_map = map_name
	world.refresh_map_presentation()
	point_camera(map_name)
	world.versus_label.text = title
	world.versus_label.visible = true
	world.interaction_label.visible = false
	world.refresh_top_text_layout()
	if is_instance_valid(world._center_watermark_root): world._center_watermark_root.hide()
	var map_rect:Rect2 = world.return_map_visual_rect(world.map_group[map_name])
	var title_label:RichTextLabel = world.versus_label
	var font:int = title_label.get_theme_font_size("bold_font_size")
	var scale:float = world.get_map_versus_scale(world.map_group[map_name])
	print("VS_MAP_METRIC ",map_name," scale=",scale," bounds=",world.versus_font_min_size,"..",world.versus_font_max_size,
		" chosen=",font," world_box=",title_label.get_rect()," content=",title_label.get_content_height(),
		" camera=",world.get_effective_camera_zoom())
	check(title_label.visible and font <= world.versus_font_max_size and font >= world.versus_font_min_size,map_name+": title uses the map-specific font bounds")
	check(title_label.size.x == map_rect.size.x and absf(title_label.position.x - map_rect.position.x) < 0.1,map_name+": title stays as wide as the selected map")
	check(title_label.get_content_height() <= title_label.size.y + 0.5,map_name+": long names and effects have enough line height")
	check(title_label.position.y + title_label.size.y <= map_rect.position.y - world.interaction_map_gap + 0.5,map_name+": title stays outside the arena")
	return {"font":font,"max":world.versus_font_max_size,"scale":scale,"screen_font":float(font)*world.get_effective_camera_zoom()}

func save_frame(name:String) -> void:
	await RenderingServer.frame_post_draw
	var screenshot:Image = root.get_texture().get_image()
	check(screenshot != null and screenshot.get_size().x >= 500,"GPU rendered the "+name+" layout")
	if screenshot != null:
		var text_pixels:int = 0
		for y:int in range(0,screenshot.get_height(),2):
			for x:int in range(0,screenshot.get_width(),2):
				var color:Color = screenshot.get_pixel(x,y)
				if (color.r > 0.65 and color.g < 0.55) or (color.r > 0.72 and color.g > 0.72 and color.b > 0.72):
					text_pixels += 1
		check(text_pixels > 20,name+": VS/name glyphs are visible in actual GPU pixels")
		screenshot.save_png(snapshots.path_join(name+".png"))

func check_bilingual_mirror() -> void:
	# The real recorder uses this same mirror. If the standalone baseline lacks
	# its independently fitted localized titles, skip only that newer behavior.
	var mirror:Node = load("res://scripts/ui/battle_record_locale.gd").new()
	world.add_child(mirror)
	mirror.begin(world,root)
	mirror.sync()
	var title_id:int = world.versus_label.get_instance_id()
	check(mirror.copies.has(title_id),"bilingual recording mirror captures the scaled VS title")
	if mirror.copies.has(title_id):
		var copies:Dictionary = mirror.copies[title_id]
		var map_rect:Rect2 = world.return_map_visual_rect(world.map_group[world.now_choose_map])
		for locale:String in ["zh","en"]:
			var copy:RichTextLabel = copies[locale].text
			check(copy.get_theme_font_size("bold_font_size") > 12,"recording "+locale+": large map title is larger than reference font")
			if mirror.has_method("_fit_localized_versus"):
				check(copy.get_content_height() <= copy.size.y + 0.5,"recording "+locale+": translated lines are not clipped")
				var bottom:Vector2 = copy.get_global_transform() * Vector2(0,copy.get_content_height())
				check(bottom.y <= map_rect.position.y - world.interaction_map_gap + 0.5,"recording "+locale+": translated title stays above the wall")
			check(copy.text.contains("[color=") and copy.text.contains("VS"),"recording "+locale+": title retains colors and separator")
	select_map("Map10x10",LONG_TITLE)
	mirror.sync()
	if mirror.copies.has(title_id):
		check((mirror.copies[title_id].en.text as RichTextLabel).get_theme_font_size("bold_font_size") <= 12,
			"recording mirror invalidates its font cache when returning to the reference map")
	mirror.finish()
	mirror.queue_free()
	await process_frame

func check_boss_roster() -> void:
	game.Game_Settings.Training_Mode = true
	game.Game_Settings.Training_Mode_Type = "boss"
	game.Game_Settings.Training_Boss_Wheel_Battle = true
	check(world._queue_battle_mode_active() and not game.is_rotation_training_mode(),"Boss wheel uses the legacy roster VS")
	var left_name:Label = world._make_rotation_name_label(HORIZONTAL_ALIGNMENT_RIGHT)
	left_name.text = "Longbow of the Heavens"
	world.rotation_left_root.add_child(left_name)
	var right_name:Label = world._make_rotation_name_label(HORIZONTAL_ALIGNMENT_LEFT)
	right_name.text = "鞘翅长矛"
	world.rotation_right_root.add_child(right_name)
	var reference_pixels:float = 0.0
	for map_name:String in ["Map2x2","Map10x10","Map50x50","Map10x10"]:
		world.now_choose_map = map_name
		world.refresh_map_presentation()
		point_camera(map_name)
		if is_instance_valid(world._center_watermark_root): world._center_watermark_root.hide()
		world._layout_rotation_versus_hud()
		var rect:Rect2 = world.return_map_visual_rect(world.map_group[map_name])
		var hud:Control = world.rotation_versus_root
		var pixel_size:float = hud.scale.x * float(world.rotation_vs_label.get_theme_font_size("font_size")) * world.get_effective_camera_zoom()
		print("VS_ROSTER_METRIC ",map_name," world_scale=",hud.scale," px_font=",pixel_size," width=",hud.size.x * hud.scale.x)
		check(hud.visible and world.rotation_vs_label.visible,map_name+": Boss VS and rosters remain visible")
		check(absf(hud.size.x * hud.scale.x - rect.size.x) < 0.5,map_name+": scaled roster stays within arena width")
		check(hud.position.y + hud.size.y * hud.scale.y < rect.position.y,map_name+": complete roster stays above the arena")
		for side_label:Label in [left_name,right_name]:
			var column:Control = side_label.get_parent() as Control
			var font:Font = side_label.get_theme_font("font")
			var measured:float = font.get_string_size(side_label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,side_label.get_theme_font_size("font_size")).x
			check(measured * side_label.scale.x <= column.size.x + 0.5,map_name+": localized/long roster name fits its column")
		if map_name == "Map10x10":
			reference_pixels = pixel_size
			check(is_equal_approx(hud.scale.x,1.0),"Map10x10 roster keeps its original scale")
		elif map_name == "Map50x50":
			check(hud.scale.x > 3.0 and pixel_size > reference_pixels * 0.7,"Map50x50 Boss VS no longer shrinks with camera zoom")
			await save_frame("boss_50x50")
	left_name.queue_free()
	right_name.queue_free()
	await process_frame

func run() -> void:
	create_timer(85.0,true,false,true).timeout.connect(func(): print("VS_MAP_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	var saved_settings:Dictionary = game.Game_Settings.duplicate(true)
	var saved_locale:String = game.current_locale
	game.set_language("zh",false)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Boss_Wheel_Battle = false
	game.Game_Settings.Training_Boss_Intro = false
	game.Game_Settings.Map_Background = "blue"
	game.Game_Settings.Camera_Move = false
	root.size = Vector2i(540,960)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	await create_timer(0.45,true,false,true).timeout
	world.set_process(false)
	world.set_physics_process(false)
	world.control.get_parent().hide() # Hide all screen-space controls in GPU evidence.
	if is_instance_valid(world._center_watermark_root): world._center_watermark_root.hide()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(snapshots))
	var tiny:Dictionary = select_map("Map2x2",SHORT_TITLE)
	await save_frame("ordinary_2x2")
	var baseline:Dictionary = select_map("Map10x10",LONG_TITLE)
	await save_frame("ordinary_10x10")
	var medium:Dictionary = select_map("Map30x30",LONG_TITLE)
	var large:Dictionary = select_map("Map50x50",LONG_TITLE)
	check(baseline.max == 12 and world._versus_base_min_size == 6,"Map10x10 preserves the old 12/6 font bounds")
	check(tiny.max < baseline.max and baseline.max < medium.max and medium.max < large.max,"font bounds follow increasing map size")
	check(large.font > baseline.font and large.font > 12,"long names actually render larger on a large map")
	check(large.screen_font > baseline.screen_font * 0.55,"large-map VS remains legible at the fitted camera zoom")
	await save_frame("ordinary_50x50")
	await check_bilingual_mirror()
	await check_boss_roster()
	world.queue_free()
	await process_frame
	game.Game_Settings = saved_settings
	game.set_language(saved_locale,false)
	print("VS_MAP_SCALING: %d checks / %d failures" % [checks,failures])
	quit(1 if failures > 0 else 0)
