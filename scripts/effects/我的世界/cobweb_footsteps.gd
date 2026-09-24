extends Node
# One per-world clock per walking target, shared across overlapping webs/owners.
const BANK = preload("res://scripts/effects/我的世界/mc16_sound_bank.gd")
const GEOMETRY = preload("res://scripts/effects/我的世界/mc16_geometry.gd")
@export var random_gap_min:float = 0.15
@export var random_gap_max:float = 0.45
var states:Dictionary = {}
var longest_step:float = 0.0
var _elapsed:float = 0.0
var _rng := RandomNumberGenerator.new()
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
	_rng.randomize()
	for stream:AudioStream in BANK.EVENTS["block.cobweb.step"]: longest_step = maxf(longest_step,stream.get_length())
func next_interval() -> float:
	var low:float = maxf(minf(random_gap_min,random_gap_max),0.05)
	var high:float = maxf(maxf(random_gap_min,random_gap_max),low)
	# Peers can choose different native variants: protect even the longest clip.
	return longest_step+_rng.randf_range(low,high)
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
		var state:Dictionary = states.get(id,{"point":point,"remaining":0.0})
		var travel:float = point.distance_to(state.point)
		state.point = point
		state.remaining = maxf(0.0,float(state.remaining)-maxf(delta,0.0))
		states[id] = state
		if target.dizziness or not target.is_combat_runtime_active() or travel<=0.025 or travel>=maxf(48.0,target.Speed*delta*5.0) or state.remaining>0.0: continue
		var previous:Variant = target.get_meta("mc_cobweb_step_player",false)
		var player:Variant = previous.get_ref() if previous is WeakRef else null
		if is_instance_valid(player) and player.playing: continue
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
				player = net.unit.native_feedback.cobweb_step(target)
				state.remaining = next_interval() if is_instance_valid(player) else 0.15
			break
	for id:Variant in states.keys():
		if not present.has(id): states.erase(id)
