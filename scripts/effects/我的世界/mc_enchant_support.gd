extends RefCounted
## Enchantment support registry: which enchantment hooks each character's attacks really
## reach, and the per-target "effective enchantment" pool used by the Enchanting Table.
## SUPPORT is generated from tests/audit_mc_enchant_support.gd (real World fights) merged
## with the combat classification catalog; QUICK_CHARGE lists characters whose charge-up
## code multiplies its progress by mc_enchantments.charge_speed(). Rules: MCP_CONTEXT.md
## "附魔适配". New characters must be added here (tests/verify_mc_enchant_support.gd).
##
## Capability flags:
##   melee / ranged  hits reach the shared enchantment hook as melee / ranged attacks
##   fire            deals fire damage (Fire Protection matters to its opponents)
##   explosion       deals explosion damage (Blast Protection matters)
##   multishot       its shots are shaped by Multishot / Piercing (mc_enchant_projectiles.gd)
##   efficiency      its attack rate follows Attack_Cooling (Efficiency)
##   passive         deals no damage by itself (support, summoner, objects)
const CLASSIFY = preload("res://classes/combat_classification.gd")
const U = preload("res://scripts/characters/我的世界/new5/utils.gd")
const SOUL_SAND_FIELD_PATH:String = "res://scripts/characters/我的世界/torch/soul_sand_field.gd"
const TORCH_SCENE:String = "res://scenes/characters/我的世界/火把.tscn"
const ENCHANTS_PATH:String = "res://scripts/effects/我的世界/mc_enchantments.gd"
const CATALOG_PATH:String = "res://scripts/effects/我的世界/mc_enchantment_catalog.gd"

const SUPPORT:Dictionary = {
	"res://scenes/characters/meme/不坏煎饼.tscn": ["ranged"],
	"res://scenes/characters/meme/凑企鹅.tscn": ["melee", "ranged"],
	"res://scenes/characters/meme/愤怒的普通人.tscn": ["melee"],
	"res://scenes/characters/meme/棍母.tscn": ["melee"],
	"res://scenes/characters/meme/肌肉男.tscn": ["melee"],
	"res://scenes/characters/meme/菊花茶.tscn": ["melee", "ranged", "multishot"],
	"res://scenes/characters/meme/野生狗奶.tscn": ["melee"],
	"res://scenes/characters/三角洲/堵桥.tscn": ["ranged", "fire", "multishot"],
	"res://scenes/characters/三角洲/夺舍狼.tscn": ["efficiency"],
	"res://scenes/characters/三角洲/猛攻哥.tscn": ["ranged", "multishot"],
	"res://scenes/characters/三角洲/盾狗.tscn": ["melee", "efficiency"],
	"res://scenes/characters/三角洲/背刺鼠.tscn": ["ranged", "multishot"],
	"res://scenes/characters/乐队/户山香澄.tscn": ["melee", "efficiency"],
	"res://scenes/characters/乐队/薇欧拉.tscn": ["melee"],
	"res://scenes/characters/人物/NC佬.tscn": ["melee"],
	"res://scenes/characters/人物/伤心的男人.tscn": ["melee", "efficiency"],
	"res://scenes/characters/人物/伪军头子.tscn": ["melee", "ranged", "multishot"],
	"res://scenes/characters/人物/保安.tscn": ["melee", "efficiency"],
	"res://scenes/characters/人物/决斗者.tscn": ["melee", "efficiency"],
	"res://scenes/characters/人物/占卜师.tscn": ["melee", "efficiency"],
	"res://scenes/characters/人物/原始人.tscn": ["melee", "fire", "efficiency"],
	"res://scenes/characters/人物/国王.tscn": ["melee"],
	"res://scenes/characters/人物/小丑.tscn": ["ranged", "multishot", "efficiency"],
	"res://scenes/characters/人物/小偷.tscn": ["melee"],
	"res://scenes/characters/人物/布鲁斯.tscn": ["melee", "efficiency"],
	"res://scenes/characters/人物/建筑工人.tscn": ["ranged", "multishot"],
	"res://scenes/characters/人物/形态/疲倦的人_愤怒形态.tscn": ["melee", "efficiency"],
	"res://scenes/characters/人物/影子.tscn": ["melee", "efficiency"],
	"res://scenes/characters/人物/战斧重骑兵.tscn": ["melee"],
	"res://scenes/characters/人物/投资者.tscn": ["melee"],
	"res://scenes/characters/人物/拳击手.tscn": ["melee", "efficiency"],
	"res://scenes/characters/人物/掷骰子的人.tscn": ["ranged", "efficiency"],
	"res://scenes/characters/人物/收债人.tscn": ["ranged", "multishot"],
	"res://scenes/characters/人物/数学老师.tscn": ["ranged", "multishot"],
	"res://scenes/characters/人物/时光客.tscn": ["ranged", "multishot", "efficiency"],
	"res://scenes/characters/人物/极速者.tscn": ["melee"],
	"res://scenes/characters/人物/火车长.tscn": ["melee"],
	"res://scenes/characters/人物/炸弹客.tscn": ["ranged"],
	"res://scenes/characters/人物/猎人.tscn": ["ranged", "multishot", "efficiency"],
	"res://scenes/characters/人物/疲倦的人.tscn": ["melee", "efficiency"],
	"res://scenes/characters/人物/矿工.tscn": ["melee"],
	"res://scenes/characters/人物/科学家.tscn": ["ranged", "multishot", "efficiency"],
	"res://scenes/characters/人物/背刺者.tscn": ["efficiency"],
	"res://scenes/characters/人物/裁判.tscn": ["melee", "efficiency"],
	"res://scenes/characters/人物/训犬师.tscn": ["melee"],
	"res://scenes/characters/人物/赌徒.tscn": ["ranged", "multishot"],
	"res://scenes/characters/人物/醉汉.tscn": ["ranged", "multishot"],
	"res://scenes/characters/人物/重女.tscn": ["melee"],
	"res://scenes/characters/人物/键盘侠.tscn": ["ranged", "multishot", "efficiency"],
	"res://scenes/characters/人物/锻刀师.tscn": ["melee", "fire", "efficiency"],
	"res://scenes/characters/人物/镜子.tscn": ["melee"],
	"res://scenes/characters/人物/领导.tscn": ["melee", "efficiency"],
	"res://scenes/characters/人物/黑帮老大.tscn": ["melee", "ranged", "multishot"],
	"res://scenes/characters/人物/鼓手.tscn": ["melee"],
	"res://scenes/characters/传说之下/Sans.tscn": ["melee"],
	"res://scenes/characters/动漫/宿傩.tscn": ["melee", "fire"],
	"res://scenes/characters/动漫/菜月昴.tscn": ["melee"],
	"res://scenes/characters/动物/九头蛇.tscn": ["melee"],
	"res://scenes/characters/动物/兔子.tscn": ["melee"],
	"res://scenes/characters/动物/牛.tscn": ["melee"],
	"res://scenes/characters/动物/牛犊子.tscn": ["melee"],
	"res://scenes/characters/动物/猫.tscn": ["melee"],
	"res://scenes/characters/小弟/NC坦克.tscn": ["melee"],
	"res://scenes/characters/小弟/NC步枪兵.tscn": ["melee", "efficiency"],
	"res://scenes/characters/小弟/伪军.tscn": ["ranged", "multishot"],
	"res://scenes/characters/小弟/功夫小弟.tscn": ["melee"],
	"res://scenes/characters/小弟/国王守卫.tscn": ["melee"],
	"res://scenes/characters/小弟/国王将军.tscn": ["melee"],
	"res://scenes/characters/小弟/愤怒的人.tscn": ["melee"],
	"res://scenes/characters/小弟/拳头小混混.tscn": ["melee"],
	"res://scenes/characters/小弟/持刀小混混.tscn": ["melee"],
	"res://scenes/characters/小弟/铁棍小混混.tscn": ["efficiency"],
	"res://scenes/characters/小弟/黑帮小弟.tscn": ["melee", "efficiency"],
	"res://scenes/characters/小弟/黑帮持枪小弟.tscn": ["ranged", "multishot", "efficiency"],
	"res://scenes/characters/我的世界/三废石.tscn": ["ranged", "multishot", "efficiency"],
	"res://scenes/characters/我的世界/避雷针.tscn": ["melee"],
	"res://scenes/characters/我的世界/仙人掌.tscn": ["melee", "ranged", "multishot"],
	"res://scenes/characters/我的世界/凋灵.tscn": ["melee"],
	"res://scenes/characters/我的世界/凋灵骷髅.tscn": ["melee"],
	"res://scenes/characters/我的世界/卫道士.tscn": ["melee", "efficiency"],
	"res://scenes/characters/我的世界/史莱姆.tscn": ["melee"],
	"res://scenes/characters/我的世界/唤魔者.tscn": ["melee"],
	"res://scenes/characters/我的世界/唱片机.tscn": ["melee"],
	"res://scenes/characters/我的世界/天堂陨落长弓.tscn": ["melee", "ranged", "multishot"],
	"res://scenes/characters/我的世界/女巫.tscn": ["ranged", "multishot"],
	"res://scenes/characters/我的世界/守卫者.tscn": ["melee"],
	"res://scenes/characters/我的世界/山羊角.tscn": ["melee"],
	"res://scenes/characters/我的世界/弓.tscn": ["ranged", "multishot"],
	"res://scenes/characters/我的世界/恶魂.tscn": ["ranged", "multishot"],
	"res://scenes/characters/我的世界/悦灵.tscn": ["ranged", "multishot"],
	"res://scenes/characters/我的世界/时钟.tscn": ["melee", "efficiency"],
	"res://scenes/characters/我的世界/木剑.tscn": ["melee"],
	"res://scenes/characters/我的世界/木矛.tscn": ["melee", "efficiency"],
	"res://scenes/characters/我的世界/末影人.tscn": ["melee"],
	"res://scenes/characters/我的世界/流浪商人.tscn": ["ranged", "multishot"],
	"res://scenes/characters/我的世界/溺尸.tscn": ["ranged"],
	"res://scenes/characters/我的世界/潜影贝.tscn": ["ranged", "multishot"],
	"res://scenes/characters/我的世界/烈焰人.tscn": ["melee", "ranged", "fire", "multishot", "efficiency"],
	"res://scenes/characters/我的世界/石矛.tscn": ["melee", "efficiency"],
	"res://scenes/characters/我的世界/矿车.tscn": ["melee"],
	"res://scenes/characters/我的世界/硫方怪.tscn": ["melee", "efficiency"],
	"res://scenes/characters/我的世界/粘性活塞.tscn": ["melee"],
	"res://scenes/characters/我的世界/羊.tscn": ["melee", "efficiency"],
	"res://scenes/characters/我的世界/苔藓.tscn": ["efficiency"],
	"res://scenes/characters/我的世界/蝙蝠.tscn": ["melee"],
	"res://scenes/characters/我的世界/蠹虫.tscn": ["melee"],
	"res://scenes/characters/我的世界/重锤.tscn": ["melee"],
	"res://scenes/characters/我的世界/钓鱼竿.tscn": ["melee"],
	"res://scenes/characters/我的世界/钻石剑.tscn": ["melee"],
	"res://scenes/characters/我的世界/钻石长矛.tscn": ["melee", "efficiency"],
	"res://scenes/characters/我的世界/铁傀儡.tscn": ["melee"],
	"res://scenes/characters/我的世界/铁匠村民.tscn": ["melee"],
	"res://scenes/characters/我的世界/铜剑.tscn": ["melee", "efficiency"],
	"res://scenes/characters/我的世界/附魔台.tscn": ["ranged", "multishot", "efficiency"],
	"res://scenes/characters/我的世界/雪傀儡.tscn": ["ranged", "multishot", "efficiency"],
	"res://scenes/characters/我的世界/鞘翅重锤.tscn": ["melee"],
	"res://scenes/characters/我的世界/鞘翅重锤长矛.tscn": ["melee"],
	"res://scenes/characters/我的世界/鞘翅长矛.tscn": ["melee"],
	"res://scenes/characters/我的世界/骷髅.tscn": ["ranged", "multishot", "efficiency"],
	"res://scenes/characters/月计/伞夫.tscn": ["melee", "efficiency"],
	"res://scenes/characters/月计/堇紫泪滴.tscn": ["melee"],
	"res://scenes/characters/月计/殷红迷雾.tscn": ["melee"],
	"res://scenes/characters/杀戮尖塔/小刀猎.tscn": ["ranged", "multishot", "efficiency"],
	"res://scenes/characters/杀戮尖塔/异蛙寄生虫.tscn": ["melee"],
	"res://scenes/characters/杀戮尖塔/异蛙寄生虫_小.tscn": ["melee"],
	"res://scenes/characters/杀戮尖塔/战士.tscn": ["melee"],
	"res://scenes/characters/杀戮尖塔/猎人杀手.tscn": ["melee"],
	"res://scenes/characters/杀戮尖塔/虔诚雕刻师.tscn": ["melee"],
	"res://scenes/characters/杀戮尖塔/蛇咬相生猎.tscn": ["ranged", "multishot"],
	"res://scenes/characters/杀戮尖塔/蜂群术士.tscn": ["ranged", "multishot", "efficiency"],
	"res://scenes/characters/杀戮尖塔/观者.tscn": ["melee"],
	"res://scenes/characters/杀戮尖塔/锻剑储君.tscn": ["melee", "efficiency"],
	"res://scenes/characters/游戏/战争女神.tscn": ["melee", "fire", "efficiency"],
	"res://scenes/characters/游戏/魔角猎人.tscn": ["melee", "ranged", "fire", "multishot", "efficiency"],
	"res://scenes/characters/物品/气球.tscn": ["melee"],
	"res://scenes/characters/默认/丁某人睡觉.tscn": ["ranged", "multishot"],
	"res://scenes/characters/默认/弓箭盔甲架.tscn": ["ranged", "multishot", "efficiency"],
}

const QUICK_CHARGE:Array[String] = [
	"res://scenes/characters/乐队/薇欧拉.tscn",
	"res://scenes/characters/人物/军火商.tscn",
	"res://scenes/characters/人物/矿工.tscn",
	"res://scenes/characters/动漫/五条悟.tscn",
	"res://scenes/characters/我的世界/凋灵.tscn",
	"res://scenes/characters/我的世界/卫道士.tscn",
	"res://scenes/characters/我的世界/天堂陨落长弓.tscn",
	"res://scenes/characters/我的世界/守卫者.tscn",
	"res://scenes/characters/我的世界/弓.tscn",
	"res://scenes/characters/我的世界/木剑.tscn",
	"res://scenes/characters/我的世界/溺尸.tscn",
	"res://scenes/characters/我的世界/火把.tscn",
	"res://scenes/characters/我的世界/矿车.tscn",
	"res://scenes/characters/我的世界/羊.tscn",
	"res://scenes/characters/我的世界/苦力怕.tscn",
]

## Every enchantment the Enchanting Table may roll; each one has a real combat effect.
const COMBAT_POOL:Array[String] = [
	"protection","fire_protection","blast_protection","projectile_protection","unbreaking","thorns",
	"sharpness","knockback","fire_aspect","power","punch","flame","smite","bane_of_arthropods",
	"density","breach","mending","multishot","piercing","efficiency","quick_charge","impaling","soul_speed",
]

static func scene_of(unit:Node) -> String:
	return unit.scene_file_path if is_instance_valid(unit) else ""

## Capability flags of one unit. Audited rows win; a row without observed damage, and any
## scene missing from SUPPORT, takes its attack flags from the classification catalog.
## Fire always merges the catalog's damage_kinds (burn ticks count for Fire Protection).
static func capabilities(unit:Node) -> Array:
	var result:Array = (SUPPORT.get(scene_of(unit),[]) as Array).duplicate()
	var profile:Dictionary = CLASSIFY.profile_of(unit) if is_instance_valid(unit) else {}
	if not deals_damage(result):
		var modes:Array = profile.get("attack_modes",[])
		var carriers:Array = profile.get("carriers",[])
		if modes.has("melee") or carriers.has("body_contact") or carriers.has("weapon_sweep"): result.append("melee")
		if modes.has("ranged") or carriers.has("projectile"): result.append("ranged")
		if not deals_damage(result) and unit is ball and int((unit as ball).Damage) > 0 and bool((unit as ball).Has_Collision_Damage): result.append("melee")
	if not result.has("fire") and (profile.get("damage_kinds",[]) as Array).has("fire"): result.append("fire")
	if not deals_damage(result): result.append("passive")
	return result

static func deals_damage(caps:Array) -> bool:
	return caps.has("melee") or caps.has("ranged") or caps.has("fire") or caps.has("explosion")

static func has_quick_charge(unit:Node) -> bool:
	return QUICK_CHARGE.has(scene_of(unit))

## Live opponents of target (characters and summons that can fight it).
static func opponents(target:ball) -> Array:
	var result:Array = []
	if not is_instance_valid(target) or not target.is_inside_tree(): return result
	for raw:Node in target.get_tree().get_nodes_in_group("Ball"):
		if raw == target or not (raw is ball) or raw.is_queued_for_deletion(): continue
		var other:ball = raw as ball
		if other.health <= 0 or CLASSIFY.is_projectile(other): continue
		if other.Master == target or target.Master == other: continue
		if U.enemy(target,other): result.append(other)
	return result

static func _soul_sand_possible(target:ball) -> bool:
	if load(SOUL_SAND_FIELD_PATH).find(target) != null: return true
	for raw:Node in target.get_tree().get_nodes_in_group("Ball"):
		if raw is ball and raw.scene_file_path == TORCH_SCENE and (raw as ball).health > 0: return true
	return false

## Impaling lets the unit pass through characters, so it needs a live character it can
## physically touch.
static func _collides_with_characters(target:ball) -> bool:
	for raw:Node in target.get_tree().get_nodes_in_group("Ball"):
		if raw == target or not (raw is ball) or (raw as ball).health <= 0 or CLASSIFY.is_projectile(raw): continue
		if (target.collision_mask & (raw as ball).collision_layer) != 0 or ((raw as ball).collision_mask & target.collision_layer) != 0: return true
	return false

## Enchantments that actually change something for target right now. The same pool is used
## for positive (ally) and inverse (enemy) levels: both only matter where the effect exists.
## delta is the level about to be added: levelless enchantments (CATALOG.LEVELLESS) never go
## negative and never upgrade, so they leave the pool for delta < 0 and once already owned.
static func pool_for(target:ball,delta:int = 0) -> Array[String]:
	# Every id below is also listed in COMBAT_POOL (checked by tests/verify_mc_enchant_support.gd).
	var pool:Array[String] = []
	if not is_instance_valid(target): return pool
	var own:Array = capabilities(target)
	var attacks:bool = deals_damage(own)
	var enemies:Array = opponents(target)
	var enemy_damage:bool = false
	var enemy_ranged:bool = false
	var enemy_fire:bool = false
	var enemy_explosion:bool = false
	var undead_enemy:bool = false
	var arthropod_enemy:bool = false
	var enchants:Script = load(ENCHANTS_PATH)
	for other:ball in enemies:
		var caps:Array = capabilities(other)
		enemy_damage = enemy_damage or deals_damage(caps)
		enemy_ranged = enemy_ranged or caps.has("ranged")
		enemy_fire = enemy_fire or caps.has("fire")
		enemy_explosion = enemy_explosion or caps.has("explosion")
		var tags:Array = enchants.target_tags_for(other)
		undead_enemy = undead_enemy or tags.has("undead")
		arthropod_enemy = arthropod_enemy or tags.has("arthropod")
	if enemy_damage:
		pool.append_array(["protection","unbreaking","thorns"])
		if enemy_fire and target.get_fire_effect_ratio() > 0.0: pool.append("fire_protection")
		if enemy_explosion: pool.append("blast_protection")
		if enemy_ranged: pool.append("projectile_protection")
	if own.has("melee"): pool.append_array(["sharpness","knockback","fire_aspect"])
	if own.has("ranged"): pool.append_array(["power","punch","flame"])
	if attacks and not enemies.is_empty():
		pool.append_array(["breach","mending"])
		if float(target.Speed) > 0.0: pool.append("density")
		if undead_enemy: pool.append("smite")
		if arthropod_enemy: pool.append("bane_of_arthropods")
	if own.has("multishot"): pool.append_array(["multishot","piercing"])
	if own.has("efficiency"): pool.append("efficiency")
	if has_quick_charge(target): pool.append("quick_charge")
	if _collides_with_characters(target): pool.append("impaling")
	if float(target.Speed) > 0.0 and _soul_sand_possible(target): pool.append("soul_speed")
	if delta != 0:
		var catalog:Script = load(CATALOG_PATH)
		var owned:Dictionary = enchants.levels_of(target)
		for i:int in range(pool.size()-1,-1,-1):
			if catalog.is_levelless(pool[i]) and (delta < 0 or int(owned.get(pool[i],0)) >= 1): pool.remove_at(i)
	return pool
