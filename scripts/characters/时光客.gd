extends ball

const CLOCK_PROJECTILE_SCENE := preload("res://scenes/shooter/时光客时钟.tscn")
const TIME_NODE_MATERIAL:ShaderMaterial = preload("res://shaders/after_image_material.tres")
const REWIND_VHS_SHADER:Shader = preload("res://shaders/time_rewind_vhs.gdshader")

@export_category("时钟弹")
@export_range(20.0,600.0,5.0) var projectile_speed:float = 175.0
@export_range(0.0,120.0,1.0) var projectile_spawn_offset:float = 30.0
@export_range(0.1,20.0,0.1) var projectile_lifetime:float = 6.0
@export_range(0.0,80.0,1.0) var projectile_orbit_radius:float = 16.0
@export_range(0.1,20.0,0.1) var projectile_orbit_speed:float = 6.2
@export_range(0.02,0.8,0.01) var attack_visual_lock_time:float = 0.14
@export var shoot_audio:String = "Blue"

@export_category("时间倒放")
@export_range(0.8,5.0,0.1) var rewind_history_seconds:float = 2.2
@export_range(2.0,15.0,0.1) var rewind_interval:float = 6.2
@export_range(0.35,2.0,0.05) var rewind_playback_duration:float = 0.90
@export_range(0.0,10.0,0.05) var rewind_contact_damage_multiplier:float = 1.0
@export_range(8.0,60.0,1.0) var rewind_contact_radius:float = 24.0
@export_range(0.0,120.0,1.0) var rewind_contact_knockback_distance:float = 28.0
@export_range(0.0,10.0,0.05) var projectile_damage_multiplier:float = 2.6153846
@export_range(0.0,10.0,0.05) var rewind_projectile_damage_multiplier:float = 1.7
@export var rewind_audio:String = "时光客倒放"

@export_category("时间节点显示")
@export_range(1,1,1) var time_node_count:int = 1
@export_range(0.05,0.85,0.01) var time_node_alpha:float = 0.30
@export var time_node_tint:Color = Color(0.72,0.84,1.0,1.0)
@export_range(0.0,10.0,0.25) var time_node_blur_pixels:float = 1.0
@export_range(0.0,20.0,0.5) var time_node_smear_pixels:float = 3.0

var _history:Array[Dictionary] = []
var _rewind_timer:float = 0.0
var _rewinding:bool = false
var _rewind_elapsed:float = 0.0
var _rewind_start_msec:int = 0
var _rewind_target_msec:int = 0
var _rewind_cursor:int = 0
var _rewind_hit_ids:Dictionary = {}
var _time_node_visuals:Array[Node2D] = []
var _rewind_visual_remote:bool = false
var _rewind_original_image_material:Material = null
var _rewind_local_material:ShaderMaterial = null


func _ready() -> void:
	Has_Collision_Damage = false
	Can_Attack = true
	super._ready()
	_rewind_timer = maxf(rewind_interval,rewind_history_seconds + 0.5)
	_record_history_sample()
	_ensure_time_node_visuals()
	_update_time_nodes()


func has_collision_damage() -> bool:
	return false


func get_next_state(state:State) -> int:
	# 死亡必须高于倒放。旧逻辑先检查 _rewinding，导致倒放期间被打到 0HP 后
	# 永远返回 keep_state，既进不了 Die，公共 0HP 兜底再次询问时也仍被倒放拦住。
	if health <= 0:
		return super(state)
	if _rewinding:
		return -1
	return super(state)


func Attack() -> void:
	super()
	if state_machine.current_state == State.Die or not is_multiplayer_authority():
		return
	if is_damage_output_disabled() or _rewinding:
		Attacking = false
		return

	var target:Node = return_reusable_combat_target()
	var shoot_dir:Vector2 = direction.normalized() if direction.length_squared() > 0.000001 else Vector2.RIGHT
	if target is Node2D and is_instance_valid(target):
		var to_target:Vector2 = combat_target_position(target) - global_position
		if to_target.length_squared() > 0.000001:
			shoot_dir = to_target.normalized()

	var projectile:ball = CLOCK_PROJECTILE_SCENE.instantiate()
	projectile.Master = self
	projectile.Master_name = name
	projectile.Team = Team
	projectile.Target_Enemy = null if has_player_control_aim() else (target as ball if target is ball else null)
	projectile.Damage = Damage
	projectile.set("forward_damage_multiplier",projectile_damage_multiplier)
	projectile.Speed = projectile_speed
	projectile.direction = shoot_dir
	projectile.global_position = global_position + shoot_dir * projectile_spawn_offset
	projectile.set("lifetime",projectile_lifetime)
	projectile.set("orbit_radius",projectile_orbit_radius)
	projectile.set("orbit_angular_speed",projectile_orbit_speed)
	projectile.set("initial_orbit_phase",randf_range(0.0,TAU))
	projectile.name = Game.return_random_name(projectile)
	get_tree().current_scene.add_child(projectile,true)

	if shoot_audio != "":
		Audios.play_sfx.rpc(shoot_audio,{volume = -5.0},true,true)

	Attacking = true
	await get_tree().create_timer(maxf(attack_visual_lock_time,0.02)).timeout
	if is_instance_valid(self) and not _rewinding:
		Attacking = false


func tick_physics(state:State,delta:float) -> void:
	if not is_multiplayer_authority():
		super.tick_physics(state,delta)
		if state != State.Die and health > 0:
			# 远端也记录同步到本机的视觉轨迹，用于显示同样的“时间节点”残影。
			if not _rewind_visual_remote:
				_record_history_sample()
			_update_time_nodes()
		return

	if state == State.Die or health <= 0:
		super.tick_physics(state,delta)
		return

	if _rewinding:
		_process_rewind(delta)
		_update_time_nodes()
		_process_auto_after_image(delta)
		Repel = Vector2.ZERO
		return

	super.tick_physics(state,delta)
	_record_history_sample()
	_update_time_nodes()
	_rewind_timer -= delta
	if _rewind_timer <= 0.0 and _history_span_seconds() >= rewind_history_seconds * 0.92:
		_begin_rewind()


func _record_history_sample() -> void:
	var now_msec:int = Time.get_ticks_msec()
	var visual_transform:Transform2D = global_transform
	var visual_flip_h:bool = false
	if image is Node2D:
		visual_transform = (image as Node2D).global_transform
	if image is Sprite2D:
		visual_flip_h = (image as Sprite2D).flip_h
	elif image is AnimatedSprite2D:
		visual_flip_h = (image as AnimatedSprite2D).flip_h

	_history.append({
		"t":now_msec,
		"p":global_position,
		"d":direction,
		"h":health,
		"b":block,
		"e":energy,
		"a":Attacking,
		"vt":visual_transform,
		"fh":visual_flip_h,
	})
	var keep_msec:int = int(round(maxf(rewind_history_seconds,0.8) * 1000.0)) + 180
	while _history.size() > 2 and now_msec - int(_history[0].get("t",now_msec)) > keep_msec:
		_history.pop_front()


func _ensure_time_node_visuals() -> void:
	var world:Node = get_tree().current_scene
	if world == null or image == null or not is_instance_valid(image):
		return

	# 时间节点只允许存在一个：它表示当前可倒流到的最早时间点。
	while _time_node_visuals.size() > 1:
		var extra:Node2D = _time_node_visuals.pop_back()
		if extra != null and is_instance_valid(extra):
			extra.queue_free()

	if _time_node_visuals.is_empty():
		var ghost:Node2D = image.duplicate() as Node2D
		if ghost == null:
			return
		ghost.name = "TimeNodeAfterImage"
		ghost.visible = false
		ghost.z_as_relative = false
		ghost.z_index = image.z_index - 2

		if ghost is CanvasItem:
			var item:CanvasItem = ghost as CanvasItem
			item.material = TIME_NODE_MATERIAL
			item.modulate = image.modulate
			item.self_modulate = image.self_modulate
			item.set_instance_shader_parameter("progress",0.18)
			item.set_instance_shader_parameter("trail_direction",Vector2.RIGHT)
			item.set_instance_shader_parameter("source_flip_h",0.0)
			item.set_instance_shader_parameter("start_color",time_node_tint)
			item.set_instance_shader_parameter("end_color",time_node_tint)
			item.set_instance_shader_parameter(
				"visual_params_a",
				Vector4(time_node_alpha,time_node_alpha,time_node_blur_pixels,time_node_blur_pixels)
			)
			item.set_instance_shader_parameter(
				"visual_params_b",
				Vector4(time_node_smear_pixels,time_node_smear_pixels,0.8,0.8)
			)
			item.set_instance_shader_parameter("style_mode",1)
			item.set_instance_shader_parameter("sample_count",5)
			item.set_instance_shader_parameter("fade_mode",0)

		world.add_child(ghost)
		ghost.add_to_group("BattleTransient")
		ghost.add_to_group("TimeTravelerTimeNode")
		_time_node_visuals.append(ghost)


func _update_time_nodes() -> void:
	_ensure_time_node_visuals()
	if _time_node_visuals.is_empty():
		return

	var ghost:Node2D = _time_node_visuals[0]
	if ghost == null or not is_instance_valid(ghost) or _history.size() < 2:
		_set_time_nodes_visible(false)
		return

	# 唯一节点固定显示在历史缓冲区最早的样本，也就是下一次倒流的目标点。
	var sample:Dictionary = _history[0]
	var sampled_transform:Transform2D = global_transform
	if sample.has("vt"):
		sampled_transform = sample.get("vt",global_transform)
	else:
		sampled_transform.origin = sample.get("p",global_position)
	ghost.global_transform = sampled_transform
	ghost.visible = true

	var sampled_flip:bool = bool(sample.get("fh",false))
	if ghost is Sprite2D:
		(ghost as Sprite2D).flip_h = sampled_flip
	elif ghost is AnimatedSprite2D:
		(ghost as AnimatedSprite2D).flip_h = sampled_flip
		(ghost as AnimatedSprite2D).pause()


func _set_time_nodes_visible(visible_value:bool) -> void:
	for ghost:Node2D in _time_node_visuals:
		if ghost != null and is_instance_valid(ghost):
			ghost.visible = visible_value


func _clear_time_node_visuals() -> void:
	for ghost:Node2D in _time_node_visuals:
		if ghost != null and is_instance_valid(ghost):
			ghost.queue_free()
	_time_node_visuals.clear()


func _history_span_seconds() -> float:
	if _history.size() < 2:
		return 0.0
	return float(int(_history[-1].get("t",0)) - int(_history[0].get("t",0))) / 1000.0


func _set_own_rewind_material(enabled:bool) -> void:
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


func _set_owned_projectile_rewind_material(enabled:bool) -> void:
	for node:Node in get_tree().get_nodes_in_group("TimeTravelerClock"):
		if node == null or not is_instance_valid(node):
			continue
		var belongs:bool = false
		if node is ball:
			var as_ball:ball = node as ball
			belongs = as_ball.Master == self or as_ball.Master_name == name
		if belongs and node.has_method("set_rewind_visual"):
			node.call("set_rewind_visual",enabled)


func _set_rewind_vhs_local(enabled:bool) -> void:
	_rewind_visual_remote = enabled
	_set_own_rewind_material(enabled)
	_set_owned_projectile_rewind_material(enabled)


func _set_rewind_vhs_everywhere(enabled:bool) -> void:
	_set_rewind_vhs_local(enabled)
	if multiplayer.has_multiplayer_peer():
		_remote_set_rewind_vhs.rpc(enabled)


@rpc("authority","call_remote","reliable")
func _remote_set_rewind_vhs(enabled:bool) -> void:
	_set_rewind_vhs_local(enabled)


func _begin_rewind() -> void:
	if _rewinding or _history.size() < 2:
		return
	_rewinding = true
	_rewind_elapsed = 0.0
	_rewind_start_msec = Time.get_ticks_msec()
	_rewind_target_msec = maxi(
		_rewind_start_msec - int(round(maxf(rewind_history_seconds,0.8) * 1000.0)),
		int(_history[0].get("t",_rewind_start_msec))
	)
	_rewind_cursor = _history.size() - 1
	_rewind_hit_ids.clear()
	velocity = Vector2.ZERO
	Repel = Vector2.ZERO
	Attacking = false
	Using_Skill = false
	if health_bar != null:
		health_bar.suppress_floating_text = true
	_set_rewind_vhs_everywhere(true)

	for node:Node in get_tree().get_nodes_in_group("TimeTravelerClock"):
		if node == null or not is_instance_valid(node):
			continue
		var belongs:bool = false
		if node is ball:
			var as_ball:ball = node as ball
			belongs = as_ball.Master == self or as_ball.Master_name == name
		if belongs and node.has_method("begin_time_rewind"):
			node.call(
				"begin_time_rewind",
				_rewind_start_msec,
				_rewind_target_msec,
				maxf(rewind_playback_duration,0.35),
				clampf(rewind_projectile_damage_multiplier,0.0,1.5)
			)

	if rewind_audio != "":
		# 用户提供的倒放音频前约 0.45 秒接近静音，从有效声音处开始播放；不随机变调。
		Audios.play_sfx.rpc(rewind_audio,{position = 0.45},false,true)


func _process_rewind(delta:float) -> void:
	if _history.size() < 2:
		_finish_rewind()
		return

	_rewind_elapsed += delta
	var duration:float = maxf(rewind_playback_duration,0.35)
	var progress:float = clampf(_rewind_elapsed / duration,0.0,1.0)
	var wanted_msec:int = int(round(lerpf(float(_rewind_start_msec),float(_rewind_target_msec),progress)))
	var sample:Dictionary = _sample_history_at(wanted_msec)
	var old_position:Vector2 = global_position
	var new_position:Vector2 = sample.get("p",global_position)
	global_position = new_position
	_deal_rewind_contact_damage(old_position,new_position)

	direction = sample.get("d",direction)
	velocity = Vector2.ZERO
	Repel = Vector2.ZERO
	Attacking = bool(sample.get("a",false))
	Using_Skill = false

	health = clampi(int(sample.get("h",health)),0,Max_health)
	block = clampi(int(sample.get("b",block)),0,max_block)
	energy = clampi(int(sample.get("e",energy)),0,max_energy)

	if progress >= 1.0:
		_finish_rewind()


func _sample_history_at(wanted_msec:int) -> Dictionary:
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
	var left_dir:Vector2 = left.get("d",direction)
	var right_dir:Vector2 = right.get("d",left_dir)
	var blended_dir:Vector2 = left_dir.lerp(right_dir,weight)
	if blended_dir.length_squared() > 0.000001:
		blended_dir = blended_dir.normalized()
	var left_position:Vector2 = left.get("p",global_position)
	var right_position:Vector2 = right.get("p",global_position)
	return {
		"p":left_position.lerp(right_position,weight),
		"d":blended_dir,
		"h":roundi(lerpf(float(left.get("h",health)),float(right.get("h",health)),weight)),
		"b":roundi(lerpf(float(left.get("b",block)),float(right.get("b",block)),weight)),
		"e":roundi(lerpf(float(left.get("e",energy)),float(right.get("e",energy)),weight)),
		"a":bool(left.get("a",false)) if weight < 0.5 else bool(right.get("a",false)),
	}


func _deal_rewind_contact_damage(from_position:Vector2,to_position:Vector2) -> void:
	if rewind_contact_damage_multiplier <= 0.0 or is_damage_output_disabled():
		return
	var segment:Vector2 = to_position - from_position
	var segment_len_sq:float = segment.length_squared()
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if not _can_rewind_damage(target):
			continue
		var target_id:int = target.get_instance_id()
		if _rewind_hit_ids.has(target_id):
			continue
		var nearest:Vector2 = from_position
		if segment_len_sq > 0.000001:
			var t:float = clampf((target.global_position - from_position).dot(segment) / segment_len_sq,0.0,1.0)
			nearest = from_position + segment * t
		if target.global_position.distance_to(nearest) > maxf(rewind_contact_radius,1.0):
			continue
		_rewind_hit_ids[target_id] = true
		var outgoing:float = attack_damage(rewind_contact_damage_multiplier)
		if outgoing <= 0.0:
			continue
		target.receive_spatial_damage(
			outgoing,
			{"shape":"capsule","from":from_position,"to":to_position,"half_width":maxf(rewind_contact_radius,1.0),"source":self},
			false
		)
		if rewind_contact_knockback_distance > 0.0:
			var push:Vector2 = target.global_position - nearest
			if push.length_squared() <= 0.000001:
				push = -direction if direction.length_squared() > 0.000001 else Vector2.RIGHT
			target.apply_knockback(
				push.normalized(),rewind_contact_knockback_distance,460.0,
				0.22,0.0,
				{"source":self,"max_wall_bounces":1,"stop_on_character":true}
			)


func _can_rewind_damage(target:ball) -> bool:
	if target == null or not is_instance_valid(target) or target == self or target.health <= 0:
		return false
	if not target.is_combat_targetable():
		return false
	if Team != "" and target.Team != "" and Team == target.Team:
		return false
	return true


func _finish_rewind() -> void:
	if not _rewinding:
		return
	_rewinding = false
	_rewind_elapsed = 0.0
	Attacking = false
	Using_Skill = false
	velocity = Vector2.ZERO
	Repel = Vector2.ZERO
	if health_bar != null:
		health_bar.suppress_floating_text = false
	_set_rewind_vhs_everywhere(false)
	_history.clear()
	_record_history_sample()
	_rewind_timer = maxf(rewind_interval,rewind_history_seconds + 0.5)


func _exit_tree() -> void:
	_set_rewind_vhs_local(false)
	_clear_time_node_visuals()


func Die() -> void:
	_rewinding = false
	if health_bar != null:
		health_bar.suppress_floating_text = false
	_set_rewind_vhs_everywhere(false)
	_set_time_nodes_visible(false)
	super()
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(self):
		Game.free_node(self)
