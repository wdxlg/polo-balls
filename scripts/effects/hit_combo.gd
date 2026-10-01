extends RefCounted
## 连击升调：同一攻击者（投射物、召唤物算到主人身上）在窗口内连续命中，
## 命中音一下比一下高一个半音，封顶后保持；断档或自己被打中后回到原调。
const OWNERS = preload("res://classes/projectile_interactions.gd")
const WINDOW_USEC:int = 1500000
const SEMITONE_STEP:float = 1.0
const MAX_STEPS:int = 8
const META:StringName = &"_hit_combo_state"


static func owner_of(source:Node) -> Node:
	var node:Node = source
	var seen:Dictionary = {}
	while is_instance_valid(node) and not seen.has(node.get_instance_id()):
		seen[node.get_instance_id()] = true
		var up:Node = OWNERS.source_of(node)
		if not is_instance_valid(up) or up == node: return node
		node = up
	return node if is_instance_valid(node) else null


## 记一次命中并返回当前连击数（同一物理帧的群攻只算一下）。
static func register(source:Node) -> int:
	var owner:Node = owner_of(source)
	if owner == null: return 1
	var now:int = Time.get_ticks_usec()
	var frame:int = Engine.get_physics_frames()
	var state:Array = owner.get_meta(META,[0,-WINDOW_USEC * 2,-1])
	var count:int = int(state[0])
	if int(state[2]) == frame and count > 0: return count
	count = count + 1 if count > 0 and now - int(state[1]) <= WINDOW_USEC else 1
	owner.set_meta(META,[count,now,frame])
	return count


static func count_of(source:Node) -> int:
	var owner:Node = owner_of(source)
	if owner == null or not owner.has_meta(META): return 0
	var state:Array = owner.get_meta(META)
	return int(state[0]) if Time.get_ticks_usec() - int(state[1]) <= WINDOW_USEC else 0


static func reset(node:Node) -> void:
	if is_instance_valid(node) and node.has_meta(META): node.remove_meta(META)


static func pitch_for(count:int) -> float:
	return pow(2.0,float(clampi(count - 1,0,MAX_STEPS)) * SEMITONE_STEP / 12.0)


static func next_pitch(source:Node) -> float:
	return pitch_for(register(source))

