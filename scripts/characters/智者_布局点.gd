extends Area2D

const PROPERTY_INDEX = preload("res://classes/property_index.gd")

# 智者逐步放下的布局点。
# 仅做重叠检测：collision_layer = 0，所以永远不是地形，不挡角色/子弹。

var wise_owner:Node = null
var layout_index:int = 0 # 0=1号，1=2号……
var point_radius:float = 6.0
var _shape_node:CollisionShape2D = null
var _visual:Polygon2D = null
var _number_label:Label = null
var _is_expected:bool = false
var _is_completed:bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	set_collision_mask_value(2,true)
	set_collision_mask_value(4,true)
	monitoring = true
	monitorable = false
	z_as_relative = false
	z_index = 40
	add_to_group("AI_Hazard")
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	_build_nodes()
	_refresh_visual()


func configure(owner_node:Node,index_value:int,radius_value:float) -> void:
	wise_owner = owner_node
	layout_index = maxi(index_value,0)
	point_radius = maxf(radius_value,3.0)
	_build_nodes()
	_refresh_visual()


func set_layout_index(index_value:int) -> void:
	layout_index = maxi(index_value,0)
	_refresh_visual()


func set_state(expected:bool,completed:bool) -> void:
	_is_expected = expected
	_is_completed = completed
	_refresh_visual()


func _build_nodes() -> void:
	if not is_inside_tree():
		return
	if _shape_node == null or not is_instance_valid(_shape_node):
		_shape_node = CollisionShape2D.new()
		add_child(_shape_node)
	var circle := CircleShape2D.new()
	circle.radius = point_radius
	_shape_node.shape = circle

	if _visual == null or not is_instance_valid(_visual):
		_visual = Polygon2D.new()
		_visual.z_index = 40
		add_child(_visual)
	var polygon := PackedVector2Array()
	for i in range(20):
		polygon.append(Vector2.from_angle(TAU * float(i) / 20.0) * point_radius)
	_visual.polygon = polygon

	if _number_label == null or not is_instance_valid(_number_label):
		_number_label = Label.new()
		_number_label.z_index = 41
		_number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_number_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_number_label.add_theme_color_override("font_color",Color.WHITE)
		_number_label.add_theme_color_override("font_outline_color",Color.BLACK)
		_number_label.add_theme_constant_override("outline_size",1)
		add_child(_number_label)
	var font_size:int = maxi(int(round(point_radius * 1.05)),6)
	_number_label.add_theme_font_size_override("font_size",font_size)
	var label_side:float = maxf(point_radius * 2.6,14.0)
	_number_label.position = Vector2(-label_side * 0.5,-label_side * 0.5)
	_number_label.size = Vector2(label_side,label_side)


func _refresh_visual() -> void:
	if _visual == null or not is_instance_valid(_visual):
		return
	var t:float = clampf(float(layout_index) / 3.0,0.0,1.0)
	var base_color := Color(0.92 + 0.06 * t,0.78 - 0.36 * t,0.18 - 0.06 * t,0.80)
	if _is_completed:
		base_color.a = 0.28
	elif _is_expected:
		# 当前真正应该踩的点更亮，玩家/观战时能一眼看出“下一步”。
		base_color = base_color.lightened(0.20)
		base_color.a = 0.96
	_visual.color = base_color

	if _number_label != null and is_instance_valid(_number_label):
		_number_label.text = str(layout_index + 1)
		_number_label.modulate = Color(1.0,1.0,1.0,0.42 if _is_completed else 1.0)


func _on_body_entered(body:Node) -> void:
	if body is ball:
		_try_touch(body as ball)


func _on_area_entered(area:Area2D) -> void:
	var target:ball = _find_ball_from_area(area)
	if target != null:
		_try_touch(target)


func _find_ball_from_area(area:Area2D) -> ball:
	if area == null:
		return null
	if area.owner is ball:
		return area.owner as ball
	var cursor:Node = area
	while cursor != null:
		if cursor is ball:
			return cursor as ball
		cursor = cursor.get_parent()
	return null


func _try_touch(target:ball) -> void:
	if wise_owner == null or not is_instance_valid(wise_owner):
		return
	if target == null or not is_instance_valid(target):
		return
	# 不在点自身记录“碰过”。敌人可能提前经过3号，之后自适应把3号改成1号；
	# 如果这里永久缓存，重新编号后反而永远触发不了。顺序去重由智者的 _target_progress 负责。
	if wise_owner.has_method("on_wise_layout_point_touched"):
		wise_owner.call("on_wise_layout_point_touched",self,target)


# AI 通用危险地形接口：只有“当前应该踩”且不是第1号的布局点才会对敌人造成伤害。
func get_ai_hazard_info(receiver:ball) -> Dictionary:
	if not _is_expected or _is_completed or layout_index <= 0:
		return {}
	if wise_owner == null or not is_instance_valid(wise_owner):
		return {}
	if receiver == null or not is_instance_valid(receiver):
		return {}
	if wise_owner.has_method("_is_enemy") and not bool(wise_owner.call("_is_enemy",receiver)):
		return {}
	var start_multiplier:float = 1.0
	var step_multiplier:float = 0.9
	# V431 性能：属性存在性改用按脚本缓存的属性名集合，不再遍历 get_property_list()。
	if PROPERTY_INDEX.has_property(wise_owner,"point_damage_start_multiplier"):
		start_multiplier = float(wise_owner.get("point_damage_start_multiplier"))
	if PROPERTY_INDEX.has_property(wise_owner,"point_damage_step_multiplier"):
		step_multiplier = float(wise_owner.get("point_damage_step_multiplier"))
	var multiplier:float = maxf(start_multiplier + step_multiplier * float(layout_index-1),0.0)
	var amount:float = wise_owner.attack_damage(multiplier)
	return {
		"shape":"circle",
		"position":global_position,
		"radius":maxf(point_radius,1.0),
		"damage":amount,
		"blocking":false,
		"kind":"wise_layout_point",
		"source":wise_owner,
	}
