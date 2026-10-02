extends RefCounted
## Event resolver for all Java enchantments. This is deterministic: callers provide
## context (damage type, item, biome, roll) and execute returned actions once.
## Levels are SIGNED: a negative level is the inverse enchantment (Enchanting Table
## curses) and every formula below mirrors its positive effect; 0 means absent.
const CATALOG = preload("res://scripts/effects/我的世界/mc_enchantment_catalog.gd")
const MAX_LEVEL:int = 32767
const MAX_DAMAGE:float = 10000000.0

static func clean(values:Dictionary) -> Dictionary:
	var result:Dictionary = {}
	for raw:Variant in values:
		var id:String = CATALOG.canonical(str(raw))
		if CATALOG.has_id(id) and values[raw] is int and absi(int(values[raw])) <= MAX_LEVEL and CATALOG.clamp_level(id,int(values[raw])) != 0:
			result[id] = CATALOG.clamp_level(id,int(values[raw]))
	return result

static func level(values:Dictionary,id:String) -> int:
	return clampi(int(values.get(id,0)),-MAX_LEVEL,MAX_LEVEL)

static func _factor(n:int,per_level:float) -> float:
	return 1.0/(1.0+per_level*float(maxi(n,0)))

static func _bounded(value:float,low:float,high:float) -> float:
	return clampf(value,low,high)

static func _remaining(n:int,per_level:float) -> float:
	# Percentage-point reduction per level; negative levels add damage taken.
	return maxf(1.0-float(n)*per_level,0.0)

static func _scale(n:int,per_level:float) -> float:
	# Linear +x% per level; inverse levels lower it but never below zero.
	return maxf(1.0+float(n)*per_level,0.0)

## Charge speed multiplier for Quick Charge (+10% per level, never below 0.1).
static func charge_speed(n:int) -> float:
	return clampf(1.0+0.10*float(n),0.1,64.0)

## Multishot: n>0 turns each shot into n+1 shots; n<0 keeps a shot with 1/(|n|+1).
static func multishot_count(n:int) -> int:
	return mini(maxi(n,0)+1,64)

static func multishot_keep_chance(n:int) -> float:
	return 1.0 if n >= 0 else 1.0/float(1-n)

## Evenly spaced spread from -45 to +45 degrees (radians); one shot keeps its heading.
static func multishot_angles(n:int) -> Array[float]:
	var count:int = multishot_count(n)
	var result:Array[float] = []
	if count <= 1:
		result.append(0.0)
		return result
	for i:int in range(count):
		result.append(deg_to_rad(lerpf(-45.0,45.0,float(i)/float(count-1))))
	return result

## The context returned is a COPY. Supported events/keys are documented in MCP_CONTEXT.md.
## A result always contains event-specific values; no mutating a target from pure calculation.
static func resolve(values:Dictionary,event:String,context:Dictionary = {}) -> Dictionary:
	var v:Dictionary = clean(values)
	var result:Dictionary = context.duplicate(true)
	var mode:String = str(context.get("mode","melee"))
	var element:String = str(context.get("element","physical"))
	var tags:Array = context.get("target_tags",[])
	match event:
		"damage_out":
			var damage:float = maxf(float(context.get("damage",0.0)),0.0)
			if mode == "melee":
				damage *= _scale(level(v,"sharpness"),0.10)
				if bool(context.get("sweeping",false)):
					damage += minf(float(context.get("base_damage",damage))*0.08*maxi(level(v,"sweeping_edge"),0),MAX_DAMAGE)
			elif mode == "ranged":
				damage *= _scale(level(v,"power"),0.10)
			if tags.has("undead"): damage *= _scale(level(v,"smite"),0.30)
			if tags.has("arthropod"): damage *= _scale(level(v,"bane_of_arthropods"),0.30)
			# Speed is the actor's current Speed STAT (including buffs), not velocity.
			damage += maxf(float(context.get("current_speed",0.0)),0.0)*0.05*level(v,"density")
			var breach:int = level(v,"breach")
			if breach != 0:
				# Negative: the target's damage reduction is RAISED by the same amount.
				result["armor_penetration"] = clampf(0.05*breach,-1.0,1.0)
				result["shield_bypass"] = clampf(0.05*breach,0.0,1.0)
			result["damage"] = clampf(damage,0.0,MAX_DAMAGE)
		"damage_in":
			var incoming:float = maxf(float(context.get("damage",0.0)),0.0)
			incoming *= _remaining(level(v,"protection"),0.05)
			match element:
				"fire": incoming *= _remaining(level(v,"fire_protection"),0.10)
				"explosion": incoming *= _remaining(level(v,"blast_protection"),0.10)
				"projectile": incoming *= _remaining(level(v,"projectile_protection"),0.10)
				"fall": incoming *= _remaining(level(v,"feather_falling"),0.10)
			# Unbreaking: 1%/level to ignore this hit; inverse 1%/level to take it twice.
			var unbreaking:int = level(v,"unbreaking")
			var roll:float = clampf(float(context.get("roll",1.0)),0.0,1.0)
			result["unbreaking_immune"] = unbreaking > 0 and roll < minf(0.01*unbreaking,1.0)
			result["unbreaking_double"] = unbreaking < 0 and roll < minf(-0.01*unbreaking,1.0)
			if result["unbreaking_immune"]: incoming = 0.0
			elif result["unbreaking_double"]: incoming *= 2.0
			result["damage"] = _bounded(incoming,0.0,MAX_DAMAGE)
			result["explosion_push_multiplier"] = _remaining(level(v,"blast_protection"),0.10)
			result["burn_time_multiplier"] = _remaining(level(v,"fire_protection"),0.10)
		"on_hit":
			var melee:bool = mode == "melee"
			var ranged:bool = mode == "ranged"
			# Negative knockback/punch PULLS the target toward the attacker.
			result["knockback_distance"] = _bounded(8.0*level(v,"knockback") if melee else 6.0*level(v,"punch") if ranged else 0.0,-220.0,220.0)
			var fire:int = level(v,"fire_aspect") if melee else level(v,"flame") if ranged else 0
			result["burn_seconds"] = _bounded(0.7*fire,0.0,12.0)
			result["burn_damage"] = _bounded(0.5*float(fire),0.0,200.0)
			# Inverse Fire Aspect / Flame sets the ATTACKER itself on fire.
			result["self_burn_seconds"] = _bounded(-0.7*fire,0.0,12.0)
			result["self_burn_damage"] = _bounded(-0.5*float(fire),0.0,200.0)
			result["chain_lightning"] = mode == "trident" and bool(context.get("wet",false)) and level(v,"channeling") > 0
			result["lightning_radius"] = _bounded(12.0+level(v,"channeling")*3.0,12.0,120.0) if result["chain_lightning"] else 0.0
		"on_hurt":
			# Shield and health actually lost in THIS hit are both valid bases.
			var thorns:float = maxf(float(context.get("taken_damage",0.0)),0.0)*0.05*level(v,"thorns")
			result["retaliation_damage"] = _bounded(thorns,0.0,MAX_DAMAGE)
			# Inverse Thorns heals the attacker by the same amount.
			result["attacker_heal"] = _bounded(-thorns,0.0,MAX_DAMAGE)
		"on_kill":
			# Mending: heal 5% of the victim's max health per level; inverse loses it.
			result["mending_health"] = clampf(maxf(float(context.get("victim_max_health",0.0)),0.0)*0.05*level(v,"mending"),-MAX_DAMAGE,MAX_DAMAGE)
			result["loot_multiplier"] = 1.0+0.08*maxi(level(v,"looting"),0)
			result["xp_multiplier"] = 1.0+0.04*maxi(level(v,"looting"),0)
		"wear":
			var wear_roll:float = _bounded(float(context.get("roll",0.5)),0.0,1.0)
			result["consume_durability"] = wear_roll < _factor(level(v,"unbreaking"),1.0)
		"mine":
			var hardness:float = maxf(float(context.get("hardness",1.0)),0.01)
			result["mining_rate"] = 1.0/hardness
			result["drop_original"] = level(v,"silk_touch") > 0
			result["extra_drops"] = 0 if result["drop_original"] else mini(int(context.get("base_drops",1))*maxi(level(v,"fortune"),0),64)
		"move":
			var move_factor:float = 1.0
			if bool(context.get("in_water",false)): move_factor += 0.10*level(v,"depth_strider")
			if bool(context.get("sneaking",false)): move_factor += 0.05*level(v,"swift_sneak")
			# on_soul = standing on fully grown soul sand: 0.8 without Soul Speed; level 1 cancels it,
			# +0.2 per further level; inverse levels sink it by 0.2 per level (floor 0.1).
			if bool(context.get("on_soul",false)):
				var soul:int = level(v,"soul_speed")
				if soul > 0: move_factor *= 1.0+0.2*float(soul-1)
				else: move_factor *= maxf(0.8+0.2*float(soul),0.1)
			result["speed_multiplier"] = _bounded(move_factor,0.1,4.0)
			result["freeze_radius"] = _bounded(float(level(v,"frost_walker"))*0.3,0.0,8.0) if bool(context.get("near_water",false)) else 0.0
		"attack_rate":
			var rate:float = 1.0+0.05*level(v,"efficiency")
			if bool(context.get("in_water",false)): rate += 0.10*level(v,"aqua_affinity")
			result["attack_rate_multiplier"] = _bounded(rate,0.1,12.0)
		"oxygen":
			result["oxygen_loss_multiplier"] = _factor(level(v,"respiration"),0.12)
		"fishing":
			result["bite_wait_multiplier"] = _factor(level(v,"lure"),0.10)
			result["treasure_weight"] = 1.0+0.1*maxi(level(v,"luck_of_the_sea"),0)
		"shoot":
			var multishot:int = level(v,"multishot")
			result["projectile_count"] = multishot_count(multishot)
			result["projectile_keep_chance"] = multishot_keep_chance(multishot)
			var piercing:int = level(v,"piercing")
			result["pierce_targets"] = mini(maxi(piercing,0),64)
			# Inverse Piercing: 10%/level that the shot shatters harmlessly on its first character hit.
			result["fizzle_chance"] = clampf(-0.10*piercing,0.0,1.0)
			result["charge_speed_multiplier"] = charge_speed(level(v,"quick_charge"))
			result["charge_time_multiplier"] = 1.0/charge_speed(level(v,"quick_charge"))
			result["consume_ammo"] = level(v,"infinity") <= 0 or not bool(context.get("is_arrow",true))
		"body":
			# Impaling (levelless): ignore body collision with characters.
			result["ignore_character_collision"] = level(v,"impaling") > 0
		"projectile":
			result["return_speed_multiplier"] = _bounded(1.0+0.1*level(v,"loyalty"),0.1,5.0)
			result["water_dash_speed_multiplier"] = _bounded(1.0+0.1*level(v,"riptide"),0.1,5.0) if bool(context.get("wet",false)) else 1.0
			result["spear_lunge_speed_multiplier"] = _bounded(1.0+0.12*level(v,"lunge"),0.1,5.0)
		"smash":
			result["wind_burst_distance"] = _bounded(6.0*level(v,"wind_burst"),0.0,240.0)
		"visual":
			result["underwater_visibility"] = _bounded(1.0+0.08*level(v,"respiration"),1.0,3.0)
		"enchant_info":
			result["catalog_size"] = CATALOG.all_ids().size()
	return result
