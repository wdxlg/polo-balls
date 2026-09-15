extends Node2D

@export_category("爱心")
@export_range(1,12,1) var heart_count:int = 6
@export_range(4.0,40.0,1.0) var heart_size:float = 15.0
@export_range(20.0,160.0,1.0) var rise_min:float = 62.0
@export_range(20.0,180.0,1.0) var rise_max:float = 94.0
@export_range(0.0,50.0,1.0) var side_drift:float = 18.0
@export_range(0.2,2.5,0.05) var life_min:float = 0.82
@export_range(0.2,3.0,0.05) var life_max:float = 1.12
@export_range(0.0,45.0,1.0) var rotation_range_deg:float = 10.0
# 标准爱心尖端朝下。上一版默认旋转 180°，这里已经修正。
@export var tip_points_up:bool = false
@export var heart_color:Color = Color(1.0,0.20,0.46,1.0)
@export var heart_highlight:Color = Color(1.0,0.52,0.68,1.0)

@onready var breed_sfx:AudioStreamPlayer2D = $BreedSfx


func _ready() -> void:
	# 这个节点就是繁殖中点：音效和所有爱心都从这里开始。
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		breed_sfx.bus = &"GameplayRecord"
	breed_sfx.pitch_scale = randf_range(0.96,1.04)
	breed_sfx.play()

	for i in range(heart_count):
		_spawn_heart(i)

	var cleanup_delay:float = maxf(
		life_max + float(maxi(heart_count - 1,0)) * 0.07 + 0.35,
		1.35
	)
	await get_tree().create_timer(cleanup_delay).timeout
	if is_instance_valid(self):
		queue_free()


func _spawn_heart(index:int) -> void:
	var heart := Polygon2D.new()
	heart.polygon = _make_heart_polygon(heart_size * randf_range(0.82,1.16))
	heart.color = heart_color.lerp(heart_highlight,randf_range(0.0,0.55))
	heart.position = Vector2(randf_range(-3.0,3.0),randf_range(-2.0,2.0))
	# 参数曲线本身是标准“尖端朝下”的爱心；需要尖朝上时才翻转 180°。
	var base_rotation:float = PI if tip_points_up else 0.0
	heart.rotation = base_rotation + deg_to_rad(randf_range(-rotation_range_deg,rotation_range_deg))
	heart.scale = Vector2.ONE * randf_range(0.82,1.12)
	heart.z_index = 20
	add_child(heart)

	var delay:float = float(index) * randf_range(0.035,0.065)
	var life:float = randf_range(life_min,life_max)
	var rise:float = randf_range(rise_min,rise_max)
	var drift:float = randf_range(-side_drift,side_drift)
	var target_rotation:float = heart.rotation + deg_to_rad(randf_range(-rotation_range_deg,rotation_range_deg))
	var target_position:Vector2 = heart.position + Vector2(drift,-rise)

	heart.scale = Vector2.ZERO
	var tween := create_tween().bind_node(heart)
	if delay > 0.0:
		tween.tween_interval(delay)

	var pop_time:float = minf(0.14,life * 0.22)
	tween.tween_property(heart,"scale",Vector2.ONE * randf_range(0.88,1.13),pop_time) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var start_delay:float = delay + pop_time
	var float_tween := create_tween().bind_node(heart).set_parallel(true)
	float_tween.tween_property(heart,"position",target_position,life) \
		.set_delay(start_delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	float_tween.tween_property(heart,"rotation",target_rotation,life) \
		.set_delay(start_delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	float_tween.tween_property(heart,"modulate:a",0.0,life * 0.72) \
		.set_delay(start_delay + life * 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	float_tween.chain().tween_callback(heart.queue_free)


func _make_heart_polygon(size:float) -> PackedVector2Array:
	var points := PackedVector2Array()
	const SEGMENTS:int = 32
	for i in range(SEGMENTS):
		var t:float = TAU * float(i) / float(SEGMENTS)
		var st:float = sin(t)
		var x:float = 16.0 * st * st * st
		var y:float = 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		# Godot 的 +Y 向下；这里得到标准尖端朝下的爱心。
		points.append(Vector2(x,-y) * (size / 32.0))
	return points
