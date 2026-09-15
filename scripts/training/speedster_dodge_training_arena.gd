extends Node2D

# 这个训练场只做第一阶段：单颗投射物 -> KEEP / LEFT / RIGHT。
# 每个 episode 只生成一颗子弹，命中=失败，安全越过=成功。
# 障碍会随机封住左边或右边，使 AI 必须读取候选路线是否有效。

@export_category("节点")
@export var speedster_path:NodePath = NodePath("极速者_RL训练")
@export var controller_path:NodePath = NodePath("极速者_RL训练/SpeedsterDodgeRLController")
@export var projectile_container_path:NodePath = NodePath("Projectiles")
@export var projectile_scene:PackedScene

@export_category("场地")
@export var arena_center:Vector2 = Vector2(640,360)
@export var arena_size:Vector2 = Vector2(1120,640)
@export_range(10.0,100.0,1.0) var boundary_thickness:float = 36.0
@export var randomize_side_blocker:bool = true
@export_range(40.0,120.0,1.0) var blocker_side_offset:float = 62.0
@export var blocker_size:Vector2 = Vector2(180,36)

@export_category("投射物课程")
@export_range(0.0,2.0,0.01) var spawn_delay:float = 0.22
@export_range(120.0,500.0,5.0) var spawn_distance_min:float = 260.0
@export_range(140.0,520.0,5.0) var spawn_distance_max:float = 300.0
@export_range(100.0,1600.0,10.0) var projectile_speed_min:float = 520.0
@export_range(100.0,1800.0,10.0) var projectile_speed_max:float = 940.0
@export_range(0.0,40.0,1.0) var aim_lateral_error:float = 10.0
@export_range(20.0,240.0,5.0) var pass_margin:float = 110.0
@export_range(1,200,1) var projectile_damage:int = 35
@export var projectile_team:String = "RL_TRAINER"

@export_category("调试")
@export var draw_training_debug:bool = true
@export var print_episode_result:bool = false

# ball.gd 的通用命中反馈会读取 current_scene.camera_shake_amount。
var camera_shake_amount:float = 0.0

var _speedster:ball = null
var _controller:Node = null
var _projectiles:Node = null
var _active_projectile:ball = null
var _active_travel_dir:Vector2 = Vector2.RIGHT
var _spawn_time_left:float = 0.0
var _waiting_for_reset:bool = false
var _episode_started:bool = false
var _episode_count:int = 0

var _walls:Array[StaticBody2D] = []
var _blocker:StaticBody2D = null
var _blocker_visible:bool = false


func _ready() -> void:
	_speedster = get_node_or_null(speedster_path) as ball
	_controller = get_node_or_null(controller_path)
	_projectiles = get_node_or_null(projectile_container_path)
	if _speedster == null:
		push_error("SpeedsterDodgeTrainingArena: 找不到极速者：%s" % speedster_path)
		return
	if _controller == null or not _controller.has_method("finish_episode"):
		push_error("SpeedsterDodgeTrainingArena: 找不到 RL Controller：%s" % controller_path)
		return
	if _projectiles == null:
		push_error("SpeedsterDodgeTrainingArena: 找不到 Projectiles 节点。")
		return
	if projectile_scene == null:
		push_error("SpeedsterDodgeTrainingArena: projectile_scene 未设置。")
		return

	_build_static_geometry()
	rl_reset_episode()


func _physics_process(delta:float) -> void:
	if _speedster == null or _controller == null or _waiting_for_reset:
		return

	if not _episode_started:
		_spawn_time_left -= maxf(delta,0.0)
		if _spawn_time_left <= 0.0:
			_start_shot()
		return

	if _active_projectile == null or not is_instance_valid(_active_projectile):
		return

	# travel_dir 指向“从出生点射向极速者”的方向。
	# 当投射物在这个方向上已经越过极速者 pass_margin，说明本次攻击已安全通过。
	var relative:Vector2 = _active_projectile.global_position - _speedster.global_position
	if relative.dot(_active_travel_dir) >= pass_margin:
		_finish_episode(true,"passed")


# Sync 在 Python reset 后通过 Controller 调用这里。
func rl_reset_episode() -> void:
	_clear_projectiles()
	_waiting_for_reset = false
	_episode_started = false
	_spawn_time_left = spawn_delay
	camera_shake_amount = 0.0

	_speedster.rl_reset_training_state(arena_center)
	_configure_blocker(Vector2.RIGHT,0)
	queue_redraw()


func _start_shot() -> void:
	_episode_started = true
	_episode_count += 1

	var angle:float = randf_range(-PI,PI)
	var travel_dir:Vector2 = Vector2.RIGHT.rotated(angle).normalized()
	var side_dir:Vector2 = Vector2(-travel_dir.y,travel_dir.x)
	var distance:float = randf_range(spawn_distance_min,spawn_distance_max)
	var lateral_error:float = randf_range(-aim_lateral_error,aim_lateral_error)
	var target_point:Vector2 = _speedster.global_position + side_dir * lateral_error
	var spawn_point:Vector2 = target_point - travel_dir * distance

	# 0=不封路，1=封左，2=封右。不会同时封死两边。
	var blocker_mode:int = randi_range(0,2) if randomize_side_blocker else 0
	_configure_blocker(travel_dir,blocker_mode)

	var projectile:Node = projectile_scene.instantiate()
	if not projectile is ball:
		push_error("SpeedsterDodgeTrainingArena: 训练弹场景根节点必须继承 ball。")
		return
	var p:ball = projectile as ball
	p.global_position = spawn_point
	p.direction = travel_dir
	p.Speed = randf_range(projectile_speed_min,projectile_speed_max)
	p.Damage = projectile_damage
	p.Team = projectile_team
	p.Target_Enemy = _speedster
	p.Nearest_Enemy = _speedster

	if p.has_signal("training_hit"):
		p.connect("training_hit",Callable(self,"_on_training_projectile_hit"))
	if p.has_signal("training_expired"):
		p.connect("training_expired",Callable(self,"_on_training_projectile_expired"))

	_projectiles.add_child(p)
	_active_projectile = p
	_active_travel_dir = travel_dir
	queue_redraw()


func _on_training_projectile_hit(target:ball) -> void:
	if _waiting_for_reset:
		return
	if target == _speedster:
		_finish_episode(false,"hit")


func _on_training_projectile_expired(projectile:ball) -> void:
	if _waiting_for_reset or projectile != _active_projectile:
		return
	# 正常情况下成功会在“越过极速者”时先结算。
	# 若它提前撞到场地/异常超时，视为无效样本：不给终局奖惩，重新发一颗。
	_active_projectile = null
	_episode_started = false
	_spawn_time_left = 0.05


func _finish_episode(success:bool,reason:String) -> void:
	if _waiting_for_reset:
		return
	_waiting_for_reset = true
	if print_episode_result:
		print("[Speedster RL] episode=",_episode_count," success=",success," reason=",reason)
	if _active_projectile != null and is_instance_valid(_active_projectile):
		_active_projectile.queue_free()
	_active_projectile = null
	_controller.finish_episode(success)


func _clear_projectiles() -> void:
	_active_projectile = null
	if _projectiles == null:
		return
	for child:Node in _projectiles.get_children():
		child.queue_free()


func _build_static_geometry() -> void:
	for wall:StaticBody2D in _walls:
		if is_instance_valid(wall):
			wall.queue_free()
	_walls.clear()

	var half:Vector2 = arena_size * 0.5
	var t:float = boundary_thickness
	_walls.append(_make_wall("WallTop",arena_center + Vector2(0,-half.y - t * 0.5),Vector2(arena_size.x + t * 2.0,t),0.0))
	_walls.append(_make_wall("WallBottom",arena_center + Vector2(0,half.y + t * 0.5),Vector2(arena_size.x + t * 2.0,t),0.0))
	_walls.append(_make_wall("WallLeft",arena_center + Vector2(-half.x - t * 0.5,0),Vector2(t,arena_size.y),0.0))
	_walls.append(_make_wall("WallRight",arena_center + Vector2(half.x + t * 0.5,0),Vector2(t,arena_size.y),0.0))

	_blocker = _make_wall("SideBlocker",arena_center,blocker_size,0.0)
	_walls.append(_blocker)
	_blocker.set_collision_layer_value(1,false)


func _configure_blocker(travel_dir:Vector2,mode:int) -> void:
	if _blocker == null or not is_instance_valid(_blocker):
		return
	if mode == 0:
		_blocker_visible = false
		_blocker.set_collision_layer_value(1,false)
		queue_redraw()
		return

	var dir:Vector2 = travel_dir.normalized() if travel_dir.length_squared() > 0.0001 else Vector2.RIGHT
	var left:Vector2 = Vector2(-dir.y,dir.x)
	var side:Vector2 = left if mode == 1 else -left
	_blocker.global_position = _speedster.global_position + side * blocker_side_offset
	_blocker.global_rotation = dir.angle()
	_blocker.set_collision_layer_value(1,true)
	_blocker_visible = true
	queue_redraw()


func _make_wall(wall_name:String,position_value:Vector2,size_value:Vector2,rotation_value:float) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = wall_name
	body.collision_layer = 1
	body.collision_mask = 0
	body.global_position = position_value
	body.global_rotation = rotation_value

	var shape := RectangleShape2D.new()
	shape.size = size_value
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	return body


func _draw() -> void:
	if not draw_training_debug:
		return
	var rect := Rect2(arena_center - arena_size * 0.5,arena_size)
	draw_rect(rect,Color(0.35,0.45,0.60,0.55),false,3.0)
	if _blocker_visible and _blocker != null and is_instance_valid(_blocker):
		var local_center:Vector2 = to_local(_blocker.global_position)
		var points := PackedVector2Array([
			Vector2(-blocker_size.x,-blocker_size.y) * 0.5,
			Vector2(blocker_size.x,-blocker_size.y) * 0.5,
			Vector2(blocker_size.x,blocker_size.y) * 0.5,
			Vector2(-blocker_size.x,blocker_size.y) * 0.5,
		])
		for i:int in range(points.size()):
			points[i] = local_center + points[i].rotated(_blocker.global_rotation)
		draw_colored_polygon(points,Color(0.85,0.35,0.25,0.35))
	if _active_projectile != null and is_instance_valid(_active_projectile):
		draw_line(to_local(_active_projectile.global_position),to_local(_speedster.global_position),Color(1.0,0.4,0.2,0.35),1.5)
