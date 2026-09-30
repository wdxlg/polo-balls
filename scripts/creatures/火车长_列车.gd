extends Node2D

# 火车长的列车攻击系统。
# 列车不是 ball，不参与普通索敌；每节真实 Area2D/CollisionShape2D 就是实际撞击伤害区域。
# 停靠车头上方另有真实 RefuelArea；火车长必须实际碰到该区域才加煤，不允许自动导航到站台。
# 运动模糊复用 V114 当前帧方向性 motion-blur Shader，不保存历史残影。

const HEAD_TEXTURE:Texture2D = preload("res://Images/characters/人物/火车长/05_蒸汽火车_车头.png")
const CARRIAGE_TEXTURE:Texture2D = preload("res://Images/characters/人物/火车长/06_蒸汽火车_车厢.png")
const TAIL_TEXTURE:Texture2D = preload("res://Images/characters/人物/火车长/07_蒸汽火车_车尾.png")
const MOTION_BLUR_SHADER:Shader = preload("res://shaders/ball_motion_blur.gdshader")
const TRAIN_START_AUDIO:AudioStream = preload("res://audio/characters/火车长/喷气.mp3")
const TRAIN_RUN_AUDIO:AudioStream = preload("res://audio/characters/火车长/火车运行.mp3")
# V130：烟囱直接复用炮兵炮击现有烟雾图片，不复制素材、不创建新图片路径。
const CHIMNEY_SMOKE_TEXTURE:Texture2D = preload("res://Images/characters/人物/炮兵/烟雾.png")

const STATE_STAGED:int = 0
const STATE_RUNNING:int = 1
const STATE_ARRIVING:int = 2
const STATE_DEPARTING:int = 3
const TRAIN_DRAW_Z_INDEX:int = 120

@export_group("列车攻击")
@export_range(120.0,1200.0,10.0,"or_greater") var train_speed:float = 520.0
@export_range(1.0,60.0,0.1,"or_greater") var launch_interval:float = 30.0
@export_range(1,8,1) var initial_carriage_count:int = 1
@export_range(1,8,1) var minimum_carriage_count:int = 1
@export_range(1,12,1) var maximum_carriage_count:int = 8
@export_range(1,10,1) var maximum_coal:int = 5
@export_range(0.0,10.0,0.25,"or_greater") var coal_launch_time_reduction:float = 4.0
@export_range(0.05,3.0,0.05,"or_greater") var train_damage_multiplier:float = 1.0
@export_range(0.03,2.0,0.01) var same_target_hit_cooldown:float = 0.18
@export_range(0.0,200.0,1.0,"or_greater") var knockback_distance:float = 58.0
@export_range(50.0,1500.0,10.0,"or_greater") var knockback_speed:float = 520.0

@export_group("列车视觉")
@export_range(48.0,220.0,1.0,"or_greater") var train_visual_height:float = 96.0
@export_range(0.60,1.10,0.01) var part_spacing_ratio:float = 0.92
@export_range(0.40,1.0,0.01) var collision_width_ratio:float = 0.86
@export_range(0.35,1.0,0.01) var collision_height_ratio:float = 0.72
@export_range(0.0,700.0,1.0,"or_greater") var train_motion_blur_pixels:float = 430.0
@export_range(0.0,1.0,0.01) var train_motion_blur_alpha:float = 0.94
@export_range(0.0,4.0,0.05,"or_greater") var train_motion_blur_forward_stretch:float = 1.25
@export_range(0.1,4.0,0.05,"or_greater") var train_motion_blur_sample_spread:float = 1.45
@export_range(0.0,1.0,0.01) var train_motion_blur_core_sharpness:float = 0.02
# V121：低速必须真正退掉模糊；start 以下目标强度为 0，start~full 连续插值。
@export_range(0.0,600.0,1.0,"or_greater") var train_motion_blur_start_speed:float = 125.0
@export_range(1.0,1200.0,1.0,"or_greater") var train_motion_blur_full_speed:float = 500.0
@export_range(0.15,3.0,0.05,"or_greater") var train_motion_blur_strength_curve:float = 0.90
@export_range(0.5,40.0,0.5,"or_greater") var train_motion_blur_response:float = 9.0
@export_range(8.0,240.0,1.0,"or_greater") var outside_margin:float = 48.0

@export_group("烟囱烟雾")
@export_range(-1.0,1.0,0.01) var chimney_offset_x_ratio:float = -0.18
@export_range(-1.0,1.0,0.01) var chimney_offset_y_ratio:float = -0.34
@export_range(0.03,1.0,0.01,"or_greater") var chimney_smoke_interval:float = 0.16
@export_range(8.0,160.0,1.0,"or_greater") var chimney_smoke_world_size_min:float = 28.0
@export_range(8.0,200.0,1.0,"or_greater") var chimney_smoke_world_size_max:float = 48.0
@export_range(0.10,3.0,0.05,"or_greater") var chimney_smoke_lifetime_min:float = 0.95
@export_range(0.10,4.0,0.05,"or_greater") var chimney_smoke_lifetime_max:float = 1.55
@export_range(0.0,1.0,0.01) var chimney_smoke_alpha_min:float = 0.18
@export_range(0.0,1.0,0.01) var chimney_smoke_alpha_max:float = 0.34
@export_range(0.0,300.0,1.0,"or_greater") var chimney_smoke_min_emit_speed:float = 28.0
@export_range(1.0,900.0,1.0,"or_greater") var chimney_smoke_full_emit_speed:float = 260.0
@export_range(0.0,180.0,1.0,"or_greater") var chimney_smoke_rise_min:float = 34.0
@export_range(0.0,240.0,1.0,"or_greater") var chimney_smoke_rise_max:float = 72.0
@export_range(0.0,180.0,1.0,"or_greater") var chimney_smoke_trail_min:float = 20.0
@export_range(0.0,260.0,1.0,"or_greater") var chimney_smoke_trail_max:float = 64.0

@export_group("列车音效")
@export_range(-30.0,18.0,0.5,"or_greater") var train_start_volume_db:float = 0.0
@export_range(-30.0,18.0,0.5,"or_greater") var train_run_volume_db:float = 8.0
# V125：运行声随真实列车速度连续淡入/淡出。高速保持 train_run_volume_db，
# 进入减速区后开始逐渐变小；接近停车时先淡到静音，再真正 stop()，禁止停站瞬间硬切。
@export_range(0.0,300.0,1.0,"or_greater") var train_run_audio_silent_speed:float = 24.0
@export_range(20.0,800.0,5.0,"or_greater") var train_run_audio_full_speed:float = 260.0
@export_range(0.15,3.0,0.05,"or_greater") var train_run_audio_fade_curve:float = 0.85
@export_range(0.5,40.0,0.5,"or_greater") var train_run_audio_fade_response:float = 8.0
@export_range(-80.0,-20.0,1.0) var train_run_audio_silence_db:float = -60.0
@export_range(200.0,5000.0,50.0,"or_greater") var train_audio_max_distance:float = 2600.0
@export_range(-18.0,18.0,0.5,"or_greater") var train_hit_audio_volume_db:float = 5.0

@export_group("停靠")
@export_range(0.0,10.0,0.1,"or_greater") var minimum_station_dwell:float = 2.5
# V119：这里表示“车头中心比地图底边低多少像素”，不再是“整节车体与地图之间的空隙”。
# 因此默认 8px 会让列车紧贴地图下沿，只露在下方一部分，不会离地图很远。
@export_range(0.0,80.0,1.0,"or_greater") var station_gap_below_map:float = 8.0
@export_range(0.0,24.0,1.0,"or_greater") var station_screen_margin:float = 3.0
@export_range(16.0,100.0,1.0,"or_greater") var refuel_area_width:float = 42.0
@export_range(12.0,70.0,1.0,"or_greater") var refuel_area_height:float = 26.0
@export_range(-80.0,80.0,1.0) var refuel_area_offset_x:float = 8.0
@export_range(-80.0,40.0,1.0) var refuel_area_offset_y:float = -30.0
@export_range(60.0,900.0,10.0,"or_greater") var station_approach_speed:float = 360.0
@export_range(10.0,180.0,1.0,"or_greater") var station_min_approach_speed:float = 34.0
@export_range(80.0,1200.0,10.0,"or_greater") var station_brake_distance:float = 420.0
@export_range(0.0,240.0,1.0,"or_greater") var station_entry_margin:float = 40.0
@export_range(60.0,1000.0,10.0,"or_greater") var station_departure_max_speed:float = 430.0
@export_range(60.0,2400.0,10.0,"or_greater") var station_departure_acceleration:float = 760.0

@export_group("加煤弹性反馈")
@export_range(0.0,24.0,0.5,"or_greater") var refuel_bounce_height:float = 7.0
@export_range(0.0,0.30,0.01,"or_greater") var refuel_bounce_squash:float = 0.08
@export_range(0.02,0.30,0.01,"or_greater") var refuel_bounce_out_time:float = 0.07
@export_range(0.04,0.50,0.01,"or_greater") var refuel_bounce_return_time:float = 0.17
@export_range(0.0,0.05,0.001,"or_greater") var refuel_bounce_part_delay:float = 0.008

var owner_conductor:ball = null
var map_rect:Rect2 = Rect2()
var coal_count:int = 0

var _state:int = STATE_STAGED
var _launch_elapsed:float = 0.0
var _launch_serial:int = 0
var _parts:Array[Area2D] = []
var _blur_layers:Array[Sprite2D] = []
var _last_hit_msec:Dictionary = {}
var _part_width:float = 64.0
var _part_height:float = 48.0
var _part_spacing:float = 58.0
var _total_length:float = 0.0
var _started:bool = false
var _station_position:Vector2 = Vector2.ZERO
var _arrival_speed:float = 0.0
var _departure_speed:float = 0.0
var _pending_attack_carriages:int = 0
var _refuel_area:Area2D = null
var _motion_blur_strength:float = 0.0
var _motion_blur_target:float = 0.0
var _start_audio:AudioStreamPlayer2D = null
var _run_audio:AudioStreamPlayer2D = null
var _run_audio_speed:float = 0.0
var _run_audio_volume_linear:float = 0.0
var _chimney_smoke_elapsed:float = 0.0


func setup(conductor:ball,world_map_rect:Rect2) -> void:
	owner_conductor = conductor
	map_rect = world_map_rect
	z_as_relative = false
	z_index = TRAIN_DRAW_Z_INDEX
	# 开局列车应从右侧直接进入第一次攻击，不要先在地图下方闪现一帧。
	_state = STATE_STAGED
	_rebuild_consist(clampi(initial_carriage_count,minimum_carriage_count,maximum_carriage_count))
	_station_position = _calculate_visible_station_position()
	visible = false
	_set_parts_active(false)
	_set_motion_blur_running(false)
	_set_refuel_area_active(false)
	_ensure_audio_players()


func start_initial_run() -> void:
	if _started:
		return
	_started = true
	_launch_with_carriages(clampi(initial_carriage_count,minimum_carriage_count,maximum_carriage_count))


func add_coal(amount:int = 1) -> void:
	if amount <= 0:
		return
	coal_count = clampi(coal_count + amount,0,maximum_coal)
	if _state == STATE_STAGED:
		# V123：0 煤时下一趟只有 1 节；每加 1 煤增加 1 节，同时把 30 秒基础等待缩短 4 秒。
		# 加满煤也不再“立即发车”，而是按缩短后的目标等待时间发车。
		var preview_carriages:int = clampi(minimum_carriage_count + coal_count,minimum_carriage_count,maximum_carriage_count)
		_rebuild_consist(preview_carriages)
		# V124：煤块视觉真正飞进车头后才会调用 add_coal，所以这里正是“入炉命中”时刻；
		# 只弹视觉 Sprite，不移动列车根/碰撞框/RefuelArea。
		_play_refuel_bounce()


func get_coal_count() -> int:
	return coal_count


func is_waiting_for_coal() -> bool:
	return _started and _state == STATE_STAGED


func can_request_manual_launch() -> bool:
	return is_waiting_for_coal() and _launch_elapsed >= _current_launch_delay()


func launch_waiting_train() -> void:
	# 服务器已核准等待时间，远端使用同一个同步发车时刻，不再各自比较本地帧计时。
	if is_waiting_for_coal():
		_launch_from_current_coal()


func _conductor_is_manually_controlled() -> bool:
	if owner_conductor == null or not is_instance_valid(owner_conductor):
		return false
	if owner_conductor.is_player_controlled():
		return true
	# 客户端不会直接给球设置 player_control_peer_id，而是接收服务器的控制分配。
	if not multiplayer.has_multiplayer_peer():
		return false
	var assignments:Dictionary = Game._current_control_assignments_for_display()
	return assignments.values().has(str(owner_conductor.get_path()))


func get_refuel_target_position() -> Vector2:
	if map_rect.size.x <= 0.0 or map_rect.size.y <= 0.0:
		return global_position
	# 火车停在地图下方；火车长本人只走到地图底边内侧，避免触发项目出界淘汰。
	return Vector2(
		map_rect.position.x + maxf(_part_width * 0.58,22.0),
		map_rect.end.y - maxf(_part_height * 0.30,14.0)
	)


func get_refuel_visual_target_position() -> Vector2:
	# 煤块视觉要真正飞到车头的小型 RefuelArea，而不是飞向整列车中心。
	if _refuel_area != null and is_instance_valid(_refuel_area):
		return _refuel_area.global_position
	return global_position + Vector2(refuel_area_offset_x,refuel_area_offset_y)


func _physics_process(delta:float) -> void:
	if owner_conductor == null or not is_instance_valid(owner_conductor) or owner_conductor.health <= 0:
		_stop_run_audio_immediate()
		queue_free()
		return

	# 列车永远绘制在地图外遮罩和黑色地图边框之上，任何状态都不再被地图裁掉。
	z_as_relative = false
	z_index = TRAIN_DRAW_Z_INDEX
	_update_chimney_smoke(delta)

	if not owner_conductor.is_combat_runtime_active():
		_set_motion_blur_speed(0.0)
		_set_run_audio_speed(0.0)
		_update_motion_blur(delta)
		_update_run_audio_fade(delta)
		return

	if _state == STATE_RUNNING:
		var speed_value:float = maxf(train_speed,0.0)
		global_position.x -= speed_value * delta
		_set_motion_blur_speed(speed_value)
		_set_run_audio_speed(speed_value)
		_ensure_run_audio_playing()
		if owner_conductor.is_multiplayer_authority():
			_scan_running_hits()
		# 车尾也完全越过地图左侧后，整列车才算真正出图。
		if global_position.x + _total_length < map_rect.position.x - outside_margin:
			_begin_station_approach()

	elif _state == STATE_ARRIVING:
		# 从地图下方右侧开进来，并按剩余距离连续减速到站位。
		global_position.y = _station_position.y
		var remaining:float = maxf(global_position.x - _station_position.x,0.0)
		if remaining <= 0.5:
			_finish_station_approach()
		else:
			var brake_distance:float = maxf(station_brake_distance,_part_width * 2.0)
			var t:float = clampf(remaining / brake_distance,0.0,1.0)
			var smooth_t:float = t * t * (3.0 - 2.0 * t)
			var min_speed:float = maxf(station_min_approach_speed,1.0)
			var max_speed:float = maxf(station_approach_speed,min_speed)
			_arrival_speed = lerpf(min_speed,max_speed,smooth_t)
			global_position.x -= minf(_arrival_speed * delta,remaining)
			_set_motion_blur_speed(_arrival_speed)
			_set_run_audio_speed(_arrival_speed)
			_ensure_run_audio_playing()
			if global_position.x <= _station_position.x + 0.5:
				_finish_station_approach()

	elif _state == STATE_DEPARTING:
		# 再次发车时，停靠列车必须从站台实际向左开走。
		var max_depart_speed:float = maxf(station_departure_max_speed,1.0)
		_departure_speed = move_toward(
			_departure_speed,
			max_depart_speed,
			maxf(station_departure_acceleration,1.0) * delta
		)
		global_position.x -= _departure_speed * delta
		_set_motion_blur_speed(_departure_speed)
		_set_run_audio_speed(_departure_speed)
		_ensure_run_audio_playing()
		var visible_world:Rect2 = _get_visible_world_rect()
		var visible_left:float = map_rect.position.x
		if visible_world.size.x > 1.0:
			visible_left = minf(visible_left,visible_world.position.x)
		if global_position.x + _total_length < visible_left - outside_margin:
			_start_attack_run_from_right(maxi(_pending_attack_carriages,minimum_carriage_count),false)

	else:
		# 停靠状态：模糊目标和运行声目标都归零，但运行声由淡出器慢慢减小，
		# 不允许在刚切到 STATE_STAGED 的一帧内硬 stop。
		_set_motion_blur_speed(0.0)
		_set_run_audio_speed(0.0)
		if owner_conductor.is_multiplayer_authority():
			_scan_refuel_contacts()
		global_position = _station_position
		_launch_elapsed += delta
		var normal_launch_delay:float = _current_launch_delay()
		if _launch_elapsed >= normal_launch_delay and not _conductor_is_manually_controlled():
			_launch_from_current_coal()

	_update_motion_blur(delta)
	_update_run_audio_fade(delta)


func _current_chimney_motion_speed() -> float:
	match _state:
		STATE_RUNNING:
			return maxf(train_speed,0.0)
		STATE_ARRIVING:
			return maxf(_arrival_speed,0.0)
		STATE_DEPARTING:
			return maxf(_departure_speed,0.0)
	return 0.0


func _update_chimney_smoke(delta:float) -> void:
	if not visible or owner_conductor == null or not is_instance_valid(owner_conductor):
		_chimney_smoke_elapsed = 0.0
		return
	if not owner_conductor.is_combat_runtime_active():
		_chimney_smoke_elapsed = 0.0
		return
	# V131：烟只由真实列车运动驱动。停站 STATE_STAGED 不再新生烟；
	# 进站减速时生成频率连续降低，完全停车后已有烟继续按自己的 Tween 淡出，因此视觉是“逐渐停烟”而不是硬删除。
	var speed_value:float = _current_chimney_motion_speed()
	var min_speed:float = maxf(chimney_smoke_min_emit_speed,0.0)
	if speed_value <= min_speed:
		_chimney_smoke_elapsed = 0.0
		return
	var full_speed:float = maxf(chimney_smoke_full_emit_speed,min_speed + 1.0)
	var activity:float = clampf((speed_value - min_speed) / (full_speed - min_speed),0.0,1.0)
	_chimney_smoke_elapsed += maxf(delta,0.0)
	# 低速时最多稀释到约 1/4 烟量，高速恢复完整频率。
	var emission_strength:float = lerpf(0.25,1.0,activity)
	var interval:float = maxf(chimney_smoke_interval,0.03) / maxf(emission_strength,0.05)
	while _chimney_smoke_elapsed >= interval:
		_chimney_smoke_elapsed -= interval
		_spawn_chimney_smoke(activity)


func _chimney_world_position() -> Vector2:
	# 车头 TrainPart_0 的中心就是列车根局部原点。用车头世界宽高比例定位烟囱，
	# Inspector 可微调，不依赖贴图原始像素尺寸。
	return to_global(Vector2(
		_part_width * chimney_offset_x_ratio,
		_part_height * chimney_offset_y_ratio
	))


func _spawn_chimney_smoke(activity:float = 1.0) -> void:
	if CHIMNEY_SMOKE_TEXTURE == null:
		return
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var smoke := Sprite2D.new()
	smoke.name = "TrainChimneySmoke"
	smoke.texture = CHIMNEY_SMOKE_TEXTURE
	smoke.centered = true
	smoke.z_as_relative = false
	smoke.z_index = TRAIN_DRAW_Z_INDEX + 2
	var alpha_low:float = minf(chimney_smoke_alpha_min,chimney_smoke_alpha_max)
	var alpha_high:float = maxf(chimney_smoke_alpha_min,chimney_smoke_alpha_max)
	var smoke_alpha:float = randf_range(alpha_low,alpha_high) * lerpf(0.72,1.0,clampf(activity,0.0,1.0))
	smoke.modulate = Color(0.88,0.88,0.88,smoke_alpha)
	var texture_size:Vector2 = CHIMNEY_SMOKE_TEXTURE.get_size()
	var requested_size:float = randf_range(
		minf(chimney_smoke_world_size_min,chimney_smoke_world_size_max),
		maxf(chimney_smoke_world_size_min,chimney_smoke_world_size_max)
	)
	var reference:float = maxf(maxf(texture_size.x,texture_size.y),1.0)
	var base_scale:float = requested_size / reference
	smoke.scale = Vector2.ONE * base_scale
	world.add_child(smoke)
	smoke.global_position = _chimney_world_position() + Vector2(randf_range(-2.5,2.5),randf_range(-1.5,1.5))
	smoke.rotation = randf_range(-0.35,0.35)

	var life:float = randf_range(
		minf(chimney_smoke_lifetime_min,chimney_smoke_lifetime_max),
		maxf(chimney_smoke_lifetime_min,chimney_smoke_lifetime_max)
	)
	var rise:float = randf_range(
		minf(chimney_smoke_rise_min,chimney_smoke_rise_max),
		maxf(chimney_smoke_rise_min,chimney_smoke_rise_max)
	)
	# 列车向左行驶时烟会相对车体向右拖；进站减速时拖尾也随速度缩短。
	var trail:float = randf_range(
		minf(chimney_smoke_trail_min,chimney_smoke_trail_max),
		maxf(chimney_smoke_trail_min,chimney_smoke_trail_max)
	) * lerpf(0.35,1.0,clampf(activity,0.0,1.0))
	var travel:= Vector2(trail,-rise)
	var tween:Tween = smoke.create_tween()
	tween.set_parallel(true)
	tween.tween_property(smoke,"global_position",smoke.global_position + travel,life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(smoke,"scale",Vector2.ONE * base_scale * randf_range(1.70,2.30),life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(smoke,"rotation",smoke.rotation + randf_range(-0.45,0.45),life)
	tween.tween_property(smoke,"modulate:a",0.0,life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(smoke.queue_free)


func _current_launch_delay() -> float:
	var shortened:float = maxf(launch_interval,0.1) - float(coal_count) * maxf(coal_launch_time_reduction,0.0)
	return maxf(shortened,maxf(minimum_station_dwell,0.0))


func _launch_from_current_coal() -> void:
	# V123：0 煤 = 1 节车厢；每煤 +1 节。煤只改变车长与等待时间，不再在 5 煤时强制瞬发。
	var carriages:int = clampi(minimum_carriage_count + coal_count,minimum_carriage_count,maximum_carriage_count)
	coal_count = 0
	_begin_station_departure(carriages)


func _launch_with_carriages(carriages:int) -> void:
	# 开局第一次没有停靠列车可供离站，因此直接从右侧进入；之后的循环统一走 STATE_DEPARTING。
	_start_attack_run_from_right(carriages,true)


func _begin_station_departure(carriages:int) -> void:
	_pending_attack_carriages = clampi(carriages,minimum_carriage_count,maximum_carriage_count)
	_rebuild_consist(_pending_attack_carriages)
	_state = STATE_DEPARTING
	visible = true
	_set_refuel_area_active(false)
	_set_parts_active(false)
	_launch_elapsed = 0.0
	_last_hit_msec.clear()
	_departure_speed = 0.0
	_set_motion_blur_speed(0.0)
	_set_run_audio_speed(0.0)
	_play_train_start_audio()
	_ensure_run_audio_playing()


func _start_attack_run_from_right(carriages:int,play_start_audio:bool) -> void:
	_rebuild_consist(clampi(carriages,minimum_carriage_count,maximum_carriage_count))
	visible = true
	_state = STATE_RUNNING
	_set_refuel_area_active(false)
	_launch_elapsed = 0.0
	_launch_serial += 1
	_last_hit_msec.clear()
	_departure_speed = 0.0
	_pending_attack_carriages = 0

	# V122：每一次攻击列车从右侧真正“出现”时，Y 轴直接使用火车长当时的世界 Y。
	# 不再轮换固定 28%/50%/72% 三条车道。
	var spawn_y:float = map_rect.position.y + map_rect.size.y * 0.5
	if owner_conductor != null and is_instance_valid(owner_conductor):
		spawn_y = owner_conductor.global_position.y
	global_position = Vector2(map_rect.end.x + outside_margin + _part_width * 0.55,spawn_y)
	_set_parts_active(true)
	_set_motion_blur_speed(maxf(train_speed,0.0))
	_set_run_audio_speed(maxf(train_speed,0.0))
	if play_start_audio:
		_play_train_start_audio()
	_ensure_run_audio_playing()


func _begin_station_approach() -> void:
	_state = STATE_ARRIVING
	_set_refuel_area_active(false)
	_launch_elapsed = 0.0
	_last_hit_msec.clear()
	# 当前攻击列车已经完全离开左侧后，在不可见处切换成下一趟的基础编组。
	# 然后从地图下方右侧真正“开进站”，玩家看到的是连续减速，而不是最终站位瞬间出现。
	_rebuild_consist(clampi(minimum_carriage_count + coal_count,minimum_carriage_count,maximum_carriage_count))
	_station_position = _calculate_visible_station_position()
	var visible_world:Rect2 = _get_visible_world_rect()
	var visible_right:float = map_rect.end.x
	if visible_world.size.x > 1.0:
		visible_right = maxf(visible_right,visible_world.end.x)
	var start_x:float = visible_right + maxf(station_entry_margin,0.0) + _part_width
	global_position = Vector2(start_x,_station_position.y)
	_arrival_speed = maxf(station_approach_speed,1.0)
	z_as_relative = false
	z_index = TRAIN_DRAW_Z_INDEX
	visible = true
	_set_parts_active(false)
	_set_motion_blur_speed(_arrival_speed)
	_set_run_audio_speed(_arrival_speed)
	_ensure_run_audio_playing()


func _finish_station_approach() -> void:
	_state = STATE_STAGED
	_launch_elapsed = 0.0
	_arrival_speed = 0.0
	z_as_relative = false
	z_index = TRAIN_DRAW_Z_INDEX
	global_position = _station_position
	_set_parts_active(false)
	_set_motion_blur_speed(0.0)
	_set_run_audio_speed(0.0)
	# 不在这一帧直接 stop。运行声会继续由 _update_run_audio_fade() 平滑降到静音，
	# 达到静音阈值后才真正停止播放器。
	_set_refuel_area_active(true)


func _calculate_visible_station_position() -> Vector2:
	# 理想位置仍然是“地图正下方”：车头在左、后续车厢向右。
	var desired:Vector2 = Vector2(
		map_rect.position.x + _part_width * 0.52,
		# V119：列车中心只比地图底边低一个很小偏移，让车体紧贴地图下沿，而不是整个车高都放在地图外。
		map_rect.end.y + maxf(station_gap_below_map,0.0)
	)

	# V117 的问题：地图外视觉遮罩 + Camera2D/viewport 可见范围可能让这个理想位置完全看不见。
	# 因此只对 Y 做“可见性夹紧”：有足够的屏幕下沿空间就真正停在地图外；
	# 没有空间时就贴着地图底边内侧停，保证玩家一定看得到等待中的火车。
	var visible_world:Rect2 = _get_visible_world_rect()
	if visible_world.size.x <= 1.0 or visible_world.size.y <= 1.0:
		return Vector2(desired.x,map_rect.end.y - _part_height * 0.50 - maxf(station_screen_margin,0.0))

	var lowest_visible_center:float = visible_world.end.y - _part_height * 0.50 - maxf(station_screen_margin,0.0)
	var highest_reasonable_center:float = map_rect.end.y - _part_height * 0.50 - maxf(station_screen_margin,0.0)
	var station_y:float = minf(desired.y,lowest_visible_center)
	if station_y < highest_reasonable_center:
		station_y = highest_reasonable_center
	return Vector2(desired.x,station_y)


func _get_visible_world_rect() -> Rect2:
	var viewport:Viewport = get_viewport()
	if viewport == null:
		return Rect2()
	var viewport_rect:Rect2 = viewport.get_visible_rect()
	if viewport_rect.size.x <= 1.0 or viewport_rect.size.y <= 1.0:
		return Rect2()
	var inverse_canvas:Transform2D = viewport.get_canvas_transform().affine_inverse()
	var corners:PackedVector2Array = PackedVector2Array([
		inverse_canvas * viewport_rect.position,
		inverse_canvas * Vector2(viewport_rect.end.x,viewport_rect.position.y),
		inverse_canvas * viewport_rect.end,
		inverse_canvas * Vector2(viewport_rect.position.x,viewport_rect.end.y),
	])
	var min_p:Vector2 = corners[0]
	var max_p:Vector2 = corners[0]
	for point:Vector2 in corners:
		min_p.x = minf(min_p.x,point.x)
		min_p.y = minf(min_p.y,point.y)
		max_p.x = maxf(max_p.x,point.x)
		max_p.y = maxf(max_p.y,point.y)
	return Rect2(min_p,max_p - min_p)


func _rebuild_consist(carriage_count:int) -> void:
	for child:Node in get_children():
		if child.has_meta("train_audio_player"):
			continue
		remove_child(child)
		child.queue_free()
	_parts.clear()
	_blur_layers.clear()
	_refuel_area = null

	var textures:Array[Texture2D] = [HEAD_TEXTURE]
	for _i:int in range(carriage_count):
		textures.append(CARRIAGE_TEXTURE)
	textures.append(TAIL_TEXTURE)

	var reference_size:Vector2 = HEAD_TEXTURE.get_size()
	var visual_scale:float = train_visual_height / maxf(reference_size.y,1.0)
	_part_width = reference_size.x * visual_scale
	_part_height = reference_size.y * visual_scale
	_part_spacing = _part_width * clampf(part_spacing_ratio,0.35,1.2)
	_total_length = _part_spacing * float(maxi(textures.size() - 1,0)) + _part_width

	for index:int in range(textures.size()):
		var area := Area2D.new()
		area.name = "TrainPart_%d" % index
		area.position = Vector2(float(index) * _part_spacing,0.0)
		area.collision_layer = 0
		area.collision_mask = 2
		area.monitoring = false
		area.monitorable = false
		area.set_meta("threat_debug_damage",0.0)
		add_child(area)
		_parts.append(area)

		var sprite := Sprite2D.new()
		sprite.name = "Visual"
		sprite.texture = textures[index]
		sprite.scale = Vector2.ONE * visual_scale
		sprite.set_meta("train_base_scale",sprite.scale)
		sprite.z_index = 0
		area.add_child(sprite)

		var blur := Sprite2D.new()
		blur.name = "MotionBlurLayer"
		blur.texture = textures[index]
		blur.scale = Vector2.ONE * visual_scale
		blur.set_meta("train_base_scale",blur.scale)
		blur.z_index = 1
		var material := ShaderMaterial.new()
		material.shader = MOTION_BLUR_SHADER
		blur.material = material
		area.add_child(blur)
		_configure_blur_layer(blur)
		_blur_layers.append(blur)

		var shape_node := CollisionShape2D.new()
		shape_node.name = "CollisionShape2D"
		var shape := RectangleShape2D.new()
		shape.size = Vector2(
			_part_width * clampf(collision_width_ratio,0.1,1.2),
			_part_height * clampf(collision_height_ratio,0.1,1.2)
		)
		shape_node.shape = shape
		area.add_child(shape_node)

	_create_refuel_area()
	_set_parts_active(_state == STATE_RUNNING)
	_set_motion_blur_running(_state == STATE_RUNNING)
	_set_refuel_area_active(_started and _state == STATE_STAGED)


func _create_refuel_area() -> void:
	# V123：加煤判定必须贴着车头，不能人物离火车很远就触发。
	# 仍使用真实 Area2D + RectangleShape2D，只缩小交互框，不改列车撞击伤害框。
	var area := Area2D.new()
	area.name = "RefuelArea"
	area.position = Vector2(refuel_area_offset_x,refuel_area_offset_y)
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitoring = false
	area.monitorable = false
	area.set_meta("train_conductor_refuel_area",true)
	add_child(area)

	var shape_node := CollisionShape2D.new()
	shape_node.name = "CollisionShape2D"
	var shape := RectangleShape2D.new()
	shape.size = Vector2(
		maxf(refuel_area_width,8.0),
		maxf(refuel_area_height,8.0)
	)
	shape_node.shape = shape
	area.add_child(shape_node)
	_refuel_area = area


func _set_refuel_area_active(active:bool) -> void:
	if _refuel_area == null or not is_instance_valid(_refuel_area):
		return
	_refuel_area.monitoring = active


func _scan_refuel_contacts() -> void:
	if _refuel_area == null or not is_instance_valid(_refuel_area) or not _refuel_area.monitoring:
		return
	for body:Node2D in _refuel_area.get_overlapping_bodies():
		if body == null or not is_instance_valid(body):
			continue
		if body.has_method("notify_train_refuel_contact"):
			body.call("notify_train_refuel_contact",self)


func _play_refuel_bounce() -> void:
	# 停靠列车每收到 1 个煤后弹一下。只动画每节车体的 Visual/MotionBlurLayer，
	# 不移动 Area2D 根、碰撞框或 RefuelArea，避免加煤期间交互范围跟着抖动。
	var height:float = maxf(refuel_bounce_height,0.0)
	var squash:float = clampf(refuel_bounce_squash,0.0,0.45)
	var out_time:float = maxf(refuel_bounce_out_time,0.02)
	var return_time:float = maxf(refuel_bounce_return_time,0.04)
	var part_delay:float = maxf(refuel_bounce_part_delay,0.0)
	for index:int in range(_parts.size()):
		var part:Area2D = _parts[index]
		if part == null or not is_instance_valid(part):
			continue
		for node_name:String in ["Visual","MotionBlurLayer"]:
			var sprite:Sprite2D = part.get_node_or_null(node_name) as Sprite2D
			if sprite == null or not is_instance_valid(sprite):
				continue
			var base_scale_variant:Variant = sprite.get_meta("train_base_scale",sprite.scale)
			var base_scale:Vector2 = sprite.scale
			if base_scale_variant is Vector2:
				base_scale = base_scale_variant
			sprite.position = Vector2.ZERO
			sprite.scale = base_scale
			var squashed_scale:Vector2 = base_scale * Vector2(1.0 + squash,1.0 - squash * 0.55)
			var tween:Tween = sprite.create_tween()
			var delay:float = float(index) * part_delay
			if delay > 0.0:
				tween.tween_interval(delay)
			tween.tween_property(sprite,"position:y",-height,out_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.parallel().tween_property(sprite,"scale",squashed_scale,out_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(sprite,"position:y",0.0,return_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.parallel().tween_property(sprite,"scale",base_scale,return_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _configure_blur_layer(blur:Sprite2D) -> void:
	blur.set_instance_shader_parameter("blur_direction",Vector2.LEFT)
	blur.set_instance_shader_parameter("blur_uv_direction",Vector2.LEFT)
	blur.set_instance_shader_parameter("blur_pixels",maxf(train_motion_blur_pixels,0.0))
	blur.set_instance_shader_parameter("blur_alpha",clampf(train_motion_blur_alpha,0.0,1.0))
	blur.set_instance_shader_parameter("forward_stretch",maxf(train_motion_blur_forward_stretch,0.0))
	blur.set_instance_shader_parameter("sample_spread",maxf(train_motion_blur_sample_spread,0.01))
	blur.set_instance_shader_parameter("core_sharpness",clampf(train_motion_blur_core_sharpness,0.0,1.0))
	blur.set_instance_shader_parameter("frame_uv_min",Vector2.ZERO)
	blur.set_instance_shader_parameter("frame_uv_max",Vector2.ONE)
	blur.set_instance_shader_parameter("tint_mix",0.0)
	blur.set_instance_shader_parameter("blur_strength",_motion_blur_strength)
	blur.visible = _motion_blur_strength > 0.003


func _set_motion_blur_running(running:bool) -> void:
	_set_motion_blur_speed(maxf(train_speed,0.0) if running else 0.0)


func _set_motion_blur_speed(speed_value:float) -> void:
	var speed:float = maxf(speed_value,0.0)
	var start_speed:float = maxf(train_motion_blur_start_speed,0.0)
	var full_speed:float = maxf(train_motion_blur_full_speed,start_speed + 1.0)
	if speed <= start_speed:
		_motion_blur_target = 0.0
		return
	var normalized:float = clampf((speed - start_speed) / (full_speed - start_speed),0.0,1.0)
	_motion_blur_target = pow(normalized,maxf(train_motion_blur_strength_curve,0.01))


func _update_motion_blur(delta:float) -> void:
	# 指数平滑不会受 physics FPS 明显影响；减速时会连续淡出，而不是低速还挂着固定残余。
	var response:float = maxf(train_motion_blur_response,0.01)
	var blend:float = 1.0 - exp(-response * maxf(delta,0.0))
	_motion_blur_strength = lerpf(_motion_blur_strength,_motion_blur_target,blend)
	if _motion_blur_target <= 0.0 and _motion_blur_strength < 0.002:
		_motion_blur_strength = 0.0
	for blur:Sprite2D in _blur_layers:
		if blur == null or not is_instance_valid(blur):
			continue
		blur.visible = _motion_blur_strength > 0.003
		blur.set_instance_shader_parameter("blur_strength",_motion_blur_strength)


func _ensure_audio_players() -> void:
	if _start_audio == null or not is_instance_valid(_start_audio):
		_start_audio = AudioStreamPlayer2D.new()
		_start_audio.name = "TrainStartAudio"
		_start_audio.set_meta("train_audio_player",true)
		_start_audio.stream = TRAIN_START_AUDIO
		_start_audio.bus = &"GameplayRecord"
		_start_audio.volume_db = train_start_volume_db
		_start_audio.max_distance = maxf(train_audio_max_distance,200.0)
		_start_audio.attenuation = 0.45
		add_child(_start_audio)

	if _run_audio == null or not is_instance_valid(_run_audio):
		_run_audio = AudioStreamPlayer2D.new()
		_run_audio.name = "TrainRunAudio"
		_run_audio.set_meta("train_audio_player",true)
		var loop_stream:AudioStream = TRAIN_RUN_AUDIO.duplicate()
		if loop_stream is AudioStreamMP3:
			(loop_stream as AudioStreamMP3).loop = true
			(loop_stream as AudioStreamMP3).loop_offset = 0.0
		_run_audio.stream = loop_stream
		_run_audio.bus = &"GameplayRecord"
		_run_audio.volume_db = train_run_audio_silence_db
		_run_audio_volume_linear = 0.0
		_run_audio.max_distance = maxf(train_audio_max_distance,200.0)
		_run_audio.attenuation = 0.40
		add_child(_run_audio)


func _play_train_start_audio() -> void:
	_ensure_audio_players()
	if _start_audio == null or not is_instance_valid(_start_audio):
		return
	_start_audio.volume_db = train_start_volume_db
	_start_audio.stop()
	_start_audio.play()


func _ensure_run_audio_playing() -> void:
	_ensure_audio_players()
	if _run_audio == null or not is_instance_valid(_run_audio):
		return
	# 不再每帧把 volume_db 硬写回满音量；否则进站减速永远无法真正淡出。
	if not _run_audio.playing:
		_run_audio.volume_db = train_run_audio_silence_db
		_run_audio_volume_linear = 0.0
		_run_audio.play()


func _set_run_audio_speed(speed_value:float) -> void:
	_run_audio_speed = maxf(speed_value,0.0)


func _run_audio_target_ratio() -> float:
	var silent_speed:float = maxf(train_run_audio_silent_speed,0.0)
	var full_speed:float = maxf(train_run_audio_full_speed,silent_speed + 1.0)
	if _run_audio_speed <= silent_speed:
		return 0.0
	var ratio:float = clampf((_run_audio_speed - silent_speed) / (full_speed - silent_speed),0.0,1.0)
	# smootherstep 让进入/退出淡化区时速度变化连续，不会在某个阈值突然跳一下。
	ratio = ratio * ratio * ratio * (ratio * (ratio * 6.0 - 15.0) + 10.0)
	return pow(ratio,maxf(train_run_audio_fade_curve,0.05))


func _update_run_audio_fade(delta:float) -> void:
	if _run_audio == null or not is_instance_valid(_run_audio):
		return
	var max_linear:float = db_to_linear(train_run_volume_db)
	var target_linear:float = max_linear * _run_audio_target_ratio()
	var response:float = maxf(train_run_audio_fade_response,0.01)
	var blend:float = 1.0 - exp(-response * maxf(delta,0.0))
	_run_audio_volume_linear = lerpf(_run_audio_volume_linear,target_linear,blend)

	# AudioStreamPlayer2D.volume_linear 会正确映射到 dB，避免直接对 dB 做线性插值产生听感不自然。
	if _run_audio_volume_linear > 0.00001:
		_run_audio.volume_linear = _run_audio_volume_linear
	else:
		_run_audio.volume_db = train_run_audio_silence_db
		_run_audio_volume_linear = 0.0

	if target_linear > 0.00001:
		_ensure_run_audio_playing()
	elif _run_audio.playing:
		var silence_linear:float = db_to_linear(train_run_audio_silence_db)
		if _run_audio_volume_linear <= maxf(silence_linear,0.00002):
			_run_audio.volume_db = train_run_audio_silence_db
			_run_audio_volume_linear = 0.0
			_run_audio.stop()


func _stop_run_audio_immediate() -> void:
	_run_audio_speed = 0.0
	_run_audio_volume_linear = 0.0
	if _run_audio != null and is_instance_valid(_run_audio):
		_run_audio.volume_db = train_run_audio_silence_db
		if _run_audio.playing:
			_run_audio.stop()


func _set_parts_active(active:bool) -> void:
	var damage_value:float = _current_train_damage() if active else 0.0
	for area:Area2D in _parts:
		if area == null or not is_instance_valid(area):
			continue
		area.monitoring = active
		area.set_meta("threat_debug_damage",damage_value)


func _scan_running_hits() -> void:
	for area:Area2D in _parts:
		if area == null or not is_instance_valid(area) or not area.monitoring:
			continue
		for body:Node2D in area.get_overlapping_bodies():
			_try_hit_body(body,area.global_position)


func _try_hit_body(body:Node,impact_position:Vector2) -> void:
	if not body is ball:
		return
	var target:ball = body as ball
	if not _is_valid_target(target):
		return

	var target_id:int = target.get_instance_id()
	var now_msec:int = Time.get_ticks_msec()
	var cooldown_msec:int = int(round(maxf(same_target_hit_cooldown,0.0) * 1000.0))
	if _last_hit_msec.has(target_id) and now_msec - int(_last_hit_msec[target_id]) < cooldown_msec:
		return
	_last_hit_msec[target_id] = now_msec

	var damage_value:float = _current_train_damage()
	if damage_value <= 0.0:
		return
	var before_health:float = float(target.health)
	var before_block:float = float(target.block)
	var hit:bool = target.receive_spatial_damage(
		damage_value,
		{"point":impact_position,"source":owner_conductor}
	)
	var health_loss:float = maxf(before_health - float(target.health),0.0)
	var block_loss:float = maxf(before_block - float(target.block),0.0)

	if hit or health_loss > 0.0 or block_loss > 0.0:
		target.notify_hit_burst_feedback(
			impact_position + Vector2.RIGHT * 8.0,
			damage_value,
			health_loss,
			block_loss,
			_part_height * 0.72,
			now_msec ^ target_id ^ get_instance_id(),
			Vector2.LEFT
		)
		_play_hit_audio(damage_value)

	if knockback_distance > 0.0:
		target.apply_knockback(
			Vector2.LEFT,
			knockback_distance,
			knockback_speed,
			0.12,
			0.0,
			{
				"source":owner_conductor,
				"lock_control":true,
				"stop_on_character":false,
				"max_wall_bounces":1,
				"smooth_motion":true,
			}
		)


func _current_train_damage() -> float:
	if owner_conductor == null or not is_instance_valid(owner_conductor):
		return 0.0
	return owner_conductor.attack_damage(maxf(train_damage_multiplier,0.0))


func _is_valid_target(target:ball) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(owner_conductor,target): return false # 皓宸复制品及其产物不把己方选为目标
	if target == null or not is_instance_valid(target) or target == owner_conductor:
		return false
	if not target.is_combat_targetable():
		return false
	if (
		not Game.Game_Settings.Have_Team_Damage
		and not owner_conductor.Ignore_Team_Damage_Setting
		and owner_conductor.Team != ""
		and target.Team == owner_conductor.Team
	):
		return false
	return true


func _play_hit_audio(_damage_value:float) -> void:
	# V122：列车只要真正结算出伤害/格挡损失，就明确复用项目标准碰撞伤害音 balls_hit1。
	# 独立 voice 允许高频连续撞击时每一下都能听见，不会被前一声截断。
	var params:Dictionary = {"volume":train_hit_audio_volume_db}
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc("balls_hit1",params,true,true)
	else:
		Audios.play_sfx("balls_hit1",params,true,true)
