extends Node2D
# Visual-only transit. The physics body moves once, after the sprite leaves the
# REAL viewport; no collision shape is stretched or flown out of the arena.
signal crossed_screen
signal recovered
const WHITE_SHADER: Shader = preload("res://shaders/heavenfall_transit.gdshader")
const COMPRESS_TIME: float = 0.035
const RISE_TIME: float = 0.075
const EXIT_HOLD: float = 0.017
const EMERGE_TIME: float = 0.045
const RECOVER_TIME: float = 0.11
const EXIT_AT: float = COMPRESS_TIME + RISE_TIME + EXIT_HOLD
const RECOVER_AT: float = EXIT_AT + EMERGE_TIME
const TOTAL_TIME: float = RECOVER_AT + RECOVER_TIME
const THIN: Vector2 = Vector2(0.14, 2.8)

var origin: Vector2
var target: Vector2
var opening: Vector2
var elapsed: float = 0.0
var crossed: bool = false
var finished: bool = false
var sprite: Sprite2D
var white_material: ShaderMaterial
var pose_scale: Vector2 = Vector2.ONE
var last_exit_bounds: Rect2
var _source: WeakRef
var _basis: Transform2D
var _visual_offset: Vector2
var _hidden: Array[Dictionary] = []


func setup(source: ball, from: Vector2, to: Vector2, aperture: Vector2) -> void:
	_source = weakref(source)
	origin = from
	target = to
	opening = aperture
	add_to_group("BattleTransient")
	z_as_relative = false
	z_index = 98 # Above the world mask, below health/UI: the launch really exits the screen.
	global_transform = Transform2D.IDENTITY
	var original: Sprite2D = source.image as Sprite2D
	sprite = Sprite2D.new()
	sprite.name = "WhiteTransitBody"
	sprite.texture = original.texture
	sprite.centered = original.centered
	sprite.offset = original.offset
	sprite.texture_filter = original.texture_filter
	sprite.flip_h = original.flip_h
	sprite.flip_v = original.flip_v
	add_child(sprite)
	_basis = original.global_transform
	_visual_offset = _basis.origin - source.global_position
	_basis.origin = Vector2.ZERO
	white_material = ShaderMaterial.new()
	white_material.shader = WHITE_SHADER
	sprite.material = white_material
	# Modulate, not self_modulate: the shared poison tint owns self_modulate.
	# Do not toggle synchronized Image.visible or alter any original shader/scale.
	for item: CanvasItem in [source.graphics, source.health_bar, source.get_node_or_null("CharacterGroundShadow"), source.get_node_or_null("Status_Image")]:
		if is_instance_valid(item):
			_hidden.append({"ref": weakref(item), "modulate": item.modulate})
			var hidden_color: Color = item.modulate
			hidden_color.a = 0.0
			item.modulate = hidden_color
	sync_pose()


func _screen_matrix() -> Transform2D:
	# Stretch is required for portrait render scale. Final transform would add
	# letterbox/window offsets that do not belong to the viewport texture.
	return get_viewport().get_stretch_transform() * get_canvas_transform()


func _stretch(multiplier: Vector2) -> Transform2D:
	var screen: Transform2D = _screen_matrix()
	var axes := Transform2D(screen.x.normalized(), screen.y.normalized(), Vector2.ZERO)
	return axes.affine_inverse() * Transform2D(Vector2(multiplier.x, 0), Vector2(0, multiplier.y), Vector2.ZERO) * axes


func _up() -> Vector2:
	return _screen_matrix().affine_inverse().basis_xform(Vector2.UP).normalized()


func _half_height() -> float:
	var view: Transform2D = _screen_matrix()
	var projected: Transform2D = view * _stretch(THIN) * _basis
	projected.origin = Vector2.ZERO
	var bounds: Rect2 = projected * sprite.get_rect()
	var pixels_per_unit: float = view.basis_xform(_up()).length()
	return maxf(maxf(absf(bounds.position.y), absf(bounds.end.y)) / maxf(pixels_per_unit, 0.001), 1.0)


func exit_position() -> Vector2:
	var screen: Transform2D = _screen_matrix()
	var projected: Transform2D = screen * _stretch(THIN) * _basis
	projected.origin = Vector2.ZERO
	var bounds: Rect2 = projected * sprite.get_rect()
	var start: Vector2 = screen * (origin + _visual_offset)
	return screen.affine_inverse() * Vector2(start.x, -bounds.end.y - 24.0) - _visual_offset


func _process(_delta: float) -> void:
	# The owner advances one battle clock on each peer; rendering may be faster.
	if _source == null or not is_instance_valid(_source.get_ref()):
		restore()
		queue_free()
		return
	if not finished:
		sync_pose()


func advance(delta: float) -> void:
	if finished:
		return
	elapsed = minf(elapsed + maxf(delta, 0.0), TOTAL_TIME)
	if not crossed and elapsed >= EXIT_AT:
		# Record the actual final departure rectangle, including pan/zoom/stretch.
		_set_pose(exit_position(), THIN, 1.0, false)
		last_exit_bounds = (_screen_matrix() * sprite.global_transform) * sprite.get_rect()
		crossed = true
		crossed_screen.emit()
		if finished: return # Owner may cancel if the landing became blocked.
	sync_pose()
	if elapsed >= TOTAL_TIME:
		finished = true
		recovered.emit()


func sync_pose() -> void:
	if not is_instance_valid(sprite):
		return
	var source: Variant = _source.get_ref() if _source != null else null
	if is_instance_valid(source) and source.image is Sprite2D:
		sprite.texture = source.image.texture # Keep the nine native bow frames playing.
	var point: Vector2 = origin
	var whitening: float = 1.0
	var clip: bool = false
	pose_scale = THIN
	if elapsed < COMPRESS_TIME:
		var p: float = smoothstep(0.0, COMPRESS_TIME, elapsed)
		pose_scale = Vector2.ONE.lerp(THIN, p)
		whitening = p
	elif elapsed < COMPRESS_TIME + RISE_TIME:
		var p: float = (elapsed - COMPRESS_TIME) / RISE_TIME
		point = origin.lerp(exit_position(), pow(p, 2.2))
	elif elapsed < EXIT_AT:
		point = exit_position()
	elif elapsed < RECOVER_AT:
		var p: float = (elapsed - EXIT_AT) / EMERGE_TIME
		point = opening + _up() * lerpf(-_half_height(), _half_height(), p)
		clip = true # Reveal from the mouth, not a full sprite popping in beside it.
	else:
		var p: float = clampf((elapsed - RECOVER_AT) / RECOVER_TIME, 0.0, 1.0)
		var spring: float = 1.0 - exp(-7.0 * p) * cos(11.0 * p)
		if p >= 1.0: spring = 1.0
		pose_scale = THIN.lerp(Vector2.ONE, spring)
		point = (opening + _up() * _half_height()).lerp(target, 1.0 - pow(1.0 - p, 3.0))
		whitening = 1.0 - smoothstep(0.0, 0.70, p)
	_set_pose(point, pose_scale, whitening, clip)


func _set_pose(point: Vector2, multiplier: Vector2, whitening: float, clip: bool) -> void:
	var pose: Transform2D = _stretch(multiplier) * _basis
	pose.origin = point + _visual_offset
	sprite.global_transform = pose
	white_material.set_shader_parameter("whitening", whitening)
	white_material.set_shader_parameter("clip_opening", clip)
	white_material.set_shader_parameter("opening", opening)
	white_material.set_shader_parameter("emergence_up", _up())


func restore() -> void:
	for entry: Dictionary in _hidden:
		var item: Variant = entry["ref"].get_ref()
		if is_instance_valid(item):
			item.modulate = entry["modulate"]
	_hidden.clear()
	finished = true
	if is_instance_valid(sprite): sprite.hide()


func _exit_tree() -> void:
	restore()
