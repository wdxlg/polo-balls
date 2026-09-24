@tool
class_name MCPreviewPotionEffect
extends Resource

## Display-only example data: the test armor stand does not gain the actual buff.
@export var effect_name:String = "生命恢复"
## Optional English display name; leave empty to use the game's translation table.
@export var english_name:String = ""
@export var icon:Texture2D
@export_range(1,3999,1) var level:int = 1
@export var level_text_override:String = ""
@export_range(0,86400,1) var duration_seconds:int = 90
@export var duration_text_override:String = ""
@export var name_color:Color = Color("dddddd")
@export var duration_color:Color = Color("777777")
