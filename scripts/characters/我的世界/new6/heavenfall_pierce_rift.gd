extends Node2D
# 箭穿过障碍物时，沿实际路径边穿边留下的空间裂隙。
# 每段采样各自张开（OPEN_RAMP）后保持 HOLD_TIME，再快速闭合（CLOSE_TIME）；
# 采样按穿越顺序生成，所以先开的先闭合——收口从穿入点向穿出点像拉链一样推进。
# 只沿路径延伸几何，不整体缩放裂纹或星空；星空沿用天陨裂隙同一套原生 Avaritia 算法。
const UNION = preload("res://scripts/characters/我的世界/new6/heavenfall_union.gd")
const COSMIC_SHADER: Shader = preload("res://shaders/heavenfall_cosmic.gdshader")
const COSMIC_ATLAS: Texture2D = preload("res://Images/characters/我的世界/new6/av_cosmic_atlas.png")
const HALO_SCALE: float = 1.45 # 与 heavenfall_cosmic.gdshader 保持一致
const MAX_OUTSIDE_RECTS: int = 32
const SAMPLE_STEP: float = 1.25
const TEAR_W0: float = 4.6
const OPEN_RAMP: float = 0.10 # 撕开动画：每段约 0.1 秒从零撕到全开，跟在箭后呈拉链状
const HOLD_TIME: float = 0.12
const CLOSE_TIME: float = 0.40 # 收口放慢：能看清先开先闭合的拉链过程
const TIP_LENGTH: float = 1.25
const MAX_SAMPLES: int = 256
# 可见贴图轮廓：透明像素不算障碍物的一部分，裂缝不得画进贴图透明区。
const VISUAL_ALPHA_THRESHOLD: float = 0.30
const VISUAL_STEP: float = 0.40
const VISUAL_REFINE_STEP: float = 0.10

var _points: PackedVector2Array = PackedVector2Array()
var _tangents: PackedVector2Array = PackedVector2Array()
var _open_at: PackedFloat32Array = PackedFloat32Array()
var _distances: PackedFloat32Array = PackedFloat32Array()
var _last_raw_point: Vector2 = Vector2.ZERO
var _path_direction: Vector2 = Vector2.RIGHT
var _travel_speed: float = 620.0
var _clip_body: WeakRef = null
var _clip_offsets: PackedFloat32Array = PackedFloat32Array()
var _visual_sprite: WeakRef = null
var _visual_image: Image = null
var _visual_invalid: bool = false
var _visual_from_world: Transform2D = Transform2D()
var _visual_size: Vector2 = Vector2.ZERO
var _visual_half: Vector2 = Vector2.ZERO
# 地图安全墙/边界是纯碰撞体：改按“看得见的墙”裁剪（贴图环或黑色边框线段）。
var _map_wall_rects: Array[Rect2] = []
var _map_wall_resolved: bool = false
var _age: float = 0.0
var _finished: bool = false
var _dirty: bool = false
var _end_time: float = 0.0
var _rng := RandomNumberGenerator.new()
var _surface: MeshInstance2D
var _exterior_surface: MeshInstance2D
var _material: ShaderMaterial
var _exterior_material: ShaderMaterial
var _last_depth: int = -99999
var _last_outside: PackedVector4Array = PackedVector4Array()


func configure(origin: Vector2, direction: Vector2, seed_value: int, travel_speed: float = 620.0, entry_delay: float = 0.0, clip_body: Object = null) -> void:
	add_to_group("BattleTransient")
	add_to_group("HeavenfallPierceTear")
	global_position = origin
	_path_direction = direction.normalized() if not direction.is_zero_approx() else Vector2.RIGHT
	_travel_speed = maxf(travel_speed, 1.0)
	_age = -maxf(entry_delay, 0.0)
	_clip_body = weakref(clip_body) if clip_body is CollisionObject2D else null
	_rng.seed = maxi(seed_value, 1)
	z_as_relative = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_surfaces()
	add_sample(origin, direction)
	UNION.register_aperture(self)


func is_open() -> bool:
	return not is_queued_for_deletion() and _age < _end_time


func sample_count() -> int:
	return _points.size()


func is_finished() -> bool:
	return _finished


func add_sample(world_point: Vector2, direction: Vector2) -> void:
	if _finished:
		return
	var axis: Vector2 = direction.normalized() if direction.length_squared() > 0.000001 else Vector2.RIGHT
	var target: Vector2 = to_local(world_point)
	if _points.is_empty():
		_append(target, axis)
		return
	var last: Vector2 = _last_raw_point
	var span: float = to_global(last).distance_to(world_point)
	if span < 0.0001:
		return
	if (world_point - to_global(last)).dot(_path_direction) < 0.0:
		return
	# Even a sub-step thin wall needs an interior vertex between its two tips.
	var steps: int = maxi(2, int(ceil(span / SAMPLE_STEP)))
	for i in range(1, steps + 1):
		if _points.size() >= MAX_SAMPLES:
			_compact_samples()
		_append(last.lerp(target, float(i) / float(steps)), axis)


func finish() -> void:
	_finished = true
	# 最后一个采样是真实穿出点：还原为未抖动的精确位置，尖端不越出穿出面。
	if not _points.is_empty():
		_points[_points.size() - 1] = _last_raw_point
	_trim_visual_ends()


func close_start(index: int) -> float:
	if index < 0 or index >= _open_at.size():
		return INF
	return _open_at[index] + OPEN_RAMP + HOLD_TIME


func sample_aperture(index: int, at_time: float) -> float:
	if index < 0 or index >= _open_at.size(): return 0.0
	# Same eased (smoothstep) opening / hold / closing curve as the shader, shifted in time.
	# 两端减速的缓动消除线性速率的速度突变，撕开与收口都丝滑。
	var local_age: float = at_time - _open_at[index]
	var open_t: float = clampf(local_age / OPEN_RAMP, 0.0, 1.0)
	var opening: float = open_t * open_t * (3.0 - 2.0 * open_t)
	var close_t: float = clampf((local_age - OPEN_RAMP - HOLD_TIME) / CLOSE_TIME, 0.0, 1.0)
	var closing: float = 1.0 - close_t * close_t * (3.0 - 2.0 * close_t)
	return minf(opening, closing)


func _append(point: Vector2, direction: Vector2) -> void:
	var previous: Vector2 = _last_raw_point if not _points.is_empty() else point
	var along: Vector2 = point - previous
	var tangent: Vector2 = along.normalized() if along.length_squared() > 0.000001 else direction
	var world_side := Vector2(-_path_direction.y, _path_direction.x)
	var side: Vector2 = global_transform.affine_inverse().basis_xform(world_side)
	# Keep jitter perpendicular to the true trajectory. It cannot lengthen the slit
	# or contaminate the distance/time calculation for the next sample.
	# 端点（穿入面）不抖动：尖端宽≈0，抖动只会把它推出表面。
	var jittered: Vector2 = point + side * _rng.randf_range(-0.30, 0.30) if not _points.is_empty() else point
	_points.append(jittered)
	_tangents.append(tangent)
	_last_raw_point = point
	var distance: float = maxf((to_global(point) - global_position).dot(_path_direction), 0.0)
	var opened: float = distance / _travel_speed
	_distances.append(distance)
	_open_at.append(opened)
	# 裁剪距离在“实际使用的（带抖动）中心”上测量：角落/曲率不再引入越界余量。
	_clip_offsets.append(_shape_clip_limit(jittered))
	_dirty = true
	_end_time = opened + OPEN_RAMP + HOLD_TIME + CLOSE_TIME


func _shape_clip_limit(point: Vector2) -> float:
	# 裂缝横向不得超过被穿障碍物的真实形状：贴边/过角时按两侧表面距离收窄。
	var limit: float = TEAR_W0 * 0.5 * HALO_SCALE
	var clipper: Object = _clip_body.get_ref() if _clip_body != null else null
	if not clipper is CollisionObject2D or not is_inside_tree():
		return limit
	_resolve_visual_source(clipper as CollisionObject2D)
	var world_center: Vector2 = to_global(point)
	var world_side := Vector2(-_path_direction.y, _path_direction.x)
	var clip_rid: RID = (clipper as CollisionObject2D).get_rid()
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	for dir_sign: float in [-1.0, 1.0]:
		# 不能从体内向外射（hit_from_inside 会把命中点报在起点）；
		# 从外侧射向中心，用命中点反推中心到该方向边界的真实距离。
		var reach: float = limit + 1.0
		var outside: Vector2 = world_center + world_side * dir_sign * reach
		var excluded: Array[RID] = []
		for _attempt in range(8):
			var query := PhysicsRayQueryParameters2D.create(outside, world_center)
			query.collide_with_areas = false
			query.collide_with_bodies = true
			query.exclude = excluded
			var hit: Dictionary = space.intersect_ray(query)
			if hit.is_empty():
				break
			var rid: RID = hit.get("rid", RID())
			if rid == clip_rid:
				var boundary: float = reach - (hit.get("position", outside) as Vector2).distance_to(outside)
				limit = minf(limit, maxf(boundary - 0.30, 0.0))
				break
			if not rid.is_valid() or excluded.has(rid):
				break
			excluded.append(rid)
	# 可见几何之外不算障碍物的一部分：横向再按不透明轮廓/可见墙环收窄。
	if _visual_image != null or _map_wall_resolved:
		if not _visible_ok(world_center):
			return 0.0
		for dir_sign: float in [-1.0, 1.0]:
			var distance: float = 0.0
			while distance < limit:
				var next: float = minf(distance + VISUAL_STEP, limit)
				if not _visible_ok(world_center + world_side * dir_sign * next):
					break
				distance = next
			limit = minf(limit, maxf(distance - 0.20, 0.0))
	return limit


func _resolve_visual_source(clipper: CollisionObject2D) -> void:
	if _visual_sprite != null or _visual_image != null or _visual_invalid or _map_wall_resolved:
		return
	for node: Node in clipper.find_children("*", "Sprite2D", true, false):
		var sprite: Sprite2D = node as Sprite2D
		if sprite == null or sprite.texture == null or sprite.region_enabled or sprite.flip_h or sprite.flip_v:
			continue
		var image: Image = sprite.texture.get_image()
		if image == null or image.is_empty():
			continue
		_visual_sprite = weakref(sprite)
		_visual_image = image
		_visual_from_world = sprite.global_transform.affine_inverse()
		_visual_size = image.get_size()
		_visual_half = _visual_size * 0.5
		return
	if _resolve_map_wall_rects(clipper):
		_map_wall_resolved = true
		return
	_visual_invalid = true


func _resolve_map_wall_rects(clipper: CollisionObject2D) -> bool:
	# 地图安全墙/边界是纯碰撞体（不可见、还比可见墙厚得多）：改用地图
	# “看得见的墙”裁剪——草方块主题是背景贴图环，其他主题是黑色边框线段。
	var node: Node = clipper
	while is_instance_valid(node):
		if node.has_meta(&"map_safety_wall") or node.has_meta(&"map_safety_frame") or node.has_meta(&"mc_map_boundary"):
			var world: Node = get_tree().current_scene
			if world == null or not world.has_method("map_island_rects"):
				return false
			var tiles: Node = world.get("map_background_tiles")
			if tiles != null and is_instance_valid(tiles) and tiles.has_method("visible_wall_rects"):
				for rect: Rect2 in tiles.call("visible_wall_rects"):
					_map_wall_rects.append(rect)
				if not _map_wall_rects.is_empty():
					return true
			var seg_root: Node = world.get("map_border_segment_root")
			if seg_root != null and is_instance_valid(seg_root):
				for child: Node in seg_root.get_children():
					var line: Line2D = child as Line2D
					if line == null or line.points.size() < 2:
						continue
					var lo: Vector2 = line.points[0].min(line.points[1])
					var hi: Vector2 = line.points[0].max(line.points[1])
					_map_wall_rects.append(Rect2(lo, hi - lo).grow(maxf(line.width, 2.0) * 0.5))
				if not _map_wall_rects.is_empty():
					return true
			return false
		node = node.get_parent()
	return false


func _visible_ok(world_point: Vector2) -> bool:
	# 世界点是否落在障碍物的可见部分：贴图不透明像素 / 地图外墙可见环。
	if _visual_image != null:
		return _visual_alpha(world_point) >= VISUAL_ALPHA_THRESHOLD
	if _map_wall_resolved:
		for rect: Rect2 in _map_wall_rects:
			if rect.grow(0.10).has_point(world_point):
				return true
		return false
	return true


func _visual_alpha(world_point: Vector2) -> float:
	if _visual_image == null:
		return 1.0
	var sprite: Sprite2D = _visual_sprite.get_ref() as Sprite2D
	if sprite == null or not is_instance_valid(sprite):
		return 1.0
	var local: Vector2 = _visual_from_world * world_point - sprite.offset
	var pixel: Vector2i = Vector2i((local + _visual_half).round())
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= int(_visual_size.x) or pixel.y >= int(_visual_size.y):
		return 0.0
	return _visual_image.get_pixelv(pixel).a


func _trim_visual_ends() -> void:
	# 首尾落在可见几何之外的段直接裁掉：只穿过碰撞框、没有真正切开可见障碍物的路径不留裂缝。
	if _points.is_empty():
		return
	if _visual_image == null and not _map_wall_resolved:
		var clipper: Object = _clip_body.get_ref() if _clip_body != null else null
		if clipper is CollisionObject2D:
			_resolve_visual_source(clipper as CollisionObject2D)
	if _visual_image == null and not _map_wall_resolved:
		return
	var count: int = _points.size()
	var first: int = 0
	while first < count and not _visible_ok(_raw_path_point(first)):
		first += 1
	if first >= count:
		_points = PackedVector2Array()
		_tangents = PackedVector2Array()
		_open_at = PackedFloat32Array()
		_distances = PackedFloat32Array()
		_clip_offsets = PackedFloat32Array()
		_dirty = true
		return
	var last: int = count - 1
	while last > first and not _visible_ok(_raw_path_point(last)):
		last -= 1
	# 端点精确定位在路径直线上做，不用带抖动的采样点（抖动会让边界偏移）。
	var start_point: Vector2 = _points[first]
	if first > 0:
		start_point = to_local(_visual_boundary_world(_raw_path_point(first), _raw_path_point(first - 1)))
	var end_point: Vector2 = _points[last]
	if last < count - 1:
		end_point = to_local(_visual_boundary_world(_raw_path_point(last), _raw_path_point(last + 1)))
	var points := PackedVector2Array()
	var tangents := PackedVector2Array()
	var times := PackedFloat32Array()
	var distances := PackedFloat32Array()
	var clips := PackedFloat32Array()
	for i in range(first, last + 1):
		points.append(start_point if i == first else (end_point if i == last else _points[i]))
		tangents.append(_tangents[i])
		times.append(_open_at[i])
		distances.append(_distances[i])
		clips.append(_clip_offsets[i] if i < _clip_offsets.size() else TEAR_W0 * 0.5 * HALO_SCALE)
	_points = points
	_tangents = tangents
	_open_at = times
	_distances = distances
	_clip_offsets = clips
	_refresh_sample_meta(0)
	_refresh_sample_meta(_points.size() - 1)
	_end_time = _open_at[_open_at.size() - 1] + OPEN_RAMP + HOLD_TIME + CLOSE_TIME
	_dirty = true


func _raw_path_point(index: int) -> Vector2:
	# 采样 i 的未抖动位置：入口 + 沿路径的路程。
	return global_position + _path_direction * _distances[index]


func _visual_boundary_world(opaque_world: Vector2, transparent_world: Vector2) -> Vector2:
	# 在两个位置之间沿直线精确定位可见边界（步长 0.1 世界单位）。
	var offset: Vector2 = transparent_world - opaque_world
	var total: float = offset.length()
	if total < 0.0001:
		return opaque_world
	var direction: Vector2 = offset / total
	var distance: float = 0.0
	while distance < total:
		var next: float = minf(distance + VISUAL_REFINE_STEP, total)
		if not _visible_ok(opaque_world + direction * next):
			break
		distance = next
	return opaque_world + direction * distance


func _refresh_sample_meta(index: int) -> void:
	var world_point: Vector2 = to_global(_points[index])
	var distance: float = maxf((world_point - global_position).dot(_path_direction), 0.0)
	_distances[index] = distance
	_open_at[index] = distance / _travel_speed
	_clip_offsets[index] = _shape_clip_limit(_points[index])


func _compact_samples() -> void:
	# Long obstacles must reach their actual exit rather than stop at a sample cap.
	# Retain endpoints and true timestamps while reducing only redundant geometry.
	var keep: Array[int] = []
	for i in range(0, _points.size(), 2): keep.append(i)
	if keep.back() != _points.size() - 1: keep.append(_points.size() - 1)
	var points := PackedVector2Array()
	var tangents := PackedVector2Array()
	var times := PackedFloat32Array()
	var distances := PackedFloat32Array()
	var clips := PackedFloat32Array()
	for i: int in keep:
		points.append(_points[i])
		tangents.append(_tangents[i])
		times.append(_open_at[i])
		distances.append(_distances[i])
		clips.append(_clip_offsets[i] if i < _clip_offsets.size() else TEAR_W0 * 0.5 * HALO_SCALE)
	_points = points
	_tangents = tangents
	_open_at = times
	_distances = distances
	_clip_offsets = clips


func _build_surfaces() -> void:
	if is_instance_valid(_surface):
		return
	_surface = MeshInstance2D.new()
	_surface.name = "PierceCosmicInterior"
	_surface.z_as_relative = false
	_surface.visible = false
	add_child(_surface)
	_material = ShaderMaterial.new()
	_material.shader = COSMIC_SHADER
	_material.set_shader_parameter("cosmic_atlas", COSMIC_ATLAS)
	_material.set_shader_parameter("linear_output", get_viewport().use_hdr_2d and RenderingServer.get_current_rendering_method() != "gl_compatibility")
	_material.set_shader_parameter("cosmic_origin", global_position)
	_material.set_shader_parameter("opening_progress", 1.0)
	_material.set_shader_parameter("opening_feather", 0.0001) # 张开完全由每段自己的时间决定
	_material.set_shader_parameter("sample_life_enabled", true)
	_material.set_shader_parameter("sample_direction", _path_direction)
	_material.set_shader_parameter("sample_speed", _travel_speed)
	_material.set_shader_parameter("sample_open_ramp", OPEN_RAMP)
	_material.set_shader_parameter("sample_hold_time", HOLD_TIME)
	_material.set_shader_parameter("sample_close_time", CLOSE_TIME)
	_surface.material = _material
	_exterior_surface = MeshInstance2D.new()
	_exterior_surface.name = "PierceExteriorCosmicInterior"
	_exterior_surface.z_as_relative = false
	_exterior_surface.visible = false
	add_child(_exterior_surface)
	_exterior_material = _material.duplicate() as ShaderMaterial
	_exterior_material.set_shader_parameter("outside_only", true)
	_exterior_surface.material = _exterior_material
	_sync_depth()


func _process(delta: float) -> void:
	if Game.now_stop_state or get_tree().paused:
		return
	_age += maxf(delta, 0.0)
	_sync_depth()
	_update_outside_regions()
	if _dirty:
		_rebuild_mesh()
	if _material != null:
		_material.set_shader_parameter("sample_time", _age)
	if _exterior_material != null:
		_exterior_material.set_shader_parameter("sample_time", _age)
	if _age >= _end_time:
		queue_free()


func _sync_depth() -> void:
	if not is_instance_valid(_surface):
		return
	var depth: int = 0
	var ancestor: Node = get_parent()
	while ancestor != null:
		if ancestor is CanvasLayer or ancestor is Viewport:
			break
		var item: CanvasItem = ancestor as CanvasItem
		if item != null:
			depth += item.z_index
			if not item.z_as_relative:
				break
		ancestor = ancestor.get_parent()
	if depth == _last_depth:
		return
	_last_depth = depth
	# 穿行裂隙切在障碍表面，不能像终点裂纹一样藏在实体之下；仍低于箭矢 z=8。
	_surface.z_index = depth + 7
	_exterior_surface.z_index = depth + 91


func _update_outside_regions() -> void:
	if not is_instance_valid(_exterior_surface) or _exterior_material == null:
		return
	var world: Node = get_tree().current_scene
	var parts: Variant = world.get("map_outside_mask_parts") if world != null else null
	var regions := PackedVector4Array()
	var count: int = 0
	if parts is Array:
		for part: Variant in parts:
			if not is_instance_valid(part) or not part is Polygon2D or not part.is_visible_in_tree() or part.polygon.is_empty():
				continue
			var rect := Rect2(part.to_global(part.polygon[0]), Vector2.ZERO)
			for vertex: Vector2 in part.polygon:
				rect = rect.expand(part.to_global(vertex))
			regions.append(Vector4(rect.position.x, rect.position.y, rect.end.x, rect.end.y))
			count += 1
			if count >= MAX_OUTSIDE_RECTS:
				break
	_exterior_surface.visible = count > 0 and _surface.visible
	regions.resize(MAX_OUTSIDE_RECTS)
	if regions != _last_outside:
		_last_outside = regions
		_exterior_material.set_shader_parameter("outside_rects", regions)
		_exterior_material.set_shader_parameter("outside_count", count)


func _rebuild_mesh() -> void:
	_dirty = false
	if _points.size() < 2 or not is_instance_valid(_surface):
		_surface.visible = false
		_exterior_surface.visible = false
		return
	var vertices := PackedVector2Array()
	var offsets := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var length: float = _distances[_distances.size() - 1]
	var tip_length: float = maxf(minf(TIP_LENGTH, length * 0.5), 0.0001)
	for i in range(_points.size()):
		# Uniform section width/rate, with only a short fixed-distance pointed cap.
		# Growing the tail no longer reshapes the entire already-open slit.
		var edge_distance: float = minf(_distances[i], length - _distances[i])
		var width_value: float = TEAR_W0 * clampf(edge_distance / tip_length, 0.0, 1.0)
		var half_width: float = width_value * 0.5
		var side: Vector2 = global_transform.affine_inverse().basis_xform(Vector2(-_path_direction.y, _path_direction.x))
		var reach: float = half_width * HALO_SCALE
		if i < _clip_offsets.size():
			reach = minf(reach, _clip_offsets[i])
		var offset: Vector2 = side * reach
		vertices.append(_points[i] - offset)
		vertices.append(_points[i] + offset)
		offsets.append(-offset)
		offsets.append(offset)
		# Birth time is reconstructed from world path distance in the shader.
		# No vertex-colour quantisation can merge close timestamps in HDR or LDR.
		colors.append(Color(0.0, 0.0, 0.0, 1.0))
		colors.append(Color(1.0, 0.0, 0.0, 1.0))
	for i in range(_points.size() - 1):
		var a: int = i * 2
		indices.append_array(PackedInt32Array([a, a + 1, a + 2, a + 2, a + 1, a + 3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = offsets
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_surface.mesh = mesh
	_exterior_surface.mesh = mesh
	_surface.visible = true
	_update_outside_regions()
