extends CharacterBody2D

# ============================================================
# 手动训练：无重力弹球
# - 出生时先获得随机初速度，随后短暂加速。
# - 加速阶段结束后进入减速；减速度会随减速时间持续增大，因此越到后面掉速越快。
# - 不施加向下重力；撞地图仍按碰撞法线反弹并损失部分能量。
# - 速度足够低并持续数帧后会在当前位置完全停住。
# ============================================================

@export_category("外观")
@export_range(3.0,24.0,0.5) var ball_radius:float = 7.0
@export var ball_color:Color = Color(0.96,0.76,0.22,1.0)
@export var outline_color:Color = Color(0.19,0.14,0.08,1.0)

@export_category("初始运动")
@export_range(20.0,1200.0,10.0) var initial_speed_min:float = 260.0
@export_range(20.0,1200.0,10.0) var initial_speed_max:float = 420.0

@export_category("速度曲线")
@export_range(0.05,3.0,0.05) var acceleration_duration:float = 0.65
@export_range(0.0,1600.0,10.0) var acceleration_strength:float = 300.0
@export_range(0.0,1200.0,10.0) var deceleration_start:float = 80.0
@export_range(0.0,1600.0,10.0) var deceleration_growth:float = 260.0

@export_category("弹性")
@export_range(0.05,1.0,0.01) var bounce_retention:float = 0.78
@export_range(0.0,1.0,0.01) var collision_tangent_friction:float = 0.08

@export_category("停止")
@export_range(1.0,160.0,1.0) var settle_speed:float = 18.0
@export_range(1,20,1) var settle_frames:int = 5
@export_range(1,8,1) var max_collisions_per_tick:int = 4

var settled:bool = false
var _slow_frames:int = 0
var _motion_age:float = 0.0


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_update_collision_radius()
	_launch_randomly()
	queue_redraw()


func _draw() -> void:
	var radius:float = maxf(ball_radius,1.0)
	# 与重力弹球保持相同外观，靠下拉框名称区分两种测试物。
	draw_circle(Vector2.ZERO,radius,ball_color,true)
	draw_circle(Vector2.ZERO,radius,outline_color,false,1.5)
	draw_circle(Vector2(-radius * 0.28,-radius * 0.30),maxf(radius * 0.18,1.0),Color(1.0,1.0,1.0,0.72),true)


func _launch_randomly() -> void:
	var low:float = minf(initial_speed_min,initial_speed_max)
	var high:float = maxf(initial_speed_min,initial_speed_max)
	var launch_speed:float = randf_range(maxf(low,1.0),maxf(high,1.0))
	var launch_angle:float = randf_range(0.0,TAU)
	velocity = Vector2.RIGHT.rotated(launch_angle) * launch_speed
	settled = false
	_slow_frames = 0
	_motion_age = 0.0


func _update_collision_radius() -> void:
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null or collision.shape == null:
		return
	if collision.shape is CircleShape2D:
		# resource_local_to_scene=true，修改的只是这个实例自己的 Shape。
		(collision.shape as CircleShape2D).radius = maxf(ball_radius,1.0)


func _physics_process(delta:float) -> void:
	if settled:
		return
	if delta <= 0.0:
		return

	# 无重力版：不修改 velocity.y。速度只沿当前运动方向改变大小。
	# 阶段 1：出生后短暂加速；阶段 2：随后减速，而且减速度随时间线性增强。
	_motion_age += delta
	var speed:float = velocity.length()
	if speed > 0.0001:
		var direction:Vector2 = velocity / speed
		if _motion_age <= maxf(acceleration_duration,0.0):
			speed += maxf(acceleration_strength,0.0) * delta
		else:
			var decel_time:float = _motion_age - maxf(acceleration_duration,0.0)
			var current_deceleration:float = maxf(deceleration_start,0.0) + maxf(deceleration_growth,0.0) * decel_time
			speed = maxf(speed - current_deceleration * delta,0.0)
		velocity = direction * speed

	var remaining_motion:Vector2 = velocity * delta
	var collision_limit:int = clampi(max_collisions_per_tick,1,8)

	for _i:int in range(collision_limit):
		if remaining_motion.length_squared() <= 0.000001:
			break
		var collision:KinematicCollision2D = move_and_collide(remaining_motion)
		if collision == null:
			break

		var normal:Vector2 = collision.get_normal()
		if normal.length_squared() <= 0.000001:
			break
		normal = normal.normalized()

		# 按碰撞法线反射，并损失一部分法向/切向能量。
		if velocity.dot(normal) < 0.0:
			velocity = velocity.bounce(normal) * clampf(bounce_retention,0.0,1.0)
			var normal_component:Vector2 = normal * velocity.dot(normal)
			var tangent_component:Vector2 = velocity - normal_component
			velocity = normal_component + tangent_component * (1.0 - clampf(collision_tangent_friction,0.0,1.0))

		# 继续处理这一物理帧尚未走完的位移，降低高速时贴墙或吞位移的概率。
		remaining_motion = collision.get_remainder().bounce(normal) * clampf(bounce_retention,0.0,1.0)

	# 没有重力就没有固定“地面”。当总速度已经足够低并连续保持数帧，
	# 直接在当前位置锁死，避免减速尾段产生无限微小漂移。
	if _motion_age > maxf(acceleration_duration,0.0) and velocity.length() <= maxf(settle_speed,1.0):
		_slow_frames += 1
	else:
		_slow_frames = 0

	if _slow_frames >= maxi(settle_frames,1):
		velocity = Vector2.ZERO
		settled = true
