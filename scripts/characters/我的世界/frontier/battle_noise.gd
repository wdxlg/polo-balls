extends Node
## One authority-owned sampler per battle, not one enemy scan per Warden.
const POWER = {"move":24.0,"collision":64.0,"attack":120.0,"action":16.0}
var clock:float = 0.0
var _sample_left:float = 0.0
var _positions:Dictionary = {}
var _projectiles:Dictionary = {}
var _next_event:Dictionary = {}
var _regions_active:Dictionary = {}
var _region_repeat:Dictionary = {}
static func ensure(context:Node) -> Node:
	var world:Node = context.get_tree().current_scene
	var found:Node = world.get_node_or_null("MCBattleNoise")
	if is_instance_valid(found): return found
	var result:Node = load("res://scripts/characters/我的世界/frontier/battle_noise.gd").new()
	result.name = "MCBattleNoise"
	world.add_child(result)
	result.add_to_group("BattleTransient")
	return result
func _ready() -> void:
	if is_multiplayer_authority(): Game.combat_damage_resolved.connect(_on_damage)
func _physics_process(delta:float) -> void:
	if not is_multiplayer_authority() or Game.now_stop_state or get_tree().paused: return
	if get_tree().get_nodes_in_group("MCWardenListener").is_empty(): return
	clock += delta
	_sample_left -= delta
	if _sample_left<=0.0:
		_sample_left = 0.15
		sample_actions()
func publish(source:Node,kind:String,point:Vector2 = Vector2.INF) -> bool:
	if not is_instance_valid(source) or not source.has_method("is_combat_runtime_active") or not source.is_multiplayer_authority(): return false
	if not source.is_combat_runtime_active() or source.health<=0: return false
	if kind=="attack" and (source.dizziness or source.is_damage_output_disabled()): return false
	if not POWER.has(kind): kind = "action"
	var key:String = str(source.get_instance_id())+":"+kind
	if float(_next_event.get(key,-1.0))>clock: return false
	_next_event[key] = clock+(0.25 if kind=="attack" else 0.20 if kind=="collision" else 0.14)
	var origin:Vector2 = source.global_position if not point.is_finite() else point
	for listener:Node in get_tree().get_nodes_in_group("MCWardenListener"):
		if is_instance_valid(listener) and not listener.is_queued_for_deletion():
			listener.hear_noise(source,origin,kind,float(POWER[kind]))
	return true
func sample_actions() -> void:
	var positions:Dictionary = {}
	var projectiles:Dictionary = {}
	var regions:Dictionary = {}
	for source:Node in get_tree().get_nodes_in_group("Ball"):
		if not is_instance_valid(source) or source.is_queued_for_deletion() or source.health<=0 or not source.is_combat_runtime_active(): continue
		var id:int = source.get_instance_id()
		positions[id] = source.global_position
		if _positions.has(id) and source.global_position.distance_squared_to(_positions[id])>0.0001:
			publish(source,"move")
		# Emission itself is noisy even if a projectile later misses.
		if is_instance_valid(source.Master) and source.Master!=source:
			projectiles[id] = true
			if not _projectiles.has(id): publish(source.Master,"attack")
		# Independent attack controllers expose their active strike through this common interface.
		if source.has_method("get_debug_attack_regions") and not source.dizziness and source.Can_Attack:
			var active_regions:Variant = source.get_debug_attack_regions()
			var striking:bool = active_regions is Array and not active_regions.is_empty()
			regions[id] = striking
			if striking and (not bool(_regions_active.get(id,false)) or float(_region_repeat.get(id,0.0))<=clock):
				publish(source,"attack")
				_region_repeat[id] = clock+0.6
	_positions = positions
	_projectiles = projectiles
	_regions_active = regions
	for id:Variant in _region_repeat.keys():
		if not positions.has(id): _region_repeat.erase(id)
	for key:Variant in _next_event.keys():
		if float(_next_event[key])<clock-2.0: _next_event.erase(key)
func _on_damage(source:Node,_target:Node,amount:float,_before:float) -> void:
	if amount>0.0 and is_instance_valid(source): publish(source,"attack")
