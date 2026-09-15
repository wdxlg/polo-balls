extends "res://scripts/training/benchmark_profile_capture.gd"
func _finish() -> void:
	var file:FileAccess = FileAccess.open("res://scripts/training/benchmark_round2_profile.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"signatures":signatures,"frames":frames,"totals":totals},"\t"))
	file.close()
	print("ROUND2_PROFILE_CAPTURED frames=",frames.size()," signatures=",signatures.size())
	server.stop()
	quit()
