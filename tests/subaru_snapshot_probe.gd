extends Node2D
var owner_ref:Node
var weak_target:WeakRef
var payload:Dictionary = {"phase":2,"trail":[Vector2(1,2),Vector2(3,4)]}
var rng := RandomNumberGenerator.new()
var elapsed:float = 1.25
var ticks:int = 0
func _process(delta:float) -> void:
	elapsed += delta
	ticks += 1

func on_timer_finished() -> void:
	payload.phase = 99
