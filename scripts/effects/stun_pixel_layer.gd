extends Node2D
## One half of the orbit; individual pixels are split by orbital depth.
var pixels:Dictionary={}
var glyphs:Array[Dictionary]=[]
var tint:Color=Color("d7e58c")
var atlas:Texture2D
func _draw() -> void:
	for point:Vector2 in pixels:
		var color:Color=tint
		color.a=float(pixels[point])
		draw_rect(Rect2(point,Vector2(2,2)),color)
	for glyph:Dictionary in glyphs:
		var color:Color=tint
		color.a=glyph.alpha
		draw_texture_rect_region(atlas,Rect2(glyph.point,Vector2(10,10)),Rect2(64-glyph.frame*8,64,8,8),color)
