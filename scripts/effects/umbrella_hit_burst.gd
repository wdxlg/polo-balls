extends RefCounted

const FOLLOW_EFFECT_SCRIPT = preload("res://scripts/effects/umbrella_hit_burst_follow.gd")

# 伤心男人专用伞面白线：
# - 起点绑定到伞面局部坐标，因此角色移动时不会把白线“甩”在身后；
# - 方向每帧按伞面局部法线重新换算到世界坐标，角色旋转时也能贴着伞面；
# - 动画保持短、快、小。
static func spawn(
	parent:Node,
	anchor:Node2D,
	impact_position:Vector2,
	surface_normal:Vector2,
	impact_speed:float,
	seed:int
) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	if anchor == null or not is_instance_valid(anchor):
		return
	var effect:Node2D = FOLLOW_EFFECT_SCRIPT.new()
	effect.name = "UmbrellaHitBurst_%d" % seed
	effect.call("setup",anchor,impact_position,surface_normal,maxf(impact_speed,1.0),seed)
	parent.add_child(effect)
