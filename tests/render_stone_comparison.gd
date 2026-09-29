extends SceneTree

func _initialize() -> void:
	call_deferred("render")

func render() -> void:
	create_timer(10).timeout.connect(func(): quit(2))
	var vp = SubViewport.new()
	vp.size = Vector2i(400, 240)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var bg = ColorRect.new()
	bg.size = Vector2(400, 240)
	bg.color = Color(0.18, 0.20, 0.24, 1.0)
	vp.add_child(bg)

	# Label for 锻造台
	var label1 = Label.new()
	label1.text = "锻造台 (原版)"
	label1.position = Vector2(60, 40)
	vp.add_child(label1)

	# Label for 石头
	var label2 = Label.new()
	label2.text = "石头 (新增障碍物)"
	label2.position = Vector2(230, 40)
	vp.add_child(label2)

	# Instance 锻造台
	var smithing_packed = load("res://scenes/terrain/我的世界/锻造台.tscn")
	var smithing = smithing_packed.instantiate()
	smithing.position = Vector2(110, 140)
	vp.add_child(smithing)

	# Instance 石头
	var stone_packed = load("res://scenes/characters/默认/石头.tscn")
	var stone = stone_packed.instantiate()
	stone.position = Vector2(290, 140)
	stone.process_mode = Node.PROCESS_MODE_DISABLED
	vp.add_child(stone)

	await process_frame
	await process_frame

	var img = vp.get_texture().get_image()
	img.save_png("render_stone_comparison.png")
	print("Saved render_stone_comparison.png")
	quit(0)
