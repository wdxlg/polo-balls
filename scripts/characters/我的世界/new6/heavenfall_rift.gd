extends Node2D
# 天陨裂隙：多道裂纹通过一个连续中央开口连接；不参与地形碰撞。
# 青绿、银白边缘取自天堂弓，寰宇星空使用同版本 Avaritia 的原生图集和 shader 算法。
const UNION = preload("res://scripts/characters/我的世界/new6/heavenfall_union.gd")
const COSMIC_SHADER: Shader = preload("res://shaders/heavenfall_cosmic.gdshader")
const COSMIC_ATLAS: Texture2D = preload("res://Images/characters/我的世界/new6/av_cosmic_atlas.png")
const WARP_SHADER: Shader = preload("res://shaders/heavenfall_warp.gdshader")
const BIRTH_DEBRIS = preload("res://scripts/characters/我的世界/new6/heavenfall_debris.gd")
const OPEN_TIME: float = 0.5
@export var opening_time: float = OPEN_TIME
@export var opening_ease: float = 1.4
const OPEN_FEATHER: float = 5.0
const MAIN_W0: float = 4.0
const CENTER_W0: float = 6.0
const CENTER_ID: int = -1
const WARP_SCALE: float = 4.5
const WARP_STRENGTH: float = 5.0
const WARP_REACH: float = 10.0
const MAX_MASK_SEGMENTS: int = 128
const MAX_OUTSIDE_RECTS: int = 32
const CONSUME_CLOSE_TIME: float = 0.24
const SAMPLE_STEP: float = 5.0
const HALO_SCALE: float = 1.45 # 与 heavenfall_cosmic.gdshader 保持一致；外辉也收束到零宽尖端。

var rift_id: int = 0
var landing: Vector2 = Vector2.ZERO

var _owner_ref: WeakRef
var _points: PackedVector2Array = PackedVector2Array()
var _branches: Array = []
var _life: float = 6.0
var _age: float = 0.0
var _closed: bool = false
var _reserved: bool = false
var _reserved_width: float = 1.0
var _reserve_elapsed: float = 0.0
var _surface: MeshInstance2D
var _exterior_surface: MeshInstance2D
var _exterior_material: ShaderMaterial
var _cached_cracks: Array[Dictionary] = []
var _has_center_join: bool = false
var _last_mask_transform: Transform2D
var _last_draw_depth: int = -99999
var _last_outside_rects := PackedVector4Array()
var _rift_material: ShaderMaterial
var _space_copy: BackBufferCopy
var _space_warp: MeshInstance2D
var _warp_material: ShaderMaterial
var _copy_bounds: Rect2
var _close_from: float = 1.0
var _close_elapsed: float = 0.0
var _birth_span: float = 1.0
var _close_opening: float = 1.0
var _birth_debris: WeakRef


func _ready() -> void:
	add_to_group("BattleTransient")
	z_index = 6
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if not RenderingServer.frame_pre_draw.is_connected(_update_copy_region):
		RenderingServer.frame_pre_draw.connect(_update_copy_region)


func configure(owner: ball, id: int, points: PackedVector2Array, branches: Array, anchor: Vector2, lifetime: float) -> void:
	_owner_ref = weakref(owner) if owner != null else null
	rift_id = id
	_points = points
	_branches = branches
	landing = anchor
	_life = maxf(lifetime, 0.5)
	_age = 0.0
	_closed = false
	_reserved = false
	_reserve_elapsed = 0.0
	_close_elapsed = 0.0
	_rebuild_visual()
	_sync_visual()
	_spawn_birth_debris()
	UNION.register_aperture(self)


func is_open() -> bool:
	return not _closed and not _reserved and _age < _life and is_inside_tree() and not is_queued_for_deletion()


func is_mature() -> bool:
	return _age >= maxf(opening_time, 0.001)


func can_transit() -> bool:
	# Keep is_open() as lifecycle/capacity membership: an opening rift must not
	# be pruned before it has had time to mature.
	return is_open() and is_mature()


func reserve_transit(confirmed_replay: bool = false) -> bool:
	# The authority decides maturity. A remote visual clock may lag behind the
	# reliable action packet; only replicas may reserve that confirmed replay.
	var owner: Variant = _owner_ref.get_ref() if _owner_ref != null else null
	var replay: bool = confirmed_replay and is_instance_valid(owner) and not owner.is_multiplayer_authority()
	if not is_open() or (not is_mature() and not replay):
		return false
	_reserved_width = _closure_factor()
	_reserved = true # No second dodge charge, but do not shut on an emerging body.
	_reserve_elapsed = 0.0
	return true


func is_reserved() -> bool:
	return _reserved and not _closed and not is_queued_for_deletion()


func remaining() -> float:
	return maxf(_life - _age, 0.0)


func consume() -> void:
	_begin_close()


func close_quietly() -> void:
	_begin_close()


func _begin_close() -> void:
	if _closed:
		return
	_close_from = _closure_factor()
	_close_opening = _opening_factor()
	var debris: Variant = _birth_debris.get_ref() if _birth_debris != null else null
	if is_instance_valid(debris): debris.call("stop_emitting", _age)
	_reserved = false
	_close_elapsed = 0.0
	_closed = true # 立刻停止可用性，但收口动画不停顿/不淡出。
	set_process(true)
	_sync_visual()
	if _close_from <= 0.000001:
		queue_free()


func _opening_factor() -> float:
	if _closed: return _close_opening
	var t: float = clampf(_age / maxf(opening_time, 0.001), 0.0, 1.0)
	return 1.0 - pow(1.0 - t, maxf(opening_ease, 0.01)) # Visible gradual tearing, fixed star coordinates.


func opening_age_for_progress(progress: float) -> float:
	# Exact inverse for floor-chip timing; small rain cracks retain their own old curve.
	return maxf(opening_time, 0.001) * (1.0 - pow(1.0 - clampf(progress, 0.0, 1.0), 1.0 / maxf(opening_ease, 0.01)))


func _closure_factor() -> float:
	if _closed:
		return _close_from * (1.0 - smoothstep(0.0, CONSUME_CLOSE_TIME, _close_elapsed))
	if _reserved:
		return _reserved_width
	return 1.0 - smoothstep(0.0, 1.0, clampf(_age / maxf(_life, 0.01), 0.0, 1.0))


func _process(delta: float) -> void:
	if Game.now_stop_state or get_tree().paused:
		return
	var step: float = maxf(delta, 0.0)
	if _closed:
		_age += step
		_close_elapsed += step
		_sync_visual()
		if _close_elapsed >= CONSUME_CLOSE_TIME:
			queue_free()
		return
	if _owner_ref != null:
		var owner: Variant = _owner_ref.get_ref()
		if not is_instance_valid(owner) or float(owner.get("health")) <= 0.0:
			close_quietly()
			return
	_age += step
	if _reserved:
		_reserve_elapsed += step
		if _reserve_elapsed >= 2.0: # Interrupted/missing owner animation cannot leak a permanent aperture.
			close_quietly()
		_sync_visual()
		return
	if _age >= _life:
		_sync_visual()
		_closed = true
		queue_free()
		return
	_sync_visual()


func _sync_visual() -> void:
	if _rift_material == null:
		return
	var close: float = _closure_factor()
	for material: ShaderMaterial in [_rift_material, _exterior_material, _warp_material]:
		if material != null:
			material.set_shader_parameter("opening_progress", _opening_factor())
			material.set_shader_parameter("opening_feather", OPEN_FEATHER / maxf(_birth_span, 1.0))
	_rift_material.set_shader_parameter("closure", close)
	if _exterior_material != null:
		_exterior_material.set_shader_parameter("closure", close)
		_exterior_material.set_shader_parameter("cosmic_time", _age)
	# 星空只受开口遮罩遮挡：世界坐标、色彩、亮度、不透明度不随闭合改变。
	# 原生星空动画正常播放，暂停时则与战斗一起停下。
	_rift_material.set_shader_parameter("cosmic_time", _age)
	if _warp_material != null:
		_warp_material.set_shader_parameter("closure", close)
		_warp_material.set_shader_parameter("rift_time", _age)


func _rebuild_visual() -> void:
	if not is_instance_valid(_space_copy):
		_space_copy = BackBufferCopy.new()
		_space_copy.name = "SpaceBackBuffer"
		_space_copy.z_as_relative = false
		_space_copy.z_index = 92 # 地图裁剪已完成，不能再污染裁剪用的背景快照。
		add_child(_space_copy)
	if not is_instance_valid(_space_warp):
		_space_warp = MeshInstance2D.new()
		_space_warp.name = "SpaceRefraction"
		_space_warp.z_as_relative = false
		_space_warp.z_index = 93 # 完整人物/场景之后，血条/UI 之前。
		add_child(_space_warp)
	_warp_material = ShaderMaterial.new()
	_warp_material.shader = WARP_SHADER
	_warp_material.set_shader_parameter("warp_strength", WARP_STRENGTH)
	_warp_material.set_shader_parameter("root_half_width", MAIN_W0 * 0.5)
	_space_warp.material = _warp_material
	if not is_instance_valid(_surface):
		_surface = MeshInstance2D.new()
		_surface.name = "CosmicInterior"
		_surface.z_as_relative = false
		_surface.z_index = -1 # 裂口在人物后面，不再用不透明星空切掉人物。
		add_child(_surface)
	_rift_material = ShaderMaterial.new()
	_rift_material.shader = COSMIC_SHADER
	_rift_material.set_shader_parameter("cosmic_atlas", COSMIC_ATLAS)
	_rift_material.set_shader_parameter("linear_output", get_viewport().use_hdr_2d and RenderingServer.get_current_rendering_method() != "gl_compatibility")
	_rift_material.set_shader_parameter("cosmic_origin", _points[0] if not _points.is_empty() else landing)
	_surface.material = _rift_material
	if not is_instance_valid(_exterior_surface):
		_exterior_surface = MeshInstance2D.new()
		_exterior_surface.name = "ExteriorCosmicInterior"
		_exterior_surface.z_as_relative = false
		_exterior_surface.z_index = 91
		add_child(_exterior_surface)
	_exterior_material = _rift_material.duplicate() as ShaderMaterial
	_exterior_material.set_shader_parameter("outside_only", true)
	_exterior_surface.material = _exterior_material
	_exterior_surface.visible = false
	_sync_compositing_depth()

	var cracks: Array[Dictionary] = []
	_has_center_join = false
	if not _points.is_empty():
		for limb: PackedVector2Array in _branches:
			if limb.size() >= 2 and limb[0].distance_to(_points[0]) < 0.01:
				_has_center_join = true
				break
	for bi in range(_branches.size()):
		var limb: PackedVector2Array = _branches[bi]
		cracks.append({"points": limb, "id": bi + 1, "width": _branch_width(limb), "joined_root": _has_center_join})
	# 主断口最后画，覆盖分叉根部的接缝；整个内腔共用世界坐标星空。
	cracks.append({"points": _points, "id": 0, "width": MAIN_W0, "joined_root": _has_center_join})
	if _has_center_join:
		# A short irregular opening joins the arms with AREA, not coincident tips.
		# It uses the same material, star coordinates and geometric closure.
		var center: Vector2 = _points[0]
		var axis: Vector2 = (_points[1] - center).normalized() if _points.size() > 1 else Vector2.RIGHT
		var normal := Vector2(-axis.y, axis.x)
		var core := PackedVector2Array([center - axis * 5.5 - normal * 0.3, center - axis * 2.5 + normal * 0.45, center, center + axis * 2.5 - normal * 0.3, center + axis * 4.5 + normal * 0.15])
		cracks.append({"points": core, "id": CENTER_ID, "width": CENTER_W0, "joined_root": false})
	for crack: Dictionary in cracks:
		crack["samples"] = _crack_samples(crack["points"], int(crack["id"]), float(crack["width"]), 1.0, bool(crack.get("joined_root", false)))
	_prepare_growth(cracks)
	_cached_cracks = cracks
	_sync_segment_masks()
	var interior_arrays: Array = _ribbon_arrays(cracks, HALO_SCALE)
	var warp_arrays: Array = _ribbon_arrays(cracks, WARP_SCALE)
	_surface.mesh = _ribbon_mesh(interior_arrays)
	_exterior_surface.mesh = _surface.mesh
	_space_warp.mesh = _ribbon_mesh(warp_arrays)
	_surface.visible = _surface.mesh != null
	# Godot screen backbuffers do not reliably retain alpha in transparent
	# SubViewports. Keep those previews transparent instead of drawing an opaque
	# refraction rectangle; the actual opaque battle viewport uses the warp.
	_space_warp.visible = _space_warp.mesh != null and not get_viewport().transparent_bg
	if _space_warp.visible:
		var vertices: PackedVector2Array = warp_arrays[Mesh.ARRAY_VERTEX]
		var bounds := Rect2(vertices[0], Vector2.ZERO)
		for vertex: Vector2 in vertices:
			bounds = bounds.expand(vertex)
		# A single shared CanvasItem is rendered into the main window and both
		# full-HD recording viewports. A RECT computed from get_viewport() uses
		# the main window's scale there and samples old background over actors.
		# Each viewport must copy its own finished scene before the refraction.
		_copy_bounds = bounds.grow(WARP_STRENGTH + 2.0)
		_space_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
		_update_copy_region()
	else:
		_space_copy.copy_mode = BackBufferCopy.COPY_MODE_DISABLED


func _prepare_growth(cracks: Array[Dictionary]) -> void:
	var center: Vector2 = _points[0] if not _points.is_empty() else landing
	var maximum: float = 0.0
	for crack: Dictionary in cracks:
		var path: PackedVector2Array = crack["points"]
		var offset: float = 0.0
		if not path.is_empty() and path[0].distance_to(center) > 0.01 and int(crack["id"]) != CENTER_ID:
			# Find the attachment on a principal arm; secondary branches cannot
			# appear as disconnected islands ahead of their parent's growing tip.
			var best: float = INF
			for parent: Dictionary in cracks:
				var parent_path: PackedVector2Array = parent["points"]
				if parent_path.is_empty() or parent_path[0].distance_to(center) > 0.01: continue
				var traveled: float = 0.0
				for i in range(parent_path.size() - 1):
					var ray: Vector2 = parent_path[i + 1] - parent_path[i]
					var fraction: float = clampf((path[0] - parent_path[i]).dot(ray) / maxf(ray.length_squared(), 0.000001), 0.0, 1.0)
					var distance: float = path[0].distance_squared_to(parent_path[i] + ray * fraction)
					if distance < best:
						best = distance
						offset = traveled + ray.length() * fraction
					traveled += ray.length()
		var length: float = _crack_length(path)
		for sample: Dictionary in crack["samples"]:
			var distance: float = offset + float(sample["s"]) * length
			if int(crack["id"]) == CENTER_ID: distance = to_global(sample["ps"]).distance_to(center)
			sample["growth_distance"] = distance
			maximum = maxf(maximum, distance)
	_birth_span = maxf(maximum + OPEN_FEATHER + 0.5, 1.0)
	for crack: Dictionary in cracks:
		for sample: Dictionary in crack["samples"]:
			sample["growth"] = float(sample["growth_distance"]) / _birth_span


func _spawn_birth_debris() -> void:
	var owner: Variant = _owner_ref.get_ref() if _owner_ref != null else null
	var world: Node = get_tree().current_scene
	if not is_instance_valid(owner) or world == null or get_viewport().transparent_bg: return
	var effect: Node2D = BIRTH_DEBRIS.new()
	world.add_child(effect)
	_birth_debris = weakref(effect)
	effect.call("configure", self, _cached_cracks, _birth_span, opening_time)


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_update_copy_region):
		RenderingServer.frame_pre_draw.disconnect(_update_copy_region)


func _update_copy_region() -> void:
	_sync_compositing_depth()
	_update_exterior_regions()
	if _warp_material != null and global_transform != _last_mask_transform:
		_sync_segment_masks()
	if not is_instance_valid(_space_copy) or not is_instance_valid(_space_warp) or not _space_warp.visible:
		return
	# Partial copies need canvas/camera coordinates, not just mesh-local bounds.
	# Correct both CanvasLayer zoom and Camera2D motion; updating immediately
	# before drawing avoids a one-frame stale region when the camera moves.
	# Canvas/camera coordinates are LOGICAL viewport units. With canvas_items
	# stretching (1080x1920 -> 540x960), the backbuffer lives in RENDER pixels.
	# Use stretch, not final/window embedding transform: letterbox offsets
	# are outside the render texture and must not enter a backbuffer rectangle.
	var to_pixels: Transform2D = get_viewport().get_stretch_transform() * get_global_transform_with_canvas()
	var screen_bounds: Rect2 = to_pixels * _copy_bounds
	_space_copy.rect = _space_copy.global_transform.affine_inverse() * screen_bounds


func _sync_compositing_depth() -> void:
	if not is_instance_valid(_surface) or not is_instance_valid(_exterior_surface):
		return
	# World itself is z=-2 in the real game. Absolute -1 would STILL cover
	# actors at effective z=-2, despite looking correct in isolated z=0 tests.
	var ancestor: Node = get_parent()
	var depth: int = 0
	while ancestor != null:
		if ancestor is CanvasLayer or ancestor is Viewport:
			break
		var item: CanvasItem = ancestor as CanvasItem
		if item != null:
			depth += item.z_index
			if not item.z_as_relative:
				break
		ancestor = ancestor.get_parent()
	if depth == _last_draw_depth:
		return
	_last_draw_depth = depth
	_surface.z_index = depth - 1
	_exterior_surface.z_index = depth + 91
	_space_copy.z_index = depth + 92
	_space_warp.z_index = depth + 93


func _update_exterior_regions() -> void:
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
	if regions != _last_outside_rects:
		_last_outside_rects = regions
		_exterior_material.set_shader_parameter("outside_rects", regions)
		_exterior_material.set_shader_parameter("outside_count", count)


func _sync_segment_masks() -> void:
	# Guard every refraction sample against all apertures in this cluster, so
	# a neighbouring branch cannot drag star pixels out into the surrounding air.
	if _warp_material == null:
		return
	var segments := PackedVector4Array()
	var widths := PackedVector2Array()
	var scale_width: float = maxf(global_transform.x.length(), global_transform.y.length())
	var count: int = 0
	for crack: Dictionary in _cached_cracks:
		var samples: Array = crack["samples"]
		for i in range(samples.size() - 1):
			if count >= MAX_MASK_SEGMENTS:
				break
			var a: Vector2 = to_global(samples[i]["p"])
			var b: Vector2 = to_global(samples[i + 1]["p"])
			segments.append(Vector4(a.x, a.y, b.x, b.y))
			widths.append(Vector2(float(samples[i]["w"]), float(samples[i + 1]["w"])) * 0.5 * scale_width)
			count += 1
	segments.resize(MAX_MASK_SEGMENTS)
	widths.resize(MAX_MASK_SEGMENTS)
	_warp_material.set_shader_parameter("aperture_segments", segments)
	_warp_material.set_shader_parameter("aperture_widths", widths)
	_warp_material.set_shader_parameter("segment_count", count)
	_last_mask_transform = global_transform


func _ribbon_arrays(cracks: Array[Dictionary], width_scale: float) -> Array:
	var vertices := PackedVector2Array()
	var offsets := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var hdr_data: bool = get_viewport().use_hdr_2d and RenderingServer.get_current_rendering_method() != "gl_compatibility"
	for crack in cracks:
		# Refraction belongs around the outer cracks, never inside the connecting opening.
		if int(crack["id"]) == CENTER_ID and is_equal_approx(width_scale, WARP_SCALE):
			continue
		var samples: Array = crack["samples"]
		if samples.size() < 2:
			continue
		var first: int = vertices.size()
		for sm: Dictionary in samples:
			var center: Vector2 = sm["p"]
			var radius: float = float(sm["w"]) * 0.5 * width_scale
			if is_equal_approx(width_scale, WARP_SCALE):
				radius = float(sm["w"]) * 0.5 + WARP_REACH * sqrt(maxf(sin(PI * float(sm["s"])), 0.0))
				if float(sm["s"]) <= 0.0 or float(sm["s"]) >= 1.0:
					radius = 0.0
			var offset: Vector2 = (sm["n"] as Vector2) * radius
			vertices.append(center - offset)
			vertices.append(center + offset)
			# UV 保存未闭合时的法向位移，GPU 只缩窄断口，不重新生成/抖动网格。
			offsets.append(-offset)
			offsets.append(offset)
			var width_data: float = clampf(float(sm["w"]) / MAIN_W0, 0.0, 1.0)
			var growth: float = float(sm.get("growth", 0.0))
			# HDR Canvas converts vertex RGB from sRGB to linear before the custom
			# shader. Encode this DATA channel so path distance stays linear too.
			if hdr_data:
				growth = Color(growth, growth, growth).linear_to_srgb().g
			colors.append(Color(0, growth, 1, width_data))
			colors.append(Color(1, growth, 1, width_data))
		for si in range(samples.size() - 1):
			var a: int = first + si * 2
			indices.append_array(PackedInt32Array([a, a + 1, a + 2, a + 2, a + 1, a + 3]))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = offsets
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


func _ribbon_mesh(arrays: Array) -> ArrayMesh:
	if (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
		return null
	var mesh := ArrayMesh.new()
	# 显式三角带可容忍折返/反射；不对可能自交的长多边形做耳切三角化。
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh



func _branch_width(limb: PackedVector2Array) -> float:
	if limb.size() < 2:
		return 0.0
	var total: float = _crack_length(_points)
	var traveled: float = 0.0
	var nearest_s: float = 0.0
	var nearest_d: float = INF
	for i in range(_points.size() - 1):
		var segment: Vector2 = _points[i + 1] - _points[i]
		var length: float = segment.length()
		var along: float = clampf((limb[0] - _points[i]).dot(segment) / maxf(segment.length_squared(), 0.000001), 0.0, 1.0)
		var distance: float = limb[0].distance_squared_to(_points[i] + segment * along)
		if distance < nearest_d:
			nearest_d = distance
			nearest_s = (traveled + length * along) / maxf(total, 0.001)
		traveled += length
	# 越靠主缝尾部的分叉越细，避免细尾上突然长出粗枝。
	var parent_width: float = MAIN_W0 * pow(maxf(1.0 - nearest_s, 0.0), 1.3)
	return minf(clampf(_crack_length(limb) * 0.055, 0.7, 2.4), parent_width * 0.65)


func _crack_samples(pts: PackedVector2Array, crack_idx: int, w0: float, close: float, joined_root: bool = false) -> Array:
	var samples: Array = []
	var total: float = _crack_length(pts)
	if pts.size() < 2 or total < 0.001:
		return samples
	var centers := PackedVector2Array()
	var fracs := PackedFloat32Array()
	var traveled: float = 0.0
	for i in range(pts.size() - 1):
		var segment_length: float = pts[i].distance_to(pts[i + 1])
		if segment_length < 0.0001:
			continue
		var steps: int = maxi(1, int(ceil(segment_length / SAMPLE_STEP)))
		for step in range(steps):
			var f: float = float(step) / float(steps)
			centers.append(to_local(pts[i].lerp(pts[i + 1], f)))
			fracs.append(clampf((traveled + segment_length * f) / total, 0.0, 1.0))
		traveled += segment_length
	# 末端永远保留；不能因采样间距太短而漏掉真正的零宽尖端。
	centers.append(to_local(pts[pts.size() - 1]))
	fracs.append(1.0)
	for si in range(centers.size()):
		var previous: Vector2 = centers[maxi(si - 1, 0)]
		var following: Vector2 = centers[mini(si + 1, centers.size() - 1)]
		var tangent: Vector2 = following - previous
		if tangent.length_squared() < 0.0001:
			tangent = following - centers[si]
		if tangent.length_squared() < 0.0001:
			tangent = centers[si] - previous
		tangent = tangent.normalized() if tangent.length_squared() >= 0.0001 else Vector2.RIGHT
		var normal := Vector2(-tangent.y, tangent.x)
		var s: float = fracs[si]
		# 两端都是尖点，中段有不规则张口与收束；不是定宽线/长三角形。
		var u: float = s * 5.0
		var knot: int = int(floor(u))
		var rough_a: float = 0.65 + 0.35 * _hash01(rift_id, crack_idx + 11, knot, 19)
		var rough_b: float = 0.65 + 0.35 * _hash01(rift_id, crack_idx + 11, knot + 1, 19)
		var pinch: float = lerpf(rough_a, rough_b, smoothstep(0.0, 1.0, u - floor(u)))
		var aperture: float = clampf(pow(maxf(sin(PI * s), 0.0), 0.62) * pow(maxf(1.0 - s, 0.0), 0.46) / 0.76, 0.0, 1.0)
		if joined_root:
			aperture = lerpf(0.70, aperture, smoothstep(0.0, 0.22, s))
		var width: float = maxf(w0, 0.0) * aperture * pinch * clampf(close, 0.0, 1.0)
		if (s <= 0.0 and not joined_root) or s >= 1.0:
			width = 0.0
		var jag: float = (_hash01(rift_id, crack_idx + 1, si, 7) - 0.5) * width * 0.18
		if (joined_root and si == 0) or crack_idx == CENTER_ID:
			jag = 0.0 # Joined roots must not drift apart while the aperture closes.
		samples.append({"ps": centers[si], "p": centers[si] + normal * jag, "s": s, "n": normal, "w": width})
	return samples


func _crack_length(pts: PackedVector2Array) -> float:
	var total: float = 0.0
	for i in range(pts.size() - 1):
		total += pts[i].distance_to(pts[i + 1])
	return total


func _hash01(a: int, b: int, c: int, d: int) -> float:
	var h: int = abs(a * 73856093 ^ b * 19349663 ^ c * 83492791 ^ d * 83492791)
	return float(h % 1000) / 1000.0
