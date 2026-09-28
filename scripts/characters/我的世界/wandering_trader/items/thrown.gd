extends Node2D
## Thrown item flying on a parabola (ground track + height, with a ground shadow).
## * 粘液球 (slime ball): aimed at an enemy with lead. It hits the first enemy its ground track
##   touches near the end of the arc: damage, knockback along the throw and Slowness; walls and
##   obstacles on the way bounce it back once. Every hit (person or obstacle) splashes slime
##   (item particles of the slime ball, vanilla ITEM_SLIME) with the small slime squish sound.
## * 干草块 (hay bale): spins while it flies to one of his llamas (the target is followed) and
##   heals it on arrival, with hay crumbs and heart particles.
const CATALOG = preload("res://scripts/characters/我的世界/wandering_trader/items/catalog.gd")
const CRUMBS = preload("res://scripts/characters/我的世界/wandering_trader/items/crumbs.gd")
const POTION_EFFECTS = preload("res://scripts/effects/我的世界/女巫药水效果.gd")
const SLIME_DAMAGE:float = 10.0
const SLIME_KNOCKBACK:float = 32.0
const SLIME_SLOW_TIME:float = 3.0
const HAY_HEAL:float = 70.0
var kind:StringName = CATALOG.SLIME_BALL
var trader_ref:WeakRef
var target_ref:WeakRef
var authoritative:bool = false
var from:Vector2
var to:Vector2
var flight:float = 0.6
var apex:float = 18.0
var t:float = 0.0
var ground:Vector2
var height:float = 0.0
var spin:float = 0.0
var bounced:bool = false
var done:bool = false
var result:StringName = &""

static func launch(trader:Node2D,item:StringName,start:Vector2,target:Node2D,aim_point:Vector2,is_authority:bool,flight_time:float,node_name:String) -> Node2D:
	var tree:SceneTree = trader.get_tree()
	var parent:Node = tree.current_scene if tree.current_scene != null else tree.root
	var shot:Node2D = (load("res://scripts/characters/我的世界/wandering_trader/items/thrown.gd") as Script).new()
	shot.name = node_name
	shot.kind = item
	shot.trader_ref = weakref(trader)
	shot.target_ref = weakref(target) if target != null else null
	shot.authoritative = is_authority
	shot.from = start
	shot.to = aim_point
	shot.ground = start
	shot.flight = maxf(flight_time,0.1)
	shot.apex = clampf(start.distance_to(aim_point)*0.28,10.0,34.0)
	shot.z_as_relative = false
	shot.z_index = 50
	shot.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shot.add_to_group(&"MCWanderingTraderItem")
	shot.add_to_group(&"BattleTransient")
	parent.add_child(shot)
	shot.global_position = start
	return shot

func trader() -> Node2D:
	var node:Variant = trader_ref.get_ref() if trader_ref != null else null
	return node as Node2D if is_instance_valid(node) else null

func target() -> Node2D:
	var node:Variant = target_ref.get_ref() if target_ref != null else null
	if not is_instance_valid(node) or float(node.get(&"health")) <= 0.0: return null
	return node as Node2D

func _physics_process(delta:float) -> void:
	if done: return
	if trader() == null:
		queue_free()
		return
	if CATALOG.paused(self): return
	if kind == CATALOG.HAY and target() != null: to = target().global_position # hay follows its llama
	t = minf(t + delta/flight,1.0)
	var previous:Vector2 = ground
	ground = from.lerp(to,t)
	height = 4.0*apex*t*(1.0 - t)
	spin += delta*(10.0 if kind == CATALOG.HAY else 4.0)
	global_position = ground
	queue_redraw()
	if kind == CATALOG.SLIME_BALL:
		if not bounced and _wall_between(previous,ground): return
		if t > 0.55 and _hit_enemy(): return
	if t >= 1.0: _arrive()

## Wall / obstacle on the ground track: slime splash and one bounce back.
func _wall_between(a:Vector2,b:Vector2) -> bool:
	if a.distance_squared_to(b) < 0.0001: return false
	var query := PhysicsRayQueryParameters2D.create(a,b,1)
	query.collide_with_areas = false
	var hit:Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return false
	var point:Vector2 = hit.position
	var normal:Vector2 = hit.normal
	splash(point,normal,false)
	if authoritative and trader() != null: trader().set(&"slime_wall_bounces",int(trader().get(&"slime_wall_bounces")) + 1)
	bounced = true
	var left:Vector2 = (to - point)
	from = point + normal*1.0
	to = from + left.bounce(normal)*0.5
	ground = from
	t = 0.5
	flight *= 0.5
	return true

func _hit_enemy() -> bool:
	if not authoritative: return false
	var owner_trader:Node2D = trader()
	for unit:ball in CATALOG.units(self):
		if not CATALOG.enemy_of(owner_trader,unit): continue
		if not CATALOG.body_rect(unit).grow(2.0).has_point(ground): continue
		var heading:Vector2 = (to - from).normalized() if to.distance_squared_to(from) > 0.01 else Vector2.RIGHT
		var actual:float = CATALOG.hurt(owner_trader,unit,SLIME_DAMAGE,ground,true)
		if is_instance_valid(unit) and unit.health > 0 and unit.can_receive_negative_effects():
			unit.apply_knockback(heading,SLIME_KNOCKBACK*unit.get_negative_effect_ratio(),300.0,0.0,0.0,{"source":owner_trader,"lock_control":true})
			POTION_EFFECTS.apply_effect(unit,"slowness",owner_trader,1,SLIME_SLOW_TIME)
		owner_trader.set(&"slime_hits",int(owner_trader.get(&"slime_hits")) + 1)
		result = &"hit"
		_relay(&"hit",ground)
		splash(ground,-heading,true)
		finish()
		return true
	return false

func _arrive() -> void:
	if kind == CATALOG.HAY:
		var llama:Node2D = target()
		if authoritative and llama != null and llama.has_method(&"heal"):
			var healed:int = int(llama.call(&"heal",HAY_HEAL))
			var owner_trader:Node2D = trader()
			if owner_trader != null: owner_trader.set(&"hay_healed",int(owner_trader.get(&"hay_healed")) + healed)
		result = &"healed" if llama != null else &"landed"
		hay_land(ground)
	else:
		result = &"landed"
		splash(ground,Vector2.UP,false)
	finish()

## Remote copies mirror the authority's slime hit so the splash shows where it really hit.
func _relay(event:StringName,point:Vector2) -> void:
	var owner_trader:Node2D = trader()
	if authoritative and owner_trader != null and owner_trader.has_method(&"wt_item_event"): owner_trader.call(&"wt_item_event",name,event,point)

func remote_event(event:StringName,point:Vector2) -> void:
	if done: return
	if event == &"hit":
		splash(point,Vector2.UP,true)
		finish()

func splash(point:Vector2,normal:Vector2,person:bool) -> void:
	CRUMBS.spawn(self,point,CRUMBS.texture_source(CATALOG.icon(CATALOG.SLIME_BALL)),14 if person else 10,normal,55.0,2.0,0.55,1.3,false)
	var owner_trader:Node2D = trader()
	if authoritative and owner_trader != null:
		owner_trader.call(&"wt_sound",&"item_slime_attack" if person else &"item_slime_small",-2.0,point)

func hay_land(point:Vector2) -> void:
	CRUMBS.spawn(self,point,CRUMBS.texture_source(CATALOG.TEX_HAY_SIDE),14,Vector2.UP,45.0,2.2,0.55,PI,true,4.0)
	var owner_trader:Node2D = trader()
	if owner_trader != null:
		if authoritative: owner_trader.call(&"wt_sound",&"item_grass_place",-1.0,point)
		if owner_trader.has_method(&"wt_hearts"): owner_trader.call(&"wt_hearts",point + Vector2(0,-14))

func finish() -> void:
	done = true
	queue_free()

func _draw() -> void:
	var lift := Vector2(0.0,-height)
	var shadow_w:float = 6.0*(1.0 - 0.4*height/maxf(apex,1.0))
	draw_circle(Vector2(0,1),shadow_w*0.5,Color(0,0,0,0.28))
	if kind == CATALOG.HAY:
		draw_set_transform(lift,spin,Vector2.ONE)
		draw_texture_rect(CATALOG.TEX_HAY_SIDE,Rect2(-5,-5,10,10),false)
		draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
	else:
		draw_set_transform(lift,spin,Vector2.ONE)
		draw_texture_rect(CATALOG.icon(CATALOG.SLIME_BALL),Rect2(-4,-4,8,8),false)
		draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
