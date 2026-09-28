extends RefCounted

const EFFECTS = preload("res://scripts/effects/我的世界/mc_status_effects.gd")

const INSTANT_HEAL:String = "instant_heal"
const REGEN:String = "regen"
const POISON:String = "poison"
const INSTANT_DAMAGE:String = "instant_damage"
const WITHER:String = "wither"
const INVISIBILITY:String = "invisibility"
const SPEED:String = "speed"
const STRENGTH:String = "strength"
const SLOWNESS:String = "slowness"

const TEX_INSTANT_HEAL = preload("res://Images/characters/我的世界/女巫/药水_瞬间治疗.png")
const TEX_REGEN = preload("res://Images/characters/我的世界/女巫/药水_持续治疗.png")
const TEX_POISON = preload("res://Images/characters/我的世界/女巫/药水_中毒.png")
const TEX_INSTANT_DAMAGE = preload("res://Images/characters/我的世界/女巫/药水_瞬间伤害.png")
# 按用户要求：凋零药水使用虚弱药水图片，同时附带少量虚弱效果。
const TEX_WITHER = preload("res://Images/characters/我的世界/女巫/药水_虚弱.png")
const TEX_INVISIBILITY = preload("res://Images/characters/我的世界/女巫/药水_隐身.png")
const TEX_SPEED = preload("res://Images/characters/我的世界/女巫/药水_速度.png")
const TEX_STRENGTH = preload("res://Images/characters/我的世界/女巫/药水_力量.png")
const TEX_SLOWNESS = preload("res://Images/characters/我的世界/女巫/药水_缓慢.png")

const ALL:Array[String] = [
	INSTANT_HEAL,
	REGEN,
	POISON,
	INSTANT_DAMAGE,
	WITHER,
	INVISIBILITY,
	SPEED,
	STRENGTH,
	SLOWNESS,
]

const GOOD:Array[String] = [
	INSTANT_HEAL,
	REGEN,
	INVISIBILITY,
	SPEED,
	STRENGTH,
]


static func is_good(effect_type:String) -> bool:
	return EFFECTS.positive(effect_type)


static func is_healing_family(effect_type:String) -> bool:
	return effect_type == INSTANT_HEAL or effect_type == REGEN


static func is_damage_family(effect_type:String) -> bool:
	return effect_type == INSTANT_DAMAGE or effect_type == POISON


static func color_for(effect_type:String) -> Color:
	match effect_type:
		INSTANT_HEAL: return Color(1.0,0.20,0.46,1.0)
		REGEN: return Color(0.95,0.20,0.82,1.0)
		POISON: return Color(0.30,0.84,0.20,1.0)
		INSTANT_DAMAGE: return Color(0.34,0.08,0.46,1.0)
		WITHER: return Color(0.28,0.34,0.42,1.0)
		INVISIBILITY: return Color(0.66,0.82,0.98,1.0)
		SPEED: return Color(0.20,0.86,1.0,1.0)
		STRENGTH: return Color(0.92,0.16,0.10,1.0)
		SLOWNESS: return Color(0.36,0.48,0.73,1.0)
	return Color.WHITE


static func texture_for(effect_type:String) -> Texture2D:
	match effect_type:
		INSTANT_HEAL: return TEX_INSTANT_HEAL
		REGEN: return TEX_REGEN
		POISON: return TEX_POISON
		INSTANT_DAMAGE: return TEX_INSTANT_DAMAGE
		WITHER: return TEX_WITHER
		INVISIBILITY: return TEX_INVISIBILITY
		SPEED: return TEX_SPEED
		STRENGTH: return TEX_STRENGTH
		SLOWNESS: return TEX_SLOWNESS
	return TEX_INSTANT_HEAL


# All Witch throws are sources of the SAME 1.21.4 status implementation used
# by the beacon, Wither and Shulker. This file only chooses bottle artwork,
# defaults for *duration*, and the existing extra Weakness on Wither bottles.
# "level" is 1-based; -1 duration means use the Witch's existing lifetime.
static func apply_effect(target:ball,effect_type:String,source:Variant = null,level:int = 1,duration:float = -1.0,increase_level:bool = false) -> void:
	if target == null or not is_instance_valid(target) or target.health <= 0: return
	effect_type = EFFECTS.canonical(effect_type)
	var lifetime:float = duration
	if lifetime < 0.0:
		match effect_type:
			INSTANT_HEAL, INSTANT_DAMAGE: lifetime = 0.0
			REGEN, POISON: lifetime = INF
			WITHER: lifetime = 6.5
			INVISIBILITY: lifetime = 6.0
			SPEED, STRENGTH, SLOWNESS: lifetime = 8.0
			_: lifetime = 30.0
	var caster:Node = source as Node if source is Node and is_instance_valid(source) else null
	var grade:int = mini(EFFECTS.level_of(target,effect_type)+1,255) if increase_level and not EFFECTS.is_instant(effect_type) else level
	if not EFFECTS.apply_effect(target,effect_type,grade,lifetime,caster): return
	# The Witch's Wither bottle *also* carries Weakness. It is a distinct
	# canonical status, not a source-specific damage multiplier or fake tooltip.
	if effect_type == WITHER:
		var weakness_grade:int = mini(EFFECTS.level_of(target,"weakness")+1,255) if increase_level else level
		EFFECTS.apply_effect(target,"weakness",weakness_grade,lifetime,caster)


static func apply_stacking_effect(target:ball,effect_type:String,source:Variant = null) -> void:
	# Witch drinking, direct hits and EACH cloud pulse upgrade the current effective
	# level. Other callers (e.g. Trader invisibility) retain fixed-level apply_effect.
	# Instant effects have no persistent level to upgrade; do not invent a counter.
	if not is_instance_valid(target) or not target.is_multiplayer_authority(): return
	apply_effect(target,effect_type,source,1,-1.0,true)
