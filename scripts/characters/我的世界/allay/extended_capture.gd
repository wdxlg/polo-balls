extends RefCounted
## Compatibility facade for native-state restoration; identity is shared.
const API = preload("res://classes/projectile_interactions.gd")
const LEGACY = preload("res://classes/projectile_legacy_adapters.gd")
# Deprecated inspection exports kept for historical regression fixtures only.
# These arrays never gate describe/candidates/capture.
const BALL_PROJECTILES = [
	"res://scripts/shooter/科学家弹丸.gd",
	"res://scripts/shooter/不坏煎饼弹.gd",
	"res://scripts/shooter/伪军子弹.gd",
	"res://scripts/shooter/堵桥PSG子弹.gd",
	"res://scripts/shooter/磁铁_电球.gd",
	"res://scripts/shooter/菊花茶水滴.gd",
	"res://scripts/shooter/裁判牌.gd",
	"res://scripts/shooter/酒瓶.gd",
	"res://scripts/shooter/键盘文字.gd",
	"res://scripts/shooter/蛇咬.gd",
	"res://scripts/shooter/clown/clown_projectile.gd",
]
const CUSTOM = LEGACY.CUSTOM
static func config(shot:Node) -> Dictionary: return LEGACY.config(shot)
static func source(shot:Node,_config:Dictionary) -> Node: return API.source_of(shot)
static func team(shot:Node,_config:Dictionary) -> String: return API.team_of(shot)
static func native_descriptor(damage:float,speed:float) -> Dictionary:
	return {"kind":"native","damage":maxf(damage,0.0),"speed":speed}
static func describe(shot:Node) -> Dictionary: return API.capture_descriptor(shot)
