extends ball

# 小狗叫：真正继承 ball，但作为不可瞄准、不可受伤的附属 ball，只保留实体碰撞、弹性、跟随和狗叫机制。
const VISUAL_IDLE:Texture2D = preload("res://Images/characters/meme/大狗叫/小狗.png")
const VISUAL_BARK:Texture2D = preload("res://Images/characters/meme/大狗叫/小狗叫.png")

# 专用身体层：数值 8 = 第 4 个碰撞层。普通 ball 的 collision_mask=3 不扫描这一层，因此小狗不会反向影响普通角色/大狗。
const COMPANION_BODY_LAYER:int = 8

@export_category("小狗叫 - 跟随位置")
@export_range(16.0,140.0,1.0) var follow_distance:float = 62.0
@export_range(-40.0,40.0,1.0) var follow_side_offset:float = 0.0
@export_range(2.0,40.0,1.0) var follow_dead_zone:float = 8.0
@export_range(40.0,260.0,5.0) var follow_catchup_distance:float = 135.0

@export_category("小狗叫 - 绕大狗")
# 小狗到“正后方目标”的直线会切过大狗身体时，先走侧面绕行点，绝不把跟随路径直接穿过大狗。
@export_range(0.0,40.0,1.0) var master_avoidance_margin:float = 10.0
@export_range(1.0,2.2,0.05) var master_orbit_radius_multiplier:float = 1.30
@export_range(0.0,1.0,0.05) var master_orbit_back_bias:float = 0.20
@export_range(4.0,40.0,1.0) var master_route_release_margin:float = 12.0
@export_range(180.0,900.0,10.0) var follow_emergency_snap_distance:float = 520.0
@export_range(0.05,0.40,0.01) var safe_anchor_refresh_interval:float = 0.12
@export_range(0.20,3.0,0.05) var blocked_rescue_time:float = 0.85
@export_range(30.0,220.0,5.0) var blocked_rescue_min_distance:float = 70.0

@export_category("小狗叫 - 跟随速度")
@export_range(0.0,180.0,5.0) var follow_slow_speed:float = 55.0
@export_range(40.0,320.0,5.0) var follow_cruise_speed:float = 155.0
@export_range(100.0,650.0,5.0) var follow_fast_speed:float = 345.0
@export_range(40.0,1200.0,10.0) var follow_acceleration:float = 520.0
@export_range(40.0,1200.0,10.0) var follow_deceleration:float = 390.0
@export_range(1.0,20.0,0.5) var follow_anchor_smoothing:float = 7.0

@export_category("小狗叫 - 碰撞")
@export_range(6.0,40.0,1.0) var body_radius:float = 15.0
@export_range(0.2,1.2,0.05) var wall_bounce_elasticity:float = 1.00
@export_range(0.2,1.2,0.05) var character_bounce_elasticity:float = 0.82
@export_range(0.04,0.50,0.01) var bounce_hold_time:float = 0.26

@export_category("小狗叫 - 视觉")
@export_range(10.0,100.0,1.0) var visual_max_world_size:float = 22.0

@onready var bark_mechanic:Node2D = $BarkMechanic

var master_dog:ball = null
var _last_visual:Texture2D = null
var _smoothed_anchor:Vector2 = Vector2.ZERO
var _safe_anchor:Vector2 = Vector2.ZERO
var _last_facing:Vector2 = Vector2.RIGHT
var _bounce_velocity:Vector2 = Vector2.ZERO
var _bounce_left:float = 0.0
var _safe_anchor_refresh_left:float = 0.0
var _wall_separated_elapsed:float = 0.0
var _routing_around_master:bool = false
var _route_side_sign:float = 1.0


# 功能：初始化为不可瞄准/不可受伤的独立 ball，并建立只对小狗自身生效的实体碰撞。
func _ready() -> void:
    Type = Ball_Type.Creature # Creature 让 World 默认目标选择调用 is_combat_targetable()。
    Can_Attack = false # 普通 ball 攻击关闭，伤害完全由 BarkMechanic 的真实 DamageArea 负责。
    Can_Skill = false # 小狗没有手动技能。
    Has_Collision_Damage = false # 身体碰撞只负责反弹，不直接造成接触伤害。
    side_status_ui_enabled = false # 没有生命/状态 UI。
    Health_Restore = 0
    Max_health = 1 # 仅满足 ball 基类内部字段约束；所有伤害入口都会拒绝，外观也不显示生命。
    Speed = 0.0 # 跟随速度由本脚本直接控制，不使用 ball 默认移动速度。

    if get_parent() is ball:
        master_dog = get_parent() as ball
        Master = master_dog # 保留附属身份/队伍归属，但小狗本身仍是独立 ball 节点。
        Team = master_dog.Team

    super._ready()

    # 关键：它是 ball 类，但不加入普通目标/胜负/训练扫描使用的 "Ball" 组，因此不会被绝大多数锁定逻辑枚举到。
    if is_in_group("Ball"):
        remove_from_group("Ball")
    add_to_group("DogBarkingCompanion")

    input_pickable = false # 鼠标/物理拾取不把小狗当可选角色。
    collision_layer = COMPANION_BODY_LAYER # 大狗默认 mask=3 看不到第 4 层，所以不会被小狗阻挡。
    collision_mask = 3 # 小狗自己仍扫描 Layer1 墙体 + Layer2 普通角色/大狗，因此能真实碰撞并反弹。
    motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
    safe_margin = 0.06

    _disable_health_and_damage_receiving()
    _configure_body_collision()
    _set_visual(VISUAL_IDLE)

    if master_dog != null and is_instance_valid(master_dog):
        var desired_anchor:Vector2 = _get_desired_anchor()
        var navigation_anchor:Vector2 = _get_navigation_anchor(desired_anchor)
        _safe_anchor = _find_safe_anchor_near_master(navigation_anchor)
        global_position = _safe_anchor # 初始位置先做真实墙体形状检查，也不会直接跨过大狗身体去背后。
        _smoothed_anchor = _safe_anchor

        if bark_mechanic != null and bark_mechanic.has_method("setup"):
            bark_mechanic.call("setup",self,master_dog,master_dog.Team,true)


# 功能：关闭 ball 自带的生命条、Hurtbox 和默认 Hitbox，让小狗功能上没有生命且不会被攻击命中。
func _disable_health_and_damage_receiving() -> void:
    health = Max_health # 保持内部哨兵生命为 1，不参与玩法。
    block = 0

    if health_bar != null:
        health_bar.visible = false # 不显示任何生命/格挡/能量 UI。
        health_bar.process_mode = Node.PROCESS_MODE_DISABLED

    if health_restore_timer != null:
        health_restore_timer.stop()

    if self_hurtbox != null:
        self_hurtbox.collision_layer = 0 # 攻击 Area2D 不会发现小狗 Hurtbox。
        self_hurtbox.collision_mask = 0
        self_hurtbox.monitoring = false
        self_hurtbox.monitorable = false
        var hurt_shape:CollisionShape2D = self_hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
        if hurt_shape != null:
            hurt_shape.disabled = true

    if self_hitbox != null:
        self_hitbox.collision_layer = 0
        self_hitbox.collision_mask = 0
        self_hitbox.monitoring = false
        self_hitbox.monitorable = false
        var hit_shape:CollisionShape2D = self_hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
        if hit_shape != null:
            hit_shape.disabled = true


# 功能：把继承 ball 的根碰撞框固定为真实圆形，专门用于墙/单位弹性碰撞。
func _configure_body_collision() -> void:
    if collision_shape_2d == null:
        return
    var circle:CircleShape2D
    if collision_shape_2d.shape is CircleShape2D:
        circle = (collision_shape_2d.shape as CircleShape2D).duplicate() as CircleShape2D
    else:
        circle = CircleShape2D.new()
    if circle == null:
        return
    circle.radius = maxf(body_radius,1.0)
    collision_shape_2d.shape = circle
    collision_shape_2d.position = Vector2.ZERO
    collision_shape_2d.scale = Vector2.ONE
    collision_shape_2d.disabled = false


# 功能：明确告诉所有遵循标准接口的索敌系统，小狗永远不是战斗目标。
func is_combat_targetable() -> bool:
    return false


# 功能：给狗叫机制识别附属小狗，确保大狗即使未来碰撞层改动也不会把小狗碰撞算进自己的蓄力。
func is_dog_barking_companion() -> bool:
    return true


# 功能：拒绝方向伤害，小狗没有可扣除的生命。
func can_receive_directional_damage(_source_position:Vector2,_incoming_direction:Vector2) -> bool:
    return false


# 功能：拒绝方向伤害入口，保持所有通用攻击兼容调用时安全返回 false。
func receive_directional_damage(
    _damage:float,
    _source_position:Vector2,
    _incoming_direction:Vector2 = Vector2.ZERO,
    _ignore_block:bool = false
) -> bool:
    return false


# 功能：拒绝带空间几何的伤害入口，声波/范围技即使直接调用也不会伤到小狗。
func receive_spatial_damage(
    _damage:float,
    _damage_space:Variant,
    _ignore_block:bool = false,
    _raw_health:bool = false
) -> bool:
    return false


# 功能：拒绝真实生命伤害入口，小狗不存在可减少的生命。
func receive_spatial_raw_health_damage(_damage:float,_damage_space:Variant) -> bool:
    return false


# 功能：拒绝位置伤害入口，兼容所有普通 hitbox 的统一结算接口。
func receive_positional_damage(
    _damage:float,
    _impact_position:Vector2,
    _ignore_block:bool = false,
    _source:Node = null
) -> bool:
    return false


# 功能：拒绝普通 take_damage()；即使特殊脚本直接调用也不会减少哨兵生命。
func take_damage(_damage:float,_ignore_block:bool = false) -> void:
    pass


# 功能：小狗没有受击白闪/受伤状态。
func hit_white(_ignore_block:bool = false) -> void:
    pass


# 功能：小狗没有普通攻击。
func Attack() -> void:
    Attacking = false


# 功能：小狗没有普通技能。
func Skill() -> void:
    Using_Skill = false


# 功能：状态机每个物理帧调用这里；只执行软跟随、弹性碰撞与狗叫视觉，不使用 ball 默认移动。
func tick_physics(_state:State,delta:float) -> void:
    if not is_multiplayer_authority():
        return
    if master_dog == null or not is_instance_valid(master_dog) or master_dog.health <= 0:
        queue_free() # 主人死亡后附属小狗直接释放，避免无生命单位把胜负/场景长期挂住。
        return

    if bark_mechanic != null and bark_mechanic.has_method("set_mechanic_enabled"):
        bark_mechanic.call("set_mechanic_enabled",true)

    var desired_anchor:Vector2 = _get_desired_anchor()
    var navigation_anchor:Vector2 = _get_navigation_anchor(desired_anchor) # 当前在大狗前方时，会先主动绕到侧面，再进入正后方。
    _safe_anchor_refresh_left -= delta
    if _safe_anchor_refresh_left <= 0.0:
        _safe_anchor_refresh_left = maxf(safe_anchor_refresh_interval,0.05)
        _safe_anchor = _find_safe_anchor_near_master(navigation_anchor)
        _update_blocked_rescue_state(_safe_anchor_refresh_left)

    var smooth_weight:float = 1.0 - exp(-maxf(follow_anchor_smoothing,0.1) * maxf(delta,0.0))
    _smoothed_anchor = _smoothed_anchor.lerp(_safe_anchor,clampf(smooth_weight,0.0,1.0))

    var to_anchor:Vector2 = _smoothed_anchor - global_position
    var distance_value:float = to_anchor.length()

    if distance_value >= maxf(follow_emergency_snap_distance,follow_catchup_distance + 40.0):
        _rescue_to_safe_anchor(navigation_anchor)
    else:
        _move_with_elastic_collision(distance_value,to_anchor,delta)

    direction = velocity.normalized() if velocity.length_squared() > 4.0 else Vector2.ZERO # 只用于视觉朝向/公共兼容字段。
    _update_visual_from_motion()


# 功能：按当前跟随距离计算速度，并通过 move_and_collide() 对墙、角色和大狗做手动弹性反射。
func _move_with_elastic_collision(distance_value:float,to_anchor:Vector2,delta:float) -> void:
    var target_velocity:Vector2 = Vector2.ZERO

    if _bounce_left > 0.0:
        _bounce_left = maxf(_bounce_left - delta,0.0)
        target_velocity = _bounce_velocity # 反弹保持期间优先离开碰撞面，不立刻被跟随力拉回。
        _bounce_velocity = _bounce_velocity.move_toward(Vector2.ZERO,follow_deceleration * 0.45 * delta)
    elif distance_value > maxf(follow_dead_zone,1.0):
        var direction_to_anchor:Vector2 = to_anchor / maxf(distance_value,0.0001)
        target_velocity = direction_to_anchor * _get_follow_speed(distance_value)

    var accelerating:bool = target_velocity.length_squared() > velocity.length_squared()
    var rate:float = follow_acceleration if accelerating else follow_deceleration
    velocity = velocity.move_toward(target_velocity,maxf(rate,1.0) * delta)

    var requested_velocity:Vector2 = velocity
    var collision:KinematicCollision2D = move_and_collide(requested_velocity * delta)
    if collision == null:
        return

    var collider:Object = collision.get_collider()
    if collider != null and bark_mechanic != null and bark_mechanic.has_method("notify_collision"):
        bark_mechanic.call("notify_collision",collider) # 小狗自己的碰撞仍正常增加小狗进度，包括撞到大狗。

    var normal:Vector2 = collision.get_normal().normalized()
    if requested_velocity.dot(normal) >= 0.0:
        return

    var elasticity:float = character_bounce_elasticity if collider is CharacterBody2D else wall_bounce_elasticity
    _bounce_velocity = requested_velocity.bounce(normal) * clampf(elasticity,0.0,1.2)
    velocity = _bounce_velocity
    _bounce_left = maxf(bounce_hold_time,0.04)

    var remainder:Vector2 = collision.get_remainder()
    if remainder.length_squared() > 0.000001:
        move_and_collide(remainder.bounce(normal) * clampf(elasticity,0.0,1.2)) # 当帧补一次剩余反射位移，让弹性立即可见。


# 功能：返回大狗当前可靠朝向；优先使用主动移动方向，其次使用真实 velocity，静止时沿用上一帧朝向。
func _get_master_facing() -> Vector2:
    if master_dog == null or not is_instance_valid(master_dog):
        return _last_facing

    var facing:Vector2 = master_dog.direction
    if facing.length_squared() <= 0.000001 and master_dog.velocity.length_squared() > 4.0:
        facing = master_dog.velocity.normalized()
    elif facing.length_squared() > 0.000001:
        facing = facing.normalized()

    if facing.length_squared() <= 0.000001:
        facing = _last_facing
    if facing.length_squared() <= 0.000001:
        facing = Vector2.RIGHT

    return facing.normalized()


# 功能：生成大狗真正的“身后”跟随点；默认 side_offset=0，因此目标就是正后方而不是旁边固定点。
func _get_desired_anchor() -> Vector2:
    if master_dog == null or not is_instance_valid(master_dog):
        return global_position

    var facing:Vector2 = _get_master_facing()
    _last_facing = facing

    var side:Vector2 = Vector2(-facing.y,facing.x)
    return (
        master_dog.global_position
        - facing * maxf(follow_distance,body_radius * 2.0)
        + side * follow_side_offset
    )


# 功能：估算大狗世界空间身体半径，用于判断“直线去身后”是否会穿过主人。
func _get_master_avoidance_radius() -> float:
    if master_dog == null or not is_instance_valid(master_dog):
        return maxf(body_radius * 2.0,30.0)

    var master_radius:float = 28.0
    if master_dog.has_method("get_crowd_separation_radius_world"):
        master_radius = maxf(float(master_dog.call("get_crowd_separation_radius_world")),8.0)

    return (
        master_radius
        + maxf(body_radius,1.0)
        + maxf(master_avoidance_margin,0.0)
    )


# 功能：计算线段到点的最短距离平方；用于判断小狗直线追身后目标时是否会切过大狗实体身体。
func _segment_point_distance_squared(from_position:Vector2,to_position:Vector2,point:Vector2) -> float:
    var segment:Vector2 = to_position - from_position
    var length_sq:float = segment.length_squared()
    if length_sq <= 0.000001:
        return from_position.distance_squared_to(point)

    var t:float = clampf((point - from_position).dot(segment) / length_sq,0.0,1.0)
    var closest:Vector2 = from_position + segment * t
    return closest.distance_squared_to(point)


# 功能：判断当前直线路径是否会穿过大狗的安全排斥圆；只要会穿过就必须绕行。
func _direct_path_crosses_master(target:Vector2) -> bool:
    if master_dog == null or not is_instance_valid(master_dog):
        return false

    var radius:float = _get_master_avoidance_radius()
    return (
        _segment_point_distance_squared(
            global_position,
            target,
            master_dog.global_position
        )
        < radius * radius
    )


# 功能：选择从大狗左侧还是右侧绕；优先沿小狗当前所在侧，正前方时沿当前运动侧，避免左右来回跳。
func _choose_master_route_side() -> float:
    if master_dog == null or not is_instance_valid(master_dog):
        return _route_side_sign

    var facing:Vector2 = _get_master_facing()
    var side:Vector2 = Vector2(-facing.y,facing.x)
    var relative:Vector2 = global_position - master_dog.global_position
    var side_amount:float = relative.dot(side)

    if absf(side_amount) >= 2.0:
        return 1.0 if side_amount >= 0.0 else -1.0

    var velocity_side:float = velocity.dot(side)
    if absf(velocity_side) >= 2.0:
        return 1.0 if velocity_side >= 0.0 else -1.0

    return _route_side_sign if not is_zero_approx(_route_side_sign) else 1.0


# 功能：生成大狗侧后方的绕行点；先跑到这里，再转入真正后方，路径不会直接切过大狗身体。
func _get_master_orbit_waypoint() -> Vector2:
    if master_dog == null or not is_instance_valid(master_dog):
        return global_position

    var facing:Vector2 = _get_master_facing()
    var side:Vector2 = Vector2(-facing.y,facing.x) * _route_side_sign
    var avoid_radius:float = _get_master_avoidance_radius()
    var orbit_radius:float = maxf(
        avoid_radius * maxf(master_orbit_radius_multiplier,1.0),
        follow_distance * 0.92
    )

    return (
        master_dog.global_position
        + side * orbit_radius
        - facing * orbit_radius * clampf(master_orbit_back_bias,0.0,1.0)
    )


# 功能：返回这一帧真正要追的点；如果去正后方会穿过大狗，就主动走侧面绕行，而不是原地卡住或直接穿过去。
func _get_navigation_anchor(desired_anchor:Vector2) -> Vector2:
    if master_dog == null or not is_instance_valid(master_dog):
        _routing_around_master = false
        return desired_anchor

    var facing:Vector2 = _get_master_facing()
    var relative:Vector2 = global_position - master_dog.global_position
    var avoid_radius:float = _get_master_avoidance_radius()

    # 位于大狗前半侧，或者直线去后方会切过身体时，进入绕行状态。
    var still_in_front:bool = relative.dot(facing) > -maxf(master_route_release_margin,0.0)
    var direct_blocked:bool = _direct_path_crosses_master(desired_anchor)

    if not _routing_around_master and direct_blocked:
        _route_side_sign = _choose_master_route_side()
        _routing_around_master = true

    if _routing_around_master:
        # 已经进入明显后半侧，并且到真正后方的直线不再切过大狗时，结束绕行。
        if not direct_blocked and not still_in_front:
            _routing_around_master = false
            return desired_anchor

        var waypoint:Vector2 = _get_master_orbit_waypoint()

        # 如果主人靠墙导致首选侧面点不可用，自动尝试另一侧，仍然不会通过主人身体。
        if not _is_wall_clear_position(waypoint) or _has_wall_between(global_position,waypoint):
            var old_sign:float = _route_side_sign
            _route_side_sign = -_route_side_sign
            var alternate:Vector2 = _get_master_orbit_waypoint()
            if _is_wall_clear_position(alternate) and not _has_wall_between(global_position,alternate):
                return alternate
            _route_side_sign = old_sign

        return waypoint

    return desired_anchor


# 功能：搜索一个不与 Layer1 墙体重叠、且与主人之间没有墙阻隔的安全跟随点。
func _find_safe_anchor_near_master(desired_anchor:Vector2) -> Vector2:
    if master_dog == null or not is_instance_valid(master_dog):
        return global_position
    if _is_wall_clear_position(desired_anchor) and not _has_wall_between(master_dog.global_position,desired_anchor):
        return desired_anchor

    var master_position:Vector2 = master_dog.global_position
    var preferred:Vector2 = desired_anchor - master_position
    preferred = Vector2.RIGHT if preferred.length_squared() <= 0.000001 else preferred.normalized()

    var radii:Array[float] = [
        maxf(body_radius * 2.4,28.0),
        maxf(follow_distance * 0.70,36.0),
        maxf(follow_distance,48.0),
        maxf(follow_distance * 1.25,62.0),
        82.0,
    ]
    var angle_offsets:Array[float] = [0.0,25.0,-25.0,50.0,-50.0,80.0,-80.0,115.0,-115.0,150.0,-150.0,180.0]

    for radius_value:float in radii:
        for angle_deg:float in angle_offsets:
            var candidate:Vector2 = master_position + preferred.rotated(deg_to_rad(angle_deg)) * radius_value
            if not _is_wall_clear_position(candidate):
                continue
            if _has_wall_between(master_position,candidate):
                continue
            return candidate

    # 不再把大狗中心当兜底：小狗虽然不会影响大狗，但自己必须真实碰撞，不能被瞬移进主人身体。
    return global_position


# 功能：用小狗真实根 CircleShape2D 检查候选位置是否与 Layer1 墙体重叠。
func _is_wall_clear_position(candidate:Vector2) -> bool:
    if collision_shape_2d == null or collision_shape_2d.shape == null or get_world_2d() == null:
        return true
    var query := PhysicsShapeQueryParameters2D.new()
    query.shape = collision_shape_2d.shape
    query.transform = Transform2D(0.0,candidate)
    query.collision_mask = 1
    query.collide_with_bodies = true
    query.collide_with_areas = false
    var hits:Array[Dictionary] = get_world_2d().direct_space_state.intersect_shape(query,1)
    return hits.is_empty()


# 功能：检测主人与候选点之间是否有 Layer1 墙，避免救援把小狗送到墙的另一侧。
func _has_wall_between(from_position:Vector2,to_position:Vector2) -> bool:
    if get_world_2d() == null or from_position.distance_squared_to(to_position) <= 1.0:
        return false
    var query := PhysicsRayQueryParameters2D.new()
    query.from = from_position
    query.to = to_position
    query.collision_mask = 1
    query.collide_with_bodies = true
    query.collide_with_areas = false
    return not get_world_2d().direct_space_state.intersect_ray(query).is_empty()


# 功能：低频检测小狗是否长期隔墙掉队，只有持续卡住才进行安全救援。
func _update_blocked_rescue_state(sample_delta:float) -> void:
    if master_dog == null or not is_instance_valid(master_dog):
        _wall_separated_elapsed = 0.0
        return

    var distance_to_master:float = global_position.distance_to(master_dog.global_position)
    var separated:bool = (
        distance_to_master >= maxf(blocked_rescue_min_distance,body_radius * 3.0)
        and _has_wall_between(global_position,master_dog.global_position)
    )

    if separated:
        _wall_separated_elapsed += maxf(sample_delta,0.01)
        if _wall_separated_elapsed >= maxf(blocked_rescue_time,0.20):
            var desired_anchor:Vector2 = _get_desired_anchor()
            _rescue_to_safe_anchor(_get_navigation_anchor(desired_anchor))
            _wall_separated_elapsed = 0.0
    else:
        _wall_separated_elapsed = 0.0


# 功能：把极端掉队的小狗救回主人同侧的安全位置，目的点必须先通过真实墙体检查。
func _rescue_to_safe_anchor(desired_anchor:Vector2) -> void:
    var safe_position:Vector2 = _find_safe_anchor_near_master(desired_anchor)
    if not _is_wall_clear_position(safe_position):
        return
    if master_dog != null and is_instance_valid(master_dog) and _has_wall_between(master_dog.global_position,safe_position):
        return

    global_position = safe_position
    _safe_anchor = safe_position
    _smoothed_anchor = safe_position
    velocity = Vector2.ZERO
    _bounce_velocity = Vector2.ZERO
    _bounce_left = 0.0


# 功能：根据离跟随点的距离连续改变追赶速度，近处慢、掉队后快。
func _get_follow_speed(distance_value:float) -> float:
    var dead_zone:float = maxf(follow_dead_zone,1.0)
    var catchup:float = maxf(follow_catchup_distance,dead_zone + 1.0)
    var normalized_distance:float = clampf((distance_value - dead_zone) / (catchup - dead_zone),0.0,1.0)

    if normalized_distance < 0.45:
        return lerpf(maxf(follow_slow_speed,0.0),maxf(follow_cruise_speed,0.0),normalized_distance / 0.45)

    return lerpf(
        maxf(follow_cruise_speed,0.0),
        maxf(follow_fast_speed,follow_cruise_speed),
        (normalized_distance - 0.45) / 0.55
    )


# 功能：按当前运动和持续狗叫状态切换小狗图片。
func _update_visual_from_motion() -> void:
    var visual_direction:Vector2 = velocity
    if visual_direction.length_squared() > 4.0:
        _last_facing = visual_direction.normalized()

    if image is Sprite2D:
        set_character_visual_flip_h(_last_facing.x < 0.0)

    var howling:bool = (
        bark_mechanic != null
        and bark_mechanic.has_method("is_howling")
        and bool(bark_mechanic.call("is_howling"))
    )
    _set_visual(VISUAL_BARK if howling else VISUAL_IDLE)


# 功能：把用户提供的小狗图片缩放到指定世界尺寸，不依赖 CharacterAutoFit。
func _set_visual(texture:Texture2D) -> void:
    if not image is Sprite2D or texture == null or texture == _last_visual:
        return
    _last_visual = texture

    var sprite:Sprite2D = image as Sprite2D
    sprite.texture = texture
    sprite.offset = Vector2.ZERO
    sprite.visible = true

    var texture_size:Vector2 = texture.get_size()
    var longest:float = maxf(maxf(texture_size.x,texture_size.y),1.0)
    var root_world_scale:Vector2 = global_scale.abs()
    var max_root_scale:float = maxf(maxf(root_world_scale.x,root_world_scale.y),0.0001)
    var target_local_size:float = maxf(visual_max_world_size,1.0) / max_root_scale
    var fit:float = target_local_size / longest
    sprite.scale = Vector2.ONE * fit


# 功能：提供空威胁列表；小狗自身实体身体是无伤害碰撞，攻击威胁由 BarkMechanic 的真实 AI_Hazard 上报。
func get_ai_attack_threats(_receiver:ball) -> Array:
    return []
