extends Node2D
## 一张附魔台的计数显示（World 下的 top_level 画布，绝对 z 90：在人物之上、血条之下）。
## 每个被符文命中的目标左上角显示原版附魔台等级绿色的罗马数字 I–X；多张附魔台同时计数时
## 按附魔台名字顺序向下错开。计数到 X 时数字消失，原位置浮起获得的附魔名（正面灰色、负面红色），
## 1.2 秒内上升淡出。纯表现，各端按附魔台同步的计数各自绘制。
const NUMBER_FONT:Font = preload("res://fonts/Mojangles.ttf")
const TEXT_FONT:Font = preload("res://fonts/BoutiqueBitmap9x9_1.92.ttf")
const CATALOG = preload("res://scripts/effects/我的世界/mc_enchantment_catalog.gd")
const NUMBER_COLOR:Color = Color("80ff20")
const OVERLAY_Z:int = 90
const FONT_SIZE:int = 10
## 罗马数字按 COUNTER_RASTER 字号栅格化后缩到 COUNTER_SIZE 世界像素高，比附魔名小一号且保持清晰。
const COUNTER_SIZE:float = 7.0
const COUNTER_RASTER:int = 16
const POPUP_SECONDS:float = 1.2
var table_ref:WeakRef = null
var _popups:Array[Dictionary] = []

func _ready() -> void:
	top_level = true
	z_as_relative = false
	z_index = OVERLAY_Z
	global_position = Vector2.ZERO
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

static func roman(value:int) -> String:
	return CATALOG.display_level(clampi(value,1,3999))

func table() -> Node:
	var node:Variant = table_ref.get_ref() if table_ref != null else null
	return node if is_instance_valid(node) else null

## 目标左上角（世界坐标），同一目标上第 slot 个附魔台的计数再往下错开一行。
static func anchor_for(target:Node2D,slot:int) -> Vector2:
	var radius:float = float(target.call("get_crowd_separation_radius_world")) if target.has_method("get_crowd_separation_radius_world") else 12.0
	return target.global_position + Vector2(-radius,-radius) + Vector2(0.0,float(slot)*(COUNTER_SIZE+1.0))

func _slot_for(target:Node) -> int:
	var owner_table:Node = table()
	if owner_table == null or not owner_table.is_inside_tree(): return 0
	var tables:Array = []
	for other:Node in owner_table.get_tree().get_nodes_in_group(&"MCEnchantingTable"):
		if other.has_method("counter_of") and int(other.call("counter_of",target)) > 0: tables.append(str(other.name))
	tables.sort()
	return maxi(tables.find(str(owner_table.name)),0)

func popup(target:Node2D,kind:String,level:int) -> void:
	if not is_instance_valid(target): return
	_popups.append({"ref":weakref(target),"point":anchor_for(target,_slot_for(target)),"kind":kind,"level":level,"age":0.0})
	queue_redraw()

func _process(delta:float) -> void:
	var owner_table:Node = table()
	var running:bool = owner_table != null and owner_table.has_method("is_combat_runtime_active") and bool(owner_table.call("is_combat_runtime_active"))
	if running:
		for entry:Dictionary in _popups: entry.age = float(entry.age) + delta
		_popups = _popups.filter(func(entry:Dictionary) -> bool: return float(entry.age) < POPUP_SECONDS)
	queue_redraw()

func _english() -> bool:
	var game:Node = get_node_or_null("/root/Game")
	return game != null and str(game.get("current_locale")).begins_with("en")

func _draw_text(font:Font,point:Vector2,text:String,color:Color,size:int = FONT_SIZE,scale_factor:float = 1.0) -> void:
	# 原版 GUI 文字阴影：同色 1/4 亮度，右下偏 1 个字体像素。
	draw_set_transform(point,0.0,Vector2.ONE*scale_factor)
	var shadow:float = maxf(float(size)/8.0,1.0)
	draw_string(font,Vector2(shadow,shadow),text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,Color(color.r*0.25,color.g*0.25,color.b*0.25,color.a))
	draw_string(font,Vector2.ZERO,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)

func _draw() -> void:
	var owner_table:Node = table()
	if owner_table == null: return
	var counters:Dictionary = owner_table.get("counters")
	for key:Variant in counters:
		var entry:Dictionary = counters[key]
		var target:Node2D = (entry.ref as WeakRef).get_ref() as Node2D if entry.get("ref") is WeakRef else null
		if not is_instance_valid(target) or not target.visible or int(target.get("health")) <= 0: continue
		var count:int = int(entry.get("count",0))
		if count <= 0: continue
		_draw_text(NUMBER_FONT,anchor_for(target,_slot_for(target)),roman(count),NUMBER_COLOR,COUNTER_RASTER,COUNTER_SIZE/float(COUNTER_RASTER))
	var english:bool = _english()
	for entry:Dictionary in _popups:
		var progress:float = clampf(float(entry.age)/POPUP_SECONDS,0.0,1.0)
		var level:int = int(entry.level)
		var color:Color = CATALOG.level_color(level) if level < 0 else Color("ffffff")
		color.a = 1.0 - progress*progress
		var text:String = CATALOG.display_line(str(entry.kind),level,english)
		_draw_text(NUMBER_FONT if english else TEXT_FONT,Vector2(entry.point) + Vector2(0.0,-14.0*progress),text,color)
