extends AnimatableBody2D

var full_width:float = 10.0
var full_height:float = 40.0
var bar_color:Color = Color.WHITE
var _visual:Polygon2D = null
var _collision:CollisionShape2D = null
var _shape:RectangleShape2D = null
var visual_only:bool = false


func configure(width:float,height:float,color:Color,p_visual_only:bool = false) -> void:
	full_width = maxf(width,0.5)
	visual_only = p_visual_only
	if not is_in_group("AI_Hazard"):
		add_to_group("AI_Hazard")
	full_height = maxf(height,0.5)
	bar_color = color

	collision_layer = 0 if visual_only else 1
	collision_mask = 0
	sync_to_physics = true
	z_index = -1

	_visual = Polygon2D.new()
	_visual.name = "StockBarVisual"
	_visual.color = bar_color
	add_child(_visual)

	_collision = CollisionShape2D.new()
	_collision.name = "CollisionShape2D"
	_shape = RectangleShape2D.new()
	_collision.shape = _shape
	add_child(_collision)

	set_growth(0.01)


func set_growth(progress:float) -> void:
	var t:float = clampf(progress,0.0,1.0)
	var current_height:float = maxf(full_height * t,0.15)

	# 节点原点固定在柱子的底部，所以增长永远是“从下往上”。
	_visual.polygon = PackedVector2Array([
		Vector2(-full_width * 0.5,0.0),
		Vector2(full_width * 0.5,0.0),
		Vector2(full_width * 0.5,-current_height),
		Vector2(-full_width * 0.5,-current_height),
	])

	# 不缩放 CollisionShape2D，而是直接改 Shape 的 size；这样物理更稳定。
	_shape.size = Vector2(full_width,current_height)
	_collision.position = Vector2(0.0,-current_height * 0.5)


func grow_from_bottom(duration:float) -> void:
	if duration <= 0.0:
		set_growth(1.0)
		return

	var tween := create_tween().bind_node(self)
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_method(set_growth,0.01,1.0,duration)
	await tween.finished


# AI 通用危险地形接口：这是纯阻挡矩形，不造成伤害。
func get_ai_hazard_info(_receiver:ball) -> Dictionary:
	if _shape == null or _collision == null:
		return {}
	return {
		"shape":"rect",
		"position":_collision.global_position,
		"half_extents":_shape.size * global_scale.abs() * 0.5,
		"rotation":global_rotation,
		"damage":0.0,
		"blocking":true,
		"kind":"blocking_terrain",
		"source":self,
	}
