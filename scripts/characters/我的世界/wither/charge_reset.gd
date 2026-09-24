extends Node
## A Wither charge uses the shared terrain manager; restore its damage when a
## new battle/rematch begins. World increments this generation before clearing
## actors. Do not hook a particular Wither lifetime (it may die mid-round).
var _generation:int = -1

static func ensure(context:Node) -> void:
	var world:Node = context.get_tree().current_scene
	if world == null: return
	if world.get_node_or_null("WitherChargeTerrainReset") != null: return
	var watcher:Node = load("res://scripts/characters/我的世界/wither/charge_reset.gd").new()
	watcher.name = "WitherChargeTerrainReset"
	watcher._generation = int(world.get("_mc_placement_generation"))
	watcher.process_mode = Node.PROCESS_MODE_ALWAYS
	world.add_child(watcher)

func _process(_delta:float) -> void:
	var world:Node = get_parent()
	if world == null or not world.is_inside_tree(): return
	var current:int = int(world.get("_mc_placement_generation"))
	if current == _generation: return
	_generation = current
	var manager:Node = world.get_node_or_null("GhastObstacleDamage")
	if manager != null: manager.reset_all()
