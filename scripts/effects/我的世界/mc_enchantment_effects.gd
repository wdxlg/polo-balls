extends RefCounted
## Event resolver for all Java enchantments. This is deterministic: callers provide
## context (damage type, item, biome, roll) and execute returned actions once.
## Native arena adapters call it for hits; systems not yet present use the same API.
const CATALOG = preload("res://scripts/effects/我的世界/mc_enchantment_catalog.gd")
const MAX_LEVEL:int = 32767
const MAX_DAMAGE:float = 10000000.0

static func clean(values:Dictionary) -> Dictionary:
	var result:Dictionary = {}
	for raw:Variant in values:
		var id:String = CATALOG.canonical(str(raw))
		if CATALOG.has_id(id) and values[raw] is int and int(values[raw]) >= 1 and int(values[raw]) <= MAX_LEVEL:
			result[id] = values[raw]
	return result

static func level(values:Dictionary,id:String) -> int:
	return clampi(int(values.get(id,0)),0,MAX_LEVEL)

static func _factor(n:int,per_level:float) -> float:
	return 1.0/(1.0+per_level*float(n))

static func _bounded(value:float,low:float,high:float) -> float:
	return clampf(value,low,high)

## The context returned is a COPY. Supported events/keys are documented in docs/MC_ENCHANTMENTS.md.
## A result always contains event-specific values; no mutating a target from pure calculation.
static func resolve(values:Dictionary,event:String,context:Dictionary = {}) -> Dictionary:
	var v:Dictionary = clean(values)
	var result:Dictionary = context.duplicate(true)
	var mode:String = str(context.get("mode","melee"))
	var element:String = str(context.get("element","physical"))
	var tags:Array = context.get("target_tags",[])
	var n:int
	match event:
		"damage_out":
			var damage:float = maxf(float(context.get("damage",0.0)),0.0)
			if mode == "melee":
				damage += 0.5*level(v,"sharpness")
				if tags.has("undead"): damage += 1.0*level(v,"smite")
				if tags.has("arthropod"):
					damage += 1.0*level(v,"bane_of_arthropods")
					result["slow_seconds"] = _bounded(0.5+0.2*level(v,"bane_of_arthropods"),0.0,6.0)
				if bool(context.get("sweeping",false)):
					damage += minf(float(context.get("base_damage",damage))*0.08*level(v,"sweeping_edge"),MAX_DAMAGE)
				if mode == "melee" and level(v,"breach") > 0:
					result["armor_penetration"] = 1.0-_factor(level(v,"breach"),0.12)
			elif mode == "ranged":
				damage *= 1.0+0.10*level(v,"power")
			elif mode == "trident": damage += 0.6*level(v,"impaling")*(1.0 if bool(context.get("wet",false)) else 0.0)
			elif mode == "smash": damage += 0.5*level(v,"density")*maxf(float(context.get("fall_distance",0.0)),0.0)
			result["damage"] = minf(damage,MAX_DAMAGE)
		"damage_in":
			var incoming:float = maxf(float(context.get("damage",0.0)),0.0)
			incoming *= _factor(level(v,"protection"),0.045)
			match element:
				"fire": incoming *= _factor(level(v,"fire_protection"),0.08)
				"explosion": incoming *= _factor(level(v,"blast_protection"),0.08)
				"projectile": incoming *= _factor(level(v,"projectile_protection"),0.08)
				"fall": incoming *= _factor(level(v,"feather_falling"),0.10)
			result["damage"] = _bounded(incoming,0.0,MAX_DAMAGE)
			result["explosion_push_multiplier"] = _factor(level(v,"blast_protection"),0.035)
			result["burn_time_multiplier"] = _factor(level(v,"fire_protection"),0.06)
		"on_hit":
			var melee:bool = mode == "melee"
			var ranged:bool = mode == "ranged"
			result["knockback_distance"] = _bounded(8.0*level(v,"knockback") if melee else 6.0*level(v,"punch") if ranged else 0.0,0.0,220.0)
			result["burn_seconds"] = _bounded(0.7*level(v,"fire_aspect") if melee else 0.7*level(v,"flame") if ranged else 0.0,0.0,12.0)
			result["burn_damage"] = _bounded(0.5*float(level(v,"fire_aspect") if melee else level(v,"flame") if ranged else 0),0.0,200.0)
			result["stun_seconds"] = _bounded(0.025*level(v,"bane_of_arthropods") if melee and tags.has("arthropod") else 0.0,0.0,3.0)
			result["chain_lightning"] = mode == "trident" and bool(context.get("wet",false)) and level(v,"channeling") > 0
			result["lightning_radius"] = _bounded(12.0+level(v,"channeling")*3.0,12.0,120.0) if result["chain_lightning"] else 0.0
		"on_hurt":
			result["retaliation_damage"] = _bounded(0.8*level(v,"thorns"),0.0,MAX_DAMAGE)
		"on_kill":
			result["loot_multiplier"] = 1.0+0.08*level(v,"looting")
			result["xp_multiplier"] = 1.0+0.04*level(v,"looting")
			result["drop_item"] = level(v,"vanishing_curse") == 0
		"equipment":
			result["can_unequip"] = not bool(context.get("alive",true)) or level(v,"binding_curse") == 0
			result["drop_on_death"] = level(v,"vanishing_curse") == 0
		"wear":
			var roll:float = _bounded(float(context.get("roll",0.5)),0.0,1.0)
			result["consume_durability"] = roll < _factor(level(v,"unbreaking"),1.0)
		"experience":
			var xp:float = maxf(float(context.get("xp",0.0)),0.0)
			var missing:float = maxf(float(context.get("missing_durability",0.0)),0.0)
			result["repair"] = minf(missing,xp*2.0*(1.0+0.05*level(v,"mending"))) if level(v,"mending")>0 else 0.0
		"mine":
			var hardness:float = maxf(float(context.get("hardness",1.0)),0.01)
			result["mining_rate"] = _bounded((1.0+0.12*level(v,"efficiency"))*(1.0+0.12*level(v,"aqua_affinity") if bool(context.get("underwater",false)) else 1.0),1.0,12.0)/hardness
			result["drop_original"] = level(v,"silk_touch") > 0
			result["extra_drops"] = 0 if result["drop_original"] else mini(int(context.get("base_drops",1))*level(v,"fortune"),64)
		"move":
			var move_factor:float = 1.0
			if bool(context.get("in_water",false)): move_factor += 0.05*level(v,"depth_strider")
			if bool(context.get("on_soul",false)): move_factor += 0.05*level(v,"soul_speed")
			if bool(context.get("sneaking",false)): move_factor += 0.05*level(v,"swift_sneak")
			result["speed_multiplier"] = _bounded(move_factor,1.0,4.0)
			result["freeze_radius"] = _bounded(float(level(v,"frost_walker"))*0.3,0.0,8.0) if bool(context.get("near_water",false)) else 0.0
		"oxygen":
			result["oxygen_loss_multiplier"] = _factor(level(v,"respiration"),0.12)
		"fishing":
			result["bite_wait_multiplier"] = _factor(level(v,"lure"),0.10)
			result["treasure_weight"] = 1.0+0.1*level(v,"luck_of_the_sea")
		"shoot":
			result["projectile_count"] = mini(1+2*level(v,"multishot"),9)
			result["pierce_targets"] = mini(level(v,"piercing"),32)
			result["charge_time_multiplier"] = _factor(level(v,"quick_charge"),0.10)
			result["consume_ammo"] = level(v,"infinity")==0 or not bool(context.get("is_arrow",true))
		"projectile":
			result["return_speed_multiplier"] = _bounded(1.0+0.1*level(v,"loyalty"),1.0,5.0)
			result["water_dash_speed_multiplier"] = _bounded(1.0+0.1*level(v,"riptide"),1.0,5.0) if bool(context.get("wet",false)) else 1.0
			result["spear_lunge_speed_multiplier"] = _bounded(1.0+0.12*level(v,"lunge"),1.0,5.0)
		"smash":
			result["wind_burst_distance"] = _bounded(6.0*level(v,"wind_burst"),0.0,240.0)
		"visual":
			result["underwater_visibility"] = _bounded(1.0+0.08*level(v,"respiration"),1.0,3.0)
		"enchant_info":
			result["catalog_size"] = CATALOG.all_ids().size()
	return result
