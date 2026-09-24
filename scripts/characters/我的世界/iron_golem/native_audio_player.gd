extends AudioStreamPlayer2D
# World-owned one-shot: death/landing tails survive actor cleanup and pause safely.
var actor_ref:WeakRef
var follow_actor:bool = false
var stop_with_actor:bool = false
func _ready() -> void:
	_process(0.0)
func _process(_delta:float) -> void:
	stream_paused = get_tree().paused or Game.now_stop_state
	var actor:Node2D = actor_ref.get_ref() as Node2D if actor_ref!=null else null
	if stop_with_actor and (not is_instance_valid(actor) or actor.is_queued_for_deletion() or actor.health<=0):
		stop()
		queue_free()
		return
	if follow_actor and is_instance_valid(actor):
		global_position = actor.global_position
		stream_paused = stream_paused or not actor.is_combat_runtime_active()
