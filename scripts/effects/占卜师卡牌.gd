extends Node2D

signal attack_contact(target:Node2D)

const CARD_ATTACK:int = 0
const CARD_DEFENSE:int = 1
const CARD_RECOVERY:int = 2
const CARD_WHEEL:int = 3

# V383：保留 V382 已缩小后的世界显示尺寸；素材本身可以很大，Sprite2D 会按此尺寸等比缩放。
const CARD_SIZE:Vector2 = Vector2(10.0,15.0)
# V92：保留 V91 的低速长追踪轨迹；修复红牌偶发“碰到占卜师自己就消失”的两条风险链。
# 1) 物理扫掠显式排除发牌者本体及其所有 CollisionObject2D 子节点；2) 飞出去的牌不再被攻击序列收尾统一清理。
# 牌的“上方”仍朝当前飞行方向；追踪结束后锁定当时方向，再平滑加速直飞。
const ATTACK_SWEEP_MIN_WIDTH:float = 7.0

const CARD_BACK_TEXTURE:Texture2D = preload("res://Images/characters/人物/占卜师/02_占卜卡牌背景.png")
const CARD_ATTACK_TEXTURE:Texture2D = preload("res://Images/characters/人物/占卜师/03_攻击占卜牌.png")
const CARD_DEFENSE_TEXTURE:Texture2D = preload("res://Images/characters/人物/占卜师/04_防御占卜牌.png")
const CARD_RECOVERY_TEXTURE:Texture2D = preload("res://Images/characters/人物/占卜师/05_治疗占卜牌.png")
const CARD_WHEEL_TEXTURE:Texture2D = preload("res://Images/characters/人物/占卜师/06_命运之轮占卜牌.png")

# 卡背保持中性金光，避免牌还没翻开时通过描边颜色提前泄露牌型。
const BACK_GLOW_COLOR:Color = Color(0.95,0.72,0.26,1.0)

var initial_type:int = CARD_ATTACK
var resolved_type:int = CARD_ATTACK
var face_up:bool = false
var draw_index:int = 0

var _face_sprite:Sprite2D = null
var _glow_inner:Sprite2D = null
var _glow_middle:Sprite2D = null
var _glow_outer:Sprite2D = null
var _additive_material:CanvasItemMaterial = null

var _flight_active:bool = false
var _flight_elapsed:float = 0.0
var _flight_duration:float = 0.8
var _flight_start:Vector2 = Vector2.ZERO
var _flight_end:Vector2 = Vector2.ZERO
var _flight_target_path:NodePath = NodePath("")
var _flight_target_cache:Node2D = null
var _curve_side:float = 1.0
var _curve_height:float = 62.0
var _homing_strength:float = 2.3
# V91：攻击红牌前段低速缓慢追踪时间加长；追踪结束后锁定方向并平滑加速直飞。
var _flight_velocity:Vector2 = Vector2.ZERO
var _flight_homing_time:float = 0.0
var _flight_accel_time:float = 0.0
var _flight_start_speed:float = 0.0
var _flight_cruise_speed:float = 0.0
var _flight_heading_angle:float = -PI * 0.5
var _flight_hit_emitted:bool = false
# V92：发射前从当前父链捕获真正的发牌者。之后即使红牌 reparent 到场景根，也能持续排除自己的 Body/Hurtbox。
var _flight_source_cache:CollisionObject2D = null
var _flight_source_exclude_rids:Array[RID] = []
# _flight_duration 只负责运动节奏；真正的安全寿命更长，避免慢速弧线尚未接触敌人就按动画时长直接消失。
var _flight_max_lifetime:float = 4.0


func _ready() -> void:
	z_index = 90
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_build_card_visuals()
	_refresh_visual()
	set_physics_process(false)


func setup(card_type:int,index:int = 0,start_face_up:bool = false) -> void:
	initial_type = clampi(card_type,CARD_ATTACK,CARD_WHEEL)
	resolved_type = initial_type
	draw_index = index
	face_up = start_face_up
	if is_inside_tree():
		_refresh_visual()


func set_resolved_type(card_type:int) -> void:
	resolved_type = clampi(card_type,CARD_ATTACK,CARD_WHEEL)
	if is_inside_tree():
		_refresh_visual()


func set_face_up(value:bool) -> void:
	face_up = value
	if is_inside_tree():
		_refresh_visual()


func animate_draw(target_position:Vector2,delay:float,duration:float) -> void:
	position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE
	modulate = Color.WHITE
	set_face_up(false)

	var safe_duration:float = maxf(duration,0.20)
	var move_tween:Tween = create_tween()
	move_tween.tween_interval(maxf(delay,0.0))
	move_tween.tween_property(self,"position",target_position,safe_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# 2D 中通过 X 方向压缩到接近 0 再展开，模拟卡牌绕 Y 轴旋转。
	# 只有真正转到正面时才显示对应颜色的发光描边，因此卡背不会提前泄露牌型。
	var flip_tween:Tween = create_tween()
	flip_tween.tween_interval(maxf(delay,0.0))
	var half_step:float = safe_duration / 10.0
	for _flip:int in range(5):
		flip_tween.tween_property(self,"scale:x",0.05,half_step).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		flip_tween.tween_callback(_toggle_face)
		flip_tween.tween_property(self,"scale:x",1.0,half_step).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	flip_tween.tween_callback(func(): set_face_up(true))


func animate_confirm(final_type:int,delay:float,duration:float) -> void:
	var target_type:int = clampi(final_type,CARD_ATTACK,CARD_WHEEL)
	var highlight:Color = color_for_type(target_type)
	var safe_duration:float = maxf(duration,0.20)
	var rise_time:float = safe_duration * 0.34
	var return_time:float = safe_duration - rise_time

	var scale_tween:Tween = create_tween()
	scale_tween.tween_interval(maxf(delay,0.0))
	scale_tween.tween_property(self,"scale",Vector2(1.24,1.24),rise_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 命运之轮在峰值处真正切换成被填补的牌图，同时发光颜色也同步切换。
	scale_tween.tween_callback(func(): set_resolved_type(target_type))
	scale_tween.tween_property(self,"scale",Vector2.ONE,return_time).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	var color_tween:Tween = create_tween()
	color_tween.tween_interval(maxf(delay,0.0))
	color_tween.tween_property(self,"modulate",highlight,rise_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	color_tween.tween_property(self,"modulate",Color.WHITE,return_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func animate_reorder(target_position:Vector2,delay:float,duration:float) -> void:
	var tween:Tween = create_tween()
	tween.tween_interval(maxf(delay,0.0))
	tween.tween_property(self,"position",target_position,maxf(duration,0.12)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func animate_consume(card_type:int,delay:float,duration:float) -> void:
	var target_color:Color = color_for_type(card_type)
	var safe_duration:float = maxf(duration,0.25)
	var rise_time:float = safe_duration * 0.42
	var vanish_time:float = safe_duration - rise_time

	var scale_tween:Tween = create_tween()
	scale_tween.tween_interval(maxf(delay,0.0))
	scale_tween.tween_property(self,"scale",Vector2(1.34,1.34),rise_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	scale_tween.tween_property(self,"scale",Vector2(0.18,0.18),vanish_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	scale_tween.tween_callback(queue_free)

	var color_tween:Tween = create_tween()
	color_tween.tween_interval(maxf(delay,0.0))
	color_tween.tween_property(self,"modulate",target_color,rise_time)
	color_tween.tween_property(self,"modulate",Color(target_color.r,target_color.g,target_color.b,0.0),vanish_time)


func animate_jackpot(delay:float,duration:float) -> void:
	var safe_duration:float = maxf(duration,0.45)
	var golden:Color = Color(1.0,0.78,0.20,1.0)
	# 四命运之轮大奖前，牌本体仍然是命运之轮，静态描边基础色保持蓝色。
	_set_glow_color(color_for_type(CARD_WHEEL))
	var tween:Tween = create_tween()
	tween.tween_interval(maxf(delay,0.0))
	tween.tween_property(self,"scale",Vector2(1.42,1.42),safe_duration * 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self,"modulate",golden,safe_duration * 0.35)
	tween.tween_property(self,"scale",Vector2(1.08,1.08),safe_duration * 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self,"modulate",Color(golden.r,golden.g,golden.b,0.0),safe_duration * 0.40)
	tween.parallel().tween_property(self,"scale",Vector2(1.70,1.70),safe_duration * 0.40).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(queue_free)


func start_attack_flight(
	target_path:NodePath,
	fallback_target:Vector2,
	delay:float,
	duration:float,
	curve_side:float,
	curve_height:float,
	homing_strength:float
) -> void:
	if maxf(delay,0.0) > 0.0:
		await get_tree().create_timer(maxf(delay,0.0)).timeout
	if not is_inside_tree() or is_queued_for_deletion():
		return
	var scene:Node = get_tree().current_scene
	if scene == null:
		queue_free()
		return

	# V92：必须在 reparent 之前捕获发牌者。TarotCardLayer 虽然 top-level，但父链仍然是 红牌 -> TarotCardLayer -> 占卜师。
	# 这样物理扫掠可以用 PhysicsShapeQueryParameters2D.exclude 显式排除占卜师自己的 Body / Hurtbox / 其他 Area2D。
	_flight_source_cache = _find_source_collision_owner()
	_flight_source_exclude_rids = _collect_collision_rids(_flight_source_cache)

	# 只切换父节点，不重算起点：reparent(..., true) 会保持红牌此刻真实的全局位置。
	# 因此牌从抽牌/重排后当前所在的位置直接飞出，不会先吸附到敌人或别的位置。
	reparent(scene,true)
	reset_physics_interpolation()
	set_as_top_level(true)
	z_index = 95
	set_face_up(true)
	set_resolved_type(CARD_ATTACK)
	modulate = Color.WHITE
	scale = Vector2.ONE

	_flight_active = true
	_flight_hit_emitted = false
	_flight_elapsed = 0.0
	_flight_duration = maxf(duration,0.65)
	# 不再把“运动参数时长”当作硬销毁时刻。弧线/追踪可能让实际路程比初始直线距离更长。
	_flight_max_lifetime = maxf(_flight_duration * 3.0,4.0)
	_flight_start = global_position
	_flight_end = fallback_target
	_flight_target_path = target_path
	_flight_target_cache = _resolve_flight_target()
	_curve_side = -1.0 if curve_side < 0.0 else 1.0
	_curve_height = maxf(curve_height,0.0)
	_homing_strength = maxf(homing_strength,0.0)

	# V91 三段节奏：
	# 1) 低速飞出 + 长时间缓慢追踪；2) 锁定当前方向 + 平滑加速；3) 保持该方向匀速直飞。
	# V90 默认 1.15 秒飞行中追踪只有约 0.40 秒，牌只来得及偏转一点就锁向。
	# V91 默认 1.45 秒飞行中追踪约 0.84 秒，让缓慢转向真正有足够时间形成明显弧线。
	_flight_homing_time = clampf(_flight_duration * 0.58,0.75,0.90)
	_flight_accel_time = clampf(_flight_duration * 0.22,0.26,0.32)

	var launch_chord:Vector2 = _flight_end - _flight_start
	if launch_chord.length_squared() <= 0.000001:
		launch_chord = Vector2.UP
	var launch_distance:float = maxf(launch_chord.length(),1.0)

	# 起手方向严格读取红牌当前牌面的“上方”，不在发射帧直接朝敌人瞬间转正。
	# Sprite2D 默认上方是 Vector2.UP；当前 global_rotation 转换后即为牌面此刻真正朝向。
	var current_up:Vector2 = Vector2.UP.rotated(global_rotation)
	if current_up.length_squared() <= 0.000001:
		current_up = Vector2.UP
	_flight_heading_angle = current_up.normalized().angle()

	# 初速只取最终巡航速度的一小部分；追踪阶段结束以后才开始加速。
	# 根据三段持续时间反推巡航速度，使整体仍大致能覆盖初始目标距离，但比 V84/V89 更慢、更有起步感。
	var start_ratio:float = 0.28
	var remaining_time:float = maxf(_flight_duration - _flight_homing_time - _flight_accel_time,0.0)
	var distance_factor:float = (
		start_ratio * _flight_homing_time
		+ 0.5 * (start_ratio + 1.0) * _flight_accel_time
		+ remaining_time
	)
	_flight_cruise_speed = maxf(launch_distance / maxf(distance_factor,0.20),78.0)
	_flight_start_speed = maxf(_flight_cruise_speed * start_ratio,22.0)
	_flight_velocity = Vector2.from_angle(_flight_heading_angle) * _flight_start_speed
	global_rotation = _flight_heading_angle + PI * 0.5
	set_physics_process(true)


func _physics_process(delta:float) -> void:
	if not _flight_active:
		return
	_flight_elapsed += delta

	var current_speed:float = _flight_start_speed
	if _flight_elapsed <= _flight_homing_time:
		# 飞出去以后才追踪：位置一直在移动，但转向是缓慢插值，不会直接把角度吸到敌人身上。
		var target:Node2D = _resolve_flight_target()
		var wanted_position:Vector2 = target.global_position if target != null else _flight_end
		var to_target:Vector2 = wanted_position - global_position
		if to_target.length_squared() > 0.000001:
			var wanted_angle:float = to_target.angle()
			# 比 V84 原来的 *3.0 响应明显慢，牌面能看见逐渐旋过去的过程。
			var turn_weight:float = 1.0 - exp(-maxf(_homing_strength,0.01) * 1.15 * delta)
			_flight_heading_angle = lerp_angle(
				_flight_heading_angle,
				wanted_angle,
				clampf(turn_weight,0.0,1.0)
			)
	else:
		# 追踪结束后不再读取敌人位置。先从低速平滑加到巡航速度，再保持锁定方向直飞。
		var accel_elapsed:float = _flight_elapsed - _flight_homing_time
		if _flight_accel_time > 0.000001 and accel_elapsed < _flight_accel_time:
			var accel_t:float = clampf(accel_elapsed / _flight_accel_time,0.0,1.0)
			# smoothstep：起加速和收加速都没有速度突跳。
			var smooth_t:float = accel_t * accel_t * (3.0 - 2.0 * accel_t)
			current_speed = lerpf(_flight_start_speed,_flight_cruise_speed,smooth_t)
		else:
			current_speed = _flight_cruise_speed

	_flight_velocity = Vector2.from_angle(_flight_heading_angle) * current_speed
	var old_position:Vector2 = global_position
	var new_position:Vector2 = old_position + _flight_velocity * delta
	var contacted_target:Node2D = _sweep_attack_contact(old_position,new_position)
	if contacted_target != null:
		# 仍然是“第一次实际接触就立刻伤害”，不会因为轨迹动画而延迟到穿过目标以后。
		_flight_active = false
		_flight_hit_emitted = true
		attack_contact.emit(contacted_target)
		queue_free()
		return

	global_position = new_position
	# 牌面上方和当前飞行方向一致；追踪阶段慢慢转，锁向后保持不变。
	global_rotation = _flight_heading_angle + PI * 0.5

	# V92：只有达到独立安全寿命才兜底清理。正常情况下仍应由真实命中先销毁。
	if _flight_elapsed >= _flight_max_lifetime:
		_flight_active = false
		queue_free()


func _sweep_attack_contact(from_position:Vector2,to_position:Vector2) -> Node2D:
	var intended_target:Node2D = _resolve_flight_target()
	if intended_target == null or not is_instance_valid(intended_target):
		return null
	# 即使某个异常 NodePath 在运行时解析成发牌者自身，也绝不允许把自己当作攻击目标。
	if _flight_source_cache != null and is_instance_valid(_flight_source_cache) and intended_target == _flight_source_cache:
		return null
	var world:World2D = get_world_2d()
	if world == null:
		return null

	var segment:Vector2 = to_position - from_position
	var segment_length:float = segment.length()
	var direction:Vector2 = segment.normalized() if segment_length > 0.000001 else Vector2.RIGHT
	var sweep_shape := RectangleShape2D.new()
	# 红牌长边朝飞行方向；矩形同时覆盖本体长度与这一物理帧全部位移。
	sweep_shape.size = Vector2(maxf(segment_length + CARD_SIZE.y,CARD_SIZE.y),maxf(CARD_SIZE.x,ATTACK_SWEEP_MIN_WIDTH))
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = sweep_shape
	query.transform = Transform2D(direction.angle(),(from_position + to_position) * 0.5)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	query.collision_mask = 0xFFFFFFFF
	# Godot 的 shape query 支持按 RID 排除。这里排除占卜师根 CharacterBody2D 以及它下面所有 Hurtbox/Area2D，
	# 防止红牌刚从人物附近飞出时自己的碰撞体进入查询结果，更不会因为自身复杂碰撞体挤满结果列表而漏掉目标。
	query.exclude = _flight_source_exclude_rids

	var hits:Array[Dictionary] = world.direct_space_state.intersect_shape(query,96)
	for hit:Dictionary in hits:
		var raw = hit.get("collider")
		if not raw is Node:
			continue
		if _node_belongs_to_target(raw as Node,intended_target):
			return intended_target
	return null


func _node_belongs_to_target(node:Node,target:Node) -> bool:
	var cursor:Node = node
	while cursor != null:
		if cursor == target:
			return true
		cursor = cursor.get_parent()
	return false


func _find_source_collision_owner() -> CollisionObject2D:
	var cursor:Node = get_parent()
	while cursor != null:
		if cursor is CollisionObject2D:
			return cursor as CollisionObject2D
		cursor = cursor.get_parent()
	return null


func _collect_collision_rids(root:Node) -> Array[RID]:
	var result:Array[RID] = []
	if root == null or not is_instance_valid(root):
		return result
	var stack:Array[Node] = [root]
	while not stack.is_empty():
		var current:Node = stack.pop_back()
		if current is CollisionObject2D:
			result.append((current as CollisionObject2D).get_rid())
		for child:Node in current.get_children():
			stack.append(child)
	return result


func _resolve_flight_target() -> Node2D:
	if _flight_target_cache != null and is_instance_valid(_flight_target_cache) and _flight_target_cache.is_inside_tree():
		if _flight_source_cache == null or _flight_target_cache != _flight_source_cache:
			return _flight_target_cache
		_flight_target_cache = null
	if _flight_target_path.is_empty() or get_tree().root == null:
		return null
	var node:Node = get_tree().root.get_node_or_null(_flight_target_path)
	if node is Node2D and is_instance_valid(node) and node.is_inside_tree():
		# 路径异常解析到发牌者自己时拒绝锁定，继续按 fallback 方向飞，不把自己当成命中目标。
		if _flight_source_cache != null and node == _flight_source_cache:
			return null
		_flight_target_cache = node as Node2D
		return _flight_target_cache
	return null


func _toggle_face() -> void:
	set_face_up(not face_up)


func _build_card_visuals() -> void:
	if _face_sprite != null:
		return

	_additive_material = CanvasItemMaterial.new()
	_additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_additive_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED

	# 三层同贴图、略微放大的加法混合副本形成柔和发光描边。
	# 主牌图最后绘制在最上方，因此不会把整张牌染色，只露出轮廓外沿。
	_glow_outer = _make_sprite(-3)
	_glow_outer.material = _additive_material
	add_child(_glow_outer)

	_glow_middle = _make_sprite(-2)
	_glow_middle.material = _additive_material
	add_child(_glow_middle)

	_glow_inner = _make_sprite(-1)
	_glow_inner.material = _additive_material
	add_child(_glow_inner)

	_face_sprite = _make_sprite(0)
	add_child(_face_sprite)


func _make_sprite(relative_z:int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.centered = true
	sprite.z_index = relative_z
	sprite.z_as_relative = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return sprite


func _refresh_visual() -> void:
	if _face_sprite == null:
		return
	var texture:Texture2D = _current_texture()
	_face_sprite.texture = texture
	_glow_inner.texture = texture
	_glow_middle.texture = texture
	_glow_outer.texture = texture

	var base_scale:Vector2 = _scale_for_texture(texture)
	_face_sprite.scale = base_scale
	_glow_inner.scale = base_scale * 1.08
	_glow_middle.scale = base_scale * 1.17
	_glow_outer.scale = base_scale * 1.29

	var glow_color:Color = color_for_type(resolved_type) if face_up else BACK_GLOW_COLOR
	_set_glow_color(glow_color)


func _current_texture() -> Texture2D:
	if not face_up:
		return CARD_BACK_TEXTURE
	return _texture_for_type(resolved_type)


func _texture_for_type(card_type:int) -> Texture2D:
	match card_type:
		CARD_ATTACK:
			return CARD_ATTACK_TEXTURE
		CARD_DEFENSE:
			return CARD_DEFENSE_TEXTURE
		CARD_RECOVERY:
			return CARD_RECOVERY_TEXTURE
		CARD_WHEEL:
			return CARD_WHEEL_TEXTURE
	return CARD_BACK_TEXTURE


func _scale_for_texture(texture:Texture2D) -> Vector2:
	if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0:
		return Vector2.ONE
	return Vector2(
		CARD_SIZE.x / float(texture.get_width()),
		CARD_SIZE.y / float(texture.get_height())
	)


func _set_glow_color(base:Color) -> void:
	if _glow_inner == null:
		return
	_glow_inner.modulate = Color(base.r,base.g,base.b,0.58)
	_glow_middle.modulate = Color(base.r,base.g,base.b,0.33)
	_glow_outer.modulate = Color(base.r,base.g,base.b,0.17)


func color_for_type(card_type:int) -> Color:
	match card_type:
		CARD_ATTACK:
			return Color(1.0,0.18,0.14,1.0)
		CARD_DEFENSE:
			return Color(0.90,0.95,1.0,1.0)
		CARD_RECOVERY:
			return Color(0.20,1.0,0.40,1.0)
		CARD_WHEEL:
			# V383：命运之轮按用户要求固定为蓝色发光。
			return Color(0.18,0.52,1.0,1.0)
	return Color.WHITE
