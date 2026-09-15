class_name SpeedsterMotionPlan
extends RefCounted

# 防御只是一段临时 interrupt；攻击计划由极速者本体持续保存。
enum Kind {
	NORMAL,
	DODGE_PROJECTILE,
	DODGE_MELEE,
	DETOUR,
}

var kind:int = Kind.NORMAL
var direction:Vector2 = Vector2.ZERO
var speed_time_left:float = 0.0
var carry_time_left:float = 0.0
var source_key:String = ""
var reason:String = ""
var priority:float = 0.0

func clear() -> void:
	kind = Kind.NORMAL
	direction = Vector2.ZERO
	speed_time_left = 0.0
	carry_time_left = 0.0
	source_key = ""
	reason = ""
	priority = 0.0

func active() -> bool:
	return kind != Kind.NORMAL

func using_speed() -> bool:
	return active() and speed_time_left > 0.0
