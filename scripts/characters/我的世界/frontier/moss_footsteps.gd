extends Node
## One per-world scheduler, one cadence per walking enemy, even across moss owners.
const FOOTSTEP = preload("res://scripts/effects/我的世界/footstep_cadence.gd")
const AUDIO = preload("res://scripts/characters/我的世界/new5/audio.gd")
const U = preload("res://scripts/characters/我的世界/new5/utils.gd")
@export var random_gap_min:float = 0.08
@export var random_gap_max:float = 0.32
var states:Dictionary = {}
var longest_step:float = 0.0
var _elapsed:float = 0.0
static func ensure(context:Node) -> Node:
	for node:Node in context.get_tree().get_nodes_in_group("MCMossFootsteps"):
		if not node.is_queued_for_deletion(): return node
	var manager:Node = load("res://scripts/characters/我的世界/frontier/moss_footsteps.gd").new()
	manager.name = "MossFootsteps"
	context.get_tree().current_scene.add_child(manager)
	return manager
func _ready() -> void:
	add_to_group("MCMossFootsteps")
	add_to_group("BattleTransient")
	for record:Dictionary in AUDIO.EVENTS["block.moss.step"]:
		longest_step = maxf(longest_step,record.stream.get_length()/maxf(float(record.pitch),0.01))
func base_interval() -> float:
	return longest_step+(maxf(random_gap_min,0.0)+maxf(random_gap_max,0.0))*0.5
func _physics_process(delta:float) -> void:
	if get_tree().paused or Game.now_stop_state: return
	_elapsed += maxf(delta,0.0)
	if _elapsed < 0.08: return
	sample(_elapsed)
	_elapsed = 0.0
func sample(delta:float) -> void:
	if get_tree().paused or Game.now_stop_state: return
	var field:Dictionary = {}
	var reference:Node = null
	for owner:Node in get_tree().get_nodes_in_group("MCMossOwner"):
		if not is_instance_valid(owner) or owner.is_queued_for_deletion() or not owner.active(): continue
		if reference == null: reference = owner
		for patch:Dictionary in owner.patches:
			field[owner.cell_at(patch.point)] = owner
	if reference == null: return
	var present:Dictionary = {}
	for target:Node in get_tree().get_nodes_in_group("Ball"):
		if not is_instance_valid(target) or target.is_queued_for_deletion(): continue
		if not target is ball or target.Type in [ball.Ball_Type.Shooter,ball.Ball_Type.Shooter_with_Health]: continue
		var id:int = target.get_instance_id()
		present[id] = true
		var point:Vector2 = target.global_position
		var state:Dictionary = states.get(id,{"point":point,"cadence":FOOTSTEP.new()})
		var travel:float = point.distance_to(state.point)
		state.point = point
		if state.cadence.tick(travel if travel>0.15 else 0.0,delta,FOOTSTEP.base_speed(target),base_interval()):
			for cell:Vector2i in reference.touching_moss_cells(target as ball,field):
				var owner:Node = field[cell]
				if not is_instance_valid(owner) or not U.enemy(owner,target): continue
				owner.emit_moss_sound("block.moss.step",point,-15.0,target)
				break # Sound is per walker, unlike the independent per-cell damage ticks.
		states[id] = state
	for id:Variant in states.keys():
		if not present.has(id): states.erase(id)
