extends Node
const GEOMETRY = preload("res://scripts/effects/我的世界/mc16_geometry.gd")
var _pulse_left:float = 0.5
var last_pair_count:int = 0
static func attach(world:Node) -> Node:
	var manager:Node = world.get_node_or_null("MCTridentNetwork")
	if manager==null:
		manager = load("res://scripts/effects/我的世界/trident_network.gd").new()
		manager.name = "MCTridentNetwork"
		world.add_child(manager)
		manager.add_to_group("BattleTransient")
	return manager
func _physics_process(delta:float) -> void:
	if Game.now_stop_state or get_tree().paused: return
	var casters:Array[Node] = get_tree().get_nodes_in_group("MCDrowned")
	if casters.is_empty():
		queue_free()
		return
	var active:bool = false
	for unit:Node in casters:
		if unit.health>0 and unit.is_combat_runtime_active(): active = true; break
	if not active: return
	_pulse_left -= delta
	if _pulse_left<=0.0:
		_pulse_left = pulse()
func endpoints() -> Array[Node]:
	var result:Array[Node] = []
	for spear:Node in get_tree().get_nodes_in_group("MCTrident"):
		if spear.charged and spear.eligible(): result.append(spear)
	result.sort_custom(func(a:Node,b:Node) -> bool: return a.key()<b.key())
	return result
func pulse() -> float:
	if Game.now_stop_state or get_tree().paused: return 0.1
	var charged:Array[Node] = endpoints()
	var interval:float = INF
	last_pair_count = 0
	# One unordered pair only; each team gets a complete graph, not just nearest neighbors.
	for i:int in range(charged.size()):
		var a:Node = charged[i]
		interval = minf(interval,maxf(a.unit.network_interval,0.2))
		for j:int in range(i+1,charged.size()):
			var b:Node = charged[j]
			if not GEOMETRY.same_team(a.unit,b.unit): continue
			if not a.unit.mc_live(): continue
			last_pair_count += 1
			a.unit.emit_trident_arc(a,b)
	return 2.0 if charged.is_empty() else interval
