extends "res://tests/test_diamond_spear_live.gd"
## Real GPU / physics-frame audit and a controlled visual sample, not autonomous combat coverage.
class Driver extends Node:
	var low:Node2D
	var high:Node2D
	var target:Node2D
	var clock:float = 0.0
	var moved:bool = false
	var old_target:Vector2
	var birth_frames:Array[int] = []
	var known:Dictionary = {}
	func _physics_process(delta:float) -> void:
		clock += delta
		for unit:Node2D in [low,high]:
			if unit._action!=unit.Action.IDLE: unit._tick_action(delta)
			unit._apply_pose(false)
		if high.total_blinks>0 and not moved:
			moved = true
			target.global_position += Vector2(0,35)
		for node:Variant in high._visual_nodes:
			if is_instance_valid(node) and not node.is_queued_for_deletion() and node.attack_echo and not known.has(node.get_instance_id()):
				known[node.get_instance_id()] = true
				birth_frames.append(Engine.get_physics_frames())

class Marker extends Node2D:
	func _draw() -> void:
		draw_arc(Vector2.ZERO,6.0,0.0,TAU,24,Color(0.65,0.96,1.0,0.70),0.7,true)
		draw_line(Vector2(-9,0),Vector2(9,0),Color(0.65,0.96,1.0,0.55),0.6,true)
		draw_line(Vector2(0,-9),Vector2(0,9),Color(0.65,0.96,1.0,0.55),0.6,true)

func caption(layer:CanvasLayer,text:String,point:Vector2,size:int) -> void:
	var label := Label.new()
	label.text = text
	label.position = point
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",Color(0.84,0.99,1.0))
	label.add_theme_color_override("font_shadow_color",Color(0.0,0.025,0.035))
	label.add_theme_constant_override("shadow_offset_x",2)
	label.add_theme_constant_override("shadow_offset_y",2)
	layer.add_child(label)

func run() -> void:
	root.size = Vector2i(960,600)
	root.content_scale_size = root.size
	var center:Vector2 = await setup()
	Engine.physics_ticks_per_second = 60
	Engine.max_fps = 120
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	create_timer(35).timeout.connect(func(): finish(2))
	for layer:Node in world.find_children("*","CanvasLayer",true,false): layer.visible = false
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.position = center
	camera.zoom = Vector2(2.8,2.8)
	camera.make_current()
	var a:Node2D = spawn(center+Vector2(-90,-60))
	var ea:Node2D = victim(a.global_position+Vector2(25,0))
	var b:Node2D = spawn(center+Vector2(-90,35))
	var eb:Node2D = victim(b.global_position+Vector2(85,0))
	for unit:Node2D in [a,b,ea,eb]:
		unit.state_machine.set_physics_process(false)
		unit.collision_layer = 0
		unit.health_bar.hide()
	a._momentum = 600.0
	b._momentum = 850.0
	a._attack_wait = 0.0
	b._blink_wait = 0.0
	var marker := Marker.new()
	world.add_child(marker)
	marker.global_position = eb.global_position
	var old_target:Vector2 = eb.global_position
	# Warm native textures and the new line/trail pipelines before timing the actual action.
	b._emit_echo(b.global_position,Vector2.RIGHT,0.20,true,0.0,1.0,90.0,true)
	b._play_pierce_feedback(b.global_position,old_target)
	b._play_impact_feedback(old_target,Vector2.RIGHT)
	for i:int in range(40): await RenderingServer.frame_post_draw
	b._cancel_action()
	for node:Variant in b._visual_nodes:
		if is_instance_valid(node): node.queue_free()
	b._visual_nodes.clear()
	for node:Variant in b._feedback_nodes:
		if is_instance_valid(node): node.queue_free()
	b._feedback_nodes.clear()
	await process_frame
	var titles := CanvasLayer.new()
	titles.layer = 115
	root.add_child(titles)
	caption(titles,"钻石长矛 · 速度分级穿刺",Vector2(44,25),28)
	caption(titles,"600 速度：四根定点虚影，前快后重",Vector2(44,84),19)
	caption(titles,"800+：本体先穿，虚影逐根沿旧目标位置穿过",Vector2(44,297),19)
	caption(titles,"十字标记为锁定位置；目标下移，虚影不改道",Vector2(44,531),18)
	caption(titles,"真实引擎渲染 · 技能摆放验证（非自动战斗录像）",Vector2(44,567),14)
	var driver := Driver.new()
	driver.low = a
	driver.high = b
	driver.target = eb
	driver.old_target = old_target
	a.Attack()
	check(b._begin_blink(eb),"GPU fixture starts a real upgraded blink")
	root.add_child(driver)
	var snapshot:Image
	var positions:Dictionary = {}
	var last_physics:int = -1
	var moving_subframes:int = 0
	var visible_trails:int = 0
	var aim_ok:bool = true
	var body_before_echo:bool = true
	var screenshot_saved:bool = false
	while driver.clock<0.60:
		await RenderingServer.frame_post_draw
		var physics:int = Engine.get_physics_frames()
		for node:Variant in b._visual_nodes:
			if not is_instance_valid(node) or node.is_queued_for_deletion() or not node.attack_echo: continue
			body_before_echo = body_before_echo and b.total_blinks>0 and b.global_position.x>old_target.x
			aim_ok = aim_ok and node.axis.dot((old_target-node.anchor).normalized())>0.999
			var id:int = node.get_instance_id()
			if physics==last_physics and positions.has(id) and node.elapsed>0.0 and node.elapsed<node.stroke_duration:
				if node.sprite.global_position.distance_to(positions[id])>0.0001: moving_subframes += 1
			positions[id] = node.sprite.global_position
			for trail:Sprite2D in node._trail_sprites:
				if trail.visible and trail.modulate.a>0.03: visible_trails += 1
		if driver.clock>=0.24 and not screenshot_saved:
			snapshot = root.get_texture().get_image()
			screenshot_saved = snapshot.save_jpg("res://.godot/agent_diamond_spear_upgrade.jpg",0.90)==OK
		last_physics = physics
	check(driver.birth_frames.size()==4,"GPU run generates all four upgraded echoes")
	var separate:bool = true
	for i:int in range(1,driver.birth_frames.size()): separate = separate and driver.birth_frames[i]>driver.birth_frames[i-1]
	check(separate and body_before_echo,"actual rendered births occur on separate physics frames after the body crossing")
	check(driver.moved and aim_ok,"actual echoes remain aimed at the old location after the target moves")
	check(moving_subframes>0,"travelling spears interpolate on real render frames between physics updates")
	check(visible_trails>0,"actual GPU frame samples include visible trailing spear silhouettes")
	check(screenshot_saved and snapshot!=null and snapshot.get_size()==Vector2i(960,600),"real GPU visual sample saved successfully")
	check(b._feedback_nodes.size()<=12 and b._visual_nodes.size()<=48,"render effects remain within node budgets")
	print("DIAMOND_UPGRADE_RENDER_METRICS births=",driver.birth_frames," subframe_motion=",moving_subframes," trail_samples=",visible_trails," screenshot=",screenshot_saved)
	driver.queue_free()
	titles.queue_free()
	finish(0 if failures==0 else 1)
