extends Node
# One per-world cadence per walking target, shared across overlapping webs/owners.
# 脚步节奏按踩踏者当前实际移速计步（footstep_cadence.gd）：越快越密、越慢越稀，可与上一声重叠。
# 基础间隔 = 最长一声蛛网脚步 + 随机停顿区间的平均值。
const FOOTSTEP = preload("res://scripts/effects/我的世界/footstep_cadence.gd")
const BANK = preload("res://scripts/effects/我的世界/mc16_sound_bank.gd")
const GEOMETRY = preload("res://scripts/effects/我的世界/mc16_geometry.gd")
@export var random_gap_min:float = 0.15
@export var random_gap_max:float = 0.45
var states:Dictionary = {}
var longest_step:float = 0.0
var _elapsed:float = 0.0
static func ensure(context:Node) -> Node:
	for node:Node in context.get_tree().get_nodes_in_group("MCSpiderWebFootsteps"):
		if not node.is_queued_for_deletion(): return node
	var manager:Node = load("res://scripts/effects/我的世界/cobweb_footsteps.gd").new()
	manager.name = "CobwebFootsteps"
	context.get_tree().current_scene.add_child(manager)
	return manager
func _ready() -> void:
	add_to_group("MCSpiderWebFootsteps")
	add_to_group("BattleTransient")
	for stream:AudioStream in BANK.EVENTS["block.cobweb.step"]: longest_step = maxf(longest_step,stream.get_length())
func base_interval() -> float:
	return longest_step+(maxf(random_gap_min,0.05)+maxf(random_gap_max,0.05))*0.5
func _physics_process(delta:float) -> void:
	if Game.now_stop_state or get_tree().paused: return
	_elapsed += maxf(delta,0.0)
	if _elapsed<0.08: return
	sample(_elapsed)
	_elapsed = 0.0
func sample(delta:float) -> void:
	if Game.now_stop_state or get_tree().paused: return
	var nets:Array[Node] = get_tree().get_nodes_in_group("MCSpiderSilk")
	nets.sort_custom(func(a:Node,b:Node) -> bool: return str(a.unit.get_path())<str(b.unit.get_path()))
	var present:Dictionary = {}
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball or not is_instance_valid(raw) or raw.is_queued_for_deletion() or raw.health<=0: continue
		var target:ball = raw
		var id:int = target.get_instance_id()
		present[id] = true
		var point:Vector2 = target.global_position
		var state:Dictionary = states.get(id,{"point":point,"cadence":FOOTSTEP.new()})
		var travel:float = point.distance_to(state.point)
		state.point = point
		states[id] = state
		var walking:bool = not target.dizziness and target.is_combat_runtime_active() and travel>0.025 and travel<maxf(48.0,target.Speed*delta*5.0)
		if not state.cadence.tick(travel if walking else 0.0,delta,FOOTSTEP.base_speed(target),base_interval()): continue
		for net:Node in nets:
			if not is_instance_valid(net.unit) or net.unit.health<=0 or not net.unit.is_combat_runtime_active() or not GEOMETRY.enemy(net.unit,target): continue
			var on_web:bool = false
			for web_point:Vector2 in net.web_points():
				if point.distance_to(web_point)<=net.unit.web_radius+GEOMETRY.radius(target):
					on_web = true
					break
			if not on_web: continue
			# Deterministically choose one owner on every peer; only that owner emits.
			if net.unit.is_multiplayer_authority():
				net.unit.native_feedback.cobweb_step(target)
			break
	for id:Variant in states.keys():
		if not present.has(id): states.erase(id)
