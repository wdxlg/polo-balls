extends Node2D
var polygons:Array[PackedVector2Array] = []
var colors:Array[Color] = []
func _draw() -> void:
	for i:int in range(polygons.size()):
		if polygons[i].size() >= 3: draw_colored_polygon(polygons[i],colors[i])
