extends "res://scripts/training/benchmark_round2_final.gd"
func _finish() -> void:
	if world.has_meta(&"_performance_knife_snapshot_renderer"):
		var renderer:Node = world.get_meta(&"_performance_knife_snapshot_renderer")
		print("DRAW_COMMAND_CACHE ",JSON.stringify({"recorded_draws":renderer.recorded_draws,"reused_draws":renderer.reused_draws}))
	super._finish()
