extends RefCounted
## Shared Creeper-style meter: the actual Creeper and other characters call this painter.
const OUTER_COLOR:Color = Color(0.02,0.02,0.025,0.92)
const BACKGROUND_COLOR:Color = Color(0.12,0.12,0.14,1.0)
const BORDER_COLOR:Color = Color(0.78,0.82,0.88,0.86)
const START_COLOR:Color = Color(1,1,1,1)
const END_COLOR:Color = Color(1,0.08,0.04,1)
static func paint(canvas:CanvasItem,rect:Rect2,ratio:float,warning:float,fill_color:Color = Color(-1,-1,-1,-1)) -> void:
	var unit:float = rect.size.x/110.0
	var pad:Vector2 = Vector2.ONE*4.0*unit
	canvas.draw_rect(Rect2(rect.position-pad,rect.size+pad*2.0),OUTER_COLOR,true)
	canvas.draw_rect(rect,BACKGROUND_COLOR,true)
	if ratio>0.0:
		canvas.draw_rect(Rect2(rect.position,Vector2(rect.size.x*clampf(ratio,0,1),rect.size.y)),(fill_color if fill_color.a>=0.0 else START_COLOR.lerp(END_COLOR,clampf(warning,0,1))),true)
	canvas.draw_rect(rect,BORDER_COLOR,false,2.5*unit)


static func below_body(canvas:Node2D,shape_node:CollisionShape2D,width:float = 110.0,height:float = 16.0,gap:float = 8.0) -> Rect2:
	var bottom:float = 82.0
	var center_x:float = 0.0
	if is_instance_valid(shape_node) and shape_node.shape != null:
		var bounds:Rect2 = shape_node.shape.get_rect()
		bottom = -INF
		for point:Vector2 in [bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)]:
			bottom = maxf(bottom,canvas.to_local(shape_node.to_global(point)).y)
		center_x = canvas.to_local(shape_node.to_global(bounds.get_center())).x
	return Rect2(center_x-width*0.5,bottom+gap,width,height)
