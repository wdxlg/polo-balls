extends Node2D
const DIR:String = "res://Images/characters/我的世界/bucket/"
const AIR:Texture2D = preload(DIR + "air.png")
const AIR_BURSTING:Texture2D = preload(DIR + "air_bursting.png")
const AIR_EMPTY:Texture2D = preload(DIR + "air_empty.png")
const BUBBLES:int = 10
const ICON:float = 8.0
const GAP:float = 0.0
const LIFT:float = 6.0
const FADE_SECONDS:float = 0.6
const BURST_SECONDS:float = 0.25

var field:Node
var _shown:Dictionary = {}


func _ready() -> void:
	name = "MCOxygenBubbles"
	top_level = true
	z_as_relative = false
	z_index = 98
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	global_position = Vector2.ZERO


func _process(delta:float) -> void:
	if not is_instance_valid(field): return
	var view:Dictionary = field.call("air_view")
	for id:Variant in view.keys():
		var data:Dictionary = view[id]
		var unit:Node = data.get("unit")
		if not is_instance_valid(unit): continue
		var entry:Dictionary = _shown.get(id,{"alpha":0.0,"bubbles":BUBBLES,"burst":-1,"burst_left":0.0})
		entry["unit"] = weakref(unit)
		var ratio:float = clampf(float(data.get("ratio",1.0)),0.0,1.0)
		var full:int = int(ceil(ratio * float(BUBBLES) - 0.0001))
		if full < int(entry.bubbles):
			entry["burst"] = full
			entry["burst_left"] = BURST_SECONDS
		entry["bubbles"] = full
		entry["visible_wanted"] = bool(data.get("wet",false)) or ratio < 0.999
		_shown[id] = entry
	for id:Variant in _shown.keys():
		var entry:Dictionary = _shown[id]
		var unit:Variant = (entry.unit as WeakRef).get_ref() if entry.get("unit") is WeakRef else null
		if not is_instance_valid(unit) or (unit.get("health") != null and float(unit.health) <= 0.0):
			_shown.erase(id)
			continue
		var wanted:bool = bool(entry.get("visible_wanted",false)) and view.has(id)
		entry["alpha"] = 1.0 if wanted else maxf(float(entry.alpha) - delta / FADE_SECONDS,0.0)
		entry["burst_left"] = maxf(float(entry.burst_left) - delta,0.0)
		if float(entry.alpha) <= 0.0 and not wanted: _shown.erase(id)
	queue_redraw()


func visible_units() -> Array:
	var result:Array = []
	for entry:Dictionary in _shown.values():
		var unit:Variant = (entry.unit as WeakRef).get_ref() if entry.get("unit") is WeakRef else null
		if is_instance_valid(unit) and float(entry.alpha) > 0.0: result.append(unit)
	return result


func bubbles_for(unit:Node) -> int:
	var entry:Dictionary = _shown.get(unit.get_instance_id(),{})
	return int(entry.get("bubbles",BUBBLES))


func alpha_for(unit:Node) -> float:
	var entry:Dictionary = _shown.get(unit.get_instance_id(),{})
	return float(entry.get("alpha",0.0))


static func head_top(unit:Node2D) -> float:
	var top:float = unit.global_position.y - 40.0
	var shape:CollisionShape2D = unit.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null and shape.shape != null: top = (shape.global_transform * shape.shape.get_rect()).position.y
	var bar:Node = unit.get_node_or_null("Health_Bar")
	if bar is CanvasItem and (bar as CanvasItem).is_visible_in_tree():
		var rect_node:Node = bar.get_node_or_null("TextureRect")
		if rect_node is Control: top = minf(top,(rect_node as Control).get_global_rect().position.y)
	return top


func _draw() -> void:
	for entry:Dictionary in _shown.values():
		var unit:Variant = (entry.unit as WeakRef).get_ref() if entry.get("unit") is WeakRef else null
		if not is_instance_valid(unit) or float(entry.alpha) <= 0.0: continue
		var width:float = float(BUBBLES) * ICON + float(BUBBLES - 1) * GAP
		var origin:Vector2 = Vector2((unit as Node2D).global_position.x - width * 0.5,head_top(unit) - LIFT - ICON)
		var tint := Color(1,1,1,float(entry.alpha))
		var full:int = int(entry.bubbles)
		for i:int in range(BUBBLES):
			var texture:Texture2D = AIR_EMPTY
			if i < full: texture = AIR
			elif i == int(entry.burst) and float(entry.burst_left) > 0.0: texture = AIR_BURSTING
			draw_texture_rect(texture,Rect2(origin + Vector2(float(BUBBLES - 1 - i) * (ICON + GAP),0.0),Vector2(ICON,ICON)),false,tint)
