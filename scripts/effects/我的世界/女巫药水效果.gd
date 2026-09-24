extends RefCounted

const STATUS_SCRIPT = preload("res://scripts/effects/我的世界/女巫药水状态.gd")
const DAMAGE_SFX = preload("res://scripts/effects/我的世界/女巫药水伤害音效.gd")
const ACTIVE_TOOLTIP = preload("res://scripts/ui/mc_active_effect_tooltip.gd")

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
	return effect_type in GOOD


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


# Minecraft 药水统一从 ball 的公共效果倍率读取：
# 最终正/负面药水倍率 = 通用正/负面倍率 × Minecraft 药水专用倍率。
# 0 会在任何状态、粒子或 Buff 创建前直接拒绝，是真正的“免疫”。
static func apply_effect(target:ball,effect_type:String,source:Variant = null) -> void:
	if target == null or not is_instance_valid(target) or target.health <= 0:
		return
	var positive:bool = is_good(effect_type)
	var effect_ratio:float = _potion_effect_ratio(target,positive)
	if effect_ratio <= 0.000001:
		return

	var source_node:Node = _valid_source_node(source)
	var inverted:bool = _healing_damage_inverted(target)
	var particle_options:Dictionary = {
		"particle_color": color_for(effect_type),
		"particle_interval": 0.18,
	}

	match effect_type:
		INSTANT_HEAL:
			var heal_amount:float = 55.0 * effect_ratio
			if inverted:
				_apply_raw_damage(target,heal_amount,source_node)
			else:
				target.heal(heal_amount)
		REGEN:
			# 不再借用永久 Health_Restore Buff；由药水状态自己每秒结算，
			# 这样反转目标可以把同一“恢复”稳定转换成持续伤害。
			var regen_options:Dictionary = particle_options.duplicate()
			regen_options["regen_amount"] = 7.0
			_ensure_status(target,REGEN,INF,source_node,regen_options)
		POISON:
			var poison_options:Dictionary = particle_options.duplicate()
			poison_options["poison_damage"] = 6.0
			_ensure_status(target,POISON,INF,source_node,poison_options)
		INSTANT_DAMAGE:
			var amount:float = _scaled_damage(source_node,36.0,1.8) * effect_ratio
			if inverted:
				target.heal(amount)
			else:
				_apply_raw_damage(target,amount,source_node)
		WITHER:
			var wither_options:Dictionary = particle_options.duplicate()
			wither_options["wither_damage"] = _scaled_damage(source_node,16.0,0.72)
			_ensure_status(target,WITHER,6.5,source_node,wither_options)
			# 乘法型效果按“偏离中性 1.0 的幅度”缩放，而不是直接把 0.82 再乘倍率。
			var weak_mul:float = _scaled_mul_from_neutral(target,0.82,effect_ratio)
			_apply_buff(target,"女巫_凋零虚弱",Buff.new(2,6.5,Buff.Buff_types.Damage,weak_mul,Buff.Algorithms.mul))
		INVISIBILITY:
			var invis_options:Dictionary = particle_options.duplicate()
			invis_options["invis_alpha"] = clampf(_scaled_mul_from_neutral(target,0.22,effect_ratio),0.02,1.0)
			_ensure_status(target,INVISIBILITY,6.0,source_node,invis_options)
		SPEED:
			var speed_mul:float = _scaled_mul_from_neutral(target,1.35,effect_ratio)
			var cooldown_mul:float = _scaled_mul_from_neutral(target,0.78,effect_ratio)
			_apply_buff(target,"女巫_速度",Buff.new(2,8.0,Buff.Buff_types.Speed,speed_mul,Buff.Algorithms.mul))
			_apply_buff(target,"女巫_攻速",Buff.new(2,8.0,Buff.Buff_types.Attack_Cooling,cooldown_mul,Buff.Algorithms.mul))
			_ensure_status(target,SPEED,8.0,source_node,particle_options)
		STRENGTH:
			var strength_mul:float = _scaled_mul_from_neutral(target,1.45,effect_ratio)
			_apply_buff(target,"女巫_力量",Buff.new(2,8.0,Buff.Buff_types.Damage,strength_mul,Buff.Algorithms.mul))
			_ensure_status(target,STRENGTH,8.0,source_node,particle_options)
		SLOWNESS:
			var slow_mul:float = _scaled_mul_from_neutral(target,0.58,effect_ratio)
			_apply_buff(target,"女巫_缓慢",Buff.new(2,8.0,Buff.Buff_types.Speed,slow_mul,Buff.Algorithms.mul))
			_ensure_status(target,SLOWNESS,8.0,source_node,particle_options)
	# Only actual sustained statuses appear. Instant healing/damage never leave
	# a misleading countdown; immune targets returned before any status creation.
	if effect_type != INSTANT_HEAL and effect_type != INSTANT_DAMAGE:
		ACTIVE_TOOLTIP.ensure(target)


static func _potion_effect_ratio(target:ball,positive:bool) -> float:
	if target == null or not is_instance_valid(target):
		return 1.0
	if target.has_method("get_minecraft_potion_effect_ratio"):
		return maxf(float(target.call("get_minecraft_potion_effect_ratio",positive)),0.0)
	return 1.0


static func _healing_damage_inverted(target:ball) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.has_method("is_minecraft_potion_healing_damage_inverted"):
		return bool(target.call("is_minecraft_potion_healing_damage_inverted"))
	return false


static func _scaled_mul_from_neutral(target:ball,value:float,ratio:float) -> float:
	if target != null and is_instance_valid(target) and target.has_method("scale_effect_from_neutral"):
		return float(target.call("scale_effect_from_neutral",value,1.0,ratio))
	return 1.0 + (value - 1.0) * maxf(ratio,0.0)


static func _valid_source_node(candidate:Variant) -> Node:
	if candidate == null or not is_instance_valid(candidate):
		return null
	if candidate is Node:
		return candidate as Node
	return null


static func _scaled_damage(source:Node,fallback:float,multiplier:float) -> float:
	if is_instance_valid(source) and source is ball:
		return maxf((source as ball).attack_damage(multiplier),fallback)
	return fallback


static func _apply_raw_damage(target:ball,amount:float,source:Node) -> void:
	if amount <= 0.0 or target.health <= 0:
		return
	var context:Dictionary = {
		"point": target.global_position,
		"shape": "all",
	}
	if is_instance_valid(source):
		context["source"] = source
	var damage_applied:bool = target.receive_spatial_raw_health_damage(amount,context)
	if damage_applied:
		DAMAGE_SFX.play(target,target.global_position)


static func _apply_buff(target:ball,key:String,buff:Buff) -> void:
	var tree:SceneTree = target.get_tree()
	if tree == null:
		return
	var world:Node = tree.current_scene
	if world == null or not world.has_method("new_buff"):
		return
	# 用目标自身作为稳定来源键，施法者死亡后永久药效仍可独立存在。
	world.call("new_buff",target,target,key,buff,"cover")


static func _ensure_status(
	target:ball,
	effect_type:String,
	duration:float,
	source:Node,
	options:Dictionary
) -> void:
	var node_name:String = "WitchPotionStatus_%s" % effect_type
	var existing:Node = target.get_node_or_null(node_name)
	if existing != null and is_instance_valid(existing) and existing.has_method("refresh"):
		existing.call("refresh",duration,source,options)
		return
	var status:Node = STATUS_SCRIPT.new()
	status.name = node_name
	target.add_child(status)
	status.call("setup",target,effect_type,duration,source,options)
