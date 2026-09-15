extends "res://scripts/training/test_visual_equivalence.gd"
# Exercise cached Transform2D multiplication against Node2D.to_global() with
# nontrivial parent/source transforms, both flips, crops and animated frames.
func _check_pixels(seed_value:int) -> void:
	super._check_pixels(seed_value)
	var old_root:Transform2D = unit.transform
	var old_image:Transform2D = unit.image.transform
	var params:RandomNumberGenerator = RandomNumberGenerator.new()
	params.seed = seed_value + 90000
	for i:int in range(160):
		unit.position = Vector2(params.randf_range(-2000,2000),params.randf_range(-2000,2000))
		unit.rotation = params.randf_range(-PI,PI)
		unit.scale = Vector2(params.randf_range(0.05,3.0),params.randf_range(0.05,3.0))
		unit.image.rotation = params.randf_range(-PI,PI)
		unit.image.skew = params.randf_range(-0.8,0.8)
		unit.image.scale = Vector2(-1.2 if i % 2 else 0.8,1.7)
		var a:RandomNumberGenerator = RandomNumberGenerator.new()
		var b:RandomNumberGenerator = RandomNumberGenerator.new()
		a.seed = seed_value * 1000 + i
		b.seed = a.seed
		var outward:Vector2 = Vector2.RIGHT.rotated(params.randf_range(-PI,PI))
		var radius:float = params.randf_range(1.0,48.0)
		var coverage:float = params.randf()
		var expected:Dictionary = reference.sample(unit,a,i % 2 == 0,outward,radius,coverage)
		var actual:Dictionary = unit._random_hit_effect_visual_sample(b,i % 2 == 0,outward,radius,coverage)
		random_checks += 1
		if expected != actual or a.state != b.state:
			_fail("transformed sample/RNG " + str(seed_value) + ":" + str(i))
	unit.transform = old_root
	unit.image.transform = old_image
