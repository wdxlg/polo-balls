extends CharacterBody2D

# ============================================================
# 手动训练：弹球
# - 由“设置 -> 训练 -> 手动攻击”的 scenes/shooter 自动目录扫描收录。
# - 手动训练控制器会在鼠标世界坐标实例化本场景；本脚本故意不读取瞄准方向，
#   每次出生都自行生成一个随机初速度方向。
# - 只与地图层（collision_mask = 1）碰撞，不造成伤害，也不参与角色碰撞。
# - CharacterBody2D 不会自动受到重力，因此这里显式积分向下重力；碰撞后按法线反弹。
# - 反弹持续损失能量；在“地面”低速接触数帧后完全停住，避免无限微小弹跳。
# ============================================================

@export_category("外观")
@export_range(3.0,24.0,0.5) var ball_radius:float = 7.0
@export var ball_color:Color = Color(0.96,0.76,0.22,1.0)
@export var outline_color:Color = Color(0.19,0.14,0.08,1.0)

@export_category("初始运动")
@export_range(20.0,1200.0,10.0) var initial_speed_min:float = 260.0
@export_range(20.0,1200.0,10.0) var initial_speed_max:float = 420.0

@export_category("弹性")
@export_range(0.05,1.0,0.01) var bounce_retention:float = 0.78
@export_range(0.0,1.0,0.01) var collision_tangent_friction:float = 0.08
@export_range(0.0,4.0,0.01) var air_drag:float = 0.16
@export_range(10.0,2400.0,10.0) var gravity_acceleration:float = 720.0
@export_range(0.0,1600.0,10.0) var ground_friction:float = 320.0

@export_category("停止")
@export_range(1.0,160.0,1.0) var settle_speed:float = 18.0
@export_range(1.0,180.0,1.0) var settle_vertical_speed:float = 46.0
@export_range(1,20,1) var settle_contact_frames:int = 5
@export_range(1,8,1) var max_collisions_per_tick:int = 4

var settled:bool = false
var _ground_contact_frames:int = 0


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_update_collision_radius()
	_launch_randomly()
	queue_redraw()


func _draw() -> void:
	var radius:float = maxf(ball_radius,1.0)
	# 简单像素感弹球，不依赖额外图片资源。
	draw_circle(Vector2.ZERO,radius,ball_color,true)
	draw_circle(Vector2.ZERO,radius,outline_color,false,1.5)
	# 小高光让静止后仍能看出球体朝向/体积。
	draw_circle(Vector2(-radius * 0.28,-radius * 0.30),maxf(radius * 0.18,1.0),Color(1.0,1.0,1.0,0.72),true)


func _launch_randomly() -> void:
	var low:float = minf(initial_speed_min,initial_speed_max)
	var high:float = maxf(initial_speed_min,initial_speed_max)
	var launch_speed:float = randf_range(maxf(low,1.0),maxf(high,1.0))
	var launch_angle:float = randf_range(0.0,TAU)
	velocity = Vector2.RIGHT.rotated(launch_angle) * launch_speed
	settled = false
	_ground_contact_frames = 0


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

	# CharacterBody2D 不会被 Godot 自动施加重力，手动积分屏幕向下（+Y）的加速度。
	velocity.y += maxf(gravity_acceleration,0.0) * delta
	if air_drag > 0.0:
		velocity *= exp(-air_drag * delta)

	var touched_ground:bool = false
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
		if normal.y < -0.55:
			touched_ground = true

		# 只有速度确实朝碰撞面内部时才反射，避免恢复接触产生的“二次反弹”。
		if velocity.dot(normal) < 0.0:
			velocity = velocity.bounce(normal) * clampf(bounce_retention,0.0,1.0)
			# 切向摩擦独立衰减，使斜撞墙仍能自然保留一部分横向速度。
			var normal_component:Vector2 = normal * velocity.dot(normal)
			var tangent_component:Vector2 = velocity - normal_component
			velocity = normal_component + tangent_component * (1.0 - clampf(collision_tangent_friction,0.0,1.0))

		# 把本次尚未走完的位移也沿碰撞法线反射，减少高速时贴墙/吞位移。
		remaining_motion = collision.get_remainder().bounce(normal) * clampf(bounce_retention,0.0,1.0)

	# 底边视为“地面”。反弹已经很弱时停止竖直微跳，再让横向速度靠地面摩擦耗尽。
	if touched_ground and absf(velocity.y) <= maxf(settle_vertical_speed,1.0):
		velocity.y = 0.0
		velocity.x = move_toward(velocity.x,0.0,maxf(ground_friction,0.0) * delta)
		_ground_contact_frames += 1
	else:
		_ground_contact_frames = 0

	if _ground_contact_frames >= maxi(settle_contact_frames,1) and velocity.length() <= maxf(settle_speed,1.0):
		velocity = Vector2.ZERO
		settled = true
