extends RefCounted
# Hit feedback only. 0 dB is the untouched source level, never a negative baseline.
const MAX_GAIN_DB:float=6.0
static func damage_event(actual:float) -> String:
	if is_nan(actual) or actual<=0.0: return ""
	return "entity.player.attack.crit" if actual>50.0 else "entity.player.hurt"
static func damage_gain(actual:float) -> float:
	if is_nan(actual) or actual<=0.0: return 0.0
	return MAX_GAIN_DB*(1.0-50.0/(50.0+actual))
static func is_hit_event(event:String) -> bool:
	return event in ["entity.player.hurt","entity.player.attack.crit","entity.generic.hurt"]
