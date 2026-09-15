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
