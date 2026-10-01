extends RefCounted
const MIN_INTERVAL:float = 0.07
const STILL_RESET:float = 0.25
var _progress:float = 1.0
var _since_step:float = INF
var _still:float = 0.0

static func base_speed(unit:Variant) -> float:
	if not is_instance_valid(unit): return 100.0
	if unit.has_meta("training_boss_base_speed"): return maxf(float(unit.get_meta("training_boss_base_speed")),1.0)
	var props:Variant = unit.get("default_properties")
	if props is Dictionary and props.has("Speed"): return maxf(float(props["Speed"]),1.0)
	var raw:Variant = unit.get("Speed")
	return maxf(float(raw),1.0) if raw != null else 100.0

func tick(moved:float,delta:float,speed_base:float,interval_base:float) -> bool:
	return tick_stride(moved,delta,speed_base*interval_base)

func tick_stride(moved:float,delta:float,stride:float) -> bool:
	_since_step += maxf(delta,0.0)
	if moved <= 0.0:
		_still += maxf(delta,0.0)
		if _still >= STILL_RESET: _progress = 1.0
		return false
	_still = 0.0
	_progress += moved/maxf(stride,1.0)
	if _progress < 1.0 or _since_step < MIN_INTERVAL: return false
	_progress = minf(_progress-1.0,0.99)
	_since_step = 0.0
	return true

func ready_now() -> void:
	_progress = 1.0
	_since_step = INF
