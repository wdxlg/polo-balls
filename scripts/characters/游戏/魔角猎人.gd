extends ball

const BLACK_BULLET_SCENE:PackedScene = preload("res://scenes/shooter/魔角猎人_黑弹.tscn")
const SMALL_BOMB_SCENE:PackedScene = preload("res://scenes/effects/魔角猎人_小爆弹.tscn")
const MARK_SCRIPT:Script = preload("res://scripts/effects/魔角猎人_标记.gd")
const EXPLOSION_EFFECT_SCENE:PackedScene = preload("res://scenes/effects/魔角猎人_爆炸特效.tscn")
const CHARACTER_TEXTURE:Texture2D = preload("res://Images/characters/游戏/魔角猎人/人物.png")
const WEAPON_TEXTURE:Texture2D = preload("res://Images/characters/游戏/魔角猎人/武器.png")
const BURN_SFX:AudioStream = preload("res://audio/status/debuff/烫伤.wav")
const FIRE_SFX:AudioStream = preload("res://audio/characters/魔角猎人/发射.mp3")
const WEAPON_SPIN_SFX:AudioStream = preload("res://audio/characters/魔角猎人/转枪.mp3")

@export_category("魔角猎人 - 普攻黑弹")
@export_range(50.0,1200.0,10.0) var projectile_speed:float = 430.0
@export_range(50.0,1200.0,10.0) var projectile_max_distance:float = 520.0
@export_range(0.1,5.0,0.05) var projectile_damage_multiplier:float = 1.0
@export_range(2.0,20.0,0.5) var projectile_visual_radius:float = 5.0
@export_range(0.0,40.0,0.5) var muzzle_offset:float = 20.0
@export_range(0.02,0.40,0.01) var attack_recovery:float = 0.10

@export_category("魔角猎人 - 标记 / 灼烧")
@export_range(0.2,20.0,0.1) var mark_duration:float = 4.5
@export_range(0.05,2.0,0.05) var burn_tick_interval:float = 0.5
@export_range(0.0,100.0,0.5) var burn_tick_damage_per_stack:float = 5.0
@export_range(1,12,1) var mark_points_per_stage:int = 3
@export_range(0,12,1) var normal_attack_mark_points:int = 2
@export_range(0,12,1) var small_bomb_mark_points:int = 1
@export_range(0.05,1.0,0.01) var mark_overload_flash_duration:float = 0.26
@export_range(0.0,10.0,0.05) var mark_overload_damage_multiplier:float = 2.4
@export_range(0.0,180.0,1.0) var mark_overload_knockback_distance:float = 78.0
@export_range(0.0,1600.0,10.0) var mark_overload_knockback_speed:float = 700.0

@export_category("魔角猎人 - 爆弹窗口")
@export_range(0.1,15.0,0.1) var bomb_window_duration:float = 4.0
@export_range(0,12,1) var small_bomb_count:int = 4
@export_range(0.0,160.0,1.0) var small_bomb_min_distance:float = 24.0
@export_range(0.0,220.0,1.0) var small_bomb_max_distance:float = 58.0
@export_range(0.1,2.0,0.05) var small_bomb_flight_duration:float = 0.56
@export_range(0.05,1.5,0.01) var small_bomb_shake_duration:float = 0.42
@export_range(8.0,160.0,1.0) var small_bomb_explosion_radius:float = 42.0
@export_range(0.0,5.0,0.05) var small_bomb_damage_multiplier:float = 2.00

@export_category("魔角猎人 - 武器视觉")
@export var weapon_texture:Texture2D = WEAPON_TEXTURE
@export_range(0.2,5.0,0.05) var weapon_visual_scale:float = 2.15
@export var weapon_local_offset:Vector2 = Vector2(13.0,1.0)
@export_range(0.05,0.60,0.01) var weapon_turn_duration:float = 0.17 # 持续瞄准的缓动时间尺度：角差越大转得越快，接近目标时自然减速
@export_range(0.0,20.0,0.25) var weapon_recoil_distance:float = 6.5
@export_range(0.02,0.25,0.01) var weapon_recoil_kick_duration:float = 0.04
@export_range(0.03,0.35,0.01) var weapon_recoil_return_duration:float = 0.14
@export_range(0.0,12.0,0.25) var weapon_recoil_shake_degrees:float = 4.0
@export_range(1.0,3.0,0.05) var enhanced_recoil_multiplier:float = 2.15
@export_range(0.0,30.0,0.5) var enhanced_body_visual_recoil_distance:float = 7.0
@export_range(0.0,8.0,0.25) var enhanced_body_visual_shake_distance:float = 2.0
@export_range(0.0,60.0,0.5) var enhanced_body_physical_recoil_distance:float = 16.0
@export_range(50.0,1000.0,10.0) var enhanced_body_physical_recoil_speed:float = 420.0
@export_range(0.02,0.25,0.01) var enhanced_body_recoil_kick_duration:float = 0.05
@export_range(0.03,0.45,0.01) var enhanced_body_recoil_return_duration:float = 0.15

@export_category("魔角猎人 - 发射 / 印记转枪音效")
@export_range(-24.0,8.0,0.5) var fire_sfx_volume_db:float = -1.0
@export_range(-24.0,8.0,0.5) var enhanced_fire_sfx_volume_db:float = 1.0
@export_range(1.0,6.0,0.25) var mark_weapon_spin_turns:float = 3.0
@export_range(0.35,3.0,0.05) var mark_weapon_spin_duration:float = 1.35
@export_range(-12.0,16.0,0.5) var mark_weapon_spin_sfx_volume_db:float = 10.0
@export_range(0.05,1.5,0.05) var mark_weapon_spin_sfx_fade_duration:float = 0.38

@onready var graphics_node:Node2D = get_node_or_null("Graphics") as Node2D
@onready var weapon_pivot:Node2D = get_node_or_null("WeaponPivot") as Node2D
@onready var weapon_sprite:Sprite2D = get_node_or_null("WeaponPivot/Weapon") as Sprite2D

var _last_aim_direction:Vector2 = Vector2.RIGHT
var _bomb_window_until_msec:int = 0
var _rng := RandomNumberGenerator.new()
var _weapon_recoil_tween:Tween = null
var _weapon_shake_tween:Tween = null
var _body_recoil_tween:Tween = null
var _last_body_facing_sign:int = 1
var _weapon_rest_position:Vector2 = Vector2.ZERO
var _graphics_rest_position:Vector2 = Vector2.ZERO
var _weapon_spin_active:bool = false
var _weapon_spin_elapsed:float = 0.0
var _weapon_spin_start_angle:float = 0.0
var _weapon_spin_target:ball = null
var _weapon_spin_fallback_position:Vector2 = Vector2.ZERO
var _weapon_spin_audio_player:AudioStreamPlayer2D = null
var _weapon_spin_audio_tween:Tween = null


func _ready() -> void:
	Has_Collision_Damage = false
	Can_Attack = true
	Can_Skill = false
	Health_Restore = 0
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rng.seed = Game.battle_rng_seed_or("scripts/characters/游戏/魔角猎人.gd:_rng",int(Time.get_ticks_usec()) ^ int(get_instance_id()))

	if image is Sprite2D:
		var body_sprite:Sprite2D = image as Sprite2D
		body_sprite.texture = CHARACTER_TEXTURE
		body_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		body_sprite.visible = true

	if weapon_sprite != null:
		weapon_sprite.texture = weapon_texture if weapon_texture != null else WEAPON_TEXTURE
		weapon_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		weapon_sprite.scale = Vector2.ONE * maxf(weapon_visual_scale,0.05)
		weapon_sprite.position = weapon_local_offset
		weapon_sprite.rotation = 0.0
		weapon_sprite.flip_v = false
		weapon_sprite.visible = true
		_weapon_rest_position = weapon_local_offset

	if graphics_node != null:
		_graphics_rest_position = graphics_node.position

	super._ready()
	_last_body_facing_sign = _resolve_body_facing_sign()
	_snap_weapon_to_direction(_last_aim_direction)


func _process(delta:float) -> void:
	if weapon_pivot == null or weapon_sprite == null:
		return

	# 枪始终追踪“当前会射击的方向”，而不是等到 Attack() 才转。
	# AI 角色持续瞄准最近的有效敌人；玩家控制时则持续跟随玩家的瞄准输入。
	# 人物自身左右转身不参与枪的目标角计算，所以身体翻面不会把枪强行拉到水平朝向。
	if _weapon_spin_active:
		_update_mark_weapon_spin(delta)
	else:
		var aim:Vector2 = _current_weapon_aim_vector()
		if aim.length_squared() > 0.000001:
			_last_aim_direction = aim.normalized()
			_track_weapon_to_direction(_last_aim_direction,delta)

	# 这个值只保留给身体朝向相关逻辑使用，不再驱动 WeaponPivot。
	_last_body_facing_sign = _resolve_body_facing_sign()


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

	var aim:Vector2 = _current_weapon_aim_vector()
	if aim.length_squared() <= 0.000001:
		Attacking = false
		return

	Attacking = true
	# 开火瞬间重新读取一次当前目标方向。平时枪已经持续追踪，因此这里不再暂停攻击等待一次独立转枪动画。
	var shot_direction:Vector2 = aim.normalized()
	_last_aim_direction = shot_direction

	var enhanced_shot:bool = is_magic_horn_bomb_window_active()
	_spawn_black_bullet(shot_direction)
	_play_fire_sfx_everywhere(_get_weapon_muzzle_world_position(shot_direction),enhanced_shot)
	_play_weapon_recoil(enhanced_shot)
	if enhanced_shot:
		_play_enhanced_body_recoil(shot_direction)

	if attack_recovery > 0.0:
		await wait_for_combat_time(attack_recovery)
	if is_instance_valid(self):
		Attacking = false


func _spawn_black_bullet(aim_direction:Vector2) -> void:
	if not is_multiplayer_authority() or is_damage_output_disabled():
		return
	if aim_direction.length_squared() <= 0.000001:
		aim_direction = Vector2.RIGHT
	var projectile:Area2D = BLACK_BULLET_SCENE.instantiate() as Area2D
	if projectile == null:
		return
	var dir:Vector2 = aim_direction.normalized()
	projectile.set("Master_name",str(name))
	projectile.set("Team",Team)
	projectile.set("damage_amount",attack_damage(projectile_damage_multiplier))
	projectile.set("speed",projectile_speed)
	projectile.set("max_distance",projectile_max_distance)
	projectile.set("direction",dir)
	projectile.set("visual_radius",projectile_visual_radius)
	projectile.global_position = _get_weapon_muzzle_world_position(dir)
	projectile.global_rotation = dir.angle()
	projectile.name = Game.return_random_name(projectile)
	get_tree().current_scene.add_child(projectile,true)


func apply_magic_horn_mark(
	target:ball,
	impact_position:Vector2 = Vector2.ZERO,
	point_amount:int = -1
) -> void:
	if not is_multiplayer_authority() or not _is_enemy(target):
		return

	# 新规则：3 点层数 = 1 个可见阶段。普通黑弹默认 +2 点；小爆弹显式传入 +1 点。
	# 达到第 3 阶段后，再凑满下一层（再获得 mark_points_per_stage 点）立即进入过载爆炸。
	var points_to_add:int = normal_attack_mark_points if point_amount < 0 else point_amount
	points_to_add = maxi(points_to_add,0)
	if points_to_add <= 0:
		return

	var existing:Node = target.get_node_or_null("MagicHornMark")
	if existing != null and is_instance_valid(existing) and existing.has_method("apply_points"):
		existing.call("apply_points",self,mark_duration,points_to_add)
		return

	var mark:Node2D = MARK_SCRIPT.new() as Node2D
	if mark == null:
		return
	mark.name = "MagicHornMark"
	target.add_child(mark,true)
	mark.call(
		"setup",
		target,
		self,
		mark_duration,
		burn_tick_interval,
		burn_tick_damage_per_stack,
		mark_overload_flash_duration,
		maxi(mark_points_per_stage,1),
		points_to_add
	)
	if impact_position != Vector2.ZERO:
		mark.global_position = impact_position


func on_magic_horn_mark_triggered(target:ball) -> void:
	if not is_multiplayer_authority() or target == null or not is_instance_valid(target):
		return
	var target_name:String = str(target.name)
	var target_position:Vector2 = combat_target_position(target)
	if multiplayer.has_multiplayer_peer():
		_rpc_start_mark_weapon_spin.rpc(target_name,target_position)
	else:
		_rpc_start_mark_weapon_spin(target_name,target_position)


@rpc("authority","call_local","reliable")
func _rpc_start_mark_weapon_spin(target_name:String,target_position:Vector2) -> void:
	_weapon_spin_target = _find_ball_by_name(target_name)
	_weapon_spin_fallback_position = target_position
	_weapon_spin_elapsed = 0.0
	_weapon_spin_start_angle = weapon_pivot.rotation if weapon_pivot != null else _last_aim_direction.angle()
	_weapon_spin_active = weapon_pivot != null and weapon_sprite != null
	if _weapon_spin_active:
		_play_weapon_spin_sfx_local()


func _find_ball_by_name(target_name:String) -> ball:
	if target_name.is_empty():
		return null
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if raw is ball and str(raw.name) == target_name:
			return raw as ball
	return null


func _mark_spin_target_direction() -> Vector2:
	if _weapon_spin_target != null and is_instance_valid(_weapon_spin_target):
		var target_position:Vector2 = combat_target_position(_weapon_spin_target)
		var live_direction:Vector2 = target_position - global_position
		if live_direction.length_squared() > 0.000001:
			_weapon_spin_fallback_position = target_position
			return live_direction.normalized()
	var fallback_direction:Vector2 = _weapon_spin_fallback_position - global_position
	if fallback_direction.length_squared() > 0.000001:
		return fallback_direction.normalized()
	return _last_aim_direction.normalized() if _last_aim_direction.length_squared() > 0.000001 else Vector2.RIGHT


func _update_mark_weapon_spin(delta:float) -> void:
	if weapon_pivot == null or weapon_sprite == null:
		_weapon_spin_active = false
		return
	var duration:float = maxf(mark_weapon_spin_duration,0.05)
	_weapon_spin_elapsed = minf(_weapon_spin_elapsed + maxf(delta,0.0),duration)
	var progress:float = clampf(_weapon_spin_elapsed / duration,0.0,1.0)
	# 三次方 Ease-Out：开始快速转动，最后明显减速，并精确停在当前目标方向。
	var eased_progress:float = 1.0 - pow(1.0 - progress,3.0)
	var target_direction:Vector2 = _mark_spin_target_direction()
	var target_angle:float = target_direction.angle()
	var final_angle_delta:float = wrapf(target_angle - _weapon_spin_start_angle,-PI,PI)
	var total_rotation:float = TAU * maxf(mark_weapon_spin_turns,1.0) + final_angle_delta
	weapon_pivot.rotation = _weapon_spin_start_angle + total_rotation * eased_progress

	var visual_scale:float = maxf(weapon_visual_scale,0.05)
	var target_scale_y:float = -visual_scale if target_direction.x < 0.0 else visual_scale
	weapon_sprite.flip_v = false
	weapon_sprite.scale.x = visual_scale
	# 最后 28% 再把图片翻面收束到目标侧，避免转圈中途反复镜像。
	var side_settle:float = clampf((progress - 0.72) / 0.28,0.0,1.0)
	weapon_sprite.scale.y = lerpf(weapon_sprite.scale.y,target_scale_y,side_settle)

	if progress < 1.0:
		return
	_weapon_spin_active = false
	_weapon_spin_target = null
	weapon_pivot.rotation = target_angle
	weapon_sprite.scale = Vector2(visual_scale,target_scale_y)
	_last_aim_direction = target_direction


func _play_weapon_spin_sfx_local() -> void:
	if WEAPON_SPIN_SFX == null:
		return
	if _weapon_spin_audio_tween != null and _weapon_spin_audio_tween.is_valid():
		_weapon_spin_audio_tween.kill()
	if _weapon_spin_audio_player != null and is_instance_valid(_weapon_spin_audio_player):
		_weapon_spin_audio_player.stop()
		_weapon_spin_audio_player.queue_free()
	var player := AudioStreamPlayer2D.new()
	_weapon_spin_audio_player = player
	player.name = "MagicHornWeaponSpinSfx"
	player.stream = WEAPON_SPIN_SFX
	player.volume_db = mark_weapon_spin_sfx_volume_db
	player.max_distance = 1000.0
	player.attenuation = 0.75
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	var parent:Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	parent.add_child(player)
	player.global_position = global_position
	player.play()

	var total_duration:float = maxf(mark_weapon_spin_duration,0.05)
	var fade_duration:float = clampf(mark_weapon_spin_sfx_fade_duration,0.01,total_duration)
	var hold_duration:float = maxf(total_duration - fade_duration,0.0)
	_weapon_spin_audio_tween = create_tween().bind_node(self)
	if hold_duration > 0.0:
		_weapon_spin_audio_tween.tween_interval(hold_duration)
	_weapon_spin_audio_tween.tween_property(player,"volume_db",-48.0,fade_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_weapon_spin_audio_tween.tween_callback(_finish_temporary_audio.bind(player))


func on_magic_horn_mark_overload(target:ball,impact_position:Vector2) -> void:
	if not is_multiplayer_authority() or not _is_enemy(target):
		return
	var point:Vector2 = impact_position if impact_position != Vector2.ZERO else target.global_position
	var damage_value:float = attack_damage(mark_overload_damage_multiplier)
	if damage_value > 0.0:
		target.receive_spatial_damage(
			damage_value,
			{
				"shape":"circle",
				"center":point,
				"radius":maxf(small_bomb_explosion_radius,1.0),
				"source":self,
			},
			false,
			false
		)
	var push_dir:Vector2 = target.global_position - global_position
	if push_dir.length_squared() <= 0.000001:
		push_dir = Vector2.RIGHT.rotated(_rng.randf_range(0.0,TAU))
	target.apply_knockback(
		push_dir.normalized(),
		maxf(mark_overload_knockback_distance,0.0),
		maxf(mark_overload_knockback_speed,50.0),
		0.30,
		0.0,
		{"source":self,"max_wall_bounces":1,"stop_on_character":true}
	)
	_bomb_window_until_msec = maxi(
		_bomb_window_until_msec,
		Time.get_ticks_msec() + int(round(maxf(bomb_window_duration,0.0) * 1000.0))
	)
	_play_magic_horn_explosion_everywhere(point,maxf(small_bomb_explosion_radius,1.0) * 2.60,-5.0)


func is_magic_horn_bomb_window_active() -> bool:
	return Time.get_ticks_msec() < _bomb_window_until_msec


func spawn_magic_horn_small_bombs(hit_position:Vector2) -> void:
	if not is_multiplayer_authority() or not is_magic_horn_bomb_window_active():
		return
	var count:int = maxi(small_bomb_count,0)
	if count <= 0:
		return
	var min_dist:float = minf(maxf(small_bomb_min_distance,0.0),maxf(small_bomb_max_distance,0.0))
	var max_dist:float = maxf(maxf(small_bomb_min_distance,0.0),maxf(small_bomb_max_distance,0.0))
	var phase:float = _rng.randf_range(0.0,TAU)
	for i:int in range(count):
		var bomb:Node2D = SMALL_BOMB_SCENE.instantiate() as Node2D
		if bomb == null:
			continue
		var spread_angle:float = phase + TAU * float(i) / float(maxi(count,1)) + _rng.randf_range(-0.34,0.34)
		var landing_distance:float = _rng.randf_range(min_dist,max_dist)
		var landing:Vector2 = hit_position + Vector2.RIGHT.rotated(spread_angle) * landing_distance
		bomb.set("Master_name",str(name))
		bomb.set("Team",Team)
		bomb.set("start_position",hit_position)
		bomb.set("landing_position",landing)
		bomb.set("flight_duration",small_bomb_flight_duration)
		bomb.set("shake_duration",small_bomb_shake_duration)
		bomb.set("explosion_radius",small_bomb_explosion_radius)
		bomb.set("damage_multiplier",small_bomb_damage_multiplier)
		bomb.global_position = hit_position
		bomb.name = Game.return_random_name(bomb)
		get_tree().current_scene.add_child(bomb,true)


func resolve_magic_horn_small_bomb_explosion(point:Vector2,radius:float,damage_multiplier:float) -> void:
	if not is_multiplayer_authority() or is_damage_output_disabled():
		return
	var safe_radius:float = maxf(radius,1.0)
	var damage_value:float = attack_damage(maxf(damage_multiplier,0.0))
	var hit_any:bool = false
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var target:ball = raw as ball
		if not _is_enemy(target):
			continue
		if point.distance_squared_to(target.global_position) > safe_radius * safe_radius:
			continue
		var did_hit:bool = false
		if damage_value > 0.0:
			did_hit = target.receive_spatial_damage(
				damage_value,
				{
					"shape":"circle",
					"center":point,
					"radius":safe_radius,
					"source":self,
				},
				false,
				false
			)
		hit_any = hit_any or did_hit
		# 小爆弹按需求只负责范围伤害 + 施加/推进标记；击退只属于三层标记的过载爆炸。
		apply_magic_horn_mark(target,point,small_bomb_mark_points)
	if hit_any:
		play_magic_horn_collision_sfx(damage_value)
	_play_magic_horn_explosion_everywhere(point,safe_radius * 2.60,-6.0)


func play_magic_horn_collision_sfx(outgoing_damage:float) -> void:
	var params:Dictionary = {
		"volume": clampf(outgoing_damage - 12.0,-100.0,0.0),
	}
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc("balls_hit1",params,true,true)
	else:
		Audios.play_sfx("balls_hit1",params,true,true)


func _play_fire_sfx_everywhere(world_position:Vector2,enhanced:bool) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_fire_sfx.rpc(world_position,enhanced)
	else:
		_rpc_play_fire_sfx(world_position,enhanced)


@rpc("authority","call_local","unreliable")
func _rpc_play_fire_sfx(world_position:Vector2,enhanced:bool) -> void:
	if FIRE_SFX == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.name = "MagicHornFireSfx"
	player.stream = FIRE_SFX
	player.volume_db = enhanced_fire_sfx_volume_db if enhanced else fire_sfx_volume_db
	player.pitch_scale = randf_range(0.98,1.025)
	player.max_distance = 1050.0
	player.attenuation = 0.78
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	var parent:Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	parent.add_child(player)
	player.global_position = world_position
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _finish_temporary_audio(player:AudioStreamPlayer2D) -> void:
	if player == null or not is_instance_valid(player):
		return
	player.stop()
	player.queue_free()
	if player == _weapon_spin_audio_player:
		_weapon_spin_audio_player = null
		_weapon_spin_audio_tween = null


func play_magic_horn_burn_tick_sfx(world_position:Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_burn_tick_sfx.rpc(world_position)
	else:
		_rpc_play_burn_tick_sfx(world_position)


@rpc("authority","call_local","unreliable")
func _rpc_play_burn_tick_sfx(world_position:Vector2) -> void:
	if BURN_SFX == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.name = "MagicHornBurnTickSfx"
	player.stream = BURN_SFX
	player.volume_db = -3.0
	player.pitch_scale = randf_range(0.97,1.04)
	player.max_distance = 900.0
	player.attenuation = 0.8
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	var parent:Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	parent.add_child(player)
	player.global_position = world_position
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()



func _play_magic_horn_explosion_everywhere(world_position:Vector2,visual_diameter:float,volume_db:float) -> void:
	var selected_variant:int = _rng.randi_range(1,3)
	if multiplayer.has_multiplayer_peer():
		_rpc_play_magic_horn_explosion.rpc(world_position,selected_variant,visual_diameter,volume_db)
	else:
		_rpc_play_magic_horn_explosion(world_position,selected_variant,visual_diameter,volume_db)


@rpc("authority","call_local","reliable")
func _rpc_play_magic_horn_explosion(world_position:Vector2,selected_variant:int,visual_diameter:float,volume_db:float) -> void:
	var effect:Node2D = EXPLOSION_EFFECT_SCENE.instantiate() as Node2D
	if effect == null:
		return
	effect.set("variant",clampi(selected_variant,1,3))
	effect.set("visual_diameter",maxf(visual_diameter,16.0))
	effect.set("volume_db",volume_db)
	# 视觉由每个客户端本地创建，挂在角色下避免被 World 的 MultiplayerSpawner 当成网络对象再次自动生成。
	add_child(effect)
	effect.global_position = world_position


func _current_weapon_aim_vector() -> Vector2:
	if has_player_control_aim():
		var player_aim:Vector2 = player_control_aim_direction(_last_aim_direction)
		if player_aim.length_squared() > 0.000001:
			return player_aim

	var target:ball = _nearest_enemy()
	if target != null:
		var target_aim:Vector2 = combat_target_position(target) - global_position
		if target_aim.length_squared() > 0.000001:
			return target_aim

	# 没有可瞄准对象时保持最后一次枪口方向，不因为人物转身而强制回正。
	return _last_aim_direction


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
	if target == null or not is_instance_valid(target) or target == self:
		return false
	if target.Type != Ball_Type.Ball or target.health <= 0 or not target.is_combat_targetable():
		return false
	if target.state_machine != null and target.state_machine.current_state == State.Die:
		return false
	if not Game.Game_Settings.Have_Team_Damage and not Team.is_empty() and not target.Team.is_empty() and Team == target.Team:
		return false
	return true


func _resolve_body_facing_sign() -> int:
	var movement_direction:Vector2 = player_control_direction if is_player_controlled() else direction
	if absf(movement_direction.x) > 0.05:
		return 1 if movement_direction.x > 0.0 else -1
	if absf(_last_aim_direction.x) > 0.05:
		return 1 if _last_aim_direction.x > 0.0 else -1
	return _last_body_facing_sign if _last_body_facing_sign != 0 else 1


func _snap_weapon_to_direction(aim_direction:Vector2) -> void:
	if weapon_pivot == null or weapon_sprite == null:
		return
	var dir:Vector2 = aim_direction.normalized() if aim_direction.length_squared() > 0.000001 else Vector2.RIGHT
	# V191：目标方向是世界向量，根节点受 Sans 重力旋转后仍要瞄准真实目标。
	weapon_pivot.global_rotation = dir.angle()
	weapon_sprite.flip_v = false
	var visual_scale:float = maxf(weapon_visual_scale,0.05)
	weapon_sprite.scale = Vector2(visual_scale,-visual_scale if dir.x < 0.0 else visual_scale)
	weapon_sprite.position = weapon_local_offset
	weapon_sprite.rotation = 0.0
	_weapon_rest_position = weapon_local_offset


func _track_weapon_to_direction(aim_direction:Vector2,delta:float) -> void:
	if weapon_pivot == null or weapon_sprite == null:
		return
	if aim_direction.length_squared() <= 0.000001:
		return

	var dir:Vector2 = aim_direction.normalized()
	var target_angle:float = dir.angle()
	var safe_duration:float = maxf(weapon_turn_duration,0.01)

	# 指数式追踪：角差大时第一段转得很快，越接近敌人越慢；目标移动时每帧更新目标角，形成持续瞄准。
	# 约在 weapon_turn_duration 内完成 98% 左右的角差，不需要每帧 kill/recreate Tween。
	var follow_weight:float = clampf(1.0 - exp(-4.0 * maxf(delta,0.0) / safe_duration),0.0,1.0)
	weapon_pivot.global_rotation = lerp_angle(weapon_pivot.global_rotation,target_angle,follow_weight)

	# 枪械图片是否上下镜像只由“枪实际瞄准到哪一侧”决定，与角色身体朝向无关。
	# scale:y 同样缓动跨过 0，避免敌人越过角色左右两侧时瞬间翻图。
	var visual_scale:float = maxf(weapon_visual_scale,0.05)
	var target_scale_y:float = -visual_scale if dir.x < 0.0 else visual_scale
	weapon_sprite.flip_v = false
	weapon_sprite.scale.x = visual_scale
	weapon_sprite.scale.y = lerpf(weapon_sprite.scale.y,target_scale_y,follow_weight)


func _get_weapon_muzzle_world_position(fallback_direction:Vector2) -> Vector2:
	if weapon_pivot != null and weapon_sprite != null:
		# muzzle_offset 现在从枪械当前局部中心继续向枪口方向推出，因此枪向前挪后子弹出生点也会跟着挪。
		var local_muzzle:Vector2 = weapon_sprite.position + Vector2(maxf(muzzle_offset,0.0),0.0)
		return weapon_pivot.to_global(local_muzzle)
	var dir:Vector2 = fallback_direction.normalized() if fallback_direction.length_squared() > 0.000001 else Vector2.RIGHT
	return global_position + dir * maxf(muzzle_offset,0.0)


func _play_weapon_recoil(enhanced:bool) -> void:
	if weapon_sprite == null:
		return
	if _weapon_recoil_tween != null and _weapon_recoil_tween.is_valid():
		_weapon_recoil_tween.kill()
	if _weapon_shake_tween != null and _weapon_shake_tween.is_valid():
		_weapon_shake_tween.kill()

	var strength:float = maxf(enhanced_recoil_multiplier,1.0) if enhanced else 1.0
	var rest_position:Vector2 = weapon_local_offset
	_weapon_rest_position = rest_position
	weapon_sprite.position = rest_position
	weapon_sprite.rotation = 0.0
	var kick_position:Vector2 = rest_position - Vector2(maxf(weapon_recoil_distance,0.0) * strength,0.0)

	_weapon_recoil_tween = create_tween().bind_node(self)
	_weapon_recoil_tween.tween_property(weapon_sprite,"position",kick_position,maxf(weapon_recoil_kick_duration,0.01)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_weapon_recoil_tween.tween_property(weapon_sprite,"position",rest_position,maxf(weapon_recoil_return_duration,0.01)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var shake_radians:float = deg_to_rad(maxf(weapon_recoil_shake_degrees,0.0) * strength)
	if shake_radians <= 0.0:
		return
	var first_shake:float = _rng.randf_range(-shake_radians,shake_radians)
	if absf(first_shake) < shake_radians * 0.35:
		first_shake = signf(first_shake if first_shake != 0.0 else 1.0) * shake_radians * 0.55
	_weapon_shake_tween = create_tween().bind_node(self)
	_weapon_shake_tween.tween_property(weapon_sprite,"rotation",first_shake,maxf(weapon_recoil_kick_duration * 0.65,0.015)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_weapon_shake_tween.tween_property(weapon_sprite,"rotation",-first_shake * 0.45,maxf(weapon_recoil_kick_duration * 0.55,0.015)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_weapon_shake_tween.tween_property(weapon_sprite,"rotation",0.0,maxf(weapon_recoil_return_duration * 0.60,0.025)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _play_enhanced_body_recoil(shot_direction:Vector2) -> void:
	var dir:Vector2 = shot_direction.normalized() if shot_direction.length_squared() > 0.000001 else _last_aim_direction
	if dir.length_squared() <= 0.000001:
		dir = Vector2.RIGHT

	# 先做本地视觉冲击：身体快速往射击反方向缩一下，并带一点横向震动。
	_play_enhanced_body_visual_recoil(dir)

	# 强化攻击不仅“看起来后退”，authority 上的角色实体也真正后退。
	# 如果此刻已经在承受别人的通用击退，就只保留视觉后坐，避免自己的开枪反冲覆盖敌方击退。
	if not is_multiplayer_authority() or enhanced_body_physical_recoil_distance <= 0.0:
		return
	if _has_active_generic_knockback():
		return
	apply_knockback(
		-dir,
		maxf(enhanced_body_physical_recoil_distance,0.0),
		maxf(enhanced_body_physical_recoil_speed,50.0),
		0.0,
		0.0,
		{
			"source":self,
			"lock_control":false,
			"max_wall_bounces":0,
			"stop_on_character":true,
			"character_bounce_strength":0.0,
			"use_speed_falloff":true,
			"end_speed_ratio":0.0,
			"smooth_motion":true,
			"smooth_end_ratio":0.55,
			"smooth_end_speed_ratio":0.0,
			"minimum_motion_time":0.06,
			"control_recovery_time":0.0,
			"replace_existing":true,
		}
	)


func _has_active_generic_knockback() -> bool:
	for child:Node in get_children():
		if child == null or not is_instance_valid(child):
			continue
		if not child.has_method("is_active_effect") or not child.has_method("replace_with_hit"):
			continue
		if bool(child.call("is_active_effect")):
			return true
	return false


func _play_enhanced_body_visual_recoil(shot_direction:Vector2) -> void:
	if graphics_node == null or enhanced_body_visual_recoil_distance <= 0.0:
		return
	if _body_recoil_tween != null and _body_recoil_tween.is_valid():
		_body_recoil_tween.kill()
		graphics_node.position = _graphics_rest_position
	else:
		# 角色若有其它视觉动画，使用开枪前的当前位置作为这次后坐的基准，避免突然吸回出生偏移。
		_graphics_rest_position = graphics_node.position

	var dir:Vector2 = shot_direction.normalized() if shot_direction.length_squared() > 0.000001 else _last_aim_direction
	if dir.length_squared() <= 0.000001:
		dir = Vector2.RIGHT
	var side:Vector2 = Vector2(-dir.y,dir.x)
	var shake_amount:float = maxf(enhanced_body_visual_shake_distance,0.0)
	var side_shake:Vector2 = side * _rng.randf_range(-shake_amount,shake_amount)
	var recoil_distance:float = maxf(enhanced_body_visual_recoil_distance,0.0)
	var kick_position:Vector2 = _graphics_rest_position - dir * recoil_distance + side_shake
	var settle_position:Vector2 = _graphics_rest_position - dir * recoil_distance * 0.35 - side_shake * 0.55
	var return_duration:float = maxf(enhanced_body_recoil_return_duration,0.01)

	_body_recoil_tween = create_tween().bind_node(self)
	_body_recoil_tween.tween_property(graphics_node,"position",kick_position,maxf(enhanced_body_recoil_kick_duration,0.01)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_body_recoil_tween.tween_property(graphics_node,"position",settle_position,return_duration * 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_body_recoil_tween.tween_property(graphics_node,"position",_graphics_rest_position,return_duration * 0.62).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
