extends StaticBody2D

var stone_radius:float = 7.0
var life_time:float = 9.0
var stone_color:Color = Color(0.86,0.72,0.18,0.92)

var _shape_node:CollisionShape2D = null
var _visual:Polygon2D = null


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	z_as_relative = false
	z_index = 30
	_build_nodes()
	if life_time > 0.0:
		get_tree().create_timer(life_time).timeout.connect(_expire)


func configure(radius_value:float,lifetime_value:float,color_value:Color) -> void:
	stone_radius = maxf(radius_value,2.0)
	life_time = maxf(lifetime_value,0.2)
	stone_color = color_value
	if is_inside_tree():
		_build_nodes()


func _build_nodes() -> void:
	if not is_inside_tree():
		return
	if _shape_node == null or not is_instance_valid(_shape_node):
		_shape_node = CollisionShape2D.new()
		add_child(_shape_node)
	var circle := CircleShape2D.new()
	circle.radius = stone_radius
	_shape_node.shape = circle

	if _visual == null or not is_instance_valid(_visual):
		_visual = Polygon2D.new()
		_visual.z_index = 30
		add_child(_visual)
	var points := PackedVector2Array()
	for i in range(20):
		points.append(Vector2.from_angle(TAU * float(i) / 20.0) * stone_radius)
	_visual.polygon = points
	_visual.color = stone_color


func _expire() -> void:
	if is_instance_valid(self):
		queue_free()
