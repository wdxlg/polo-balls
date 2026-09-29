extends "res://tests/test_mc_snow_golem.gd"
## Real World/GPU: original full-heading pixels, worn-head fracture and actual projectile fan.
var folder:String
var frames:int = 0
var save_movie:bool = false
var camera:Camera2D
var caption:Label
var metrics:Array = []

func grab(label:String = "",movie:bool = false) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image:Image = root.get_texture().get_image()
	if not label.is_empty(): image.save_png(folder.path_join(label+".png"))
	if movie and save_movie:
		image.save_png(folder.path_join("frames/frame_%04d.png" % frames))
		frames+=1
	return image

func changed(a:Image,b:Image) -> int:
	var count:int = 0
	for y:int in range(0,a.get_height(),2):
		for x:int in range(0,a.get_width(),2):
			var p:Color = a.get_pixel(x,y)
			var q:Color = b.get_pixel(x,y)
			if maxf(absf(p.r-q.r),maxf(absf(p.g-q.g),absf(p.b-q.b)))>0.08: count+=1
	return count

func golem(point:Vector2) -> Node2D:
	var unit:Node2D = spawn(GOLEM_PATH,point)
	unit.state_machine.set_physics_process(false)
	unit.set_physics_process(false)
	unit.set_process(false)
	unit._field.set_physics_process(false)
	unit.health_bar.hide()
	return unit

func finish(code:int) -> void:
	if done: return
	var file:=FileAccess.open(folder.path_join("metrics.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"frames":frames,"metrics":metrics},"\t"))
	file.close()
	print("SNOW_BURST_GPU_RESULT checks=",checks," failures=",failures," frames=",frames)
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
	var center:Vector2 = await setup_world()
	saved = original
	folder = OS.get_environment("SNOW_GOLEM_EVIDENCE_DIR")
	if folder.is_empty(): folder = "user://snow_golem_burst_gpu"
	DirAccess.make_dir_recursive_absolute(folder)
	save_movie = OS.get_environment("SNOW_GOLEM_CAPTURE_MOVIE")=="1"
	if save_movie: DirAccess.make_dir_recursive_absolute(folder.path_join("frames"))
	create_timer(170,true,false,true).timeout.connect(func():finish(2))
	world.set_process(false)
	world.set_physics_process(false)
	world.control.hide()
	world.versus_label.hide()
	for layer:CanvasLayer in root.find_children("*","CanvasLayer",true,false): layer.hide()
	camera = Camera2D.new()
	world.add_child(camera)
	camera.make_current()
	camera.global_position = center
	camera.zoom = Vector2.ONE*2.5
	camera.force_update_scroll()
	var ui:=CanvasLayer.new()
	ui.layer = 60
	world.add_child(ui)
	caption = Label.new()
	caption.position = Vector2(22,16)
	caption.add_theme_font_size_override("font_size",24)
	caption.add_theme_color_override("font_outline_color",Color.BLACK)
	caption.add_theme_constant_override("outline_size",5)
	ui.add_child(caption)
	await heading_gallery(center)
	await fracture_and_volley(center)
	await finish(0 if failures==0 else 1)

func heading_gallery(center:Vector2) -> void:
	caption.text = "攻击瞄准｜16个原版方向：图示8方向，带头与露脸；行走仅左右斜向"
	var nodes:Array[Node2D] = []
	var labels:Array[Label] = []
	for state:int in range(2):
		for i:int in range(8):
			var row:int = state*2+i/4
			var column:int = i%4
			var unit:Node2D = golem(center+Vector2((column-1.5)*95,(row-1.5)*61))
			unit.has_pumpkin = state==0
			unit._aim_hold_left = 0
			unit.direction = Vector2.from_angle(float(i)*TAU/8)
			unit._aim = unit.direction
			unit._aim_hold_left = 0.25
			unit.move(0.0,0.016)
			unit.visual_mob()
			nodes.append(unit)
			check(unit._aim_pose==i*2 and not unit.is_character_visual_flipped_h(),"GPU native heading %d state=%d is not mirrored by the mover" % [i*2,state])
			var label:=Label.new()
			label.text = ("带头 " if state==0 else "露脸 ")+["右","右下","下","左下","左","左上","上","右上"][i]
			label.add_theme_font_size_override("font_size",14)
			label.add_theme_constant_override("outline_size",2)
			label.position = unit.global_position+Vector2(-16,26)
			label.scale = Vector2.ONE*0.5
			world.add_child(label)
			labels.append(label)
	game.now_stop_state = true
	var visible:Image = await grab("native_heading_gallery")
	for unit:Node2D in nodes: unit.image.hide()
	var blank:Image = await grab()
	for unit:Node2D in nodes: unit.image.show()
	check(changed(visible,blank)>1500,"all worn/bare native characters contribute real GPU pixels")
	check(nodes[2].image.texture!=nodes[6].image.texture and nodes[10].image.texture!=nodes[14].image.texture,"forward/rear are distinct original-model views in both head states")
	game.now_stop_state = false
	for node:Node2D in nodes: node.queue_free()
	for label:Label in labels: label.queue_free()
	await process_frame
	await process_frame

func advance_demo(unit:Node2D,delta:float) -> void:
	# Rendering/readback can be slower than 60 Hz; advance the REAL projectile
	# tick on the same combat delta as its firing schedule, never duplicate move().
	unit.step_mob(delta)
	for node:Node in get_nodes_in_group("MCSnowball"):
		if node.Master!=unit or node.is_queued_for_deletion(): continue
		node.state_machine.set_physics_process(false)
		node.set_physics_process(false)
		node.tick_physics(node.State.Move,delta)
	for node:Node in get_nodes_in_group("MCBlockFragments"):
		if node.has_meta("snow_pumpkin_break") and not node.is_queued_for_deletion():
			node.set_process(false)
			node.advance(delta)

func fracture_and_volley(center:Vector2) -> void:
	var unit:Node2D = golem(center+Vector2(-115,-30))
	var target:Node2D = dummy(Vector2(-10000,-10000))
	target.global_position = unit.global_position+Vector2.from_angle(PI/8)*225
	target.set_physics_process(false)
	target.health_bar.hide()
	unit.burst_probability = 0.0 # Demonstrate the real half-health guarantee, not a lucky random roll.
	unit.direction = unit.global_position.direction_to(target.global_position)
	unit.visual_mob()
	camera.global_position = center+Vector2(-10,-10)
	camera.zoom = Vector2.ONE*3.0
	camera.force_update_scroll()
	var analyzer:Node = world.get_node_or_null("CombatThreatAnalyzer")
	if analyzer!=null: analyzer.set_physics_process(false)
	await physics_frame
	await physics_frame
	caption.text = "雪傀儡｜半血南瓜碎裂 → 下一轮必定20发连射"
	await grab("pumpkin_before")
	for i:int in range(25):
		advance_demo(unit,1.0/60.0)
		await grab("",true)
	var snow_before:Dictionary = unit._field.patches.duplicate(true)
	unit.take_damage(ceilf(unit.Max_health*0.5),true)
	var effect:Node2D
	for node:Node in get_nodes_in_group("MCBlockFragments"):
		if node.has_meta("snow_pumpkin_break"): effect = node
	check(is_instance_valid(effect) and not unit.has_pumpkin and unit.force_next_burst,"actual GPU half-health transition creates block shards and the next-attack guarantee")
	check(unit._field.patches==snow_before and get_nodes_in_group("MCSnowGolem").size()==1,"GPU fracture leaves no consumed snow, ground pumpkin or mini")
	if is_instance_valid(effect):
		caption.text = "首次半血｜南瓜原版方块碎裂 · 露脸 · 下一轮保证连射"
		for i:int in range(6):
			advance_demo(unit,1.0/60.0)
			await grab("",true)
		game.now_stop_state = true
		var with_shards:Image = await grab("pumpkin_break")
		effect.hide()
		var without_shards:Image = await grab()
		effect.show()
		var pixels:int = changed(with_shards,without_shards)
		check(pixels>30,"shared native pumpkin fragments are genuinely visible in the composed frame")
		var age:float = effect.age
		effect._process(0.5)
		check(effect.age==age,"GPU fracture pauses instead of continuing behind a stopped battle")
		metrics.append({"phase":"fracture","sampled_fragment_pixels":pixels,"pieces":effect.pieces.size()})
		game.now_stop_state = false
	var saw_burst:bool = false
	var peak_visible:int = 0
	var captured_fan:bool = false
	for frame:int in range(240):
		advance_demo(unit,1.0/60.0)
		saw_burst = saw_burst or unit._burst_remaining>0
		var count:int = 0
		for node:Node in get_nodes_in_group("MCSnowball"):
			if node.Master==unit and not node.is_queued_for_deletion(): count+=1
		peak_visible = maxi(peak_visible,count)
		caption.text = "雪傀儡｜"+("等待下一轮攻击" if unit.shots_fired==0 else "半血保证连射")+"｜已发 %d / 20｜每发±15°散射" % mini(unit.shots_fired,20)
		if unit.shots_fired>=10 and not captured_fan:
			captured_fan = true
			await grab("twenty_shot_fan")
			if analyzer!=null:
				game.Game_Settings.Training_Debug_Mode = true
				analyzer._physics_process(0.2)
				check(analyzer.visible and not analyzer._debug_threats.is_empty(),"actual threat display is populated during the live projectile fan")
				await grab("volley_real_threats")
				game.Game_Settings.Training_Debug_Mode = false
				analyzer._physics_process(0.2)
				check(not analyzer.visible and analyzer._debug_threats.is_empty(),"turning off threat display clears the fan geometry")
		else: await grab("",true)
		if unit.shots_fired>=20 and unit._burst_remaining==0: break
	check(saw_burst and unit.shots_fired==20 and unit.bursts_started==1,"actual World/GPU loop completes exactly one guaranteed twenty-shot burst")
	check(peak_visible>=4 and captured_fan,"multiple real snowballs form a visible moving fan, not one repeated fake sprite")
	check(unit.image.texture in unit.BARE and not unit.is_character_visual_flipped_h(),"bare-face aiming stays correctly oriented after the pumpkin is gone")
	check(unit.head_break_count==1 and get_nodes_in_group("MCSnowGolem").size()==1,"the live burst produces no second head or autonomous descendant")
	metrics.append({"phase":"volley","shots":unit.shots_fired,"peak_visible_projectiles":peak_visible,"bursts":unit.bursts_started})
	unit.Can_Attack = false # Let existing real snowballs finish without starting a second demo round.
	for i:int in range(25):
		advance_demo(unit,1.0/60.0)
		await grab("",true)
	await grab("bare_after_volley")
	unit.queue_free()
	target.queue_free()
	await process_frame
