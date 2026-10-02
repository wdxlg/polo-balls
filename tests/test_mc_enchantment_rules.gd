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
func near(value:Variant,expected:float) -> bool:
	return absf(float(value)-expected) < 0.0001
func run() -> void:
	var probes:Dictionary = {
		"aqua_affinity":["attack_rate","attack_rate_multiplier",{"in_water":true}],
		"bane_of_arthropods":["damage_out","damage",{"damage":10.0,"target_tags":["arthropod"]}],
		"blast_protection":["damage_in","damage",{"damage":100.0,"element":"explosion"}],
		"breach":["damage_out","armor_penetration",{"damage":10.0}],
		"channeling":["on_hit","lightning_radius",{"mode":"trident","wet":true}],
		"density":["damage_out","damage",{"damage":10.0,"current_speed":100.0}],
		"depth_strider":["move","speed_multiplier",{"in_water":true}],
		"efficiency":["attack_rate","attack_rate_multiplier",{}],
		"feather_falling":["damage_in","damage",{"damage":100.0,"element":"fall"}],
		"fire_aspect":["on_hit","burn_seconds",{"mode":"melee"}],
		"fire_protection":["damage_in","damage",{"damage":100.0,"element":"fire"}],
		"flame":["on_hit","burn_seconds",{"mode":"ranged"}],
		"fortune":["mine","extra_drops",{"base_drops":1}],
		"frost_walker":["move","freeze_radius",{"near_water":true}],
		"impaling":["body","ignore_character_collision",{}],
		"infinity":["shoot","consume_ammo",{}],
		"knockback":["on_hit","knockback_distance",{"mode":"melee"}],
		"looting":["on_kill","loot_multiplier",{}],
		"loyalty":["projectile","return_speed_multiplier",{}],
		"luck_of_the_sea":["fishing","treasure_weight",{}],
		"lunge":["projectile","spear_lunge_speed_multiplier",{}],
		"lure":["fishing","bite_wait_multiplier",{}],
		"mending":["on_kill","mending_health",{"victim_max_health":100.0}],
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
		"thorns":["on_hurt","retaliation_damage",{"taken_damage":100.0}],
		"unbreaking":["damage_in","unbreaking_immune",{"damage":100.0,"roll":0.0}],
		"wind_burst":["smash","wind_burst_distance",{}],
	}
	check(probes.size()==41 and probes.size()==CATALOG.all_ids().size(),"each of 41 supported IDs has an event contract")
	for id:String in probes:
		var probe:Array = probes[id]
		var original:Dictionary = RULES.resolve({},probe[0],probe[2])
		var changed:Dictionary = RULES.resolve({id:1},probe[0],probe[2])
		check(changed.has(probe[1]) and changed[probe[1]] != original.get(probe[1],null),id+" changes its event result at level one")
	var armor:Dictionary = RULES.resolve({"protection":1},"damage_in",{"damage":100.0})
	check(RULES.resolve({"protection":32767},"damage_in",{"damage":100.0}).damage < armor.damage,"protection continues strengthening up to 32767")
	check(RULES.resolve({"multishot":32767},"shoot").projectile_count <= 64 and RULES.resolve({"knockback":32767},"on_hit").knockback_distance <= 220,"entity counts and movement respect execution safety limits")
	check(not CATALOG.has_id("binding_curse") and not CATALOG.has_id("vanishing_curse") and RULES.clean({"binding_curse":1,"vanishing_curse":5}).is_empty(),"removed curses cannot be resolved from old saved data")
	check(near(RULES.resolve({"aqua_affinity":3},"attack_rate",{"in_water":true}).attack_rate_multiplier,1.3) and near(RULES.resolve({"aqua_affinity":3},"attack_rate",{"in_water":false}).attack_rate_multiplier,1.0),"Aqua Affinity grants 10% attack rate per level only in actual water")
	check(near(RULES.resolve({"efficiency":4},"attack_rate").attack_rate_multiplier,1.2) and near(RULES.resolve({"aqua_affinity":2,"efficiency":3},"attack_rate",{"in_water":true}).attack_rate_multiplier,1.35),"Efficiency grants 5% attack rate per level and adds to Aqua Affinity")
	check(near(RULES.resolve({"efficiency":3,"aqua_affinity":3},"mine",{"underwater":true,"hardness":2.0}).mining_rate,0.5) and RULES.resolve({"efficiency":32767},"attack_rate").attack_rate_multiplier <= 12.0,"these two enchants no longer boost mining and extreme attack rates stay safe")
	check(near(RULES.resolve({"bane_of_arthropods":3},"damage_out",{"damage":100.0,"target_tags":["arthropod"]}).damage,190.0) and near(RULES.resolve({"bane_of_arthropods":3},"damage_out",{"damage":100.0}).damage,100.0),"Bane grants 30% per level exclusively against arthropods")
	check(near(RULES.resolve({"bane_of_arthropods":1},"damage_out",{"damage":100.0,"mode":"ranged","target_tags":["arthropod"]}).damage,130.0),"arthropod bonus also follows an enchanted ranged hit")
	check(near(RULES.resolve({"density":2},"damage_out",{"damage":100.0,"current_speed":250.0}).damage,125.0) and near(RULES.resolve({"density":2},"damage_out",{"damage":100.0,"current_speed":0.0}).damage,100.0),"Density converts 5% of current Speed stat per level to attack")
	var breach:Dictionary = RULES.resolve({"breach":3},"damage_out",{"damage":100.0})
	check(near(breach.armor_penetration,0.15) and near(breach.shield_bypass,0.15) and near(RULES.resolve({"breach":1},"damage_out",{"damage":100.0,"mode":"ranged"}).shield_bypass,0.05),"Breach bypasses 5% of reduction and shields per level")
	check(near(RULES.resolve({"breach":32767},"damage_out",{"damage":100.0}).shield_bypass,1.0),"Breach bypass cannot exceed 100%")
	check(near(armor.damage,95.0) and near(RULES.resolve({"protection":2},"damage_in",{"damage":100.0}).damage,90.0),"ordinary Protection reduces all incoming damage 5% per level")
	for pair:Array in [["fire_protection","fire"],["blast_protection","explosion"],["projectile_protection","projectile"],["feather_falling","fall"]]:
		var damage:float = float(RULES.resolve({pair[0]:2},"damage_in",{"damage":100.0,"element":pair[1]}).damage)
		check(near(damage,80.0),"specialized protection %s reduces 10%% per level" % pair[0])
	check(near(RULES.resolve({"protection":1,"projectile_protection":1},"damage_in",{"damage":100.0,"element":"projectile"}).damage,85.5),"ordinary and specialized protection multiply without a second hidden scaling")
	check(near(RULES.resolve({"fire_protection":1},"damage_in",{"damage":100.0,"element":"fire"}).burn_time_multiplier,0.9) and near(RULES.resolve({"blast_protection":1},"damage_in",{"damage":100.0,"element":"explosion"}).explosion_push_multiplier,0.9),"fire duration and explosion push use the same 10% protection step")
	check(near(RULES.resolve({"depth_strider":3},"move",{"in_water":true}).speed_multiplier,1.3) and near(RULES.resolve({"depth_strider":3},"move",{"in_water":false}).speed_multiplier,1.0),"Depth Strider adds 10% movement speed per level only in real water")
	check(near(RULES.resolve({"fire_aspect":2},"on_hit",{"mode":"melee"}).burn_seconds,1.4) and near(RULES.resolve({"fire_aspect":2},"on_hit",{"mode":"ranged"}).burn_seconds,0.0),"Fire Aspect burns melee hits only")
	check(near(RULES.resolve({"flame":2},"on_hit",{"mode":"ranged"}).burn_seconds,1.4) and near(RULES.resolve({"flame":2},"on_hit",{"mode":"melee"}).burn_seconds,0.0),"Flame burns ranged hits only")
	check(near(RULES.resolve({"knockback":2},"on_hit",{"mode":"melee"}).knockback_distance,16.0) and near(RULES.resolve({"knockback":2},"on_hit",{"mode":"ranged"}).knockback_distance,0.0),"Knockback works on melee hits only")
	check(near(RULES.resolve({"punch":2},"on_hit",{"mode":"ranged"}).knockback_distance,12.0) and near(RULES.resolve({"punch":2},"on_hit",{"mode":"melee"}).knockback_distance,0.0),"Punch works on ranged hits only")
	check(near(RULES.resolve({"thorns":2},"on_hurt",{"taken_damage":40.0}).retaliation_damage,4.0) and near(RULES.resolve({"thorns":2},"on_hurt",{"taken_damage":0.0}).retaliation_damage,0.0),"Thorns reflects 5% per level of actual shield plus health lost")
	# Signed levels: user-facing values and the inverse (negative-level) mirror of each effect.
	check(near(RULES.resolve({"sharpness":3},"damage_out",{"damage":100.0,"mode":"melee"}).damage,130.0) and near(RULES.resolve({"sharpness":3},"damage_out",{"damage":100.0,"mode":"ranged"}).damage,100.0),"Sharpness adds 10% per level to melee only, like Power")
	check(near(RULES.resolve({"power":3},"damage_out",{"damage":100.0,"mode":"ranged"}).damage,130.0),"Power adds 10% per level to ranged hits")
	check(near(RULES.resolve({"smite":2},"damage_out",{"damage":100.0,"target_tags":["undead"]}).damage,160.0) and near(RULES.resolve({"smite":2},"damage_out",{"damage":100.0}).damage,100.0),"Smite adds 30% per level against undead only")
	check(near(RULES.resolve({"sharpness":-3},"damage_out",{"damage":100.0}).damage,70.0) and near(RULES.resolve({"sharpness":-20},"damage_out",{"damage":100.0}).damage,0.0),"inverse Sharpness lowers damage and never below zero")
	check(near(RULES.resolve({"mending":2},"on_kill",{"victim_max_health":200.0}).mending_health,20.0) and near(RULES.resolve({"mending":-1},"on_kill",{"victim_max_health":200.0}).mending_health,-10.0),"Mending heals 5% of the victim max health per level; inverse loses it")
	check(RULES.resolve({"unbreaking":30},"damage_in",{"damage":100.0,"roll":0.2}).damage == 0.0 and near(RULES.resolve({"unbreaking":30},"damage_in",{"damage":100.0,"roll":0.5}).damage,100.0),"Unbreaking gives a 1% per level chance to ignore a hit")
	check(near(RULES.resolve({"unbreaking":-30},"damage_in",{"damage":100.0,"roll":0.2}).damage,200.0),"inverse Unbreaking doubles a hit with 1% per level")
	check(RULES.multishot_angles(1).size() == 2 and near(rad_to_deg(RULES.multishot_angles(1)[0]),-45.0) and near(rad_to_deg(RULES.multishot_angles(1)[1]),45.0),"Multishot I: two shots at -45 and +45 degrees")
	check(RULES.multishot_angles(2).size() == 3 and near(rad_to_deg(RULES.multishot_angles(2)[1]),0.0) and RULES.multishot_angles(3).size() == 4 and near(rad_to_deg(RULES.multishot_angles(3)[1]),-15.0),"Multishot II/III spread 3/4 shots evenly over 90 degrees")
	check(near(RULES.resolve({"multishot":-1},"shoot").projectile_keep_chance,0.5) and near(RULES.resolve({"multishot":-3},"shoot").projectile_keep_chance,0.25),"inverse Multishot keeps each shot with 1/(|n|+1)")
	check(int(RULES.resolve({"piercing":2},"shoot").pierce_targets) == 2 and near(RULES.resolve({"piercing":-3},"shoot").fizzle_chance,0.3),"Piercing passes n characters; inverse shatters 10% per level")
	check(near(RULES.charge_speed(2),1.2) and near(RULES.charge_speed(-20),0.1),"Quick Charge adds 10% charge speed per level, inverse floors at 0.1")
	var inverse_hit:Dictionary = RULES.resolve({"knockback":-2,"fire_aspect":-2},"on_hit",{"mode":"melee"})
	check(near(inverse_hit.knockback_distance,-16.0) and near(inverse_hit.burn_seconds,0.0) and near(inverse_hit.self_burn_seconds,1.4),"inverse Knockback pulls and inverse Fire Aspect burns the attacker")
	check(near(RULES.resolve({"thorns":-2},"on_hurt",{"taken_damage":40.0}).attacker_heal,4.0) and near(RULES.resolve({"thorns":-2},"on_hurt",{"taken_damage":40.0}).retaliation_damage,0.0),"inverse Thorns heals the attacker")
	var inverse_breach:Dictionary = RULES.resolve({"breach":-2},"damage_out",{"damage":100.0})
	check(near(inverse_breach.armor_penetration,-0.1) and near(inverse_breach.shield_bypass,0.0),"inverse Breach raises the target reduction")
	check(near(RULES.resolve({"protection":-2},"damage_in",{"damage":100.0}).damage,110.0),"inverse Protection increases damage taken")
	check(near(RULES.resolve({"efficiency":-10},"attack_rate").attack_rate_multiplier,0.5) and near(RULES.resolve({"efficiency":-100},"attack_rate").attack_rate_multiplier,0.1),"inverse Efficiency slows attacks down to 0.1")
	check(near(RULES.resolve({"soul_speed":-2},"move",{"on_soul":true}).speed_multiplier,0.4) and near(RULES.resolve({"soul_speed":-9},"move",{"on_soul":true}).speed_multiplier,0.1),"inverse Soul Speed sinks deeper into soul sand")
	check(RULES.resolve({"impaling":2},"body").ignore_character_collision and RULES.resolve({"impaling":-1},"body").bounce_on_character,"Impaling ignores character collision; inverse bounces off")
	check(RULES.clean({"sharpness":-3,"power":0}) == {"sharpness":-3},"clean keeps negative levels and drops 0")
	check(CATALOG.display_level(-3) == "-3" and CATALOG.display_level(4) == "IV" and CATALOG.level_color(-1) != CATALOG.level_color(1),"negative levels show -N in red")
	print("MC ENCHANT RULES RESULT checks=",checks," failures=",fails)
	quit(0 if fails==0 else 1)
