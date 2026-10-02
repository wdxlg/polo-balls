extends MCPreviewTooltip
## Live enchantment list for a character whose enchantments change during battle
## (Enchanting Table). Rows come straight from the character's enchantment component;
## inverse (negative) levels are red with "-N" levels.

const ENCHANTS_PATH:String = "res://scripts/effects/我的世界/mc_enchantments.gd"
const NAME:String = "Minecraft附魔状态框"

var _shown:Dictionary = {}


static func ensure(unit:Node) -> void:
	if not (unit is Node2D) or not unit.is_inside_tree() or unit.is_queued_for_deletion():
		return
	var tooltip:MCPreviewTooltip = unit.get_node_or_null(NAME) as MCPreviewTooltip
	if tooltip == null:
		tooltip = (load("res://scripts/ui/mc_active_enchantment_tooltip.gd") as GDScript).new()
		tooltip.name = NAME
		tooltip.target = unit
		unit.add_child(tooltip)
	tooltip.set_process(true)
	tooltip.call("refresh_display")


func _process(_delta:float) -> void:
	refresh_display()


func refresh_display() -> void:
	if _panel == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	var health_value:Variant = target.get("health")
	if target.is_queued_for_deletion() or ((health_value is int or health_value is float) and float(health_value) <= 0.0):
		hide()
		return
	var enchants:Script = load(ENCHANTS_PATH)
	var levels:Dictionary = enchants.levels_of(target)
	if levels != _shown:
		_shown = levels.duplicate()
		set_enchantment_entries("附魔书",enchants.preview_entries(target),"Enchanted Book")
	# Stack beside the live potion box (or an armor stand's demo box) instead of covering it.
	var potion:MCPreviewTooltip = target.get_node_or_null("Minecraft药水状态框") as MCPreviewTooltip
	stack_below = potion if potion != null and potion.visible else target.get_node_or_null("Minecraft信息框") as MCPreviewTooltip
	if levels.is_empty():
		hide()
		set_process(false) # Re-enabled by ensure() when the next enchantment lands.
		return
	show()
	super._process(0.0)
