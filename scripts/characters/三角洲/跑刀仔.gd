extends ball

@export_category("跑刀仔")
@export var supply_count:int=8 # V216：作为场上普通物资的软上限，不再表示整局固定总数。
@export var safe_count:int=4
@export var safe_wall_min_visual_gap:float=12.0 # V224：保险沿同一侧墙必须留出可见间隔，禁止彼此叠放。
@export var supply_initial_delay_min:float=0.9
@export var supply_initial_delay_max:float=1.8
@export var supply_spawn_interval_min:float=1.4
@export var supply_spawn_interval_max:float=2.8
@export var supply_money:int=18 # V215 前兼容字段；新物资使用各自 value。
@export var safe_money:int=100
@export var safe_open_time:float=6.687 # V217：仅作音频缺失时兜底；正常运行直接使用保险音效 get_length()。
@export var interact_radius:float=34.0
@export var safe_interact_radius:float=44.0
@export var pickup_fly_duration:float=0.34
@export var safe_search_duration:float=1.05 # V222前兼容兜底；保险现在按每件物品品质分别决定搜索时间。
@export var safe_result_hold_time:float=0.42
@export var safe_search_time_purple:float=0.68
@export var safe_search_time_gold:float=0.96
@export var safe_search_time_red:float=1.34
@export var safe_search_time_infinite:float=1.72
@export var safe_open_volume_db:float=7.0

@export_category("跑刀仔音乐")
@export var first_life_bgm_volume_db:float=-8.0
@export var revive_bgm_volume_db:float=-14.5
@export var rare_loot_music_volume_db:float=-0.5

@export_category("跑刀仔直升机复活")
@export var revive_helicopter_fly_in_time:float=1.15
@export var revive_rope_extend_time:float=0.28
@export var revive_character_descend_time:float=1.05
@export var revive_rope_retract_time:float=0.24
@export var revive_helicopter_fly_out_time:float=1.05
@export var revive_helicopter_visual_width:float=118.0
@export var revive_helicopter_hover_height:float=82.0
@export var revive_min_rope_length:float=68.0

@export_category("猛攻哥装备")
# V369：三角洲/猛攻哥.tscn 只把这个开关设为 true。
# 独立角色直接复用跑刀仔第二命的同一套脚本，不复制枪械/护甲/药品战斗实现。
@export var standalone_berserker:bool=false
@export var berserker_inventory_cell_world_size:float=16.0
@export var berserker_inventory_wall_flip_distance:float=76.0
@export var berserker_inventory_offset:float=58.0
@export var berserker_heal_trigger_ratio:float=0.72
@export var berserker_armor_repair_trigger_ratio:float=0.38
@export var berserker_inventory_z_index:int=188

const ITEM_TEXTURE_DIR:String = "res://Images/characters/三角洲/跑刀仔/"
const SAFE_TEXTURE_PATH:String = ITEM_TEXTURE_DIR + "保险.png"
const INFINITE_MONEY_SENTINEL:int = 2_000_000_000
const INFINITE_PURCHASE_BUDGET:int = 100_000
const ITEM_SPAWN_SHADER_PATH:String = "res://shaders/跑刀仔物资出生闪光.gdshader"
const SAFE_Z_INDEX:int = 120
const SEARCH_LOW_SFX_PATH:String = "res://audio/characters/三角洲/搜索紫以下.MP3"
const SEARCH_HIGH_SFX_PATH:String = "res://audio/characters/三角洲/搜索金以上.MP3"
const PICKUP_LOW_SFX_PATH:String = "res://audio/characters/三角洲/紫以下拾取(1).mp3"
const PICKUP_HIGH_SFX_PATH:String = "res://audio/characters/三角洲/金以上拾取.mp3"
const SAFE_OPEN_SFX_PATH:String = "res://audio/characters/三角洲/三角洲开保险.MP3"
const FIRST_LIFE_BGM_PATH:String = "res://audio/characters/三角洲/哈哈基米 P1 🎵曼波 𝑵𝒐 𝑴𝒐𝒓𝒆🎵不再曼波.mp3"
const REVIVE_BGM_PATH:String = "res://audio/characters/三角洲/TAKEDISKRUSH! P1 TAKEDISKRUSH!.mp3"
const RARE_LOOT_MUSIC_PATH:String = "res://audio/characters/三角洲/三角洲行动BGM P1 《得吃の小曲》《78の小曲》《舔包の小曲》《鼠鼠の小曲》.mp3"
const RUNNER_MUSIC_GROUP:StringName = &"RunnerExclusiveMusic"
const RUNNER_FIRST_LIFE_TEXTURE_PATH:String = ITEM_TEXTURE_DIR + "跑刀鼠.png"
const RUNNER_REVIVE_TEXTURE_PATH:String = ITEM_TEXTURE_DIR + "吴彦祖.png"
const RUNNER_HELICOPTER_TEXTURE_PATH:String = ITEM_TEXTURE_DIR + "直升机.png"
const RUNNER_FIRST_LIFE_VISUAL_LONGEST_SIDE:float = 235.0
const RUNNER_REVIVE_VISUAL_LONGEST_SIDE:float = 270.0
# V230 的绳降临时 Sprite 挂在 top_level 世界节点下，不吃 ball 根 0.2 缩放，
# 因此必须使用单独的世界像素尺寸，不能复用角色本体 200+ 的本地像素尺寸。
const RUNNER_AIRDROP_VISUAL_LONGEST_SIDE:float = 64.0

# V358：第一命仍是跑刀鼠；第二命优先购买枪。枪和护甲是身上装备，不占3x3九格；
# 九格只放血药/甲修。没有“通用子弹”物品，所有枪统一实例化夺舍狼同款 res://scenes/shooter/子弹.tscn；
# 连最便宜枪都买不起时使用免费匕首近战。
const BERSERKER_EQUIPMENT_DIR:String = ITEM_TEXTURE_DIR + "猛攻装备/"
const BERSERKER_BULLET_SCENE:PackedScene = preload("res://scenes/shooter/子弹.tscn")
# V365：正式枪声全部 parse-time preload。
# 不再依赖运行时字符串 load()，Godot 导入/导出依赖也能明确追踪到六段声音。
const BERSERKER_G18_AUDIO:AudioStream = preload("res://audio/characters/三角洲/跑刀仔/猛攻枪声/g18.mp3")
const BERSERKER_AUG_AUDIO:AudioStream = preload("res://audio/characters/三角洲/跑刀仔/猛攻枪声/aug.mp3")
const BERSERKER_PSG_AUDIO:AudioStream = preload("res://audio/characters/三角洲/跑刀仔/猛攻枪声/psg.mp3")
const BERSERKER_M7_AUDIO:AudioStream = preload("res://audio/characters/三角洲/跑刀仔/猛攻枪声/m7.mp3")
const BERSERKER_M250_AUDIO:AudioStream = preload("res://audio/characters/三角洲/跑刀仔/猛攻枪声/250.mp3")
const BERSERKER_AWM_AUDIO:AudioStream = preload("res://audio/characters/三角洲/跑刀仔/猛攻枪声/awm.mp3")

const BERSERKER_LOOP_GUN_AUDIO:Dictionary = {
	"G18": true,
	"AUG": true,
	"M7": true,
	"M250": true,
}
const BERSERKER_GRID_SIZE:Vector2i = Vector2i(3,3)
const BERSERKER_MAX_WEAPONS:int = 2
const BERSERKER_DAGGER_TEXTURE_PATH:String = BERSERKER_EQUIPMENT_DIR + "匕首.png"
const BERSERKER_DAGGER_DAMAGE:float = 24.0
const BERSERKER_DAGGER_RANGE:float = 43.0
const BERSERKER_DAGGER_COOLDOWN:float = 0.72
const BERSERKER_DAGGER_KNOCKBACK_DISTANCE:float = 12.0
const BERSERKER_DAGGER_KNOCKBACK_SPEED:float = 185.0

# V361：价格继续使用跑刀仔项目内 money；枪械战斗属性完全按用户本轮指定的角色定位重做，
# 不再沿用 V357 的公开枪械数值。
const BERSERKER_ARMOR_VISUAL_LONGEST_SIDE:float = 126.0
const BERSERKER_M250_WINDUP_DEFAULT:float = 0.24
const BERSERKER_M250_BURST_RESET_DEFAULT:float = 0.22
const BERSERKER_WEAPON_SWITCH_DURATION:float = 0.40
const BERSERKER_SWITCH_IN_LOWER_ANGLE:float = deg_to_rad(36.0)
const BERSERKER_BACK_GUN_NORMAL_POSITION:Vector2 = Vector2(-8.0,7.0)
const BERSERKER_BACK_GUN_SWITCH_START_POSITION:Vector2 = Vector2(-8.0,-28.0)
const BERSERKER_BACK_GUN_NORMAL_ROTATION:float = deg_to_rad(-68.0)
const BERSERKER_BACK_GUN_SWITCH_START_ROTATION:float = deg_to_rad(-42.0)

# V374：手持枪继续往人物前侧推出。
# 朝左使用负值，朝右使用正值。
const BERSERKER_HAND_GUN_FRONT_X:float = 82.0
# V394：V370 为了提亮猛攻哥曾向纯白混合 8%，实际观感偏白；
# 只保留很轻的提亮，恢复原图的深色层次。
const BERSERKER_CHARACTER_WHITE_MIX:float = 0.025
# V394：枪口点基于当前枪 Sprite2D 的真实不透明边界自动计算。
# 枪械原图默认朝左，所以局部 -X 是枪口方向；再向枪管外多推出少量像素，
# 避免子弹第一帧和枪口贴图重叠。
const BERSERKER_MUZZLE_OUTSET_LOCAL:float = 3.0

# V368：完全沿用军火商狙击枪 SniperAimLine 的主要视觉参数。
const BERSERKER_AWM_AIM_LINE_WIDTH:float = 1.4
const BERSERKER_AWM_AIM_LINE_COLOR:Color = Color(1.0,0.12,0.08,0.78)
const BERSERKER_AWM_AIM_LINE_MAX_LENGTH:float = 440.0
const BERSERKER_AWM_AIM_LINE_MUZZLE_OFFSET:float = 16.0 * 0.72

const BERSERKER_WEAPON_DEFS:Dictionary = {
	# 快射 / 快换 / 低伤 / 中速弹 / 中幅偏差
	"G18": {"file":"g18.png","price":70,"equipped":true,"mag":33,"damage":2.0,"rpm":1650.0,"projectile_speed":520.0,"reload":0.95,"spread_deg":5.0,"aim_turn_deg":900.0},
	# 中偏慢 / 30发 / 中等换弹 / 高伤 / 快弹 / 0偏差
	"PSG-1": {"file":"psg.png","price":150,"equipped":true,"mag":30,"damage":10.0,"rpm":840.0,"projectile_speed":900.0,"reload":2.05,"spread_deg":0.0,"aim_turn_deg":420.0},
	# 中偏快 / 快换 / 30发 / 中伤 / 中偏快弹 / 小偏差
	"AUG": {"file":"aug.png","price":175,"equipped":true,"mag":30,"damage":4.0,"rpm":1150.0,"projectile_speed":650.0,"reload":1.20,"spread_deg":1.4,"aim_turn_deg":620.0},
	# 快射 / 快换 / 30发 / 中伤 / 快弹 / 0偏差
	"M7": {"file":"m7.png","price":230,"equipped":true,"mag":30,"damage":4.0,"rpm":1380.0,"projectile_speed":860.0,"reload":1.25,"spread_deg":0.0,"aim_turn_deg":680.0},
	# 较快 / 每段连续射击第一发有前腰 / 60发 / 慢换 / 高伤 / 小偏差
	"M250": {"file":"250.png","price":320,"equipped":true,"mag":60,"damage":7.0,"rpm":1250.0,"projectile_speed":760.0,"reload":4.00,"spread_deg":1.1,"first_shot_windup":0.24,"burst_reset":0.22,"aim_turn_deg":240.0},
	# 极高伤 / 1发 / 快弹 / 0偏差 / 军火商狙同类预判 / 直接生命伤害
	"AWM": {"file":"awm.png","price":380,"equipped":true,"mag":1,"damage":120.0,"rpm":170.0,"projectile_speed":1100.0,"reload":3.40,"spread_deg":0.0,"requires":"ammo_part","predictive":true,"raw_health":true,"aim_turn_deg":560.0,"knockback_distance":145.0,"knockback_speed":1150.0},
}

const BERSERKER_ARMOR_DEFS:Dictionary = {
	"蓝甲": {"file":"蓝甲.png","price":80,"equipped":true,"shield":90},
	"紫甲": {"file":"紫甲.png","price":150,"equipped":true,"shield":160},
	"金甲": {"file":"金甲.png","price":260,"equipped":true,"shield":260},
	# 红甲与金甲花费完全相同，但额外要求第一命捡到高级咖啡豆。
	# 护盾不是固定值：装备时等于当前 Max_health。
	"红甲": {"file":"红甲.png","price":260,"equipped":true,"shield_mode":"health","requires":"coffee"},
}

const BERSERKER_CONSUMABLE_DEFS:Dictionary = {
	"60血": {"file":"60血.png","price":30,"grid":Vector2i(1,1),"kind":"heal","capacity":60.0,"heal_rate":70.0,"quality":"绿"},
	"350血包": {"file":"350血包.png","price":90,"grid":Vector2i(3,1),"kind":"heal","capacity":350.0,"heal_rate":105.0,"quality":"紫","allow_rotate":false},
	"800血包": {"file":"800血包.png","price":150,"grid":Vector2i(2,2),"kind":"heal","capacity":800.0,"heal_rate":145.0,"quality":"金"},
	"甲修": {"file":"甲修.png","price":110,"grid":Vector2i(2,2),"kind":"repair","uses":1,"quality":"红"},
}

const SPECIAL_UNLOCK_ITEMS:Dictionary = {
	# 沿用项目已有正式素材。V218 曾禁止随机生成；V357 为猛攻装备门槛重新以极低概率开放。
	"高级咖啡豆": {"file":"咖啡豆.png","value":0,"size":"小","quality":"红","special_unlock":"coffee"},
	"高级子弹零件": {"file":"子弹零件.png","value":0,"size":"小","quality":"金","special_unlock":"ammo_part"},
}

# V215：用户提供物品的项目内价值。这里只是跑刀仔自身的“钱”单位，
# 不冒充《三角洲行动》实时交易行价格；同品质内部也故意保留不同价格。
# 大件 > 同品质小件；大大红 > 所有大红。
const ITEM_POOLS:Dictionary = {
	"白": [
		{"file":"白.png", "value":5, "size":"小"},
		{"file":"白2.png", "value":6, "size":"小"},
		{"file":"白3.png", "value":7, "size":"小"},
		{"file":"白4.png", "value":8, "size":"小"},
		{"file":"白5.png", "value":9, "size":"小"},
	],
	"蓝": [
		{"file":"蓝.png", "value":12, "size":"小"},
		{"file":"蓝2.png", "value":14, "size":"小"},
		{"file":"蓝3.png", "value":16, "size":"小"},
		{"file":"蓝4.png", "value":18, "size":"小"},
	],
	"紫": [
		{"file":"紫.png", "value":22, "size":"小"},
		{"file":"紫2.png", "value":25, "size":"小"},
		{"file":"紫3.png", "value":28, "size":"小"},
		{"file":"紫4.png", "value":31, "size":"小"},
		{"file":"大紫.png", "value":42, "size":"大"},
		{"file":"大紫2.png", "value":48, "size":"大"},
	],
	"金": [
		{"file":"金.png", "value":40, "size":"小"},
		{"file":"金2.png", "value":45, "size":"小"},
		{"file":"金3.png", "value":50, "size":"小"},
		{"file":"金4.png", "value":55, "size":"小"},
	],
	"红": [
		{"file":"小红.png", "value":65, "size":"小"},
		{"file":"小红2.png", "value":70, "size":"小"},
		{"file":"小红3.png", "value":75, "size":"小"},
		{"file":"小红4.png", "value":80, "size":"小"},
		{"file":"中红.png", "value":90, "size":"中"},
		{"file":"大红.png", "value":115, "size":"大"},
		{"file":"大红2.png", "value":125, "size":"大"},
		{"file":"大红3.png", "value":135, "size":"大"},
		{"file":"大大红.png", "value":185, "size":"大大"},
	],
	"无限": [
		{"file":"无限钱.png", "value":0, "size":"小", "infinite":true},
		{"file":"无限钱2.png", "value":0, "size":"小", "infinite":true},
	],
}

# V221：保险专属可出物品。只允许用户本轮点名的物资进入保险，不沿用整个 ITEM_POOLS。
# weight 仅用于保险内部抽取；无限钱仍最低。grid 为保险 3x3 背包中的默认横向/纵向占格。
const SAFE_LOOT_CHOICES:Array = [
	{"file":"大紫.png", "weight":8.0, "grid":Vector2i(3,2)},
	{"file":"大紫2.png", "weight":8.0, "grid":Vector2i(2,3)},
	{"file":"小红.png", "weight":4.0, "grid":Vector2i(1,1)},
	{"file":"小红2.png", "weight":4.0, "grid":Vector2i(1,1)},
	{"file":"大红2.png", "weight":2.3, "grid":Vector2i(3,2)},
	{"file":"大红3.png", "weight":2.3, "grid":Vector2i(2,3)},
	{"file":"无限钱.png", "weight":0.45, "grid":Vector2i(1,1)},
	{"file":"无限钱2.png", "weight":0.45, "grid":Vector2i(1,1)},
	{"file":"紫2.png", "weight":15.0, "grid":Vector2i(1,2), "allow_rotate":true},
	{"file":"金.png", "weight":10.0, "grid":Vector2i(1,1)},
	{"file":"金2.png", "weight":10.0, "grid":Vector2i(1,1)},
	{"file":"金3.png", "weight":10.0, "grid":Vector2i(1,1)},
	{"file":"金4.png", "weight":10.0, "grid":Vector2i(1,1)},
	# V357：两种猛攻门槛物可以从保险极低概率搜到。
	{"file":"咖啡豆.png", "weight":0.70, "grid":Vector2i(1,1)},
	{"file":"子弹零件.png", "weight":0.90, "grid":Vector2i(1,1)},
]

var money:int=0
var has_infinite_money:bool=false
var life_index:int=1
var _supplies:Array=[] # V227：外部节点可能已被 reset/queue_free；保持 Variant，先 is_instance_valid 再强转。
var _safes:Array=[]
var _opening_safe:Variant=null
var _safe_progress:float=0.0
var _rng:=RandomNumberGenerator.new()
var _revive_pending:bool=false
var _supply_spawn_left:float=0.0
var _pickup_flights:Array[Dictionary]=[]
var _safe_search_displays:Array=[]
var _money_label:Label=null
var _money_label_text_cache:String=""
var _runner_music_player:AudioStreamPlayer=null
var _runner_music_phase_revived:bool=false
var _runner_music_rare_active:bool=false
var _runner_music_resume_position:float=0.0
var _revive_airdrop_active:bool=false
var _revive_landing_position:Vector2=Vector2.ZERO
var _revive_cinematic_root:Variant=null
var _revive_collision_snapshot:Dictionary={}

# V357 第一命特殊门槛物。
var has_advanced_coffee_bean:bool=false
var has_advanced_ammo_part:bool=false

# V357 第二命 3x3 装备系统。
var _berserker_items:Array[Dictionary]=[]
var _berserker_weapon_indices:Array[int]=[]
var _berserker_armor_index:int=-1
var _berserker_active_weapon_slot:int=0
var _berserker_reload_in_progress:bool=false
var _berserker_using_item_index:int=-1
var _berserker_use_mode:String=""
var _berserker_use_fraction:float=0.0
var _berserker_inventory_root:Node2D=null
var _berserker_inventory_item_layer:Node2D=null
# V371：V370高亮层已改成容器，必须是Node2D。
# 子节点分别是白色填充Polygon2D和白色描边Line2D。
var _berserker_inventory_highlight:Node2D=null
var _berserker_inventory_visible:bool=false
var _berserker_inventory_highlight_item_id:int=-1
var _berserker_armor_sprite:Sprite2D=null
var _berserker_gun_sprite:Sprite2D=null
var _berserker_back_gun_sprite:Sprite2D=null
var _berserker_used_item_sprite:Sprite2D=null
var _berserker_awm_aim_line:Line2D=null
var _berserker_dagger_attack_active:bool=false
var _berserker_m250_windup_active:bool=false
var _berserker_m250_session_active:bool=false
var _berserker_m250_last_fire_msec:int=-100000
var _berserker_item_ui_sync_elapsed:float=0.0
var _berserker_gun_front_sign:float=1.0
# V372：人物实际朝向只由本帧移动方向更新。
# +1=人物朝右，-1=人物朝左；停止移动后保持最后一次朝向。
var _berserker_character_facing_sign:float=1.0
var _berserker_loop_gun_audio_player:AudioStreamPlayer=null
var _berserker_loop_gun_audio_weapon:String=""
var _berserker_loop_gun_last_shot_msec:int=-100000

# V365：第二命枪械完全独立于公共 State.Attack 冷却。
# 保留负余量：例如0.04s间隔在60Hz下会自然形成2/3帧交替，而不是永远向上取整成3帧。
var _berserker_fire_cooldown_remaining:float=0.0
var _berserker_manual_fire_requested:bool=false

# V366：枪械真正瞄准角。子弹只沿这个角度发射，不直接使用目标瞬时方向。
var _berserker_gun_aim_angle:float=0.0
var _berserker_gun_aim_initialized:bool=false
# V394：每张枪械贴图只扫描一次不透明边界，缓存原始局部枪口坐标。
var _berserker_muzzle_local_cache:Dictionary={}

# 切枪过程中锁定攻击；所有客户端播放同一套手持枪/背枪动画。
var _berserker_switch_animation_active:bool=false
var _berserker_switch_animation_elapsed:float=0.0
var _berserker_switch_from_slot:int=-1
var _berserker_switch_to_slot:int=-1

static var _berserker_dagger_geometry_cache:Dictionary={}

func _ready()->void:
	Can_Attack=false
	Can_Skill=false
	Has_Collision_Damage=false
	_rng.seed= Game.battle_rng_seed_or("scripts/characters/三角洲/跑刀仔.gd:_rng.seed",int(Time.get_ticks_usec())^get_instance_id())
	super._ready()

	if standalone_berserker:
		_setup_standalone_berserker()
		return

	_apply_runner_character_texture(RUNNER_FIRST_LIFE_TEXTURE_PATH)
	_setup_money_label()
	_setup_runner_music()
	call_deferred("_spawn_loot")


func _setup_standalone_berserker()->void:
	# 独立“猛攻哥”就是跑刀仔第二命本体：
	# 没有第一命、金钱文字、搜刮物资、保险和直升机复活阶段。
	life_index=2
	_revive_pending=false
	_revive_airdrop_active=false
	money=0
	has_infinite_money=false

	_apply_runner_character_texture(RUNNER_REVIVE_TEXTURE_PATH)
	health=Max_health
	visible=true
	Can_Attack=false
	Can_Skill=false
	Has_Collision_Damage=false
	_berserker_gun_aim_initialized=false
	_berserker_switch_animation_active=false
	velocity=Vector2.ZERO
	direction=Vector2.ZERO
	Repel=Vector2.ZERO

	if state_machine!=null:
		state_machine.current_state=State.Move

	# authority 抽随机装备；复用现有 loadout RPC 同步所有客户端。
	if is_multiplayer_authority():
		call_deferred("_build_random_standalone_berserker_loadout")


func _process(_delta:float)->void:
	_update_berserker_equipment_visual_transform()
	_update_berserker_awm_aim_line_visual()

	# V361：血药/甲修真正处于使用过程时，3x3面板必须持续打开。
	# 即使中途因为一次重建/同步让 root.visible 被改掉，也在本渲染帧恢复。
	if _berserker_using_item_index>=0:
		_berserker_inventory_visible=true
		if is_instance_valid(_berserker_inventory_root):
			_berserker_inventory_root.visible=true

	if _berserker_inventory_visible:
		_update_berserker_inventory_world_position()

func Attack()->void:
	# 兼容其它旧调用：真正逻辑统一走独立发射函数。
	_try_berserker_fire_now()


func controlled_attack_action()->void:
	# 玩家直接控制点击时不走公共 Can_Attack / State.Attack。
	# 冷却未到时只记录一次请求，下一次物理帧到点立即发射。
	if life_index!=2 or not is_multiplayer_authority():
		return
	_berserker_manual_fire_requested=true
	if _berserker_fire_cooldown_remaining<=0.0001:
		if _try_berserker_fire_now():
			_berserker_manual_fire_requested=false


func _try_berserker_fire_now()->bool:
	if life_index!=2 or not is_multiplayer_authority():
		return false
	if state_machine==null or state_machine.current_state==State.Die or health<=0:
		return false
	if (
		dizziness
		or state_machine.current_state==State.Hurt
		or _berserker_switch_animation_active
		or _berserker_reload_in_progress
		or _berserker_using_item_index>=0
		or is_damage_output_disabled()
	):
		return false

	if _berserker_weapon_indices.is_empty():
		var dagger_aim:Vector2=_berserker_attack_direction()
		if dagger_aim.length_squared()<=0.000001 or _berserker_dagger_attack_active:
			return false
		Attacking=true
		_start_berserker_dagger_attack(dagger_aim.normalized())
		_berserker_fire_cooldown_remaining+=BERSERKER_DAGGER_COOLDOWN
		return true

	var weapon_index:int=_current_berserker_weapon_item_index()
	if weapon_index<0 or weapon_index>=_berserker_items.size():
		return false
	var weapon:Dictionary=_berserker_items[weapon_index]

	if int(weapon.get("mag_current",0))<=0:
		_handle_empty_berserker_weapon()
		return false

	# 仍需存在合法目标/玩家瞄准，避免AI没有目标时向旧角度盲射；
	# 但真正子弹方向绝对只来自“枪此刻实际朝向”。
	var desired:Vector2=_berserker_weapon_attack_direction(weapon)
	if desired.length_squared()<=0.000001:
		return false
	var aim:Vector2=_berserker_current_gun_direction()

	# M250只有“这一段连续射击的第一发”进入前腰。
	if str(weapon.get("name",""))=="M250" and not _berserker_m250_session_active:
		if _berserker_m250_windup_active:
			return false
		_berserker_m250_windup_active=true
		Attacking=true
		call_deferred("_run_berserker_m250_first_shot",weapon_index)
		return true

	_fire_berserker_weapon(weapon_index,aim.normalized())
	_arm_berserker_fire_interval(weapon)
	return true


func _arm_berserker_fire_interval(weapon:Dictionary)->void:
	var rpm:float=maxf(float(weapon.get("rpm",300.0)),1.0)
	var interval:float=60.0/rpm
	# 关键：+= 而不是 =。如果本帧已经超时了几毫秒，负余量会带到下一发，
	# 从长期平均值上逼近设定RPM，而不是每发都被physics frame向上取整。
	_berserker_fire_cooldown_remaining+=interval


func continue_attack()->void:
	# 猛攻哥每次 State.Attack 只发一颗；射速由当前枪 Attack_Cooling 控制。
	pass

func Skill()->void:
	Using_Skill=false

func _exit_tree()->void:
	# 退出树时每个客户端本地直接停自己的循环播放器，避免节点释放前还残留枪声。
	_stop_berserker_loop_gun_audio_local()
	# V222：地面物资/保险/保险搜索界面都挂在 current_scene，而不是跑刀仔子节点。
	# 因此人物被手动删除、换场景或 queue_free 时必须主动清理，否则会留下“无主人战利品”。
	_cleanup_revive_cinematic()
	_stop_runner_music()
	_cleanup_runner_loot()
	_cleanup_berserker_inventory_visual()

func tick_physics(state:State,delta:float)->void:
	_refresh_money_label()
	if _revive_airdrop_active:
		velocity=Vector2.ZERO
		direction=Vector2.ZERO
		Repel=Vector2.ZERO
		return
	if is_multiplayer_authority() and life_index==1 and health>0:
		_tick_loot(delta)
	elif is_multiplayer_authority() and life_index==2 and health>0:
		# V365：真实射速时钟。允许少量负余量保留，避免高RPM被整帧向上取整。
		_berserker_fire_cooldown_remaining-=maxf(delta,0.0)
		_berserker_fire_cooldown_remaining=maxf(_berserker_fire_cooldown_remaining,-0.25)

		_update_berserker_character_facing_from_motion()
		_tick_berserker_switch_animation(delta)
		_tick_berserker_gun_aim(delta)
		_tick_berserker_m250_session(state)
		_tick_berserker_consumables(delta)
		_tick_berserker_gun_audio(state)
		_sync_red_armor_to_health()

		if is_player_controlled():
			if (
				_berserker_manual_fire_requested
				and _berserker_fire_cooldown_remaining<=0.0001
				and _try_berserker_fire_now()
			):
				_berserker_manual_fire_requested=false
		elif _berserker_fire_cooldown_remaining<=0.0001:
			_try_berserker_fire_now()
	else:
		_berserker_manual_fire_requested=false

	# 非authority端也要让本地枪动画持续走；authority上面已经更新过。
	if life_index==2 and not is_multiplayer_authority():
		_update_berserker_character_facing_from_motion()
		_tick_berserker_switch_animation(delta)
		_tick_berserker_gun_aim(delta)

	# 先让 ball.gd 在本 physics tick 根据 direction / dir_left 更新人物 Shader 朝向。
	super.tick_physics(state,delta)

	# V363：紧接着读取刚更新好的 is_character_visual_flipped_h() 刷枪位。
	# 不再只等下一次 _process()，消除人物转向后枪偶尔晚一帧换边的问题。
	if life_index==2:
		_update_berserker_equipment_visual_transform()

func _tick_loot(delta:float)->void:
	_tick_supply_spawner(delta)
	_tick_pickup_flights(delta)
	for raw_supply:Variant in _supplies.duplicate():
		if not is_instance_valid(raw_supply):
			_supplies.erase(raw_supply)
			continue
		var n:=raw_supply as Node2D
		if n==null:
			_supplies.erase(raw_supply)
			continue
		if global_position.distance_to(n.global_position)<=interact_radius:
			_supplies.erase(raw_supply)
			_start_pickup_flight(n)

	var candidate:Node2D=null
	for raw_safe:Variant in _safes:
		if not is_instance_valid(raw_safe):
			continue
		var n:=raw_safe as Node2D
		if n!=null and global_position.distance_to(n.global_position)<=safe_interact_radius:
			candidate=n
			break
	if candidate==null:
		_stop_safe_open_audio(_opening_safe)
		_opening_safe=null
		_safe_progress=0.0
		return
	if _opening_safe!=candidate:
		_stop_safe_open_audio(_opening_safe)
		_opening_safe=candidate
		_safe_progress=0.0
		_prepare_safe_loot(candidate)
		_start_safe_open_audio(candidate)
	velocity=Vector2.ZERO
	direction=Vector2.ZERO
	_safe_progress+=delta
	var open_duration:float=_safe_open_duration(candidate)
	if _safe_progress>=open_duration:
		_stop_safe_open_audio(candidate)
		var planned:Array=candidate.get_meta("runner_safe_planned_loot",[]) as Array
		var safe_pos:Vector2=candidate.global_position
		var on_right:bool=bool(candidate.get_meta("runner_safe_on_right",false))
		_safes.erase(candidate)
		_opening_safe=null
		_safe_progress=0.0
		# V219：搜索界面必须以保险本体当前位置为锚点。先生成更高Z的搜索框覆盖保险，
		# 同时让保险原地缩小并渐隐；淡出完成后才释放保险，禁止瞬间消失或再次往墙外偏移。
		_start_safe_search_display(safe_pos,on_right,planned)
		_fade_safe_into_search(candidate)

func _collect_supply(n:Node2D)->void:
	_trigger_rare_loot_music_if_needed(n)
	_play_loot_sfx(str(n.get_meta("runner_loot_quality","白")),false,n.global_position)

	var special_unlock:String=str(n.get_meta("runner_special_unlock",""))
	if special_unlock=="coffee":
		has_advanced_coffee_bean=true
		return
	if special_unlock=="ammo_part":
		has_advanced_ammo_part=true
		return

	if bool(n.get_meta("runner_infinite_money",false)):
		has_infinite_money=true
		money=INFINITE_MONEY_SENTINEL
		_refresh_money_label(true)
		return
	if has_infinite_money:
		_refresh_money_label()
		return
	money+=int(n.get_meta("runner_loot_value",supply_money))
	_refresh_money_label(true)

func _start_pickup_flight(n:Node2D)->void:
	if not is_instance_valid(n):
		return
	if bool(n.get_meta("runner_pickup_flying",false)):
		return
	n.set_meta("runner_pickup_flying",true)
	var sprite:=n.get_node_or_null("ItemSprite") as Sprite2D
	var start_scale:=Vector2.ONE
	if sprite!=null:
		start_scale=sprite.scale
	_pickup_flights.append({"node":n,"elapsed":0.0,"start_scale":start_scale})

func _tick_pickup_flights(delta:float)->void:
	for entry:Dictionary in _pickup_flights.duplicate():
		var raw_node:Variant=entry.get("node")
		if not is_instance_valid(raw_node):
			_pickup_flights.erase(entry)
			continue
		var n:=raw_node as Node2D
		if n==null:
			_pickup_flights.erase(entry)
			continue
		var elapsed:float=float(entry.get("elapsed",0.0))+delta
		entry["elapsed"]=elapsed
		var duration:float=maxf(pickup_fly_duration,0.08)
		var t:float=clampf(elapsed/duration,0.0,1.0)
		# 每帧追踪跑刀仔当前位置，不用固定 Tween 终点，因此人物移动时物资也会弯着追过去。
		var follow_alpha:float=1.0-exp(-12.0*delta)
		n.global_position=n.global_position.lerp(global_position,follow_alpha)
		var sprite:=n.get_node_or_null("ItemSprite") as Sprite2D
		if sprite!=null:
			var start_scale:Vector2=entry.get("start_scale",sprite.scale)
			sprite.scale=start_scale.lerp(Vector2.ONE*0.03,t*t)
		if t>=1.0 or n.global_position.distance_to(global_position)<=3.0:
			_finish_collect_supply(n)
			n.queue_free()
			_pickup_flights.erase(entry)

func _finish_collect_supply(n:Node2D)->void:
	if not is_instance_valid(n):
		return
	_collect_supply(n)

func get_next_state(state:State) -> int:
	# V230：第一命死亡后先进入“不可交互的直升机空降阶段”，而不是立刻把第二命实体放回战场。
	if _revive_airdrop_active:
		if state!=State.Stand:
			return State.Stand
		return -1
	if life_index==1 and health<=0:
		if not _revive_pending:
			_revive_pending=true
			_prepare_first_life_airdrop()
			call_deferred("_buy_equipment_and_revive")
		if state!=State.Stand:
			return State.Stand
		return -1
	return super.get_next_state(state)

func Die()->void:
	if is_instance_valid(_berserker_awm_aim_line):
		_berserker_awm_aim_line.visible=false
	_request_stop_berserker_loop_gun_audio()
	_reset_berserker_m250_session(true)
	_berserker_switch_animation_active=false
	_berserker_gun_aim_initialized=false
	# V359：最终死亡立即隐藏金钱文字。
	if is_instance_valid(_money_label):
		_money_label.visible=false
	# 最终死亡立即清理；不要等0.55秒释放人物后才处理，避免战场上短暂残留保险/物资。
	_cleanup_revive_cinematic()
	_stop_runner_music()
	_cleanup_runner_loot()
	super.Die()
	await get_tree().create_timer(0.55).timeout
	if is_instance_valid(self):
		Game.free_node(self)

func _buy_equipment_and_revive()->void:
	if life_index!=1 or not _revive_airdrop_active:
		return

	# TAKEDISKRUSH 从第一命死亡这一刻开始，作为整个空降复活阶段的阶段BGM。
	_switch_runner_phase_music(true)
	_cleanup_runner_loot()

	# V357：第二命不再把预算直接换成抽象 Damage/Block/Speed/MaxHealth。
	# 预算进入真实 3x3（9格）猛攻装备购买；最多两把枪，所有物品必须能实际排进格子。
	var budget:int=INFINITE_PURCHASE_BUDGET if has_infinite_money else money
	_build_berserker_loadout(budget)

	await _run_helicopter_revive_sequence()


func _prepare_first_life_airdrop()->void:
	if _revive_airdrop_active:
		return
	_revive_airdrop_active=true
	_refresh_money_label(true)
	_revive_landing_position=global_position
	velocity=Vector2.ZERO
	direction=Vector2.ZERO
	Repel=Vector2.ZERO
	Attacking=false
	Using_Skill=false
	visible=false
	_set_revive_body_enabled(false)
	if state_machine!=null:
		state_machine.current_state=State.Stand


func _set_revive_body_enabled(enabled:bool)->void:
	if not enabled:
		if _revive_collision_snapshot.is_empty():
			_revive_collision_snapshot={
				"body_layer":collision_layer,
				"body_mask":collision_mask,
				"body_shape_disabled":collision_shape_2d.disabled if collision_shape_2d!=null else false,
				"hitbox_monitoring":self_hitbox.monitoring if self_hitbox!=null else false,
				"hitbox_monitorable":self_hitbox.monitorable if self_hitbox!=null else false,
				"hitbox_layer":self_hitbox.collision_layer if self_hitbox!=null else 0,
				"hitbox_mask":self_hitbox.collision_mask if self_hitbox!=null else 0,
				"hurtbox_monitoring":self_hurtbox.monitoring if self_hurtbox!=null else false,
				"hurtbox_monitorable":self_hurtbox.monitorable if self_hurtbox!=null else false,
				"hurtbox_layer":self_hurtbox.collision_layer if self_hurtbox!=null else 0,
				"hurtbox_mask":self_hurtbox.collision_mask if self_hurtbox!=null else 0,
			}
		collision_layer=0
		collision_mask=0
		if collision_shape_2d!=null:
			collision_shape_2d.set_deferred("disabled",true)
		if self_hitbox!=null:
			self_hitbox.set_deferred("monitoring",false)
			self_hitbox.set_deferred("monitorable",false)
			self_hitbox.set_deferred("collision_layer",0)
			self_hitbox.set_deferred("collision_mask",0)
		if self_hurtbox!=null:
			self_hurtbox.set_deferred("monitoring",false)
			self_hurtbox.set_deferred("monitorable",false)
			self_hurtbox.set_deferred("collision_layer",0)
			self_hurtbox.set_deferred("collision_mask",0)
		return

	if _revive_collision_snapshot.is_empty():
		return
	collision_layer=int(_revive_collision_snapshot.get("body_layer",collision_layer))
	collision_mask=int(_revive_collision_snapshot.get("body_mask",collision_mask))
	if collision_shape_2d!=null:
		collision_shape_2d.set_deferred(
			"disabled",
			bool(_revive_collision_snapshot.get("body_shape_disabled",false))
		)
	if self_hitbox!=null:
		self_hitbox.set_deferred(
			"monitoring",
			bool(_revive_collision_snapshot.get("hitbox_monitoring",false))
		)
		self_hitbox.set_deferred(
			"monitorable",
			bool(_revive_collision_snapshot.get("hitbox_monitorable",false))
		)
		self_hitbox.set_deferred(
			"collision_layer",
			int(_revive_collision_snapshot.get("hitbox_layer",0))
		)
		self_hitbox.set_deferred(
			"collision_mask",
			int(_revive_collision_snapshot.get("hitbox_mask",0))
		)
	if self_hurtbox!=null:
		self_hurtbox.set_deferred(
			"monitoring",
			bool(_revive_collision_snapshot.get("hurtbox_monitoring",false))
		)
		self_hurtbox.set_deferred(
			"monitorable",
			bool(_revive_collision_snapshot.get("hurtbox_monitorable",false))
		)
		self_hurtbox.set_deferred(
			"collision_layer",
			int(_revive_collision_snapshot.get("hurtbox_layer",0))
		)
		self_hurtbox.set_deferred(
			"collision_mask",
			int(_revive_collision_snapshot.get("hurtbox_mask",0))
		)
	_revive_collision_snapshot.clear()


func is_combat_targetable()->bool:
	if _revive_airdrop_active:
		return false
	return super.is_combat_targetable()


func _visible_world_rect()->Rect2:
	var viewport:=get_viewport()
	if viewport==null:
		return _map_rect()
	var screen_rect:Rect2=viewport.get_visible_rect()
	var inv:Transform2D=viewport.get_canvas_transform().affine_inverse()
	var a:Vector2=inv*screen_rect.position
	var b:Vector2=inv*screen_rect.end
	var top_left:=Vector2(minf(a.x,b.x),minf(a.y,b.y))
	var bottom_right:=Vector2(maxf(a.x,b.x),maxf(a.y,b.y))
	return Rect2(top_left,bottom_right-top_left)


func _fitted_sprite_scale(tex:Texture2D,longest_side:float)->Vector2:
	if tex==null:
		return Vector2.ONE
	var tex_size:=tex.get_size()
	var longest:=maxf(tex_size.x,tex_size.y)
	if longest<=0.001:
		return Vector2.ONE
	return Vector2.ONE*(longest_side/longest)


func _set_revive_rope_fraction(
	fraction:float,
	rope:Line2D,
	attach_point:Vector2,
	landing_point:Vector2
)->void:
	if rope==null or not is_instance_valid(rope):
		return
	var t:float=clampf(fraction,0.0,1.0)
	rope.points=PackedVector2Array([
		attach_point,
		attach_point.lerp(landing_point,t)
	])


func _run_helicopter_revive_sequence()->void:
	var scene:=get_tree().current_scene
	var helicopter_tex:=load(RUNNER_HELICOPTER_TEXTURE_PATH) as Texture2D
	var revive_tex:=load(RUNNER_REVIVE_TEXTURE_PATH) as Texture2D

	# 资源/场景异常时不能让角色永远卡在隐藏状态，直接安全完成第二命。
	if scene==null or helicopter_tex==null or revive_tex==null:
		_finish_second_life_revive(_revive_landing_position)
		return

	_cleanup_revive_cinematic()

	var cinematic:=Node2D.new()
	cinematic.name="跑刀仔直升机复活"
	cinematic.z_index=228
	cinematic.top_level=true
	scene.add_child(cinematic)
	cinematic.global_position=Vector2.ZERO
	_revive_cinematic_root=cinematic

	var map_rect:Rect2=_map_rect()
	var visible_rect:Rect2=_visible_world_rect()
	var landing:=_revive_landing_position
	landing.x=clampf(landing.x,map_rect.position.x+22.0,map_rect.end.x-22.0)
	landing.y=clampf(landing.y,map_rect.position.y+22.0,map_rect.end.y-22.0)

	# 保证机腹到落点至少有一段可见绳长。
	var hover_y:float=maxf(visible_rect.position.y+30.0,landing.y-revive_helicopter_hover_height)
	if landing.y-hover_y<revive_min_rope_length:
		landing.y=minf(map_rect.end.y-22.0,hover_y+revive_min_rope_length)
	var hover_x:float=clampf(
		landing.x,
		visible_rect.position.x+58.0,
		visible_rect.end.x-58.0
	)
	var hover_pos:=Vector2(hover_x,hover_y)

	var from_left:bool=_rng.randf()<0.5
	var side_padding:float=revive_helicopter_visual_width*0.72+28.0
	var start_x:float=visible_rect.position.x-side_padding if from_left else visible_rect.end.x+side_padding
	var exit_x:float=visible_rect.end.x+side_padding if from_left else visible_rect.position.x-side_padding

	var helicopter:=Sprite2D.new()
	helicopter.name="直升机"
	helicopter.texture=helicopter_tex
	helicopter.centered=true
	helicopter.scale=_fitted_sprite_scale(helicopter_tex,revive_helicopter_visual_width)
	helicopter.flip_h=from_left # 原图机头向左；从左飞入时翻转为机头向右。
	helicopter.position=Vector2(start_x,hover_pos.y-4.0)
	helicopter.rotation_degrees=1.8 if from_left else -1.8
	helicopter.z_index=230
	cinematic.add_child(helicopter)

	var fly_in:=cinematic.create_tween().set_parallel(true)
	fly_in.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fly_in.tween_property(
		helicopter,
		"position",
		hover_pos,
		maxf(revive_helicopter_fly_in_time,0.1)
	)
	fly_in.tween_property(
		helicopter,
		"rotation_degrees",
		0.0,
		maxf(revive_helicopter_fly_in_time,0.1)
	)
	await fly_in.finished
	if not is_instance_valid(cinematic):
		return

	var heli_height:float=helicopter_tex.get_size().y*helicopter.scale.y
	var attach_point:Vector2=hover_pos+Vector2(-4.0,heli_height*0.38)
	var rope:=Line2D.new()
	rope.name="空降绳"
	rope.width=1.8
	rope.default_color=Color(0.16,0.14,0.12,0.96)
	rope.begin_cap_mode=Line2D.LINE_CAP_ROUND
	rope.end_cap_mode=Line2D.LINE_CAP_ROUND
	rope.z_index=229
	cinematic.add_child(rope)
	_set_revive_rope_fraction(0.0,rope,attach_point,landing)

	var rope_out:=cinematic.create_tween()
	rope_out.tween_method(
		_set_revive_rope_fraction.bind(rope,attach_point,landing),
		0.0,
		1.0,
		maxf(revive_rope_extend_time,0.05)
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await rope_out.finished
	if not is_instance_valid(cinematic):
		return

	var descending_character:=Sprite2D.new()
	descending_character.name="复活人物"
	descending_character.texture=revive_tex
	descending_character.centered=true
	descending_character.scale=_fitted_sprite_scale(revive_tex,RUNNER_AIRDROP_VISUAL_LONGEST_SIDE)
	descending_character.position=attach_point
	descending_character.z_index=231
	cinematic.add_child(descending_character)

	var descend:=cinematic.create_tween()
	descend.tween_property(
		descending_character,
		"position",
		landing,
		maxf(revive_character_descend_time,0.1)
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await descend.finished
	if not is_instance_valid(cinematic):
		return

	descending_character.visible=false
	_finish_second_life_revive(landing)

	var rope_in:=cinematic.create_tween()
	rope_in.tween_method(
		_set_revive_rope_fraction.bind(rope,attach_point,landing),
		1.0,
		0.0,
		maxf(revive_rope_retract_time,0.05)
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await rope_in.finished
	if is_instance_valid(rope):
		rope.queue_free()

	if not is_instance_valid(cinematic) or not is_instance_valid(helicopter):
		return
	var fly_out:=cinematic.create_tween().set_parallel(true)
	fly_out.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	fly_out.tween_property(
		helicopter,
		"position",
		Vector2(exit_x,hover_pos.y-6.0),
		maxf(revive_helicopter_fly_out_time,0.1)
	)
	fly_out.tween_property(
		helicopter,
		"rotation_degrees",
		-1.6 if from_left else 1.6,
		maxf(revive_helicopter_fly_out_time,0.1)
	)
	await fly_out.finished
	_cleanup_revive_cinematic()


func _finish_second_life_revive(landing:Vector2)->void:
	if life_index!=1:
		return
	global_position=landing
	life_index=2
	_refresh_money_label(true)
	_apply_runner_character_texture(RUNNER_REVIVE_TEXTURE_PATH)
	health=Max_health
	_set_revive_body_enabled(true)
	visible=true
	# V365：第二命不再进入公共 State.Attack；所有枪/匕首由本脚本独立调度。
	# 这同时彻底切断公共 Attack transition 可能附带的旧发射声音。
	Can_Attack=false
	Has_Collision_Damage=false
	_apply_berserker_armor_state()
	_berserker_gun_aim_initialized=false
	_berserker_switch_animation_active=false
	_refresh_berserker_equipment_visuals()
	_update_active_weapon_attack_cooling()
	_revive_pending=false
	_revive_airdrop_active=false
	velocity=Vector2.ZERO
	direction=Vector2.ZERO
	Repel=Vector2.ZERO
	if state_machine!=null:
		state_machine.current_state=State.Move


func _cleanup_revive_cinematic()->void:
	var raw_root:Variant=_revive_cinematic_root
	_revive_cinematic_root=null
	if is_instance_valid(raw_root):
		var cinematic:=raw_root as Node
		if cinematic!=null:
			cinematic.queue_free()

func _cleanup_runner_loot()->void:
	# V227：World reset / 手动删除可能已经先释放了 current_scene 下的物资节点。
	# Object 引用被 free 后不会自动变 null；必须先以 Variant 做 is_instance_valid()，
	# 不能先赋给 Node2D 强类型循环变量，否则会在有效性检查之前触发
	# “Trying to assign invalid previously freed instance”。
	var opening_ref:Variant=_opening_safe
	_opening_safe=null
	_safe_progress=0.0
	if is_instance_valid(opening_ref):
		_stop_safe_open_audio(opening_ref)

	for raw_supply:Variant in _supplies.duplicate():
		if is_instance_valid(raw_supply):
			var supply_node:=raw_supply as Node
			if supply_node!=null:
				supply_node.queue_free()
	for raw_safe:Variant in _safes.duplicate():
		if is_instance_valid(raw_safe):
			var safe_node:=raw_safe as Node
			if safe_node!=null:
				safe_node.queue_free()
	for entry:Dictionary in _pickup_flights.duplicate():
		var raw_pickup:Variant=entry.get("node")
		if is_instance_valid(raw_pickup):
			var pickup_node:=raw_pickup as Node
			if pickup_node!=null:
				pickup_node.queue_free()
	for raw_display:Variant in _safe_search_displays.duplicate():
		if is_instance_valid(raw_display):
			var display_node:=raw_display as Node
			if display_node!=null:
				display_node.queue_free()

	_supplies.clear()
	_safes.clear()
	_pickup_flights.clear()
	_safe_search_displays.clear()
	_supply_spawn_left=0.0

func get_money_text()->String:
	return "∞" if has_infinite_money else str(money)

func _setup_money_label()->void:
	if is_instance_valid(_money_label):
		return
	var label:=Label.new()
	label.name="MoneyValue"
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.z_index=92
	# 只显示数字，固定在人物世界坐标右侧；不挂背景、不加货币图标或文字。
	# ball 根节点默认 scale=0.2；因此这里使用约 5 倍的本地像素尺寸，
	# 保证战场实际显示仍有清晰可读的金色数字，并放在放大后的角色右侧。
	label.position=Vector2(118.0,-34.0)
	label.size=Vector2(190.0,64.0)
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",48)
	label.add_theme_color_override("font_color",Color(1.0,0.78,0.18,1.0))
	# 0偏移的低透明金色 shadow_outline 只做一圈很轻的光晕，不做明显投影。
	label.add_theme_color_override("font_shadow_color",Color(1.0,0.58,0.05,0.28))
	label.add_theme_constant_override("shadow_offset_x",0)
	label.add_theme_constant_override("shadow_offset_y",0)
	label.add_theme_constant_override("shadow_outline_size",5)
	# 一像素深金轮廓只用于压住复杂战场背景；视觉主体仍然是纯金数字。
	label.add_theme_color_override("font_outline_color",Color(0.28,0.15,0.02,0.72))
	label.add_theme_constant_override("outline_size",2)
	add_child(label)
	_money_label=label
	_refresh_money_label(true)

func _refresh_money_label(force:bool=false)->void:
	if not is_instance_valid(_money_label):
		return

	# V359：金钱只属于第一命跑刀鼠“搜刮阶段”的可视信息。
	# 第一命死亡、进入空降复活阶段或已经变成第二命猛攻哥后，立即隐藏文字。
	# money 数值本身仍保留，供死亡后购买猛攻装备使用。
	var should_show:bool = (
		life_index == 1
		and health > 0
		and not _revive_airdrop_active
	)
	_money_label.visible = should_show
	if not should_show:
		return

	var next_text:String=get_money_text()
	if force or next_text!=_money_label_text_cache:
		_money_label.text=next_text
		_money_label_text_cache=next_text

func _runner_music_bus()->StringName:
	if AudioServer.get_bus_index(&"GameplayRecord")>=0:
		return &"GameplayRecord"
	return &"Master"

func _load_runner_music_stream(path:String,looped:bool)->AudioStream:
	var source:=load(path) as AudioStream
	if source==null:
		return null
	# 不直接修改共享 imported resource 的 loop 属性，避免其它播放器引用同一资源时也被改成循环。
	var stream:=source.duplicate(true) as AudioStream
	var mp3:=stream as AudioStreamMP3
	if mp3!=null:
		mp3.loop=looped
		mp3.loop_offset=0.0
	return stream

func _setup_runner_music()->void:
	# V227：三首跑刀仔音乐严格共用一个播放器。
	# 不再用“BGM player + rare player 暂停其中一个”的双播放器结构，
	# 从节点层面保证任意时刻最多只存在一条跑刀仔音乐播放链。
	if not is_instance_valid(_runner_music_player):
		var player:=AudioStreamPlayer.new()
		player.name="跑刀仔专属音乐"
		player.bus=_runner_music_bus()
		player.max_polyphony=1
		player.add_to_group(RUNNER_MUSIC_GROUP)
		add_child(player)
		_runner_music_player=player
		player.finished.connect(_on_runner_music_finished)
	_switch_runner_phase_music(false)

func _claim_runner_music_channel()->void:
	# 同一战场即使存在多个跑刀仔，也只允许一个跑刀仔专属音乐播放器真正处于播放状态。
	if get_tree()==null:
		return
	for raw_player:Variant in get_tree().get_nodes_in_group(RUNNER_MUSIC_GROUP):
		if not is_instance_valid(raw_player):
			continue
		var other:=raw_player as AudioStreamPlayer
		if other!=null and other!=_runner_music_player and other.playing:
			other.stop()

func _runner_phase_music_path()->String:
	return REVIVE_BGM_PATH if _runner_music_phase_revived else FIRST_LIFE_BGM_PATH

func _runner_phase_music_volume()->float:
	return revive_bgm_volume_db if _runner_music_phase_revived else first_life_bgm_volume_db

func _switch_runner_phase_music(revived:bool)->void:
	if not is_instance_valid(_runner_music_player):
		return
	_runner_music_phase_revived=revived
	_runner_music_rare_active=false
	_runner_music_resume_position=0.0
	var stream:=_load_runner_music_stream(_runner_phase_music_path(),true)
	if stream==null:
		return
	_claim_runner_music_channel()
	_runner_music_player.stop()
	_runner_music_player.stream=stream
	_runner_music_player.volume_db=_runner_phase_music_volume()
	_runner_music_player.play(0.0)

func _is_big_red_or_infinite_loot(n:Node)->bool:
	if not is_instance_valid(n):
		return false
	if bool(n.get_meta("runner_infinite_money",false)):
		return true
	var quality:String=str(n.get_meta("runner_loot_quality",""))
	var size_name:String=str(n.get_meta("runner_loot_size",""))
	return quality=="红" and (size_name=="大" or size_name=="大大")

func _trigger_rare_loot_music_if_needed(n:Node)->void:
	if not is_instance_valid(n) or bool(n.get_meta("runner_rare_music_triggered",false)):
		return
	if not _is_big_red_or_infinite_loot(n):
		return
	n.set_meta("runner_rare_music_triggered",true)
	_play_runner_rare_loot_music()

func _play_runner_rare_loot_music()->void:
	if not is_instance_valid(_runner_music_player):
		return
	# 若该播放器曾被另一只跑刀仔抢占全局频道而 stop()，旧 rare_active 不能卡死后续触发。
	if _runner_music_rare_active and not _runner_music_player.playing:
		_runner_music_rare_active=false
	if _runner_music_rare_active:
		return
	var stream:=_load_runner_music_stream(RARE_LOOT_MUSIC_PATH,false)
	if stream==null:
		return
	# 用同一个播放器切歌。先记住当前阶段BGM位置，再 stop() 后播放稀有曲。
	# 因为 max_polyphony=1 且只有一个 AudioStreamPlayer，三首曲不可能同时存在。
	_runner_music_resume_position=_runner_music_player.get_playback_position() if _runner_music_player.playing else 0.0
	_runner_music_rare_active=true
	_claim_runner_music_channel()
	_runner_music_player.stop()
	_runner_music_player.stream=stream
	_runner_music_player.volume_db=rare_loot_music_volume_db
	_runner_music_player.play(0.0)

func _on_runner_music_finished()->void:
	# 循环的阶段BGM不会自然 finished；这里只有一次性稀有曲结束才需要恢复阶段BGM。
	if not _runner_music_rare_active or not is_instance_valid(_runner_music_player):
		return
	_runner_music_rare_active=false
	var stream:=_load_runner_music_stream(_runner_phase_music_path(),true)
	if stream==null:
		return
	var resume_at:float=maxf(_runner_music_resume_position,0.0)
	var length:float=stream.get_length()
	if length>0.0:
		resume_at=fmod(resume_at,length)
	_claim_runner_music_channel()
	_runner_music_player.stream=stream
	_runner_music_player.volume_db=_runner_phase_music_volume()
	_runner_music_player.play(resume_at)

func _stop_runner_music()->void:
	_runner_music_rare_active=false
	_runner_music_resume_position=0.0
	if is_instance_valid(_runner_music_player):
		_runner_music_player.stop()

func _spawn_loot()->void:
	var rect:=_map_rect()
	# V216：保险数量固定且开局就摆好；普通物资不再开局一次性全铺满。
	# 普通物资使用 supply_count 作为“场上软上限”，第一批也要经过随机延迟后才出现。
	_supply_spawn_left=_rng.randf_range(supply_initial_delay_min,supply_initial_delay_max)
	var start_right:bool=_rng.randi_range(0,1)==1
	var right_total:int=int(ceil(float(safe_count)*0.5)) if start_right else int(floor(float(safe_count)*0.5))
	var left_total:int=safe_count-right_total
	var right_index:int=0
	var left_index:int=0
	for i in range(safe_count):
		var on_right:bool=(i % 2 == 0) == start_right
		var side_index:int=right_index if on_right else left_index
		var side_total:int=right_total if on_right else left_total
		var n:=_safe_node(on_right)
		get_tree().current_scene.add_child(n)
		n.global_position=_spaced_side_wall_position(rect,on_right,side_index,side_total)
		if on_right:
			right_index+=1
		else:
			left_index+=1
		_safes.append(n)

func _tick_supply_spawner(delta:float)->void:
	if life_index!=1 or health<=0:
		return
	_supply_spawn_left=maxf(_supply_spawn_left-delta,0.0)
	if _supply_spawn_left>0.0:
		return
	if _supplies.size()<maxi(supply_count,1):
		_spawn_one_supply()
	_supply_spawn_left=_rng.randf_range(supply_spawn_interval_min,supply_spawn_interval_max)

func _spawn_one_supply()->void:
	var rect:=_map_rect()
	var item_def:Dictionary=_roll_item_definition()
	var n:=_item_node(item_def)
	get_tree().current_scene.add_child(n)
	n.global_position=_random_inside(rect)
	_supplies.append(n)
	_play_item_spawn_animation(n)
	_play_loot_sfx(str(item_def.get("quality","白")),true,n.global_position)

func _roll_item_definition()->Dictionary:
	# V357：为红甲/AWM门槛恢复两种“高级材料”极低概率地面刷新。
	# 它们不兑换钱，只作为第二命购买资格；普通品质概率结构随后继续沿用。
	var special_roll:float=_rng.randf_range(0.0,100.0)
	if special_roll<0.85:
		return (SPECIAL_UNLOCK_ITEMS["高级咖啡豆"] as Dictionary).duplicate(true)
	if special_roll<1.70:
		return (SPECIAL_UNLOCK_ITEMS["高级子弹零件"] as Dictionary).duplicate(true)

	# 普通地面物资品质越高越稀有；无限钱仍最低。
	var roll:=_rng.randf_range(0.0,100.0)
	var quality:String="白"
	if roll < 45.0:
		quality="白"
	elif roll < 75.0:
		quality="蓝"
	elif roll < 92.0:
		quality="紫"
	elif roll < 98.5:
		quality="金"
	elif roll < 99.9:
		quality="红"
	else:
		quality="无限"
	return _pick_item_from_quality(quality)

func _safe_definition_from_file(file_name:String)->Dictionary:
	for special_key:Variant in SPECIAL_UNLOCK_ITEMS.keys():
		var special:Dictionary=SPECIAL_UNLOCK_ITEMS[special_key] as Dictionary
		if str(special.get("file",""))==file_name:
			return special.duplicate(true)
	for quality_key:Variant in ITEM_POOLS.keys():
		var quality:String=str(quality_key)
		var pool:Array=ITEM_POOLS[quality] as Array
		for v:Variant in pool:
			var d:=v as Dictionary
			if str(d.get("file",""))==file_name:
				var result:Dictionary=d.duplicate(true)
				result["quality"]=quality
				return result
	return {}

func _roll_safe_item_definition()->Dictionary:
	# V221：保险只从 SAFE_LOOT_CHOICES 点名池抽取，不再从整个紫/金/红池随机。
	var total:float=0.0
	for choice_v:Variant in SAFE_LOOT_CHOICES:
		total+=float((choice_v as Dictionary).get("weight",1.0))
	if total<=0.0:
		return {}
	var roll:=_rng.randf_range(0.0,total)
	var acc:float=0.0
	var picked_choice:Dictionary=SAFE_LOOT_CHOICES[0] as Dictionary
	for choice_v:Variant in SAFE_LOOT_CHOICES:
		var choice:=choice_v as Dictionary
		acc+=float(choice.get("weight",1.0))
		if roll<=acc:
			picked_choice=choice
			break
	var result:=_safe_definition_from_file(str(picked_choice.get("file","")))
	if result.is_empty():
		return {}
	result["safe_grid_size"]=picked_choice.get("grid",Vector2i(1,1))
	result["safe_allow_rotate"]=bool(picked_choice.get("allow_rotate",false))
	return result

func _pick_item_from_quality(quality:String)->Dictionary:
	var pool:Array=ITEM_POOLS.get(quality,ITEM_POOLS["白"]) as Array
	if pool.is_empty():
		pool=ITEM_POOLS["白"] as Array
	# 同品质内也不是完全等概率：标注“大/大大”的高价值物品略稀有。
	var total:float=0.0
	var weights:Array[float]=[]
	for v:Variant in pool:
		var d:=v as Dictionary
		var size_name:String=str(d.get("size","小"))
		var w:float=1.0
		if size_name=="中": w=0.78
		elif size_name=="大": w=0.52
		elif size_name=="大大": w=0.22
		weights.append(w)
		total+=w
	var pick_roll:=_rng.randf_range(0.0,total)
	var acc:float=0.0
	var chosen:Dictionary=(pool[0] as Dictionary)
	for i in range(pool.size()):
		acc+=weights[i]
		if pick_roll<=acc:
			chosen=pool[i] as Dictionary
			break
	var picked:Dictionary=chosen.duplicate(true)
	picked["quality"]=quality
	return picked

func _safe_find_grid_fit(occupied:Array,requested:Vector2i,allow_rotate:bool)->Dictionary:
	var orientations:Array[Vector2i]=[requested]
	if allow_rotate and requested.x!=requested.y:
		orientations.append(Vector2i(requested.y,requested.x))
	# 3x3 从左上到右下按行顺序扫描；只有确实放不下默认朝向时才尝试旋转。
	for size:Vector2i in orientations:
		if size.x<1 or size.y<1 or size.x>3 or size.y>3:
			continue
		for y in range(0,4-size.y):
			for x in range(0,4-size.x):
				var free:bool=true
				for yy in range(y,y+size.y):
					for xx in range(x,x+size.x):
						if bool(occupied[yy*3+xx]):
							free=false
							break
					if not free:
						break
				if free:
					return {"pos":Vector2i(x,y),"size":size,"rotated":size!=requested}
	return {}

func _safe_mark_grid(occupied:Array,fit:Dictionary)->void:
	var pos:Vector2i=fit.get("pos",Vector2i.ZERO)
	var size:Vector2i=fit.get("size",Vector2i.ONE)
	for y in range(pos.y,pos.y+size.y):
		for x in range(pos.x,pos.x+size.x):
			occupied[y*3+x]=true

func _prepare_safe_loot(safe:Node2D)->void:
	if not is_instance_valid(safe) or safe.has_meta("runner_safe_planned_loot"):
		return
	var wanted_count:int=1
	var r:float=_rng.randf()
	if r>=0.50 and r<0.85:
		wanted_count=2
	elif r>=0.85:
		wanted_count=3
	var planned:Array[Dictionary]=[]
	var used:Dictionary={}
	var occupied:Array=[false,false,false,false,false,false,false,false,false]
	for _slot in range(wanted_count):
		var accepted:Dictionary={}
		# 尝试抽到一个“既未重复、又能真实塞进当前3x3剩余空间”的物品。
		for _try in range(48):
			var candidate:=_roll_safe_item_definition()
			if candidate.is_empty():
				continue
			var file_name:String=str(candidate.get("file",""))
			if used.has(file_name):
				continue
			var requested:Vector2i=candidate.get("safe_grid_size",Vector2i(1,1))
			var fit:=_safe_find_grid_fit(occupied,requested,bool(candidate.get("safe_allow_rotate",false)))
			if fit.is_empty():
				continue
			candidate["safe_grid_pos"]=fit.get("pos",Vector2i.ZERO)
			candidate["safe_grid_size_actual"]=fit.get("size",requested)
			candidate["safe_grid_rotated"]=bool(fit.get("rotated",false))
			_safe_mark_grid(occupied,fit)
			used[file_name]=true
			accepted=candidate
			break
		if accepted.is_empty():
			break
		planned.append(accepted)
	safe.set_meta("runner_safe_planned_loot",planned)


func _item_node(item_def:Dictionary)->Node2D:
	var root:=Node2D.new()
	root.name="跑刀物资_"+str(item_def.get("file","物资"))
	root.add_to_group("BattleTransient")
	root.set_meta("runner_loot_quality",str(item_def.get("quality","白")))
	root.set_meta("runner_loot_file",str(item_def.get("file","")))
	root.set_meta("runner_loot_size",str(item_def.get("size","小")))
	root.set_meta("runner_loot_value",int(item_def.get("value",supply_money)))
	root.set_meta("runner_infinite_money",bool(item_def.get("infinite",false)))
	root.set_meta("runner_special_unlock",str(item_def.get("special_unlock","")))

	var tex:=load(ITEM_TEXTURE_DIR+str(item_def.get("file",""))) as Texture2D
	if tex==null:
		return _fallback_loot_node(root,_quality_color(str(item_def.get("quality","白"))),Vector2(9,9))

	var target_extent:=_item_display_extent(str(item_def.get("size","小")))
	var tex_size:=tex.get_size()
	var max_side:=maxf(tex_size.x,tex_size.y)
	var visual_scale:=target_extent/maxf(max_side,1.0)

	# V216：物资只显示原图，不再绘制任何品质背景板。品质只用于出生瞬间的纯色闪光。
	var sprite:=Sprite2D.new()
	sprite.name="ItemSprite"
	sprite.texture=tex
	sprite.scale=Vector2.ONE*visual_scale*0.28
	sprite.z_index=0
	root.set_meta("runner_item_base_scale",visual_scale)
	var shader:=load(ITEM_SPAWN_SHADER_PATH) as Shader
	if shader!=null:
		var material:=ShaderMaterial.new()
		material.shader=shader
		material.set_shader_parameter("flash_color",_quality_color(str(item_def.get("quality","白"))))
		material.set_shader_parameter("flash_amount",1.0)
		sprite.material=material
	root.add_child(sprite)
	return root

func _play_item_spawn_animation(root:Node2D)->void:
	if not is_instance_valid(root):
		return
	var sprite:=root.get_node_or_null("ItemSprite") as Sprite2D
	if sprite==null:
		return
	var base_scale:float=float(root.get_meta("runner_item_base_scale",1.0))
	var base_vec:=Vector2.ONE*base_scale
	# 出现动作：从小尺寸瞬间爆到约1.38倍，再回弹到0.90倍，最后稳定在正常尺寸。
	var pop:=root.create_tween()
	pop.tween_property(sprite,"scale",base_vec*1.38,0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(sprite,"scale",base_vec*0.90,0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pop.tween_property(sprite,"scale",base_vec,0.11).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 品质闪光：出生第一瞬间整张图只保留alpha轮廓并替换成对应品质纯色，然后快速恢复原贴图。
	var material:=sprite.material as ShaderMaterial
	if material!=null:
		var flash:=root.create_tween()
		flash.tween_interval(0.055)
		flash.tween_method(_set_item_spawn_flash.bind(material),1.0,0.0,0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _set_item_spawn_flash(amount:float,material:ShaderMaterial)->void:
	if material!=null:
		material.set_shader_parameter("flash_amount",clampf(amount,0.0,1.0))

func _safe_node(on_right_wall:bool)->Node2D:
	var root:=Node2D.new()
	root.name="跑刀保险"
	root.add_to_group("BattleTransient")
	root.set_meta("runner_loot_kind","safe")
	root.set_meta("runner_safe_on_right",on_right_wall)
	# V216：保险必须压在地图边界墙/背景之上。使用绝对Z，避免继承World负z后再次被地图层遮住。
	root.z_as_relative=false
	root.z_index=SAFE_Z_INDEX
	var tex:=load(SAFE_TEXTURE_PATH) as Texture2D
	if tex==null:
		return _fallback_loot_node(root,Color(0.76,0.68,0.28),Vector2(16,11))
	var sprite:=Sprite2D.new()
	sprite.texture=tex
	var size:=tex.get_size()
	var scale_value:=36.0/maxf(maxf(size.x,size.y),1.0)
	sprite.scale=Vector2.ONE*scale_value
	# 用户提供的保险默认朝右：左墙保持原图朝地图内；右墙水平翻转后朝左、同样朝地图内。
	sprite.flip_h=on_right_wall
	root.add_child(sprite)
	var open_audio:=AudioStreamPlayer2D.new()
	open_audio.name="OpenAudio"
	open_audio.stream=load(SAFE_OPEN_SFX_PATH) as AudioStream
	# V222：保险开启音效提高基础音量；AudioStreamPlayer2D仍保留正常2D距离衰减。
	open_audio.volume_db=safe_open_volume_db
	root.add_child(open_audio)
	return root

func _is_gold_or_above(quality:String)->bool:
	return quality=="金" or quality=="红" or quality=="无限"

func _play_loot_sfx(quality:String,is_spawn:bool,world_pos:Vector2)->void:
	var path:String
	if is_spawn:
		path=SEARCH_HIGH_SFX_PATH if _is_gold_or_above(quality) else SEARCH_LOW_SFX_PATH
	else:
		path=PICKUP_HIGH_SFX_PATH if _is_gold_or_above(quality) else PICKUP_LOW_SFX_PATH
	var stream:=load(path) as AudioStream
	if stream==null or get_tree()==null or get_tree().current_scene==null:
		return
	var player:=AudioStreamPlayer2D.new()
	player.stream=stream
	get_tree().current_scene.add_child(player)
	player.global_position=world_pos
	player.finished.connect(player.queue_free)
	player.play()

func _safe_audio_player(safe_ref:Variant)->AudioStreamPlayer2D:
	if not is_instance_valid(safe_ref):
		return null
	var safe:=safe_ref as Node2D
	if safe==null:
		return null
	return safe.get_node_or_null("OpenAudio") as AudioStreamPlayer2D

func _start_safe_open_audio(safe_ref:Variant)->void:
	var player:=_safe_audio_player(safe_ref)
	if player==null or player.stream==null:
		return
	player.stop()
	player.play(0.0)

func _stop_safe_open_audio(safe_ref:Variant)->void:
	var player:=_safe_audio_player(safe_ref)
	if player!=null and player.playing:
		player.stop()

func _safe_open_duration(safe_ref:Variant)->float:
	var player:=_safe_audio_player(safe_ref)
	if player!=null and player.stream!=null:
		var stream_length:float=player.stream.get_length()
		if stream_length>0.0:
			return stream_length
	return maxf(safe_open_time,0.05)

func _fade_safe_into_search(safe:Node2D)->void:
	if not is_instance_valid(safe):
		return
	# 搜索框的Z高于保险，因此动画开始同帧就会盖在保险上；保险只在原地缩小/淡出。
	var start_scale:Vector2=safe.scale
	var start_modulate:Color=safe.modulate
	var target_modulate:=Color(start_modulate.r,start_modulate.g,start_modulate.b,0.0)
	var fade:=safe.create_tween().set_parallel(true)
	fade.tween_property(safe,"scale",start_scale*0.56,0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	fade.tween_property(safe,"modulate",target_modulate,0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	fade.finished.connect(safe.queue_free)

func _start_safe_search_display(safe_pos:Vector2,on_right:bool,planned:Array)->void:
	if get_tree()==null or get_tree().current_scene==null or planned.is_empty():
		return
	var display:=Node2D.new()
	display.name="跑刀保险搜索结果"
	display.add_to_group("BattleTransient")
	display.z_as_relative=false
	display.z_index=SAFE_Z_INDEX+4
	get_tree().current_scene.add_child(display)
	display.global_position=safe_pos
	_safe_search_displays.append(display)

	var cell:float=13.0
	var panel:=_make_safe_search_panel(cell)
	display.add_child(panel)

	# V222：保险不是“一次搜完全部”。每件提前确定的战利品都先被自己的深灰遮罩盖住；
	# 搜索时逐件移动放大镜到对应占格，品质越高等待越久，完成一件才揭开下一件。
	var search_entries:Array[Dictionary]=[]
	for planned_v:Variant in planned:
		var item_def:=planned_v as Dictionary
		var grid_pos:Vector2i=item_def.get("safe_grid_pos",Vector2i.ZERO)
		var grid_size:Vector2i=item_def.get("safe_grid_size_actual",Vector2i.ONE)
		var center_cells:=Vector2(float(grid_pos.x)+float(grid_size.x)*0.5,float(grid_pos.y)+float(grid_size.y)*0.5)
		var local_pos:Vector2=(center_cells-Vector2(1.5,1.5))*cell

		var quality:String=str(item_def.get("quality","紫"))
		var quality_bg:=_make_safe_quality_background(local_pos,grid_size,cell,quality)
		quality_bg.visible=false
		quality_bg.z_index=0
		display.add_child(quality_bg)

		var item_root:=_item_node(item_def)
		item_root.position=local_pos
		item_root.visible=false
		item_root.z_index=1
		if bool(item_def.get("safe_grid_rotated",false)):
			item_root.rotation=PI*0.5
		_fit_safe_result_item(item_root,grid_size,cell,bool(item_def.get("safe_grid_rotated",false)))
		display.add_child(item_root)

		var cover:=_make_safe_unsearched_cover(local_pos,grid_size,cell)
		cover.z_index=2
		display.add_child(cover)
		search_entries.append({
			"item":item_root,
			"quality_bg":quality_bg,
			"cover":cover,
			"center":local_pos,
			"grid_size":grid_size,
			"cell":cell,
			"quality":quality,
		})

	var magnifier:=_make_magnifier_icon()
	magnifier.z_index=3
	display.add_child(magnifier)
	call_deferred("_run_safe_search_animation",display,magnifier,search_entries)

func _make_safe_quality_background(local_center:Vector2,grid_size:Vector2i,cell:float,quality:String)->Node2D:
	# V227：已搜出的保险物品按品质给“实际占据格子区域”上色，但继续保留渐变。
	# 未搜索时仍由深灰条纹问号遮罩完全盖住，因此不会提前泄露品质。
	var root:=Node2D.new()
	root.name="品质渐变背景_"+quality
	root.position=local_center
	var width:float=maxf(float(grid_size.x)*cell-1.2,4.0)
	var height:float=maxf(float(grid_size.y)*cell-1.2,4.0)
	var hw:float=width*0.5
	var hh:float=height*0.5
	var base:=_quality_color(quality)
	var panel_gray_top:=Color(0.205,0.215,0.225,0.96)
	var panel_gray_bottom:=Color(0.115,0.122,0.132,0.96)
	# 上半部更亮、下半部更深；品质色只作为色相和强调，不改成纯色块。
	var top_color:=panel_gray_top.lerp(base,0.58)
	var bottom_color:=panel_gray_bottom.lerp(base.darkened(0.34),0.72)
	top_color.a=0.94
	bottom_color.a=0.94
	var steps:int=8
	for i in range(steps):
		var t0:float=float(i)/float(steps)
		var t1:float=float(i+1)/float(steps)
		var y0:float=lerpf(-hh,hh,t0)
		var y1:float=lerpf(-hh,hh,t1)
		var strip:=Polygon2D.new()
		strip.polygon=PackedVector2Array([
			Vector2(-hw,y0),Vector2(hw,y0),Vector2(hw,y1),Vector2(-hw,y1)
		])
		strip.color=top_color.lerp(bottom_color,(t0+t1)*0.5)
		root.add_child(strip)
	return root

func _make_safe_unsearched_cover(local_center:Vector2,grid_size:Vector2i,cell:float)->Node2D:
	var root:=Node2D.new()
	root.name="未搜索物资遮罩"
	root.position=local_center
	var width:float=maxf(float(grid_size.x)*cell-1.2,4.0)
	var height:float=maxf(float(grid_size.y)*cell-1.2,4.0)
	var hw:float=width*0.5
	var hh:float=height*0.5

	var fill:=Polygon2D.new()
	fill.polygon=PackedVector2Array([
		Vector2(-hw,-hh),Vector2(hw,-hh),Vector2(hw,hh),Vector2(-hw,hh)
	])
	fill.color=Color(0.067,0.073,0.082,0.985)
	root.add_child(fill)

	# 深灰底上叠轻微斜向条纹杂色。条纹只落在本物品真实占格矩形内，避免污染相邻格子。
	var diagonal_min:float=-hw-hh
	var diagonal_max:float=hw+hh
	var d:float=diagonal_min
	var stripe_index:int=0
	while d<=diagonal_max+0.001:
		var pts:=_safe_diagonal_segment(d,hw,hh)
		if pts.size()>=2:
			var stripe:=Line2D.new()
			stripe.width=1.05 if stripe_index%3!=0 else 1.35
			var alpha:float=0.17 if stripe_index%2==0 else 0.10
			stripe.default_color=Color(0.27,0.285,0.31,alpha)
			stripe.points=pts
			root.add_child(stripe)
		stripe_index+=1
		d+=4.6

	# V224：问号不再使用字体 Label。字体的 ascent / side-bearing 会让“?”视觉上看起来偏离几何中心。
	# 改为以 root 原点直接绘制的矢量问号，因此 1x1 / 1x2 / 2x3 等任何 footprint 都严格居中。
	var icon_span:float=maxf(minf(width,height)*0.62,5.0)
	var question_color:=Color(0.67,0.69,0.72,0.92)
	var hook:=Line2D.new()
	hook.name="QuestionHook"
	hook.width=maxf(icon_span*0.115,1.05)
	hook.default_color=question_color
	hook.joint_mode=Line2D.LINE_JOINT_ROUND
	hook.begin_cap_mode=Line2D.LINE_CAP_ROUND
	hook.end_cap_mode=Line2D.LINE_CAP_ROUND
	hook.points=PackedVector2Array([
		Vector2(-0.27,-0.23)*icon_span,
		Vector2(-0.22,-0.36)*icon_span,
		Vector2(-0.04,-0.43)*icon_span,
		Vector2(0.17,-0.39)*icon_span,
		Vector2(0.29,-0.24)*icon_span,
		Vector2(0.26,-0.08)*icon_span,
		Vector2(0.12,0.04)*icon_span,
		Vector2(0.015,0.10)*icon_span,
		Vector2(0.015,0.19)*icon_span,
	])
	root.add_child(hook)
	var dot:=Polygon2D.new()
	dot.name="QuestionDot"
	var dot_pts:=PackedVector2Array()
	var dot_center:=Vector2(0.015,0.36)*icon_span
	var dot_radius:float=maxf(icon_span*0.072,0.75)
	for qi in range(14):
		var qa:float=TAU*float(qi)/14.0
		dot_pts.append(dot_center+Vector2(cos(qa),sin(qa))*dot_radius)
	dot.polygon=dot_pts
	dot.color=question_color
	root.add_child(dot)
	return root

func _safe_diagonal_segment(d:float,hw:float,hh:float)->PackedVector2Array:
	# 斜线定义 x-y=d，与矩形四边求交，返回矩形内部的两个端点。
	var candidates:Array[Vector2]=[]
	var x_top:float=d-hh
	if x_top>=-hw and x_top<=hw:
		candidates.append(Vector2(x_top,-hh))
	var x_bottom:float=d+hh
	if x_bottom>=-hw and x_bottom<=hw:
		candidates.append(Vector2(x_bottom,hh))
	var y_left:float=-hw-d
	if y_left>=-hh and y_left<=hh:
		candidates.append(Vector2(-hw,y_left))
	var y_right:float=hw-d
	if y_right>=-hh and y_right<=hh:
		candidates.append(Vector2(hw,y_right))
	var unique:=PackedVector2Array()
	for p:Vector2 in candidates:
		var duplicated:bool=false
		for u:Vector2 in unique:
			if u.distance_squared_to(p)<0.0001:
				duplicated=true
				break
		if not duplicated:
			unique.append(p)
		if unique.size()>=2:
			break
	return unique

func _safe_item_search_duration(quality:String)->float:
	match quality:
		"无限": return maxf(safe_search_time_infinite,0.05)
		"红": return maxf(safe_search_time_red,0.05)
		"金": return maxf(safe_search_time_gold,0.05)
		"紫": return maxf(safe_search_time_purple,0.05)
		_: return maxf(safe_search_duration,0.05)

func _make_safe_search_panel(cell:float)->Node2D:
	var panel:=Node2D.new()
	panel.name="SafeSearchPanel"
	# V221：固定3x3，整体明显缩小。只保留“渐变填充 + 单层描边 + 必要网格分隔”。
	var half:float=cell*1.5+2.0
	var gradient_steps:int=10
	var top_color:=Color(0.205,0.215,0.225,0.985)
	var bottom_color:=Color(0.115,0.122,0.132,0.985)
	for i in range(gradient_steps):
		var t0:float=float(i)/float(gradient_steps)
		var t1:float=float(i+1)/float(gradient_steps)
		var y0:float=lerpf(-half,half,t0)
		var y1:float=lerpf(-half,half,t1)
		var strip:=Polygon2D.new()
		strip.polygon=PackedVector2Array([
			Vector2(-half,y0),Vector2(half,y0),Vector2(half,y1),Vector2(-half,y1)
		])
		strip.color=top_color.lerp(bottom_color,(t0+t1)*0.5)
		panel.add_child(strip)
	# 描边颜色刻意接近填充色，只比背景略亮，不再用灰白高对比双描边。
	var border:=Line2D.new()
	border.width=1.35
	border.default_color=Color(0.31,0.33,0.36,0.96)
	border.points=PackedVector2Array([
		Vector2(-half,-half),Vector2(half,-half),Vector2(half,half),Vector2(-half,half),Vector2(-half,-half)
	])
	panel.add_child(border)
	# 3x3只画四条很淡的分隔线，不为每个格子再套独立填充/描边。
	for k in [1,2]:
		var x:float=-cell*1.5+cell*float(k)
		var vline:=Line2D.new()
		vline.width=0.75
		vline.default_color=Color(0.27,0.285,0.31,0.54)
		vline.points=PackedVector2Array([Vector2(x,-cell*1.5),Vector2(x,cell*1.5)])
		panel.add_child(vline)
		var y:float=-cell*1.5+cell*float(k)
		var hline:=Line2D.new()
		hline.width=0.75
		hline.default_color=Color(0.27,0.285,0.31,0.54)
		hline.points=PackedVector2Array([Vector2(-cell*1.5,y),Vector2(cell*1.5,y)])
		panel.add_child(hline)
	return panel

func _fit_safe_result_item(item_root:Node2D,grid_size:Vector2i,cell:float,rotated:bool)->void:
	var sprite:=item_root.get_node_or_null("ItemSprite") as Sprite2D
	if sprite==null or sprite.texture==null:
		return
	var tex_size:Vector2=sprite.texture.get_size()
	if rotated:
		tex_size=Vector2(tex_size.y,tex_size.x)
	var available:=Vector2(float(grid_size.x)*cell-3.0,float(grid_size.y)*cell-3.0)
	# 旋转后的1x2会用2x1实际占格尺寸重新计算可见缩放，不会超出3x3面板。
	var fit_scale:float=minf(available.x/maxf(tex_size.x,1.0),available.y/maxf(tex_size.y,1.0))
	fit_scale=maxf(fit_scale,0.01)
	item_root.set_meta("runner_item_base_scale",fit_scale)
	sprite.scale=Vector2.ONE*fit_scale*0.28


func _make_magnifier_icon()->Node2D:
	var root:=Node2D.new()
	root.name="SearchMagnifier"
	# V224：几何围绕原点重新校准。整体包围盒以(0,0)为视觉中心，避免把Node放在footprint中心后
	# 放大镜仍因为手柄偏向右下而看起来偏位。影子很轻，只用于和深灰遮罩分离。
	var shadow_color:=Color(0.01,0.015,0.02,0.48)
	var body_color:=Color(0.94,0.96,0.99,0.97)
	var circle_center:=Vector2(-1.7,-1.7)
	var circle_radius:float=4.8
	var handle_start:=Vector2(1.65,1.65)
	var handle_end:=Vector2(6.45,6.45)
	var shadow_offset:=Vector2(0.65,0.75)

	var shadow_circle:=Line2D.new()
	shadow_circle.position=shadow_offset
	shadow_circle.width=3.0
	shadow_circle.default_color=shadow_color
	var shadow_pts:=PackedVector2Array()
	for i in range(25):
		var sa:=TAU*float(i)/24.0
		shadow_pts.append(circle_center+Vector2(cos(sa),sin(sa))*circle_radius)
	shadow_circle.points=shadow_pts
	root.add_child(shadow_circle)
	var shadow_handle:=Line2D.new()
	shadow_handle.position=shadow_offset
	shadow_handle.width=3.35
	shadow_handle.default_color=shadow_color
	shadow_handle.points=PackedVector2Array([handle_start,handle_end])
	root.add_child(shadow_handle)

	var circle:=Line2D.new()
	circle.width=2.05
	circle.default_color=body_color
	var pts:=PackedVector2Array()
	for i in range(25):
		var a:=TAU*float(i)/24.0
		pts.append(circle_center+Vector2(cos(a),sin(a))*circle_radius)
	circle.points=pts
	root.add_child(circle)
	var handle:=Line2D.new()
	handle.width=2.45
	handle.default_color=body_color
	handle.points=PackedVector2Array([handle_start,handle_end])
	root.add_child(handle)
	return root

func _safe_magnifier_scale_for_grid(grid_size:Vector2i,cell:float)->float:
	# V224：仍按短边格数等比缩放，但图标本体必须完整落在对应短边占格里。
	# 1格图标目标可见跨度约为0.76格；2格约为1.52格，给摆动与描边留出余量。
	var short_cells:int=maxi(1,mini(grid_size.x,grid_size.y))
	var target_span:float=float(short_cells)*cell*0.76
	# 新矢量放大镜的基础可见包围盒约14px。
	return maxf(target_span/14.0,0.05)

func _run_safe_search_animation(display:Node2D,magnifier:Node2D,search_entries:Array[Dictionary])->void:
	if not is_instance_valid(display):
		return

	# V222：一件一件搜。尚未轮到的物品一直保持“深灰条纹 + ?”覆盖；
	# 当前品质只决定这一件需要搜多久：紫 < 金 < 红 < 无限钱。
	for entry:Dictionary in search_entries:
		if not is_instance_valid(display) or not is_instance_valid(magnifier):
			return
		var raw_item:Variant=entry.get("item")
		var raw_cover:Variant=entry.get("cover")
		var item_root:Node2D=null
		var cover:Node2D=null
		if is_instance_valid(raw_item):
			item_root=raw_item as Node2D
		if is_instance_valid(raw_cover):
			cover=raw_cover as Node2D
		var center:Vector2=entry.get("center",Vector2.ZERO)
		var grid_size:Vector2i=entry.get("grid_size",Vector2i.ONE)
		var cell:float=float(entry.get("cell",13.0))
		var quality:String=str(entry.get("quality","紫"))
		var duration:float=_safe_item_search_duration(quality)

		# V223：放大镜的基准点就是该物品实际 footprint 的几何中心；摆动只围绕这个中心小幅发生。
		var short_cells:int=maxi(1,mini(grid_size.x,grid_size.y))
		var short_span:float=float(short_cells)*cell
		var magnifier_scale:float=_safe_magnifier_scale_for_grid(grid_size,cell)
		magnifier.scale=Vector2.ONE*magnifier_scale
		magnifier.position=center
		magnifier.rotation=0.0
		var swing_x:float=short_span*0.065
		var swing_y:float=short_span*0.022
		var half_cycle:float=0.30
		var loops:int=maxi(1,int(ceil(duration/(half_cycle*2.0))))
		var swing:=display.create_tween().set_loops(loops)
		swing.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		swing.tween_property(magnifier,"position",center+Vector2(swing_x,swing_y),half_cycle)
		swing.parallel().tween_property(magnifier,"rotation",deg_to_rad(4.5),half_cycle)
		swing.tween_property(magnifier,"position",center+Vector2(-swing_x,-swing_y),half_cycle)
		swing.parallel().tween_property(magnifier,"rotation",deg_to_rad(-4.5),half_cycle)

		await get_tree().create_timer(duration).timeout
		if swing!=null:
			swing.kill()
		if not is_instance_valid(display):
			return

		var quality_bg_ref:Variant=entry.get("quality_bg")
		if is_instance_valid(quality_bg_ref):
			var quality_bg:=quality_bg_ref as CanvasItem
			if quality_bg!=null:
				quality_bg.visible=true
		if is_instance_valid(item_root):
			item_root.visible=true
			_play_item_spawn_animation(item_root)
			# V228：保险逐件揭示物资时必须播放与地面“刷新物资”完全相同的搜索音效。
			# 紫及以下 -> 搜索紫以下.MP3；金/红/无限 -> 搜索金以上.MP3。
			# 这是“搜出来/刷新”音效，不替代稍后吸附到人物时的拾取音效。
			_play_loot_sfx(quality,true,item_root.global_position)
			# V226：保险逐件搜索到“大红及以上/无限钱”时，在真正揭示这一件的瞬间触发稀有物资音乐。
			# 物品稍后自动飞到人物身上时不会再次重播。
			_trigger_rare_loot_music_if_needed(item_root)
		if is_instance_valid(cover):
			var cover_tween:=cover.create_tween().set_parallel(true)
			cover_tween.tween_property(cover,"modulate:a",0.0,0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			cover_tween.tween_property(cover,"scale",Vector2.ONE*1.035,0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			cover_tween.finished.connect(cover.queue_free)
		await get_tree().create_timer(0.10).timeout

	if is_instance_valid(magnifier):
		magnifier.queue_free()
	await get_tree().create_timer(maxf(safe_result_hold_time,0.10)).timeout

	for entry:Dictionary in search_entries:
		var raw_item:Variant=entry.get("item")
		if not is_instance_valid(raw_item):
			continue
		var item_root:=raw_item as Node2D
		if item_root==null:
			continue
		item_root.reparent(get_tree().current_scene,true)
		_start_pickup_flight(item_root)

	_safe_search_displays.erase(display)
	if is_instance_valid(display):
		display.queue_free()

func _fallback_loot_node(root:Node2D,c:Color,size:Vector2)->Node2D:
	var p:=Polygon2D.new()
	p.polygon=PackedVector2Array([
		Vector2(-size.x,-size.y),Vector2(size.x,-size.y),
		Vector2(size.x,size.y),Vector2(-size.x,size.y)
	])
	p.color=c
	root.add_child(p)
	return root

func _item_display_extent(size_name:String)->float:
	match size_name:
		"大大": return 36.0
		"大": return 29.0
		"中": return 21.0
		_: return 18.0

func _quality_color(quality:String)->Color:
	match quality:
		"蓝": return Color(0.22,0.50,1.0,1.0)
		"紫": return Color(0.65,0.28,0.95,1.0)
		"金": return Color(1.0,0.72,0.16,1.0)
		"红": return Color(1.0,0.18,0.14,1.0)
		"无限": return Color(1.0,0.05,0.22,1.0)
		_: return Color(0.92,0.94,0.96,1.0)

func _random_inside(r:Rect2)->Vector2:
	return Vector2(
		_rng.randf_range(r.position.x+35,r.end.x-35),
		_rng.randf_range(r.position.y+35,r.end.y-35)
	)

func _spaced_side_wall_position(r:Rect2,on_right_wall:bool,index:int,total:int)->Vector2:
	# V224：同一侧保险使用分段采样而不是各自完全随机Y。这样数量固定时不会互相叠在一起，
	# 同时仍保留少量随机感。视觉保险约36px，高度方向额外留 safe_wall_min_visual_gap。
	var x:float=r.end.x+18.0 if on_right_wall else r.position.x-18.0
	var min_y:float=r.position.y+24.0
	var max_y:float=r.end.y-24.0
	if total<=1 or max_y<=min_y+1.0:
		return Vector2(x,(min_y+max_y)*0.5)
	var span:float=max_y-min_y
	var segment:float=span/float(total)
	var safe_visual_height:float=36.0
	var max_jitter:float=maxf((segment-(safe_visual_height+safe_wall_min_visual_gap))*0.5,0.0)
	max_jitter=minf(max_jitter,4.0)
	var center_y:float=min_y+segment*(float(index)+0.5)
	if max_jitter>0.01:
		center_y+=_rng.randf_range(-max_jitter,max_jitter)
	return Vector2(x,clampf(center_y,min_y,max_y))


# ========================================================
# V357 第二命“猛攻哥”真实 3x3 装备系统
# ========================================================

func _berserker_definition_for_weapon(name:String)->Dictionary:
	if not BERSERKER_WEAPON_DEFS.has(name):
		return {}
	var result:Dictionary=(BERSERKER_WEAPON_DEFS[name] as Dictionary).duplicate(true)
	result["name"]=name
	result["kind"]="weapon"
	result["allow_rotate"]=true
	result["mag_current"]=int(result.get("mag",0))
	result["consumed"]=false
	return result


func _berserker_definition_for_armor(name:String)->Dictionary:
	if not BERSERKER_ARMOR_DEFS.has(name):
		return {}
	var result:Dictionary=(BERSERKER_ARMOR_DEFS[name] as Dictionary).duplicate(true)
	result["name"]=name
	result["kind"]="armor"
	result["allow_rotate"]=true
	result["consumed"]=false
	return result


func _berserker_definition_for_consumable(name:String)->Dictionary:
	if not BERSERKER_CONSUMABLE_DEFS.has(name):
		return {}
	var result:Dictionary=(BERSERKER_CONSUMABLE_DEFS[name] as Dictionary).duplicate(true)
	result["name"]=name
	# V376：尊重单个药品定义。350血包固定横向，不允许为了塞格子自动旋转。
	result["allow_rotate"]=bool(result.get("allow_rotate",true))
	result["consumed"]=false
	match str(result.get("kind","")):
		"heal":
			result["remaining"]=float(result.get("capacity",0.0))
		"repair":
			result["remaining_uses"]=int(result.get("uses",1))
	return result


func _berserker_requirement_met(definition:Dictionary)->bool:
	var requirement:String=str(definition.get("requires",""))
	match requirement:
		"coffee":
			return has_advanced_coffee_bean
		"ammo_part":
			return has_advanced_ammo_part
		_:
			return true


func _berserker_add_packed_item(
	item:Dictionary,
	occupied:Array,
	budget_left:int
)->Dictionary:
	if item.is_empty():
		return {"accepted":false,"budget":budget_left}
	var price:int=maxi(int(item.get("price",0)),0)
	if price>budget_left:
		return {"accepted":false,"budget":budget_left}
	if not _berserker_requirement_met(item):
		return {"accepted":false,"budget":budget_left}

	var stored:Dictionary=item.duplicate(true)
	stored["item_id"]=_berserker_items.size()+1
	var kind:String=str(stored.get("kind",""))

	# V358：枪和护甲是人物身上装备，不进入 3x3 背包，也不占任何格子。
	# 只有血药/甲修等 backpack consumable 才调用 grid fit。
	if kind=="weapon" or kind=="armor":
		stored["equipped"]=true
		stored.erase("grid_pos")
		stored.erase("grid_size_actual")
		stored.erase("grid_rotated")
		_berserker_items.append(stored)
	else:
		var requested:Vector2i=stored.get("grid",Vector2i.ONE)
		var fit:Dictionary=_safe_find_grid_fit(occupied,requested,bool(stored.get("allow_rotate",true)))
		if fit.is_empty():
			return {"accepted":false,"budget":budget_left}
		stored["grid_pos"]=fit.get("pos",Vector2i.ZERO)
		stored["grid_size_actual"]=fit.get("size",requested)
		stored["grid_rotated"]=bool(fit.get("rotated",false))
		_berserker_items.append(stored)
		_safe_mark_grid(occupied,fit)

	# 红甲/AWM 的高级材料属于“制作资格材料”，成功买到后消费掉。
	var requirement:String=str(stored.get("requires",""))
	if requirement=="coffee":
		has_advanced_coffee_bean=false
	elif requirement=="ammo_part":
		has_advanced_ammo_part=false

	return {"accepted":true,"budget":budget_left-price}


func _berserker_best_affordable_weapon(
	budget_left:int,
	_occupied:Array,
	max_price:int=-1
)->Dictionary:
	var order:PackedStringArray=PackedStringArray(["AWM","M250","M7","AUG","PSG-1","G18"])
	for weapon_name:String in order:
		var candidate:Dictionary=_berserker_definition_for_weapon(weapon_name)
		var price:int=int(candidate.get("price",0))
		if max_price>=0 and price>max_price:
			continue
		if price>budget_left or not _berserker_requirement_met(candidate):
			continue
		return candidate
	return {}


func _berserker_best_affordable_armor(budget_left:int,_occupied:Array)->Dictionary:
	var order:PackedStringArray=PackedStringArray(["红甲","金甲","紫甲","蓝甲"])
	for armor_name:String in order:
		var candidate:Dictionary=_berserker_definition_for_armor(armor_name)
		if int(candidate.get("price",0))>budget_left or not _berserker_requirement_met(candidate):
			continue
		return candidate
	return {}


func _berserker_count_kind(kind:String)->int:
	var total:int=0
	for item:Dictionary in _berserker_items:
		if not bool(item.get("consumed",false)) and str(item.get("kind",""))==kind:
			total+=1
	return total


func _append_standalone_berserker_item(item:Dictionary,occupied:Array)->bool:
	if item.is_empty():
		return false

	var stored:Dictionary=item.duplicate(true)
	stored["item_id"]=_berserker_items.size()+1
	var kind:String=str(stored.get("kind",""))

	if kind=="weapon" or kind=="armor":
		stored["equipped"]=true
		stored.erase("grid_pos")
		stored.erase("grid_size_actual")
		stored.erase("grid_rotated")
		_berserker_items.append(stored)
		return true

	var requested:Vector2i=stored.get("grid",Vector2i.ONE)
	var fit:Dictionary=_safe_find_grid_fit(
		occupied,
		requested,
		bool(stored.get("allow_rotate",true))
	)
	if fit.is_empty():
		return false
	stored["grid_pos"]=fit.get("pos",Vector2i.ZERO)
	stored["grid_size_actual"]=fit.get("size",requested)
	stored["grid_rotated"]=bool(fit.get("rotated",false))
	_berserker_items.append(stored)
	_safe_mark_grid(occupied,fit)
	return true


func _build_random_standalone_berserker_loadout()->void:
	if not standalone_berserker or not is_multiplayer_authority():
		return

	_berserker_items.clear()
	_berserker_weapon_indices.clear()
	_berserker_armor_index=-1
	_berserker_active_weapon_slot=0
	_berserker_reload_in_progress=false
	_berserker_using_item_index=-1
	_berserker_use_mode=""
	_berserker_use_fraction=0.0

	var occupied:Array=[false,false,false,false,false,false,false,false,false]

	# 1~2把不重复随机枪。独立猛攻哥没有第一命资格材料，
	# 所以 AWM 也直接进入随机池；抽到后的战斗规则与跑刀鼠第二命完全一致。
	var weapon_pool:Array[String]=["G18","AUG","PSG-1","M7","M250","AWM"]
	var weapon_count:int=_rng.randi_range(1,BERSERKER_MAX_WEAPONS)
	for _i:int in range(weapon_count):
		if weapon_pool.is_empty():
			break
		var pick_index:int=_rng.randi_range(0,weapon_pool.size()-1)
		var weapon_name:String=weapon_pool[pick_index]
		weapon_pool.remove_at(pick_index)
		_append_standalone_berserker_item(
			_berserker_definition_for_weapon(weapon_name),
			occupied
		)

	# 必有一件随机甲；红甲随机到时原生 ball max_block = Max_health。
	var armor_pool:Array[String]=["蓝甲","紫甲","金甲","红甲"]
	var armor_name:String=armor_pool[_rng.randi_range(0,armor_pool.size()-1)]
	_append_standalone_berserker_item(
		_berserker_definition_for_armor(armor_name),
		occupied
	)

	# 随机2~6件耗材，但仍必须能真实排进3x3九格。
	var consumable_names:Array[String]=["60血","350血包","800血包","甲修"]
	var desired_consumables:int=_rng.randi_range(2,6)
	var added_consumables:int=0
	for _attempt:int in range(28):
		if added_consumables>=desired_consumables:
			break
		var item_name:String=consumable_names[
			_rng.randi_range(0,consumable_names.size()-1)
		]
		if _append_standalone_berserker_item(
			_berserker_definition_for_consumable(item_name),
			occupied
		):
			added_consumables+=1

	var snapshot:Dictionary={
		"items":_berserker_items.duplicate(true),
		"remaining_money":0,
		"infinite":false,
	}
	if multiplayer.has_multiplayer_peer():
		_rpc_apply_berserker_loadout.rpc(snapshot)
	else:
		_rpc_apply_berserker_loadout(snapshot)


func _build_berserker_loadout(budget:int)->void:
	_berserker_items.clear()
	_berserker_weapon_indices.clear()
	_berserker_armor_index=-1
	_berserker_active_weapon_slot=0
	_berserker_reload_in_progress=false
	_berserker_using_item_index=-1
	_berserker_use_mode=""
	_berserker_use_fraction=0.0

	# 九格只给血药/甲修；枪和甲完全不占 occupied。
	var occupied:Array=[false,false,false,false,false,false,false,false,false]
	var remaining:int=maxi(budget,0)

	# V358：第一优先“必须尝试买枪”。不为护甲/血药/弹药预留预算。
	# 有多少钱就先买当前条件下能买到的最好枪；连 G18 都买不起才会最终用免费匕首。
	var first_weapon:Dictionary=_berserker_best_affordable_weapon(remaining,occupied)
	if not first_weapon.is_empty():
		var first_result:=_berserker_add_packed_item(first_weapon,occupied,remaining)
		remaining=int(first_result.get("budget",remaining))

	# 枪后再买最好护甲。护甲穿在身上，不占九格。
	var armor:Dictionary=_berserker_best_affordable_armor(remaining,occupied)
	if not armor.is_empty():
		var armor_result:=_berserker_add_packed_item(armor,occupied,remaining)
		remaining=int(armor_result.get("budget",remaining))

	# 最多两把枪；第二把同样不占九格。
	if _berserker_count_kind("weapon")<BERSERKER_MAX_WEAPONS:
		var second_weapon:Dictionary=_berserker_best_affordable_weapon(remaining,occupied)
		if not second_weapon.is_empty():
			var second_result:=_berserker_add_packed_item(second_weapon,occupied,remaining)
			remaining=int(second_result.get("budget",remaining))

	# 九格只装真正的背包消耗品。没有“通用子弹”这一物品。
	# 尽量花完钱，直到九格排不下或剩余钱买不起任何可放入道具。
	var filler_order:PackedStringArray=PackedStringArray(["800血包","甲修","350血包","60血"])
	for _loop:int in range(18):
		var bought:bool=false
		for item_name:String in filler_order:
			if item_name=="甲修" and _berserker_count_kind("armor")<=0:
				continue
			var candidate:=_berserker_definition_for_consumable(item_name)
			if int(candidate.get("price",0))>remaining:
				continue
			var fit:=_safe_find_grid_fit(
				occupied,
				candidate.get("grid",Vector2i.ONE),
				bool(candidate.get("allow_rotate",true))
			)
			if fit.is_empty():
				continue
			var result:=_berserker_add_packed_item(candidate,occupied,remaining)
			if bool(result.get("accepted",false)):
				remaining=int(result.get("budget",remaining))
				bought=true
				break
		if not bought:
			break

	if not has_infinite_money:
		money=maxi(remaining,0)
	_refresh_money_label(true)

	var snapshot:Dictionary={
		"items":_berserker_items.duplicate(true),
		"remaining_money":money,
		"infinite":has_infinite_money,
	}
	if multiplayer.has_multiplayer_peer():
		_rpc_apply_berserker_loadout.rpc(snapshot)
	else:
		_rpc_apply_berserker_loadout(snapshot)


@rpc("authority","call_local","reliable")
func _rpc_apply_berserker_loadout(snapshot:Dictionary)->void:
	_berserker_items.clear()
	var raw_items:Array=snapshot.get("items",[]) as Array
	for raw:Variant in raw_items:
		if raw is Dictionary:
			_berserker_items.append((raw as Dictionary).duplicate(true))
	_reindex_berserker_equipment()
	has_infinite_money=bool(snapshot.get("infinite",has_infinite_money))
	if not has_infinite_money:
		money=int(snapshot.get("remaining_money",money))
	_refresh_money_label(true)
	_apply_berserker_armor_state()
	_refresh_berserker_equipment_visuals()
	_update_active_weapon_attack_cooling()
	_rebuild_berserker_inventory_visual()


func _sync_berserker_runtime_inventory()->void:
	if not is_multiplayer_authority():
		return
	var snapshot:Dictionary={
		"items":_berserker_items.duplicate(true),
		"active_weapon_slot":_berserker_active_weapon_slot,
	}
	if multiplayer.has_multiplayer_peer():
		_rpc_sync_berserker_runtime_inventory.rpc(snapshot)
	else:
		_rpc_sync_berserker_runtime_inventory(snapshot)


@rpc("authority","call_local","reliable")
func _rpc_sync_berserker_runtime_inventory(snapshot:Dictionary)->void:
	_berserker_items.clear()
	var raw_items:Array=snapshot.get("items",[]) as Array
	for raw:Variant in raw_items:
		if raw is Dictionary:
			_berserker_items.append((raw as Dictionary).duplicate(true))
	_reindex_berserker_equipment()
	_berserker_active_weapon_slot=clampi(
		int(snapshot.get("active_weapon_slot",_berserker_active_weapon_slot)),
		0,
		maxi(_berserker_weapon_indices.size()-1,0)
	)
	_refresh_berserker_equipment_visuals()
	_update_active_weapon_attack_cooling()
	_rebuild_berserker_inventory_visual()


func _reindex_berserker_equipment()->void:
	_berserker_weapon_indices.clear()
	_berserker_armor_index=-1
	for i:int in range(_berserker_items.size()):
		var item:Dictionary=_berserker_items[i]
		if bool(item.get("consumed",false)):
			continue
		match str(item.get("kind","")):
			"weapon":
				if _berserker_weapon_indices.size()<BERSERKER_MAX_WEAPONS:
					_berserker_weapon_indices.append(i)
			"armor":
				if _berserker_armor_index<0:
					_berserker_armor_index=i


func _current_berserker_weapon_item_index()->int:
	if _berserker_weapon_indices.is_empty():
		return -1
	_berserker_active_weapon_slot=clampi(
		_berserker_active_weapon_slot,
		0,
		_berserker_weapon_indices.size()-1
	)
	return _berserker_weapon_indices[_berserker_active_weapon_slot]


func _back_berserker_weapon_item_index()->int:
	if _berserker_weapon_indices.size()<2:
		return -1
	var active_index:int=_current_berserker_weapon_item_index()
	for item_index:int in _berserker_weapon_indices:
		if item_index!=active_index:
			return item_index
	return -1


func _berserker_gun_target_long(weapon:Dictionary,back_slot:bool=false)->float:
	var target_long:float=150.0
	var weapon_name:String=str(weapon.get("name",""))
	if weapon_name in ["AWM","M250"]:
		target_long=172.0
	elif weapon_name=="G18":
		target_long=112.0

	# 背枪略小一点，避免遮住整个角色，但仍保持清晰可见。
	if back_slot:
		target_long*=0.82
	return target_long


func _update_active_weapon_attack_cooling()->void:
	# Attack_Cooling 只保留为Inspector/其它系统可读的“当前理论射击间隔”。
	# 第二命真实开火不再读取公共 last_state_dis.Attack。
	var item_index:int=_current_berserker_weapon_item_index()
	if item_index<0:
		Attack_Cooling=BERSERKER_DAGGER_COOLDOWN
		Can_Attack=false
		return
	var weapon:Dictionary=_berserker_items[item_index]
	var rpm:float=maxf(float(weapon.get("rpm",300.0)),1.0)
	Attack_Cooling=maxf(60.0/rpm,0.001)
	Can_Attack=false


func _berserker_attack_direction()->Vector2:
	if has_player_control_aim():
		return player_control_aim_direction(direction)
	var enemy:Node=return_reusable_combat_target()
	if (
		enemy!=null
		and is_instance_valid(enemy)
		and _berserker_target_is_in_front_180(enemy)
	):
		return combat_target_position(enemy)-global_position
	return Vector2.ZERO


func _berserker_weapon_attack_direction(weapon:Dictionary)->Vector2:
	# 玩家直接控制时尊重鼠标，不替玩家自动改瞄准。
	if has_player_control_aim():
		return player_control_aim_direction(direction)

	var enemy:Node=return_reusable_combat_target()
	if (
		enemy==null
		or not is_instance_valid(enemy)
		or not _berserker_target_is_in_front_180(enemy)
	):
		return Vector2.ZERO

	if bool(weapon.get("predictive",false)) and enemy is ball:
		var predicted:Vector2=_berserker_predict_intercept_point(
			enemy as ball,
			maxf(float(weapon.get("projectile_speed",500.0)),1.0)
		)
		return predicted-global_position
	return combat_target_position(enemy)-global_position


func _berserker_weapon_aim_turn_speed_rad(weapon:Dictionary)->float:
	return deg_to_rad(maxf(float(weapon.get("aim_turn_deg",520.0)),1.0))


func _update_berserker_character_facing_from_motion()->void:
	# 公共 ball.move() 也是按这个有效移动方向决定人物左右镜像。
	# 所以这里直接记录移动方向本身，避免再从 Shader flip 反推并出现左右语义颠倒。
	var move_dir:Vector2=(
		player_control_direction
		if is_player_controlled()
		else direction
	)
	if absf(move_dir.x)>0.001:
		_berserker_character_facing_sign=1.0 if move_dir.x>0.0 else -1.0


func _berserker_fallback_facing_direction()->Vector2:
	return (
		Vector2.RIGHT
		if _berserker_character_facing_sign>0.0
		else Vector2.LEFT
	)


func _berserker_direction_is_in_front_180(direction_to_target:Vector2)->bool:
	# 人物前方180° = 面朝向左右各90°的半平面。
	# 两个归一化方向点积 >= 0，代表夹角 <= 90°。
	if direction_to_target.length_squared()<=0.000001:
		return false
	var facing:Vector2=_berserker_fallback_facing_direction().normalized()
	return facing.dot(direction_to_target.normalized())>=0.0


func _berserker_target_is_in_front_180(target:Node)->bool:
	if target==null or not is_instance_valid(target):
		return false
	var target_direction:Vector2=combat_target_position(target)-global_position
	return _berserker_direction_is_in_front_180(target_direction)


func _tick_berserker_gun_aim(delta:float)->void:
	if life_index!=2:
		return
	var item_index:int=_current_berserker_weapon_item_index()
	if item_index<0 or item_index>=_berserker_items.size():
		_berserker_gun_aim_initialized=false
		return
	var weapon:Dictionary=_berserker_items[item_index]

	var desired:Vector2=_berserker_weapon_attack_direction(weapon)
	if desired.length_squared()<=0.000001:
		# V372：没有敌人/没有鼠标瞄准时，枪的默认朝向就是人物朝向。
		# 不保留上一名敌人的旧枪口角度。
		desired=_berserker_fallback_facing_direction()
		_berserker_gun_aim_angle=desired.angle()
		_berserker_gun_aim_initialized=true
		return
	desired=desired.normalized()
	var desired_angle:float=desired.angle()

	if not _berserker_gun_aim_initialized:
		var facing:Vector2=_berserker_fallback_facing_direction()
		_berserker_gun_aim_angle=facing.angle()
		_berserker_gun_aim_initialized=true

	var angle_delta:float=wrapf(
		desired_angle-_berserker_gun_aim_angle,
		-PI,
		PI
	)
	var max_step:float=_berserker_weapon_aim_turn_speed_rad(weapon)*maxf(delta,0.0)
	_berserker_gun_aim_angle+=clampf(angle_delta,-max_step,max_step)
	_berserker_gun_aim_angle=wrapf(_berserker_gun_aim_angle,-PI,PI)


func _berserker_current_gun_direction()->Vector2:
	if not _berserker_gun_aim_initialized:
		return _berserker_fallback_facing_direction()
	return Vector2(cos(_berserker_gun_aim_angle),sin(_berserker_gun_aim_angle)).normalized()


func _berserker_ease_out_cubic(t:float)->float:
	var x:float=clampf(t,0.0,1.0)
	return 1.0-pow(1.0-x,3.0)


func _begin_berserker_weapon_switch_animation(from_slot:int,to_slot:int)->void:
	if from_slot==to_slot:
		return
	_berserker_switch_from_slot=from_slot
	_berserker_switch_to_slot=to_slot
	_berserker_switch_animation_elapsed=0.0
	_berserker_switch_animation_active=true
	_berserker_fire_cooldown_remaining=maxf(
		_berserker_fire_cooldown_remaining,
		BERSERKER_WEAPON_SWITCH_DURATION
	)


func _tick_berserker_switch_animation(delta:float)->void:
	if not _berserker_switch_animation_active:
		return
	_berserker_switch_animation_elapsed+=maxf(delta,0.0)
	if _berserker_switch_animation_elapsed>=BERSERKER_WEAPON_SWITCH_DURATION:
		_berserker_switch_animation_elapsed=BERSERKER_WEAPON_SWITCH_DURATION
		_berserker_switch_animation_active=false


func _berserker_switch_eased_progress()->float:
	if not _berserker_switch_animation_active:
		return 1.0
	var t:float=_berserker_switch_animation_elapsed/maxf(
		BERSERKER_WEAPON_SWITCH_DURATION,
		0.001
	)
	return _berserker_ease_out_cubic(t)


func _berserker_predict_intercept_point(target:ball,shot_speed:float)->Vector2:
	# 直接复用军火商狙击枪同一类二次方程拦截模型：
	# |relative + target_velocity*t| = projectile_speed*t
	if target==null or not is_instance_valid(target):
		return global_position
	var target_position:Vector2=combat_target_position(target)
	var relative:Vector2=target_position-global_position
	if relative.length_squared()<=0.000001:
		return target_position

	var target_velocity:Vector2=combat_target_velocity(target)
	var s:float=maxf(shot_speed,1.0)
	var a:float=target_velocity.dot(target_velocity)-s*s
	var b:float=2.0*relative.dot(target_velocity)
	var c:float=relative.dot(relative)
	var t:float=-1.0

	if absf(a)<0.00001:
		if absf(b)>0.00001:
			t=-c/b
	else:
		var disc:float=b*b-4.0*a*c
		if disc>=0.0:
			var root:float=sqrt(disc)
			var t1:float=(-b-root)/(2.0*a)
			var t2:float=(-b+root)/(2.0*a)
			if t1>0.0 and t2>0.0:
				t=minf(t1,t2)
			elif t1>0.0:
				t=t1
			elif t2>0.0:
				t=t2

	if t<=0.0:
		t=relative.length()/s
	t=clampf(t,0.0,1.15)
	return target_position+target_velocity*t


func _reset_berserker_m250_session(cancel_windup:bool=true)->void:
	_berserker_m250_session_active=false
	_berserker_m250_last_fire_msec=-100000
	if cancel_windup:
		_berserker_m250_windup_active=false
		Attacking=false


func _tick_berserker_m250_session(state:State)->void:
	if not _berserker_m250_session_active and not _berserker_m250_windup_active:
		return

	# 明确的中断：换弹、用道具、眩晕/受击硬直、禁攻、死亡或切离 M250。
	if (
		life_index!=2
		or health<=0
		or dizziness
		or state==State.Hurt
		or _berserker_reload_in_progress
		or _berserker_using_item_index>=0
		or is_damage_output_disabled()
	):
		_reset_berserker_m250_session(true)
		return

	var active_index:int=_current_berserker_weapon_item_index()
	if active_index<0 or active_index>=_berserker_items.size():
		_reset_berserker_m250_session(true)
		return
	var active_weapon:Dictionary=_berserker_items[active_index]
	if str(active_weapon.get("name",""))!="M250":
		_reset_berserker_m250_session(true)
		return

	# 真正“停止射击”：最后一发之后超过 burst_reset 都没有下一发，
	# 才结束本次连续射击会话。正常900RPM连射约66ms/发，远低于0.28s。
	if _berserker_m250_session_active:
		var reset_sec:float=maxf(
			float(active_weapon.get("burst_reset",BERSERKER_M250_BURST_RESET_DEFAULT)),
			0.10
		)
		if Time.get_ticks_msec()-_berserker_m250_last_fire_msec >= int(round(reset_sec*1000.0)):
			_reset_berserker_m250_session(false)


func _run_berserker_m250_first_shot(item_index:int)->void:
	if item_index<0 or item_index>=_berserker_items.size():
		_berserker_m250_windup_active=false
		Attacking=false
		return
	var weapon:Dictionary=_berserker_items[item_index]
	var delay:float=maxf(
		float(weapon.get("first_shot_windup",BERSERKER_M250_WINDUP_DEFAULT)),
		0.0
	)
	if delay>0.0:
		await get_tree().create_timer(delay).timeout

	# 如果前腰期间发生眩晕/换弹/切枪等，中断函数会把 windup_active 清掉，
	# 这条协程必须立刻作废，不能醒来以后继续补射。
	if not _berserker_m250_windup_active:
		Attacking=false
		return

	if (
		not is_instance_valid(self)
		or health<=0
		or life_index!=2
		or state_machine==null
		or state_machine.current_state==State.Die
		or dizziness
		or state_machine.current_state==State.Hurt
		or _berserker_reload_in_progress
		or _berserker_using_item_index>=0
		or is_damage_output_disabled()
	):
		_reset_berserker_m250_session(true)
		return

	weapon=_berserker_items[item_index]
	if str(weapon.get("name",""))!="M250":
		_reset_berserker_m250_session(true)
		return

	# 前腰结束后仍需确认目标存在；真正子弹只沿当前枪管方向射出。
	var desired:Vector2=_berserker_weapon_attack_direction(weapon)
	var aim:Vector2=_berserker_current_gun_direction()
	if desired.length_squared()>0.000001 and aim.length_squared()>0.000001 and int(weapon.get("mag_current",0))>0:
		_fire_berserker_weapon(item_index,aim.normalized())
		_arm_berserker_fire_interval(weapon)
		_berserker_m250_session_active=true
		_berserker_m250_last_fire_msec=Time.get_ticks_msec()

	_berserker_m250_windup_active=false
	Attacking=false



func _start_berserker_dagger_attack(aim:Vector2)->void:
	if _berserker_dagger_attack_active:
		Attacking=false
		return
	_berserker_dagger_attack_active=true
	call_deferred("_run_berserker_dagger_attack",aim)


func _run_berserker_dagger_attack(aim:Vector2)->void:
	var dir:Vector2=aim.normalized()
	if dir.length_squared()<=0.000001:
		dir=Vector2.RIGHT

	var weapon:Area2D=_create_berserker_dagger_area()
	if weapon==null:
		_berserker_dagger_attack_active=false
		Attacking=false
		return
	var world:Node=get_tree().current_scene
	if world==null:
		weapon.queue_free()
		_berserker_dagger_attack_active=false
		Attacking=false
		return

	world.add_child(weapon)
	var hit_ids:Dictionary={}
	var steps:int=10
	for i:int in range(steps):
		if not is_instance_valid(self) or health<=0 or life_index!=2:
			break
		var t:float=float(i)/float(maxi(steps-1,1))
		# 从后侧 -55° 挥到前侧 +55°，同时略微向前伸。
		var swing_angle:float=lerpf(-0.96,0.96,t)
		var blade_dir:Vector2=dir.rotated(swing_angle)
		weapon.global_rotation=blade_dir.angle()
		weapon.global_position=global_position+blade_dir*(17.0+sin(t*PI)*8.0)
		await get_tree().physics_frame
		_damage_berserker_dagger_overlaps(weapon,hit_ids,blade_dir)

	if weapon!=null and is_instance_valid(weapon):
		weapon.queue_free()
	_berserker_dagger_attack_active=false
	Attacking=false


func _create_berserker_dagger_area()->Area2D:
	var tex:=load(BERSERKER_DAGGER_TEXTURE_PATH) as Texture2D
	if tex==null:
		return null
	var geometry:Dictionary=_berserker_dagger_geometry(tex)
	if geometry.is_empty():
		return null

	var area:=Area2D.new()
	area.name="BerserkerDaggerAttack"
	area.collision_layer=0
	area.collision_mask=0xFFFFFFFF
	area.monitoring=true
	area.monitorable=false
	area.z_index=30

	var sprite:=Sprite2D.new()
	sprite.texture=tex
	sprite.centered=true
	sprite.position=geometry.get("sprite_position",Vector2.ZERO)
	sprite.scale=Vector2.ONE*float(geometry.get("sprite_scale",1.0))
	sprite.z_index=1
	area.add_child(sprite)

	var polygons:Array=geometry.get("polygons",[])
	for raw:Variant in polygons:
		if not (raw is PackedVector2Array):
			continue
		var polygon:PackedVector2Array=raw
		if polygon.size()<3:
			continue
		var collision:=CollisionPolygon2D.new()
		collision.polygon=polygon
		area.add_child(collision)
	return area


func _berserker_dagger_geometry(tex:Texture2D)->Dictionary:
	var key:String=tex.resource_path
	if _berserker_dagger_geometry_cache.has(key):
		return _berserker_dagger_geometry_cache[key]

	var image_data:Image=tex.get_image()
	if image_data==null or image_data.is_empty():
		return {}
	var bitmap:=BitMap.new()
	bitmap.create_from_image_alpha(image_data,0.08)
	var source:Array[PackedVector2Array]=bitmap.opaque_to_polygons(
		Rect2i(Vector2i.ZERO,image_data.get_size()),
		3.0
	)
	if source.is_empty():
		return {}

	var image_center:=Vector2(image_data.get_width()*0.5,image_data.get_height()*0.5)
	var min_x:float=INF
	var max_x:float=-INF
	var min_y:float=INF
	var max_y:float=-INF
	for poly:PackedVector2Array in source:
		for p:Vector2 in poly:
			var local:Vector2=p-image_center
			min_x=minf(min_x,local.x)
			max_x=maxf(max_x,local.x)
			min_y=minf(min_y,local.y)
			max_y=maxf(max_y,local.y)

	var raw_length:float=maxf(max_x-min_x,1.0)
	var scale_value:float=36.0/raw_length
	var shift:=Vector2(-min_x*scale_value,-(min_y+max_y)*0.5*scale_value)

	var final:Array[PackedVector2Array]=[]
	for poly:PackedVector2Array in source:
		var transformed:=PackedVector2Array()
		transformed.resize(poly.size())
		for i:int in range(poly.size()):
			transformed[i]=(poly[i]-image_center)*scale_value+shift
		final.append(transformed)

	var result:Dictionary={
		"polygons":final,
		"sprite_position":shift,
		"sprite_scale":scale_value,
	}
	_berserker_dagger_geometry_cache[key]=result
	return result


func _damage_berserker_dagger_overlaps(weapon:Area2D,hit_ids:Dictionary,attack_dir:Vector2)->void:
	if weapon==null or not is_instance_valid(weapon):
		return
	for area:Area2D in weapon.get_overlapping_areas():
		_try_damage_berserker_dagger_target(_berserker_collision_owner_ball(area),hit_ids,attack_dir)
	for body:Node2D in weapon.get_overlapping_bodies():
		_try_damage_berserker_dagger_target(_berserker_collision_owner_ball(body),hit_ids,attack_dir)


func _berserker_collision_owner_ball(node:Node)->ball:
	var current:Node=node
	for _i:int in range(8):
		if current==null:
			break
		if current is ball:
			return current as ball
		current=current.get_parent()
	return null


func _try_damage_berserker_dagger_target(target:ball,hit_ids:Dictionary,attack_dir:Vector2)->void:
	if target==null or not is_instance_valid(target) or target==self or target.health<=0:
		return
	if not target.is_combat_targetable():
		return
	if Team!="" and target.Team==Team:
		return
	var id:int=target.get_instance_id()
	if hit_ids.has(id):
		return
	hit_ids[id]=true

	var damage_value:float=attack_damage(BERSERKER_DAGGER_DAMAGE/maxf(float(Damage),1.0))
	var dealt:bool=target.receive_positional_damage(
		damage_value,
		target.global_position,
		false,
		self
	)
	if dealt:
		var push:Vector2=attack_dir.normalized()
		target.apply_knockback(
			push,
			BERSERKER_DAGGER_KNOCKBACK_DISTANCE,
			BERSERKER_DAGGER_KNOCKBACK_SPEED,
			0.0,
			0.0,
			{"source":self,"lock_control":true,"stop_on_character":true}
		)


func _berserker_gun_muzzle_global_position(shot_dir:Vector2)->Vector2:
	# V394：官方推荐的 2D 枪械做法也是从枪口 Marker 的 global_position 发射。
	# 本项目枪械 Sprite 是运行时动态创建/换图，所以这里不为六把枪硬编码六套 Marker；
	# 而是从当前 Sprite2D 的真实可见像素边界自动找出枪口，再转换到世界坐标。
	if not is_instance_valid(_berserker_gun_sprite) or not _berserker_gun_sprite.visible:
		return global_position+shot_dir*12.0
	var sprite:=_berserker_gun_sprite
	if sprite.texture==null:
		return global_position+shot_dir*12.0

	var texture_key:String=sprite.texture.resource_path
	if texture_key.is_empty():
		texture_key=str(sprite.texture.get_instance_id())

	var muzzle_local:Vector2
	if _berserker_muzzle_local_cache.has(texture_key):
		muzzle_local=_berserker_muzzle_local_cache[texture_key]
	else:
		var rect:Rect2=sprite.get_rect()
		var found:bool=false
		var best_x:float=rect.position.x
		var best_y:float=rect.get_center().y
		var x_start:int=int(floor(rect.position.x))
		var x_end:int=int(ceil(rect.end.x))
		var y_start:int=int(floor(rect.position.y))
		var y_end:int=int(ceil(rect.end.y))

		# 枪械正式图默认朝左：从最左列向右找第一组可见像素。
		# 至少要求同一列有 2 个不透明采样点，过滤抗锯齿边缘偶发的孤立像素。
		for xi in range(x_start,x_end+1):
			var y_sum:float=0.0
			var opaque_count:int=0
			for yi in range(y_start,y_end+1):
				var sample:=Vector2(float(xi)+0.5,float(yi)+0.5)
				if sprite.is_pixel_opaque(sample):
					y_sum+=sample.y
					opaque_count+=1
			if opaque_count>=2:
				best_x=float(xi)+0.5
				best_y=y_sum/float(opaque_count)
				found=true
				break

		if not found:
			best_x=rect.position.x
			best_y=rect.get_center().y
		muzzle_local=Vector2(best_x-BERSERKER_MUZZLE_OUTSET_LOCAL,best_y)
		_berserker_muzzle_local_cache[texture_key]=muzzle_local

	# Sprite2D 的 flip_h/flip_v 是绘制翻转，不会体现在 Node2D transform 中；
	# 因此在 to_global() 前手工镜像枪口局部坐标。
	var rendered_local:Vector2=muzzle_local
	if sprite.flip_h:
		rendered_local.x=2.0*sprite.offset.x-rendered_local.x
	if sprite.flip_v:
		rendered_local.y=2.0*sprite.offset.y-rendered_local.y

	return sprite.to_global(rendered_local)


func _fire_berserker_weapon(item_index:int,aim:Vector2)->void:
	if item_index<0 or item_index>=_berserker_items.size():
		return
	var weapon:Dictionary=_berserker_items[item_index]
	var mag_current:int=int(weapon.get("mag_current",0))
	if mag_current<=0:
		return

	var spread:float=deg_to_rad(maxf(float(weapon.get("spread_deg",0.0)),0.0))
	var shot_dir:Vector2=aim.rotated(_rng.randf_range(-spread,spread)).normalized()
	var projectile:=BERSERKER_BULLET_SCENE.instantiate() as ball
	if projectile==null:
		return
	projectile.set_collision_layer_value(2,false)
	projectile.Master=self
	projectile.Master_name=self.name
	projectile.Team=Team
	projectile.Speed=maxf(float(weapon.get("projectile_speed",500.0)),80.0)

	# 武器 damage 是本项目该枪基准伤害；继续经过角色 attack_damage()，
	# 让公共增伤/减伤 Buff 仍然有效，而不直接改跑刀仔自身 Damage。
	var base_character_damage:float=maxf(float(Damage),1.0)
	var weapon_damage:float=maxf(float(weapon.get("damage",Damage)),0.0)
	projectile.Damage=maxi(int(round(attack_damage(weapon_damage/base_character_damage))),0)

	# AWM：仍然是夺舍狼同一个“子弹.tscn”，只是给该颗子弹附加绝对生命伤害标记。
	# 子弹脚本收到这个标记后不走 block / Damage_reduction / receive_* 免疫入口。
	if bool(weapon.get("raw_health",false)):
		projectile.set_meta(&"berserker_raw_health_damage",true)
		projectile.set_meta(
			&"berserker_raw_knockback_distance",
			maxf(float(weapon.get("knockback_distance",0.0)),0.0)
		)
		projectile.set_meta(
			&"berserker_raw_knockback_speed",
			maxf(float(weapon.get("knockback_speed",0.0)),0.0)
		)

	# V394：先刷新这一帧枪械姿态，再从当前枪口真实世界坐标生成子弹。
	_update_berserker_equipment_visual_transform()
	projectile.global_position=_berserker_gun_muzzle_global_position(shot_dir)
	projectile.global_rotation=projectile.Default_Rotation+shot_dir.angle()
	projectile.direction=shot_dir
	projectile.name=Game.return_random_name(projectile)
	get_tree().current_scene.add_child(projectile,true)

	weapon["mag_current"]=mag_current-1
	_berserker_items[item_index]=weapon
	if str(weapon.get("name",""))=="M250":
		_berserker_m250_session_active=true
		_berserker_m250_last_fire_msec=Time.get_ticks_msec()

	# V364：
	# G18/AUG/M7/M250 -> 连续射击录音只在射击段开始时启动，持续循环；
	# PSG-1/AWM -> 每真正生成一颗子弹播放一次完整单发音效。
	_trigger_berserker_weapon_audio(weapon)

	if int(weapon.get("mag_current",0))<=0:
		_handle_empty_berserker_weapon()
	else:
		_sync_berserker_runtime_inventory()



func _berserker_gun_audio_bus()->StringName:
	if AudioServer.get_bus_index(&"GameplayRecord")>=0:
		return &"GameplayRecord"
	return &"Master"


func _berserker_gun_audio_source(weapon_name:String)->AudioStream:
	match weapon_name:
		"G18":
			return BERSERKER_G18_AUDIO
		"AUG":
			return BERSERKER_AUG_AUDIO
		"PSG-1":
			return BERSERKER_PSG_AUDIO
		"M7":
			return BERSERKER_M7_AUDIO
		"M250":
			return BERSERKER_M250_AUDIO
		"AWM":
			return BERSERKER_AWM_AUDIO
	return null


func _load_berserker_gun_audio_stream(weapon_name:String,looped:bool)->AudioStream:
	var source:AudioStream=_berserker_gun_audio_source(weapon_name)
	if source==null:
		return null
	var stream:=source.duplicate(true) as AudioStream
	var mp3:=stream as AudioStreamMP3
	if mp3!=null:
		mp3.loop=looped
		mp3.loop_offset=0.0
	return stream


func _ensure_berserker_loop_gun_audio_player()->AudioStreamPlayer:
	if is_instance_valid(_berserker_loop_gun_audio_player):
		return _berserker_loop_gun_audio_player
	var player:=AudioStreamPlayer.new()
	player.name="猛攻哥连续枪声"
	player.bus=_berserker_gun_audio_bus()
	player.volume_db=2.0
	player.max_polyphony=1
	player.process_mode=Node.PROCESS_MODE_ALWAYS
	add_child(player)
	_berserker_loop_gun_audio_player=player
	return player


func _trigger_berserker_weapon_audio(weapon:Dictionary)->void:
	if not is_multiplayer_authority():
		return
	var weapon_name:String=str(weapon.get("name",""))
	if weapon_name.is_empty() or _berserker_gun_audio_source(weapon_name)==null:
		return

	if bool(BERSERKER_LOOP_GUN_AUDIO.get(weapon_name,false)):
		_berserker_loop_gun_last_shot_msec=Time.get_ticks_msec()

		# 已经是同一把枪的循环录音时，每颗子弹只刷新“仍在射击”的时间，
		# 绝对不能重新从头播放。
		if (
			_berserker_loop_gun_audio_weapon!=weapon_name
			or not is_instance_valid(_berserker_loop_gun_audio_player)
			or not _berserker_loop_gun_audio_player.playing
		):
			_request_start_berserker_loop_gun_audio(weapon_name)
		return

	# PSG/AWM 是严格单发录音；每真正生成一颗子弹就播一次。
	_request_stop_berserker_loop_gun_audio()
	if multiplayer.has_multiplayer_peer():
		_rpc_play_berserker_one_shot_gun_audio.rpc(weapon_name,global_position)
	else:
		_rpc_play_berserker_one_shot_gun_audio(weapon_name,global_position)


func _request_start_berserker_loop_gun_audio(weapon_name:String)->void:
	if multiplayer.has_multiplayer_peer():
		_rpc_start_berserker_loop_gun_audio.rpc(weapon_name)
	else:
		_rpc_start_berserker_loop_gun_audio(weapon_name)


func _request_stop_berserker_loop_gun_audio()->void:
	if (
		_berserker_loop_gun_audio_weapon.is_empty()
		and (
			not is_instance_valid(_berserker_loop_gun_audio_player)
			or not _berserker_loop_gun_audio_player.playing
		)
	):
		return
	if multiplayer.has_multiplayer_peer():
		_rpc_stop_berserker_loop_gun_audio.rpc()
	else:
		_rpc_stop_berserker_loop_gun_audio()


@rpc("authority","call_local","reliable")
func _rpc_start_berserker_loop_gun_audio(weapon_name:String)->void:
	if not bool(BERSERKER_LOOP_GUN_AUDIO.get(weapon_name,false)):
		return
	var stream:AudioStream=_load_berserker_gun_audio_stream(weapon_name,true)
	if stream==null:
		return
	var player:AudioStreamPlayer=_ensure_berserker_loop_gun_audio_player()
	if player==null:
		return

	if player.playing:
		player.stop()
	player.stream=stream
	_berserker_loop_gun_audio_weapon=weapon_name
	player.play()


@rpc("authority","call_local","reliable")
func _rpc_stop_berserker_loop_gun_audio()->void:
	_stop_berserker_loop_gun_audio_local()


func _stop_berserker_loop_gun_audio_local()->void:
	if is_instance_valid(_berserker_loop_gun_audio_player):
		_berserker_loop_gun_audio_player.stop()
		_berserker_loop_gun_audio_player.stream=null
	_berserker_loop_gun_audio_weapon=""


@rpc("authority","call_local","unreliable")
func _rpc_play_berserker_one_shot_gun_audio(
	weapon_name:String,
	world_position:Vector2
)->void:
	var stream:AudioStream=_load_berserker_gun_audio_stream(weapon_name,false)
	if stream==null:
		return
	var world:Node=get_tree().current_scene
	if world==null:
		return

	# PSG/AWM每发独立播放器，允许PSG尾音重叠。
	# V365改为非定位AudioStreamPlayer，避免2D listener/衰减配置让正式枪声听不见。
	var player:=AudioStreamPlayer.new()
	player.name="猛攻哥_%s_单发枪声" % weapon_name
	player.stream=stream
	player.bus=_berserker_gun_audio_bus()
	player.volume_db=5.0 if weapon_name=="PSG-1" else 3.0
	player.process_mode=Node.PROCESS_MODE_ALWAYS
	world.add_child(player)
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _tick_berserker_gun_audio(state:State)->void:
	if _berserker_loop_gun_audio_weapon.is_empty():
		return

	# 这些情况属于明确“停止射击”，循环声立即停，不等待尾部超时。
	if (
		life_index!=2
		or health<=0
		or dizziness
		or state==State.Hurt
		or _berserker_reload_in_progress
		or _berserker_using_item_index>=0
		or is_damage_output_disabled()
	):
		_request_stop_berserker_loop_gun_audio()
		return

	var item_index:int=_current_berserker_weapon_item_index()
	if item_index<0 or item_index>=_berserker_items.size():
		_request_stop_berserker_loop_gun_audio()
		return
	var weapon:Dictionary=_berserker_items[item_index]
	var weapon_name:String=str(weapon.get("name",""))
	if (
		weapon_name!=_berserker_loop_gun_audio_weapon
		or not bool(BERSERKER_LOOP_GUN_AUDIO.get(weapon_name,false))
	):
		_request_stop_berserker_loop_gun_audio()
		return

	# 连射过程中不会按每一颗子弹重新播音频，只刷新last_shot。
	# 超过约3个正常射击间隔仍没有新子弹，才视为真正停止射击。
	var rpm:float=maxf(float(weapon.get("rpm",600.0)),1.0)
	var shot_interval:float=60.0/rpm
	var release_sec:float=clampf(shot_interval*3.4,0.12,0.24)
	if Time.get_ticks_msec()-_berserker_loop_gun_last_shot_msec >= int(round(release_sec*1000.0)):
		_request_stop_berserker_loop_gun_audio()


func _handle_empty_berserker_weapon()->void:
	if _berserker_weapon_indices.is_empty():
		return
	var current_slot:int=clampi(_berserker_active_weapon_slot,0,_berserker_weapon_indices.size()-1)

	if _berserker_weapon_indices.size()>=2:
		var other_slot:int=(current_slot+1)%_berserker_weapon_indices.size()
		var other_index:int=_berserker_weapon_indices[other_slot]
		var other:Dictionary=_berserker_items[other_index]

		# 第一把打空 -> 切已经有弹的第二把；
		# 第二把也打空 -> 回到第一把并开始换弹。
		#
		# V372关键修复：这里绝对不能提前写 `_berserker_active_weapon_slot=other_slot`。
		# V366~V371提前写了以后，RPC读取到的old_slot已经等于new_slot，
		# `_begin_berserker_weapon_switch_animation()` 的 old!=new 条件永远不成立，
		# 所以用户看到的是“完全没有切枪动画”。
		_call_berserker_weapon_switch(other_slot)
		if int(other.get("mag_current",0))>0:
			_update_active_weapon_attack_cooling()
			_sync_berserker_runtime_inventory()
			return
		_start_berserker_reload(other_index)
		return

	_start_berserker_reload(_berserker_weapon_indices[0])


func _call_berserker_weapon_switch(slot:int)->void:
	_request_stop_berserker_loop_gun_audio()
	_reset_berserker_m250_session(true)
	_berserker_fire_cooldown_remaining=0.0
	if multiplayer.has_multiplayer_peer():
		_rpc_set_berserker_active_weapon.rpc(slot)
	else:
		_rpc_set_berserker_active_weapon(slot)


@rpc("authority","call_local","reliable")
func _rpc_set_berserker_active_weapon(slot:int)->void:
	if _berserker_weapon_indices.is_empty():
		_berserker_active_weapon_slot=0
		return
	var old_slot:int=clampi(
		_berserker_active_weapon_slot,
		0,
		_berserker_weapon_indices.size()-1
	)
	var new_slot:int=clampi(slot,0,_berserker_weapon_indices.size()-1)
	_berserker_active_weapon_slot=new_slot
	_refresh_berserker_equipment_visuals()

	if old_slot!=new_slot:
		_begin_berserker_weapon_switch_animation(old_slot,new_slot)

	_update_active_weapon_attack_cooling()
	_update_berserker_equipment_visual_transform()


func _start_berserker_reload(item_index:int)->void:
	if _berserker_reload_in_progress or item_index<0 or item_index>=_berserker_items.size():
		return
	_request_stop_berserker_loop_gun_audio()
	_reset_berserker_m250_session(true)
	var weapon:Dictionary=_berserker_items[item_index]
	if int(weapon.get("mag_current",0))>=int(weapon.get("mag",0)):
		return
	_berserker_reload_in_progress=true
	# 枪不属于九格背包，所以换弹时不显示枪占用格子。
	call_deferred("_finish_berserker_reload",item_index)


func _finish_berserker_reload(item_index:int)->void:
	if item_index<0 or item_index>=_berserker_items.size():
		_berserker_reload_in_progress=false
		return
	var weapon:Dictionary=_berserker_items[item_index]
	var duration:float=maxf(float(weapon.get("reload",1.8)),0.1)
	await get_tree().create_timer(duration).timeout
	if not is_instance_valid(self) or health<=0 or life_index!=2:
		return

	# V358：没有“子弹/备弹”背包物品。每把枪保留自己的弹匣与换弹动作，
	# 换弹结束后直接补满本枪弹匣。
	weapon["mag_current"]=maxi(int(weapon.get("mag",0)),0)
	_berserker_items[item_index]=weapon
	_berserker_reload_in_progress=false
	_sync_berserker_runtime_inventory()
	_update_active_weapon_attack_cooling()


func _set_berserker_native_ball_shield(new_max:int,refill:bool)->void:
	# V369 根因：
	# World.set_ball_properties_to_dafault() 每个 physics tick 都会从
	# ball.default_properties 恢复 max_block。旧版只改运行时 max_block，
	# 因此下一帧又被跑刀仔初始 default max_block=0 洗掉。
	#
	# 这里不创造任何第二套护甲生命值，直接维护 ball 原生的：
	# default_properties["max_block"] / max_block / block。
	var resolved_max:int=maxi(new_max,0)
	var previous_max:int=max_block
	var previous_block:int=int(block)

	default_properties["max_block"]=resolved_max
	max_block=resolved_max

	var target_block:int=resolved_max if refill else clampi(int(block),0,resolved_max)
	if target_block!=int(block):
		block=target_block
	elif health_bar!=null and previous_max!=resolved_max:
		# block没变但上限变了（例如红甲随Max_health变化）时刷新原生护盾条分母。
		health_bar.block_changed.emit(
			previous_block,
			target_block,
			resolved_max,
			false
		)


func _apply_berserker_armor_state()->void:
	if _berserker_armor_index<0 or _berserker_armor_index>=_berserker_items.size():
		_set_berserker_native_ball_shield(0,true)
		return

	var armor:Dictionary=_berserker_items[_berserker_armor_index]
	var shield:int=int(armor.get("shield",0))
	if str(armor.get("shield_mode",""))=="health":
		shield=maxi(Max_health,0)

	# 穿甲时直接充满 ball 自带护盾。
	_set_berserker_native_ball_shield(shield,true)


func _sync_red_armor_to_health()->void:
	if _berserker_armor_index<0 or _berserker_armor_index>=_berserker_items.size():
		return
	var armor:Dictionary=_berserker_items[_berserker_armor_index]
	if str(armor.get("shield_mode",""))!="health":
		return
	var next_max:int=maxi(Max_health,0)
	if max_block==next_max and int(default_properties.get("max_block",0))==next_max:
		return

	# 红甲同步上限，但不会因为生命上限改变免费回满已经损失的block。
	_set_berserker_native_ball_shield(next_max,false)


func _find_berserker_heal_item()->int:
	var missing:float=maxf(float(Max_health-health),0.0)
	if missing<=0.0:
		return -1
	var best_index:int=-1
	var best_capacity:float=INF
	for i:int in range(_berserker_items.size()):
		var item:Dictionary=_berserker_items[i]
		if bool(item.get("consumed",false)) or str(item.get("kind",""))!="heal":
			continue
		var remaining:float=maxf(float(item.get("remaining",0.0)),0.0)
		if remaining<=0.0:
			continue
		# 优先使用“能覆盖当前缺血量的最小血药”；否则用剩余容量最大的那个。
		if remaining>=missing and remaining<best_capacity:
			best_index=i
			best_capacity=remaining
	if best_index>=0:
		return best_index
	var largest:float=-1.0
	for i:int in range(_berserker_items.size()):
		var item:Dictionary=_berserker_items[i]
		if bool(item.get("consumed",false)) or str(item.get("kind",""))!="heal":
			continue
		var remaining:float=maxf(float(item.get("remaining",0.0)),0.0)
		if remaining>largest:
			largest=remaining
			best_index=i
	return best_index


func _find_berserker_repair_item()->int:
	for i:int in range(_berserker_items.size()):
		var item:Dictionary=_berserker_items[i]
		if bool(item.get("consumed",false)) or str(item.get("kind",""))!="repair":
			continue
		if int(item.get("remaining_uses",0))>0:
			return i
	return -1


func _tick_berserker_consumables(delta:float)->void:
	if _berserker_reload_in_progress:
		return

	if _berserker_using_item_index>=0:
		_continue_berserker_item_use(delta)
		return

	if max_block>0 and block<float(max_block)*clampf(berserker_armor_repair_trigger_ratio,0.0,1.0):
		var repair_index:int=_find_berserker_repair_item()
		if repair_index>=0:
			_begin_berserker_item_use(repair_index,"repair")
			return

	if health<float(Max_health)*clampf(berserker_heal_trigger_ratio,0.0,1.0):
		var heal_index:int=_find_berserker_heal_item()
		if heal_index>=0:
			_begin_berserker_item_use(heal_index,"heal")


func _begin_berserker_item_use(item_index:int,mode:String)->void:
	if item_index<0 or item_index>=_berserker_items.size():
		return
	_request_stop_berserker_loop_gun_audio()
	_reset_berserker_m250_session(true)
	_berserker_using_item_index=item_index
	_berserker_use_mode=mode
	_berserker_use_fraction=0.0
	_berserker_item_ui_sync_elapsed=0.0
	Attacking=false
	_berserker_switch_animation_active=false
	_berserker_manual_fire_requested=false
	_call_berserker_inventory_panel(
		true,
		int(_berserker_items[item_index].get("item_id",-1))
	)
	_refresh_berserker_equipment_visuals()
	_update_berserker_used_item_visual()


func _continue_berserker_item_use(delta:float)->void:
	var index:int=_berserker_using_item_index

	# 整个“正在吃药/修甲”的持续时间里强制保持面板开启。
	if index>=0 and index<_berserker_items.size() and not _berserker_inventory_visible:
		_call_berserker_inventory_panel(
			true,
			int(_berserker_items[index].get("item_id",-1))
		)

	if index<0 or index>=_berserker_items.size():
		_finish_berserker_item_use()
		return
	var item:Dictionary=_berserker_items[index]
	match _berserker_use_mode:
		"heal":
			var remaining:float=maxf(float(item.get("remaining",0.0)),0.0)
			if remaining<=0.0 or health>=Max_health:
				if remaining<=0.0:
					item["consumed"]=true
					_berserker_items[index]=item
				_finish_berserker_item_use()
				return

			# 用浮点累计，避免不同 physics FPS 让整数取整改变总治疗量。
			_berserker_use_fraction+=maxf(float(item.get("heal_rate",70.0)),1.0)*maxf(delta,0.0)
			var wanted:int=floori(_berserker_use_fraction)
			if wanted<=0:
				return
			_berserker_use_fraction-=float(wanted)
			wanted=mini(wanted,int(ceil(remaining)))
			var healed:int=heal(wanted)
			item["remaining"]=maxf(remaining-float(healed),0.0)
			if float(item.get("remaining",0.0))<=0.001:
				item["consumed"]=true
			_berserker_items[index]=item
			_update_berserker_item_durability_ui(index,delta)
			if healed<=0 or health>=Max_health or bool(item.get("consumed",false)):
				_finish_berserker_item_use()
		"repair":
			# 甲修是一次性完整修复。持续约0.85秒后生效，期间显示整个3x3装备格。
			_berserker_use_fraction+=maxf(delta,0.0)
			if _berserker_use_fraction<0.85:
				return
			if max_block>0:
				block=max_block
			item["remaining_uses"]=maxi(int(item.get("remaining_uses",1))-1,0)
			if int(item.get("remaining_uses",0))<=0:
				item["consumed"]=true
			_berserker_items[index]=item
			_update_berserker_item_durability_ui(index,delta)
			_finish_berserker_item_use()
		_:
			_finish_berserker_item_use()


func _finish_berserker_item_use()->void:
	var was_using:bool=_berserker_using_item_index>=0
	_berserker_using_item_index=-1
	_berserker_use_mode=""
	_berserker_use_fraction=0.0
	_berserker_item_ui_sync_elapsed=0.0
	_call_berserker_inventory_panel(false,-1)
	_sync_berserker_runtime_inventory()
	_refresh_berserker_equipment_visuals()
	_update_berserker_used_item_visual()
	if was_using and not _berserker_weapon_indices.is_empty():
		_berserker_switch_animation_elapsed=0.0
		_berserker_switch_animation_active=true
		_berserker_fire_cooldown_remaining=maxf(
			_berserker_fire_cooldown_remaining,
			BERSERKER_WEAPON_SWITCH_DURATION
		)


func _update_berserker_item_durability_ui(item_index:int,delta:float)->void:
	if item_index<0 or item_index>=_berserker_items.size():
		return

	# 10Hz足够让数字看起来连续变化，同时避免每个physics frame都发送一整个背包快照。
	_berserker_item_ui_sync_elapsed+=maxf(delta,0.0)
	if _berserker_item_ui_sync_elapsed<0.10:
		# authority 本机仍然直接重建，所以单机/主机显示每帧都准确。
		_rebuild_berserker_inventory_visual()
		return
	_berserker_item_ui_sync_elapsed=0.0

	var item:Dictionary=_berserker_items[item_index]
	var item_id:int=int(item.get("item_id",-1))
	var remaining:float=float(item.get("remaining",0.0))
	var remaining_uses:int=int(item.get("remaining_uses",0))
	if multiplayer.has_multiplayer_peer():
		_rpc_update_berserker_item_durability.rpc(item_id,remaining,remaining_uses)
	else:
		_rpc_update_berserker_item_durability(item_id,remaining,remaining_uses)


@rpc("authority","call_local","unreliable")
func _rpc_update_berserker_item_durability(
	item_id:int,
	remaining:float,
	remaining_uses:int
)->void:
	for i:int in range(_berserker_items.size()):
		var item:Dictionary=_berserker_items[i]
		if int(item.get("item_id",-1))!=item_id:
			continue
		if str(item.get("kind",""))=="heal":
			item["remaining"]=maxf(remaining,0.0)
		elif str(item.get("kind",""))=="repair":
			item["remaining_uses"]=maxi(remaining_uses,0)
		_berserker_items[i]=item
		break
	_rebuild_berserker_inventory_visual()
	if _berserker_inventory_visible and is_instance_valid(_berserker_inventory_root):
		_berserker_inventory_root.visible=true


func _call_berserker_inventory_panel(show:bool,highlight_item_id:int)->void:
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		_rpc_set_berserker_inventory_panel.rpc(show,highlight_item_id)
	else:
		_rpc_set_berserker_inventory_panel(show,highlight_item_id)


@rpc("authority","call_local","reliable")
func _rpc_set_berserker_inventory_panel(show:bool,highlight_item_id:int)->void:
	_berserker_inventory_visible=show
	_berserker_inventory_highlight_item_id=highlight_item_id
	_ensure_berserker_inventory_visual()
	_rebuild_berserker_inventory_visual()
	if is_instance_valid(_berserker_inventory_root):
		_berserker_inventory_root.visible=show
	if show:
		_update_berserker_inventory_world_position()


func _ensure_berserker_inventory_visual()->void:
	if is_instance_valid(_berserker_inventory_root):
		return
	var scene:Node=get_tree().current_scene
	if scene==null:
		return
	var root:=Node2D.new()
	root.name="猛攻哥保险九格"
	root.z_as_relative=false
	root.z_index=berserker_inventory_z_index
	root.visible=false
	scene.add_child(root)
	_berserker_inventory_root=root

	var cell:float=maxf(berserker_inventory_cell_world_size,8.0)
	var panel:Node2D=_make_safe_search_panel(cell)
	panel.name="保险同款3x3底板"
	root.add_child(panel)

	var highlight:=Node2D.new()
	highlight.name="UsingItemHighlight"
	highlight.visible=false
	root.add_child(highlight)
	_berserker_inventory_highlight=highlight

	var layer:=Node2D.new()
	layer.name="Items"
	root.add_child(layer)
	_berserker_inventory_item_layer=layer


func _berserker_consumable_quality_color(item:Dictionary)->Color:
	match str(item.get("quality","")):
		"绿":
			return Color(0.24,0.92,0.36,1.0)
		"紫":
			return Color(0.68,0.34,1.0,1.0)
		"金":
			return Color(1.0,0.76,0.18,1.0)
		"红":
			return Color(1.0,0.20,0.20,1.0)
		_:
			return Color(0.78,0.84,0.90,1.0)


func _berserker_item_durability_text(item:Dictionary)->String:
	match str(item.get("kind","")):
		"heal":
			return str(maxi(int(ceil(float(item.get("remaining",0.0)))),0))
		"repair":
			return str(maxi(int(item.get("remaining_uses",0)),0))
		_:
			return ""


func _rebuild_berserker_inventory_visual()->void:
	_ensure_berserker_inventory_visual()
	if not is_instance_valid(_berserker_inventory_item_layer):
		return
	for child:Node in _berserker_inventory_item_layer.get_children():
		child.queue_free()
	if is_instance_valid(_berserker_inventory_highlight):
		for child:Node in _berserker_inventory_highlight.get_children():
			child.queue_free()
		_berserker_inventory_highlight.visible=false

	var cell:float=maxf(berserker_inventory_cell_world_size,8.0)
	var half:float=cell*1.5
	for item:Dictionary in _berserker_items:
		if bool(item.get("consumed",false)):
			continue
		var kind:String=str(item.get("kind",""))
		if kind!="heal" and kind!="repair":
			continue

		var pos:Vector2i=item.get("grid_pos",Vector2i.ZERO)
		var size:Vector2i=item.get("grid_size_actual",item.get("grid",Vector2i.ONE))
		var center:=Vector2(
			-half+(float(pos.x)+float(size.x)*0.5)*cell,
			-half+(float(pos.y)+float(size.y)*0.5)*cell
		)
		var item_id:int=int(item.get("item_id",-1))
		var quality:String=str(item.get("quality","绿"))

		var quality_bg:Node2D=_make_safe_quality_background(center,size,cell,quality)
		quality_bg.z_index=0
		_berserker_inventory_item_layer.add_child(quality_bg)

		if item_id==_berserker_inventory_highlight_item_id and is_instance_valid(_berserker_inventory_highlight):
			var hw:float=maxf(float(size.x)*cell*0.5-0.8,2.0)
			var hh:float=maxf(float(size.y)*cell*0.5-0.8,2.0)
			var white_fill:=Polygon2D.new()
			white_fill.polygon=PackedVector2Array([
				center+Vector2(-hw,-hh),center+Vector2(hw,-hh),
				center+Vector2(hw,hh),center+Vector2(-hw,hh)
			])
			white_fill.color=Color(1.0,1.0,1.0,0.22)
			white_fill.z_index=3
			_berserker_inventory_highlight.add_child(white_fill)

			var white_border:=Line2D.new()
			white_border.width=1.65
			white_border.default_color=Color(1.0,1.0,1.0,0.98)
			white_border.closed=true
			white_border.points=PackedVector2Array([
				center+Vector2(-hw,-hh),center+Vector2(hw,-hh),
				center+Vector2(hw,hh),center+Vector2(-hw,hh)
			])
			white_border.z_index=4
			_berserker_inventory_highlight.add_child(white_border)
			_berserker_inventory_highlight.visible=true

		var file_name:String=str(item.get("file",""))
		var tex:=load(BERSERKER_EQUIPMENT_DIR+file_name) as Texture2D
		if tex==null:
			continue
		var sprite:=Sprite2D.new()
		sprite.texture=tex
		sprite.centered=true
		sprite.position=center
		sprite.rotation=PI*0.5 if bool(item.get("grid_rotated",false)) else 0.0
		var target:=Vector2(maxf(float(size.x)*cell-4.0,4.0),maxf(float(size.y)*cell-4.0,4.0))
		if bool(item.get("grid_rotated",false)):
			target=Vector2(target.y,target.x)
		var tex_size:Vector2=tex.get_size()
		var scale_value:float=minf(target.x/maxf(tex_size.x,1.0),target.y/maxf(tex_size.y,1.0))
		sprite.scale=Vector2.ONE*scale_value
		sprite.z_index=2
		_berserker_inventory_item_layer.add_child(sprite)

		var durability_text:String=_berserker_item_durability_text(item)
		if not durability_text.is_empty():
			var durability:=Label.new()
			durability.text=durability_text
			durability.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
			durability.vertical_alignment=VERTICAL_ALIGNMENT_BOTTOM
			# V376：按实际占格矩形计算右下角，标签整个矩形必须留在物品格内部。
			var occupied_width:float=float(size.x)*cell
			var occupied_height:float=float(size.y)*cell
			var durability_margin:float=1.0
			var durability_width:float=minf(22.0,maxf(occupied_width-2.0,8.0))
			var durability_height:float=minf(10.0,maxf(occupied_height-2.0,8.0))
			var occupied_right:float=center.x+occupied_width*0.5
			var occupied_bottom:float=center.y+occupied_height*0.5
			durability.position=Vector2(
				occupied_right-durability_margin-durability_width,
				occupied_bottom-durability_margin-durability_height
			)
			durability.size=Vector2(durability_width,durability_height)
			durability.z_index=5
			durability.add_theme_font_size_override("font_size",7)
			durability.add_theme_color_override("font_color",Color.WHITE)
			durability.add_theme_color_override("font_outline_color",Color(0.0,0.0,0.0,0.98))
			durability.add_theme_constant_override("outline_size",2)
			_berserker_inventory_item_layer.add_child(durability)


func _update_berserker_inventory_world_position()->void:
	if not is_instance_valid(_berserker_inventory_root):
		return
	var rect:Rect2=_map_rect()
	var p:Vector2=global_position
	var left:float=absf(p.x-rect.position.x)
	var right:float=absf(rect.end.x-p.x)
	var top:float=absf(p.y-rect.position.y)
	var bottom:float=absf(rect.end.y-p.y)
	var nearest:float=minf(minf(left,right),minf(top,bottom))
	var offset:=Vector2(berserker_inventory_offset,-8.0)
	if nearest<=maxf(berserker_inventory_wall_flip_distance,1.0):
		if nearest==left:
			offset=Vector2(absf(berserker_inventory_offset),-8.0)
		elif nearest==right:
			offset=Vector2(-absf(berserker_inventory_offset),-8.0)
		elif nearest==top:
			offset=Vector2(0.0,absf(berserker_inventory_offset))
		else:
			offset=Vector2(0.0,-absf(berserker_inventory_offset))
	_berserker_inventory_root.global_position=p+offset


func _cleanup_berserker_inventory_visual()->void:
	if is_instance_valid(_berserker_inventory_root):
		_berserker_inventory_root.queue_free()
	_berserker_inventory_root=null
	_berserker_inventory_item_layer=null
	_berserker_inventory_highlight=null
	_berserker_inventory_visible=false


func _ensure_berserker_equipment_sprites()->void:
	var graphics:=get_node_or_null("Graphics") as Node2D
	if graphics==null:
		return
	if not is_instance_valid(_berserker_armor_sprite):
		var armor:=Sprite2D.new()
		armor.name="BerserkerArmor"
		armor.centered=true
		# V362：护甲继续下移，减少遮头/遮枪。
		# V368：用户仍反馈护甲偏高，继续明显下移。
		armor.position=Vector2(0.0,42.0)
		armor.z_index=3
		# 护甲源图目前默认朝左。
		armor.flip_h=false
		armor.flip_v=false
		armor.visible=false
		graphics.add_child(armor)
		_berserker_armor_sprite=armor

	# 当前正在使用的枪：固定放人物右边。
	if not is_instance_valid(_berserker_gun_sprite):
		var gun:=Sprite2D.new()
		gun.name="BerserkerGun"
		gun.centered=true
		gun.z_index=5
		gun.visible=false
		graphics.add_child(gun)
		_berserker_gun_sprite=gun

	# 非当前枪：竖斜着背在人物背后，z_index 低于人物本体。
	if not is_instance_valid(_berserker_back_gun_sprite):
		var back_gun:=Sprite2D.new()
		back_gun.name="BerserkerBackGun"
		back_gun.centered=true
		back_gun.z_index=-2
		back_gun.visible=false
		graphics.add_child(back_gun)
		_berserker_back_gun_sprite=back_gun

	if not is_instance_valid(_berserker_used_item_sprite):
		var used_item:=Sprite2D.new()
		used_item.name="BerserkerUsedItem"
		used_item.centered=true
		used_item.z_index=8
		used_item.visible=false
		graphics.add_child(used_item)
		_berserker_used_item_sprite=used_item

	# AWM红线不继承人物/Graphics缩放，直接使用世界坐标。
	# 参数复用军火商 SniperAimLine：1.4宽、红色、圆头、抗锯齿。
	if not is_instance_valid(_berserker_awm_aim_line):
		var aim_line:=Line2D.new()
		aim_line.name="BerserkerAWMAimLine"
		aim_line.visible=false
		aim_line.width=BERSERKER_AWM_AIM_LINE_WIDTH
		aim_line.default_color=BERSERKER_AWM_AIM_LINE_COLOR
		aim_line.begin_cap_mode=Line2D.LINE_CAP_ROUND
		aim_line.end_cap_mode=Line2D.LINE_CAP_ROUND
		aim_line.antialiased=true
		aim_line.z_index=4
		aim_line.set_as_top_level(true)
		add_child(aim_line)
		_berserker_awm_aim_line=aim_line


func _update_berserker_used_item_visual()->void:
	_ensure_berserker_equipment_sprites()
	if not is_instance_valid(_berserker_used_item_sprite):
		return
	_berserker_used_item_sprite.visible=false
	if life_index!=2 or _berserker_using_item_index<0 or _berserker_using_item_index>=_berserker_items.size():
		return
	var item:Dictionary=_berserker_items[_berserker_using_item_index]
	if bool(item.get("consumed",false)):
		return
	var file_name:String=str(item.get("file",""))
	var tex:=load(BERSERKER_EQUIPMENT_DIR+file_name) as Texture2D
	if tex==null:
		return
	_berserker_used_item_sprite.texture=tex
	var longest:float=maxf(tex.get_size().x,tex.get_size().y)
	_berserker_used_item_sprite.scale=Vector2.ONE*(82.0/maxf(longest,1.0))
	var side:float=_berserker_character_facing_sign
	_berserker_used_item_sprite.position=Vector2(18.0*side,16.0)
	_berserker_used_item_sprite.rotation=deg_to_rad(-8.0*side)
	_berserker_used_item_sprite.visible=true


func _refresh_berserker_equipment_visuals()->void:
	_ensure_berserker_equipment_sprites()
	if not is_instance_valid(_berserker_armor_sprite) or not is_instance_valid(_berserker_gun_sprite) or not is_instance_valid(_berserker_back_gun_sprite):
		return

	_berserker_armor_sprite.visible=false
	if life_index==2 and _berserker_armor_index>=0 and _berserker_armor_index<_berserker_items.size():
		var armor:Dictionary=_berserker_items[_berserker_armor_index]
		var armor_tex:=load(BERSERKER_EQUIPMENT_DIR+str(armor.get("file",""))) as Texture2D
		if armor_tex!=null:
			_berserker_armor_sprite.texture=armor_tex
			var armor_long:float=maxf(armor_tex.get_size().x,armor_tex.get_size().y)
			_berserker_armor_sprite.scale=Vector2.ONE*(BERSERKER_ARMOR_VISUAL_LONGEST_SIDE/maxf(armor_long,1.0))
			# 护甲原图朝左：人物朝右时才水平翻转护甲。
			_berserker_armor_sprite.flip_h=_berserker_character_facing_sign>0.0
			_berserker_armor_sprite.flip_v=false
			_berserker_armor_sprite.visible=true

	if is_instance_valid(_berserker_awm_aim_line):
		_berserker_awm_aim_line.visible=false

	_berserker_gun_sprite.visible=false
	_berserker_back_gun_sprite.visible=false
	var current_index:int=_current_berserker_weapon_item_index()
	var back_index:int=_back_berserker_weapon_item_index()

	if _berserker_using_item_index>=0:
		if current_index>=0 and current_index<_berserker_items.size():
			var current_weapon:Dictionary=_berserker_items[current_index]
			var current_tex:=load(BERSERKER_EQUIPMENT_DIR+str(current_weapon.get("file",""))) as Texture2D
			if current_tex!=null:
				_berserker_gun_sprite.texture=current_tex
				var gun_long:float=maxf(current_tex.get_size().x,current_tex.get_size().y)
				_berserker_gun_sprite.scale=Vector2.ONE*(_berserker_gun_target_long(current_weapon,true)/maxf(gun_long,1.0))
				_berserker_gun_sprite.z_index=-2
				_berserker_gun_sprite.visible=true
		if back_index>=0 and back_index<_berserker_items.size():
			var back_weapon:Dictionary=_berserker_items[back_index]
			var back_tex:=load(BERSERKER_EQUIPMENT_DIR+str(back_weapon.get("file",""))) as Texture2D
			if back_tex!=null:
				_berserker_back_gun_sprite.texture=back_tex
				var back_long:float=maxf(back_tex.get_size().x,back_tex.get_size().y)
				_berserker_back_gun_sprite.scale=Vector2.ONE*(_berserker_gun_target_long(back_weapon,true)/maxf(back_long,1.0))
				_berserker_back_gun_sprite.z_index=-2
				_berserker_back_gun_sprite.visible=true
		_update_berserker_used_item_visual()
		return

	_berserker_gun_sprite.z_index=5
	if life_index==2 and current_index>=0:
		var weapon:Dictionary=_berserker_items[current_index]
		var gun_tex:=load(BERSERKER_EQUIPMENT_DIR+str(weapon.get("file",""))) as Texture2D
		if gun_tex!=null:
			_berserker_gun_sprite.texture=gun_tex
			var gun_long:float=maxf(gun_tex.get_size().x,gun_tex.get_size().y)
			_berserker_gun_sprite.scale=Vector2.ONE*(_berserker_gun_target_long(weapon,false)/maxf(gun_long,1.0))
			_berserker_gun_sprite.visible=true
	if life_index==2 and back_index>=0:
		var back_weapon:Dictionary=_berserker_items[back_index]
		var back_tex:=load(BERSERKER_EQUIPMENT_DIR+str(back_weapon.get("file",""))) as Texture2D
		if back_tex!=null:
			_berserker_back_gun_sprite.texture=back_tex
			var back_long:float=maxf(back_tex.get_size().x,back_tex.get_size().y)
			_berserker_back_gun_sprite.scale=Vector2.ONE*(_berserker_gun_target_long(back_weapon,true)/maxf(back_long,1.0))
			_berserker_back_gun_sprite.z_index=-2
			_berserker_back_gun_sprite.visible=true
	_update_berserker_used_item_visual()


func _berserker_awm_aim_target_point(weapon:Dictionary)->Variant:
	if has_player_control_aim():
		return player_control_aim_position

	var enemy:Node=return_reusable_combat_target()
	if (
		enemy==null
		or not is_instance_valid(enemy)
		or not _berserker_target_is_in_front_180(enemy)
	):
		return null

	if bool(weapon.get("predictive",false)) and enemy is ball:
		return _berserker_predict_intercept_point(
			enemy as ball,
			maxf(float(weapon.get("projectile_speed",1100.0)),1.0)
		)
	return combat_target_position(enemy)


func _update_berserker_awm_aim_line_visual()->void:
	if not is_instance_valid(_berserker_awm_aim_line):
		return

	var item_index:int=_current_berserker_weapon_item_index()
	if (
		life_index!=2
		or health<=0
		or item_index<0
		or item_index>=_berserker_items.size()
		or _berserker_using_item_index>=0
		or not is_instance_valid(_berserker_gun_sprite)
		or not _berserker_gun_sprite.visible
	):
		_berserker_awm_aim_line.visible=false
		return

	var weapon:Dictionary=_berserker_items[item_index]
	if str(weapon.get("name",""))!="AWM":
		_berserker_awm_aim_line.visible=false
		return

	# 和军火商狙一样：必须存在真实瞄准目标/鼠标点才显示。
	var point_value:Variant=_berserker_awm_aim_target_point(weapon)
	if not (point_value is Vector2):
		_berserker_awm_aim_line.visible=false
		return

	var target_point:Vector2=point_value
	var gun_position:Vector2=_berserker_gun_sprite.global_position
	var distance_value:float=clampf(
		gun_position.distance_to(target_point),
		BERSERKER_AWM_AIM_LINE_MUZZLE_OFFSET+1.0,
		BERSERKER_AWM_AIM_LINE_MAX_LENGTH
	)
	if distance_value<=BERSERKER_AWM_AIM_LINE_MUZZLE_OFFSET:
		_berserker_awm_aim_line.visible=false
		return

	# 红线严格沿“枪当前真实角度”，不是瞬间直接指向目标。
	# 因此枪口尚未转到预判点时，红线也会跟着枪管慢慢扫过去。
	var current_dir:Vector2=_berserker_current_gun_direction()
	if current_dir.length_squared()<=0.000001:
		_berserker_awm_aim_line.visible=false
		return

	_berserker_awm_aim_line.global_position=gun_position
	_berserker_awm_aim_line.global_rotation=current_dir.angle()
	_berserker_awm_aim_line.points=PackedVector2Array([
		Vector2(BERSERKER_AWM_AIM_LINE_MUZZLE_OFFSET,0.0),
		Vector2(distance_value,0.0),
	])

	# 与军火商 SniperAimLine 相同的呼吸闪烁公式。
	var pulse:float=0.68+sin(float(Time.get_ticks_msec())*0.010)*0.16
	_berserker_awm_aim_line.modulate=Color(
		1.0,1.0,1.0,clampf(pulse,0.45,0.90)
	)
	_berserker_awm_aim_line.visible=true


func _update_berserker_equipment_visual_transform()->void:
	if life_index!=2:
		return

	# V374：BerserkerArmor是独立Sprite2D，不会自动继承人物Image Shader的水平镜像。
	# 护甲原图朝左，所以人物朝左保持原图；人物朝右时flip_h=true。
	if is_instance_valid(_berserker_armor_sprite) and _berserker_armor_sprite.visible:
		_berserker_armor_sprite.flip_h=_berserker_character_facing_sign>0.0
		_berserker_armor_sprite.flip_v=false

	if _berserker_using_item_index>=0:
		if is_instance_valid(_berserker_gun_sprite) and _berserker_gun_sprite.visible:
			_berserker_gun_sprite.z_index=-2
			_berserker_gun_sprite.position=Vector2(13.0,7.0)
			_berserker_gun_sprite.rotation=deg_to_rad(-64.0)
			_berserker_gun_sprite.flip_h=false
			_berserker_gun_sprite.flip_v=false
		if is_instance_valid(_berserker_back_gun_sprite) and _berserker_back_gun_sprite.visible:
			_berserker_back_gun_sprite.z_index=-2
			_berserker_back_gun_sprite.position=Vector2(-13.0,7.0)
			_berserker_back_gun_sprite.rotation=deg_to_rad(-116.0)
			_berserker_back_gun_sprite.flip_h=false
			_berserker_back_gun_sprite.flip_v=false
		_update_berserker_used_item_visual()
		return

	if is_instance_valid(_berserker_gun_sprite) and _berserker_gun_sprite.visible:
		var aim:Vector2=_berserker_current_gun_direction()
		if aim.length_squared()<=0.000001:
			aim=_berserker_fallback_facing_direction()
		aim=aim.normalized()
		# V372：人物朝左枪就在左边，人物朝右枪就在右边。
		# 直接使用本帧实际移动朝向，不再用Shader flip反推。
		_berserker_gun_front_sign=_berserker_character_facing_sign
		# V374：人物朝哪边，就继续把枪往那一侧的前方推出。
		_berserker_gun_sprite.position=Vector2(
			BERSERKER_HAND_GUN_FRONT_X*_berserker_gun_front_sign,
			8.0
		)
		var render_aim_angle:float=aim.angle()
		if _berserker_switch_animation_active:
			var switch_eased:float=_berserker_switch_eased_progress()
			render_aim_angle+=BERSERKER_SWITCH_IN_LOWER_ANGLE*_berserker_gun_front_sign*(1.0-switch_eased)
		_berserker_gun_sprite.z_index=5
		_berserker_gun_sprite.rotation=render_aim_angle+PI
		_berserker_gun_sprite.flip_h=false
		_berserker_gun_sprite.flip_v=cos(render_aim_angle)>0.0

	if is_instance_valid(_berserker_back_gun_sprite) and _berserker_back_gun_sprite.visible:
		var back_position:Vector2=BERSERKER_BACK_GUN_NORMAL_POSITION
		var back_rotation:float=BERSERKER_BACK_GUN_NORMAL_ROTATION
		if _berserker_switch_animation_active:
			var back_eased:float=_berserker_switch_eased_progress()
			back_position=BERSERKER_BACK_GUN_SWITCH_START_POSITION.lerp(BERSERKER_BACK_GUN_NORMAL_POSITION,back_eased)
			back_rotation=lerpf(BERSERKER_BACK_GUN_SWITCH_START_ROTATION,BERSERKER_BACK_GUN_NORMAL_ROTATION,back_eased)
		_berserker_back_gun_sprite.z_index=-2
		_berserker_back_gun_sprite.position=back_position
		_berserker_back_gun_sprite.rotation=back_rotation
		_berserker_back_gun_sprite.flip_h=false
		_berserker_back_gun_sprite.flip_v=false
	_update_berserker_used_item_visual()


func _map_rect()->Rect2:
	var w:=get_tree().current_scene
	if w!=null and "map_group" in w and "now_choose_map" in w and w.has_method("return_map_world_rect"):
		var maps:Variant=w.get("map_group")
		var key:=str(w.get("now_choose_map"))
		if maps is Dictionary and (maps as Dictionary).has(key):
			return w.call("return_map_world_rect",(maps as Dictionary)[key]) as Rect2
	return Rect2(global_position-Vector2(350,220),Vector2(700,440))

func _apply_runner_character_texture(texture_path:String)->void:
	if not (image is Sprite2D):
		return
	var sprite:=image as Sprite2D
	var tex:=load(texture_path) as Texture2D
	if tex==null:
		push_warning("跑刀仔角色贴图加载失败: %s" % texture_path)
		return
	sprite.texture=tex
	sprite.visible=true
	sprite.centered=true
	sprite.modulate=Color.WHITE
	sprite.self_modulate=Color.WHITE
	sprite.rotation=0.0

	# V370：猛攻哥原图整体偏黑，只对第二命/独立猛攻哥向白色轻混合。
	if texture_path==RUNNER_REVIVE_TEXTURE_PATH:
		sprite.set_instance_shader_parameter("default_color",Color.WHITE)
		sprite.set_instance_shader_parameter("defualt_color_mix",BERSERKER_CHARACTER_WHITE_MIX)
	else:
		sprite.set_instance_shader_parameter("defualt_color_mix",0.0)
	# V373：跑刀鼠和猛攻哥两张原图都按“默认朝右”解释。
	# 公共 ball 的 dir_left=false 表示：
	#   向右 -> 不镜像；
	#   向左 -> 水平镜像。
	# V360~V372曾把猛攻哥错误设成dir_left=true，导致左右显示完全反过来。
	dir_left=false
	sprite.flip_h=false

	if texture_path==RUNNER_REVIVE_TEXTURE_PATH:
		# 猛攻哥无移动时默认朝右；开始移动后，V372的motion facing sign
		# 会在同一physics tick更新成人物真实移动朝向。
		_berserker_character_facing_sign=1.0

	# 贴图切换后立即按当前方向刷新一次公共 Shader 朝向，避免等到下一次移动才纠正。
	var facing_dir:Vector2 = player_control_direction if is_player_controlled() else direction
	if absf(facing_dir.x) > 0.001:
		var desired_flip:bool = (facing_dir.x > 0.0) if dir_left else (facing_dir.x <= 0.0)
		set_character_visual_flip_h(desired_flip)
	else:
		set_character_visual_flip_h(false)

	var tex_size:=tex.get_size()
	var longest:=maxf(tex_size.x,tex_size.y)
	if longest>0.001:
		var target_longest:float=RUNNER_REVIVE_VISUAL_LONGEST_SIDE if texture_path==RUNNER_REVIVE_TEXTURE_PATH else RUNNER_FIRST_LIFE_VISUAL_LONGEST_SIDE
		var fit_scale:float=target_longest/longest
		sprite.scale=Vector2.ONE*fit_scale


func get_preview_texture()->Texture2D:
	# World.create_ghost_ball() 的局内放置预览不会让角色进入 SceneTree。
	var preview_path:String=(
		RUNNER_REVIVE_TEXTURE_PATH
		if standalone_berserker
		else RUNNER_FIRST_LIFE_TEXTURE_PATH
	)
	return load(preview_path) as Texture2D
