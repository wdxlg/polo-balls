extends ball
var seen_kinds:Array[String] = []
var nested_damage:float = 0.0
func receive_positional_damage(damage:float,point:Vector2,ignore_block:bool = false,source:Node = null) -> bool:
	seen_kinds.append(str(get_meta("_combat_damage_kind","ordinary")))
	if nested_damage > 0.0:
		var nested:float = nested_damage
		nested_damage = 0.0
		receive_spatial_damage(nested,{"element":"fire","point":point},ignore_block,false)
	return super.receive_positional_damage(damage,point,ignore_block,source)

var spatial_calls:int = 0
var spatial_ratio:float = 1.0
func receive_spatial_damage(damage:float,space:Variant,ignore_block:bool = false,raw_health:bool = false) -> bool:
	spatial_calls += 1
	return super.receive_spatial_damage(damage*spatial_ratio,space,ignore_block,raw_health)
