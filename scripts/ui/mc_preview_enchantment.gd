@tool
class_name MCPreviewEnchantment
extends Resource

## A line in a Minecraft-style enchanted-item tooltip; text and colour are editable.
@export var enchantment_name:String = "穿透"
@export_range(1,3999,1) var level:int = 4
@export var level_text_override:String = ""
@export var text_color:Color = Color("aaaaaa")
