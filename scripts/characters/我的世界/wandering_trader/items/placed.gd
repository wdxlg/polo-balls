extends Node2D
## Base for the trader's placed items (火药 / 蓝冰 / 滴水石锥 / 仙人掌). Lives in the battle scene,
## ages only while the battle runs, and only the authority copy (the trader's peer) applies
## gameplay; remote copies are visual. Nothing expires on its own (user rule 2026-09-29): an item
## stays until it is used up (gunpowder explodes) or the battle is reset (BattleTransient); it
## keeps working with its team even if the trader node is gone.
const CATALOG = preload("res://scripts/characters/我的世界/wandering_trader/items/catalog.gd")
const CRUMBS = preload("res://scripts/characters/我的世界/wandering_trader/items/crumbs.gd")
const AUDIO = preload("res://scripts/characters/我的世界/wandering_trader/audio.gd")
var trader_ref:WeakRef
var authoritative:bool = false
var kind:StringName = &""
var life:float = INF # no natural expiry
var team:String = ""
var age:float = 0.0
var data:Dictionary = {}
var _hit_wait:Dictionary = {} # unit instance id -> seconds until it can be hurt again
var _gone:bool = false

func setup(trader:Node2D,point:Vector2,extra:Dictionary,is_authority:bool) -> void:
	trader_ref = weakref(trader)
	team = str(trader.get(&"Team")) if is_instance_valid(trader) else ""
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

## Enemy of the trader's side (his team when he is gone).
func hostile(unit:Node) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(self,unit): return false # 皓宸复制品及其产物不把己方选为目标
	var owner_trader:Node2D = trader()
	if owner_trader != null: return CATALOG.enemy_of(owner_trader,unit)
	return is_instance_valid(unit) and not team.is_empty() and str(unit.get(&"Team")) != team

func sound(event:StringName,volume:float = 0.0) -> void:
	if not authoritative: return
	var owner_trader:Node2D = trader()
	if owner_trader != null: owner_trader.call(&"wt_sound",event,volume,global_position)
	else: AUDIO.play(self,event,global_position,volume,randf_range(0.92,1.08))
