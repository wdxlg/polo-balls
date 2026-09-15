extends Area2D

var inward_normal:Vector2 = Vector2.RIGHT
var paired_portal:Area2D = null
var portal_length:float = 38.0
var portal_thickness:float = 5.0
var portal_color:Color = Color(0.2,0.55,1.0,0.9)
var portal_texture:Texture2D = null
var exit_offset:float = 16.0
var teleport_lock_seconds:float = 0.22
var visual_only:bool = false

@export_range(1.0,3.0,0.05) var visual_length_multiplier:float = 1.6
@export_range(2.0,12.0,0.25) var visual_thickness_multiplier:float = 6.0
@export_range(8.0,80.0,1.0) var visual_min_thickness:float = 22.0

var _shape_node:CollisionShape2D
var _visual:Sprite2D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	# 角色本体通常在 2；部分 Shooter 在 3；所有 ball 的 hurtbox 会补到 4。
	set_collision_mask_value(2,true)
	set_collision_mask_value(3,true)
	set_collision_mask_value(4,true)
	monitoring = not visual_only
	monitorable = false
	if not visual_only:
		body_entered.connect(_on_body_entered)
		area_entered.connect(_on_area_entered)
	else:
		collision_mask = 0
	_build_nodes()


func configure_portal(
	position:Vector2,
	normal:Vector2,
	length:float,
	thickness:float,
	color:Color,
	new_exit_offset:float,
	lock_seconds:float
) -> void:
	portal_length = maxf(length,8.0)
	portal_thickness = maxf(thickness,4.0)
	portal_color = color
	exit_offset = maxf(new_exit_offset,4.0)
	teleport_lock_seconds = maxf(lock_seconds,0.05)
	_relocate(position,normal)
	_build_nodes()


func _relocate(position:Vector2,normal:Vector2) -> void:
	global_position = position
	inward_normal = normal.normalized() if normal.length_squared() > 0.000001 else Vector2.RIGHT
	# 本地 X 轴沿墙面切线，矩形长边贴墙。
	rotation = inward_normal.rotated(PI * 0.5).angle()


func relocate(position:Vector2,normal:Vector2) -> void:
	_relocate(position,normal)


func _build_nodes() -> void:
	if not is_inside_tree():
		return

	if _shape_node == null or not is_instance_valid(_shape_node):
		_shape_node = CollisionShape2D.new()
		add_child(_shape_node)
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = Vector2(portal_length,portal_thickness)
	_shape_node.shape = rect_shape

	if _visual == null or not is_instance_valid(_visual):
		_visual = Sprite2D.new()
		_visual.name = "PortalVisual"
		_visual.centered = true
		_visual.z_as_relative = false
		_visual.z_index = 45
		add_child(_visual)

	_visual.texture = portal_texture
	_visual.modulate = Color(1.0,1.0,1.0,clampf(portal_color.a,0.0,1.0))
	# 素材是竖向椭圆；根节点本地 X 轴才是沿墙方向，所以图片转 90°。
	_visual.rotation = -PI * 0.5
	if portal_texture != null:
		var tex_size:Vector2 = portal_texture.get_size()
		if tex_size.x > 0.001 and tex_size.y > 0.001:
			var target_length:float = maxf(portal_length * visual_length_multiplier,portal_length)
			var target_thickness:float = maxf(portal_thickness * visual_thickness_multiplier,visual_min_thickness)
			# 旋转前：X=厚度、Y=长度；旋转后正好交换到沿墙/离墙方向。
			_visual.scale = Vector2(target_thickness / tex_size.x,target_length / tex_size.y)


func _on_body_entered(body:Node) -> void:
	if body is ball:
		_try_schedule_teleport(body as ball)


func _on_area_entered(area:Area2D) -> void:
	# 一些旧投射物的 CharacterBody2D 本体 collision_layer=0，
	# 但它们的 hurtbox 仍在第 4 层，所以同时通过 area_entered 捕获。
	var target:ball = _find_ball_from_area(area)
	if target != null:
		_try_schedule_teleport(target)


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


func _try_schedule_teleport(body:ball) -> void:
	if paired_portal == null or not is_instance_valid(paired_portal):
		return
	if body == null or not is_instance_valid(body):
		return
	if body.state_machine != null and body.state_machine.current_state == ball.State.Die:
		return

	var now_msec:int = Time.get_ticks_msec()
	var lock_key:StringName = &"__scientist_portal_lock_until"
	if body.has_meta(lock_key) and now_msec < int(body.get_meta(lock_key)):
		return

	# body_entered 与 hurtbox.area_entered 可能在同一帧同时触发，先锁再 deferred。
	body.set_meta(lock_key,now_msec + int(round(teleport_lock_seconds * 1000.0)))
	call_deferred("_teleport_body",body)


func _teleport_body(body:ball) -> void:
	if body == null or not is_instance_valid(body):
		return
	if paired_portal == null or not is_instance_valid(paired_portal):
		return

	var exit_portal = paired_portal
	var old_dir:Vector2 = body.direction
	if old_dir.length_squared() <= 0.000001:
		old_dir = -inward_normal

	# 保留它在入口长边上的相对偏移，避免所有东西都从出口中心挤出来。
	var entry_tangent:Vector2 = Vector2.RIGHT.rotated(global_rotation)
	var exit_tangent:Vector2 = Vector2.RIGHT.rotated(exit_portal.global_rotation)
	var tangent_offset:float = clampf(
		(body.global_position - global_position).dot(entry_tangent),
		-portal_length * 0.45,
		portal_length * 0.45
	)
	body.global_position = (
		exit_portal.global_position
		+ exit_tangent * tangent_offset
		+ exit_portal.inward_normal * exit_offset
	)

	# “朝入口墙里飞”的方向映射成“从出口向场内飞出”的方向。
	var rotate_delta:float = exit_portal.inward_normal.angle() - (-inward_normal).angle()
	body.direction = old_dir.normalized().rotated(rotate_delta).normalized()
	body.velocity = Vector2.ZERO
	body.Repel = Vector2.ZERO

	if body.Type != ball.Ball_Type.Ball:
		body.global_rotation = body.Default_Rotation + body.direction.angle()

	if body.has_method("on_scientist_portal_pass"):
		body.call("on_scientist_portal_pass")
