extends RefCounted
## Same frame, trough, outline and fill palette as creeper._draw_fuse_progress_bar.
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
