extends "res://scripts/characters/默认/移动盔甲架.gd"

## A moving, harmless stand for previewing configurable Minecraft UI. No buffs,
## enchantment damage, collision damage or new threat regions are applied.
@export_group("Minecraft 信息框")
@export_enum("药水效果", "附魔提示") var tooltip_mode:int = 0
@export_range(0.5,5.0,0.5) var tooltip_scale:float = 3.0
@export_range(0.0,80.0,1.0) var right_gap:float = 8.0
@export_range(0.0,80.0,1.0) var screen_margin:float = 8.0
@export_range(8,32,1) var tooltip_font_size:int = 10
@export var custom_text_font:Font
@export var custom_time_font:Font

@export_group("药水效果：名称/图标/等级/时长在每个 Resource 内编辑")
@export var potion_pool:Array[Resource] = []
@export var custom_potion_background:Texture2D
@export_range(1,32,1) var custom_potion_border:int = 5

@export_group("附魔：首行黄色物品名，下方为附魔行")
@export var tooltip_title:String = "附魔书"
@export var tooltip_title_en:String = ""
@export var tooltip_title_color:Color = Color("ffff55")
@export var enchantment_pool:Array[Resource] = []
@export var custom_enchant_background:Texture2D
@export var custom_enchant_frame:Texture2D
@export_range(1,32,1) var custom_enchant_background_border:int = 9
@export_range(1,32,1) var custom_enchant_frame_border:int = 10

@export_group("每次出生抽取不重复的演示条目")
@export var randomize_on_spawn:bool = true
@export_range(1,20,1) var random_min_entries:int = 2
@export_range(1,20,1) var random_max_entries:int = 4

var preview_tooltip:MCPreviewTooltip
var displayed_potions:Array[MCPreviewPotionEffect] = []
var displayed_enchantments:Array[MCPreviewEnchantment] = []


func _ready() -> void:
	super._ready()
	preview_tooltip = MCPreviewTooltip.new()
	preview_tooltip.name = "Minecraft信息框"
	preview_tooltip.target = self
	preview_tooltip.display_scale = tooltip_scale
	preview_tooltip.right_gap = right_gap
	preview_tooltip.screen_margin = screen_margin
	preview_tooltip.text_size = tooltip_font_size
	preview_tooltip.title_color = tooltip_title_color
	if custom_text_font != null:
		preview_tooltip.text_font = custom_text_font
	if custom_time_font != null:
		preview_tooltip.time_font = custom_time_font
	if custom_potion_background != null:
		preview_tooltip.potion_background = custom_potion_background
		preview_tooltip.potion_border = custom_potion_border
	if custom_enchant_background != null:
		preview_tooltip.enchant_background = custom_enchant_background
		preview_tooltip.enchant_background_border = custom_enchant_background_border
	if custom_enchant_frame != null:
		preview_tooltip.enchant_frame = custom_enchant_frame
		preview_tooltip.enchant_frame_border = custom_enchant_frame_border
	add_child(preview_tooltip)
	var chosen:Array[int] = _sample_indices()
	if tooltip_mode == 0:
		var selected:Array[MCPreviewPotionEffect] = []
		for index:int in chosen:
			selected.append(potion_pool[index] as MCPreviewPotionEffect)
		set_displayed_potions(selected)
	else:
		var selected:Array[MCPreviewEnchantment] = []
		for index:int in chosen:
			selected.append(enchantment_pool[index] as MCPreviewEnchantment)
		set_displayed_enchantments(tooltip_title,selected,tooltip_title_en)


func _sample_indices() -> Array[int]:
	var indices:Array[int] = []
	var pool:Array[Resource] = potion_pool if tooltip_mode == 0 else enchantment_pool
	for index:int in range(pool.size()):
		if (tooltip_mode == 0 and pool[index] is MCPreviewPotionEffect) or (tooltip_mode == 1 and pool[index] is MCPreviewEnchantment):
			indices.append(index)
	if indices.is_empty() or not randomize_on_spawn:
		return indices
	var rng := RandomNumberGenerator.new()
	rng.seed = Game.battle_rng_seed_or(
		"scripts/characters/默认/效果测试盔甲架.gd:mode=" + str(tooltip_mode),
		maxi(abs(int(Time.get_ticks_usec()) ^ int(get_instance_id())),1)
	)
	for index:int in range(indices.size() - 1,0,-1):
		var swap_index:int = rng.randi_range(0,index)
		var previous:int = indices[index]
		indices[index] = indices[swap_index]
		indices[swap_index] = previous
	var minimum:int = clampi(random_min_entries,1,indices.size())
	var maximum:int = clampi(random_max_entries,minimum,indices.size())
	var count:int = rng.randi_range(minimum,maximum)
	var picked:Array[int] = indices.slice(0,count)
	picked.sort() # Preserve the pool's chosen ordering instead of jittering the UI.
	return picked


func set_displayed_potions(entries:Array[MCPreviewPotionEffect]) -> void:
	tooltip_mode = 0
	displayed_potions = entries.duplicate()
	if is_instance_valid(preview_tooltip):
		preview_tooltip.set_potion_entries(displayed_potions)


func set_displayed_enchantments(item_name:String,entries:Array[MCPreviewEnchantment],english_item_name:String = "") -> void:
	tooltip_mode = 1
	tooltip_title = item_name
	displayed_enchantments = entries.duplicate()
	if is_instance_valid(preview_tooltip):
		preview_tooltip.set_enchantment_entries(tooltip_title,displayed_enchantments,english_item_name)
