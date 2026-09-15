extends "res://scripts/training/benchmark_catchup_probe.gd"
func _finish() -> void:
	if world.has_meta(&"_performance_knife_snapshot_renderer"):
		var renderer:Node = world.get_meta(&"_performance_knife_snapshot_renderer")
		print("SNAPSHOT_POOL ",JSON.stringify({"created_canvases":renderer.created_canvases,"reused_records":renderer.reused_snapshots,"idle_records":renderer.idle_snapshots.size(),"active_records":renderer.snapshots.size()}))
	super._finish()
