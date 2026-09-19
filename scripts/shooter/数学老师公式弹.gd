extends Node2D

const CHALK_MOVE_SFX:AudioStream = preload("res://audio/characters/数学老师/移动.mp3")
const TRAJECTORY_KIND_COUNT:int = 8

var owner_teacher:Node = null
var authoritative_logic:bool = false
var projectile_team:String = ""
var travel_origin:Vector2 = Vector2.ZERO
var forward:Vector2 = Vector2.RIGHT
var lateral:Vector2 = Vector2.DOWN
var travel_speed:float = 210.0
var max_lifetime:float = 2.8
var damage_amount:float = 20.0
var curve_span:float = 220.0
var curve_amplitude:float = 28.0
var curve_kind:int = 0
var elapsed:float = 0.0
var traveled_x:float = 0.0
var hit_ids:Dictionary = {}
var trajectory_line:Line2D = null
var move_audio:AudioStreamPlayer2D = null
var chalk_rect_shape:RectangleShape2D = null
var chalk_hitbox_local_center:Vector2 = Vector2.ZERO
var chalk_hitbox_local_rotation:float = 0.0
var map_world_rect:Rect2 = Rect2()
var has_valid_map_rect:bool = false
var path_end_distance:float = 720.0

@onready var chalk_sprite:Sprite2D = $Visual
@onready var chalk_hit_area:Area2D = $ChalkHitbox
@onready var chalk_collision_shape:CollisionShape2D = $ChalkHitbox/CollisionShape2D


func configure(owner_node:Node,config:Dictionary,is_authority:bool) -> void:
	owner_teacher = owner_node
	authoritative_logic = is_authority
	travel_origin = config.get("origin",global_position)
	global_position = travel_origin
	forward = config.get("forward",Vector2.RIGHT)
	if forward.length_squared() <= 0.000001:
		forward = Vector2.RIGHT
	forward = forward.normalized()
	lateral = forward.rotated(PI * 0.5)
	travel_speed = maxf(float(config.get("speed",210.0)),1.0)
	max_lifetime = maxf(float(config.get("lifetime",2.8)),0.1)
	damage_amount = maxf(float(config.get("damage",20.0)),0.0)
	projectile_team = str(config.get("team",""))
	curve_span = maxf(float(config.get("span",220.0)),20.0)
	curve_amplitude = float(config.get("amplitude",28.0))
	curve_kind = clampi(int(config.get("curve_kind",0)),0,TRAJECTORY_KIND_COUNT - 1)
	z_as_relative = false
	z_index = 80
	add_to_group("BattleTransient")
	_configure_chalk_hitbox()
	map_world_rect = _resolve_current_map_rect()
	has_valid_map_rect = map_world_rect.size.x > 1.0 and map_world_rect.size.y > 1.0
	# V338：轨迹/速度文字显示已彻底删除；这里只保留真实白色运动轨迹线。
	_build_trajectory_line()
	_start_move_audio()
	if chalk_sprite != null:
		chalk_sprite.visible = true


func _physics_process(delta:float) -> void:
	elapsed += delta
	var previous:Vector2 = global_position
	traveled_x += travel_speed * delta
	var next_pos:Vector2 = travel_origin + forward * traveled_x + lateral * _curve_y(traveled_x)
	var motion:Vector2 = next_pos - previous
	var facing_angle:float = motion.angle() if motion.length_squared() > 0.000001 else rotation

	# V342：粉笔实体完全无视墙体、地形和其它物理阻挡。
	# 不再执行 terrain ShapeCast / RayCast，也不会因为任何阻挡播放撞墙声或提前 queue_free。
	# 人物伤害仍由下方“图片矩形连续扫过目标碰撞形状”的独立逻辑处理，因此穿墙/穿物体不等于穿过敌人不结算。
	global_position = next_pos
	rotation = facing_angle
	if authoritative_logic:
		_damage_all_crossed_targets(previous,next_pos,facing_angle)

	# 只有两个生命周期终点：
	# 1) 整张旋转后的粉笔图片完全离开地图 Rect2；
	# 2) 沿本次已画出的真实轨迹走到 Line2D 的路径终点。
	# 有地图时二者任一成立即删除；拿不到地图矩形的兼容场景则只依赖路径终点，绝不恢复墙体/时间销毁。
	var fully_outside_map:bool = false
	if has_valid_map_rect:
		fully_outside_map = not _chalk_world_aabb(global_position,facing_angle).intersects(map_world_rect,true)
	var reached_path_end:bool = traveled_x >= maxf(path_end_distance,1.0)
	if fully_outside_map or reached_path_end:
		queue_free()
		return


func _configure_chalk_hitbox() -> void:
	if chalk_sprite == null or chalk_collision_shape == null:
		return
	var rect:Rect2 = chalk_sprite.get_rect()
	var visual_scale:Vector2 = chalk_sprite.scale
	var size_world := Vector2(
		maxf(absf(rect.size.x * visual_scale.x),0.5),
		maxf(absf(rect.size.y * visual_scale.y),0.5)
	)
	var shape := RectangleShape2D.new()
	shape.size = size_world
	chalk_rect_shape = shape
	chalk_collision_shape.shape = shape
	chalk_collision_shape.position = Vector2.ZERO
	chalk_collision_shape.rotation = 0.0
	chalk_collision_shape.scale = Vector2.ONE
	chalk_hitbox_local_center = chalk_sprite.transform * rect.get_center()
	chalk_hitbox_local_rotation = chalk_sprite.rotation
	if chalk_hit_area != null:
		chalk_hit_area.position = chalk_hitbox_local_center
		chalk_hit_area.rotation = chalk_hitbox_local_rotation
		chalk_hit_area.scale = Vector2.ONE


func _chalk_shape_transform(root_position:Vector2,facing_angle:float) -> Transform2D:
	var center:Vector2 = root_position + chalk_hitbox_local_center.rotated(facing_angle)
	return Transform2D(facing_angle + chalk_hitbox_local_rotation,center)


func _resolve_current_map_rect() -> Rect2:
	var world:Node = get_tree().current_scene
	if world == null or not world.has_method("return_map_world_rect"):
		return Rect2()
	var groups_value:Variant = world.get("map_group")
	var current_value:Variant = world.get("now_choose_map")
	if not groups_value is Dictionary:
		return Rect2()
	var groups:Dictionary = groups_value
	var key:String = str(current_value)
	if not groups.has(key):
		return Rect2()
	var map_node:Variant = groups[key]
	if not map_node is TileMapLayer:
		return Rect2()
	var rect_value:Variant = world.call("return_map_world_rect",map_node)
	return rect_value if rect_value is Rect2 else Rect2()


func _chalk_world_aabb(root_position:Vector2,facing_angle:float) -> Rect2:
	if chalk_rect_shape == null:
		return Rect2(root_position,Vector2.ZERO)
	var half:Vector2 = chalk_rect_shape.size * 0.5
	var xform:Transform2D = _chalk_shape_transform(root_position,facing_angle)
	var corners := PackedVector2Array([
		xform * Vector2(-half.x,-half.y),
		xform * Vector2(half.x,-half.y),
		xform * Vector2(half.x,half.y),
		xform * Vector2(-half.x,half.y),
	])
	var min_p:Vector2 = corners[0]
	var max_p:Vector2 = corners[0]
	for point:Vector2 in corners:
		min_p.x = minf(min_p.x,point.x)
		min_p.y = minf(min_p.y,point.y)
		max_p.x = maxf(max_p.x,point.x)
		max_p.y = maxf(max_p.y,point.y)
	return Rect2(min_p,max_p - min_p)


func _curve_y(x:float) -> float:
	var p:float = clampf(x / curve_span,0.0,1.0)
	if x > curve_span:
		return 0.0
	match clampi(curve_kind,0,TRAJECTORY_KIND_COUNT - 1):
		0:
			# y = A·4p(1-p)：标准抛物线弧。
			return curve_amplitude * 4.0 * p * (1.0 - p)
		1:
			# y = A sin(pi p)：单拱半正弦。
			return curve_amplitude * sin(PI * p)
		2:
			# y = A sin(2pi p)：一次完整 S 波。
			return curve_amplitude * sin(TAU * p)
		3:
			# y = A sin(3pi p)：三段交替弯折。
			return curve_amplitude * sin(3.0 * PI * p)
		4:
			# y = A sin(4pi p)：两次完整波动。
			return curve_amplitude * sin(2.0 * TAU * p)
		5:
			# y = A·16p²(1-p)²：比抛物线更集中的钟形弧。
			var bell:float = 16.0 * p * p * (1.0 - p) * (1.0 - p)
			return curve_amplitude * bell
		6:
			# y = A·4p(1-p)cos(2pi p)：带抛物包络的波动。
			return curve_amplitude * 4.0 * p * (1.0 - p) * cos(TAU * p)
		_:
			# y = A·sin(2pi p)sin(pi p)：两端收束的平滑 S 波。
			return curve_amplitude * sin(TAU * p) * sin(PI * p)


func _build_trajectory_line() -> void:
	if trajectory_line != null and is_instance_valid(trajectory_line):
		trajectory_line.queue_free()
	var line := Line2D.new()
	line.name = "数学公式白色轨迹"
	line.width = 1.6
	line.default_color = Color(1.0,1.0,1.0,0.88)
	line.antialiased = true
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.z_as_relative = false
	# V341：轨迹线与粉笔实体同为 z=80，保持在 World 的 MapOutsideVisualMask(z=90) 下方。
	# 因此轨迹可以继续按真实曲线生成，但地图矩形外的部分会被外侧背景遮掉。
	line.z_index = 80
	add_child(line)
	line.top_level = true
	line.global_position = travel_origin
	line.global_rotation = 0.0
	var max_distance:float = _trajectory_preview_distance()
	# V342：这条 Line2D 的末端就是粉笔允许飞行的“路径尽头”；实体与视觉使用同一个终点距离。
	path_end_distance = maxf(max_distance,1.0)
	var sample_count:int = clampi(int(ceil(max_distance / 7.0)),72,220)
	var points := PackedVector2Array()
	for i:int in range(sample_count + 1):
		var t:float = float(i) / float(sample_count)
		var x:float = max_distance * t
		points.append(forward * x + lateral * _curve_y(x))
	line.points = points
	trajectory_line = line


func _trajectory_preview_distance() -> float:
	# V340：轨迹预览不再用旧 720px 固定上限，也不参考地图矩形。
	# 直接把当前 Viewport 可见区域转换成世界坐标，沿真实曲线一直采样到“屏幕外再多一段距离”。
	var fallback_distance:float = maxf(travel_speed * max_lifetime,maxf(curve_span + 260.0,720.0))
	var viewport:Viewport = get_viewport()
	if viewport == null:
		return fallback_distance
	var screen_rect:Rect2 = viewport.get_visible_rect()
	if screen_rect.size.x <= 1.0 or screen_rect.size.y <= 1.0:
		return fallback_distance

	var canvas_xform:Transform2D = get_canvas_transform()
	var inv_canvas:Transform2D = canvas_xform.affine_inverse()
	var screen_end:Vector2 = screen_rect.position + screen_rect.size
	var corners := PackedVector2Array([
		inv_canvas * screen_rect.position,
		inv_canvas * Vector2(screen_end.x,screen_rect.position.y),
		inv_canvas * screen_end,
		inv_canvas * Vector2(screen_rect.position.x,screen_end.y),
	])
	var min_corner:Vector2 = corners[0]
	var max_corner:Vector2 = corners[0]
	for corner:Vector2 in corners:
		min_corner.x = minf(min_corner.x,corner.x)
		min_corner.y = minf(min_corner.y,corner.y)
		max_corner.x = maxf(max_corner.x,corner.x)
		max_corner.y = maxf(max_corner.y,corner.y)
	var world_view_rect := Rect2(min_corner,max_corner - min_corner)

	# 用屏幕像素定义“再划出去一段”，不同地图 Camera zoom 下视觉长度保持接近。
	var pixel_scale_x:float = maxf(canvas_xform.basis_xform(Vector2.RIGHT).length(),0.001)
	var pixel_scale_y:float = maxf(canvas_xform.basis_xform(Vector2.DOWN).length(),0.001)
	var pixels_per_world:float = maxf(minf(pixel_scale_x,pixel_scale_y),0.001)
	var outside_margin_world:float = 140.0 / pixels_per_world
	var expanded_view:Rect2 = world_view_rect.grow(outside_margin_world)

	var scan_limit:float = maxf(
		fallback_distance,
		world_view_rect.size.length() * 1.8 + outside_margin_world * 2.0
	)
	var entered_view:bool = expanded_view.has_point(travel_origin)
	var last_inside_x:float = 0.0
	var scan_steps:int = 260
	for i:int in range(1,scan_steps + 1):
		var x:float = scan_limit * float(i) / float(scan_steps)
		var point:Vector2 = travel_origin + forward * x + lateral * _curve_y(x)
		if expanded_view.has_point(point):
			entered_view = true
			last_inside_x = x
		elif entered_view:
			return maxf(x,curve_span)
	return maxf(fallback_distance,last_inside_x)


func _start_move_audio() -> void:
	if move_audio != null and is_instance_valid(move_audio):
		move_audio.stop()
		move_audio.queue_free()
	var player := AudioStreamPlayer2D.new()
	player.name = "数学老师粉笔移动音效"
	var stream:AudioStream = CHALK_MOVE_SFX.duplicate(true) as AudioStream
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	player.stream = stream
	player.volume_db = 4.0
	player.max_distance = 1800.0
	player.attenuation = 0.35
	player.max_polyphony = 1
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	add_child(player)
	move_audio = player
	player.finished.connect(_on_move_audio_finished)
	player.play()


func _on_move_audio_finished() -> void:
	if move_audio != null and is_instance_valid(move_audio) and is_inside_tree() and not is_queued_for_deletion():
		move_audio.play()


func _damage_all_crossed_targets(from_pos:Vector2,to_pos:Vector2,facing_angle:float) -> void:
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not (raw is ball):
			continue
		var target:ball = raw as ball
		if target == owner_teacher or not target.is_combat_targetable():
			continue
		if hit_ids.has(target.get_instance_id()):
			continue
		if (
			not bool(Game.Game_Settings.get("Have_Team_Damage",false))
			and projectile_team != ""
			and target.Team != ""
			and target.Team == projectile_team
		):
			continue
		if not _chalk_sweep_hits_target(target,from_pos,to_pos,facing_angle):
			continue
		# V179：闪避只改变 Sans 自身；粉笔继续原路径，也不把 Sans 记进本弹的已命中列表。
		if target.has_method("try_full_projectile_dodge") and bool(target.call("try_full_projectile_dodge",self)):
			continue
		hit_ids[target.get_instance_id()] = true
		var final_damage:float = damage_amount
		if owner_teacher is ball and is_instance_valid(owner_teacher):
			final_damage = (owner_teacher as ball).effective_outgoing_damage(damage_amount)
		if final_damage <= 0.0:
			continue

		# V343：数学公式弹走自定义的图片矩形连续扫掠，不经过普通 hitbox，
		# 所以必须和项目其它子弹一样，在“实际掉血成功”后显式触发人物通用受击白线。
		# 白线只跟真实 health_loss 绑定：被完全防住、无敌、伤害被取消时都不凭空播放。
		var before_health:float = float(target.health)
		var before_block:float = float(target.block)
		var impact_point:Vector2 = target.global_position
		var dealt:bool = target.receive_spatial_damage(
			final_damage,
			{"point":impact_point,"source":owner_teacher},
			false,
			false
		)
		var health_loss:float = maxf(before_health - float(target.health),0.0)
		var block_loss:float = maxf(before_block - float(target.block),0.0)
		if dealt and health_loss > 0.0:
			var incoming:Vector2 = to_pos - from_pos
			if incoming.length_squared() <= 0.000001:
				incoming = forward
			incoming = incoming.normalized()
			var hit_seed:int = (
				int(Time.get_ticks_usec())
				^ int(get_instance_id())
				^ int(target.get_instance_id())
			)
			target.notify_hit_burst_feedback(
				impact_point,
				final_damage,
				health_loss,
				block_loss,
				_chalk_impact_cross_section(incoming),
				hit_seed,
				incoming
			)

		if dealt and owner_teacher != null and is_instance_valid(owner_teacher) and owner_teacher.has_method("_call_chalk_hit_audio"):
			owner_teacher.call("_call_chalk_hit_audio",impact_point)


func _chalk_sweep_hits_target(target:ball,from_pos:Vector2,to_pos:Vector2,facing_angle:float) -> bool:
	if chalk_rect_shape == null:
		return false
	# V432 性能：先用粗包围圆剔除明显够不到的目标，再对少数近距离目标做 find_children + 精确扫掠。
	# 保守半径 = 粉笔矩形半对角线 + 目标占据半径 + 200px 余量（覆盖 Boss 倍率放大后的碰撞体），不会漏掉任何原本能命中的目标。
	var segment_center:Vector2 = (from_pos + to_pos) * 0.5
	var reach:float = (to_pos - from_pos).length() * 0.5 + chalk_rect_shape.size.length() * 0.5 + _target_radius(target) * maxf(target.global_scale.length(),1.0) + 200.0
	if segment_center.distance_squared_to(target.global_position) > reach * reach:
		return false
	var start_xform:Transform2D = _chalk_shape_transform(from_pos,facing_angle)
	var motion:Vector2 = to_pos - from_pos
	var found_relevant_shape:bool = false
	for raw_shape:Node in target.find_children("*","CollisionShape2D",true,false):
		if not raw_shape is CollisionShape2D:
			continue
		var shape_node:CollisionShape2D = raw_shape as CollisionShape2D
		if shape_node.disabled or shape_node.shape == null:
			continue
		if _collision_shape_belongs_to_outgoing_hitbox(shape_node,target):
			continue
		found_relevant_shape = true
		if chalk_rect_shape.collide_with_motion(start_xform,motion,shape_node.shape,shape_node.global_transform,Vector2.ZERO):
			return true

	# 兼容没有正常 CollisionShape2D 的特殊 Ball：目标仍可用自身占据半径受击，
	# 但粉笔一侧始终使用图片矩形，不再回退到旧 16px 圆形粉笔判定。
	if not found_relevant_shape:
		var fallback := CircleShape2D.new()
		fallback.radius = _target_radius(target)
		return chalk_rect_shape.collide_with_motion(
			start_xform,motion,fallback,Transform2D(0.0,target.global_position),Vector2.ZERO
		)
	return false


func _chalk_impact_cross_section(incoming_direction:Vector2) -> float:
	# 给通用受击白线一个与当前粉笔图片真实尺寸一致的“命中横截面”。
	# 沿入射方向的垂直轴投影 RectangleShape2D，避免重新引入固定半径。
	if chalk_rect_shape == null:
		return 8.0
	var incoming:Vector2 = incoming_direction
	if incoming.length_squared() <= 0.000001:
		incoming = forward
	incoming = incoming.normalized()
	var tangent:Vector2 = Vector2(-incoming.y,incoming.x)
	var half:Vector2 = chalk_rect_shape.size * 0.5
	var xform:Transform2D = _chalk_shape_transform(global_position,rotation)
	var half_x:Vector2 = xform.x * half.x
	var half_y:Vector2 = xform.y * half.y
	return maxf(
		2.0 * (absf(half_x.dot(tangent)) + absf(half_y.dot(tangent))),
		1.0
	)


func _collision_shape_belongs_to_outgoing_hitbox(shape_node:CollisionShape2D,owner_ball:ball) -> bool:
	var node:Node = shape_node.get_parent()
	while node != null and node != owner_ball:
		if node is hurtbox:
			return false
		if node is hitbox:
			return true
		node = node.get_parent()
	return false


func _target_radius(target:ball) -> float:
	if target.has_method("get_crowd_separation_radius_world"):
		return clampf(float(target.call("get_crowd_separation_radius_world")),5.0,28.0)
	return 12.0
