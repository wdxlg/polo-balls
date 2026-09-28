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
var _first_frame:int = 0
var _delay:float = 0.0
var _anchor_parent:WeakRef
var _anchor_name:String = ""
var _anchor_unit:Vector2 = Vector2.ZERO
var _anchor_box:Vector2 = Vector2.ZERO

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

## Optional: play only the later cyan-wisp frames (the early frames are the brown
## soul-sand face, which reads as dirt on grass maps).
func from_frame(index:int) -> void:
	_first_frame = clampi(index,0,FRAMES.size()-1)
	texture = FRAMES[_first_frame]

## Optional staggered start: stay hidden for `seconds`, then start from the anchor's
## CURRENT body (anchor looked up by name so peers work before it replicates):
## start = anchor position + unit_offset * anchor collision box (fallback_box if absent).
func delay_start(seconds:float,anchor_parent:Node = null,anchor_name:String = "",unit_offset:Vector2 = Vector2.ZERO,fallback_box:Vector2 = Vector2.ZERO) -> void:
	_delay = maxf(seconds,0.0)
	_anchor_parent = weakref(anchor_parent) if is_instance_valid(anchor_parent) else null
	_anchor_name = anchor_name
	_anchor_unit = unit_offset
	_anchor_box = fallback_box
	visible = _delay<=0.0
	if _delay<=0.0: _activate_anchor()

func _activate_anchor() -> void:
	var parent:Node = _anchor_parent.get_ref() as Node if _anchor_parent != null else null
	var anchor:Node2D = parent.get_node_or_null(NodePath(_anchor_name)) as Node2D if is_instance_valid(parent) and not _anchor_name.is_empty() else null
	var box:Vector2 = _anchor_box
	var shape_node:CollisionShape2D = anchor.get("collision_shape_2d") as CollisionShape2D if is_instance_valid(anchor) else null
	if is_instance_valid(shape_node) and shape_node.shape != null: box = shape_node.shape.get_rect().size*shape_node.global_scale.abs()
	var center:Vector2 = anchor.global_position if is_instance_valid(anchor) and anchor.is_inside_tree() else _start
	_start = center+_anchor_unit*box
	global_position = _start
	visible = true

func _process(delta:float) -> void:
	if Game.now_stop_state or get_tree().paused: return
	if _delay>0.0:
		_delay -= delta
		if _delay>0.0: return
		_activate_anchor()
	_age += delta
	var t:float = clampf(_age/_life,0.0,1.0)
	var target:Node2D = _follow.get_ref() as Node2D if _follow != null else null
	if is_instance_valid(target) and target.is_inside_tree(): _motion = target.global_position+_follow_offset-_start
	var span:int = FRAMES.size()-_first_frame
	texture = FRAMES[_first_frame+mini(int(t*span),span-1)]
	global_position = _start+_motion*(t*t)+Vector2.UP*_rise*t
	modulate.a = 1.0-smoothstep(0.82,1.0,t)
	if t>=1.0: queue_free()
