extends ball

# ============================================================
# 炮兵
# - 不靠身体造成伤害，周期性“指挥开炮”。
# - 每轮先在地图内部随机一个完整可容纳的绿色虚线炮击区。
# - 炮击区内随机产生多个红色落点；落点视觉由炮兵炮击区域.gd 绘制。
# - 红色内圈扩大 + 四角方框收缩到实际爆炸圆后，炮弹落下。
# - authority 负责实际圆形伤害和径向击退；视觉通过 RPC 在所有客户端生成。
# ============================================================

const BARRAGE_VISUAL_SCRIPT = preload("res://scripts/effects/炮兵炮击区域.gd")
const EXPLOSION_SFX:AudioStream = preload("res://audio/characters/炮兵/爆炸.mp3")
const MISSILE_LAUNCH_SFX:AudioStream = preload("res://audio/characters/炮兵/导弹发射.mp3")
const COMMAND_CALL_SFX:AudioStream = preload("res://audio/characters/炮兵/呼叫.mp3")
const IMAGE_DIR:String = "res://Images/characters/人物/炮兵"

@export_category("炮兵 - 外观（可留空，会自动找图片）")
@export var normal_texture:Texture2D
@export var command_texture:Texture2D
@export_range(0.10,2.0,0.05) var command_visual_duration:float = 0.95

@export_category("炮兵 - 指挥频率")
@export_range(0.2,20.0,0.1) var first_barrage_delay:float = 2.0
@export_range(1.0,30.0,0.1) var barrage_interval:float = 6.8
@export_range(0.05,3.0,0.05) var command_windup:float = 0.65

@export_category("炮兵 - 绿色炮击区")
@export_range(20.0,600.0,2.0) var barrage_radius:float = 55.0
@export_range(0.0,80.0,1.0) var map_edge_margin:float = 12.0

@export_category("炮兵 - 红色落点")
@export_range(1,16,1) var strike_count_min:int = 3
@export_range(1,16,1) var strike_count_max:int = 6
# 每一发直接在上下限之间随机，避免“基准半径 + 比例”难以直观看出真实范围。
# v15 提高为 18~24px；视觉、伤害和击退判定都使用同一个随机结果。
@export_range(6.0,240.0,1.0) var strike_radius_min:float = 18.0
@export_range(6.0,240.0,1.0) var strike_radius_max:float = 24.0
@export_range(0.2,5.0,0.05) var warning_duration:float = 1.55
@export_range(0.0,1.0,0.02) var warning_hold_duration:float = 0.12
@export_range(0.05,1.5,0.02) var shell_fall_duration:float = 0.24
@export_range(0.05,1.5,0.01) var strike_spawn_interval_min:float = 0.30
@export_range(0.05,1.5,0.01) var strike_spawn_interval_max:float = 0.46
@export_range(0.0,1.0,0.05) var minimum_marker_separation_ratio:float = 1.15

@export_category("炮兵 - 炮弹")
@export_range(0.0,10.0,0.05) var shell_damage_multiplier:float = 1.0
@export var shell_ignore_block:bool = false
@export_range(0.0,400.0,2.0) var knockback_distance:float = 98.0
@export_range(50.0,2000.0,10.0) var knockback_speed:float = 790.0
@export_range(0.0,1.5,0.05) var knockback_wall_bounce:float = 0.42
@export_range(0.0,250.0,2.0) var impact_camera_shake:float = 34.0

@export_category("炮兵 - 音效")
# 上传的爆炸素材本身峰值较高，因此默认稍微压低；导弹发射素材较轻，适当提高。
@export_range(-30.0,12.0,0.5) var explosion_sfx_volume_db:float = -8.0
@export_range(-30.0,12.0,0.5) var missile_launch_sfx_volume_db:float = 4.0
@export_range(-30.0,12.0,0.5) var command_call_sfx_volume_db:float = -8.0
@export_range(100.0,3000.0,50.0) var artillery_sfx_max_distance:float = 1200.0

var _artillery_loop_running:bool = false
var _visual_token:int = 0
var _default_texture:Texture2D = null
var _barrage_serial:int = 0
var _last_controlled_barrage_msec:int = -1000000000


func _ready() -> void:
	Can_Attack = false
	Can_Skill = false
	super._ready()
	_auto_load_textures()
	if image is Sprite2D:
		_default_texture = (image as Sprite2D).texture
	_set_visual_state_local(false)
	if is_multiplayer_authority():
		call_deferred("_artillery_loop")


func controlled_skill_action() -> void:
	# V131：直接控制时右键以鼠标位置为炮击区中心；后台炮击循环暂停。
	if not is_player_controlled() or not is_multiplayer_authority():
		return
	if health <= 0 or state_machine.current_state == State.Die or dizziness or is_damage_output_disabled():
		return
	if not has_player_control_aim():
		return
	var now_msec:int = Time.get_ticks_msec()
	var cooldown_msec:int = int(round(maxf(barrage_interval,0.0) * 1000.0))
	if now_msec - _last_controlled_barrage_msec < cooldown_msec:
		return
	_last_controlled_barrage_msec = now_msec
	_command_barrage(player_control_aim_position)


func _artillery_loop() -> void:
	if _artillery_loop_running:
		return
	_artillery_loop_running = true

	if first_barrage_delay > 0.0:
		if not (await wait_for_combat_time(first_barrage_delay)):
			_artillery_loop_running = false
			return

	while is_instance_valid(self) and is_inside_tree() and health > 0:
		if is_combat_runtime_active() and not is_player_controlled():
			await _command_barrage()
		if not is_instance_valid(self) or not is_inside_tree() or health <= 0:
			break
		if not (await wait_for_combat_time(maxf(barrage_interval,1.0))):
			break

	_artillery_loop_running = false


func _command_barrage(forced_center:Variant = null) -> void:
	if not is_multiplayer_authority() or health <= 0 or not is_combat_runtime_active():
		return
	if forced_center == null and is_player_controlled():
		return

	var map_rect:Rect2 = _get_map_rect()
	if map_rect.size.x <= 1.0 or map_rect.size.y <= 1.0:
		# 没有有效地图边界时宁可不发炮，避免违反“炮击区域必须在地图内部”。
		return

	# 先把这一轮所有小范围炮击安排好，才能准确知道“指挥开火”图片要保持多久。
	var effective_barrage_radius:float = _fit_barrage_radius_to_map(map_rect)
	if effective_barrage_radius < 24.0:
		return
	# 小范围炮直接使用可调的最小/最大半径。仍受绿色总区域限制，
	# 保证整枚红色爆炸圆可以完整落在绿色区域内部。
	var strike_limit:float = maxf(effective_barrage_radius * 0.46,6.0)
	var requested_radius_min:float = minf(strike_radius_min,strike_radius_max)
	var requested_radius_max:float = maxf(strike_radius_min,strike_radius_max)
	var effective_strike_radius_min:float = clampf(requested_radius_min,6.0,strike_limit)
	var effective_strike_radius_max:float = clampf(requested_radius_max,effective_strike_radius_min,strike_limit)
	var center:Vector2
	if forced_center is Vector2:
		var edge_margin:float = maxf(map_edge_margin,0.0) + effective_barrage_radius
		var min_x:float = map_rect.position.x + edge_margin
		var max_x:float = map_rect.end.x - edge_margin
		var min_y:float = map_rect.position.y + edge_margin
		var max_y:float = map_rect.end.y - edge_margin
		if min_x > max_x:
			min_x = (map_rect.position.x + map_rect.end.x) * 0.5
			max_x = min_x
		if min_y > max_y:
			min_y = (map_rect.position.y + map_rect.end.y) * 0.5
			max_y = min_y
		center = Vector2(
			clampf(forced_center.x,min_x,max_x),
			clampf(forced_center.y,min_y,max_y)
		)
	else:
		center = _random_barrage_center(map_rect,effective_barrage_radius)
	var strike_count:int = randi_range(
		mini(strike_count_min,strike_count_max),
		maxi(strike_count_min,strike_count_max)
	)
	strike_count = maxi(strike_count,1)

	# 每发的小范围炮独立在上下限之间随机。
	var strike_radii:= PackedFloat32Array()
	for _i:int in range(strike_count):
		strike_radii.append(randf_range(effective_strike_radius_min,effective_strike_radius_max))

	var points:PackedVector2Array = _pick_strike_points(
		center,
		effective_barrage_radius,
		strike_radii
	)
	if points.is_empty():
		return

	# 落点不是同时出现：第一个立即出现，之后每个按小幅随机间隔依次出现。
	var reveal_delays:= PackedFloat32Array()
	var interval_min:float = maxf(minf(strike_spawn_interval_min,strike_spawn_interval_max),0.05)
	var interval_max:float = maxf(maxf(strike_spawn_interval_min,strike_spawn_interval_max),interval_min)
	var cumulative_delay:float = 0.0
	for i:int in range(points.size()):
		if i > 0:
			cumulative_delay += randf_range(interval_min,interval_max)
		reveal_delays.append(cumulative_delay)

	# “指挥开火”图片从前摇开始，一直维持到最后一枚小范围炮弹真正命中。
	# 这比旧版固定 0.95 秒更可靠：炮多、间隔长时也不会提前切回普通图。
	var last_reveal_delay:float = reveal_delays[reveal_delays.size() - 1] if not reveal_delays.is_empty() else 0.0
	var fire_pose_duration:float = (
		maxf(command_windup,0.05)
		+ last_reveal_delay
		+ maxf(warning_duration,0.05)
		+ maxf(warning_hold_duration,0.0)
		+ maxf(shell_fall_duration,0.05)
		+ 0.08
	)
	# 每轮真正开始“呼叫炮击”时先播放一次呼叫音效。
	# 这段素材峰值接近 0 dB，因此默认压低，避免盖住随后导弹发射与爆炸声。
	if multiplayer.has_multiplayer_peer():
		_rpc_command_call_feedback.rpc(global_position)
	else:
		_rpc_command_call_feedback(global_position)

	_show_command_visual_everywhere(fire_pose_duration)
	var token:int = _visual_token

	if not (await wait_for_combat_time(maxf(command_windup,0.05))):
		return
	if not is_instance_valid(self) or health <= 0 or token != _visual_token or not is_combat_runtime_active():
		return
	if forced_center == null and is_player_controlled():
		return

	_barrage_serial += 1
	var barrage_id:int = _barrage_serial

	if multiplayer.has_multiplayer_peer():
		_rpc_show_barrage.rpc(
			center,
			effective_barrage_radius,
			points,
			strike_radii,
			reveal_delays,
			warning_duration,
			warning_hold_duration,
			shell_fall_duration
		)
	else:
		_rpc_show_barrage(
			center,
			effective_barrage_radius,
			points,
			strike_radii,
			reveal_delays,
			warning_duration,
			warning_hold_duration,
			shell_fall_duration
		)

	for i:int in range(points.size()):
		var reveal_delay:float = reveal_delays[i] if i < reveal_delays.size() else 0.0
		var actual_radius:float = strike_radii[i] if i < strike_radii.size() else effective_strike_radius_min

		# “导弹发射”音效在这一发真正开始从空中落下时播放。
		# 声音从炮兵当前位置发出；爆炸声则在最终落点播放。
		var launch_delay:float = (
			reveal_delay
			+ maxf(warning_duration,0.05)
			+ maxf(warning_hold_duration,0.0)
		)
		_run_launch_after(maxf(launch_delay,0.05))

		var impact_delay:float = launch_delay + maxf(shell_fall_duration,0.05)
		_run_strike_after(maxf(impact_delay,0.05),points[i],actual_radius,barrage_id)


func _run_launch_after(delay:float) -> void:
	if not (await wait_for_combat_time(delay)):
		return
	_on_launch_timer()


func _run_strike_after(delay:float,point:Vector2,radius:float,barrage_id:int) -> void:
	if not (await wait_for_combat_time(delay)):
		return
	_on_strike_timer(point,radius,barrage_id)


func _on_launch_timer() -> void:
	if not is_instance_valid(self) or not is_inside_tree() or health <= 0 or not is_combat_runtime_active():
		return
	if multiplayer.has_multiplayer_peer():
		_rpc_launch_feedback.rpc(global_position)
	else:
		_rpc_launch_feedback(global_position)


func _on_strike_timer(point:Vector2,radius:float,_barrage_id:int) -> void:
	if not is_instance_valid(self) or not is_inside_tree() or health <= 0 or not is_combat_runtime_active():
		return

	_apply_shell_impact(point,radius)
	if multiplayer.has_multiplayer_peer():
		_rpc_impact_feedback.rpc(point)
	else:
		_rpc_impact_feedback(point)


func _apply_shell_impact(point:Vector2,radius:float) -> void:
	if not is_multiplayer_authority():
		return

	var damage_enabled:bool = not is_damage_output_disabled()
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if not _can_hit_target(target):
			continue

		var distance:float = point.distance_to(target.global_position)
		if distance > radius:
			continue

		var ratio:float = clampf(distance / maxf(radius,1.0),0.0,1.0)
		var falloff:float = lerpf(1.0,0.70,ratio)
		var shell_damage_amount:float = attack_damage(shell_damage_multiplier)
		if damage_enabled and shell_damage_amount > 0.0:
			target.receive_spatial_damage(
				shell_damage_amount * falloff,
				{
					"shape": "circle",
					"point": point,
					"center": point,
					"radius": maxf(radius,1.0),
					"source": self,
				},
				shell_ignore_block
			)

		if knockback_distance > 0.0:
			var push_dir:Vector2 = target.global_position - point
			if push_dir.length_squared() <= 0.000001:
				push_dir = Vector2.RIGHT.rotated(randf_range(0.0,TAU))
			var push_distance:float = knockback_distance * lerpf(1.0,0.58,ratio)
			target.apply_knockback(
				push_dir.normalized(),
				push_distance,
				knockback_speed,
				knockback_wall_bounce,
				0.0,
				{
					"source": self,
					"max_wall_bounces": 1,
					"stop_on_character": true,
					"smooth_motion": true,
				}
			)


func _can_hit_target(target:ball) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target == self or not target.is_combat_targetable():
		return false
	if (
		not Game.Game_Settings.Have_Team_Damage
		and Team != ""
		and target.Team != ""
		and Team == target.Team
	):
		return false
	return true


@rpc("authority","call_local","reliable")
func _rpc_show_barrage(
	center:Vector2,
	radius:float,
	points:PackedVector2Array,
	impact_radii:PackedFloat32Array,
	reveal_delays:PackedFloat32Array,
	warn_duration:float,
	hold_duration:float,
	fall_duration:float
) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var visual:Node2D = BARRAGE_VISUAL_SCRIPT.new() as Node2D
	if visual == null:
		return
	visual.name = "ArtilleryBarrage_%d" % Time.get_ticks_usec()
	visual.set("barrage_radius",radius)
	visual.set("strike_radius",_average_radius_or_default(impact_radii))
	visual.set("strike_points",points)
	visual.set("strike_radii",impact_radii)
	visual.set("strike_reveal_delays",reveal_delays)
	visual.set("warning_duration",warn_duration)
	visual.set("warning_hold_duration",hold_duration)
	visual.set("shell_fall_duration",fall_duration)
	visual.global_position = center
	world.add_child(visual)


@rpc("authority","call_local","reliable")
func _rpc_command_call_feedback(point:Vector2) -> void:
	_spawn_local_positional_sfx(
		COMMAND_CALL_SFX,
		point,
		command_call_sfx_volume_db,
		1.0,
		artillery_sfx_max_distance
	)


@rpc("authority","call_local","unreliable")
func _rpc_launch_feedback(point:Vector2) -> void:
	_spawn_local_positional_sfx(
		MISSILE_LAUNCH_SFX,
		point,
		missile_launch_sfx_volume_db,
		randf_range(0.98,1.02),
		artillery_sfx_max_distance
	)


@rpc("authority","call_local","unreliable")
func _rpc_impact_feedback(point:Vector2) -> void:
	_spawn_local_positional_sfx(
		EXPLOSION_SFX,
		point,
		explosion_sfx_volume_db,
		randf_range(0.97,1.03),
		artillery_sfx_max_distance
	)
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var shake_value:Variant = world.get("camera_shake_amount")
	if shake_value != null:
		world.set("camera_shake_amount",float(shake_value) + impact_camera_shake)


func _spawn_local_positional_sfx(
	stream:AudioStream,
	point:Vector2,
	volume:float,
	pitch:float = 1.0,
	max_distance:float = 1200.0
) -> void:
	if stream == null:
		return
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var player:= AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume
	player.pitch_scale = clampf(pitch,0.5,2.0)
	player.max_distance = maxf(max_distance,100.0)
	player.attenuation = 0.75
	world.add_child(player)
	player.global_position = point
	player.finished.connect(player.queue_free)
	player.play()


func _get_map_rect() -> Rect2:
	var world = get_tree().current_scene
	if world == null or not world.has_method("return_map_world_rect"):
		return Rect2()
	if not world.map_group.has(str(world.now_choose_map)):
		return Rect2()
	var map_node = world.map_group[str(world.now_choose_map)]
	if not map_node is TileMapLayer:
		return Rect2()
	return world.return_map_world_rect(map_node)


func _fit_barrage_radius_to_map(rect:Rect2) -> float:
	var margin:float = maxf(map_edge_margin,0.0)
	var max_radius:float = minf(rect.size.x,rect.size.y) * 0.5 - margin
	if max_radius <= 0.0:
		return 0.0
	return minf(maxf(barrage_radius,20.0),max_radius)


func _random_barrage_center(rect:Rect2,radius:float) -> Vector2:
	var inset:float = maxf(radius + map_edge_margin,0.0)
	var min_x:float = rect.position.x + inset
	var max_x:float = rect.end.x - inset
	var min_y:float = rect.position.y + inset
	var max_y:float = rect.end.y - inset

	if min_x > max_x:
		min_x = (rect.position.x + rect.end.x) * 0.5
		max_x = min_x
	if min_y > max_y:
		min_y = (rect.position.y + rect.end.y) * 0.5
		max_y = min_y

	return Vector2(randf_range(min_x,max_x),randf_range(min_y,max_y))


func _pick_strike_points(
	center:Vector2,
	area_radius:float,
	impact_radii:PackedFloat32Array
) -> PackedVector2Array:
	var points:= PackedVector2Array()
	var separation_ratio:float = maxf(minimum_marker_separation_ratio,0.0)

	for index:int in range(maxi(impact_radii.size(),1)):
		var impact_radius:float = impact_radii[index] if index < impact_radii.size() else _default_strike_radius()
		# 每发按自己的随机半径缩进，保证整个红色爆炸圆仍完整落在绿色区域内。
		var available_radius:float = maxf(area_radius - impact_radius - 3.0,0.0)
		var chosen:Vector2 = center
		var accepted:bool = false
		var last_candidate:Vector2 = center
		for _attempt:int in range(42):
			var angle:float = randf_range(0.0,TAU)
			# sqrt 让随机点在圆面积内更均匀，而不是全部挤在中心。
			var radial:float = sqrt(randf()) * available_radius
			var candidate:Vector2 = center + Vector2.RIGHT.rotated(angle) * radial
			last_candidate = candidate

			var separated:bool = true
			for existing_index:int in range(points.size()):
				var existing_radius:float = impact_radii[existing_index] if existing_index < impact_radii.size() else impact_radius
				var min_separation:float = (impact_radius + existing_radius) * 0.5 * separation_ratio
				if candidate.distance_to(points[existing_index]) < min_separation:
					separated = false
					break
			if separated:
				chosen = candidate
				accepted = true
				break

		if not accepted:
			# 小区域或落点很多时允许部分重叠，但仍保证在绿色区域内部。
			chosen = last_candidate
		points.append(chosen)

	return points


func _default_strike_radius() -> float:
	return maxf((strike_radius_min + strike_radius_max) * 0.5,6.0)


func _average_radius_or_default(values:PackedFloat32Array) -> float:
	if values.is_empty():
		return _default_strike_radius()
	var total:float = 0.0
	for value:float in values:
		total += value
	return total / float(values.size())


func _auto_load_textures() -> void:
	if normal_texture == null:
		normal_texture = _load_first_texture([
			IMAGE_DIR.path_join("炮兵_普通状态.png"),
			IMAGE_DIR.path_join("炮兵_正常.png"),
			IMAGE_DIR.path_join("人_正常.png"),
			IMAGE_DIR.path_join("炮兵_正常.webp"),
		])
	if command_texture == null:
		command_texture = _load_first_texture([
			IMAGE_DIR.path_join("炮兵_指挥开火.png"),
			IMAGE_DIR.path_join("炮兵_指挥.png"),
			IMAGE_DIR.path_join("人_指挥.png"),
			IMAGE_DIR.path_join("炮兵_开炮.png"),
			IMAGE_DIR.path_join("炮兵_攻击.png"),
		])


func _load_first_texture(paths:Array[String]) -> Texture2D:
	for path:String in paths:
		if not ResourceLoader.exists(path):
			continue
		var resource:Resource = ResourceLoader.load(path)
		if resource is Texture2D:
			return resource as Texture2D
	return null


func _show_command_visual_everywhere(duration:float) -> void:
	_visual_token += 1
	var token:int = _visual_token
	if multiplayer.has_multiplayer_peer():
		_rpc_show_command_visual.rpc(token,duration)
	else:
		_rpc_show_command_visual(token,duration)


@rpc("authority","call_local","reliable")
func _rpc_show_command_visual(token:int,duration:float) -> void:
	if token < _visual_token:
		return
	_visual_token = token
	_set_visual_state_local(true)
	_restore_normal_visual_after(duration,token)


func _restore_normal_visual_after(delay:float,token:int) -> void:
	await get_tree().create_timer(maxf(delay,0.10)).timeout
	if not is_instance_valid(self) or token != _visual_token:
		return
	_set_visual_state_local(false)


func _set_visual_state_local(commanding:bool) -> void:
	if not (image is Sprite2D):
		return
	var sprite:Sprite2D = image as Sprite2D
	var normal:Texture2D = normal_texture if normal_texture != null else _default_texture
	var wanted:Texture2D = command_texture if commanding and command_texture != null else normal
	if wanted != null:
		sprite.texture = wanted

	# 没有“指挥”图片时也给一个暖色闪烁，确保玩家能看到角色正在下令。
	sprite.self_modulate = Color(1.0,0.82,0.62,1.0) if commanding and command_texture == null else Color.WHITE
	var auto_fit:Node = get_node_or_null("CharacterAutoFit")
	if auto_fit != null and auto_fit.has_method("apply_visual_fit_only"):
		auto_fit.call_deferred("apply_visual_fit_only")


func Die() -> void:
	_visual_token += 1
	super()
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(self):
		Game.free_node(self)
