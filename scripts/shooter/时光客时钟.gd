extends ball

const REWIND_VHS_SHADER:Shader = preload("res://shaders/time_rewind_vhs.gdshader")

# 时光客时钟弹：
# 正向时记录自己的真实轨迹；时光客倒放时，弹丸按同一条历史轨迹倒着运动。
# 已经命中/撞墙而“消失”的弹丸会短暂保留历史，因此倒放越过消失时刻时会重新出现。

@export_range(0.1,20.0,0.1) var lifetime:float = 6.0
@export_range(0.0,80.0,1.0) var orbit_radius:float = 16.0
@export_range(-20.0,20.0,0.1) var orbit_angular_speed:float = 6.2
@export_range(0.0,6.283185,0.01) var initial_orbit_phase:float = 0.0
@export_range(1.0,5.0,0.1) var history_keep_seconds:float = 2.6
@export_range(1.0,8.0,0.1) var finished_retention_seconds:float = 3.0
@export_range(5.0,50.0,1.0) var rewind_hit_radius:float = 16.0

var _life_left:float = 0.0
var _pivot_position:Vector2 = Vector2.ZERO
var _orbit_angle:float = 0.0
var _history:Array[Dictionary] = []
var _spawn_msec:int = 0
var _forward_finished:bool = false
var _finish_msec:int = -1
var _retention_left:float = 0.0

var _rewinding:bool = false
var _rewind_start_msec:int = 0
var _rewind_target_msec:int = 0
var _rewind_duration:float = 0.9
var _rewind_elapsed:float = 0.0
@export_range(0.0,10.0,0.05) var forward_damage_multiplier:float = 2.6153846

var _rewind_damage_multiplier:float = 1.7
var _rewind_cursor:int = 0
var _rewind_hit_ids:Dictionary = {}
var _rewind_original_image_material:Material = null
var _rewind_local_material:ShaderMaterial = null


func _ready() -> void:
	super._ready()
	add_to_group("TimeTravelerClock")
	_life_left = maxf(lifetime,0.1)
	_spawn_msec = Time.get_ticks_msec()

	var travel_dir:Vector2 = direction.normalized() if direction.length_squared() > 0.000001 else Vector2.RIGHT
	var radial:Vector2 = travel_dir.rotated(PI * 0.5) * maxf(orbit_radius,0.0)
	_orbit_angle = radial.angle() + initial_orbit_phase
	var initial_offset:Vector2 = Vector2.from_angle(_orbit_angle) * maxf(orbit_radius,0.0)
	_pivot_position = global_position - initial_offset
	_record_history_sample()

	if self_hitbox != null and not self_hitbox.on_hit.is_connected(_on_successful_hit):
		self_hitbox.on_hit.connect(_on_successful_hit)


func set_rewind_visual(enabled:bool) -> void:
	if image == null or not is_instance_valid(image) or not image is CanvasItem:
		return
	var item:CanvasItem = image as CanvasItem
	if enabled:
		if _rewind_local_material == null:
			_rewind_original_image_material = item.material
			_rewind_local_material = ShaderMaterial.new()
			_rewind_local_material.shader = REWIND_VHS_SHADER
		item.material = _rewind_local_material
	else:
		if _rewind_local_material != null and item.material == _rewind_local_material:
			item.material = _rewind_original_image_material
		_rewind_local_material = null
		_rewind_original_image_material = null


func tick_physics(_state:State,delta:float) -> void:
	if not is_multiplayer_authority():
		return
	if _rewinding:
		_process_time_rewind(delta)
		return
	if _forward_finished:
		_retention_left -= delta
		if _retention_left <= 0.0:
			_free_self()
		return
	if health <= 0:
		_finish_forward()
		return

	_life_left -= delta
	if _life_left <= 0.0:
		_finish_forward()
		return

	var travel_dir:Vector2 = direction.normalized() if direction.length_squared() > 0.000001 else Vector2.RIGHT
	_pivot_position += travel_dir * maxf(Speed,0.0) * delta
	_orbit_angle += orbit_angular_speed * delta

	var desired_position:Vector2 = _pivot_position + Vector2.from_angle(_orbit_angle) * maxf(orbit_radius,0.0)
	var motion:Vector2 = desired_position - global_position
	if motion.length_squared() > 0.000001:
		var collision:KinematicCollision2D = move_and_collide(motion)
		if collision != null:
			_handle_physical_collision(collision,motion)
			if _forward_finished:
				_record_history_sample()
				return

	global_rotation = _orbit_angle + PI * 0.5
	_record_history_sample()
	_process_auto_after_image(delta)
	Repel = Vector2.ZERO


func begin_time_rewind(
	rewind_start_msec:int,
	rewind_target_msec:int,
	playback_duration:float,
	damage_multiplier:float
) -> void:
	if not is_multiplayer_authority() or _history.size() < 2:
		return
	var first_t:int = int(_history[0].get("t",_spawn_msec))
	var last_t:int = int(_history[-1].get("t",_spawn_msec))
	if last_t < rewind_target_msec or first_t > rewind_start_msec:
		return
	_rewinding = true
	_rewind_start_msec = rewind_start_msec
	_rewind_target_msec = rewind_target_msec
	_rewind_duration = maxf(playback_duration,0.35)
	_rewind_elapsed = 0.0
	_rewind_damage_multiplier = clampf(damage_multiplier,0.0,1.5)
	_rewind_cursor = _history.size() - 1
	_rewind_hit_ids.clear()
	set_rewind_visual(true)
	_set_active_collision(false)


func _process_time_rewind(delta:float) -> void:
	_rewind_elapsed += delta
	var progress:float = clampf(_rewind_elapsed / maxf(_rewind_duration,0.35),0.0,1.0)
	var wanted_msec:int = int(round(lerpf(float(_rewind_start_msec),float(_rewind_target_msec),progress)))

	# 倒放时间仍晚于弹丸的消失时刻：这一刻历史上弹丸本来就不存在。
	if _finish_msec >= 0 and wanted_msec > _finish_msec:
		visible = false
	else:
		visible = wanted_msec >= _spawn_msec
		if visible:
			var old_position:Vector2 = global_position
			var sample:Dictionary = _sample_history_at(wanted_msec)
			global_position = sample.get("p",global_position)
			global_rotation = float(sample.get("r",global_rotation))
			_deal_reverse_projectile_damage(old_position,global_position)

	if progress >= 1.0:
		_finish_time_rewind()


func _finish_time_rewind() -> void:
	var final_time:int = _rewind_target_msec
	set_rewind_visual(false)
	_rewinding = false
	_rewind_elapsed = 0.0
	_rewind_hit_ids.clear()

	if final_time < _spawn_msec:
		_free_self()
		return

	var final_sample:Dictionary = _sample_history_at(final_time)
	global_position = final_sample.get("p",global_position)
	global_rotation = float(final_sample.get("r",global_rotation))
	visible = true
	_forward_finished = false
	_finish_msec = -1
	_retention_left = 0.0
	_set_active_collision(true)

	# 回到过去以后，弹丸寿命也恢复到那个时刻。
	var historical_age:float = maxf(float(final_time - _spawn_msec) / 1000.0,0.0)
	_life_left = maxf(lifetime - historical_age,0.05)

	# 用当前回溯到的位置重新推算公转中心，之后继续正常向前运行。
	var travel_dir:Vector2 = direction.normalized() if direction.length_squared() > 0.000001 else Vector2.RIGHT
	_orbit_angle = global_rotation - PI * 0.5
	_pivot_position = global_position - Vector2.from_angle(_orbit_angle) * maxf(orbit_radius,0.0)
	if travel_dir.length_squared() <= 0.000001:
		direction = Vector2.RIGHT

	# 丢掉“未来”的轨迹，接下来重新记录新的时间线。
	while not _history.is_empty() and int(_history[-1].get("t",0)) > final_time:
		_history.pop_back()
	_record_history_sample()


func _record_history_sample() -> void:
	var now_msec:int = Time.get_ticks_msec()
	_history.append({"t":now_msec,"p":global_position,"r":global_rotation})
	var keep_msec:int = int(round(maxf(history_keep_seconds,1.0) * 1000.0)) + 160
	while _history.size() > 2 and now_msec - int(_history[0].get("t",now_msec)) > keep_msec:
		_history.pop_front()


func _sample_history_at(wanted_msec:int) -> Dictionary:
	if _history.is_empty():
		return {"p":global_position,"r":global_rotation}
	_rewind_cursor = clampi(_rewind_cursor,0,_history.size() - 1)
	while _rewind_cursor > 0 and int(_history[_rewind_cursor].get("t",0)) > wanted_msec:
		_rewind_cursor -= 1
	var left_index:int = clampi(_rewind_cursor,0,_history.size() - 1)
	var right_index:int = mini(left_index + 1,_history.size() - 1)
	var left:Dictionary = _history[left_index]
	var right:Dictionary = _history[right_index]
	var left_t:int = int(left.get("t",wanted_msec))
	var right_t:int = int(right.get("t",wanted_msec))
	var weight:float = 0.0
	if right_t > left_t:
		weight = clampf(float(wanted_msec - left_t) / float(right_t - left_t),0.0,1.0)
	var left_position:Vector2 = left.get("p",global_position)
	var right_position:Vector2 = right.get("p",global_position)
	return {
		"p":left_position.lerp(right_position,weight),
		"r":lerp_angle(float(left.get("r",global_rotation)),float(right.get("r",global_rotation)),weight),
	}


func _deal_reverse_projectile_damage(from_position:Vector2,to_position:Vector2) -> void:
	if _rewind_damage_multiplier <= 0.0:
		return
	var master:ball = Master if Master != null and is_instance_valid(Master) else null
	if master == null or master.is_damage_output_disabled():
		return
	var segment:Vector2 = to_position - from_position
	var segment_len_sq:float = segment.length_squared()
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if _should_ignore_character(target):
			continue
		if not target.is_combat_targetable():
			continue
		var target_id:int = target.get_instance_id()
		if _rewind_hit_ids.has(target_id):
			continue
		var nearest:Vector2 = from_position
		if segment_len_sq > 0.000001:
			var t:float = clampf((target.global_position - from_position).dot(segment) / segment_len_sq,0.0,1.0)
			nearest = from_position + segment * t
		if target.global_position.distance_to(nearest) > maxf(rewind_hit_radius,1.0):
			continue
		_rewind_hit_ids[target_id] = true
		var outgoing:float = master.attack_damage(_rewind_damage_multiplier)
		if outgoing <= 0.0:
			continue
		if target.has_method("try_block_projectile_hit") and bool(target.call("try_block_projectile_hit",self,to_position,outgoing)):
			continue
		target.receive_spatial_damage(
			outgoing,
			{"shape":"capsule","from":from_position,"to":to_position,"half_width":maxf(rewind_hit_radius,1.0),"source":self},
			false
		)


func _handle_physical_collision(collision:KinematicCollision2D,motion:Vector2) -> void:
	if collision == null:
		return
	var collider = collision.get_collider()
	if collider is ball:
		var target:ball = collider as ball
		if _should_ignore_character(target):
			add_collision_exception_with(target)
			if motion.length_squared() > 0.000001:
				global_position += motion.normalized() * 2.0
			return

		if self_hitbox != null and target.self_hurtbox != null:
			self_hitbox.try_hit_hurtbox(target.self_hurtbox)
			_finish_forward()
			return

	var incoming_direction:Vector2 = motion.normalized() if motion.length_squared() > 0.000001 else direction.normalized()
	notify_wall_impact_feedback(
		collision.get_position(),
		collision.get_normal(),
		maxf(Speed,motion.length()),
		-1.0,
		incoming_direction
	)
	_finish_forward()


func _should_ignore_character(target:ball) -> bool:
	if target == null or not is_instance_valid(target):
		return true
	if target == self:
		return true
	if Master != null and is_instance_valid(Master) and target == Master:
		return true
	if not Game.Game_Settings.Have_Team_Damage and Team != "" and target.Team == Team:
		return true
	return false


func _on_successful_hit(_hurt:hurtbox) -> void:
	if is_multiplayer_authority() and not _rewinding:
		call_deferred("_finish_forward")




func current_hit_damage_multiplier() -> float:
	return maxf(forward_damage_multiplier,0.0)


func take_damage(_damage:float,_ignore_block:bool = false) -> void:
	pass


func hit_white(_ignore_block:bool = false) -> void:
	pass


func _finish_forward() -> void:
	if _forward_finished or _rewinding:
		return
	_forward_finished = true
	_finish_msec = Time.get_ticks_msec()
	_retention_left = maxf(finished_retention_seconds,1.0)
	visible = false
	velocity = Vector2.ZERO
	_set_active_collision(false)
	_record_history_sample()


func _set_active_collision(enabled:bool) -> void:
	if collision_shape_2d != null:
		collision_shape_2d.set_deferred("disabled",not enabled)
	if self_hitbox != null:
		self_hitbox.set_deferred("monitoring",enabled)
		self_hitbox.set_deferred("monitorable",enabled)
	if self_hurtbox != null:
		self_hurtbox.set_deferred("monitoring",false)
		self_hurtbox.set_deferred("monitorable",false)


func _free_self() -> void:
	set_rewind_visual(false)
	if is_instance_valid(self) and not is_queued_for_deletion():
		Game.free_node(self)


func Die() -> void:
	_finish_forward()
