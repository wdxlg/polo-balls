extends Control

# 放置角色时长按左键出现的框选覆盖层。
# 只负责屏幕空间绘制，不拦截任何鼠标事件。
var start_point:Vector2 = Vector2.ZERO
var end_point:Vector2 = Vector2.ZERO
# 横向 x 纵向 将要生成的人物个数；由放置逻辑用同一套网格算法算出后传入。
var grid_count_x:int = 1
var grid_count_y:int = 1
const GRID_LABEL_FONT_SIZE:int = 16
const GRID_LABEL_PADDING:Vector2 = Vector2(5.0,2.0)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	z_index = 4096
	visible = false
	_update_viewport_size()
	if not get_viewport().size_changed.is_connected(_update_viewport_size):
		get_viewport().size_changed.connect(_update_viewport_size)

func _exit_tree() -> void:
	if get_viewport() != null and get_viewport().size_changed.is_connected(_update_viewport_size):
		get_viewport().size_changed.disconnect(_update_viewport_size)

func _update_viewport_size() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	queue_redraw()

func set_selection_points(from_point:Vector2,to_point:Vector2) -> void:
	start_point = from_point
	end_point = to_point
	visible = true
	queue_redraw()

func clear_selection() -> void:
	visible = false
	queue_redraw()

func set_grid_counts(count_x:int,count_y:int) -> void:
	var new_x:int = maxi(count_x,1)
	var new_y:int = maxi(count_y,1)
	if new_x == grid_count_x and new_y == grid_count_y:
		return
	grid_count_x = new_x
	grid_count_y = new_y
	queue_redraw()

func _draw() -> void:
	if not visible:
		return
	var top_left := Vector2(minf(start_point.x,end_point.x),minf(start_point.y,end_point.y))
	var bottom_right := Vector2(maxf(start_point.x,end_point.x),maxf(start_point.y,end_point.y))
	var rect := Rect2(top_left,bottom_right - top_left)
	# 地图本身偏蓝，框选改成更亮的电光青蓝，仍保持低透明填充 + 细高对比描边。
	draw_rect(rect,Color(0.05,0.78,1.0,0.18),true)
	draw_rect(rect,Color(0.78,0.97,1.0,0.98),false,1.0,false)
	_draw_grid_label(rect)

# 左上角标注“横向个数x纵向个数”。标签固定贴在框外上方；顶到屏幕边缘时改放框内。
func _draw_grid_label(rect:Rect2) -> void:
	var font:Font = get_theme_default_font()
	if font == null:
		font = ThemeDB.fallback_font
	if font == null:
		return
	var text:String = "%dx%d" % [grid_count_x,grid_count_y]
	var text_size:Vector2 = font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1.0,GRID_LABEL_FONT_SIZE)
	var box_size:Vector2 = text_size + GRID_LABEL_PADDING * 2.0
	var box_pos:Vector2 = Vector2(rect.position.x,rect.position.y - box_size.y - 1.0)
	if box_pos.y < 0.0:
		box_pos.y = rect.position.y + 1.0
	box_pos.x = clampf(box_pos.x,0.0,maxf(size.x - box_size.x,0.0))
	var box := Rect2(box_pos,box_size)
	draw_rect(box,Color(0.02,0.16,0.28,0.85),true)
	draw_rect(box,Color(0.78,0.97,1.0,0.98),false,1.0,false)
	var ascent:float = font.get_ascent(GRID_LABEL_FONT_SIZE)
	var baseline:Vector2 = box_pos + GRID_LABEL_PADDING + Vector2(0.0,ascent)
	draw_string(font,baseline + Vector2(1.0,1.0),text,HORIZONTAL_ALIGNMENT_LEFT,-1.0,GRID_LABEL_FONT_SIZE,Color(0.0,0.0,0.0,0.6))
	draw_string(font,baseline,text,HORIZONTAL_ALIGNMENT_LEFT,-1.0,GRID_LABEL_FONT_SIZE,Color(0.9,0.99,1.0,1.0))
