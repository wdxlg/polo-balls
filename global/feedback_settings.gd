extends RefCounted
## Local presentation tuning. Pure validation/curves; never owns combat state or RNG.
const SIMPLE_LABELS:Dictionary = {
	"Feedback_Body_Tiny":"FEEDBACK_SIMPLE_FAINT",
	"Feedback_Body_Light":"FEEDBACK_SIMPLE_LIGHT",
	"Feedback_Body_Strong":"FEEDBACK_SIMPLE_STRONG",
	"Feedback_Focus_MaxZoom":"FEEDBACK_SIMPLE_ZOOM",
	"Feedback_Hitstop_Factor":"FEEDBACK_SIMPLE_SPEED",
	"Feedback_Hitstop_MaxDuration":"FEEDBACK_SIMPLE_TIME",
}
const SPECS:Dictionary = {
	"Feedback_Shake_Low": {"default":10,"min":1,"max":99999,"step":1,"group":"Shaking_Camera","section":"TIERS","unit":""},
	"Feedback_Shake_High": {"default":50,"min":2,"max":100000,"step":1,"group":"Shaking_Camera","section":"TIERS","unit":""},
	"Feedback_Body_Tiny": {"default":0.08,"min":0.01,"max":64,"step":0.01,"group":"Shaking_Camera","section":"BODY","unit":""},
	"Feedback_Body_Light": {"default":0.6,"min":0.01,"max":64,"step":0.01,"group":"Shaking_Camera","section":"BODY","unit":""},
	"Feedback_Body_Strong": {"default":10.0,"min":0.01,"max":64,"step":0.01,"group":"Shaking_Camera","section":"BODY","unit":""},
	"Feedback_Body_Max": {"default":18.0,"min":0.01,"max":128,"step":0.01,"group":"Shaking_Camera","section":"BODY","unit":""},
	"Feedback_Body_Gain": {"default":1.0,"min":0.0,"max":3.0,"step":0.05,"group":"Shaking_Camera","section":"BODY","unit":"x"},
	"Feedback_Camera_Tiny": {"default":0.08,"min":0.01,"max":64,"step":0.01,"group":"Shaking_Camera","section":"CAMERA","unit":""},
	"Feedback_Camera_Light": {"default":0.75,"min":0.01,"max":64,"step":0.01,"group":"Shaking_Camera","section":"CAMERA","unit":""},
	"Feedback_Camera_Strong": {"default":6.0,"min":0.01,"max":64,"step":0.01,"group":"Shaking_Camera","section":"CAMERA","unit":""},
	"Feedback_Camera_Max": {"default":10.0,"min":0.01,"max":128,"step":0.01,"group":"Shaking_Camera","section":"CAMERA","unit":""},
	"Feedback_Camera_Gain": {"default":1.0,"min":0.0,"max":3.0,"step":0.05,"group":"Shaking_Camera","section":"CAMERA","unit":"x"},
	"Feedback_Shake_Growth": {"default":60.0,"min":1,"max":10000,"step":1,"group":"Shaking_Camera","section":"ENVELOPE","unit":""},
	"Feedback_Shake_Curve": {"default":0.75,"min":0.1,"max":3.0,"step":0.05,"group":"Shaking_Camera","section":"ENVELOPE","unit":""},
	"Feedback_Shake_MinDuration": {"default":0.1,"min":0.01,"max":2.0,"step":0.01,"group":"Shaking_Camera","section":"ENVELOPE","unit":"s"},
	"Feedback_Shake_MaxDuration": {"default":0.28,"min":0.01,"max":2.0,"step":0.01,"group":"Shaking_Camera","section":"ENVELOPE","unit":"s"},
	"Feedback_Shake_Frequency": {"default":18.0,"min":1.0,"max":60.0,"step":1,"group":"Shaking_Camera","section":"ENVELOPE","unit":"Hz"},
	"Feedback_Focus_Damage": {"default":40.0,"min":1,"max":100000,"step":1,"group":"High_Damage_Feedback","section":"FOCUS","unit":""},
	"Feedback_Focus_HealthPercent": {"default":25.0,"min":0,"max":100,"step":1,"group":"High_Damage_Feedback","section":"FOCUS","unit":"%"},
	"Feedback_Focus_ThresholdCap": {"default":75.0,"min":1,"max":100000,"step":1,"group":"High_Damage_Feedback","section":"FOCUS","unit":""},
	"Feedback_Focus_MinZoom": {"default":1.06,"min":1.0,"max":2.0,"step":0.01,"group":"High_Damage_Feedback","section":"FOCUS","unit":"x"},
	"Feedback_Focus_MaxZoom": {"default":1.18,"min":1.0,"max":2.0,"step":0.01,"group":"High_Damage_Feedback","section":"FOCUS","unit":"x"},
	"Feedback_Focus_In": {"default":0.08,"min":0.01,"max":2.0,"step":0.01,"group":"High_Damage_Feedback","section":"FOCUS","unit":"s"},
	"Feedback_Focus_Hold": {"default":0.07,"min":0.0,"max":2.0,"step":0.01,"group":"High_Damage_Feedback","section":"FOCUS","unit":"s"},
	"Feedback_Focus_Out": {"default":0.3,"min":0.01,"max":3.0,"step":0.01,"group":"High_Damage_Feedback","section":"FOCUS","unit":"s"},
	"Feedback_Focus_Cooldown": {"default":0.7,"min":0.0,"max":10.0,"step":0.05,"group":"High_Damage_Feedback","section":"FOCUS","unit":"s"},
	"Feedback_Hitstop_Damage": {"default":12.0,"min":1,"max":100000,"step":1,"group":"High_Damage_Feedback","section":"HITSTOP","unit":""},
	"Feedback_Hitstop_HealthPercent": {"default":6.0,"min":0.0,"max":100.0,"step":1,"group":"High_Damage_Feedback","section":"HITSTOP","unit":"%"},
	"Feedback_Hitstop_Factor": {"default":0.12,"min":0.01,"max":1.0,"step":0.01,"group":"High_Damage_Feedback","section":"HITSTOP","unit":"x"},
	"Feedback_Hitstop_MinDuration": {"default":0.025,"min":0.01,"max":0.5,"step":0.005,"group":"High_Damage_Feedback","section":"HITSTOP","unit":"s"},
	"Feedback_Hitstop_MaxDuration": {"default":0.09,"min":0.01,"max":0.5,"step":0.005,"group":"High_Damage_Feedback","section":"HITSTOP","unit":"s"},
	"Feedback_Hitstop_Cooldown": {"default":0.35,"min":0.0,"max":10.0,"step":0.05,"group":"High_Damage_Feedback","section":"HITSTOP","unit":"s"},
}

static func number(settings:Dictionary,suffix:String) -> float:
	var key:String = suffix if suffix.begins_with("Feedback_") else "Feedback_"+suffix
	var spec:Dictionary = SPECS[key]
	var raw:Variant = settings.get(key,spec.default)
	if not (raw is float or raw is int) or not is_finite(float(raw)): return float(spec.default)
	return clampf(float(raw),float(spec.min),float(spec.max))

## 分级顿挫之前的旧默认值。四项都还是旧默认（玩家没动过）时迁移到新的分级默认值。
const LEGACY_HITSTOP_DEFAULTS:Dictionary = {"Feedback_Hitstop_Damage":20.0,"Feedback_Hitstop_HealthPercent":18.0,"Feedback_Hitstop_MinDuration":0.035,"Feedback_Hitstop_MaxDuration":0.06}

static func _migrate_legacy_hitstop(settings:Dictionary) -> void:
	for key:String in LEGACY_HITSTOP_DEFAULTS:
		var raw:Variant = settings.get(key)
		if not (raw is float or raw is int) or not is_equal_approx(float(raw),float(LEGACY_HITSTOP_DEFAULTS[key])): return
	for key:String in LEGACY_HITSTOP_DEFAULTS: settings[key] = SPECS[key].default

static func normalize(settings:Dictionary) -> void:
	_migrate_legacy_hitstop(settings)
	for key:String in SPECS: settings[key] = number(settings,key)
	settings.Feedback_Shake_High = maxf(settings.Feedback_Shake_High,settings.Feedback_Shake_Low+1.0)
	for channel:String in ["Body","Camera"]:
		var previous:float = 0.0
		var names:Array[String] = ["Tiny","Light","Strong","Max"]
		for index:int in names.size():
			var key:String = "Feedback_"+channel+"_"+names[index]
			settings[key] = clampf(float(settings[key]),previous+0.01,float(SPECS[key].max)-float(maxi(2-index,0))*0.01)
			previous = float(settings[key])
	for pair:Array in [["Shake_MinDuration","Shake_MaxDuration"],["Focus_Damage","Focus_ThresholdCap"],["Focus_MinZoom","Focus_MaxZoom"],["Hitstop_MinDuration","Hitstop_MaxDuration"]]:
		settings["Feedback_"+str(pair[1])] = maxf(number(settings,pair[0]),number(settings,pair[1]))

static func reset_group(settings:Dictionary,group:String) -> void:
	for key:String in SPECS:
		if str(SPECS[key].group)==group: settings[key] = SPECS[key].default
	normalize(settings)

static func tier(damage:float,settings:Dictionary) -> int:
	if damage <= number(settings,"Shake_Low"): return 0
	return 1 if damage <= number(settings,"Shake_High") else 2

static func amplitude(damage:float,settings:Dictionary,channel:String) -> float:
	if not is_finite(damage) or damage <= 0.0: return 0.0
	var low:float = number(settings,"Shake_Low")
	var high:float = maxf(number(settings,"Shake_High"),low+1.0)
	var tiny:float = number(settings,channel+"_Tiny")
	var light:float = number(settings,channel+"_Light")
	var strong:float = number(settings,channel+"_Strong")
	var ceiling:float = number(settings,channel+"_Max")
	var exponent:float = number(settings,"Shake_Curve")
	var result:float
	if damage <= low:
		result = tiny*pow(damage/low,exponent)
	elif damage <= high:
		result = lerpf(tiny,light,pow((damage-low)/(high-low),exponent))
	else:
		# Asymptotic growth retains differences between large hits, rather than clipping early.
		var extra:float = damage-high
		var growth:float = number(settings,"Shake_Growth")
		# Leave perceptible growth above the heavy threshold, instead of starting near the ceiling.
		var start:float = maxf(light,strong*(0.55 if channel=="Body" else 0.85))
		result = lerpf(start,ceiling,pow(1.0-growth/(extra+growth),exponent))
	return result*number(settings,channel+"_Gain")

static func duration(damage:float,settings:Dictionary) -> float:
	var weight:float = damage/(damage+number(settings,"Shake_Growth"))
	return lerpf(number(settings,"Shake_MinDuration"),number(settings,"Shake_MaxDuration"),clampf(weight,0.0,1.0))

static func apply_simple(settings:Dictionary,key:String,value:Variant) -> void:
	if not SIMPLE_LABELS.has(key): return
	settings[key] = value
	if key=="Feedback_Focus_MaxZoom":
		settings.Feedback_Focus_MinZoom = minf(number(settings,key),number(settings,"Focus_MinZoom"))
	elif key=="Feedback_Hitstop_MaxDuration":
		settings.Feedback_Hitstop_MinDuration = number(settings,key)
	normalize(settings)
	if key.begins_with("Feedback_Body_"):
		# Each visible tier strength drives both rendering channels; hidden gains must not mask edits.
		settings.Feedback_Body_Gain = 1.0
		settings.Feedback_Camera_Gain = 1.0
		settings.Feedback_Camera_Tiny = settings.Feedback_Body_Tiny
		settings.Feedback_Camera_Light = settings.Feedback_Body_Light*1.25
		settings.Feedback_Camera_Strong = settings.Feedback_Body_Strong*0.6
		settings.Feedback_Camera_Max = settings.Feedback_Body_Strong
		settings.Feedback_Body_Max = settings.Feedback_Body_Strong*1.8
		normalize(settings)
