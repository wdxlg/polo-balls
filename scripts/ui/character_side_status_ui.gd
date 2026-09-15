extends Control

# 通用角色侧边信息区：
# - negative / left：负面效果，统一显示在人物左侧。
# - right：角色自己的专属文字，保留在人物右侧上方。
# - positive：正面效果，统一显示在人物右侧下方，避免挡住角色专属文字。
# - 同一区域内，永久信息在上，临时信息在下并自动淡出。
# - 不绘制背景，只保留文字与细描边。

var follow_target:Node2D = null
var horizontal_gap:float = 10.0
var column_width:float = 76.0
var base_font_size:int = 8
var max_temporary_entries:int = 5

var _left_root:VBoxContainer = null
var _right_root:VBoxContainer = null
var _positive_root:VBoxContainer = null
var _left_permanent:VBoxContainer = null
var _right_permanent:VBoxContainer = null
var _positive_permanent:VBoxContainer = null
var _left_temporary:VBoxContainer = null
var _right_temporary:VBoxContainer = null
var _positive_temporary:VBoxContainer = null

var _left_permanent_labels:Dictionary = {}
var _right_permanent_labels:Dictionary = {}
var _positive_permanent_labels:Dictionary = {}
var _temporary_entries:Array[Dictionary] = []
# 性能：临时状态全部消失且没有永久状态时，空 UI 延迟回收；下次需要时由 ball 懒加载重建。
var _empty_idle_elapsed:float = 0.0
const EMPTY_UI_RECYCLE_DELAY:float = 1.5


func setup(target:Node2D,gap:float = 10.0,width:float = 76.0,font_size:int = 8) -> void:
	follow_target = target
	horizontal_gap = maxf(gap,2.0)
	column_width = maxf(width,40.0)
	base_font_size = maxi(font_size,6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_as_relative = false
	z_index = 1100
	clip_contents = false
	_build_layout()
	_update_follow_position()


func _build_layout() -> void:
	for child in get_children():
		child.queue_free()

	_left_root = _make_side_root()
	_right_root = _make_side_root()
	_positive_root = _make_side_root()
	add_child(_left_root)
	add_child(_right_root)
	add_child(_positive_root)

	_left_permanent = VBoxContainer.new()
	_right_permanent = VBoxContainer.new()
	_positive_permanent = VBoxContainer.new()
	_left_temporary = VBoxContainer.new()
	_right_temporary = VBoxContainer.new()
	_positive_temporary = VBoxContainer.new()

	_configure_stack(_left_permanent)
	_configure_stack(_right_permanent)
	_configure_stack(_positive_permanent)
	_configure_stack(_left_temporary)
	_configure_stack(_right_temporary)
	_configure_stack(_positive_temporary)

	_left_root.add_child(_left_permanent)
	_left_root.add_child(_make_spacer())
	_left_root.add_child(_left_temporary)

	# 右侧上方只给角色自己的文字使用。
	_right_root.add_child(_right_permanent)
	_right_root.add_child(_make_spacer())
	_right_root.add_child(_right_temporary)

	# 正面 Buff 独立成右下区域，不会把角色自己的右上文字往下顶。
	_positive_root.add_child(_positive_permanent)
	_positive_root.add_child(_make_spacer())
	_positive_root.add_child(_positive_temporary)

	_refresh_layout_positions()


func _make_side_root() -> VBoxContainer:
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(column_width,0.0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override("separation",1)
	return root


func _configure_stack(stack:VBoxContainer) -> void:
	stack.custom_minimum_size = Vector2(column_width,0.0)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation",1)


func _make_spacer() -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(column_width,5.0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


func _process(delta:float) -> void:
	if follow_target == null or not is_instance_valid(follow_target) or not follow_target.is_inside_tree():
		queue_free()
		return

	_update_follow_position()

	for i in range(_temporary_entries.size() - 1,-1,-1):
		var entry:Dictionary = _temporary_entries[i]
		var label:Label = entry.get("label") as Label
		if label == null or not is_instance_valid(label):
			_temporary_entries.remove_at(i)
			continue

		var elapsed:float = float(entry.get("elapsed",0.0)) + delta
		var duration:float = maxf(float(entry.get("duration",1.2)),0.15)
		entry["elapsed"] = elapsed
		_temporary_entries[i] = entry

		var fade_start:float = duration * 0.62
		if elapsed >= fade_start:
			label.modulate.a = clampf(1.0 - (elapsed - fade_start) / maxf(duration - fade_start,0.01),0.0,1.0)

		if elapsed >= duration:
			label.queue_free()
			_temporary_entries.remove_at(i)

	# 性能：绝大多数单位平时没有任何侧边文字，空壳 UI 不长期占 SceneTree/Control 布局成本。
	var has_permanent:bool = (
		not _left_permanent_labels.is_empty()
		or not _right_permanent_labels.is_empty()
		or not _positive_permanent_labels.is_empty()
	)
	if has_permanent or not _temporary_entries.is_empty():
		_empty_idle_elapsed = 0.0
	else:
		_empty_idle_elapsed += maxf(delta,0.0)
		if _empty_idle_elapsed >= EMPTY_UI_RECYCLE_DELAY:
			if follow_target != null and is_instance_valid(follow_target) and follow_target.get("side_status_ui") == self:
				follow_target.set("side_status_ui",null)
			queue_free()
			return


func _update_follow_position() -> void:
	if follow_target == null or not is_instance_valid(follow_target):
		return
	var desired_position:Vector2 = follow_target.global_position
	if global_position != desired_position:
		global_position = desired_position


func _refresh_layout_positions() -> void:
	if _left_root == null or _right_root == null or _positive_root == null:
		return

	# 左侧负面从人物上半区开始排列；债务等永久 Debuff 在最上面，
	# 被偷属性等临时负面紧跟其下。
	_left_root.position = Vector2(-horizontal_gap - column_width,-28.0)

	# 右上明确留给“角色自己的文字”，例如赌徒轮盘等。
	_right_root.position = Vector2(horizontal_gap,-32.0)

	# 所有正面状态单独从右下开始，避免和角色专属文字抢位置。
	_positive_root.position = Vector2(horizontal_gap,8.0)

	_left_root.custom_minimum_size.x = column_width
	_right_root.custom_minimum_size.x = column_width
	_positive_root.custom_minimum_size.x = column_width


func set_permanent(side:String,key:String,text_value:String,color:Color = Color.WHITE) -> void:
	var normalized_side:String = _normalize_side(side)
	var labels:Dictionary = _permanent_dictionary(normalized_side)
	var stack:VBoxContainer = _permanent_stack(normalized_side)
	if stack == null:
		return

	var label:Label = null
	if labels.has(key):
		label = labels[key] as Label
	if label == null or not is_instance_valid(label):
		label = _make_label(normalized_side,true)
		stack.add_child(label)
		labels[key] = label

	label.text = Game.translate_game_text(text_value)
	label.add_theme_color_override("font_color",color)
	label.modulate.a = 1.0


func remove_permanent(side:String,key:String) -> void:
	var normalized_side:String = _normalize_side(side)
	var labels:Dictionary = _permanent_dictionary(normalized_side)
	if not labels.has(key):
		return
	var label:Label = labels[key] as Label
	labels.erase(key)
	if label != null and is_instance_valid(label):
		label.queue_free()


func clear_permanent(side:String = "") -> void:
	if side.is_empty():
		_clear_permanent_dictionary(_left_permanent_labels)
		_clear_permanent_dictionary(_right_permanent_labels)
		_clear_permanent_dictionary(_positive_permanent_labels)
		return

	match _normalize_side(side):
		"left":
			_clear_permanent_dictionary(_left_permanent_labels)
		"positive":
			_clear_permanent_dictionary(_positive_permanent_labels)
		_:
			_clear_permanent_dictionary(_right_permanent_labels)


func push_temporary(side:String,text_value:String,color:Color = Color.WHITE,duration:float = 1.25) -> void:
	var normalized_side:String = _normalize_side(side)
	var stack:VBoxContainer = _temporary_stack(normalized_side)
	if stack == null:
		return

	var label:Label = _make_label(normalized_side,false)
	label.text = Game.translate_game_text(text_value)
	label.add_theme_color_override("font_color",color)
	stack.add_child(label)

	_temporary_entries.append({
		"label":label,
		"side":normalized_side,
		"elapsed":0.0,
		"duration":maxf(duration,0.15),
	})
	_trim_temporary(normalized_side)


func _trim_temporary(side:String) -> void:
	var normalized_side:String = _normalize_side(side)
	var count:int = 0
	for entry:Dictionary in _temporary_entries:
		if str(entry.get("side","")) == normalized_side:
			count += 1
	while count > max_temporary_entries:
		for i in range(_temporary_entries.size()):
			var entry:Dictionary = _temporary_entries[i]
			if str(entry.get("side","")) != normalized_side:
				continue
			var label:Label = entry.get("label") as Label
			if label != null and is_instance_valid(label):
				label.queue_free()
			_temporary_entries.remove_at(i)
			count -= 1
			break


func _make_label(side:String,is_permanent:bool) -> Label:
	var normalized_side:String = _normalize_side(side)
	var label := Label.new()
	label.custom_minimum_size = Vector2(column_width,11.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.clip_text = false
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if normalized_side == "left" else HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",base_font_size)
	label.add_theme_color_override("font_outline_color",Color(0.0,0.0,0.0,0.92))
	label.add_theme_constant_override("outline_size",1)
	if is_permanent:
		label.add_theme_color_override("font_shadow_color",Color(0.0,0.0,0.0,0.55))
		label.add_theme_constant_override("shadow_offset_x",1)
		label.add_theme_constant_override("shadow_offset_y",1)
	return label


func _normalize_side(side:String) -> String:
	match side.to_lower():
		"left","negative","debuff":
			return "left"
		"positive","buff":
			return "positive"
		_:
			# 兼容旧代码：right 以及未知值仍走角色自己的右上区域。
			return "right"


func _permanent_stack(side:String) -> VBoxContainer:
	match _normalize_side(side):
		"left":
			return _left_permanent
		"positive":
			return _positive_permanent
		_:
			return _right_permanent


func _temporary_stack(side:String) -> VBoxContainer:
	match _normalize_side(side):
		"left":
			return _left_temporary
		"positive":
			return _positive_temporary
		_:
			return _right_temporary


func _permanent_dictionary(side:String) -> Dictionary:
	match _normalize_side(side):
		"left":
			return _left_permanent_labels
		"positive":
			return _positive_permanent_labels
		_:
			return _right_permanent_labels


func _clear_permanent_dictionary(labels:Dictionary) -> void:
	for raw_label in labels.values():
		var label:Label = raw_label as Label
		if label != null and is_instance_valid(label):
			label.queue_free()
	labels.clear()
