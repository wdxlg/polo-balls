extends "res://scripts/training/benchmark_100.gd"
var first_physics_usec:int = 0
var process_usec:int = 0
var draw_usec:int = 0
var step_count:int = 0
var physics_wall:Array[float] = []
var process_wall:Array[float] = []
var draw_wall:Array[float] = []
var steps:Array[float] = []
func _initialize() -> void:
	physics_frame.connect(_physics_begin)
	process_frame.connect(_process_begin)
	RenderingServer.frame_pre_draw.connect(_draw_begin)
	RenderingServer.frame_post_draw.connect(_draw_end)
	super._initialize()
func _physics_begin() -> void:
	if first_physics_usec == 0:
		first_physics_usec = Time.get_ticks_usec()
	step_count += 1
func _process_begin() -> void:
	process_usec = Time.get_ticks_usec()
	if sampling:
		physics_wall.append(float(process_usec - first_physics_usec) / 1000.0 if first_physics_usec != 0 else 0.0)
		steps.append(float(step_count))
	first_physics_usec = 0
	step_count = 0
func _draw_begin() -> void:
	draw_usec = Time.get_ticks_usec()
	if sampling:
		process_wall.append(float(draw_usec - process_usec) / 1000.0)
func _draw_end() -> void:
	if sampling:
		draw_wall.append(float(Time.get_ticks_usec()-draw_usec) / 1000.0)
func _finish() -> void:
	var result:Dictionary = {}
	for entry:Array in [["physics_wall",physics_wall],["process_wall",process_wall],["render_wall",draw_wall],["physics_steps",steps]]:
		var values:Array[float] = entry[1]
		values.sort()
		result[entry[0]] = {"p50":_percentile(values,0.5),"p95":_percentile(values,0.95)}
	print("FRAME_PHASES ",JSON.stringify(result))
	super._finish()
