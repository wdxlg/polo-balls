extends "res://tests/test_heavenfall_actor_refraction.gd"
# 普通箭外观、穿过一次障碍物（沿途裂隙、先开先闭合）、地图墙外飞后出屏消失，
# 以及到达圆圈的 5 跳固定伤害与微小向外击退。全部在真实 World + 真实窗口下检查。
# 默认地图只有 160×160，所以所有坐标都从真实地图矩形内部取，并先清走会闯入弹道的单位。
var bow: Node2D
var render: bool = false
var lane_center: Vector2 = Vector2.ZERO
var FX_SCRIPT: Script
var DEBRIS_FX_SCRIPT: Script


func frame() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func screen_point(world_point: Vector2) -> Vector2:
	return root.get_stretch_transform() * root.canvas_transform * world_point


func _world_rect_image(img: Image, world_a: Vector2, world_b: Vector2) -> Rect2i:
	var sa: Vector2 = screen_point(world_a)
	var sb: Vector2 = screen_point(world_b)
	var pos: Vector2i = Vector2i(Vector2(minf(sa.x, sb.x), minf(sa.y, sb.y)).floor())
	var endp: Vector2i = Vector2i(Vector2(maxf(sa.x, sb.x), maxf(sa.y, sb.y)).ceil())
	return Rect2i(pos, endp - pos)


func _mk_dummy(point: Vector2) -> Node2D:
	var dummy: Node2D = _mk_enemy(point)
	dummy.Speed = 0.0
	dummy.default_properties.Speed = 0.0
	dummy.Can_Attack = false
	dummy.Can_Skill = false
	dummy.direction = Vector2.ZERO
	dummy.state_machine.set_physics_process(true)
	return dummy


func _park_intruders(keep: Array = []) -> void:
	# 世界自己会刷出单位；把挡在弹道附近的单位挪走，避免它们吃掉测试用的箭。
	var moved: int = 0
	for other: Node in get_nodes_in_group("Ball"):
		if other == bow or keep.has(other):
			continue
		var body: Node2D = other as Node2D
		if body == null:
			continue
		if body.global_position.distance_to(lane_center) > 400.0:
			continue
		body.global_position = Vector2(-3000, -3000)
		moved += 1
	if moved > 0:
		await physics_frame


func _spawn_bolt(start: Vector2, rain_count: int = 3) -> Node:
	var bolt: Node = load("res://scenes/shooter/我的世界/天陨箭矢.tscn").instantiate()
	world.add_child(bolt, true)
	bolt.set_physics_process(false)
	bolt.global_position = start
	bolt.call("configure", bow, bow.Team, Vector2.RIGHT, 620.0, 10.0, 30.0, 0.0, 0.0, 5000.0, rain_count, 60.0, 4.0, 22.0, 0.38)
	return bolt


func run() -> void:
	# Defer autoload-dependent scripts until Game is initialized by --script.
	FX_SCRIPT = load("res://scripts/characters/我的世界/new6/fx_burst.gd")
	DEBRIS_FX_SCRIPT = load("res://scripts/characters/我的世界/new6/heavenfall_arrow_debris.gd")
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
	# 普通默认视角：不换相机、不放大，只固定真实镜头矩阵用于 A/B。
	var actual_canvas: Transform2D = root.canvas_transform
	world.camera_2d.enabled = false
	root.canvas_transform = actual_canvas
	print("PIERCE_ARENA: arena=", arena, " center=", center, " viewport=", root.get_visible_rect())
	await _park_intruders()
	check_arrow_skin()
	await check_pierce(center)
	await check_second_obstacle(center)
	await check_rain_physics(center, arena)
	await check_map_wall(arena, center)
	await check_circle_ticks(center)
	check_bow_recoil()
	world.camera_2d.enabled = true
	print("HEAVENFALL ARROW RESULT: %d/%d passed" % [checks - failures, checks])
	finish(0 if failures == 0 else 1)


func _alpha_bytes(img: Image) -> PackedByteArray:
	# 只取 alpha 通道字节（统一转 RGBA8 后每 4 字节取第 4 个）。
	if img == null:
		return PackedByteArray()
	img.convert(Image.FORMAT_RGBA8)
	var raw: PackedByteArray = img.get_data()
	var out := PackedByteArray()
	out.resize(raw.size() / 4)
	for i in range(out.size()):
		out[i] = raw[i * 4 + 3]
	return out


func check_arrow_skin() -> void:
	var white: Texture2D = load("res://Images/characters/我的世界/new6/天陨箭_纯白.png")
	var glow_tex: Texture2D = load("res://Images/characters/我的世界/new6/天陨箭_光晕.png")
	var normal_alpha: PackedByteArray = _alpha_bytes(load("res://Images/characters/我的世界/骷髅/箭.png").get_image())
	for path: String in ["res://scenes/shooter/我的世界/天陨箭矢.tscn", "res://scenes/shooter/我的世界/天陨箭.tscn"]:
		var arrow: Node = load(path).instantiate()
		world.add_child(arrow)
		arrow.set_physics_process(false)
		var sprite: Sprite2D = arrow.get_node("Sprite2D")
		var glow: Sprite2D = arrow.get_node_or_null("Glow") as Sprite2D
		check(sprite.texture == white, path.get_file() + " uses the pure-white arrow sprite")
		check(_alpha_bytes(sprite.texture.get_image()) == normal_alpha, path.get_file() + " keeps the ordinary arrow's exact silhouette")
		var correct_glow: bool = false
		if glow != null and glow.texture == glow_tex:
			if path.ends_with("天陨箭.tscn"):
				correct_glow = glow.material is ShaderMaterial and (glow.material as ShaderMaterial).shader.resource_path == "res://shaders/heavenfall_arrow_clip_add.gdshader"
			else:
				correct_glow = glow.material is CanvasItemMaterial and (glow.material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_ADD
		check(correct_glow, path.get_file() + " carries additive glow; only burrowing rain requires ground clipping")
		check(sprite.scale.is_equal_approx(Vector2(0.016, 0.016)) and is_equal_approx(sprite.rotation, PI * 0.25), path.get_file() + " keeps the normal arrow's size and tilt")
		arrow.queue_free()


func check_pierce(center: Vector2) -> void:
	var start: Vector2 = center + Vector2(-50, -20)
	var wall: StaticBody2D = _mk_wall(start + Vector2(36, 0))
	await physics_frame
	await _park_intruders()
	var bolt: Node = _spawn_bolt(start)
	var heading: Vector2 = bolt._dir
	var tear: Node2D = null
	var inside_samples: Array[int] = []
	for i in range(40):
		bolt._physics_process(1.0 / 60.0)
		if bolt.is_inside_obstacle():
			if tear == null and _tears().size() > 0:
				tear = _tears()[0]
				tear.set_process(false) # 测试自己推进裂隙时钟
			if tear != null:
				tear._process(1.0 / 60.0)
				inside_samples.append(tear.sample_count())
		if bolt.has_pierced() and not bolt.is_inside_obstacle():
			break
	check(inside_samples.size() >= 2, "the rift exists while the arrow is still inside the obstacle")
	check(inside_samples.size() >= 2 and inside_samples[inside_samples.size() - 1] > inside_samples[0], "every frame inside keeps extending the rift along the actual path")
	check(bolt.has_pierced() and not bolt.is_inside_obstacle() and bolt.global_position.x > wall.global_position.x + 15.0, "the arrow comes out on the far side of the wall")
	check(bolt._dir.is_equal_approx(heading) and not bolt.is_queued_for_deletion(), "the old bounce is gone: the heading never changes")
	check(_tears().size() == 1, "a passing arrow leaves exactly one tear behind")
	var path_ok: bool = true
	var covering: bool = false
	for local: Vector2 in tear._points:
		var point: Vector2 = tear.global_position + local
		path_ok = path_ok and absf(point.y - start.y) <= 3.0
		covering = covering or point.x > wall.global_position.x
	check(path_ok and covering and tear.sample_count() >= 12, "the rift follows the real crossed path instead of a decorative line")
	check(tear._open_at[0] < tear._open_at[tear.sample_count() - 1] and tear.close_start(0) < tear.close_start(tear.sample_count() - 1), "samples open in crossing order, so the first-opened part closes first")
	check(tear.is_finished(), "the rift stops growing once the arrow is out")
	if render:
		await check_tear_closing_order(tear)
	# 像素探针会把 _age 直接拨到收口中段；回到最后一段出生时刻，再量完整寿命。
	tear._age = tear._open_at[tear.sample_count() - 1]
	# 撕开 ~0.1s、保持、再较慢收口：寿命比旧版长，但仍有明确上限。
	var lifetime: float = 0.0
	for i in range(150):
		tear._process(1.0 / 60.0)
		lifetime += 1.0 / 60.0
		if tear.is_queued_for_deletion():
			break
	check(tear.is_queued_for_deletion(), "the tear finishes its slower closing instead of lingering on the map")
	check(lifetime > 0.45, "closing is slow enough to be watched")
	check(lifetime < 1.6, "the tear still disappears instead of lingering forever")
	bolt.queue_free()
	wall.queue_free()
	await physics_frame


func check_tear_closing_order(tear: Node2D) -> void:
	# 每一段各自张开后闭合，越早开的越早进入闭合：所以随时间推移，剩下的亮度重心
	# 会从穿入点向穿出点移动。用加权重心来量，避免“快闭合但还没完全消失”被误判。
	var entry: Vector2 = tear.global_position + tear._points[0]
	var exit: Vector2 = tear.global_position + tear._points[tear.sample_count() - 1]
	print("TEAR_OPEN_AT: first=", tear._open_at[0], " last=", tear._open_at[tear.sample_count() - 1], " count=", tear.sample_count(), " age=", tear._age)
	var early: Vector2 = await tear_pixels(tear, entry, exit)
	tear._age = tear.OPEN_RAMP + tear.HOLD_TIME + tear.CLOSE_TIME * 0.55
	tear._process(0.0)
	var late: Vector2 = await tear_pixels(tear, entry, exit)
	check(early.x > 20.0, "the young rift is really rendered in the actual window")
	check(late.x > 0.0, "the far end of the rift is still visible after the near part closed")
	check(late.y > early.y + 0.05, "the entry side closes first: the remaining rift sits further along the path")
	print("TEAR_PIXELS: early=", early, " late=", late)


func tear_pixels(tear: Node2D, entry: Vector2, exit: Vector2) -> Vector2:
	# 隐藏／显示同一帧求差，只测量这道裂隙实际画出来的像素；
	# 返回 (变化像素数, 以变化强度加权的横向重心 0~1)。
	tear.hide()
	var without: Image = await frame()
	tear.show()
	var with_tear: Image = await frame()
	var from: Vector2 = screen_point(entry)
	var to: Vector2 = screen_point(exit)
	var axis: Vector2 = to - from
	var length_squared: float = maxf(axis.length_squared(), 0.0001)
	var count: int = 0
	var weight_sum: float = 0.0
	var weighted: float = 0.0
	var bounds: Rect2i = Rect2i(Vector2i(from.min(to).floor() - Vector2.ONE * 24.0), Vector2i(axis.abs().ceil() + Vector2.ONE * 48.0)).intersection(Rect2i(Vector2i.ZERO, with_tear.get_size()))
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var delta: float = colour_delta(without.get_pixel(x, y), with_tear.get_pixel(x, y))
			if delta <= 0.02:
				continue
			count += 1
			weight_sum += delta
			weighted += delta * clampf((Vector2(x, y) - from).dot(axis) / length_squared, 0.0, 1.0)
	var centroid: float = weighted / weight_sum if weight_sum > 0.0001 else 0.0
	return Vector2(count, centroid)


func check_second_obstacle(center: Vector2) -> void:
	var start: Vector2 = center + Vector2(-60, 28)
	var wall_a: StaticBody2D = _mk_wall(start + Vector2(34, 0))
	var wall_b: StaticBody2D = _mk_wall(start + Vector2(96, 0))
	await physics_frame
	await _park_intruders()
	var rain_before: int = _falls().size()
	var rifts_before: int = _rifts().size()
	var bolt: Node = _spawn_bolt(start)
	var pierced: bool = false
	for i in range(60):
		bolt._physics_process(1.0 / 60.0)
		pierced = pierced or bolt.has_pierced()
		if bolt.is_queued_for_deletion():
			break
	check(pierced, "the first wall is pierced once")
	check(bolt.is_queued_for_deletion(), "the second obstacle still stops the arrow")
	check(_falls().size() == rain_before + 3, "a stopped arrow still summons its rain")
	check(_rifts().size() == rifts_before + 1, "a stopped arrow still tears its rift")
	for fall: Node in _falls():
		fall.queue_free()
	for rift: Node in _rifts():
		rift.queue_free()
	for tear: Node in _tears():
		tear.queue_free()
	wall_a.queue_free()
	wall_b.queue_free()
	await physics_frame


func check_rain_physics(center: Vector2, arena: Rect2) -> void:
	# 箭雨：在一段时间内陆续落地（不是一齐砸下）、真实受重力加速（速度积分），
	# 落地时在落点从中心撕开网状小裂纹，箭钻进去消失，裂纹随后慢慢闭合。
	for node: Node in _bolts() + _falls() + _rifts() + _tears() + get_nodes_in_group("HeavenfallRainCrack"):
		node.queue_free()
	await physics_frame
	await _park_intruders()
	var base: Vector2 = center + Vector2(-24.0, -16.0)
	var total: int = 3
	var arrows: Array[Node] = []
	var points: Array[Vector2] = []
	for i in range(total):
		var point: Vector2 = base + Vector2(float(i) * 10.0, 0.0)
		var arrow: Node = load("res://scenes/shooter/我的世界/天陨箭.tscn").instantiate()
		world.add_child(arrow, true)
		arrow.set_physics_process(false)
		arrow.call("configure", bow, bow.Team, point, 0.38, 0.0, 4.0, i, total)
		arrows.append(arrow)
		points.append(point)
	var land_step: Array[int] = [-1, -1, -1]
	var dys: Array[float] = []
	var vys: Array[float] = []
	var last_y: float = (arrows[0] as Node2D).global_position.y
	var crack0: Node = null
	var crack_found: bool = false
	var burrow_alive: bool = false
	var burrow_y: float = -999.0
	var burrow_gone: bool = false
	var screen_top: float = (root.get_canvas_transform().affine_inverse() * Vector2.ZERO).y
	check(int((arrows[0] as CanvasItem).z_index) == 91, "rain arrows draw above the outside-map mask (z=90) instead of being cut")
	check((arrows[0] as Node2D).global_position.y < screen_top - 8.0, "rain arrows enter from outside the top of the visible screen")
	# 天穹带：箭雨在途时存在、层级高于落箭（手动步进期间无真实帧，不显现属预期）。
	var sky_bands: Array = get_nodes_in_group("HeavenfallSkyBand")
	check(sky_bands.size() == 1, "a single sky band covers the top of the screen while rain is inbound")
	if not sky_bands.is_empty():
		check(int((sky_bands[0] as CanvasItem).z_index) == 94 and int((sky_bands[0] as CanvasItem).z_index) > int((arrows[0] as CanvasItem).z_index), "the sky band draws above the rain arrows")
	for step in range(300):
		for a in range(total):
			if is_instance_valid(arrows[a]):
				arrows[a].call("_physics_process", 1.0 / 60.0)
		if land_step[0] < 0:
			var y0: float = (arrows[0] as Node2D).global_position.y
			# 落地那一步的位置被 _land() 钳到地面，位移被截断，不计入加速采样。
			if y0 < points[0].y:
				dys.append(y0 - last_y)
			last_y = y0
			var v: Variant = arrows[0].get("_vy")
			if v is float:
				vys.append(v)
			if y0 >= points[0].y:
				land_step[0] = step
				for web: Node in get_nodes_in_group("HeavenfallRainCrack"):
					if (web.get("landing") as Vector2).distance_to(points[0]) < 2.0:
						crack0 = web
						break
				crack_found = crack0 != null
		else:
			if step == land_step[0] + 1 and is_instance_valid(arrows[0]):
				# 钻入刚开始：箭杆地上段还长，像素证据最清晰的一档。
				var body_mat: ShaderMaterial = arrows[0].call("sprite_material") as ShaderMaterial
				var glow_mat: ShaderMaterial = arrows[0].call("glow_material") as ShaderMaterial
				check(body_mat != null and bool(body_mat.get_shader_parameter("clip_enabled")) and absf(float(body_mat.get_shader_parameter("clip_y")) - points[0].y) < 0.01, "the burrowing arrow starts clipping at the crack mouth line")
				check(glow_mat != null and bool(glow_mat.get_shader_parameter("clip_enabled")) and absf(float(glow_mat.get_shader_parameter("clip_y")) - points[0].y) < 0.01, "the glow clips at the same crack mouth line")
				if render:
					# 冻结裂缝、隐藏特效，再“藏箭/显箭”各拍一帧：两帧在落点线以下的差分
					# 就是箭的“地下部分”，必须为 0；线以上的差分应明显（箭身还在）。
					var frozen_cracks: Array = []
					for web: Node in get_nodes_in_group("HeavenfallRainCrack"):
						web.set_process(false)
						frozen_cracks.append(web)
					var fx_hidden: Array = []
					for n: Node in world.find_children("*", "Node2D", false, false):
						if (n.get_script() == FX_SCRIPT or n.get_script() == DEBRIS_FX_SCRIPT) and n.visible:
							n.visible = false
							fx_hidden.append(n)
					var burrow_arrow: Node2D = arrows[0] as Node2D
					burrow_arrow.visible = false
					await process_frame
					var underground: Image = await frame()
					burrow_arrow.visible = true
					await process_frame
					var with_arrow: Image = await frame()
					for web: Node in frozen_cracks:
						web.set_process(true)
					for n: Node in fx_hidden:
						n.visible = true
					var below_rect: Rect2i = _world_rect_image(underground, points[0] + Vector2(-5.0, 1.5), points[0] + Vector2(5.0, 15.0))
					var above_rect: Rect2i = _world_rect_image(underground, points[0] + Vector2(-5.0, -13.0), points[0] + Vector2(5.0, -1.5))
					var below_diff: int = diff_pixels(underground, with_arrow, below_rect)
					var above_diff: int = diff_pixels(underground, with_arrow, above_rect)
					check(below_diff <= 2, "no part of the burrowing arrow is drawn below the crack mouth (it goes underground, " + str(below_diff) + " px)")
					check(above_diff >= 8, "the shaft above the crack mouth keeps rendering while burrowing (" + str(above_diff) + " px)")
					print("RAIN_BURROW_CLIP: below=", below_diff, " above=", above_diff)
			if step == land_step[0] + 4:
				burrow_alive = is_instance_valid(arrows[0])
				if burrow_alive:
					burrow_y = (arrows[0] as Node2D).global_position.y
			if step == land_step[0] + 30:
				burrow_gone = not is_instance_valid(arrows[0]) or arrows[0].is_queued_for_deletion()
		for a in range(1, total):
			if land_step[a] < 0 and is_instance_valid(arrows[a]) and (arrows[a] as Node2D).global_position.y >= points[a].y:
				land_step[a] = step
		if land_step[2] >= 0 and step >= land_step[2] + 35:
			break
	var all_landed: bool = land_step[0] >= 0 and land_step[1] >= 0 and land_step[2] >= 0
	check(all_landed, "fixture: every rain arrow lands")
	if not all_landed:
		for node: Node in _falls() + _tears():
			node.queue_free()
		await physics_frame
		return
	var t0: float = float(land_step[0]) / 60.0
	check(t0 >= 0.30 and t0 <= 0.50, "the first rain arrow lands at about the configured delay")
	check(land_step[2] - land_step[0] >= 36, "rain arrows keep landing over a period instead of one simultaneous burst")
	check(land_step[1] - land_step[0] >= 15 and land_step[2] - land_step[1] >= 15, "landings are staggered in schedule order")
	var falling: Array[float] = []
	for d in dys:
		if d > 0.0001:
			falling.append(d)
	var growing: bool = falling.size() >= 5
	for k in range(2, falling.size()):
		growing = growing and falling[k] > falling[k - 1]
	check(growing, "the fall keeps speeding up under gravity")
	check(vys.size() >= 4 and vys[vys.size() - 1] > vys[0] + 200.0, "fall motion is integrated velocity state, not a time-parameterized animation")
	check(crack0 != null, "landing tears a small web of cracks open from the impact point")
	if crack0 != null:
		var web_center: Vector2 = crack0.get("landing")
		var arms: int = 1
		var reach: float = 0.0
		for limb: PackedVector2Array in crack0.get("_branches"):
			if limb.is_empty():
				continue
			if crack0.to_global(limb[0]).distance_to(web_center) < 0.01:
				arms += 1
			for vertex: Vector2 in limb:
				reach = maxf(reach, crack0.to_global(vertex).distance_to(web_center))
		check(arms >= 5, "the landing crack is a center-out web of primary arms")
		check(bool(crack0.get("_has_center_join")), "the web arms meet through one connected central aperture")
		check(reach > 4.0 and reach < 20.0, "the landing web stays small")
		# 手动步进期间没有真实帧，_age 不会自己前进；直接给定年龄读回材质参数。
		var widths: Array[float] = []
		for age: float in [0.20, 0.45, 0.75]:
			crack0.set("_age", age)
			crack0.call("_sync_visual")
			var material: ShaderMaterial = crack0.get("_rift_material")
			widths.append(float(material.get_shader_parameter("opening_progress")) * float(material.get_shader_parameter("closure")))
		check(widths[0] > 0.5 and widths[0] < 8.0, "the landing web opens to a small visible width")
		check(widths[0] > widths[1] and widths[1] > widths[2], "the landing web closes slowly after the arrow enters")
		check(widths[2] <= 0.01, "the landing web is fully closed in the end")
	check(burrow_alive and burrow_y >= points[0].y - 0.5, "the arrow burrows into the crack instead of vanishing on impact")
	check(burrow_gone, "the burrowed arrow disappears shortly after entering")
	await create_timer(1.3).timeout
	# 已释放的对象与 null 的比较不可靠，用独立的布尔记录裂缝存在过。
	check(crack_found and not is_instance_valid(crack0), "the closed crack cleans itself up")
	# 地图上空（岛外虚空）里的落箭必须可见：它高于地图外遮罩，而不是被裁掉。
	if render:
		await _park_intruders()
		var calm: Image = await frame()
		# 地图位于画面左上角，上缘之外在可视画面以上：改用地图下方的虚空取样。
		var sky_point: Vector2 = Vector2(center.x, arena.end.y + 200.0)
		var sky_arrow: Node = load("res://scenes/shooter/我的世界/天陨箭.tscn").instantiate()
		world.add_child(sky_arrow, true)
		sky_arrow.set_physics_process(false)
		sky_arrow.call("configure", bow, bow.Team, sky_point, 0.9, 0.0, 4.0, 0, 1)
		check((sky_arrow as Node2D).global_position.y < screen_top - 8.0, "fixture: the sky arrow also starts outside the visible screen")
		var guard: int = 0
		while guard < 90 and is_instance_valid(sky_arrow) and (sky_arrow as Node2D).global_position.y <= arena.end.y + 20.0:
			guard += 1
			sky_arrow.call("_physics_process", 1.0 / 60.0)
		check((sky_arrow as Node2D).global_position.y > arena.end.y, "fixture: the sky arrow is over the void when captured")
		var shot: Image = await frame()
		var screen_pos: Vector2 = screen_point((sky_arrow as Node2D).global_position)
		var changed: int = 0
		for y in range(int(screen_pos.y) - 14, int(screen_pos.y) + 15):
			for x in range(int(screen_pos.x) - 14, int(screen_pos.x) + 15):
				if x < 0 or y < 0 or x >= shot.get_width() or y >= shot.get_height():
					continue
				if pixel_delta(calm.get_pixel(x, y), shot.get_pixel(x, y)) > 0.05:
					changed += 1
		check(changed > 8, "a rain arrow high above the map island stays visible over the void mask")
		print("RAIN_OVER_VOID: changed_pixels=", changed)
		sky_arrow.queue_free()
		await physics_frame
	for node: Node in _falls() + _tears() + get_nodes_in_group("HeavenfallRainCrack"):
		node.queue_free()
	await physics_frame
	# 箭雨结束后（含虚空取证用的落箭），天穹带应完全退去并自清理。
	await create_timer(0.8).timeout
	check(get_nodes_in_group("HeavenfallSkyBand").is_empty(), "the sky band fades away and cleans itself up after the rain")


func pixel_delta(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))


func check_bow_recoil() -> void:
	# 天堂弓松弦后坐：曲线/幅度/交替倾角与 bow.gd 完全一致，且真实发射会触发。
	var plain_bow: GDScript = load("res://scripts/characters/我的世界/new6/bow.gd")
	var heaven_script: GDScript = bow.get_script()
	var curves_match: bool = true
	for age: float in [0.01, 0.032, 0.1, 0.3, 0.44]:
		curves_match = curves_match and is_equal_approx(float(plain_bow.recoil_curve(age)), float(heaven_script.recoil_curve(age)))
	check(curves_match, "the recoil spring curve is identical to bow.gd")
	var aim: Vector2 = bow.facing
	bow._fire()
	check(bow._recoil_power == 1.0 and bow._recoil_dir.is_equal_approx(-aim), "firing kicks the heavenfall bow back along the reverse aim at full power")
	check(bow._shot_seq == 1, "each release advances the visual shot sequence")
	var tilt_before: float = bow._recoil_tilt_sign
	bow._start_recoil(1.0, Vector2.RIGHT, bow._view_clock - 0.032)
	bow.visual_mob()
	var offset: Vector2 = (bow.image as Sprite2D).position - bow._rest_image_position
	check(offset.length() > 30.0 and offset.normalized().dot(Vector2.LEFT) > 0.9, "the bow body reaches the bow-matched recoil displacement at about 32ms")
	check(bow._recoil_tilt_sign == -tilt_before, "the recoil tilt alternates sides between consecutive shots")
	bow._start_recoil(1.0, Vector2.RIGHT, bow._view_clock - 0.5)
	bow.visual_mob()
	check((bow.image as Sprite2D).position.is_equal_approx(bow._rest_image_position), "the bow body elastically returns to its rest pose within 0.45s")


func check_map_wall(arena: Rect2, center: Vector2) -> void:
	var start: Vector2 = Vector2(arena.end.x - 60.0, center.y - 40.0)
	await _park_intruders()
	var rain_before: int = _falls().size()
	var rifts_before: int = _rifts().size()
	var tears_before: int = _tears().size()
	var bolt: Node = _spawn_bolt(start)
	var passed: bool = false
	for i in range(240):
		bolt._physics_process(1.0 / 60.0)
		passed = passed or bolt.has_pierced()
		if bolt.is_queued_for_deletion():
			break
	check(passed, "the arrow pierces the map's outer wall")
	check(bolt.is_queued_for_deletion() and bolt._leave_offscreen and bolt._offscreen(), "outside the map the arrow disappears exactly once it leaves the screen")
	check(_falls().size() == rain_before and _rifts().size() == rifts_before, "leaving the screen replaces rain and end-rift with a clean disappearance")
	check(_tears().size() == tears_before + 1, "the pass through the map wall still left its rift on the actual path")
	print("MAP_WALL_EXIT: canvas=", bolt.global_position, " viewport=", root.get_visible_rect())


func expected_tick_radius(step: int) -> float:
	# 圆圈沿用重锤的扩张曲线：第 step 跳时它真正的半径。
	var ring_script: GDScript = load("res://scripts/characters/我的世界/new6/heavenfall_ring.gd")
	var probe_ring: Node2D = ring_script.new()
	world.add_child(probe_ring)
	var interval: float = probe_ring.tick_interval
	var detail: float = probe_ring.lifetime
	var end_scale: float = probe_ring.ring_end_scale
	probe_ring.queue_free()
	var p: float = clampf(float(step) * interval / maxf(detail, 0.02), 0.0, 1.0)
	return lerpf(bow.rift_blast_radius, bow.rift_blast_radius * end_scale, 1.0 - pow(1.0 - p, 3.1))


func check_circle_ticks(center: Vector2) -> void:
	var inside: Node2D = _mk_dummy(center + Vector2(18, 0))
	await physics_frame
	# 受击者体型会给出额外命中余量，所以外侧目标的距离按它自己的体型推算：
	# 起始半径够不到，等圆圈扩到第四跳附近才够得到。
	var allowance: float = maxf(inside.get_crowd_separation_radius_world(), 3.0)
	var far: float = clampf(expected_tick_radius(3) + allowance - 10.0, 45.0, 60.0)
	var outside: Node2D = _mk_dummy(center + Vector2(far, 0))
	await physics_frame
	var inside_hp: float = inside.health
	var outside_hp: float = outside.health
	var inside_start: Vector2 = inside.global_position
	var outside_start: Vector2 = outside.global_position
	var ring: Node2D = load("res://scripts/characters/我的世界/new6/heavenfall_ring.gd").new()
	world.add_child(ring)
	var seen: Array[float] = []
	ring.connect("tick", bow._on_arrival_tick) # 与到达时完全相同的接线
	ring.tick.connect(func(_point: Vector2, radius: float, _index: int) -> void: seen.append(radius))
	ring.call("configure", center, bow.rift_blast_radius, center, 0.0, 29)
	ring.set_process(false)
	check(seen.size() == 1, "the circle deals damage on the arrival frame itself")
	var guard: int = 0
	while guard < 60 and is_instance_valid(ring) and seen.size() < 5:
		guard += 1
		ring._process(1.0 / 60.0)
		await physics_frame
	for i in range(4):
		await physics_frame
	check(seen.size() == 5, "five damage ticks across the 0.46 second circle")
	check(is_equal_approx(seen[0], bow.rift_blast_radius) and seen[seen.size() - 1] > seen[0] * 1.4, "each tick uses the circle's current expanding radius")
	check(is_equal_approx(inside_hp - inside.health, 10.0), "a target inside takes the fixed 2 damage on every tick")
	check(outside_hp - outside.health > 0.0 and outside_hp - outside.health < 10.0, "a target beyond the starting radius is only caught as the circle reaches it")
	var inward_push: float = inside.global_position.distance_to(center) - inside_start.distance_to(center)
	var outward_push: float = outside.global_position.distance_to(center) - outside_start.distance_to(center)
	check(inward_push > 1.0 and outward_push > 1.0, "every tick pushes the target outward, never inward")
	check(inward_push < 24.0, "the repeated knockback stays tiny instead of launching the target")
	print("CIRCLE_TICKS: radii=", seen, " inside_push=", inward_push, " outside_push=", outward_push, " far=", far, " allowance=", allowance)
	inside.queue_free()
	outside.queue_free()
