extends "res://scripts/characters/默认/盔甲架.gd"

const DEFENSE_HEALTH:int = 500
const DEFENSE_BLOCK:int = 500

# V38：铁甲视觉不再由脚本运行时创建/定位。
# 头盔和胸甲已经作为真实 Sprite2D 节点写进：
# res://scenes/characters/默认/防御盔甲架.tscn
#
# 这样打开“防御盔甲架.tscn”时，可以在 2D 编辑器里直接：
# - 拖动「铁头盔_可视调整」「铁胸甲_可视调整」改位置；
# - 用缩放工具，或 Inspector -> Transform -> Scale 改大小；
# - 所有手动 Transform 都会保存在场景里，运行时本脚本不会再覆盖。


func armor_stand_initial_max_health() -> int:
	return DEFENSE_HEALTH


func _ready() -> void:
	# 从初始化阶段就使用 500 生命，避免先按基类 1000 初始化再回写造成假跳字。
	super._ready()
	max_block = DEFENSE_BLOCK
	block = DEFENSE_BLOCK
	if default_properties != null:
		default_properties["Max_health"] = DEFENSE_HEALTH
		default_properties["max_block"] = DEFENSE_BLOCK
