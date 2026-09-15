extends CharacterBody2D

enum DropKind {
	COIN,
	CAR_KEY,
	PROPERTY_DEED,
}

const COIN_TEXTURE:Texture2D = preload("res://Images/characters/人物/领导/金币(2).png")
const CAR_KEY_TEXTURE:Texture2D = preload("res://Images/characters/人物/领导/车钥匙 - 副本.png")
const PROPERTY_DEED_TEXTURE:Texture2D = preload("res://Images/characters/人物/领导/房产证 - 副本.png")

var owner_leader:Node = null
var authoritative_logic:bool = false
var drop_id:String = ""
var kind:int = DropKind.COIN
var drop_team:String = ""
var start_position:Vector2 = Vector2.ZERO
var ground_position:Vector2 = Vector2.ZERO
var arc_duration:float = 0.72
var arc_height:float = 58.0
var pickup_radius:float = 18.0
var pickup_grace:float = 0.70
var boundary_bounce:float = 0.72
var launch_velocity:Vector2 = Vector2.ZERO
var launch_gravity:float = 0.0
var return_speed:float = 260.0
var elapsed:float = 0.0
var landed:bool = false
var resolved:bool = false
var returning:bool = false
var return_picker_path:NodePath = NodePath()
var ground_elapsed:float = 0.0
var ground_lifetime:float = 14.0
var spin_speed:float = 0.0

# V84：领导掉落物改用“重力弹球”同款运动模型。
# 出生即有随机初速度方向（方向仍由领导生成的随机落点决定），持续受重力；
# 撞地图按法线反弹并损失能量，落地后靠摩擦继续滑动，真正低速后才进入可拾取的 landed 状态。
const BOUNCY_INITIAL_SPEED_MIN:float = 260.0
const BOUNCY_INITIAL_SPEED_MAX:float = 420.0
const BOUNCY_GRAVITY:float = 720.0
const BOUNCY_AIR_DRAG:float = 0.16
const BOUNCY_GROUND_FRICTION:float = 320.0
const BOUNCY_SETTLE_SPEED:float = 18.0
const BOUNCY_SETTLE_VERTICAL_SPEED:float = 46.0
const BOUNCY_SETTLE_CONTACT_FRAMES:int = 5
const BOUNCY_COLLISION_TANGENT_FRICTION:float = 0.08
var _ground_contact_frames:int = 0

# V346：掉落物缩回 14/18/22px；飞行阶段使用 CharacterBody2D 真实碰撞反弹，落地后仍保留展示期。
const MAP_SAFE_MARGIN:float = 12.0
var _map_rect:Rect2 = Rect2()
var _has_map_rect:bool = false

@onready var render_pivot:Node2D = $RenderPivot
@onready var visual:Sprite2D = $RenderPivot/Visual
@onready var collision_shape:CollisionShape2D = $CollisionShape2D

# V348：物理根只在 physics tick 中运动；图片单独追随物理根，减轻高刷新率下的阶梯感。
var _render_world_position:Vector2 = Vector2.ZERO
var _render_world_rotation:float = 0.0
var _render_initialized:bool = false
const RENDER_POSITION_SMOOTH:float = 28.0
const RENDER_ROTATION_SMOOTH:float = 24.0
const MAX_BOUNCES_PER_TICK:int = 4


func configure(owner_node:Node,config:Dictionary,is_authority:bool) -> void:
	owner_leader = owner_node
	authoritative_logic = is_authority
	drop_id = str(config.get("id","0"))
	kind = clampi(int(config.get("kind",0)),0,2)
	drop_team = str(config.get("team",""))
	start_position = config.get("start",global_position)
	ground_position = config.get("ground",start_position)
	_refresh_map_rect()
	start_position = _clamp_to_map(start_position)
	arc_duration = maxf(float(config.get("arc_duration",0.72)),0.05)
	arc_height = maxf(float(config.get("arc_height",58.0)),0.0)
	pickup_radius = maxf(float(config.get("pickup_radius",18.0)),2.0)
	pickup_grace = maxf(float(config.get("pickup_grace",0.70)),0.0)
	boundary_bounce = clampf(float(config.get("boundary_bounce",0.72)),0.0,1.2)
	return_speed = maxf(float(config.get("return_speed",260.0)),20.0)
	spin_speed = float(config.get("spin_speed",0.0))
	global_position = start_position
	z_as_relative = false
	z_index = 104
	add_to_group("BattleTransient")
	_apply_visual()
	_prepare_launch_physics()
	_render_world_position = global_position
	_render_world_rotation = rotation
	_render_initialized = true
	if render_pivot != null:
		render_pivot.global_position = _render_world_position
		render_pivot.global_rotation = _render_world_rotation


func _apply_visual() -> void:
	if visual == null:
		return
	var texture:Texture2D = COIN_TEXTURE
	var target_size:float = 14.0
	match kind:
		DropKind.COIN:
			texture = COIN_TEXTURE
			target_size = 14.0
		DropKind.CAR_KEY:
			texture = CAR_KEY_TEXTURE
			target_size = 18.0
		_:
			texture = PROPERTY_DEED_TEXTURE
			target_size = 22.0
	visual.texture = texture
	visual.visible = true
	var tex_size:Vector2 = texture.get_size()
	var max_dimension:float = maxf(maxf(tex_size.x,tex_size.y),1.0)
	var scale_value:float = target_size / max_dimension
	visual.scale = Vector2.ONE * scale_value
	if collision_shape != null:
		var rect := RectangleShape2D.new()
		rect.size = Vector2(maxf(tex_size.x * scale_value,2.0),maxf(tex_size.y * scale_value,2.0))
		collision_shape.shape = rect


func _prepare_launch_physics() -> void:
	# V84：不再按 arc_duration 到点强制落地，而是与“弹球.gd”一样真正靠速度、重力和碰撞运动。
	# 领导本体已经为 ground_position 选了随机 360° 方向；这里用 drop_id 生成稳定随机初速度，
	# 确保多人模式每个 peer 得到同一初速度，不因本地 randf() 各自漂移。
	var launch_direction:Vector2 = ground_position - start_position
	var launch_rng := RandomNumberGenerator.new()
	launch_rng.seed = maxi(abs(int(drop_id.hash())),1)
	if launch_direction.length_squared() <= 0.000001:
		launch_direction = Vector2.RIGHT.rotated(launch_rng.randf_range(0.0,TAU))
	else:
		launch_direction = launch_direction.normalized()
	var launch_speed:float = launch_rng.randf_range(BOUNCY_INITIAL_SPEED_MIN,BOUNCY_INITIAL_SPEED_MAX)
	launch_velocity = launch_direction * launch_speed
	launch_gravity = BOUNCY_GRAVITY
	velocity = launch_velocity
	_ground_contact_frames = 0


func _physics_process(delta:float) -> void:
	if owner_leader == null or not is_instance_valid(owner_leader):
		queue_free()
		return

	if returning:
		_update_return(delta)
		return

	if not landed:
		elapsed += delta
		velocity.y += launch_gravity * delta
		if BOUNCY_AIR_DRAG > 0.0:
			velocity *= exp(-BOUNCY_AIR_DRAG * delta)

		var touched_ground:bool = false
		# V84：和弹球一样，一个 physics tick 可以连续处理多个剩余反弹。
		var remaining:Vector2 = velocity * delta
		for _bounce_index:int in range(MAX_BOUNCES_PER_TICK):
			if remaining.length_squared() <= 0.000001:
				break
			var collision:KinematicCollision2D = move_and_collide(remaining)
			if collision == null:
				break
			var normal:Vector2 = collision.get_normal()
			if normal.length_squared() <= 0.000001:
				break
			normal = normal.normalized()
			if normal.y < -0.55:
				touched_ground = true
			if velocity.dot(normal) < 0.0:
				velocity = velocity.bounce(normal) * clampf(boundary_bounce,0.0,1.0)
				var normal_component:Vector2 = normal * velocity.dot(normal)
				var tangent_component:Vector2 = velocity - normal_component
				velocity = normal_component + tangent_component * (1.0 - BOUNCY_COLLISION_TANGENT_FRICTION)
			remaining = collision.get_remainder().bounce(normal) * clampf(boundary_bounce,0.0,1.0)

		# V85：第一次真正撞到地面后立即停止自转；侧墙反弹仍可继续旋转。
		# 同时把渲染插值角度立即对齐，避免 RenderPivot 还追赶旧角度而产生“落地后还在转”的错觉。
		if touched_ground and spin_speed != 0.0:
			spin_speed = 0.0
			_render_world_rotation = rotation
			if render_pivot != null:
				render_pivot.global_rotation = rotation

		# 原来的轻微缩放/飞行旋转视觉保留，但不再用 arc_duration 作为“强制落地计时器”。
		var t:float = clampf(elapsed / maxf(arc_duration,0.05),0.0,1.0)
		var visual_scale:float = 1.0 + 0.12 * sin(PI * t)
		if render_pivot != null:
			render_pivot.scale = Vector2.ONE * visual_scale
		rotation += spin_speed * delta

		# 与重力弹球一致：落地后的微小竖直跳动先归零，再用地面摩擦耗尽横向速度。
		if touched_ground and absf(velocity.y) <= BOUNCY_SETTLE_VERTICAL_SPEED:
			velocity.y = 0.0
			velocity.x = move_toward(velocity.x,0.0,BOUNCY_GROUND_FRICTION * delta)
			_ground_contact_frames += 1
		else:
			_ground_contact_frames = 0

		if _ground_contact_frames >= BOUNCY_SETTLE_CONTACT_FRAMES and velocity.length() <= BOUNCY_SETTLE_SPEED:
			landed = true
			velocity = Vector2.ZERO
			ground_elapsed = 0.0
			# V85：真正落地的这一帧就冻结旋转。以前根 rotation 已停止增加，
			# 但 RenderPivot 还会继续插值追赶最后角度，看起来像“落地后仍在转”。
			spin_speed = 0.0
			_render_world_rotation = rotation
			_render_world_position = global_position
			if render_pivot != null:
				render_pivot.scale = Vector2.ONE
				render_pivot.global_rotation = rotation
				render_pivot.global_position = global_position
			return

	ground_elapsed += delta
	# V345：落地后强制展示一段时间。以前领导自己可能在物品刚落地的第一帧就把它捡回去，
	# 实战看起来像“根本没有掉东西”。展示期内任何人物都不能拾取。
	if authoritative_logic and not resolved and ground_elapsed >= pickup_grace:
		var picker:ball = _nearest_picker()
		if picker != null and owner_leader.has_method("_on_drop_picked"):
			resolved = true
			owner_leader.call("_on_drop_picked",drop_id,kind,picker)
			return
	if ground_elapsed >= ground_lifetime:
		queue_free()


func resolve_pickup(resolution:String,picker:Node) -> void:
	resolved = true
	match resolution:
		"hostile_return":
			returning = true
			return_picker_path = picker.get_path() if picker is ball and is_instance_valid(picker) and picker.is_inside_tree() else NodePath()
			landed = true
			z_index = 105
		_:
			queue_free()


func _update_return(delta:float) -> void:
	if owner_leader == null or not is_instance_valid(owner_leader):
		queue_free()
		return
	var target_position:Vector2 = _clamp_to_map((owner_leader as Node2D).global_position)
	var distance:float = global_position.distance_to(target_position)
	var step:float = return_speed * delta
	if distance <= maxf(step,7.0):
		global_position = target_position
		if authoritative_logic and owner_leader.has_method("_on_hostile_drop_arrived"):
			# V348：不要把几百毫秒前保存的 Object 引用传回去。
			# 按 NodePath 在到达这一刻重新解析；原拾取者已经死亡/释放时传 null。
			var current_picker:Variant = null
			if not return_picker_path.is_empty():
				var candidate:Node = get_node_or_null(return_picker_path)
				if candidate is ball and is_instance_valid(candidate):
					current_picker = candidate
			owner_leader.call("_on_hostile_drop_arrived",kind,current_picker)
		queue_free()
		return
	var dir:Vector2 = (target_position - global_position).normalized()
	global_position = _clamp_to_map(global_position + dir * step)
	rotation += delta * 7.0



func _process(delta:float) -> void:
	if render_pivot == null or not is_instance_valid(render_pivot):
		return
	if not _render_initialized:
		_render_world_position = global_position
		_render_world_rotation = rotation
		_render_initialized = true

	# 指数趋近比固定 lerp 比例更不受帧率影响。
	var pos_weight:float = 1.0 - exp(-RENDER_POSITION_SMOOTH * maxf(delta,0.0))
	var rot_weight:float = 1.0 - exp(-RENDER_ROTATION_SMOOTH * maxf(delta,0.0))
	_render_world_position = _render_world_position.lerp(global_position,clampf(pos_weight,0.0,1.0))
	_render_world_rotation = lerp_angle(_render_world_rotation,rotation,clampf(rot_weight,0.0,1.0))
	render_pivot.global_position = _render_world_position
	render_pivot.global_rotation = _render_world_rotation


func _refresh_map_rect() -> void:
	_has_map_rect = false
	_map_rect = Rect2()
	var world:Node = get_tree().current_scene
	if world == null or not world.has_method("return_map_world_rect"):
		return
	var map_group_value:Variant = world.get("map_group")
	var map_index:int = int(world.get("now_choose_map"))
	if not (map_group_value is Array) or map_index < 0 or map_index >= (map_group_value as Array).size():
		return
	var map_node:Variant = (map_group_value as Array)[map_index]
	if not (map_node is TileMapLayer):
		return
	var rect:Rect2 = world.call("return_map_world_rect",map_node)
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	_map_rect = rect.abs()
	_has_map_rect = true


func _clamp_to_map(point:Vector2) -> Vector2:
	if not _has_map_rect:
		return point
	var margin_x:float = minf(MAP_SAFE_MARGIN,maxf(_map_rect.size.x * 0.45,0.0))
	var margin_y:float = minf(MAP_SAFE_MARGIN,maxf(_map_rect.size.y * 0.45,0.0))
	return Vector2(
		clampf(point.x,_map_rect.position.x + margin_x,_map_rect.end.x - margin_x),
		clampf(point.y,_map_rect.position.y + margin_y,_map_rect.end.y - margin_y)
	)


func _nearest_picker() -> ball:
	var best:ball = null
	var best_dist_sq:float = INF
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not (raw is ball):
			continue
		var candidate:ball = raw as ball
		if not candidate.is_combat_targetable():
			continue
		# V320：拾取判定不再用固定 pickup_radius 圆兜底冒充图片碰撞。
		# 使用 Sprite2D 本地坐标 + is_pixel_opaque() 检查实际不透明图片范围，并给人物实体半径做周向采样。
		if not _picker_overlaps_visible_image(candidate):
			continue
		var dist_sq:float = global_position.distance_squared_to(candidate.global_position)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = candidate
	return best


func _picker_overlaps_visible_image(candidate:ball) -> bool:
	if visual == null or visual.texture == null:
		return global_position.distance_to(candidate.global_position) <= pickup_radius + _target_radius_world(candidate)

	var target_radius:float = _target_radius_world(candidate)
	var visual_radius:float = _visual_world_radius()
	if global_position.distance_to(candidate.global_position) > visual_radius + target_radius + 3.0:
		return false

	var samples := PackedVector2Array()
	samples.append(candidate.global_position)
	var ring_samples:int = 12
	for radius_scale:float in [0.5,1.0]:
		for i:int in range(ring_samples):
			var angle:float = TAU * float(i) / float(ring_samples)
			samples.append(candidate.global_position + Vector2(cos(angle),sin(angle)) * target_radius * radius_scale)

	var rect:Rect2 = visual.get_rect()
	for world_point:Vector2 in samples:
		var local_point:Vector2 = visual.to_local(world_point)
		if not rect.has_point(local_point):
			continue
		if visual.is_pixel_opaque(local_point):
			return true
	return false


func _visual_world_radius() -> float:
	if visual == null or visual.texture == null:
		return pickup_radius
	var rect:Rect2 = visual.get_rect()
	var local_radius:float = rect.size.length() * 0.5
	var raw_scale:Vector2 = visual.global_transform.get_scale()
	var world_scale:Vector2 = Vector2(absf(raw_scale.x),absf(raw_scale.y))
	return local_radius * maxf(world_scale.x,world_scale.y)


func _target_radius_world(candidate:ball) -> float:
	if candidate.has_method("get_crowd_separation_radius_world"):
		return clampf(float(candidate.call("get_crowd_separation_radius_world")),5.0,32.0)
	return 12.0
