extends "res://scripts/characters/我的世界/wandering_trader/items/placed.gd"
## 仙人掌: a cactus block (14/16 wide like the vanilla block) placed behind the trader a while after
## he leaves the wall. Solid obstacle for everyone (layer 1 StaticBody2D, units bounce off it).
## Neutral: touching its LEFT or RIGHT side hurts anyone, the trader and his llamas included;
## the top and bottom faces are harmless.
const SIZE:float = 14.0
const DAMAGE:float = 8.0
const COOLDOWN:float = 0.5
const SIDE_REACH:float = 2.5
const KNOCKBACK:float = 8.0
var body:StaticBody2D
var hits:int = 0

func _placed() -> void:
	life = 16.0
	z_index = 3
	body = StaticBody2D.new()
	body.name = "CactusBody"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta(&"wt_item_obstacle",true)
	body.add_to_group(&"WTItemObstacle")
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(SIZE,SIZE)
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	sound(&"item_wool_place",-1.0)
	CRUMBS.spawn(self,global_position,CRUMBS.texture_source(CATALOG.TEX_CACTUS_SIDE),10,Vector2.UP,30.0,2.0,0.45,PI,true,SIZE*0.4)

func rect() -> Rect2:
	return Rect2(global_position - Vector2(SIZE,SIZE)*0.5,Vector2(SIZE,SIZE))

## -1 = touching the left face, +1 = the right face, 0 = none (top/bottom contact is harmless).
func side_touched(unit:ball) -> int:
	var r:Rect2 = rect()
	var b:Rect2 = CATALOG.body_rect(unit)
	var inner := Rect2(r.position.x,r.position.y + 1.0,r.size.x,r.size.y - 2.0)
	if b.end.y <= inner.position.y or b.position.y >= inner.end.y: return 0
	if b.end.x >= r.position.x - SIDE_REACH and b.end.x <= r.position.x + 2.0: return -1
	if b.position.x <= r.end.x + SIDE_REACH and b.position.x >= r.end.x - 2.0: return 1
	return 0

func _tick(_delta:float) -> void:
	if not authoritative: return
	for unit:ball in CATALOG.units(self):
		var side:int = side_touched(unit)
		if side == 0 or not ready_to_hit(unit,COOLDOWN): continue
		var r:Rect2 = rect()
		var point := Vector2(r.position.x if side < 0 else r.end.x,clampf(unit.global_position.y,r.position.y,r.end.y))
		var actual:float = CATALOG.hurt(trader(),unit,DAMAGE,point,false)
		if actual > 0.0: hits += 1
		if is_instance_valid(unit) and unit.health > 0 and unit.can_receive_negative_effects():
			unit.apply_knockback(Vector2(float(side),0.0),KNOCKBACK*unit.get_negative_effect_ratio(),200.0,0.0,0.0,{"source":trader(),"lock_control":false})

func _removed() -> void:
	sound(&"item_wool_place",-3.0)
	CRUMBS.spawn(self,global_position,CRUMBS.texture_source(CATALOG.TEX_CACTUS_SIDE),18,Vector2.UP,45.0,2.4,0.6,PI,true,SIZE*0.45)

func _draw() -> void:
	draw_texture_rect_region(CATALOG.TEX_CACTUS_SIDE,Rect2(-SIZE*0.5,-SIZE*0.5,SIZE,SIZE),Rect2(1,0,14,16))
