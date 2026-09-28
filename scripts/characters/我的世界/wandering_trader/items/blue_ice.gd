extends "res://scripts/characters/我的世界/wandering_trader/items/placed.gd"
## 蓝冰: a 3x3 patch of blue ice blocks on the floor. Enemies of the trader standing on it build
## up extra speed along their own movement (ice_boost.gd); the boost decays after they leave it
## and hurts them if they hit a wall before it has worn off. The trader's side is unaffected.
const ICE_BOOST = preload("res://scripts/characters/我的世界/wandering_trader/items/ice_boost.gd")
const BLOCK:float = 11.0 # one block at character scale (the trader is ~2 blocks / 22 px tall)
const BLOCKS:int = 3 # user rule 2026-09-29: 3x3
const HALF:float = BLOCK*BLOCKS*0.5
var touched:int = 0

func _placed() -> void:
	life = 12.0
	# Floor layer (placed items default to absolute z 2, above the characters): relative to World
	# (z -2) this is -3, above the map tiles (-4) and under every character (-2).
	z_as_relative = true
	z_index = -1
	sound(&"item_stone_place",-2.0)

func rect() -> Rect2:
	return Rect2(global_position - Vector2(HALF,HALF),Vector2(HALF,HALF)*2.0)

func _tick(_delta:float) -> void:
	if not authoritative: return
	var area:Rect2 = rect()
	for unit:ball in CATALOG.units(self):
		if not CATALOG.enemy_of(trader(),unit): continue
		if area.has_point(unit.global_position):
			if ICE_BOOST.touch(unit,trader()) != null: touched += 1

func _removed() -> void:
	CRUMBS.spawn(self,global_position,CRUMBS.texture_source(CATALOG.TEX_BLUE_ICE),24,Vector2.UP,40.0,2.4,0.6,PI,true,HALF*0.8)

func _draw() -> void:
	var fade:float = clampf((life - age)/0.5,0.0,1.0)
	for x:int in range(BLOCKS):
		for y:int in range(BLOCKS):
			draw_texture_rect(CATALOG.TEX_BLUE_ICE,Rect2(-HALF + x*BLOCK,-HALF + y*BLOCK,BLOCK,BLOCK),false,Color(1,1,1,fade))
