extends ball

const SHOUT_WAVE_SCRIPT = preload("res://scripts/effects/影子_吼叫波.gd")
const BODY_SHOUT_AUDIO:AudioStream = preload("res://audio/characters/影子/喊叫.mp3")
const SHADOW_SHOUT_AUDIO:AudioStream = preload("res://audio/characters/影子/喊叫_影子粗慢.wav")

# ============================================================
# 影子（碰撞伤害 + 吼叫攻击版）
# - 本体与延迟影子都拥有接触碰撞伤害；影子使用独立 Area2D 结算。
# - 普攻为前方圆弧声波：声波向外扩散，命中一次并击退敌人。
# - 影子保持约 shadow_delay 秒的动作延迟；本体吼叫后，影子也会在延迟后
#   从它当时所在的位置、沿同一个攻击方向重复一次吼叫。
# ============================================================

@export_category("影子 - 外观（可留空）")
@export var body_texture:Texture2D
@export var body_shout_texture:Texture2D
@export var shadow_texture:Texture2D
@export var shadow_shout_texture:Texture2D

@export_category("影子 - 延迟分身")
@export_range(0.1,4.0,0.05) var shadow_delay:float = 1.10
@export_range(0.01,0.2,0.01) var history_sample_interval:float = 0.04
@export_range(0.05,1.0,0.05) var shadow_alpha:float = 0.50
@export_range(0.0,3.0,0.05) var shadow_collision_damage_multiplier:float = 1.0
@export_range(1.0,1.5,0.01) var shadow_damage_area_scale:float = 1.12
@export_range(0.0,24.0,1.0) var shadow_contact_padding:float = 6.0
@export_range(0.05,1.0,0.01) var shadow_contact_rehit_cooldown:float = 0.45

@export_category("影子 - 吼叫攻击")
@export_range(30.0,260.0,2.0) var shout_range:float = 100.0
@export_range(10.0,170.0,1.0) var shout_half_angle_degrees:float = 55.0
@export_range(0.08,1.0,0.01) var shout_wave_duration:float = 0.34
@export_range(4.0,50.0,1.0) var shout_wave_thickness:float = 16.0
@export_range(0.0,3.0,0.05) var shout_damage_multiplier:float = 1.0
@export_range(0.0,200.0,2.0) var shout_knockback_distance:float = 40.0
@export_range(80.0,1400.0,10.0) var shout_knockback_speed:float = 520.0
@export_range(0.05,1.0,0.01) var shout_attack_lock_time:float = 0.38
@export var shout_color:Color = Color(0.88,0.93,1.0,0.72)
@export var shadow_shout_color:Color = Color(0.46,0.45,0.62,0.58)
@export_range(-30.0,12.0,0.5) var shout_audio_volume_db:float = -1.0
@export_range(80.0,2000.0,20.0) var shout_audio_max_distance:float = 850.0

var _history:Array[Dictionary] = []
var _sample_left:float = 0.0
var _shadow_world_position:Vector2 = Vector2.ZERO

var _shadow_body:AnimatableBody2D = null
var _shadow_sprite:Sprite2D = null
var _shadow_collision:CollisionShape2D = null
var _shadow_damage_area:Area2D = null
var _shadow_damage_collision:CollisionShape2D = null
var _shadow_active:bool = false
var _shadow_previous_world_position:Vector2 = Vector2.ZERO
var _shadow_has_previous_world_position:bool = false
var _shadow_contact_next_hit_msec:Dictionary = {}
var _attack_serial:int = 0
var _body_pose_serial:int = 0
var _shadow_pose_serial:int = 0


func _ready() -> void:
	# 本体使用 ball.gd 的标准接触伤害；影子另由独立 Area2D 结算。
	Has_Collision_Damage = true
	Can_Attack = true
	super._ready()
	_auto_load_textures()

	if image is Sprite2D and body_texture != null:
		(image as Sprite2D).texture = body_texture
		_refit_visual_only_now()

	_create_shadow_proxy()
	tree_exiting.connect(_cleanup_shadow_proxy,CONNECT_ONE_SHOT)


func has_collision_damage() -> bool:
	return true


func _auto_load_textures() -> void:
	if body_texture == null:
		body_texture = _try_load_texture("res://Images/characters/人物/影子/懦夫_紧张.png")
	if body_shout_texture == null:
		body_shout_texture = _try_load_texture("res://Images/characters/人物/影子/懦夫_大喊.png")
	if shadow_texture == null:
		shadow_texture = _try_load_texture("res://Images/characters/人物/影子/影子怪物_紧张.png")
	if shadow_shout_texture == null:
		shadow_shout_texture = _try_load_texture("res://Images/characters/人物/影子/影子怪物_大喊.png")


func _try_load_texture(path:String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var resource:Resource = ResourceLoader.load(path)
	return resource as Texture2D if resource is Texture2D else null


func tick_physics(state:State,delta:float) -> void:
	_sample_left -= delta
	if _sample_left <= 0.0:
		_sample_left += maxf(history_sample_interval,0.01)
		_record_history_sample()
		_trim_history()

	_update_delayed_shadow()
	super.tick_physics(state,delta)


func Attack() -> void:
	super()
	if state_machine.current_state == State.Die or not is_multiplayer_authority():
		return
	if is_damage_output_disabled():
		Attacking = false
		return

	var attack_direction:Vector2 = direction.normalized() if direction.length_squared() > 0.000001 else Vector2.RIGHT
	var target:Node = return_reusable_combat_target()
	if target is Node2D and is_instance_valid(target):
		var to_target:Vector2 = combat_target_position(target) - global_position
		if to_target.length_squared() > 0.000001:
			attack_direction = to_target.normalized()

	direction = attack_direction
	Attacking = true
	_attack_serial += 1
	var serial:int = _attack_serial

	# 本体立刻吼叫。
	_start_shout_wave(global_position,attack_direction,false)
	# 影子不会“锁敌”；只记住本体这一刻的攻击方向，延迟后原样模仿。
	_queue_shadow_mimic(serial,attack_direction)

	await get_tree().create_timer(maxf(shout_attack_lock_time,0.05)).timeout
	if is_instance_valid(self) and serial == _attack_serial:
		Attacking = false


func _queue_shadow_mimic(serial:int,attack_direction:Vector2) -> void:
	await get_tree().create_timer(maxf(shadow_delay,0.05)).timeout
	if not is_instance_valid(self):
		return
	if health <= 0 or state_machine == null or state_machine.current_state == State.Die:
		return
	# 即使本体此时已经进行了下一次攻击，也允许上一发的影子按自己的延迟完成模仿。
	# serial 仅用于保留调试语义，不用于取消合法的延迟回声。
	var _unused_serial:int = serial
	if not _shadow_active:
		return
	_start_shout_wave(_shadow_world_position,attack_direction,true)


func _start_shout_wave(origin:Vector2,attack_direction:Vector2,is_shadow_echo:bool) -> void:
	var normalized_direction:Vector2 = attack_direction.normalized() if attack_direction.length_squared() > 0.000001 else Vector2.RIGHT
	_show_shout_everywhere(origin,normalized_direction,is_shadow_echo)
	_run_shout_hit_scan(origin,normalized_direction,is_shadow_echo)


func _run_shout_hit_scan(origin:Vector2,attack_direction:Vector2,is_shadow_echo:bool) -> void:
	var started_msec:int = Time.get_ticks_msec()
	var duration_value:float = maxf(shout_wave_duration,0.05)
	var hit_ids:Dictionary = {}

	while is_instance_valid(self):
		if health <= 0 or state_machine == null or state_machine.current_state == State.Die:
			return

		var elapsed:float = float(Time.get_ticks_msec() - started_msec) / 1000.0
		var progress:float = clampf(elapsed / duration_value,0.0,1.0)
		var wave_radius:float = lerpf(5.0,maxf(shout_range,1.0),progress)
		_hit_targets_on_wave(origin,attack_direction,wave_radius,hit_ids,is_shadow_echo)

		if progress >= 1.0:
			break
		await get_tree().physics_frame


func _hit_targets_on_wave(
	origin:Vector2,
	attack_direction:Vector2,
	wave_radius:float,
	hit_ids:Dictionary,
	is_shadow_echo:bool
) -> void:
	if not is_multiplayer_authority() or is_damage_output_disabled():
		return

	var half_angle_radians:float = deg_to_rad(clampf(shout_half_angle_degrees,5.0,175.0))
	var band_half_width:float = maxf(shout_wave_thickness * 0.65,8.0)
	var outgoing:float = attack_damage(maxf(shout_damage_multiplier,0.0))

	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if not _is_valid_enemy(target):
			continue

		var target_id:int = int(target.get_instance_id())
		if hit_ids.has(target_id):
			continue

		var to_target:Vector2 = target.global_position - origin
		var distance_to_target:float = to_target.length()
		if distance_to_target > maxf(shout_range,1.0) + band_half_width:
			continue
		if absf(distance_to_target - wave_radius) > band_half_width:
			continue

		var target_direction:Vector2 = to_target.normalized() if distance_to_target > 0.001 else attack_direction
		var angular_error:float = absf(wrapf(target_direction.angle() - attack_direction.angle(),-PI,PI))
		if angular_error > half_angle_radians:
			continue

		hit_ids[target_id] = true
		_deal_shout_hit(target,origin,attack_direction,outgoing,is_shadow_echo)


func _deal_shout_hit(
	target:ball,
	origin:Vector2,
	attack_direction:Vector2,
	outgoing:float,
	is_shadow_echo:bool
) -> void:
	if target == null or not is_instance_valid(target):
		return

	# 冲击波真正撞到角色时，沿用角色正常“命中造成伤害”的音效。
	# 与 ball.gd 的普通碰撞伤害规则一致：只有伤害能穿过当前格挡时才播命中声。
	if outgoing > 0.0 and (target.block < outgoing or ignore_block):
		if Unique_Hit_Audio != null:
			play_unique_audio(Character_Audio_Slot.Hit,true)
		elif Hit_Audio != "":
			Audios.play_sfx.rpc(Hit_Audio,{volume = clampf(outgoing - 12.0,-100.0,0.0)},true)

	if outgoing > 0.0:
		target.receive_spatial_damage(
			outgoing,
			{
				"shape":"sector",
				"origin":origin,
				"direction":attack_direction,
				"radius":maxf(shout_range,1.0) + maxf(shout_wave_thickness * 0.65,8.0),
				"half_angle_degrees":clampf(shout_half_angle_degrees,5.0,175.0),
				"source":self,
			},
			false
		)

	if shout_knockback_distance > 0.0:
		var push_direction:Vector2 = target.global_position - origin
		if push_direction.length_squared() <= 0.000001:
			push_direction = attack_direction
		target.apply_knockback(
			push_direction.normalized(),
			shout_knockback_distance,
			shout_knockback_speed,
			0.20,
			0.0,
			{
				"source": self,
				"max_wall_bounces": 1,
				"stop_on_character": true,
				"smooth_motion": true,
			}
		)

	if get_tree().current_scene != null:
		get_tree().current_scene.camera_shake_amount += maxf(outgoing,10.0) * (0.20 if is_shadow_echo else 0.26)


func _show_shout_everywhere(origin:Vector2,attack_direction:Vector2,is_shadow_echo:bool) -> void:
	_play_shout_pose_local(is_shadow_echo)
	_spawn_shout_visual_local(origin,attack_direction,is_shadow_echo)
	_play_shout_audio_local(origin,is_shadow_echo)
	if multiplayer.has_multiplayer_peer():
		_remote_show_shout_visual.rpc(origin,attack_direction,is_shadow_echo)


@rpc("authority","call_remote","unreliable")
func _remote_show_shout_visual(origin:Vector2,attack_direction:Vector2,is_shadow_echo:bool) -> void:
	_play_shout_pose_local(is_shadow_echo)
	_spawn_shout_visual_local(origin,attack_direction,is_shadow_echo)
	_play_shout_audio_local(origin,is_shadow_echo)


func _play_shout_pose_local(is_shadow_echo:bool) -> void:
	if is_shadow_echo:
		_shadow_pose_serial += 1
		var shadow_serial:int = _shadow_pose_serial
		if _shadow_sprite != null and is_instance_valid(_shadow_sprite) and shadow_shout_texture != null:
			_shadow_sprite.texture = shadow_shout_texture
		_restore_shadow_pose_after(shadow_serial)
		return

	_body_pose_serial += 1
	var body_serial:int = _body_pose_serial
	if image is Sprite2D and body_shout_texture != null:
		(image as Sprite2D).texture = body_shout_texture
	_restore_body_pose_after(body_serial)


func _restore_body_pose_after(serial:int) -> void:
	await get_tree().create_timer(maxf(shout_attack_lock_time,0.05)).timeout
	if not is_instance_valid(self) or serial != _body_pose_serial:
		return
	if image is Sprite2D and body_texture != null:
		(image as Sprite2D).texture = body_texture


func _restore_shadow_pose_after(serial:int) -> void:
	await get_tree().create_timer(maxf(shout_attack_lock_time,0.05)).timeout
	if not is_instance_valid(self) or serial != _shadow_pose_serial:
		return
	if _shadow_sprite != null and is_instance_valid(_shadow_sprite) and shadow_texture != null:
		_shadow_sprite.texture = shadow_texture


func _play_shout_audio_local(origin:Vector2,is_shadow_echo:bool) -> void:
	var parent:Node = get_tree().current_scene
	if parent == null:
		return
	var stream:AudioStream = SHADOW_SHOUT_AUDIO if is_shadow_echo else BODY_SHOUT_AUDIO
	if stream == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.name = "ShadowEchoShoutAudio" if is_shadow_echo else "ShadowBodyShoutAudio"
	player.stream = stream
	player.global_position = origin
	player.volume_db = shout_audio_volume_db - (1.5 if is_shadow_echo else 0.0)
	player.pitch_scale = randf_range(0.98,1.02)
	player.max_distance = maxf(shout_audio_max_distance,80.0)
	player.attenuation = 1.0
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	parent.add_child(player)
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _spawn_shout_visual_local(origin:Vector2,attack_direction:Vector2,is_shadow_echo:bool) -> void:
	var parent:Node = get_tree().current_scene
	if parent == null:
		return
	var effect:Node2D = SHOUT_WAVE_SCRIPT.new()
	effect.name = "ShadowShoutWave"
	effect.z_index = z_index + 1
	parent.add_child(effect)
	var color_value:Color = shadow_shout_color if is_shadow_echo else shout_color
	effect.call(
		"configure",
		origin,
		attack_direction,
		shout_range,
		shout_half_angle_degrees,
		shout_wave_duration,
		shout_wave_thickness,
		color_value
	)


func _record_history_sample() -> void:
	var image_transform:Transform2D = global_transform
	var image_flip_h:bool = false
	if image is Node2D:
		image_transform = (image as Node2D).global_transform
	if image is Sprite2D:
		image_flip_h = (image as Sprite2D).flip_h

	_history.append({
		"time": Time.get_ticks_msec(),
		"body_transform": global_transform,
		"image_transform": image_transform,
		"flip_h": image_flip_h,
	})


func _trim_history() -> void:
	var keep_after:int = Time.get_ticks_msec() - int(round((shadow_delay + 1.0) * 1000.0))
	while _history.size() > 2 and int(_history[1]["time"]) < keep_after:
		_history.pop_front()


func _update_delayed_shadow() -> void:
	if _history.is_empty() or _shadow_body == null or not is_instance_valid(_shadow_body):
		_set_shadow_active(false)
		return

	var wanted:int = Time.get_ticks_msec() - int(round(maxf(shadow_delay,0.0) * 1000.0))
	var chosen:Dictionary = {}
	for sample:Dictionary in _history:
		if int(sample["time"]) <= wanted:
			chosen = sample
		else:
			break

	if chosen.is_empty():
		_set_shadow_active(false)
		return

	_set_shadow_active(true)
	var sampled_body_transform:Transform2D = chosen["body_transform"]
	var sampled_image_transform:Transform2D = chosen["image_transform"]
	var new_shadow_position:Vector2 = sampled_body_transform.origin
	var sweep_from:Vector2 = _shadow_previous_world_position if _shadow_has_previous_world_position else new_shadow_position

	_shadow_world_position = new_shadow_position
	_shadow_body.global_transform = sampled_body_transform
	if _shadow_sprite != null and is_instance_valid(_shadow_sprite):
		_shadow_sprite.global_transform = sampled_image_transform
		_shadow_sprite.flip_h = bool(chosen.get("flip_h",false))

	# Area2D 的 area_entered 只看物理帧里真正发生的重叠。延迟影子是按历史样本
	# 直接移动到新位置的，速度较快时可能一帧跨过敌人；而实体碰撞又会先把角色弹开，
	# 于是会出现“明明贴着影子反弹，却没有触发伤害”的情况。
	# 这里额外做一次上一帧 -> 当前帧的扫掠接触检测，保证擦边、快速穿过和持续贴身都能命中。
	_scan_shadow_swept_contacts(sweep_from,new_shadow_position)
	_shadow_previous_world_position = new_shadow_position
	_shadow_has_previous_world_position = true


func _create_shadow_proxy() -> void:
	if image == null or not is_instance_valid(image):
		return
	var parent:Node = get_tree().current_scene
	if parent == null:
		return

	var body := AnimatableBody2D.new()
	body.name = str(name) + "_ShadowBody"
	body.collision_layer = collision_layer
	body.collision_mask = collision_mask
	body.sync_to_physics = true
	body.z_index = z_index - 1
	body.global_transform = global_transform
	body.visible = false
	parent.add_child(body)
	body.add_to_group("ShadowVisual")
	body.add_to_group("BattleTransient")
	_shadow_body = body

	_shadow_body.add_collision_exception_with(self)
	add_collision_exception_with(_shadow_body)
	_create_shadow_collision()
	_create_shadow_damage_area()
	_create_shadow_sprite()
	_set_shadow_active(false)


func _create_shadow_collision() -> void:
	if _shadow_body == null:
		return
	var source_collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if source_collision == null or source_collision.shape == null:
		return

	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	collision.transform = source_collision.transform
	collision.shape = source_collision.shape.duplicate(true) as Shape2D
	collision.disabled = true
	_shadow_body.add_child(collision)
	_shadow_collision = collision


func _create_shadow_damage_area() -> void:
	if _shadow_body == null:
		return
	var source_collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if source_collision == null or source_collision.shape == null:
		return

	var area := Area2D.new()
	area.name = "ShadowDamageArea"
	area.collision_layer = 0
	area.collision_mask = 0
	# ball.gd 保证正常角色 hurtbox 位于碰撞层 2。
	area.set_collision_mask_value(2,true)
	area.monitoring = false
	area.monitorable = false
	_shadow_body.add_child(area)

	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	collision.transform = source_collision.transform
	collision.scale *= Vector2.ONE * maxf(shadow_damage_area_scale,1.0)
	collision.shape = source_collision.shape.duplicate(true) as Shape2D
	collision.disabled = false
	area.add_child(collision)

	area.area_entered.connect(_on_shadow_damage_area_entered)
	_shadow_damage_area = area
	_shadow_damage_collision = collision


func _on_shadow_damage_area_entered(area:Area2D) -> void:
	if not area is hurtbox:
		return

	var parent_node:Node = area.get_parent()
	if not parent_node is ball:
		return
	_try_deal_shadow_contact_damage(parent_node as ball)


func _scan_shadow_swept_contacts(from_position:Vector2,to_position:Vector2) -> void:
	if not _shadow_active or not is_multiplayer_authority() or is_damage_output_disabled():
		return

	var shadow_radius:float = _collision_radius_from_shape(_shadow_damage_collision)
	if shadow_radius <= 0.0:
		shadow_radius = 18.0

	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if not _is_valid_enemy(target):
			continue

		var nearest:Vector2 = _closest_point_on_segment(target.global_position,from_position,to_position)
		var target_radius:float = _collision_radius_for_ball(target)
		var allowed:float = shadow_radius + target_radius + maxf(shadow_contact_padding,0.0)
		if target.global_position.distance_squared_to(nearest) <= allowed * allowed:
			_try_deal_shadow_contact_damage(target)


func _play_shadow_contact_hit_audio(outgoing:float,target:ball) -> void:
	if outgoing <= 0.0 or target == null or not is_instance_valid(target):
		return

	# 与 ball.gd 的普通人物撞击伤害共用同一套命中音效。
	# 默认 Hit_Audio 是 balls_hit1；如果角色以后配置独立 Hit 音效，也自动沿用。
	if Unique_Hit_Audio != null:
		play_unique_audio(Character_Audio_Slot.Hit,true)
	elif Hit_Audio != "":
		Audios.play_sfx.rpc(
			Hit_Audio,
			{volume = clampf(outgoing - 12.0,-100.0,0.0)},
			true
		)


func _try_deal_shadow_contact_damage(target:ball) -> void:
	if not _shadow_active or not is_multiplayer_authority() or is_damage_output_disabled():
		return
	if not _is_valid_enemy(target):
		return

	var target_id:int = int(target.get_instance_id())
	var now_msec:int = Time.get_ticks_msec()
	var next_allowed:int = int(_shadow_contact_next_hit_msec.get(target_id,0))
	if now_msec < next_allowed:
		return

	var outgoing:float = attack_damage(maxf(shadow_collision_damage_multiplier,0.0))
	if outgoing <= 0.0:
		return

	_shadow_contact_next_hit_msec[target_id] = now_msec + int(round(maxf(shadow_contact_rehit_cooldown,0.05) * 1000.0))
	var health_before:float = float(target.health)
	var contact_radius:float = maxf(_collision_radius_for_ball(self),2.0)
	target.receive_spatial_damage(
		outgoing,
		{"shape":"circle","center":global_position,"radius":contact_radius,"source":self},
		false
	)
	# 只有真的造成生命伤害时才播“人物撞击造成伤害”的命中声；
	# 被完整格挡/免疫时不额外冒出伤害音。
	if float(target.health) < health_before:
		_play_shadow_contact_hit_audio(outgoing,target)
	if get_tree().current_scene != null:
		get_tree().current_scene.camera_shake_amount += maxf(outgoing,8.0) * 0.22


func _collision_radius_for_ball(target:ball) -> float:
	if target == null or not is_instance_valid(target):
		return 12.0
	var shape_node:CollisionShape2D = target.get_node_or_null("CollisionShape2D") as CollisionShape2D
	return _collision_radius_from_shape(shape_node)


func _collision_radius_from_shape(shape_node:CollisionShape2D) -> float:
	if shape_node == null or shape_node.shape == null:
		return 12.0

	var scale_value:Vector2 = shape_node.global_scale.abs()
	var shape_value:Shape2D = shape_node.shape
	if shape_value is CircleShape2D:
		return (shape_value as CircleShape2D).radius * maxf(scale_value.x,scale_value.y)
	if shape_value is RectangleShape2D:
		var world_size:Vector2 = (shape_value as RectangleShape2D).size * scale_value
		return maxf(world_size.x,world_size.y) * 0.5
	if shape_value is CapsuleShape2D:
		var capsule:CapsuleShape2D = shape_value as CapsuleShape2D
		return maxf(capsule.height * scale_value.y * 0.5,capsule.radius * scale_value.x)
	return 12.0


func _closest_point_on_segment(point:Vector2,a:Vector2,b:Vector2) -> Vector2:
	var ab:Vector2 = b - a
	var len_sq:float = ab.length_squared()
	if len_sq <= 0.000001:
		return a
	var t:float = clampf((point - a).dot(ab) / len_sq,0.0,1.0)
	return a + ab * t


func _create_shadow_sprite() -> void:
	if _shadow_body == null or not image is Sprite2D:
		return

	var source_sprite := image as Sprite2D
	var sprite := source_sprite.duplicate() as Sprite2D
	if sprite == null:
		return

	sprite.name = "ShadowImage"
	if shadow_texture != null:
		var old_texture:Texture2D = sprite.texture
		sprite.texture = shadow_texture
		_match_replacement_texture_scale(sprite,old_texture,shadow_texture)

	sprite.modulate = Color(1.0,1.0,1.0,shadow_alpha)
	sprite.material = null
	_shadow_body.add_child(sprite)
	_shadow_sprite = sprite


func _match_replacement_texture_scale(sprite:Sprite2D,old_texture:Texture2D,new_texture:Texture2D) -> void:
	if sprite == null or old_texture == null or new_texture == null:
		return
	var old_size:Vector2 = old_texture.get_size()
	var new_size:Vector2 = new_texture.get_size()
	var old_longest:float = maxf(old_size.x,old_size.y)
	var new_longest:float = maxf(new_size.x,new_size.y)
	if old_longest <= 0.0 or new_longest <= 0.0:
		return
	var ratio:float = old_longest / new_longest
	sprite.scale *= ratio


func _set_shadow_active(active:bool) -> void:
	if _shadow_active == active:
		return
	_shadow_active = active
	if not active:
		_shadow_has_previous_world_position = false
		_shadow_contact_next_hit_msec.clear()
	if _shadow_body != null and is_instance_valid(_shadow_body):
		_shadow_body.visible = active
	if _shadow_collision != null and is_instance_valid(_shadow_collision):
		_shadow_collision.set_deferred("disabled",not active)
	if _shadow_damage_area != null and is_instance_valid(_shadow_damage_area):
		_shadow_damage_area.set_deferred("monitoring",active)


func _refit_visual_only_now() -> void:
	var auto_fit:Node = get_node_or_null("CharacterAutoFit")
	if auto_fit != null and auto_fit.has_method("apply_visual_fit_only"):
		auto_fit.call("apply_visual_fit_only")


func _is_valid_enemy(target:ball) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(self,target): return false # 皓宸复制品及其产物不把己方选为目标
	if target == null or not is_instance_valid(target) or target == self:
		return false
	if not target.is_combat_targetable():
		return false
	if Team != "" and target.Team == Team:
		return false
	return true


func _cleanup_shadow_proxy() -> void:
	if _shadow_body != null and is_instance_valid(_shadow_body):
		_shadow_body.queue_free()
	_shadow_body = null
	_shadow_sprite = null
	_shadow_collision = null
	_shadow_damage_area = null
	_shadow_damage_collision = null
	_shadow_active = false


func Die() -> void:
	_cleanup_shadow_proxy()
	super()
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(self):
		Game.free_node(self)
