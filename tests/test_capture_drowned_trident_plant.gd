extends "res://tests/test_drowned_trident_aim_stick.gd"
# 取证用：真实窗口 + 真实默认视角，拍“溺尸投戟没打到就插在地上”的画面。
# 1) 出手当帧瞄准敌人当前坐标并直飞（含飞行中段）。
# 2) 没打中就插在落点地面：斜插姿态 + 土堆。
# 3) 插地后照常附魔，周期引雷落在戟身上（戟不动、效果跟着戟）。
# 输出 user://drowned_trident_plant_sheet.png（近景序列）与 user://drowned_trident_plant_wide.png（默认视角）。
const COLS: int = 3
const ZOOM: float = 12.0
var TRIDENT: Script
var shots: Array[Image] = []
var shot_size: Vector2i


func grab(rect: Rect2i) -> Image:
	await RenderingServer.frame_post_draw
	var shot: Image = root.get_texture().get_image()
	var region: Rect2i = rect.intersection(Rect2i(Vector2i.ZERO, shot.get_size()))
	var crop: Image = shot.get_region(region)
	crop.convert(Image.FORMAT_RGBA8)
	return crop


func wide(path: String) -> void:
	await RenderingServer.frame_post_draw
	var shot: Image = root.get_texture().get_image()
	shot.convert(Image.FORMAT_RGBA8)
	var err: int = shot.save_png(path)
	print("CAPTURE_WIDE_SAVED: ", path, " size=", shot.get_size(), " err=", err)


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


func center_rect(width: int, height: int) -> Rect2i:
	return Rect2i(Vector2i(shot_size.x / 2 - width / 2, shot_size.y / 2 - height / 2), Vector2i(width, height))


func frame_camera(focus: Vector2, zoom: float) -> void:
	# 世界自己每帧重算镜头（_apply_camera_zoom + 只看地图中心+中键平移），
	# 所以取证时改成驱动世界自己的两个旋钮，而不是直接写 Camera2D。
	world.toolbar_zoom_multiplier = zoom
	world.mouse_offset = focus - center
	world.process_always(0.0)
	print("CAPTURE_ZOOM: multiplier=", zoom, " effective=", world.get_effective_camera_zoom())


func shoot() -> Image:
	await process_frame
	await process_frame
	return await grab(center_rect(320, 300))


func run() -> void:
	TRIDENT = load("res://scripts/effects/我的世界/三叉戟.gd")
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Camera_Move = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0, true)
	create_timer(200.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world, CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.6).timeout
	if not await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self):
		finish(1)
		return
	arena = world.return_map_world_rect(world.map_group["Map50x50"])
	center = arena.get_center()
	world.mouse_offset = Vector2.ZERO
	world.toolbar_zoom_multiplier = 1.0
	world.camera_2d.position_smoothing_enabled = false
	world.process_always(0.0)
	frame_camera(center, 1.0)
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	shot_size = root.get_texture().get_image().get_size()

	var drowned: Node2D = spawn("res://scenes/characters/我的世界/溺尸.tscn", center + Vector2(-330, 0))
	var target: Node2D = dummy(center + Vector2(-30, -40))
	await process_frame
	await process_frame
	drowned.mc_native_animation.set_process(false)
	drowned.set_physics_process(false)
	drowned.set_process(false)
	drowned.state_machine.set_physics_process(false)
	drowned._trident.set_physics_process(true)
	drowned._trident.set_process(true)
	print("CAPTURE_SETUP: center=", center, " drowned=", drowned.global_position, " target=", target.global_position, " window=", shot_size, " cam_zoom=", world.camera_2d.zoom)

	# --- 0) 默认视角全景：溺尸持戟站在场上 -----------------------------------------
	frame_camera(center, 1.0)
	await wide("user://drowned_trident_plant_wide.png")

	# --- 1) 近景：手上握着戟 / 蓄力（出手当帧才读取敌人当前坐标） -------------------
	frame_camera(drowned.global_position + Vector2(24, -8), ZOOM)
	shots.append(await shoot())
	check(drowned.throw_trident(target), "capture throw starts")
	drowned._advance_trident_throw(drowned.trident_throw_windup * 0.55)
	shots.append(await shoot())

	# --- 2) 出手后目标离开弹道 → 打空 → 插在“出手当帧锁定的坐标”地面上 ------------------
	target.global_position = center + Vector2(-60, -190) # 蓄力途中走位
	var release_aim: Vector2 = target.global_position
	drowned._advance_trident_throw(drowned.trident_throw_windup + 0.001)
	var spear: Node = drowned._trident
	print("CAPTURE_RELEASE: aim=", release_aim, " fired_at=", drowned.trident_last_aim_point(), " axis=", spear.axis, " origin=", spear.global_position)
	target.global_position = center + Vector2(390, 330) # 出手后立刻离开弹道 → 必然打空
	for i in range(4):
		frame_camera(spear.global_position + spear.axis * 60.0, ZOOM)
		await physics_frame
		shots.append(await shoot())
	var guard: int = 0
	while spear.flight_state == 1 and guard < 600:
		guard += 1
		await physics_frame
	var contact: Vector2 = spear.plant_contact_point()
	print("CAPTURE_LOCKED: aim=", release_aim, " endpoint=", spear.aim_point, " length=", spear.flight_length)
	print("CAPTURE_PLANT: planted=", spear.planted, " state=", spear.flight_state, " at=", spear.global_position, " contact=", contact, " rotation=", spear.rotation, " traveled=", spear.traveled, " axis=", spear.axis, " frames=", guard)
	for i in range(5):
		frame_camera(contact + Vector2(3, -5), ZOOM)
		await physics_frame
		shots.append(await shoot())
	frame_camera(contact, 1.0)
	await wide("user://drowned_trident_plant_wide_after.png")

	# --- 3) 插地后照常附魔（12 秒后附魔，效果贴着插地姿态） -------------------------
	spear.advance(drowned.stuck_enchant_delay + 0.05)
	print("CAPTURE_ENCHANT: charged=", spear.charged, " charge_visual=", spear.charge_visual.visible, " pose=", spear.charge_visual.global_position, " trident=", spear.global_position)
	frame_camera(contact + Vector2(3, -5), ZOOM)
	for i in range(3):
		await physics_frame
		shots.append(await shoot())

	# --- 4) 周期引雷打在插地戟身上 ---------------------------------------------------
	drowned.summon_trident_lightning(spear, false)
	var effect: Node = null
	for child: Node in spear.get_children():
		if child.name == "TridentLightning": effect = child
	if effect == null:
		print("CAPTURE_LIGHTNING: missing effect")
	else:
		effect.set_process(false)
		effect.set_physics_process(false)
		print("CAPTURE_LIGHTNING: at=", (effect as Node2D).global_position)
		for i in range(4):
			for j in range(5):
				effect._process(1.0 / 60.0)
			shots.append(await shoot())

	sheet(shots, "user://drowned_trident_plant_sheet.png")
	await process_frame
	print("DROWNED TRIDENT PLANT CAPTURE DONE failures=", failures, " checks=", checks)
	finish(0)
