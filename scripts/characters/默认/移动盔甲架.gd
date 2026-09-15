extends "res://scripts/characters/默认/盔甲架.gd"

# 移动盔甲架与普通盔甲架保持完全相同的生命、受伤、死亡、无攻击等机制；
# 唯一区别是恢复项目普通角色的默认 Speed 数值，因此会走 ball 的正常 Move 状态。
const MOBILE_ARMOR_STAND_SPEED:float = 100.0


func _ready() -> void:
	# inherited 盔甲架._ready() 会为了普通盔甲架把 Speed 设为 0。
	# 先让它完整完成所有盔甲架初始化，再只恢复移动速度。
	super._ready()
	Speed = MOBILE_ARMOR_STAND_SPEED
	# World 每帧会从 default_properties 恢复运行时属性，所以同步更新默认速度，
	# 防止下一帧又被还原成普通盔甲架的 0。
	default_properties["Speed"] = MOBILE_ARMOR_STAND_SPEED
