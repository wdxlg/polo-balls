class_name MCActiveEffectTooltip
extends MCPreviewTooltip
## The vanilla frame is shared with the preview stands, but THESE rows come
## from real, live combat statuses. Do not create a second gameplay timer.

const NAME:String = "Minecraft药水状态框"
const LEVITATION_META:StringName = &"mc_shulker_levitation"
const ORDER:Array[String] = ["regen","speed","haste","resistance","jump_boost",
	"strength","invisibility","poison","wither","weakness","slowness","levitation"]
const SPECS:Dictionary = {
	"regen":{"zh":"生命恢复","en":"Regeneration","icon":preload("res://Images/UI/minecraft_tooltips/mob_effect/regeneration.png")},
	"speed":{"zh":"迅捷","en":"Speed","icon":preload("res://Images/UI/minecraft_tooltips/mob_effect/speed.png")},
	"haste":{"zh":"急迫","en":"Haste","icon":preload("res://Images/UI/minecraft_tooltips/mob_effect/haste.png")},
	"resistance":{"zh":"抗性提升","en":"Resistance","icon":preload("res://Images/UI/minecraft_tooltips/mob_effect/resistance.png")},
	"jump_boost":{"zh":"跳跃提升","en":"Jump Boost","icon":preload("res://Images/UI/minecraft_tooltips/mob_effect/jump_boost.png")},
	"strength":{"zh":"力量","en":"Strength","icon":preload("res://Images/UI/minecraft_tooltips/mob_effect/strength.png")},
	"invisibility":{"zh":"隐身","en":"Invisibility","icon":preload("res://Images/UI/minecraft_tooltips/mob_effect/invisibility.png")},
	"poison":{"zh":"中毒","en":"Poison","icon":preload("res://Images/UI/minecraft_tooltips/mob_effect/poison.png")},
	"wither":{"zh":"凋零","en":"Wither","icon":preload("res://Images/UI/minecraft_tooltips/mob_effect/wither.png")},
	"weakness":{"zh":"虚弱","en":"Weakness","icon":preload("res://Images/UI/minecraft_tooltips/mob_effect/weakness.png")},
	"slowness":{"zh":"缓慢","en":"Slowness","icon":preload("res://Images/UI/minecraft_tooltips/mob_effect/slowness.png")},
	"levitation":{"zh":"飘浮","en":"Levitation","icon":preload("res://Images/UI/minecraft_tooltips/mob_effect/levitation.png")},
}

var _shown_keys:PackedStringArray = PackedStringArray()


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


func _remember(found:Dictionary,kind:String,seconds:float) -> void:
	if not SPECS.has(kind) or (seconds <= 0.0 and not is_inf(seconds)):
		return
	if not found.has(kind) or seconds > float(found[kind]):
		found[kind] = seconds


func _active_times() -> Dictionary:
	var times:Dictionary = {}
	if not target is ball:
		return times
	var unit:ball = target as ball
	for child:Node in unit.get_children():
		if child.is_queued_for_deletion() or not child.name.begins_with("WitchPotionStatus_"):
			continue
		var kind:String = str(child.get("effect_type"))
		if child.name == "WitchPotionStatus_" + kind:
			_remember(times,kind,float(child.get("remaining")))
	var wither:Node = unit.get_node_or_null("WitherStatus")
	if wither != null and not wither.is_queued_for_deletion():
		_remember(times,"wither",float(wither.get("remaining")))
	if unit.has_meta(LEVITATION_META):
		var ref:WeakRef = unit.get_meta(LEVITATION_META) as WeakRef
		var floating:Variant = ref.get_ref() if ref != null else null
		if is_instance_valid(floating) and not floating.is_queued_for_deletion():
			_remember(times,"levitation",float(floating.get("remaining")))
	# Beacon primary effect: on the Wither itself, never on the struck target.
	if unit.has_method("apply_beacon_buff"):
		_remember(times,str(unit.get("_buff")),float(unit.get("_buff_left")))
	# The Witch's wither potion also applies a REAL weakness Buff for 6.5 s.
	var own_buffs:Dictionary = unit.Buff_Dic.get(unit.get_instance_id(),{})
	var weakness:Buff = own_buffs.get("女巫_凋零虚弱") as Buff
	if weakness != null:
		_remember(times,"weakness",weakness.duration)
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
	if keys != _shown_keys:
		_shown_keys = keys
		var rows:Array[MCPreviewPotionEffect] = []
		for kind:String in keys:
			var info:Dictionary = SPECS[kind]
			var row := MCPreviewPotionEffect.new()
			row.effect_name = str(info.zh)
			row.english_name = str(info.en)
			row.icon = info.icon as Texture2D
			row.duration_seconds = 0 if is_inf(float(times[kind])) else ceili(float(times[kind]))
			row.duration_text_override = "∞" if is_inf(float(times[kind])) else ""
			rows.append(row)
		set_potion_entries(rows)
	if keys.is_empty():
		hide()
		set_process(false) # Re-enabled by ensure() when the next effect is applied.
		return
	show()
	var changed:bool = false
	for index:int in range(keys.size()):
		var seconds:float = float(times[keys[index]])
		var time:String = "∞" if is_inf(seconds) else _duration(ceili(seconds))
		_remaining_seconds[index] = 0 if is_inf(seconds) else ceili(seconds)
		if _time_labels[index].text != time:
			_time_labels[index].text = time
			changed = true
	if changed:
		_refresh_potion_widths()
	super._process(0.0) # Only the original gameplay statuses own the countdown.
