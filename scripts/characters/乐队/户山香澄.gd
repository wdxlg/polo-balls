extends ball

# V392 + V80平衡补丁：户山香澄射速成长、落星命中音效与强化落星视觉。
# - 落星视觉不再直接加入 World/MultiplayerSpawner 的 spawn_path，避免 @Node2D@xxxx 保留名报错。
# - 星星从左上/右上随机范围斜向旋转坠落。
# - 警告标识仅快速红<->黄变色，不再缩放。
# - 人物根据正在播放的 popipa1/2/3 实际时间位置读取预计算音量包络：
#   大声时变细、变高；小声时变宽、变扁；底部中心锚点保持不动。
# - 普攻射速不再随时间自动提高：只有落星真正命中敌人才叠加攻速。
# - AI 落星不会固定砸敌人中心，而是在敌人周围可调半径内随机选择落点。
# - 星星真正命中人物/护盾时复用项目通用 balls_hit1 碰撞伤害音效。

const CHARACTER_TEXTURE:Texture2D = preload("res://Images/characters/乐队/户山香澄/户山香澄.png")
const STAR_STRIKE_SCENE:PackedScene = preload("res://scenes/effects/户山香澄_星星坠落.tscn")
const POPIPA_1:AudioStream = preload("res://audio/characters/户山香澄/popipa1.mp3")
const POPIPA_2:AudioStream = preload("res://audio/characters/户山香澄/popipa2.mp3")
const POPIPA_3:AudioStream = preload("res://audio/characters/户山香澄/popipa3.mp3")

const POPIPA_ENVELOPE_HZ:float = 50.0

const POPIPA_1_ENVELOPE = [
	0.000, 0.007, 0.785, 0.785, 0.764, 0.738, 0.670, 0.008, 0.000, 0.000, 0.000, 0.715,
	0.784, 0.764, 0.688, 0.219, 0.000, 0.000, 0.000, 0.000, 0.673, 0.760, 0.740, 0.675,
	0.709, 0.712, 0.722, 0.711, 0.700, 0.625, 0.609, 0.668, 0.644, 0.533, 0.209, 0.000,
	0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000,
	0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000,
	0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000,
	0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000,
	0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000,
	0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000,
	0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.749, 0.785, 0.764,
	0.738, 0.670, 0.008, 0.000, 0.000, 0.000, 0.715, 0.784, 0.764, 0.688, 0.219, 0.000,
	0.000, 0.000, 0.000, 0.673, 0.760, 0.740, 0.675, 0.709, 0.712, 0.723, 0.711, 0.699,
	0.625, 0.609, 0.668, 0.644, 0.533, 0.209, 0.000
]

const POPIPA_2_ENVELOPE = [
	0.000, 0.691, 0.902, 0.908, 0.919, 0.911, 0.681, 0.153, 0.000, 0.000, 0.000, 0.870,
	0.966, 0.951, 0.971, 0.507, 0.000, 0.000, 0.000, 0.000, 0.000, 0.965, 0.927, 0.922,
	0.937, 0.935, 0.884, 0.917, 0.920, 0.932, 0.799, 0.810, 0.828, 0.722, 0.495, 0.000,
	0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000,
	0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000,
	0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000,
	0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000,
	0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000,
	0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000,
	0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000,
	0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000,
	0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000,
	0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000
]

const POPIPA_3_ENVELOPE = [
	0.000, 0.556, 0.973, 0.937, 0.963, 0.954, 0.702, 0.000, 0.000, 0.000, 0.000, 0.823,
	0.918, 0.927, 0.871, 0.518, 0.000, 0.000, 0.000, 0.000, 0.746, 0.903, 0.909, 0.894,
	0.920, 0.877, 0.329, 0.000, 0.000, 0.000, 0.862, 0.931, 0.972, 0.959, 0.692, 0.033,
	0.000, 0.000, 0.000, 0.000, 0.720, 0.920, 0.924, 0.908, 0.800, 0.314, 0.000, 0.000,
	0.000, 0.909, 0.952, 0.951, 0.911, 0.333, 0.000, 0.000, 0.000, 0.000, 0.000, 0.940,
	0.884, 0.872, 0.871, 0.851, 0.842, 0.842, 0.842, 0.845, 0.848, 0.866, 0.871, 0.786,
	0.843, 0.782, 0.774, 0.794, 0.828, 0.826, 0.808, 0.785, 0.725, 0.561, 0.093, 0.000,
	0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000,
	0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000,
	0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000,
	0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000,
	0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000,
	0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000
]

@export_category("户山香澄 - 星星普攻")
@export_range(0.15,3.0,0.01) var star_impact_delay:float = 0.92
@export_range(8.0,120.0,1.0) var star_damage_radius:float = 34.0
@export_range(0.0,5.0,0.05) var star_damage_multiplier:float = 1.0
@export_range(40.0,420.0,2.0) var star_fall_height:float = 210.0
@export_range(0.06,1.0,0.01) var warning_color_cycle:float = 0.16
@export_range(4.0,42.0,0.5) var star_visual_radius:float = 16.0
@export_range(40.0,320.0,2.0) var star_entry_side_min_x:float = 110.0
@export_range(40.0,420.0,2.0) var star_entry_side_max_x:float = 220.0
@export_range(0.0,0.60,0.01) var star_entry_height_jitter:float = 0.18
@export_range(0.02,0.50,0.01) var attack_recovery:float = 0.10
@export_range(0.0,160.0,1.0) var target_random_radius:float = 42.0

@export_category("户山香澄 - 命中叠攻速")
@export_range(0.12,1.0,0.01) var minimum_attack_cooling:float = 0.25
@export_range(1,80,1) var hits_to_max_fire_rate:int = 10

@export_category("户山香澄 - 音效")
@export_range(-24.0,8.0,0.5) var popipa_volume_db:float = -2.0
@export_range(100.0,2400.0,10.0) var popipa_max_distance:float = 1100.0

@export_category("户山香澄 - Popipa音量形变")
@export_range(1.0,1.6,0.01) var quiet_width_scale:float = 1.18
@export_range(0.45,1.0,0.01) var quiet_height_scale:float = 0.82
@export_range(0.45,1.0,0.01) var loud_width_scale:float = 0.76
@export_range(1.0,1.8,0.01) var loud_height_scale:float = 1.30
@export_range(1.0,30.0,0.5) var voice_shape_response:float = 13.0
@export_range(0.0,0.20,0.005) var voice_shape_silence_threshold:float = 0.015

var _attack_audio_cursor:int = 0
var _local_effect_serial:int = 0
var _star_rng:=RandomNumberGenerator.new()
var _successful_star_hits:int = 0
var _fire_rate_start_cooling:float = 1.0
var _active_popipa_players:Array[AudioStreamPlayer2D] = []

var _body_sprite:Sprite2D = null
var _body_base_scale:Vector2 = Vector2.ONE
var _body_base_position:Vector2 = Vector2.ZERO
var _body_base_rotation:float = 0.0
var _body_bottom_local:Vector2 = Vector2.ZERO
var _body_bottom_anchor:Vector2 = Vector2.ZERO
var _current_voice_shape:Vector2 = Vector2.ONE
var _body_visual_ready:bool = false


func _ready() -> void:
	Has_Collision_Damage = false
	Can_Attack = true
	Can_Skill = false
	Health_Restore = 0
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if image is Sprite2D:
		var body_sprite:Sprite2D = image as Sprite2D
		body_sprite.texture = CHARACTER_TEXTURE
		body_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		body_sprite.visible = true
	super._ready()
	_star_rng.seed = Game.battle_rng_seed_or("scripts/characters/乐队/户山香澄.gd:_star_rng",int(Time.get_ticks_usec()) ^ int(get_instance_id()))
	_fire_rate_start_cooling = maxf(Attack_Cooling,0.05)
	default_properties["Attack_Cooling"] = _fire_rate_start_cooling
	call_deferred("_capture_voice_visual_baseline")


func _process(delta:float) -> void:
	_update_popipa_body_shape(delta)


func _add_fire_rate_on_successful_hit() -> void:
	# 一颗落星无论同时砸中几名敌人，只算一次“成功命中”，避免范围攻击瞬间叠满攻速。
	_successful_star_hits += 1
	var start_cooling:float = maxf(_fire_rate_start_cooling,0.05)
	var min_cooling:float = clampf(minimum_attack_cooling,0.05,start_cooling)
	var needed_hits:int = maxi(hits_to_max_fire_rate,1)
	var hit_t:float = clampf(float(_successful_star_hits) / float(needed_hits),0.0,1.0)
	# 继续在 attacks/sec 空间线性增长，但进度只由“真正命中次数”推进。
	var start_rate:float = 1.0 / start_cooling
	var end_rate:float = 1.0 / min_cooling
	var current_rate:float = lerpf(start_rate,end_rate,hit_t)
	var new_cooling:float = 1.0 / maxf(current_rate,0.001)
	default_properties["Attack_Cooling"] = new_cooling
	Attack_Cooling = new_cooling


func has_collision_damage() -> bool:
	return false


func get_preview_texture() -> Texture2D:
	return CHARACTER_TEXTURE


func Attack() -> void:
	super()
	if not is_multiplayer_authority() or state_machine == null or state_machine.current_state == State.Die:
		return
	if health <= 0 or is_damage_output_disabled() or not is_combat_runtime_active():
		Attacking = false
		return
	if Attacking:
		return

	var landing_point:Vector2
	if has_player_control_aim():
		landing_point = player_control_aim_world_position(global_position)
	else:
		var target:ball = _nearest_enemy()
		if target == null:
			Attacking = false
			return
		landing_point = _roll_landing_point_near_target(target)

	Attacking = true
	_play_next_popipa_everywhere(global_position)
	_spawn_star_strike_everywhere(landing_point)
	_resolve_star_impact_later(landing_point)

	if attack_recovery > 0.0:
		await wait_for_combat_time(attack_recovery)
	if is_instance_valid(self):
		Attacking = false


func _roll_landing_point_near_target(target:ball) -> Vector2:
	var center:Vector2 = combat_target_position(target)
	var radius:float = maxf(target_random_radius,0.0)
	if radius <= 0.001:
		return center
	# sqrt(randf()) 让落点在整个圆面积内均匀分布，而不是大量堆在圆心。
	var angle:float = _star_rng.randf_range(0.0,TAU)
	var distance:float = sqrt(_star_rng.randf()) * radius
	return center + Vector2.RIGHT.rotated(angle) * distance


func _resolve_star_impact_later(landing_point:Vector2) -> void:
	await wait_for_combat_time(maxf(star_impact_delay,0.05))
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if not is_multiplayer_authority() or health <= 0:
		return
	if state_machine == null or state_machine.current_state == State.Die:
		return
	if is_damage_output_disabled() or not is_combat_runtime_active():
		return
	_resolve_star_impact(landing_point)


func _resolve_star_impact(landing_point:Vector2) -> void:
	var radius:float = maxf(star_damage_radius,1.0)
	var damage_value:float = attack_damage(maxf(star_damage_multiplier,0.0))
	if damage_value <= 0.0:
		return
	var radius_sq:float = radius * radius
	var hit_any:bool = false
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var target:ball = raw as ball
		if not _is_enemy(target):
			continue
		if landing_point.distance_squared_to(target.global_position) > radius_sq:
			continue
		var did_hit:bool = target.receive_spatial_damage(
			damage_value,
			{
				"shape":"circle",
				"center":landing_point,
				"radius":radius,
				"source":self,
			},
			false,
			false
		)
		hit_any = hit_any or did_hit
	if hit_any:
		_add_fire_rate_on_successful_hit()
		_play_star_collision_sfx(damage_value)


func _play_star_collision_sfx(outgoing_damage:float) -> void:
	var params:Dictionary = {
		"volume": clampf(outgoing_damage - 12.0,-100.0,0.0),
	}
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc("balls_hit1",params,true,true)
	else:
		Audios.play_sfx("balls_hit1",params,true,true)


func _spawn_star_strike_everywhere(landing_point:Vector2) -> void:
	var start_offset:Vector2 = _roll_star_start_offset()
	var visual_seed:int = _star_rng.randi()
	if multiplayer.has_multiplayer_peer():
		_rpc_spawn_star_strike.rpc(
			landing_point,
			start_offset,
			maxf(star_impact_delay,0.05),
			maxf(warning_color_cycle,0.06),
			maxf(star_visual_radius,2.0),
			visual_seed
		)
	else:
		_rpc_spawn_star_strike(
			landing_point,
			start_offset,
			maxf(star_impact_delay,0.05),
			maxf(warning_color_cycle,0.06),
			maxf(star_visual_radius,2.0),
			visual_seed
		)


func _roll_star_start_offset() -> Vector2:
	var min_x:float = minf(star_entry_side_min_x,star_entry_side_max_x)
	var max_x:float = maxf(star_entry_side_min_x,star_entry_side_max_x)
	var side:float = -1.0 if _star_rng.randf() < 0.5 else 1.0
	var x:float = _star_rng.randf_range(maxf(min_x,8.0),maxf(max_x,maxf(min_x,8.0)))
	var height_scale:float = _star_rng.randf_range(
		maxf(1.0 - star_entry_height_jitter,0.60),
		1.0 + maxf(star_entry_height_jitter,0.0)
	)
	return Vector2(side * x,-maxf(star_fall_height,8.0) * height_scale)


@rpc("authority","call_local","reliable")
func _rpc_spawn_star_strike(
	landing_point:Vector2,
	start_offset:Vector2,
	impact_delay_value:float,
	warning_cycle_value:float,
	star_radius_value:float,
	visual_seed:int
) -> void:
	if not is_inside_tree():
		return
	var effect:Node2D = STAR_STRIKE_SCENE.instantiate() as Node2D
	if effect == null:
		return

	# World 根节点正是 MultiplayerSpawner.spawn_path。V390 把视觉场景直接
	# scene_root.add_child(effect) 会让 Spawner 捕获到 @Node2D@xxxx 保留名称并报错。
	# 这个视觉本来已经由 RPC 在每个 peer 各自创建，所以挂到角色下面并设 top_level，
	# 既避开重复自动 Spawn，也不会继承角色正在做的音量缩放。
	_local_effect_serial += 1
	effect.name = "KasumiStarStrike_%d" % _local_effect_serial
	effect.top_level = true
	effect.position = landing_point
	add_child(effect,true)
	effect.global_position = landing_point

	if effect.has_method("configure"):
		effect.call(
			"configure",
			impact_delay_value,
			start_offset,
			warning_cycle_value,
			star_radius_value,
			visual_seed
		)


func _play_next_popipa_everywhere(position_value:Vector2) -> void:
	var sound_index:int = _attack_audio_cursor
	_attack_audio_cursor = (_attack_audio_cursor + 1) % 3
	if multiplayer.has_multiplayer_peer():
		_rpc_play_popipa.rpc(sound_index,position_value,popipa_volume_db,popipa_max_distance)
	else:
		_rpc_play_popipa(sound_index,position_value,popipa_volume_db,popipa_max_distance)


@rpc("authority","call_local","unreliable")
func _rpc_play_popipa(sound_index:int,position_value:Vector2,volume_db:float,max_distance:float) -> void:
	var stream:AudioStream = null
	match posmod(sound_index,3):
		0:
			stream = POPIPA_1
		1:
			stream = POPIPA_2
		_:
			stream = POPIPA_3
	if stream == null or not is_inside_tree():
		return

	# 音频直接挂在角色上，不再把临时 Node 加到 World/MultiplayerSpawner 根。
	# 每一击仍然创建独立 player，因此 3 秒音频可以自然重叠，不会被下一击截断。
	var player:=AudioStreamPlayer2D.new()
	player.name = "KasumiAttackSFX_%d" % (Time.get_ticks_usec() & 0x7fffffff)
	player.stream = stream
	player.volume_db = clampf(volume_db,-40.0,12.0)
	player.pitch_scale = 1.0
	player.max_distance = maxf(max_distance,50.0)
	player.attenuation = 0.50
	player.max_polyphony = 1
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	player.set_meta("kasumi_popipa_index",posmod(sound_index,3))
	player.position = to_local(position_value)
	add_child(player,true)
	_active_popipa_players.append(player)
	player.finished.connect(_on_popipa_finished.bind(player),CONNECT_ONE_SHOT)
	player.play()


func _on_popipa_finished(player:AudioStreamPlayer2D) -> void:
	_active_popipa_players.erase(player)
	if is_instance_valid(player):
		player.queue_free()


func _capture_voice_visual_baseline() -> void:
	if not is_inside_tree() or not image is Sprite2D:
		return
	_body_sprite = image as Sprite2D
	if _body_sprite == null or _body_sprite.texture == null:
		return
	_body_base_scale = _body_sprite.scale
	_body_base_position = _body_sprite.position
	_body_base_rotation = _body_sprite.rotation
	_body_bottom_local = _visible_bottom_center_local(_body_sprite)
	_body_bottom_anchor = _body_base_position + _scaled_rotated_point(
		_body_bottom_local,
		_body_base_scale,
		_body_base_rotation
	)
	_current_voice_shape = Vector2.ONE
	_body_visual_ready = true


func _visible_bottom_center_local(sprite:Sprite2D) -> Vector2:
	if sprite == null or sprite.texture == null:
		return Vector2.ZERO
	var texture_size:Vector2 = sprite.texture.get_size()
	var used_position:=Vector2.ZERO
	var used_size:=texture_size
	var texture_image:Image = sprite.texture.get_image()
	if texture_image != null:
		var used_rect:Rect2i = texture_image.get_used_rect()
		if used_rect.size.x > 0 and used_rect.size.y > 0:
			used_position = Vector2(float(used_rect.position.x),float(used_rect.position.y))
			used_size = Vector2(float(used_rect.size.x),float(used_rect.size.y))
	var draw_origin:Vector2 = sprite.offset
	if sprite.centered:
		draw_origin -= texture_size * 0.5
	return draw_origin + Vector2(
		used_position.x + used_size.x * 0.5,
		used_position.y + used_size.y
	)


func _scaled_rotated_point(point:Vector2,scale_value:Vector2,rotation_value:float) -> Vector2:
	return Vector2(point.x * scale_value.x,point.y * scale_value.y).rotated(rotation_value)


func _update_popipa_body_shape(delta:float) -> void:
	if not _body_visual_ready or _body_sprite == null or not is_instance_valid(_body_sprite):
		return

	var loudness:float = _current_popipa_loudness()
	var target_shape:=Vector2.ONE
	if not _active_popipa_players.is_empty() and loudness > voice_shape_silence_threshold:
		var t:float = clampf(loudness,0.0,1.0)
		target_shape = Vector2(
			lerpf(quiet_width_scale,loud_width_scale,t),
			lerpf(quiet_height_scale,loud_height_scale,t)
		)

	var smoothing:float = 1.0 - exp(-maxf(voice_shape_response,0.1) * maxf(delta,0.0))
	_current_voice_shape = _current_voice_shape.lerp(target_shape,clampf(smoothing,0.0,1.0))

	var new_scale:=Vector2(
		_body_base_scale.x * _current_voice_shape.x,
		_body_base_scale.y * _current_voice_shape.y
	)
	_body_sprite.scale = new_scale
	# 只移动 Sprite2D 自身来补偿非等比缩放，碰撞、角色根、血条都不动。
	# 因此人物最下面的可见中心点始终锁在初始位置。
	_body_sprite.position = _body_bottom_anchor - _scaled_rotated_point(
		_body_bottom_local,
		new_scale,
		_body_base_rotation
	)


func _current_popipa_loudness() -> float:
	var loudness:float = 0.0
	for i:int in range(_active_popipa_players.size() - 1,-1,-1):
		var player:AudioStreamPlayer2D = _active_popipa_players[i]
		if player == null or not is_instance_valid(player):
			_active_popipa_players.remove_at(i)
			continue
		if not player.playing:
			continue
		var sound_index:int = int(player.get_meta("kasumi_popipa_index",0))
		var playback_position:float = player.get_playback_position() + AudioServer.get_time_since_last_mix()
		loudness = maxf(loudness,_sample_popipa_envelope(sound_index,playback_position))
	return loudness


func _sample_popipa_envelope(sound_index:int,playback_position:float) -> float:
	var envelope:Array = _get_popipa_envelope(sound_index)
	if envelope.is_empty():
		return 0.0
	var sample_position:float = maxf(playback_position,0.0) * POPIPA_ENVELOPE_HZ
	var i0:int = clampi(int(floor(sample_position)),0,envelope.size() - 1)
	var i1:int = mini(i0 + 1,envelope.size() - 1)
	var frac:float = clampf(sample_position - float(i0),0.0,1.0)
	return lerpf(envelope[i0],envelope[i1],frac)


func _get_popipa_envelope(sound_index:int) -> Array:
	match posmod(sound_index,3):
		0:
			return POPIPA_1_ENVELOPE
		1:
			return POPIPA_2_ENVELOPE
		_:
			return POPIPA_3_ENVELOPE


func _nearest_enemy() -> ball:
	var nearest:ball = null
	var nearest_distance_sq:float = INF
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var target:ball = raw as ball
		if not _is_enemy(target):
			continue
		var distance_sq:float = global_position.distance_squared_to(target.global_position)
		if distance_sq < nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest = target
	return nearest


func _is_enemy(target:ball) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(self,target): return false # 皓宸复制品及其产物不把己方选为目标
	if target == null or not is_instance_valid(target) or target == self:
		return false
	if target.Type != Ball_Type.Ball or target.health <= 0 or not target.is_combat_targetable():
		return false
	if target.state_machine != null and target.state_machine.current_state == State.Die:
		return false
	if not Team.is_empty() and not target.Team.is_empty() and Team == target.Team:
		return false
	return true
