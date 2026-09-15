extends ball

const WALL_TEXTURE:Texture2D = preload("res://Images/characters/建筑工人/砖墙.png")
const AUDIO_WALL_SHAKE:AudioStream = preload("res://audio/characters/建筑工人/墙颤抖.wav")
const AUDIO_WALL_COLLAPSE:AudioStream = preload("res://audio/characters/建筑工人/墙倒塌.wav")

@export_category("建筑工人墙 - 下沉倒塌")
@export_range(0.1,3.0,0.05) var collapse_wait:float = 0.55
@export_range(0.15,1.2,0.05) var pre_collapse_shake_duration:float = 0.38
@export_range(0.2,2.0,0.05) var sink_duration:float = 0.78
@export_range(0.0,20.0,0.05) var collapse_damage_multiplier:float = 6.6666667
@export_range(10.0,180.0,1.0) var collapse_radius:float = 72.0
@export_range(0.0,180.0,1.0) var collapse_knockback_distance:float = 46.0
@export_range(50.0,1200.0,10.0) var collapse_knockback_speed:float = 430.0
@export_range(0.02,0.30,0.01) var smoke_interval:float = 0.075

@export_category("建筑工人墙 - 倒塌两侧动画")
@export_range(0.2,1.5,0.05) var collapse_fx_duration:float = 0.55
@export_range(0.0,160.0,1.0) var collapse_fx_side_offset:float = 52.0
@export_range(0.0,220.0,1.0) var collapse_fx_outward_distance:float = 72.0
@export_range(-100.0,100.0,1.0) var collapse_fx_y:float = 30.0
@export_range(0.1,3.0,0.05) var collapse_fx_scale:float = 1.15

const WALL_HALF_WIDTH:float = 65.0
const WALL_TOP:float = -165.0
const WALL_BOTTOM:float = 165.0
const WALL_HEIGHT:float = WALL_BOTTOM - WALL_TOP

const MORTAR_SEGMENTS:Array = [
	[Vector2(-65,-110),Vector2(65,-110)],
	[Vector2(-65,-55),Vector2(65,-55)],
	[Vector2(-65,0),Vector2(65,0)],
	[Vector2(-65,55),Vector2(65,55)],
	[Vector2(-65,110),Vector2(65,110)],
	[Vector2(0,-165),Vector2(0,-110)],
	[Vector2(-32,-110),Vector2(-32,-55)],
	[Vector2(28,-55),Vector2(28,0)],
	[Vector2(-22,0),Vector2(-22,55)],
	[Vector2(34,55),Vector2(34,110)],
	[Vector2(-10,110),Vector2(-10,165)]
]

var builder_owner:ball = null
var _collapse_started:bool = false
var _collapse_serial:int = 0
var _wall_visual:Node2D = null
var _wall_sprite:Sprite2D = null
var _wall_full_display_height:float = 135.0
var _shake_audio_player:AudioStreamPlayer2D = null
@onready var _collapse_right_sprite:Sprite2D = get_node_or_null("Graphics/CollapseRight") as Sprite2D
@onready var _collapse_left_sprite:Sprite2D = get_node_or_null("Graphics/CollapseLeft") as Sprite2D


func _ready() -> void:
	Type = Ball_Type.Creature
	Can_Attack = false
	Can_Skill = false
	Speed = 0.0
	Damage = 0
	Has_Collision_Damage = false
	side_status_ui_enabled = false
	# 墙是固定建筑：角色撞上时不播放通用 ball 的弹性形变。
	When_Coliide_Tween = false

	super._ready()
	add_to_group("BuilderWall")
	image_color = Color.WHITE
	image_color_mix = 0.0
	set_image_color()
	_configure_wall_collision()
	_build_wall_visual()


func is_builder_wall() -> bool:
	return true


# 建筑墙不能被通用击退系统推动。它继续继承 ball 以兼容现有生命值、
# Hitbox/Hurtbox 和联网逻辑，但物理表现固定为“锚在原地”。
func apply_knockback(
	_knockback_direction:Vector2,
	_knockback_distance:float,
	_knockback_speed:float = 700.0,
	_wall_bounce_strength:float = 0.0,
	_stun_duration:float = 0.0,
	_options:Dictionary = {}
) -> Node:
	velocity = Vector2.ZERO
	direction = Vector2.ZERO
	Repel = Vector2.ZERO
	return null


func is_combat_targetable() -> bool:
	return health > 0 and not _collapse_started and not is_queued_for_deletion()


func is_collapse_started() -> bool:
	return _collapse_started


func tick_physics(_state:State,_delta:float) -> void:
	velocity = Vector2.ZERO
	direction = Vector2.ZERO
	Repel = Vector2.ZERO
	if health <= 0 and not _collapse_started:
		_begin_collapse()


func _build_wall_visual() -> void:
	if not image is Sprite2D:
		return
	_wall_sprite = image as Sprite2D
	_wall_sprite.texture = WALL_TEXTURE
	_wall_sprite.offset = Vector2.ZERO
	_wall_sprite.centered = true
	_wall_sprite.region_enabled = true
	_wall_sprite.region_rect = Rect2(Vector2.ZERO,WALL_TEXTURE.get_size())
	var size:Vector2 = WALL_TEXTURE.get_size()
	var longest:float = maxf(size.x,size.y)
	var fit:float = 135.0 / maxf(longest,1.0)
	_wall_sprite.scale = Vector2(fit,fit)
	_wall_sprite.visible = true
	_wall_visual = _wall_sprite
	_wall_full_display_height = size.y * fit
	_update_sink_visual(0.0,0.0)


func _update_sink_visual(progress:float,jitter_x:float) -> void:
	if _wall_sprite == null or not is_instance_valid(_wall_sprite) or WALL_TEXTURE == null:
		return
	var t:float = clampf(progress,0.0,1.0)
	var tex_size:Vector2 = WALL_TEXTURE.get_size()
	var visible_h:float = maxf(tex_size.y * (1.0 - t),0.0)
	_wall_sprite.position.x = jitter_x
	if visible_h <= 1.0:
		_wall_sprite.visible = false
		return
	_wall_sprite.visible = true
	_wall_sprite.region_rect = Rect2(0.0,0.0,tex_size.x,visible_h)
	var shown_height:float = visible_h * absf(_wall_sprite.scale.y)
	# 墙的“地面线”固定在原始底边，主体逐渐向下陷并从底部被裁掉。
	_wall_sprite.position.y = _wall_full_display_height * 0.5 - shown_height * 0.5


func hit_white_visual_only() -> void:
	if _wall_visual == null or not is_instance_valid(_wall_visual):
		return
	_wall_visual.modulate = Color(1.8,1.8,1.8,1.0)
	var tween := create_tween()
	tween.tween_property(_wall_visual,"modulate",Color.WHITE,0.12)


func hit_white(_ignore_block:bool = false) -> void:
	hit_white_visual_only()


func _configure_wall_collision() -> void:
	var body_shape := RectangleShape2D.new()
	body_shape.size = Vector2(118.0,112.0)
	collision_shape_2d.shape = body_shape
	collision_shape_2d.scale = Vector2.ONE

	var hit_shape:CollisionShape2D = self_hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if hit_shape != null:
		hit_shape.shape = body_shape.duplicate()
		hit_shape.scale = Vector2.ONE
	var hurt_shape:CollisionShape2D = self_hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if hurt_shape != null:
		hurt_shape.shape = body_shape.duplicate()
		hurt_shape.scale = Vector2.ONE


func _begin_collapse() -> void:
	if _collapse_started:
		return
	_collapse_started = true
	_collapse_serial += 1
	var token:int = _collapse_serial

	# 死亡等待阶段仍保留实体墙体；但已经不能再作为可攻击目标。
	if self_hurtbox != null:
		self_hurtbox.set_deferred("monitorable",false)
	if self_hitbox != null:
		self_hitbox.set_deferred("monitoring",false)
	call_deferred("_collapse_sequence",token)


func _collapse_sequence(token:int) -> void:
	var total_wait:float = maxf(collapse_wait,0.05)
	var shake_time:float = minf(maxf(pre_collapse_shake_duration,0.05),total_wait)
	var quiet_wait:float = maxf(total_wait - shake_time,0.0)
	if quiet_wait > 0.0:
		await get_tree().create_timer(quiet_wait).timeout
	if not is_instance_valid(self) or token != _collapse_serial:
		return

	# 临倒前先原地急促颤抖；颤抖行为一结束，音效立即停止，不要求把 5 秒素材放完。
	_start_shake_audio()
	var shake_elapsed:float = 0.0
	while shake_elapsed < shake_time:
		await get_tree().physics_frame
		if not is_instance_valid(self) or token != _collapse_serial:
			_stop_shake_audio()
			return
		var shake_dt:float = maxf(get_physics_process_delta_time(),0.001)
		shake_elapsed += shake_dt
		var shake_t:float = clampf(shake_elapsed / maxf(shake_time,0.05),0.0,1.0)
		var shake_strength:float = lerpf(2.2,10.5,shake_t)
		var jitter:float = sin(shake_t * TAU * lerpf(7.0,18.0,shake_t)) * shake_strength
		jitter += sin(shake_t * TAU * 31.0) * shake_strength * 0.22
		_update_sink_visual(0.0,jitter)
	_stop_shake_audio()
	_update_sink_visual(0.0,0.0)

	# 正式倒塌/下沉时播放一次倒塌音。
	# 状态机只在 multiplayer authority 上推进，所以这里显式同步给其他客户端。
	_play_collapse_audio_everywhere(global_position)

	# 开始陷入地面后关闭实体碰撞，避免已经看不见的墙仍然挡人。
	_disable_all_collisions()

	var elapsed:float = 0.0
	var smoke_elapsed:float = smoke_interval
	while elapsed < maxf(sink_duration,0.2):
		await get_tree().physics_frame
		if not is_instance_valid(self) or token != _collapse_serial:
			return
		var dt:float = maxf(get_physics_process_delta_time(),0.001)
		elapsed += dt
		smoke_elapsed += dt
		var progress:float = clampf(elapsed / maxf(sink_duration,0.2),0.0,1.0)
		var shake_strength:float = lerpf(11.0,2.0,progress)
		var jitter:float = sin(progress * TAU * 10.0) * shake_strength
		jitter += sin(progress * TAU * 23.0) * shake_strength * 0.25
		_update_sink_visual(progress,jitter)
		if smoke_elapsed >= maxf(smoke_interval,0.02):
			smoke_elapsed = 0.0
			_spawn_square_smoke(progress)

	_update_sink_visual(1.0,0.0)
	_spawn_square_smoke(1.0,6)
	_deal_collapse_damage()
	# 两侧碎砖动画与倒塌伤害在同一结算帧出现，不再使用固定延迟。
	_play_collapse_side_animation_everywhere()

	await get_tree().create_timer(0.16).timeout
	if is_instance_valid(self):
		Game.free_node(self)


func _start_shake_audio() -> void:
	_stop_shake_audio()
	if AUDIO_WALL_SHAKE == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.name = "WallShakeAudio"
	player.stream = AUDIO_WALL_SHAKE
	player.max_distance = 900.0
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	add_child(player)
	_shake_audio_player = player
	player.play()


func _stop_shake_audio() -> void:
	if _shake_audio_player == null:
		return
	if is_instance_valid(_shake_audio_player):
		_shake_audio_player.stop()
		_shake_audio_player.queue_free()
	_shake_audio_player = null


func _play_collapse_audio_everywhere(where:Vector2) -> void:
	_play_world_one_shot(AUDIO_WALL_COLLAPSE,where)
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		_remote_play_collapse_audio.rpc(where)


@rpc("authority","call_remote","reliable")
func _remote_play_collapse_audio(where:Vector2) -> void:
	_play_world_one_shot(AUDIO_WALL_COLLAPSE,where)


func _play_collapse_side_animation_everywhere() -> void:
	# 这里由倒塌伤害结算点直接调用，因此动画与伤害反馈同一帧开始。
	_start_collapse_side_animation_now()
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		_remote_play_collapse_side_animation.rpc()


@rpc("authority","call_remote","reliable")
func _remote_play_collapse_side_animation() -> void:
	_start_collapse_side_animation_now()


func _start_collapse_side_animation_now() -> void:
	if not is_inside_tree() or _collapse_started == false:
		return
	_start_collapse_side_sprite(_collapse_right_sprite,1.0)
	_start_collapse_side_sprite(_collapse_left_sprite,-1.0)

func _start_collapse_side_sprite(sprite:Sprite2D,direction_sign:float) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	var duration:float = maxf(collapse_fx_duration,0.2)
	var start_pos := Vector2(direction_sign * collapse_fx_side_offset,collapse_fx_y)
	var end_pos := start_pos + Vector2(direction_sign * collapse_fx_outward_distance,0.0)

	sprite.visible = true
	sprite.frame = 0
	sprite.position = start_pos
	sprite.scale = Vector2.ONE * collapse_fx_scale
	sprite.modulate = Color(1.0,1.0,1.0,1.0)

	# 位移与透明度同时进行；Sprite2D 的 3x3 图集按 frame 0..8 播放。
	var motion_tween:Tween = sprite.create_tween()
	motion_tween.set_parallel(true)
	motion_tween.tween_property(sprite,"position",end_pos,duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	motion_tween.tween_property(sprite,"modulate:a",0.0,duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	motion_tween.chain().tween_callback(func() -> void:
		if is_instance_valid(sprite):
			sprite.visible = false
	)

	# 9 帧在同一段时间内播放完。
	var frame_count:int = max(1,sprite.hframes * sprite.vframes)
	var frame_tween:Tween = sprite.create_tween()
	frame_tween.tween_method(
		_set_collapse_sprite_frame.bind(sprite,frame_count),
		0.0,
		float(frame_count) - 0.001,
		duration
	)


func _set_collapse_sprite_frame(value:float,sprite:Sprite2D,frame_count:int) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	sprite.frame = clampi(int(floor(value)),0,frame_count - 1)


func _play_world_one_shot(stream:AudioStream,where:Vector2) -> void:
	if stream == null or not is_inside_tree():
		return
	var world:Node = get_tree().current_scene
	if world == null:
		return

	# 倒塌声是一次性音效；若 WAV 导入设置误开了循环，这里也强制关闭。
	var playback_stream:AudioStream = stream
	if stream is AudioStreamWAV:
		playback_stream = stream.duplicate() as AudioStream
		(playback_stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED

	var player := AudioStreamPlayer2D.new()
	player.name = "WallCollapseAudio"
	player.stream = playback_stream
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.max_distance = 1400.0
	player.attenuation = 0.7
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	world.add_child(player)
	player.global_position = where
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _disable_all_collisions() -> void:
	for layer:int in range(1,33):
		set_collision_layer_value(layer,false)
		set_collision_mask_value(layer,false)
	if collision_shape_2d != null:
		collision_shape_2d.set_deferred("disabled",true)


func _spawn_square_smoke(progress:float,forced_count:int = -1) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var count:int = forced_count if forced_count >= 0 else (2 if progress < 0.7 else 3)
	for _i:int in range(count):
		var smoke := Polygon2D.new()
		var half_size:float = randf_range(1.8,3.8)
		smoke.polygon = PackedVector2Array([
			Vector2(-half_size,-half_size),Vector2(half_size,-half_size),
			Vector2(half_size,half_size),Vector2(-half_size,half_size)
		])
		var shade:float = randf_range(0.48,0.72)
		smoke.color = Color(shade,shade,shade,randf_range(0.45,0.72))
		smoke.z_index = 7
		world.add_child(smoke)
		smoke.global_position = global_position + Vector2(randf_range(-10.0,10.0),randf_range(8.0,14.0))
		smoke.rotation = randf_range(-0.4,0.4)

		var travel:Vector2 = Vector2(randf_range(-14.0,14.0),randf_range(-20.0,-8.0))
		var duration:float = randf_range(0.38,0.72)
		var tween:Tween = smoke.create_tween()
		tween.set_parallel(true)
		tween.tween_property(smoke,"position",smoke.position + travel,duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(smoke,"rotation",smoke.rotation + randf_range(-1.1,1.1),duration)
		tween.tween_property(smoke,"scale",Vector2.ONE * randf_range(1.4,2.2),duration)
		tween.tween_property(smoke,"modulate:a",0.0,duration)
		tween.chain().tween_callback(smoke.queue_free)


func _deal_collapse_damage() -> void:
	# 最终只结算一次圆形区域伤害；建筑工人和友军不会受到自己的墙伤害。
	var radius:float = maxf(collapse_radius,1.0)
	var radius_sq:float = radius * radius
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if target == self or target == builder_owner or target.health <= 0:
			continue
		if _is_friendly(target):
			continue
		if target.global_position.distance_squared_to(global_position) > radius_sq:
			continue

		var before_health:float = float(target.health)
		var collapse_damage_amount:float = builder_owner.attack_damage(collapse_damage_multiplier) if builder_owner != null and is_instance_valid(builder_owner) else 0.0
		var accepted:bool = target.receive_spatial_damage(
			collapse_damage_amount,
			{
				"shape":"circle",
				"center":global_position,
				"radius":radius,
				"point":target.global_position,
				"source":self
			},
			false,
			false
		)
		var health_damage:float = maxf(before_health - float(target.health),0.0)
		if health_damage > 0.0:
			_play_collapse_collision_damage_audio(health_damage)
		if accepted and collapse_knockback_distance > 0.0:
			var push_dir:Vector2 = target.global_position - global_position
			if push_dir.length_squared() <= 0.000001:
				push_dir = Vector2.from_angle(randf_range(0.0,TAU))
			target.apply_knockback(
				push_dir.normalized(),
				collapse_knockback_distance,
				collapse_knockback_speed,
				0.0,
				0.0,
				{"source":builder_owner if builder_owner != null else self,"stop_on_character":true}
			)


func _play_collapse_collision_damage_audio(actual_damage:float) -> void:
	if actual_damage <= 0.0:
		return
	# 与项目里普通角色“碰撞伤害真正扣到生命值”使用同一命中音：balls_hit1。
	# create_new_audio=true 让倒塌同时砸到多名角色时每次命中都拥有独立 voice。
	var params:Dictionary = {
		"volume": clampf(actual_damage - 12.0,-100.0,0.0)
	}
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc("balls_hit1",params,true,true)
	else:
		Audios.play_sfx("balls_hit1",params,true,true)


func _is_friendly(target:ball) -> bool:
	if target == null:
		return true
	if Team.is_empty() or target.Team.is_empty():
		return false
	return Team == target.Team
