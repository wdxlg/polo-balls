extends Node2D
## Base for the trader's placed items (火药 / 蓝冰 / 滴水石锥 / 仙人掌). Lives in the battle scene,
## ages only while the battle runs, and only the authority copy (the trader's peer) applies
## gameplay; remote copies are visual. Freed when its trader is gone (battle reset).
const CATALOG = preload("res://scripts/characters/我的世界/wandering_trader/items/catalog.gd")
const CRUMBS = preload("res://scripts/characters/我的世界/wandering_trader/items/crumbs.gd")
var trader_ref:WeakRef
var authoritative:bool = false
var kind:StringName = &""
var life:float = 20.0
var age:float = 0.0
var data:Dictionary = {}
var _hit_wait:Dictionary = {} # unit instance id -> seconds until it can be hurt again
var _gone:bool = false

func setup(trader:Node2D,point:Vector2,extra:Dictionary,is_authority:bool) -> void:
	trader_ref = weakref(trader)
	authoritative = is_authority
	data = extra
	global_position = point
	z_as_relative = false
	z_index = 2
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_to_group(&"MCWanderingTraderItem")
	add_to_group(&"BattleTransient")
	_placed()

func trader() -> Node2D:
	var node:Variant = trader_ref.get_ref() if trader_ref != null else null
	return node as Node2D if is_instance_valid(node) else null

func _physics_process(delta:float) -> void:
	if _gone: return
	if trader() == null:
		queue_free()
		return
	if CATALOG.paused(self): return
	age += delta
	for id:Variant in _hit_wait.keys():
		_hit_wait[id] = float(_hit_wait[id]) - delta
		if float(_hit_wait[id]) <= 0.0: _hit_wait.erase(id)
	_tick(delta)
	queue_redraw()
	if age >= life and not _gone: expire()

## True (and starts the per-unit cooldown) when this unit may be hurt now.
func ready_to_hit(unit:Node,cooldown:float) -> bool:
	var id:int = unit.get_instance_id()
	if _hit_wait.has(id): return false
	_hit_wait[id] = cooldown
	return true

func expire() -> void:
	if _gone: return
	_gone = true
	_removed()
	queue_free()

func _placed() -> void: pass
func _tick(_delta:float) -> void: pass
func _removed() -> void: pass

func sound(event:StringName,volume:float = 0.0) -> void:
	var owner_trader:Node2D = trader()
	if owner_trader == null or not authoritative: return
	owner_trader.call(&"wt_sound",event,volume,global_position)
