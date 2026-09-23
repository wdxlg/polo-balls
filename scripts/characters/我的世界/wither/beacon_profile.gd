extends RefCounted
## One simulation-time envelope for movement, visible width, collision and threat.
const WARNING:float = 0.6
const FIRING:float = 1.5
const RECOVERY:float = 0.35
const INTERVAL:float = 0.1
const PULSES:int = 15
const DAMAGE:float = 36.0 / PULSES
static func smooth_phase(value:float) -> float:
	var t:float=clampf(value,0.0,1.0)
	return t*t*(3.0-2.0*t)
static func speed_factor(warning:float,firing:float) -> float:
	if warning>0: return lerpf(1.0,0.5,smooth_phase(1.0-warning/WARNING))
	if firing>0: return lerpf(0.5,1.0,smooth_phase(1.0-firing/RECOVERY))
	return 1.0
static func width(body_width:float,warning:float,firing:float) -> float:
	var thin:float=maxf(body_width*0.035,0.35)
	if warning>0: return thin*lerpf(1.0,1.7,smooth_phase(1.0-warning/WARNING))
	if firing<=0: return 0.0
	var elapsed:float=FIRING-firing
	var size:float
	if elapsed<0.08:
		var t:float=clampf(elapsed/0.08,0.0,1.0)
		size=lerpf(thin*1.7,body_width*1.16,1.0-pow(1.0-t,3.0))
	else:
		var t:float=elapsed-0.08
		size=body_width*(0.90+0.26*exp(-10.0*t)*cos(28.0*t))
	return maxf(size,0.0)*(1.0-smooth_phase(1.0-firing/RECOVERY))
static func opacity(warning:float,firing:float) -> float:
	if warning>0: return lerpf(0.45,0.95,smooth_phase(1.0-warning/WARNING))
	if firing>0: return 1.0-smooth_phase(1.0-firing/RECOVERY)
	return 0.0
static func shake(warning:float) -> float:
	return smooth_phase(1.0-warning/WARNING) if warning>0 else 0.0

static func pulse_damage(index:int) -> float:
	# The project's health settlement rounds fractional damage up. Apportion
	# the integer budget (2,2,3,2,3...) so 15 hits stay 36, not 15*ceil(2.4)=45.
	var i:int=clampi(index,0,PULSES-1)
	return floorf(float(i+1)*36.0/PULSES)-floorf(float(i)*36.0/PULSES)
