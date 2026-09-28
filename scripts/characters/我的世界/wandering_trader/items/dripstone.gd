extends "res://scripts/characters/我的世界/wandering_trader/items/placed.gd"
## 滴水石锥: a pointed dripstone spike growing out of the wall the trader touched (or out of the
## floor if he never reached a wall in time). Neutral: anyone who touches the spike, the trader
## and his llamas included, takes damage and a small push away from the wall.
const DAMAGE:float = 18.0
const COOLDOWN:float = 0.6
const LENGTH:float = 14.0
const KNOCKBACK:float = 10.0
var normal:Vector2 = Vector2.UP
var hits:int = 0

func _placed() -> void:
	z_index = 3
	normal = data.get("normal",Vector2.UP)
	normal = normal.normalized() if normal.length_squared() > 0.000001 else Vector2.UP
	rotation = normal.angle() + PI*0.5 # the texture's tip points up (-y)
	sound(&"item_dripstone_place",-1.0)
	CRUMBS.spawn(self,global_position,CRUMBS.texture_source(CATALOG.TEX_DRIPSTONE_TIP),10,normal,45.0,2.0,0.5,1.1,true)

## Points on the spike's axis the body test uses (base -> tip).
func axis_points() -> Array[Vector2]:
	var points:Array[Vector2] = []
	for t:float in [2.0,5.0,8.0,11.0,LENGTH]:
		points.append(global_position + normal*t)
	return points

func touching(unit:ball) -> bool:
	var body:Rect2 = CATALOG.body_rect(unit).grow(1.5)
	for point:Vector2 in axis_points():
		if body.has_point(point): return true
	return false

func _tick(_delta:float) -> void:
	if not authoritative: return
	for unit:ball in CATALOG.units(self):
		if age < 0.8 and unit.get_instance_id() == int(data.get("grace",0)): continue # he just set it down
		if not touching(unit) or not ready_to_hit(unit,COOLDOWN): continue
		var actual:float = CATALOG.hurt(trader(),unit,DAMAGE,global_position + normal*LENGTH*0.6,false)
		if actual > 0.0: hits += 1
		if is_instance_valid(unit) and unit.health > 0 and unit.can_receive_negative_effects():
			unit.apply_knockback(normal,KNOCKBACK*unit.get_negative_effect_ratio(),220.0,0.0,0.0,{"source":trader(),"lock_control":false})

func _removed() -> void:
	CRUMBS.spawn(self,global_position + normal*6.0,CRUMBS.texture_source(CATALOG.TEX_DRIPSTONE_TIP),12,normal,40.0,2.0,0.55,PI,true,3.0)

func _draw() -> void:
	# Base on the wall surface, tip LENGTH out along the normal (local -y after rotation).
	draw_texture_rect(CATALOG.TEX_DRIPSTONE_TIP,Rect2(-8,-16,16,16),false)
