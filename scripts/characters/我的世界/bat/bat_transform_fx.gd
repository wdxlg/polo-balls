extends "res://scripts/effects/我的世界/mc_explosion.gd"
## One original circular explosion animation + independently scattered animated smoke.
func _ready() -> void:
	radius = 34.0
	explosion_count = 1
	smoke_count = 16
	play_audio = false
	super._ready()
	add_to_group("MCBatTransformFX")
	# One centered, immediately visible burst; never a disk of multiple explosions.
	var central:Dictionary = particles[0]
	central.delay = 0.0
	central.diameter = 40.0
	central.life = 0.55
	central.start_shade = 1.0
	central.end_shade = 1.0
	central.position3 = Vector3.ZERO
	for i:int in range(1,particles.size()):
		var puff:Dictionary = particles[i]
		puff.diameter = _rng.randf_range(6.0,9.0)
		puff.life = _rng.randf_range(1.0,1.4)
		puff.start_shade = _rng.randf_range(0.55,0.80)
		puff.end_shade = 0.18
	advance_visual(0.0)
