extends "res://tests/test_mc_snow_golem.gd"
## Arranged visual demonstration, sampled from the real 1.4-second status timeline.
var caption:Label
func text_line(text:String,pos:Vector2,width:float,size:int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size.x = width
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",Color.WHITE)
	label.add_theme_color_override("font_shadow_color",Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x",2)
	label.add_theme_constant_override("shadow_offset_y",2)
	root.get_node("IceCaptions").add_child(label)
	return label
func run() -> void:
	root.size = Vector2i(960,640)
	root.content_scale_size = Vector2i(960,640)
	var center:Vector2 = await setup_world()
	for ui:Node in world.find_children("*","CanvasLayer",true,false): ui.visible = false
	world.versus_label.hide()
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.global_position = center
	camera.zoom = Vector2(5,5)
	camera.make_current()
	var layer := CanvasLayer.new()
	layer.name = "IceCaptions"
	layer.layer = 115
	root.add_child(layer)
	text_line("原版冰包裹 / 冻结挣脱",Vector2(90,28),780,28)
	text_line("原版冰与破坏贴图 · 只抖动视觉，不移动碰撞体",Vector2(60,76),840,18)
	caption = text_line("冻结前",Vector2(160,128),640,20)
	text_line("普通雪傀儡",Vector2(50,460),260,20)
	text_line("苦力怕",Vector2(350,460),260,20)
	text_line("普通受害者",Vector2(650,460),260,20)
	text_line("实际冻结时长 1.4 秒：轻颤 → 逐渐剧烈 → 碎冰脱出",Vector2(50,566),860,19)
	var source:Node2D = spawn(GOLEM_PATH,center+Vector2(384,240),"Team0")
	source._field.set_physics_process(false)
	var units:Array[Node2D] = [spawn(GOLEM_PATH,center+Vector2(-60,0),"Team1"),spawn("res://scenes/characters/我的世界/苦力怕.tscn",center,"Team1"),dummy(center+Vector2(60,0),"Team1")]
	var cold_nodes:Array[Node2D] = []
	var physical_positions:Array[Vector2] = []
	for unit:Node2D in units:
		unit.health_bar.hide()
		unit.Can_Attack = false
		unit.Can_Skill = false
		unit.direction = Vector2.LEFT
		if unit.has_method("visual_mob"): unit.visual_mob()
		physical_positions.append(unit.global_position)
		cold_nodes.append(COLD.ensure(unit))
	var folder:String = "res://tests/snow_ice_frames"
	DirAccess.make_dir_recursive_absolute(folder)
	var enclosed_seen:bool = false
	var cracks_seen:bool = false
	var ended:bool = false
	var moved_physics:bool = false
	var shader_shake_seen:bool = false
	var saved_frames:int = 0
	for index:int in range(84):
		if index == 8:
			for cold:Node2D in cold_nodes: cold.add_cold(100.0,1.4)
		var remaining:float = cold_nodes[1].frozen_left
		if remaining > 0.0:
			caption.text = "冻结剩余 %.2f 秒"%remaining
			enclosed_seen = enclosed_seen or cold_nodes[1]._ice.enclosed
			cracks_seen = cracks_seen or cold_nodes[1]._ice.crack_stage() == 9
			shader_shake_seen = shader_shake_seen or (cold_nodes[1]._ice._mode == 1 and cold_nodes[1]._ice.shake_world.length() > 0.8)
			for i:int in range(units.size()): moved_physics = moved_physics or not units[i].global_position.is_equal_approx(physical_positions[i])
		elif index >= 8:
			caption.text = "解冻 · 冰壳碎开，角色恢复"
			ended = true
		for cold:Node2D in cold_nodes:
			if is_instance_valid(cold._ice) and cold._ice.enclosed: cold._ice.refresh()
		await process_frame
		await RenderingServer.frame_post_draw
		if index%2 == 0:
			var image:Image = root.get_texture().get_image()
			image.save_png(folder+"/frame_%03d.png"%saved_frames)
			saved_frames += 1
			if index == 12: image.save_png("res://tests/snow_ice_early.png")
			if index == 44: image.save_png("res://tests/snow_ice_late.png")
			if index == 52: image.save_png("res://tests/snow_ice_breakout.png")
			if index == 80: image.save_png("res://tests/snow_ice_released.png")
	check(enclosed_seen and cracks_seen,"actual GPU timeline displays native ice and terminal cracking")
	check(shader_shake_seen and not moved_physics,"actual GPU freeze has shader tremor but no physical-position motion")
	check(ended and cold_nodes[1].frozen_left == 0.0 and not cold_nodes[1]._ice.enclosed,"real status timer releases the enclosure without manual thaw callbacks")
	check(cold_nodes[1]._ice.fragments.is_empty() and not cold_nodes[1]._ice.visible,"ice shards disappear completely after escape")
	print("SNOW_ICE_GPU frames=",saved_frames," checks=",checks," failures=",failures)
	finish(0 if failures == 0 else 1)
