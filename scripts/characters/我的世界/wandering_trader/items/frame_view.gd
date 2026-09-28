extends Node2D
## 物品展示框 under the trader: the vanilla item frame model seen from the front (leather back =
## block/item_frame, 1-texel birch plank border) with his current item in it at half size, like
## the item frame renders items. Only shown while he holds an item (user rule 2026-09-29), small.
## World-space (top_level) so it never inherits the unit scale or the sprite flip; visibility still
## follows the trader.
const CATALOG = preload("res://scripts/characters/我的世界/wandering_trader/items/catalog.gd")
const SIZE:float = 8.0
@export var offset:Vector2 = Vector2(0.0,14.0)
var trader_ref:WeakRef
var kind:StringName = &""
var _pop:float = 0.0

func setup(trader:Node2D) -> void:
	trader_ref = weakref(trader)
	top_level = true
	z_as_relative = false
	z_index = 60
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	name = "TraderItemFrame"

func show_item(new_kind:StringName) -> void:
	if new_kind != kind: _pop = 1.0
	kind = new_kind
	queue_redraw()

func _process(delta:float) -> void:
	var trader:Variant = trader_ref.get_ref() if trader_ref != null else null
	if not is_instance_valid(trader):
		queue_free()
		return
	global_position = (trader as Node2D).global_position + offset
	var shown:bool = float(trader.get(&"health")) > 0.0 and not kind.is_empty()
	if shown and trader.has_method(&"frame_outside_wall"): shown = bool(trader.call(&"frame_outside_wall",global_position))
	self_modulate.a = 1.0 if shown else 0.0
	if _pop > 0.0:
		_pop = maxf(_pop - delta*4.0,0.0)
		queue_redraw()

func _draw() -> void:
	var s:float = SIZE*(1.0 + 0.25*_pop)
	var half:float = s*0.5
	var px:float = s/12.0
	draw_texture_rect_region(CATALOG.TEX_FRAME_WOOD,Rect2(-half,-half,s,s),Rect2(2,2,12,12))
	draw_texture_rect_region(CATALOG.TEX_FRAME_BACK,Rect2(-half + px,-half + px,s - px*2.0,s - px*2.0),Rect2(3,3,10,10))
	var icon:Texture2D = CATALOG.icon(kind)
	if icon != null:
		var item:float = s*0.7
		draw_texture_rect(icon,Rect2(-item*0.5,-item*0.5,item,item),false)
