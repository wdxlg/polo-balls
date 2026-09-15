class_name SpeedsterThreat
extends RefCounted

# V23: 统一“未来危险”数据。极速者只看几何威胁，不认识具体角色名。
enum Kind {
	PROJECTILE,
	RANGED_WINDUP,
	MELEE_LINE,
	HAZARD,
}

var kind:int = Kind.PROJECTILE
var source:Node2D = null
var source_key:String = ""
var origin:Vector2 = Vector2.ZERO
var axis:Vector2 = Vector2.RIGHT
var source_velocity:Vector2 = Vector2.ZERO

# 以游戏时间计：危险从 active_from 开始，到 active_until 结束。
var active_from:float = 0.0
var active_until:float = 0.0

# PROJECTILE / RANGED_WINDUP：radius 是弹道安全半径。
# MELEE_LINE：reach + radius 描述一条胶囊形攻击走廊。
var reach:float = 0.0
var radius:float = 0.0
var hard_radius:float = 0.0

var time_to_impact:float = INF
var severity:float = 0.0
var label:String = ""

func is_valid() -> bool:
	return source != null and is_instance_valid(source)

func is_line_threat() -> bool:
	return kind == Kind.MELEE_LINE

func is_projectile_like() -> bool:
	return kind == Kind.PROJECTILE or kind == Kind.RANGED_WINDUP

func is_area_threat() -> bool:
	return kind == Kind.HAZARD
