extends "res://scripts/characters/我的世界/new6/heavenfall_rift.gd"
# Impact-only miniature fracture: no owner / dodge registration / extra damage.
# Reuse the center-out aperture lifecycle, not the directional pierce zipper.
const IMPACT_LIFE: float = 0.64

func configure_impact(point: Vector2, seed_value: int, radius: float = 10.0) -> void:
	# Independent timing: changing the large impact rift must not slow rain cracks.
	opening_time = 0.15
	opening_ease = 3.0
	add_to_group("HeavenfallRainCrack")
	var rng := RandomNumberGenerator.new()
	rng.seed = maxi(seed_value, 1)
	var count: int = rng.randi_range(5, 6)
	var phase: float = rng.randf_range(0.0, TAU)
	var arms: Array[PackedVector2Array] = []
	for i in range(count):
		var angle: float = phase + TAU * float(i) / float(count) + rng.randf_range(-0.18, 0.18)
		var direction := Vector2.RIGHT.rotated(angle)
		var normal := Vector2(-direction.y, direction.x)
		var reach: float = radius * rng.randf_range(0.72, 1.15)
		var arm := PackedVector2Array([point])
		for k in range(1, 5):
			arm.append(point + direction * reach * float(k) / 4.0 + normal * rng.randf_range(-0.10, 0.10) * reach)
		arms.append(arm)
	var branches: Array = []
	for i in range(1, count): branches.append(arms[i])
	# Irregular secondary forks give a fractured web, not a regular star glyph.
	for i in [0, count / 2]:
		var arm: PackedVector2Array = arms[i]
		var start: Vector2 = arm[2]
		var direction: Vector2 = (arm[3] - arm[1]).normalized().rotated(rng.randf_range(0.6, 1.1))
		branches.append(PackedVector2Array([start, start + direction * radius * 0.22, start + direction.rotated(-0.18) * radius * 0.45]))
	configure(null, seed_value, arms[0], branches, point, IMPACT_LIFE)

func _branch_width(limb: PackedVector2Array) -> float:
	# Tiny primary spokes must not inherit the main path's distant-tail taper.
	return 2.2 if not limb.is_empty() and limb[0].distance_to(_points[0]) < 0.01 else 1.25
