extends "res://tests/test_diamond_spear_live.gd"
## Arranged GPU action samples, not a substitute for the autonomous live test.
func label_at(layer:CanvasLayer,text:String,point:Vector2,size:int=20) -> void:
	var label := Label.new()
	label.text = text
	label.position = point
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",Color(0.85,0.99,1.0))
	label.add_theme_color_override("font_shadow_color",Color(0.0,0.03,0.05))
	label.add_theme_constant_override("shadow_offset_x",2)
	label.add_theme_constant_override("shadow_offset_y",2)
	layer.add_child(label)
func run() -> void:
	root.size = Vector2i(1100,760)
	root.content_scale_size = root.size
	var center:Vector2 = await setup()
	for layer:Node in world.find_children("*","CanvasLayer",true,false): layer.visible = false
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.position = center
	camera.zoom = Vector2(3.3,3.3)
	camera.make_current()
	var a:Node2D = spawn(center+Vector2(-70,-65))
	var ea:Node2D = victim(a.global_position+Vector2(24,0))
	var b:Node2D = spawn(center+Vector2(75,-65))
	var eb:Node2D = victim(b.global_position+Vector2(0,15))
	var c:Node2D = spawn(center+Vector2(-112,62))
	var ec:Node2D = victim(c.global_position+Vector2(125,0))
	for unit:Node2D in [a,b,c,ea,eb,ec]:
		unit.state_machine.set_physics_process(false)
		unit.health_bar.hide()
	for unit:Node2D in [ea,eb,ec]:
		unit.image.modulate = Color(0.65,0.72,0.78,0.75)
	a._momentum = 420.0
	a._attack_wait = 0.0
	a.Attack()
	a._elapsed = 0.06
	a._visual_shift = a.thrust_offset_at(0.06,0.38)
	for fx:Node2D in a._visual_nodes:
		if fx.attack_echo: fx._physics_process(0.06)
	a._apply_pose()
	b._sweep_wait = 0.0
	b._begin_sweep(eb)
	for i:int in range(7): b._tick_action(b.sweep_duration/9.0)
	b._apply_pose()
	c._blink_wait = 0.0
	c._begin_blink(ec)
	c._tick_action(c.blink_windup)
	c._tick_action(0.10)
	c._apply_pose()
	for unit:Node2D in [a,b,c]:
		for fx:Node2D in unit._visual_nodes: fx.set_physics_process(false)
	game.now_stop_state = true
	var titles := CanvasLayer.new()
	titles.layer = 115
	root.add_child(titles)
	label_at(titles,"钻石长矛  /  DIAMOND SPEAR",Vector2(55,35),32)
	label_at(titles,"原版素材 · 普通移动 · 定点虚影 · 半周旋扫 · 闪白瞬移",Vector2(57,82),19)
	label_at(titles,"01  快速前刺 + 偏移瞄准虚影",Vector2(110,253),20)
	label_at(titles,"02  旋扫放大再缩回，不损失移速",Vector2(610,253),20)
	label_at(titles,"03  前方正负25度瞬移穿刺，落点弹性回拉",Vector2(185,645),23)
	label_at(titles,"Mojang 原版 1.21.11 手持贴图 · 技能摆放预览",Vector2(315,704),16)
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var snapshot:Image = root.get_texture().get_image()
	var error:Error = snapshot.save_png("res://tests/diamond_spear_preview.png")
	print("DIAMOND_GPU_PREVIEW saved=",error==OK," size=",snapshot.get_size())
	finish(0 if error==OK else 1)
