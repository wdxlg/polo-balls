class_name World
extends Node2D

signal character_dialogue_battle_started(serial:int)

var random_character_draft:RefCounted = preload("res://scripts/random_character_draft.gd").new(self)

func is_placeable_obstacle(char_name:String,scene_path:String="") -> bool:
	var path:String = scene_path if not scene_path.is_empty() else character_scene_path(char_name)
	var info:Dictionary = preload("res://classes/combat_classification_catalog.gd").SCENES.get(path,{})
	return str(info.get("entity_kind","")) == "obstacle"


func character_scene_path(char_name:String) -> String:
	_ensure_character_path_index()
	char_name = _canonical_character_name(char_name)
	var current:Variant = Characters_Dic.get(char_name,"")
	if current is PackedScene: return current.resource_path
	if not str(current).is_empty(): return str(current)
	for category:String in _char_folder_names:
		var indexed:Dictionary = _character_paths_by_folder.get(category,{})
		if indexed.has(char_name): return str(indexed[char_name])
	return ""

func _get_character_scene_path(char_name:String,scene_path:String = "") -> PackedScene:
	if scene_path.is_empty(): return _get_character_scene_any(char_name)
	if _character_scene_cache.has(scene_path): return _character_scene_cache[scene_path]
	if not ResourceLoader.exists(scene_path,"PackedScene"): return null
	var scene:PackedScene = load(scene_path) as PackedScene
	if scene != null: _character_scene_cache[scene_path] = scene
	return scene


const TRAINING_STATS_HUD_SCRIPT = preload("res://scripts/training/training_stats_hud.gd")
const MANUAL_TRAINING_CONTROLLER_SCRIPT = preload("res://scripts/training/manual_training_controller.gd")
const COMBAT_THREAT_ANALYZER_SCRIPT = preload("res://scripts/training/combat_threat_analyzer.gd")
const BOSS_INTRO_OVERLAY_SCRIPT = preload("res://scripts/ui/boss_intro_overlay.gd")
const WAITER_DOOR_VISUAL_SCRIPT = preload("res://scripts/effects/服务员门.gd")
const VICTORY_BELL_AUDIO:AudioStream = preload("res://audio/system/胜利铃声.mp3")
## 开战钟声：我的世界 block.bell.use（两个采样 × 原版三档音高）。
const BATTLE_START_BELL_PATHS:Array[String] = ["res://audio/effects/我的世界/bell/bell_use01.ogg","res://audio/effects/我的世界/bell/bell_use02.ogg"]
const BATTLE_START_BELL_PITCHES:Array[float] = [0.93,0.95,0.97]
const WORLD_OUTSIDE_GRID_SHADER:Shader = preload("res://shaders/world_outside_checker.gdshader")
const MAP_BACKGROUND_THEMES = preload("res://scripts/effects/我的世界/地图背景主题.gd")
const HEAVY_GIRL_GLYPH_SHAKE_EFFECT = preload("res://scripts/effects/重女式逐字颤抖.gd")
const MOJANGLES_FONT = preload("res://fonts/Mojangles.ttf")
const VERSUS_TITLE_3D_SCRIPT:GDScript = preload("res://scripts/ui/versus_title_3d.gd")
const DUEL_TOP_HUD_SCRIPT = preload("res://scripts/ui/duel_top_hud.gd")
const COMBAT_IMPACT_LAYER_SCRIPT = preload("res://scripts/effects/combat_impact_layer.gd")

# 地图下方创作者水印：只显示文字，不再使用任何平台图标。

#引用
@export var camera_zoom:float = 5.0

@export_group("工具栏画面缩放")
# 这是相对各地图原始 Camera2D zoom 的倍率，而不是写死绝对 zoom。
@export_range(0.20,1.0,0.05) var toolbar_zoom_min_multiplier:float = 0.45
@export_range(1.0,4.0,0.05) var toolbar_zoom_max_multiplier:float = 2.20
@export_range(1.01,1.50,0.01) var toolbar_zoom_step:float = 1.12
# 兼容旧场景保留该导出字段。V35 起关闭工具栏不再重置缩放倍率；
# 运行中的比赛只归零中键拖动产生的画面偏移。
@export var toolbar_zoom_reset_when_closed:bool = true
var toolbar_zoom_multiplier:float = 1.0

@export_group("战斗电影镜头")
@export_range(0.10,1.0,0.01) var cinematic_focus_default_slow_factor:float = 0.25
@export_range(1.0,2.5,0.05) var cinematic_focus_default_zoom_multiplier:float = 1.55
@export_range(0.05,1.0,0.01) var cinematic_focus_enter_duration:float = 0.34
@export_range(0.05,1.0,0.01) var cinematic_focus_exit_duration:float = 0.32
const CINEMATIC_FOCUS_TIME_KEY:String = "WorldCinematicFocus"
var _cinematic_focus_requests:Dictionary = {}
var _cinematic_focus_weight:float = 0.0
var _cinematic_focus_zoom_multiplier:float = 1.0
var _cinematic_focus_anchor:Vector2 = Vector2.ZERO
var _cinematic_focus_tween:Tween = null

@onready var introduce: Control = $Introduce
@onready var camera_2d: Camera2D = $Camera2D
@onready var control: Control = $CanvasLayer/Control
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner

@export_group("地图下方水印")
@export_range(0.05,1.0,0.01) var center_watermark_opacity:float = 0.48
@export_range(12,96,1) var center_watermark_font_size:int = 36
@export_range(0.0,128.0,1.0) var center_watermark_bottom_gap:float = 7.0
# 只允许按地图比例缩小，不会因为换成纯文字后反而被放大。
# 中文继续用 0.30。英文单独放宽，避免把中文水印一起放大。
@export_range(0.05,0.80,0.01) var center_watermark_map_width_ratio:float = 0.30
@export_range(0.05,0.80,0.01) var center_watermark_english_map_width_ratio:float = 0.56
@export_range(0.03,0.30,0.01) var center_watermark_map_height_ratio:float = 0.07
var _center_watermark_root:Control = null
var _center_watermark_row:HBoxContainer = null
var _center_watermark_name:Label = null
var _center_watermark_follow:Label = null
var _dead_save_watermark_name:RichTextLabel = null

# V392：菜月昴 5 死“死亡回归死档”覆盖顶部对战信息/底部水印。
# 该状态由死档效果节点维持到本局 Reset/场景退出。
var _dead_save_ui_override_active:bool = false
var _dead_save_love_text:String = ""
# V405：死档期间临时强制使用“镜头跟随 / Camera_Move=false”的静态地图视角，不改玩家设置本身。
# 同时压掉 Follow_Controlled_Character 与 cinematic focus 对中心/倍率的再次覆盖。
# Game Autoload 即使 SceneTree 暂停仍会调用 world.process_always()，所以必须逐帧维持。
var _dead_save_force_non_follow_camera:bool = false
const DEAD_SAVE_VERSUS_TEXT:String = "愛してる"
const DEAD_SAVE_WATERMARK_TEXT:String = "サテラ"

@export_group("Boss开场动画")
@export var boss_intro_enabled:bool = true
@export var boss_intro_sound_name:String = "DeadBell"
@export_range(-30.0,6.0,0.5) var boss_intro_sound_volume_db:float = -5.0

#设置
@export var now_char_folder_index:int = 0:
	set(v):
		now_char_folder_index = v
		set_char_dic()
@export var Debug_box := preload("res://scenes/debug_in_hit.tscn")
func create_debug_box(poi:Vector2):
	var new_box:Sprite2D = Debug_box.instantiate()
	new_box.position = poi
	
	add_child(new_box)

@export var Characters_Dic:Dictionary = {}
# V9：角色分类切换只切“路径索引”，不再同步 load 整个分类的所有 tscn。
# 真正选中/生成某个角色时才加载那一个 PackedScene，并放进缓存。
var _char_folder_names:PackedStringArray = PackedStringArray()
var _character_paths_by_folder:Dictionary = {}
var _character_scene_cache:Dictionary = {}

# ========================================================
# 场景级定向重力注册表
#
# 某些角色会周期性向整个战场施加“朝某个方向的重力”。
# 这里不直接改每个对象的位置，而是由提供者把一个加速度向量登记到 World，
# ball 派生对象在自己的公共物理链里查询并积分；少数不继承 ball 的 shooter/BattleTransient
# 则由 World 把同一加速度写回它们原有的方向/速度字段。这样人物、投射物、召唤物
# 可以共享同一套规则，也方便多个来源同时叠加。
# ========================================================
var _directional_gravity_sources:Dictionary = {}

# V286：非 ball shooter 的视觉朝向缓存。只用于渲染方向，不参与命中/速度计算。
var _projectile_visual_last_positions:Dictionary = {}
# V410：非 ball 投射物改为事件注册 + 低频校验；渲染帧不再扫描整个 BattleTransient 组。
var _non_ball_projectiles:Array[Node] = []
var _non_ball_projectile_ids:Dictionary = {}
# 同一脚本的属性结构固定，缓存一次 property_list 解析结果，避免每帧多次反射查询。
var _directional_projectile_profile_cache:Dictionary = {}
const DIRECTIONAL_GRAVITY_NON_BALL_PROJECTILE_MULTIPLIER:float = 7.0
const PROJECTILE_AUTO_FACE_EXCLUDED_SCRIPTS:Array[String] = [
	"res://scripts/shooter/clown/clown_area_object.gd", # 彩纸本身就是持续旋转物体
]


func _ensure_character_path_index() -> void:
	if not _char_folder_names.is_empty() and not _character_paths_by_folder.is_empty():
		return
	var dir := DirAccess.open(char_path)
	if dir == null:
		push_error("无法打开角色目录: " + char_path)
		return
	_char_folder_names = dir.get_directories()
	for folder_name in _char_folder_names:
		var folder_path:String = char_path.path_join(folder_name)
		var folder_dir := DirAccess.open(folder_path)
		var indexed:Dictionary = {}
		if folder_dir != null:
			for file_name in folder_dir.get_files():
				var resource_name:String = file_name
				if resource_name.ends_with(".remap"):
					resource_name = resource_name.trim_suffix(".remap")
				if not resource_name.ends_with(".tscn"):
					continue
				var char_name:String = resource_name.get_basename()
				# “雨衣男”已迁移到月计分类并改名为“伞夫”。旧文件可能仍残留在
				# 玩家工程里；索引层直接隐藏，保证覆盖更新无需手动删旧文件。
				# 若叶睦/薇欧拉 旧版本已于 2026-09 物理删除（正式版在 乐队/），此处继续隐藏以兼容玩家磁盘上的残留旧 tscn。
				if folder_name == "人物" and char_name in ["雨衣男","若叶睦","薇欧拉","愤怒的人"]:
					continue
				# V169：V167/V168 曾误命名为“盔甲甲”。覆盖更新不能删除旧 tscn，
				# 因此保留兼容壳但从角色选择索引中隐藏，正式名称只显示“盔甲架”。
				if folder_name == "默认" and char_name == "盔甲甲":
					continue
				# V100：女巫已从“投稿”迁移到“我的世界”。覆盖更新无法删除玩家磁盘上的旧 tscn，
				# 因此索引层明确隐藏旧投稿路径；旧场景只作为外部引用兼容壳保留。
				if folder_name == "投稿" and char_name in ["女巫","掷骰子的人","疲倦的人"]:
					continue
				# 乌鲁鲁就是既有“堵桥”。上一轮若已复制过误建的独立 乌鲁鲁.tscn，
				# 覆盖更新无法物理删除旧文件，因此索引层隐藏它，避免角色选择出现两个乌鲁鲁。
				if folder_name == "三角洲" and char_name == "乌鲁鲁":
					continue
				indexed[char_name] = folder_path.path_join(resource_name)
		_character_paths_by_folder[folder_name] = indexed

func set_char_dic() -> void:
	now_choose_char = ""
	_ensure_character_path_index()
	Characters_Dic = {}
	if now_char_folder_index < 0 or now_char_folder_index >= _char_folder_names.size():
		return
	var folder_name:String = _char_folder_names[now_char_folder_index]
	var indexed:Dictionary = _character_paths_by_folder.get(folder_name,{})
	# 这里只复制几十个 String 引用，不解析/实例化场景，因此切分类不再阻塞主线程。
	Characters_Dic = indexed.duplicate()

func add_to_chars(path:String) -> void:
	# 保留旧回调兼容，但只登记路径，不同步 load。
	var resource_path:String = path.trim_suffix(".remap") if path.ends_with(".remap") else path
	if not resource_path.ends_with(".tscn"):
		return
	Characters_Dic[resource_path.get_file().get_basename()] = resource_path

func _canonical_character_name(char_name:String) -> String:
	# 兼容旧录像/旧配置：资源已经改名，但历史数据里的“雨衣男”仍应生成伞夫。
	if char_name == "雨衣男":
		return "伞夫"
	# Wither is 凋灵; 凋零 names the status effect, not the character.
	if char_name == "凋零":
		return "凋灵"
	return char_name


func _get_character_scene(char_name:String) -> PackedScene:
	char_name = _canonical_character_name(char_name)
	if not Characters_Dic.has(char_name):
		return null
	var entry = Characters_Dic[char_name]
	if entry is PackedScene:
		return entry as PackedScene
	var path:String = str(entry)
	if path.is_empty():
		return null
	if _character_scene_cache.has(path):
		return _character_scene_cache[path] as PackedScene
	# 单个角色第一次被选择时才加载；之后 World 生命周期内直接复用。
	var loaded := ResourceLoader.load(path,"PackedScene") as PackedScene
	if loaded != null:
		_character_scene_cache[path] = loaded
	return loaded

func _get_character_scene_any(char_name:String) -> PackedScene:
	char_name = _canonical_character_name(char_name)
	# 轮放/计时会先把跨分类角色加入名单，真正开战时 Characters_Dic 可能已经切到别的分类。
	# 因此特殊训练不能只查“当前分类”，而要从完整路径索引中定位角色。
	var current:PackedScene = _get_character_scene(char_name)
	if current != null:
		return current
	_ensure_character_path_index()
	for folder_name in _char_folder_names:
		var indexed:Dictionary = _character_paths_by_folder.get(folder_name,{})
		if not indexed.has(char_name):
			continue
		var path:String = str(indexed[char_name])
		if _character_scene_cache.has(path):
			return _character_scene_cache[path] as PackedScene
		var loaded := ResourceLoader.load(path,"PackedScene") as PackedScene
		if loaded != null:
			_character_scene_cache[path] = loaded
		return loaded
	return null

func _has_character_scene_any(char_name:String) -> bool:
	return _get_character_scene_any(char_name) != null

func return_all_character_names() -> Array[String]:
	# 搜索框需要跨分类查角色，但只读取路径索引，不提前 load 所有场景。
	_ensure_character_path_index()
	var unique:Dictionary = {}
	for folder_name in _char_folder_names:
		var indexed:Dictionary = _character_paths_by_folder.get(folder_name,{})
		for raw_name:Variant in indexed.keys():
			unique[str(raw_name)] = true
	var names:Array[String] = []
	for raw_name:Variant in unique.keys():
		names.append(str(raw_name))
	names.sort()
	return names

func return_max_char_index() -> int:
	_ensure_character_path_index()
	return _char_folder_names.size() - 1
func return_now_char_type() -> String:
	_ensure_character_path_index()
	if now_char_folder_index >= 0 and now_char_folder_index < _char_folder_names.size():
		return _char_folder_names[now_char_folder_index]
	return ""


var _character_translation_keys_reported:bool = false

func report_all_character_translation_keys() -> void:
	# 只在第一次切到英文时扫描一次。Game 会把缺少的 key 合并后一次写盘，
	# 避免切语言时按“每个角色一个文件操作”的方式卡住主线程。
	if _character_translation_keys_reported or not Game.current_locale.begins_with("en"):
		return
	_character_translation_keys_reported = true

	var root_dir := DirAccess.open(char_path)
	if root_dir == null:
		return

	for folder_name in root_dir.get_directories():
		Game.t(folder_name)
		var folder_path:String = char_path.path_join(folder_name)
		var folder_dir := DirAccess.open(folder_path)
		if folder_dir == null:
			continue
		for file_name in folder_dir.get_files():
			if file_name.ends_with(".tscn"):
				Game.t(file_name.get_basename())


@export var Particle_Dic:Dictionary = {}
func add_to_prticles(path:String) -> void:
	var particle:PackedScene = load(path)
	Particle_Dic[particle.resource_path.get_file().split(".")[0]] = particle

@rpc("authority","call_local")
func create_new_particle(particle_name:String,master:Node,offset:Vector2 = Vector2.ZERO,delya_time:float = 0,parent:Node = null,destroy_self:bool = false) -> void:
	var new_particle:particles = Particle_Dic[particle_name].instantiate()
	new_particle.master = master
	new_particle.position_offset = offset
	new_particle.delay_emit = delya_time
	new_particle.destroy_self = destroy_self
	
	new_particle.global_position = master.global_position
	
	new_particle.name = Game.return_random_name(new_particle)
	if parent:parent.add_child(new_particle,true)
	else:add_child(new_particle,true)


@export var default_map:String = "Map10x10"

#========================================================
# 出界淘汰规则
#========================================================
@export_category("出界规则")
@export var out_of_bounds_enabled:bool = true
@export_range(0.5,10.0,0.1) var out_of_bounds_death_delay:float = 3.0
# 默认按地图真实矩形判断；需要给墙边留容错时可以填正数。
@export_range(0.0,100.0,1.0) var out_of_bounds_margin:float = 0.0
var _out_of_bounds_states:Dictionary = {}

#========================================================
# 地图防挤出
#
# TileMap 自己的墙仍然保留；这里额外建立一圈不可见 StaticBody2D 安全框，
# 防止多个 CharacterBody2D、击退、移动地形等在墙角把角色挤穿。
# 如果已经只挤出去一点点，会把角色纠正回合法中心区域；
# 真正被传送到很远的地图外仍然走上面的 3 秒出界淘汰规则。
#========================================================
@export_category("地图防挤出")
@export var map_safety_frame_enabled:bool = true
@export_range(4.0,120.0,1.0) var map_safety_wall_thickness:float = 48.0
# 安全墙的内侧面相对地图外边界向内压多少像素。通常 1~2 px 即可。
@export_range(0.0,12.0,0.5) var map_safety_wall_inset:float = 1.0
# 角色中心只越界少量时视为“被挤出”，立即救回；更远则保留 3 秒淘汰倒计时。
@export_range(0.0,160.0,1.0) var map_squeeze_rescue_distance:float = 56.0
# 按角色真实 CollisionShape2D 半径再多留一点余量，避免救回后下一帧又贴墙穿出。
@export_range(0.0,16.0,0.5) var map_squeeze_rescue_padding:float = 2.0
const MAP_WALL_EMBED_TOLERANCE:float = 1.5

var _map_safety_frame:Node2D = null
var _map_safety_frame_map_name:String = ""

#========================================================
# 服务员开门
#
# 门本身由 World 管理，因为它必须同时改变：
# 1. 黑色地图边线；
# 2. 额外安全墙；
# 3. 角色对 TileMap/安全墙（物理层 1）的临时穿行权限；
# 4. 从门口逃出的敌人的自动回拉豁免。
#========================================================
var _waiter_doors:Dictionary = {}
var _waiter_door_next_id:int = 1
var _waiter_door_masked_bodies:Dictionary = {}
const WAITER_DOOR_PASSAGE_GRACE_MSEC:int = 520

@onready var now_choose_team:String
@onready var now_choose_char:String
@onready var now_choose_map:String = default_map
var map_group:Dictionary = {}
const DEVELOPMENT_MODE_SCRIPT = preload("res://scripts/development_mode.gd")
var _development

#========================================================
# 断开地形（PortalMap）支持
#
# map_group 里既可以是普通 TileMapLayer，也可以是 PortalMap（多个 TileMapLayer 岛 + 传送门）。
# 下面的辅助函数把“当前地图”抽象成“一个或多个岛矩形”，地图边框 / 内沿阴影 / 地图外遮罩 /
# 安全墙 / 越界规则都按岛逐个处理；相机仍按所有岛的外接矩形取景。
# 传送本身由 PortalMap.process_transits() 在 World 的物理帧里驱动（早于角色 move_and_slide）。
#========================================================
var _ball_projectile_units:Array = []
var _ball_projectile_ids:Dictionary = {}
var _island_extra_inside_shadows:Array[Node2D] = []
var _island_extra_background_tiles:Array[Node2D] = []
var _island_extra_background_shadows:Array[Node2D] = []


func _is_map_node(node:Variant) -> bool:
	return node is TileMapLayer or node is PortalMap


func _current_map_node() -> Node:
	if not map_group.has(now_choose_map):
		return null
	var node:Variant = map_group[now_choose_map]
	if _is_map_node(node) and is_instance_valid(node):
		return node
	return null


func current_portal_map() -> PortalMap:
	if _development != null and _development.is_prebattle():
		return null # 发育期每张副本各有自己的 PortalMap，不能误用原始地图的门。
	var node:Node = _current_map_node()
	if node is PortalMap:
		return node as PortalMap
	return null


# 当前地图的岛列表：[{name, rect}]。普通 TileMapLayer 地图只有一个岛。
const TileGeometry = preload("res://classes/map_tile_geometry.gd")

func map_islands(map_node:Node) -> Array[Dictionary]:
	if _development != null and _development.is_prebattle() and map_node == _current_map_node():
		return _development.current_islands
	var result:Array[Dictionary] = []
	if map_node is PortalMap:
		for entry:Dictionary in (map_node as PortalMap).island_entries():
			var shape:Dictionary = TileGeometry.from_layer(map_node.islands[str(entry.name)])
			result.append({"name":str(entry.name),"rect":entry.rect,"regions":shape.regions,"walls":shape.walls})
	elif map_node is TileMapLayer:
		var shape:Dictionary = TileGeometry.from_layer(map_node)
		result.append({"name":str(map_node.name),"rect":return_map_world_rect(map_node),"regions":shape.regions,"walls":shape.walls})
	return result

func map_island_rects(map_node:Node) -> Array[Rect2]:
	var rects:Array[Rect2] = []
	for island:Dictionary in map_islands(map_node):
		rects.append_array(island["regions"])
	return rects


func current_map_island_rects() -> Array[Rect2]:
	return map_island_rects(_current_map_node())


func _island_visual_rect(rect:Rect2,cell:Vector2) -> Rect2:
	if not _is_grass_map_background():
		return rect
	return Rect2(rect.position-cell,rect.size+cell*2.0)


func _island_display_rect(rect:Rect2,cell:Vector2) -> Rect2:
	var outward:float = maxf(map_border_width,0.0) if _is_grass_map_background() else maxf(map_border_width*0.5-1.0,0.0)
	return _island_visual_rect(rect,cell).grow(outward)


# 点是否落在任意一个岛内。
func map_contains_point(p:Vector2,rects:Array[Rect2]) -> bool:
	for rect:Rect2 in rects:
		if rect.has_point(p):
			return true
	return false


# 包含该点的岛，否则离该点最近的岛；没有岛时返回空矩形。
func nearest_map_island_rect(p:Vector2,rects:Array[Rect2]) -> Rect2:
	var best:Rect2 = Rect2()
	var best_distance:float = INF
	for rect:Rect2 in rects:
		if rect.has_point(p):
			return rect
		var nearest:Vector2 = Vector2(clampf(p.x,rect.position.x,rect.end.x),clampf(p.y,rect.position.y,rect.end.y))
		var d:float = p.distance_squared_to(nearest)
		if d < best_distance:
			best_distance = d
			best = rect
	return best


# 把“无限平面 - 所有岛”切成若干矩形；用于地图外裁剪遮罩与视差网格。
func _map_outside_rects(rects:Array[Rect2]) -> Array[Rect2]:
	var extent:float = 1000000.0
	if rects.is_empty():
		return [Rect2(Vector2(-extent,-extent),Vector2(extent*2.0,extent*2.0))]
	var bounds:Rect2 = rects[0]
	for rect:Rect2 in rects:
		bounds = bounds.merge(rect)
	var l:float = bounds.position.x
	var r:float = bounds.end.x
	var t:float = bounds.position.y
	var b:float = bounds.end.y
	var result:Array[Rect2] = [
		Rect2(Vector2(-extent,-extent),Vector2(extent*2.0,t+extent)),
		Rect2(Vector2(-extent,b),Vector2(extent*2.0,extent-b)),
		Rect2(Vector2(-extent,t),Vector2(l+extent,maxf(b-t,0.0))),
		Rect2(Vector2(r,t),Vector2(extent-r,maxf(b-t,0.0))),
	]
	if rects.size() <= 1:
		return result
	# 多岛：用所有岛的边缘切成网格，把不属于任何岛的格子补成遮罩。
	var xs:Array[float] = []
	var ys:Array[float] = []
	for rect:Rect2 in rects:
		for x:float in [rect.position.x,rect.end.x]:
			if not xs.has(x):
				xs.append(x)
		for y:float in [rect.position.y,rect.end.y]:
			if not ys.has(y):
				ys.append(y)
	xs.sort()
	ys.sort()
	for i:int in range(xs.size()-1):
		for j:int in range(ys.size()-1):
			var cell:Rect2 = Rect2(xs[i],ys[j],xs[i+1]-xs[i],ys[j+1]-ys[j])
			if cell.size.x <= 0.001 or cell.size.y <= 0.001:
				continue
			if not map_contains_point(cell.get_center(),rects):
				result.append(cell)
	return result


static func _rect_polygon(rr:Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rr.position,
		Vector2(rr.end.x,rr.position.y),
		rr.end,
		Vector2(rr.position.x,rr.end.y),
	])


func _ensure_island_visual_count(list:Array[Node2D],count:int,script_path:String,node_name:String,z:int) -> void:
	while list.size() < count:
		var node:Node2D = load(script_path).new()
		node.name = "%s_%d" % [node_name,list.size()+2]
		node.z_as_relative = false
		node.z_index = z
		add_child(node)
		list.append(node)
	for i:int in range(list.size()):
		if is_instance_valid(list[i]):
			list[i].visible = i < count


# 岛的安全墙允许向外伸出的最大厚度：不能压进其它岛。
func _island_safety_clearance(rects:Array[Rect2],index:int) -> float:
	var clearance:float = INF
	var rect:Rect2 = rects[index]
	for i:int in range(rects.size()):
		if i == index:
			continue
		var other:Rect2 = rects[i]
		var dx:float = maxf(maxf(other.position.x - rect.end.x,rect.position.x - other.end.x),0.0)
		var dy:float = maxf(maxf(other.position.y - rect.end.y,rect.position.y - other.end.y),0.0)
		clearance = minf(clearance,maxf(dx,dy))
	return clearance


func portal_get_projectile_velocity(node:Node) -> Vector2:
	return _directional_gravity_projectile_velocity(node)


func portal_set_projectile_velocity(node:Node,new_velocity:Vector2) -> void:
	_set_directional_gravity_projectile_velocity(node,new_velocity)


func _process_portal_transits(delta:float,ball_group:Array) -> void:
	if _development != null and _development.is_prebattle():
		_development.process_portal_transits(delta,ball_group,_ball_projectile_units,_non_ball_projectiles)
		return
	var portal:PortalMap = current_portal_map()
	if portal == null:
		return
	for i:int in range(_ball_projectile_units.size()-1,-1,-1):
		var raw:Variant = _ball_projectile_units[i]
		if raw == null or not is_instance_valid(raw):
			_ball_projectile_units.remove_at(i)
	portal.process_transits(delta,ball_group,_ball_projectile_units,_non_ball_projectiles)

#========================================================
# 地图 / 顶部标题 / 互动文字
#========================================================

# 地图黑色描边粗细
@export var map_border_width:float = 2.0

# 第一行：角色名 VS 角色名
# 不再固定字号：优先使用最大字号，内容太长时自动缩小；
# 即使缩到最小仍放不下，也会自动换行并自动增加高度，避免文字被截断。
@export var versus_font_max_size:int = 12
@export var versus_font_min_size:int = 6
# 与地图边缘和相机平移无关的屏幕标题留白（屏幕像素）。
@export var versus_screen_top_padding_px:float = 240.0
@export var versus_screen_side_padding_px:float = 24.0

# Armor introductions replace VS in test battles; ordinary match titles are unchanged.
@export var armor_intro_screen_top_padding_px:float = 48.0
@export var armor_intro_font_size:int = 32
var armor_intro_label:RichTextLabel

# 第二行：互动文字（紧贴在 VS 文字下面）
# 同样使用自适应字号，不再固定高度。
@export var interaction_font_max_size:int = 9
@export var interaction_font_min_size:int = 6

# 左右留白，防止文字贴着地图边缘。
@export var top_text_horizontal_padding:float = 4.0

# 动画文字会轻微离开原字形位置，因此额外保留一点上下空间。
@export var versus_effect_margin:float = 2.0
@export var interaction_effect_margin:float = 4.0

# The exported sizes are the Map10x10 editor defaults. Keep their original values
# so switching between maps does not compound the scale on every layout pass.
var _versus_base_max_size:int = -1
var _versus_base_min_size:int = -1
var _versus_base_effect_margin:float = -1.0
var _versus_layout_base_zoom:float = 1.0

@export var versus_interaction_gap:float = 1.0
@export var interaction_map_gap:float = 4.0
@export var interaction_enabled:bool = false

# 地图画面自动适配。Map10x10 是视觉基准：默认 zoom 必须保持和旧版一致。
# 其他地图才根据实际尺寸相对这个基准缩放，避免“修适配”后连 10x10 本身都变小。
@export var map_reference_name:String = "Map10x10"
@export var map_reference_zoom:float = 5.0
@export_range(0.50,1.0,0.01) var map_fit_viewport_ratio:float = 0.98
# 很小的地图允许比 10x10 放大一些以减少空白，但限制最大倍率，避免 2x2 被放大到夸张程度。
@export_range(1.0,3.0,0.05) var small_map_max_zoom_multiplier:float = 1.50
# 地图外遮罩用于把角色/特效伸出地图的部分裁掉。它位于普通战斗对象之上、血条/地图边框/顶部文字之下。
@export var map_outside_mask_enabled:bool = true
@export var map_outside_mask_color:Color = Color(0.0,0.0,0.0,1.0)

@export_group("地图外视差网格")
@export var map_outside_grid_enabled:bool = true
# 棋盘浅格沿用当前场景的标准背景蓝。
@export var map_outside_grid_normal_color:Color = Color(0.0,0.5882353,0.87058824,1.0)
# 深格保持同色相，只降低亮度，避免地图外区域抢过战斗主体。
@export var map_outside_grid_dark_color:Color = Color(0.0,0.27,0.48,0.18)
@export_range(24.0,120.0,1.0) var map_outside_grid_cell_size_px:float = 64.0
# 0 = 完全固定在屏幕，1 = 与世界同速；较小值会产生“远处背景”的视差。
@export_range(0.0,1.0,0.01) var map_outside_grid_parallax_scale:float = 0.32
# 血条允许跨出地图边界显示；它高于地图外裁剪遮罩，但低于黑色地图边线。
@export_range(91,99,1) var map_health_bar_z_index:int = 99
# 轻度越界时不再瞬移，而是在这段时间内平滑拉回合法区域。
@export_range(0.05,0.8,0.01) var map_rescue_animation_duration:float = 0.20

#========================================================
# ★ 互动文字表 ★
#
# 只需要在这里填写普通文字，不要写 BBCode。
# 每次 World 启动时：
# 1. 从这里随机选一句；
# 2. 随机选一种较轻的 RichText 动画效果；
# 3. 互动文字保持纯白色；
# 4. 本次运行期间固定，不会因为角色、队伍、地图或 reset 改变。
#========================================================
@export var interaction_text_table:Array[String] = []

# 不同阵营依次使用不同颜色。
# 颜色用完后会自动生成新颜色，所以阵营数量不限。
@export var team_text_colors:Array[Color] = [
	Color(1.0,0.25,0.25),
	Color(0.25,0.65,1.0),
	Color(0.25,1.0,0.35),
	Color(1.0,0.85,0.2),
	Color(0.95,0.35,1.0),
	Color(0.2,1.0,1.0),
	Color(1.0,0.55,0.2),
	Color(0.65,0.45,1.0)
]

var map_border_line:Line2D
var map_border_segment_root:Node2D = null
var versus_screen_layer:CanvasLayer = null
var versus_label:RichTextLabel
var duel_top_hud:Control = null
var interaction_label:RichTextLabel
# 只要场上存在任意盔甲架系角色，顶部战斗标题切换为测试信息 HUD。
# 该状态由 refresh_versus_text() 以顶部 UI 的既有 5Hz 节奏刷新，避免每渲染帧扫描角色组。
var _armor_stand_test_hud_active:bool = false
# 测试 HUD 只锁定“第一个上场的真实敌方角色”。普通召唤物永远不切换目标；
# 蠹虫这类比赛延续单位则沿用原角色身份，因此一窝单位仍只算一个角色。
var _armor_stand_test_primary_setup_id:int = -1
var _armor_stand_test_primary_instance_id:int = 0
var _armor_stand_test_primary_side_key:String = ""
var _armor_stand_test_primary_identity:String = ""
# 锁定第一个敌人时同时记住“原角色脚本”。后续即使它生成延续单位/切换形态，
# 顶部说明仍介绍这个角色整体，而不是突然变成某个召唤物或第二形态的说明。
var _armor_stand_test_primary_script_path:String = ""
var _armor_stand_test_primary_snapshot:Dictionary = {}
var map_outside_mask_root:Node2D = null
var map_outside_mask_parts:Array[Polygon2D] = []
var map_outside_grid_root:Node2D = null
var map_outside_grid_parts:Array[Polygon2D] = []
var map_outside_grid_material:ShaderMaterial = null
# 地图外裁剪不再用纯黑色矩形盖住画面。
# TileMap 只用于规划地图范围/碰撞，运行时本身不绘制；因此这里在角色之前
# 复制的是“真实场景背景”。地图外遮罩读取这份 back buffer，只擦掉越界的角色视觉。
var map_clip_backbuffer:BackBufferCopy = null
var map_clip_material:ShaderMaterial = null
var training_stats_hud:Control = null
var manual_training_controller:Node2D = null

#========================================================
# 地图下方角色对话
#========================================================
@export_group("地图下方角色对话")
@export_range(1.0,12.0,0.1) var character_dialogue_default_duration:float = 3.6
@export_range(24.0,96.0,1.0) var character_dialogue_lane_height:float = 46.0
@export_range(6,20,1) var character_dialogue_font_size:int = 9
@export_range(32.0,120.0,1.0) var character_dialogue_timed_clock_width:float = 54.0
# 计时模式按用户约定：前三个阵营依次放在计时器左边，第四个开始放到右边。
@export_range(1,6,1) var character_dialogue_timed_left_slots:int = 3
var character_dialogue_root:Control = null
var _character_dialogue_labels:Dictionary = {}
var _character_dialogue_entries:Dictionary = {}
var _character_dialogue_serials:Dictionary = {}
var _character_dialogue_tweens:Dictionary = {}
var _character_dialogue_seen_order:Array[String] = []
var _character_dialogue_battle_was_active:bool = false
var _character_dialogue_battle_serial:int = 0

#========================================================
# 训练模式：轮放 / 计时 / Boss
#========================================================
var rotation_versus_root:Control = null
var rotation_left_root:Control = null
var rotation_right_root:Control = null
var rotation_vs_label:Label = null
var _rotation_rosters:Dictionary = {"left": [], "right": []}
var rotation_selected_round:int = 0 # 0 = automatic single-slot placement.
const ROTATION_QUICK_LAYOUT_SCRIPT = preload("res://scripts/ui/rotation_quick_layout.gd")
var _rotation_quick_layout:Node2D
var _rotation_draft_rounds:Array[int]=[1]
var _rotation_preview_round:int = 1
var _rotation_formation_preview:Dictionary = {}
var _rotation_active_records:Dictionary = {"left":[],"right":[]}
var _rotation_next_index:Dictionary = {"left": 0, "right": 0}
var _rotation_active_setup:Dictionary = {"left": -1, "right": -1}
var _rotation_active_name:Dictionary = {"left": "", "right": ""}
var _rotation_current_labels:Dictionary = {"left": null, "right": null}
var _rotation_history_labels:Dictionary = {"left": [], "right": []}
var _rotation_future_labels:Dictionary = {"left": [], "right": []}
# 布阵阶段也要实时显示名单。这里保留每一侧用于“滚动预览”的 Label，
# 以及第一位实际人物的冻结预览实例。开战时第一位从预览状态直接启用。
var _rotation_setup_preview_labels:Dictionary = {"left": [], "right": []}
var _rotation_preview_character:Dictionary = {"left": null, "right": null}
var _rotation_results:Dictionary = {}
var _rotation_frame_hud:Node2D
var _rotation_epoch:int = 0
var _rotation_finished:bool = false
var _rotation_clearing_round:bool = false
var _rotation_fresh_round:bool = false
var _rotation_saved_rosters:Dictionary = {"left": [], "right": []}
var _rotation_saved_map:String = ""
var _rotation_started:bool = false
var _rotation_transitioning:bool = false
var _rotation_combat_released:bool = false
var _rotation_combat_blocked:bool = false
var _rotation_door:CanvasLayer
## 轮换切换时门上的胜利卡片（rotation_result_card.gd）。
var _rotation_toast_mirror:Control
## 轮换切换：门关上后保持的秒数，底部经验条按这段时间充满后开门。
const ROTATION_RESULT_WAIT_SECONDS:float = 2.0
const ROTATION_PRE_DOOR_SECONDS:float = 0.6
## 比赛完整结束时从屏幕下方放的我的世界烟花（scripts/effects/我的世界/mc_firework.gd）。
const MC_FIREWORK_SCRIPT:String = "res://scripts/effects/我的世界/mc_firework.gd"
var _match_fireworks:Node2D
var _match_fireworks_played:bool = false
var _rotation_load_ready:bool = false
var _rotation_ui_token:int = 0
var _rotation_ui_progress:float = 0.0
var _rotation_pending_dead_sides:Array[String] = []
# V83：布阵名单超过顶部可视区域时，用滚轮查看更早/更后的名字。
# 数值表示“从最新一页向旧名单回滚了多少行”，0 = 始终跟随最新加入的人物。
var _rotation_setup_scroll_rows:Dictionary = {"left": 0, "right": 0}
const ROTATION_SETUP_VISIBLE_ROWS:int = 5
const ROTATION_NAME_ROW_HEIGHT:float = 12.0

var timed_training_label:Label = null
var _timed_pending_entries:Array[Dictionary] = []
var _timed_running:bool = false
var _timed_finished:bool = false
var _timed_overtime:bool = false
var _timed_winner_setup:int = -1
var _timed_defeated_setups:Dictionary = {}
var _timed_sync_elapsed:float = 0.0
var _timed_sync_sequence:int = 0
var _timed_received_sequence:int = -1
# 只有“本轮确实新放置过计时角色”时，关闭工具栏才允许自动开始。
# Reset 后旧角色使用 queue_free()，同一帧仍可能暂时留在 Ball 组里；
# 没有这个闸门时会被误判为“仍有两名角色”，从而把刚重置的计时器立刻再次启动。
var _timed_start_armed:bool = false
var _timed_time_left:float = 0.0
# 计时模式分数：每个参战 setup 本局【受到】的全部实际生命伤害（敌人/召唤物/环境/自伤都算），最少者胜。
# 变量名沿用旧名，duel_top_hud 与联机快照共用同一份数据。
var _timed_damage_by_setup:Dictionary = {}
var _timed_name_by_setup:Dictionary = {}
var _timed_damage_labels:Dictionary = {}
# 伤害数字不再作为人物的子控件（否则会继承人物/图片的缩放差异）。
# 这里只保存人物 instance_id，每帧按实际显示 Sprite 的全局边界重新定位。
var _timed_damage_label_character_ids:Dictionary = {}
# 计时模式队伍：setup_id -> 队伍键（"team:队名"；无队伍为 "solo_setup:id"），与胜利判定的阵营键一致。
# 权威端按当前布阵实时计算并随快照下发；客机没收到快照前本地推算。
var _timed_team_by_setup:Dictionary = {}
# 头顶数字 / 顶部对战 UI 数字按所在队伍的受伤排名，由白色渐变到这个红色。
const TIMED_HEAT_RED:Color = Color(1.0,0.2,0.2)

# 轮放/计时布阵阶段需要冻结所有实际战斗对象。
# 某些角色（例如兔子）会在 _ready()/call_deferred 中额外生成同伴，
# 只禁用最初放下的主角色会漏掉这些后生成对象，因此按 instance_id 统一追踪。
var _special_prestart_frozen_ids:Dictionary = {}

# Boss 模式在布阵阶段同样冻结；关闭选人面板后先播放开场，再恢复战斗。
var _boss_started:bool = false
var _boss_intro_playing:bool = false
var _boss_intro_overlay:CanvasLayer = null

var _presentation_map_name:String = ""
var _last_versus_text:String = ""

# 阵营颜色在本次 World 生命周期里保持固定。
var _side_color_map:Dictionary = {}
var _next_side_color_index:int = 0
# VS 文案独立于人物 Shader 染色：仅缓存第三队起的随机色；前两队按当前展示顺序分色。
var _versus_team_colors:Dictionary = {}
var _next_versus_team_color_index:int = 0

# 本次启动时只随机一次，之后不会再次修改。
var _fixed_interaction_bbcode:String = ""
var _fixed_interaction_source:String = ""
var _fixed_interaction_effect_index:int = 0
var _interaction_initialized:bool = false

@onready var camera_shake_amount:float = 0

@export var default_shake_restore:float = 100
@onready var shake_restore:float = default_shake_restore

@export var shake_rate:float = 0.1
@export var max_shake_amount:float = 100

# 伤害通道与旧技能演出通道分开，渲染时取较强者而非相加，避免同次命中双倍震动。
# 强度以视口像素计算，不随地图缩放而忽强忽弱。
@export_range(0.0,3.0,0.05) var damage_shake_strength:float = 1.0
@export_range(0.0,24.0,0.5) var damage_shake_max_pixels:float = 10.0
const FEEDBACK_TUNING = preload("res://global/feedback_settings.gd")
const LIGHT_DAMAGE_SHAKE_MAX_PIXELS:float = 0.75
var _damage_shake_pending_peak:float = 0.0
var _damage_shake_pending_sum:float = 0.0
var _damage_shake_pending_duration:float = 0.10
var _damage_shake_pixels:float = 0.0
var _damage_shake_time_left:float = 0.0
var _damage_shake_duration:float = 0.12
var _damage_shake_elapsed:float = 0.0
# 方向性推镜：命中瞬间沿击退方向推一下画面，再用欠阻尼弹簧回中；与零中心抖动叠加。
const CAMERA_KICK_GAIN:float = 0.9
const CAMERA_KICK_FREQUENCY:float = 20.0
const CAMERA_KICK_DAMPING_RATIO:float = 0.55
# 欠阻尼冲量响应的峰值约为 v0/ω × 0.52（ζ=0.55）。
const CAMERA_KICK_PEAK_FACTOR:float = 0.52
var _camera_kick_pending:Vector2 = Vector2.ZERO
var _camera_kick_offset:Vector2 = Vector2.ZERO
var _camera_kick_velocity:Vector2 = Vector2.ZERO

@export_group("命中视觉与重击顿挫")
@export var impact_visuals_enabled:bool = true
@export var heavy_hitstop_enabled:bool = true
@export_range(1.0,200.0,1.0) var heavy_hit_min_damage:float = 12.0
@export_range(0.01,0.80,0.01) var heavy_hit_health_ratio:float = 0.06
@export_range(0.20,1.0,0.01) var heavy_hitstop_cooldown:float = 0.35
@export_range(0.01,0.5,0.001) var heavy_hitstop_min_duration:float = 0.025
@export_range(0.01,0.5,0.001) var heavy_hitstop_max_duration:float = 0.090
@export_range(0.05,0.5,0.01) var heavy_hitstop_time_factor:float = 0.12
@export_group("")
var _combat_impact_layer:Node2D = null
var _heavy_hit_pending_strength:float = -1.0
var _heavy_hit_end_usec:int = 0
var _heavy_hit_next_allowed_usec:int = 0
var _heavy_hit_time_key:String = ""
# 分级顿挫：门槛 = max(最低伤害, 生命 × 百分比)。达到门槛轻顿，两倍重顿，
# 四倍或致命一击为暴击档：最长停顿 × 1.8、受击者全白、整屏白闪。震屏仍只走“镜头震动”设置的伤害曲线。
const HITSTOP_CRIT_RATIO:float = 4.0
const HITSTOP_CRIT_SCALE:float = 1.8
const CRIT_FLASH_LAYER:int = 100
const CRIT_FLASH_ALPHA:float = 0.5
const CRIT_FLASH_COOLDOWN:float = 0.45
var _heavy_hit_pending_tier:int = 0
var _heavy_hit_pending_duration:float = 0.0
var _heavy_hit_active_tier:int = 0
var _crit_flash_rect:ColorRect = null
var _crit_flash_tween:Tween = null
var _crit_flash_next_usec:int = 0
# 局部顿帧（设置 Local_Hitstop）：只暂停受击者与攻击者自身的处理，不改全局时间。
var _local_hitstop_entries:Dictionary = {}
var _local_hitstop_cooldowns:Dictionary = {}


func _impact_is_on_screen(origin:Vector2) -> bool:
	var view_position:Vector2 = get_viewport().get_canvas_transform() * origin
	return get_viewport_rect().grow(80.0).has_point(view_position)


func _heavy_hit_threshold(max_health:float) -> float:
	return maxf(heavy_hit_min_damage,maxf(max_health,1.0) * heavy_hit_health_ratio)


func add_confirmed_impact_visual(unit_id:int,origin:Vector2,radius:float,actual_damage:float,max_health:float,blocked:bool) -> bool:
	if not impact_visuals_enabled or not is_finite(actual_damage) or actual_damage <= 0.0:
		return false
	if not is_combat_runtime_active() or not _impact_is_on_screen(origin):
		return false
	if not is_instance_valid(_combat_impact_layer):
		_combat_impact_layer = COMBAT_IMPACT_LAYER_SCRIPT.new()
		_combat_impact_layer.name = "CombatImpactLayer"
		add_child(_combat_impact_layer)
	var strength:float = sqrt(clampf(actual_damage / maxf(max_health * 0.35,24.0),0.0,1.0))
	var heavy:bool = not blocked and actual_damage >= _heavy_hit_threshold(max_health)
	return bool(_combat_impact_layer.call("add_impact",unit_id,origin,radius,strength,heavy,blocked,actual_damage))


func _feedback_number(suffix:String) -> float:
	return FEEDBACK_TUNING.number(Game.Game_Settings,suffix)


func _sync_feedback_settings() -> void:
	damage_shake_max_pixels = _feedback_number("Camera_Max") * _feedback_number("Camera_Gain")
	damage_focus_min_damage = _feedback_number("Focus_Damage")
	damage_focus_health_ratio = _feedback_number("Focus_HealthPercent") / 100.0
	damage_focus_max_threshold = _feedback_number("Focus_ThresholdCap")
	damage_focus_max_zoom = _feedback_number("Focus_MaxZoom")
	damage_focus_cooldown = _feedback_number("Focus_Cooldown")
	heavy_hit_min_damage = _feedback_number("Hitstop_Damage")
	heavy_hit_health_ratio = _feedback_number("Hitstop_HealthPercent") / 100.0
	heavy_hitstop_min_duration = _feedback_number("Hitstop_MinDuration")
	heavy_hitstop_max_duration = _feedback_number("Hitstop_MaxDuration")
	heavy_hitstop_time_factor = _feedback_number("Hitstop_Factor")
	heavy_hitstop_cooldown = _feedback_number("Hitstop_Cooldown")


func _high_damage_feedback_enabled() -> bool:
	return bool(Game.Game_Settings.get("High_Damage_Feedback",true))


func _clear_high_damage_feedback() -> void:
	_damage_focus_pending_strength = -1.0
	_damage_focus_started_usec = 0
	_damage_focus_next_usec = 0
	_damage_focus_weight = 0.0
	_damage_focus_peak_zoom = 1.0
	_heavy_hit_pending_strength = -1.0
	_heavy_hit_pending_tier = 0
	_heavy_hit_pending_duration = 0.0
	_heavy_hit_next_allowed_usec = 0
	_release_heavy_hitstop() # Release only our own lease, never another character's slow motion.
	_release_all_local_hitstop()
	if is_instance_valid(camera_2d): _apply_camera_zoom()


func hitstop_tier(actual_health_damage:float,max_health:float,lethal:bool = false) -> int:
	if not is_finite(actual_health_damage) or actual_health_damage <= 0.0:
		return 0
	# 主角色被击倒的最后一下无论伤害大小都按暴击档定格。
	if lethal:
		return 3
	var threshold:float = _heavy_hit_threshold(max_health)
	if actual_health_damage < threshold:
		return 0
	if actual_health_damage >= threshold * HITSTOP_CRIT_RATIO:
		return 3
	return 2 if actual_health_damage >= threshold * 2.0 else 1


func hitstop_duration(actual_health_damage:float,max_health:float,tier:int) -> float:
	if tier <= 0:
		return 0.0
	if tier >= 3:
		return clampf(heavy_hitstop_max_duration * HITSTOP_CRIT_SCALE,0.01,0.5)
	var ratio:float = actual_health_damage / _heavy_hit_threshold(max_health)
	var weight:float = clampf((ratio - 1.0) / (HITSTOP_CRIT_RATIO - 1.0),0.0,1.0)
	return clampf(lerpf(heavy_hitstop_min_duration,heavy_hitstop_max_duration,weight),0.01,0.5)


## 已确认的攻击命中调用。返回档位：0 不停，1 轻顿，2 重顿，3 暴击/致命。
func request_heavy_hitstop(actual_health_damage:float,max_health:float,origin:Vector2,lethal:bool = false,participants:Array = []) -> int:
	var tier:int = hitstop_tier(actual_health_damage,max_health,lethal)
	if tier == 0 or not origin.is_finite() or not _impact_is_on_screen(origin):
		return 0
	# 击杀只顿帧不闪白；非致命的超大伤害才整屏白闪。
	if tier >= 3 and not lethal:
		_play_crit_flash()
	if not _can_play_heavy_hitstop():
		return tier
	if local_hitstop_enabled():
		_freeze_local_hitstop(participants,hitstop_duration(actual_health_damage,max_health,tier),tier)
		return tier
	var now:int = Time.get_ticks_usec()
	# 冷却与进行中的顿挫只拦普通档；暴击/致命可以插队或延长。
	if tier < 3 and (now < _heavy_hit_next_allowed_usec or _heavy_hit_end_usec > 0):
		return tier
	var duration:float = hitstop_duration(actual_health_damage,max_health,tier)
	if tier > _heavy_hit_pending_tier or (tier == _heavy_hit_pending_tier and duration > _heavy_hit_pending_duration):
		_heavy_hit_pending_tier = tier
		_heavy_hit_pending_duration = duration
	var threshold:float = _heavy_hit_threshold(max_health)
	var strength:float = clampf((actual_health_damage - threshold) / maxf(threshold * 2.0,1.0),0.0,1.0)
	# 不在伤害结算中立刻改时间；同帧群攻只保留最强一次，下一次 always 更新统一消费。
	_heavy_hit_pending_strength = maxf(_heavy_hit_pending_strength,strength)
	return tier


func _play_crit_flash() -> void:
	if not _high_damage_feedback_enabled() or not is_combat_runtime_active() or Game.is_training_mode():
		return
	var now:int = Time.get_ticks_usec()
	if now < _crit_flash_next_usec:
		return
	_crit_flash_next_usec = now + int(CRIT_FLASH_COOLDOWN * 1000000.0)
	if not is_instance_valid(_crit_flash_rect):
		var layer := CanvasLayer.new()
		layer.name = "CritFlashLayer"
		layer.layer = CRIT_FLASH_LAYER
		layer.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(layer)
		_crit_flash_rect = ColorRect.new()
		_crit_flash_rect.name = "CritFlash"
		_crit_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_crit_flash_rect.color = Color.WHITE
		layer.add_child(_crit_flash_rect)
		_crit_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _crit_flash_tween != null and _crit_flash_tween.is_valid():
		_crit_flash_tween.kill()
	_crit_flash_rect.modulate.a = CRIT_FLASH_ALPHA
	_crit_flash_tween = _crit_flash_rect.create_tween()
	_crit_flash_tween.set_ignore_time_scale(true)
	_crit_flash_tween.tween_interval(0.035)
	_crit_flash_tween.tween_property(_crit_flash_rect,"modulate:a",0.0,0.16)


func _can_play_heavy_hitstop() -> bool:
	# 联机不单方面改变物理时钟；训练/高倍速不干扰训练统计与效率。
	# Godot 单机也可能持有 OfflineMultiplayerPeer；不能只用 has_multiplayer_peer 判断联机。
	var offline:bool = Game.network_role == "offline" and (
		not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	return (heavy_hitstop_enabled and _high_damage_feedback_enabled() and offline
		and not Game.is_training_mode() and Game.get_base_game_time_scale() <= 2.0
		and is_combat_runtime_active())


func local_hitstop_enabled() -> bool:
	return bool(Game.Game_Settings.get("Local_Hitstop",false))


func _freeze_local_hitstop(participants:Array,duration:float,tier:int) -> void:
	var now:int = Time.get_ticks_usec()
	var end_usec:int = now + int(maxf(duration,0.0) * 1000000.0)
	for raw:Variant in participants:
		if not raw is Node or not is_instance_valid(raw):
			continue
		var node:Node = raw as Node
		if not node.is_inside_tree() or node.is_queued_for_deletion():
			continue
		var id:int = node.get_instance_id()
		if _local_hitstop_entries.has(id):
			# 冻结中只允许更高档延长，不叠加。
			var entry:Dictionary = _local_hitstop_entries[id]
			if tier > int(entry.tier):
				entry.end = maxi(int(entry.end),end_usec)
				entry.tier = tier
			continue
		if tier < 3 and now < int(_local_hitstop_cooldowns.get(id,0)):
			continue
		if node.process_mode == Node.PROCESS_MODE_DISABLED:
			continue
		# DISABLED 默认会把碰撞体移出物理世界；冻结期间保持碰撞/受击判定，只停自身处理。
		var collision_objects:Array = []
		_collect_collision_objects(node,collision_objects)
		var collision_modes:Array = []
		for body:CollisionObject2D in collision_objects:
			collision_modes.append([weakref(body),body.disable_mode])
			body.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
		_local_hitstop_entries[id] = {"ref":weakref(node),"end":end_usec,"tier":tier,"mode":node.process_mode,"collision":collision_modes}
		_local_hitstop_cooldowns[id] = now + int(maxf(heavy_hitstop_cooldown,0.0) * 1000000.0)
		node.process_mode = Node.PROCESS_MODE_DISABLED


func _collect_collision_objects(node:Node,result:Array) -> void:
	if node is CollisionObject2D:
		result.append(node)
	for child:Node in node.get_children():
		_collect_collision_objects(child,result)


func is_local_hitstop_frozen(node:Node) -> bool:
	return is_instance_valid(node) and _local_hitstop_entries.has(node.get_instance_id())


func _update_local_hitstop() -> void:
	var now:int = Time.get_ticks_usec()
	if _local_hitstop_entries.is_empty():
		for id:Variant in _local_hitstop_cooldowns.keys():
			if now >= int(_local_hitstop_cooldowns[id]): _local_hitstop_cooldowns.erase(id)
		return
	var release_all:bool = not _can_play_heavy_hitstop() or not local_hitstop_enabled()
	for id:Variant in _local_hitstop_entries.keys():
		var entry:Dictionary = _local_hitstop_entries[id]
		if release_all or now >= int(entry.end):
			_release_local_hitstop_entry(entry)
			_local_hitstop_entries.erase(id)


func _release_local_hitstop_entry(entry:Dictionary) -> void:
	var node:Node = (entry.ref as WeakRef).get_ref() as Node
	# 期间别的系统改过 process_mode 就不覆盖它。
	if is_instance_valid(node) and node.process_mode == Node.PROCESS_MODE_DISABLED:
		node.process_mode = int(entry.mode)
	for pair:Array in entry.get("collision",[]):
		var body:CollisionObject2D = (pair[0] as WeakRef).get_ref() as CollisionObject2D
		if is_instance_valid(body) and body.disable_mode == CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE:
			body.disable_mode = int(pair[1])


func _release_all_local_hitstop() -> void:
	for id:Variant in _local_hitstop_entries.keys():
		_release_local_hitstop_entry(_local_hitstop_entries[id])
	_local_hitstop_entries.clear()
	_local_hitstop_cooldowns.clear()


func _release_heavy_hitstop() -> void:
	if not _heavy_hit_time_key.is_empty():
		Game.release_time_scale_override(_heavy_hit_time_key)
	_heavy_hit_time_key = ""
	_heavy_hit_end_usec = 0
	_heavy_hit_active_tier = 0


func _update_heavy_hitstop() -> void:
	var now:int = Time.get_ticks_usec()
	# Game 的 always 更新在菜单暂停时仍运行；按真实时间回收，不会被自身 0.12x 困住。
	if _heavy_hit_end_usec > 0 and (now >= _heavy_hit_end_usec or not _can_play_heavy_hitstop()):
		_release_heavy_hitstop()
	var strength:float = _heavy_hit_pending_strength
	var tier:int = _heavy_hit_pending_tier
	var duration:float = _heavy_hit_pending_duration
	_heavy_hit_pending_strength = -1.0
	_heavy_hit_pending_tier = 0
	_heavy_hit_pending_duration = 0.0
	if strength < 0.0 or tier <= 0 or not _can_play_heavy_hitstop():
		return
	if _heavy_hit_end_usec > 0:
		# 顿挫中只允许更高档延长（如轻顿中接上致命一击），不叠加。
		if tier > _heavy_hit_active_tier:
			_heavy_hit_end_usec = maxi(_heavy_hit_end_usec,now + int(duration * 1000000.0))
			_heavy_hit_active_tier = tier
		return
	if tier < 3 and now < _heavy_hit_next_allowed_usec:
		return
	if Game.get_time_scale_override_factor() < 0.95:
		return
	# 不覆盖已有角色慢动作/电影镜头。只注册自己的 key，释放时由 Game 重算玩家基础倍速。
	_heavy_hit_end_usec = now + int(duration * 1000000.0)
	_heavy_hit_next_allowed_usec = now + int(maxf(heavy_hitstop_cooldown,0.0) * 1000000.0)
	_heavy_hit_active_tier = tier
	_heavy_hit_time_key = "WorldHeavyHit_%d" % get_instance_id()
	# 只冻结画面与物理；命中音照常播完，不被慢速拖成闷响。
	Game.request_time_scale_override(_heavy_hit_time_key,heavy_hitstop_time_factor,Color(0.0,0.0,0.0,0.0),false)


@export_group("大伤害定点推镜")
@export var damage_focus_enabled:bool = true
@export_range(1.0,500.0,1.0) var damage_focus_min_damage:float = 40.0
@export_range(0.05,1.0,0.01) var damage_focus_health_ratio:float = 0.25
@export_range(1.0,500.0,1.0) var damage_focus_max_threshold:float = 75.0
@export_range(1.02,1.40,0.01) var damage_focus_max_zoom:float = 1.18
@export_range(0.3,2.0,0.05) var damage_focus_cooldown:float = 0.70
@export_group("")
var _damage_focus_anchor:Vector2 = Vector2.ZERO
var _damage_focus_pending_position:Vector2 = Vector2.ZERO
var _damage_focus_pending_strength:float = -1.0
var _damage_focus_weight:float = 0.0
var _damage_focus_peak_zoom:float = 1.0
var _damage_focus_started_usec:int = 0
var _damage_focus_next_usec:int = 0


func request_damage_focus(damage:float,reference_health:float,impact_position:Vector2) -> void:
	# A boss's large HP pool must not raise the hit threshold without bound:
	# a confirmed 100-damage hit is still a strong hit on a 1000-HP target.
	var relative_threshold:float = maxf(damage_focus_min_damage,reference_health * damage_focus_health_ratio)
	var threshold:float = minf(relative_threshold,maxf(damage_focus_max_threshold,damage_focus_min_damage))
	if not damage_focus_enabled or not _high_damage_feedback_enabled() or not is_finite(damage) or damage < threshold:
		return
	if not impact_position.is_finite() or not is_combat_runtime_active() or not _impact_is_on_screen(impact_position):
		return
	if _dead_save_force_non_follow_camera or _cinematic_focus_weight > 0.01 or not _cinematic_focus_requests.is_empty():
		return
	if Time.get_ticks_usec() < _damage_focus_next_usec or _damage_focus_started_usec > 0:
		return
	var strength:float = clampf((damage - threshold) / maxf(threshold * 2.0,1.0),0.0,1.0)
	# 同帧选最强命中，不对多个目标求平均，也不在推镜中来回换目标。
	if strength > _damage_focus_pending_strength:
		_damage_focus_pending_strength = strength
		_damage_focus_pending_position = impact_position


func _update_damage_focus() -> void:
	if not damage_focus_enabled or not _high_damage_feedback_enabled() or not is_combat_runtime_active() or _dead_save_force_non_follow_camera or _cinematic_focus_weight > 0.01 or not _cinematic_focus_requests.is_empty():
		_damage_focus_weight = 0.0
		_damage_focus_started_usec = 0
		_damage_focus_pending_strength = -1.0
		return
	var now:int = Time.get_ticks_usec()
	if _damage_focus_pending_strength >= 0.0 and _damage_focus_started_usec == 0 and now >= _damage_focus_next_usec:
		_damage_focus_anchor = _damage_focus_pending_position
		var maximum_zoom:float = clampf(damage_focus_max_zoom,1.0,2.0)
		_damage_focus_peak_zoom = lerpf(minf(_feedback_number("Focus_MinZoom"),maximum_zoom),maximum_zoom,_damage_focus_pending_strength)
		_damage_focus_started_usec = now
		_damage_focus_next_usec = now + int(maxf(damage_focus_cooldown,0.0) * 1000000.0)
	_damage_focus_pending_strength = -1.0
	if _damage_focus_started_usec == 0:
		_damage_focus_weight = 0.0
		return
	var age:float = float(now - _damage_focus_started_usec) * 0.000001
	var ease_in:float = _feedback_number("Focus_In")
	var hold_end:float = ease_in + _feedback_number("Focus_Hold")
	var end:float = hold_end + _feedback_number("Focus_Out")
	if age < ease_in:
		_damage_focus_weight = smoothstep(0.0,ease_in,age)
	elif age < hold_end:
		_damage_focus_weight = 1.0
	else:
		_damage_focus_weight = 1.0 - smoothstep(hold_end,end,age)
	if age >= end:
		_damage_focus_weight = 0.0
		_damage_focus_started_usec = 0


func add_damage_camera_shake(actual_damage:float) -> void:
	if not is_finite(actual_damage) or actual_damage <= 0.0:
		return
	if not Game.Game_Settings.Shaking_Camera or not is_combat_runtime_active():
		return
	var pixels:float = FEEDBACK_TUNING.amplitude(actual_damage,Game.Game_Settings,"Camera") * maxf(damage_shake_strength,0.0)
	if pixels >= _damage_shake_pending_peak:
		_damage_shake_pending_duration = FEEDBACK_TUNING.duration(actual_damage,Game.Game_Settings)
	_damage_shake_pending_peak = maxf(_damage_shake_pending_peak,pixels)
	_damage_shake_pending_sum = minf(_damage_shake_pending_sum + pixels,damage_shake_max_pixels * 8.0)


func add_directional_camera_kick(direction:Vector2,actual_damage:float,origin:Vector2) -> void:
	if not is_finite(actual_damage) or actual_damage <= 0.0 or not direction.is_finite() or direction.length_squared() <= 0.000001:
		return
	if not Game.Game_Settings.Shaking_Camera or not is_combat_runtime_active():
		return
	if not origin.is_finite() or not _impact_is_on_screen(origin):
		return
	var pixels:float = FEEDBACK_TUNING.amplitude(actual_damage,Game.Game_Settings,"Camera") * maxf(damage_shake_strength,0.0) * CAMERA_KICK_GAIN
	# 同帧多次命中只取最强一次的方向，不累加越级。
	if pixels > _camera_kick_pending.length():
		_camera_kick_pending = direction.normalized() * pixels


func _clear_camera_kick() -> void:
	_camera_kick_pending = Vector2.ZERO
	_camera_kick_offset = Vector2.ZERO
	_camera_kick_velocity = Vector2.ZERO


## 返回本帧推镜偏移（视口像素）。画面内容沿击退方向移动，所以相机偏移取反方向。
func _advance_camera_kick(delta:float) -> Vector2:
	var omega:float = CAMERA_KICK_FREQUENCY
	if _camera_kick_pending.length_squared() > 0.0:
		var velocity_cap:float = maxf(damage_shake_max_pixels,0.0) * omega / CAMERA_KICK_PEAK_FACTOR
		_camera_kick_velocity = (_camera_kick_velocity - _camera_kick_pending * omega / CAMERA_KICK_PEAK_FACTOR).limit_length(velocity_cap)
		_camera_kick_pending = Vector2.ZERO
	if _camera_kick_offset.length_squared() <= 0.0 and _camera_kick_velocity.length_squared() <= 0.0:
		return Vector2.ZERO
	var remaining:float = clampf(delta,0.0,0.25)
	while remaining > 0.0:
		var step:float = minf(remaining,1.0 / 240.0)
		_camera_kick_velocity += (-omega * omega * _camera_kick_offset - 2.0 * CAMERA_KICK_DAMPING_RATIO * omega * _camera_kick_velocity) * step
		_camera_kick_offset += _camera_kick_velocity * step
		remaining -= step
	if _camera_kick_offset.length() < 0.01 and _camera_kick_velocity.length() < 0.5:
		_clear_camera_kick()
	return _camera_kick_offset


func _update_damage_camera_shake(delta:float) -> void:
	if not Game.Game_Settings.Shaking_Camera:
		camera_shake_amount = 0.0
		_damage_shake_pending_peak = 0.0
		_damage_shake_pending_sum = 0.0
		_damage_shake_pixels = 0.0
		_damage_shake_time_left = 0.0
		_clear_camera_kick()
		camera_2d.offset = Vector2.ZERO
		return
	if _damage_shake_pending_peak > 0.0:
		# Same-frame crowds retain the strongest hit; small hits never stack into a higher tier.
		var impulse:float = _damage_shake_pending_peak
		# 弱小 DOT 不延长尚未结束的重击；达到当前衰减强度才刷新包络。
		if impulse >= _damage_shake_pixels:
			# 连续命中时保持相位推进，否则每帧重置会把震动锁成单向偏移。
			if _damage_shake_time_left <= 0.0:
				_damage_shake_elapsed = 0.0
			_damage_shake_pixels = impulse
			_damage_shake_duration = _damage_shake_pending_duration
			_damage_shake_time_left = _damage_shake_duration
	_damage_shake_pending_peak = 0.0
	_damage_shake_pending_sum = 0.0
	# Skill-authored impulses share the visible strong control instead of masking its changes.
	var legacy_gain:float = _feedback_number("Body_Strong") / float(FEEDBACK_TUNING.SPECS.Feedback_Body_Strong.default)
	var legacy_pixels:float = maxf(camera_shake_amount * shake_rate,0.0) * _feedback_number("Camera_Gain") * legacy_gain
	var amplitude:float = maxf(_damage_shake_pixels,legacy_pixels)
	# 双向、零中心衰减振荡；不占用战斗 RNG，不影响命中/AI 的随机序列。
	var screen_offset:Vector2 = Vector2.ZERO
	if amplitude > 0.001:
		var phase:float = _damage_shake_elapsed * TAU * _feedback_number("Shake_Frequency")
		screen_offset = Vector2(cos(phase),sin(phase * 1.31 + 0.7)) * amplitude
	screen_offset += _advance_camera_kick(delta)
	if screen_offset.length_squared() > 0.0:
		camera_2d.offset = screen_offset / Vector2(maxf(absf(camera_2d.zoom.x),0.001),maxf(absf(camera_2d.zoom.y),0.001))
	else:
		camera_2d.offset = Vector2.ZERO
	var safe_delta:float = maxf(delta,0.0)
	_damage_shake_elapsed += safe_delta
	_damage_shake_time_left = maxf(_damage_shake_time_left - safe_delta,0.0)
	# 按剩余时间作线性衰减，避免单位越多震动越快消失。
	if _damage_shake_time_left <= 0.0:
		_damage_shake_pixels = 0.0
	else:
		_damage_shake_pixels *= _damage_shake_time_left / (_damage_shake_time_left + safe_delta)
	camera_shake_amount = move_toward(camera_shake_amount,0.0,maxf(shake_restore,0.0) * safe_delta)

#辅助删除
func free_node_after_time(time:float,node:Node) -> void:
	await get_tree().create_timer(time).timeout
	
	Game.free_node(node)
func free_node_after_tween(params:Dictionary) -> void:
	var tween:Tween = create_tween()
	tween.tween_property(params.node,params.property,params.value,params.time)
	
	await tween.finished
	params.node.queue_free()
	

#========================================================
# 战斗文字 Canvas 可见层
#========================================================
# 普通世界元素使用默认 bit 1；顶部 VS / 互动文字 / 训练 HUD 放在 bit 2。
# 旧“未完成”录制/回放系统已经删除，但这些显示层仍被正式战斗 UI 使用。
const COMBAT_TEXT_VISIBILITY_LAYER:int = 2

#========================================================
# V9 性能 / 重打
#========================================================
# 顶部 VS/互动文字无需每一帧重新扫描全场角色。
@export_range(0.05, 1.0, 0.05) var top_text_refresh_interval:float = 0.20
# Nearest_Enemy 原版是每个物理帧 O(n²) 扫描；10Hz 足够角色转向，同时大幅减少多人战 CPU。
@export_range(0.05, 0.5, 0.05) var nearest_enemy_refresh_interval:float = 0.10
# 功能：角色通用 housekeeping（随机移动方向、血条层级、阵营着色）无需跟渲染帧同频。
@export_range(0.02, 0.25, 0.01) var unit_housekeeping_refresh_interval:float = 0.05
# 功能：地图挤回/越界检查不是命中判定，20Hz 足以响应，同时避免每物理帧重复扫描全场。
@export_range(0.02, 0.25, 0.01) var map_rule_refresh_interval:float = 0.05

@export_category("大规模战斗性能")
# 达到该数量后自动把角色↔角色实体碰撞切换为“空间网格软分离”，墙体/Hitbox/Hurtbox 不变。
@export var large_battle_optimization_enabled:bool = true
# V79 性能修复：从 64 降到 40，确保 50~100 人单人对局也能及时进入轻量模式，
# 避免 64 单位以下全部进行完整角色身体碰撞导致明显卡顿。
@export_range(20,300,1) var large_battle_unit_threshold:int = 40
# 低于该数量才退出，形成迟滞区间，避免单位在阈值附近死亡/生成时反复切换物理模式。
# V79：对应从 52 降到 30，保持迟滞区间比例。
@export_range(10,280,1) var large_battle_disable_below:int = 30
# 网格应略大于普通角色世界碰撞直径；只比较自身格与相邻八格。
@export_range(24.0,128.0,2.0) var large_battle_grid_cell_size:float = 48.0
@export_range(0.0,12.0,0.5) var large_battle_separation_margin:float = 2.0
# overlap × response 得到分离速度，并由 max_speed 封顶。
@export_range(1.0,30.0,0.5) var large_battle_separation_response:float = 12.0
@export_range(40.0,500.0,5.0) var large_battle_separation_max_speed:float = 220.0
@export var large_battle_print_monitor:bool = false
# V105：软分离不需要 60Hz 重建邻居对；默认 30Hz，角色真实 move_and_slide/攻击仍是 60Hz。
@export_range(0.016,0.10,0.001) var large_battle_separation_refresh_interval:float = 0.033
# V106：空间网格只需要服务 30Hz 软分离与 10Hz 索敌，不再 60Hz 重建 Dictionary。
@export_range(0.016,0.10,0.001) var large_battle_spatial_refresh_interval:float = 0.033
# 事件注册是主路径；低频重扫仅用于兼容极少数没有走 ball._ready() 的旧派生脚本。
@export_range(0.25,2.0,0.05) var battle_registry_resync_interval:float = 0.75
var _large_battle_mode_active:bool = false
var _large_battle_monitor_elapsed:float = 0.0
# V420 性能：is_combat_runtime_active() 每个 physics tick 被每个单位/Hitbox/投射物调用数百次，
# 而“是否还有存活主战角色”在同一个 physics tick 内不会变。按 physics frame 缓存一次，
# 单位死亡/注册/删除会把缓存打脏，语义与 _has_alive_primary_battle_character() 完全一致。
var _alive_primary_cache_frame:int = -1
var _alive_primary_cache_value:bool = false
# V420 性能：胜负铃判定要遍历全部单位并逐个解析阵营 key（100 人时约 0.6ms/tick）。
# 改为 ~20Hz 轮询；胜利提示最多延后 50ms，肉眼不可感知。铃声本身仍只触发一次。
var _victory_bell_poll_elapsed:float = 0.0
const VICTORY_BELL_POLL_INTERVAL:float = 0.05
var _large_battle_separation_elapsed:float = 999.0
var _battle_spatial_elapsed:float = 999.0
var _battle_registry_resync_elapsed:float = 999.0
var _battle_registry_dirty:bool = true

# V106：战斗单位改为 ball 入树/离树时注册。避免 World 每个 physics tick 调 get_nodes_in_group()
# 并重新分配整张单位数组；缓存自身就是权威列表，渲染帧/物理帧共同复用。
var _battle_units_cache:Array = []
var _battle_unit_ids:Dictionary = {}
# V411：复用 Buff 筛选/删除临时数组，避免 60Hz 持续制造短命 Array。
var _buffed_group_scratch:Array = []
var _buff_delete_scratch:Array = []
# 关闭阵营自动着色时，绝大多数时间没有任何颜色需要恢复；避免 20Hz 空扫全体人物。
var _team_auto_colors_applied:bool = false
var _battle_spatial_grid:Dictionary = {}
var _battle_spatial_active_cells:Array[Vector2i] = []
var _battle_spatial_positions:Array[Vector2] = []
var _battle_spatial_radii:Array[float] = []
var _battle_spatial_pushes:Array[Vector2] = []
var _battle_spatial_has_units:bool = false
var _battle_spatial_min_cell:Vector2i = Vector2i.ZERO
var _battle_spatial_max_cell:Vector2i = Vector2i.ZERO
# 相机中心也跟空间网格一起低频汇总，避免 render frame 再 O(N) 扫全场。
var _battle_primary_center:Vector2 = Vector2.ZERO
var _battle_primary_count:int = 0

var _top_text_refresh_elapsed:float = 0.0
# 功能：最近敌人采用“分帧预算”，每个单位平均仍按 nearest_enemy_refresh_interval 更新，但不在同一帧做完 O(N²)。
var _nearest_enemy_refresh_cursor:int = 0
var _nearest_enemy_update_budget:float = 0.0
var _unit_housekeeping_elapsed:float = 999.0
var _map_rule_refresh_elapsed:float = 999.0
var _map_rule_accumulated_delta:float = 0.0
var _fps_refresh_elapsed:float = 0.0

# “重打”保存的是创建那一刻的规则数据，而不是战斗结束时已经移动过的位置。
var _battle_setup:Array[Dictionary] = []
var _last_battle_setup:Array[Dictionary] = []
var _battle_setup_map:String = ""
var _last_battle_setup_map:String = ""
var _battle_random_seed:int = 0
var _last_battle_random_seed:int = 0
var _restoring_battle_setup:bool = false
var _battle_setup_next_id:int = 1

# 手动/普通战斗胜利铃：先见到至少两个阵营才“武装”，只剩一个阵营时响一次。
# 阵营计算包含 Ball/Creature 型附属，但不把子弹等 Shooter 算成独立阵营。
var _victory_bell_armed:bool = false
var _victory_bell_played:bool = false
## 本场开战钟声已敲过；和胜利铃一起重置（新一局 / 轮换下一场 / 手动模式新对手）。
var _battle_start_bell_played:bool = false
## 开场镜头：开战时视角先贴近双方，再先快后慢地拉远回正常视角。
## 0 空闲 / 1 门后预备（停在近景等开战）/ 2 播放中。录像构图读 _intro_camera_weight 跟着走。
const INTRO_CAMERA_PUNCH_SECONDS:float = 0.12
const INTRO_CAMERA_PULL_SECONDS:float = 1.15
const INTRO_CAMERA_MAX_ZOOM:float = 1.6
const INTRO_CAMERA_MIN_ZOOM:float = 1.3
var _intro_camera_state:int = 0
var _intro_camera_age:float = 0.0
var _intro_camera_peak:float = 1.0
var _intro_camera_anchor:Vector2 = Vector2.ZERO
var _intro_camera_weight:float = 0.0
var _victory_encounter_limited:bool = false
var _victory_encounter_setup_ids:Dictionary = {}
# V434 性能：网格重建时顺带整理一份“当前可被索敌的人物”快照（仍在 Ball 组、is_combat_targetable()）。
# 投稿角色工具 / MC 生物等公共索敌助手每次查询不再遍历 SceneTree 整个 Ball 组
# （其中大半是投射物、死亡单位），候选数从 ~250 降到真正存活的人物数；
# 助手仍对每个候选逐个做实时 is_combat_targetable/阵营判断，结果与全量扫描一致。
var _battle_targetable_units:Array = []
var _victory_bell_sequence_generation:int = 0

#========================================================
# 训练模式 V2：自然死亡后单体复活
#========================================================
@export_range(0.1,10.0,0.1) var training_respawn_delay:float = 1.0
var _training_respawn_pending:Dictionary = {}


func _apply_mojangles_rich_text_fonts(label:RichTextLabel) -> void:
	if label == null:
		return
	for font_name in [&"normal_font", &"bold_font", &"italics_font", &"bold_italics_font", &"mono_font"]:
		label.add_theme_font_override(font_name, MOJANGLES_FONT)


func _is_center_watermark_enabled() -> bool:
	# 设置开关已删除。旧存档里的 false 不能再隐藏水印。
	return true


func _get_center_watermark_map_rect() -> Rect2:
	var map_node:Node = _current_map_node()
	if map_node == null:
		return Rect2()
	return return_map_visual_rect(map_node)


func _refresh_center_watermark_layout(map_rect:Rect2 = Rect2()) -> void:
	if not is_instance_valid(_center_watermark_root) or not is_instance_valid(_center_watermark_row):
		return
	if map_rect.size.x <= 0.0 or map_rect.size.y <= 0.0:
		map_rect = _get_center_watermark_map_rect()
	if map_rect.size.x <= 0.0 or map_rect.size.y <= 0.0:
		_center_watermark_root.visible = false
		return

	_center_watermark_root.visible = true

	var base_size:Vector2 = _center_watermark_row.get_combined_minimum_size()
	if base_size.x <= 0.0 or base_size.y <= 0.0:
		call_deferred("_refresh_center_watermark_layout",map_rect)
		return
	_center_watermark_row.size = base_size
	_center_watermark_row.position = -base_size * 0.5
	var content_width:float = base_size.x
	if is_instance_valid(_center_watermark_follow):
		var follow_size:Vector2 = _center_watermark_follow.get_minimum_size()
		if follow_size.x > 1.0 and follow_size.y > 1.0:
			_center_watermark_follow.size = follow_size
			_center_watermark_follow.position = Vector2(-follow_size.x * 0.5,_center_watermark_row.position.y + base_size.y + 4.0)
			content_width = maxf(content_width,follow_size.x)
	if is_instance_valid(_dead_save_watermark_name):
		_dead_save_watermark_name.position = -base_size * 0.5
		_dead_save_watermark_name.size = base_size

	var width_ratio:float = center_watermark_map_width_ratio
	if not str(Game.current_locale).begins_with("zh"):
		width_ratio = center_watermark_english_map_width_ratio
	var scale_by_width:float = (map_rect.size.x * maxf(width_ratio,0.001)) / content_width
	var scale_by_height:float = (map_rect.size.y * maxf(center_watermark_map_height_ratio,0.001)) / base_size.y
	var uniform_scale:float = clampf(minf(scale_by_width,scale_by_height),0.001,1.0)
	_center_watermark_root.scale = Vector2.ONE * uniform_scale

	# 水印放到地图黑框正下方并水平居中。Root 的中心点再补半个文字高度，
	# 因而 bottom_gap 表示“地图底边 -> 文字上缘”的真实间距。
	var map_bottom:float = map_rect.position.y + map_rect.size.y
	var scaled_half_height:float = base_size.y * uniform_scale * 0.5
	if Game.is_rotation_training_mode() and not _armor_stand_test_hud_active and not _dead_save_ui_override_active and not (_development != null and _development.is_prebattle()) and map_group.has(now_choose_map):
		# Keep existing watermark text below the new red frame row, not behind it.
		var frame_cell:Vector2 = map_visual_cell_size(map_group[now_choose_map])
		map_bottom += minf(frame_cell.x,frame_cell.y)*1.22
	_center_watermark_root.global_position = Vector2(
		map_rect.get_center().x,
		map_bottom + center_watermark_bottom_gap + scaled_half_height
	)


func _setup_center_watermark() -> void:
	if is_instance_valid(_center_watermark_root):
		_ensure_center_watermark_follow()
		_refresh_center_watermark()
		return

	# 水印直接使用 World 世界坐标，所以会跟地图一起缩放/移动。
	# 因为它位于地图外侧，Z 必须高于地图外裁剪遮罩(90)，否则会被遮掉。
	_center_watermark_root = Control.new()
	_center_watermark_root.name = "BottomCenterWatermark"
	_center_watermark_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_watermark_root.z_as_relative = true
	_center_watermark_root.z_index = 98
	add_child(_center_watermark_root)

	_center_watermark_row = HBoxContainer.new()
	_center_watermark_row.name = "WatermarkTextRow"
	_center_watermark_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_watermark_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_center_watermark_row.modulate.a = clampf(center_watermark_opacity,0.0,1.0)
	_center_watermark_root.add_child(_center_watermark_row)

	_center_watermark_name = Label.new()
	_center_watermark_name.name = "CreatorName"
	_center_watermark_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_watermark_name.add_theme_font_size_override("font_size",center_watermark_font_size)
	_center_watermark_name.add_theme_color_override("font_color",Color.WHITE)
	_center_watermark_name.add_theme_color_override("font_outline_color",Color(0.0,0.0,0.0,0.82))
	_center_watermark_name.add_theme_constant_override("outline_size",4)
	_center_watermark_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_watermark_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_center_watermark_row.add_child(_center_watermark_name)

	# 死档名称单独用 RichTextLabel，才能使用和“重女文字”同节奏的逐 glyph 位移+旋转。
	# 普通水印 Label 仍保留在 HBox 中负责稳定测量尺寸；死档时只把它透明，不改变布局。
	_dead_save_watermark_name = RichTextLabel.new()
	_dead_save_watermark_name.name = "DeadSaveSatellaName"
	_apply_mojangles_rich_text_fonts(_dead_save_watermark_name)
	_dead_save_watermark_name.bbcode_enabled = true
	_dead_save_watermark_name.fit_content = false
	_dead_save_watermark_name.scroll_active = false
	_dead_save_watermark_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dead_save_watermark_name.clip_contents = false
	_dead_save_watermark_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	_dead_save_watermark_name.add_theme_font_size_override("normal_font_size",center_watermark_font_size)
	_dead_save_watermark_name.add_theme_font_size_override("bold_font_size",center_watermark_font_size)
	_dead_save_watermark_name.add_theme_color_override("default_color",Color(1.0,0.08,0.10,1.0))
	_dead_save_watermark_name.add_theme_color_override("font_outline_color",Color(0.0,0.0,0.0,0.82))
	_dead_save_watermark_name.add_theme_constant_override("outline_size",4)
	_dead_save_watermark_name.process_mode = Node.PROCESS_MODE_ALWAYS
	_dead_save_watermark_name.visible = false
	_dead_save_watermark_name.install_effect(HEAVY_GIRL_GLYPH_SHAKE_EFFECT.new())
	_center_watermark_root.add_child(_dead_save_watermark_name)

	_ensure_center_watermark_follow()
	_refresh_center_watermark()
	call_deferred("_refresh_center_watermark_layout")


func _ensure_center_watermark_follow() -> void:
	if is_instance_valid(_center_watermark_follow) or not is_instance_valid(_center_watermark_root):
		return
	_center_watermark_follow = Label.new()
	_center_watermark_follow.name = "WatermarkFollow"
	_center_watermark_follow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_watermark_follow.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_center_watermark_follow.add_theme_font_size_override("font_size",center_watermark_font_size)
	_center_watermark_follow.add_theme_color_override("font_color",Color.WHITE)
	_center_watermark_follow.add_theme_color_override("font_outline_color",Color(0.0,0.0,0.0,0.82))
	_center_watermark_follow.add_theme_constant_override("outline_size",4)
	_center_watermark_follow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_watermark_follow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_center_watermark_root.add_child(_center_watermark_follow)


func _refresh_center_watermark() -> void:
	if not is_instance_valid(_center_watermark_row):
		return
	if is_instance_valid(_center_watermark_root):
		_center_watermark_root.visible = true
	var chinese_mode:bool = str(Game.current_locale).begins_with("zh")
	if is_instance_valid(_center_watermark_name):
		if _dead_save_ui_override_active:
			# 保留正常 Label 的字宽作为布局基准，但实际绘制交给逐字颤抖 RichTextLabel。
			_center_watermark_name.text = DEAD_SAVE_WATERMARK_TEXT
			_center_watermark_name.modulate.a = 0.0
		else:
			_center_watermark_name.text = _development.time_text() if _development != null and _development.is_prebattle() else ("@丁某人睡觉" if chinese_mode else "@Gameking")
			_center_watermark_name.modulate.a = 1.0
			_center_watermark_name.add_theme_color_override("font_color",Color.WHITE)
	if is_instance_valid(_center_watermark_follow):
		_center_watermark_follow.text = Game.t("点赞加关注！")
		_center_watermark_follow.modulate.a = clampf(center_watermark_opacity,0.0,1.0)
		_center_watermark_follow.visible = not _dead_save_ui_override_active and not (_development != null and _development.is_prebattle())
	if is_instance_valid(_dead_save_watermark_name):
		_dead_save_watermark_name.visible = _dead_save_ui_override_active
		_dead_save_watermark_name.modulate.a = clampf(center_watermark_opacity,0.0,1.0)
		if _dead_save_ui_override_active:
			var dead_save_name_markup:String = "[center][color=#FF141A][b][heavy_girl_jitter]" + escape_bbcode(DEAD_SAVE_WATERMARK_TEXT) + "[/heavy_girl_jitter][/b][/color][/center]"
			if _dead_save_watermark_name.text != dead_save_name_markup:
				_dead_save_watermark_name.text = dead_save_name_markup
	_center_watermark_row.modulate.a = clampf(center_watermark_opacity,0.0,1.0)
	_refresh_center_watermark_layout()


func set_dead_save_camera_follow_override(active:bool) -> void:
	# V405：只覆盖运行时相机分支，不写回 Camera_Move / Follow_Controlled_Character。
	# 死档结束/换局后会自然恢复玩家原本的两套跟随设置。
	_dead_save_force_non_follow_camera = active


func set_dead_save_ui_override(active:bool) -> void:
	_dead_save_ui_override_active = active
	if active:
		if is_instance_valid(versus_label):
			# SceneTree 在莎缇拉演出时暂停；设为 ALWAYS 才能让逐字颤抖继续播放。
			versus_label.process_mode = Node.PROCESS_MODE_ALWAYS
		_apply_dead_save_ui_override()
	else:
		if is_instance_valid(versus_label):
			versus_label.process_mode = Node.PROCESS_MODE_INHERIT
		if is_instance_valid(_dead_save_watermark_name):
			_dead_save_watermark_name.visible = false
		if is_instance_valid(_center_watermark_name):
			_center_watermark_name.modulate.a = 1.0
		_dead_save_love_text = ""
		_last_versus_text = ""
		_refresh_center_watermark()
		refresh_versus_text()


func set_dead_save_love_text(value:String) -> void:
	_dead_save_love_text = value
	if _dead_save_ui_override_active:
		_apply_dead_save_ui_override()


func _apply_dead_save_ui_override() -> void:
	if not _dead_save_ui_override_active:
		return
	if is_instance_valid(rotation_versus_root):
		rotation_versus_root.visible = false
	if is_instance_valid(interaction_label):
		interaction_label.visible = false
		interaction_label.text = ""
		interaction_label.size.y = 0.0
	if is_instance_valid(versus_label):
		versus_label.visible = true
		var dead_save_text:String = _dead_save_love_text
		# V392：不再使用 Godot 内建 shake；改用与重女文字同参数的逐 glyph 离散位移+旋转。
		var dead_save_markup:String = "[center][color=#FF141A][b][heavy_girl_jitter]" + escape_bbcode(dead_save_text) + "[/heavy_girl_jitter][/b][/color][/center]"
		if versus_label.text != dead_save_markup:
			versus_label.text = dead_save_markup
		versus_label.add_theme_font_size_override("normal_font_size",versus_font_max_size)
		versus_label.add_theme_font_size_override("bold_font_size",versus_font_max_size)
		_last_versus_text = "__dead_save_aishiteru__"
		refresh_top_text_layout()
	if is_instance_valid(_center_watermark_root):
		_center_watermark_root.visible = true
	if is_instance_valid(_center_watermark_name):
		_center_watermark_name.text = DEAD_SAVE_WATERMARK_TEXT
		_center_watermark_name.modulate.a = 0.0
	if is_instance_valid(_center_watermark_follow):
		_center_watermark_follow.visible = false
	if is_instance_valid(_dead_save_watermark_name):
		_dead_save_watermark_name.visible = true
		_dead_save_watermark_name.modulate.a = clampf(center_watermark_opacity,0.0,1.0)
		var dead_save_name_markup:String = "[center][color=#FF141A][b][heavy_girl_jitter]" + escape_bbcode(DEAD_SAVE_WATERMARK_TEXT) + "[/heavy_girl_jitter][/b][/color][/center]"
		if _dead_save_watermark_name.text != dead_save_name_markup:
			_dead_save_watermark_name.text = dead_save_name_markup
	_refresh_center_watermark_layout()


var day_night_cycle:Node2D
var minecraft_clouds:Node2D
var battle_conditions:Node2D
var _mc_prewarmer:Node
var _mc_placement_generation:int = 0
var _mc_pending_placements:Array[int] = []
var _mc_next_placement:int = 0

func _ready() -> void:
	_sync_feedback_settings()
	_mc_prewarmer = load("res://scripts/effects/我的世界/mc_native_prewarm.gd").new()
	_mc_prewarmer.name = "MinecraftResourcePreparation"
	add_child(_mc_prewarmer)
	# 门通道必须在角色本帧 move_and_slide() 之前更新碰撞 mask。
	# Godot 对更低的 process_physics_priority 先执行，所以 World 提前处理。
	process_physics_priority = -100
	randomize()
	
	for c in get_children():
		if c is TileMapLayer or c is PortalMap:
			map_group[c.name] = c

	# 创建黑色地图边框和 VS 标题；随机互动文字已删除。
	setup_map_presentation()
	day_night_cycle = load("res://scripts/day_night_cycle.gd").new(self)
	day_night_cycle.name = "DayNightCycle"
	add_child(day_night_cycle)
	minecraft_clouds = load("res://scripts/effects/我的世界/minecraft_clouds.gd").new(self)
	minecraft_clouds.name = "MinecraftClouds"
	add_child(minecraft_clouds)
	load("res://scripts/effects/motion_blur.gd").attach(self,get_viewport())
	_setup_center_watermark()
	setup_manual_training_controller()
	setup_combat_threat_analyzer()
	setup_training_stats_hud()
	_reset_special_training_state()
	_development = DEVELOPMENT_MODE_SCRIPT.new(self)
	_development.prepare()

	# 初始化已删除的互动文案兼容状态（保持为空）。
	initialize_interaction_text()

	# 根据当前地图尺寸摆放黑框与两行文字。
	refresh_map_presentation()
	# VS 保持 RichTextLabel 供双语录制镜像，但由独立屏幕画布绘制：
	# 在 World 的反向 Canvas 变换下逐帧追相机，视觉像素会抖动。
	if not get_viewport().size_changed.is_connected(refresh_top_text_layout):
		get_viewport().size_changed.connect(refresh_top_text_layout)

	control.visible = true

	var initial_map_rect:Rect2 = return_map_world_rect(map_group[now_choose_map])
	camera_2d.global_position = initial_map_rect.get_center()
	camera_2d.reset_smoothing()

	_apply_camera_zoom()
	
	Traverse_folders(start_path,add_to_spawner)
	Traverse_folders(image_path,add_to_status)
	Traverse_folders(particle_path,add_to_prticles)
	set_char_dic()
	call_deferred("report_all_character_translation_keys")

	if not Game.language_changed.is_connected(_on_language_changed):
		Game.language_changed.connect(_on_language_changed)
	if not Game.game_setting_changed.is_connected(_on_training_game_setting_changed):
		Game.game_setting_changed.connect(_on_training_game_setting_changed)
	if not get_tree().node_added.is_connected(_on_training_scene_node_added):
		get_tree().node_added.connect(_on_training_scene_node_added)
	# 场景中可能已有在 World._ready() 之前进入树的投射物，延后一帧做一次兼容同步。
	call_deferred("_resync_non_ball_projectile_registry")
	battle_conditions = load("res://scripts/training/battle_conditions.gd").new(self)
	add_child(battle_conditions)


func _exit_tree() -> void:
	random_character_draft.cancel(false)
	_cancel_rotation_presentation()
	if get_viewport() != null and get_viewport().size_changed.is_connected(refresh_top_text_layout):
		get_viewport().size_changed.disconnect(refresh_top_text_layout)
	if _development != null:
		_development.cleanup(false)
	_release_heavy_hitstop()
	_release_all_local_hitstop()
	_cinematic_focus_requests.clear()
	Game.release_time_scale_override(CINEMATIC_FOCUS_TIME_KEY)
	if get_tree() != null and get_tree().node_added.is_connected(_on_training_scene_node_added):
		get_tree().node_added.disconnect(_on_training_scene_node_added)
	if Game.game_setting_changed.is_connected(_on_training_game_setting_changed):
		Game.game_setting_changed.disconnect(_on_training_game_setting_changed)

var start_path:String = "res://scenes/"
var particle_path:String = "res://scenes/particle/"
var char_path:String = "res://scenes/characters/"
var image_path:String = "res://Images/Status/"
var dont_copy:Array[String] = ["particle"]
func add_to_spawner(path:String) -> void:
	spawner.add_spawnable_scene(path)

func Traverse_folders(path:String,callback:Callable,traverse_sub:bool = true): #-> Array[PackedScene]:
	#var scenes:Array[PackedScene] = []
	var dir = DirAccess.open(path)
	if dir == null:
		push_error("can open folder:" + path)
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if (
		file_name.ends_with(".tscn") or
		file_name.ends_with(".png") or
		file_name.ends_with(".jng") or 
		file_name.ends_with(".webp") or 
		file_name.ends_with(".import") or 
		file_name.ends_with(".remap") 
		):
			if file_name.ends_with(".import"):file_name = file_name.trim_suffix(".import")
			if file_name.ends_with(".remap"):file_name = file_name.trim_suffix(".remap")
			callback.call(path.path_join(file_name))
		elif dir.current_is_dir() and not file_name in dont_copy and traverse_sub:
			Traverse_folders(path.path_join(file_name),callback)
		file_name = dir.get_next()
	dir.list_dir_end()

	#return scenes

func get_nth_folder(path:String,n:int) -> String:
	var dir := DirAccess.open(path)
	if dir:
		var folders := dir.get_directories()
		
		if n>=0 and n<folders.size():
			return folders[n]
		else:
			print("文件夹索引错误:",n)
	else:
		print("无法打开路径:",path)
		
	return ""

@onready var mouse_offset := Vector2.ZERO
@export var mouse_offset_lerp_weight := 0.5
@onready var fps: Label = $CanvasLayer/Fps
func set_fps_text() -> void:
	fps.text = Game.t("UI_FPS") + str(int(Engine.get_frames_per_second()))

func process_always(delta:float):
	_update_damage_focus()
	_update_heavy_hitstop()
	_update_local_hitstop()
	# FPS 文本 4Hz 更新即可；每帧重新排版 Label 没有视觉收益。
	_fps_refresh_elapsed += delta
	if _fps_refresh_elapsed >= 0.25:
		_fps_refresh_elapsed = 0.0
		set_fps_text()
	shake_restore = default_shake_restore
	camera_shake_amount = clampf(camera_shake_amount,0,max_shake_amount)

	# V106：战斗中心在空间网格刷新时（默认 30Hz）统一汇总。
	# 相机 render frame 不再扫描全部角色，也不会碰到 physics 帧后刚被 free 的缓存对象。
	var poi:Vector2 = _battle_primary_center
	var ball_count:int = _battle_primary_count

	shake_restore += ball_count
	var map_center:Vector2 = camera_2d.global_position
	if _current_map_node() != null:
		map_center = return_map_world_rect(_current_map_node()).get_center()
	var desired_center:Vector2 = map_center
	var controlled:Node = Game.get_local_controlled_character()
	var follow_controlled:bool = false

	# V405：用户所说的“关闭镜头跟随”对应的是 Game_Settings.Camera_Move=false 的视角，
	# 不是仅关闭 Follow_Controlled_Character。只有一名角色时，战斗中心 poi 与角色位置完全相同，
	# 所以 V404 虽然关闭了角色跟随，Camera_Move=true 仍会一直看着该角色，直到角色死亡后 ball_count 归零才回地图中心。
	# 死档覆盖开启时直接固定走“Camera_Move=false”分支：地图中心 + 现有中键平移；同时跳过电影镜头中心覆盖。
	if _dead_save_force_non_follow_camera:
		desired_center = map_center + mouse_offset
	else:
		follow_controlled = Game.should_follow_controlled_character() and controlled is Node2D
		if follow_controlled:
			# V128：跟随控制角色时无视 Camera_Move 与手动平移，始终锁定被控角色；
			# Alt+滚轮缩放仍走 toolbar_zoom_multiplier，因此不会影响跟随中心。
			desired_center = (controlled as Node2D).global_position
		elif ball_count > 0 and Game.Game_Settings.Camera_Move:
			desired_center = poi
		# 只有非强制跟随控制角色时才叠加中键平移。控制模式中键已被 Game 禁用。
		if not follow_controlled:
			desired_center += mouse_offset

		# 可复用电影镜头：所有调用方只需登记“来源 + 目标”。
		# 死档覆盖开启时不允许电影镜头再次把中心拉回仍存活的角色。
		var cinematic_center:Vector2 = _resolve_cinematic_focus_center()
		if not _cinematic_focus_requests.is_empty():
			_cinematic_focus_anchor = cinematic_center
		if _cinematic_focus_weight > 0.0001:
			desired_center = desired_center.lerp(_cinematic_focus_anchor,clampf(_cinematic_focus_weight,0.0,1.0))
			desired_center = _constrain_camera_center_to_keep_map_visible(desired_center,get_effective_camera_zoom())

	if _damage_focus_weight > 0.0:
		desired_center = desired_center.lerp(_damage_focus_anchor,_damage_focus_weight * 0.55)
		desired_center = _constrain_camera_center_to_keep_map_visible(desired_center,get_effective_camera_zoom())
	_update_intro_camera(delta)
	if _intro_camera_weight > 0.0:
		desired_center = desired_center.lerp(_intro_camera_anchor,_intro_camera_weight)
	_apply_camera_zoom()
	camera_2d.global_position = desired_center

	_update_damage_camera_shake(delta)

func _process(delta: float) -> void:
	_update_map_outside_grid_parallax()
	# V286：渲染帧发生在物理更新之后，这里读取投射物上一帧到当前帧的真实位移，
	# 只修视觉根节点朝向，不参与其运动。这样重力把弹道掰弯后，图片也会跟着转向。
	_update_non_ball_projectile_visual_facing()
	if _development != null:
		_development.update(delta)
		if _development.phase == _development.MERGING:
			return
	_update_special_training_modes(delta)
	# 训练模式自身会每帧刷新轮放/计时 HUD；盔甲架测试时在同一帧末尾统一压回隐藏，
	# 这样不会出现 VS/计时器短暂闪回。
	_apply_armor_stand_test_hud_suppression()
	_update_character_dialogue_battle_start_edge()
	# 功能：100+ 单位时不再每一个渲染帧都扫描全场并重复写同样的 UI/颜色属性。
	_unit_housekeeping_elapsed += maxf(delta,0.0)
	if _unit_housekeeping_elapsed >= maxf(unit_housekeeping_refresh_interval,0.02):
		_unit_housekeeping_elapsed = 0.0
		for raw_b in _battle_units_cache:
			if raw_b == null or not is_instance_valid(raw_b):
				continue
			if not raw_b is ball:
				continue
			var b:ball = raw_b as ball
			# V192：地图外来客不显示血条；即使角色自己的 health_bar 脚本稍后尝试恢复可见，这里也会持续压回隐藏。
			var hide_guest_ui:bool = b.has_meta(&"pig_outside_guest_hide_ui") and bool(b.get_meta(&"pig_outside_guest_hide_ui"))
			if b.health_bar != null and is_instance_valid(b.health_bar):
				if hide_guest_ui:
					b.health_bar.visible = false
				else:
					# 血条层级只在实际不一致时写入，避免无意义 Canvas 排序脏标记。
					if b.health_bar.z_as_relative:
						b.health_bar.z_as_relative = false
					if b.health_bar.z_index != map_health_bar_z_index:
						b.health_bar.z_index = map_health_bar_z_index

			if (
				b.Type != ball.Ball_Type.Ball
				and b.Type != ball.Ball_Type.Creature
			):
				continue

			if Game.Game_Settings.Ball_Can_Move:
				_apply_or_record_initial_battle_direction(b)
			elif not b.has_meta(&"battle_initial_direction_processed"):
				b.direction = Vector2.ZERO

		if Game.Game_Settings.Same_Ball_Change_Color:
			set_char_random_color()
		else:
			_restore_team_auto_character_colors()

	if _presentation_map_name != now_choose_map:
		random_character_draft.on_map_changed()
		refresh_map_presentation()
		_top_text_refresh_elapsed = top_text_refresh_interval

	# VS/互动文字只在 5Hz 左右检查一次，避免每一渲染帧遍历整个角色组并触发 RichText 排版。
	_top_text_refresh_elapsed += delta
	if _top_text_refresh_elapsed >= top_text_refresh_interval:
		_top_text_refresh_elapsed = 0.0
		refresh_versus_text()
		refresh_interaction_text()

	# 死档覆盖必须压住轮放/Boss HUD 自己的可见性刷新；否则恢复时间后可能闪回 VS。
	if _dead_save_ui_override_active:
		_apply_dead_save_ui_override()

# V411：只读快速入口。ball.return_nearest_teammate() 可直接扫描这份事件维护缓存，
# 保持逐个读取当前 global_position 的精确最近结果，同时避免 SceneTree group Array 分配。
func get_battle_units_fast() -> Array:
	return _battle_units_cache


# V106：ball 基类调用的事件注册。只登记真正参与战斗/镜头/索敌的 Ball 与 Creature。
func register_battle_unit(unit:ball) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	bind_battle_lifecycle(unit)
	if _timed_finished and _timed_defeated_setups.has(_resolve_timed_source_setup_id(unit)):
		call_deferred("_eliminate_timed_defeated",unit)
	# 继承 ball 的投射物单独登记，供传送门地图逐帧检查穿越；不进入战斗单位表。
	if unit.Type == ball.Ball_Type.Shooter or unit.Type == ball.Ball_Type.Shooter_with_Health:
		var projectile_id:int = unit.get_instance_id()
		if not _ball_projectile_ids.has(projectile_id):
			_ball_projectile_ids[projectile_id] = true
			_ball_projectile_units.append(unit)
		return
	if unit.Type != ball.Ball_Type.Ball and unit.Type != ball.Ball_Type.Creature:
		return
	var id:int = unit.get_instance_id()
	if _battle_unit_ids.has(id):
		return
	_battle_unit_ids[id] = true
	_battle_units_cache.append(unit)
	_include_victory_encounter_unit(unit)
	if is_instance_valid(duel_top_hud): duel_top_hud.remember_victory_participant(unit)
	_battle_registry_dirty = true
	_alive_primary_cache_frame = -1
	# 盔甲架一注册就立即切换顶部 HUD；测试模式下新放角色也立刻刷新，
	# 不必等 5Hz 定时器，避免短时间还显示旧角色信息。
	if _is_armor_stand_test_unit(unit):
		_armor_stand_test_hud_active = true
		_last_versus_text = ""
		call_deferred("refresh_versus_text")
	elif _armor_stand_test_hud_active:
		call_deferred("refresh_versus_text")
	# 新生成单位立即继承当前大规模模式，不必等下一次全量切换。
	if unit.is_large_battle_performance_mode() != _large_battle_mode_active:
		unit.set_large_battle_performance_mode(_large_battle_mode_active)


func unregister_battle_unit(unit:ball) -> void:
	if unit == null:
		return
	unit.set_meta("battle_lifecycle_exiting",true)
	var id:int = unit.get_instance_id()
	if _ball_projectile_ids.has(id):
		_ball_projectile_ids.erase(id)
		for i:int in range(_ball_projectile_units.size()-1,-1,-1):
			if _ball_projectile_units[i] == unit:
				_ball_projectile_units.remove_at(i)
				break
	call_deferred("_scan_rotation_family_extinctions")
	_battle_unit_ids.erase(id)
	for i:int in range(_battle_units_cache.size()-1,-1,-1):
		var raw:Variant = _battle_units_cache[i]
		if raw == unit:
			_battle_units_cache.remove_at(i)
			break
	_battle_registry_dirty = true
	_alive_primary_cache_frame = -1
	# queue_free/tree_exiting 发生时，节点可能要到帧末才真正离开场景树。
	# 因此统一延后一拍刷新：盔甲架退出时重算测试模式，普通角色退出时则解除旧目标锁，
	# 让新放下的第一个角色立即接管顶部信息。
	if _is_armor_stand_test_unit(unit) or _armor_stand_test_hud_active:
		call_deferred("refresh_versus_text")


# V434：只读快速入口，返回最近一次（≤33ms 前）网格重建时仍可被索敌的人物快照。
# 调用方必须继续对每个候选做自己的实时有效性/敌我判断；这里只负责去掉投射物、
# 已死亡、已退出 Ball 组或已明确退出索敌契约的单位。
func get_combat_targetable_units_fast() -> Array:
	return _battle_targetable_units


func _rebuild_battle_unit_ids() -> void:
	_battle_unit_ids.clear()
	for raw:Variant in _battle_units_cache:
		if raw == null or not is_instance_valid(raw) or not raw is ball:
			continue
		var unit:ball = raw as ball
		_battle_unit_ids[unit.get_instance_id()] = true


# 跨帧缓存必须在任何全量玩法循环之前清掉已 free / 正在 queue_free 的对象。
# 反向 remove_at 只在真的有死亡/删除时搬移数组；平稳帧只是 O(N) 的 validity 检查。
func _prune_battle_unit_registry() -> void:
	var changed:bool = false
	for i:int in range(_battle_units_cache.size()-1,-1,-1):
		var raw:Variant = _battle_units_cache[i]
		if raw == null or not is_instance_valid(raw):
			_battle_units_cache.remove_at(i)
			changed = true
			continue
		if not raw is ball:
			_battle_units_cache.remove_at(i)
			changed = true
			continue
		var unit:ball = raw as ball
		if unit.is_queued_for_deletion() or (unit.Type != ball.Ball_Type.Ball and unit.Type != ball.Ball_Type.Creature):
			_battle_unit_ids.erase(unit.get_instance_id())
			_battle_units_cache.remove_at(i)
			changed = true
	if changed:
		_rebuild_battle_unit_ids()
		_battle_registry_dirty = true


# 兼容旧派生脚本：低频同步组列表，而不是 60Hz 每帧 get_nodes_in_group。
func _resync_battle_registry_from_group() -> void:
	var seen:Dictionary = {}
	for raw:Variant in get_tree().get_nodes_in_group("Ball"):
		if raw == null or not is_instance_valid(raw) or not raw is ball:
			continue
		var unit:ball = raw as ball
		if unit.Type != ball.Ball_Type.Ball and unit.Type != ball.Ball_Type.Creature:
			continue
		seen[unit.get_instance_id()] = true
		register_battle_unit(unit)
	for i:int in range(_battle_units_cache.size()-1,-1,-1):
		var raw:Variant = _battle_units_cache[i]
		if raw == null or not is_instance_valid(raw):
			_battle_units_cache.remove_at(i)
			_battle_registry_dirty = true
			continue
		var unit:ball = raw as ball
		var id:int = unit.get_instance_id()
		if not seen.has(id):
			_battle_unit_ids.erase(id)
			_battle_units_cache.remove_at(i)
			_battle_registry_dirty = true
	# 防御性重建一次 ID 表，避免极端 free 顺序留下不可恢复的旧 instance_id。
	_rebuild_battle_unit_ids()


# V106：空间网格最多 30Hz 重建。索敌本来约 10Hz，软分离也是 30Hz，
# 因此 60Hz 重建只会增加 Dictionary/Array 开销，不会增加玩法精度。
func _refresh_battle_spatial_grid_if_needed(delta:float) -> void:
	_battle_spatial_elapsed += maxf(delta,0.0)
	var interval:float = maxf(large_battle_spatial_refresh_interval,0.016)
	if not _battle_registry_dirty and _battle_spatial_elapsed < interval:
		return
	_battle_spatial_elapsed = fmod(_battle_spatial_elapsed,interval) if interval > 0.0 else 0.0
	_rebuild_battle_spatial_grid(_battle_units_cache)
	_battle_registry_dirty = false


# V105：重建统一空间网格。bucket Array 会跨帧复用，避免每次为每个格子创建新 Array。
func _rebuild_battle_spatial_grid(units:Array) -> void:
	for cell:Vector2i in _battle_spatial_active_cells:
		var old_bucket:Variant = _battle_spatial_grid.get(cell,null)
		if old_bucket is Array:
			(old_bucket as Array).clear()
	_battle_spatial_active_cells.clear()
	_battle_spatial_has_units = false
	_battle_targetable_units.clear()

	var count:int = units.size()
	_battle_spatial_positions.resize(count)
	var cell_size:float = maxf(large_battle_grid_cell_size,8.0)
	var first_cell:bool = true
	var primary_sum:Vector2 = Vector2.ZERO
	var primary_count:int = 0

	for i:int in range(count):
		var unit:ball = units[i] as ball
		if unit == null or not is_instance_valid(unit) or unit.health <= 0:
			_battle_spatial_positions[i] = Vector2.ZERO
			continue
		# V434：可索敌人物快照（投射物已在 register 时排除；这里再排除死亡/退出契约/退出 Ball 组的单位）。
		if unit.is_combat_targetable() and unit.is_in_group("Ball"):
			_battle_targetable_units.append(unit)
		var pos:Vector2 = unit.global_position
		_battle_spatial_positions[i] = pos
		if _is_primary_battle_character(unit):
			primary_sum += pos
			primary_count += 1
		var cell:=Vector2i(floori(pos.x/cell_size),floori(pos.y/cell_size))
		var bucket:Array
		if _battle_spatial_grid.has(cell):
			bucket = _battle_spatial_grid[cell] as Array
		else:
			bucket = []
			_battle_spatial_grid[cell] = bucket
		if bucket.is_empty():
			_battle_spatial_active_cells.append(cell)
		bucket.append(i)
		if first_cell:
			_battle_spatial_min_cell = cell
			_battle_spatial_max_cell = cell
			first_cell = false
		else:
			_battle_spatial_min_cell.x = mini(_battle_spatial_min_cell.x,cell.x)
			_battle_spatial_min_cell.y = mini(_battle_spatial_min_cell.y,cell.y)
			_battle_spatial_max_cell.x = maxi(_battle_spatial_max_cell.x,cell.x)
			_battle_spatial_max_cell.y = maxi(_battle_spatial_max_cell.y,cell.y)

	_battle_spatial_has_units = not first_cell
	_battle_primary_count = primary_count
	_battle_primary_center = primary_sum / float(primary_count) if primary_count > 0 else Vector2.ZERO


func _nearest_enemy_candidate_distance_sq(source:ball,candidate:ball) -> float:
	if candidate == null or not is_instance_valid(candidate) or source == candidate:
		return INF
	if candidate.has_meta("development_reserve") or (_development != null and not _development.same_lane(source,candidate)):
		return INF
	if candidate.Type == ball.Ball_Type.Shooter or candidate.health <= 0:
		return INF
	if not candidate.is_combat_lockable():
		return INF
	if candidate.Master != null and is_instance_valid(candidate.Master) and candidate.Master == source:
		return INF
	if source.Team != "" and candidate.Team != "" and candidate.Team == source.Team:
		return INF
	if candidate.has_method(&"combat_distance_point_for"):
		# Tall / multi-part bodies: distance to their part nearest to the source.
		return source.global_position.distance_squared_to(candidate.call(&"combat_distance_point_for",source))
	return source.global_position.distance_squared_to(candidate.global_position)


# Tall / multi-part bodies register here: the spatial grid only knows their origin cell, so the
# nearest-enemy search checks them explicitly (usually an empty list).
var _tall_combat_bodies:Array = []
func register_tall_combat_body(body:Node) -> void:
	if is_instance_valid(body) and not _tall_combat_bodies.has(body): _tall_combat_bodies.append(body)


# 精确最近敌人空间查询：逐圈扩展格子；一旦当前最佳距离已经小于“已扫描矩形到外界的最短距离”，
# 数学上即可证明外圈不可能有更近目标，因此提前结束。密集大场面从 O(N) 候选降为局部候选。
func _find_nearest_enemy_spatial(source:ball,units:Array) -> ball:
	if not _battle_spatial_has_units or source == null or not is_instance_valid(source):
		return null
	var cell_size:float = maxf(large_battle_grid_cell_size,8.0)
	var pos:Vector2 = source.global_position
	var center:=Vector2i(floori(pos.x/cell_size),floori(pos.y/cell_size))
	var max_ring:int = maxi(
		maxi(abs(center.x-_battle_spatial_min_cell.x),abs(center.x-_battle_spatial_max_cell.x)),
		maxi(abs(center.y-_battle_spatial_min_cell.y),abs(center.y-_battle_spatial_max_cell.y))
	)
	var nearest:ball = null
	var nearest_sq:float = INF

	for ring:int in range(max_ring+1):
		if ring == 0:
			var bucket0:Variant = _battle_spatial_grid.get(center,null)
			if bucket0 is Array:
				var bucket0_array:Array = bucket0 as Array
				for raw_index in bucket0_array:
					var idx:int = int(raw_index)
					if idx < 0 or idx >= units.size():
						continue
					var candidate:ball = units[idx] as ball
					var distance_sq:float = _nearest_enemy_candidate_distance_sq(source,candidate)
					if distance_sq < nearest_sq:
						nearest_sq = distance_sq
						nearest = candidate
		else:
			var min_x:int = center.x-ring
			var max_x:int = center.x+ring
			var min_y:int = center.y-ring
			var max_y:int = center.y+ring
			# 上/下边
			for x:int in range(min_x,max_x+1):
				for y:int in [min_y,max_y]:
					var bucket_y:Variant = _battle_spatial_grid.get(Vector2i(x,y),null)
					if not bucket_y is Array:
						continue
					var bucket_y_array:Array = bucket_y as Array
					for raw_index in bucket_y_array:
						var idx:int = int(raw_index)
						if idx < 0 or idx >= units.size():
							continue
						var candidate:ball = units[idx] as ball
						var distance_sq:float = _nearest_enemy_candidate_distance_sq(source,candidate)
						if distance_sq < nearest_sq:
							nearest_sq = distance_sq
							nearest = candidate
			# 左/右边（去掉角，避免重复）
			for y:int in range(min_y+1,max_y):
				for x:int in [min_x,max_x]:
					var bucket_x:Variant = _battle_spatial_grid.get(Vector2i(x,y),null)
					if not bucket_x is Array:
						continue
					var bucket_x_array:Array = bucket_x as Array
					for raw_index in bucket_x_array:
						var idx:int = int(raw_index)
						if idx < 0 or idx >= units.size():
							continue
						var candidate:ball = units[idx] as ball
						var distance_sq:float = _nearest_enemy_candidate_distance_sq(source,candidate)
						if distance_sq < nearest_sq:
							nearest_sq = distance_sq
							nearest = candidate

		if nearest != null:
			var left:float = float(center.x-ring)*cell_size
			var right:float = float(center.x+ring+1)*cell_size
			var top:float = float(center.y-ring)*cell_size
			var bottom:float = float(center.y+ring+1)*cell_size
			var boundary_distance:float = minf(minf(pos.x-left,right-pos.x),minf(pos.y-top,bottom-pos.y))
			if nearest_sq <= boundary_distance*boundary_distance:
				break
	return nearest


# 功能：按当前单位数量启停大规模战斗物理模式，并确保后来新生成的单位同步进入当前模式。
func _update_large_battle_mode(units:Array) -> void:
	var count:int = units.size()
	var should_enable:bool = _large_battle_mode_active
	if not large_battle_optimization_enabled:
		should_enable = false
	elif _large_battle_mode_active:
		should_enable = count >= mini(large_battle_disable_below,large_battle_unit_threshold)
	else:
		should_enable = count >= large_battle_unit_threshold

	# V106：模式没改变时不要每个 physics tick 再遍历 N 个角色。
	# 新生成角色已在 register_battle_unit() 中立即继承当前模式。
	if should_enable == _large_battle_mode_active:
		return
	_large_battle_mode_active = should_enable

	for raw_unit in units:
		if raw_unit == null or not is_instance_valid(raw_unit) or not raw_unit is ball:
			continue
		var unit:ball = raw_unit as ball
		if unit.is_large_battle_performance_mode() != should_enable:
			unit.set_large_battle_performance_mode(should_enable)
			# 退出大规模模式会还原角色原始 mask；隐身期间不可短暂恢复身体互撞。
			if bool(unit.get_meta(&"mc_ignore_character_body_collision",false)):
				unit.set_collision_mask_value(2,false)


# 功能：用统一空间网格计算角色间软分离。V105 默认 30Hz 刷新分离速度，角色真实物理仍保持 60Hz。
func _update_large_battle_crowd_separation(units:Array,delta:float) -> void:
	if not _large_battle_mode_active:
		_large_battle_separation_elapsed = 999.0
		return

	_large_battle_separation_elapsed += maxf(delta,0.0)
	var interval:float = maxf(large_battle_separation_refresh_interval,0.016)
	if _large_battle_separation_elapsed < interval:
		return
	_large_battle_separation_elapsed = fmod(_large_battle_separation_elapsed,interval)

	var count:int = units.size()
	if count <= 1:
		return
	_battle_spatial_radii.resize(count)
	_battle_spatial_pushes.resize(count)
	for i:int in range(count):
		_battle_spatial_pushes[i] = Vector2.ZERO
		var unit:ball = units[i] as ball
		_battle_spatial_radii[i] = (
			unit.get_crowd_separation_radius_world()
			if unit != null and is_instance_valid(unit) and unit.health > 0 and not bool(unit.get_meta(&"mc_ignore_character_body_collision",false))
			else 0.0
		)

	var _cell_size:float = maxf(large_battle_grid_cell_size,8.0)
	# 只遍历本帧真正有单位的格子；每对单位只处理一次。
	for cell:Vector2i in _battle_spatial_active_cells:
		var bucket_value:Variant = _battle_spatial_grid.get(cell,null)
		if not bucket_value is Array:
			continue
		var bucket:Array = bucket_value as Array
		for raw_i in bucket:
			var i:int = int(raw_i)
			if i < 0 or i >= count:
				continue
			var unit_i:ball = units[i] as ball
			var radius_i:float = _battle_spatial_radii[i]
			if unit_i == null or radius_i <= 0.0:
				continue
			var pos_i:Vector2 = _battle_spatial_positions[i]

			for offset_y:int in range(-1,2):
				for offset_x:int in range(-1,2):
					var neighbor_cell:=cell+Vector2i(offset_x,offset_y)
					var neighbor_value:Variant = _battle_spatial_grid.get(neighbor_cell,null)
					if not neighbor_value is Array:
						continue
					var neighbor_bucket:Array = neighbor_value as Array
					for raw_j in neighbor_bucket:
						var j:int = int(raw_j)
						if j <= i or j < 0 or j >= count:
							continue
						var unit_j:ball = units[j] as ball
						var radius_j:float = _battle_spatial_radii[j]
						if unit_j == null or radius_j <= 0.0:
							continue
						# Temporary pair leases must bypass soft separation as well as physics.
						if preload("res://classes/body_collision_exclusions.gd").are_excluded(unit_i,unit_j):
							continue
						# Same-cohort bats already exclude body collisions; soft separation must agree.
						# get_meta(key, null) still logs an error for missing keys in Godot.
						# Most fighters are not bats, so guard both lookups in this hot pair loop.
						if unit_i.has_meta(&"mc_bat_cohort") and unit_j.has_meta(&"mc_bat_cohort"):
							if unit_i.get_meta(&"mc_bat_cohort") == unit_j.get_meta(&"mc_bat_cohort"):
								continue
						var pos_j:Vector2 = _battle_spatial_positions[j]
						var difference:Vector2 = pos_i-pos_j
						var distance_sq:float = difference.length_squared()
						var wanted_distance:float = radius_i+radius_j+large_battle_separation_margin
						if distance_sq >= wanted_distance*wanted_distance:
							continue

						var away:Vector2
						var distance_value:float
						if distance_sq <= 0.000001:
							var seed_value:int = Game.battle_rng_seed_or("scripts/world.gd:spatial_overlap_tie",unit_i.get_instance_id() ^ unit_j.get_instance_id()) % 360
							away = Vector2.RIGHT.rotated(deg_to_rad(float(seed_value)))
							distance_value = 0.0
						else:
							distance_value = sqrt(distance_sq)
							away = difference/distance_value
						var overlap:float = maxf(wanted_distance-distance_value,0.0)
						var pair_speed:float = minf(
							overlap*maxf(large_battle_separation_response,1.0),
							large_battle_separation_max_speed
						)*0.5
						_battle_spatial_pushes[i] += away*pair_speed
						_battle_spatial_pushes[j] -= away*pair_speed

	for i:int in range(count):
		var unit:ball = units[i] as ball
		if unit == null or not is_instance_valid(unit):
			continue
		var push:Vector2 = _battle_spatial_pushes[i]
		if push.length_squared() > large_battle_separation_max_speed*large_battle_separation_max_speed:
			push = push.normalized()*large_battle_separation_max_speed
		unit.set_crowd_separation_velocity(push)

	if large_battle_print_monitor:
		_large_battle_monitor_elapsed += interval
		if _large_battle_monitor_elapsed >= 1.0:
			_large_battle_monitor_elapsed = 0.0
			print(
				"[LargeBattle] units=",count,
				" physics_pairs=",int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)),
				" physics_ms=",float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))*1000.0
			)


# 功能：只刷新一个单位的最近合法敌人；V105 优先使用本帧空间网格，保持“全场精确最近”语义。
func _refresh_one_nearest_enemy(b:ball,set_property_group:Array) -> void:
	if b == null or not is_instance_valid(b):
		return

	if (
		is_instance_valid(b.Target_Enemy)
		and (
			(b.Target_Enemy.has_method("is_combat_lockable") and not bool(b.Target_Enemy.call("is_combat_lockable")))
			or (not b.Target_Enemy.has_method("is_combat_lockable") and b.Target_Enemy.has_method("is_combat_targetable") and not bool(b.Target_Enemy.call("is_combat_targetable")))
		)
	):
		b.Target_Enemy = null

	var nearest_enemy:ball = _find_nearest_enemy_spatial(b,set_property_group)
	# 极端情况下网格尚未建立（例如首个物理帧前的手动调用），保留旧全扫兜底。
	if not _battle_spatial_has_units and set_property_group.size() > 1:
		var nearest_distance_sq:float = INF
		for b2:ball in set_property_group:
			var distance_sq:float = _nearest_enemy_candidate_distance_sq(b,b2)
			if distance_sq < nearest_distance_sq:
				nearest_distance_sq = distance_sq
				nearest_enemy = b2
	if not _tall_combat_bodies.is_empty():
		var best_sq:float = _nearest_enemy_candidate_distance_sq(b,nearest_enemy) if nearest_enemy != null else INF
		for i:int in range(_tall_combat_bodies.size()-1,-1,-1):
			var tall:Variant = _tall_combat_bodies[i]
			if not is_instance_valid(tall) or not tall is ball:
				_tall_combat_bodies.remove_at(i)
				continue
			var tall_sq:float = _nearest_enemy_candidate_distance_sq(b,tall as ball)
			if tall_sq < best_sq:
				best_sq = tall_sq
				nearest_enemy = tall as ball
	b.Nearest_Enemy = nearest_enemy


func _physics_process(delta: float) -> void:
	if _development != null and _development.phase == _development.MERGING:
		return
	if is_instance_valid(day_night_cycle): day_night_cycle.advance(delta)
	if is_instance_valid(minecraft_clouds): minecraft_clouds.advance(delta)
	# World 的定向重力注册表只在这里清理一次；ball 之后走 fast 查询，避免 N 个单位重复清理。
	_cleanup_directional_gravity_sources()
	# V259：非 ball 的飞行投射物没有公共 ball.tick_physics()，因此只在重力场存在时
	# 由 World 给现有 shooter/BattleTransient 的“方向+速度”运动接口补同一份加速度。
	# ball 派生对象仍由 classes/ball.gd 自己积分，避免重复施力。
	_apply_directional_gravity_to_non_ball_projectiles(delta)

	# V410：ball 的 tree_exiting 已能即时注销；O(N) validity prune 移到 0.75s 兼容校验，
	# 不再在每个 60Hz physics tick 扫整张单位表。
	_battle_registry_resync_elapsed += maxf(delta,0.0)
	if _battle_registry_resync_elapsed >= maxf(battle_registry_resync_interval,0.25):
		_battle_registry_resync_elapsed = 0.0
		_prune_battle_unit_registry()
		_resync_battle_registry_from_group()
		_resync_non_ball_projectile_registry()
	var set_property_group:Array = _battle_units_cache

	# 100+ 单位的主要瓶颈若来自 Physics 2D，则自动改用“墙体物理 + 空间网格角色分离”。
	_update_large_battle_mode(set_property_group)
	_refresh_battle_spatial_grid_if_needed(delta)
	_update_large_battle_crowd_separation(set_property_group,delta)

	# 功能：最近敌人仍保持平均 10Hz 更新，但把 N 个单位均匀摊到各物理帧。
	# 100 单位时不再每帧执行约 9900 次候选判断，也不会每 0.1 秒突然集中执行一次造成尖峰。
	var unit_count:int = set_property_group.size()
	if unit_count > 0:
		var refresh_interval:float = maxf(nearest_enemy_refresh_interval,0.02)
		_nearest_enemy_update_budget += float(unit_count) * maxf(delta,0.0) / refresh_interval
		var update_count:int = mini(int(floor(_nearest_enemy_update_budget)),unit_count)
		if update_count > 0:
			_nearest_enemy_update_budget -= float(update_count)
			if _nearest_enemy_refresh_cursor < 0 or _nearest_enemy_refresh_cursor >= unit_count:
				_nearest_enemy_refresh_cursor = 0
			for step:int in range(update_count):
				var index:int = (_nearest_enemy_refresh_cursor + step) % unit_count
				_refresh_one_nearest_enemy(set_property_group[index] as ball,set_property_group)
			_nearest_enemy_refresh_cursor = (_nearest_enemy_refresh_cursor + update_count) % unit_count
	else:
		_nearest_enemy_refresh_cursor = 0
		_nearest_enemy_update_budget = 0.0

	# 服务员门需要逐物理帧处理穿门碰撞；直接复用本帧单位数组，避免再次 get_nodes_in_group()。
	_process_waiter_door_passages(set_property_group)
	# 传送门地图：角色 / 投射物前沿贴到门边时立即映射到目标岛（早于本帧 move_and_slide）。
	_process_portal_transits(delta,set_property_group)

	# 地图救回/越界淘汰不是攻击命中判定，20Hz 足够；delta 累计后计时仍然准确。
	_map_rule_refresh_elapsed += maxf(delta,0.0)
	_map_rule_accumulated_delta += maxf(delta,0.0)
	if _map_rule_refresh_elapsed >= maxf(map_rule_refresh_interval,0.02):
		_map_rule_refresh_elapsed = 0.0
		_process_map_squeeze_protection(set_property_group)
		_process_out_of_bounds_rule(_map_rule_accumulated_delta,set_property_group)
		_map_rule_accumulated_delta = 0.0

	set_ball_properties_to_dafault(set_property_group)
	figure_buffs(delta,set_property_group)

	# 训练模式固定人物生命上限为 9999。Buff 计算可能再次改写 Max_health，
	# 所以在 Buff 之后再做一次轻量锁定；只有值真的偏离时才会同步 UI。
	if Game.is_training_mode():
		for training_ball:ball in set_property_group:
			if training_ball.Type == ball.Ball_Type.Ball:
				training_ball.enforce_training_health_cap()

	_victory_bell_poll_elapsed += maxf(delta,0.0)
	if _victory_bell_poll_elapsed >= VICTORY_BELL_POLL_INTERVAL or set_property_group.size() <= 8:
		_victory_bell_poll_elapsed = 0.0
		_update_manual_victory_bell()
		_update_battle_start_bell()


#========================================================
# 地图防挤出：额外物理安全框 + 轻度越界恢复
#========================================================
func _rebuild_map_safety_frame() -> void:
	if _map_safety_frame != null and is_instance_valid(_map_safety_frame):
		_map_safety_frame.queue_free()
	_map_safety_frame = null
	_map_safety_frame_map_name = ""

	if not map_safety_frame_enabled:
		return
	var map_node:Node = _current_map_node()
	if map_node == null:
		return
	var rects:Array[Rect2] = map_island_rects(map_node)
	if rects.is_empty():
		return

	var root := Node2D.new()
	root.name = "MapSafetyFrame"
	root.set_meta(&"map_safety_frame",true)
	add_child(root)
	_map_safety_frame = root
	_map_safety_frame_map_name = now_choose_map

	var portal:PortalMap = current_portal_map()
	var all_ground:Array[Rect2] = map_island_rects(map_node)
	for island:Dictionary in map_islands(map_node):
		for edge:Dictionary in TileGeometry.edges(island.regions):
			var side:int = edge.side
			var normal:Vector2 = PortalMap.SIDE_NORMALS[side]
			var spans:Array[Vector2] = _subtract_axis_intervals(edge.a,edge.b,_shape_edge_gaps(edge,island,portal,false))
			for span:Vector2 in spans:
				var a:Vector2 = TileGeometry.point(edge,span.x)
				var b:Vector2 = TileGeometry.point(edge,span.y)
				# Only exterior geometry; subtract ground so thin holes/nearby islands never receive internal walls.
				var depth:float = maxf(map_safety_wall_thickness,4.0)
				var outer:Vector2 = normal*depth
				var wall:Rect2 = Rect2(a.min(b).min(a+outer),(a.max(b).max(b+outer)-a.min(b).min(a+outer)))
				for piece:Rect2 in TileGeometry.subtract([wall],all_ground):
					_add_map_safety_wall(root,piece.get_center(),piece.size)

func _add_map_safety_side_segments(
	parent:Node2D,
	map_rect:Rect2,
	side:int,
	thickness:float,
	inset:float
) -> void:
	var horizontal:bool = side >= 2
	var axis_min:float
	var axis_max:float
	if horizontal:
		axis_min = map_rect.position.x - thickness
		axis_max = map_rect.end.x + thickness
	else:
		axis_min = map_rect.position.y - thickness
		axis_max = map_rect.end.y + thickness

	# 门洞的安全墙缺口必须与画出来的门宽完全一致。
	# 旧版这里额外 +2px/侧，会让真实缺口比可见门宽大 4px。
	var intervals:Array[Vector2] = _waiter_door_gap_intervals(side,axis_min,axis_max,0.0)
	var segments:Array[Vector2] = _subtract_axis_intervals(axis_min,axis_max,intervals)

	var left_x:float = map_rect.position.x + inset - thickness * 0.5
	var right_x:float = map_rect.end.x - inset + thickness * 0.5
	var top_y:float = map_rect.position.y + inset - thickness * 0.5
	var bottom_y:float = map_rect.end.y - inset + thickness * 0.5

	for span:Vector2 in segments:
		var length:float = span.y - span.x
		if length <= 0.5:
			continue
		if side == 0:
			_add_map_safety_wall(parent,Vector2(left_x,(span.x + span.y) * 0.5),Vector2(thickness,length))
		elif side == 1:
			_add_map_safety_wall(parent,Vector2(right_x,(span.x + span.y) * 0.5),Vector2(thickness,length))
		elif side == 2:
			_add_map_safety_wall(parent,Vector2((span.x + span.y) * 0.5,top_y),Vector2(length,thickness))
		else:
			_add_map_safety_wall(parent,Vector2((span.x + span.y) * 0.5,bottom_y),Vector2(length,thickness))


func _add_map_safety_wall(parent:Node2D,center:Vector2,size:Vector2) -> void:
	var body := StaticBody2D.new()
	body.name = "SafetyWall"
	# 普通角色 collision_mask=3，会检测物理层 1；这与地图墙的用途一致。
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta(&"map_safety_wall",true)

	var collision := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = Vector2(maxf(size.x,1.0),maxf(size.y,1.0))
	collision.shape = rect_shape
	body.add_child(collision)
	parent.add_child(body)
	body.global_position = center


#========================================================
# 服务员开门：公开 API
#========================================================
func open_waiter_door(
	owner:Node,
	door_width:float = 38.0,
	inner_tunnel_depth:float = 28.0,
	outer_tunnel_depth:float = 46.0,
	open_animation_duration:float = 0.28
) -> int:
	if owner == null or not is_instance_valid(owner) or not owner is Node2D:
		return -1
	var map_node:Node = _current_map_node()
	if map_node == null:
		return -1

	_prune_waiter_doors_for_current_map()
	# 传送门地图：门开在服务员所在（或最近）的岛上。
	var map_rect:Rect2 = nearest_map_island_rect((owner as Node2D).global_position,map_island_rects(map_node))
	if map_rect.size.x <= 1.0 or map_rect.size.y <= 1.0:
		return -1

	var owner_half_extents:Vector2 = Vector2(7.0,7.0)
	if owner is ball:
		owner_half_extents = _ball_collision_world_half_extents(owner as ball)
	var tile_depth:float = 16.0
	var tile_layer:TileMapLayer = map_node as TileMapLayer if map_node is TileMapLayer else (map_node as PortalMap).primary_island()
	if tile_layer != null and tile_layer.tile_set != null:
		var ts:Vector2i = tile_layer.tile_set.tile_size
		tile_depth = float(maxi(ts.x,ts.y))
	var placement:Dictionary = _choose_waiter_door_placement(
		(owner as Node2D).global_position,
		map_rect,
		maxf(door_width,8.0),
		owner_half_extents,
		tile_depth
	)
	if placement.is_empty():
		return -1

	# 服务员只有靠墙时才能发动技能，所以门直接开在他当前位置旁边。
	# 这里绝不修改 owner.global_position；开门期间的位置冻结由服务员脚本自身负责。
	if owner is CharacterBody2D:
		(owner as CharacterBody2D).velocity = Vector2.ZERO
	if owner is ball:
		(owner as ball).Repel = Vector2.ZERO

	var door_id:int = _waiter_door_next_id
	_waiter_door_next_id += 1

	var visual:Node2D = WAITER_DOOR_VISUAL_SCRIPT.new() as Node2D
	if visual != null:
		visual.name = "WaiterDoor_%d" % door_id
		visual.z_index = 100
		add_child(visual)
		visual.call(
			"configure",
			placement["center"],
			placement["outward"],
			float(placement["width"]),
			maxf(open_animation_duration,0.05),
			map_border_width,
			float(placement.get("hinge_sign",1.0)),
			_waiter_door_background_color(),
			float(placement["width"])
		)

	_waiter_doors[door_id] = {
		"id": door_id,
		"map_name": now_choose_map,
		"island_rect": map_rect,
		"owner_ref": weakref(owner),
		"center": placement["center"],
		"side": int(placement["side"]),
		"outward": placement["outward"],
		"tangent": placement["tangent"],
		"width": float(placement["width"]),
		"inner_depth": maxf(inner_tunnel_depth,4.0),
		"outer_depth": maxf(outer_tunnel_depth,4.0),
		"visual": visual,
		"closing": false,
		"body_states": {},
	}

	_rebuild_map_safety_frame()
	_refresh_current_map_border_geometry()
	return door_id


func _waiter_door_background_color() -> Color:
	# 门洞填充色跟随当前地图外背景，而不是固定读取蓝色场景渐变。
	return MAP_BACKGROUND_THEMES.theme(map_background_style()).get("grid_normal",Color(0.0,0.5882353,0.87058824,1.0))


func close_waiter_door(door_id:int,close_animation_duration:float = 0.28) -> void:
	if not _waiter_doors.has(door_id):
		return
	var info:Dictionary = _waiter_doors[door_id]
	if bool(info.get("closing",false)):
		return
	info["closing"] = true
	_waiter_doors[door_id] = info

	var visual:Variant = info.get("visual",null)
	if visual != null and is_instance_valid(visual) and visual.has_method("close"):
		visual.call("close",maxf(close_animation_duration,0.05))

	var timer:SceneTreeTimer = get_tree().create_timer(maxf(close_animation_duration,0.05))
	timer.timeout.connect(_finish_waiter_door_close.bind(door_id))


func _finish_waiter_door_close(door_id:int) -> void:
	if not _waiter_doors.has(door_id):
		return
	var info:Dictionary = _waiter_doors[door_id]
	var visual:Variant = info.get("visual",null)
	if visual != null and is_instance_valid(visual):
		visual.queue_free()
	_waiter_doors.erase(door_id)
	_rebuild_map_safety_frame()
	_refresh_current_map_border_geometry()
	_restore_waiter_door_wall_masks_not_in_tunnel()


func _choose_waiter_door_placement(
	position:Vector2,
	map_rect:Rect2,
	requested_width:float,
	owner_half_extents:Vector2 = Vector2(7.0,7.0),
	_wall_cell_depth:float = 16.0
) -> Dictionary:
	var distances:PackedFloat32Array = PackedFloat32Array([
		absf(position.x - map_rect.position.x),
		absf(map_rect.end.x - position.x),
		absf(position.y - map_rect.position.y),
		absf(map_rect.end.y - position.y),
	])
	var side:int = 0
	var best:float = distances[0]
	for i:int in range(1,4):
		if distances[i] < best:
			best = distances[i]
			side = i

	var wall_span:float = map_rect.size.y if side < 2 else map_rect.size.x
	var usable_width:float = clampf(requested_width,8.0,maxf(wall_span - 12.0,8.0))
	var outward:Vector2
	var wall_point:Vector2
	if side == 0:
		outward = Vector2.LEFT
		wall_point = Vector2(map_rect.position.x,clampf(position.y,map_rect.position.y,map_rect.end.y))
	elif side == 1:
		outward = Vector2.RIGHT
		wall_point = Vector2(map_rect.end.x,clampf(position.y,map_rect.position.y,map_rect.end.y))
	elif side == 2:
		outward = Vector2.UP
		wall_point = Vector2(clampf(position.x,map_rect.position.x,map_rect.end.x),map_rect.position.y)
	else:
		outward = Vector2.DOWN
		wall_point = Vector2(clampf(position.x,map_rect.position.x,map_rect.end.x),map_rect.end.y)

	var tangent:Vector2 = Vector2(-outward.y,outward.x).normalized()
	# 门洞尽量开在服务员“旁边”而不是正对着他的中心。
	# 这样视觉上服务员站在铰链旁，角色通道不会穿过他的身体中心。
	var along_body_half:float = owner_half_extents.y if side < 2 else owner_half_extents.x
	var body_clearance:float = maxf(along_body_half + 3.0,5.0)
	var corner_margin:float = 5.0
	var axis_min:float = (map_rect.position.y if side < 2 else map_rect.position.x) + corner_margin
	var axis_max:float = (map_rect.end.y if side < 2 else map_rect.end.x) - corner_margin
	var base_scalar:float = wall_point.y if side < 2 else wall_point.x

	var chosen_sign:float = 0.0
	var chosen_center:Vector2 = wall_point
	var best_room:float = -INF
	for candidate_sign:float in [1.0,-1.0]:
		var dir:Vector2 = tangent * candidate_sign
		var scalar_dir:float = dir.y if side < 2 else dir.x
		var near_scalar:float = base_scalar + scalar_dir * body_clearance
		var far_scalar:float = near_scalar + scalar_dir * usable_width
		var low:float = minf(near_scalar,far_scalar)
		var high:float = maxf(near_scalar,far_scalar)
		if low < axis_min or high > axis_max:
			continue
		var room:float = minf(low - axis_min,axis_max - high)
		if room > best_room:
			best_room = room
			chosen_sign = candidate_sign
			chosen_center = wall_point + dir * (body_clearance + usable_width * 0.5)

	if is_zero_approx(chosen_sign):
		# 两侧都没有足够空间时不把门强行开在服务员脚下。
		# 由于服务员开门期间保持实体碰撞，这种情况直接判定为本次无法开门。
		return {}

	return {
		"center": chosen_center,
		"outward": outward,
		"tangent": tangent,
		"side": side,
		"width": usable_width,
		"hinge_sign": chosen_sign,
	}


func _waiter_interval_sort(a:Vector2,b:Vector2) -> bool:
	return a.x < b.x


func _waiter_door_gap_intervals(side:int,axis_min:float,axis_max:float,extra:float = 0.0) -> Array[Vector2]:
	return _waiter_door_gap_intervals_for_island(side,axis_min,axis_max,extra,Rect2())


# island_rect 非空时只统计开在该岛上的门（传送门地图逐岛绘制边框 / 安全墙）。
func _waiter_door_gap_intervals_for_island(side:int,axis_min:float,axis_max:float,extra:float,island_rect:Rect2) -> Array[Vector2]:
	var intervals:Array[Vector2] = []
	for raw_id:Variant in _waiter_doors.keys():
		var info:Dictionary = _waiter_doors[raw_id]
		if str(info.get("map_name","")) != now_choose_map:
			continue
		if int(info.get("side",-1)) != side:
			continue
		if island_rect.size.x > 0.0 and info.has("island_rect") and not (info["island_rect"] as Rect2).is_equal_approx(island_rect):
			continue
		var center:Vector2 = info.get("center",Vector2.ZERO)
		var scalar:float = center.y if side < 2 else center.x
		var half:float = maxf(float(info.get("width",8.0)) * 0.5 + extra,1.0)
		var a:float = maxf(axis_min,scalar - half)
		var b:float = minf(axis_max,scalar + half)
		if b > a:
			intervals.append(Vector2(a,b))

	intervals.sort_custom(_waiter_interval_sort)
	if intervals.size() <= 1:
		return intervals

	var merged:Array[Vector2] = []
	var current:Vector2 = intervals[0]
	for i:int in range(1,intervals.size()):
		var next_span:Vector2 = intervals[i]
		if next_span.x <= current.y:
			current.y = maxf(current.y,next_span.y)
		else:
			merged.append(current)
			current = next_span
	merged.append(current)
	return merged


func _subtract_axis_intervals(axis_min:float,axis_max:float,intervals:Array[Vector2]) -> Array[Vector2]:
	var segments:Array[Vector2] = []
	var cursor:float = axis_min
	for gap:Vector2 in intervals:
		if gap.x > cursor:
			segments.append(Vector2(cursor,minf(gap.x,axis_max)))
		cursor = maxf(cursor,gap.y)
		if cursor >= axis_max:
			break
	if cursor < axis_max:
		segments.append(Vector2(cursor,axis_max))
	return segments


func _process_waiter_door_passages(ball_group:Array = []) -> void:
	_prune_waiter_doors_for_current_map()
	_close_orphaned_waiter_doors()
	if _waiter_doors.is_empty():
		_restore_all_waiter_door_wall_masks()
		return
	var map_node:Node = _current_map_node()
	if map_node == null:
		_restore_all_waiter_door_wall_masks()
		return

	var island_rects:Array[Rect2] = map_island_rects(map_node)
	var now_msec:int = Time.get_ticks_msec()
	var inside_any_tunnel:Dictionary = {}

	for node:Node in ball_group:
		if not node is ball:
			continue
		var b:ball = node as ball
		if b.Type != ball.Ball_Type.Ball or b.health <= 0:
			continue

		var body_id:int = b.get_instance_id()
		for raw_door_id:Variant in _waiter_doors.keys():
			var door_id:int = int(raw_door_id)
			var info:Dictionary = _waiter_doors[door_id]
			var body_states:Dictionary = info.get("body_states",{})
			var old_state:Dictionary = body_states.get(body_id,{})
			var passage_latched:bool = bool(old_state.get("passage_active",false))

			# 第一次进入必须真的对准可见门洞；一旦已经进入通道，就使用稍宽的
			# “释放区域”保持 mask，避免角色在门线附近因为 1px 抖动反复恢复墙碰撞而反弹。
			var in_passage:bool = (
				_ball_is_in_waiter_door_release_tunnel(b,info)
				if passage_latched
				else _ball_is_in_waiter_door_tunnel(b,info)
			)
			if not in_passage:
				if passage_latched:
					old_state["passage_active"] = false
					old_state["last_seen_msec"] = now_msec
					body_states[body_id] = old_state
					info["body_states"] = body_states
					_waiter_doors[door_id] = info
				continue

			inside_any_tunnel[body_id] = true
			_suspend_waiter_door_wall_collision(b)
			b.set_meta(&"waiter_door_passage_grace_until_msec",now_msec + WAITER_DOOR_PASSAGE_GRACE_MSEC)

			var inside_map_now:bool = map_contains_point(b.global_position,island_rects)
			var had_state:bool = body_states.has(body_id)
			var previous_inside:bool = inside_map_now
			if had_state:
				previous_inside = bool(old_state.get("inside_map",inside_map_now))

			# 只有“先在地图内 -> 从这扇门跨到地图外”的敌人才获得永久自动回拉豁免。
			if had_state and previous_inside and not inside_map_now and _waiter_door_body_is_enemy(info,b):
				b.set_meta(&"waiter_door_escape_exempt",true)
				b.set_meta(&"waiter_door_escape_id",door_id)

			body_states[body_id] = {
				"inside_map": inside_map_now,
				"last_seen_msec": now_msec,
				"passage_active": true,
			}
			info["body_states"] = body_states
			_waiter_doors[door_id] = info

	_restore_waiter_door_wall_masks_not_in_tunnel(inside_any_tunnel)


func _waiter_door_body_projection_extents(b:ball,tangent:Vector2,outward:Vector2) -> Vector2:
	var half_extents:Vector2 = _ball_collision_world_half_extents(b)
	# 门永远是水平/垂直的，但用投影公式可兼容未来旋转地图。
	var tangent_half:float = absf(tangent.x) * half_extents.x + absf(tangent.y) * half_extents.y
	var normal_half:float = absf(outward.x) * half_extents.x + absf(outward.y) * half_extents.y
	return Vector2(
		clampf(tangent_half,2.0,18.0),
		clampf(normal_half,2.0,18.0)
	)


func _ball_is_in_waiter_door_tunnel(b:ball,info:Dictionary) -> bool:
	if b == null or not is_instance_valid(b):
		return false
	var center:Vector2 = info.get("center",Vector2.ZERO)
	var outward:Vector2 = info.get("outward",Vector2.UP)
	outward = outward.normalized()
	var tangent:Vector2 = info.get("tangent",Vector2.RIGHT)
	tangent = tangent.normalized()
	var delta:Vector2 = b.global_position - center
	var extents:Vector2 = _waiter_door_body_projection_extents(b,tangent,outward)
	var tangent_half:float = extents.x
	var normal_half:float = extents.y

	# “实际门宽 = 显示门宽”。这里按角色碰撞体在门切线方向上的真实投影收缩中心范围，
	# 而不是使用 max(x,y) 粗略半径；后者会让一些长方形人物看起来已经对准门却仍被拒绝。
	var visible_half_width:float = float(info.get("width",8.0)) * 0.5
	var entry_tolerance:float = 1.0
	var center_pass_half_width:float = visible_half_width - tangent_half + entry_tolerance
	if center_pass_half_width <= 0.5:
		return false
	if absf(delta.dot(tangent)) > center_pass_half_width:
		return false

	var across:float = delta.dot(outward)
	var inner_depth:float = maxf(float(info.get("inner_depth",24.0)),4.0) + normal_half
	var outer_depth:float = maxf(float(info.get("outer_depth",40.0)),4.0) + normal_half
	return across >= -inner_depth and across <= outer_depth


func _ball_is_in_waiter_door_release_tunnel(b:ball,info:Dictionary) -> bool:
	if b == null or not is_instance_valid(b):
		return false
	var center:Vector2 = info.get("center",Vector2.ZERO)
	var outward:Vector2 = info.get("outward",Vector2.UP)
	outward = outward.normalized()
	var tangent:Vector2 = info.get("tangent",Vector2.RIGHT)
	tangent = tangent.normalized()
	var delta:Vector2 = b.global_position - center
	var extents:Vector2 = _waiter_door_body_projection_extents(b,tangent,outward)
	var tangent_half:float = extents.x
	var normal_half:float = extents.y

	# 已经进入门洞后给很小的迟滞区，只用于防止 mask 在门线附近一帧开一帧关。
	# 这不会扩大“第一次可以进入”的门宽。
	var visible_half_width:float = float(info.get("width",8.0)) * 0.5
	var release_half_width:float = visible_half_width + maxf(tangent_half * 0.35,2.0)
	if absf(delta.dot(tangent)) > release_half_width:
		return false

	var across:float = delta.dot(outward)
	var inner_depth:float = maxf(float(info.get("inner_depth",24.0)),4.0) + normal_half + 6.0
	var outer_depth:float = maxf(float(info.get("outer_depth",40.0)),4.0) + normal_half + 8.0
	return across >= -inner_depth and across <= outer_depth

func _waiter_door_body_is_enemy(info:Dictionary,b:ball) -> bool:
	var owner_ref:Variant = info.get("owner_ref",null)
	if owner_ref == null:
		return false
	var owner:Variant = owner_ref.get_ref()
	if owner == null or not is_instance_valid(owner) or owner == b:
		return false
	var owner_team:String = str(owner.get("Team")).strip_edges()
	var body_team:String = str(b.Team).strip_edges()
	if owner_team.is_empty() or body_team.is_empty():
		return owner != b
	return owner_team != body_team


func _suspend_waiter_door_wall_collision(b:ball) -> void:
	if b == null or not is_instance_valid(b):
		return
	var body_id:int = b.get_instance_id()
	if not b.has_meta(&"waiter_door_prev_wall_mask_layer1"):
		b.set_meta(&"waiter_door_prev_wall_mask_layer1",b.get_collision_mask_value(1))
	_waiter_door_masked_bodies[body_id] = weakref(b)
	# TileSet 物理墙和 World 安全墙都使用物理层 1；只关这一位，角色之间的层 2 碰撞仍保留。
	b.set_collision_mask_value(1,false)


func _restore_waiter_door_wall_masks_not_in_tunnel(active_ids:Dictionary = {}) -> void:
	for raw_id:Variant in _waiter_door_masked_bodies.keys().duplicate():
		var body_id:int = int(raw_id)
		if active_ids.has(body_id):
			continue
		var ref_value:Variant = _waiter_door_masked_bodies[body_id]
		var obj:Variant = ref_value.get_ref() if ref_value != null else null
		if obj != null and is_instance_valid(obj):
			var previous:bool = bool(obj.get_meta(&"waiter_door_prev_wall_mask_layer1",true))
			obj.set_collision_mask_value(1,previous)
			obj.remove_meta(&"waiter_door_prev_wall_mask_layer1")
		_waiter_door_masked_bodies.erase(body_id)


func _restore_all_waiter_door_wall_masks() -> void:
	_restore_waiter_door_wall_masks_not_in_tunnel({})


# The waiter only closes its door from its own timer or Die(); reset and rotation retire
# free it without dying, which left a permanent gap that later fighters walked out through.
func _close_orphaned_waiter_doors() -> void:
	for raw_id:Variant in _waiter_doors.keys().duplicate():
		var info:Dictionary = _waiter_doors[raw_id]
		if bool(info.get("closing",false)): continue
		var owner_ref:Variant = info.get("owner_ref",null)
		var owner:Variant = owner_ref.get_ref() if owner_ref != null else null
		if owner == null or not is_instance_valid(owner) or owner.is_queued_for_deletion() or ("health" in owner and owner.health <= 0):
			close_waiter_door(int(raw_id),0.12)


func _prune_waiter_doors_for_current_map() -> void:
	var removed:bool = false
	for raw_id:Variant in _waiter_doors.keys().duplicate():
		var door_id:int = int(raw_id)
		var info:Dictionary = _waiter_doors[door_id]
		if str(info.get("map_name","")) == now_choose_map:
			continue
		var visual:Variant = info.get("visual",null)
		if visual != null and is_instance_valid(visual):
			visual.queue_free()
		_waiter_doors.erase(door_id)
		removed = true
	if removed:
		_restore_all_waiter_door_wall_masks()


func _refresh_current_map_border_geometry() -> void:
	var map_node:Node = _current_map_node()
	if map_node != null:
		# 服务员的门不只要断开立体侧面，也必须移走五种贴图地图的原有墙顶。
		# 普通地图切换仍走 refresh_map_presentation()，这里只处理开/关门的局部刷新。
		if _is_grass_map_background():
			_refresh_map_background_tiles(map_node)
			_refresh_map_outside_grid(return_map_visual_rect(map_node))
		_refresh_map_border_geometry(return_map_world_rect(map_node))


func _process_map_squeeze_protection(ball_group:Array = []) -> void:
	if not is_multiplayer_authority(): return
	# 正常贴墙完全交给 CharacterBody2D.move_and_slide()。
	# 这里不再因为“碰撞体边缘接近/轻微压到地图边界”就启动 Tween，
	# 否则角色每次撞墙都会被暂停 physics_process 一小段时间，产生明显顿挫。
	# 只有角色中心真正越过地图矩形时，才认为是被挤出了地图并执行动画救回。
	if not map_safety_frame_enabled:
		return
	var map_node:Node = _current_map_node()
	if map_node == null:
		return

	if _map_safety_frame_map_name != now_choose_map or _map_safety_frame == null or not is_instance_valid(_map_safety_frame):
		_rebuild_map_safety_frame()

	var island_rects:Array[Rect2] = map_island_rects(map_node)
	for node in ball_group:
		if not node is ball:
			continue
		var b:ball = node as ball
		if b.has_meta("development_reserve"):
			continue
		if b.Type == ball.Ball_Type.Creature:
			# Summons get only the instant wall-embed release, never the walk-back rescue.
			if b.health > 0 and not b.has_meta(&"submission_allow_map_escape") and not b.has_meta(&"map_rescue_animating"):
				var creature_rect:Rect2 = nearest_map_island_rect(b.global_position,island_rects)
				if creature_rect.size.x > 0.0 and creature_rect.has_point(b.global_position): _release_body_from_safety_wall(b,creature_rect)
			continue
		if b.Type != ball.Ball_Type.Ball:
			continue
		if b.health <= 0 or (b.state_machine != null and b.state_machine.current_state == ball.State.Die):
			continue
		if b.has_meta(&"map_rescue_animating") and bool(b.get_meta(&"map_rescue_animating")):
			continue

		# 明确允许离场的运行时单位（例如黑帮普通小弟跑路）不执行地图越界救回。
		# 它们会由自身脚本在真正跑出边界后 queue_free()。
		if b.has_meta(&"submission_allow_map_escape") and bool(b.get_meta(&"submission_allow_map_escape")):
			continue

		var old_pos:Vector2 = b.global_position
		# 传送门地图：按角色所在 / 最近的岛判断挤出。
		var map_rect:Rect2 = nearest_map_island_rect(old_pos,island_rects)
		if map_rect.size.x <= 0.0:
			continue

		# 服务员门例外：
		# - 任意角色正在穿门时有短暂 grace，不会刚跨线就被自动拉回；
		# - 敌人确实从门内跨到门外后持续豁免自动回拉，直到它自己重新进入地图。
		if b.has_meta(&"waiter_door_escape_exempt") and bool(b.get_meta(&"waiter_door_escape_exempt")):
			if map_rect.has_point(old_pos):
				b.remove_meta(&"waiter_door_escape_exempt")
				if b.has_meta(&"waiter_door_escape_id"):
					b.remove_meta(&"waiter_door_escape_id")
			else:
				continue
		if b.has_meta(&"waiter_door_passage_grace_until_msec"):
			var grace_until:int = int(b.get_meta(&"waiter_door_passage_grace_until_msec",0))
			if Time.get_ticks_msec() < grace_until and not map_rect.has_point(old_pos):
				continue
			if Time.get_ticks_msec() >= grace_until:
				b.remove_meta(&"waiter_door_passage_grace_until_msec")

		# 关键修复：角色中心仍在地图内时，不做动画纠正。
		# 安全墙本身已经负责阻止 CharacterBody2D 穿出边界，move_and_slide()
		# 会自然保留沿墙切向速度，因此贴墙移动不会再出现 0.2 秒停顿。
		# 只有碰撞体真的嵌进安全墙（拥挤时角色间的穿透修正会把人挤进墙）才原地移回。
		if map_rect.has_point(old_pos):
			_release_body_from_safety_wall(b,map_rect)
			continue

		# 中心确实已经在地图外：只有离边界不远时才动画救回；
		# 很远的位置继续交给原有“越界 3 秒死亡”规则。
		var nearest_raw:Vector2 = Vector2(
			clampf(old_pos.x,map_rect.position.x,map_rect.end.x),
			clampf(old_pos.y,map_rect.position.y,map_rect.end.y)
		)
		if old_pos.distance_to(nearest_raw) > maxf(map_squeeze_rescue_distance,0.0):
			continue

		# The collision shape may be offset from the character origin (AutoFit/manual bodies).
		# Center +/- half-size alone can place that shape back inside the same solid wall.
		var corrected:Vector2 = _map_free_body_position(b,map_rect,old_pos,3)
		var correction:Vector2 = corrected - old_pos
		if correction.length_squared() <= 0.0001:
			continue

		var incoming_velocity:Vector2 = b.velocity
		b.velocity = Vector2.ZERO
		b.Repel = Vector2.ZERO
		_animate_ball_back_inside_map(b,corrected)

		# 真正被挤出边界时才给一次向内的反弹反馈；普通撞墙不走这里。
		var inward:Vector2 = correction.normalized()
		if inward.length_squared() > 0.0001:
			if b.direction.length_squared() <= 0.0001:
				b.direction = inward
			elif b.direction.dot(inward) < 0.0:
				var incoming_dir:Vector2 = b.direction.normalized()
				var feedback_power:float = maxf(incoming_velocity.length(),maxf(b.Speed,80.0))
				b.direction = b.direction.bounce(inward).normalized()
				if b.is_multiplayer_authority() and b.has_method("notify_bounce_feedback"):
					b.notify_bounce_feedback(incoming_dir,feedback_power,null)


func _release_body_from_safety_wall(b:ball,map_rect:Rect2) -> void:
	if not b.get_collision_mask_value(1) or b.collision_layer == 0 or b.has_meta(&"waiter_door_passage_grace_until_msec"): return
	var extents:Rect2=_body_extents_from_origin(b)
	var body:Rect2=Rect2(b.global_position+extents.position,extents.size)
	var depth:float=maxf(maxf(map_rect.position.x-body.position.x,body.end.x-map_rect.end.x),maxf(map_rect.position.y-body.position.y,body.end.y-map_rect.end.y))
	if depth<=MAP_WALL_EMBED_TOLERANCE: return
	var collision:CollisionShape2D=b.collision_shape_2d
	if not is_instance_valid(collision) or collision.shape==null: return
	var query:=PhysicsShapeQueryParameters2D.new()
	query.shape=collision.shape
	query.transform=collision.global_transform
	query.collision_mask=1
	query.margin=-MAP_WALL_EMBED_TOLERANCE
	var in_wall:bool=false
	for hit:Dictionary in get_world_2d().direct_space_state.intersect_shape(query,8):
		var collider:Object=hit.get("collider")
		if collider!=null and collider.has_meta(&"map_safety_wall"):
			in_wall=true
			break
	if not in_wall: return
	# Pulling straight back can land on the body that wedged it into the wall (e.g. a bat
	# between a sheep and the wall), which shoves it straight back in; take a clear spot.
	var target:Vector2=_map_free_body_position(b,map_rect,b.global_position,4)
	if target.distance_squared_to(b.global_position)>0.0001: b.global_position=target

func _animate_ball_back_inside_map(b:ball,target_position:Vector2,entry_seconds:float=-1.0) -> void:
	if b == null or not is_instance_valid(b) or not is_multiplayer_authority():
		return
	if b.has_meta(&"map_rescue_animating") and bool(b.get_meta(&"map_rescue_animating")):
		return
	b.set_meta(&"map_rescue_animating",true)
	b.set_meta("map_rescue_target",target_position)
	var had_physics:bool = b.is_physics_processing()
	b.set_meta(&"map_rescue_had_physics",had_physics)
	b.set_physics_process(false)
	# Root processing does not disable the child state machine that calls move_and_slide().
	# The shared Tween owns motion for BOTH ordinary recovery and wheel entry.
	b.set_meta("map_rescue_state_physics",b.state_machine.is_physics_processing() if b.state_machine!=null else false)
	if b.state_machine!=null: b.state_machine.set_physics_process(false)
	var tween:Tween = create_tween().bind_node(b)
	if entry_seconds>0.0:
		b.set_meta("queue_entry_z",b.z_index)
		b.set_meta("queue_entry_z_relative",b.z_as_relative)
		b.z_as_relative=false
		b.z_index=95 # Visible outside the map crop; restore the original depth on entry.
		b.direction=b.global_position.direction_to(target_position)
		tween.set_trans(Tween.TRANS_LINEAR)
	else:
		tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(b,"global_position",target_position,entry_seconds if entry_seconds>0.0 else maxf(map_rescue_animation_duration,0.05))
	# Tween.finished() 自身不携带参数。这里绑定 WeakRef 而不是把自定义
	# class_name ball 作为强类型回调参数，避免脚本热重载后出现
	# “Cannot convert argument 1 from Object to Object”的类身份不一致错误。
	tween.finished.connect(_finish_ball_map_rescue.bind(weakref(b)))
	_guard_queue_entry_tween(weakref(b),tween)


func _guard_queue_entry_tween(b_ref:WeakRef,tween:Tween) -> void:
	while tween.is_valid() and is_inside_tree():
		var actor:Variant=b_ref.get_ref()
		if not is_instance_valid(actor) or actor.is_queued_for_deletion(): return
		if not actor.has_meta("map_rescue_animating"): return
		if actor.health<=0:
			tween.kill()
			_finish_ball_map_rescue(b_ref)
			return
		if is_combat_runtime_active(): tween.play()
		else: tween.pause()
		await get_tree().physics_frame

func _finish_ball_map_rescue(b_ref:WeakRef) -> void:
	if b_ref == null:
		return
	var obj:Variant = b_ref.get_ref()
	if obj == null or not is_instance_valid(obj):
		return
	# 不在函数签名里使用自定义 ball 类型；对象本身仍然是原角色实例。
	var b:Variant = obj
	if b.has_meta("queue_entry_z"):
		b.z_index=int(b.get_meta("queue_entry_z"))
		b.z_as_relative=bool(b.get_meta("queue_entry_z_relative"))
		for key:String in ["queue_entry_z","queue_entry_z_relative"]: b.remove_meta(key)
	if b.has_meta("map_rescue_state_physics"):
		if b.state_machine!=null: b.state_machine.set_physics_process(bool(b.get_meta("map_rescue_state_physics")))
		b.remove_meta("map_rescue_state_physics")
	# A wheel entry already running during script reload may still own the old key.
	elif b.has_meta("queue_entry_state_physics"):
		if b.state_machine!=null: b.state_machine.set_physics_process(bool(b.get_meta("queue_entry_state_physics")))
	if b.has_meta("queue_entry_state_physics"): b.remove_meta("queue_entry_state_physics")
	var restore_physics:bool = bool(b.get_meta(&"map_rescue_had_physics",true))
	b.set_physics_process(restore_physics)
	b.remove_meta(&"map_rescue_had_physics")
	b.remove_meta(&"map_rescue_animating")
	if b.has_meta("map_rescue_target"): b.remove_meta("map_rescue_target")
	b.velocity = Vector2.ZERO
	b.Repel = Vector2.ZERO


func _body_extents_from_origin(b:ball) -> Rect2:
	# Include the root as well, since the existing boundary rule tests root position.
	var lower:Vector2=Vector2.ZERO
	var upper:Vector2=Vector2.ZERO
	var collision:CollisionShape2D=b.collision_shape_2d
	if is_instance_valid(collision) and collision.shape!=null:
		var local_rect:Rect2=collision.shape.get_rect()
		for corner:Vector2 in [local_rect.position,Vector2(local_rect.end.x,local_rect.position.y),local_rect.end,Vector2(local_rect.position.x,local_rect.end.y)]:
			var relative:Vector2=collision.global_transform*corner-b.global_position
			lower=lower.min(relative);upper=upper.max(relative)
	else:
		lower=-_ball_collision_world_half_extents(b);upper=-lower
	return Rect2(lower,upper-lower)

func _map_safe_body_position(b:ball,map_rect:Rect2,wanted:Vector2) -> Vector2:
	var extents:Rect2=_body_extents_from_origin(b)
	var lower:Vector2=extents.position
	var upper:Vector2=extents.end
	var padding:Vector2=Vector2.ONE*maxf(map_squeeze_rescue_padding,b.safe_margin)
	var minimum:Vector2=map_rect.position+padding-lower
	var maximum:Vector2=map_rect.end-padding-upper
	# Do not shrink oversized actors or issue an inverted clamp on an impossible island.
	if minimum.x>maximum.x or minimum.y>maximum.y: return wanted
	return wanted.clamp(minimum,maximum)

# Bodies spawned or moved onto the same point get identical depenetration every physics
# frame and are shoved through the safety wall together; give each one its own spot.
# For summons placed beside their owner: nearest clear spot fully inside the map walls.
func map_free_spawn_position(b:ball,wanted:Vector2) -> Vector2:
	var map_node:Node=_current_map_node()
	if b==null or map_node==null: return wanted
	var map_rect:Rect2=nearest_map_island_rect(wanted,map_island_rects(map_node))
	if map_rect.size.x<=1.0 or map_rect.size.y<=1.0: return wanted
	return _map_free_body_position(b,map_rect,wanted,4)

func _map_free_body_position(b:ball,map_rect:Rect2,wanted:Vector2,max_rings:int=6,reserved:Array=[]) -> Vector2:
	var extents:Rect2=_body_extents_from_origin(b)
	var size:Vector2=extents.size.max(Vector2.ONE*4.0)
	var occupied:Array[Rect2]=[]
	for point:Variant in reserved:
		if point is Vector2: occupied.append(Rect2(point+extents.position,size))
	for unit:Variant in _battle_units_cache:
		if unit==b or not is_instance_valid(unit) or unit.is_queued_for_deletion() or not unit is ball: continue
		var other:ball=unit as ball
		if (other.Type!=ball.Ball_Type.Ball and other.Type!=ball.Ball_Type.Creature) or other.collision_layer==0 or other.health<=0 or other.has_meta("development_reserve") or other.has_meta("rotation_prestart_preview"): continue
		var at:Vector2=other.get_meta("map_rescue_target",other.global_position) if other.has_meta("map_rescue_animating") else other.global_position
		var other_extents:Rect2=_body_extents_from_origin(other)
		occupied.append(Rect2(at+other_extents.position,other_extents.size))
	var base:Vector2=_map_safe_body_position(b,map_rect,wanted)
	var best:Vector2=base
	var best_overlap:float=INF
	var step:float=maxf(size.x,size.y)*0.6
	for ring:int in range(max_rings+1):
		var count:int=1 if ring==0 else ring*8
		for i:int in range(count):
			var offset:Vector2=Vector2.ZERO if ring==0 else Vector2.from_angle(TAU*float(i)/float(count)+float(ring)*0.37)*step*float(ring)
			var candidate:Vector2=_map_safe_body_position(b,map_rect,base+offset)
			var body:Rect2=Rect2(candidate+extents.position,size)
			var overlap:float=0.0
			for other_rect:Rect2 in occupied:
				if body.intersects(other_rect): overlap+=body.intersection(other_rect).get_area()
			if overlap<=0.0: return candidate
			if overlap<best_overlap-0.01:
				best_overlap=overlap
				best=candidate
	return best

# Placed templates keep their formation spot (only pulled out of walls or off an exactly
# coincident body); quantity copies search a free spot and avoid the round's planned spots.
func _settle_rotation_spawn(actor:ball,keep_placement:bool,reserved:Array=[]) -> void:
	if actor==null or not is_instance_valid(actor) or not is_multiplayer_authority(): return
	var map_node:Node=_current_map_node()
	if map_node==null: return
	var map_rect:Rect2=nearest_map_island_rect(actor.global_position,map_island_rects(map_node))
	if map_rect.size.x<=0.0: return
	if keep_placement:
		var safe:Vector2=_map_safe_body_position(actor,map_rect,actor.global_position)
		var coincident:bool=false
		for unit:Variant in _battle_units_cache:
			if unit==actor or not is_instance_valid(unit) or unit.is_queued_for_deletion() or not unit is ball or unit.has_meta("rotation_prestart_preview"): continue
			if (unit as ball).Type==ball.Ball_Type.Ball and (unit as ball).health>0 and (unit as ball).global_position.distance_squared_to(safe)<1.0:
				coincident=true
				break
		actor.global_position=_map_free_body_position(actor,map_rect,safe) if coincident else safe
	else:
		actor.global_position=_map_free_body_position(actor,map_rect,actor.global_position,6,reserved)

func _ball_collision_world_half_extents(b:ball) -> Vector2:
	if b == null or not is_instance_valid(b) or b.collision_shape_2d == null:
		return Vector2(14.0,14.0)
	var shape = b.collision_shape_2d.shape
	var xform:Transform2D = b.collision_shape_2d.global_transform
	var basis_x:Vector2 = xform.x
	var basis_y:Vector2 = xform.y

	if shape is RectangleShape2D:
		var half:Vector2 = (shape as RectangleShape2D).size * 0.5
		return Vector2(
			absf(basis_x.x) * half.x + absf(basis_y.x) * half.y,
			absf(basis_x.y) * half.x + absf(basis_y.y) * half.y
		)
	if shape is CircleShape2D:
		var radius:float = (shape as CircleShape2D).radius
		return Vector2(
			radius * (absf(basis_x.x) + absf(basis_y.x)),
			radius * (absf(basis_x.y) + absf(basis_y.y))
		)
	if shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		var half:Vector2 = Vector2(capsule.radius,capsule.height * 0.5)
		return Vector2(
			absf(basis_x.x) * half.x + absf(basis_y.x) * half.y,
			absf(basis_x.y) * half.x + absf(basis_y.y) * half.y
		)

	return Vector2(14.0,14.0)


#========================================================
# 出界淘汰：角色连续离开地图 3 秒后死亡。
# 回到地图范围内会取消倒计时，主要用于清理被挤/传送到墙外后无法回来的角色。
#========================================================
func _process_out_of_bounds_rule(delta:float,ball_group:Array = []) -> void:
	if not out_of_bounds_enabled:
		_clear_all_out_of_bounds_states()
		return
	var map_node:Node = _current_map_node()
	if map_node == null:
		_clear_all_out_of_bounds_states()
		return

	var island_rects:Array[Rect2] = map_island_rects(map_node)
	if out_of_bounds_margin > 0.0:
		for i:int in range(island_rects.size()):
			island_rects[i] = island_rects[i].grow(out_of_bounds_margin)

	var active_ids:Dictionary = {}
	for node in ball_group:
		if not node is ball:
			continue
		var b:ball = node as ball
		if b.has_meta("development_reserve"):
			continue
		# 这里只处理真正角色；子弹和召唤物有自己的生命周期。
		if b.Type != ball.Ball_Type.Ball:
			continue

		var id:int = b.get_instance_id()
		active_ids[id] = true

		if b.health <= 0 or (b.state_machine != null and b.state_machine.current_state == ball.State.Die):
			_clear_out_of_bounds_state(id)
			continue

		# V187：寸头猪的地图外一次性袭击者需要从地图外走到边界再离场。
		# 这类角色由猪脚本自己管理生命周期，绝不能触发通用“地图外 3 秒死亡”。
		if b.has_meta(&"pig_outside_guest_exempt") and bool(b.get_meta(&"pig_outside_guest_exempt")):
			_clear_out_of_bounds_state(id)
			continue

		# V100：复用地图挤出保护已经使用的通用合法越界标记。
		# 堵桥等技能角色主动跑到地图外时，由角色自己负责何时返回，不能被 3 秒越界规则击杀。
		if b.has_meta(&"submission_allow_map_escape") and bool(b.get_meta(&"submission_allow_map_escape")):
			_clear_out_of_bounds_state(id)
			continue

		if map_contains_point(b.global_position,island_rects):
			_clear_out_of_bounds_state(id)
			continue

		var entry:Dictionary
		if not _out_of_bounds_states.has(id):
			entry = {
				"node": b,
				"elapsed": 0.0
			}
			_out_of_bounds_states[id] = entry
		else:
			entry = _out_of_bounds_states[id]

		entry["elapsed"] = float(entry.get("elapsed",0.0)) + delta
		_out_of_bounds_states[id] = entry

		if float(entry["elapsed"]) >= maxf(out_of_bounds_death_delay,0.1):
			# 出界淘汰属于地图规则，标记后让猫这类“多条命”角色也直接结束本局，
			# 防止它在地图外原地复活九次。
			b.set_meta(&"__out_of_bounds_forced_death",true)
			b.block = 0
			if b.health_bar != null:
				b.health_bar.suppress_floating_text = true
			b.health = 0
			if b.health_bar != null:
				b.health_bar.suppress_floating_text = false
			_clear_out_of_bounds_state(id)

	# 清除已经删除/换形的旧节点留下的计时状态。
	for raw_id in _out_of_bounds_states.keys().duplicate():
		var stale_id:int = int(raw_id)
		if not active_ids.has(stale_id):
			_clear_out_of_bounds_state(stale_id)


func _clear_out_of_bounds_state(id:int) -> void:
	if not _out_of_bounds_states.has(id):
		return
	_out_of_bounds_states.erase(id)


func _clear_all_out_of_bounds_states() -> void:
	for raw_id in _out_of_bounds_states.keys().duplicate():
		_clear_out_of_bounds_state(int(raw_id))


#控制角色buff
#恢复默认属性
func set_ball_properties_to_dafault(group:Array) -> void:
	var training_mode:bool = Game.is_training_mode()
	for b:ball in group:
		# 原逻辑每个 physics tick 都从 default_properties 恢复属性。
		# 训练人物先把默认 Max_health 也锁到 9999，防止第一次受击时瞬间恢复原上限。
		# V410：两个接口都定义在 ball 基类，直接调用，移除 60Hz × 人数的 has_method/call 反射。
		if training_mode and b.Type == ball.Ball_Type.Ball:
			b.training_prepare_property_reset()
		# V379：固定 9 项运行时属性走 ball 的直接字段恢复，不再每单位每物理帧
		# Dictionary 遍历 + str() + 动态属性索引。default_properties 仍是唯一默认值来源。
		b.restore_default_runtime_properties_fast()
#设置buff
func new_buff(char:ball,from,buff_name:String,buff:Buff,mode:String = "cover") -> void:
	from = from if typeof(from) == 2 else from.get_instance_id()
	
	if not from in char.Buff_Dic:
		char.Buff_Dic[from] = {}

	if mode == "cover":
		if not buff_name in char.Buff_Dic[from]:
			char.Buff_Dic[from][buff_name] = Buff.new()
		
		char.Buff_Dic[from][buff_name] = buff
	elif mode == "delete" and buff_name in char.Buff_Dic[from]:
		char.Buff_Dic[from].erase(buff_name)
	elif mode == "add":
		if not buff_name in char.Buff_Dic[from]:
			char.Buff_Dic[from][buff_name] = buff
		else:
			char.Buff_Dic[from][buff_name].duration = buff.duration
			char.Buff_Dic[from][buff_name].amount += buff.amount
	elif mode == "mul":
		if not buff_name in char.Buff_Dic[from]:
			char.Buff_Dic[from][buff_name] = buff
		else:
			char.Buff_Dic[from][buff_name].duration = buff.duration
			char.Buff_Dic[from][buff_name].amount *= buff.amount

# V379：Buff_types 的前 9 项与 ball.default_properties 一一对应。
# 旧热循环每处理一个 Buff 都调用 Buff.Buff_types.keys() 重新构造键数组；
# 角色/Buff 数量上升时会形成大量短命 Array。固定表只创建一次。
const BUFF_RUNTIME_PROPERTY_NAMES:Array = [
	"Damage",
	"Speed",
	"max_block",
	"max_energy",
	"Max_health",
	"Attack_Cooling",
	"Skill_Cooling",
	"Health_Restore",
	"Damage_reduction",
]

func _apply_runtime_property_buff(b:ball,buff:Buff) -> void:
	if buff.buff_type >= 0 and buff.buff_type < BUFF_RUNTIME_PROPERTY_NAMES.size():
		var property_name:String = String(BUFF_RUNTIME_PROPERTY_NAMES[buff.buff_type])
		if property_name in b.default_properties:
			if buff.algorithm == Buff.Algorithms.add: b[property_name] += buff.amount
			elif buff.algorithm == Buff.Algorithms.mul: b[property_name] *= buff.amount
			elif buff.algorithm == Buff.Algorithms.Set: b[property_name] = buff.amount

func refresh_runtime_buffs(b:ball) -> void:
	# Immediate refresh after cleansing, using the same property math as the
	# normal tick; never advance duration, poison/parasite ticks or global clocks.
	if not is_instance_valid(b) or not b.is_multiplayer_authority(): return
	b.restore_default_runtime_properties_fast()
	for index:int in range(4):
		for source_buffs:Dictionary in b.Buff_Dic.values():
			for buff:Buff in source_buffs.values():
				if buff.index==index and buff.duration>0.0: _apply_runtime_property_buff(b,buff)

var process_time:float =  0
func figure_buffs(delta:float,group:Array) -> void:
	if not is_multiplayer_authority():
		return
	process_time += delta

	# V411：scratch Array 跨帧复用；筛选规则与旧版完全一致。
	_buffed_group_scratch.clear()
	for candidate:ball in group:
		if (
			(candidate.Type == ball.Ball_Type.Ball or candidate.Type == ball.Ball_Type.Creature)
			and not candidate.Buff_Dic.is_empty()
		):
			_buffed_group_scratch.append(candidate)

	for i in 4:#从0到3按索引加效果
		for b:ball in _buffed_group_scratch:
			for come_from:int in b.Buff_Dic:
				var source_buffs:Dictionary = b.Buff_Dic[come_from]
				_buff_delete_scratch.clear()

				for buff_name:String in source_buffs:
					var buff:Buff = source_buffs[buff_name]
					if buff.index != i:
						continue

					_apply_runtime_property_buff(b,buff)

					if process_time >= 1 and buff.buff_type == Buff.Buff_types.poison:
						Audios.play_sfx.rpc(
							"balls_hit1",
							{volume = clampf(buff.amount - 12,-100,0)},
							true
						)
						b.receive_spatial_raw_health_damage(
							buff.amount,
							{"shape":"all","damage_kind":"poison","carrier":"status_tick"}
						)

					buff.duration -= delta
					if buff.duration <= 0:
						_buff_delete_scratch.append(buff_name)

				for btd in _buff_delete_scratch:
					if btd == "寄生":
						set_status_image.rpc(infection_texture,b.global_position)
						Audios.play_sfx.rpc("寄生",{},true)
						var parasite_buff:Buff = source_buffs.get(btd,null) as Buff
						if parasite_buff != null:
							b.receive_spatial_damage(
								3 * 2 * parasite_buff.amount,
								{"shape":"all"},
								true
							)

					source_buffs.erase(btd)

	if process_time >= 1:
		process_time = 0


func is_toolbar_open() -> bool:
	return control != null and control.visible


func request_cinematic_focus(
	source:Node,
	target:Node2D,
	slow_factor:float = -1.0,
	zoom_multiplier:float = -1.0
) -> void:
	if source == null or not is_instance_valid(source) or target == null or not is_instance_valid(target):
		return
	var source_id:int = source.get_instance_id()
	var resolved_slow:float = cinematic_focus_default_slow_factor if slow_factor <= 0.0 else slow_factor
	var resolved_zoom:float = cinematic_focus_default_zoom_multiplier if zoom_multiplier <= 0.0 else zoom_multiplier
	_cinematic_focus_requests[source_id] = {
		"source":weakref(source),
		"target":weakref(target),
		"slow":clampf(resolved_slow,0.05,1.0),
		"zoom":clampf(resolved_zoom,1.0,2.5),
	}
	_recompute_cinematic_focus_state()


func release_cinematic_focus(source:Node) -> void:
	if source == null:
		return
	_cinematic_focus_requests.erase(source.get_instance_id())
	_recompute_cinematic_focus_state()


func _prune_cinematic_focus_requests() -> void:
	for raw_key:Variant in _cinematic_focus_requests.keys():
		var request:Variant = _cinematic_focus_requests.get(raw_key,null)
		if not request is Dictionary:
			_cinematic_focus_requests.erase(raw_key)
			continue
		var source_ref:Variant = request.get("source",null)
		var target_ref:Variant = request.get("target",null)
		var source_obj:Variant = source_ref.get_ref() if source_ref is WeakRef else null
		var target_obj:Variant = target_ref.get_ref() if target_ref is WeakRef else null
		if source_obj == null or not is_instance_valid(source_obj) or target_obj == null or not is_instance_valid(target_obj):
			_cinematic_focus_requests.erase(raw_key)


func _resolve_cinematic_focus_center() -> Vector2:
	_prune_cinematic_focus_requests()
	if _cinematic_focus_requests.is_empty():
		return _cinematic_focus_anchor
	var total:Vector2 = Vector2.ZERO
	var count:int = 0
	for raw_request:Variant in _cinematic_focus_requests.values():
		if not raw_request is Dictionary:
			continue
		var target_ref:Variant = raw_request.get("target",null)
		var target_obj:Variant = target_ref.get_ref() if target_ref is WeakRef else null
		if target_obj is Node2D and is_instance_valid(target_obj):
			total += (target_obj as Node2D).global_position
			count += 1
	if count <= 0:
		return _cinematic_focus_anchor
	return total / float(count)


func _recompute_cinematic_focus_state() -> void:
	_prune_cinematic_focus_requests()
	var active:bool = not _cinematic_focus_requests.is_empty()
	var target_zoom:float = 1.0
	var slow_factor:float = 1.0
	if active:
		_cinematic_focus_anchor = _resolve_cinematic_focus_center()
		for raw_request:Variant in _cinematic_focus_requests.values():
			if not raw_request is Dictionary:
				continue
			var request:Dictionary = raw_request
			target_zoom = maxf(target_zoom,float(request.get("zoom",cinematic_focus_default_zoom_multiplier)))
			slow_factor = minf(slow_factor,float(request.get("slow",cinematic_focus_default_slow_factor)))
		Game.request_time_scale_override(CINEMATIC_FOCUS_TIME_KEY,slow_factor,Color(0.0,0.0,0.0,0.0))
	else:
		Game.release_time_scale_override(CINEMATIC_FOCUS_TIME_KEY)

	if _cinematic_focus_tween != null and _cinematic_focus_tween.is_valid():
		_cinematic_focus_tween.kill()
	_cinematic_focus_tween = create_tween()
	# 镜头转场必须按真实时间执行，否则 0.25x 慢动作会把镜头移动也拖成四倍时长。
	_cinematic_focus_tween.set_ignore_time_scale(true)
	_cinematic_focus_tween.set_parallel(true)
	_cinematic_focus_tween.set_trans(Tween.TRANS_QUART)
	_cinematic_focus_tween.set_ease(Tween.EASE_OUT)
	var duration:float = cinematic_focus_enter_duration if active else cinematic_focus_exit_duration
	_cinematic_focus_tween.tween_property(self,"_cinematic_focus_weight",1.0 if active else 0.0,maxf(duration,0.01))
	_cinematic_focus_tween.tween_property(self,"_cinematic_focus_zoom_multiplier",target_zoom,maxf(duration,0.01))


func _fit_zoom_for_map(map_node:Node) -> float:
	if map_node == null or not is_instance_valid(map_node):
		return 0.0
	var map_rect:Rect2 = return_map_shadow_rect(map_node)
	if map_rect.size.x <= 1.0 or map_rect.size.y <= 1.0:
		return 0.0
	var viewport_size:Vector2 = get_viewport_rect().size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		return 0.0
	var ratio:float = clampf(map_fit_viewport_ratio,0.50,1.0)
	return minf(
		viewport_size.x / map_rect.size.x,
		viewport_size.y / map_rect.size.y
	) * ratio


func _base_camera_zoom_value() -> float:
	# 旧版 Map10x10 的基础 Camera2D zoom 就是 5.0。
	# 这里把它作为绝对视觉锚点，不允许“fit viewport”算法重新把 10x10 缩小。
	var reference_zoom:float = maxf(map_reference_zoom,0.05)
	if map_reference_name.is_empty():
		reference_zoom = maxf(camera_zoom,0.05)

	if now_choose_map == map_reference_name:
		if map_group.has(now_choose_map):
			return minf(reference_zoom,maxf(_fit_zoom_for_map(map_group[now_choose_map]),0.05))
		return reference_zoom

	var current_node:Node = _current_map_node()
	if current_node == null:
		return reference_zoom

	var current_map:Node = current_node
	var current_fit:float = _fit_zoom_for_map(current_map)
	if current_fit <= 0.0:
		return reference_zoom

	if map_group.has(map_reference_name) and map_group[map_reference_name] is TileMapLayer:
		var reference_map:TileMapLayer = map_group[map_reference_name] as TileMapLayer
		var current_rect:Rect2 = return_map_world_rect(current_map)
		var reference_rect:Rect2 = return_map_world_rect(reference_map)

		# 只要当前地图任一方向比 10x10 基准更大，就优先保证整张地图能看到。
		# 10x10 本身仍走上面的固定 zoom=5 分支，不受这一规则影响。
		if current_rect.size.x > reference_rect.size.x + 0.5 or current_rect.size.y > reference_rect.size.y + 0.5:
			return maxf(current_fit,0.05)

		# 小地图按 10x10 的旧视觉大小做相对校准，减少四周空白。
		var reference_fit:float = _fit_zoom_for_map(reference_map)
		if reference_fit > 0.0:
			var calibrated_zoom:float = current_fit * (reference_zoom / reference_fit)
			var max_small_map_zoom:float = reference_zoom * maxf(small_map_max_zoom_multiplier,1.0)
			return clampf(calibrated_zoom,0.05,max_small_map_zoom)

	return maxf(current_fit,0.05)


func get_effective_camera_zoom() -> float:
	# V405：死档期间视角等价于关闭“镜头跟随”；不能继续继承尚未退场的电影镜头放大倍率，
	# 否则即使中心已经切到地图中心，看起来仍像角色特写。保留玩家自己的工具栏缩放倍率。
	var cinematic_multiplier:float = 1.0 if _dead_save_force_non_follow_camera else _cinematic_focus_zoom_multiplier
	var impact_multiplier:float = 1.0 if _dead_save_force_non_follow_camera else lerpf(1.0,_damage_focus_peak_zoom,_damage_focus_weight)
	var intro_multiplier:float = lerpf(1.0,_intro_camera_peak,_intro_camera_weight)
	return maxf(_base_camera_zoom_value() * toolbar_zoom_multiplier * cinematic_multiplier * impact_multiplier * intro_multiplier,0.05)


func _constrain_camera_center_to_keep_map_visible(desired_center:Vector2,zoom_value:float) -> Vector2:
	var map_node:Node = _current_map_node()
	if map_node == null:
		return desired_center
	var map_rect:Rect2 = return_map_visual_rect(map_node)
	var viewport_size:Vector2 = get_viewport_rect().size
	var safe_zoom:float = maxf(zoom_value,0.001)
	var half_view:Vector2 = viewport_size / (2.0 * safe_zoom)
	var result:Vector2 = desired_center
	var _center:Vector2 = map_rect.get_center()

	# 相机约束分两种情况：
	# - 视野比地图小：保证视口边缘不越出地图。
	# - 视野已经覆盖整张地图：仍允许相机中心在地图范围内移动。
	#   不能强制锁到 center，否则“镜头跟随”和中键平移在默认 fit 视角都会完全失效。
	if half_view.x < map_rect.size.x * 0.5:
		result.x = clampf(
			result.x,
			map_rect.position.x + half_view.x,
			map_rect.end.x - half_view.x
		)
	else:
		result.x = clampf(result.x,map_rect.position.x,map_rect.end.x)

	if half_view.y < map_rect.size.y * 0.5:
		result.y = clampf(
			result.y,
			map_rect.position.y + half_view.y,
			map_rect.end.y - half_view.y
		)
	else:
		result.y = clampf(result.y,map_rect.position.y,map_rect.end.y)
	return result


func _apply_camera_zoom() -> void:
	if camera_2d == null or not is_instance_valid(camera_2d):
		return
	var zoom_value:float = get_effective_camera_zoom()
	camera_2d.zoom = Vector2(zoom_value,zoom_value)


func pan_toolbar_view_by_screen_delta(screen_delta:Vector2) -> void:
	# 中键拖动采用“抓住地图”的手感：鼠标往右拖，画面内容也往右走，
	# 因此 Camera2D 世界中心向相反方向移动。screen_delta 是真实屏幕像素，
	# 除以 zoom 后得到对应的世界位移；这样 X/Y 灵敏度完全一致。
	# 中键平移不再依赖工具栏展开状态。
	if screen_delta.is_zero_approx():
		return
	var effective_zoom:float = maxf(get_effective_camera_zoom(),0.001)
	mouse_offset -= screen_delta / effective_zoom


func toolbar_zoom_at_screen_position(
	screen_position:Vector2,
	wheel_direction:int,
	scroll_factor:float = 1.0
) -> void:
	# V224：缩放能力不再依赖工具栏可见性。工具栏关闭只隐藏UI，
	# 已有倍率继续保留，并且 Alt+滚轮仍可继续调整。
	if wheel_direction == 0:
		return

	var factor:float = absf(scroll_factor)
	if factor <= 0.001:
		factor = 1.0

	var old_multiplier:float = toolbar_zoom_multiplier
	var step_multiplier:float = pow(maxf(toolbar_zoom_step,1.001),factor)
	if wheel_direction > 0:
		toolbar_zoom_multiplier *= step_multiplier
	else:
		toolbar_zoom_multiplier /= step_multiplier

	toolbar_zoom_multiplier = clampf(
		toolbar_zoom_multiplier,
		minf(toolbar_zoom_min_multiplier,toolbar_zoom_max_multiplier),
		maxf(toolbar_zoom_min_multiplier,toolbar_zoom_max_multiplier)
	)
	if is_equal_approx(old_multiplier,toolbar_zoom_multiplier):
		return

	# 缩放前先记录鼠标指向的世界坐标。
	# 之后立即更新 Camera2D，再反算一次同一个屏幕坐标；
	# 两者差值补进 mouse_offset，因此鼠标指着的位置会尽量留在原地。
	var viewport := get_viewport()
	var before_world:Vector2 = (
		viewport.get_canvas_transform().affine_inverse() * screen_position
	)

	_apply_camera_zoom()
	camera_2d.force_update_scroll()

	var after_world:Vector2 = (
		viewport.get_canvas_transform().affine_inverse() * screen_position
	)
	var anchor_delta:Vector2 = before_world - after_world

	mouse_offset += anchor_delta
	camera_2d.global_position += anchor_delta
	camera_2d.force_update_scroll()


func reset_toolbar_view() -> void:
	mouse_offset = Vector2.ZERO
	toolbar_zoom_multiplier = 1.0
	_apply_camera_zoom()
	if camera_2d != null and is_instance_valid(camera_2d):
		camera_2d.force_update_scroll()


func clear_mouse_drag_offset() -> void:
	mouse_offset = Vector2.ZERO


func set_menu() -> void:
	if random_character_draft.playing: return
	if control.visible and random_character_draft.is_enabled() and not random_character_draft.pending.is_empty():
		if random_character_draft.pool().is_empty():
			control.team.hide()
			control.game_setting.show()
			control._show_settings_category("training")
			control._sync_character_mode_controls()
			return
		if is_multiplayer_authority(): random_character_draft.start()
		elif Game.can_local_manage_world(): Game.request_random_character_draw.rpc_id(Game.Server_Id)
		return
	control.set_menu()

	# V35：M 关闭顶部工具栏时终止当前拖动，但保留玩家已经调整好的缩放倍率。
	# 只有时间正在正常流动时才把中键平移偏移归零；暂停中关闭工具栏时保留取景位置，
	# 方便暂停观察。缩放不再跟随工具栏关闭而复位。
	if not is_toolbar_open():
		Game.mouse_drag = false
		Game.world_middle_drag = false
		if not Game.now_stop_state and not get_tree().paused and Engine.time_scale > 0.000001:
			clear_mouse_drag_offset()
	
# ========================================================
# 战斗临时节点清理
# 炸弹、矿工石头、影子分身和短命特效并不都继承 ball，
# 因此不能只依赖 Ball/Shooter 组。统一通过 BattleTransient 清场。
# 同时保留旧组名兼容已经生成/旧版本的炸弹和石头。
# ========================================================
func _clear_battle_transients() -> void:
	var seen:Dictionary = {}
	# 共享地形破坏保留了原始碰撞和贴图，必须在清理对象前立即恢复。
	var terrain_damage:Node = get_node_or_null("GhastObstacleDamage")
	if terrain_damage != null: terrain_damage.reset_all()

	# 新版所有运行时战斗对象统一进 BattleTransient。
	# 其余组名保留用于兼容已经生成的旧版本对象。
	for group_name:String in [
		"BattleTransient",
		"BomberBomb",
		"MinerStone",
		"ShadowVisual",
		"OfficerNuke",
		"GuardReinforcementRequest", # Cancel confirmed arrivals during reset/round retirement.
		# V43：这两类运行时节点挂在 World 下，不随角色父节点自动释放。
		# 专用组只用于清场，不加入 BattleTransient，避免菜月昴时间轴把无 PackedScene 的
		# Line2D / script.new() 行情柱当成可重建快照对象。
		"ShieldDogHookVisual",
		"InvestorStockBar"
	]:
		for node:Node in get_tree().get_nodes_in_group(group_name):
			if node == null or not is_instance_valid(node):
				continue
			var instance_id:int = int(node.get_instance_id())
			if seen.has(instance_id):
				continue
			seen[instance_id] = true
			Game.free_node(node)

	# 兼容更早版本军官：旧核弹/爆炸/爆炸音效创建在 World 下，
	# 当时没有加入任何 group，Reset 无法靠 group 找到它们。
	# 动态节点的名字固定以 OfficerNuke 开头，因此 Reset 再做一次兜底扫描。
	for node:Node in find_children("*", "", true, false):
		if node == null or not is_instance_valid(node):
			continue
		if not String(node.name).begins_with("OfficerNuke"):
			continue
		var instance_id:int = int(node.get_instance_id())
		if seen.has(instance_id):
			continue
		seen[instance_id] = true
		Game.free_node(node)


@rpc("authority")
func reset() -> void:
	if not is_multiplayer_authority():
		return
	random_character_draft.cancel()
	if is_instance_valid(day_night_cycle): day_night_cycle.reset_to_noon()
	if is_instance_valid(minecraft_clouds): minecraft_clouds.reset_drift()
	if _development != null:
		_development.cleanup(false)

	_reset_victory_bell_state()
	_stop_match_fireworks()
	# Reset 是“清空战场”。在清空前保存这一套初始阵容，之后仍可点“重打”。
	if not _battle_setup.is_empty():
		_last_battle_setup = _battle_setup.duplicate(true)
		_last_battle_setup_map = _battle_setup_map
		_last_battle_random_seed = _battle_random_seed
	_mc_placement_generation += 1
	_mc_pending_placements.clear()
	_battle_setup.clear()
	_battle_setup_map = ""
	_battle_random_seed = 0
	Game.end_battle_random()
	_training_respawn_pending.clear()
	_reset_special_training_state()

	_clear_battle_transients()
	for b in get_tree().get_nodes_in_group("Ball"):
		Game.free_node(b)
	for b in get_tree().get_nodes_in_group("Shooter"):
		Game.free_node(b)
	if _development != null:
		_development.prepare()


func has_rematch_setup() -> bool:
	if Game.is_rotation_training_mode():
		return not _rotation_rosters["left"].is_empty() or not _rotation_saved_rosters["left"].is_empty()
	return not _battle_setup.is_empty() or not _last_battle_setup.is_empty()


func delete_rotation_queue_setup_id(setup_id:int,side_hint:String = "") -> bool:
	if Game.is_rotation_training_mode(): return _remove_rotation_slot(setup_id)
	if setup_id < 0:
		return false

	# 当前出战者/布阵冻结预览有真实节点时，继续走统一的 forget + free 路径，
	# 这样死亡队列、Boss 车轮战补位、胜利状态都会同步更新。
	var existing:ball = _find_character_by_setup_id_any(setup_id)
	if existing != null and is_instance_valid(existing):
		forget_battle_setup_node(existing)
		Game.free_node(existing)
		return true

	# 后续队员尚未实例化，只存在 roster 里；右键名字时直接按 setup_id 精确移除。
	var found_side:String = side_hint if side_hint in ["left","right"] else ""
	var found_index:int = -1
	if not found_side.is_empty():
		var hinted_roster:Array = _rotation_rosters[found_side]
		for i:int in range(hinted_roster.size()):
			if int((hinted_roster[i] as Dictionary).get("id",-1)) == setup_id:
				found_index = i
				break
	if found_index < 0:
		for side:String in ["left","right"]:
			var roster:Array = _rotation_rosters[side]
			for i:int in range(roster.size()):
				if int((roster[i] as Dictionary).get("id",-1)) == setup_id:
					found_side = side
					found_index = i
					break
			if found_index >= 0:
				break
	if found_side.is_empty() or found_index < 0:
		return false

	var roster:Array = _rotation_rosters[found_side]
	roster.remove_at(found_index)
	_rotation_rosters[found_side] = roster
	if found_index < int(_rotation_next_index.get(found_side,0)):
		_rotation_next_index[found_side] = maxi(0,int(_rotation_next_index[found_side]) - 1)

	for index:int in range(_battle_setup.size() - 1,-1,-1):
		if int(_battle_setup[index].get("id",-1)) == setup_id:
			_battle_setup.remove_at(index)
			break

	if not _rotation_started:
		# 预览阶段重新构建可滚动名单；人物本体只有第一位实际存在，
		# 若删的是未来队员则无需碰当前冻结预览。
		_clear_rotation_hud_labels()
		for rebuild_side:String in ["left","right"]:
			_rotation_setup_scroll_rows[rebuild_side] = 0
			for record:Dictionary in _rotation_rosters[rebuild_side]:
				_rotation_add_setup_preview_label(
					rebuild_side,
					str(record.get("char","")),
					int(record.get("id",-1))
				)
	else:
		_rotation_refresh_future_labels(found_side)
	if _development != null:
		_development.on_character_removed(setup_id)

	_reset_victory_bell_state()
	return true


func forget_battle_setup_node(node:Node) -> void:
	if node == null or not node.has_meta("battle_setup_id"):
		return
	var setup_id:int = int(node.get_meta("battle_setup_id"))
	if Game.is_rotation_training_mode() and node.has_meta("rotation_side"):
		_remove_rotation_slot(setup_id)
		return
	# 轮放/Boss车轮战的名单并不只存在于 _battle_setup。手动删除预览/当前人物时，
	# 同步从对应 roster 移除，避免删掉后又在后续轮次重新生成。
	if node.has_meta("rotation_side"):
		var queue_side:String = str(node.get_meta("rotation_side",""))
		if queue_side in ["left","right"]:
			var roster:Array = _rotation_rosters[queue_side]
			var removed_index:int = -1
			for r_i:int in range(roster.size()):
				if int((roster[r_i] as Dictionary).get("id",-1)) == setup_id:
					removed_index = r_i
					roster.remove_at(r_i)
					break
			_rotation_rosters[queue_side] = roster
			if removed_index >= 0 and removed_index < int(_rotation_next_index.get(queue_side,0)):
				_rotation_next_index[queue_side] = maxi(0,int(_rotation_next_index[queue_side]) - 1)
			var preview_raw:Variant = _rotation_preview_character.get(queue_side,null)
			if preview_raw == node:
				_rotation_preview_character[queue_side] = null
			if int(_rotation_active_setup.get(queue_side,-1)) == setup_id:
				# 手动删除不是“战死历史”。直接移除当前名字，避免右键删除后还在上方留灰名。
				var current_label_raw:Variant = _rotation_current_labels.get(queue_side,null)
				if current_label_raw is Label and is_instance_valid(current_label_raw):
					(current_label_raw as Label).queue_free()
				_rotation_current_labels[queue_side] = null
				_rotation_active_setup[queue_side] = -1
				_rotation_active_name[queue_side] = ""
				if _queue_battle_mode_active() and _rotation_started:
					call_deferred("_spawn_next_rotation_character",queue_side)
			if not _rotation_started:
				_clear_rotation_hud_labels()
				for rebuild_side:String in ["left","right"]:
					for record:Dictionary in _rotation_rosters[rebuild_side]:
						_rotation_add_setup_preview_label(
							rebuild_side,
							str(record.get("char","")),
							int(record.get("id",-1))
						)
				call_deferred("_spawn_rotation_preview_character_if_needed",queue_side)
			else:
				_rotation_refresh_future_labels(queue_side)
	for index in range(_battle_setup.size() - 1, -1, -1):
		if int(_battle_setup[index].get("id", -1)) == setup_id:
			_battle_setup.remove_at(index)
			break
	if _development != null:
		_development.on_character_removed(setup_id)

	# 手动删除角色属于重新布阵，不应该被当成“击败最后一个阵营”。
	# 清掉已经武装的胜利状态；如果删除后场上仍然有至少两个阵营，
	# 下一次物理帧会按真实存活阵营重新武装。
	_reset_victory_bell_state()


@rpc("authority")
func rematch_last_battle(exact_replay:bool = true) -> void:
	if is_multiplayer_authority(): random_character_draft.cancel()
	if not is_multiplayer_authority():
		return
	if is_instance_valid(day_night_cycle) and has_rematch_setup(): day_night_cycle.reset_to_noon()
	if is_instance_valid(minecraft_clouds) and has_rematch_setup(): minecraft_clouds.reset_drift()
	if Game.is_rotation_training_mode():
		_sync_rotation_preview_positions()
		var roster_source:Dictionary = _rotation_rosters if not _rotation_rosters["left"].is_empty() else _rotation_saved_rosters
		if not roster_source["left"].is_empty():
			if not exact_replay: _battle_random_seed = 0
			if not _rotation_saved_map.is_empty() and map_group.has(_rotation_saved_map) and _rotation_rosters["left"].is_empty():
				Game.request_map_choice(_rotation_saved_map)
			_restart_rotation_series(roster_source.duplicate(true))
		return

	_reset_victory_bell_state()
	var using_current:bool = not _battle_setup.is_empty()
	var source:Array = _battle_setup.duplicate(true) if using_current else _last_battle_setup.duplicate(true)
	var source_map:String = _battle_setup_map if using_current else _last_battle_setup_map
	var source_seed:int = _battle_random_seed if using_current else _last_battle_random_seed
	if source.is_empty():
		return
	if _development != null:
		_development.cleanup(false)

	# 右键只复用地图/人物/位置：抹掉上一局记录的初始移动方向，并使用全新随机种子。
	if not exact_replay:
		for entry_value:Variant in source:
			if not entry_value is Dictionary:
				continue
			var entry:Dictionary = entry_value as Dictionary
			entry.erase("initial_direction_x")
			entry.erase("initial_direction_y")
			entry.erase("initial_direction_source")

	_last_battle_setup = source.duplicate(true)
	_last_battle_setup_map = source_map
	_last_battle_random_seed = source_seed
	_mc_placement_generation += 1
	_mc_pending_placements.clear()
	_battle_setup.clear()
	_battle_setup_map = ""
	_battle_random_seed = 0
	Game.end_battle_random()
	_training_respawn_pending.clear()
	_reset_special_training_state()

	_clear_battle_transients()
	for b in get_tree().get_nodes_in_group("Ball"):
		Game.free_node(b)
	for b in get_tree().get_nodes_in_group("Shooter"):
		Game.free_node(b)

	reset_toolbar_view()
	Game.mouse_drag = false
	if not source_map.is_empty() and map_group.has(source_map):
		# 通过 Game 的地图入口恢复，联机房主会同步给客户端；离线则直接本地应用。
		Game.request_map_choice(source_map)

	# queue_free 在帧末处理；下一帧按保存的 setup id / team / char / position 重建。
	await get_tree().process_frame
	if _development != null:
		_development.prepare()
	_battle_setup = source.duplicate(true)
	_battle_setup_map = source_map
	_battle_random_seed = source_seed if exact_replay and source_seed > 0 else Game.make_battle_random_seed()
	_battle_random_seed = Game.begin_battle_random(_battle_random_seed)
	_battle_setup_next_id = 1
	for entry_value:Variant in _battle_setup:
		if entry_value is Dictionary:
			_battle_setup_next_id = maxi(_battle_setup_next_id,int((entry_value as Dictionary).get("id",0)) + 1)

	_restoring_battle_setup = true
	for entry_value:Variant in _battle_setup:
		if entry_value is Dictionary:
			_spawn_character_from_setup((entry_value as Dictionary).duplicate(true))
	_restoring_battle_setup = false

	_last_versus_text = ""
	refresh_versus_text()
	refresh_interaction_text()

#地图
#========================================================
# 训练模式地图下方统计 / 积分 HUD
#========================================================
func setup_manual_training_controller() -> void:
	# SpeedsterRLWorld 已经在继承场景里显式放了一个控制器；普通 world.tscn 没有。
	# 这里统一兜底创建，使“手动训练”成为所有 World 场景都可用的工具。
	var existing:Node = get_node_or_null("ManualTrainingController")
	if existing is Node2D:
		manual_training_controller = existing as Node2D
		return

	manual_training_controller = MANUAL_TRAINING_CONTROLLER_SCRIPT.new() as Node2D
	if manual_training_controller == null:
		push_warning("ManualTrainingController: 无法创建手动训练控制器")
		return
	manual_training_controller.name = "ManualTrainingController"
	manual_training_controller.process_priority = -15
	add_child(manual_training_controller)


func setup_combat_threat_analyzer() -> void:
	# 威胁调试不应只存在于 SpeedsterRLWorld。普通 World 也统一兜底创建；
	# 训练场继承场景若已经显式放置则直接复用，避免重复扫描/重复绘制。
	var existing:Node = get_node_or_null("CombatThreatAnalyzer")
	if existing is Node2D:
		return
	var analyzer:Node2D = COMBAT_THREAT_ANALYZER_SCRIPT.new() as Node2D
	if analyzer == null:
		push_warning("CombatThreatAnalyzer: 无法创建威胁调试分析器")
		return
	analyzer.name = "CombatThreatAnalyzer"
	analyzer.process_priority = -18
	add_child(analyzer)


func setup_training_stats_hud() -> void:
	if training_stats_hud != null and is_instance_valid(training_stats_hud):
		return
	training_stats_hud = TRAINING_STATS_HUD_SCRIPT.new() as Control
	if training_stats_hud == null:
		push_warning("TrainingStatsHUD: 无法创建训练统计 HUD")
		return
	add_child(training_stats_hud)
	training_stats_hud.call("setup",self)


#========================================================
# 地图显示初始化
#========================================================
var map_background_tiles:Node2D
var map_background_shadow:Node2D
var map_inside_shadow:Node2D
var map_wall_volume:Node2D
@export_category("地图立体墙")
# 指向右上角的光源，影子朝其反方向投在地面；纯视觉配置，不触碰安全墙。
@export var map_wall_light_direction:Vector2 = Vector2(1.0,-1.0)
var map_wall_height_cells:float = 0.4 # 低矮连续墙；渲染端同步固定为 0.4 格，物理碰撞不变。
func map_background_style() -> String:
	return MAP_BACKGROUND_THEMES.normalize(str(Game.Game_Settings.get("Map_Background","blue")))
func _is_grass_map_background() -> bool:
	# 保持旧调用方名称；沙/石/下界/末地也复用草地的一格外墙与几何逻辑。
	return MAP_BACKGROUND_THEMES.tiled(map_background_style())
func map_visual_cell_size(map_node:Node) -> Vector2:
	var layer:TileMapLayer = map_node as TileMapLayer if map_node is TileMapLayer else ((map_node as PortalMap).primary_island() if map_node is PortalMap else null)
	if not is_instance_valid(layer) or layer.tile_set == null: return Vector2(16,16)
	var tile:Vector2 = Vector2(layer.tile_set.tile_size)
	return Vector2(maxf(layer.global_transform.x.length()*tile.x,0.01),maxf(layer.global_transform.y.length()*tile.y,0.01))
func return_map_visual_rect(layer:Node) -> Rect2:
	var rect:Rect2 = return_map_world_rect(layer)
	if not _is_grass_map_background(): return rect
	var cell:Vector2 = map_visual_cell_size(layer)
	return Rect2(rect.position-cell,rect.size+cell*2.0)
# 草方块地图的边墙分段：把传送门缺口从每边的墙里减掉，墙就真的断开。
func _island_wall_spans(physical_rect:Rect2,island_name:String,portal:PortalMap,cell:Vector2) -> Array:
	if portal == null or physical_rect.size.x <= 0.0 or physical_rect.size.y <= 0.0:
		return []
	var visual_rect:Rect2 = _island_visual_rect(physical_rect,cell)
	var spans:Array = []
	for side:int in range(4):
		var axis_min:float = physical_rect.position.y if side < 2 else visual_rect.position.x
		var axis_max:float = physical_rect.end.y if side < 2 else visual_rect.end.x
		var gaps:Array[Vector2] = portal.gap_intervals(island_name,side,axis_min,axis_max)
		spans.append(_subtract_axis_intervals(axis_min,axis_max,gaps))
	return spans


func _island_shadow_cutouts(rect:Rect2,island_name:String,portal:PortalMap,cell:Vector2) -> Array[Rect2]:
	var cuts:Array[Rect2] = []
	if portal == null or not _is_grass_map_background(): return cuts
	var reach:Vector2 = cell*4.0
	for side:int in range(4):
		var low:float = rect.position.y if side < 2 else rect.position.x
		var high:float = rect.end.y if side < 2 else rect.end.x
		for gap:Vector2 in portal.gap_intervals(island_name,side,low,high):
			match side:
				0: cuts.append(Rect2(rect.position.x-reach.x,gap.x,reach.x,gap.y-gap.x))
				1: cuts.append(Rect2(rect.end.x,gap.x,reach.x,gap.y-gap.x))
				2: cuts.append(Rect2(gap.x,rect.position.y-reach.y,gap.y-gap.x,reach.y))
				3: cuts.append(Rect2(gap.x,rect.end.y,gap.y-gap.x,reach.y))
	return cuts


func _map_shape_walls(map_node:Node) -> Array[Rect2]:
	var walls:Array[Rect2] = []
	if not _is_grass_map_background(): return walls
	for island:Dictionary in map_islands(map_node): walls.append_array(island.walls)
	walls = TileGeometry.subtract(walls,map_island_rects(map_node))
	var portal:PortalMap = current_portal_map()
	if portal != null: walls = TileGeometry.subtract(walls,portal.void_rects())
	if _development != null and _development.is_prebattle() and _development.phase != _development.MERGING:
		for raw_clone:Variant in _development.portal_clones.values():
			if is_instance_valid(raw_clone): walls = TileGeometry.subtract(walls,(raw_clone as PortalMap).void_rects())
	if not _waiter_doors.is_empty():
		var cell:Vector2 = map_visual_cell_size(map_node)
		var door_cuts:Array[Rect2] = []
		for island:Dictionary in map_islands(map_node):
			var rect:Rect2 = island.rect
			for side:int in range(4):
				var low:float = rect.position.y if side<2 else rect.position.x
				var high:float = rect.end.y if side<2 else rect.end.x
				for gap:Vector2 in _waiter_door_gap_intervals_for_island(side,low,high,0.0,rect):
					match side:
						0: door_cuts.append(Rect2(rect.position.x-cell.x,gap.x,cell.x,gap.y-gap.x))
						1: door_cuts.append(Rect2(rect.end.x,gap.x,cell.x,gap.y-gap.x))
						2: door_cuts.append(Rect2(gap.x,rect.position.y-cell.y,gap.y-gap.x,cell.y))
						3: door_cuts.append(Rect2(gap.x,rect.end.y,gap.y-gap.x,cell.y))
		walls = TileGeometry.subtract(walls,door_cuts)
	return walls

func _map_shape_visual(map_node:Node) -> Array[Rect2]:
	var regions:Array[Rect2] = map_island_rects(map_node)
	regions.append_array(_map_shape_walls(map_node))
	return regions

func _shape_edge_gaps(edge:Dictionary,island:Dictionary,portal:PortalMap,include_portals:bool = true) -> Array[Vector2]:
	if _development != null and _development.is_prebattle() and _development.phase != _development.MERGING and island.has("development_lane_key"):
		portal = _development.portal_for_lane(str(island["development_lane_key"]))
	var rect:Rect2 = island.rect
	var side:int = edge.side
	var outer:float = [rect.position.x,rect.end.x,rect.position.y,rect.end.y][side]
	var gaps:Array[Vector2] = []
	if absf(outer-float(edge.line)) < 0.01:
		gaps = _waiter_door_gap_intervals_for_island(side,edge.a,edge.b,0.0,rect if portal != null else Rect2())
	if portal != null and include_portals: gaps.append_array(portal.gap_intervals(str(island.name),side,edge.a,edge.b,edge.line))
	return PortalMap.merge_intervals(gaps)

func _refresh_map_background_tiles(layer:Node) -> void:
	if not is_instance_valid(map_background_tiles):
		map_background_tiles = load("res://scripts/effects/我的世界/地图草方块背景.gd").new()
		map_background_tiles.name = "MapBackgroundTiles"
		# 与石砖场一样在血液(-4)之下、原背景之后；之后生成的石砖仍可覆盖草地。
		map_background_tiles.z_as_relative = false
		map_background_tiles.z_index = -5
		add_child(map_background_tiles)
	if not is_instance_valid(map_background_shadow):
		map_background_shadow = load("res://scripts/effects/我的世界/地图外沿阴影.gd").new()
		map_background_shadow.name = "MapOutsideShadow"
		add_child(map_background_shadow)
	# Summit's compatibility tiles must stay below the true 3D floor (-6).
	# Keep other themes at their existing depth and restore it on every switch.
	map_background_tiles.z_index = -7 if map_background_style()=="summit" else -5
	var cell:Vector2 = map_visual_cell_size(layer)
	var ground:Array[Rect2] = map_island_rects(layer)
	var portal:PortalMap = current_portal_map()
	if portal != null:
		portal.set_wall_carving(_is_grass_map_background())
		portal.refresh_visuals(map_border_width,-maxf(map_border_width,0.0)*0.5-cell.x if _is_grass_map_background() else 1.0,not _is_grass_map_background())
	elif _development != null and _development.is_prebattle() and _development.phase != _development.MERGING:
		_development.refresh_portal_visuals(map_border_width,-maxf(map_border_width,0.0)*0.5-cell.x if _is_grass_map_background() else 1.0,not _is_grass_map_background())
	map_background_tiles.configure_regions(ground,_map_shape_walls(layer),cell,_is_grass_map_background(),map_background_style())
	map_background_shadow.configure_union(_map_shape_visual(layer),cell,[])
	for extra:Node2D in _island_extra_background_tiles: extra.visible = false
	for extra:Node2D in _island_extra_background_shadows: extra.visible = false

func return_map_display_rect(layer:Node) -> Rect2:
	var outward:float = maxf(map_border_width,0.0) if _is_grass_map_background() else maxf(map_border_width*0.5-1.0,0.0)
	return return_map_visual_rect(layer).grow(outward)
func return_map_shadow_rect(layer:Node) -> Rect2:
	var rect:Rect2 = return_map_display_rect(layer)
	var cell:Vector2 = map_visual_cell_size(layer)
	return Rect2(rect.position-cell,rect.size+cell*2.0)

func setup_map_presentation() -> void:
	# World 本身允许普通世界(bit 1)和顶部战斗文字(bit 2)。
	visibility_layer = visibility_layer | COMBAT_TEXT_VISIBILITY_LAYER

	# 黑色地图边框
	map_border_line = Line2D.new()
	map_border_line.name = "MapBorderLine"
	map_border_line.default_color = Color.BLACK
	map_border_line.width = map_border_width
	map_border_line.closed = true
	map_border_line.antialiased = true
	map_border_line.z_index = 100
	add_child(map_border_line)
	# 门需要在黑线中真正留出缺口，因此实际边框改为多个 Line2D 线段；
	# 保留原 map_border_line 变量只做兼容占位。
	map_border_line.visible = false
	map_border_segment_root = Node2D.new()
	map_border_segment_root.name = "MapBorderSegments"
	map_border_segment_root.z_index = 100
	add_child(map_border_segment_root)

	# 第一行：不同阵营不同颜色的角色名 VS 角色名。屏幕画布不继承 Camera2D 的分数像素位移。
	versus_screen_layer = CanvasLayer.new()
	versus_screen_layer.name = "VersusScreenLayer"
	versus_screen_layer.layer = 2 # 1 is reserved for motion blur
	add_child(versus_screen_layer)
	versus_label = RichTextLabel.new()
	versus_label.name = "VersusLabel"
	_apply_mojangles_rich_text_fonts(versus_label)
	versus_label.bbcode_enabled = true
	versus_label.fit_content = false
	versus_label.scroll_active = false
	versus_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	versus_label.clip_contents = false
	versus_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	versus_label.add_theme_font_size_override("normal_font_size",versus_font_max_size)
	versus_label.add_theme_font_size_override("bold_font_size",versus_font_max_size)
	versus_label.add_theme_color_override("default_color",Color.WHITE)
	versus_label.add_theme_color_override("font_outline_color",Color.BLACK)
	versus_label.add_theme_constant_override("outline_size",2)
	versus_label.z_index = 101
	versus_label.visibility_layer = COMBAT_TEXT_VISIBILITY_LAYER
	versus_label.install_effect(HEAVY_GIRL_GLYPH_SHAKE_EFFECT.new())
	versus_screen_layer.add_child(versus_label)
	armor_intro_label = versus_label.duplicate(0) as RichTextLabel
	armor_intro_label.name = "ArmorStandIntroduction"
	armor_intro_label.add_theme_constant_override("outline_size",4)
	armor_intro_label.add_theme_constant_override("line_separation",6)
	armor_intro_label.visible = false
	versus_screen_layer.add_child(armor_intro_label)
	# 顶部 VS 用我的世界 3D 立体字显示；标签本身仍负责文字、布局与可见性（盔甲架介绍复制后再挂）。
	VERSUS_TITLE_3D_SCRIPT.attach(versus_label).top_limit_provider = _versus_title_top_limit
	# 1v1 顶部对战 HUD：仅在恰好两名主角色分属两方时自行显示；原文字 VS 保留。
	duel_top_hud = DUEL_TOP_HUD_SCRIPT.new()
	duel_top_hud.world = self
	duel_top_hud.visibility_bit = COMBAT_TEXT_VISIBILITY_LAYER
	versus_screen_layer.add_child(duel_top_hud)

	# 第二行：固定互动文字。RichText 效果在启动时随机一次。
	interaction_label = RichTextLabel.new()
	interaction_label.name = "InteractionLabel"
	_apply_mojangles_rich_text_fonts(interaction_label)
	interaction_label.bbcode_enabled = true
	interaction_label.fit_content = false
	interaction_label.scroll_active = false
	interaction_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Wave / Shake / Tornado 可能超出文字原始边界，因此不裁剪。
	interaction_label.clip_contents = false
	interaction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	interaction_label.add_theme_font_size_override("normal_font_size",interaction_font_max_size)
	interaction_label.add_theme_font_size_override("bold_font_size",interaction_font_max_size)
	interaction_label.add_theme_color_override("default_color",Color.WHITE)
	interaction_label.add_theme_color_override("font_outline_color",Color.BLACK)
	interaction_label.add_theme_constant_override("outline_size",1)
	interaction_label.z_index = 101
	interaction_label.visibility_layer = COMBAT_TEXT_VISIBILITY_LAYER
	add_child(interaction_label)

	_setup_map_outside_grid()
	_setup_map_outside_mask()

	_build_rotation_versus_hud()
	_build_timed_training_hud()
	_build_character_dialogue_hud()

	# 所有 TileMapLayer 运行时都隐藏，只保留当前地图的碰撞/导航数据。
	_sync_selected_map_visibility()

#========================================================
# 地图可见性 / 地图外视觉裁剪
#========================================================
func _sync_selected_map_visibility() -> void:
	for map_name:Variant in map_group.keys():
		var node:Variant = map_group[map_name]
		var selected:bool = str(map_name) == now_choose_map
		if node is PortalMap:
			var portal:PortalMap = node as PortalMap
			if _development != null and _development.is_prebattle() and selected:
				selected = false
			if portal.is_active() != selected:
				portal.set_active(selected)
			continue
		if node is TileMapLayer:
			var layer:TileMapLayer = node as TileMapLayer
			# TileMap 只用来规划地图范围、墙体和导航，不作为运行时背景。
			# 所有地图层始终隐藏；黑色 MapBorderLine 才是玩家实际看到的地图边界。
			layer.visible = false
			# 只有当前地图保留碰撞/导航，避免隐藏的其他地图继续产生墙体。
			layer.collision_enabled = false # painted tiles are ground; exposed edges provide collision
			layer.navigation_enabled = selected


func _setup_map_outside_grid() -> void:
	if map_outside_grid_root != null and is_instance_valid(map_outside_grid_root):
		return

	map_outside_grid_root = Node2D.new()
	map_outside_grid_root.name = "MapOutsideParallaxGrid"
	# Background 是 -3，BackBufferCopy 是 -1；网格夹在两者之间，
	# 因而地图外裁剪遮罩也会复制到同一份棋盘背景。
	# 明确置于阴影(-4)下面；不能与阴影同层后绘制而覆盖门洞侧边阴影。
	map_outside_grid_root.z_as_relative = false
	map_outside_grid_root.z_index = -5
	add_child(map_outside_grid_root)

	map_outside_grid_material = ShaderMaterial.new()
	map_outside_grid_material.shader = WORLD_OUTSIDE_GRID_SHADER

	map_outside_grid_parts.clear()
	for i:int in range(4):
		var poly := Polygon2D.new()
		poly.name = "OutsideGrid_%d" % i
		poly.color = Color.WHITE
		poly.material = map_outside_grid_material
		map_outside_grid_root.add_child(poly)
		map_outside_grid_parts.append(poly)

	_update_map_outside_grid_parallax()


func _refresh_map_outside_grid(map_rect:Rect2) -> void:
	# The scene's original blue Sprite must remain below the summit scenery (-8).
	# Preserve its original depth exactly when returning to a non-summit theme.
	var base:CanvasItem = get_node_or_null("Background") as CanvasItem
	if is_instance_valid(base):
		if not base.has_meta("summit_original_depth"):
			base.set_meta("summit_original_depth",Vector2i(base.z_index,int(base.z_as_relative)))
		var original:Vector2i = base.get_meta("summit_original_depth")
		base.z_as_relative = false if map_background_style()=="summit" else bool(original.y)
		base.z_index = -10 if map_background_style()=="summit" else original.x
	if is_instance_valid(minecraft_clouds): minecraft_clouds.refresh()
	_setup_map_outside_grid()
	if map_outside_grid_root == null or not is_instance_valid(map_outside_grid_root):
		return
	map_outside_grid_root.visible = map_outside_grid_enabled
	if not map_outside_grid_enabled:
		return

	# 网格只存在于地图矩形外侧。这里沿用地图外裁剪遮罩的四块几何，
	# 因此地图内部仍完整显示原来的蓝色 Background。
	# 传送门地图：岛与岛之间的空隙同样属于地图外，用同一网格材质补齐。
	var rects:Array[Rect2] = _map_outside_rects(_current_visual_island_rects(map_rect))
	# 墙上的门洞也属于地图外：使用同一视差材质，不能留下纯蓝底。
	var portal:PortalMap = current_portal_map()
	if portal != null and _is_grass_map_background():
		portal.set_wall_carving(true)
		var cell:Vector2 = map_visual_cell_size(portal)
		portal.refresh_visuals(map_border_width,-maxf(map_border_width,0.0)*0.5-cell.x,false)
		rects.append_array(portal.void_rects())
	elif _development != null and _development.is_prebattle() and _development.phase != _development.MERGING and _is_grass_map_background():
		for raw_clone:Variant in _development.portal_clones.values():
			if is_instance_valid(raw_clone): rects.append_array((raw_clone as PortalMap).void_rects())
	while map_outside_grid_parts.size() < rects.size():
		var extra_poly := Polygon2D.new()
		extra_poly.name = "OutsideGrid_%d" % map_outside_grid_parts.size()
		extra_poly.color = Color.WHITE
		extra_poly.material = map_outside_grid_material
		map_outside_grid_root.add_child(extra_poly)
		map_outside_grid_parts.append(extra_poly)
	for i:int in range(map_outside_grid_parts.size()):
		var poly:Polygon2D = map_outside_grid_parts[i]
		poly.visible = i < rects.size()
		if i < rects.size():
			poly.polygon = _rect_polygon(rects[i])
	_update_map_outside_grid_parallax()


# 当前地图各岛的“视觉矩形”（草地背景时向外扩一格）。fallback_rect 用于没有地图节点的情况。
func _current_visual_island_rects(fallback_rect:Rect2) -> Array[Rect2]:
	var node:Node = _current_map_node()
	return [fallback_rect] if node == null else _map_shape_visual(node)

func _current_physical_island_rects(fallback_rect:Rect2) -> Array[Rect2]:
	var node:Node = _current_map_node()
	return [fallback_rect] if node == null else map_island_rects(node)

func _update_map_outside_grid_parallax() -> void:
	if not map_outside_grid_enabled:
		if map_outside_grid_root != null and is_instance_valid(map_outside_grid_root):
			map_outside_grid_root.visible = false
		return
	if map_outside_grid_material == null or not is_instance_valid(map_outside_grid_material):
		return
	if camera_2d == null or not is_instance_valid(camera_2d):
		return

	if map_outside_grid_root != null and is_instance_valid(map_outside_grid_root):
		map_outside_grid_root.visible = true
		# Keep the fallback grid behind the mountain/cloud/map sandwich.
		map_outside_grid_root.z_index = -9 if map_background_style()=="summit" else -5
	var viewport_size:Vector2 = get_viewport_rect().size
	var zoom:Vector2 = camera_2d.zoom
	var theme:Dictionary = MAP_BACKGROUND_THEMES.theme(map_background_style())
	map_outside_grid_material.set_shader_parameter("normal_color",theme.get("grid_normal",map_outside_grid_normal_color))
	map_outside_grid_material.set_shader_parameter("dark_color",theme.get("grid_dark",map_outside_grid_dark_color))
	map_outside_grid_material.set_shader_parameter("accent_color",theme.get("grid_accent",Color(1,1,1,0.12)))
	map_outside_grid_material.set_shader_parameter("pattern_style",int(theme.get("grid_style",0)))
	map_outside_grid_material.set_shader_parameter("background_texture",theme.get("grid_texture",null))
	map_outside_grid_material.set_shader_parameter("cell_size_px",maxf(float(theme.get("grid_cell",map_outside_grid_cell_size_px)),1.0))
	map_outside_grid_material.set_shader_parameter("parallax_scale",clampf(float(theme.get("grid_parallax",map_outside_grid_parallax_scale)),0.0,1.0))
	map_outside_grid_material.set_shader_parameter("camera_position",camera_2d.global_position)
	map_outside_grid_material.set_shader_parameter("camera_zoom",Vector2(maxf(absf(zoom.x),0.001),maxf(absf(zoom.y),0.001)))
	map_outside_grid_material.set_shader_parameter("viewport_size",Vector2(maxf(viewport_size.x,1.0),maxf(viewport_size.y,1.0)))


func _setup_map_outside_mask() -> void:
	if map_outside_mask_root != null and is_instance_valid(map_outside_mask_root):
		return

	# BackBufferCopy 在真实场景背景之后、普通角色（通常 z=0）之前执行。
	# TileMap 运行时不可见，所以这里不会把用于规划区域的格子背景重新显示出来。
	# 角色状态框是世界画布的绝对 Z=-3；先复制它，再画 Z=-2 的普通战斗对象，
	# 地图外遮罩仍裁掉越界的角色/投射物，但不会擦除延伸到地图外的信息框。
	map_clip_backbuffer = BackBufferCopy.new()
	map_clip_backbuffer.name = "MapClipBackBuffer"
	map_clip_backbuffer.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	map_clip_backbuffer.z_index = 0
	add_child(map_clip_backbuffer)

	var clip_shader := Shader.new()
	clip_shader.code = """
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
void fragment() {
	COLOR = textureLod(screen_texture, SCREEN_UV, 0.0);
}
"""
	map_clip_material = ShaderMaterial.new()
	map_clip_material.shader = clip_shader

	map_outside_mask_root = Node2D.new()
	map_outside_mask_root.name = "MapOutsideVisualMask"
	map_outside_mask_root.z_index = 90
	add_child(map_outside_mask_root)
	map_outside_mask_parts.clear()
	for i:int in range(4):
		var poly := Polygon2D.new()
		poly.name = "OutsideMask_%d" % i
		poly.color = Color.WHITE
		poly.material = map_clip_material
		poly.z_index = 0
		map_outside_mask_root.add_child(poly)
		map_outside_mask_parts.append(poly)


func _refresh_map_outside_mask(map_rect:Rect2) -> void:
	if not map_outside_mask_enabled:
		if map_outside_mask_root != null:
			map_outside_mask_root.visible = false
		return
	_setup_map_outside_mask()
	map_outside_mask_root.visible = true
	# 传送门地图：多岛之间的空隙也要裁掉越界的角色视觉。
	var rects:Array[Rect2] = _map_outside_rects(_current_physical_island_rects(map_rect))
	while map_outside_mask_parts.size() < rects.size():
		var extra_poly := Polygon2D.new()
		extra_poly.name = "OutsideMask_%d" % map_outside_mask_parts.size()
		extra_poly.color = Color.WHITE
		extra_poly.material = map_outside_mask_parts[0].material if not map_outside_mask_parts.is_empty() else map_clip_material
		extra_poly.z_index = 0
		map_outside_mask_root.add_child(extra_poly)
		map_outside_mask_parts.append(extra_poly)
	for i:int in range(map_outside_mask_parts.size()):
		var poly:Polygon2D = map_outside_mask_parts[i]
		poly.visible = i < rects.size()
		if i >= rects.size():
			continue
		var rr:Rect2 = rects[i]
		poly.color = Color.WHITE
		poly.polygon = _rect_polygon(rr)


#========================================================
# 获取地图真实世界矩形
#========================================================
func return_map_world_rect(map_layer:Node) -> Rect2:
	if _development != null and _development.is_prebattle() and map_layer == _current_map_node():
		return _development.world_rect()
	# 传送门地图：所有岛的外接矩形（相机取景、顶部文字、水印用）。
	if map_layer is PortalMap:
		return (map_layer as PortalMap).world_rect()
	if not map_layer is TileMapLayer:
		return Rect2()
	# 临时终幕地图的物理边界会延伸；原地图/10×10参考地图仍返回原始单格范围。
	if is_instance_valid(map_layer) and map_layer.has_meta(&"sans_final_rect"):
		return map_layer.get_meta(&"sans_final_rect") as Rect2
	if map_layer == null or not is_instance_valid(map_layer) or map_layer.tile_set == null:
		return Rect2()
	var rect:Rect2i = map_layer.get_used_rect()
	if rect.size.x <= 0 or rect.size.y <= 0:
		return Rect2(map_layer.global_position,Vector2.ZERO)

	# get_used_rect() 返回地图单元格范围。先在 TileMapLayer 的局部坐标
	# 得到网格外沿，再用 to_global() 转换，避免只加 position 导致
	# 地图存在缩放/父节点变换时相机、墙和遮罩范围全部算错。
	var tile_size:Vector2 = Vector2(map_layer.tile_set.tile_size)
	var local_min:Vector2 = Vector2(rect.position) * tile_size
	var local_max:Vector2 = Vector2(rect.end) * tile_size
	var corners:PackedVector2Array = PackedVector2Array([
		map_layer.to_global(local_min),
		map_layer.to_global(Vector2(local_max.x,local_min.y)),
		map_layer.to_global(local_max),
		map_layer.to_global(Vector2(local_min.x,local_max.y)),
	])
	var min_p:Vector2 = corners[0]
	var max_p:Vector2 = corners[0]
	for p:Vector2 in corners:
		min_p.x = minf(min_p.x,p.x)
		min_p.y = minf(min_p.y,p.y)
		max_p.x = maxf(max_p.x,p.x)
		max_p.y = maxf(max_p.y,p.y)
	return Rect2(min_p,max_p - min_p)

#========================================================
# 根据文字宽度自动选择合适字号，并返回需要的实际高度。
#
# 规则：
# 1. 从最大字号开始；
# 2. 一行放不下就逐级缩小；
# 3. 缩到最小仍过长时允许自动换行；
# 4. 高度按实际内容计算，不再用固定高度裁掉文字。
#========================================================
func fit_rich_text_label(
	label:RichTextLabel,
	min_font_size:int,
	max_font_size:int,
	available_width:float,
	effect_margin:float
) -> float:
	if label == null:
		return 0.0

	var plain_text:String = label.get_parsed_text()
	if plain_text.is_empty():
		return 0.0

	var usable_width:float = maxf(
		available_width - top_text_horizontal_padding * 2.0,
		1.0
	)

	# 这些文字都使用了 [b]，因此按 bold_font 测量更接近最终显示结果。
	var measure_font:Font = label.get_theme_font("bold_font")
	var chosen_size:int = maxi(max_font_size,min_font_size)
	var safe_min_size:int = mini(min_font_size,chosen_size)

	while chosen_size > safe_min_size:
		var one_line_size:Vector2 = measure_font.get_string_size(
			plain_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			chosen_size
		)

		# 留一点余量，避免粗体、描边或动画偏移让最末字符刚好被切掉。
		if one_line_size.x <= usable_width * 0.94:
			break

		chosen_size -= 1

	label.add_theme_font_size_override("normal_font_size",chosen_size)
	label.add_theme_font_size_override("bold_font_size",chosen_size)

	# 如果最小字号依然过长，就按照当前可用宽度计算多行高度。
	var measured_size:Vector2 = measure_font.get_multiline_string_size(
		plain_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		usable_width,
		chosen_size
	)

	return maxf(
		measured_size.y + effect_margin * 2.0,
		float(chosen_size) + effect_margin * 2.0
	)


# Match the reference map's apparent title size at the map-fit camera zoom.
# Comparing the two fits in the same viewport also works after window resizing
# and for portal maps; manual/animated camera zoom does not change UI layout.
func get_map_versus_scale(map_node:Node) -> float:
	if map_node == null or not map_group.has(map_reference_name):
		return 1.0
	var reference_map:Node = map_group[map_reference_name]
	if map_node == reference_map:
		return 1.0
	var reference_fit:float = _fit_zoom_for_map(reference_map)
	var current_fit:float = _fit_zoom_for_map(map_node)
	if reference_fit <= 0.0 or current_fit <= 0.0:
		return 1.0
	return clampf(reference_fit / current_fit,0.5,8.0)


func _update_map_versus_font(map_node:Node) -> void:
	if _versus_base_max_size < 0:
		_versus_base_max_size = versus_font_max_size
		_versus_base_min_size = versus_font_min_size
		_versus_base_effect_margin = versus_effect_margin
	var map_scale:float = get_map_versus_scale(map_node)
	# Publish the effective bounds through the existing properties: the bilingual
	# recording mirror uses them to independently fit longer translated names.
	versus_font_max_size = maxi(4,roundi(float(_versus_base_max_size) * map_scale))
	versus_font_min_size = mini(versus_font_max_size,maxi(4,roundi(float(_versus_base_min_size) * map_scale)))
	versus_effect_margin = _versus_base_effect_margin * maxf(map_scale,1.0)
	# 标题描边随地图字号等比放大；基准地图由 1 加粗为 2。
	var outline:int = maxi(2,roundi(map_scale * 2.0))
	if versus_label.get_theme_constant("outline_size") != outline:
		versus_label.add_theme_constant_override("outline_size",outline)


#========================================================
# 重新排版顶部战斗文字。
#
# 不固定字号、不固定高度：
# - 短文字会自动变大；
# - 长文字会自动缩小；
# - 实在太长则换行；
# - VS 锁定视口上沿；互动文字保持原来的地图上方位置。
#========================================================
func refresh_top_text_layout() -> void:
	if versus_label == null or interaction_label == null:
		return
	if not map_group.has(now_choose_map):
		return

	var map_node:Node = map_group[now_choose_map]
	_update_map_versus_font(map_node)
	var map_rect:Rect2 = return_map_visual_rect(map_node)
	var available_width:float = map_rect.size.x
	# VS 独立于世界画布；仍用地图基准 zoom 换算控件宽度与地图适配字号。
	# 镜头跟随、Alt+滚轮与临时镜头缩放不影响标题的屏幕宽度或字号。
	var base_zoom:float = maxf(_base_camera_zoom_value(),0.001)
	_versus_layout_base_zoom = base_zoom
	var viewport_width:float = get_viewport_rect().size.x
	var versus_width:float = maxf(viewport_width - versus_screen_side_padding_px * 2.0,40.0) / base_zoom

	var interaction_real_height:float = 0.0
	if interaction_label.visible:
		interaction_real_height = fit_rich_text_label(
			interaction_label,
			interaction_font_min_size,
			interaction_font_max_size,
			available_width,
			interaction_effect_margin
		)

	var versus_real_height:float = 0.0
	if versus_label.visible:
		versus_real_height = fit_rich_text_label(
			versus_label,
			versus_font_min_size,
			versus_font_max_size,
			versus_width,
			versus_effect_margin
		)

	var current_y:float = map_rect.position.y - interaction_map_gap

	# 第二行互动文字最靠近地图。
	if interaction_label.visible:
		current_y -= interaction_real_height
		interaction_label.position = Vector2(map_rect.position.x,current_y)
		interaction_label.size = Vector2(available_width,interaction_real_height)
	else:
		interaction_label.size = Vector2(available_width,0.0)

	# VS 单独靠视口上边缘，不再被地图/互动文字/镜头带走。
	if versus_label.visible:
		versus_label.size = Vector2(versus_width,versus_real_height)
	else:
		versus_label.size = Vector2(versus_width,0.0)
	_anchor_versus_to_screen()

	_layout_rotation_versus_hud()
	_layout_timed_training_hud()
	_layout_character_dialogue_hud()

## VS 立体字标题带的最高位置（屏幕 y，0 = 不限制）：在顶部时间/VS 面板（工具栏打开时会缩小下移）
## 下方，也不被顶部工具栏盖住。
func _versus_title_top_limit() -> float:
	var limit:float = 0.0
	if is_instance_valid(duel_top_hud):
		var hud_bottom:float = (duel_top_hud.get_global_transform_with_canvas() * Vector2(0.0,DUEL_TOP_HUD_SCRIPT.TOP + DUEL_TOP_HUD_SCRIPT.PANEL_HEIGHT)).y
		limit = hud_bottom + 8.0
	if not is_instance_valid(control): return limit
	var bar:Control = control.get_node_or_null("Settings") as Control
	if bar == null or not bar.is_visible_in_tree(): return limit
	var bar_layer:CanvasLayer = bar.get_canvas_layer_node()
	if bar_layer != null and not bar_layer.visible: return limit
	var bar_canvas:Transform2D = bar.get_global_transform_with_canvas()
	var bottom:float = maxf((bar_canvas * Vector2(0.0,bar.size.y)).y,(bar_canvas * bar.size).y)
	return maxf(limit,bottom + 12.0) if bottom > 0.0 else limit

func _anchor_versus_to_screen() -> void:
	if not is_inside_tree() or not is_instance_valid(versus_label):
		return
	versus_label.position = Vector2(versus_screen_side_padding_px,versus_screen_top_padding_px)
	versus_label.scale = Vector2.ONE * _versus_layout_base_zoom
	versus_label.rotation = 0.0
	_layout_armor_intro_to_screen()

func _layout_armor_intro_to_screen() -> void:
	if not is_instance_valid(armor_intro_label) or not armor_intro_label.visible:
		return
	var width:float = maxf(1.0,get_viewport_rect().size.x - 2.0 * versus_screen_side_padding_px)
	armor_intro_label.size.x = width # Shape at the final width before measuring wrapped content.
	var height:float = fit_rich_text_label(armor_intro_label,armor_intro_font_size,armor_intro_font_size,width,2.0)
	height = maxf(height,float(armor_intro_label.get_content_height()) + 4.0)
	armor_intro_label.size = Vector2(width,height)
	armor_intro_label.scale = Vector2.ONE
	var top:float = maxf(24.0,armor_intro_screen_top_padding_px)
	armor_intro_label.position = Vector2(maxf(0.0,versus_screen_side_padding_px),top)


#========================================================
# 更新黑框及战斗文字的位置
#========================================================
func _refresh_map_border_geometry(_map_rect:Rect2) -> void:
	_refresh_map_inside_shadow()
	if map_border_segment_root == null or not is_instance_valid(map_border_segment_root):
		map_border_segment_root = Node2D.new()
		map_border_segment_root.name = "MapBorderSegments"
		map_border_segment_root.z_index = 100
		add_child(map_border_segment_root)

	for child:Node in map_border_segment_root.get_children():
		map_border_segment_root.remove_child(child)
		child.queue_free()

	var portal:PortalMap = current_portal_map()
	var map_node:Node = _current_map_node()
	if _is_grass_map_background():
		for edge:Dictionary in TileGeometry.edges(_map_shape_visual(map_node)):
			var n:Vector2 = PortalMap.SIDE_NORMALS[int(edge.side)]
			var gaps:Array[Vector2] = []
			# 墙顶被门挖走后，露出的物理边也成了视觉边；别再用黑线封死入口。
			if not _waiter_doors.is_empty():
				for island:Dictionary in map_islands(map_node):
					var rect:Rect2 = island.rect
					var outer:float = [rect.position.x,rect.end.x,rect.position.y,rect.end.y][int(edge.side)]
					if absf(float(edge.line)-outer)<0.01:
						gaps.append_array(_waiter_door_gap_intervals_for_island(int(edge.side),edge.a,edge.b,0.0,rect))
			for span:Vector2 in _subtract_axis_intervals(edge.a,edge.b,PortalMap.merge_intervals(gaps)):
				_add_map_border_segment(TileGeometry.point(edge,span.x)+n*map_border_width*0.5,TileGeometry.point(edge,span.y)+n*map_border_width*0.5)
	else:
		for island:Dictionary in map_islands(map_node):
			for edge:Dictionary in TileGeometry.edges(island.regions):
				var n:Vector2 = PortalMap.SIDE_NORMALS[int(edge.side)]
				for span:Vector2 in _subtract_axis_intervals(edge.a,edge.b,_shape_edge_gaps(edge,island,portal)):
					_add_map_border_segment(TileGeometry.point(edge,span.x)-n,TileGeometry.point(edge,span.y)-n)
	if portal != null:
		var cell:Vector2 = map_visual_cell_size(map_node)
		portal.set_wall_carving(_is_grass_map_background())
		portal.refresh_visuals(map_border_width,-maxf(map_border_width,0.0)*0.5-cell.x if _is_grass_map_background() else 1.0,not _is_grass_map_background())

func _refresh_island_border_geometry(map_rect:Rect2,physical_rect:Rect2,island_name:String,portal:PortalMap) -> void:
	# Line2D以中心线向两边扩宽；木圈必须连线宽都完全置于纹理外侧。
	var inset:float = -maxf(map_border_width,0.0)*0.5 if _is_grass_map_background() else 1.0
	var top_left:Vector2 = map_rect.position + Vector2.ONE*inset
	var bottom_right:Vector2 = map_rect.end - Vector2.ONE*inset
	if bottom_right.x <= top_left.x or bottom_right.y <= top_left.y:
		return

	for side:int in range(4):
		var axis_min:float = top_left.y if side < 2 else top_left.x
		var axis_max:float = bottom_right.y if side < 2 else bottom_right.x
		var gaps:Array[Vector2] = _waiter_door_gap_intervals_for_island(side,axis_min,axis_max,0.0,physical_rect if portal != null else Rect2())
		if portal != null:
			gaps.append_array(portal.gap_intervals(island_name,side,axis_min,axis_max))
			gaps = PortalMap.merge_intervals(gaps)
		var segments:Array[Vector2] = _subtract_axis_intervals(axis_min,axis_max,gaps)
		for span:Vector2 in segments:
			if span.y - span.x <= 0.2:
				continue
			var a:Vector2
			var b:Vector2
			if side == 0:
				a = Vector2(top_left.x,span.x)
				b = Vector2(top_left.x,span.y)
			elif side == 1:
				a = Vector2(bottom_right.x,span.x)
				b = Vector2(bottom_right.x,span.y)
			elif side == 2:
				a = Vector2(span.x,top_left.y)
				b = Vector2(span.y,top_left.y)
			else:
				a = Vector2(span.x,bottom_right.y)
				b = Vector2(span.y,bottom_right.y)
			if portal != null and _is_grass_map_background():
				for exposed:PackedVector2Array in portal.exposed_border_segments(island_name,a,b,map_border_width):
					_add_map_border_segment(exposed[0],exposed[1])
			else:
				_add_map_border_segment(a,b)


func _refresh_map_inside_shadow() -> void:
	var map_node:Node = _current_map_node()
	if map_node == null:
		return
	var islands:Array[Dictionary] = map_islands(map_node)
	if islands.is_empty():
		return
	var portal:PortalMap = current_portal_map()
	if not is_instance_valid(map_inside_shadow):
		map_inside_shadow = load("res://scripts/effects/我的世界/地图内沿阴影.gd").new()
		map_inside_shadow.name = "MapInsideShadow"
		add_child(map_inside_shadow)
	var edges:Array[Dictionary] = []
	for island:Dictionary in islands:
		for edge:Dictionary in TileGeometry.edges(island.regions):
			for span:Vector2 in _subtract_axis_intervals(edge.a,edge.b,_shape_edge_gaps(edge,island,portal)):
				var segment:Dictionary = edge.duplicate()
				segment.a = span.x
				segment.b = span.y
				edges.append(segment)
	var cell:Vector2 = map_visual_cell_size(map_node)
	var sun:Vector2 = map_wall_light_direction.normalized() if map_wall_light_direction.length_squared() > 0.0001 else Vector2(1.0,-1.0).normalized()
	# 六主题都只保留贴边的 2D 接触暗边；五种方块主题的斜向地影由
	# DirectionalLight3D 投向真实 3D 接影平面，绝不叠加旧的手绘长影。
	var cast:Vector2 = Vector2.ZERO
	map_inside_shadow.configure_regions(map_island_rects(map_node),cell,edges,cast)
	if _is_grass_map_background():
		if not is_instance_valid(map_wall_volume):
			map_wall_volume = load("res://scripts/effects/我的世界/地图立体墙.gd").new()
			map_wall_volume.name = "MapWallVolume"
			add_child(map_wall_volume)
		map_wall_volume.configure_regions(map_island_rects(map_node),_map_shape_walls(map_node),edges,cell,map_background_style(),sun,map_wall_height_cells)
	elif is_instance_valid(map_wall_volume):
		# 主题切回蓝色时停止 3D Viewport，且绝不在蓝色边框上画凸起。
		var no_ground:Array[Rect2] = []
		var no_walls:Array[Rect2] = []
		map_wall_volume.configure_regions(no_ground,no_walls,edges,cell,"blue",sun,map_wall_height_cells)
	for extra:Node2D in _island_extra_inside_shadows: extra.visible = false
	if is_instance_valid(day_night_cycle): day_night_cycle.apply_lighting()

func _configure_island_inside_shadow(shadow:Node2D,physical_rect:Rect2,island_name:String,portal:PortalMap) -> void:
	var layer:Node = _current_map_node()
	var rect:Rect2 = physical_rect
	# 蓝色墙中心线内缩1，阴影从线条内缘开始；木墙内缘就是草地边缘。
	if not _is_grass_map_background():
		rect = rect.grow(-(1.0+maxf(map_border_width,0.0)*0.5))
	var wall_spans:Array = []
	for side:int in range(4):
		var axis_min:float = rect.position.y if side < 2 else rect.position.x
		var axis_max:float = rect.end.y if side < 2 else rect.end.x
		var gaps:Array[Vector2] = _waiter_door_gap_intervals_for_island(side,axis_min,axis_max,0.0,physical_rect if portal != null else Rect2())
		if portal != null:
			gaps.append_array(portal.gap_intervals(island_name,side,axis_min,axis_max))
			gaps = PortalMap.merge_intervals(gaps)
		wall_spans.append(_subtract_axis_intervals(axis_min,axis_max,gaps))
	shadow.configure(rect,map_visual_cell_size(layer),wall_spans)


func _add_map_border_segment(a:Vector2,b:Vector2) -> void:
	# 蓝色保留原黑框；五种方块主题只画原版材质墙，不叠加外圈黑线。
	if map_border_segment_root == null or _is_grass_map_background():
		return
	var line := Line2D.new()
	line.width = map_border_width
	line.default_color = Color.BLACK
	line.antialiased = true
	line.points = PackedVector2Array([a,b])
	if _is_grass_map_background():
		line.antialiased = false # 防止抗锯齿灰边继续侵入原木像素。
		line.begin_cap_mode = Line2D.LINE_CAP_BOX
		line.end_cap_mode = Line2D.LINE_CAP_BOX
	map_border_segment_root.add_child(line)


func refresh_map_presentation() -> void:
	random_character_draft.on_map_changed()
	if map_border_line == null or versus_label == null or interaction_label == null:
		return
	if not map_group.has(now_choose_map):
		return

	_prune_waiter_doors_for_current_map()
	_sync_selected_map_visibility()
	var now_map:Node = _current_map_node()
	if now_map == null:
		return
	var map_rect:Rect2 = return_map_world_rect(now_map)
	var visual_rect:Rect2 = return_map_visual_rect(now_map)
	_refresh_map_background_tiles(now_map)
	_refresh_map_outside_grid(visual_rect)
	_refresh_map_outside_mask(map_rect)
	_refresh_center_watermark_layout(visual_rect)

	# 地图切换时重建不可见安全墙，防止角色从不同尺寸地图的边角被挤出去。
	_rebuild_map_safety_frame()

	# 黑色地图边框按线段绘制，服务员开门时对应门宽会真实断开。
	_refresh_map_border_geometry(visual_rect)

	# 先给两个 RichTextLabel 当前地图宽度；高度随后由内容自动决定。
	versus_label.size.x = map_rect.size.x
	interaction_label.size.x = map_rect.size.x

	if is_instance_valid(battle_conditions): battle_conditions.refresh_layout()
	_presentation_map_name = now_choose_map
	_last_versus_text = ""
	refresh_versus_text()
	refresh_interaction_text()
	refresh_top_text_layout()
	_layout_character_dialogue_hud()

#========================================================
# 获取角色显示名
#========================================================
func return_ball_display_name(b:Node) -> String:
	# 允许会临时替换场景的角色保持自己的“身份名”。
	# 例如变形者变成牛/小丑时，顶部 VS 仍显示“变形者”。
	if b.has_meta(&"morph_display_name"):
		return str(b.get_meta(&"morph_display_name"))

	# 创建角色后 Node.name 会被随机化，因此使用角色场景文件名。
	if not b.scene_file_path.is_empty():
		return b.scene_file_path.get_file().get_basename()
	return str(b.name)

#========================================================
# 防止角色名/互动文案中的 [ 被 BBCode 当成标签
#========================================================
func escape_bbcode(text:String) -> String:
	return text.replace("[","[lb]")

#========================================================
# 一个角色属于哪一方
#========================================================
func _resolve_ball_presentation_team(b:ball) -> String:
	if b == null or not is_instance_valid(b):
		return ""

	# 召唤物的 Team 在网络生成后的极短窗口里可能还是默认值；顶部 UI 永远优先主人队伍。
	if b.Master != null and is_instance_valid(b.Master):
		return str(b.Master.Team).strip_edges()
	if not b.Master_name.is_empty():
		var resolved = get_node_or_null(NodePath(b.Master_name))
		if resolved is ball:
			return str((resolved as ball).Team).strip_edges()
	return str(b.Team).strip_edges()


func _is_runtime_summon(b:ball) -> bool:
	if b == null:
		return false
	return (b.Master != null and is_instance_valid(b.Master)) or not b.Master_name.is_empty()


func _is_battle_continuation_unit(b:ball) -> bool:
	# 少数召唤物是“原角色仍存活的延续”，而不是普通宠物/投射物。
	# 蠹虫从石砖孵化出的同阵营个体使用这个契约：本体先死时仍应保留该方 VS 与胜负资格。
	if b == null or not is_instance_valid(b):
		return false
	return (
		b.has_meta(&"battle_continuation_victory_side_key")
		and not str(b.get_meta(&"battle_continuation_victory_side_key","")).strip_edges().is_empty()
	)


func _battle_continuation_presentation_side_key(b:ball) -> String:
	if b == null or not is_instance_valid(b):
		return ""
	return str(b.get_meta(&"battle_continuation_presentation_side_key","")).strip_edges()


func _is_battle_death_bridge_unit(b:ball) -> bool:
	# V83：少数角色有明确的死亡演出，并且死亡期间可能生成比赛延续单位。
	# 只要节点尚未真正退场，允许它用冻结的 side key 暂时维持 VS/胜负资格，避免 HP=0 的同帧先响铃。
	if b == null or not is_instance_valid(b):
		return false
	if not bool(b.get_meta(&"battle_death_bridge_active",false)):
		return false
	return not str(b.get_meta(&"battle_death_bridge_victory_side_key","")).strip_edges().is_empty()


func _battle_death_bridge_victory_side_key(b:ball) -> String:
	if b == null or not is_instance_valid(b):
		return ""
	return str(b.get_meta(&"battle_death_bridge_victory_side_key","")).strip_edges()


func _battle_death_bridge_presentation_side_key(b:ball) -> String:
	if b == null or not is_instance_valid(b):
		return ""
	return str(b.get_meta(&"battle_death_bridge_presentation_side_key","")).strip_edges()


func _is_primary_battle_character(b:ball) -> bool:
	if b == null:
		return false
	if b.has_meta("development_reserve"):
		return false
	# V192：寸头猪地图外来客只是一次性攻击演出，不属于比赛阵营，不能进入 VS / 胜利统计。
	if b.has_meta(&"pig_outside_guest_exempt") and bool(b.get_meta(&"pig_outside_guest_exempt")):
		return false
	# V89：苦力怕头这类“二阶段延续单位”虽然为了继承阵营/来源仍保留 Master / Master_name，
	# 但玩法上它就是原角色的下一阶段，不应被当成普通召唤物从主战角色计数中排除。
	# 否则本体爆炸、附近敌人同时死亡后，_count_primary_battle_characters() 可能变成 0，
	# is_combat_runtime_active() 随即关闭；苦力怕头仍处于 _launch_active 时就会停止更新炸飞运动，
	# 并永远到不了“速度降到正常速度 -> 切回普通移动”的结束条件。
	# continuation metadata 已经是 World 现有的二阶段/比赛延续契约，因此这里直接复用它。
	return (
		b.Type == ball.Ball_Type.Ball
		and (not _is_runtime_summon(b) or _is_battle_continuation_unit(b))
	)


func return_ball_side_key(b:ball) -> String:
	var team_name:String = _resolve_ball_presentation_team(b)

	# 没有 Team：每一个角色都是独立阵营。
	if team_name.is_empty():
		return "solo:" + str(b.get_instance_id())

	# 有 Team：相同 Team 的角色属于同一阵营。
	return "team:" + team_name

#========================================================
# 获取所有阵营及成员
#========================================================
func return_battle_sides() -> Dictionary:
	var side_order:Array[String] = []
	var side_members:Dictionary = {}

	for node in _battle_units_cache:
		if not node is ball:
			continue

		var b:ball = node
		if b.is_queued_for_deletion():
			continue
		var is_death_bridge:bool = _is_battle_death_bridge_unit(b)
		if b.health <= 0 and not is_death_bridge:
			continue
		var is_primary:bool = _is_primary_battle_character(b)
		var is_continuation:bool = _is_battle_continuation_unit(b)
		# 普通召唤物仍不进入顶部 VS；只有显式声明“比赛延续”或“死亡演出桥”的单位可代表比赛阵营。
		if not is_primary and not is_continuation and not is_death_bridge:
			continue

		var side_key:String = return_ball_side_key(b)
		if is_continuation:
			var continuation_side:String = _battle_continuation_presentation_side_key(b)
			if not continuation_side.is_empty():
				side_key = continuation_side
		if is_death_bridge:
			var bridge_side:String = _battle_death_bridge_presentation_side_key(b)
			if not bridge_side.is_empty():
				side_key = bridge_side

		if not side_members.has(side_key):
			side_order.append(side_key)
			side_members[side_key] = []

		var display_name:String = return_ball_display_name(b)
		if is_continuation:
			var continuation_name:String = str(b.get_meta(&"battle_continuation_display_name","")).strip_edges()
			if not continuation_name.is_empty():
				display_name = continuation_name
		if is_death_bridge:
			var bridge_name:String = str(b.get_meta(&"battle_death_bridge_display_name","")).strip_edges()
			if not bridge_name.is_empty():
				display_name = bridge_name
		if is_continuation or is_death_bridge:
			# 一窝蠹虫仍代表一个“蠹虫”角色，不在 VS 上重复成 蠹虫 + 蠹虫 + ...
			if (side_members[side_key] as Array).has(display_name):
				continue
		(side_members[side_key] as Array).append(display_name)

	return {
		"order":side_order,
		"members":side_members
	}

func _victory_side_key_for_character(b:ball) -> String:
	if b == null or not is_instance_valid(b):
		return ""

	# 只要主人还在，就实时把附属的阵营缓存成“根主人”的阵营。
	# 主人之后即使先死亡/释放，附属仍沿用缓存，不会被误算成新的独立阵营。
	var root:ball = b
	var safety:int = 0
	while root.Master != null and is_instance_valid(root.Master) and safety < 12:
		root = root.Master
		safety += 1

	var team_name:String = str(root.Team).strip_edges()
	var key:String = ""
	if not team_name.is_empty():
		key = "team:" + team_name
	elif root.has_meta("battle_setup_id"):
		key = "solo_setup:" + str(int(root.get_meta("battle_setup_id")))
	else:
		key = "solo_instance:" + str(root.get_instance_id())

	b.set_meta(&"victory_side_key",key)
	return key


func _victory_root_primary_character(b:ball) -> ball:
	if b == null or not is_instance_valid(b):
		return null
	var root:ball = b
	var safety:int = 0
	while root.Master != null and is_instance_valid(root.Master) and safety < 12:
		root = root.Master
		safety += 1
	return root if _is_primary_battle_character(root) else null


# A roster slot is a family, never a particular body or a Team alone.
# Ownership is captured at registration, BEFORE the first victory poll or death.
# See docs/BATTLE_LIFECYCLE.md; use tickets for spawns that outlive their source.
const BATTLE_LIFECYCLE_META:StringName = &"battle_lifecycle_identity"
const BATTLE_LIFECYCLE_CLASSIFICATION = preload("res://classes/combat_classification.gd")
var _battle_lifecycle_generation:int = 0
var _battle_lifecycle_round:int = 0
var _battle_spawn_ticket_serial:int = 0
var _battle_spawn_tickets:Dictionary = {}

func bind_battle_lifecycle(unit:ball,source:ball = null,force:bool = false,depth:int = 0) -> Dictionary:
	if not is_instance_valid(unit) or depth > 12: return {}
	if unit.has_meta("development_reserve") or bool(unit.get_meta("pig_outside_guest_exempt",false)): return {}
	var old:Dictionary = unit.get_meta(BATTLE_LIFECYCLE_META,{})
	if not force and not old.is_empty() and (int(old.get("generation",-1)) != _battle_lifecycle_generation or int(old.get("round",-1)) != _battle_lifecycle_round): return {}
	if not is_instance_valid(source):
		if is_instance_valid(unit.Master): source = unit.Master
		elif not unit.Master_name.is_empty(): source = get_node_or_null(NodePath(unit.Master_name)) as ball
	var identity:Dictionary = {}
	if is_instance_valid(source) and source != unit:
		identity = bind_battle_lifecycle(source,null,false,depth+1)
		if identity.is_empty(): return {}
	elif not force and not old.is_empty() and int(old.get("root",0)) != unit.get_instance_id():
		# Orphans keep their original family even after Master is freed/cleared.
		identity = old
	elif _is_primary_battle_character(unit):
		var setup_id:int = int(unit.get_meta("battle_setup_id",unit.get_meta("battle_continuation_setup_id",-1)))
		identity = {"generation":_battle_lifecycle_generation,"round":_battle_lifecycle_round,
			"root":unit.get_instance_id(),"setup":setup_id,
			"victory":str(unit.get_meta("battle_continuation_victory_side_key",_victory_side_key_for_character(unit)))}
	elif not old.is_empty(): identity = old
	if identity.is_empty(): return {}
	if int(identity.get("generation",-1)) != _battle_lifecycle_generation or int(identity.get("round",-1)) != _battle_lifecycle_round:
		return {}
	unit.set_meta(BATTLE_LIFECYCLE_META,identity.duplicate())
	unit.set_meta("victory_side_key",str(identity.get("victory","")))
	return identity

func _battle_unit_keeps_family_alive(unit:ball) -> bool:
	if not is_instance_valid(unit) or unit.is_queued_for_deletion() or not unit.is_inside_tree(): return false
	if unit.has_meta("development_reserve") or bool(unit.get_meta("pig_outside_guest_exempt",false)) or bool(unit.get_meta("battle_lifecycle_exiting",false)): return false
	# Shared identity/phase classification excludes projectiles, detached weapons,
	# terrain, hazards and decorations even if their old Type says Ball/Creature.
	var kind:String = str(BATTLE_LIFECYCLE_CLASSIFICATION.profile_of(unit).get("entity_kind",""))
	if kind not in ["character","subentity"]: return false
	if bind_battle_lifecycle(unit).is_empty(): return false
	if unit.health > 0 or _is_battle_death_bridge_unit(unit): return true
	# Give the real death/revival state machine its turn, not an arbitrary delay.
	# Dead animations without a continuation bridge do NOT keep a side alive.
	return unit.Type == ball.Ball_Type.Ball and (unit._zero_health_resolution_pending or (unit.state_machine != null and unit.state_machine.current_state != ball.State.Die))

func begin_battle_spawn(source:ball,custodian:Node) -> int:
	if not is_multiplayer_authority() or not is_instance_valid(custodian): return 0
	if _timed_finished and _timed_defeated_setups.has(_resolve_timed_source_setup_id(source)): return 0
	var identity:Dictionary = bind_battle_lifecycle(source)
	if identity.is_empty(): return 0
	_battle_spawn_ticket_serial += 1
	_battle_spawn_tickets[_battle_spawn_ticket_serial] = {"identity":identity.duplicate(),"custodian":weakref(custodian)}
	return _battle_spawn_ticket_serial

func _prune_battle_spawn_tickets() -> void:
	for ticket:Variant in _battle_spawn_tickets.keys():
		var row:Dictionary = _battle_spawn_tickets[ticket]
		var keeper:Node = (row.custodian as WeakRef).get_ref() as Node
		var identity:Dictionary = row.identity
		if not is_instance_valid(keeper) or keeper.is_queued_for_deletion() or not keeper.is_inside_tree() or int(identity.generation) != _battle_lifecycle_generation or int(identity.round) != _battle_lifecycle_round:
			_battle_spawn_tickets.erase(ticket)

func apply_battle_spawn_identity(unit:ball,ticket:int) -> bool:
	_prune_battle_spawn_tickets()
	if not is_instance_valid(unit) or not _battle_spawn_tickets.has(ticket): return false
	unit.set_meta(BATTLE_LIFECYCLE_META,(_battle_spawn_tickets[ticket].identity as Dictionary).duplicate())
	return true

func finish_battle_spawn(ticket:int) -> void:
	_battle_spawn_tickets.erase(ticket)
	call_deferred("_scan_rotation_family_extinctions")

func _battle_family_alive(setup_id:int) -> bool:
	if setup_id < 0: return false
	for raw:Variant in _battle_units_cache:
		if not raw is ball or not _battle_unit_keeps_family_alive(raw): continue
		var identity:Dictionary = raw.get_meta(BATTLE_LIFECYCLE_META,{})
		if int(identity.get("setup",-1)) == setup_id: return true
	_prune_battle_spawn_tickets()
	for row:Dictionary in _battle_spawn_tickets.values():
		if int(row.identity.get("setup",-1)) == setup_id: return true
	return false

func _scan_rotation_family_extinctions() -> void:
	if not is_multiplayer_authority() or not _queue_battle_mode_active() or not _rotation_started or _rotation_clearing_round or _rotation_finished: return
	for side:String in ["left","right"]:
		var setup_id:int=int(_rotation_active_setup.get(side,-1))
		if setup_id<0: continue
		if _rotation_side_alive(side):
			_rotation_pending_dead_sides.erase(side)
		elif not _rotation_pending_dead_sides.has(side):
			# Only a candidate. Do not erase the slot, cross the portrait or end a totem save yet.
			_rotation_pending_dead_sides.append(side)
	if not _rotation_transitioning and not _rotation_pending_dead_sides.is_empty():
		call_deferred("_rotation_resolve_pending_deaths")

func _retire_rotation_families() -> void:
	# Snapshot victory BEFORE clearing descendants. A living minion can win even
	# when the original body no longer exists. Administrative removal never kills.
	_rotation_clearing_round = true
	var setup_ids:Array[int] = []
	for side:String in ["left","right"]:
		var setup_id:int = int(_rotation_active_setup.get(side,-1))
		if setup_id >= 0:
			setup_ids.append(setup_id)
			var alive:bool = _rotation_side_alive(side)
			_rotation_mark_current_dead(side,not alive,alive)
	for side:String in ["left","right"]:
		for id:int in _rotation_active_records[side]:
			if not setup_ids.has(id): setup_ids.append(id)
	# Include already-extinct slots whose dying bodies/children may still linger.
	for side:String in ["left","right"]:
		var index:int = int(_rotation_next_index[side])-1
		if index >= 0 and index < _rotation_rosters[side].size(): setup_ids.append(int(_rotation_rosters[side][index].id))
	for raw:Variant in _battle_units_cache.duplicate():
		if not raw is ball or not is_instance_valid(raw): continue
		var identity:Dictionary = raw.get_meta(BATTLE_LIFECYCLE_META,{})
		if setup_ids.has(int(identity.get("setup",-1))) and not raw.has_meta("development_reserve"):
			raw.process_mode = Node.PROCESS_MODE_DISABLED
			Game.free_node(raw)
	_battle_lifecycle_round += 1
	_battle_spawn_tickets.clear()
	_rotation_active_setup = {"left":-1,"right":-1}
	_rotation_active_name = {"left":"","right":""}
	_clear_battle_transients()
	_rotation_clearing_round = false

func _collect_alive_victory_sides() -> Dictionary:
	var sides:Dictionary = {}
	for raw:Variant in _battle_units_cache:
		if not raw is ball or not _battle_unit_keeps_family_alive(raw): continue
		var identity:Dictionary = raw.get_meta(BATTLE_LIFECYCLE_META,{})
		var key:String = str(identity.get("victory",""))
		if not key.is_empty(): sides[key] = true
	_prune_battle_spawn_tickets()
	for row:Dictionary in _battle_spawn_tickets.values():
		var key:String = str(row.identity.get("victory",""))
		if not key.is_empty(): sides[key] = true
	return sides

func _configured_manual_victory_side_count() -> int:
	# 手动模式的胜利判定不能只靠“这一帧仍活着的节点”来武装。
	# 某些角色死亡和训练复活都可能发生在相邻帧里，旧逻辑会错过 side_count >= 2，
	# 结果场上已经只剩一方却从未进入可触发状态。
	# _battle_setup 会一直保存玩家实际放下的参战角色，因此用它确认本局原本是否至少有两方。
	var sides:Dictionary = {}
	for entry_value:Variant in _battle_setup:
		if not entry_value is Dictionary:
			continue
		var entry:Dictionary = entry_value as Dictionary
		if str(entry.get("kind","")) == "obstacle": continue
		if not is_victory_setup_current(int(entry.get("id",-1))): continue
		var team_name:String = str(entry.get("team","")).strip_edges()
		var key:String = ""
		if not team_name.is_empty():
			key = "team:" + team_name
		else:
			var setup_id:int = int(entry.get("id",-1))
			if setup_id >= 0:
				key = "solo_setup:" + str(setup_id)
		if not key.is_empty():
			sides[key] = true

	# 兼容不是经 create_char() 放入场景的角色。
	if sides.is_empty():
		# V410：主角色都会由 ball._ready() 注册，复用缓存避免胜负检查每物理帧重新取组。
		for node:Node in _battle_units_cache:
			if not node is ball:
				continue
			var b:ball = node as ball
			if b.health <= 0 or not _is_primary_battle_character(b) or not _battle_unit_keeps_family_alive(b):
				continue
			if not is_victory_setup_current(int(b.get_meta("battle_setup_id",-1))): continue
			var fallback_key:String = _victory_side_key_for_character(b)
			if not fallback_key.is_empty():
				sides[fallback_key] = true

	return sides.size()


func _rotation_side_has_contender(side:String) -> bool:
	if _rotation_side_alive(side): return true
	var roster:Array = _rotation_rosters[side]
	var next_index:int = int(_rotation_next_index.get(side,0))
	return next_index >= 0 and next_index < roster.size()

func request_silverfish_extinction_victory_recheck(extinct_side_key:String) -> void:
	# Compatibility entry only. Never bypass queue/challenge/timed/prebattle rules.
	if extinct_side_key.is_empty() or not is_multiplayer_authority(): return
	var generation:int = _battle_lifecycle_generation
	await get_tree().process_frame
	if generation != _battle_lifecycle_generation or _victory_bell_played: return
	var alive:Dictionary = _collect_alive_victory_sides()
	if alive.has(extinct_side_key): return
	# Do not invent an armed state from an old actor's exit callback.
	# Normal setup/observed sides arm the shared collector, including after reset.
	_update_manual_victory_bell()

func _trigger_victory_bell(ring:bool = true) -> void:
	if _victory_bell_played:
		return
	_victory_bell_played = true
	_victory_bell_armed = false
	if ring: play_victory_bell_triplet()
	# 整场比赛完整结束才放烟花；轮换中间每一场的结算铃不算（最后一场由 _present_rotation_final 放）。
	if not _queue_battle_mode_active() or is_queue_battle_finished(): _celebrate_match_end()

	# V108：胜利音效类角色由World真正完成胜负结算时收到回调。
	# 不让角色自己用“瞬间没敌人”猜胜利，避免轮放换人/复活间隙误触发。
	if not Game.is_timed_training_mode():
		var alive_sides:Dictionary = _collect_alive_victory_sides()
		if alive_sides.size() == 1:
			_notify_battle_victory_for_side(str(alive_sides.keys()[0]))


func _notify_battle_victory_for_side(winner_key:String) -> void:
	if winner_key.is_empty():
		return
	for node:Node in _battle_units_cache:
		if not node is ball or not is_instance_valid(node):
			continue
		var b:ball = node as ball
		if b.health <= 0 or not _is_primary_battle_character(b):
			continue
		if _victory_side_key_for_character(b) != winner_key:
			continue
		if b.has_method("on_battle_victory"):
			b.call_deferred("on_battle_victory")


func _notify_battle_victory_for_setup(setup_id:int) -> void:
	if setup_id < 0:
		return
	for node:Node in _battle_units_cache:
		if not node is ball or not is_instance_valid(node):
			continue
		var b:ball = node as ball
		if b.health <= 0 or not _is_primary_battle_character(b):
			continue
		if int(b.get_meta("battle_setup_id",-1)) != setup_id:
			continue
		if b.has_method("on_battle_victory"):
			b.call_deferred("on_battle_victory")


func _update_manual_victory_bell() -> void:
	_scan_rotation_family_extinctions()
	if not is_multiplayer_authority(): return
	# Free placement / training respawn can introduce a new opponent after a verdict.
	# Reconcile real families BEFORE the old verdict's early return.
	if Game.get_training_mode_type()=="manual" and _victory_bell_played and _collect_alive_victory_sides().size()>=2:
		_begin_manual_victory_encounter()
	if _victory_bell_played: return
	if _development != null and _development.is_prebattle():
		return

	# 手动模式不能把 Team/选人面板是否可见当成“比赛是否开始”的条件。
	# 手动模式允许面板一直开着边放人边战斗；旧逻辑在这里直接 return，
	# 因而手动模式永远走不到下面的最后存活阵营判断。
	# 鼠标主动删除角色会经过 forget_battle_setup_node() 并清掉武装状态，
	# 所以这里可以始终按真实存活阵营判断，而不会把重新布阵误报成胜利。

	# 计时模式按时间结束时的累计伤害判胜，不能因为中途只剩一人就提前响铃。
	if Game.is_timed_training_mode():
		return

	# 轮放不能用“当前场上只剩一边”判断，否则换人间隙会误报。
	# 只有一边已经没有当前角色、也没有后续名单时，另一边才算最终胜利。
	if _queue_battle_mode_active():
		# Challenge settles per blue attempt, not whenever a red roster runs out.
		if Game.is_rotation_training_mode() and Game.get_rotation_match_type() == "challenge": return
		if not _rotation_started or _rotation_transitioning:
			return
		var left_alive:bool = _rotation_side_has_contender("left")
		var right_alive:bool = _rotation_side_has_contender("right")
		if left_alive and right_alive:
			_victory_bell_armed = true
		elif left_alive != right_alive and _victory_bell_armed:
			_trigger_victory_bell()
		return

	# Boss 开场没结束前不结算；开场结束后和普通战斗一样按最后存活阵营判断。
	if Game.is_boss_training_mode() and (not _boss_started or _boss_intro_playing):
		return

	var side_count:int = _collect_alive_victory_sides().size()
	var configured_side_count:int = _configured_manual_victory_side_count()
	# 只要本局实际配置过至少两方，就允许后续只剩一方时结算。
	if configured_side_count >= 2 or side_count >= 2:
		_victory_bell_armed = true

	if side_count == 1 and _victory_bell_armed:
		_trigger_victory_bell()


func is_victory_setup_current(setup_id:int) -> bool:
	return not _victory_encounter_limited or setup_id<0 or _victory_encounter_setup_ids.has(setup_id)

func _include_victory_encounter_unit(unit:ball) -> void:
	if not _victory_encounter_limited or not _battle_unit_keeps_family_alive(unit): return
	if not _is_primary_battle_character(unit): return
	var identity:Dictionary=unit.get_meta(BATTLE_LIFECYCLE_META,{})
	var setup_id:int=int(identity.get("setup",unit.get_meta("battle_setup_id",-1)))
	if setup_id>=0: _victory_encounter_setup_ids[setup_id]=true

func _begin_manual_victory_encounter() -> void:
	# Start a new result scope, not a new battle scene: survivors keep HP, effects and families.
	_reset_victory_bell_state()
	_victory_encounter_limited=true
	for unit:Node in _battle_units_cache:
		if not is_instance_valid(unit) or not unit is ball: continue
		_include_victory_encounter_unit(unit)
		if is_instance_valid(duel_top_hud): duel_top_hud.remember_victory_participant(unit)
	_victory_bell_armed=_collect_alive_victory_sides().size()>=2

func _reset_victory_bell_state() -> void:
	_victory_encounter_limited=false
	_victory_encounter_setup_ids.clear()
	_victory_bell_armed = false
	_victory_bell_played = false
	_battle_start_bell_played = false
	_match_fireworks_played = false
	_intro_camera_state = 0
	_intro_camera_weight = 0.0
	_victory_bell_sequence_generation += 1
	if is_instance_valid(duel_top_hud): duel_top_hud.reset_victory_roster()

func _celebrate_match_end() -> void:
	if _match_fireworks_played or not is_inside_tree(): return
	_match_fireworks_played = true
	_stop_match_fireworks()
	# 烟花在地图上：从画面外飞进来，在地图上空炸开，跟随镜头和录制画面。
	var map_node:Node = _current_map_node()
	_match_fireworks = load(MC_FIREWORK_SCRIPT).celebrate(self,{"area":return_map_world_rect(map_node) if map_node != null else Rect2()})

func _stop_match_fireworks() -> void:
	if is_instance_valid(_match_fireworks): _match_fireworks.queue_free()
	_match_fireworks = null


func play_victory_bell_triplet() -> void:
	# 0.2 秒按真实时间计算；重置/新增对手后不能补播上一场的胜利铃。
	var generation:int=_victory_bell_sequence_generation
	_play_victory_bell_once()
	for _index:int in range(2):
		await get_tree().create_timer(0.2,true,false,true).timeout
		if not is_inside_tree() or generation!=_victory_bell_sequence_generation: return
		_play_victory_bell_once()


func _play_victory_bell_once() -> void:
	if VICTORY_BELL_AUDIO == null or get_tree() == null or get_tree().root == null:
		return
	var player := AudioStreamPlayer.new()
	player.name = "VictoryBell"
	player.stream = VICTORY_BELL_AUDIO
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.volume_db = 1.0
	# 显式指定游戏音频总线；若总线尚未创建则退回 Master。
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	else:
		player.bus = &"Master"
	# 挂到 SceneTree 根节点，避免比赛结算/World 清理过程中把铃声播放器一起删掉。
	get_tree().root.add_child(player,true)
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


## 开战：时间在走、至少两方在场时敲一下钟。每场一次；轮换每一场等门打开后再敲。
func _update_battle_start_bell() -> void:
	if _battle_start_bell_played or _victory_bell_played: return
	if is_instance_valid(_rotation_door) and not _rotation_combat_released:
		# 门关着时先把镜头停在近景，开门后直接拉远，门缝里不会看到镜头突然推进。
		if int(_rotation_door.phase) == int(_rotation_door.Phase.COVERED): _arm_intro_camera()
		return
	if not is_combat_runtime_active(): return
	if _collect_alive_victory_sides().size() < 2: return
	_battle_start_bell_played = true
	_play_battle_start_bell()
	_start_intro_camera()


func _arm_intro_camera() -> void:
	_intro_camera_state = 1
	_intro_camera_age = INTRO_CAMERA_PUNCH_SECONDS
	_aim_intro_camera()
	_intro_camera_weight = 1.0


func _start_intro_camera() -> void:
	# 门后已预备就直接拉远；画面本来可见时先用 0.12 秒快速推近，避免硬切。
	if _intro_camera_state != 1: _intro_camera_age = 0.0
	_intro_camera_state = 2
	_aim_intro_camera()


## 近景对准所有在场角色的中心，倍率尽量让双方都留在画面里。
func _aim_intro_camera() -> void:
	var bounds:Rect2 = Rect2()
	var found:bool = false
	for actor:Node in get_tree().get_nodes_in_group("Ball"):
		if not actor is Node2D or not is_ancestor_of(actor) or not (actor as Node2D).visible: continue
		var point:Vector2 = (actor as Node2D).global_position
		bounds = bounds.expand(point) if found else Rect2(point,Vector2.ZERO)
		found = true
	var view:Vector2 = get_viewport_rect().size
	var zoom_now:float = maxf(_base_camera_zoom_value() * toolbar_zoom_multiplier,0.001)
	if not found:
		var map_node:Node = _current_map_node()
		_intro_camera_anchor = return_map_world_rect(map_node).get_center() if map_node != null else camera_2d.global_position
		_intro_camera_peak = INTRO_CAMERA_MAX_ZOOM
		return
	_intro_camera_anchor = bounds.get_center()
	var span:Vector2 = (bounds.size + Vector2(48.0,48.0)) * zoom_now
	var fit:float = minf(view.x * 0.8 / maxf(span.x,1.0),view.y * 0.6 / maxf(span.y,1.0))
	_intro_camera_peak = clampf(fit,INTRO_CAMERA_MIN_ZOOM,INTRO_CAMERA_MAX_ZOOM)


func _update_intro_camera(delta:float) -> void:
	if _intro_camera_state == 0 or _dead_save_force_non_follow_camera:
		_intro_camera_weight = 0.0
		return
	if _intro_camera_state == 1:
		_aim_intro_camera()
		_intro_camera_weight = 1.0
		return
	_intro_camera_age += minf(delta,1.0 / 30.0)
	if _intro_camera_age < INTRO_CAMERA_PUNCH_SECONDS:
		var punch:float = _intro_camera_age / INTRO_CAMERA_PUNCH_SECONDS
		_intro_camera_weight = 1.0 - (1.0 - punch) * (1.0 - punch)
		return
	var pull:float = clampf((_intro_camera_age - INTRO_CAMERA_PUNCH_SECONDS) / INTRO_CAMERA_PULL_SECONDS,0.0,1.0)
	# 先快后慢：四次方缓出，尾段几乎无感地落回正常视角。
	_intro_camera_weight = pow(1.0 - pull,4.0)
	if pull >= 1.0:
		_intro_camera_state = 0
		_intro_camera_weight = 0.0


func _play_battle_start_bell() -> void:
	if get_tree() == null or get_tree().root == null: return
	var stream:AudioStream = load(BATTLE_START_BELL_PATHS[randi() % BATTLE_START_BELL_PATHS.size()]) as AudioStream
	if stream == null: return
	var player := AudioStreamPlayer.new()
	player.name = "BattleStartBell"
	player.stream = stream
	player.pitch_scale = BATTLE_START_BELL_PITCHES[randi() % BATTLE_START_BELL_PITCHES.size()]
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.bus = &"GameplayRecord" if AudioServer.get_bus_index(&"GameplayRecord") >= 0 else &"Master"
	get_tree().root.add_child(player,true)
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func return_battle_side_count() -> int:
	var battle_data:Dictionary = return_battle_sides()
	return battle_data["order"].size()

#========================================================
# 每个不同阵营分配不同颜色
#========================================================
func return_side_color(side_key:String) -> Color:
	if _side_color_map.has(side_key):
		return _side_color_map[side_key]

	var new_color:Color

	if _next_side_color_index < team_text_colors.size():
		new_color = team_text_colors[_next_side_color_index]
	else:
		# 预设颜色用完后继续自动生成不同色相。
		var extra_index:int = _next_side_color_index - team_text_colors.size()
		var hue:float = fmod(float(extra_index) * 0.61803398875 + 0.08,1.0)
		new_color = Color.from_hsv(hue,0.78,1.0)

	_side_color_map[side_key] = new_color
	_next_side_color_index += 1
	return new_color

func _versus_is_named_team(side_key:String) -> bool:
	if not side_key.begins_with("team:"):
		return false
	var team_name:String = side_key.trim_prefix("team:").strip_edges()
	return not team_name.is_empty() and team_name.to_lower() not in ["中立","neutral"]

func _versus_side_color(side_key:String,active_team_count:int,team_index:int) -> Color:
	# VS 和中立者在只有一个真实队伍时也保持白字；有多个真实队伍才分色。
	if active_team_count < 2 or not _versus_is_named_team(side_key):
		return Color.WHITE
	# 布阵时队伍可能移除/重排：蓝、红必须始终对应当前第一、第二队。
	if team_index == 0:
		return Color(0.25,0.65,1.0)
	if team_index == 1:
		return Color(1.0,0.26,0.26)
	if _versus_team_colors.has(side_key):
		return _versus_team_colors[side_key]
	# 第三队起按本局 seed / 队名抽色，后续标题刷新与位置变化沿用缓存。
	var picker:= RandomNumberGenerator.new()
	picker.seed = int(_battle_random_seed) ^ int(side_key.hash()) ^ ((_next_versus_team_color_index+2) * 1315423911)
	var hue:float = 0.31
	for _attempt:int in range(18):
		hue = picker.randf()
		if minf(hue,1.0-hue) < 0.11 or absf(hue-0.59) < 0.11:
			continue
		var used:bool = false
		for existing:Color in _versus_team_colors.values():
			var gap:float = absf(existing.h-hue)
			if minf(gap,1.0-gap) < 0.09:
				used = true
				break
		if not used:
			break
	var color:Color = Color.from_hsv(hue,picker.randf_range(0.70,0.88),picker.randf_range(0.84,1.0))
	_versus_team_colors[side_key] = color
	_next_versus_team_color_index += 1
	return color

#========================================================
# 第一行：A + B  VS  C + D
#
# 不显示 Team 名；同 Team 角色名放在同一组；不同阵营不同颜色。
#========================================================
# 盔甲架测试 HUD
#========================================================
func _is_armor_stand_test_unit(candidate:ball) -> bool:
	if candidate == null or not is_instance_valid(candidate) or candidate.is_queued_for_deletion():
		return false
	var script_resource:Script = candidate.get_script() as Script
	if script_resource == null:
		return false
	var script_path:String = script_resource.resource_path
	return (
		script_path.begins_with("res://scripts/characters/默认/")
		and script_path.get_file().contains("盔甲架.gd")
	)


func _refresh_armor_stand_test_mode_state() -> bool:
	var was_active:bool = _armor_stand_test_hud_active
	_armor_stand_test_hud_active = false
	for node:Node in _battle_units_cache:
		if node is ball and _is_armor_stand_test_unit(node as ball):
			_armor_stand_test_hud_active = true
			break
	if was_active != _armor_stand_test_hud_active:
		_last_versus_text = ""
		if not _armor_stand_test_hud_active:
			_clear_armor_stand_test_primary_enemy()
	return _armor_stand_test_hud_active


func _clear_armor_stand_test_primary_enemy() -> void:
	_armor_stand_test_primary_setup_id = -1
	_armor_stand_test_primary_instance_id = 0
	_armor_stand_test_primary_side_key = ""
	_armor_stand_test_primary_identity = ""
	_armor_stand_test_primary_script_path = ""
	_armor_stand_test_primary_snapshot.clear()


func _armor_test_candidate_identity(candidate:ball) -> String:
	if candidate == null or not is_instance_valid(candidate):
		return ""
	if _is_battle_continuation_unit(candidate):
		var continuation_name:String = str(candidate.get_meta(&"battle_continuation_display_name","")).strip_edges()
		if not continuation_name.is_empty():
			return continuation_name
	if _is_battle_death_bridge_unit(candidate):
		var bridge_name:String = str(candidate.get_meta(&"battle_death_bridge_display_name","")).strip_edges()
		if not bridge_name.is_empty():
			return bridge_name
	return return_ball_display_name(candidate)


func _armor_test_candidate_side_key(candidate:ball) -> String:
	if candidate == null or not is_instance_valid(candidate):
		return ""
	if _is_battle_continuation_unit(candidate):
		var continuation:String = str(candidate.get_meta(&"battle_continuation_victory_side_key","")).strip_edges()
		if not continuation.is_empty():
			return continuation
	if _is_battle_death_bridge_unit(candidate):
		var bridge:String = _battle_death_bridge_victory_side_key(candidate)
		if not bridge.is_empty():
			return bridge
	return _victory_side_key_for_character(candidate)


func _armor_test_is_enemy_candidate(candidate:ball) -> bool:
	if candidate == null or not is_instance_valid(candidate) or candidate.is_queued_for_deletion():
		return false
	if _is_armor_stand_test_unit(candidate):
		return false
	# 普通召唤物、宠物、投射物和二级单位都不是新的“敌人角色”。
	# 只有比赛延续单位可以在原角色死亡后继续代表同一个角色。
	if not _is_primary_battle_character(candidate) and not _is_battle_continuation_unit(candidate):
		return false
	if candidate.health <= 0 and not _is_battle_death_bridge_unit(candidate):
		return false
	return true


func _armor_test_matches_locked_role(candidate:ball) -> bool:
	if not _armor_test_is_enemy_candidate(candidate):
		return false
	if _armor_stand_test_primary_instance_id != 0 and candidate.get_instance_id() == _armor_stand_test_primary_instance_id:
		return true

	# 手动放置的主角色优先用 battle_setup_id 精确锁定；这能区分同队伍里的多个不同角色。
	if _armor_stand_test_primary_setup_id >= 0 and candidate.has_meta(&"battle_setup_id"):
		if int(candidate.get_meta(&"battle_setup_id",-1)) == _armor_stand_test_primary_setup_id:
			return true

	# 原角色被“延续单位”接棒后（例如蠹虫从石砖孵化），setup_id 可能不在新实例上。
	# 此时使用冻结的阵营键 + 身份名继续认作同一个角色，而不是切到第二个敌人。
	var identity:String = _armor_test_candidate_identity(candidate)
	if identity != _armor_stand_test_primary_identity:
		return false
	var side_key:String = _armor_test_candidate_side_key(candidate)
	return not _armor_stand_test_primary_side_key.is_empty() and side_key == _armor_stand_test_primary_side_key


func _armor_stand_test_first_enemy() -> ball:
	# 已锁定时优先追踪这个角色本身或它的比赛延续单位。
	# 如果整个角色已经真正从场上消失，就立刻解除旧锁并重新选择当前“第一个角色”。
	# 这样删除旧角色后再放新角色，不会继续显示上一只的缓存信息。
	if not _armor_stand_test_primary_identity.is_empty():
		for raw:Variant in _battle_units_cache:
			if raw is ball:
				var locked_candidate:ball = raw as ball
				if _armor_test_matches_locked_role(locked_candidate):
					return locked_candidate
		_clear_armor_stand_test_primary_enemy()

	# 严格按战斗单位注册顺序，跳过盔甲架与普通召唤物。
	# 因而同一时刻只显示一个角色；该角色的普通召唤物不会抢走 HUD。
	for raw:Variant in _battle_units_cache:
		if not raw is ball:
			continue
		var candidate:ball = raw as ball
		if not _armor_test_is_enemy_candidate(candidate):
			continue
		_armor_stand_test_primary_instance_id = candidate.get_instance_id()
		_armor_stand_test_primary_setup_id = int(candidate.get_meta(&"battle_setup_id",-1))
		_armor_stand_test_primary_side_key = _armor_test_candidate_side_key(candidate)
		_armor_stand_test_primary_identity = _armor_test_candidate_identity(candidate)
		_armor_stand_test_primary_script_path = _armor_test_script_path(candidate)
		return candidate
	return null

func _armor_test_number(value:float) -> String:
	if is_equal_approx(value,round(value)):
		return str(int(round(value)))
	return "%.1f" % value


func _armor_test_script_path(enemy:ball) -> String:
	if enemy == null or not is_instance_valid(enemy):
		return ""
	var script_resource:Script = enemy.get_script() as Script
	return script_resource.resource_path if script_resource != null else ""


func _armor_test_bark_collisions_needed(enemy:ball) -> int:
	if enemy == null or not is_instance_valid(enemy):
		return 0
	var bark_mechanic:Node = enemy.get_node_or_null("BarkMechanic")
	if bark_mechanic == null:
		return 0
	var value:Variant = bark_mechanic.get("collisions_before_howl")
	if value == null:
		return 0
	return maxi(int(value),0)


func _armor_test_bark_collision_progress(enemy:ball) -> int:
	if enemy == null or not is_instance_valid(enemy):
		return 0
	var bark_mechanic:Node = enemy.get_node_or_null("BarkMechanic")
	if bark_mechanic == null:
		return 0
	if bark_mechanic.has_method("get_sound_count"):
		return maxi(int(bark_mechanic.call("get_sound_count")),0)
	var value:Variant = bark_mechanic.get("_sound_count")
	return maxi(int(value),0) if value != null else 0


func _armor_test_sans_dodge_status(enemy:ball) -> Dictionary:
	if _armor_test_script_path(enemy) != "res://scripts/characters/传说之下/Sans.gd":
		return {}
	var remaining_value:Variant = enemy.get("_dodge_count")
	var max_value:Variant = enemy.get("max_dodge_count")
	var high_value:Variant = enemy.get("attack_high_dodge_min")
	var medium_value:Variant = enemy.get("attack_medium_dodge_min")
	if remaining_value == null or max_value == null:
		return {}
	var remaining:int = maxi(int(remaining_value),0)
	var maximum:int = maxi(int(max_value),1)
	var high_min:int = clampi(int(high_value) if high_value != null else 10,0,maximum)
	var medium_min:int = clampi(int(medium_value) if medium_value != null else 5,0,high_min)
	var pace:String = "正常"
	if remaining < medium_min:
		pace = "慢"
	elif remaining < high_min:
		pace = "快"
	return {"remaining":remaining,"maximum":maximum,"pace":pace}


func _armor_test_pancake_projectile_status(enemy:ball) -> Dictionary:
	if _armor_test_script_path(enemy) != "res://scripts/characters/meme/不坏煎饼.gd":
		return {}
	var projectile_variant:Variant = enemy.get("_projectile")
	if not projectile_variant is ball:
		return {}
	var projectile:ball = projectile_variant as ball
	if projectile == null or not is_instance_valid(projectile) or projectile.is_queued_for_deletion():
		return {}
	var ratio:float = 0.0
	if projectile.has_method("get_rot_ratio"):
		ratio = clampf(float(projectile.call("get_rot_ratio")),0.0,1.0)
	var damage_multiplier:float = 1.0
	if projectile.has_method("current_hit_damage_multiplier"):
		damage_multiplier = maxf(float(projectile.call("current_hit_damage_multiplier")),0.0)
	var poison_threshold_value:Variant = projectile.get("poison_rot_threshold")
	var poison_threshold:float = clampf(float(poison_threshold_value) if poison_threshold_value != null else 0.70,0.0,1.0)
	return {
		"rot_ratio":ratio,
		"speed":maxf(projectile.Speed,0.0),
		"damage_multiplier":damage_multiplier,
		"poison_threshold":poison_threshold,
		"poison_active":ratio >= poison_threshold,
	}


const ARMOR_TEST_ROLE_SUMMARIES:Dictionary = {
	# 人物
	"res://scripts/characters/NC佬.gd":"开局补到4名步枪兵；存活约120秒后召唤坦克。",
	"res://scripts/characters/伤心的男人.gd":"持续落雨攻击；伞能挡住从上方来的部分攻击。",
	"res://scripts/characters/伪军头子.gd":"受伤会积累增援进度，消耗会恢复的钞票补充伪军。",
	"res://scripts/characters/保安.gd":"半血或队友阵亡时会呼叫巡逻车增援。",
	"res://scripts/characters/默认/军官.gd":"掉血积怒，脱战会降怒；满怒呼叫核弹。",
	"res://scripts/characters/军火商.gd":"定期放置随机枪械，枪会自动锁敌、射击和装填。",
	"res://scripts/characters/决斗者.gd":"敌人进入突刺距离后会高速突进，起手后锁定方向完成突刺。",
	"res://scripts/characters/剑客.gd":"会短暂招架；招架成功立刻反击，剑击还能叠流血。",
	"res://scripts/characters/占卜师.gd":"每次抽4张牌产生不同效果；4张命运之轮会直接处决全部敌人。",
	"res://scripts/characters/原始人.gd":"火堆能给自己回血。",
	"res://scripts/characters/变形者.gd":"周期性随机变成其他角色，并暂时使用那个角色的机制。",
	"res://scripts/characters/国王.gd":"半血召唤将军；血量更低时会召唤更多守卫。",
	"res://scripts/characters/小丑.gd":"每次攻击随机抽取一种武器，效果和强度都随机。",
	"res://scripts/characters/小偷.gd":"准备完成后，下一次撞到敌人会随机偷取攻击、移速、生命上限或攻速。",
	"res://scripts/characters/布鲁斯.gd":"主要靠狗作战；狗死亡时主人也会死亡。",
	"res://scripts/characters/建筑工人.gd":"最多保留一堵墙；有墙后会扔砖，砖既能伤敌也会损耗自己的墙。",
	"res://scripts/characters/影子.gd":"影子会延迟重复本体的吼叫攻击。",
	"res://scripts/characters/战斧重骑兵.gd":"护甲破碎后速度和攻速提高，但受到的伤害也更高。",
	"res://scripts/characters/投资者.gd":"行情柱会压缩场地；红柱越低，攻击和移动越强。",
	"res://scripts/characters/拳击手.gd":"身体碰撞不直接伤害；贴身会出拳，距离远时会冲拳接近。",
	"res://scripts/characters/人物/掷骰子的人.gd":"周期性掷骰子，不同点数触发不同随机效果；半血会额外掷一次。",
	"res://scripts/characters/收债人.gd":"攻击会给敌人好处并记债；债务复利增长，超过当前生命时直接斩杀。",
	"res://scripts/characters/数学老师.gd":"算式答案就是粉笔的基础伤害。",
	"res://scripts/characters/时光客.gd":"记录最近轨迹；倒放时沿原路返回，并伤害途中碰到的敌人。",
	"res://scripts/characters/智者.gd":"依次布置1到4号阵点；敌人按顺序踩中时伤害逐段提高。",
	"res://scripts/characters/服务员.gd":"能在墙边开门让角色穿出地图，但仍受出界倒计时限制。",
	"res://scripts/characters/极速者.gd":"会预测弹道和冲锋，在命中前主动闪避。",
	"res://scripts/characters/棋手.gd":"连成五子时触发高伤害连线。",
	"res://scripts/characters/火车长.gd":"挖煤送进列车；煤越多，车厢越多、再次发车越快。",
	"res://scripts/characters/炮兵.gd":"炮击先标记区域和落点，警示结束后同时轰炸。",
	"res://scripts/characters/炸弹客.gd":"地雷不会自行爆炸，只会被其他爆炸连锁引燃；撞到敌人还会贴定时炸弹。",
	"res://scripts/characters/猎人.gd":"会布捕兽夹，踩中后受伤并短暂无法移动。",
	"res://scripts/characters/人物/疲倦的人.gd":"第一次死亡不会退场，而是随机变成愤怒或悲伤形态继续战斗。",
	"res://scripts/characters/人物/悲伤的男人.gd":"持续发射高频泪滴弹幕。",
	"res://scripts/characters/人物/愤怒的男人.gd":"接近目标时才会减速连续出拳。",
	"res://scripts/characters/矿工.gd":"重锤后会进入短暂疲劳；砸出的石头落地后会变成地形。",
	"res://scripts/characters/磁铁.gd":"吸引时把附近投射物抓进轨道，排斥时再一起甩出去。",
	"res://scripts/characters/科学家.gd":"弹丸可以通过自己布置的传送门改变位置。",
	"res://scripts/characters/红绿灯.gd":"黄灯惩罚短时间移动过远；红灯按移动距离持续造成伤害。",
	"res://scripts/characters/背刺者.gd":"会主动绕到目标背后抓背刺机会。",
	"res://scripts/characters/乐队/若叶睦.gd":"若叶睦靠黄瓜恢复；墨提斯改用近战。",
	"res://scripts/characters/裁判.gd":"短时间承受大量伤害后随机出牌：黄牌眩晕，蓝牌高伤，红牌封锁伤害输出。",
	"res://scripts/characters/训犬师.gd":"标记敌人后，猎犬会围绕标记目标行动；猎犬不足时会继续补充。",
	"res://scripts/characters/赌徒.gd":"六膛左轮使用真实弹巢；空膛不会造成枪击伤害，打空后逐颗装填。",
	"res://scripts/characters/醉汉.gd":"移动和攻击方式都随机，并会有限度躲弹。",
	"res://scripts/characters/重女.gd":"第一次死亡进入二阶段：持续吸引附近敌人并造成范围伤害，同时自己不断掉血。",
	"res://scripts/characters/键盘侠.gd":"文字越长伤害越高；负面词会获得额外伤害倍率。",
	"res://scripts/characters/锻刀师.gd":"先锻造武器再战斗；刀耐久耗尽后重新锻造。",
	"res://scripts/characters/镜子.gd":"会短暂开启反射窗口，把命中的投射物反射回去。",
	"res://scripts/characters/面包车.gd":"冲撞速度越高，伤害和击退越强；还会周期性放下跟班。",
	"res://scripts/characters/领导.gd":"受伤有概率掉落不同资产，并触发对应的经济/处分效果。",
	"res://scripts/characters/黑帮老大.gd":"会维持一批小弟，人数不足时持续补充，并给小弟扔钱强化。",
	"res://scripts/characters/鼓手.gd":"碰撞推进节拍；第3拍拉近敌人，第4拍强化伤害并推开敌人。",
	# 动物
	"res://scripts/characters/动物/九头蛇.gd":"蛇头被打掉后会重新长出；蛇头越多，同时攻击方向越多。",
	"res://scripts/characters/兔子.gd":"成年兔子相遇会繁殖，小兔长大后继续繁殖，数量有上限。",
	"res://scripts/characters/动物/牛系.gd":"连续奔跑会不断加速并提高冲撞伤害；受伤积累到阈值会吃草回血。",
	"res://scripts/characters/猫.gd":"拥有多条命，前几次死亡会消耗一条命复活。",
	# Meme
	"res://scripts/characters/meme/不坏煎饼.gd":"腐烂越高，子弹速度、伤害和命中频率越低；70%后命中叠永久中毒，满腐烂重置状态。",
	"res://scripts/characters/meme/凑企鹅.gd":"石头扔出后必须捡回；低血量目标会被同化成新的凑企鹅。",
	"res://scripts/characters/meme/大狗叫.gd":"碰撞累计进度，满后连续发射声波；小狗会跟随大狗，但效果更弱。",
	"res://scripts/characters/meme/寸头没事沙漠溜达猪.gd":"会预测来弹并闪避；危险过高时直接跳开。",
	"res://scripts/characters/meme/愤怒的普通人.gd":"生命越低，伤害和攻速越高。",
	"res://scripts/characters/meme/时光.gd":"段位随时间提升；段位越高落子越快，九段后有概率进入更强状态。",
	"res://scripts/characters/meme/棍母.gd":"不会和其他角色实体阻挡，但贴身伤害区域会持续造成伤害。",
	"res://scripts/characters/meme/肌肉男.gd":"手臂持续加速；真正命中后速度重置再重新加速。",
	"res://scripts/characters/meme/菊花茶.gd":"周期性开启定向重力，把全场单位和投射物往当前移动方向拉。",
	"res://scripts/characters/meme/野生狗奶.gd":"会不断减慢世界时间；加速期间无敌并回血，还会让敌人衰老并降低属性。",
	# 三角洲
	"res://scripts/characters/三角洲/堵桥.gd":"技能会转移到地图上方持续向下射击，并配合火圈和巡飞弹压制区域。",
	"res://scripts/characters/夺舍狼.gd":"技能会停下并进入蓄力攻击姿态。",
	"res://scripts/characters/三角洲/盾狗.gd":"正面盾牌减伤并完全格挡前方投射物；近身会盾击，造成伤害、击退与眩晕并消耗体力。\n会自动向正面中距离敌人发射钩爪，命中造成伤害并把目标拉到自己面前；墙体会挡住钩爪。\n技能会投掷刀片生成铁丝网：进入会受伤并持续减速，在网内移动会继续受伤并叠流血；铁丝网有耐久、会自然损耗，也会被攻击/投射物破坏。\n盾击会优先把正前方敌人撞向附近铁丝网；体力会自动回复。",
	"res://scripts/characters/三角洲/背刺鼠.gd":"永远攻击最近角色，不分敌我，也不受全局友伤开关限制。",
	"res://scripts/characters/三角洲/跑刀仔.gd":"死亡后进入第二命，并通过搜物资购买枪械和护甲。",
	# 乐队
	"res://scripts/characters/乐队/户山香澄.gd":"星星砸中敌人会永久提高攻速。",
	"res://scripts/characters/乐队/薇欧拉.gd":"拍照会眩晕并积累舆论；录音会记录伤害来源并用文字弹幕反击。",
	# 我的世界：稳定翻译键；中英文战斗机制统一维护于 translations.csv。
	"res://scripts/characters/我的世界/bat/bat.gd":"MC_ARMOR_INTRO_BAT",
	"res://scripts/characters/我的世界/cactus_note/note_block.gd":"MC_ARMOR_INTRO_JUKEBOX",
	"res://scripts/characters/我的世界/wither/wither.gd":"MC_ARMOR_INTRO_WITHER",
	"res://scripts/characters/我的世界/wither_skeleton/wither_skeleton.gd":"MC_ARMOR_INTRO_WITHER_SKELETON",
	"res://scripts/characters/我的世界/new5/fishing_rod.gd":"MC_ARMOR_INTRO_FISHING_ROD",
	"res://scripts/characters/我的世界/蠹虫.gd":"MC_ARMOR_INTRO_SILVERFISH",
	"res://scripts/characters/我的世界/new5/ghast.gd":"MC_ARMOR_INTRO_GHAST",
	"res://scripts/characters/我的世界/new6/bow.gd":"MC_ARMOR_INTRO_BOW",
	"res://scripts/characters/我的世界/皓宸.gd":"MC_ARMOR_INTRO_HAOCHEN",
	"res://scripts/characters/我的世界/唤魔者.gd":"MC_ARMOR_INTRO_EVOKER",
	"res://scripts/characters/我的世界/vindicator/vindicator.gd":"MC_ARMOR_INTRO_VINDICATOR",
	"res://scripts/characters/我的世界/frontier/warden.gd":"MC_ARMOR_INTRO_WARDEN",
	"res://scripts/characters/我的世界/骷髅.gd":"MC_ARMOR_INTRO_SKELETON",
	"res://scripts/characters/我的世界/苦力怕.gd":"MC_ARMOR_INTRO_CREEPER",
	"res://scripts/characters/我的世界/minecart/minecart.gd":"MC_ARMOR_INTRO_MINECART",
	"res://scripts/characters/我的世界/clock/clock.gd":"MC_ARMOR_INTRO_CLOCK",
	"res://scripts/characters/我的世界/烈焰人.gd":"MC_ARMOR_INTRO_BLAZE",
	"res://scripts/characters/我的世界/流浪商人.gd":"MC_ARMOR_INTRO_WANDERING_TRADER",
	"res://scripts/characters/我的世界/硫方怪.gd":"MC_ARMOR_INTRO_SULFUR_CUBE",
	"res://scripts/characters/我的世界/末影人.gd":"MC_ARMOR_INTRO_ENDERMAN",
	"res://scripts/characters/我的世界/new6/oak_boat.gd":"MC_ARMOR_INTRO_OAK_BOAT",
	"res://scripts/characters/我的世界/frontier/wooden_sword.gd":"MC_ARMOR_INTRO_WOODEN_SWORD",
	"res://scripts/characters/我的世界/木矛.gd":"MC_ARMOR_INTRO_WOODEN_SPEAR",
	"res://scripts/characters/我的世界/溺尸.gd":"MC_ARMOR_INTRO_DROWNED",
	"res://scripts/characters/我的世界/女巫.gd":"MC_ARMOR_INTRO_WITCH",
	"res://scripts/characters/我的世界/潜影贝.gd":"MC_ARMOR_INTRO_SHULKER",
	"res://scripts/characters/我的世界/鞘翅长矛.gd":"MC_ARMOR_INTRO_ELYTRA_SPEAR",
	"res://scripts/characters/我的世界/鞘翅重锤.gd":"MC_ARMOR_INTRO_ELYTRA_MACE",
	"res://scripts/characters/我的世界/鞘翅重锤长矛.gd":"MC_ARMOR_INTRO_ELYTRA_MACE_SPEAR",
	"res://scripts/characters/我的世界/石矛.gd":"MC_ARMOR_INTRO_STONE_SPEAR",
	"res://scripts/characters/我的世界/new5/slime.gd":"MC_ARMOR_INTRO_SLIME",
	"res://scripts/characters/我的世界/new5/guardian.gd":"MC_ARMOR_INTRO_GUARDIAN",
	"res://scripts/characters/我的世界/frontier/moss.gd":"MC_ARMOR_INTRO_MOSS_BLOCK",
	"res://scripts/characters/我的世界/new6/heavenfall_longbow.gd":"MC_ARMOR_INTRO_LONGBOW_OF_THE_HEAVENS",
	"res://scripts/characters/我的世界/goat_horn/goat_horn.gd":"MC_ARMOR_INTRO_GOAT_HORN",
	"res://scripts/characters/我的世界/useless_stones/useless_stones.gd":"MC_ARMOR_INTRO_USELESS_STONES",
	"res://scripts/characters/我的世界/enchanting_table/enchanting_table.gd":"MC_ARMOR_INTRO_ENCHANTING_TABLE",
	"res://scripts/characters/我的世界/铁匠村民.gd":"MC_ARMOR_INTRO_BLACKSMITH_VILLAGER",
	"res://scripts/characters/我的世界/铁傀儡.gd":"MC_ARMOR_INTRO_IRON_GOLEM",
	"res://scripts/characters/我的世界/铁砧.gd":"MC_ARMOR_INTRO_ANVIL",
	"res://scripts/characters/我的世界/铜剑.gd":"MC_ARMOR_INTRO_COPPER_SWORD",
	"res://scripts/characters/我的世界/fog_man/actor.gd":"MC_ARMOR_INTRO_FOG_MAN",
	"res://scripts/characters/我的世界/cactus_note/cactus.gd":"MC_ARMOR_INTRO_CACTUS",
	"res://scripts/characters/我的世界/snow_golem/snow_golem.gd":"MC_ARMOR_INTRO_SNOW_GOLEM",
	"res://scripts/characters/我的世界/new6/sheep.gd":"MC_ARMOR_INTRO_SHEEP",
	"res://scripts/characters/我的世界/allay/allay.gd":"MC_ARMOR_INTRO_ALLAY",
	"res://scripts/characters/我的世界/new5/piston.gd":"MC_ARMOR_INTRO_STICKY_PISTON",
	"res://scripts/characters/我的世界/蜘蛛.gd":"MC_ARMOR_INTRO_SPIDER",
	"res://scripts/characters/我的世界/重锤.gd":"MC_ARMOR_INTRO_MACE",
	"res://scripts/characters/我的世界/钻石剑.gd":"MC_ARMOR_INTRO_DIAMOND_SWORD",
	"res://scripts/characters/我的世界/钻石长矛.gd":"MC_ARMOR_INTRO_DIAMOND_SPEAR",
	# 月计
	"res://scripts/characters/月计/伞夫.gd":"理智越低连段越长，负理智时会追加更多攻击段数。",
	"res://scripts/characters/月计/堇紫泪滴.gd":"四种姿态机制不同；能叠流血，并在低血时回溯一次几秒前的状态。",
	"res://scripts/characters/月计/殷红迷雾.gd":"理智影响攻防；进入E.G.O后大幅强化，并解锁横扫和低血处决。",
	# 杀戮尖塔
	"res://scripts/characters/杀戮尖塔/小刀猎.gd":"无额外特殊机制。",
	"res://scripts/characters/杀戮尖塔/异蛙寄生虫.gd":"命中会寄生；会生成小寄生虫，本体死亡时还会爆出多只小虫继续作战。",
	"res://scripts/characters/杀戮尖塔/异蛙寄生虫_小.gd":"母体生成的弱化小虫。",
	"res://scripts/characters/杀戮尖塔/战士.gd":"攻击时伤害和攻击距离提高，但自己会减速；命中后强力击退。",
	"res://scripts/characters/杀戮尖塔/猎人杀手.gd":"攻击它的人会被削弱攻击和移速，连续攻击会继续叠加。",
	"res://scripts/characters/杀戮尖塔/虔诚雕刻师.gd":"技能会永久叠加自己的攻击力。",
	"res://scripts/characters/杀戮尖塔/蛇咬相生猎.gd":"每轮攻击数量会翻倍，直到达到单轮上限。",
	"res://scripts/characters/杀戮尖塔/蜂群术士.gd":"持续召唤蜜蜂追敌；受伤时会反伤并短暂眩晕攻击者。",
	"res://scripts/characters/杀戮尖塔/观者.gd":"红姿态强化输出和速度，蓝姿态强化防御，神格同时强化攻防。",
	"res://scripts/characters/杀戮尖塔/锻剑储君.gd":"每次攻击都会永久提高飞剑攻击力。",
	"res://scripts/characters/杀戮尖塔/门扉缔造者.gd":"吞噬形态偷Buff，眼睛形态减速敌人，手形态召唤帮手。",
	# 游戏 / 动漫 / 传说之下 / 物品
	"res://scripts/characters/游戏/战争女神.gd":"法阵会伤敌并回血；累计回复到阈值后进入二阶段，获得更高移速和远程火焰。",
	"res://scripts/characters/游戏/魔角猎人.gd":"攻击会叠标记并灼烧；标记升到最高后继续叠满会触发过载爆炸。",
	"res://scripts/characters/动漫/菜月昴.gd":"死亡会触发死亡回归，把整场战斗倒回之前的时间点。",
	"res://scripts/characters/传说之下/Sans.gd":"最多闪避14次；剩5~9次时攻速加快，0~4次时反而变慢；骨头和龙骨炮会叠业力。",
	"res://scripts/characters/气球.gd":"持续充气，达到条件后爆炸。",
	"res://scripts/characters/bilibili.gd":"无额外特殊机制。",
}


func _armor_test_special_effect_summary(enemy:ball,_tags:PackedStringArray) -> String:
	if enemy == null or not is_instance_valid(enemy):
		return ""
	# V419：复杂角色可以在自己的脚本中提供完整盔甲架测试说明。
	# 角色脚本最清楚自己的真实机制与当前 Inspector 数值，因此优先使用它，
	# 避免 world.gd 的一行简表在角色持续迭代后漏掉钩爪、陷阱、控制等关键特性。
	if enemy.has_method("get_armor_test_effect_summary"):
		var custom_summary:String = str(enemy.call("get_armor_test_effect_summary")).strip_edges()
		if not custom_summary.is_empty():
			return custom_summary

	# 没有角色自定义说明时才回退到历史汇总表。说明仍绑定到“最初放下的角色”，
	# 这样蠹虫、小弟、第二形态等只属于原角色整体，不会把顶部介绍切成召唤物自己的说明。
	var role_script_path:String = _armor_stand_test_primary_script_path
	if role_script_path.is_empty():
		role_script_path = _armor_test_script_path(enemy)
	return Game.t(str(ARMOR_TEST_ROLE_SUMMARIES.get(role_script_path,"")))

func _armor_test_capture_snapshot(enemy:ball) -> Dictionary:
	if enemy == null or not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
		_armor_stand_test_primary_snapshot.clear()
		return {}
	var snapshot:Dictionary = {
		"script_path":_armor_test_script_path(enemy),
		"bark_collisions_needed":_armor_test_bark_collisions_needed(enemy),
		"bark_collision_progress":_armor_test_bark_collision_progress(enemy),
		"sans_dodge":_armor_test_sans_dodge_status(enemy),
		"pancake_projectile":_armor_test_pancake_projectile_status(enemy),
		"shield_dog_stamina":float(enemy.get("stamina")) if _armor_test_script_path(enemy) == "res://scripts/characters/三角洲/盾狗.gd" and enemy.get("stamina") != null else -1.0,
		"shield_dog_stamina_max":float(enemy.get("stamina_max")) if _armor_test_script_path(enemy) == "res://scripts/characters/三角洲/盾狗.gd" and enemy.get("stamina_max") != null else -1.0,
		"damage":enemy.Damage,
		"speed":enemy.Speed,
		"can_attack":enemy.Can_Attack,
		"can_skill":enemy.Can_Skill,
		"attack_cd":enemy.Attack_Cooling,
		"skill_cd":enemy.Skill_Cooling,
		"collision_damage":enemy.Has_Collision_Damage,
		"block":enemy.block,
		"max_block":enemy.max_block,
		"damage_reduction":enemy.Damage_reduction,
		"tags":enemy.Type_Tags.duplicate(),
		"special":_armor_test_special_effect_summary(enemy,enemy.Type_Tags),
	}
	_armor_stand_test_primary_snapshot = snapshot
	return snapshot


func _build_armor_stand_test_enemy_info() -> String:
	var enemy:ball = _armor_stand_test_first_enemy()
	var snapshot:Dictionary = _armor_test_capture_snapshot(enemy)
	if snapshot.is_empty():
		return ""

	var parts:PackedStringArray = PackedStringArray()
	var script_path:String = str(snapshot.get("script_path",""))
	var is_big_dog:bool = script_path == "res://scripts/characters/meme/大狗叫.gd"
	var is_sans:bool = script_path == "res://scripts/characters/传说之下/Sans.gd"
	var is_pancake:bool = script_path == "res://scripts/characters/meme/不坏煎饼.gd"
	var is_shield_dog:bool = script_path == "res://scripts/characters/三角洲/盾狗.gd"

	# 顶部只显示角色真正的特殊机制。通用攻击、移速、CD、外形变化等都不再展示；
	# 只有与核心机制直接相关的动态状态才额外显示。
	if is_sans:
		var dodge_status:Dictionary = snapshot.get("sans_dodge",{}) as Dictionary
		if not dodge_status.is_empty():
			parts.append(
				"闪避 " + str(int(dodge_status.get("remaining",0))) + "/"
				+ str(int(dodge_status.get("maximum",1)))
			)
			parts.append("攻速 " + str(dodge_status.get("pace","正常")))
	elif is_pancake:
		var pancake_status:Dictionary = snapshot.get("pancake_projectile",{}) as Dictionary
		if not pancake_status.is_empty():
			parts.append("腐烂 " + str(int(round(float(pancake_status.get("rot_ratio",0.0)) * 100.0))) + "%")
			parts.append("弹速 " + _armor_test_number(float(pancake_status.get("speed",0.0))))
			parts.append("弹伤 " + str(int(round(float(pancake_status.get("damage_multiplier",1.0)) * 100.0))) + "%")
			if bool(pancake_status.get("poison_active",false)):
				parts.append("中毒 开")
	elif is_big_dog:
		var collisions_needed:int = int(snapshot.get("bark_collisions_needed",0))
		if collisions_needed > 0:
			var collision_progress:int = clampi(int(snapshot.get("bark_collision_progress",0)),0,collisions_needed)
			parts.append("碰撞 " + str(collision_progress) + "/" + str(collisions_needed))
	elif is_shield_dog:
		var stamina_now:float = float(snapshot.get("shield_dog_stamina",-1.0))
		var stamina_maximum:float = float(snapshot.get("shield_dog_stamina_max",-1.0))
		if stamina_now >= 0.0 and stamina_maximum > 0.0:
			parts.append("体力 " + _armor_test_number(stamina_now) + "/" + _armor_test_number(stamina_maximum))

	var lines:PackedStringArray = PackedStringArray()
	if not parts.is_empty():
		lines.append("  |  ".join(parts))
	var special_text:String = str(snapshot.get("special","")).strip_edges()
	if not special_text.is_empty():
		lines.append(special_text)
	if lines.is_empty():
		return ""
	# Keep the selected original role name, not a matchup or a summoned unit name.
	var role_name:String = escape_bbcode(Game.t(_armor_stand_test_primary_identity).replace("_"," "))
	return "[center][color=#F2F2F2][b]" + role_name + "[/b]\n" + "\n".join(lines) + "[/color][/center]"


func _apply_armor_stand_test_hud_suppression() -> void:
	if not _armor_stand_test_hud_active:
		return
	if is_instance_valid(rotation_versus_root):
		rotation_versus_root.visible = false
	if is_instance_valid(timed_training_label):
		timed_training_label.visible = false
	if is_instance_valid(interaction_label):
		interaction_label.visible = false
		interaction_label.text = ""
		interaction_label.size.y = 0.0


func _refresh_armor_stand_test_enemy_info() -> void:
	if not is_instance_valid(versus_label) or not is_instance_valid(armor_intro_label):
		return
	_apply_armor_stand_test_hud_suppression()
	var new_text:String = _build_armor_stand_test_enemy_info()
	if armor_intro_label.text != new_text:
		armor_intro_label.text = new_text
	armor_intro_label.visible = bool(Game.Game_Settings.get("Show_Armor_Stand_Intro",true)) and not new_text.is_empty()
	versus_label.text = ""
	versus_label.hide()
	versus_label.size.y = 0.0
	_last_versus_text = "__armor_stand_test_hud__"
	refresh_top_text_layout()


#========================================================
func build_versus_text() -> String:
	var battle_data:Dictionary = return_battle_sides()
	var side_order:Array = battle_data["order"]
	var side_members:Dictionary = battle_data["members"]
	var colored_sides:PackedStringArray = PackedStringArray()
	var active_team_count:int = 0
	for side_key:String in side_order:
		if _versus_is_named_team(side_key):
			active_team_count += 1

	var team_index:int = 0
	for side_key:String in side_order:
		var members:PackedStringArray = PackedStringArray()
		# Count the participants currently represented by return_battle_sides,
		# not the saved lineup. Keep first-appearance order and never merge teams.
		var counts:Dictionary = {}
		var names:PackedStringArray = PackedStringArray()

		for member in side_members[side_key]:
			var name:String = str(member)
			if not counts.has(name):
				counts[name] = 0
				names.append(name)
			counts[name] = int(counts[name]) + 1
		for name:String in names:
			var text:String = escape_bbcode(Game.t(name).replace("_", " "))
			if int(counts[name]) > 1:
				text += " * %d" % int(counts[name])
			members.append(text)

		var side_text:String = " + ".join(members)
		var side_color:Color = _versus_side_color(side_key,active_team_count,team_index)
		if _versus_is_named_team(side_key):
			team_index += 1
		var color_hex:String = side_color.to_html(false)

		colored_sides.append(
			"[color=#" + color_hex + "][b]" + side_text + "[/b][/color]"
		)

	if colored_sides.is_empty():
		return ""

	# VS 固定白色。
	return "[center]" + "  [color=#FFFFFF][b]VS[/b][/color]  ".join(colored_sides) + "[/center]"

func refresh_versus_text() -> void:
	# Early returns for prebattle/dead-save must not leave the previous prose visible.
	if is_instance_valid(armor_intro_label):
		armor_intro_label.hide()
	if versus_label == null:
		return
	if _dead_save_ui_override_active:
		_apply_dead_save_ui_override()
		return
	if _development != null and _development.is_prebattle():
		versus_label.visible = false
		versus_label.text = ""
		_last_versus_text = ""
		if is_instance_valid(rotation_versus_root): rotation_versus_root.visible = false
		if is_instance_valid(timed_training_label): timed_training_label.visible = false
		return

	# 场上只要有任意盔甲架系角色，就把这一局视为测试。
	# 只显示放大的角色名称与机制介绍，不显示 VS、轮换名单或计时器。
	if _refresh_armor_stand_test_mode_state():
		_refresh_armor_stand_test_enemy_info()
		return

	# Rotation shows no XX VS XX at all; the top HUD keeps only its clock.
	if Game.is_rotation_training_mode():
		versus_label.visible = false
		versus_label.text = ""
		versus_label.size.y = 0.0
		_last_versus_text = ""
		if is_instance_valid(rotation_versus_root): rotation_versus_root.visible = false
		_layout_character_dialogue_hud()
		return
	# Boss wheel mode still owns its legacy name-column VS; never show both.
	if _queue_battle_mode_active() and not Game.is_rotation_training_mode():
		versus_label.visible = false
		versus_label.text = ""
		versus_label.size.y = 0.0
		_last_versus_text = ""
		if is_instance_valid(rotation_versus_root):
			rotation_versus_root.visible = true
		_rotation_refresh_all_texts()
		_layout_rotation_versus_hud()
		_layout_character_dialogue_hud()
		return
	elif is_instance_valid(rotation_versus_root):
		rotation_versus_root.visible = false

	var new_text:String = build_versus_text()
	if new_text == _last_versus_text:
		_layout_character_dialogue_hud()
		return

	_last_versus_text = new_text
	versus_label.text = new_text
	versus_label.visible = not new_text.is_empty()
	refresh_top_text_layout()
	_layout_character_dialogue_hud()

#========================================================
# 每次 World 启动时只执行一次：
# 固定一条互动文案 + 固定一种 RichText 效果。
#========================================================
func initialize_interaction_text() -> void:
	# V173：顶部随机互动文案已删除。保留空状态只为兼容旧录像/旧调用。
	_interaction_initialized = true
	_fixed_interaction_source = ""
	_fixed_interaction_bbcode = ""
	_fixed_interaction_effect_index = 0


#========================================================
# RichText 效果随机器
#
# 注意：这个函数只会由 initialize_interaction_text() 在启动时调用一次。
#========================================================
func return_random_interaction_effect(raw_text:String) -> String:
	return build_interaction_effect(raw_text, randi_range(0, 4))


func build_interaction_effect(raw_text:String, effect_index:int) -> String:
	var safe_text:String = escape_bbcode(raw_text)
	var result:String = ""

	# 互动文字统一使用纯白色。
	# 不再使用 rainbow，因为 rainbow 会覆盖原文字颜色，无法保持纯白。
	# 效果幅度也刻意调轻，避免比战斗本身更抢眼。
	match effect_index:
		# Wave：轻微上下浮动
		0:
			result = (
				"[color=#FFFFFF][wave amp=3.0 freq=2.0 connected=1][b]"
				+ safe_text
				+ "[/b][/wave][/color]"
			)

		# Shake：非常轻的抖动
		1:
			result = (
				"[color=#FFFFFF][shake rate=10.0 level=1 connected=1][b]"
				+ safe_text
				+ "[/b][/shake][/color]"
			)

		# Tornado：很小半径的圆周运动
		2:
			result = (
				"[color=#FFFFFF][tornado radius=1.5 freq=1.0 connected=1][b]"
				+ safe_text
				+ "[/b][/tornado][/color]"
			)

		# Pulse：只改变透明度强弱，色相仍保持白色
		3:
			result = (
				"[color=#FFFFFF][pulse freq=0.6 color=#FFFFFFAA ease=-2.0][b]"
				+ safe_text
				+ "[/b][/pulse][/color]"
			)

		# Wave 2：另一种更柔和的波动参数
		_:
			result = (
				"[color=#FFFFFF][wave amp=2.0 freq=4.0 connected=1][b]"
				+ safe_text
				+ "[/b][/wave][/color]"
			)

	return "[center]" + result + "[/center]"

func _on_language_changed(_locale:String) -> void:
	_refresh_center_watermark()
	_last_versus_text = ""
	refresh_versus_text()
	_rotation_refresh_all_texts()
	_refresh_timed_training_hud()
	_refresh_character_dialogue_texts()

	if not _fixed_interaction_source.is_empty():
		_fixed_interaction_bbcode = build_interaction_effect(
			Game.t(_fixed_interaction_source),
			_fixed_interaction_effect_index
		)
	refresh_interaction_text()
	refresh_top_text_layout()


#========================================================
# 第二行只显示启动时已经固定的互动文字。
# 不会在 _process、地图切换、角色死亡、换队或 reset 时重新随机。
#========================================================
func refresh_interaction_text() -> void:
	# V173：删除“谁会赢 / 会不会爆冷”等顶部随机互动文字。
	if interaction_label == null:
		return
	interaction_label.text = ""
	interaction_label.visible = false
	refresh_top_text_layout()


#========================================================
# 人物放置测试区域
#
# “真正地图区域”和“允许放人物的区域”必须分开：
# - return_now_map_border()/Game.mouse_in_map 仍然只代表黑线内部；
# - 放置人物时额外允许地图外一圈测试带，用来直接测试自动回地图动画。
# 测试带宽度复用 map_squeeze_rescue_distance，保证从这里放下的人物
# 都属于自动救援距离，而不是进入远距离越界淘汰。
#========================================================
func return_character_placement_test_bounds() -> Rect2:
	var map_node:Node = _current_map_node()
	if map_node == null:
		return Rect2()
	return return_map_world_rect(map_node).grow(maxf(map_squeeze_rescue_distance,0.0))


func can_place_character_at(position:Vector2) -> bool:
	return map_contains_point(position,map_island_rects(_current_map_node()))

func return_now_map_border() -> Dictionary:
	var map_node:Node = _current_map_node()
	if map_node is PortalMap:
		var rect_all:Rect2 = return_map_world_rect(map_node)
		return {
			start = rect_all.position + Vector2(1,1),
			end = rect_all.end - Vector2(1,1)
		}
	var rect = map_group[now_choose_map].get_used_rect()
	var tile_size = map_group[now_choose_map].tile_set.tile_size
	
	return {
		start = map_group[now_choose_map].position + Vector2(rect.position) * Vector2(tile_size) + Vector2(1,1),
		end = map_group[now_choose_map].position + Vector2(rect.end) * Vector2(tile_size) - Vector2(1,1)
	}
#角色
var status_image_tem := preload("res://scenes/status_image.tscn")

var status_textures:Dictionary = {
}
var infection_texture = "infection"

func add_to_status(path:String) -> void:
	var texture:CompressedTexture2D= load(path)
	status_textures[texture.load_path.get_file().split(".")[0]] = texture

@rpc("authority","call_local")
func set_status_image(texture,poi:Vector2) -> void:
	var status_image = status_image_tem.instantiate()
	
	status_image.texture = status_textures[texture]
	status_image.global_position = poi
	
	status_image.self_modulate = Color(1.0, 1.0, 1.0, 1.0)
	
	status_image.name = Game.return_random_name(status_image)
	add_child(status_image)
	
	var Status_image_tween:Tween = create_tween()
	Status_image_tween.set_parallel(true)
	Status_image_tween.tween_property(status_image,"self_modulate",Color(1.0, 1.0, 1.0, 0.0),0.2)
	Status_image_tween.tween_property(status_image,"global_position",poi + Vector2(0,-10),0.2)

	await Status_image_tween.finished
	status_image.queue_free()

func Delete_char() -> void:
	for b:ball in get_tree().get_nodes_in_group("Ball"):
		if b.mouse_in_char:
			Game.free_node(b)
func set_char_random_color() -> void:
	_team_auto_colors_applied = true
	# 旧设置名保留兼容，但行为改为“按阵营着色”。
	# 顶部 VS / 队伍文字与角色都调用 return_side_color()，所以两处颜色严格一致，
	# 不再给相同角色随机生成一套与 UI 无关的颜色。
	# V410：复用事件维护的战斗单位缓存，避免 20Hz 重新构造 Ball 组数组。
	for node:Node in _battle_units_cache:
		if node == null or not is_instance_valid(node) or not node is ball:
			continue
		var b:ball = node as ball
		if b.Type != ball.Ball_Type.Ball:
			continue

		# 第一次由设置接管颜色时保存角色原本的着色，关闭设置后可以完整恢复。
		if not b.has_meta(&"team_auto_color_active"):
			b.set_meta(&"team_auto_color_original_color", b.image_color)
			b.set_meta(&"team_auto_color_original_mix", b.image_color_mix)
			b.set_meta(&"team_auto_color_active", true)

		var side_key:String = return_ball_side_key(b)
		var team_color:Color = return_side_color(side_key)
		# 队伍颜色是“覆盖色层”而不是把人物直接刷成纯色。基础人物 Shader 的
		# defualt_color_mix 会在原纹理 RGB 与队伍色之间混合；0.50 就是 50% 强度的叠色，
		# 原人物明暗、线稿和材质细节都会保留。Color.a 不参与这个 RGB 混合，所以保持 1。
		team_color.a = 1.0
		if b.image_color != team_color or not is_equal_approx(b.image_color_mix,0.5):
			b.image_color = team_color
			b.image_color_mix = 0.5
			b.set_image_color()


func _restore_team_auto_character_colors() -> void:
	# V411：设置本来就没启用、也从未给角色自动着色时，不再 20Hz 空扫全场。
	if not _team_auto_colors_applied:
		return
	# V410：与着色路径一致，直接复用战斗单位缓存。
	for node:Node in _battle_units_cache:
		if node == null or not is_instance_valid(node) or not node is ball:
			continue
		var b:ball = node as ball
		if not b.has_meta(&"team_auto_color_active"):
			continue
		var old_color:Variant = b.get_meta(&"team_auto_color_original_color", Color.WHITE)
		var old_mix:Variant = b.get_meta(&"team_auto_color_original_mix", 0.0)
		b.image_color = old_color if old_color is Color else Color.WHITE
		b.image_color_mix = float(old_mix)
		b.set_image_color()
		b.remove_meta(&"team_auto_color_active")
		b.remove_meta(&"team_auto_color_original_color")
		b.remove_meta(&"team_auto_color_original_mix")
	_team_auto_colors_applied = false
func return_random_dir() -> Vector2:
	var randomangle = randf_range(0,2 * PI)
	var dir = Vector2(cos(randomangle),sin(randomangle))
	return dir

func return_random_char() -> String:
	return Characters_Dic.keys()[randi_range(0,Characters_Dic.size()-1)]

#========================================================
# 特殊训练模式公共流程
#========================================================
func _should_freeze_special_training_prestart() -> bool:
	if random_character_draft.blocks_combat(): return true
	if _rotation_clearing_round: return true
	# Boss 开场必须在“任何战斗逻辑运行之前”冻结，即使是 Rematch 这种没有重新打开
	# Team 面板的启动路径也一样，因此 Boss 判断要早于 is_set_team()。
	if Game.is_boss_training_mode():
		return not _boss_started
	if control == null or not is_instance_valid(control) or not control.has_method("is_set_team"):
		return false
	if not bool(control.call("is_set_team")):
		return false
	if Game.is_rotation_training_mode():
		return not _rotation_started
	if Game.is_timed_training_mode():
		return not _timed_running and not _timed_finished
	return false


func _is_special_training_runtime_node(node:Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	# Ball 覆盖人物、兔子伙伴/幼兔等角色型召唤物；Shooter 覆盖独立投射物。
	return node is ball or node.is_in_group("Ball") or node.is_in_group("Shooter")


func _freeze_special_training_node(node:Node) -> void:
	if not _should_freeze_special_training_prestart():
		return
	if not _is_special_training_runtime_node(node):
		return
	var id:int = node.get_instance_id()
	if not node.has_meta("training_prestart_prev_process_mode"):
		node.set_meta("training_prestart_prev_process_mode",int(node.process_mode))
	_special_prestart_frozen_ids[id] = true
	node.process_mode = Node.PROCESS_MODE_DISABLED


func _on_training_scene_node_added(node:Node) -> void:
	# node_added 会在角色脚本开始正常物理行为前触发。
	# 这能抓住兔子在 call_deferred 中补出的第二只兔等“额外角色”。
	if _development != null:
		_development.on_scene_node_added(node)
	_freeze_special_training_node(node)

	# V410：只对 shooter 脚本安排一次延迟注册。BattleTransient 通常在投射物 _ready()
	# 内加入，因此这里延后一拍检查；普通 UI/特效节点不会产生额外 deferred 调用。
	if node == null or node is ball or not node is Node2D:
		return
	var script_value:Variant = node.get_script()
	if script_value is Script and (script_value as Script).resource_path.begins_with("res://scripts/shooter/"):
		call_deferred("_try_register_non_ball_projectile_id",node.get_instance_id())


func _freeze_existing_special_prestart_nodes() -> void:
	if not _should_freeze_special_training_prestart():
		return
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		_freeze_special_training_node(node)
	for node:Node in get_tree().get_nodes_in_group("Shooter"):
		_freeze_special_training_node(node)


func _restore_special_prestart_nodes() -> void:
	for raw_id:Variant in _special_prestart_frozen_ids.keys():
		var id:int = int(raw_id)
		if not is_instance_id_valid(id):
			continue
		var obj:Object = instance_from_id(id)
		if not obj is Node:
			continue
		var node:Node = obj as Node
		if node.has_meta("training_prestart_prev_process_mode"):
			node.process_mode = int(node.get_meta("training_prestart_prev_process_mode")) as Node.ProcessMode
			node.remove_meta("training_prestart_prev_process_mode")
	_special_prestart_frozen_ids.clear()


func _on_training_game_setting_changed(setting:String,_value:Variant) -> void:
	if setting == "Character_Placement_Mode" or setting == "Training_Mode_Type":
		random_character_draft.cancel()
		Game._placement._cancel_placement_press()
	if setting in ["Random_Character_Categories","Random_Character_Excluded"]:
		Game._placement._cancel_placement_press()
	if FEEDBACK_TUNING.SPECS.has(setting) or setting == "Feedback_Reset":
		_sync_feedback_settings()
		if setting.begins_with("Feedback_Focus_") or setting.begins_with("Feedback_Hitstop_") or (setting=="Feedback_Reset" and str(_value)=="High_Damage_Feedback"):
			_clear_high_damage_feedback()
		else:
			_damage_shake_pending_peak = 0.0
			_damage_shake_pending_sum = 0.0
			_damage_shake_pixels = 0.0
			_damage_shake_time_left = 0.0
		return
	if setting == "High_Damage_Feedback":
		if not bool(_value): _clear_high_damage_feedback()
		return
	if setting == "Development_Mode" and _development != null:
		if bool(_value):
			# 战斗中途不突然拆成两张地图；从新一局布阵开始生效。
			if _battle_setup.is_empty() and _rotation_rosters["left"].is_empty() and _rotation_rosters["right"].is_empty():
				_development.prepare()
		else:
			_development.cleanup()
		return
	if setting == "Development_Speed" and _development != null and _development.is_running():
		Game.set_development_time_multiplier(float(_value))
		return
	if setting == "Minecraft_Clouds":
		if is_instance_valid(minecraft_clouds): minecraft_clouds.refresh()
		return
	if setting == "Day_Night_Cycle":
		if is_instance_valid(day_night_cycle): day_night_cycle.refresh_enabled()
		return
	if setting == "Map_Background":
		refresh_map_presentation()
		return
	if setting == "Show_Center_Watermark":
		_refresh_center_watermark()
		return
	if setting == "Show_Armor_Stand_Intro":
		refresh_versus_text() # Presentation only: keep armor-test suppression and combat state unchanged.
		return
	if setting == "Enable_Dialogue":
		if not _is_character_dialogue_enabled():
			_clear_character_dialogues()
		if is_instance_valid(character_dialogue_root):
			character_dialogue_root.visible = _is_character_dialogue_enabled()
		_layout_character_dialogue_hud()
		_layout_timed_training_hud()
		return
	if setting == "Training_Mode_Type":
		if _development != null and _development.is_prebattle():
			_development.cleanup(false)
		_reset_victory_bell_state()
		# 切换玩法只重置轮放/计时/Boss自己的运行状态，不再打开训练模式，也不强制清空普通布阵。
		_reset_special_training_state()
		if _development != null and _battle_setup.is_empty():
			_development.prepare()
		refresh_versus_text()
		_refresh_center_watermark_layout()
	elif setting == "Training_Mode":
		_reset_victory_bell_state()
		if not Game.is_training_mode():
			_reset_special_training_state()
		refresh_versus_text()
		refresh_top_text_layout()
	elif setting == "Training_Timed_Duration":
		if Game.is_timed_training_mode() and not _timed_running:
			_timed_time_left = Game.get_training_timed_duration()
			_refresh_timed_training_hud()
	elif setting in ["Training_Wheel_Battle","Rotation_Match_Type","Rotation_Multi_Characters"]:
		if setting=="Rotation_Multi_Characters":
			rotation_selected_round=1 if Game.rotation_multi_enabled() else 0
			if not Game.rotation_multi_enabled():
				for side:String in ["left","right"]:
					for i:int in range(_rotation_rosters[side].size()): _rotation_rosters[side][i]["round"]=i+1
		if Game.is_rotation_training_mode() and is_multiplayer_authority():
			_sync_rotation_preview_positions()
			_restart_rotation_series(_rotation_rosters.duplicate(true))
		_rotation_refresh_all_texts()
	elif setting in ["Training_Boss_Side","Training_Boss_Wheel_Battle","Training_Boss_Multiplier","Training_Boss_Specialization","Training_Boss_Intro"]:
		# Boss 队伍/倍率/特殊化是布阵属性；开场动画开关影响下一次正式开战。
		refresh_versus_text()


func _reset_special_training_state() -> void:
	_rotation_draft_rounds=[1]
	_clear_rotation_formation_preview(false)
	rotation_selected_round=1 if Game.rotation_multi_enabled() else 0
	_rotation_preview_round=1
	_rotation_active_records={"left":[],"right":[]}
	_battle_lifecycle_generation += 1
	_battle_spawn_tickets.clear()
	_rotation_epoch += 1 # Cancel delayed deaths from reset / mode switches / rematches.
	_cancel_rotation_presentation()
	if not _rotation_rosters["left"].is_empty() or not _rotation_rosters["right"].is_empty():
		_rotation_saved_rosters = _rotation_rosters.duplicate(true)
		_rotation_saved_map = now_choose_map
	_rotation_results.clear()
	_rotation_finished = false
	_rotation_clearing_round = false
	if is_instance_valid(_rotation_frame_hud): _rotation_frame_hud.reset_scroll()
	if is_instance_valid(_boss_intro_overlay):
		_boss_intro_overlay.queue_free()
	_boss_intro_overlay = null
	_boss_intro_playing = false
	_boss_started = false
	_restore_special_prestart_nodes()
	_rotation_rosters = {"left": [], "right": []}
	_rotation_next_index = {"left": 0, "right": 0}
	_rotation_active_setup = {"left": -1, "right": -1}
	_rotation_active_name = {"left": "", "right": ""}
	_rotation_started = false
	_rotation_transitioning = false
	_rotation_pending_dead_sides.clear()
	_rotation_setup_scroll_rows = {"left": 0, "right": 0}
	_clear_rotation_hud_labels()
	_rotation_preview_character = {"left": null, "right": null}

	_timed_pending_entries.clear()
	_timed_running = false
	_timed_finished = false
	_timed_overtime = false
	_timed_winner_setup = -1
	_timed_defeated_setups.clear()
	_timed_start_armed = false
	_timed_time_left = Game.get_training_timed_duration()
	_timed_damage_by_setup.clear()
	_timed_name_by_setup.clear()
	_timed_team_by_setup.clear()
	for raw_label:Variant in _timed_damage_labels.values():
		if raw_label is Label and is_instance_valid(raw_label):
			(raw_label as Label).queue_free()
	_timed_damage_labels.clear()
	_timed_damage_label_character_ids.clear()
	if is_instance_valid(timed_training_label):
		timed_training_label.visible = false
	_refresh_timed_training_hud()
	if is_instance_valid(rotation_versus_root):
		rotation_versus_root.visible = _queue_battle_mode_active()


func _update_special_training_modes(delta:float) -> void:
	if random_character_draft.blocks_combat(): return
	if _development != null and _development.is_prebattle():
		return
	if _queue_battle_mode_active() and (not is_multiplayer_authority() or _rotation_transitioning or _rotation_finished): return
	# 轮放 / 计时 / Boss 都是独立玩法，不能被“训练模式”总开关关掉。
	if Game.is_boss_training_mode():
		var boss_wheel:bool = Game.is_training_boss_wheel_battle_enabled()
		if is_instance_valid(rotation_versus_root):
			rotation_versus_root.visible = boss_wheel
		if is_instance_valid(timed_training_label): timed_training_label.visible = false

		# Boss 车轮战与轮放共享名单/当前/历史 HUD；布阵时每边只保留第一位冻结预览。
		if boss_wheel:
			if not _boss_started and control.is_set_team():
				_freeze_existing_special_prestart_nodes()
			if not _boss_started and not control.is_set_team():
				var left_roster:Array = _rotation_rosters["left"]
				var right_roster:Array = _rotation_rosters["right"]
				if not left_roster.is_empty() and not right_roster.is_empty():
					_rotation_started = true
					_boss_started = true
					_restore_special_prestart_nodes()
					_spawn_next_rotation_character("left")
					_spawn_next_rotation_character("right")
					if boss_intro_enabled and Game.is_training_boss_intro_enabled():
						_begin_boss_intro()
			return

		# 普通 Boss 模式仍然是所有已放置人物同时开战。
		if not _boss_started:
			_freeze_existing_special_prestart_nodes()
		if not _boss_started and not control.is_set_team() and _count_primary_battle_characters() >= 2:
			_boss_started = true
			if boss_intro_enabled and Game.is_training_boss_intro_enabled():
				_begin_boss_intro()
			else:
				_restore_special_prestart_nodes()
		return

	if Game.is_rotation_training_mode():
		if is_instance_valid(rotation_versus_root): rotation_versus_root.visible = true
		if not _rotation_started and control.is_set_team():
			# 布阵时每帧补一次兜底扫描，确保 _ready 后才加入组的特殊对象也不会漏掉。
			_freeze_existing_special_prestart_nodes()
		# Team 面板就是布阵状态。关掉面板以后才真正开始，允许先无限添加双方名单。
		if not _rotation_started and not control.is_set_team():
			var left_roster:Array = _rotation_rosters["left"]
			var right_roster:Array = _rotation_rosters["right"]
			if not _rotation_draft_is_complete(): return
			if not left_roster.is_empty() and not right_roster.is_empty():
				_clear_rotation_formation_preview(true)
				_rotation_started = true
				_restore_special_prestart_nodes()
				_spawn_next_rotation_character("left")
				_spawn_next_rotation_character("right")
		return

	if is_instance_valid(rotation_versus_root): rotation_versus_root.visible = false

	if Game.is_timed_training_mode():
		if is_instance_valid(timed_training_label): timed_training_label.visible = false
		if not is_multiplayer_authority():
			_enforce_timed_character_hud()
			return
		if not _timed_running and not _timed_finished and control.is_set_team():
			_freeze_existing_special_prestart_nodes()
		# 计时模式人物在布阵时已经实际生成，只是被冻结。关掉工具栏才一起启用并开始计时。
		if not control.is_set_team() and not _timed_pending_entries.is_empty():
			_spawn_pending_timed_characters()
		if _timed_running and not _timed_finished and is_combat_runtime_active():
			_timed_time_left = maxf(_timed_time_left - maxf(delta,0.0),0.0)
			_refresh_timed_training_hud()
			if _timed_time_left <= 0.0:
				_finish_timed_training()
		elif _timed_start_armed and not _timed_running and not _timed_finished and _count_primary_battle_characters() >= 2 and not control.is_set_team():
			_activate_timed_prestart_characters()
			_timed_running = true
			_timed_start_armed = false
			_timed_time_left = Game.get_training_timed_duration()
			_refresh_timed_training_hud()
		_enforce_timed_character_hud()
		_sync_timed_match(delta)
	else:
		if is_instance_valid(timed_training_label): timed_training_label.visible = false


# Existence query for the per-unit combat gate; deliberately not cached.
# Preserve the count predicate, including queued deletion, summons and continuation units.
# Full-count callers keep using _count_primary_battle_characters().
func _has_alive_primary_battle_character() -> bool:
	for node:Node in _battle_units_cache:
		if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if node is ball and _is_primary_battle_character(node as ball) and (node as ball).health > 0:
			return true
	return false


func _count_primary_battle_characters() -> int:
	var count:int = 0
	for node:Node in _battle_units_cache:
		# Reset 使用 queue_free()；节点会一直留到当前帧末尾。
		# 如果这里仍把“已排队删除”的旧角色算进去，Boss 模式会把 Reset
		# 误判成新一局布阵完成，从而在清场瞬间重复播放一次开场。
		if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if node is ball and _is_primary_battle_character(node as ball) and (node as ball).health > 0:
			count += 1
	return count


#========================================================
# 轮放模式
#========================================================
func _enqueue_rotation_character(_requested_team:String,char_name:String,poi:Vector2,forced_side:String = "",scene_path:String = "",round_choice:int=-1) -> void:
	if _get_character_scene_path(char_name,scene_path) == null:
		push_warning("轮放模式无法加入角色: " + char_name)
		return
	var side:String = forced_side if forced_side in ["left","right"] else _boss_side_for_position(poi)
	var setup_id:int = _battle_setup_next_id
	_battle_setup_next_id += 1
	var roster:Array = _rotation_rosters[side]
	var round_number:int=roster.size()+1
	if Game.is_rotation_training_mode():
		var selected:int=rotation_selected_round if round_choice<0 else round_choice
		if selected>0: round_number=selected
		elif Game.rotation_multi_enabled(): round_number=maxi(rotation_selected_round,1)
		else:
			for old:Dictionary in roster: round_number=maxi(round_number,int(old.get("round",1))+1)
		if _rotation_started:
			# Do not silently insert new contenders into an already consumed group.
			for old:Dictionary in roster.slice(0,int(_rotation_next_index[side])): round_number=maxi(round_number,int(old.get("round",1))+1)
		if not Game.rotation_multi_enabled():
			for old:Dictionary in roster.duplicate():
				if int(old.get("round",-1))==round_number: delete_rotation_queue_setup_id(int(old.id),side)
		_rotation_preview_round=round_number
	roster.append({"id":setup_id,"char":char_name,"scene_path":scene_path if not scene_path.is_empty() else character_scene_path(char_name),"round":round_number,"x":poi.x,"y":poi.y})
	roster.sort_custom(func(a:Dictionary,c:Dictionary): return int(a.get("round",0))<int(c.get("round",0)))
	if Game.is_rotation_training_mode() and not Game.rotation_multi_enabled(): rotation_selected_round=0
	if is_instance_valid(control): control.call_deferred("_sync_rotation_formation_ui")
	_rotation_rosters[side] = roster
	if _development != null and _development.is_prebattle():
		_development._sync_lanes(true)

	if not _rotation_started:
		# 布阵阶段：名单立刻在 VS 两侧显示；每边第一位角色也立即显示在固定出生点，
		# 但被冻结，直到关闭工具栏正式开战。新加入人物时默认跟随名单最底部；
		# 用户滚轮向上后才查看更早的人物。
		_rotation_setup_scroll_rows[side] = 0
		_rotation_add_setup_preview_label(side,char_name,setup_id)
		_spawn_rotation_preview_character_if_needed(side)
	else:
		_rotation_refresh_future_labels(side)
	_rotation_refresh_all_texts()
	if is_instance_valid(rotation_versus_root):
		rotation_versus_root.visible = true
		_layout_rotation_versus_hud()
	if _development != null and _development.is_prebattle():
		_development.on_rotation_enqueued(side)
		refresh_versus_text()

	# 如果比赛已经开始但这一边刚好没人（名单先耗尽、后来又补了人），关掉选人面板后会补上。
	if _rotation_started and int(_rotation_active_setup[side]) < 0 and not control.is_set_team():
		_spawn_next_rotation_character(side)


func _spawn_rotation_preview_character_if_needed(side:String) -> void:
	if Game.is_rotation_training_mode() and not (_development!=null and _development.is_prebattle()):
		_refresh_rotation_formation_preview()
		return
	var existing:Variant = _rotation_preview_character.get(side,null)
	if existing is ball and is_instance_valid(existing):
		return
	var roster:Array = _rotation_rosters[side]
	if roster.is_empty():
		return
	var record:Dictionary = roster[0]
	var entry:Dictionary = _queue_entry_for_record(record, side, _rotation_spawn_position(side))
	var preview:ball = _spawn_character_from_setup(entry)
	if preview == null:
		return
	preview.set_meta("rotation_side",side)
	preview.set_meta("rotation_prestart_preview",true)
	preview.process_mode = Node.PROCESS_MODE_DISABLED
	_rotation_preview_character[side] = preview



func _rotation_record_position(record:Dictionary,side:String) -> Vector2:
	return Vector2(float(record.get("x",_rotation_spawn_position(side).x)),float(record.get("y",_rotation_spawn_position(side).y)))

func rotation_round_numbers() -> Array[int]:
	var numbers:Array[int]=_rotation_draft_rounds.duplicate()
	for side:String in ["left","right"]:
		for i:int in range(_rotation_rosters[side].size()):
			var number:int=int(_rotation_rosters[side][i].get("round",i+1))
			if not numbers.has(number): numbers.append(number)
	if rotation_selected_round>0 and not numbers.has(rotation_selected_round): numbers.append(rotation_selected_round)
	numbers.sort()
	return numbers

func select_rotation_round(number:int) -> void:
	if not Game.is_rotation_training_mode(): return
	var chosen:int=clampi(number,1,999)
	if number>0 and not _rotation_draft_rounds.has(chosen): _rotation_draft_rounds.append(chosen)
	if not is_multiplayer_authority():
		rotation_selected_round=clampi(number,1 if Game.rotation_multi_enabled() else 0,999)
		_request_rotation_round.rpc_id(1,rotation_selected_round)
		if is_instance_valid(control): control.call_deferred("_sync_rotation_formation_ui")
		return
	_sync_rotation_preview_positions()
	rotation_selected_round=clampi(number,1 if Game.rotation_multi_enabled() else 0,999)
	_rotation_preview_round=maxi(rotation_selected_round,1)
	_refresh_rotation_formation_preview()
	if is_instance_valid(control): control.call_deferred("_sync_rotation_formation_ui")

func rotation_quick_layout() -> Node2D:
	if not is_instance_valid(_rotation_quick_layout):
		_rotation_quick_layout = ROTATION_QUICK_LAYOUT_SCRIPT.new()
		add_child(_rotation_quick_layout)
	return _rotation_quick_layout

func rotation_quick_layout_active() -> bool:
	return is_instance_valid(_rotation_quick_layout) and _rotation_quick_layout.active

## Left click while quick layout is open places/moves that team's single position marker.
func rotation_quick_layout_click(poi:Vector2) -> bool:
	if not rotation_quick_layout_active(): return false
	if can_place_character_at(poi):
		var side:String = _special_two_team_side(str(now_choose_team),poi)
		if not side.is_empty():
			_rotation_quick_layout.place_marker(side,poi)
			if is_instance_valid(control): control.call_deferred("_sync_quick_layout_ui")
	return true

func rotation_quick_layout_commit() -> void:
	if not rotation_quick_layout_active(): return
	var entries:Array = _rotation_quick_layout.entries()
	_rotation_quick_layout.cancel()
	if entries.is_empty(): return
	if is_multiplayer_authority(): _apply_rotation_quick_layout(entries)
	else: _request_rotation_quick_layout.rpc_id(1,entries)

@rpc("any_peer","call_remote","reliable")
func _request_rotation_quick_layout(entries:Array) -> void:
	if is_multiplayer_authority() and multiplayer.get_remote_sender_id()>0: _apply_rotation_quick_layout(entries)

## Each team's k-th checked character goes into the same new round, after every existing one.
func _apply_rotation_quick_layout(entries:Array) -> void:
	if not Game.is_rotation_training_mode() or _rotation_started: return
	var last_round:int = 0
	for side:String in ["left","right"]:
		for i:int in range(_rotation_rosters[side].size()):
			last_round = maxi(last_round,int(_rotation_rosters[side][i].get("round",i+1)))
	for raw:Variant in entries:
		if not raw is Dictionary: continue
		var side:String = str(raw.get("side",""))
		var char_name:String = str(raw.get("char",""))
		if side not in ["left","right"] or not _has_character_scene_any(char_name): continue
		var round_number:int = last_round+1+clampi(int(raw.get("index",0)),0,998)
		if round_number > 999: continue
		create_char("__rotation_"+side,char_name,Vector2(float(raw.get("x",0.0)),float(raw.get("y",0.0))),round_number)

@rpc("any_peer","call_remote","reliable")
func _request_rotation_round(number:int) -> void:
	# Round choice is a placement/view action, like the existing unrestricted team choice.
	if is_multiplayer_authority() and not _rotation_started and multiplayer.get_remote_sender_id()>0:
		select_rotation_round(number)

func _sync_rotation_preview_positions() -> void:
	if _rotation_started: return
	for side:String in ["left","right"]:
		for record:Dictionary in _rotation_rosters[side]:
			var actor:Variant=_rotation_formation_preview.get(int(record.id))
			if is_instance_valid(actor) and not actor.is_queued_for_deletion():
				record.x=actor.global_position.x;record.y=actor.global_position.y

func _clear_rotation_formation_preview(save_positions:bool) -> void:
	if save_positions: _sync_rotation_preview_positions()
	var had_preview:bool = not _rotation_formation_preview.is_empty()
	for actor:Variant in _rotation_formation_preview.values():
		if is_instance_valid(actor): Game.free_node(actor)
	_rotation_formation_preview.clear()
	if had_preview and not _rotation_started: _free_rotation_preview_residue()

# Previews are PROCESS_MODE_DISABLED, but deferred calls from _ready still run, so bats,
# dogs, followers... spawned by a preview outlived it and overlapped the real spawns.
func _free_rotation_preview_residue() -> void:
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball or node.is_queued_for_deletion(): continue
		if node.has_meta("rotation_side") or node.has_meta("rotation_prestart_preview") or node.has_meta("development_reserve"): continue
		Game.free_node(node)

func _refresh_rotation_formation_preview() -> void:
	if not is_multiplayer_authority(): return
	if _rotation_started or not Game.is_rotation_training_mode(): return
	if _development!=null and _development.is_prebattle(): return
	_sync_rotation_preview_positions()
	var wanted:Dictionary={}
	for side:String in ["left","right"]:
		for i:int in range(_rotation_rosters[side].size()):
			var record:Dictionary=_rotation_rosters[side][i]
			if int(record.get("round",i+1))!=_rotation_preview_round: continue
			var id:int=int(record.id);wanted[id]=true
			var actor:Variant=_rotation_formation_preview.get(id)
			if is_instance_valid(actor) and not actor.is_queued_for_deletion(): continue
			actor=_spawn_character_from_setup(_queue_entry_for_record(record,side,_rotation_record_position(record,side)))
			if not is_instance_valid(actor): continue
			actor.set_meta("rotation_side",side);actor.set_meta("rotation_prestart_preview",true)
			actor.process_mode=Node.PROCESS_MODE_DISABLED
			_rotation_formation_preview[id]=actor
	for id:Variant in _rotation_formation_preview.keys():
		if not wanted.has(id):
			var actor:Variant=_rotation_formation_preview[id]
			if is_instance_valid(actor): Game.free_node(actor)
			_rotation_formation_preview.erase(id)

func _rotation_side_alive(side:String) -> bool:
	if Game.is_rotation_training_mode() and not _rotation_active_records[side].is_empty():
		for id:int in _rotation_active_records[side]:
			if _battle_family_alive(id): return true
		return false
	return _battle_family_alive(int(_rotation_active_setup.get(side,-1)))

func _rotation_wall_entry(position_hint:Vector2) -> Dictionary:
	var rect:Rect2=return_map_world_rect(map_group[now_choose_map])
	var point:Vector2=position_hint.clamp(rect.position,rect.end)
	var distances:Array[float]=[point.x-rect.position.x,rect.end.x-point.x,point.y-rect.position.y,rect.end.y-point.y]
	var wall:int=0
	for i:int in range(1,4):
		if distances[i]<distances[wall]: wall=i
	var inset:float=minf(64.0,minf(rect.size.x,rect.size.y)*0.2)
	point=point.clamp(rect.position+Vector2.ONE*inset,rect.end-Vector2.ONE*inset)
	var start:Vector2=point;var finish:Vector2=point
	match wall:
		0: start.x=rect.position.x-64.0;finish.x=rect.position.x+inset
		1: start.x=rect.end.x+64.0;finish.x=rect.end.x-inset
		2: start.y=rect.position.y-64.0;finish.y=rect.position.y+inset
		3: start.y=rect.end.y+64.0;finish.y=rect.end.y-inset
	return {"start":start,"end":finish,"wall":wall}

func _spawn_next_rotation_character(side:String) -> ball:
	if not Game.is_rotation_training_mode(): return _spawn_next_rotation_member(side)
	_rotation_active_records[side]=[]
	var roster:Array=_rotation_rosters[side]
	var start_index:int=int(_rotation_next_index[side])
	if start_index>=roster.size():
		_rotation_active_setup[side]=-1;_rotation_active_name[side]=""
		return null
	var round_number:int=int(roster[start_index].get("round",start_index+1))
	var first:ball=null
	var names:PackedStringArray=[]
	var planned_spots:Array=[]
	for planned_index:int in range(start_index,roster.size()):
		if int(roster[planned_index].get("round",planned_index+1))!=round_number: break
		planned_spots.append(_rotation_record_position(roster[planned_index],side))
	while int(_rotation_next_index[side])<roster.size():
		var index:int=int(_rotation_next_index[side]);var record:Dictionary=roster[index]
		if int(record.get("round",index+1))!=round_number: break
		var actor:ball=_spawn_next_rotation_member(side,start_index)
		if actor==null: continue
		if first==null: first=actor
		_rotation_active_records[side].append(int(record.id));names.append(str(record.char))
		var reinforcement:bool=start_index>0 and not _rotation_fresh_round and Game.is_rotation_wheel_enabled()
		for copy_index:int in range(1,Game.rotation_team_count(side)):
			var position_hint:Vector2=_rotation_record_position(record,side)
			var ingress:Dictionary=_rotation_wall_entry(position_hint) if reinforcement else {}
			var copy:ball=_spawn_character_from_setup(_queue_entry_for_record(record,side,ingress.start if reinforcement else position_hint))
			if copy==null: continue
			bind_battle_lifecycle(copy,null,true)
			copy.set_meta("rotation_side",side);copy.set_meta("queue_character_name",str(record.char))
			copy.set_meta("rotation_copy_index",copy_index)
			copy.tree_exiting.connect(_on_rotation_character_tree_exiting.bind(copy,side,int(record.id)),CONNECT_ONE_SHOT)
			if reinforcement:
				copy.set_meta("rotation_entry_target",ingress.end)
				_animate_queue_reinforcement_into_map(copy,side)
			else:
				_settle_rotation_spawn(copy,false,planned_spots)
	_rotation_active_setup[side]=int(roster[start_index].id)
	_rotation_active_name[side]=" + ".join(names)
	_rotation_create_current_label(side,_rotation_active_name[side],int(roster[start_index].id))
	_rotation_refresh_future_labels(side)
	return first

func _remove_rotation_slot(setup_id:int) -> bool:
	if not is_multiplayer_authority() or _rotation_transitioning: return false
	for side:String in ["left","right"]:
		var roster:Array=_rotation_rosters[side]
		for i:int in range(roster.size()):
			if int(roster[i].id)!=setup_id: continue
			roster.remove_at(i)
			if i<int(_rotation_next_index[side]): _rotation_next_index[side]=maxi(0,int(_rotation_next_index[side])-1)
			_rotation_active_records[side].erase(setup_id)
			if int(_rotation_active_setup[side])==setup_id:
				_rotation_active_setup[side]=int(_rotation_active_records[side][0]) if not _rotation_active_records[side].is_empty() else -1
			_rotation_formation_preview.erase(setup_id);_rotation_results.erase(setup_id)
			for index:int in range(_battle_setup.size()-1,-1,-1):
				if int(_battle_setup[index].get("id",-1))==setup_id: _battle_setup.remove_at(index)
			for ticket:Variant in _battle_spawn_tickets.keys():
				if int(_battle_spawn_tickets[ticket].identity.get("setup",-1))==setup_id: _battle_spawn_tickets.erase(ticket)
			if _development!=null: _development.on_character_removed(setup_id)
			for actor:Variant in _battle_units_cache.duplicate():
				if not is_instance_valid(actor): continue
				var identity:Dictionary=actor.get_meta(BATTLE_LIFECYCLE_META,{})
				if int(identity.get("setup",actor.get_meta("battle_setup_id",-1)))==setup_id: Game.free_node(actor)
			if not _rotation_started:
				_clear_rotation_hud_labels()
				for rebuild_side:String in ["left","right"]:
					for record:Dictionary in _rotation_rosters[rebuild_side]: _rotation_add_setup_preview_label(rebuild_side,str(record.char),int(record.id))
				_refresh_rotation_formation_preview()
			else:
				var names:PackedStringArray=[]
				for record:Dictionary in roster:
					if _rotation_active_records[side].has(int(record.id)): names.append(str(record.char))
				_rotation_active_name[side]=" + ".join(names)
				_rotation_create_current_label(side,_rotation_active_name[side],int(_rotation_active_setup[side]))
				_rotation_refresh_future_labels(side)
				if int(_rotation_active_setup[side])<0: call_deferred("_rotation_fill_empty_side",side,_rotation_epoch)
			_reset_victory_bell_state()
			control.call_deferred("_sync_rotation_formation_ui")
			return true
	return false

func _rotation_fill_empty_side(side:String,epoch:int) -> void:
	if epoch==_rotation_epoch and _rotation_started and not _rotation_transitioning and int(_rotation_active_setup[side])<0:
		_spawn_next_rotation_character(side)

func _rotation_draft_is_complete() -> bool:
	if not Game.rotation_multi_enabled() or Game.get_rotation_match_type()!="duel": return true
	var rounds:Dictionary={}
	for side:String in ["left","right"]:
		for i:int in range(_rotation_rosters[side].size()):
			var number:int=int(_rotation_rosters[side][i].get("round",i+1))
			rounds[number]=int(rounds.get(number,0))|(1 if side=="left" else 2)
	for number:int in rounds:
		if int(rounds[number])!=3:
			control.show();control.team.show()
			var dialog:=AcceptDialog.new();dialog.dialog_text=Game.ui_t("ROTATION_INCOMPLETE_ROUND")%number
			control.add_child(dialog);dialog.confirmed.connect(dialog.queue_free,CONNECT_ONE_SHOT)
			dialog.canceled.connect(dialog.queue_free,CONNECT_ONE_SHOT);dialog.popup_centered()
			return false
	return true

func _rotation_spawn_position(side:String) -> Vector2:
	var border:Dictionary = return_now_map_border()
	var start:Vector2 = border.get("start",Vector2.ZERO)
	var end:Vector2 = border.get("end",Vector2.ZERO)
	var width:float = maxf(end.x - start.x,1.0)
	var x:float = start.x + width * (0.25 if side == "left" else 0.75)
	return Vector2(x,(start.y + end.y) * 0.5)


func _spawn_next_rotation_member(side:String,group_start:int=-1) -> ball:
	var roster:Array = _rotation_rosters[side]
	var index:int = int(_rotation_next_index[side])
	if index < 0 or index >= roster.size():
		_rotation_active_setup[side] = -1
		_rotation_active_name[side] = ""
		_rotation_refresh_future_labels(side)
		return null

	var record:Dictionary = roster[index]
	_rotation_next_index[side] = index + 1
	var setup_id:int = int(record.get("id",-1))
	var char_name:String = str(record.get("char",""))
	var is_reinforcement:bool = (index if group_start<0 else group_start) > 0 and not _rotation_fresh_round and (not Game.is_rotation_training_mode() or Game.is_rotation_wheel_enabled())
	var pos:Vector2 = _rotation_record_position(record,side) if Game.is_rotation_training_mode() else _rotation_spawn_position(side)
	var ingress:Dictionary=_rotation_wall_entry(pos) if is_reinforcement and Game.is_rotation_training_mode() else {}
	if is_reinforcement: pos=ingress.start if not ingress.is_empty() else _queue_outside_spawn_position(side)
	var entry:Dictionary = _queue_entry_for_record(record, side, pos)
	var spawned:ball = null
	var preview:Variant = _rotation_preview_character.get(side,null)
	var used_prestart_preview:bool = false
	if index == 0 and preview is ball and is_instance_valid(preview) and int((preview as ball).get_meta("battle_setup_id",-2)) == setup_id:
		spawned = preview as ball
		spawned.process_mode = Node.PROCESS_MODE_INHERIT
		spawned.remove_meta("rotation_prestart_preview")
		_rotation_preview_character[side] = null
		used_prestart_preview = true
	else:
		if _development != null:
			spawned = _development.take_candidate(setup_id,pos)
		if spawned == null:
			spawned = _spawn_character_from_setup(entry)
	if spawned == null:
		return null
	bind_battle_lifecycle(spawned,null,true)
	spawned.set_meta("rotation_side",side)
	spawned.set_meta("queue_character_name",char_name)
	if not ingress.is_empty(): spawned.set_meta("rotation_entry_target",ingress.end)
	if is_reinforcement and not used_prestart_preview:
		_animate_queue_reinforcement_into_map(spawned,side)
	else:
		_settle_rotation_spawn(spawned,true)
	_rotation_active_setup[side] = setup_id
	_rotation_active_name[side] = char_name
	spawned.tree_exiting.connect(
		_on_rotation_character_tree_exiting.bind(spawned,side,setup_id),
		CONNECT_ONE_SHOT
	)
	if Game.is_rotation_training_mode(): return spawned
	if used_prestart_preview and _rotation_promote_setup_preview_to_battle(side,char_name):
		pass
	else:
		_rotation_create_current_label(side,char_name,setup_id)
		_rotation_refresh_future_labels(side)
	return spawned


func _on_rotation_character_tree_exiting(_character:ball,_side:String,_setup_id:int) -> void:
	# The body exiting is only a notification; descendants own the same slot.
	if is_instance_valid(_character): _character.set_meta("battle_lifecycle_exiting",true)
	_scan_rotation_family_extinctions()

func _rotation_resolve_pending_deaths() -> void:
	if _rotation_transitioning or not _queue_battle_mode_active() or _rotation_pending_dead_sides.is_empty(): return
	_rotation_transitioning=true
	var epoch:int=_rotation_epoch
	await get_tree().create_timer(0.28,false).timeout
	if not is_inside_tree() or epoch!=_rotation_epoch: return
	if not _queue_battle_mode_active():
		_rotation_transitioning=false
		_rotation_pending_dead_sides.clear()
		return
	var dead_sides:Array[String]=[]
	for side:String in _rotation_pending_dead_sides:
		var setup_id:int=int(_rotation_active_setup.get(side,-1))
		# Revalidate the same live family after death prevention / revival / deferred descendants settle.
		if setup_id>=0 and not _rotation_side_alive(side): dead_sides.append(side)
	_rotation_pending_dead_sides.clear()
	if dead_sides.is_empty():
		_rotation_transitioning=false
		return
	for side:String in dead_sides:
		_rotation_active_setup[side]=-1
		_rotation_active_name[side]=""
		_rotation_mark_current_dead(side)
	if Game.is_rotation_training_mode() and not Game.is_rotation_wheel_enabled():
		_rotation_ui_token+=1
		if multiplayer.has_multiplayer_peer(): _rotation_remote_begin.rpc(dead_sides,_rotation_ui_token,_rotation_rosters,_rotation_next_index)
		await _present_rotation_match(dead_sides,epoch,true)
	else:
		await _advance_rotation_match(dead_sides,epoch)
	if not is_inside_tree() or epoch!=_rotation_epoch: return
	_rotation_transitioning=false
	_rotation_combat_released=false
	if not _rotation_pending_dead_sides.is_empty(): call_deferred("_rotation_resolve_pending_deaths")

func _advance_rotation_match(dead_sides:Array[String],epoch:int) -> void:
	if Game.is_rotation_training_mode() and Game.get_rotation_match_type()=="challenge":
		await _resolve_rotation_challenge(dead_sides,epoch)
	elif (Game.is_boss_training_mode() and Game.is_training_boss_wheel_battle_enabled()) or (Game.is_rotation_training_mode() and Game.is_rotation_wheel_enabled()):
		for dead_side:String in dead_sides: _spawn_next_rotation_character(dead_side)
	else:
		_retire_rotation_families()
		_spawn_next_rotation_character("left")
		_spawn_next_rotation_character("right")

func _rotation_presentation_valid(epoch:int) -> bool:
	return is_inside_tree() and epoch==_rotation_epoch and Game.is_rotation_training_mode()
func _rotation_ui_wait(seconds:float,epoch:int) -> void:
	var until:int=Time.get_ticks_usec()+int(seconds*1000000.0)
	while _rotation_presentation_valid(epoch) and Time.get_ticks_usec()<until: await get_tree().process_frame
func _cancel_rotation_presentation() -> void:
	_rotation_combat_blocked=false
	_rotation_combat_released=false
	_rotation_load_ready=false
	_rotation_ui_token+=1
	if is_instance_valid(_rotation_door): _rotation_door.cancel()
	_rotation_door=null
	if is_instance_valid(_rotation_toast_mirror): _rotation_toast_mirror.queue_free()
	_rotation_toast_mirror=null
	if is_instance_valid(duel_top_hud): duel_top_hud.end_round_result()
func _set_rotation_load_progress(value:float) -> void:
	_rotation_ui_progress=clampf(value,0.0,1.0)
	if is_instance_valid(_rotation_door): _rotation_door.set_loading_progress(_rotation_ui_progress)
	if is_multiplayer_authority() and multiplayer.has_multiplayer_peer(): _rotation_remote_progress.rpc(_rotation_ui_token,_rotation_ui_progress,false)

@rpc("authority","call_remote","reliable")
func _rotation_remote_begin(dead_sides:Array[String],token:int,rosters:Dictionary,next_index:Dictionary) -> void:
	if not Game.is_rotation_training_mode() or token<=_rotation_ui_token: return
	_rotation_ui_token=token
	_rotation_rosters=rosters.duplicate(true)
	_rotation_next_index=next_index.duplicate()
	_rotation_started=true
	_rotation_transitioning=true
	var epoch:int=_rotation_epoch
	await _present_rotation_match(dead_sides,epoch,false)
	if not _rotation_presentation_valid(epoch): return
	_rotation_transitioning=false
	_rotation_combat_released=false
@rpc("authority","call_remote","reliable")
func _rotation_remote_progress(token:int,value:float,ready:bool) -> void:
	if token!=_rotation_ui_token: return
	_rotation_ui_progress=maxf(_rotation_ui_progress,clampf(value,0.0,1.0))
	_rotation_load_ready=_rotation_load_ready or ready
	if is_instance_valid(_rotation_door) and _rotation_door.phase==_rotation_door.Phase.COVERED:
		_rotation_door.set_loading_progress(_rotation_ui_progress)

func _rotation_side_exhausted(side:String) -> bool:
	return int(_rotation_next_index.get(side,0)) >= (_rotation_rosters.get(side,[]) as Array).size()

## 对决/挑战：这一场打完后整个轮换是否已经结束（结束就不再关门换人）。
func _rotation_round_is_final(dead_sides:Array[String]) -> bool:
	if dead_sides.is_empty(): return false
	if Game.get_rotation_match_type()=="challenge":
		var attempt_over:bool=dead_sides.has("left") or (dead_sides.has("right") and _rotation_side_exhausted("right"))
		return attempt_over and _rotation_side_exhausted("left")
	return _rotation_side_exhausted("left") or _rotation_side_exhausted("right")

## 整个轮换打完：不关门、不清场、不换人，胜者留在场上继续，直接结算并放烟花。
func _present_rotation_final(dead_sides:Array[String],authority:bool) -> void:
	_rotation_combat_blocked=false
	_rotation_load_ready=false
	_rotation_combat_released=false
	_rotation_finished=true
	var winner_side:String="" if dead_sides.size()!=1 else ("right" if dead_sides[0]=="left" else "left")
	if authority and Game.get_rotation_match_type()=="challenge":
		var outcome:String="dead" if dead_sides.has("left") else "won"
		var blue_index:int=int(_rotation_next_index.left)-1
		if blue_index>=0 and blue_index<_rotation_rosters.left.size(): _rotation_results[int(_rotation_rosters.left[blue_index].id)]=outcome
		for id:int in _rotation_active_records.left: _rotation_results[id]=outcome
	if is_instance_valid(duel_top_hud): duel_top_hud.begin_round_result(winner_side)
	if authority and not winner_side.is_empty(): _trigger_victory_bell()
	_celebrate_match_end()

func _present_rotation_match(dead_sides:Array[String],epoch:int,authority:bool) -> void:
	if _rotation_round_is_final(dead_sides):
		_present_rotation_final(dead_sides,authority)
		return
	_rotation_combat_blocked=false # Old round keeps moving/attacking while the result and closing doors play.
	_rotation_load_ready=false
	_rotation_ui_progress=0.0
	_rotation_combat_released=false
	var winner_side:String="" if dead_sides.size()!=1 else ("right" if dead_sides[0]=="left" else "left")
	if is_instance_valid(duel_top_hud): duel_top_hud.begin_round_result(winner_side)
	# 先记下胜负（HUD 照常），铃声等胜利卡片在关好的门上滑下来时再响。
	if authority and not winner_side.is_empty(): _trigger_victory_bell(false)
	# Keep the previous scene/actors until the result has arrived and the doors have actually covered a frame.
	await _rotation_ui_wait(ROTATION_PRE_DOOR_SECONDS,epoch)
	if not _rotation_presentation_valid(epoch): return
	_rotation_door=load("res://scripts/ui/dark_oak_transition.gd").ensure(get_tree())
	while _rotation_presentation_valid(epoch) and _rotation_door.is_busy(): await get_tree().process_frame
	if not _rotation_presentation_valid(epoch): return
	if is_instance_valid(duel_top_hud):
		# 门关上后从上方滑下胜利卡片（人物/队伍 + 提示文字），开门时随门滑回。
		_rotation_toast_mirror=load("res://scripts/ui/rotation_result_card.gd").new()
		_rotation_toast_mirror.call("setup",duel_top_hud,_rotation_door)
		_rotation_toast_mirror.set("next_matchup",rotation_next_matchup(dead_sides))
		_rotation_door.shield.add_child(_rotation_toast_mirror)
	var began:bool=_rotation_door.play(_load_rotation_covered.bind(dead_sides,epoch,authority),_release_rotation_combat.bind(epoch))
	if not began: return
	_rotation_door.wait_seconds=ROTATION_RESULT_WAIT_SECONDS
	if authority and not winner_side.is_empty(): _ring_victory_bell_on_card(epoch)
	await _rotation_door.finished
	if not _rotation_presentation_valid(epoch): return
	if is_instance_valid(_rotation_toast_mirror): _rotation_toast_mirror.queue_free()
	_rotation_toast_mirror=null
	_rotation_door=null
## 胜利卡片在门完全关上（COVERED）时开始滑下：这时响三声胜利铃。
func _ring_victory_bell_on_card(epoch:int) -> void:
	var door:CanvasLayer=_rotation_door
	while _rotation_presentation_valid(epoch) and is_instance_valid(door) and door==_rotation_door and int(door.phase)!=int(door.Phase.COVERED): await get_tree().process_frame
	if not _rotation_presentation_valid(epoch) or not is_instance_valid(door) or door!=_rotation_door: return
	for ring:int in range(3):
		if ring>0:
			await get_tree().create_timer(0.2,true,false,true).timeout
			if not _rotation_presentation_valid(epoch): return
		_play_victory_bell_once()
func _release_rotation_combat(epoch:int) -> void:
	if not _rotation_presentation_valid(epoch) or not _rotation_load_ready: return
	_rotation_combat_released=true
	_rotation_combat_blocked=false
	if is_instance_valid(duel_top_hud): duel_top_hud.end_round_result()
func rotation_next_matchup(dead_sides:Array[String]) -> Dictionary:
	var result:Dictionary={"left":[],"right":[]}
	var mode:String=Game.get_rotation_match_type()
	var starts_fresh:bool=mode=="challenge" and (dead_sides.has("left") or (dead_sides.has("right") and int(_rotation_next_index.right)>=_rotation_rosters.right.size()))
	if starts_fresh and int(_rotation_next_index.left)>=_rotation_rosters.left.size(): return result
	for side:String in ["left","right"]:
		var roster:Array=_rotation_rosters[side]
		var replaced:bool=starts_fresh or mode=="duel" or dead_sides.has(side)
		var index:int=int(_rotation_next_index[side])
		if starts_fresh and side=="right": index=0
		elif not replaced:
			index-=1
			if index>=0 and index<roster.size():
				var current_round:int=int(roster[index].get("round",index+1))
				while index>0 and int(roster[index-1].get("round",index))==current_round: index-=1
		if index<0 or index>=roster.size(): continue
		var names:Array=[]
		var round_number:int=int(roster[index].get("round",index+1))
		while index<roster.size() and int(roster[index].get("round",index+1))==round_number:
			names.append(Game.t(str(roster[index].get("char",""))).replace("_"," "))
			index+=1
		result[side]=names
	return result
func _rotation_next_scene_paths(dead_sides:Array[String]) -> Array[String]:
	var paths:Array[String]=[]
	var mode:String=Game.get_rotation_match_type()
	var starts_fresh:bool=mode=="challenge" and (dead_sides.has("left") or (dead_sides.has("right") and int(_rotation_next_index.right)>=_rotation_rosters.right.size()))
	if starts_fresh and int(_rotation_next_index.left)>=_rotation_rosters.left.size(): return paths
	for side:String in ["left","right"]:
		if not starts_fresh and mode!="duel" and not dead_sides.has(side): continue
		var roster:Array=_rotation_rosters[side]
		var index:int=0 if starts_fresh and side=="right" else int(_rotation_next_index[side])
		if index<0 or index>=roster.size(): continue
		var round_number:int=int(roster[index].get("round",index+1))
		while index<roster.size() and int(roster[index].get("round",index+1))==round_number:
			var entry:Dictionary=roster[index]
			var path:String=str(entry.get("scene_path",""))
			if path.is_empty(): path=character_scene_path(str(entry.get("char","")))
			# Preload every template in the wave; never report completion after just its leader.
			if not paths.has(path): paths.append(path)
			index+=1
	return paths

func _rotation_fail_load(path:String) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty(): _rotation_abort_load.rpc(_rotation_ui_token,path)
	_rotation_abort_load(_rotation_ui_token,path)
@rpc("authority","call_remote","reliable")
func _rotation_abort_load(token:int,path:String) -> void:
	if token!=_rotation_ui_token: return
	_rotation_epoch+=1
	_cancel_rotation_presentation()
	_rotation_transitioning=false
	_rotation_started=false
	_rotation_finished=true
	# Return to the existing formation controls without clearing the surviving old actor.
	control.show()
	control.team.show()
	var dialog:=AcceptDialog.new()
	dialog.title="加载失败 / Load failed"
	dialog.dialog_text="无法加载下一位，请修复资源后重置对局。\nCannot load the next contender. Fix the resource and reset the match.\n"+path
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func _load_rotation_covered(dead_sides:Array[String],epoch:int,authority:bool) -> void:
	if not _rotation_presentation_valid(epoch): return
	_rotation_combat_blocked=true
	# The old winner can still die to an existing projectile/status before coverage.
	if authority:
		for side:String in ["left","right"]:
			var setup_id:int=int(_rotation_active_setup[side])
			if not dead_sides.has(side) and setup_id>=0 and not _rotation_side_alive(side):
				dead_sides.append(side)
				_rotation_active_setup[side]=-1
				_rotation_active_name[side]=""
				_rotation_mark_current_dead(side)
		_rotation_pending_dead_sides.clear()
		if dead_sides.size()==2 and is_instance_valid(duel_top_hud): duel_top_hud.begin_round_result("")
	_rotation_door.set_loading_progress(_rotation_ui_progress)
	await _rotation_ui_wait(0.25,epoch) # Let the bar emerge before blocking instantiation work.
	if not _rotation_presentation_valid(epoch): return
	if authority:
		_set_rotation_load_progress(0.10) # Covered + old scene still intact.
		var paths:Array[String]=_rotation_next_scene_paths(dead_sides)
		for i:int in range(paths.size()):
			var path:String=paths[i]
			if path.is_empty() or not ResourceLoader.exists(path,"PackedScene"):
				_rotation_fail_load(path)
				return
			if not ResourceLoader.has_cached(path):
				var error:Error=ResourceLoader.load_threaded_request(path,"PackedScene")
				if error!=OK:
					_rotation_fail_load(path)
					return
				if error==OK:
					var measured:Array=[]
					while ResourceLoader.load_threaded_get_status(path,measured)==ResourceLoader.THREAD_LOAD_IN_PROGRESS:
						if not _rotation_presentation_valid(epoch): return
						_set_rotation_load_progress(0.10+0.55*(float(i)+float(measured[0] if not measured.is_empty() else 0.0))/maxi(paths.size(),1))
						await get_tree().process_frame
					if ResourceLoader.load_threaded_get_status(path)!=ResourceLoader.THREAD_LOAD_LOADED:
						_rotation_fail_load(path)
						return
					ResourceLoader.load_threaded_get(path)
			if not load(path) is PackedScene:
				_rotation_fail_load(path)
				return
			_set_rotation_load_progress(0.10+0.55*float(i+1)/maxi(paths.size(),1))
		if not _rotation_presentation_valid(epoch): return
		await _advance_rotation_match(dead_sides,epoch) # All retirement and spawning is behind closed doors.
		if not _rotation_presentation_valid(epoch): return
		_set_rotation_load_progress(0.90)
		await get_tree().process_frame
		if not _rotation_presentation_valid(epoch): return
		if DisplayServer.get_name()!="headless": await RenderingServer.frame_post_draw
		if not _rotation_presentation_valid(epoch): return
		_rotation_load_ready=true
		_reset_victory_bell_state()
		_set_rotation_load_progress(1.0)
		if multiplayer.has_multiplayer_peer(): _rotation_remote_progress.rpc(_rotation_ui_token,1.0,true)
	else:
		while _rotation_presentation_valid(epoch) and not _rotation_load_ready: await get_tree().process_frame
	if not _rotation_presentation_valid(epoch): return
	await _rotation_ui_wait(0.15,epoch)
	if not _rotation_presentation_valid(epoch): return
	_rotation_door.set_loading_progress(-1.0)
	var started:int=Time.get_ticks_usec()
	while _rotation_presentation_valid(epoch):
		var amount:float=clampf(float(Time.get_ticks_usec()-started)/300000.0,0.0,1.0)
		if is_instance_valid(duel_top_hud): duel_top_hud.round_exit=amount
		if amount>=1.0: break
		await get_tree().process_frame

func _clear_rotation_round_units() -> void:
	_clear_rotation_formation_preview(false)
	_rotation_active_records={"left":[],"right":[]}
	_battle_lifecycle_round += 1
	_battle_spawn_tickets.clear()
	_rotation_clearing_round = true
	_rotation_active_setup = {"left": -1,"right": -1}
	_rotation_active_name = {"left": "","right": ""}
	_rotation_preview_character = {"left": null,"right": null}
	_rotation_pending_dead_sides.clear()
	_training_respawn_pending.clear()
	_restore_special_prestart_nodes()
	_release_heavy_hitstop()
	_clear_battle_transients()
	for group:String in ["Ball","Shooter"]:
		for node:Node in get_tree().get_nodes_in_group(group):
			if node.has_meta("development_reserve"):
				continue
			if is_instance_valid(node) and not node.is_queued_for_deletion():
				node.process_mode = Node.PROCESS_MODE_DISABLED
				Game.free_node(node)
	if has_method("_reset_map_character_spawners"): call("_reset_map_character_spawners")
	_reset_victory_bell_state()
	_clear_rotation_hud_labels()

func _resolve_rotation_challenge(dead_sides:Array[String],epoch:int) -> void:
	var blue_lost:bool = dead_sides.has("left")
	var red_finished:bool = dead_sides.has("right") and int(_rotation_next_index["right"]) >= _rotation_rosters["right"].size()
	if not blue_lost and not red_finished:
		if dead_sides.has("right"): _spawn_next_rotation_character("right")
		return
	# Simultaneous elimination counts as failure: a successful challenger must survive.
	var blue_index:int = int(_rotation_next_index["left"])-1
	if blue_index >= 0 and blue_index < _rotation_rosters["left"].size():
		var blue_id:int = int(_rotation_rosters["left"][blue_index]["id"])
		_rotation_results[blue_id] = "dead" if blue_lost else "won"
		for id:int in _rotation_active_records.left: _rotation_results[id]="dead" if blue_lost else "won"
		if not blue_lost and not is_instance_valid(_rotation_door): _play_victory_bell_once()
	_clear_rotation_round_units()
	await get_tree().process_frame
	if epoch != _rotation_epoch or not is_inside_tree(): return
	# Clear deferred summons/projectiles produced by the old fighters during teardown.
	_clear_battle_transients()
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if node.has_meta("development_reserve"):
			continue
		if is_instance_valid(node) and not node.is_queued_for_deletion(): Game.free_node(node)
	await get_tree().process_frame
	if epoch != _rotation_epoch or not is_inside_tree(): return
	_rotation_clearing_round = false
	if int(_rotation_next_index["left"]) >= _rotation_rosters["left"].size():
		_rotation_finished = true
		return
	# All red opponents are fresh for EVERY blue challenger (including the first red).
	_rotation_next_index["right"] = 0
	for record:Dictionary in _rotation_rosters["right"]:
		_rotation_results.erase(int(record["id"]))
	if is_instance_valid(_rotation_frame_hud): _rotation_frame_hud.rows["right"].reset_scroll()
	_rotation_fresh_round = true
	_spawn_next_rotation_character("left")
	_spawn_next_rotation_character("right")
	_rotation_fresh_round = false
	notify_primary_battle_character_alive_changed()

func _restart_rotation_series(rosters:Dictionary) -> void:
	if not is_multiplayer_authority(): return
	if _development != null:
		_development.cleanup(false)
	_rotation_epoch += 1
	_cancel_rotation_presentation()
	_stop_match_fireworks()
	var epoch:int = _rotation_epoch
	_rotation_transitioning = true
	Game.end_battle_random()
	_clear_rotation_round_units()
	await get_tree().process_frame
	if epoch != _rotation_epoch or not is_inside_tree(): return
	_rotation_rosters = rosters.duplicate(true)
	_rotation_next_index = {"left": 0,"right": 0}
	_rotation_results.clear()
	_rotation_finished = false
	_rotation_started = false
	_rotation_clearing_round = false
	_rotation_transitioning = false
	_battle_setup.clear()
	_battle_setup_next_id = 1
	if _development != null:
		_development.prepare()
	if is_instance_valid(_rotation_frame_hud): _rotation_frame_hud.reset_scroll()
	for side:String in ["left","right"]:
		for record:Dictionary in _rotation_rosters[side]:
			_battle_setup_next_id = maxi(_battle_setup_next_id,int(record["id"])+1)
			_rotation_add_setup_preview_label(side,str(record["char"]),int(record["id"]))
		_spawn_rotation_preview_character_if_needed(side)
	if _development != null:
		_development.seed_rotation_roster()
	refresh_versus_text()

@rpc("authority","call_remote","reliable")
func _receive_rotation_frame_state(rosters:Dictionary,results:Dictionary,active:Dictionary) -> void:
	if is_multiplayer_authority(): return
	_rotation_rosters = rosters
	_rotation_results = results
	_rotation_active_setup = active
	for side:String in ["left","right"]:
		_rotation_active_records[side]=[]
		var current_round:int=-1
		for record:Dictionary in _rotation_rosters[side]:
			if int(record.id)==int(active[side]): current_round=int(record.get("round",-1))
		if current_round<0: continue
		for record:Dictionary in _rotation_rosters[side]:
			if int(record.get("round",-2))==current_round: _rotation_active_records[side].append(int(record.id))
	if is_instance_valid(control): control.call_deferred("_sync_rotation_formation_ui")


func _find_character_by_setup_id_any(setup_id:int) -> ball:
	for node:Node in _battle_units_cache:
		if node is ball and node.has_meta("battle_setup_id") and int(node.get_meta("battle_setup_id")) == setup_id:
			return node as ball
	return null


func _build_rotation_versus_hud() -> void:
	_rotation_frame_hud = preload("res://scripts/ui/rotation_frame_hud.gd").new()
	_rotation_frame_hud.world = self
	_rotation_frame_hud.visibility_layer = COMBAT_TEXT_VISIBILITY_LAYER
	add_child(_rotation_frame_hud)
	rotation_versus_root = Control.new()
	rotation_versus_root.name = "RotationVersusHUD"
	# 根节点自身不拦战场输入；左右名单区域单独接管滚轮/右键。
	rotation_versus_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rotation_versus_root.z_index = 102
	rotation_versus_root.visibility_layer = COMBAT_TEXT_VISIBILITY_LAYER
	rotation_versus_root.visible = false
	add_child(rotation_versus_root)

	rotation_left_root = Control.new()
	rotation_left_root.name = "RotationLeftNames"
	rotation_right_root = Control.new()
	rotation_right_root.name = "RotationRightNames"
	for side_root:Control in [rotation_left_root,rotation_right_root]:
		side_root.mouse_filter = Control.MOUSE_FILTER_STOP
		# 名字只在 HUD 的 58px 高窗口内显示，超出的名单靠滚轮查看。
		side_root.clip_contents = true
		# 不让滚轮继续漏到战场/父级 UI。
		side_root.mouse_force_pass_scroll_events = false
	rotation_left_root.gui_input.connect(_on_rotation_side_gui_input.bind("left"))
	rotation_right_root.gui_input.connect(_on_rotation_side_gui_input.bind("right"))
	rotation_versus_root.add_child(rotation_left_root)
	rotation_versus_root.add_child(rotation_right_root)

	rotation_vs_label = _make_rotation_name_label(HORIZONTAL_ALIGNMENT_CENTER)
	rotation_vs_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rotation_vs_label.text = "VS"
	rotation_vs_label.add_theme_color_override("font_color",Color.WHITE)
	rotation_versus_root.add_child(rotation_vs_label)


func _make_rotation_name_label(alignment:HorizontalAlignment) -> Label:
	var label := Label.new()
	# V83：名字本身就是可交互目标。右键名字可以精确删除对应 setup_id，
	# 不需要再从地图上叠在一起的人物里猜到底点中了谁。
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.mouse_force_pass_scroll_events = true
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",10)
	label.add_theme_color_override("font_outline_color",Color.BLACK)
	label.add_theme_constant_override("outline_size",1)
	label.custom_minimum_size = Vector2(0,12)
	label.gui_input.connect(_on_rotation_name_label_gui_input.bind(label))
	return label


func _rotation_side_root(side:String) -> Control:
	return rotation_left_root if side == "left" else rotation_right_root


func _rotation_side_alignment(side:String) -> HorizontalAlignment:
	return HORIZONTAL_ALIGNMENT_RIGHT if side == "left" else HORIZONTAL_ALIGNMENT_LEFT


func _rotation_tween_label(label:Label,target_y:float,target_alpha:float,duration:float = 0.24) -> Tween:
	# Godot 4.7 会在不存在 meta key 时对 get_meta() 报错，因此必须先 has_meta()。
	var old_tween:Variant = null
	if label.has_meta("rotation_move_tween"):
		old_tween = label.get_meta("rotation_move_tween")
	if old_tween is Tween and is_instance_valid(old_tween):
		(old_tween as Tween).kill()
	label.visible = true
	var tween:Tween = label.create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label,"position:y",target_y,duration)
	tween.tween_property(label,"modulate:a",target_alpha,duration)
	label.set_meta("rotation_move_tween",tween)
	return tween


func _rotation_add_setup_preview_label(side:String,char_name:String,setup_id:int = -1) -> void:
	var label:Label = _make_rotation_name_label(_rotation_side_alignment(side))
	label.set_meta("raw_character_name",char_name)
	label.set_meta("rotation_side",side)
	label.set_meta("rotation_setup_id",setup_id)
	label.set_meta("rotation_delete_enabled",setup_id >= 0)
	label.text = Game.t(char_name).replace("_"," ")
	label.add_theme_color_override("font_color",Color.WHITE)
	label.position.y = 48.0
	label.modulate.a = 0.0
	_rotation_side_root(side).add_child(label)
	var labels:Array = _rotation_setup_preview_labels[side]
	labels.append(label)
	_rotation_setup_preview_labels[side] = labels
	_rotation_layout_setup_preview(side)
	_layout_rotation_label_widths()


func _rotation_layout_setup_preview(side:String) -> void:
	var labels:Array = _rotation_setup_preview_labels[side]
	var count:int = labels.size()
	if count <= 0:
		_rotation_setup_scroll_rows[side] = 0
		return

	var max_scroll:int = maxi(0,count - ROTATION_SETUP_VISIBLE_ROWS)
	var scroll_rows:int = clampi(int(_rotation_setup_scroll_rows.get(side,0)),0,max_scroll)
	_rotation_setup_scroll_rows[side] = scroll_rows

	# scroll_rows=0 时显示最新一页；滚轮向上增加该值，从而查看更早加入的人物。
	var visible_start:int = maxi(0,count - ROTATION_SETUP_VISIBLE_ROWS - scroll_rows)
	var visible_end:int = mini(count,visible_start + ROTATION_SETUP_VISIBLE_ROWS)
	var visible_count:int = maxi(visible_end - visible_start,1)
	# 1~4 个名字保持围绕 VS 高度居中；5 个名字正好占满 0..48。
	var top_y:float = 24.0 - float(visible_count - 1) * ROTATION_NAME_ROW_HEIGHT * 0.5

	for i:int in range(count):
		var raw:Variant = labels[i]
		if not raw is Label or not is_instance_valid(raw):
			continue
		var label:Label = raw as Label
		if i < visible_start or i >= visible_end:
			label.visible = false
			label.modulate.a = 0.0
			continue
		var row:int = i - visible_start
		var target_y:float = top_y + float(row) * ROTATION_NAME_ROW_HEIGHT
		_rotation_tween_label(label,target_y,1.0,0.16)


func _rotation_scroll_setup_names(side:String,direction:int) -> void:
	if _rotation_started or side not in ["left","right"]:
		return
	var labels:Array = _rotation_setup_preview_labels[side]
	var max_scroll:int = maxi(0,labels.size() - ROTATION_SETUP_VISIBLE_ROWS)
	if max_scroll <= 0:
		return
	# direction > 0 = 滚轮向上，看更早名单；direction < 0 = 回到更新的人物。
	_rotation_setup_scroll_rows[side] = clampi(
		int(_rotation_setup_scroll_rows.get(side,0)) + direction,
		0,
		max_scroll
	)
	_rotation_layout_setup_preview(side)


func _on_rotation_side_gui_input(event:InputEvent,side:String) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event:InputEventMouseButton = event as InputEventMouseButton
	if not mouse_event.is_pressed():
		return
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_rotation_scroll_setup_names(side,1)
		_rotation_side_root(side).accept_event()
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_rotation_scroll_setup_names(side,-1)
		_rotation_side_root(side).accept_event()


func _on_rotation_name_label_gui_input(event:InputEvent,label:Label) -> void:
	if label == null or not is_instance_valid(label) or not event is InputEventMouseButton:
		return
	var mouse_event:InputEventMouseButton = event as InputEventMouseButton
	if not mouse_event.is_pressed():
		return
	var side:String = str(label.get_meta("rotation_side",""))
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_rotation_scroll_setup_names(side,1)
		label.accept_event()
		return
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_rotation_scroll_setup_names(side,-1)
		label.accept_event()
		return
	if mouse_event.button_index != MOUSE_BUTTON_RIGHT:
		return
	if not bool(label.get_meta("rotation_delete_enabled",false)):
		return
	var setup_id:int = int(label.get_meta("rotation_setup_id",-1))
	if setup_id < 0:
		return
	if delete_rotation_queue_setup_id(setup_id,side):
		label.accept_event()


func _rotation_promote_setup_preview_to_battle(side:String,_char_name:String) -> bool:
	var labels:Array = _rotation_setup_preview_labels[side]
	if labels.is_empty():
		return false
	# 开战时名单从“最后加入的位置”丝滑滚回队首：第一位落到 VS，
	# 后面最多保留两位，其他名字向下渐隐。VS 本身永远不移动。
	var current:Label = labels[0] as Label
	if current == null or not is_instance_valid(current):
		return false
	current.add_theme_color_override("font_color",Color(0.35,1.0,0.42))
	_rotation_tween_label(current,24.0,1.0,0.32)
	_rotation_current_labels[side] = current

	var future:Array = []
	for i in range(1,labels.size()):
		var raw:Variant = labels[i]
		if not raw is Label or not is_instance_valid(raw):
			continue
		var label:Label = raw as Label
		label.add_theme_color_override("font_color",Color.WHITE)
		if i <= 2:
			var target_y:float = 24.0 + float(i) * 12.0
			var target_alpha:float = 0.72 if i == 1 else 0.54
			_rotation_tween_label(label,target_y,target_alpha,0.32)
			future.append(label)
		else:
			var fade:Tween = _rotation_tween_label(label,48.0 + float(i - 2) * 6.0,0.0,0.28)
			fade.finished.connect(Callable(label,"queue_free"),CONNECT_ONE_SHOT)
	_rotation_future_labels[side] = future
	_rotation_setup_preview_labels[side] = []
	_layout_rotation_label_widths()
	return true



func _rotation_create_current_label(side:String,char_name:String,setup_id:int = -1) -> void:
	var old:Variant = _rotation_current_labels.get(side,null)
	if old is Label and is_instance_valid(old):
		(old as Label).queue_free()

	# 换人时优先把已经显示在 VS 下方的“下一位”直接滚上来，避免删掉重建造成跳动。
	var future:Array = _rotation_future_labels[side]
	if not future.is_empty():
		var candidate:Variant = future[0]
		if candidate is Label and is_instance_valid(candidate) and str((candidate as Label).get_meta("raw_character_name","")) == char_name:
			var label:Label = candidate as Label
			future.pop_front()
			_rotation_future_labels[side] = future
			label.add_theme_color_override("font_color",Color(0.35,1.0,0.42))
			_rotation_current_labels[side] = label
			_rotation_tween_label(label,24.0,1.0,0.24)
			_layout_rotation_label_widths()
			return

	var label:Label = _make_rotation_name_label(_rotation_side_alignment(side))
	label.set_meta("raw_character_name",char_name)
	label.set_meta("rotation_side",side)
	label.set_meta("rotation_setup_id",setup_id)
	label.set_meta("rotation_delete_enabled",setup_id >= 0)
	label.text = Game.t(char_name).replace("_"," ")
	label.add_theme_color_override("font_color",Color(0.35,1.0,0.42))
	label.position.y = 28.0
	label.modulate.a = 0.55
	_rotation_side_root(side).add_child(label)
	_rotation_current_labels[side] = label
	_rotation_tween_label(label,24.0,1.0,0.18)
	_layout_rotation_label_widths()


func _rotation_mark_current_dead(side:String,red:bool = true,winner:bool = false) -> void:
	for id:int in _rotation_active_records[side]:
		_rotation_results[id]="dead" if red else ("won" if winner else "retired")
	var index:int = int(_rotation_next_index.get(side,0))-1
	var roster:Array = _rotation_rosters[side]
	if index >= 0 and index < roster.size():
		_rotation_results[int(roster[index].get("id",-1))] = "dead" if red else ("won" if winner else "retired")
	var raw:Variant = _rotation_current_labels.get(side,null)
	if not raw is Label or not is_instance_valid(raw):
		return
	var label:Label = raw as Label
	label.set_meta("rotation_delete_enabled",false)
	_rotation_current_labels[side] = null
	if red:
		label.add_theme_color_override("font_color",Color(1.0,0.28,0.28))
		_rotation_attach_wasted_overlay(label)
	else:
		label.add_theme_color_override("font_color",Color(0.78,0.78,0.78))
	var history:Array = _rotation_history_labels[side]
	history.append(label)
	while history.size() > 2:
		var oldest:Label = history.pop_front() as Label
		if oldest != null and is_instance_valid(oldest):
			var fade:Tween = oldest.create_tween().set_parallel(true)
			fade.tween_property(oldest,"position:y",-12.0,0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			fade.tween_property(oldest,"modulate:a",0.0,0.24)
			fade.finished.connect(Callable(oldest,"queue_free"),CONNECT_ONE_SHOT)
	_rotation_history_labels[side] = history
	for i in range(history.size()):
		var item:Label = history[i] as Label
		if item == null or not is_instance_valid(item):
			continue
		var target_y:float = 12.0 - float(history.size() - 1 - i) * 12.0
		var target_alpha:float = 0.42 if i == 0 and history.size() > 1 else 0.82
		var tween:Tween = item.create_tween().set_parallel(true)
		tween.tween_property(item,"position:y",target_y,0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(item,"modulate:a",target_alpha,0.22)
	_rotation_refresh_future_labels(side)


const ROTATION_WASTED_OVERLAY:Script = preload("res://scripts/effects/wasted_overlay.gd")
func _rotation_attach_wasted_overlay(label:Label) -> void:
	# 真正战死（不是小局结束被清场）的名字上叠一层 WASTED：黑色渐隐横带 + 红字黑边。
	if label.has_node("WastedOverlay"):
		return
	var overlay:Control = ROTATION_WASTED_OVERLAY.new()
	overlay.name = "WastedOverlay"
	label.add_child(overlay)
	_rotation_fit_wasted_overlay(label,overlay)
	# 先缩在中间，再横向展开，配合名字变红的节奏。
	overlay.scale = Vector2(0.2,1.0)
	overlay.modulate.a = 0.0
	var tween:Tween = overlay.create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(overlay,"scale",Vector2.ONE,0.22)
	tween.tween_property(overlay,"modulate:a",1.0,0.14)


func _rotation_fit_wasted_overlay(label:Label,overlay:Control) -> void:
	# 横带以名字文字本身为中心（名字靠 VS 一侧对齐，不是整行居中），宽度约为文字的 1.8 倍。
	var font:Font = label.get_theme_font("font")
	var font_size:int = label.get_theme_font_size("font_size")
	var text_w:float = font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x if font != null else label.size.x
	var band_w:float = clampf(text_w * 1.8 + 24.0,64.0,label.size.x)
	var band_h:float = label.size.y + 2.0
	var text_center_x:float = label.size.x * 0.5
	match label.horizontal_alignment:
		HORIZONTAL_ALIGNMENT_RIGHT: text_center_x = label.size.x - text_w * 0.5
		HORIZONTAL_ALIGNMENT_LEFT: text_center_x = text_w * 0.5
	var left_x:float = clampf(text_center_x - band_w * 0.5,0.0,maxf(label.size.x - band_w,0.0))
	overlay.position = Vector2(left_x,-1.0)
	overlay.size = Vector2(band_w,band_h)
	overlay.pivot_offset = overlay.size * 0.5


func _rotation_refresh_future_labels(side:String) -> void:
	var old:Array = _rotation_future_labels[side]
	for raw in old:
		if raw is Label and is_instance_valid(raw):
			(raw as Label).queue_free()
	old.clear()
	var roster:Array = _rotation_rosters[side]
	var next_index:int = int(_rotation_next_index[side])
	for offset in range(2):
		var index:int = next_index + offset
		if index < 0 or index >= roster.size():
			break
		var record:Dictionary = roster[index]
		var char_name:String = str(record.get("char",""))
		var label:Label = _make_rotation_name_label(_rotation_side_alignment(side))
		label.set_meta("raw_character_name",char_name)
		label.set_meta("rotation_side",side)
		label.set_meta("rotation_setup_id",int(record.get("id",-1)))
		label.set_meta("rotation_delete_enabled",true)
		label.text = Game.t(char_name).replace("_"," ")
		label.add_theme_color_override("font_color",Color.WHITE)
		label.modulate.a = 0.72 - float(offset) * 0.18
		label.position.y = 36.0 + float(offset) * 12.0
		_rotation_side_root(side).add_child(label)
		old.append(label)
	_rotation_future_labels[side] = old
	_layout_rotation_label_widths()


func _rotation_refresh_all_texts() -> void:
	if not is_instance_valid(rotation_versus_root):
		return
	for side:String in ["left","right"]:
		for raw in [_rotation_current_labels.get(side,null)]:
			if raw is Label and is_instance_valid(raw):
				var label:Label = raw as Label
				label.text = Game.t(str(label.get_meta("raw_character_name",""))).replace("_"," ")
		for array_raw in [_rotation_history_labels.get(side,[]),_rotation_future_labels.get(side,[]),_rotation_setup_preview_labels.get(side,[])]:
			var labels:Array = array_raw
			for raw_label in labels:
				if raw_label is Label and is_instance_valid(raw_label):
					var label:Label = raw_label as Label
					label.text = Game.t(str(label.get_meta("raw_character_name",""))).replace("_"," ")
	if is_instance_valid(rotation_vs_label):
		rotation_vs_label.text = "VS"
	_layout_rotation_label_widths()


func _clear_rotation_hud_labels() -> void:
	for side:String in ["left","right"]:
		var current:Variant = _rotation_current_labels.get(side,null)
		if current is Label and is_instance_valid(current): (current as Label).queue_free()
		for bucket in [_rotation_history_labels.get(side,[]),_rotation_future_labels.get(side,[]),_rotation_setup_preview_labels.get(side,[])]:
			for raw in bucket:
				if raw is Label and is_instance_valid(raw): (raw as Label).queue_free()
		_rotation_current_labels[side] = null
		_rotation_history_labels[side] = []
		_rotation_future_labels[side] = []
		_rotation_setup_preview_labels[side] = []


func _layout_rotation_versus_hud() -> void:
	if not is_instance_valid(rotation_versus_root) or not map_group.has(now_choose_map):
		return
	# The map-cell frame HUD must never inherit a scaled Boss roster transform.
	rotation_versus_root.scale = Vector2.ONE
	rotation_versus_root.visible = _queue_battle_mode_active() and not _armor_stand_test_hud_active
	if not rotation_versus_root.visible:
		return
	var use_frames:bool = Game.is_rotation_training_mode()
	rotation_left_root.visible = not use_frames
	rotation_right_root.visible = not use_frames
	rotation_vs_label.visible = not use_frames
	if use_frames:
		var frame_map_rect:Rect2 = return_map_visual_rect(map_group[now_choose_map])
		var frame_cell:Vector2 = map_visual_cell_size(map_group[now_choose_map])
		rotation_versus_root.position = Vector2(frame_map_rect.position.x,frame_map_rect.position.y-frame_cell.y*1.22)
		rotation_versus_root.size = Vector2(frame_map_rect.size.x,frame_cell.y)
		if is_instance_valid(_rotation_frame_hud): _rotation_frame_hud.sync()
		_refresh_center_watermark_layout()
		return
	var map_rect:Rect2 = return_map_visual_rect(map_group[now_choose_map])
	# Scale the complete legacy roster, not just the two letters: name columns,
	# scroll/selection hit areas and VS keep their original relative proportions.
	var hud_scale:float = minf(get_map_versus_scale(map_group[now_choose_map]),map_rect.size.x / 68.0)
	hud_scale = maxf(hud_scale,0.05)
	rotation_versus_root.scale = Vector2.ONE * hud_scale
	var hud_h:float = 58.0
	var base_y:float = interaction_label.position.y if interaction_label != null and interaction_label.visible else map_rect.position.y
	rotation_versus_root.position = Vector2(map_rect.position.x,base_y - (versus_interaction_gap + hud_h) * hud_scale)
	var hud_width:float = map_rect.size.x / hud_scale
	rotation_versus_root.size = Vector2(hud_width,hud_h)
	var center_w:float = 28.0
	var side_w:float = maxf((hud_width - center_w) * 0.5,20.0)
	rotation_left_root.position = Vector2.ZERO
	rotation_left_root.size = Vector2(side_w,hud_h)
	rotation_vs_label.position = Vector2(side_w,20.0)
	rotation_vs_label.size = Vector2(center_w,16.0)
	rotation_right_root.position = Vector2(side_w + center_w,0.0)
	rotation_right_root.size = Vector2(side_w,hud_h)
	_layout_rotation_label_widths()


func _layout_rotation_label_widths() -> void:
	for side:String in ["left","right"]:
		var root:Control = _rotation_side_root(side)
		if root == null or not is_instance_valid(root): continue
		for child:Node in root.get_children():
			if child is Label:
				var name_label:Label = child as Label
				name_label.size = Vector2(root.size.x,12.0)
				# Long Chinese/English names must fit the scaled columns, including
				# when returning to a smaller map after a larger one.
				var font:Font = name_label.get_theme_font("font")
				var font_size:int = 10
				var text_width:float = 0.0
				var safe_width:float = maxf(root.size.x - 2.0,1.0)
				if font != null:
					text_width = font.get_string_size(name_label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
					while font_size > 4 and text_width > safe_width:
						font_size -= 1
						text_width = font.get_string_size(name_label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
				name_label.add_theme_font_size_override("font_size",font_size)
				# On 2x2 even the smallest readable font can exceed one column.
				# Compress only its horizontal axis, retaining vertical readability.
				var width_factor:float = minf(1.0,safe_width / maxf(text_width,1.0))
				name_label.scale = Vector2(width_factor,1.0)
				name_label.size.x = root.size.x / width_factor
				if child.has_node("WastedOverlay"):
					_rotation_fit_wasted_overlay(child as Label,child.get_node("WastedOverlay") as Control)


#========================================================
# 计时模式
#========================================================
func _enqueue_timed_character(team:String,char_name:String,poi:Vector2,scene_path:String="") -> void:
	if not _has_character_scene_any(char_name):
		push_warning("计时模式无法加入角色: " + char_name)
		return
	var setup_id:int = _battle_setup_next_id
	_battle_setup_next_id += 1
	var entry:Dictionary = {"id":setup_id,"team":team,"char":char_name,"scene_path":scene_path if not scene_path.is_empty() else character_scene_path(char_name),"x":poi.x,"y":poi.y}
	if _battle_setup.is_empty():
		_battle_setup_map = now_choose_map
	_battle_setup.append(entry.duplicate(true))
	_timed_damage_by_setup[setup_id] = float(_timed_damage_by_setup.get(setup_id,0.0))
	_timed_name_by_setup[setup_id] = char_name
	_timed_start_armed = true

	# 放下去就能看见人物和头顶伤害数字；工具栏关闭前冻结全部行为。
	var spawned:ball = _spawn_character_from_setup(entry)
	if spawned != null and not _timed_running:
		spawned.set_meta("timed_prestart_preview",true)
		spawned.process_mode = Node.PROCESS_MODE_DISABLED
	_refresh_timed_training_hud()


func _spawn_pending_timed_characters() -> void:
	var pending:Array[Dictionary] = _timed_pending_entries.duplicate(true)
	_timed_pending_entries.clear()
	for entry:Dictionary in pending:
		_spawn_character_from_setup(entry)


func _activate_timed_prestart_characters() -> void:
	# 先恢复所有布阵阶段冻结对象，包括主角色 _ready 后额外生成的伙伴/召唤物。
	_restore_special_prestart_nodes()
	for node:Node in _battle_units_cache:
		if not node is ball or not is_instance_valid(node):
			continue
		if not node.has_meta("timed_prestart_preview"):
			continue
		node.remove_meta("timed_prestart_preview")
		node.process_mode = Node.PROCESS_MODE_INHERIT


func _build_timed_training_hud() -> void:
	timed_training_label = Label.new()
	timed_training_label.name = "TimedTrainingClock"
	timed_training_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timed_training_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timed_training_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	timed_training_label.add_theme_font_size_override("font_size",10)
	timed_training_label.add_theme_color_override("font_color",Color.WHITE)
	timed_training_label.add_theme_color_override("font_outline_color",Color.BLACK)
	timed_training_label.add_theme_constant_override("outline_size",1)
	timed_training_label.z_index = 104
	timed_training_label.visibility_layer = COMBAT_TEXT_VISIBILITY_LAYER
	timed_training_label.visible = false
	add_child(timed_training_label)




func _make_directional_gravity_registry_key(source:Node,key:String) -> String:
	var resolved_key:String = key.strip_edges()
	if resolved_key.is_empty():
		resolved_key = "default"
	if source == null or not is_instance_valid(source):
		return resolved_key
	return "%s::%s" % [str(source.get_instance_id()),resolved_key]


func _cleanup_directional_gravity_sources() -> void:
	if _directional_gravity_sources.is_empty():
		return
	var expired:Array[String] = []
	for raw_key:Variant in _directional_gravity_sources.keys():
		var registry_key:String = str(raw_key)
		var entry:Dictionary = _directional_gravity_sources.get(registry_key,{})
		var source_ref:WeakRef = entry.get("source_ref",null)
		if source_ref == null:
			expired.append(registry_key)
			continue
		var source_node:Node = source_ref.get_ref() as Node
		if source_node == null or not is_instance_valid(source_node) or not source_node.is_inside_tree():
			expired.append(registry_key)
			continue

		# V148：可选“只作用于某个目标”的定向重力。旧调用不提供 target_ref，
		# 行为保持原样；Sans 的蓝魂重力用它避免把整场所有单位一起吸向同一方向。
		var target_ref:WeakRef = entry.get("target_ref",null)
		if target_ref != null:
			var target_node:Node = target_ref.get_ref() as Node
			if target_node == null or not is_instance_valid(target_node) or not target_node.is_inside_tree():
				expired.append(registry_key)
	for registry_key:String in expired:
		_directional_gravity_sources.erase(registry_key)


func register_directional_gravity(
	source:Node,
	key:String,
	direction:Vector2,
	strength:float,
	include_source:bool = false,
	target:Node = null
) -> void:
	_cleanup_directional_gravity_sources()
	if source == null or not is_instance_valid(source):
		return
	var normalized_direction:Vector2 = direction.normalized() if direction.length_squared() > 0.000001 else Vector2.ZERO
	if normalized_direction == Vector2.ZERO or strength <= 0.0:
		clear_directional_gravity(source,key)
		return
	var target_ref:WeakRef = null
	if target != null and is_instance_valid(target):
		target_ref = weakref(target)
	var registry_key:String = _make_directional_gravity_registry_key(source,key)
	_directional_gravity_sources[registry_key] = {
		"source_ref": weakref(source),
		"direction": normalized_direction,
		"strength": maxf(strength,0.0),
		"include_source": include_source,
		"target_ref": target_ref,
	}


func clear_directional_gravity(source:Node,key:String = "") -> void:
	if _directional_gravity_sources.is_empty():
		return
	if source == null or not is_instance_valid(source):
		return
	if not key.strip_edges().is_empty():
		_directional_gravity_sources.erase(_make_directional_gravity_registry_key(source,key))
		return
	var expired:Array[String] = []
	for raw_key:Variant in _directional_gravity_sources.keys():
		var registry_key:String = str(raw_key)
		var entry:Dictionary = _directional_gravity_sources.get(registry_key,{})
		var source_ref:WeakRef = entry.get("source_ref",null)
		if source_ref != null and source_ref.get_ref() == source:
			expired.append(registry_key)
	for registry_key:String in expired:
		_directional_gravity_sources.erase(registry_key)


func has_active_directional_gravity_fast() -> bool:
	return not _directional_gravity_sources.is_empty()


func get_directional_gravity_for_fast(target:Node) -> Vector2:
	if _directional_gravity_sources.is_empty():
		return Vector2.ZERO
	var total:Vector2 = Vector2.ZERO
	for entry:Dictionary in _directional_gravity_sources.values():
		var source_ref:WeakRef = entry.get("source_ref",null)
		if source_ref == null:
			continue
		var source_node:Node = source_ref.get_ref() as Node
		if source_node == null or not is_instance_valid(source_node):
			continue
		if source_node == target and not bool(entry.get("include_source",false)):
			continue

		# V148：target_ref 非空时，这条重力只对指定目标生效。
		var target_ref:WeakRef = entry.get("target_ref",null)
		if target_ref != null:
			var registered_target:Node = target_ref.get_ref() as Node
			if registered_target == null or registered_target != target:
				continue

		var dir:Vector2 = entry.get("direction",Vector2.ZERO)
		var strength:float = float(entry.get("strength",0.0))
		if dir.length_squared() <= 0.000001 or strength <= 0.0:
			continue
		total += dir*strength
	return total


func get_directional_gravity_for(target:Node) -> Vector2:
	_cleanup_directional_gravity_sources()
	return get_directional_gravity_for_fast(target)


# V259：兼容项目里不继承 ball、但属于 shooter/BattleTransient 的高速弹丸。
# 这类脚本通常自己做射线/Area 移动；直接改其现有“速度向量”能让它自己的命中检测
# 继续沿真实弯曲后的方向工作，而不是从 World 直接瞬移 global_position。
func _apply_directional_gravity_to_non_ball_projectiles(delta:float) -> void:
	if delta <= 0.0:
		return
	_cleanup_directional_gravity_sources()
	if _directional_gravity_sources.is_empty():
		return

	# V410：复用事件注册表，不再在每个 physics tick 扫 BattleTransient 全组。
	for raw_node:Node in _non_ball_projectiles:
		if raw_node == null or not is_instance_valid(raw_node) or not raw_node.is_inside_tree():
			continue
		if not raw_node.is_multiplayer_authority():
			continue

		var gravity_accel:Vector2 = get_directional_gravity_for(raw_node)
		if gravity_accel.length_squared() <= 0.000001:
			continue
		# V286：非 ball 的 shooter/BattleTransient 同样使用 7 倍投射物重力。
		gravity_accel *= DIRECTIONAL_GRAVITY_NON_BALL_PROJECTILE_MULTIPLIER
		var current_velocity:Vector2 = _directional_gravity_projectile_velocity(raw_node)
		if current_velocity.length_squared() <= 0.000001:
			continue
		_set_directional_gravity_projectile_velocity(
			raw_node,
			current_velocity + gravity_accel * delta
		)


func _update_non_ball_projectile_visual_facing() -> void:
	# V410：这里只遍历真正符合 shooter 速度接口的缓存节点；不再每渲染帧
	# get_nodes_in_group("BattleTransient")，也不再反复 get_property_list()。
	for raw_node:Node in _non_ball_projectiles:
		if raw_node == null or not is_instance_valid(raw_node) or not raw_node.is_inside_tree():
			continue

		var profile:Dictionary = _directional_projectile_profile(raw_node)
		var script_path:String = str(profile.get("script_path",""))
		if script_path in PROJECTILE_AUTO_FACE_EXCLUDED_SCRIPTS:
			continue

		var projectile:Node2D = raw_node as Node2D
		if projectile == null:
			continue
		var instance_id:int = projectile.get_instance_id()
		var current_position:Vector2 = projectile.global_position
		var motion_direction:Vector2 = Vector2.ZERO
		if _projectile_visual_last_positions.has(instance_id):
			var previous_value:Variant = _projectile_visual_last_positions.get(instance_id)
			if typeof(previous_value) == TYPE_VECTOR2:
				var previous_position:Vector2 = previous_value
				var displacement:Vector2 = current_position - previous_position
				if displacement.length_squared() > 0.0004:
					motion_direction = displacement.normalized()
		_projectile_visual_last_positions[instance_id] = current_position

		if motion_direction.length_squared() <= 0.000001:
			var velocity_value:Vector2 = _directional_gravity_projectile_velocity(raw_node)
			if velocity_value.length_squared() > 0.000001:
				motion_direction = velocity_value.normalized()
		if motion_direction.length_squared() <= 0.000001:
			continue

		# scripts/shooter 中所有非 ball 的直线/弯曲弹丸，美术基准均以本地 +X 为前方。
		# V411：方向没变时不要每个 render frame 重写 global_rotation，避免弹幕多时制造大量 Transform 脏更新。
		var desired_rotation:float = motion_direction.angle()
		if not is_equal_approx(projectile.global_rotation,desired_rotation):
			projectile.global_rotation = desired_rotation


func _try_register_non_ball_projectile_id(instance_id:int) -> void:
	if is_instance_id_valid(instance_id):
		_try_register_non_ball_projectile(instance_from_id(instance_id) as Node)


func _try_register_non_ball_projectile(node:Node) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	if node is ball or not node is Node2D or not node.is_in_group("BattleTransient"):
		return
	var profile:Dictionary = _directional_projectile_profile(node)
	if not bool(profile.get("eligible",false)):
		return
	var instance_id:int = node.get_instance_id()
	if _non_ball_projectile_ids.has(instance_id):
		return
	_non_ball_projectile_ids[instance_id] = true
	_non_ball_projectiles.append(node)
	node.tree_exiting.connect(_on_non_ball_projectile_tree_exiting.bind(instance_id),CONNECT_ONE_SHOT)


func _on_non_ball_projectile_tree_exiting(instance_id:int) -> void:
	_non_ball_projectile_ids.erase(instance_id)
	_projectile_visual_last_positions.erase(instance_id)
	for i:int in range(_non_ball_projectiles.size() - 1,-1,-1):
		var raw_node:Node = _non_ball_projectiles[i]
		if raw_node == null or not is_instance_valid(raw_node) or raw_node.get_instance_id() == instance_id:
			_non_ball_projectiles.remove_at(i)


func _resync_non_ball_projectile_registry() -> void:
	var tree:SceneTree = get_tree()
	if tree == null:
		return
	var seen:Dictionary = {}
	for raw_node:Node in tree.get_nodes_in_group("BattleTransient"):
		if raw_node == null or not is_instance_valid(raw_node) or raw_node is ball or not raw_node is Node2D:
			continue
		var profile:Dictionary = _directional_projectile_profile(raw_node)
		if not bool(profile.get("eligible",false)):
			continue
		var instance_id:int = raw_node.get_instance_id()
		seen[instance_id] = true
		_try_register_non_ball_projectile(raw_node)

	for i:int in range(_non_ball_projectiles.size() - 1,-1,-1):
		var raw_node:Node = _non_ball_projectiles[i]
		if raw_node == null or not is_instance_valid(raw_node):
			_non_ball_projectiles.remove_at(i)
			continue
		var instance_id:int = raw_node.get_instance_id()
		if not seen.has(instance_id):
			_non_ball_projectile_ids.erase(instance_id)
			_projectile_visual_last_positions.erase(instance_id)
			_non_ball_projectiles.remove_at(i)


func _directional_projectile_profile(node:Node) -> Dictionary:
	if node == null or not is_instance_valid(node):
		return {"eligible":false}
	var script_value:Variant = node.get_script()
	if not script_value is Script:
		return {"eligible":false}
	var script_resource:Script = script_value as Script
	var script_path:String = script_resource.resource_path
	if not script_path.begins_with("res://scripts/shooter/"):
		return {"eligible":false,"script_path":script_path}

	var cache_key:String = script_path
	if cache_key.is_empty():
		cache_key = "script_id:%d" % script_resource.get_instance_id()
	if _directional_projectile_profile_cache.has(cache_key):
		return _directional_projectile_profile_cache[cache_key]

	var property_names:Dictionary = {}
	for info:Dictionary in node.get_property_list():
		property_names[str(info.get("name",""))] = true

	var vector_properties:Array[String] = []
	for property_name:String in ["velocity","_velocity"]:
		if property_names.has(property_name):
			vector_properties.append(property_name)
	var direction_properties:Array[String] = []
	for property_name:String in ["direction","travel_direction"]:
		if property_names.has(property_name):
			direction_properties.append(property_name)
	var speed_properties:Array[String] = []
	for property_name:String in ["Speed","speed","projectile_speed","move_speed","travel_speed"]:
		if property_names.has(property_name):
			speed_properties.append(property_name)

	var profile:Dictionary = {
		"eligible": not vector_properties.is_empty() or (not direction_properties.is_empty() and not speed_properties.is_empty()),
		"script_path": script_path,
		"vector_properties": vector_properties,
		"direction_properties": direction_properties,
		"speed_properties": speed_properties,
		"has_max_speed": property_names.has("max_speed"),
	}
	_directional_projectile_profile_cache[cache_key] = profile
	return profile


func _is_directional_gravity_projectile(node:Node) -> bool:
	return bool(_directional_projectile_profile(node).get("eligible",false))


func _directional_gravity_projectile_velocity(node:Node) -> Vector2:
	var profile:Dictionary = _directional_projectile_profile(node)
	if not bool(profile.get("eligible",false)):
		return Vector2.ZERO

	var vector_properties:Array = profile.get("vector_properties",[])
	for raw_property:Variant in vector_properties:
		var vector_property:String = str(raw_property)
		var value:Variant = node.get(vector_property)
		if typeof(value) == TYPE_VECTOR2:
			var vector_value:Vector2 = value
			if vector_value.length_squared() > 0.000001:
				return vector_value

	var resolved_direction:Vector2 = Vector2.ZERO
	var direction_properties:Array = profile.get("direction_properties",[])
	for raw_property:Variant in direction_properties:
		var direction_value:Variant = node.get(str(raw_property))
		if typeof(direction_value) == TYPE_VECTOR2:
			var direction_vector:Vector2 = direction_value
			if direction_vector.length_squared() > 0.000001:
				resolved_direction = direction_vector.normalized()
				break
	if resolved_direction == Vector2.ZERO:
		return Vector2.ZERO

	var speed_properties:Array = profile.get("speed_properties",[])
	for raw_property:Variant in speed_properties:
		var speed_value:Variant = node.get(str(raw_property))
		if typeof(speed_value) == TYPE_FLOAT or typeof(speed_value) == TYPE_INT:
			return resolved_direction * maxf(float(speed_value),0.0)
	return Vector2.ZERO


func _set_directional_gravity_projectile_velocity(node:Node,new_velocity:Vector2) -> void:
	if new_velocity.length_squared() <= 0.000001:
		return
	var profile:Dictionary = _directional_projectile_profile(node)
	if not bool(profile.get("eligible",false)):
		return
	var normalized:Vector2 = new_velocity.normalized()
	var new_speed:float = new_velocity.length()

	var wrote_vector:bool = false
	var vector_properties:Array = profile.get("vector_properties",[])
	for raw_property:Variant in vector_properties:
		var vector_property:String = str(raw_property)
		var old_value:Variant = node.get(vector_property)
		if typeof(old_value) == TYPE_VECTOR2:
			node.set(vector_property,new_velocity)
			wrote_vector = true

	var direction_properties:Array = profile.get("direction_properties",[])
	for raw_property:Variant in direction_properties:
		node.set(str(raw_property),normalized)

	if not wrote_vector:
		var speed_properties:Array = profile.get("speed_properties",[])
		for raw_property:Variant in speed_properties:
			var speed_property:String = str(raw_property)
			node.set(speed_property,new_speed)
			# speed/max_speed 配对的军火商弹不能被下一帧 acceleration 拉回旧上限。
			if speed_property == "speed" and bool(profile.get("has_max_speed",false)):
				var old_max:float = float(node.get("max_speed"))
				if new_speed > old_max:
					node.set("max_speed",new_speed)
			break

	# 只同步朝向，不改位置；真正位移仍交给投射物自己的 physics/raycast 逻辑。
	if node is Node2D:
		(node as Node2D).global_rotation = normalized.angle()


func _is_character_dialogue_enabled() -> bool:
	return bool(Game.Game_Settings.get("Enable_Dialogue", false))


# V49：统一的“战斗逻辑是否允许运行”闸门。
#
# 手动模式：
# - 工具栏开关完全不参与判断；
# - 只要时间在流动，攻击、技能和周期机制都可以运行；
# - 时间停止 / SceneTree 暂停 / time_scale=0 时全部停止。
#
# 轮放 / 计时 / Boss：
# - 仍保留各自正式开始条件。
func is_combat_runtime_active() -> bool:
	if random_character_draft.blocks_combat(): return false
	var tree:SceneTree = get_tree()
	if _development != null and _development.phase == _development.MERGING:
		return false
	if (
		tree == null
		or tree.paused
		or Game.now_stop_state
		or Engine.time_scale <= 0.000001
	):
		return false
	if _development != null and _development.is_running():
		return _has_alive_primary_battle_character_cached()

	# 手动模式：工具栏开着也算运行中，只看时间有没有停止。
	if Game.get_training_mode_type() == "manual":
		return _has_alive_primary_battle_character_cached()

	# 特殊模式仍然保留布阵/正式开战界线。
	if (
		is_instance_valid(control)
		and control.has_method("is_set_team")
		and bool(control.call("is_set_team"))
	):
		return false

	if Game.is_boss_training_mode():
		return _boss_started and not _boss_intro_playing
	if Game.is_rotation_training_mode():
		return _rotation_started and not _rotation_combat_blocked
	if Game.is_timed_training_mode():
		return _timed_running or (_timed_finished and _has_alive_primary_battle_character_cached())

	return _has_alive_primary_battle_character_cached()


# 同一 physics tick 内复用存活判断；渲染帧（非物理帧）不缓存，保持原逐次扫描语义。
# Runtime survival is broader than editable/main-character count. Keep the
# exact existence/count optimization above unchanged for placement callers.
func _has_active_battle_participant() -> bool:
	for raw:Variant in _battle_units_cache:
		if raw is ball and _battle_unit_keeps_family_alive(raw): return true
	_prune_battle_spawn_tickets()
	return not _battle_spawn_tickets.is_empty()

func _has_alive_primary_battle_character_cached() -> bool:
	if not Engine.is_in_physics_frame():
		return _has_active_battle_participant()
	var frame:int = Engine.get_physics_frames()
	if _alive_primary_cache_frame != frame:
		_alive_primary_cache_frame = frame
		_alive_primary_cache_value = _has_active_battle_participant()
	return _alive_primary_cache_value


# ball.health 归零 / 复活时调用，让同帧后续查询立即看到变化。
func notify_primary_battle_character_alive_changed() -> void:
	_alive_primary_cache_frame = -1


# 角色“开场问候”与真实战斗逻辑使用同一套开战条件，避免两套规则再次分叉。
func is_character_dialogue_battle_active() -> bool:
	return is_combat_runtime_active()


func _character_dialogue_round_started_structurally() -> bool:
	# V49：手动模式的结构性开局也不再读取工具栏状态。
	if Game.get_training_mode_type() == "manual":
		return _count_primary_battle_characters() >= 1

	if (
		is_instance_valid(control)
		and control.has_method("is_set_team")
		and bool(control.call("is_set_team"))
	):
		return false
	if Game.is_boss_training_mode():
		return _boss_started
	if Game.is_rotation_training_mode():
		return _rotation_started
	if Game.is_timed_training_mode():
		return _timed_running and not _timed_finished
	return _count_primary_battle_characters() >= 1


func _update_character_dialogue_battle_start_edge() -> void:
	# 时间静止/SceneTree.pause 只会推迟开场事件，绝不会把“恢复时间”误判成新的一局。
	var structural_started:bool = _character_dialogue_round_started_structurally()
	if not structural_started:
		_character_dialogue_battle_was_active = false
		return
	if _character_dialogue_battle_was_active:
		return
	if not is_character_dialogue_battle_active():
		return
	_character_dialogue_battle_was_active = true
	_character_dialogue_battle_serial += 1
	character_dialogue_battle_started.emit(_character_dialogue_battle_serial)


func get_character_dialogue_battle_serial() -> int:
	return _character_dialogue_battle_serial


func _build_character_dialogue_hud() -> void:
	if is_instance_valid(character_dialogue_root):
		return
	character_dialogue_root = Control.new()
	character_dialogue_root.name = "CharacterDialogueHUD"
	character_dialogue_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	character_dialogue_root.z_index = 104
	character_dialogue_root.visibility_layer = COMBAT_TEXT_VISIBILITY_LAYER
	character_dialogue_root.visible = _is_character_dialogue_enabled()
	add_child(character_dialogue_root)
	_layout_character_dialogue_hud()


func _ensure_character_dialogue_label(side_key:String) -> Label:
	var raw:Variant = _character_dialogue_labels.get(side_key, null)
	if is_instance_valid(raw) and raw is Label:
		return raw as Label

	if not is_instance_valid(character_dialogue_root):
		_build_character_dialogue_hud()
	if not is_instance_valid(character_dialogue_root):
		return null

	var label := Label.new()
	label.name = "Dialogue_" + str(abs(side_key.hash()))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# 对话允许多行：旧版居中单行 + clip_text 会在长句时把左右两端，尤其前半句直接裁掉。
	label.clip_text = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", character_dialogue_font_size)
	label.add_theme_color_override("font_color", return_side_color(side_key))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 1)
	label.visible = false
	character_dialogue_root.add_child(label)
	_character_dialogue_labels[side_key] = label
	return label


func _dialogue_root_character(b:ball) -> ball:
	if b == null or not is_instance_valid(b):
		return null
	var root:ball = b
	var safety:int = 0
	while root.Master != null and is_instance_valid(root.Master) and safety < 12:
		root = root.Master
		safety += 1
	return root


func _dialogue_side_order() -> Array[String]:
	var result:Array[String] = []
	var battle_data:Dictionary = return_battle_sides()
	var raw_order:Variant = battle_data.get("order", [])
	if raw_order is Array:
		for raw_side:Variant in raw_order:
			var side_key:String = str(raw_side)
			if not side_key.is_empty() and not result.has(side_key):
				result.append(side_key)

	# 刚死亡/被替换的角色台词仍应完整显示到超时，因此保留本局见过的阵营顺序。
	for side_key:String in _character_dialogue_seen_order:
		if _character_dialogue_entries.has(side_key) and not result.has(side_key):
			result.append(side_key)
	return result


func _character_dialogue_timed_layout(map_rect:Rect2, side_order:Array[String]) -> Dictionary:
	var count:int = side_order.size()
	if count <= 0 or not Game.is_timed_training_mode() or not _is_character_dialogue_enabled():
		return {"clock": map_rect, "slots": []}

	var clock_width:float = clampf(
		character_dialogue_timed_clock_width,
		minf(32.0, map_rect.size.x),
		maxf(map_rect.size.x * 0.45, 32.0)
	)
	clock_width = minf(clock_width, map_rect.size.x * 0.45)
	var usable_width:float = maxf(map_rect.size.x - clock_width, 1.0)
	var slot_width:float = usable_width / float(count)
	var insert_after:int = mini(character_dialogue_timed_left_slots, count)
	var slots:Array = []
	for i:int in range(count):
		var local_x:float = float(i) * slot_width
		if i >= insert_after:
			local_x += clock_width
		slots.append(Rect2(
			Vector2(map_rect.position.x + local_x, map_rect.end.y + 3.0),
			Vector2(slot_width, character_dialogue_lane_height)
		))
	var clock_x:float = map_rect.position.x + float(insert_after) * slot_width
	var clock_rect := Rect2(
		Vector2(clock_x, map_rect.end.y + 3.0),
		Vector2(clock_width, character_dialogue_lane_height)
	)
	return {"clock": clock_rect, "slots": slots}


func _layout_character_dialogue_hud() -> void:
	if not is_instance_valid(character_dialogue_root) or not map_group.has(now_choose_map):
		return
	var enabled:bool = _is_character_dialogue_enabled()
	character_dialogue_root.visible = enabled
	if not enabled:
		return

	var map_rect:Rect2 = return_map_visual_rect(map_group[now_choose_map])
	character_dialogue_root.position = Vector2.ZERO
	character_dialogue_root.size = Vector2.ZERO
	var side_order:Array[String] = _dialogue_side_order()
	var count:int = side_order.size()
	if count <= 0:
		return

	var slots:Array = []
	if Game.is_timed_training_mode():
		var timed_layout:Dictionary = _character_dialogue_timed_layout(map_rect, side_order)
		var raw_slots:Variant = timed_layout.get("slots", [])
		if raw_slots is Array:
			slots = raw_slots
	else:
		# 普通模式：1 队占左半区；2 队左右各半；3 队及以上平均分满整条地图宽度。
		var slot_width:float = map_rect.size.x * 0.5 if count == 1 else map_rect.size.x / float(count)
		for i:int in range(count):
			slots.append(Rect2(
				Vector2(map_rect.position.x + float(i) * slot_width, map_rect.end.y + 3.0),
				Vector2(slot_width, character_dialogue_lane_height)
			))

	for i:int in range(count):
		if i >= slots.size():
			break
		var side_key:String = side_order[i]
		var label:Label = _ensure_character_dialogue_label(side_key)
		if label == null:
			continue
		var rect:Rect2 = slots[i]
		label.position = rect.position
		label.size = rect.size
		label.add_theme_font_size_override("font_size", character_dialogue_font_size)
		label.add_theme_color_override("font_color", return_side_color(side_key))


func _format_character_dialogue_prefix(_entry:Dictionary) -> String:
	# 地图下方只显示角色真正说出的台词，不再拼接人物名、冒号或其它前缀。
	return ""


func _format_character_dialogue(entry:Dictionary) -> String:
	var line_source:String = str(entry.get("line", ""))
	return _format_character_dialogue_prefix(entry) + Game.t(line_source)


func _cancel_character_dialogue_animation(side_key:String) -> void:
	var raw:Variant = _character_dialogue_tweens.get(side_key, null)
	if raw is Tween and is_instance_valid(raw):
		(raw as Tween).kill()
	_character_dialogue_tweens.erase(side_key)


func _refresh_character_dialogue_texts() -> void:
	for raw_side:Variant in _character_dialogue_entries.keys():
		var side_key:String = str(raw_side)
		var entry:Variant = _character_dialogue_entries.get(side_key, null)
		if not entry is Dictionary:
			continue
		var label:Label = _ensure_character_dialogue_label(side_key)
		if label != null:
			label.text = _format_character_dialogue(entry as Dictionary)
	_layout_character_dialogue_hud()


func show_character_dialogue(speaker:Variant, text:String, duration:float = -1.0) -> void:
	if not _is_character_dialogue_enabled():
		return
	if not is_instance_valid(speaker) or not (speaker is ball):
		return
	var source:ball = speaker as ball
	var root:ball = _dialogue_root_character(source)
	if root == null:
		return
	var side_key:String = return_ball_side_key(root)
	if side_key.is_empty():
		return
	if not _character_dialogue_seen_order.has(side_key):
		_character_dialogue_seen_order.append(side_key)

	var speaker_name:String = return_ball_display_name(source)
	var serial:int = int(_character_dialogue_serials.get(side_key, 0)) + 1
	_character_dialogue_serials[side_key] = serial
	_character_dialogue_entries[side_key] = {
		"speaker": speaker_name,
		"line": text,
		"serial": serial,
	}
	var label:Label = _ensure_character_dialogue_label(side_key)
	if label == null:
		return
	_cancel_character_dialogue_animation(side_key)
	label.text = _format_character_dialogue(_character_dialogue_entries[side_key] as Dictionary)
	label.visible_characters = -1
	label.modulate.a = 1.0
	label.visible = true
	_layout_character_dialogue_hud()
	_layout_timed_training_hud()

	var shown_duration:float = character_dialogue_default_duration if duration <= 0.0 else duration
	var clear_timer:SceneTreeTimer = get_tree().create_timer(maxf(shown_duration, 0.1))
	clear_timer.timeout.connect(_expire_character_dialogue.bind(side_key, serial), CONNECT_ONE_SHOT)


# 对话动画：说话时逐字出现，整句补齐后停留，再渐隐。
# 同阵营后来的台词会中止前一个动画并立即接管同一块区域。
func show_character_dialogue_animated(
	speaker:Variant,
	text:String,
	reveal_duration:float,
	hold_duration:float = 1.2,
	fade_duration:float = 0.65
) -> void:
	if not _is_character_dialogue_enabled():
		return
	if not is_instance_valid(speaker) or not (speaker is ball):
		return
	var source:ball = speaker as ball
	var root:ball = _dialogue_root_character(source)
	if root == null:
		return
	var side_key:String = return_ball_side_key(root)
	if side_key.is_empty():
		return
	if not _character_dialogue_seen_order.has(side_key):
		_character_dialogue_seen_order.append(side_key)

	var speaker_name:String = return_ball_display_name(source)
	var serial:int = int(_character_dialogue_serials.get(side_key, 0)) + 1
	_character_dialogue_serials[side_key] = serial
	var entry:Dictionary = {
		"speaker": speaker_name,
		"line": text,
		"serial": serial,
	}
	_character_dialogue_entries[side_key] = entry

	var label:Label = _ensure_character_dialogue_label(side_key)
	if label == null:
		return
	_cancel_character_dialogue_animation(side_key)
	label.text = _format_character_dialogue(entry)
	label.modulate.a = 1.0
	label.visible = true
	# 只显示台词，因此逐字动画从第 0 个字符开始。
	label.visible_characters = 0
	_layout_character_dialogue_hud()
	_layout_timed_training_hud()

	var tween:Tween = label.create_tween()
	_character_dialogue_tweens[side_key] = tween
	var reveal:float = maxf(reveal_duration, 0.0)
	if reveal > 0.0 and label.visible_characters < label.text.length():
		tween.tween_property(label, "visible_characters", label.text.length(), reveal).set_trans(Tween.TRANS_LINEAR)
	# 无论字符插值是否碰到整数边界，这一步都保证“语音说完时整句一定完整”。
	tween.tween_callback(_complete_character_dialogue_reveal.bind(side_key, serial))
	if hold_duration > 0.0:
		tween.tween_interval(hold_duration)
	if fade_duration > 0.0:
		tween.tween_property(label, "modulate:a", 0.0, fade_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(_expire_character_dialogue.bind(side_key, serial))


func _complete_character_dialogue_reveal(side_key:String, serial:int) -> void:
	if int(_character_dialogue_serials.get(side_key, -1)) != serial:
		return
	var raw:Variant = _character_dialogue_labels.get(side_key, null)
	if is_instance_valid(raw) and raw is Label:
		(raw as Label).visible_characters = -1


func _expire_character_dialogue(side_key:String, serial:int) -> void:
	if int(_character_dialogue_serials.get(side_key, -1)) != serial:
		return
	_character_dialogue_tweens.erase(side_key)
	_character_dialogue_entries.erase(side_key)
	var raw:Variant = _character_dialogue_labels.get(side_key, null)
	if is_instance_valid(raw) and raw is Label:
		var label:Label = raw as Label
		label.visible_characters = -1
		label.modulate.a = 1.0
		label.visible = false
	_layout_character_dialogue_hud()
	_layout_timed_training_hud()


func _clear_character_dialogues() -> void:
	for raw_tween:Variant in _character_dialogue_tweens.values():
		if raw_tween is Tween and is_instance_valid(raw_tween):
			(raw_tween as Tween).kill()
	_character_dialogue_tweens.clear()
	_character_dialogue_entries.clear()
	_character_dialogue_serials.clear()
	for raw:Variant in _character_dialogue_labels.values():
		if is_instance_valid(raw) and raw is Label:
			var label:Label = raw as Label
			label.visible_characters = -1
			label.modulate.a = 1.0
			label.visible = false


func _layout_timed_training_hud() -> void:
	if not is_instance_valid(timed_training_label) or not map_group.has(now_choose_map):
		return
	var map_rect:Rect2 = return_map_visual_rect(map_group[now_choose_map])
	var clock_rect:Rect2 = Rect2(
		Vector2(map_rect.position.x, map_rect.end.y + 3.0),
		Vector2(map_rect.size.x, 16.0)
	)
	if _is_character_dialogue_enabled() and Game.is_timed_training_mode():
		var side_order:Array[String] = _dialogue_side_order()
		if not side_order.is_empty():
			var timed_layout:Dictionary = _character_dialogue_timed_layout(map_rect, side_order)
			var raw_clock:Variant = timed_layout.get("clock", clock_rect)
			if raw_clock is Rect2:
				clock_rect = raw_clock
	timed_training_label.position = clock_rect.position
	timed_training_label.size = Vector2(clock_rect.size.x, 16.0)


func _format_timed_clock(seconds_left:float) -> String:
	# 后两位是百分之一秒：30 秒显示 30:00；超过一分钟后显示 01:30:00。
	var total_centiseconds:int = maxi(int(ceil(maxf(seconds_left,0.0) * 100.0)),0)
	var whole_seconds:int = int(total_centiseconds / 100)
	var centiseconds:int = total_centiseconds % 100
	if total_centiseconds < 6000:
		return "%02d:%02d" % [whole_seconds,centiseconds]
	var minutes:int = int(whole_seconds / 60)
	var seconds:int = whole_seconds % 60
	return "%02d:%02d:%02d" % [minutes,seconds,centiseconds]


func _refresh_timed_training_hud() -> void:
	if not is_instance_valid(timed_training_label):
		return
	timed_training_label.visible = false # Clock lives in the screen-space VS HUD.
	if not timed_training_label.visible:
		return
	if _timed_finished:
		return
	timed_training_label.text = _format_timed_clock(_timed_time_left)
	# 最后 5 秒从白色连续过渡到红色，而不是突然跳色。
	var danger:float = clampf((5.0 - _timed_time_left) / 5.0,0.0,1.0) if _timed_time_left <= 5.0 else 0.0
	var clock_color:Color = Color.WHITE.lerp(Color(1.0,0.12,0.12),danger)
	timed_training_label.add_theme_color_override("font_color",clock_color)
	_layout_timed_training_hud()


func _configure_timed_character(character:ball,setup_id:int,char_name:String) -> void:
	_timed_name_by_setup[setup_id] = char_name
	if not _timed_damage_by_setup.has(setup_id):
		_timed_damage_by_setup[setup_id] = 0.0
	if character.health_bar != null:
		character.health_bar.visible = false

	# 同一个 setup 重新生成时先清掉旧数字。
	var old_raw:Variant = _timed_damage_labels.get(setup_id,null)
	if old_raw is Label and is_instance_valid(old_raw):
		(old_raw as Label).queue_free()

	# Label 直接挂在 World，而不是人物节点下面：
	# 这样字号不会继承人物/特殊角色的缩放，所有角色的数字大小完全一致。
	# 字高与普通模式头顶血量数字一致；用高分辨率字号再整体缩小，镜头放大时也不发糊。
	var label := Label.new()
	label.name = "TimedDamageLabel_%d" % setup_id
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.add_theme_font_size_override("font_size",TIMED_LABEL_RENDER_FONT)
	label.add_theme_color_override("font_color",Color.WHITE)
	label.add_theme_color_override("font_outline_color",Color.BLACK)
	label.add_theme_constant_override("outline_size",int(round(TIMED_LABEL_RENDER_FONT * 0.14)))
	label.size = Vector2(TIMED_LABEL_RENDER_FONT * 6.0,TIMED_LABEL_RENDER_FONT * 1.4)
	label.scale = Vector2.ONE * (TIMED_LABEL_WORLD_FONT / float(TIMED_LABEL_RENDER_FONT))
	label.z_index = 1200
	add_child(label)

	_timed_damage_labels[setup_id] = label
	_timed_damage_label_character_ids[setup_id] = character.get_instance_id()
	character.tree_exiting.connect(_on_timed_character_exiting.bind(setup_id),CONNECT_ONE_SHOT)
	_update_timed_damage_label(setup_id)
	_layout_timed_damage_label(setup_id)


func _on_timed_character_exiting(setup_id:int) -> void:
	var raw_label:Variant = _timed_damage_labels.get(setup_id,null)
	if raw_label is Label and is_instance_valid(raw_label):
		(raw_label as Label).queue_free()
	_timed_damage_labels.erase(setup_id)
	_timed_damage_label_character_ids.erase(setup_id)


## 头顶数字的世界尺寸：字高对齐普通模式血量数字，底边离人物实际可见像素顶部 TIMED_LABEL_HEAD_GAP。
const TIMED_LABEL_WORLD_FONT:float = 8.0
const TIMED_LABEL_RENDER_FONT:int = 96
const TIMED_LABEL_HEAD_GAP:float = 2.5
var _timed_used_rect_cache:Dictionary = {} # Texture 实例 id -> 不透明像素范围（归一化 Rect2）


## 贴图不透明像素范围（0..1 归一化）。MC 渲染帧等素材四周留白很大，只按贴图矩形会把数字推得很远。
func _timed_texture_used_fraction(character:ball,texture:Texture2D) -> Rect2:
	var full := Rect2(0.0,0.0,1.0,1.0)
	if texture == null:
		return full
	var key:int = texture.get_instance_id()
	if _timed_used_rect_cache.has(key):
		return _timed_used_rect_cache[key]
	var fraction:Rect2 = full
	var source:Image = character._get_cached_after_image_source_image(texture) if character.has_method("_get_cached_after_image_source_image") else null
	if source != null and source.get_width() > 0 and source.get_height() > 0:
		var used:Rect2i = source.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			var image_size := Vector2(source.get_size())
			fraction = Rect2(Vector2(used.position) / image_size,Vector2(used.size) / image_size)
	_timed_used_rect_cache[key] = fraction
	return fraction


func _timed_character_visual_anchor_global(character:ball) -> Vector2:
	# 不能用 character.rect_size：它保存的是源贴图尺寸，很多 PNG 在游戏里会大幅缩放。
	# 这里取当前真正显示帧的不透明像素矩形，把四角变换到全局坐标，再取实际头顶。
	var visual:Node2D = character.image
	var rect := Rect2()
	var texture:Texture2D = null
	var flip_h:bool = false
	var flip_v:bool = false
	if visual is Sprite2D:
		var sprite:Sprite2D = visual as Sprite2D
		rect = sprite.get_rect()
		flip_h = sprite.flip_h
		flip_v = sprite.flip_v
		if not sprite.region_enabled and sprite.hframes == 1 and sprite.vframes == 1:
			texture = sprite.texture
	elif visual is AnimatedSprite2D:
		var animated:AnimatedSprite2D = visual as AnimatedSprite2D
		flip_h = animated.flip_h
		flip_v = animated.flip_v
		if animated.sprite_frames != null and animated.sprite_frames.has_animation(animated.animation):
			texture = animated.sprite_frames.get_frame_texture(animated.animation,animated.frame)
			if texture != null:
				var frame_size := Vector2(texture.get_size())
				var rect_pos:Vector2 = animated.offset
				if animated.centered:
					rect_pos -= frame_size * 0.5
				rect = Rect2(rect_pos,frame_size)

	if visual != null and is_instance_valid(visual) and rect.size.x > 0.001 and rect.size.y > 0.001:
		var used:Rect2 = _timed_texture_used_fraction(character,texture)
		if flip_h: used.position.x = 1.0 - used.end.x
		if flip_v: used.position.y = 1.0 - used.end.y
		rect = Rect2(rect.position + used.position * rect.size,used.size * rect.size)
		var points:Array[Vector2] = [
			rect.position,
			rect.position + Vector2(rect.size.x,0.0),
			rect.position + Vector2(0.0,rect.size.y),
			rect.end,
		]
		var min_x:float = INF
		var max_x:float = -INF
		var min_y:float = INF
		for point:Vector2 in points:
			var world_point:Vector2 = visual.to_global(point)
			min_x = minf(min_x,world_point.x)
			max_x = maxf(max_x,world_point.x)
			min_y = minf(min_y,world_point.y)
		return Vector2((min_x + max_x) * 0.5,min_y - TIMED_LABEL_HEAD_GAP)

	# 极少数没有 Sprite 的对象使用固定兜底，不再读取素材原始尺寸。
	return character.global_position + Vector2(0.0,-22.0)


func _layout_timed_damage_label(setup_id:int) -> void:
	var raw_label:Variant = _timed_damage_labels.get(setup_id,null)
	if not raw_label is Label or not is_instance_valid(raw_label):
		_timed_damage_labels.erase(setup_id)
		_timed_damage_label_character_ids.erase(setup_id)
		return

	var character_id:int = int(_timed_damage_label_character_ids.get(setup_id,0))
	if character_id <= 0 or not is_instance_id_valid(character_id):
		(raw_label as Label).queue_free()
		_timed_damage_labels.erase(setup_id)
		_timed_damage_label_character_ids.erase(setup_id)
		return

	var object:Object = instance_from_id(character_id)
	if not object is ball or not is_instance_valid(object):
		(raw_label as Label).queue_free()
		_timed_damage_labels.erase(setup_id)
		_timed_damage_label_character_ids.erase(setup_id)
		return

	var label:Label = raw_label as Label
	var anchor_global:Vector2 = _timed_character_visual_anchor_global(object as ball)
	var anchor_local:Vector2 = to_local(anchor_global)
	# 数字底边对齐锚点（人物实际头顶上方 TIMED_LABEL_HEAD_GAP）；Label 整体缩放，按缩放后的尺寸居中。
	label.position = anchor_local - Vector2(label.size.x * 0.5,label.size.y) * label.scale


func _layout_all_timed_damage_labels() -> void:
	var setup_ids:Array = _timed_damage_labels.keys()
	for raw_id:Variant in setup_ids:
		_layout_timed_damage_label(int(raw_id))


func _enforce_timed_character_hud() -> void:
	for node:Node in _battle_units_cache:
		if not node is ball:
			continue
		var character:ball = node as ball
		if not _is_primary_battle_character(character):
			continue
		if character.health_bar != null:
			character.health_bar.visible = false
	_update_all_timed_damage_labels() # 双端每帧同步头顶数字与排名颜色（客机只收分数快照）
	_layout_all_timed_damage_labels()


func _resolve_timed_source_setup_id(source:Node) -> int:
	if is_instance_valid(source):
		var identity:Dictionary=source.get_meta(BATTLE_LIFECYCLE_META,{})
		if int(identity.get("setup",-1))>=0: return int(identity.setup)
	var cursor:Node = source
	for _i in range(4):
		if cursor == null or not is_instance_valid(cursor):
			break
		if cursor.has_meta("battle_setup_id"):
			return int(cursor.get_meta("battle_setup_id"))
		if cursor is ball and (cursor as ball).Master != null and is_instance_valid((cursor as ball).Master):
			cursor = (cursor as ball).Master
		else:
			break
	return -1


## 计时模式进行中（含加赛）主战人物不会因扣血死亡；判负淘汰在 _timed_finished 之后执行，不受影响。
func timed_prevents_death(target:Node) -> bool:
	return (Game.is_timed_training_mode() and _timed_running and not _timed_finished
		and target is ball and _is_primary_battle_character(target as ball))


## 计时模式计分入口：ball.health setter 在确认实际生命损失后调用（所有扣血路径都经过它）。
## 分数 = 该参战 setup 受到的全部实际生命伤害，不区分来源（敌人、召唤物、环境、自伤、无来源扣血）。
## 只统计主战人物/延续单位本身；召唤物与杂物自己掉血不计。只由权威端累加，客机只收快照。
func on_timed_health_loss(target:ball,actual_health_loss:float) -> void:
	if not Game.is_timed_training_mode() or not is_multiplayer_authority() or not _timed_running or _timed_finished or actual_health_loss <= 0.0:
		return
	if target == null or not is_instance_valid(target) or not _is_primary_battle_character(target):
		return
	var setup_id:int = _resolve_timed_source_setup_id(target)
	if setup_id < 0:
		return
	_timed_damage_by_setup[setup_id] = float(_timed_damage_by_setup.get(setup_id,0.0)) + actual_health_loss
	_update_all_timed_damage_labels() # 一队分数变化会改变所有队伍的颜色排名
	if _timed_overtime: _finish_timed_training() # Settle as soon as a tie for the lowest score breaks.


func _update_timed_damage_label(setup_id:int,team_map:Variant=null,team_scores:Variant=null) -> void:
	var raw:Variant = _timed_damage_labels.get(setup_id,null)
	if raw is Label and is_instance_valid(raw):
		var label:Label = raw as Label
		# 数字是本人受到的伤害；颜色按所在队伍总受伤的排名由白到红。
		label.text = str(int(round(float(_timed_damage_by_setup.get(setup_id,0.0)))))
		var map:Dictionary = team_map if team_map is Dictionary else timed_team_map()
		var totals:Dictionary = team_scores if team_scores is Dictionary else timed_team_scores(map)
		var key:String = str(map.get(setup_id,""))
		var color:Color = timed_heat_color(timed_team_heat(key,totals)) if not key.is_empty() else Color.WHITE
		if not label.has_theme_color_override("font_color") or not label.get_theme_color("font_color").is_equal_approx(color):
			label.add_theme_color_override("font_color",color)


func _update_all_timed_damage_labels() -> void:
	if _timed_damage_labels.is_empty():
		return
	var map:Dictionary = timed_team_map()
	var totals:Dictionary = timed_team_scores(map)
	for raw_id:Variant in _timed_damage_labels.keys():
		_update_timed_damage_label(int(raw_id),map,totals)


## 计时模式的队伍划分：setup_id -> 队伍键。有 Team 的布阵为 "team:队名"，没有 Team 的角色各自成队 "solo_setup:id"
## （与 _victory_side_key_for_character / _configured_manual_victory_side_count 相同）。
## 已从布阵删除且场上也没有人物的 setup 不计入。客机优先使用权威端快照。
func timed_team_map() -> Dictionary:
	if not is_multiplayer_authority() and not _timed_team_by_setup.is_empty():
		return _timed_team_by_setup
	var map:Dictionary = {}
	for raw_id:Variant in _timed_damage_by_setup.keys():
		var setup_id:int = int(raw_id)
		if setup_id < 0:
			continue
		var entry:Dictionary = _find_battle_setup_entry(setup_id)
		var key:String = ""
		if not entry.is_empty():
			var team_name:String = str(entry.get("team","")).strip_edges()
			key = "team:" + team_name if not team_name.is_empty() else "solo_setup:" + str(setup_id)
		else:
			var character:Variant = _timed_character_for_setup(setup_id)
			if character == null:
				continue
			key = _victory_side_key_for_character(character)
		if not key.is_empty():
			map[setup_id] = key
	if is_multiplayer_authority():
		_timed_team_by_setup = map
	return map


func _timed_character_for_setup(setup_id:int) -> Variant:
	for raw:Variant in _battle_units_cache:
		if is_instance_valid(raw) and raw is ball and raw.has_meta("battle_setup_id") and int(raw.get_meta("battle_setup_id")) == setup_id:
			return raw
	return null


## 队伍总受伤：队伍键 -> 全体队员（含已阵亡队员）受到的实际生命伤害之和。
func timed_team_scores(team_map:Variant=null) -> Dictionary:
	var map:Dictionary = team_map if team_map is Dictionary else timed_team_map()
	var totals:Dictionary = {}
	for raw_id:Variant in map.keys():
		var key:String = str(map[raw_id])
		totals[key] = float(totals.get(key,0.0)) + float(_timed_damage_by_setup.get(int(raw_id),0.0))
	return totals


## 受伤排名热度：0 = 受伤最少（白），1 = 受伤最多（红），中间队伍按名次均匀渐变。
## 按不同分值排名：同分同色；所有队伍分数相同（含开局全 0）时都为白色。
func timed_team_heat(team_key:String,team_scores:Variant=null) -> float:
	var totals:Dictionary = team_scores if team_scores is Dictionary else timed_team_scores()
	if not totals.has(team_key):
		return 0.0
	var levels:Array[float] = []
	for raw:Variant in totals.values():
		var value:float = float(raw)
		var seen:bool = false
		for level:float in levels:
			if absf(level - value) <= 0.001:
				seen = true
				break
		if not seen:
			levels.append(value)
	if levels.size() <= 1:
		return 0.0
	levels.sort()
	var own:float = float(totals[team_key])
	for i:int in range(levels.size()):
		if absf(levels[i] - own) <= 0.001:
			return float(i) / float(levels.size() - 1)
	return 0.0


static func timed_heat_color(heat:float) -> Color:
	return Color.WHITE.lerp(TIMED_HEAT_RED,clampf(heat,0.0,1.0))


func _sync_timed_match(delta:float,force:bool=false) -> void:
	if not is_multiplayer_authority() or not multiplayer.has_multiplayer_peer() or multiplayer.get_peers().is_empty(): return
	_timed_sync_elapsed+=maxf(delta,0.0)
	if not force and _timed_sync_elapsed<0.1: return
	_timed_sync_elapsed=0.0
	_timed_sync_sequence+=1
	_receive_timed_match.rpc(_timed_sync_sequence,_timed_time_left,_timed_damage_by_setup,_timed_running,_timed_finished,_timed_overtime,_timed_winner_setup,timed_team_map())
@rpc("authority","call_remote","reliable")
func _receive_timed_match(sequence:int,remaining:float,scores:Dictionary,running:bool,finished:bool,overtime:bool,winner:int,teams:Dictionary={}) -> void:
	if is_multiplayer_authority() or not Game.is_timed_training_mode() or sequence<=_timed_received_sequence: return
	_timed_received_sequence=sequence
	_timed_time_left=maxf(remaining,0.0)
	_timed_damage_by_setup=scores.duplicate()
	_timed_team_by_setup=teams.duplicate()
	_timed_running=running
	_timed_finished=finished
	_timed_overtime=overtime
	_timed_winner_setup=winner
	if finished: _victory_bell_played=true
	_refresh_timed_training_hud()

func _finish_timed_training() -> void:
	if _timed_finished or not is_multiplayer_authority(): return
	_timed_time_left=0.0
	# 按队伍判胜：队伍总受伤（含已阵亡队员挨过的伤害）最少的队伍获胜；没有 Team 的角色各自成队。
	# 候选队伍：至少一名队员仍在布阵名单中（或有在场人物）且家族存活/等待训练复活；
	# 全员已删除/彻底阵亡的队伍不能凭“少挨打”获胜。无队伍符合时退回全部队伍参与。
	var team_map:Dictionary = timed_team_map()
	var team_scores:Dictionary = timed_team_scores(team_map)
	var candidate_members:Dictionary = {} # 队伍键 -> Array（符合条件的队员 setup_id）
	for raw_id:Variant in _timed_damage_by_setup.keys():
		var candidate_id:int = int(raw_id)
		if not team_map.has(candidate_id): continue
		var listed:bool = not _find_battle_setup_entry(candidate_id).is_empty() or _battle_setup_character_exists(candidate_id)
		var alive:bool = _battle_family_alive(candidate_id) or _battle_setup_character_exists(candidate_id) or _training_respawn_pending.has(candidate_id)
		if listed and alive:
			var key:String = str(team_map[candidate_id])
			if not candidate_members.has(key): candidate_members[key] = []
			(candidate_members[key] as Array).append(candidate_id)
	# 兜底：没有队伍记录的 setup（既不在布阵名单也没有在场人物）按单人队伍、以自身分数参与。
	for raw_id:Variant in _timed_damage_by_setup.keys():
		if not team_map.has(int(raw_id)):
			team_scores["solo_setup:" + str(int(raw_id))] = float(_timed_damage_by_setup[raw_id])
	if candidate_members.is_empty():
		for raw_id:Variant in _timed_damage_by_setup.keys():
			var key:String = str(team_map.get(int(raw_id),"solo_setup:" + str(int(raw_id))))
			if not candidate_members.has(key): candidate_members[key] = []
			(candidate_members[key] as Array).append(int(raw_id))
	var best_score:float=INF
	var winners:Array[String]=[]
	for raw_key:Variant in candidate_members.keys():
		var team_key:String=str(raw_key)
		var score:float=float(team_scores.get(team_key,0.0))
		if score<best_score-0.001:
			best_score=score
			winners=[team_key]
		elif absf(score-best_score)<=0.001: winners.append(team_key)
	if winners.size()!=1:
		var first_overtime:bool=not _timed_overtime
		_timed_overtime=true
		_timed_running=true
		if first_overtime: _sync_timed_match(0.0,true)
		return
	_timed_finished=true
	_timed_running=false
	_timed_overtime=false
	_timed_start_armed=false
	var winner_team:String=winners[0]
	var winner_members:Array=(candidate_members[winner_team] as Array).duplicate()
	winner_members.sort()
	# 代表 setup：胜利 toast 通过它找到阵营键，多人队伍显示为“X色队伍获胜”。
	_timed_winner_setup=int(winner_members[0])
	for raw_id:Variant in _timed_damage_by_setup.keys():
		if str(team_map.get(int(raw_id),"solo_setup:" + str(int(raw_id)))) != winner_team: _timed_defeated_setups[int(raw_id)]=true
	_training_respawn_pending.clear()
	for unit:Node in _battle_units_cache.duplicate()+_ball_projectile_units.duplicate():
		if is_instance_valid(unit) and _timed_defeated_setups.has(_resolve_timed_source_setup_id(unit)):
			_eliminate_timed_defeated(unit)
	_trigger_victory_bell()
	for member:Variant in winner_members:
		_notify_battle_victory_for_setup(int(member))
	_sync_timed_match(0.0,true)
	notify_primary_battle_character_alive_changed()
	# Deliberately no SceneTree pause or disabled winner: death animations and victory movement continue.

func _eliminate_timed_defeated(unit:Node) -> void:
	if not is_instance_valid(unit) or unit.is_queued_for_deletion() or not _timed_finished: return
	if not _timed_defeated_setups.has(_resolve_timed_source_setup_id(unit)): return
	if not unit is ball: return
	var b:ball=unit
	if bool(b.get_meta("timed_verdict_death",false)): return
	b.set_meta("timed_verdict_death",true)
	# Existing forced-map-rule death policy skips multi-life/totem prevention, not normal combat hits.
	b.set_meta(&"__out_of_bounds_forced_death",true)
	b.Can_Attack=false
	b.Can_Skill=false
	b.apply_damage_disable(3600.0)
	b.block=0
	b.health=0
	if b.state_machine!=null: b.state_machine.current_state=ball.State.Die
	else: b.Die();b.queue_free()


#========================================================
# Boss 模式
#========================================================
func _find_training_boss_character() -> ball:
	var best:ball = null
	var best_health:float = -1.0
	for node:Node in _battle_units_cache:
		# 与人数检测保持一致：绝不能从 Reset 正在 queue_free 的旧角色里
		# 选出一个“Boss”来播放第二遍开场。
		if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if not node is ball:
			continue
		var candidate := node as ball
		if not _is_primary_battle_character(candidate):
			continue
		if not bool(candidate.get_meta("training_boss_is_boosted",false)):
			continue
		var score:float = float(candidate.Max_health)
		if best == null or score > best_health:
			best = candidate
			best_health = score
	return best


func _boss_intro_character_name(character:ball) -> String:
	if character == null or not is_instance_valid(character):
		return "BOSS"
	var setup_id:int = int(character.get_meta("battle_setup_id",-1))
	if setup_id >= 0:
		var entry:Dictionary = _find_battle_setup_entry(setup_id)
		var raw_name:String = str(entry.get("char",""))
		if not raw_name.is_empty():
			return Game.t(raw_name).replace("_"," ")
	var queued_name:String = str(character.get_meta("queue_character_name",""))
	if not queued_name.is_empty():
		return Game.t(queued_name).replace("_"," ")
	return str(character.name).replace("_"," ")


func _begin_boss_intro() -> void:
	if _boss_intro_playing:
		return
	var boss_character:ball = _find_training_boss_character()
	if boss_character == null:
		_restore_special_prestart_nodes()
		return

	_boss_intro_playing = true

	# Boss 出场音效由 boss_intro_overlay.gd 随机播放“鞭子1/2/3”。
	var overlay := BOSS_INTRO_OVERLAY_SCRIPT.new() as CanvasLayer
	if overlay == null:
		_boss_intro_playing = false
		_restore_special_prestart_nodes()
		return
	_boss_intro_overlay = overlay
	add_child(overlay)
	overlay.connect("finished",Callable(self,"_on_boss_intro_finished"),CONNECT_ONE_SHOT)

	var mult:float = float(boss_character.get_meta("training_boss_multiplier",Game.get_training_boss_multiplier()))
	var specialized:bool = bool(boss_character.get_meta("training_boss_specialized",false))
	overlay.call(
		"play_intro",
		boss_character,
		_boss_intro_character_name(boss_character),
		mult,
		specialized
	)


func _on_boss_intro_finished() -> void:
	_boss_intro_overlay = null
	_boss_intro_playing = false
	# 开场期间一直冻结战斗。黑幕退场后才真正允许双方行动。
	_restore_special_prestart_nodes()


func _boss_side_for_position(poi:Vector2) -> String:
	var map_rect:Rect2 = return_map_world_rect(map_group[now_choose_map])
	return "left" if poi.x < map_rect.get_center().x else "right"


func _boss_team_for_side(side:String) -> String:
	# Boss 模式只允许两个阵营。内部用固定 team id，避免工具栏当前选择的其他队伍混进来。
	return "__boss_left" if side == "left" else "__boss_right"


func _special_two_team_side(team:String, poi:Vector2) -> String:
	# 轮放/Boss 只认 Team0 与 Team1。没有明确选择队伍时才按放置点左右半场归队。
	var selected:String = team.strip_edges()
	if selected.is_empty():
		return _boss_side_for_position(poi)
	if Game.is_rotation_training_mode() and selected=="__rotation_left": return "left"
	if Game.is_rotation_training_mode() and selected=="__rotation_right": return "right"
	if selected == "Team0":
		return "left"
	if selected == "Team1":
		return "right"
	return ""


func can_place_character_for_team(team:String, poi:Vector2) -> bool:
	if not Game.is_rotation_training_mode() and not Game.is_boss_training_mode():
		return true
	return not _special_two_team_side(team, poi).is_empty()


func _queue_battle_mode_active() -> bool:
	return Game.is_rotation_training_mode() or (Game.is_boss_training_mode() and Game.is_training_boss_wheel_battle_enabled())


# Read-only series verdict: result bells also play between individual rounds.
func is_queue_battle_finished() -> bool:
	if not _queue_battle_mode_active(): return false
	if _rotation_transitioning or _rotation_clearing_round or not _rotation_pending_dead_sides.is_empty(): return false
	if _rotation_finished: return true
	if not _rotation_started: return false
	# Red exhaustion starts a new blue attempt in challenge mode, not a series end.
	if Game.is_rotation_training_mode() and Game.get_rotation_match_type()=="challenge": return false
	return not _rotation_side_has_contender("left") or not _rotation_side_has_contender("right")


func is_rotation_scene_transition_active() -> bool:
	return _queue_battle_mode_active() and _rotation_transitioning and (is_instance_valid(_rotation_door) or _rotation_combat_blocked)


func _queue_internal_team_for_side(side:String) -> String:
	if Game.is_boss_training_mode():
		return _boss_team_for_side(side)
	return "__rotation_" + side


func _queue_entry_for_record(record:Dictionary, side:String, position:Vector2) -> Dictionary:
	var entry:Dictionary = {
		"id": int(record.get("id",-1)),
		"team": _queue_internal_team_for_side(side),
		"char": str(record.get("char","")),
		"scene_path": str(record.get("scene_path","")),
		"x": position.x,
		"y": position.y,
	}
	if Game.is_boss_training_mode():
		entry["boss_side"] = side
		entry["boss_boost"] = side == Game.get_training_boss_side()
		entry["boss_specialization"] = Game.is_training_boss_specialization_enabled()
	return entry


func _queue_outside_spawn_position(side:String) -> Vector2:
	var map_rect:Rect2 = return_map_world_rect(map_group[now_choose_map])
	var inset:float = clampf(maxf(map_squeeze_rescue_distance, 32.0) * 0.75, 28.0, 48.0)
	var x:float = map_rect.position.x - inset if side == "left" else map_rect.end.x + inset
	return Vector2(x, map_rect.get_center().y)


func _animate_queue_reinforcement_into_map(character:ball, side:String) -> void:
	if character == null or not is_instance_valid(character):
		return
	# Wheel replacements visibly walk in; do not hide a 0.2-second rescue snap behind doors.
	var wheel:bool=(Game.is_rotation_training_mode() and Game.is_rotation_wheel_enabled()) or (Game.is_boss_training_mode() and Game.is_training_boss_wheel_battle_enabled())
	var planned:Vector2=character.get_meta("rotation_entry_target",_rotation_spawn_position(side))
	var target:Vector2=planned
	var map_node:Node=_current_map_node()
	if map_node!=null:
		target=_map_free_body_position(character,nearest_map_island_rect(planned,map_island_rects(map_node)),planned)
		var lane:Vector2=planned-character.global_position
		if lane.length_squared()>0.0001:
			var shift:Vector2=target-planned
			lane=lane.normalized()
			character.global_position+=shift-lane*shift.dot(lane)
	var seconds:float=clampf(character.global_position.distance_to(target)/maxf(character.Speed,40.0),0.65,3.0) if wheel else -1.0
	_animate_ball_back_inside_map(character,target,seconds)


func _apply_boss_training_scaling(character:ball, factor:float) -> void:
	if character == null or not is_instance_valid(character):
		return
	var mult:float = maxf(factor,1.0)
	# 在 add_child()/ready 之前修改导出属性，让 health 与 default_properties
	# 从一开始就读取强化后的基础值。
	character.Max_health = maxi(1,roundi(float(character.Max_health) * mult))
	character.Damage = maxi(1,roundi(float(character.Damage) * mult))
	if not character.has_meta("training_boss_base_speed"): character.set_meta("training_boss_base_speed",character.Speed)
	character.Speed = maxf(character.Speed * mult,0.0)
	character.Health_Restore = maxi(0,roundi(float(character.Health_Restore) * mult))
	character.max_block = maxi(0,roundi(float(character.max_block) * mult))
	character.max_energy = maxi(0,roundi(float(character.max_energy) * mult))
	# 冷却数值越小越强，因此按倍率除，而不是乘。
	if character.Attack_Cooling > 0.0:
		character.Attack_Cooling = maxf(character.Attack_Cooling / mult,0.01)
	if character.Skill_Cooling > 0.0:
		character.Skill_Cooling = maxf(character.Skill_Cooling / mult,0.01)
	character.set_meta("training_boss_multiplier",mult)


func _ensure_battle_random_started() -> void:
	if _battle_random_seed <= 0:
		_battle_random_seed = Game.make_battle_random_seed()
	if not Game.is_battle_random_active() or Game.current_battle_random_seed() != _battle_random_seed:
		_battle_random_seed = Game.begin_battle_random(_battle_random_seed)


func _battle_setup_index(setup_id:int) -> int:
	for index:int in range(_battle_setup.size()):
		if int(_battle_setup[index].get("id",-1)) == setup_id:
			return index
	return -1


func _store_initial_battle_direction(setup_id:int,value:Vector2,source:String) -> void:
	var index:int = _battle_setup_index(setup_id)
	if index < 0:
		return
	var entry:Dictionary = _battle_setup[index]
	entry["initial_direction_x"] = value.x
	entry["initial_direction_y"] = value.y
	entry["initial_direction_source"] = source
	_battle_setup[index] = entry


func _apply_or_record_initial_battle_direction(character:ball) -> void:
	if character == null or not is_instance_valid(character):
		return
	if character.has_meta(&"battle_initial_direction_processed"):
		return
	if not character.has_meta("battle_setup_id"):
		if character.direction == Vector2.ZERO:
			character.direction = return_random_dir()
		return

	var setup_id:int = int(character.get_meta("battle_setup_id"))
	var index:int = _battle_setup_index(setup_id)
	if index < 0:
		if character.direction == Vector2.ZERO:
			character.direction = return_random_dir()
		return
	var entry:Dictionary = _battle_setup[index]
	var has_saved:bool = entry.has("initial_direction_x") and entry.has("initial_direction_y")
	if has_saved:
		# 原局若由 World 的 return_random_dir() 生成方向，重演时仍消耗同一次全局随机调用，
		# 再写回保存值；这样后续 rand* 的序列不会因为“直接赋值”而整体错一位。
		if str(entry.get("initial_direction_source","")) == "world_random":
			return_random_dir()
		character.direction = Vector2(
			float(entry.get("initial_direction_x",0.0)),
			float(entry.get("initial_direction_y",0.0))
		)
	else:
		if character.direction == Vector2.ZERO:
			character.direction = return_random_dir()
			_store_initial_battle_direction(setup_id,character.direction,"world_random")
		else:
			_store_initial_battle_direction(setup_id,character.direction,"character_ready")
	character.set_meta(&"battle_initial_direction_processed",true)


func _remember_random_setup(setup_id:int,random_choice:bool) -> void:
	# Preserve provenance in both queues and setup snapshots without changing spawn APIs.
	if not random_choice: return
	for entries:Array in [_battle_setup,_rotation_rosters["left"],_rotation_rosters["right"]]:
		for index:int in range(entries.size() - 1,-1,-1):
			if int(entries[index].get("id",-1)) == setup_id:
				entries[index]["random_choice"] = true
				break


func create_char(team:String,char:String,poi:Vector2,rotation_round:int=-1,scene_path:String="",draft_serial:int=-1):
	var requested_round:int=rotation_selected_round if rotation_round<0 else clampi(rotation_round,0,999)
	var random_choice:bool = char == "random"
	if char == "random":
		char = return_random_char()
	# Preserve click order while cold resources load; reset cancels pending requests.
	if is_instance_valid(_mc_prewarmer) and (_mc_prewarmer.handles(char) or not _mc_pending_placements.is_empty()):
		var generation:int = _mc_placement_generation
		var request:int = _mc_next_placement
		_mc_next_placement += 1
		_mc_pending_placements.append(request)
		while _mc_pending_placements[0] != request or (_mc_prewarmer.handles(char) and not _mc_prewarmer.is_ready(char)):
			if _mc_prewarmer.has_failed(char):
				_mc_pending_placements.erase(request)
				return
			await get_tree().process_frame
			if not is_inside_tree() or generation != _mc_placement_generation: return
			if draft_serial >= 0 and not random_character_draft._valid(draft_serial):
				_mc_pending_placements.erase(request)
				return
		_mc_pending_placements.pop_front()
		var prepared:PackedScene = _mc_prewarmer.scenes.get(char)
		if prepared != null: _character_scene_cache[prepared.resource_path] = prepared
	var placement_id:int = _battle_setup_next_id
	if _development != null and _development.is_prebattle() and _development.is_default_character(char):
		# 默认分区人物（盔甲架等）是地图里的中立单位，不属于轮换名单。
		if not _has_character_scene_any(char):
			return
		_spawn_character_from_setup({"id":-1,"team":"","char":char,"x":poi.x,"y":poi.y,"development_neutral":true})
		return
	# 轮放/Boss 的队伍归属优先读取 Team0/Team1；未选队伍才按放置位置分左右。
	# 其他明确选择的队伍在这两个模式里无效，不能创建人物。
	if Game.is_rotation_training_mode() and not _restoring_battle_setup:
		var rotation_side:String = _special_two_team_side(team, poi)
		if rotation_side.is_empty():
			return
		_enqueue_rotation_character(team,char,poi,rotation_side,scene_path,requested_round)
		_remember_random_setup(placement_id,random_choice)
		return
	if Game.is_boss_training_mode() and Game.is_training_boss_wheel_battle_enabled() and not _restoring_battle_setup:
		var wheel_side:String = _special_two_team_side(team, poi)
		if wheel_side.is_empty():
			return
		_enqueue_rotation_character(team,char,poi,wheel_side,scene_path)
		_remember_random_setup(placement_id,random_choice)
		return
	if team == "random":
		team = control.return_random_team()
	if Game.is_timed_training_mode() and not _restoring_battle_setup:
		_enqueue_timed_character(team,char,poi,scene_path)
		_remember_random_setup(placement_id,random_choice)
		return
	if Game.is_boss_training_mode():
		var boss_side:String = _special_two_team_side(team, poi)
		if boss_side.is_empty():
			return
		team = _boss_team_for_side(boss_side)
	# 搜索框允许跨分类选人，因此这里不能只检查当前 Characters_Dic。
	# 只要完整角色索引里存在这个名字，就必须生成用户实际选中的角色。
	if not _has_character_scene_any(char):
		push_warning("无法创建角色，完整角色索引不存在: " + char)
		return

	_ensure_battle_random_started()
	var setup_id:int = _battle_setup_next_id
	_battle_setup_next_id += 1
	var entry:Dictionary = {
		"id": setup_id,
		"team": team,
		"char": char,
		"random_choice": random_choice,
		"scene_path": scene_path if not scene_path.is_empty() else character_scene_path(char),
		"x": poi.x,
		"y": poi.y,
	}
	if _development != null and _development.is_prebattle():
		entry = _development.normalize_manual_entry(entry)
	if Game.is_boss_training_mode():
		var side:String = "left" if team == _boss_team_for_side("left") else "right"
		entry["boss_side"] = side
		entry["boss_boost"] = side == Game.get_training_boss_side()
		entry["boss_specialization"] = Game.is_training_boss_specialization_enabled()
	if not _restoring_battle_setup:
		if _battle_setup.is_empty():
			_battle_setup_map = now_choose_map
		# 手动模式必须记录本局每一个玩家放下的角色。
		# 旧版只在 _battle_setup 为空时追加第一个角色，导致胜利判定永远看不到第二个阵营。
		_battle_setup.append(entry.duplicate(true))

	var placed:ball=_spawn_character_from_setup(entry)
	# Explicitly adding a real character ends the old free-mode result, even if it is an ally.
	# Failed placements / obstacles / summons do not restart a concluded contest.
	if is_instance_valid(placed) and _is_primary_battle_character(placed) and Game.get_training_mode_type()=="manual" and _victory_bell_played:
		_begin_manual_victory_encounter()


func _spawn_character_from_setup(entry:Dictionary) -> ball:
	var char_name:String = str(entry.get("char", ""))
	var char_scene:PackedScene = _get_character_scene_path(char_name,str(entry.get("scene_path","")))
	if char_scene == null:
		push_warning("无法加载角色场景: " + char_name)
		return null

	var spawned:Node2D = char_scene.instantiate() as Node2D
	if spawned == null:
		push_warning("角色/地形场景根节点不是 Node2D: " + char_name)
		return null
	# 可放置地形不是 ball：不设置 Team、生命、Boss 数值，也不登记为战斗单位。
	if spawned.is_in_group("PlaceableObstacle"):
		spawned.global_position = Vector2(float(entry.get("x",0.0)),float(entry.get("y",0.0)))
		var obstacle_id:int = int(entry.get("id",-1))
		spawned.set_meta("battle_setup_id",obstacle_id)
		# 仍记录位置供重演，但地形不能占用阵营席位或触发胜负判定。
		var setup_index:int = _battle_setup_index(obstacle_id)
		if setup_index >= 0:
			_battle_setup[setup_index]["kind"] = "obstacle"
			_battle_setup[setup_index]["team"] = ""
		add_child(spawned,true)
		return null
	if not spawned is ball:
		push_warning("场景不是战斗角色或可放置地形: " + char_name)
		spawned.free()
		return null
	_ensure_battle_random_started()
	var setup_id_for_seed:int = int(entry.get("id",-1))
	Game.reseed_battle_global("character_spawn:%d:%s" % [setup_id_for_seed,char_name])
	var new_char:ball = spawned as ball
	new_char.Team = str(entry.get("team", ""))
	new_char.global_position = Vector2(
		float(entry.get("x", 0.0)),
		float(entry.get("y", 0.0))
	)
	var development_placement:Dictionary = {}
	if _development != null and _development.is_prebattle():
		development_placement = _development.spawn_placement(entry,new_char.global_position)
		if not development_placement.is_empty():
			new_char.global_position = development_placement["position"]
	var setup_id:int = int(entry.get("id", -1))
	new_char.set_meta("battle_setup_id", setup_id)
	var boss_specialization_active:bool = false
	var boss_multiplier:float = 1.0
	if Game.is_boss_training_mode() and not bool(entry.get("development_neutral",false)):
		var entry_side:String = str(entry.get("boss_side",_boss_side_for_position(new_char.global_position)))
		var should_boost:bool = bool(entry.get("boss_boost",entry_side == Game.get_training_boss_side()))
		new_char.set_meta("training_boss_side",entry_side)
		new_char.set_meta("training_boss_is_boosted",should_boost)
		if should_boost:
			boss_multiplier = Game.get_training_boss_multiplier()
			_apply_boss_training_scaling(new_char,boss_multiplier)

			# “Boss特殊化”与数值倍率是两层独立机制。关闭时只保留原来的倍率强化；
			# 开启时，仅对明确声明拥有 Boss 专属形态的角色调用特殊化钩子。
			var specialization_enabled:bool = bool(
				entry.get("boss_specialization",Game.is_training_boss_specialization_enabled())
			)
			new_char.set_meta("training_boss_specialization_enabled",specialization_enabled)
			if specialization_enabled and new_char.has_training_boss_specialization():
				boss_specialization_active = true
				new_char.set_meta("training_boss_specialized",true)
				new_char.prepare_training_boss_specialization(boss_multiplier)
			else:
				new_char.set_meta("training_boss_specialized",false)

	new_char.name = Game.return_random_name(new_char)
	add_child(new_char,true)
	if _development != null:
		_development.on_spawn(new_char,entry,development_placement)

	# post-ready 钩子：允许专属 Boss 形态安全访问 @onready 节点、切换图片/动画/技能。
	if boss_specialization_active and is_instance_valid(new_char):
		new_char.activate_training_boss_specialization(boss_multiplier)

	if Game.is_timed_training_mode() and new_char.Type == ball.Ball_Type.Ball and setup_id >= 0:
		_configure_timed_character(new_char,setup_id,char_name)

	# 只对玩家布阵产生的正常人物启用“自然死亡 -> 原位复活”。
	# Reset 会先清空 _battle_setup；鼠标删除会先 forget_battle_setup_node()，
	# 因此这两种明确移除不会被复活。
	if Game.is_training_mode() and not Game.is_rotation_training_mode() and new_char.Type == ball.Ball_Type.Ball and setup_id >= 0:
		new_char.tree_exiting.connect(
			_on_training_character_tree_exiting.bind(new_char, setup_id),
			CONNECT_ONE_SHOT
		)
	# 每次布阵完成后切回该 setup 的固定运行时随机流。原局与左键重演最终都会落到同一条流上。
	Game.reseed_battle_global("battle_runtime_after_spawn:%d" % setup_id)
	return new_char


func _find_battle_setup_entry(setup_id:int) -> Dictionary:
	for entry:Dictionary in _battle_setup:
		if int(entry.get("id", -1)) == setup_id:
			return entry.duplicate(true)
	return {}


func _battle_setup_character_exists(setup_id:int) -> bool:
	for node:Node in _battle_units_cache:
		if node == null or not is_instance_valid(node):
			continue
		if node.has_meta("battle_setup_id") and int(node.get_meta("battle_setup_id")) == setup_id:
			return true
	return false


func _on_training_character_tree_exiting(character:ball, setup_id:int) -> void:
	if not Game.is_training_mode() or _timed_finished:
		return
	if character == null or not is_instance_valid(character):
		return
	# 只有真正死亡才复活。普通鼠标删除通常仍有生命，即使忘记 setup 的调用被改坏也不会误复活。
	if int(character.health) > 0:
		return
	if _find_battle_setup_entry(setup_id).is_empty():
		return
	if _training_respawn_pending.has(setup_id):
		return

	var token:int = int(Time.get_ticks_usec())
	_training_respawn_pending[setup_id] = token
	call_deferred("_training_respawn_after_delay", setup_id, token)


func _training_respawn_after_delay(setup_id:int, token:int) -> void:
	await get_tree().create_timer(maxf(training_respawn_delay,0.1)).timeout
	if not Game.is_training_mode() or _timed_finished:
		_training_respawn_pending.erase(setup_id)
		return
	if int(_training_respawn_pending.get(setup_id, -1)) != token:
		return
	var entry:Dictionary = _find_battle_setup_entry(setup_id)
	if entry.is_empty() or _battle_setup_character_exists(setup_id):
		_training_respawn_pending.erase(setup_id)
		return
	_spawn_character_from_setup(entry)
	_training_respawn_pending.erase(setup_id)


func _prepare_character_preview_visual(char:Node2D) -> void:
	if char == null:
		return

	# 当前项目中这两个方法只负责从 res:// 加载角色纹理，不启动技能、计时器或生成物。
	# 因为 Ghost 不进树，主动调用它们可以补上原本要到角色 _ready() 才加载的立绘。
	if char.has_method("_auto_load_textures"):
		char.call("_auto_load_textures")
	elif char.has_method("_auto_load_texture"):
		char.call("_auto_load_texture")

	# 允许以后某个角色显式提供预览纹理；没有该方法时按项目现有的常用
	# “正常/成年/本体”等导出属性自动选择，不需要每增加一个角色就改 World。
	var preview_texture:Texture2D = null
	if char.has_method("get_preview_texture"):
		var custom_preview:Variant = char.call("get_preview_texture")
		if custom_preview is Texture2D:
			preview_texture = custom_preview as Texture2D

	if preview_texture == null:
		var available_properties:Dictionary = {}
		for property_info in char.get_property_list():
			var property_name:String = str(property_info.get("name",""))
			if not property_name.is_empty():
				available_properties[property_name] = true

		var preferred_texture_properties:PackedStringArray = PackedStringArray([
			"normal_texture",
			"adult_texture",
			"body_texture",
			"clown_normal_texture",
			"friendly_texture",
			"attraction_texture",
			"graze_texture"
		])
		for property_name:String in preferred_texture_properties:
			if not available_properties.has(property_name):
				continue
			var value:Variant = char.get(property_name)
			if value is Texture2D:
				preview_texture = value as Texture2D
				break

	if preview_texture == null:
		return

	var sprite := char.get_node_or_null("Graphics/Image") as Sprite2D
	if sprite == null:
		return
	sprite.texture = preview_texture
	sprite.visible = true

func create_ghost_ball():
	# Missing previews are retried next frame by Game; never block on an active loader.
	if is_instance_valid(_mc_prewarmer) and _mc_prewarmer.handles(now_choose_char):
		if not _mc_prewarmer.is_ready(now_choose_char): return null
		var prepared:PackedScene = _mc_prewarmer.scenes.get(now_choose_char)
		if prepared != null: _character_scene_cache[prepared.resource_path] = prepared
	# 搜索结果可能来自当前分类之外，预览也必须走完整角色索引。
	var char_scene:PackedScene = _get_character_scene_any(now_choose_char)
	if char_scene == null:
		return null
	var char:Node2D = char_scene.instantiate() as Node2D
	if char == null: return null

	# 预览对象不会加入 SceneTree，所以角色根节点的 _ready() 不会执行。
	# 一些角色把正式立绘留到 _ready() 里才自动加载，若这里不先补上，
	# Ghost 会直接复制 ball.tscn 的默认占位图。先只执行“安全的纹理加载”并选择
	# 正常/本体立绘，再做 CharacterAutoFit，保证预览和真正放下后的角色一致。
	_prepare_character_preview_visual(char)

	# 预览角色没有真正进树，因此 CharacterAutoFit._ready() 也不会自动执行。
	# 在复制视觉节点前手动跑一次与正式角色完全相同的自动适配。
	var auto_fit := char.get_node_or_null("CharacterAutoFit")
	if auto_fit != null and auto_fit.has_method("apply_fit"):
		auto_fit.call("apply_fit")

	var graphics := char.get_node_or_null("Graphics") as Node2D
	var source_image:Node2D = null
	if graphics != null:
		var sprite := graphics.get_node_or_null("Image") as Sprite2D
		if sprite != null and sprite.texture != null:
			source_image = sprite
		else:
			var animated := graphics.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
			if animated != null:
				source_image = animated

	if source_image == null:
		char.free()
		return null

	# 用一个轻量 Node2D 做预览根节点，完整保留 Ball -> Graphics -> Image
	# 的局部缩放/旋转，而不是只粗暴地 image.scale *= char.scale。
	var ghost_root := Node2D.new()
	ghost_root.name = now_choose_char
	# Ghost 是“放置预览”而不是真实角色。真实角色越界仍被 z=90 的地图外遮罩裁掉；
	# 预览提高到 z=95，让鼠标移到地图外测试带时仍能看到准备放置的位置。
	ghost_root.z_as_relative = false
	ghost_root.z_index = 95
	ghost_root.scale = char.scale
	ghost_root.rotation = char.rotation
	ghost_root.skew = char.skew

	var image := source_image.duplicate() as Node2D
	image.name = "PreviewImage"
	image.transform = graphics.transform * source_image.transform
	image.modulate = Color(1.0,1.0,1.0,0.439)
	if image is AnimatedSprite2D:
		(image as AnimatedSprite2D).pause()

	ghost_root.add_child(image)
	add_child(ghost_root)
	char.free()
	return ghost_root
	
func create_character_preview(character_name:String,scene_path:String = "",attach_to_world:bool = true) -> Node2D:
	# Missing previews are retried next frame by Game; never block on an active loader.
	if scene_path.is_empty() and is_instance_valid(_mc_prewarmer) and _mc_prewarmer.handles(character_name):
		if not _mc_prewarmer.is_ready(character_name): return null
		var prepared:PackedScene = _mc_prewarmer.scenes.get(character_name)
		if prepared != null: _character_scene_cache[prepared.resource_path] = prepared
	# 搜索结果可能来自当前分类之外，预览也必须走完整角色索引。
	var char_scene:PackedScene = _get_character_scene_path(character_name,scene_path)
	if char_scene == null:
		return null
	var char:Node2D = char_scene.instantiate() as Node2D
	if char == null: return null

	# 预览对象不会加入 SceneTree，所以角色根节点的 _ready() 不会执行。
	# 一些角色把正式立绘留到 _ready() 里才自动加载，若这里不先补上，
	# Ghost 会直接复制 ball.tscn 的默认占位图。先只执行“安全的纹理加载”并选择
	# 正常/本体立绘，再做 CharacterAutoFit，保证预览和真正放下后的角色一致。
	_prepare_character_preview_visual(char)

	# 预览角色没有真正进树，因此 CharacterAutoFit._ready() 也不会自动执行。
	# 在复制视觉节点前手动跑一次与正式角色完全相同的自动适配。
	var auto_fit := char.get_node_or_null("CharacterAutoFit")
	if auto_fit != null and auto_fit.has_method("apply_fit"):
		auto_fit.call("apply_fit")

	var graphics := char.get_node_or_null("Graphics") as Node2D
	var source_image:Node2D = null
	if graphics != null:
		var sprite := graphics.get_node_or_null("Image") as Sprite2D
		if sprite != null and sprite.texture != null:
			source_image = sprite
		else:
			var animated := graphics.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
			if animated != null:
				source_image = animated

	if source_image == null:
		char.free()
		return null

	# 用一个轻量 Node2D 做预览根节点，完整保留 Ball -> Graphics -> Image
	# 的局部缩放/旋转，而不是只粗暴地 image.scale *= char.scale。
	var ghost_root := Node2D.new()
	ghost_root.name = character_name
	# Ghost 是“放置预览”而不是真实角色。真实角色越界仍被 z=90 的地图外遮罩裁掉；
	# 预览提高到 z=95，让鼠标移到地图外测试带时仍能看到准备放置的位置。
	ghost_root.z_as_relative = false
	ghost_root.z_index = 95
	ghost_root.scale = char.scale
	ghost_root.rotation = char.rotation
	ghost_root.skew = char.skew

	var image := source_image.duplicate() as Node2D
	image.name = "PreviewImage"
	image.transform = graphics.transform * source_image.transform
	image.modulate = Color(1.0,1.0,1.0,0.439 if attach_to_world else 1.0)
	if image is AnimatedSprite2D:
		(image as AnimatedSprite2D).pause()

	ghost_root.add_child(image)
	if attach_to_world: add_child(ghost_root)
	char.free()
	return ghost_root
	
#全局使用
func return_can_create_char() -> bool:
	if random_character_draft.playing: return false
	if random_character_draft.is_enabled() and not random_character_draft.can_place(): return false
	return not(not Game.Game_Settings.Creating or not control.is_set_team())
	
func return_spawner() -> MultiplayerSpawner:
	return spawner
