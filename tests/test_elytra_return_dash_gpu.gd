extends "res://tests/test_mc_frontier.gd"
## Actual production World, native sprites/trails and controlled real flight frames.
var folder:String
var movie_frame:int = 0
var capture_movie:bool = false
var camera:Camera2D
var caption:Label
var metrics:Array = []

func shot(label:String = "",save_movie:bool = false) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image:Image = root.get_texture().get_image()
	if not label.is_empty(): image.save_png(folder.path_join(label+".png"))
	if save_movie and capture_movie:
		image.save_png(folder.path_join("frames/frame_%04d.png" % movie_frame))
		movie_frame += 1
	return image

func difference(a:Image,b:Image) -> int:
	var count:int = 0
	for y:int in range(0,a.get_height(),2):
		for x:int in range(0,a.get_width(),2):
			var p:Color = a.get_pixel(x,y)
			var q:Color = b.get_pixel(x,y)
			if maxf(absf(p.r-q.r),maxf(absf(p.g-q.g),absf(p.b-q.b)))>0.09: count+=1
	return count

func flyer(role:String,point:Vector2) -> Node2D:
	var unit:Node2D = actor(role,point)
	unit.set_player_control_peer(0)
	unit.set_physics_process(false)
	unit.health_bar.hide()
	return unit

func opponent(point:Vector2) -> Node2D:
	var node:Node2D = dummy(Vector2(-10000,-10000))
	node.global_position = point
	node.set_physics_process(false)
	node.Can_Attack = false
	node.Can_Skill = false
	node.Health_Restore = 0
	node.health_bar.hide()
	return node

func step(unit:Node2D,delta:float) -> void:
	if unit._airborne: unit._update_flight(delta)
	else: unit._step_glide(delta)
	unit._rocket_display_left = maxf(unit._rocket_display_left-delta,0.0)
	unit._update_flight_media()
	unit._update_wing_animation(delta)
	if unit.has_method("allows_character_motion_effects") and unit.allows_character_motion_effects(): unit._process_auto_after_image(delta)

func finish(code:int) -> void:
	if done: return
	var output:=FileAccess.open(folder.path_join("metrics.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"movie_frames":movie_frame,"metrics":metrics},"\t"))
	output.close()
	print("ELYTRA_RETURN_DASH_GPU checks=",checks," failures=",failures," frames=",movie_frame)
	await super.finish(code)

func run() -> void:
	if DisplayServer.get_name()=="headless": push_error("Actual GPU renderer required"); quit(2); return
	game = root.get_node("Game")
	var original:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Environment = "none"
	game.Game_Settings.Map_Background = "grass"
	game.Game_Settings.Minecraft_Clouds = false
	game.Game_Settings.Development_Mode = false
	root.size = Vector2i(1080,720)
	root.content_scale_size = root.size
	Engine.max_fps = 60
	await setup_world()
	saved = original
	folder = OS.get_environment("ELYTRA_EVIDENCE_DIR")
	if folder.is_empty(): folder = "user://elytra_dash_gpu"
	capture_movie = OS.get_environment("ELYTRA_CAPTURE_MOVIE")=="1"
	DirAccess.make_dir_recursive_absolute(folder)
	if capture_movie: DirAccess.make_dir_recursive_absolute(folder.path_join("frames"))
	create_timer(170,true,false,true).timeout.connect(func():finish(2))
	world.set_process(false)
	world.set_physics_process(false)
	world.control.hide()
	world.versus_label.hide()
	for layer:CanvasLayer in root.find_children("*","CanvasLayer",true,false): layer.hide()
	if world.map_group.has("Map30x30"):
		world.now_choose_map = "Map30x30"
		world.refresh_map_presentation()
	var bounds:Rect2 = world.return_map_world_rect(world._current_map_node())
	camera = Camera2D.new()
	world.add_child(camera)
	camera.make_current()
	camera.global_position = bounds.get_center()
	camera.zoom = Vector2.ONE*minf(650.0/bounds.size.y,900.0/(bounds.size.x+300.0))
	camera.force_update_scroll()
	var overlay:=CanvasLayer.new()
	overlay.layer = 60
	world.add_child(overlay)
	caption = Label.new()
	caption.position = Vector2(24,18)
	caption.add_theme_font_size_override("font_size",22)
	caption.add_theme_color_override("font_color",Color.WHITE)
	caption.add_theme_color_override("font_outline_color",Color(0,0,0,0.9))
	caption.add_theme_constant_override("outline_size",5)
	overlay.add_child(caption)
	var analyzer:Node = world.get_node_or_null("CombatThreatAnalyzer")
	if analyzer!=null: analyzer.set_physics_process(false)
	await return_scene(bounds)
	for role:String in ["鞘翅长矛","鞘翅重锤长矛"]: await dash_scene(role,bounds,analyzer)
	await finish(0 if failures==0 else 1)

func return_scene(bounds:Rect2) -> void:
	var units:Array[Node2D] = []
	var targets:Array[Node2D] = []
	var entered:Array[bool] = [false,false,false]
	var roles:Array[String] = ["鞘翅重锤","鞘翅长矛","鞘翅重锤长矛"]
	for i:int in range(3):
		var point:=Vector2(bounds.end.x+15,bounds.get_center().y+(i-1)*95)
		var unit:Node2D = flyer(roles[i],point)
		unit.Can_Attack = false
		unit.Can_Skill = false
		unit.apply_damage_disable(30)
		unit._glide_velocity = Vector2.RIGHT*850
		unit.velocity = unit._glide_velocity
		unit._patrol_rect_refresh = 0
		var enemy:Node2D = opponent(point+Vector2(1400,0))
		unit._pvp_target = enemy
		units.append(unit)
		targets.append(enemy)
	await physics_frame
	await physics_frame
	caption.text = "验证回放｜三种鞘翅主动回航 · 不传送、不硬夹位置"
	await shot("return_before")
	var maximum:float = 0.0
	for frame:int in range(150):
		for i:int in range(3):
			step(units[i],1.0/60.0)
			var p:Vector2 = units[i].global_position
			maximum = maxf(maximum,p.distance_to(p.clamp(bounds.position,bounds.end)))
			entered[i] = entered[i] or bounds.grow(-12).has_point(p)
		if frame==75: await shot("return_after")
		else: await shot("",true)
	for i:int in range(3): check(entered[i],roles[i]+": actual World flight returns inside the visible map")
	check(maximum<260,"actual GPU scene stays in the soft return band")
	metrics.append({"phase":"return","max_outside":maximum,"entered":entered})
	for node:Node2D in units+targets: node.queue_free()
	await process_frame
	await process_frame

func dash_scene(role:String,bounds:Rect2,analyzer:Node) -> void:
	var point:Vector2 = bounds.get_center()+Vector2(-140,0)
	var unit:Node2D = flyer(role,point)
	var target:Node2D = opponent(bounds.get_center()+Vector2(20,0))
	unit._pvp_target = target
	unit._glide_velocity = Vector2.RIGHT*240
	unit.velocity = unit._glide_velocity
	unit.glide_gravity = 0.0
	unit.glide_drag = 0.0
	unit._rocket_cooldown = 100
	unit._pierce_dash_cooldown_left = 0
	unit._face_flight_direction()
	camera.global_position = bounds.get_center()+Vector2(10,-20)
	camera.zoom = Vector2.ONE*2.0
	camera.force_update_scroll()
	await physics_frame
	await physics_frame
	if analyzer!=null:
		game.Game_Settings.Training_Debug_Mode = true
		analyzer._physics_process(0.2)
	caption.text = role+"｜对准敌人后冲刺 · 矛尖实际判定 / 蓝色检测"
	await shot(role+"_ready")
	check(unit.get_debug_detection_regions().size()==1,"GPU "+role+": ready state declares the forward activation cone")
	if analyzer!=null:
		check(analyzer.visible and not analyzer._debug_threats.is_empty(),"GPU "+role+": real threat display receives active geometry")
		game.Game_Settings.Training_Debug_Mode = false
		analyzer._physics_process(0.2)
		check(not analyzer.visible and analyzer._debug_threats.is_empty(),"GPU "+role+": disabling threat display clears old shapes")
	var hp:int = target.health
	var hit:bool = false
	var crossed:bool = false
	var delayed:bool = true
	var peak:float = 0.0
	var hit_point:Vector2
	for frame:int in range(95):
		step(unit,1.0/60.0)
		peak = maxf(peak,unit._glide_velocity.length())
		crossed = crossed or unit.global_position.x>target.global_position.x+35
		var stage:String = "滑翔"
		if unit._pierce_dashing: stage = "穿刺冲刺中"
		if target.health<hp: stage = "命中后提速" if unit._pierce_dashing else "已穿过"
		if unit._airborne: stage = "穿过后 · 弹起连砸"
		caption.text = role+"｜"+stage+"｜速度 %.0f / %.0f" % [unit._glide_velocity.length(),unit.maximum_flight_speed]
		if target.health<hp and not hit:
			hit = true
			delayed = not unit._airborne
			hit_point = unit.global_position
			await shot(role+"_hit")
		elif frame==40: await shot(role+"_after_pass")
		else: await shot("",true)
		if frame==18:
			game.now_stop_state = true
			var original_pose:Vector2 = unit.global_position
			var time_left:float = unit._pierce_dash_left
			unit._step_glide(0.3)
			check(unit.global_position==original_pose and unit._pierce_dash_left==time_left,"GPU "+role+": paused render does not advance dash or position")
			var with_actor:Image = await shot()
			unit.graphics.hide()
			var without_actor:Image = await shot()
			unit.graphics.show()
			check(difference(with_actor,without_actor)>20,"GPU "+role+": native weapon/wings remain genuinely visible in the composed frame")
			game.now_stop_state = false
	check(hit and peak>=700,role+": actual World contact visibly increases physical flight speed")
	check(crossed and delayed,role+": actual World pass clears the target before any combo leap")
	metrics.append({"phase":role,"hit":hit,"hit_point":hit_point,"peak_speed":peak,"crossed":crossed,"delayed":delayed})
	unit.queue_free()
	target.queue_free()
	await process_frame
	await process_frame
