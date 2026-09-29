extends "res://tests/test_heavenfall_arrow_pierce.gd"
# 箭雨将至时的天穹带：画面上缘一条横向星空区域，前沿用欠阻尼弹簧弹性弹出
# （过冲后回弹收定为 1）；收回时整带统一不透明度渐隐，顶部实/向下渐隐的
# 形状全程不变；层级高于落箭；区域不大（高度被钳制）；完全收回后自清理。
# 全程真实 World + 真实帧（不手动步进）。镜头矩阵显式钉死在 zoom=3.2：
# 真实相机的战斗缩放是逐帧收敛的，不同运行会冻结在不同阶段；而这个矩阵下
# 画面上部（取样区）全部是岛外黑色虚空——静止背景，像素 A/B 零环境噪声。
# 落点挪到取样带右侧之外，坠落箭体与烟轨不进入取样区。
# 像素断言用逐行剖面：某行“明显变化的像素数”，方向性由
# “顶部已覆盖 + 前沿之下未触碰”共同证明。

const SCAN_ZOOM: float = 3.2

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
	create_timer(60.0, true, false, true).timeout.connect(func(): finish(2))
	render = DisplayServer.get_name() != "headless"
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world, CONNECT_ONE_SHOT)
	root.add_child(world)
	world.control.hide()
	await create_timer(0.55).timeout
	var arena: Rect2 = world.return_map_world_rect(world.map_group[world.now_choose_map])
	lane_center = arena.get_center()
	var center: Vector2 = lane_center
	world.mouse_offset = Vector2.ZERO
	world.toolbar_zoom_multiplier = 1.0
	world.camera_2d.position_smoothing_enabled = false
	world.process_always(0.0)
	world.camera_2d.global_position = center
	world.camera_2d.force_update_scroll()
	bow = spawn("res://scenes/characters/我的世界/天堂陨落长弓.tscn", center + Vector2(-40, -44))
	bow.state_machine.set_physics_process(false)
	bow.set_physics_process(false)
	await create_timer(0.2).timeout
	bow.set_process(false)
	world.camera_2d.enabled = false
	var canvas_size: Vector2 = root.get_visible_rect().size
	root.canvas_transform = Transform2D(Vector2(SCAN_ZOOM, 0.0), Vector2(0.0, SCAN_ZOOM), Vector2(canvas_size.x * 0.5 - center.x * SCAN_ZOOM, canvas_size.y * 0.5 - center.y * SCAN_ZOOM))
	print("SKY_BAND_ARENA: arena=", arena, " center=", center, " viewport=", root.get_visible_rect())
	await _park_intruders()
	# 顶部 UI（CanvasLayer：顶部文字/FPS 等）永远画在世界之上，且开场黑屏/入场动画
	# 要一两秒才退完：等它稳定，并把世界自己的 CanvasLayer 整层藏掉再取证。
	await create_timer(2.5).timeout
	for layer: CanvasLayer in [world.get_node_or_null("CanvasLayer")] + world.find_children("*", "CanvasLayer", false, false):
		if layer != null:
			layer.visible = false
	check(get_nodes_in_group("HeavenfallSkyBand").is_empty(), "no sky band exists before any rain is inbound")
	var calm: Image = null
	if render:
		calm = await frame()
	# 3 支箭、1.2 秒后陆续落地；落点在取样带（画面横向中段）右侧之外。
	var total: int = 3
	for i in range(total):
		var arrow: Node = load("res://scenes/shooter/我的世界/天陨箭.tscn").instantiate()
		world.add_child(arrow, true)
		arrow.call("configure", bow, bow.Team, center + Vector2(62.0 + float(i) * 6.0, 0.0), 1.2, 0.0, 4.0, i, total)
	var band: Node = null
	for i in range(10):
		await process_frame
		if not get_nodes_in_group("HeavenfallSkyBand").is_empty():
			band = get_nodes_in_group("HeavenfallSkyBand")[0]
			break
	check(band != null, "the sky band appears while rain arrows are inbound")
	if band == null:
		finish(1)
		return
	var heights: Vector2 = Vector2.ZERO
	var visible_size: Vector2 = root.get_visible_rect().size
	var arrow_z: int = int((get_nodes_in_group("HeavenfallRainArrow")[0] as CanvasItem).z_index)
	check(int(band.z_index) == 94 and int(band.z_index) > arrow_z, "the sky band draws above the rain arrows (below ghost/watermark/UI)")
	check(band.get_parent() == world, "the sky band lives in the battle scene as a transient")
	# 渐显方向：显现中期（前沿 25%~60%）画面顶部已是星空，前沿之下仍是原样。
	if render:
		var caught: bool = false
		for i in range(200):
			var reveal: float = band.reveal_extent()
			if reveal >= 0.18 and reveal <= 0.8:
				caught = true
				break
			await process_frame
		check(caught, "fixture: the elastic reveal is observed mid-progress")
		if caught:
			heights = band.get("_band_size")
			var shot: Image = await frame()
			var profile: Array = _row_profile(calm, shot)
			var front: float = band.reveal_extent() * heights.y
			var top_min: int = 1 << 20
			for y in range(1, 7):
				top_min = mini(top_min, profile[y])
			var below_max: int = 0
			for y in range(int((front + 30.0) * 0.5), int((front + 55.0) * 0.5) + 1):
				below_max = maxi(below_max, profile[y])
			check(top_min >= 300, "the starfield shows up at the very top of the screen first")
			check(below_max <= 30, "below the reveal front the sky is still untouched")
			print("SKY_BAND_REVEAL: front=", front, " top_min=", top_min, " below_max=", below_max)
	# 完全显现：弹簧过冲（前沿短暂 >1）后回弹收定为恰好 1，箭仍在途。
	var full: Image = null
	var peak: float = 0.0
	var settled: bool = false
	for i in range(240):
		var reveal: float = band.reveal_extent()
		peak = maxf(peak, reveal)
		if reveal == 1.0 and peak > 1.0:
			settled = true
			break
		await process_frame
	check(settled, "the band pops in elastically and settles at exactly full reveal while the arrows are still falling")
	check(peak > 1.05 and peak < 1.35, "the reveal springs past the rest height before settling (elastic overshoot)")
	print("SKY_BAND_POP: peak=", peak)
	heights = band.get("_band_size")
	check(heights.y >= 56.0 and heights.y <= 140.0 and heights.y <= visible_size.y * 0.2 + 1.0, "the band is a modest strip, never a large area")
	check(heights.x >= visible_size.x, "the band spans the full visible width")
	check(band.get_parent() == world and is_instance_valid(band), "the band holds steady while the rain lasts")
	if render:
		full = await frame()
		var profile: Array = _row_profile(calm, full)
		var top_min: int = 1 << 20
		for y in range(1, 7):
			top_min = mini(top_min, profile[y])
		var outside_max: int = 0
		for y in range(int(heights.y * 0.5) + 8, int(heights.y * 0.5) + 20):
			outside_max = maxi(outside_max, profile[y])
		check(top_min >= 300, "the fully revealed band paints the starfield at the top")
		check(outside_max <= 30, "nothing is painted below the modest strip")
		print("SKY_BAND_FULL: top_min=", top_min, " outside_max=", outside_max)
		# 视差：镜头平移后，带内星空应与地图外棋盘背景同比例地在屏幕上平移。
		var basis: Transform2D = root.canvas_transform
		root.canvas_transform = Transform2D(basis.x, basis.y, basis.origin - Vector2(SCAN_ZOOM * 120.0, 0.0))
		var moved: Image = await frame()
		root.canvas_transform = basis
		await process_frame
		var best_shift: int = _star_shift(full, moved)
		var expected_shift: int = -int(round(SCAN_ZOOM * 0.32 * 120.0 * 0.5))
		var world_shift: int = -int(round(SCAN_ZOOM * 120.0 * 0.5))
		check(absi(best_shift - expected_shift) <= 10, "the band's starfield scrolls at the outside-map background's parallax rate")
		check(absi(best_shift) >= 12 and absi(best_shift - world_shift) >= 15, "the starfield is neither screen-locked nor world-locked")
		print("SKY_BAND_PARALLAX: best=", best_shift, " expected=", expected_shift, " world=", world_shift)
	# 箭雨结束：收回 = 整带统一不透明度渐隐；渐变形状（顶部实、向下渐隐、底缘软边）不变；完全收回后自清理。
	var waited: float = 0.0
	while waited < 6.0 and not get_nodes_in_group("HeavenfallRainArrow").is_empty():
		waited += 0.05
		await create_timer(0.05).timeout
	check(get_nodes_in_group("HeavenfallRainArrow").is_empty(), "fixture: the rain arrows are all gone")
	var fading_seen: bool = false
	for i in range(200):
		if not is_instance_valid(band):
			break
		if band.fade_extent() >= 0.3 and band.fade_extent() <= 0.55:
			fading_seen = true
			break
		await process_frame
	check(fading_seen, "fixture: the fade phase was observed")
	if render and fading_seen and heights.y > 0.0:
		var fading: Image = await frame()
		var profile: Array = _row_profile(calm, fading)
		var top_min: int = 1 << 20
		for y in range(1, 7):
			top_min = mini(top_min, profile[y])
		var outside_max: int = 0
		for y in range(int(heights.y * 0.5) + 8, int(heights.y * 0.5) + 20):
			outside_max = maxi(outside_max, profile[y])
		check(top_min >= 300, "while retracting the top of the band keeps its full shape (uniform fade, not bottom-first clearing)")
		check(outside_max <= 30, "nothing is painted below the modest strip while retracting")
		# 渐变形状不变：收回帧相对完全显现帧的逐行平均差，在“实区”与“渐隐区”
		# 应缩放到同一个比例（= 当前的整带不透明度）。这就是“渐变不变”的直接证明。
		var top_ratios: Array = []
		var mid_ratios: Array = []
		if full != null:
			for y in range(1, 90):
				var row_full: float = _row_mean_delta(calm, full, y)
				var row_fading: float = _row_mean_delta(calm, fading, y)
				if row_full > 0.30:
					top_ratios.append(row_fading / row_full)
				elif row_full > 0.10:
					mid_ratios.append(row_fading / row_full)
		var top_med: float = _median(top_ratios)
		var mid_med: float = _median(mid_ratios)
		check(top_ratios.size() >= 4 and mid_ratios.size() >= 3, "fixture: enough solid and gradient rows were sampled")
		check(top_ratios.size() >= 4 and absf(top_med - mid_med) <= 0.12 and top_med > 0.3 and top_med < 0.75, "retraction fades the whole band uniformly: the gradient shape never changes")
		# 软边仍在：渐隐区行（相对基准的中等平均差）依然存在，不是硬切。
		var ramp_rows: int = 0
		for y in range(0, 90):
			var mean_delta: float = _row_mean_delta(calm, fading, y)
			if mean_delta > 0.03 and mean_delta < 0.25:
				ramp_rows += 1
		check(ramp_rows >= 8, "the soft top-to-bottom gradient is still present while retracting")
		print("SKY_BAND_FADE: top_min=", top_min, " outside_max=", outside_max, " top_med=", top_med, " mid_med=", mid_med, " ramp_rows=", ramp_rows)
	var cleaned: bool = false
	for i in range(200):
		if get_nodes_in_group("HeavenfallSkyBand").is_empty():
			cleaned = true
			break
		await process_frame
	check(cleaned, "the band removes itself once fully faded")
	world.camera_2d.enabled = true
	print("HEAVENFALL SKY BAND RESULT: %d/%d passed" % [checks - failures, checks])
	finish(0 if failures == 0 else 1)


func _row_profile(before: Image, after: Image) -> Array:
	# 画面上半部（canvas 前 182px = 物理行 0..90）逐行统计相对基准明显变化的像素数。
	# 横向取整行（0..宽）：带横贯全宽，UI 遮住的只是局部，整行统计对残余 UI 稳健。
	var profile: Array = []
	if before == null or after == null:
		return profile
	for y in range(0, 91):
		var changed: int = 0
		for x in range(0, after.get_width()):
			if y < 0 or y >= after.get_height():
				continue
			if pixel_delta(before.get_pixel(x, y), after.get_pixel(x, y)) > 0.05:
				changed += 1
		profile.append(changed)
	return profile


func _row_mean_delta(before: Image, after: Image, y: int) -> float:
	# 单行相对基准的平均色差：直接跟随该行 alpha，比计数剖面更能看出渐变坡。
	if before == null or after == null:
		return 0.0
	if y < 0 or y >= after.get_height():
		return 0.0
	var total: float = 0.0
	for x in range(0, after.get_width()):
		total += pixel_delta(before.get_pixel(x, y), after.get_pixel(x, y))
	return total / float(after.get_width())


func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted_vals: Array = values.duplicate()
	sorted_vals.sort()
	return float(sorted_vals[sorted_vals.size() / 2])


func _star_shift(before: Image, after: Image) -> int:
	# 在带内不透明区取几行像素，找让两张截图最吻合的水平位移（物理像素）。
	var rows_before: Array = []
	var rows_after: Array = []
	for y in range(8, 16):
		var line_a: Array = []
		var line_b: Array = []
		for x in range(0, after.get_width()):
			line_a.append(before.get_pixel(x, y))
			line_b.append(after.get_pixel(x, y))
		rows_before.append(line_a)
		rows_after.append(line_b)
	var best: int = 0
	var best_cost: float = -1.0
	for s in range(-110, 21):
		var cost: float = 0.0
		for r in range(rows_before.size()):
			var line_a: Array = rows_before[r]
			var line_b: Array = rows_after[r]
			for x in range(120, 481):
				var a: Color = line_a[x]
				var b: Color = line_b[x + s]
				cost += maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b))
		if best_cost < 0.0 or cost < best_cost:
			best_cost = cost
			best = s
	return best
