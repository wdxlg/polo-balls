extends SceneTree
const RULES = preload("res://scripts/effects/我的世界/mc_enchantment_effects.gd")
const CATALOG = preload("res://scripts/effects/我的世界/mc_enchantment_catalog.gd")
var checks:int = 0
var fails:int = 0
func _initialize() -> void: call_deferred("run")
func check(condition:bool,label:String) -> void:
	checks += 1
	if not condition:
		fails += 1
		printerr("ENCHANT FAIL: ",label)
func run() -> void:
	var probes:Dictionary = {
		"aqua_affinity":["mine","mining_rate",{"underwater":true}],
		"bane_of_arthropods":["damage_out","damage",{"damage":10.0,"target_tags":["arthropod"]}],
		"binding_curse":["equipment","can_unequip",{"alive":true}],
		"blast_protection":["damage_in","damage",{"damage":100.0,"element":"explosion"}],
		"breach":["damage_out","armor_penetration",{"damage":10.0}],
		"channeling":["on_hit","lightning_radius",{"mode":"trident","wet":true}],
		"density":["damage_out","damage",{"damage":10.0,"mode":"smash","fall_distance":4.0}],
		"depth_strider":["move","speed_multiplier",{"in_water":true}],
		"efficiency":["mine","mining_rate",{}],
		"feather_falling":["damage_in","damage",{"damage":100.0,"element":"fall"}],
		"fire_aspect":["on_hit","burn_seconds",{"mode":"melee"}],
		"fire_protection":["damage_in","damage",{"damage":100.0,"element":"fire"}],
		"flame":["on_hit","burn_seconds",{"mode":"ranged"}],
		"fortune":["mine","extra_drops",{"base_drops":1}],
		"frost_walker":["move","freeze_radius",{"near_water":true}],
		"impaling":["damage_out","damage",{"mode":"trident","wet":true,"damage":10.0}],
		"infinity":["shoot","consume_ammo",{}],
		"knockback":["on_hit","knockback_distance",{"mode":"melee"}],
		"looting":["on_kill","loot_multiplier",{}],
		"loyalty":["projectile","return_speed_multiplier",{}],
		"luck_of_the_sea":["fishing","treasure_weight",{}],
		"lunge":["projectile","spear_lunge_speed_multiplier",{}],
		"lure":["fishing","bite_wait_multiplier",{}],
		"mending":["experience","repair",{"xp":10.0,"missing_durability":1000.0}],
		"multishot":["shoot","projectile_count",{}],
		"piercing":["shoot","pierce_targets",{}],
		"power":["damage_out","damage",{"mode":"ranged","damage":10.0}],
		"projectile_protection":["damage_in","damage",{"damage":100.0,"element":"projectile"}],
		"protection":["damage_in","damage",{"damage":100.0}],
		"punch":["on_hit","knockback_distance",{"mode":"ranged"}],
		"quick_charge":["shoot","charge_time_multiplier",{}],
		"respiration":["oxygen","oxygen_loss_multiplier",{}],
		"riptide":["projectile","water_dash_speed_multiplier",{"wet":true}],
		"sharpness":["damage_out","damage",{"damage":10.0}],
		"silk_touch":["mine","drop_original",{}],
		"smite":["damage_out","damage",{"damage":10.0,"target_tags":["undead"]}],
		"soul_speed":["move","speed_multiplier",{"on_soul":true}],
		"sweeping_edge":["damage_out","damage",{"damage":10.0,"sweeping":true,"base_damage":10.0}],
		"swift_sneak":["move","speed_multiplier",{"sneaking":true}],
		"thorns":["on_hurt","retaliation_damage",{}],
		"unbreaking":["wear","consume_durability",{"roll":0.7}],
		"vanishing_curse":["on_kill","drop_item",{}],
		"wind_burst":["smash","wind_burst_distance",{}],
	}
	check(probes.size()==43 and probes.size()==CATALOG.all_ids().size(),"each of 43 catalog IDs has an event contract")
	for id:String in probes:
		var probe:Array = probes[id]
		var original:Dictionary = RULES.resolve({},probe[0],probe[2])
		var changed:Dictionary = RULES.resolve({id:1},probe[0],probe[2])
		check(changed.has(probe[1]) and changed[probe[1]] != original.get(probe[1],null),id+" changes its event result at level one")
	var armor:Dictionary = RULES.resolve({"protection":1},"damage_in",{"damage":100.0})
	check(RULES.resolve({"protection":32767},"damage_in",{"damage":100.0}).damage < armor.damage,"protection continues strengthening up to 32767")
	check(RULES.resolve({"multishot":32767},"shoot").projectile_count <= 9 and RULES.resolve({"knockback":32767},"on_hit").knockback_distance <= 220,"entity counts and movement respect execution safety limits")
	print("MC ENCHANT RULES RESULT checks=",checks," failures=",fails)
	quit(0 if fails==0 else 1)
