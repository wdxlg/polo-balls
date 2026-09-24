extends "res://scripts/effects/我的世界/重锤落地冲击.gd"
# Same wave, streaks and sampled floor debris; only add combat-pause gating.
func _process(delta:float) -> void:
	if Game.now_stop_state or get_tree().paused: return
	var world:Node = get_tree().current_scene
	if world!=null and world.has_method("is_combat_runtime_active") and not world.is_combat_runtime_active(): return
	super._process(delta)
