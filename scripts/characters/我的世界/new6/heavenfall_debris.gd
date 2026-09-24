extends Node2D
# A few low-parabola chips from the actual floor under each growing crack.
# The existing mace sampler captures terrain/shaders, not actors or cosmic FX.
const FLOOR_SAMPLER: Script = preload("res://scripts/effects/地表渲染采样.gd")
const MIN_COUNT: int = 6
const MAX_COUNT: int = 9
const MIN_HEIGHT: float = 3.0
const MAX_HEIGHT: float = 6.0
var _source: WeakRef
var _elapsed: float = 0.0
var _emit_until: float = INF
var _end_time: float = 0.0
var _sampling: bool = false
var _blocks: Array[Dictionary] = []
var _specs: Array[Dictionary] = []
var _snapshot: Dictionary = {}
var _capture_rect: Rect2


func configure(rift: Node2D, cracks: Array, birth_span: float, _opening_time: float) -> void:
	add_to_group("BattleTransient")
	add_to_group("HeavenfallBirthDebris")
	_source = weakref(rift)
	global_transform = Transform2D.IDENTITY
	z_as_relative = false
	z_index = 96
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if DisplayServer.get_name() == "headless":
		queue_free() # No rendered pixels: never invent a fallback terrain colour.
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = maxi(int(rift.get("rift_id")) * 73519 + 281, 1)
	var arms: Array = []
	for crack: Dictionary in cracks:
		if int(crack["id"]) != -1 and (crack["samples"] as Array).size() >= 2:
			arms.append(crack)
	if arms.is_empty():
		queue_free()
		return
	var count: int = rng.randi_range(MIN_COUNT, MAX_COUNT)
	for i in range(count):
		var crack: Dictionary = arms[i % arms.size()]
		var samples: Array = crack["samples"]
		var index: int = clampi(int(round(rng.randf_range(0.16, 0.77) * float(samples.size() - 1))), 0, samples.size() - 1)
		var sample: Dictionary = samples[index]
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var normal: Vector2 = sample["n"]
		var point: Vector2 = rift.to_global(sample["p"]) + normal * side * (float(sample["w"]) * 0.5 + 0.6)
		var growth: float = clampf(float(sample["growth"]) + 1.5 / maxf(birth_span, 1.0), 0.0, 0.96)
		var delay: float = float(rift.call("opening_age_for_progress", growth))
		_specs.append({"point": point, "delay": delay,
			"landing": point + normal * side * rng.randf_range(3.0, 7.0) + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-0.8, 1.5)),
			"height": rng.randf_range(MIN_HEIGHT, MAX_HEIGHT), "flight": rng.randf_range(0.16, 0.24),
			"size": rng.randf_range(1.2, 2.3), "hold": 0.035, "fade": 0.10})
		if i == 0: _capture_rect = Rect2(point, Vector2.ZERO)
		else: _capture_rect = _capture_rect.expand(point)
	_capture_rect = _capture_rect.grow(3.0)
	var world: Node = get_tree().current_scene
	if world == null:
		queue_free()
		return
	var sampler: Node = world.get_node_or_null("GroundSurfaceSampler")
	if sampler == null:
		sampler = FLOOR_SAMPLER.new()
		sampler.name = "GroundSurfaceSampler"
		world.add_child(sampler)
	_sampling = true
	_snapshot = await sampler.capture(_capture_rect)
	if not is_inside_tree(): return
	_sampling = false
	# Sampling never blocks opening. Join the same clock after GPU readback.
	if is_instance_valid(rift): _elapsed = float(rift.get("_age"))
	_build_blocks()
	if _blocks.is_empty() or _elapsed >= _end_time:
		queue_free()
	queue_redraw()


func _build_blocks() -> void:
	_blocks.clear()
	var image: Image = _snapshot.get("image")
	var rect: Rect2 = _snapshot.get("rect", Rect2())
	if image == null or not rect.has_area(): return
	for spec: Dictionary in _specs:
		var point: Vector2 = spec["point"]
		if not rect.has_point(point): continue # Do not clamp to a distant capture's edge.
		var uv: Vector2 = (point - rect.position) / rect.size
		var pixel := Vector2i(clampi(int(floor(uv.x * image.get_width())), 0, image.get_width() - 1), clampi(int(floor(uv.y * image.get_height())), 0, image.get_height() - 1))
		var colour: Color = image.get_pixelv(pixel)
		if colour.a <= 0.01: continue
		var block: Dictionary = spec.duplicate()
		block["color"] = colour # Exact sampled colour, not a preset grass/wood palette.
		block["sample_pixel"] = pixel
		_blocks.append(block)
		_end_time = maxf(_end_time, float(block["delay"]) + float(block["flight"]) + float(block["hold"]) + float(block["fade"]))


func _process(delta: float) -> void:
	if Game.now_stop_state or get_tree().paused: return
	if _sampling: return
	var source: Variant = _source.get_ref() if _source != null else null
	if is_instance_valid(source): _elapsed = float(source.get("_age"))
	else: _elapsed += maxf(delta, 0.0)
	if _elapsed >= _end_time:
		queue_free()
	queue_redraw()


func stop_emitting(birth_age: float) -> void:
	_emit_until = minf(_emit_until, birth_age) # Already-launched chips finish their low arc.


func particle_pose(block: Dictionary, time: float) -> Dictionary:
	if float(block["delay"]) > _emit_until: return {}
	var age: float = time - float(block["delay"])
	var flight: float = float(block["flight"])
	var end: float = flight + float(block["hold"]) + float(block["fade"])
	if age < 0.0 or age >= end: return {}
	var t: float = clampf(age / flight, 0.0, 1.0)
	var point: Vector2 = (block["point"] as Vector2).lerp(block["landing"], t)
	var height: float = 4.0 * float(block["height"]) * t * (1.0 - t)
	point.y -= height
	var alpha: float = 1.0 - clampf((age - flight - float(block["hold"])) / float(block["fade"]), 0.0, 1.0)
	return {"point": point, "height": height, "alpha": alpha}


func _draw() -> void:
	for block: Dictionary in _blocks:
		var pose: Dictionary = particle_pose(block, _elapsed)
		if pose.is_empty(): continue
		var colour: Color = block["color"]
		colour.a *= float(pose["alpha"])
		var size: float = float(block["size"])
		draw_rect(Rect2((pose["point"] as Vector2) - Vector2.ONE * size * 0.5, Vector2.ONE * size), colour)
