extends "res://tests/test_heavenfall_arrow_pierce.gd"
# Exercise actual static stone obstacles, opaque terrain, the real map mask,
# and the complete arrow sprite at viewport edges. Run without --headless for pixels.


func _clear_probes() -> void:
	for node: Node in _bolts() + _falls() + _rifts() + _tears():
		node.queue_free()
	await process_frame


func _changed_pixels(node: Node2D, world_bounds: Rect2) -> int:
	node.hide()
	var without: Image = await frame()
	node.show()
	var with_node: Image = await frame()
	var to_pixels: Transform2D = root.get_stretch_transform() * root.canvas_transform
	var rect: Rect2 = to_pixels * world_bounds
	var region := Rect2i(Vector2i(rect.position.floor()), Vector2i(rect.size.ceil())).intersection(Rect2i(Vector2i.ZERO, with_node.get_size()))
	return diff_pixels(without, with_node, region)


func _freeze_tear(tear: Node2D) -> void:
	tear.set_process(false)
	tear._age = 0.075
	tear._process(0.0)


func check_pierce(center: Vector2) -> void:
	await super.check_pierce(center)
	await _clear_probes()
	await check_stone(center)
	await check_opaque_wall(center)


func check_stone(center: Vector2) -> void:
	var stone: StaticBody2D = load("res://scenes/characters/默认/石头.tscn").instantiate()
	world.add_child(stone, true)
	stone.global_position = center
	await physics_frame
	await _park_intruders([stone])
	var start: Vector2 = center + Vector2(-50, 0)
	var bolt: Node = _spawn_bolt(start)
	var collision: Script = load("res://scripts/characters/我的世界/new6/heavenfall_collision.gd")
	var hit: Dictionary = collision.projectile(bolt, bow, start, center + Vector2(50, 0))
	check(hit.get("collider") == stone and not hit.has("victim"), "the real stone is terrain, not an ignored ball or a damage victim")
	var stone_transform: Transform2D = stone.global_transform
	for i in range(8):
		bolt._physics_process(1.0 / 60.0)
		if bolt.has_pierced() and not bolt.is_inside_obstacle():
			break
	check(bolt.has_pierced() and not bolt.is_leaving_screen(), "crossing a real stone consumes the single obstacle pass without entering map-exit mode")
	check(_tears().size() == 1, "crossing a real stone creates a path rift")
	check(is_instance_valid(stone) and not stone.is_queued_for_deletion() and stone.global_transform==stone_transform and stone.collision_layer==1, "the indestructible static stone stays intact without character health")
	if _tears().size() == 1:
		var tear: Node2D = _tears()[0]
		_freeze_tear(tear)
		check(tear.sample_count() > 2, "the stone rift contains the actual crossing path")
		if render:
			var pixels: int = await _changed_pixels(tear, Rect2(center - Vector2(6, 2), Vector2(12, 4)))
			check(pixels > 10, "the rift is visibly drawn over the opaque stone texture")
			print("STONE_RIFT_PIXELS: ", pixels)
	stone.queue_free()
	await _clear_probes()


func check_opaque_wall(center: Vector2) -> void:
	var start: Vector2 = center + Vector2(-50, -20)
	var wall: StaticBody2D = _mk_wall(start + Vector2(36, 0))
	var surface := Polygon2D.new()
	surface.polygon = PackedVector2Array([Vector2(-15, -15), Vector2(15, -15), Vector2(15, 15), Vector2(-15, 15)])
	surface.color = Color(0.35, 0.28, 0.20, 1.0)
	wall.add_child(surface)
	await physics_frame
	await _park_intruders()
	var bolt: Node = _spawn_bolt(start)
	for i in range(8):
		bolt._physics_process(1.0 / 60.0)
		if bolt.has_pierced() and not bolt.is_inside_obstacle():
			break
	check(_tears().size() == 1 and not bolt.is_leaving_screen(), "ordinary opaque static terrain also creates one crossing rift")
	if _tears().size() == 1:
		var tear: Node2D = _tears()[0]
		_freeze_tear(tear)
		if render:
			var pixels: int = await _changed_pixels(tear, Rect2(wall.global_position - Vector2(8, 2), Vector2(16, 4)))
			check(pixels > 10, "opaque obstacle graphics cannot cover the path rift")
			print("OPAQUE_RIFT_PIXELS: ", pixels)
			export_image(await frame(), "heavenfall_obstacle_visible.png")
	wall.queue_free()
	await _clear_probes()


func _cross_map_wall(arena: Rect2, center: Vector2) -> Node:
	await _park_intruders()
	var bolt: Node = _spawn_bolt(Vector2(arena.end.x - 60.0, center.y - 40.0))
	for i in range(20):
		bolt._physics_process(1.0 / 60.0)
		if bolt.is_queued_for_deletion() or bolt.global_position.x >= arena.end.x + 20.0:
			break
	for tear: Node in _tears():
		tear.set_process(false)
	check(bolt.has_pierced() and bolt.is_leaving_screen() and not bolt.is_queued_for_deletion(), "fixture: the arrow has really crossed the map wall and is still on screen")
	return bolt


func check_map_wall(arena: Rect2, center: Vector2) -> void:
	await check_map_wall_rift(arena, center)
	await super.check_map_wall(arena, center)
	await _clear_probes()
	var bolt: Node = await _cross_map_wall(arena, center)
	if render and not bolt.is_queued_for_deletion():
		var sprite: Sprite2D = bolt.get_node("Sprite2D")
		var pixels: int = await _changed_pixels(bolt, sprite.global_transform * sprite.get_rect())
		check(pixels > 10, "a map-exiting arrow remains visible over the outside-map mask")
		print("OUTSIDE_ARROW_PIXELS: ", pixels)
		export_image(await frame(), "heavenfall_outside_arrow_visible.png")
		var ordinary: Node = _spawn_bolt(bolt.global_position + Vector2(0, 25))
		var ordinary_sprite: Sprite2D = ordinary.get_node("Sprite2D")
		var ordinary_pixels: int = await _changed_pixels(ordinary, ordinary_sprite.global_transform * ordinary_sprite.get_rect())
		check(ordinary_pixels == 0 and world.map_outside_mask_root.visible, "the map mask still clips ordinary arrows; only the departing arrow is exempt")
		ordinary.queue_free()
	var rain_before: int = _falls().size()
	var rifts_before: int = _rifts().size()
	bolt._max_dist = bolt._travelled + 0.1
	bolt._physics_process(1.0 / 600.0)
	check(not bolt.is_queued_for_deletion(), "crossing the map wall disables the old maximum-distance expiration")
	check(_falls().size() == rain_before and _rifts().size() == rifts_before, "range exhaustion outside the map creates no premature rain or end rift")
	await _clear_probes()
	await check_sprite_edges(center)
	await check_departing_flight(arena, center)


func check_map_wall_rift(arena: Rect2, center: Vector2) -> void:
	# 地图外墙的裂隙必须贴着“看得见的墙”（贴图环），不能画进地图外遮罩区域。
	await _clear_probes()
	var visible: Array[Rect2] = []
	var tiles: Node = world.map_background_tiles
	if tiles != null and is_instance_valid(tiles) and tiles.has_method("visible_wall_rects"):
		for rect: Rect2 in tiles.call("visible_wall_rects"):
			visible.append(rect)
	check(not visible.is_empty(), "fixture: the map's visible wall rects are available")
	if visible.is_empty():
		return
	await _park_intruders()
	var lane: Vector2 = Vector2(arena.end.x - 60.0, center.y - 40.0)
	var bolt: Node = _spawn_bolt(lane)
	for i in range(30):
		bolt._physics_process(1.0 / 60.0)
		if bolt.is_queued_for_deletion():
			break
		if bolt.has_pierced() and not bolt.is_inside_obstacle():
			break
	var tears: Array = _tears()
	check(tears.size() == 1, "the map wall crossing leaves exactly one rift")
	if tears.is_empty():
		await _clear_probes()
		return
	var tear: Node2D = tears[0]
	tear.set_process(false)
	var pts: PackedVector2Array = tear.get("_points")
	check(pts.size() >= 2, "the map wall rift has real samples")
	if pts.size() < 2:
		await _clear_probes()
		return
	var near_value: float = INF
	var far_value: float = -INF
	for p: Vector2 in pts:
		var along: float = (tear.to_global(p) - lane).dot(Vector2.RIGHT)
		near_value = minf(near_value, along)
		far_value = maxf(far_value, along)
	var ring: Rect2 = Rect2()
	for rect: Rect2 in visible:
		if rect.has_point(Vector2(arena.end.x + 1.0, lane.y)):
			ring = rect
			break
	check(ring.size.x > 0.0, "fixture: the right visible wall rect is found")
	var visual_min: float = ring.position.x - lane.x
	var visual_max: float = ring.position.x + ring.size.x - lane.x
	check(near_value >= visual_min - 0.35 and far_value <= visual_max + 0.35, "the map wall rift cannot extend past the visible wall into the masked outside")
	check(absf(near_value - visual_min) <= 0.35 and absf(far_value - visual_max) <= 0.35, "the map wall rift covers the visible wall from its inner to its outer face")
	tear._rebuild_mesh()
	var mesh: ArrayMesh = tear._surface.mesh
	var inside_ok: bool = mesh != null
	if mesh != null:
		for vertex: Vector2 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var wp: Vector2 = tear.to_global(vertex)
			var inside: bool = false
			for rect: Rect2 in visible:
				if rect.grow(0.75).has_point(wp):
					inside = true
					break
			inside_ok = inside_ok and inside
	check(inside_ok, "the complete map wall rift mesh stays inside the visible wall ring")
	print("MAP_WALL_RIFT span=", Vector2(near_value, far_value), " expected=", Vector2(visual_min, visual_max))
	await _clear_probes()


func check_sprite_edges(center: Vector2) -> void:
	var bolt: Node = _spawn_bolt(center)
	bolt.global_scale = Vector2(1.4, 0.8)
	var sprite: Sprite2D = bolt.get_node("Sprite2D")
	var view: Rect2 = root.get_visible_rect()
	var from_screen: Transform2D = root.canvas_transform.affine_inverse()
	var directions: Array[Vector2] = [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]
	for i in range(directions.size()):
		var direction: Vector2 = directions[i]
		bolt.rotation = float(i) * 0.37
		bolt.global_position = from_screen * view.get_center()
		var bounds: Rect2 = sprite.get_global_transform_with_canvas() * sprite.get_rect()
		var half: float = bounds.size.x * 0.5 if direction.x != 0.0 else bounds.size.y * 0.5
		var edge: Vector2 = view.get_center() + direction * (view.size.x * 0.5 if direction.x != 0.0 else view.size.y * 0.5)
		bolt.global_position = from_screen * (edge + direction * half * 0.5)
		check(not bolt._offscreen(), "partial arrow remains on screen at edge %d, even with its center outside" % i)
		bolt.global_position = from_screen * (edge + direction * (half + 1.0))
		check(bolt._offscreen(), "the entire scaled/rotated sprite is outside at edge %d" % i)
	await _clear_probes()


func check_departing_flight(arena: Rect2, center: Vector2) -> void:
	var bolt: Node = await _cross_map_wall(arena, center)
	var target: Node2D = _mk_enemy(bolt.global_position + Vector2(5, 15))
	await physics_frame
	bolt._homing_range = 500.0
	bolt._homing_turn = 360.0
	var hp: float = target.health
	var heading: Vector2 = bolt._dir
	bolt._physics_process(1.0 / 60.0)
	check(not bolt.is_queued_for_deletion() and bolt._dir.is_equal_approx(heading), "a departing arrow flies out directly instead of homing back or expiring on outside actors")
	check(is_equal_approx(target.health, hp), "map-exit flight does not hit outside actors")
	target.queue_free()
	if not bolt.is_queued_for_deletion():
		var view: Rect2 = root.get_visible_rect()
		var sprite: Sprite2D = bolt.get_node("Sprite2D")
		var bounds: Rect2 = sprite.get_global_transform_with_canvas() * sprite.get_rect()
		var from_screen: Transform2D = root.canvas_transform.affine_inverse()
		var edge: Vector2 = Vector2(view.end.x, view.get_center().y)
		bolt.global_position = from_screen * (edge + Vector2(bounds.size.x * 0.25, 0))
		bolt._physics_process(0.0)
		check(not bolt.is_queued_for_deletion(), "crossed-wall flight keeps the partially visible tail alive")
		if not bolt.is_queued_for_deletion():
			var rain_before: int = _falls().size()
			var rifts_before: int = _rifts().size()
			bolt.global_position = from_screen * (edge + Vector2(bounds.size.x + 1.0, 0))
			bolt._physics_process(0.0)
			check(bolt.is_queued_for_deletion(), "crossed-wall flight vanishes once the whole arrow leaves the viewport")
			check(_falls().size() == rain_before and _rifts().size() == rifts_before, "the final offscreen disappearance remains quiet")
	await _clear_probes()
