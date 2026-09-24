extends RefCounted
## 41 supported Java IDs (including Lunge; both curses are intentionally removed).
## This is a display/catalog layer, NOT an implementation of combat mechanics.
## No supported-item tags, exclusivity groups, or vanilla level caps are imposed.
const NAMES:Dictionary = {
	"aqua_affinity": ["水下速掘","Aqua Affinity"],
	"bane_of_arthropods": ["节肢杀手","Bane of Arthropods"],
	"blast_protection": ["爆炸保护","Blast Protection"],
	"breach": ["破甲","Breach"],
	"channeling": ["引雷","Channeling"],
	"density": ["致密","Density"],
	"depth_strider": ["深海探索者","Depth Strider"],
	"efficiency": ["效率","Efficiency"],
	"feather_falling": ["摔落保护","Feather Falling"],
	"fire_aspect": ["火焰附加","Fire Aspect"],
	"fire_protection": ["火焰保护","Fire Protection"],
	"flame": ["火矢","Flame"],
	"fortune": ["时运","Fortune"],
	"frost_walker": ["冰霜行者","Frost Walker"],
	"impaling": ["穿刺","Impaling"],
	"infinity": ["无限","Infinity"],
	"knockback": ["击退","Knockback"],
	"looting": ["抢夺","Looting"],
	"loyalty": ["忠诚","Loyalty"],
	"luck_of_the_sea": ["海之眷顾","Luck of the Sea"],
	"lunge": ["疾冲","Lunge"],
	"lure": ["饵钓","Lure"],
	"mending": ["经验修补","Mending"],
	"multishot": ["多重射击","Multishot"],
	"piercing": ["穿透","Piercing"],
	"power": ["力量","Power"],
	"projectile_protection": ["弹射物保护","Projectile Protection"],
	"protection": ["保护","Protection"],
	"punch": ["冲击","Punch"],
	"quick_charge": ["快速装填","Quick Charge"],
	"respiration": ["水下呼吸","Respiration"],
	"riptide": ["激流","Riptide"],
	"sharpness": ["锋利","Sharpness"],
	"silk_touch": ["精准采集","Silk Touch"],
	"smite": ["亡灵杀手","Smite"],
	"soul_speed": ["灵魂疾行","Soul Speed"],
	"sweeping_edge": ["横扫之刃","Sweeping Edge"],
	"swift_sneak": ["迅捷潜行","Swift Sneak"],
	"thorns": ["荆棘","Thorns"],
	"unbreaking": ["耐久","Unbreaking"],
	"wind_burst": ["风爆","Wind Burst"],
}

static func canonical(kind:String) -> String:
	return kind.strip_edges().to_lower().trim_prefix("minecraft:")

static func all_ids() -> Array[String]:
	var result:Array[String] = []
	for id:String in NAMES: result.append(id)
	result.sort()
	return result

static func has_id(kind:String) -> bool:
	return NAMES.has(canonical(kind))

static func display_name(kind:String,english:bool = false) -> String:
	var id:String = canonical(kind)
	if not NAMES.has(id): return ""
	return str(NAMES[id][1 if english else 0])

static func display_level(level:int) -> String:
	if level <= 0: return ""
	# Do not construct unbounded-length roman numerals for arbitrary high levels.
	if level > 3999: return str(level)
	var value:int = level
	var result:String = ""
	var amounts:Array[int] = [1000,900,500,400,100,90,50,40,10,9,5,4,1]
	var symbols:Array[String] = ["M","CM","D","CD","C","XC","L","XL","X","IX","V","IV","I"]
	for i:int in range(amounts.size()):
		while value >= amounts[i]:
			result += symbols[i]
			value -= amounts[i]
	return result

static func display_line(kind:String,level:int,english:bool = false) -> String:
	var name:String = display_name(kind,english)
	return "" if name.is_empty() or level <= 0 else name+" "+display_level(level)
