extends "res://scripts/effects/我的世界/mc_explosion.gd"
## Compatibility adapter for ghast fireballs; shared MC particles, including outside maps.
func _ready() -> void:
	allow_outside=true
	super._ready()
