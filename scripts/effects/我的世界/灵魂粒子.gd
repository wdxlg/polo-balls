extends Sprite2D
## Native Minecraft Java `soul` particle: particles/soul.json -> soul_0..soul_10,
## played in order by age (brown soul-sand face -> rising cyan wisp). Shared/public:
## setup(point, motion, lifetime, width, rise). Visual only; pauses with the battle.
const FRAMES = [
	preload("res://Images/effects/我的世界/灵魂粒子/soul_0.png"),
	preload("res://Images/effects/我的世界/灵魂粒子/soul_1.png"),
	preload("res://Images/effects/我的世界/灵魂粒子/soul_2.png"),
	preload("res://Images/effects/我的世界/灵魂粒子/soul_3.png"),
	preload("res://Images/effects/我的世界/灵魂粒子/soul_4.png"),
	preload("res://Images/effects/我的世界/灵魂粒子/soul_5.png"),
	preload("res://Images/effects/我的世界/灵魂粒子/soul_6.png"),
	preload("res://Images/effects/我的世界/灵魂粒子/soul_7.png"),
	preload("res://Images/effects/我的世界/灵魂粒子/soul_8.png"),
	preload("res://Images/effects/我的世界/灵魂粒子/soul_9.png"),
	preload("res://Images/effects/我的世界/灵魂粒子/soul_10.png"),
]
const CAP:int = 260
var _age:float = 0.0
var _life:float = 0.8
var _start:Vector2
var _motion:Vector2
var _rise:float = 0.0
var _follow:WeakRef
var _follow_offset:Vector2 = Vector2.ZERO

## Free slots under the shared soul cap (callers spawn at most this many).
static func room(tree:SceneTree) -> int:
	return maxi(CAP-tree.get_nodes_in_group("MCSoulParticle").size(),0) if tree != null else 0

## motion is eased in (t^2): the soul lingers at its origin and then flies into
## start+motion; rise adds a native-style upward drift over the lifetime.
func setup(point:Vector2,motion:Vector2,lifetime:float = 0.8,width:float = 9.0,rise:float = 0.0) -> void:
	global_transform = Transform2D(0.0,point)
	_start = point
	_motion = motion
	_life = maxf(lifetime,0.05)
	_rise = rise
	texture = FRAMES[0]
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scale = Vector2.ONE*(clampf(width,2.0,32.0)/float(texture.get_width()))
	z_index = 2
	add_to_group("BattleTransient")
	add_to_group("MCSoulParticle")

## Optional homing: the eased path keeps ending on `target` (plus offset) even if
## it moves, so streamed souls really enter the moving character.
func follow(target:Node2D,offset:Vector2 = Vector2.ZERO) -> void:
	_follow = weakref(target) if is_instance_valid(target) else null
	_follow_offset = offset

func _process(delta:float) -> void:
	if Game.now_stop_state or get_tree().paused: return
	_age += delta
	var t:float = clampf(_age/_life,0.0,1.0)
	var target:Node2D = _follow.get_ref() as Node2D if _follow != null else null
	if is_instance_valid(target) and target.is_inside_tree(): _motion = target.global_position+_follow_offset-_start
	texture = FRAMES[mini(int(t*FRAMES.size()),FRAMES.size()-1)]
	global_position = _start+_motion*(t*t)+Vector2.UP*_rise*t
	modulate.a = 1.0-smoothstep(0.82,1.0,t)
	if t>=1.0: queue_free()
