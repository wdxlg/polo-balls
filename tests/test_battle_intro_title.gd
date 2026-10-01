extends SceneTree
## 开战大标题：钟声响起时砸出「A VS B」我的世界 3D 立体字（像素字按格挤出的真网格）（阵营色 + 金色 VS），录像视口里按各自语言各放一份，约 2.3 秒后自动消失；录像码率封顶约 10 Mbps。
var world:Node
var game:Node
var checks:int = 0
var failures:int = 0
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("BATTLE_INTRO_TITLE FAIL: "+label)
func wait_until(cond:Callable,ms:int) -> void:
	var deadline:int = Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline and not cond.call(): await process_frame
func count_opaque(img:Image) -> int:
	var opaque:int = 0
	for y:int in range(0,img.get_height(),4):
		for x:int in range(0,img.get_width(),4):
			if img.get_pixel(x,y).a > 0.5: opaque += 1
	return opaque
func texts(layer:Node) -> Array:
	return (layer.lines as Array).map(func(l:Dictionary) -> String: return str(l.text))
func run() -> void:
	create_timer(60.0,true,false,true).timeout.connect(func(): print("BATTLE_INTRO_TITLE TIMEOUT"); quit(2))
	game = root.get_node("Game")
	var recorder:GDScript = load("res://scripts/ui/battle_recorder.gd")
	check(recorder.VIDEO_MAXRATE == "10M" and recorder.VIDEO_BUFSIZE == "20M","recordings are capped near 10 Mbps")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Boss_Intro = false
	game.Game_Settings.Map_Background = "blue"
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	await process_frame
	await process_frame
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	game.now_stop_state = false
	# 假装正在录制：两条录像的抓帧视口。
	var Intro:GDScript = load("res://scripts/ui/battle_intro_title.gd")
	var captures:Dictionary = {}
	for locale:String in ["zh","en"]:
		var sub := SubViewport.new()
		sub.size = Vector2i(540,960)
		sub.disable_3d = true
		root.add_child(sub)
		Intro.register_capture(sub,locale)
		captures[locale] = sub
	world.reset()
	await process_frame
	var gs:Dictionary = game.Game_Settings
	gs.Training_Mode_Type = "rotation"; gs.Rotation_Match_Type = "duel"; gs.Training_Wheel_Battle = false
	gs.Rotation_Multi_Characters = true; gs.Rotation_Blue_Count = 1; gs.Rotation_Red_Count = 1
	world.control.team.show()
	world._battle_setup_next_id = 1
	for pair:Array in [["left","苦力怕"],["right","烈焰人"]]: world._enqueue_rotation_character("",str(pair[1]),world._rotation_spawn_position(str(pair[0])),str(pair[0]),"",1)
	world.control.hide(); world.control.team.hide()
	world._update_special_training_modes(0.0)
	for unit:Node in get_nodes_in_group("Ball"): unit.process_mode = Node.PROCESS_MODE_DISABLED
	await wait_until(func() -> bool: return not get_nodes_in_group(Intro.GROUP).is_empty(),3000)
	var layers:Array = get_nodes_in_group(Intro.GROUP)
	var on_screen:Array = layers.filter(func(n:Node) -> bool: return n.get_parent() == root)
	var zh:Array = layers.filter(func(n:Node) -> bool: return n.get_parent() == captures.zh)
	var en:Array = layers.filter(func(n:Node) -> bool: return n.get_parent() == captures.en)
	check(bool(world._battle_start_bell_played) and on_screen.size() == 1 and zh.size() == 1 and en.size() == 1,"the start bell shows the title on screen and in both recording viewports (%d/%d/%d)" % [on_screen.size(),zh.size(),en.size()])
	if zh.size() == 1 and en.size() == 1 and on_screen.size() == 1:
		var zt:Array = texts(zh[0])
		var et:Array = texts(en[0])
		check(zt.size() == 3 and zt[1] == "VS" and zt.has("苦力怕") and zt.has("烈焰人"),"Chinese copy reads 苦力怕 VS 烈焰人 (%s)" % str(zt))
		check(et.size() == 3 and et[1] == "VS" and et.has("Creeper") and et.has("Blaze"),"English copy reads Creeper VS Blaze (%s)" % str(et))
		var styles:Array = (zh[0].lines as Array).map(func(l:Dictionary): return l.style)
		check(styles[1] == "gold" and styles[0] is Color and styles[2] is Color and styles[0] != styles[2],"sides use their team colours around a gold VS")
		var title:Control = on_screen[0].title
		check(title.get_script().resource_path.ends_with("mc_title_text.gd") and title.size.x > root.get_visible_rect().size.x * 0.8,"the on-screen title is the wide Minecraft logo text")
		check(title.scale.x > 1.0,"the title slams in from a larger scale")
		# 先过两帧：标题出现那一帧的 delta 带着开局卡顿，计时器会被它一口吃掉。
		await process_frame
		await process_frame
		await create_timer(0.7,true,false,true).timeout
		var shot:Image = root.get_texture().get_image()
		shot.save_png(OS.get_environment("TEMP") + "/intro_title_shot.png")
		var opaque:int = count_opaque(title.texture().get_image())
		check(opaque > 200 and is_equal_approx(title.scale.x,1.0) and title.modulate.a > 0.99,"the 3D title has rendered and settled at full size (%d opaque samples)" % opaque)
		var recorded:int = count_opaque(en[0].title.texture().get_image())
		check(recorded > 200,"the copy inside a 2D-only recording viewport renders its 3D text too (%d)" % recorded)
		var mesh_count:int = title.viewport.find_children("*","MeshInstance3D",true,false).size()
		check(mesh_count == 6 and title.viewport.own_world_3d,"each of the three lines is a real extruded mesh with an outline body (%d meshes)" % mesh_count)
		await create_timer(2.0,true,false,true).timeout
		check(get_nodes_in_group(Intro.GROUP).is_empty(),"the title rises away and frees itself")
	world.reset()
	await process_frame
	for sub:Node in captures.values(): sub.queue_free()
	game.Game_Settings = saved
	world.queue_free()
	await process_frame
	var leftover_door:Node = root.get_node_or_null("DarkOakDoorTransition")
	if leftover_door != null: leftover_door.queue_free()
	print("BATTLE_INTRO_TITLE_RESULT checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)

