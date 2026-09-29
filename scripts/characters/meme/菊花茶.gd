extends ball

const TEA_DROPLET_SCENE:PackedScene = preload("res://scenes/shooter/菊花茶水滴.tscn")
const GRAVITY_FIELD_KEY:String = "chrysanthemum_tea_gravity"
const GRAVITY_AUDIO_PATH:String = "res://audio/characters/meme/菊花茶/重力.mp3"
const GRAVITY_VISUAL_SCRIPT:Script = preload("res://scripts/effects/菊花茶重力视觉.gd")
const V297_DROPLET_MIN_FLIGHT_TIME:float = 0.30
const V297_DROPLET_MAX_FLIGHT_TIME:float = 1.80

@onready var _straw_rig:Node2D = get_node_or_null("Graphics/StrawRig") as Node2D
@onready var _straw_stem:Polygon2D = get_node_or_null("Graphics/StrawRig/StrawStem") as Polygon2D
@onready var _straw_head_pivot:Node2D = get_node_or_null("Graphics/StrawRig/StrawHeadPivot") as Node2D
@onready var _straw_head:Polygon2D = get_node_or_null("Graphics/StrawRig/StrawHeadPivot/StrawHead") as Polygon2D
@onready var _straw_mouth_inner:Marker2D = get_node_or_null("Graphics/StrawRig/StrawHeadPivot/StrawMouthInner") as Marker2D
@onready var _straw_muzzle:Marker2D = get_node_or_null("Graphics/StrawRig/StrawHeadPivot/StrawMuzzle") as Marker2D

@export_category("菊花茶 - 绿色水滴")
@export_range(50.0,1600.0,10.0) var projectile_speed:float = 520.0
@export_range(50.0,2000.0,10.0) var projectile_gravity:float = 1050.0
@export_range(0.05,1.0,0.01) var projectile_damage_multiplier:float = 0.10
@export_range(0.0,1.0,0.01) var projectile_target_prediction:float = 0.16
@export_range(0.2,5.0,0.05) var projectile_lifetime:float = 2.6
@export_range(0.0,45.0,0.5) var projectile_vertical_aim_max_angle_deg:float = 26.0
@export_range(20.0,400.0,5.0) var projectile_vertical_aim_full_offset:float = 140.0

@export_category("菊花茶 - 视觉位置")
# V293：默认改为 0。V291 的 12px 下移已经直接保存到菊花茶.tscn 的 Graphics/Image.position，
# 这样编辑器看到的构图就是局内构图。若以后确实需要运行时额外偏移，仍可使用此参数。
@export var tea_body_visual_offset:Vector2 = Vector2.ZERO

@export_category("菊花茶 - 水滴发射")
# 正常出生点由场景里的 StrawMuzzle Marker2D 决定；下面三项只控制最终出生随机偏移/故障回退。
@export_range(0.0,24.0,0.5) var projectile_spawn_above_gap:float = 3.0
@export_range(0.0,16.0,0.5) var projectile_spawn_horizontal_jitter:float = 0.0
@export_range(0.0,10.0,0.5) var projectile_spawn_vertical_jitter:float = 0.0
# “角度散射”仍只改变抛物线本身，不直接旋转最终初速度。
# center 把整体飞行时间抬高来增加弧度；variation 再让不同水滴的起射角/弧高明显分散。
@export_range(0.75,1.75,0.01) var projectile_arc_time_center:float = 1.22
@export_range(0.0,0.45,0.01) var projectile_arc_time_variation:float = 0.24


@export_category("菊花茶 - 吸管手动调节")
# V294：场景里 StrawRig 的 authored Transform2D 就是局内基础变换。
# 直接在菊花茶.tscn 的 2D 编辑器里改 StrawRig / StrawStem / StrawHeadPivot / StrawHead / 两个 Marker2D。
# 运行时只额外做两件事：跟随角色左右镜像整套 StrawRig；让 StrawHeadPivot 刚体旋转到 V297 子弹实际起射角。
@export_range(0.2,2.0,0.01) var straw_visual_scale_multiplier:float = 1.0
# 如果吸管头与子弹方向整体差一个固定角度，用这个值微调；单位是度。
@export_range(-180.0,180.0,0.5,"degrees") var straw_aim_angle_offset_deg:float = 0.0
# V296：默认不再用 ±48° 把吸管头夹死。长直管仍固定，只有 StrawHeadPivot 转动；
# 需要手工限制时才把这个值调低。180° 等于不对 wrapf(-PI,PI) 的目标角做额外截断。
@export_range(0.0,180.0,1.0,"degrees") var straw_head_max_rotation_deg:float = 180.0
# 兼容旧场景保留：V295 的正常实时视觉已改为每个渲染帧直接对准，不再使用该响应值做滞后插值。
@export_range(1.0,80.0,1.0) var straw_aim_follow_response:float = 30.0

@export_category("菊花茶 - 单侧攻击")
# V297：吸管位于角色哪一侧，就只允许朝那一侧的 180° 半平面发射。
# 左侧吸管 => 只能攻击世界 X 方向左半边；角色左右翻转后吸管位置一起镜像，攻击半平面也随之切换。
@export var restrict_attack_to_straw_side:bool = true

@export_category("菊花茶 - 周期重力")
# 每次重力结束后等待这段时间再触发下一次；属于自动周期技能，不占普通 Skill 状态。
@export_range(0.5,30.0,0.1) var gravity_cycle_interval:float = 7.0
@export_range(0.2,15.0,0.1) var gravity_active_duration:float = 3.0
@export_range(10.0,1500.0,5.0) var gravity_acceleration:float = 300.0
# V297：重力激活期间对所有合法战斗目标持续造成伤害。
# 这里表示“每秒伤害 = 当前整体攻击力 × 此倍率”；默认 0.5，即每秒 50% 攻击力。
@export_range(0.0,4.0,0.05) var gravity_damage_per_second_multiplier:float = 0.50
# 伤害按固定间隔结算，避免每个物理帧都触发受击闪白/音效。默认 0.20 秒即每秒 5 次。
@export_range(0.05,1.0,0.05) var gravity_damage_tick_interval:float = 0.20

var _gravity_cycle_left:float = 0.0
var _gravity_active_left:float = 0.0
var _gravity_active:bool = false
var _gravity_damage_tick_left:float = 0.0
var _last_gravity_direction:Vector2 = Vector2.RIGHT
var _last_straw_aim_direction:Vector2 = Vector2.RIGHT
var _tea_body_base_position:Vector2 = Vector2.ZERO
var _tea_body_position_captured:bool = false
var _straw_manual_setup_captured:bool = false
var _straw_authored_transform:Transform2D = Transform2D.IDENTITY
var _realtime_mouse_world_position:Vector2 = Vector2.ZERO
var _realtime_mouse_world_valid:bool = false
var _straw_side_target_cache:WeakRef = null
var _straw_side_target_cache_until_msec:int = 0
const STRAW_SIDE_TARGET_REFRESH_MSEC:int = 100


func _ready() -> void:
	Health_Restore = 0
	Has_Collision_Damage = false
	# 重力是自动周期技能；不让状态机再额外启动一个手动 Skill 状态。
	Can_Skill = false
	super._ready()
	_apply_tea_body_visual_offset()
	add_to_group("ChrysanthemumTeaCharacter")
	_gravity_cycle_left = maxf(gravity_cycle_interval,0.5)
	_update_side_status()
	_capture_manual_straw_setup()
	_sync_straw_to_tea_sprite()
	_update_straw_to_v297_preview_launch()


func _input(event:InputEvent) -> void:
	# V302：本机鼠标事件直接刷新“V297 抛物线的起射角预览”。
	# 管头不再指向鼠标直线，而是通过 StrawHeadPivot 刚体旋转到当前 V297 子弹真正会使用的起射角。
	if event is InputEventMouseMotion and _is_locally_controlled_tea():
		_realtime_mouse_world_position = get_global_mouse_position()
		_realtime_mouse_world_valid = true
		_sync_straw_to_tea_sprite()
		_update_straw_to_v297_preview_launch()


func _process(_delta:float) -> void:
	# 每个显示帧直接采样鼠标，并重新按 V297 抛物线公式求当前预览起射角。
	# 这样吸管仍实时跟踪，但跟踪的是“子弹起射方向”，不是目标位置直线。
	if _is_locally_controlled_tea():
		_realtime_mouse_world_position = get_global_mouse_position()
		_realtime_mouse_world_valid = true
	_sync_straw_to_tea_sprite()
	_update_straw_to_v297_preview_launch()


func tick_physics(state:State,delta:float) -> void:
	if is_multiplayer_authority() and state != State.Die and health > 0:
		_update_gravity_cycle(delta)
	super.tick_physics(state,delta)
	# super.tick_physics() 会更新人物真实左右朝向；物理帧这里只同步整套吸管镜像。
	# V295 起不再在物理帧写 StrawHeadPivot.rotation，避免 60Hz 缓存瞄准与渲染帧实时鼠标互相抢写造成阶梯/回跳。
	_sync_straw_to_tea_sprite()


func Attack() -> void:
	super()
	if state_machine.current_state == State.Die or not is_multiplayer_authority():
		return
	if is_damage_output_disabled() or not is_combat_runtime_active():
		Attacking = false
		return
	_spawn_tea_droplet()


func Die() -> void:
	_clear_gravity_field()
	_update_side_status(true)
	super()


func _exit_tree() -> void:
	_clear_gravity_field()
	_update_side_status(true)


func _spawn_tea_droplet() -> void:
	if TEA_DROPLET_SCENE == null:
		return
	var world:Node = get_tree().current_scene
	if world == null:
		return

	# V302：子弹行为整体回退到 V297。这里只先决定 V297 原本就会使用的目标、随机弧度和目标预判。
	_sync_straw_to_tea_sprite()
	var target:Node = null if has_player_control_aim() else _resolve_straw_side_attack_target()
	if not has_player_control_aim() and (target == null or not is_instance_valid(target)):
		return

	var fallback_direction:Vector2 = _resolve_attack_direction(target)
	if not _is_direction_in_straw_attack_half_plane(fallback_direction):
		return

	var arc_center:float = clampf(projectile_arc_time_center,0.75,1.75)
	var arc_variation:float = clampf(projectile_arc_time_variation,0.0,0.45)
	var arc_time_scale:float = randf_range(
		maxf(arc_center - arc_variation,0.60),
		minf(arc_center + arc_variation,1.70)
	)
	var target_position:Vector2 = (
		_current_player_attack_aim_world_position(global_position + fallback_direction * 260.0)
		if has_player_control_aim()
		else combat_target_position(target)
	)
	var target_velocity:Vector2 = Vector2.ZERO if has_player_control_aim() else combat_target_velocity(target)
	var spawn_jitter:Vector2 = Vector2(
		randf_range(-maxf(projectile_spawn_horizontal_jitter,0.0),maxf(projectile_spawn_horizontal_jitter,0.0)),
		randf_range(-maxf(projectile_spawn_vertical_jitter,0.0),maxf(projectile_spawn_vertical_jitter,0.0))
	)

	# 关键改法：先按 V297 公式求“这一发实际初速度”，再让 StrawHeadPivot 整块转到这个角度。
	# Pivot 旋转会改变 StrawMuzzle 的世界位置，所以做固定点迭代：
	# 当前枪口位置 -> V297 起射角 -> Pivot 旋到该角 -> 新枪口位置 -> 再算。
	# 收敛后“当前真实管口方向”和“用当前真实枪口位置算出的 V297 初速度方向”是同一个方向。
	var launch_velocity:Vector2 = Vector2.ZERO
	var spawn_position:Vector2 = Vector2.ZERO
	for _i:int in range(20):
		spawn_position = _projectile_spawn_anchor() + spawn_jitter
		launch_velocity = _calculate_v297_parabolic_launch_velocity(
			spawn_position,
			target_position,
			fallback_direction,
			target_velocity,
			maxf(projectile_speed,60.0),
			maxf(projectile_gravity,0.0),
			clampf(projectile_target_prediction,0.0,1.0),
			arc_time_scale,
			clampf(projectile_vertical_aim_max_angle_deg,0.0,45.0),
			maxf(projectile_vertical_aim_full_offset,20.0)
		)
		if launch_velocity.length_squared() <= 0.000001:
			launch_velocity = fallback_direction * maxf(projectile_speed,60.0)
		var desired_launch_direction:Vector2 = launch_velocity.normalized()
		if not _is_direction_in_straw_attack_half_plane(desired_launch_direction):
			return
		var outlet_direction:Vector2 = _current_straw_outlet_world_direction()
		if outlet_direction.length_squared() > 0.000001 and absf(outlet_direction.angle_to(desired_launch_direction)) <= 0.00001:
			break
		_update_straw_aim(desired_launch_direction,0.0,true)

	# 以收敛后的真实枪口位置做最终一次 V297 速度计算。这里不再额外改变子弹算法。
	spawn_position = _projectile_spawn_anchor() + spawn_jitter
	launch_velocity = _calculate_v297_parabolic_launch_velocity(
		spawn_position,
		target_position,
		fallback_direction,
		target_velocity,
		maxf(projectile_speed,60.0),
		maxf(projectile_gravity,0.0),
		clampf(projectile_target_prediction,0.0,1.0),
		arc_time_scale,
		clampf(projectile_vertical_aim_max_angle_deg,0.0,45.0),
		maxf(projectile_vertical_aim_full_offset,20.0)
	)
	if launch_velocity.length_squared() <= 0.000001:
		return
	var launch_direction:Vector2 = launch_velocity.normalized()
	# 最终做误差门槛：宁可极端情况下这一发不生成，也不允许“子弹角和可见管口角明显分叉”。
	var final_outlet_direction:Vector2 = _current_straw_outlet_world_direction()
	if final_outlet_direction.length_squared() <= 0.000001:
		return
	if absf(final_outlet_direction.angle_to(launch_direction)) > 0.0005:
		_update_straw_aim(launch_direction,0.0,true)
		spawn_position = _projectile_spawn_anchor() + spawn_jitter
		launch_velocity = _calculate_v297_parabolic_launch_velocity(
			spawn_position,
			target_position,
			fallback_direction,
			target_velocity,
			maxf(projectile_speed,60.0),
			maxf(projectile_gravity,0.0),
			clampf(projectile_target_prediction,0.0,1.0),
			arc_time_scale,
			clampf(projectile_vertical_aim_max_angle_deg,0.0,45.0),
			maxf(projectile_vertical_aim_full_offset,20.0)
		)
		if launch_velocity.length_squared() <= 0.000001:
			return
		launch_direction = launch_velocity.normalized()
		final_outlet_direction = _current_straw_outlet_world_direction()
		if final_outlet_direction.length_squared() <= 0.000001 or absf(final_outlet_direction.angle_to(launch_direction)) > 0.001:
			return

	var projectile:ball = TEA_DROPLET_SCENE.instantiate() as ball
	if projectile == null:
		return
	projectile.Master = self
	projectile.Master_name = name
	projectile.Team = Team
	projectile.Damage = Damage
	projectile.direction = fallback_direction
	projectile.Speed = maxf(projectile_speed,60.0)
	projectile.inherit_master_attack_power = true
	projectile.master_attack_damage_multiplier = maxf(projectile_damage_multiplier,0.0)
	projectile.name = Game.return_random_name(projectile)
	world.add_child(projectile,true)
	projectile.global_position = spawn_position
	if projectile.has_method("configure_parabolic_launch"):
		projectile.call(
			"configure_parabolic_launch",
			spawn_position,
			target_position,
			fallback_direction,
			target_velocity,
			maxf(projectile_speed,60.0),
			maxf(projectile_gravity,0.0),
			clampf(projectile_target_prediction,0.0,1.0),
			maxf(projectile_lifetime,0.2),
			arc_time_scale,
			clampf(projectile_vertical_aim_max_angle_deg,0.0,45.0),
			maxf(projectile_vertical_aim_full_offset,20.0)
		)


func _calculate_v297_parabolic_launch_velocity(
	start:Vector2,
	target:Vector2,
	fallback_direction:Vector2,
	target_velocity:Vector2,
	launch_speed_hint:float,
	gravity_strength:float,
	prediction:float,
	arc_time_scale:float,
	vertical_aim_max_angle_deg:float,
	vertical_aim_full_offset:float
) -> Vector2:
	# V302：逐句保持 V297 / 原菊花茶水滴.configure_parabolic_launch() 的速度求解。
	# 这个纯计算副本只用于先旋转 StrawHeadPivot；真正水滴仍调用原 V297 configure。
	var aim_direction:Vector2 = fallback_direction.normalized() if fallback_direction.length_squared() > 0.000001 else Vector2.RIGHT
	var speed_hint:float = maxf(launch_speed_hint,60.0)
	var flight_min:float = maxf(minf(V297_DROPLET_MIN_FLIGHT_TIME,V297_DROPLET_MAX_FLIGHT_TIME),0.10)
	var flight_max:float = maxf(maxf(V297_DROPLET_MIN_FLIGHT_TIME,V297_DROPLET_MAX_FLIGHT_TIME),flight_min)

	var raw_delta_x:float = target.x - start.x
	var initial_horizontal_distance:float = absf(raw_delta_x)
	var initial_flight_time:float = clampf(initial_horizontal_distance / speed_hint,flight_min,flight_max)
	initial_flight_time = clampf(initial_flight_time * clampf(arc_time_scale,0.60,1.70),flight_min,flight_max)

	var predicted_target_x:float = target.x + target_velocity.x * initial_flight_time * clampf(prediction,0.0,1.0)
	var delta_x:float = predicted_target_x - start.x
	var horizontal_distance:float = absf(delta_x)
	var flight_time:float = clampf(horizontal_distance / speed_hint,flight_min,flight_max)
	flight_time = clampf(flight_time * clampf(arc_time_scale,0.60,1.70),flight_min,flight_max)

	var gravity_strength_safe:float = maxf(gravity_strength,0.0)
	var vx:float = delta_x / maxf(flight_time,0.001)
	var vertical_reference_y:float = global_position.y
	var base_arc_vy:float = (
		vertical_reference_y - start.y - 0.5 * gravity_strength_safe * flight_time * flight_time
	) / maxf(flight_time,0.001)

	var vertical_delta:float = target.y - vertical_reference_y
	var vertical_ratio:float = clampf(
		vertical_delta / maxf(vertical_aim_full_offset,20.0),
		-1.0,
		1.0
	)
	var max_angle_rad:float = deg_to_rad(clampf(vertical_aim_max_angle_deg,0.0,45.0))
	var angle_bias:float = vertical_ratio * max_angle_rad
	var angle_reference_speed:float = maxf(absf(vx),speed_hint * 0.55)
	var directional_vy:float = tan(angle_bias) * angle_reference_speed
	var vy:float = base_arc_vy + directional_vy
	if vertical_ratio > 0.0:
		vy = base_arc_vy * (1.0 - vertical_ratio) + directional_vy

	var result:Vector2 = Vector2(vx,vy)
	if result.length_squared() <= 0.000001:
		result = aim_direction * speed_hint
	return result


func _current_straw_outlet_world_direction() -> Vector2:
	if _straw_mouth_inner == null or _straw_muzzle == null:
		return Vector2.ZERO
	if not is_instance_valid(_straw_mouth_inner) or not is_instance_valid(_straw_muzzle):
		return Vector2.ZERO
	var outlet:Vector2 = _straw_muzzle.global_position - _straw_mouth_inner.global_position
	return outlet.normalized() if outlet.length_squared() > 0.000001 else Vector2.ZERO


func _update_straw_to_v297_preview_launch() -> void:
	# 实时预览使用 V297 的中心 arc_time，不引入每发随机 variation；真正开火时再按 V297 随机一次。
	var target:Node = null if has_player_control_aim() else _resolve_straw_side_attack_target()
	if not has_player_control_aim() and (target == null or not is_instance_valid(target)):
		return
	var fallback_direction:Vector2 = _resolve_attack_direction(target)
	if fallback_direction.length_squared() <= 0.000001 or not _is_direction_in_straw_attack_half_plane(fallback_direction):
		return
	var target_position:Vector2 = (
		_current_player_attack_aim_world_position(global_position + fallback_direction * 260.0)
		if has_player_control_aim()
		else combat_target_position(target)
	)
	var target_velocity:Vector2 = Vector2.ZERO if has_player_control_aim() else combat_target_velocity(target)
	var preview_arc:float = clampf(projectile_arc_time_center,0.75,1.75)
	# Pivot 改角会改变枪口位置，3 次迭代足够让显示帧中的管口方向贴合新的 V297 起射角。
	for _i:int in range(5):
		var start:Vector2 = _projectile_spawn_anchor()
		var velocity:Vector2 = _calculate_v297_parabolic_launch_velocity(
			start,
			target_position,
			fallback_direction,
			target_velocity,
			maxf(projectile_speed,60.0),
			maxf(projectile_gravity,0.0),
			clampf(projectile_target_prediction,0.0,1.0),
			preview_arc,
			clampf(projectile_vertical_aim_max_angle_deg,0.0,45.0),
			maxf(projectile_vertical_aim_full_offset,20.0)
		)
		if velocity.length_squared() <= 0.000001:
			break
		_update_straw_aim(velocity.normalized(),0.0,true)


func _projectile_spawn_anchor() -> Vector2:
	# V292：正常情况下直接使用场景里可手动拖动的 StrawMuzzle Marker2D。
	# 这样“发射口在哪里”完全由场景节点决定，不再依赖脚本里的 UV 猜测。
	if _straw_muzzle != null and is_instance_valid(_straw_muzzle):
		return _straw_muzzle.global_position

	# Marker 被误删/节点损坏时才回退到人物头顶。
	var fallback:Vector2 = global_position + Vector2(0.0,-22.0 - maxf(projectile_spawn_above_gap,0.0))
	if image == null or not is_instance_valid(image) or not image is Node2D:
		return fallback
	if image is Sprite2D:
		var sprite:Sprite2D = image as Sprite2D
		if sprite.texture == null:
			return fallback
		var rect:Rect2 = sprite.get_rect()
		var top_left:Vector2 = sprite.to_global(rect.position)
		var top_right:Vector2 = sprite.to_global(rect.position + Vector2(rect.size.x,0.0))
		return Vector2((top_left.x + top_right.x) * 0.5,minf(top_left.y,top_right.y) - maxf(projectile_spawn_above_gap,0.0))
	return fallback


func _apply_tea_body_visual_offset() -> void:
	# CharacterAutoFit 是子节点，会在人物根 _ready() 之前完成初始拟合。
	# 因此这里再移动 Image 只改变显示构图，不会把 CollisionShape2D / hurtbox / hitbox 一起向下拖。
	if image == null or not is_instance_valid(image) or not image is Sprite2D:
		return
	var tea_sprite:Sprite2D = image as Sprite2D
	if not _tea_body_position_captured:
		_tea_body_base_position = tea_sprite.position
		_tea_body_position_captured = true
	tea_sprite.position = _tea_body_base_position + tea_body_visual_offset


func _capture_manual_straw_setup() -> void:
	# 只在进入场景时读取一次用户当前 .tscn 手工摆好的完整 Transform2D。
	# V294 不把 transform 拆成 position/rotation/scale 再重建，因为用户场景现在还包含 skew；
	# 保存完整矩阵才能无损保留用户手调结果。
	if _straw_manual_setup_captured or _straw_rig == null or not is_instance_valid(_straw_rig):
		return
	_straw_authored_transform = _straw_rig.transform
	_straw_manual_setup_captured = true


func _sync_straw_to_tea_sprite() -> void:
	if _straw_rig == null or _straw_stem == null or _straw_head_pivot == null or _straw_head == null:
		return
	if not is_instance_valid(_straw_rig) or not is_instance_valid(_straw_stem) or not is_instance_valid(_straw_head_pivot) or not is_instance_valid(_straw_head):
		return
	_capture_manual_straw_setup()
	if not _straw_manual_setup_captured:
		return

	# V294：用户场景的 authored Transform2D 是唯一基础构图。
	# 角色左右翻转时，在 Graphics 父空间绕 X=0 做水平反射：这样不仅吸管图形翻转，
	# StrawRig.position.x 也会一起镜像，真正跟随人物左右反转。
	var runtime_transform:Transform2D = _straw_authored_transform
	var scale_multiplier:float = maxf(straw_visual_scale_multiplier,0.01)
	runtime_transform.x = runtime_transform.x * scale_multiplier
	runtime_transform.y = runtime_transform.y * scale_multiplier

	if is_character_visual_flipped_h():
		runtime_transform = Transform2D.FLIP_X * runtime_transform

	# 直接写 Transform2D，避免带 skew + 反射时通过 Node2D.scale/rotation 分解产生额外 180°/负 Y 变化。
	_straw_rig.transform = runtime_transform


func _update_straw_aim(desired_direction:Vector2,delta:float = 0.0,snap:bool = false) -> void:
	if _straw_head_pivot == null or _straw_mouth_inner == null or _straw_muzzle == null or _straw_rig == null:
		return
	if not is_instance_valid(_straw_head_pivot) or not is_instance_valid(_straw_mouth_inner) or not is_instance_valid(_straw_muzzle) or not is_instance_valid(_straw_rig):
		return
	if desired_direction.length_squared() <= 0.000001:
		return
	_last_straw_aim_direction = desired_direction.normalized()

	# 两个 Marker2D 都是 StrawHeadPivot 的直属子节点：
	# StrawMouthInner -> StrawMuzzle 这条线就是“吸管头在 rotation=0 时的基础出口方向”。
	var base_outlet_direction:Vector2 = _straw_muzzle.position - _straw_mouth_inner.position
	if base_outlet_direction.length_squared() <= 0.000001:
		return

	# V294：不能再只减 global_rotation。用户当前 StrawRig 有 skew，且角色翻转时 runtime Transform2D
	# 还包含水平反射；单独 global_rotation 无法正确表示这套完整基变换。
	# 用 affine_inverse().basis_xform() 把世界方向精确转换到 StrawRig 局部空间，
	# 同时正确处理缩放、skew 和负行列式反射。
	var inverse_basis:Transform2D = _straw_rig.global_transform.affine_inverse()
	var desired_local_direction:Vector2 = inverse_basis.basis_xform(_last_straw_aim_direction)
	if desired_local_direction.length_squared() <= 0.000001:
		return
	desired_local_direction = desired_local_direction.normalized()

	var desired_rotation:float = wrapf(
		desired_local_direction.angle() - base_outlet_direction.angle() + deg_to_rad(straw_aim_angle_offset_deg),
		-PI,
		PI
	)
	var max_rotation:float = deg_to_rad(clampf(straw_head_max_rotation_deg,0.0,180.0))
	var target_rotation:float = desired_rotation if max_rotation >= PI - 0.0001 else clampf(desired_rotation,-max_rotation,max_rotation)

	if snap or delta <= 0.0:
		_straw_head_pivot.rotation = target_rotation
		return

	# 渲染帧指数跟随：没有“角度分档”，每一帧都会朝当前目标角度移动。
	# lerp_angle 负责跨 -PI/PI 时取最短路径，response 控制跟随速度。
	var response:float = maxf(straw_aim_follow_response,1.0)
	var weight:float = clampf(1.0 - exp(-response * maxf(delta,0.0)),0.0,1.0)
	_straw_head_pivot.rotation = lerp_angle(_straw_head_pivot.rotation,target_rotation,weight)


func _is_locally_controlled_tea() -> bool:
	if not is_player_controlled() or Game == null or not Game.has_method("get_local_controlled_character"):
		return false
	return Game.call("get_local_controlled_character") == self


func _current_player_attack_aim_world_position(fallback:Vector2) -> Vector2:
	if _is_locally_controlled_tea():
		return _realtime_mouse_world_position if _realtime_mouse_world_valid else get_global_mouse_position()
	return player_control_aim_world_position(fallback)


func _straw_attack_side_sign() -> float:
	# 直接用当前运行时 StrawRig 的世界位置判断吸管在哪一侧。
	# V294 起 StrawRig 会随人物左右镜像，因此这里天然跟随角色翻转，不需要再维护第二套方向状态。
	if _straw_rig != null and is_instance_valid(_straw_rig):
		var offset_x:float = _straw_rig.global_position.x - global_position.x
		if absf(offset_x) > 0.5:
			return -1.0 if offset_x < 0.0 else 1.0
	# 极端情况下 StrawRig 与角色中心几乎重合，退回公共人物翻转状态。当前 authored 构图默认吸管在左侧。
	return 1.0 if is_character_visual_flipped_h() else -1.0


func _is_direction_in_straw_attack_half_plane(world_direction:Vector2) -> bool:
	if not restrict_attack_to_straw_side:
		return true
	if world_direction.length_squared() <= 0.000001:
		return false
	var allowed_axis:Vector2 = Vector2(_straw_attack_side_sign(),0.0)
	# 单位向量点积 >= 0 即与允许轴夹角 <= 90°，正好组成该侧 180° 半平面。
	return world_direction.normalized().dot(allowed_axis) >= -0.0001


func _is_target_in_straw_attack_half_plane(target:Node) -> bool:
	if target == null or not is_instance_valid(target) or not target is Node2D:
		return false
	var to_target:Vector2 = (target as Node2D).global_position - global_position
	return _is_direction_in_straw_attack_half_plane(to_target)


func _can_use_as_straw_side_enemy(candidate:ball) -> bool:
	if candidate == null or candidate == self or not is_instance_valid(candidate):
		return false
	if candidate.health <= 0 or candidate.is_queued_for_deletion():
		return false
	if candidate.has_method("is_combat_targetable") and not bool(candidate.call("is_combat_targetable")):
		return false
	# 普通 AI 索敌仍然以敌方为主；Can_Target_Teammates 明确开启时才允许同队候选。
	if not Can_Target_Teammates and not Team.is_empty() and candidate.Team == Team:
		return false
	return _is_target_in_straw_attack_half_plane(candidate)


func _resolve_straw_side_attack_target() -> Node:
	# 先复用公共目标；若它在错误半平面，则在本角色允许的 180° 内重新找最近合法目标。
	# V60 之后项目明确要求避免高频 O(N) 扫描，因此这个补充搜索最多 10Hz；渲染帧只复用缓存。
	var preferred:Node = return_reusable_combat_target()
	if preferred is ball and _can_use_as_straw_side_enemy(preferred as ball):
		_straw_side_target_cache = weakref(preferred)
		_straw_side_target_cache_until_msec = Time.get_ticks_msec() + STRAW_SIDE_TARGET_REFRESH_MSEC
		return preferred

	var now_msec:int = Time.get_ticks_msec()
	if _straw_side_target_cache != null:
		var cached:Object = _straw_side_target_cache.get_ref()
		if cached is ball and _can_use_as_straw_side_enemy(cached as ball):
			if now_msec < _straw_side_target_cache_until_msec:
				return cached as ball
		else:
			# 人物翻转/目标跨过半平面时立即使缓存失效，不等待剩余100ms。
			_straw_side_target_cache_until_msec = 0
	if now_msec < _straw_side_target_cache_until_msec:
		return null

	_straw_side_target_cache_until_msec = now_msec + STRAW_SIDE_TARGET_REFRESH_MSEC
	var nearest:ball = null
	var nearest_distance_sq:float = INF
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var candidate:ball = raw as ball
		if not _can_use_as_straw_side_enemy(candidate):
			continue
		var distance_sq:float = global_position.distance_squared_to(candidate.global_position)
		if distance_sq < nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest = candidate
	_straw_side_target_cache = weakref(nearest) if nearest != null else null
	return nearest


func _resolve_visual_attack_direction() -> Vector2:
	# V296：本机视觉优先使用鼠标事件/_process 直接采样得到的实时世界坐标。
	# 不再依赖 ball.player_control_aim_position 的物理帧缓存。
	if _is_locally_controlled_tea():
		var realtime_world:Vector2 = _realtime_mouse_world_position if _realtime_mouse_world_valid else get_global_mouse_position()
		var realtime_mouse_direction:Vector2 = realtime_world - global_position
		if realtime_mouse_direction.length_squared() > 0.000001:
			return realtime_mouse_direction.normalized()

	# AI、远端玩家以及没有本机鼠标控制的情况，只选择吸管所在一侧 180° 内的目标。
	var target:Node = _resolve_straw_side_attack_target()
	var result:Vector2 = _resolve_attack_direction(target)
	return result if result.length_squared() > 0.000001 else _last_straw_aim_direction

func _resolve_attack_direction(target:Node) -> Vector2:
	var resolved:Vector2 = Vector2.ZERO
	if has_player_control_aim():
		# 本机直接控制时使用与吸管视觉同一份实时鼠标世界坐标，避免视觉已经过半平面边界但物理缓存还没更新。
		if _is_locally_controlled_tea():
			var aim_world:Vector2 = _realtime_mouse_world_position if _realtime_mouse_world_valid else get_global_mouse_position()
			resolved = aim_world - global_position
		else:
			resolved = player_control_aim_direction(_last_gravity_direction)
	if resolved.length_squared() <= 0.000001 and target != null and is_instance_valid(target):
		resolved = combat_target_position(target) - global_position
	if resolved.length_squared() <= 0.000001:
		resolved = _resolve_gravity_direction()
	if resolved.length_squared() <= 0.000001:
		resolved = Vector2.RIGHT
	return resolved.normalized()


func _update_gravity_cycle(delta:float) -> void:
	var resolved_direction:Vector2 = _resolve_gravity_direction()
	if resolved_direction.length_squared() > 0.000001:
		_last_gravity_direction = resolved_direction

	if not is_combat_runtime_active():
		_sync_gravity_field(false,resolved_direction)
		_update_side_status()
		return

	if _gravity_active:
		_gravity_active_left = maxf(_gravity_active_left - maxf(delta,0.0),0.0)
		_sync_gravity_field(true,resolved_direction)
		_update_gravity_continuous_damage(delta)
		if _gravity_active_left <= 0.0:
			_gravity_active = false
			_gravity_damage_tick_left = 0.0
			_gravity_cycle_left = maxf(gravity_cycle_interval,0.5)
			_sync_gravity_field(false,resolved_direction)
	else:
		_gravity_cycle_left = maxf(_gravity_cycle_left - maxf(delta,0.0),0.0)
		if _gravity_cycle_left <= 0.0:
			_gravity_active = true
			_gravity_active_left = maxf(gravity_active_duration,0.2)
			_gravity_damage_tick_left = clampf(gravity_damage_tick_interval,0.05,1.0)
			_sync_gravity_field(true,resolved_direction)
			_sync_gravity_activation_feedback_request(resolved_direction)

	if image != null and is_instance_valid(image) and image is CanvasItem:
		(image as CanvasItem).self_modulate = Color(0.82,1.0,0.82,1.0) if _gravity_active else Color.WHITE
	_update_side_status()


func _update_gravity_continuous_damage(delta:float) -> void:
	if not is_multiplayer_authority() or not _gravity_active:
		return
	if is_damage_output_disabled() or not is_combat_runtime_active():
		return
	var interval:float = clampf(gravity_damage_tick_interval,0.05,1.0)
	_gravity_damage_tick_left -= maxf(delta,0.0)
	# 最多补 4 次，避免极端卡顿一帧后积压过多命中反馈。
	var safety:int = 0
	while _gravity_damage_tick_left <= 0.0 and safety < 4:
		_deal_gravity_damage_tick(interval)
		_gravity_damage_tick_left += interval
		safety += 1


func _deal_gravity_damage_tick(interval:float) -> void:
	var damage_per_tick:float = attack_damage(maxf(gravity_damage_per_second_multiplier,0.0) * maxf(interval,0.0))
	if damage_per_tick <= 0.0:
		return
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var target:ball = raw as ball
		if not _can_gravity_damage_target(target):
			continue
		target.receive_spatial_damage(
			damage_per_tick,
			{
				"point": target.global_position,
				"source": self,
			},
			false,
			false
		)


func _can_gravity_damage_target(target:ball) -> bool:
	if target == null or target == self or not is_instance_valid(target):
		return false
	if target.health <= 0 or target.is_queued_for_deletion():
		return false
	if target.Master != null and is_instance_valid(target.Master) and target.Master == self:
		return false
	if target.has_method("is_combat_targetable") and not bool(target.call("is_combat_targetable")):
		return false
	# 与项目 Hitbox 规则一致：默认尊重 Have_Team_Damage；角色自身显式 Ignore_Team_Damage_Setting 时允许无视该开关。
	var team_damage_enabled:bool = bool(Game.Game_Settings.get("Have_Team_Damage",false))
	if (
		not team_damage_enabled
		and not Ignore_Team_Damage_Setting
		and not Team.is_empty()
		and target.Team == Team
	):
		return false
	return true


func _sync_gravity_activation_feedback_request(resolved_direction:Vector2) -> void:
	# 重力周期只由 authority 推进；音效、全屏颤抖和速度线可靠 RPC 到所有 peer。
	var safe_direction:Vector2 = resolved_direction.normalized() if resolved_direction.length_squared() > 0.000001 else _last_gravity_direction
	if safe_direction.length_squared() <= 0.000001:
		safe_direction = Vector2.RIGHT
	if multiplayer.has_multiplayer_peer():
		_sync_gravity_activation_feedback.rpc(safe_direction,maxf(gravity_active_duration,0.2))
	else:
		_sync_gravity_activation_feedback(safe_direction,maxf(gravity_active_duration,0.2))


@rpc("authority","call_local","reliable")
func _sync_gravity_activation_feedback(initial_direction:Vector2,visual_duration:float) -> void:
	_play_gravity_activation_audio()
	_trigger_gravity_screen_shake()
	_spawn_gravity_speed_lines(initial_direction,visual_duration)


func _play_gravity_activation_audio() -> void:
	if not ResourceLoader.exists(GRAVITY_AUDIO_PATH):
		return
	var loaded:Resource = ResourceLoader.load(GRAVITY_AUDIO_PATH)
	if not loaded is AudioStream:
		return
	var player := AudioStreamPlayer2D.new()
	player.name = "ChrysanthemumTeaGravityAudio"
	player.stream = loaded as AudioStream
	# V284：原始重力音整体响度偏低，提高增益并降低距离衰减；仍保持 2D 定位。
	player.max_distance = 3000.0
	player.attenuation = 0.20
	player.volume_db = 10.0
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	add_child(player)
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _trigger_gravity_screen_shake() -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return
	if _object_has_property(world,&"camera_shake_amount"):
		var current_amount:float = float(world.get(&"camera_shake_amount"))
		world.set(&"camera_shake_amount",maxf(current_amount,95.0))


func _spawn_gravity_speed_lines(initial_direction:Vector2,visual_duration:float) -> void:
	var world:Node = get_tree().current_scene
	if world == null or GRAVITY_VISUAL_SCRIPT == null:
		return
	var visual:Node = GRAVITY_VISUAL_SCRIPT.new()
	if visual == null:
		return
	if visual.has_method("configure"):
		visual.call("configure",self,maxf(visual_duration,0.2),initial_direction)
	visual.name = "ChrysanthemumTeaGravityVisual"
	world.add_child(visual,true)


func _object_has_property(object:Object,property_name:StringName) -> bool:
	# V431 性能：按脚本缓存属性名集合（classes/property_index.gd），不再逐次 get_property_list()。
	return PROPERTY_INDEX.has_property(object,String(property_name))


const PROPERTY_INDEX = preload("res://classes/property_index.gd")

func _resolve_gravity_direction() -> Vector2:
	# “当前移动方向”优先读取玩家输入/上一帧真实 velocity；AI direction 只做静止时兜底。
	var candidate:Vector2 = player_control_direction if is_player_controlled() else velocity
	if candidate.length_squared() <= 0.000001:
		candidate = direction
	if candidate.length_squared() <= 0.000001:
		candidate = _last_gravity_direction
	return candidate.normalized() if candidate.length_squared() > 0.000001 else Vector2.RIGHT


func _sync_gravity_field(active:bool,resolved_direction:Vector2) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return
	if not world.has_method("register_directional_gravity") or not world.has_method("clear_directional_gravity"):
		return
	if active and resolved_direction.length_squared() > 0.000001:
		world.call(
			"register_directional_gravity",
			self,
			GRAVITY_FIELD_KEY,
			resolved_direction.normalized(),
			maxf(gravity_acceleration,0.0),
			false
		)
	else:
		world.call("clear_directional_gravity",self,GRAVITY_FIELD_KEY)


func _clear_gravity_field() -> void:
	var world:Node = get_tree().current_scene
	if world != null and world.has_method("clear_directional_gravity"):
		world.call("clear_directional_gravity",self,GRAVITY_FIELD_KEY)


func _update_side_status(clear_only:bool = false) -> void:
	if not has_method("side_status_set_permanent") or not has_method("side_status_remove_permanent"):
		return
	if clear_only:
		call("side_status_remove_permanent","right","chrysanthemum_tea_gravity")
		return
	if _gravity_active:
		call(
			"side_status_set_permanent",
			"right",
			"chrysanthemum_tea_gravity",
			"重力场",
			Color(0.28,0.96,0.42,1.0)
		)
	else:
		call(
			"side_status_set_permanent",
			"right",
			"chrysanthemum_tea_gravity",
			"重力蓄积",
			Color(0.75,0.94,0.62,1.0)
		)
