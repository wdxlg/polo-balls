extends RefCounted
## Data and eligibility only. No concrete random events are implemented yet.
const ENVIRONMENTS:Array[String] = ["none","snow"]
const EVENTS:Array[Dictionary] = [] # Future entries: {"id":String,"label_key":String}.
const SETTING_KEYS:Array[String] = ["Random_Events","Random_Event_Selection","Environment"]

static func normalize_environment(value:Variant) -> String:
	var key:String = str(value)
	return key if ENVIRONMENTS.has(key) else "none"

static func normalize_selection(value:Variant) -> Array[String]:
	var result:Array[String] = []
	if not (value is Array or value is PackedStringArray): return result
	for item:Variant in value:
		if not (item is String or item is StringName): continue
		var key:String = str(item)
		if key.is_empty() or key.length()>64 or result.has(key): continue
		result.append(key)
		if result.size()>=64: break
	return result

static func normalize_setting(key:String,value:Variant) -> Variant:
	match key:
		"Environment": return normalize_environment(value)
		"Random_Event_Selection": return normalize_selection(value)
		"Random_Events": return bool(value) if value is bool or value is int else false
	return value

static func eligible_events(settings:Dictionary,definitions:Array = EVENTS) -> Array[String]:
	var result:Array[String] = []
	if not bool(settings.get("Random_Events",false)): return result
	var checked:Array[String] = normalize_selection(settings.get("Random_Event_Selection",[]))
	for value:Variant in definitions:
		if not value is Dictionary: continue
		var id:String = str(value.get("id",""))
		if not id.is_empty() and checked.has(id) and not result.has(id): result.append(id)
	return result

static func pick_event(settings:Dictionary,rng:RandomNumberGenerator,definitions:Array = EVENTS) -> String:
	var candidates:Array[String] = eligible_events(settings,definitions)
	# An empty/unchecked catalog must not silently fall back to all events.
	return "" if candidates.is_empty() else candidates[rng.randi_range(0,candidates.size()-1)]
