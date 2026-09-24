extends Node
# All apertures on the same canvas share their *currently visible* triangle masks.
# This is a coverage union, not draw-order layering: internal rims disappear while
# the original meshes retain obstacle clipping, camera transforms and depth rules.
# Float textures avoid uniform-array truncation in dense rain / long pierce paths.
const GROUP: StringName = &"HeavenfallUnionCoordinator"
const HALO: float = 1.45
var _members: Array[WeakRef] = []
var _cache: Dictionary = {}
var _clock: float = 0.0

static func register_aperture(aperture: Node2D) -> void:
	var viewport: Viewport = aperture.get_viewport()
	for coordinator: Node in aperture.get_tree().get_nodes_in_group(GROUP):
		if coordinator.get_parent() == viewport:
			coordinator.call("register_member", aperture)
			return
	var coordinator := Node.new()
	coordinator.set_script(load("res://scripts/characters/我的世界/new6/heavenfall_union.gd"))
	coordinator.name = "HeavenfallApertureUnion"
	viewport.add_child(coordinator)
	coordinator.call("register_member", aperture)

func _ready() -> void:
	add_to_group(GROUP)
	RenderingServer.frame_pre_draw.connect(_sync)

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_sync):
		RenderingServer.frame_pre_draw.disconnect(_sync)

func register_member(member: Node2D) -> void:
	for reference: WeakRef in _members:
		if reference.get_ref() == member: return
	_members.append(weakref(member))

func _process(delta: float) -> void:
	if not Game.now_stop_state and not get_tree().paused:
		_clock += maxf(delta, 0.0)

func _parameter(material: ShaderMaterial, key: StringName, fallback: Variant) -> Variant:
	var value: Variant = material.get_shader_parameter(key)
	return fallback if value == null else value

func _geometry(member: Node2D) -> Dictionary:
	var surface: MeshInstance2D = member.get("_surface")
	if not is_instance_valid(surface) or surface.mesh == null or not surface.is_visible_in_tree(): return {}
	var material: ShaderMaterial = surface.material as ShaderMaterial
	if material == null: return {}
	var close: float = _parameter(material, &"closure", 1.0)
	var opening: float = _parameter(material, &"opening_progress", 1.0)
	var feather: float = maxf(_parameter(material, &"opening_feather", 0.05), 0.0001)
	var sample_life: bool = _parameter(material, &"sample_life_enabled", false)
	var sample_time: float = _parameter(material, &"sample_time", 0.0)
	var transform: Transform2D = surface.global_transform
	var signature: Array = [surface.mesh, transform, close, opening, feather, sample_life, sample_time]
	var id: int = member.get_instance_id()
	var record: Dictionary = _cache.get(id, {})
	if record.get("signature", []) == signature: return record
	var hdr: bool = member.get_viewport().use_hdr_2d and RenderingServer.get_current_rendering_method() != "gl_compatibility"
	var vertices: PackedVector2Array = record.get("vertices", PackedVector2Array())
	var offsets: PackedVector2Array = record.get("offsets", PackedVector2Array())
	var indices: PackedInt32Array = record.get("indices", PackedInt32Array())
	var growth: PackedFloat32Array = record.get("growth", PackedFloat32Array())
	var edges: PackedFloat32Array = record.get("edges", PackedFloat32Array())
	var widths: PackedFloat32Array = record.get("widths", PackedFloat32Array())
	# Mesh attributes and sRGB decoding are immutable between mesh rebuilds.
	# Closure animates every frame; decoding every vertex on every closure step
	# was the dominant CPU cost in multi-rift offline recording.
	if record.get("mesh") != surface.mesh or record.get("hdr") != hdr:
		var arrays: Array = surface.mesh.surface_get_arrays(0)
		vertices = arrays[Mesh.ARRAY_VERTEX]
		offsets = arrays[Mesh.ARRAY_TEX_UV]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		indices = arrays[Mesh.ARRAY_INDEX]
		growth = PackedFloat32Array()
		edges = PackedFloat32Array()
		widths = PackedFloat32Array()
		for i in range(vertices.size()):
			growth.append(colors[i].srgb_to_linear().g if hdr else colors[i].g)
			edges.append((colors[i].r * 2.0 - 1.0) * HALO)
			widths.append(offsets[i].length() / HALO)
	var data := PackedColorArray()
	var origin: Vector2 = _parameter(material, &"cosmic_origin", Vector2.ZERO)
	var direction: Vector2 = _parameter(material, &"sample_direction", Vector2.RIGHT)
	var speed: float = maxf(_parameter(material, &"sample_speed", 620.0), 1.0)
	var ramp: float = maxf(_parameter(material, &"sample_open_ramp", 0.03), 0.0001)
	var hold: float = _parameter(material, &"sample_hold_time", 0.12)
	var shutting: float = maxf(_parameter(material, &"sample_close_time", 0.16), 0.0001)
	for i in range(vertices.size()):
		var g: float = growth[i]
		var aperture: float = close * smoothstep(0.0, feather, opening - g)
		if sample_life:
			var center: Vector2 = transform * (vertices[i] - offsets[i])
			var age: float = sample_time - maxf((center - origin).dot(direction), 0.0) / speed
			aperture *= minf(smoothstep(0.0, ramp, age), 1.0 - smoothstep(ramp + hold, ramp + hold + shutting, age))
		var point: Vector2 = transform * (vertices[i] - offsets[i] * (1.0 - aperture))
		data.append(Color(point.x, point.y, edges[i], widths[i] * aperture))
	var triangles: Array = []
	var bounds := Rect2()
	for i in range(0, indices.size(), 3):
		var a: Color = data[indices[i]]
		var b: Color = data[indices[i + 1]]
		var c: Color = data[indices[i + 2]]
		var pa := Vector2(a.r, a.g)
		var pb := Vector2(b.r, b.g)
		var pc := Vector2(c.r, c.g)
		if absf((pb - pa).cross(pc - pa)) < 0.000001: continue
		var rect := Rect2(pa, Vector2.ZERO).expand(pb).expand(pc)
		bounds = rect if triangles.is_empty() else bounds.merge(rect)
		triangles.append({"rect": rect, "data": PackedColorArray([a, b, c, Color(growth[indices[i]], growth[indices[i + 1]], growth[indices[i + 2]], opening)])})
	record = {"signature": signature, "triangles": triangles, "bounds": bounds, "canvas": member.get_canvas(), "texture": record.get("texture"), "pixels": record.get("pixels", PackedByteArray()), "mesh": surface.mesh, "hdr": hdr, "vertices": vertices, "offsets": offsets, "indices": indices, "growth": growth, "edges": edges, "widths": widths}
	_cache[id] = record
	return record

func _sync() -> void:
	var alive: Array[WeakRef] = []
	var nodes: Array[Node2D] = []
	var geometry: Array[Dictionary] = []
	var live_ids: Dictionary = {}
	for reference: WeakRef in _members:
		var member: Node2D = reference.get_ref() as Node2D
		if not is_instance_valid(member) or member.is_queued_for_deletion(): continue
		alive.append(reference)
		live_ids[member.get_instance_id()] = true
		var record: Dictionary = _geometry(member)
		if record.is_empty(): continue
		nodes.append(member)
		geometry.append(record)
	_members = alive
	for id: int in _cache.keys():
		if not live_ids.has(id): _cache.erase(id)
	# Keep one cheap coordinator per viewport; no references keep dead rifts alive.
	for i in range(nodes.size()):
		var record: Dictionary = geometry[i]
		var triangles: Array = []
		var shared: bool = false
		var bounds: Rect2 = record["bounds"]
		for j in range(nodes.size()):
			if geometry[j]["canvas"] != record["canvas"]: continue
			if not bounds.intersects(geometry[j]["bounds"], true): continue
			for triangle: Dictionary in geometry[j]["triangles"]:
				if bounds.intersects(triangle["rect"], true):
					triangles.append(triangle["data"])
					shared = shared or i != j
		var count: int = triangles.size()
		# Multiple columns of rows keep even very dense effects below GPU texture limits.
		var columns: int = maxi(1, int(ceil(float(count) / 1024.0)))
		var rows: int = maxi(1, mini(count, 1024))
		var image := Image.create(columns * 4, rows, false, Image.FORMAT_RGBAF)
		for k in range(count):
			for v in range(4): image.set_pixel((k / rows) * 4 + v, k % rows, triangles[k][v])
		var pixels: PackedByteArray = image.get_data()
		var texture: ImageTexture = record.get("texture")
		if texture == null or texture.get_size() != Vector2(image.get_size()):
			texture = ImageTexture.create_from_image(image)
		elif record["pixels"] != pixels:
			texture.update(image)
		record["texture"] = texture
		record["pixels"] = pixels
		var surface: MeshInstance2D = nodes[i].get("_surface")
		var exterior: MeshInstance2D = nodes[i].get("_exterior_surface")
		var materials: Array[ShaderMaterial] = [surface.material as ShaderMaterial, exterior.material as ShaderMaterial]
		var warp: MeshInstance2D = nodes[i].get_node_or_null("SpaceRefraction") as MeshInstance2D
		if warp != null: materials.append(warp.material as ShaderMaterial)
		for material: ShaderMaterial in materials:
			material.set_shader_parameter("union_triangles", texture)
			material.set_shader_parameter("union_count", count)
			if material != (warp.material if warp != null else null):
				material.set_shader_parameter("union_time", _clock if shared else -1.0)
