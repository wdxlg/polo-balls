extends Control

# 放置角色时长按左键出现的框选覆盖层。
# 只负责屏幕空间绘制，不拦截任何鼠标事件。
var start_point:Vector2 = Vector2.ZERO
var end_point:Vector2 = Vector2.ZERO

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

func _draw() -> void:
	if not visible:
		return
	var top_left := Vector2(minf(start_point.x,end_point.x),minf(start_point.y,end_point.y))
	var bottom_right := Vector2(maxf(start_point.x,end_point.x),maxf(start_point.y,end_point.y))
	var rect := Rect2(top_left,bottom_right - top_left)
	# 地图本身偏蓝，框选改成更亮的电光青蓝，仍保持低透明填充 + 细高对比描边。
	draw_rect(rect,Color(0.05,0.78,1.0,0.18),true)
	draw_rect(rect,Color(0.78,0.97,1.0,0.98),false,1.0,false)
