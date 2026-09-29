extends "res://tests/test_heavenfall_actor_refraction.gd"
# 取证用：真实窗口、真实默认视角下拍摄本次改动的两处视觉证据。
# 1) 箭穿过障碍物时沿途生长的空间裂隙 + 从穿入点向穿出点的拉链式闭合（12 帧）。
# 2) 缩小到 0.8 倍（半径 38）的到达圆圈 + 每 0.09 秒一跳时的扩张（4 帧）。
var bow: Node2D
const COLS: int = 4
const HALF: bool = true # 每帧缩小一半，便于一次取回。


func grab(rect: Rect2i) -> Image:
	await RenderingServer.frame_post_draw
	var shot: Image = root.get_texture().get_image()
	var region: Rect2i = rect.intersection(Rect2i(Vector2i.ZERO, shot.get_size()))
	var crop: Image = shot.get_region(region)
	if HALF:
		crop.resize(maxi(crop.get_width() / 2, 1), maxi(crop.get_height() / 2, 1), Image.INTERPOLATE_BILINEAR)
	crop.convert(Image.FORMAT_RGBA8)
	return crop


func sheet(frames: Array[Image], path: String) -> void:
	if frames.is_empty():
		print("CAPTURE_EMPTY: ", path)
		return
	var fw: int = frames[0].get_width()
	var fh: int = frames[0].get_height()
	var rows: int = int(ceil(float(frames.size()) / float(COLS)))
	var out: Image = Image.create(COLS * fw, rows * fh, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 1))
	for i in range(frames.size()):
		out.blit_rect(frames[i], Rect2i(Vector2i.ZERO, Vector2i(fw, fh)), Vector2i(i % COLS, i / COLS) * Vector2i(fw, fh))
	var err: int = out.save_png(path)
	print("CAPTURE_SAVED: ", path, " frames=", frames.size(), " tile=", Vector2i(fw, fh), " err=", err)


func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Camera_Move = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0, true)
	create_timer(180.0, true, false, true).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world, CONNECT_ONE_SHOT)
	root.add_child(world)
	world.control.hide()
	await create_timer(0.55).timeout
	var arena: Rect2 = world.return_map_world_rect(world.map_group[world.now_choose_map])
	var center: Vector2 = arena.get_center()
	world.mouse_offset = Vector2.ZERO
	world.toolbar_zoom_multiplier = 1.0
	world.camera_2d.position_smoothing_enabled = false
	world.process_always(0.0)
	world.camera_2d.global_position = center
	world.camera_2d.force_update_scroll()
	await create_timer(0.25).timeout
	var actual_canvas: Transform2D = root.canvas_transform
	world.camera_2d.enabled = false
	root.canvas_transform = actual_canvas
	bow = spawn("res://scenes/characters/我的世界/天堂陨落长弓.tscn", center + Vector2(-40, -44))
	bow.state_machine.set_physics_process(false)
	bow.set_physics_process(false)
	await create_timer(0.2).timeout
	bow.set_process(false)
	await _capture_pierce(center)
	# 再拍一组三倍放大、只框住穿越段的近景，方便看清裂隙是怎么长出来的。
	var zoomed: Transform2D = Transform2D(actual_canvas.get_rotation(), actual_canvas.get_scale() * 3.0, actual_canvas.get_skew(), Vector2.ZERO)
	var image_center: Vector2 = root.get_stretch_transform() * (root.get_visible_rect().size * 0.5)
	zoomed.origin = image_center - zoomed.basis_xform(center + Vector2(-8, -20))
	root.canvas_transform = zoomed
	await _capture_pierce(center, "user://heavenfall_rev8_pierce_zoom.png", 62.0)
	root.canvas_transform = actual_canvas
	await _capture_circle(center)
	print("HEAVENFALL REV8 CAPTURE DONE")
	finish(0)


func _screen_point(world_point: Vector2) -> Vector2:
	return root.get_stretch_transform() * root.canvas_transform * world_point


func _screen_rect(a: Vector2, b: Vector2, pad: float) -> Rect2i:
	var from: Vector2 = _screen_point(a)
	var to: Vector2 = _screen_point(b)
	var rect := Rect2(from, Vector2.ZERO).expand(to).grow(pad)
	return Rect2i(rect.position.floor(), rect.size.ceil())


func _capture_pierce(center: Vector2, path: String = "user://heavenfall_rev8_pierce.png", span: float = 160.0) -> void:
	var start: Vector2 = center + Vector2(-56, -20)
	var wall: StaticBody2D = _mk_wall(start + Vector2(48, 0))
	await physics_frame
	var bolt: Node = load("res://scenes/shooter/我的世界/天陨箭矢.tscn").instantiate()
	world.add_child(bolt, true)
	bolt.set_physics_process(false)
	bolt.global_position = start
	bolt.call("configure", bow, bow.Team, Vector2.RIGHT, 620.0, 10.0, 30.0, 0.0, 0.0, 5000.0, 3, 60.0, 4.0, 22.0, 0.38)
	var focus: Vector2 = start + Vector2(48.0, 0.0)
	var region: Rect2i = _screen_rect(focus - Vector2(span * 0.5, span * 0.45), focus + Vector2(span * 0.5, span * 0.45), 12.0)
	var frames: Array[Image] = []
	var tear: Node2D = null
	for i in range(60):
		bolt._physics_process(1.0 / 60.0)
		if tear == null and _tears().size() > 0:
			tear = _tears()[0]
			tear.set_process(false)
		if tear != null:
			tear._process(1.0 / 60.0)
			frames.append(await grab(region))
		if bolt.has_pierced() and not bolt.is_inside_obstacle():
			break
	# 出墙之后再拍 4 帧：推进裂隙自己的时钟，展示“先开的先闭合”。
	for k in range(4):
		for j in range(4):
			tear._process(1.0 / 60.0)
		frames.append(await grab(region))
	sheet(frames, path)
	bolt.queue_free()
	wall.queue_free()
	await physics_frame


func _capture_circle(center: Vector2) -> void:
	var ring: Node2D = load("res://scripts/characters/我的世界/new6/heavenfall_ring.gd").new()
	world.add_child(ring)
	ring.set_process(false)
	ring.call("configure", center, 38.0, center, 0.0, 77)
	var extent: float = 38.0 * 1.58 + 10.0
	var region: Rect2i = _screen_rect(center - Vector2(extent, extent), center + Vector2(extent, extent), 8.0)
	var frames: Array[Image] = []
	frames.append(await grab(region))
	for k in range(3):
		for j in range(8):
			ring._process(1.0 / 60.0)
		frames.append(await grab(region))
	sheet(frames, "user://heavenfall_rev8_circle.png")
	ring.queue_free()
	await physics_frame
