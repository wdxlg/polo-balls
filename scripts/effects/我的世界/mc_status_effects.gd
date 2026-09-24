extends RefCounted
## Java 1.21.4 mob effects. The level is ONE-based; the source selects only the
## target and lifetime, never the potency.  "regen" and "instant_heal" retain
## the two existing Witch IDs; canonical Java IDs are also accepted as aliases.
## No duration is stored in this catalog.  In particular, INF is a valid time.

const ICON_ROOT:String = "res://Images/UI/minecraft_tooltips/mob_effect/"
const SPECS:Dictionary = {
	"absorption": {"zh":"伤害吸收","en":"Absorption","sign":1},
	"bad_omen": {"zh":"不祥之兆","en":"Bad Omen","sign":-1},
	"blindness": {"zh":"失明","en":"Blindness","sign":-1},
	"conduit_power": {"zh":"潮涌能量","en":"Conduit Power","sign":1},
	"darkness": {"zh":"黑暗","en":"Darkness","sign":-1},
	"dolphins_grace": {"zh":"海豚的恩惠","en":"Dolphin's Grace","sign":1},
	"fire_resistance": {"zh":"防火","en":"Fire Resistance","sign":1},
	"glowing": {"zh":"发光","en":"Glowing","sign":-1},
	"haste": {"zh":"急迫","en":"Haste","sign":1},
	"health_boost": {"zh":"生命提升","en":"Health Boost","sign":1},
	"hero_of_the_village": {"zh":"村庄英雄","en":"Hero of the Village","sign":1},
	"hunger": {"zh":"饥饿","en":"Hunger","sign":-1},
	"infested": {"zh":"寄生","en":"Infested","sign":-1},
	"instant_damage": {"zh":"瞬间伤害","en":"Instant Damage","sign":-1},
	"instant_heal": {"zh":"瞬间治疗","en":"Instant Health","sign":1,"icon":"instant_health"},
	"invisibility": {"zh":"隐身","en":"Invisibility","sign":1},
	"jump_boost": {"zh":"跳跃提升","en":"Jump Boost","sign":1},
	"levitation": {"zh":"飘浮","en":"Levitation","sign":-1},
	"luck": {"zh":"幸运","en":"Luck","sign":1},
	"mining_fatigue": {"zh":"挖掘疲劳","en":"Mining Fatigue","sign":-1},
	"nausea": {"zh":"反胃","en":"Nausea","sign":-1},
	"night_vision": {"zh":"夜视","en":"Night Vision","sign":1},
	"oozing": {"zh":"渗浆","en":"Oozing","sign":-1},
	"poison": {"zh":"中毒","en":"Poison","sign":-1},
	"raid_omen": {"zh":"袭击之兆","en":"Raid Omen","sign":-1},
	"regen": {"zh":"生命恢复","en":"Regeneration","sign":1,"icon":"regeneration"},
	"resistance": {"zh":"抗性提升","en":"Resistance","sign":1},
	"saturation": {"zh":"饱和","en":"Saturation","sign":1},
	"slow_falling": {"zh":"缓降","en":"Slow Falling","sign":1},
	"slowness": {"zh":"缓慢","en":"Slowness","sign":-1},
	"speed": {"zh":"迅捷","en":"Speed","sign":1},
	"strength": {"zh":"力量","en":"Strength","sign":1},
	"trial_omen": {"zh":"试炼之兆","en":"Trial Omen","sign":-1},
	"unluck": {"zh":"霉运","en":"Bad Luck","sign":-1},
	"water_breathing": {"zh":"水下呼吸","en":"Water Breathing","sign":1},
	"weakness": {"zh":"虚弱","en":"Weakness","sign":-1},
	"weaving": {"zh":"盘丝","en":"Weaving","sign":-1},
	"wind_charged": {"zh":"蓄风","en":"Wind Charged","sign":-1},
	"wither": {"zh":"凋零","en":"Wither","sign":-1},
}

static func canonical(kind:String) -> String:
	var name:String = kind.trim_prefix("minecraft:")
	match name:
		"regeneration": return "regen"
		"instant_health": return "instant_heal"
	return name

static func all_kinds() -> Array[String]:
	var result:Array[String] = []
	for name:String in SPECS:
		result.append(name)
	return result

static func all_java_ids() -> Array[String]:
	var result:Array[String] = []
	for kind:String in all_kinds():
		result.append("regeneration" if kind == "regen" else ("instant_health" if kind == "instant_heal" else kind))
	return result

static func info(kind:String) -> Dictionary:
	return SPECS.get(canonical(kind),{})

static func icon(kind:String) -> Texture2D:
	var name:String = canonical(kind)
	if not SPECS.has(name): return null
	return load(ICON_ROOT + str(SPECS[name].get("icon",name)) + ".png") as Texture2D

static func positive(kind:String) -> bool:
	return int(info(kind).get("sign",-1)) > 0

static func node_name(kind:String) -> String:
	var name:String = canonical(kind)
	return "WitherStatus" if name == "wither" else "MinecraftStatus_" + name

static func current(target:ball,kind:String) -> Node:
	return target.get_node_or_null(node_name(kind)) if is_instance_valid(target) else null

static func level_of(target:ball,kind:String) -> int:
	var status:Node = current(target,kind)
	return int(status.get("level")) if status != null and not status.is_queued_for_deletion() and float(status.get("remaining")) > 0.0 else 0

static func active(target:ball,kind:String) -> bool:
	return level_of(target,kind) > 0

static func blocks_drowning(target:ball) -> bool:
	return active(target,"water_breathing") or active(target,"conduit_power")

static func is_instant(kind:String) -> bool:
	return canonical(kind) in ["instant_heal","instant_damage","saturation"]

## Pure potency calculation. These quantities NEVER depend on the source or
## duration. Regen/Poison pulse every 5 game ticks; Wither pulses once a second
## and resolves its percentage against the target's current max health.
## Environmental-only keys are exposed as data, not invented as combat Buffs.
static func properties(kind:String,level:int = 1) -> Dictionary:
	var name:String = canonical(kind)
	if not SPECS.has(name) or level < 1: return {}
	var n:int = mini(level,255)
	var value:Dictionary = {"kind":name,"level":n}
	match name:
		"speed": value["move"] = 1.0 + 0.2*n
		"slowness": value["move"] = maxf(0.0,1.0 - 0.2*n)
		"haste":
			value["attack_rate"] = 1.0 + 0.1*n
			value["mining_rate"] = 1.0 + 0.2*n
		"mining_fatigue": value["attack_rate"] = maxf(0.0,1.0 - 0.1*n)
		"strength": value["damage_multiplier"] = 1.0 + 0.1*n
		"weakness": value["damage_multiplier"] = maxf(0.0,1.0 - 0.1*n)
		"resistance": value["damage_reduction"] = minf(1.0,0.2*n)
		"health_boost": value["extra_health"] = 20*n
		"absorption": value["absorption"] = 20*n
		"jump_boost":
			value["jump_strength"] = 0.1*n
			value["fall_damage_reduction"] = n
		"levitation": value["upward_acceleration"] = 0.05*n
		"instant_heal": value["instant_health"] = 50.0 * pow(2.0,mini(n-1,30))
		"instant_damage": value["instant_damage"] = 50.0 * pow(2.0,mini(n-1,30))
		"regen","poison":
			value["period_ticks"] = 5
			value["health_per_tick"] = float(n) if name == "regen" else -float(n)
		"wither":
			value["period_ticks"] = 20
			value["max_health_damage_per_second"] = 0.01*float(n)
		"fire_resistance": value["fire_immune"] = true
		"water_breathing": value["drowning_immune"] = true
		"conduit_power":
			value["drowning_immune"] = true
			value["underwater_vision"] = true
			value["underwater_mining_rate"] = 1.0 + 0.2*n
		"blindness": value["sight_blocks"] = 5
		"darkness": value["darkness"] = true
		"dolphins_grace": value["swim_speed"] = 9.8
		"glowing": value["outline_visible"] = true
		"invisibility":
			value["hidden_from_ai"] = true
			value["ignore_character_body_collision"] = true
		"night_vision": value["night_vision"] = true
		"nausea": value["camera_distortion"] = true
		"slow_falling": value["slow_fall"] = true
		"hunger": value["exhaustion_per_tick"] = 0.005*n
		"saturation": value["food_per_tick"] = n
		"luck": value["luck"] = n
		"unluck": value["luck"] = -n
		"infested":
			value["on_hurt_chance"] = 0.1
			value["silverfish_min"] = 1
			value["silverfish_max"] = 2
		"oozing": value["slimes_on_death"] = 2
		"weaving": value["webs_on_death"] = 3
		"wind_charged": value["wind_on_death"] = true
		"bad_omen","raid_omen","trial_omen","hero_of_the_village": value["event_level"] = n
	return value

## Per-source lifetimes, one visible potency. This prevents an expiring beacon
## from removing the Witch's longer Speed (or a skull from duplicating Wither).
static func remember_source(applications:Dictionary,source:Node,level:int,duration:float) -> void:
	var id:int = source.get_instance_id() if is_instance_valid(source) else 0
	var old:Dictionary = applications.get(id,{})
	if not old.is_empty() and level < int(old.grade): return
	applications[id] = {
		"grade":level,
		"time":maxf(float(old.get("time",0.0)),duration) if int(old.get("grade",level)) == level else duration,
		"source_ref":weakref(source) if is_instance_valid(source) else null,
	}

static func forget_source(applications:Dictionary,source:Node) -> void:
	if is_instance_valid(source): applications.erase(source.get_instance_id())

static func elapse_sources(applications:Dictionary,step:float) -> void:
	for id:int in applications.keys():
		var entry:Dictionary = applications[id]
		if not is_inf(float(entry.time)):
			entry.time = maxf(float(entry.time)-maxf(step,0.0),0.0)
		if float(entry.time) <= 0.0: applications.erase(id)
		else: applications[id] = entry

static func strongest_source(applications:Dictionary) -> Dictionary:
	var best:Dictionary = {}
	for entry:Dictionary in applications.values():
		if float(entry.time) <= 0.0: continue
		if best.is_empty() or int(entry.grade) > int(best.grade) or (int(entry.grade) == int(best.grade) and float(entry.time) > float(best.time)):
			best = entry
	return best

static func apply_effect(target:ball,kind:String,level:int = 1,duration:float = 30.0,source:Node = null) -> bool:
	var name:String = canonical(kind)
	if target == null or not is_instance_valid(target) or target.health <= 0 or not target.is_inside_tree(): return false
	if not SPECS.has(name) or level < 1 or is_nan(duration): return false
	if target.get_minecraft_potion_effect_ratio(positive(name)) <= 0.000001: return false
	if is_instant(name):
		_apply_instant(target,name,level,source)
		return true
	if duration <= 0.0: return false
	if name == "levitation":
		# The existing Shulker physics/ceiling implementation is the sole owner.
		(load("res://scripts/effects/我的世界/潜影浮空.gd") as GDScript).install(target,source,duration,level)
	else:
		var status:Node = current(target,name)
		if status != null and status.is_queued_for_deletion():
			# queue_free is deferred. Vacate its name before installing the next
			# source, otherwise Godot silently renames the live replacement.
			target.remove_child(status)
			status = null
		if status == null:
			var path:String = "res://scripts/characters/我的世界/wither/status.gd" if name == "wither" else "res://scripts/effects/我的世界/女巫药水状态.gd"
			status = (load(path) as GDScript).new()
			status.name = node_name(name)
			target.add_child(status)
			status.call("setup",target,name,duration,source,{},level)
		else:
			status.call("refresh",duration,source,{},level)
	if active(target,name):
		(load("res://scripts/ui/mc_active_effect_tooltip.gd") as GDScript).ensure(target)
	return active(target,name)

static func clear(target:ball,kind:String,source:Node = null) -> void:
	var status:Node = current(target,kind)
	if status == null or status.is_queued_for_deletion(): return
	# Remove only that caster's layer; another caster's lifetime survives.
	if source != null and status.has_method("remove_source"):
		status.call("remove_source",source)
		var tooltip_after:Node = target.get_node_or_null("Minecraft药水状态框")
		if tooltip_after != null: tooltip_after.call("refresh_display")
		return
	if source != null and status.get("source") != source: return
	if status.has_method("finish"): status.call("finish")
	else:
		status.set("remaining",0.0)
		status.queue_free()
	var tooltip:Node = target.get_node_or_null("Minecraft药水状态框")
	if tooltip != null: tooltip.call("refresh_display")

static func apply_runtime_buffs(target:ball,status:Node,kind:String,level:int) -> void:
	var tree:SceneTree = target.get_tree()
	var world:Node = tree.current_scene if tree != null else null
	if world == null or not world.has_method("new_buff") or not target.is_multiplayer_authority(): return
	var p:Dictionary = properties(kind,level)
	var ratio:float = target.get_minecraft_potion_effect_ratio(positive(kind))
	var key:String = "MC效果_"+canonical(kind)+"_"
	# Short-lived Buffs are renewed by the ONE active status and explicitly
	# erased on removal; they never outlive a beacon cancellation or level swap.
	if p.has("move"):
		var move_factor:float = maxf(0.0,1.0+(float(p.move)-1.0)*ratio)
		world.call("new_buff",target,status,key+"move",Buff.new(2,0.25,Buff.Buff_types.Speed,move_factor,Buff.Algorithms.mul))
	if p.has("attack_rate"):
		var rate:float = maxf(0.0,1.0+(float(p.attack_rate)-1.0)*ratio)
		world.call("new_buff",target,status,key+"attack",Buff.new(2,0.25,Buff.Buff_types.Attack_Cooling,1.0/maxf(rate,0.0001),Buff.Algorithms.mul))
	if p.has("damage_multiplier"):
		var damage_factor:float = maxf(0.0,1.0+(float(p.damage_multiplier)-1.0)*ratio)
		world.call("new_buff",target,status,key+"damage",Buff.new(1,0.25,Buff.Buff_types.Damage,damage_factor,Buff.Algorithms.mul))
	if p.has("damage_reduction"):
		world.call("new_buff",target,status,key+"resist",Buff.new(1,0.25,Buff.Buff_types.Damage_reduction,float(p.damage_reduction)*ratio,Buff.Algorithms.add))
	if p.has("extra_health"):
		world.call("new_buff",target,status,key+"health",Buff.new(1,0.25,Buff.Buff_types.Max_health,float(p.extra_health)*ratio,Buff.Algorithms.add))

static func _apply_instant(target:ball,kind:String,level:int,source:Node) -> void:
	var p:Dictionary = properties(kind,level)
	var ratio:float = target.get_minecraft_potion_effect_ratio(positive(kind))
	if kind == "saturation":
		# This game has an energy meter, but not Minecraft's hunger/food meter.
		# Deliberately do not invent an unrelated skill-energy restoration.
		return
	var inverted:bool = target.is_minecraft_potion_healing_damage_inverted()
	var amount:float = float(p.get("instant_health",p.get("instant_damage",0.0))) * ratio
	if (kind == "instant_heal") != inverted:
		target.heal(amount)
	else:
		var context:Dictionary = {"point":target.global_position,"shape":"all"}
		if is_instance_valid(source): context["source"] = source
		target.receive_spatial_raw_health_damage(amount,context)
