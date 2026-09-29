extends RefCounted

const GRASS_TOP:Texture2D = preload("res://Images/effects/我的世界/草方块背景/grass_block_top.png")
const OAK_LOG_TOP:Texture2D = preload("res://Images/effects/我的世界/草方块背景/oak_log_top.png")
const SAND:Texture2D = preload("res://Images/effects/我的世界/草方块背景/sand.png")
const SANDSTONE_TOP:Texture2D = preload("res://Images/effects/我的世界/草方块背景/sandstone_top.png")
const STONE_BRICKS:Texture2D = preload("res://Images/effects/我的世界/草方块背景/stone_bricks.png")
const DEEPSLATE_BRICKS:Texture2D = preload("res://Images/effects/我的世界/草方块背景/deepslate_bricks.png")
const NETHERRACK:Texture2D = preload("res://Images/effects/我的世界/草方块背景/netherrack.png")
const NETHER_BRICKS:Texture2D = preload("res://Images/effects/我的世界/草方块背景/nether_bricks.png")
const END_STONE:Texture2D = preload("res://Images/effects/我的世界/草方块背景/end_stone.png")
const PURPUR_PILLAR_TOP:Texture2D = preload("res://Images/effects/我的世界/草方块背景/purpur_pillar_top.png")
const SANDSTONE_GRID:Texture2D = preload("res://Images/effects/我的世界/草方块背景/sandstone_top.png")
const BLACKSTONE_GRID:Texture2D = preload("res://Images/effects/我的世界/草方块背景/blackstone_top.png")
const NETHER_BRICK_GRID:Texture2D = preload("res://Images/effects/我的世界/草方块背景/nether_bricks.png")
const PURPUR_GRID:Texture2D = preload("res://Images/effects/我的世界/草方块背景/purpur_block.png")

const OPTIONS:Array[String] = ["blue","grass","sand","stone","nether","end","summit"]
const DEFAULT_STYLE := "blue"

# 每个主题都分成三块：地图内部底图、单格外墙、地图外整体视差图案。
# floor/wall 保留原版16×16贴图；外部视差恢复旧棋盘，或直接使用原版方块贴图复制。
const THEMES:Dictionary = {
	"summit": {
		"tiled": true,
		"floor": STONE_BRICKS,
		"floor_modulate": Color(0.78,0.73,0.62),
		"wall": preload("res://assets/maps/summit/chiseled_stone_bricks.png"),
		"grid_normal": Color(0.075,0.115,0.17),
		"grid_dark": Color(0.075,0.115,0.17),
		"grid_accent": Color(0,0,0,0),
	},
	"blue": {
		"tiled": false,
		"grid_style": 0,
		"grid_normal": Color(0.0,0.5882353,0.87058824,1.0),
		"grid_dark": Color(0.0,0.27,0.48,0.18),
		"grid_accent": Color(1.0,1.0,1.0,0.12),
		"grid_cell": 64.0,
		"grid_parallax": 0.32,
	},
	"grass": {
		"tiled": true,
		"floor": GRASS_TOP,
		"floor_modulate": Color("91bd59"),
		"wall": OAK_LOG_TOP,
		"wall_modulate": Color.WHITE,
		"grid_style": 0,
		"grid_normal": Color(0.0,0.5882353,0.87058824,1.0),
		"grid_dark": Color(0.0,0.27,0.48,0.18),
		"grid_accent": Color(1.0,1.0,1.0,0.12),
		"grid_cell": 64.0,
		"grid_parallax": 0.32,
	},
	"sand": {
		"tiled": true,
		"floor": SAND,
		"floor_modulate": Color.WHITE,
		"wall": SANDSTONE_TOP,
		"wall_modulate": Color.WHITE,
		"grid_style": 5,
		"grid_texture": SANDSTONE_GRID,
		"grid_normal": Color(0.878,0.839,0.667,1.0),
		"grid_dark": Color(0.67,0.58,0.38,0.18),
		"grid_accent": Color(1.0,0.96,0.77,0.16),
		"grid_cell": 72.0,
		"grid_parallax": 0.30,
	},
	"stone": {
		"tiled": true,
		"floor": STONE_BRICKS,
		"floor_modulate": Color(0.88,0.88,0.88,1.0),
		"wall": DEEPSLATE_BRICKS,
		"wall_modulate": Color.WHITE,
		"grid_style": 5,
		"grid_texture": BLACKSTONE_GRID,
		"grid_normal": Color(0.165,0.141,0.165,1.0),
		"grid_dark": Color(0.055,0.045,0.08,0.18),
		"grid_accent": Color(0.30,0.25,0.33,0.16),
		"grid_cell": 64.0,
		"grid_parallax": 0.22,
	},
	"nether": {
		"tiled": true,
		"floor": NETHERRACK,
		"floor_modulate": Color.WHITE,
		"wall": NETHER_BRICKS,
		"wall_modulate": Color.WHITE,
		"grid_style": 5,
		"grid_texture": NETHER_BRICK_GRID,
		"grid_normal": Color(0.173,0.086,0.102,1.0),
		"grid_dark": Color(0.055,0.018,0.028,0.18),
		"grid_accent": Color(0.27,0.10,0.12,0.16),
		"grid_cell": 64.0,
		"grid_parallax": 0.20,
	},
	"end": {
		"tiled": true,
		"floor": END_STONE,
		"floor_modulate": Color.WHITE,
		"wall": PURPUR_PILLAR_TOP,
		"wall_modulate": Color.WHITE,
		"grid_style": 5,
		"grid_texture": PURPUR_GRID,
		"grid_normal": Color(0.667,0.494,0.667,1.0),
		"grid_dark": Color(0.21,0.12,0.23,0.18),
		"grid_accent": Color(0.82,0.66,0.84,0.16),
		"grid_cell": 72.0,
		"grid_parallax": 0.18,
	},
}

static func normalize(key:String) -> String:
	# Retired courtyard3d / unknown saved keys safely fall back to the original blue map.
	return key if THEMES.has(key) else DEFAULT_STYLE

static func theme(key:String) -> Dictionary:
	return THEMES[normalize(key)]

static func tiled(key:String) -> bool:
	return bool(theme(key).get("tiled",false))

static func floor_texture(key:String) -> Texture2D:
	return theme(key).get("floor",GRASS_TOP)

static func wall_texture(key:String) -> Texture2D:
	return theme(key).get("wall",OAK_LOG_TOP)

static func grid_texture(key:String) -> Texture2D:
	var value:Variant = theme(key).get("grid_texture",null)
	return value if value is Texture2D else null
