class_name MCActiveEffectTooltip
extends MCPreviewTooltip
## The vanilla frame is shared with the preview stands, but THESE rows come
## from real, live combat statuses. Do not create a second gameplay timer.

const EFFECTS = preload("res://scripts/effects/我的世界/mc_status_effects.gd")
const NAME:String = "Minecraft药水状态框"
const ORDER:Array[String] = ["regen","speed","haste","resistance","jump_boost",
	"strength","invisibility","poison","wither","weakness","slowness","levitation"]

var _shown_keys:PackedStringArray = PackedStringArray()
var _shown_levels:PackedInt32Array = PackedInt32Array()


static func ensure(unit:ball) -> void:
	if not is_instance_valid(unit) or unit.health <= 0 or not unit.is_inside_tree():
		return
	var tooltip:MCPreviewTooltip = unit.get_node_or_null(NAME) as MCPreviewTooltip
	if tooltip == null:
		# SceneTree script tests parse this class before global class names register.
		tooltip = (load("res://scripts/ui/mc_active_effect_tooltip.gd") as GDScript).new()
		tooltip.name = NAME
		tooltip.target = unit
		unit.add_child(tooltip)
	# A preview stand can receive a REAL effect too; keep both frames visible.
	tooltip.stack_below = unit.get_node_or_null("Minecraft信息框") as MCPreviewTooltip
	tooltip.set_process(true)
	tooltip.call("refresh_display")


func _process(_delta:float) -> void:
	refresh_display()


func _remember(found:Dictionary,kind:String,seconds:float,level:int) -> void:
	if EFFECTS.info(kind).is_empty() or (seconds <= 0.0 and not is_inf(seconds)) or level < 1:
		return
	if not found.has(kind) or level > int(found[kind].level) or (level == int(found[kind].level) and seconds > float(found[kind].seconds)):
		found[kind] = {"seconds":seconds,"level":level}


func _active_times() -> Dictionary:
	var times:Dictionary = {}
	if not target is ball:
		return times
	var unit:ball = target as ball
	for child:Node in unit.get_children():
		if child.is_queued_for_deletion() or not child.name.begins_with("MinecraftStatus_"):
			continue
		var kind:String = str(child.get("effect_type"))
		if child.name == EFFECTS.node_name(kind):
			_remember(times,kind,float(child.get("remaining")),int(child.get("level")))
	var wither:Node = unit.get_node_or_null("WitherStatus")
	if wither != null and not wither.is_queued_for_deletion():
		_remember(times,"wither",float(wither.get("remaining")),int(wither.get("level")))
	return times


func refresh_display() -> void:
	if _panel == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	if target.is_queued_for_deletion() or (target is ball and (target as ball).health <= 0):
		hide()
		return
	var times:Dictionary = _active_times()
	var keys:PackedStringArray = PackedStringArray()
	for kind:String in ORDER:
		if times.has(kind):
			keys.append(kind)
	for kind:String in EFFECTS.all_kinds():
		if times.has(kind) and not keys.has(kind):
			keys.append(kind)
	var levels:PackedInt32Array = PackedInt32Array()
	for kind:String in keys:
		levels.append(int(times[kind].level))
	if keys != _shown_keys or levels != _shown_levels:
		_shown_keys = keys
		_shown_levels = levels
		var rows:Array[MCPreviewPotionEffect] = []
		for kind:String in keys:
			var info:Dictionary = EFFECTS.info(kind)
			var row := MCPreviewPotionEffect.new()
			row.effect_name = str(info.zh)
			row.english_name = str(info.en)
			row.icon = EFFECTS.icon(kind)
			row.level = int(times[kind].level)
			row.duration_seconds = 0 if is_inf(float(times[kind].seconds)) else ceili(float(times[kind].seconds))
			row.duration_text_override = "∞" if is_inf(float(times[kind].seconds)) else ""
			rows.append(row)
		set_potion_entries(rows)
	if keys.is_empty():
		hide()
		set_process(false) # Re-enabled by ensure() when the next effect is applied.
		return
	show()
	var changed:bool = false
	for index:int in range(keys.size()):
		var seconds:float = float(times[keys[index]].seconds)
		var time:String = "∞" if is_inf(seconds) else _duration(ceili(seconds))
		_remaining_seconds[index] = 0 if is_inf(seconds) else ceili(seconds)
		if _time_labels[index].text != time:
			_time_labels[index].text = time
			changed = true
	if changed:
		_refresh_potion_widths()
	super._process(0.0) # Only the original gameplay statuses own the countdown.
