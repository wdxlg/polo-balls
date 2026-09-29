extends Node2D
## 所有待抽人物共用这一份固定虚影；没有碰撞、生命、AI，也不加入 Ball 组。
var accent:Color = Color(0.42,0.88,1.0)
var slot_number:int = 0

func _ready() -> void:
	z_as_relative = false
	z_index = 95
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2(0,10),12,Color(accent,0.12))
	draw_arc(Vector2(0,10),11,0,TAU,32,Color(accent,0.8),1.0,true)
	draw_circle(Vector2(0,-8),5.3,Color(0.50,0.62,0.80,0.65))
	var body := PackedVector2Array([Vector2(-4,-1),Vector2(4,-1),Vector2(8,5),Vector2(9,12),Vector2(-9,12),Vector2(-8,5)])
	draw_colored_polygon(body,Color(0.38,0.49,0.68,0.55))
	draw_polyline(PackedVector2Array([Vector2(-9,12),Vector2(-8,5),Vector2(-4,-1),Vector2(4,-1),Vector2(8,5),Vector2(9,12)]),Color(accent,0.8),1.0,true)
	draw_string(ThemeDB.fallback_font,Vector2(-3.5,8),"?",HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color(0.93,0.98,1.0))
	if slot_number > 0:
		draw_string(ThemeDB.fallback_font,Vector2(12,-7),str(slot_number),HORIZONTAL_ALIGNMENT_LEFT,-1,7,Color(accent,0.9))
