extends RefCounted
## 局内所有能量/进度/充能条的唯一实现（tests/verify_shared_bar.py 检查）；改外观只改这里，所有调用方一起变。
## 外观是原版 Boss 条（gui/sprites/boss_bar/white_*）：两端各 CAP 个原版像素，中段水平拉伸，
## 进度按比例裁切；白色原图乘调用方的颜色，配色由调用方决定。
## 分格条传 segments：6/10/12/20 格叠原版 notched 刻痕图，其他格数按同样的刻痕样式画分隔。
const BACKGROUND:Texture2D = preload("res://Images/UI/boss_bar/white_background.png")
const PROGRESS:Texture2D = preload("res://Images/UI/boss_bar/white_progress.png")
const CAP:float = 3.0
const NOTCHES:Dictionary = {
	6:[preload("res://Images/UI/boss_bar/notched_6_background.png"),preload("res://Images/UI/boss_bar/notched_6_progress.png")],
	10:[preload("res://Images/UI/boss_bar/notched_10_background.png"),preload("res://Images/UI/boss_bar/notched_10_progress.png")],
	12:[preload("res://Images/UI/boss_bar/notched_12_background.png"),preload("res://Images/UI/boss_bar/notched_12_progress.png")],
	20:[preload("res://Images/UI/boss_bar/notched_20_background.png"),preload("res://Images/UI/boss_bar/notched_20_progress.png")],
}
## 原版刻痕像素的颜色（notched_* 图里 2,2,2 半透明）。
const NOTCH_COLOR:Color = Color(0.008,0.008,0.008,0.5)
const START_COLOR:Color = Color(1,1,1,1)
const END_COLOR:Color = Color(1,0.08,0.04,1)
## 白色底槽主色 57/255：乘它后底槽主色为 (0.12,0.12,0.14)。
const TROUGH_TINT:Color = Color(0.5368,0.5368,0.6263,1.0)

static func paint(canvas:CanvasItem,rect:Rect2,ratio:float,warning:float,fill_color:Color = Color(-1,-1,-1,-1),trough_tint:Color = Color(-1,-1,-1,-1),opacity:float = 1.0,segments:int = 0) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0 or opacity <= 0.0: return
	var back:Color = trough_tint if trough_tint.a >= 0.0 else TROUGH_TINT
	back.a *= opacity
	_slice(canvas,BACKGROUND,rect,rect.size.x,back)
	var visible_width:float = rect.size.x * clampf(ratio,0,1)
	if visible_width > 0.0:
		var fill:Color = fill_color if fill_color.a >= 0.0 else START_COLOR.lerp(END_COLOR,clampf(warning,0,1))
		fill.a *= opacity
		_slice(canvas,PROGRESS,rect,visible_width,fill)
	if segments > 1: _notches(canvas,rect,segments,opacity)


## 原版先画底槽、底槽刻痕，再画进度、进度刻痕；两张刻痕图相同，所以整条叠一次即可。
static func _notches(canvas:CanvasItem,rect:Rect2,segments:int,opacity:float) -> void:
	var tint:Color = Color(1,1,1,opacity)
	if NOTCHES.has(segments):
		var texture:Texture2D = NOTCHES[segments][0]
		canvas.draw_texture_rect(texture,rect,false,tint)
		return
	var texel:float = rect.size.y / float(BACKGROUND.get_height())
	var color:Color = NOTCH_COLOR
	color.a *= opacity
	for i:int in range(1,segments):
		var x:float = rect.position.x + rect.size.x * float(i) / float(segments)
		canvas.draw_rect(Rect2(x - texel * 0.5,rect.position.y + texel,texel,rect.size.y - texel * 2.0),color,true)


## 按整条的三段式几何绘制，只画到 visible_width 为止（原版进度条就是裁切而不是缩短）。
static func _slice(canvas:CanvasItem,texture:Texture2D,rect:Rect2,visible_width:float,tint:Color) -> void:
	var source_w:float = texture.get_width()
	var source_h:float = texture.get_height()
	var texel:float = rect.size.y / source_h
	var cap:float = minf(CAP * texel,rect.size.x * 0.5)
	var cap_source:float = cap / texel
	var parts:Array = [
		[0.0,cap,0.0,cap_source],
		[cap,rect.size.x - cap * 2.0,cap_source,source_w - cap_source * 2.0],
		[rect.size.x - cap,cap,source_w - cap_source,cap_source],
	]
	for part:Array in parts:
		var x:float = part[0]
		var w:float = part[1]
		if w <= 0.0 or x >= visible_width: continue
		var shown:float = minf(w,visible_width - x)
		var src_w:float = float(part[3]) * shown / w
		canvas.draw_texture_rect_region(texture,Rect2(rect.position + Vector2(x,0.0),Vector2(shown,rect.size.y)),Rect2(float(part[2]),0.0,src_w,source_h),tint)


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
