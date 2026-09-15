extends "res://scripts/training/benchmark_round2_phases.gd"
var measured_ticks:int = 0
func _initialize() -> void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--steps="):
			Engine.max_physics_steps_per_frame = clampi(int(arg.trim_prefix("--steps=")),1,8)
	super._initialize()
func _physics_begin() -> void:
	if sampling:
		measured_ticks += 1
	super._physics_begin()
func _finish() -> void:
	print("CATCHUP_PROBE ",JSON.stringify({"limit":Engine.max_physics_steps_per_frame,"ticks_per_wall_second":float(measured_ticks)/sample_elapsed,"configured_tick_hz":Engine.physics_ticks_per_second}))
	super._finish()
