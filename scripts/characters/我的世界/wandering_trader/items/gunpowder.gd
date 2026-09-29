extends "res://scripts/characters/我的世界/wandering_trader/items/placed.gd"
## 火药: a little gunpowder pile on the floor. After a short arming time the first enemy that steps
## on it sets it off (TNT-style white blink + fuse hiss), then it explodes: 50 damage to every
## enemy of the trader in the blast radius, knockback away from the centre, vanilla explosion
## particles and sound. Only enemies trigger or take damage. Drawn 12 px (user rule 2026-09-29:
## bigger and easier to spot) and it smokes lightly (white -> off-white); once triggered the smoke
## pours out white -> black (gunpowder_smoke.gd).
const EXPLOSION = preload("res://scripts/characters/我的世界/wandering_trader/items/explosion_fx.gd")
const SMOKE = preload("res://scripts/characters/我的世界/wandering_trader/items/gunpowder_smoke.gd")
const DRAW_SIZE:float = 12.0
const ARM_TIME:float = 0.4
const TRIGGER_HALF:float = 6.0
const FUSE_TIME:float = 0.2
const DAMAGE:float = 50.0
const RADIUS:float = 22.0
const KNOCKBACK:float = 30.0
var triggered:bool = false
var exploded:bool = false
var _fuse:float = 0.0
var smoke:Node2D

func _placed() -> void:
	sound(&"item_sand_place",-2.0)
	call_deferred(&"_start_smoke")

func _start_smoke() -> void:
	if not _gone and smoke == null: smoke = SMOKE.attach(self,global_position)

func _removed() -> void:
	if smoke != null and is_instance_valid(smoke): smoke.call(&"release")

func _tick(delta:float) -> void:
	if triggered:
		_fuse += delta
		if _fuse >= FUSE_TIME: explode()
		return
	if not authoritative or age < ARM_TIME: return
	var pad := Rect2(global_position - Vector2(TRIGGER_HALF,TRIGGER_HALF),Vector2(TRIGGER_HALF,TRIGGER_HALF)*2.0)
	for unit:ball in CATALOG.units(self):
		if hostile(unit) and CATALOG.body_rect(unit).intersects(pad):
			trigger()
			return

func trigger() -> void:
	if triggered: return
	triggered = true
	_fuse = 0.0
	if smoke == null or not is_instance_valid(smoke): _start_smoke()
	if smoke != null: smoke.call(&"ignite")
	sound(&"item_fuse",-4.0)
	var owner_trader:Node2D = trader()
	if authoritative and owner_trader != null and owner_trader.has_method(&"wt_item_event"): owner_trader.call(&"wt_item_event",name,&"trigger")

func explode() -> void:
	if exploded: return
	exploded = true
	var owner_trader:Node2D = trader()
	EXPLOSION.spawn(self,global_position,RADIUS)
	if authoritative:
		sound(&"item_explode",0.0)
		for unit:ball in CATALOG.units(self):
			if not hostile(unit): continue
			var rect:Rect2 = CATALOG.body_rect(unit)
			var nearest:Vector2 = global_position.clamp(rect.position,rect.end)
			if nearest.distance_to(global_position) > RADIUS: continue
			var actual:float = CATALOG.hurt(owner_trader,unit,DAMAGE,global_position,true)
			if actual > 0.0 and owner_trader != null: owner_trader.set(&"gunpowder_hits",int(owner_trader.get(&"gunpowder_hits")) + 1)
			if is_instance_valid(unit) and unit.health > 0 and unit.can_receive_negative_effects():
				var away:Vector2 = ball.body_point(unit,global_position) - global_position
				if away.length_squared() < 0.01: away = Vector2.UP
				unit.apply_knockback(away.normalized(),KNOCKBACK*unit.get_negative_effect_ratio(),360.0,0.0,0.0,{"source":owner_trader,"lock_control":true})
	expire()

func _draw() -> void:
	var tex:Texture2D = CATALOG.icon(CATALOG.GUNPOWDER)
	var blink:bool = triggered and int(_fuse*20.0) % 2 == 0
	var h:float = DRAW_SIZE*0.5
	draw_set_transform(Vector2(0,h*0.55),0.0,Vector2(1.0,0.35))
	draw_circle(Vector2.ZERO,h*0.9,Color(0,0,0,0.3)) # contact shadow so the pile reads on dark floors
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
	draw_texture_rect(tex,Rect2(-h,-h,DRAW_SIZE,DRAW_SIZE),false,Color(1.8,1.8,1.8) if blink else Color.WHITE)
