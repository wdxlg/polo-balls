extends Sprite2D

# 保安增援车的独立碰撞伤害控制。
# 这个脚本直接挂在车辆 Sprite2D 上，因此原呼叫保安死亡后，车辆仍能自己完成命中结算。
# 伤害只允许发生在“驶入到停车点”的阶段；停车、下人和离场阶段全部关闭。

var damage_enabled:bool = false
var owner_team:String = ""
var collision_damage:float = 50.0
var knockback_distance:float = 72.0
var knockback_speed:float = 760.0
var travel_direction:Vector2 = Vector2.RIGHT

# 这里表示真正有撞击伤害的“车身核心”半尺寸，而不是整张图片尺寸。
# 保险杠、透明留白和车顶区域都不应该把碰撞判定撑大。
var car_half_length:float = 31.0
var car_half_thickness:float = 12.0
var damage_stop_position:Vector2 = Vector2.ZERO
var _has_damage_stop_position:bool = false

var _last_world_position:Vector2 = Vector2.ZERO
var _has_last_position:bool = false
var _hit_target_ids:Dictionary = {}


func _ready() -> void:
	set_physics_process(damage_enabled)


func configure_collision_damage(
	team_value:String,
	enabled_value:bool,
	direction_value:Vector2,
	stop_position_value:Vector2,
	damage_value:float,
	half_length_value:float,
	half_thickness_value:float,
	knockback_distance_value:float,
	knockback_speed_value:float
) -> void:
	owner_team = team_value
	travel_direction = direction_value.normalized() if direction_value.length_squared() > 0.000001 else Vector2.RIGHT
	damage_stop_position = stop_position_value
	_has_damage_stop_position = true
	collision_damage = maxf(damage_value,0.0)
	car_half_length = maxf(half_length_value,4.0)
	car_half_thickness = maxf(half_thickness_value,4.0)
	knockback_distance = maxf(knockback_distance_value,0.0)
	knockback_speed = maxf(knockback_speed_value,0.0)
	_last_world_position = global_position
	_has_last_position = true
	set_damage_active(enabled_value)


func set_damage_active(enabled_value:bool) -> void:
	damage_enabled = enabled_value
	# 重新启用/关闭时都从当前位置重新建立扫掠起点，避免跨阶段扫出一条超长伤害线。
	_last_world_position = global_position
	_has_last_position = true
	set_physics_process(damage_enabled)


func _physics_process(_delta:float) -> void:
	if not damage_enabled:
		return

	var current_position:Vector2 = global_position
	if not _has_last_position:
		_last_world_position = current_position
		_has_last_position = true
		return

	# 等待呼叫期间整辆车不可见。隐藏阶段只同步记录位置，绝不能隔着屏幕扫出一条伤害线。
	if not is_visible_in_tree():
		_last_world_position = current_position
		return

	var scan_end:Vector2 = current_position
	var reached_stop:bool = false

	# 只允许“驶入”这一段造成伤害。即使 Tween/物理帧顺序发生变化，
	# 一旦到达或越过停车点，也只扫到停车点并立刻永久关闭本次车辆伤害。
	if _has_damage_stop_position:
		var previous_remaining:float = (damage_stop_position - _last_world_position).dot(travel_direction)
		var current_remaining:float = (damage_stop_position - current_position).dot(travel_direction)
		if previous_remaining <= 0.0:
			set_damage_active(false)
			return
		if current_remaining <= 0.0:
			scan_end = damage_stop_position
			reached_stop = true

	var moved:Vector2 = scan_end - _last_world_position
	if moved.length_squared() > 0.25:
		_scan_swept_car_contact(_last_world_position,scan_end)

	_last_world_position = current_position
	if reached_stop:
		set_damage_active(false)


func _scan_swept_car_contact(previous_position:Vector2,current_position:Vector2) -> void:
	var move_dir:Vector2 = current_position - previous_position
	if move_dir.length_squared() <= 0.000001:
		move_dir = travel_direction
	else:
		move_dir = move_dir.normalized()

	# 只扫“车身核心”矩形沿本帧运动形成的区域。
	# 相比上一版接近整张车图的范围，这里刻意缩掉保险杠/透明边缘，避免隔空撞人。
	var segment_start:Vector2 = previous_position - move_dir * car_half_length
	var segment_end:Vector2 = current_position + move_dir * car_half_length

	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if not _is_valid_target(target):
			continue

		var nearest:Vector2 = _closest_point_on_segment(target.global_position,segment_start,segment_end)
		# 目标自身碰撞体只提供一个很小的接触余量，不能再用“大半径”把车判定二次撑大。
		var target_margin:float = _estimate_target_contact_margin(target)
		var allowed:float = car_half_thickness + target_margin
		if target.global_position.distance_squared_to(nearest) <= allowed * allowed:
			_hit_target(target,move_dir,segment_start,segment_end)


func _is_valid_target(target:ball) -> bool:
	if target == null or not is_instance_valid(target) or target.health <= 0:
		return false
	if not target.is_combat_targetable():
		return false
	if _hit_target_ids.has(int(target.get_instance_id())):
		return false
	if not Game.Game_Settings.Have_Team_Damage and owner_team != "" and target.Team == owner_team:
		return false
	return true


func _hit_target(target:ball,move_dir:Vector2,damage_segment_start:Vector2,damage_segment_end:Vector2) -> void:
	if not _is_valid_target(target):
		return

	var target_id:int = int(target.get_instance_id())
	_hit_target_ids[target_id] = true

	# 巡逻车真正撞到人物时始终给一次“碰撞伤害”命中声。
	# 不再依赖 block 是否小于伤害值，否则有护盾/格挡时会看见车撞到人却完全没有声音。
	# create_new_audio=true 让一辆车连续撞到多个人时每次命中都有独立声部，不互相截断。
	if collision_damage > 0.0:
		Audios.play_sfx.rpc(
			"balls_hit1",
			{volume = clampf(collision_damage - 12.0,-24.0,0.0)},
			true,
			true
		)
		target.receive_spatial_damage(
			collision_damage,
			{
				"shape":"capsule",
				"from":damage_segment_start,
				"to":damage_segment_end,
				"half_width":maxf(car_half_thickness,1.0),
				"source":self,
			},
			false
		)

	if knockback_distance > 0.0:
		var push_direction:Vector2 = move_dir.normalized() if move_dir.length_squared() > 0.000001 else travel_direction
		target.apply_knockback(
			push_direction,
			knockback_distance,
			knockback_speed,
			0.18,
			0.06,
			{
				"source":self,
				"max_wall_bounces":1,
				"stop_on_character":true,
				"character_bounce_strength":0.18,
				"smooth_motion":true,
			}
		)

	var world:Node = get_tree().current_scene
	if world != null:
		world.camera_shake_amount += 11.0


func _estimate_target_contact_margin(target:ball) -> float:
	var shape_node:CollisionShape2D = target.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or shape_node.shape == null:
		return 5.0

	var scale_value:Vector2 = shape_node.global_scale.abs()
	var shape_value:Shape2D = shape_node.shape
	var margin:float = 5.0
	if shape_value is CircleShape2D:
		margin = (shape_value as CircleShape2D).radius * maxf(scale_value.x,scale_value.y)
	elif shape_value is RectangleShape2D:
		var world_size:Vector2 = (shape_value as RectangleShape2D).size * scale_value
		# 只取较短边，避免高瘦/宽扁碰撞框把车辆判定往所有方向一起放大。
		margin = minf(world_size.x,world_size.y) * 0.5
	elif shape_value is CapsuleShape2D:
		var capsule:CapsuleShape2D = shape_value as CapsuleShape2D
		margin = capsule.radius * maxf(scale_value.x,scale_value.y)

	# 车碰撞判定应该由车身尺寸主导；角色尺寸这里只保留有限接触容错。
	return clampf(margin,3.0,7.0)


func _closest_point_on_segment(point:Vector2,a:Vector2,b:Vector2) -> Vector2:
	var ab:Vector2 = b - a
	var len_sq:float = ab.length_squared()
	if len_sq <= 0.000001:
		return a
	var t:float = clampf((point - a).dot(ab) / len_sq,0.0,1.0)
	return a + ab * t
