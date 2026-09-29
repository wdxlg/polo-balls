class_name Buff
extends RefCounted

enum Buff_types {
	Damage,
	Speed,
	max_block,
	max_energy,
	Max_health,
	Attack_Cooling,
	Skill_Cooling,
	Health_Restore,
	Damage_reduction,
	
	Infection,
	Attack_Amount,
	poison
}
enum Algorithms {
	add,
	mul,
	Set
}

var index:int = 0
var duration:float = 0
var buff_type:Buff_types
var amount
var algorithm:Algorithms

func _init(Index:int=0,Duration:float=0,Buff_type:Buff_types=Buff_types.Damage,Amount=0,Algorithm:Algorithms=Algorithms.add) -> void:
	index = Index
	duration = Duration
	buff_type = Buff_type
	amount = Amount
	algorithm = Algorithm

# Explicit polarity for future/non-stat effects: -1 negative, +1 positive,
# 0 uses the shared stat semantics below. Never infer from translated buff names.
var effect_polarity:int = 0
const BENEFIT_DIRECTION:Dictionary = {
	Buff_types.Damage:1, Buff_types.Speed:1, Buff_types.max_block:1,
	Buff_types.max_energy:1, Buff_types.Max_health:1, Buff_types.Attack_Cooling:-1,
	Buff_types.Skill_Cooling:-1, Buff_types.Health_Restore:1,
	Buff_types.Damage_reduction:1, Buff_types.Attack_Amount:1,
	Buff_types.Infection:-1, Buff_types.poison:-1,
}

func is_negative_for(target:Node) -> bool:
	if effect_polarity!=0: return effect_polarity<0
	if buff_type in [Buff_types.Infection,Buff_types.poison]: return true
	if not BENEFIT_DIRECTION.has(buff_type) or not (amount is int or amount is float): return false
	var change:float = float(amount)
	if algorithm==Algorithms.mul: change -= 1.0
	elif algorithm==Algorithms.Set:
		var property:String = str(Buff_types.find_key(buff_type))
		var baseline:float = float(target.default_properties.get(property,target.get(property) if property in target else 0.0))
		change -= baseline
	return change*int(BENEFIT_DIRECTION[buff_type]) < -0.000001
