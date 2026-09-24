extends Node
## One per-world scheduler, one cooldown per walking enemy, even across moss owners.
const AUDIO = preload("res://scripts/characters/我的世界/new5/audio.gd")
const U = preload("res://scripts/characters/我的世界/new5/utils.gd")
const CELL:float = 24.0
@export var random_gap_min:float = 0.08
@export var random_gap_max:float = 0.32
var states:Dictionary = {}
var longest_step:float = 0.0
var _elapsed:float = 0.0
var _rng := RandomNumberGenerator.new()
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
	_rng.seed = Game.battle_rng_seed_or("moss_footstep_audio",int(get_instance_id()))
	# Clients may choose a different native variant. Waiting for the LONGEST clip
	# (including pitch) ensures no peer starts a new step before the previous ends.
	for record:Dictionary in AUDIO.EVENTS["block.moss.step"]:
		longest_step = maxf(longest_step,record.stream.get_length()/maxf(float(record.pitch),0.01))
func next_interval() -> float:
	var low:float = maxf(minf(random_gap_min,random_gap_max),0.0)
	var high:float = maxf(maxf(random_gap_min,random_gap_max),low)
	return longest_step+_rng.randf_range(low,high)
func step_is_playing(target:Node) -> bool:
	var previous:Variant = target.get_meta("mc_moss_step_player",false)
	var player:Variant = previous.get_ref() if previous is WeakRef else null
	return is_instance_valid(player) and player.playing
func _physics_process(delta:float) -> void:
	if get_tree().paused or Game.now_stop_state: return
	_elapsed += maxf(delta,0.0)
	if _elapsed < 0.08: return
	sample(_elapsed)
	_elapsed = 0.0
func sample(delta:float) -> void:
	if get_tree().paused or Game.now_stop_state: return
	var field:Dictionary = {}
	var active_owner:bool = false
	for owner:Node in get_tree().get_nodes_in_group("MCMossOwner"):
		if not is_instance_valid(owner) or owner.is_queued_for_deletion() or not owner.active(): continue
		active_owner = true
		for patch:Dictionary in owner.patches:
			field[Vector2i((patch.point/CELL).round())] = owner
	if not active_owner: return
	var present:Dictionary = {}
	for target:Node in get_tree().get_nodes_in_group("Ball"):
		if not is_instance_valid(target) or target.is_queued_for_deletion(): continue
		if not target is ball or target.Type in [ball.Ball_Type.Shooter,ball.Ball_Type.Shooter_with_Health]: continue
		var id:int = target.get_instance_id()
		present[id] = true
		var point:Vector2 = target.global_position
		var state:Dictionary = states.get(id,{"point":point,"remaining":0.0})
		var moved:bool = point.distance_squared_to(state.point)>0.0225
		state.remaining = maxf(0.0,float(state.remaining)-maxf(delta,0.0))
		state.point = point
		var owner:Node = field.get(Vector2i((point/CELL).round()))
		if moved and float(state.remaining)<=0.0 and is_instance_valid(owner) and U.enemy(owner,target) and not step_is_playing(target):
			owner.emit_moss_sound("block.moss.step",point,-15.0,target)
			state.remaining = next_interval()
		states[id] = state
	for id:Variant in states.keys():
		if not present.has(id): states.erase(id)
