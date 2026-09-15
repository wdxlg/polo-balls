extends ball

const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const TRAINER_AUDIO = preload("res://scripts/audio/训犬师音效.gd")

enum DogMode { FOLLOW, GUARD, HUNT, RETURN }

@export_category("训犬师的狗 - 视觉")
@export var normal_texture:Texture2D
@export var bite_texture:Texture2D
@export_range(0.05,1.0,0.05) var bite_visual_duration:float = 0.22
@export_range(80.0,320.0,5.0) var visual_local_max_size:float = 205.0

@export_category("训犬师的狗")
@export_range(20.0,200.0,2.0) var follow_distance:float = 54.0
@export_range(8.0,120.0,1.0) var follow_back_offset:float = 38.0
@export_range(-80.0,80.0,1.0) var follow_side_offset:float = 20.0
@export_range(20.0,240.0,2.0) var follow_slow_radius:float = 96.0
@export_range(2.0,40.0,1.0) var follow_stop_radius:float = 10.0
@export_range(0.0,0.6,0.01) var follow_prediction_time:float = 0.18
@export_range(1.0,30.0,0.5) var turn_response:float = 11.0
@export_range(20.0,180.0,2.0) var guard_notice_radius:float = 56.0
@export_range(12.0,100.0,1.0) var bite_range:float = 42.0
@export_range(0.0,10.0,0.05) var bite_damage_multiplier:float = 1.0
@export var bite_hitbox_size:Vector2 = Vector2(42.0,84.0)
@export_range(0.0,80.0,1.0) var bite_hitbox_forward_offset:float = 21.0
@export_range(0.03,0.40,0.01) var bite_hitbox_active_time:float = 0.12
@export_range(0.0,0.5,0.01) var bite_cooldown:float = 0.12
@export_range(40.0,180.0,2.0) var continuous_attack_owner_radius:float = 96.0
@export_range(4.0,60.0,1.0) var post_attack_return_radius:float = 18.0
@export_range(0.0,40.0,1.0) var bite_knockback_distance:float = 10.0
@export_range(0.0,800.0,10.0) var bite_knockback_speed:float = 240.0
@export_range(0.5,10.0,0.1) var hunt_timeout:float = 4.0
@export_range(40.0,500.0,5.0) var hunt_speed:float = 205.0
@export_range(40.0,400.0,5.0) var follow_speed:float = 145.0
@export_range(8.0,80.0,1.0) var pack_avoid_radius:float = 34.0
@export_range(0.0,3.0,0.05) var pack_avoid_weight:float = 1.15
@export_range(8.0,80.0,1.0) var owner_avoid_radius:float = 30.0
@export_range(0.0,3.0,0.05) var owner_avoid_weight:float = 0.85

@export_category("训犬师的狗 - 跟随空间恢复")
@export_range(10.0,60.0,1.0) var follow_space_clearance_radius:float = 18.0
@export_range(32.0,140.0,2.0) var follow_staging_owner_radius:float = 62.0
@export_range(0.10,2.0,0.05) var follow_ideal_clear_hold_time:float = 0.45
@export_range(1.0,20.0,0.5) var follow_target_response:float = 7.5
@export_range(12.0,80.0,2.0) var follow_recovery_step:float = 42.0

@onready var bite_area:Area2D = $BiteArea
@onready var bite_shape:CollisionShape2D = $BiteArea/CollisionShape2D
@onready var character_image:Sprite2D = $Graphics/Image

var owner_trainer:ball = null
var mode:DogMode = DogMode.FOLLOW
var hunt_target:ball = null
var _hunt_left:float = 0.0
var _bite_attack_left:float = 0.0
var _bite_cooldown_left:float = 0.0
var _bite_hitbox_left:float = 0.0
var _bite_hitbox_direction:Vector2 = Vector2.RIGHT
var _bite_intended_target:ball = null
var _bite_damage_resolved:bool = false
var _return_after_bite:bool = false
var _return_after_bite_from_hunt:bool = false
var _post_attack_return_required:bool = false
var _dead_started:bool = false
var _last_owner_forward:Vector2 = Vector2.RIGHT
var _visual_serial:int = 0
var _follow_recovery_active:bool = false
var _follow_smoothed_target:Vector2 = Vector2.ZERO
var _follow_smoothed_target_ready:bool = false
var _follow_ideal_clear_time:float = 0.0

# V205：公共 ball.has_collision_damage() 对 Creature 会无条件返回 true，
# 所以仅把 Has_Collision_Damage 设为 false 并不足以关闭猎犬身体接触伤害。
# 猎犬明确覆写为 false；它唯一的主动生命伤害来源是 BiteArea 前置矩形咬击框。
func has_collision_damage() -> bool:
	return false

func _disable_inherited_body_hitbox() -> void:
	if self_hitbox == null:
		return
	self_hitbox.monitoring = false
	self_hitbox.monitorable = false
	self_hitbox.collision_layer = 0
	self_hitbox.collision_mask = 0
	var inherited_shape:CollisionShape2D = self_hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if inherited_shape != null:
		inherited_shape.disabled = true

func _ready() -> void:
	Type = Ball_Type.Creature
	Can_Attack = false
	Can_Skill = false
	Has_Collision_Damage = false
	Speed = follow_speed
	super._ready()
	_disable_inherited_body_hitbox()
	add_to_group("DogTrainerDog")
	_set_dog_texture(normal_texture)
	# V102：狗恢复完整角色身体碰撞。狗与狗必须真实互撞；
	# 只对自己的训犬师保留 collision exception，避免主人把狗卡住。
	collision_layer = 2
	collision_mask = 3
	_configure_owner_collision_exception()
	bite_area.top_level = true
	bite_area.global_scale = Vector2.ONE
	bite_area.global_rotation = 0.0
	# V206：身体碰撞永远不负责伤害；咬击伤害只来自嘴前方短暂开启的矩形 Hitbox。
	# 覆盖尺度恢复 V202 的 42px 撕咬范围：前向 42px、横向总宽 84px，但不恢复成身体四周圆形伤害。
	bite_area.monitoring = false
	if bite_shape != null and bite_shape.shape is RectangleShape2D:
		var rect:RectangleShape2D = bite_shape.shape.duplicate() as RectangleShape2D
		rect.size = Vector2(maxf(bite_hitbox_size.x,1.0),maxf(bite_hitbox_size.y,1.0))
		bite_shape.shape = rect
		bite_shape.disabled = true


func _add_mutual_collision_exception(body:Node) -> void:
	if body == null or body == self or not is_instance_valid(body) or not body is PhysicsBody2D:
		return
	var other_body:PhysicsBody2D = body as PhysicsBody2D
	add_collision_exception_with(other_body)
	other_body.add_collision_exception_with(self)

func _configure_owner_collision_exception() -> void:
	# 只让主人与自己的狗互不阻挡。狗与狗之间绝不加 exception，必须保留真实身体碰撞。
	if owner_trainer != null and is_instance_valid(owner_trainer):
		_add_mutual_collision_exception(owner_trainer)

# V102：即使 World 开启大规模战斗模式，也不能把训犬师狗的 Layer 2 身体扫描关掉。
# 狗群数量通常远少于全场角色，保留真实狗↔狗/狗↔人物碰撞更符合角色机制。
func set_large_battle_performance_mode(enabled:bool) -> void:
	super(enabled)
	collision_layer = 2
	set_collision_mask_value(1,true)
	set_collision_mask_value(2,true)
	max_slides = maxi(max_slides,4)

func _pack_avoidance_vector() -> Vector2:
	var avoidance := Vector2.ZERO

	# 虽然主人和狗之间有物理例外，但移动逻辑仍主动绕开主人，避免视觉上穿过主人。
	if owner_trainer != null and is_instance_valid(owner_trainer):
		var from_owner:Vector2 = global_position - owner_trainer.global_position
		var owner_distance:float = from_owner.length()
		if owner_distance < owner_avoid_radius:
			var owner_dir:Vector2 = from_owner / owner_distance if owner_distance > 0.001 else _fallback_separation_direction(owner_trainer.get_instance_id())
			var owner_strength:float = 1.0 - clampf(owner_distance / maxf(owner_avoid_radius,0.001),0.0,1.0)
			avoidance += owner_dir * owner_strength * owner_avoid_weight

	# 狗与狗保持真实碰撞；这里仅做预防性分离转向，让同一目标上的多条狗在接触前先错开。
	for raw:Node in get_tree().get_nodes_in_group("DogTrainerDog"):
		if raw == self or not is_instance_valid(raw) or not raw is Node2D:
			continue
		var other_dog:Node2D = raw as Node2D
		var away:Vector2 = global_position - other_dog.global_position
		var distance:float = away.length()
		if distance >= pack_avoid_radius:
			continue
		var away_dir:Vector2 = away / distance if distance > 0.001 else _fallback_separation_direction(other_dog.get_instance_id())
		var strength:float = 1.0 - clampf(distance / maxf(pack_avoid_radius,0.001),0.0,1.0)
		avoidance += away_dir * strength * pack_avoid_weight

	return avoidance

func _fallback_separation_direction(other_id:int) -> Vector2:
	# 两条狗极端情况下中心完全重合时，仍给稳定且彼此不同的拆分方向。
	var hash_value:int = abs(get_instance_id() * 31 + other_id * 17) % 360
	return Vector2.RIGHT.rotated(deg_to_rad(float(hash_value)))

func _set_dog_texture(texture_value:Texture2D) -> void:
	if texture_value == null or character_image == null:
		return
	character_image.texture = texture_value
	var texture_size:Vector2 = texture_value.get_size()
	var longest:float = maxf(texture_size.x,texture_size.y)
	if longest > 0.001:
		var fitted:float = maxf(visual_local_max_size,1.0) / longest
		character_image.scale = Vector2(fitted,fitted)

func _show_bite_visual() -> void:
	if bite_texture == null or health <= 0:
		return
	_visual_serial += 1
	var my_serial:int = _visual_serial
	_set_dog_texture(bite_texture)
	await get_tree().create_timer(maxf(bite_visual_duration,0.05)).timeout
	if not is_instance_valid(self) or health <= 0 or my_serial != _visual_serial:
		return
	_set_dog_texture(normal_texture)

func is_hunting() -> bool:
	return mode == DogMode.HUNT and hunt_target != null and is_instance_valid(hunt_target)

func assign_hunt_target(target:ball) -> void:
	if target == null or not is_instance_valid(target) or not TOOLS.is_enemy(self,target):
		return
	hunt_target = target
	_hunt_left = hunt_timeout
	mode = DogMode.HUNT

func _physics_process(delta:float) -> void:
	if health <= 0:
		_force_free()
		return
	if not is_multiplayer_authority():
		return
	if owner_trainer == null or not is_instance_valid(owner_trainer) or owner_trainer.health <= 0:
		force_owner_lost()
		return
	_bite_attack_left = maxf(_bite_attack_left - delta,0.0)
	_bite_cooldown_left = maxf(_bite_cooldown_left - delta,0.0)
	_update_bite_hitbox(delta)
	_update_owner_forward()
	# V212：每一口攻击结束后都必须回训犬师。攻击动作/Hitbox 结束前先让这一口完整收尾，
	# 一结束就切 RETURN；HUNT 同时通知训犬师本狗本次追猎结束。
	if _return_after_bite and not _bite_attack_active():
		var finished_from_hunt:bool = _return_after_bite_from_hunt
		_return_after_bite = false
		_return_after_bite_from_hunt = false
		if finished_from_hunt:
			_finish_hunt(true)
		else:
			mode = DogMode.RETURN
			_follow_smoothed_target_ready = false
	match mode:
		DogMode.HUNT:
			_process_hunt(delta)
		DogMode.RETURN:
			_process_return(delta)
		_:
			_process_follow_or_guard(delta)

func _update_owner_forward() -> void:
	if owner_trainer == null or not is_instance_valid(owner_trainer):
		return
	var candidate:Vector2 = owner_trainer.velocity
	if candidate.length_squared() <= 1.0:
		candidate = owner_trainer.direction
	if candidate.length_squared() > 0.000001:
		_last_owner_forward = candidate.normalized()

func _owner_follow_target() -> Vector2:
	var predicted_owner:Vector2 = owner_trainer.global_position + owner_trainer.velocity * follow_prediction_time
	var forward:Vector2 = _last_owner_forward
	if forward.length_squared() <= 0.000001:
		forward = Vector2.RIGHT
	var side:Vector2 = forward.orthogonal()
	return predicted_owner - forward * follow_back_offset + side * follow_side_offset

func _follow_path_blocked_by_wall(target_position:Vector2) -> bool:
	if global_position.distance_squared_to(target_position) <= 4.0:
		return false
	var query := PhysicsRayQueryParameters2D.new()
	query.from = global_position
	query.to = target_position
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	var hit:Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	return not hit.is_empty()

func _follow_point_has_space(target_position:Vector2) -> bool:
	var clearance := CircleShape2D.new()
	clearance.radius = maxf(follow_space_clearance_radius,4.0)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = clearance
	query.transform = Transform2D(0.0,target_position)
	query.collision_mask = 3
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var excluded:Array[RID] = [get_rid()]
	if owner_trainer != null and is_instance_valid(owner_trainer):
		excluded.append(owner_trainer.get_rid())
	query.exclude = excluded
	return get_world_2d().direct_space_state.intersect_shape(query,8).is_empty()

func _last_wall_collision_normal() -> Vector2:
	var accumulated := Vector2.ZERO
	for i:int in range(get_slide_collision_count()):
		var collision:KinematicCollision2D = get_slide_collision(i)
		if collision == null:
			continue
		var collider:Object = collision.get_collider()
		if collider is CollisionObject2D and (collider as CollisionObject2D).get_collision_layer_value(1):
			accumulated += collision.get_normal()
	return accumulated.normalized() if accumulated.length_squared() > 0.000001 else Vector2.ZERO

func _ideal_follow_target_has_space(ideal_target:Vector2) -> bool:
	return _follow_point_has_space(ideal_target) and not _follow_path_blocked_by_wall(ideal_target)

func _pick_follow_staging_target(ideal_target:Vector2,wall_normal:Vector2) -> Vector2:
	if owner_trainer == null or not is_instance_valid(owner_trainer):
		return ideal_target
	var predicted_owner:Vector2 = owner_trainer.global_position + owner_trainer.velocity * follow_prediction_time
	var forward:Vector2 = _last_owner_forward.normalized() if _last_owner_forward.length_squared() > 0.000001 else Vector2.RIGHT
	var side:Vector2 = forward.orthogonal()
	var radius:float = maxf(follow_staging_owner_radius,follow_space_clearance_radius * 1.5)
	var from_owner:Vector2 = global_position - predicted_owner
	var current_radial:Vector2 = from_owner.normalized() if from_owner.length_squared() > 0.000001 else -forward

	# V208：候选每帧连续重算，不再“每0.3秒突然换一个落脚点”。多半径 + 多方向让狗
	# 在墙边/人群里更容易找到可达接近位；评分同时偏好当前运动侧和理想后方，减少折返。
	var base_dirs:Array[Vector2] = [
		current_radial,
		(-forward * 0.78 + side * 0.62).normalized(),
		(-forward * 0.78 - side * 0.62).normalized(),
		side,
		-side,
		-forward,
		(forward * 0.20 + side * 0.98).normalized(),
		(forward * 0.20 - side * 0.98).normalized()
	]
	var best:Vector2 = Vector2.ZERO
	var found:bool = false
	var best_score:float = INF
	for radius_scale in [0.72,1.0,1.24]:
		for candidate_dir in base_dirs:
			var candidate:Vector2 = predicted_owner + candidate_dir * radius * radius_scale
			if not _follow_point_has_space(candidate):
				continue
			if _follow_path_blocked_by_wall(candidate):
				continue
			var score:float = global_position.distance_to(candidate) * 0.58 + candidate.distance_to(ideal_target) * 0.34
			if _follow_smoothed_target_ready:
				score += candidate.distance_to(_follow_smoothed_target) * 0.08
			if score < best_score:
				best_score = score
				best = candidate
				found = true
	if found:
		return best

	# 旧 V207 在“没有任何合格候选”时直接返回 global_position，随后 _steer_toward()
	# 把 Speed/direction 清零，造成用户看到的狗原地不动。V208 失败兜底永远返回一个
	# 前方可移动目标：有墙法线时沿墙切向滑；否则先朝主人附近接近。真正碰墙继续交给
	# CharacterBody2D.move_and_slide() 滑动，绝不以“原地”等待作为恢复策略。
	var desired:Vector2 = ideal_target - global_position
	var fallback_dir:Vector2 = desired.normalized() if desired.length_squared() > 0.000001 else (predicted_owner - global_position).normalized()
	if wall_normal.length_squared() > 0.000001:
		var along_wall:Vector2 = desired.slide(wall_normal)
		if along_wall.length_squared() <= 0.000001:
			along_wall = wall_normal.orthogonal()
			if along_wall.dot(predicted_owner - global_position) < 0.0:
				along_wall = -along_wall
		fallback_dir = along_wall.normalized()
	elif fallback_dir.length_squared() <= 0.000001:
		fallback_dir = current_radial.orthogonal().normalized()
	return global_position + fallback_dir * maxf(follow_recovery_step,12.0)

func _space_aware_follow_target(delta:float) -> Vector2:
	var ideal_target:Vector2 = _owner_follow_target()
	var ideal_clear:bool = _ideal_follow_target_has_space(ideal_target)
	var wall_normal:Vector2 = _last_wall_collision_normal()
	var wall_contact:bool = wall_normal.length_squared() > 0.000001

	if wall_contact or not ideal_clear:
		_follow_recovery_active = true
		_follow_ideal_clear_time = 0.0

	if _follow_recovery_active:
		# 理想后方要连续有空间一小段时间才恢复；但等待期间狗仍持续沿可达接近位移动。
		if ideal_clear:
			_follow_ideal_clear_time += maxf(delta,0.0)
		else:
			_follow_ideal_clear_time = 0.0
		if _follow_ideal_clear_time >= maxf(follow_ideal_clear_hold_time,0.10):
			_follow_recovery_active = false

	var desired_target:Vector2 = ideal_target
	if _follow_recovery_active:
		desired_target = _pick_follow_staging_target(ideal_target,wall_normal)

	# 连续平滑“目标点”而不是离散锁住/重选目标。即使 recovery 目标从左侧切到右侧，
	# 狗也会用指数响应平滑转过去，不会瞬间折线；目标点绝不允许退化为自身位置。
	if not _follow_smoothed_target_ready:
		_follow_smoothed_target = desired_target
		_follow_smoothed_target_ready = true
	else:
		var blend:float = 1.0 - exp(-maxf(follow_target_response,0.01) * maxf(delta,0.0))
		_follow_smoothed_target = _follow_smoothed_target.lerp(desired_target,clampf(blend,0.0,1.0))
	if _follow_recovery_active and _follow_smoothed_target.distance_squared_to(global_position) < 16.0:
		var nudge:Vector2 = desired_target - global_position
		if nudge.length_squared() <= 0.000001:
			nudge = ideal_target - global_position
		if nudge.length_squared() > 0.000001:
			_follow_smoothed_target = global_position + nudge.normalized() * maxf(follow_recovery_step,12.0)
	return _follow_smoothed_target

# V81：所有跟随/追击都走同一个连续转向器。
# 不再使用 54px/76px 的“启动/停止开关”，而是在目标附近连续减速。
func _steer_toward(target_position:Vector2,max_speed:float,slow_radius:float,stop_radius:float,delta:float) -> void:
	var to_target:Vector2 = target_position - global_position
	var distance:float = to_target.length()
	if distance <= maxf(stop_radius,0.0):
		Speed = 0.0
		direction = Vector2.ZERO
		return
	var desired_dir:Vector2 = to_target / maxf(distance,0.0001)
	var avoidance:Vector2 = _pack_avoidance_vector()
	if avoidance.length_squared() > 0.000001:
		var combined:Vector2 = desired_dir + avoidance
		if combined.length_squared() > 0.000001:
			desired_dir = combined.normalized()
	var blend:float = 1.0 - exp(-maxf(turn_response,0.01) * maxf(delta,0.0))
	if direction.length_squared() <= 0.000001:
		direction = desired_dir
	else:
		var mixed:Vector2 = direction.normalized().lerp(desired_dir,clampf(blend,0.0,1.0))
		direction = mixed.normalized() if mixed.length_squared() > 0.000001 else desired_dir
	var full_speed:float = maxf(max_speed,0.0)
	var slow_start:float = maxf(slow_radius,stop_radius + 1.0)
	var speed_ratio:float = clampf((distance - stop_radius) / (slow_start - stop_radius),0.0,1.0)
	# 近距离仍保留一点连续移动速度，避免主人移动时狗每帧在 Move/Stand 间来回切。
	var minimum_ratio:float = 0.32
	Speed = full_speed * lerpf(minimum_ratio,1.0,speed_ratio)

func _process_hunt(delta:float) -> void:
	if hunt_target == null or not is_instance_valid(hunt_target) or not TOOLS.is_enemy(self,hunt_target):
		_finish_hunt(false)
		return
	_hunt_left -= delta
	if _hunt_left <= 0.0:
		_finish_hunt(false)
		return
	# V212 硬规则：任何攻击开始前，猎犬本体必须仍在训犬师 continuous_attack_owner_radius 内。
	# 一旦追出主人周围，立即结束本狗追猎并回归；禁止“先在远处开一口、开完再检查距离”。
	if not _inside_continuous_attack_owner_radius():
		_finish_hunt(false)
		return
	_steer_toward(hunt_target.global_position,hunt_speed,bite_range * 1.35,0.0,delta)
	if _target_in_bite_trigger_range(hunt_target) and _bite_ready():
		_try_bite(hunt_target)

func _process_return(delta:float) -> void:
	var ideal_position:Vector2 = _owner_follow_target()
	var target_position:Vector2 = _space_aware_follow_target(delta)
	# V212：普通回归仍可使用原 follow_distance；但“刚攻击完”的狗必须真的回到主人后方附近，
	# 不能因为自己本来就在54px范围内而一切 RETURN 就立刻重新进入 GUARD/HUNT。
	var return_complete_radius:float = maxf(post_attack_return_radius,1.0) if _post_attack_return_required else follow_distance
	if not _follow_recovery_active and global_position.distance_to(ideal_position) <= return_complete_radius:
		_post_attack_return_required = false
		mode = DogMode.FOLLOW
	var active_stop_radius:float = 3.0 if _follow_recovery_active else follow_stop_radius
	_steer_toward(target_position,follow_speed,follow_slow_radius,active_stop_radius,delta)

# V103：自动护主只对真正靠近的敌人锁定；标记追猎不受这个范围限制。
func _nearest_guard_enemy_physics() -> ball:
	# V209：无标记护主检测改成真实物理感知圈，而不是只比较两个角色中心点。
	# CircleShape 与敌人的 CharacterBody2D 碰撞体发生重叠就算进入警戒，因此大型角色
	# 不会因为中心点还在 guard_notice_radius 外而出现“身体已经撞到狗却仍没被发现”。
	var sensor := CircleShape2D.new()
	sensor.radius = maxf(guard_notice_radius,1.0)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = sensor
	query.transform = Transform2D(0.0,global_position)
	query.collision_mask = 2
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	var hits:Array[Dictionary] = get_world_2d().direct_space_state.intersect_shape(query,32)
	var best:ball = null
	var best_distance_sq:float = INF
	for hit:Dictionary in hits:
		var collider:Variant = hit.get("collider",null)
		if not collider is ball:
			continue
		var candidate:ball = collider as ball
		if candidate == self or candidate.health <= 0 or not TOOLS.is_enemy(self,candidate):
			continue
		var distance_sq:float = global_position.distance_squared_to(candidate.global_position)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best = candidate
	return best

func _collision_support_radius(body:ball,world_direction:Vector2) -> float:
	if body == null or not is_instance_valid(body):
		return 0.0
	var shape_node:CollisionShape2D = body.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or shape_node.shape == null:
		return 0.0
	var aim:Vector2 = world_direction.normalized() if world_direction.length_squared() > 0.000001 else Vector2.RIGHT
	var local_dir:Vector2 = aim.rotated(-shape_node.global_rotation)
	var scale_abs:Vector2 = Vector2(maxf(absf(shape_node.global_scale.x),0.0001),maxf(absf(shape_node.global_scale.y),0.0001))
	if shape_node.shape is RectangleShape2D:
		var rect:RectangleShape2D = shape_node.shape as RectangleShape2D
		var half:Vector2 = rect.size * 0.5 * scale_abs
		return absf(local_dir.x) * half.x + absf(local_dir.y) * half.y
	if shape_node.shape is CircleShape2D:
		return (shape_node.shape as CircleShape2D).radius * maxf(scale_abs.x,scale_abs.y)
	if shape_node.shape is CapsuleShape2D:
		var capsule:CapsuleShape2D = shape_node.shape as CapsuleShape2D
		return maxf(capsule.radius * scale_abs.x,capsule.height * 0.5 * scale_abs.y)
	return 0.0

func _is_body_touching_target(target:ball) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	# 优先相信上一轮 move_and_slide() 的真实 CharacterBody2D 接触结果。
	for i:int in range(get_slide_collision_count()):
		var collision:KinematicCollision2D = get_slide_collision(i)
		if collision != null and collision.get_collider() == target:
			return true
	# 某些帧是敌人主动撞向静止/减速中的狗，狗自己未必产生新的 slide collision。
	# 再用双方真实 CollisionShape 在连心线方向上的支撑半径做接触兜底。
	var delta_pos:Vector2 = target.global_position - global_position
	var center_distance:float = delta_pos.length()
	if center_distance <= 0.001:
		return true
	var self_radius:float = _collision_support_radius(self,delta_pos)
	var target_radius:float = _collision_support_radius(target,-delta_pos)
	return center_distance <= self_radius + target_radius + 3.0

func _process_follow_or_guard(delta:float) -> void:
	# V212：狗如果因为碰撞/追逐暂时离开训犬师允许攻击半径，优先回主人，
	# 即使脚边刚好有敌人也不能开始新的咬击。
	if not _inside_continuous_attack_owner_radius():
		mode = DogMode.RETURN
		var far_follow_target:Vector2 = _space_aware_follow_target(delta)
		var far_stop_radius:float = 3.0 if _follow_recovery_active else follow_stop_radius
		_steer_toward(far_follow_target,follow_speed,follow_slow_radius,far_stop_radius,delta)
		return

	var nearby:ball = _nearest_guard_enemy_physics()
	if nearby != null:
		mode = DogMode.GUARD
		_steer_toward(nearby.global_position,hunt_speed,bite_range * 1.35,0.0,delta)
		if _target_in_bite_trigger_range(nearby) and _bite_ready():
			_try_bite(nearby)
		return
	mode = DogMode.FOLLOW
	var follow_target:Vector2 = _space_aware_follow_target(delta)
	var active_stop_radius:float = 3.0 if _follow_recovery_active else follow_stop_radius
	_steer_toward(follow_target,follow_speed,follow_slow_radius,active_stop_radius,delta)

func _target_in_bite_trigger_range(target:ball) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if global_position.distance_to(target.global_position) <= bite_range:
		return true
	# V209 硬保证：双方实体身体已经接触时必须允许开始咬，不能再被中心距离42px卡住。
	return _is_body_touching_target(target)

func _update_bite_hitbox_transform() -> void:
	if bite_area == null:
		return
	var aim:Vector2 = _bite_hitbox_direction
	if aim.length_squared() <= 0.000001:
		aim = Vector2.RIGHT
	aim = aim.normalized()
	bite_area.global_scale = Vector2.ONE
	bite_area.global_rotation = aim.angle()
	bite_area.global_position = global_position + aim * bite_hitbox_forward_offset

func _set_bite_hitbox_enabled(enabled:bool) -> void:
	if bite_area != null:
		bite_area.monitoring = enabled
	if bite_shape != null:
		bite_shape.disabled = not enabled

func _begin_bite_hitbox(aim_direction:Vector2,target:ball) -> void:
	_bite_hitbox_direction = aim_direction.normalized() if aim_direction.length_squared() > 0.000001 else Vector2.RIGHT
	_bite_intended_target = target
	_bite_damage_resolved = false
	_bite_hitbox_left = maxf(bite_hitbox_active_time,0.03)
	_update_bite_hitbox_transform()
	_set_bite_hitbox_enabled(true)
	_resolve_active_bite_hitbox()

func _update_bite_hitbox(delta:float) -> void:
	if _bite_hitbox_left <= 0.0:
		return
	_update_bite_hitbox_transform()
	_resolve_active_bite_hitbox()
	_bite_hitbox_left = maxf(_bite_hitbox_left - maxf(delta,0.0),0.0)
	if _bite_hitbox_left <= 0.0:
		_set_bite_hitbox_enabled(false)
		_bite_intended_target = null

func _target_inside_current_bite_hitbox(target:ball) -> bool:
	if target == null or not is_instance_valid(target) or bite_shape == null or bite_shape.shape == null:
		return false
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = bite_shape.shape
	query.transform = bite_area.global_transform
	query.collision_mask = 2
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	var hits:Array[Dictionary] = get_world_2d().direct_space_state.intersect_shape(query,16)
	for hit:Dictionary in hits:
		if hit.get("collider",null) == target:
			return true
	return false

func _bite_attack_active() -> bool:
	# “攻击中”只覆盖这一口自身动作；V211 的短冷却单独由 _bite_cooldown_left 管理。
	return _bite_attack_left > 0.0 or _bite_hitbox_left > 0.0

func _bite_ready() -> bool:
	return not _bite_attack_active() and not _return_after_bite and _bite_cooldown_left <= 0.0

func _inside_continuous_attack_owner_radius() -> bool:
	if owner_trainer == null or not is_instance_valid(owner_trainer) or owner_trainer.health <= 0:
		return false
	return global_position.distance_to(owner_trainer.global_position) <= maxf(continuous_attack_owner_radius,0.0)

func _try_bite(target:ball) -> void:
	if target == null or not is_instance_valid(target) or not TOOLS.is_enemy(self,target):
		return
	# V212：主人范围是“开始攻击”的前置硬条件，而不是开咬之后才检查。
	if not _inside_continuous_attack_owner_radius():
		return
	if not _bite_ready():
		return
	var attack_duration:float = maxf(bite_visual_duration,bite_hitbox_active_time)
	_bite_attack_left = attack_duration
	# 保留 V211 的极短间隔，但每口结束后会先强制 RETURN；只有真正回到主人附近并再次出击后才能再攻击。
	_bite_cooldown_left = attack_duration + maxf(bite_cooldown,0.0)
	_return_after_bite = true
	_return_after_bite_from_hunt = mode == DogMode.HUNT
	_post_attack_return_required = true
	_show_bite_visual()
	var aim_dir:Vector2 = target.global_position - global_position
	if aim_dir.length_squared() <= 0.000001:
		aim_dir = direction if direction.length_squared() > 0.000001 else Vector2.RIGHT
	_begin_bite_hitbox(aim_dir,target)

func _resolve_active_bite_hitbox() -> void:
	if _bite_damage_resolved:
		return
	var target:ball = _bite_intended_target
	if target == null or not is_instance_valid(target) or not TOOLS.is_enemy(self,target):
		return
	# 伤害必须由当前开启的嘴前矩形 Hitbox 真实覆盖目标后才能发生。
	if not _target_inside_current_bite_hitbox(target):
		return
	_bite_damage_resolved = true
	_deal_bite_damage(target)

func _deal_bite_damage(target:ball) -> void:
	var source:ball = owner_trainer if owner_trainer != null and is_instance_valid(owner_trainer) else self
	# V203：基础咬击 75。召唤时训犬师提供 1.5x 主人攻击力继承，50 * 1.5 = 75；
	# 脱离主人时狗自身 Damage=75 也保持同一基础值。
	var resolved_bite_damage:float = attack_damage(bite_damage_multiplier)
	var did_damage:bool = target.receive_spatial_damage(
		resolved_bite_damage,
		{"shape":"rect","center":bite_area.global_position,"size":bite_hitbox_size,"rotation":bite_area.global_rotation,"source":source},
		false,
		false
	)
	if did_damage:
		# 保留 V202 的轻微推开；无眩晕、无撞墙伤害、无碰撞伤害。
		if bite_knockback_distance > 0.0 and bite_knockback_speed > 0.0:
			var knock_dir:Vector2 = target.global_position - global_position
			if knock_dir.length_squared() <= 0.000001:
				knock_dir = _bite_hitbox_direction
			target.apply_knockback(
				knock_dir.normalized(),
				bite_knockback_distance,
				bite_knockback_speed,
				0.0,
				0.0,
				{
					"source":self,
					"lock_control":true,
					"max_wall_bounces":0,
					"stop_on_character":true,
					"collision_damage":0.0,
				}
			)
		_play_bite_sfx_everywhere(target.global_position,resolved_bite_damage)


func _play_bite_sfx_everywhere(position_value:Vector2,resolved_damage:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_bite_sfx.rpc(position_value,resolved_damage)
	else:
		_rpc_play_bite_sfx(position_value,resolved_damage)

@rpc("authority","call_local","unreliable")
func _rpc_play_bite_sfx(_position_value:Vector2,resolved_damage:float) -> void:
	# V104：狗真正咬出生命伤害后，复用 ball.gd 碰撞伤害的标准命中音 balls_hit1。
	# 这里已经是 call_local RPC，每个客户端只本地播放一次，不能再套 Audios.play_sfx.rpc()。
	var hit_volume:float = clampf(maxf(resolved_damage,0.0) - 12.0,-100.0,0.0)
	Audios.play_sfx("balls_hit1",{volume = hit_volume},true,true)

func _finish_hunt(hit:bool) -> void:
	var old_target:ball = hunt_target
	hunt_target = null
	mode = DogMode.RETURN
	# HUNT 可能把狗带离主人很远；回归时不要先朝旧的平滑跟随点折返一帧。
	_follow_smoothed_target_ready = false
	if owner_trainer != null and is_instance_valid(owner_trainer) and owner_trainer.has_method("notify_hunt_finished"):
		owner_trainer.call("notify_hunt_finished",self,old_target,hit)

func force_owner_lost() -> void:
	_visual_serial += 1
	_bite_attack_left = 0.0
	_bite_cooldown_left = 0.0
	_bite_hitbox_left = 0.0
	_bite_intended_target = null
	_bite_damage_resolved = false
	_return_after_bite = false
	_return_after_bite_from_hunt = false
	_post_attack_return_required = false
	_set_bite_hitbox_enabled(false)
	if _dead_started:
		return
	_dead_started = true
	health = 0
	call_deferred("_force_free")

func _force_free() -> void:
	if is_inside_tree() and not is_queued_for_deletion():
		Game.free_node(self)
