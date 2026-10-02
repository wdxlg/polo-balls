extends "res://scripts/characters/我的世界/wandering_trader/items/placed.gd"
## 仙人掌: a native single-block 3D cactus (mc_block_3d.gd, one map cell; the vanilla body is
## 14/16 wide) placed behind the trader a while after he leaves the wall. Solid obstacle for
## everyone (layer 1 StaticBody2D, units bounce off it).
## Neutral: touching ANY of its four faces hurts anyone, the trader and his llamas included,
## and pushes them straight out of that face.
const BLOCK = preload("res://scripts/effects/我的世界/mc_block_3d.gd")
const SIZE_RATIO:float = 14.0/16.0
var body_size:float = 14.0 # collision width = 14/16 of one map cell
const DAMAGE:float = 8.0
const COOLDOWN:float = 0.5
const SIDE_REACH:float = 2.5
const KNOCKBACK:float = 8.0
var body:StaticBody2D
var block:Node2D
var hits:int = 0

func _placed() -> void:
	z_index = 3
	var cell:float = BLOCK.map_cell(self)
	body_size = cell*SIZE_RATIO
	body = StaticBody2D.new()
	body.name = "CactusBody"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta(&"wt_item_obstacle",true)
	body.add_to_group(&"WTItemObstacle")
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(body_size,body_size)
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	block = BLOCK.create(&"cactus",cell)
	body.add_child(block)
	sound(&"item_wool_place",-1.0)
	CRUMBS.spawn(self,global_position,CRUMBS.texture_source(CATALOG.TEX_CACTUS_SIDE),10,Vector2.UP,30.0,2.0,0.45,PI,true,body_size*0.4)

func rect() -> Rect2:
	return Rect2(global_position - Vector2(body_size,body_size)*0.5,Vector2(body_size,body_size))

## Outward normal of the face the unit touches (LEFT/RIGHT/UP/DOWN), or ZERO when not touching.
## The face is the axis with the smaller relative penetration, so corners resolve to one face.
func face_touched(unit:ball) -> Vector2:
	var r:Rect2 = rect()
	var b:Rect2 = CATALOG.body_rect(unit)
	if not r.grow(SIDE_REACH).intersects(b): return Vector2.ZERO
	var offset:Vector2 = b.get_center() - r.get_center()
	var reach:Vector2 = (r.size + b.size)*0.5
	if absf(offset.x)/maxf(reach.x,0.001) >= absf(offset.y)/maxf(reach.y,0.001):
		return Vector2(-1.0 if offset.x < 0.0 else 1.0,0.0)
	return Vector2(0.0,-1.0 if offset.y < 0.0 else 1.0)

func _tick(_delta:float) -> void:
	if not authoritative: return
	for unit:ball in CATALOG.units(self):
		var normal:Vector2 = face_touched(unit)
		if normal == Vector2.ZERO or not ready_to_hit(unit,COOLDOWN): continue
		var r:Rect2 = rect()
		var point := Vector2(clampf(unit.global_position.x,r.position.x,r.end.x),clampf(unit.global_position.y,r.position.y,r.end.y))
		if normal.x != 0.0: point.x = r.position.x if normal.x < 0.0 else r.end.x
		else: point.y = r.position.y if normal.y < 0.0 else r.end.y
		var actual:float = CATALOG.hurt(trader(),unit,DAMAGE,point,false)
		if actual > 0.0: hits += 1
		if is_instance_valid(unit) and unit.health > 0 and unit.can_receive_negative_effects():
			unit.apply_knockback(normal,KNOCKBACK*unit.get_negative_effect_ratio(),200.0,0.0,0.0,{"source":trader(),"lock_control":false})

func _removed() -> void:
	sound(&"item_wool_place",-3.0)
	CRUMBS.spawn(self,global_position,CRUMBS.texture_source(CATALOG.TEX_CACTUS_SIDE),18,Vector2.UP,45.0,2.4,0.6,PI,true,body_size*0.45)
