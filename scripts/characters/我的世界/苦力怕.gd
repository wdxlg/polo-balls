extends ball
const SHARED_BAR = preload("res://scripts/characters/我的世界/frontier/creeper_style_bar.gd")
const U=preload("res://scripts/characters/我的世界/new5/utils.gd")

const NATIVE_MODEL_ANIMATION = preload("res://scripts/effects/我的世界/mc_native_batch2.gd")
var _native_mob_animation:Node

const NORMAL_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/苦力怕/苦力怕.webp")
const CHARGED_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/苦力怕/闪电苦力怕.webp")
const LIGHTNING_SCENE:PackedScene = preload("res://scenes/effects/我的世界/雷电.tscn")
const MC_ABILITIES = preload("res://scripts/effects/我的世界/mc_combat_abilities.gd")
const EXPLOSION_EFFECT_SCENE:PackedScene = preload("res://scenes/effects/我的世界/MC爆炸.tscn")
const CREEPER_HEAD_SCENE:PackedScene = preload("res://scenes/creatures/我的世界/苦力怕头.tscn")
const DEATH_SMOKE_FRAMES:SpriteFrames = preload("res://scenes/effects/我的世界/蠹虫死亡烟雾.tres")

const FUSE_SOUND:AudioStream = preload("res://audio/characters/我的世界/苦力怕/爆炸准备.ogg")
const DEATH_SOUND:AudioStream = preload("res://audio/characters/我的世界/苦力怕/死亡.ogg")
const HURT_SOUNDS:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/苦力怕/受伤.ogg"),
	preload("res://audio/characters/我的世界/苦力怕/受伤2.ogg"),
	preload("res://audio/characters/我的世界/苦力怕/受伤3.ogg"),
	preload("res://audio/characters/我的世界/苦力怕/受伤4.ogg"),
]

const DEATH_POSE_DURATION:float = 0.90
const EXPLOSION_VISUAL_HOLD:float = 1.08
const EXPLOSION_BODY_POP_DURATION:float = 0.10
const DEATH_BRIDGE_ACTIVE_META:StringName = &"battle_death_bridge_active"
const DEATH_BRIDGE_VICTORY_META:StringName = &"battle_death_bridge_victory_side_key"
const DEATH_BRIDGE_PRESENTATION_META:StringName = &"battle_death_bridge_presentation_side_key"
const DEATH_BRIDGE_DISPLAY_META:StringName = &"battle_death_bridge_display_name"

# V114：引信进度条改成与锻刀师相同的“黑色外框 + 深色槽 + 灰白描边”绘制风格。
# V115：进度条移到角色脚下；按角色碰撞体下缘留少量间距，不再悬在头顶。
# 内部填充色不再使用 ProgressBar 默认主题，而是随引信进度从白色连续过渡到红色。
const FUSE_BAR_RECT:Rect2 = Rect2(-55.0,92.0,110.0,16.0)
const FUSE_BAR_OUTER_PAD:float = 4.0
const FUSE_BAR_BORDER_WIDTH:float = 2.5
const FUSE_BAR_OUTER_COLOR:Color = SHARED_BAR.OUTER_COLOR
const FUSE_BAR_BACKGROUND_COLOR:Color = SHARED_BAR.BACKGROUND_COLOR
const FUSE_BAR_BORDER_COLOR:Color = SHARED_BAR.BORDER_COLOR
const FUSE_BAR_START_COLOR:Color = SHARED_BAR.START_COLOR
const FUSE_BAR_END_COLOR:Color = SHARED_BAR.END_COLOR

@export_category("苦力怕 / 引信")
@export_range(16.0,180.0,1.0) var fuse_start_radius:float = 50.0
@export_range(20.0,220.0,1.0) var fuse_cancel_radius:float = 50.0
@export_range(0.6,5.0,0.05) var fuse_duration:float = 2.50
@export_range(0.30,1.0,0.01) var charged_fuse_duration_ratio:float = 0.78
@export_range(0.0,2.0,0.05) var fuse_decay_delay:float = 0.55
@export_range(0.05,3.0,0.05) var fuse_decay_acceleration:float = 0.55
@export_range(0.10,4.0,0.05) var fuse_decay_max_speed:float = 1.60
@export_range(0.1,1.0,0.01) var targeting_speed_ratio:float = 0.72
@export_range(0.1,1.0,0.01) var fuse_final_speed_ratio:float = 0.34
@export_range(1.0,1.8,0.01) var fuse_final_scale:float = 1.08
@export_range(1.0,2.0,0.01) var fuse_explosion_scale:float = 1.12

@export_category("苦力怕 / 爆炸")
@export_range(20.0,1000.0,1.0) var explosion_damage:float = 500.0
@export_range(40.0,360.0,1.0) var explosion_radius:float = 60.0
@export_range(1.0,3.0,0.05) var charged_damage_multiplier:float = 1.45
@export_range(1.0,2.5,0.05) var charged_radius_multiplier:float = 1.20
@export_range(0.0,320.0,1.0) var explosion_knockback_distance:float = 145.0
@export_range(50.0,1800.0,10.0) var explosion_knockback_speed:float = 1080.0

@export_category("苦力怕 / 自引雷")
@export_range(1.0,30.0,0.1) var lightning_interval_min:float = 6.0
@export_range(1.0,40.0,0.1) var lightning_interval_max:float = 10.0
@export_range(20.0,320.0,1.0) var lightning_damage:float = 38.0
@export_range(20.0,180.0,1.0) var lightning_radius:float = 62.0
@export_range(0.10,1.50,0.01) var lightning_warning_delay:float = 0.68
@export_range(0.05,3.0,0.05) var lightning_stun_duration:float = 0.55

@export_category("苦力怕 / 反馈")
@export_range(0.0,1.0,0.01) var hurt_sound_chance:float = 0.62
@export_range(-30.0,12.0,0.5) var fuse_volume_db:float = -1.0
@export_range(-30.0,12.0,0.5) var hurt_volume_db:float = -1.5
@export_range(-30.0,12.0,0.5) var death_volume_db:float = 0.0
@export_range(-12.0,8.0,0.5) var explosion_volume_db:float = 0.0
@export_range(0.0,8.0,0.5) var charged_explosion_volume_bonus_db:float = 2.5

@onready var fuse_audio:AudioStreamPlayer2D = $FuseAudio
@onready var hurt_audio:AudioStreamPlayer2D = $HurtAudio
@onready var death_audio:AudioStreamPlayer2D = $DeathAudio
@onready var fuse_progress:ProgressBar = $FuseProgress

var _rng := RandomNumberGenerator.new()
var _charged:bool = false
var _fusing:bool = false
var _fuse_advancing:bool = false
var _fuse_elapsed:float = 0.0
var _fuse_decay_elapsed:float = 0.0
var _fuse_visual_clock:float = 0.0
var _current_fuse_duration:float = 2.5
var _fuse_target_id:int = 0
var _targeting_slow_active:bool = false
var _lightning_left:float = 0.0
var _hurt_audio_cooldown:float = 0.0
var _exploded:bool = false
var _death_sequence_started:bool = false
var _death_visual_started_local:bool = false

var _graphics_base_position:Vector2 = Vector2.ZERO
var _graphics_base_scale:Vector2 = Vector2.ONE
var _graphics_base_rotation:float = 0.0
var _foot_anchor_parent:Vector2 = Vector2.ZERO
var _foot_anchor_child:Vector2 = Vector2.ZERO


func _ready() -> void:
	Has_Collision_Damage = false
	Can_Attack = false
	Can_Skill = false
	Health_Restore = 0
	dir_left = true # 两张本体素材都朝左；向右移动时由公共朝向系统翻转。
	if image is Sprite2D:
		var sprite := image as Sprite2D
		sprite.texture = NORMAL_TEXTURE
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	super._ready()
	_native_mob_animation = NATIVE_MODEL_ANIMATION.attach(self,"creeper")
	# FuseProgress 只保留为数值容器；真正视觉由本节点 _draw() 统一绘制，
	# 避免项目默认 ProgressBar 主题把锻刀师风格覆盖掉。
	if fuse_progress != null:
		fuse_progress.hide()
	_rng.seed = Game.battle_rng_seed_or("scripts/characters/我的世界/苦力怕.gd:_rng.seed",maxi(abs(int(Time.get_ticks_usec()) ^ int(get_instance_id())),1))
	_capture_fuse_visual_base()
	if is_multiplayer_authority():
		_schedule_next_lightning()


func get_preview_texture() -> Texture2D:
	return NORMAL_TEXTURE


func tick_physics(state:State,delta:float) -> void:
	_hurt_audio_cooldown = maxf(_hurt_audio_cooldown - delta,0.0)
	if _death_visual_started_local or _exploded:
		return

	super.tick_physics(state,delta)
	if _fusing:
		_advance_fuse_progress(delta)
	_update_fuse_visual(delta)

	if not is_multiplayer_authority():
		return
	if health <= 0 or state_machine == null or state_machine.current_state == State.Die:
		return
	if not is_combat_runtime_active():
		_update_fuse_logic(delta)
		return

	if is_player_controlled(): _lightning_left=maxf(0.0,_lightning_left-delta)
	else: _update_lightning_timer(delta)
	_update_fuse_logic(delta)


# 锁到附近敌人时立即减速；真正引信推进后，再随进度继续降速。
# 目标离开检测范围后恢复正常移动，引信本身仍按原有“停留 + 回退”逻辑处理。
func move(speed:float,delta:float) -> void:
	var speed_ratio:float = 1.0
	if _targeting_slow_active:
		speed_ratio = clampf(targeting_speed_ratio,0.10,1.0)
	if _fusing and _fuse_advancing:
		var progress:float = clampf(_fuse_elapsed / maxf(_current_fuse_duration,0.05),0.0,1.0)
		speed_ratio = lerpf(
			clampf(targeting_speed_ratio,0.10,1.0),
			clampf(fuse_final_speed_ratio,0.05,1.0),
			progress
		)
	super.move(speed * speed_ratio,delta)


func _update_fuse_logic(_delta:float) -> void:
	var nearest:ball = null if is_player_controlled() else _nearest_enemy()
	_targeting_slow_active = (
		nearest != null
		and global_position.distance_to(ball.body_point(nearest,global_position)) <= fuse_cancel_radius
	)
	if not _fusing:
		if nearest != null and global_position.distance_to(ball.body_point(nearest,global_position)) <= fuse_start_radius:
			_begin_fuse(nearest)
		return

	var tracked:ball = _resolve_fuse_target()
	var active_target:ball = null
	if tracked != null and global_position.distance_to(ball.body_point(tracked,global_position)) <= fuse_cancel_radius:
		active_target = tracked
	elif nearest != null and global_position.distance_to(ball.body_point(nearest,global_position)) <= fuse_cancel_radius:
		active_target = nearest

	if active_target != null:
		_set_fuse_advancing(true,active_target.get_instance_id())
	else:
		_set_fuse_advancing(false,0)

	if _fuse_elapsed >= _current_fuse_duration:
		_explode()
	elif not _fuse_advancing and _fuse_elapsed <= 0.0:
		_cancel_fuse()

func controlled_attack_action() -> void:
	if not is_player_controlled() or not is_multiplayer_authority() or _fusing or _exploded or health<=0 or not is_combat_runtime_active() or not has_player_control_aim(): return
	var point:Vector2=player_control_aim_world_position()
	var chosen:ball=null
	var nearest:float=INF
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not (raw is ball) or not _is_enemy(raw as ball): continue
		var distance:float=ball.body_point(raw,point).distance_to(point)
		if distance<=U.radius(raw)+6.0 and distance<nearest:
			chosen=raw as ball
			nearest=distance
	if chosen!=null and global_position.distance_to(ball.body_point(chosen,global_position))<=fuse_start_radius:
		_begin_fuse(chosen)
func controlled_skill_action() -> void:
	if not is_player_controlled() or not is_multiplayer_authority() or health<=0 or _exploded or _lightning_left>0.0 or not is_combat_runtime_active(): return
	_summon_self_lightning()
	_schedule_next_lightning()


func _begin_fuse(target:ball) -> void:
	if _fusing or _exploded or target == null:
		return
	var duration:float = maxf(fuse_duration,0.1)
	if _charged:
		duration *= clampf(charged_fuse_duration_ratio,0.2,1.0)
	var target_id:int = target.get_instance_id()
	if multiplayer.has_multiplayer_peer():
		_rpc_begin_fuse.rpc(duration,target_id)
	else:
		_rpc_begin_fuse(duration,target_id)


@rpc("authority","call_local","reliable")
func _rpc_begin_fuse(duration:float,target_id:int) -> void:
	_fusing = true
	_fuse_advancing = true
	_fuse_elapsed = 0.0
	_fuse_decay_elapsed = 0.0
	_fuse_visual_clock = 0.0
	_current_fuse_duration = maxf(duration,0.1)
	_fuse_target_id = target_id
	_play_fuse_audio_from_progress()
	if fuse_progress != null:
		fuse_progress.value = 0.0
		fuse_progress.hide()
	queue_redraw()


func _advance_fuse_progress(delta:float) -> void:
	_fuse_visual_clock += maxf(delta,0.0)
	if _fuse_advancing:
		_fuse_decay_elapsed = 0.0
		_fuse_elapsed = minf(_fuse_elapsed + maxf(delta,0.0),_current_fuse_duration)
		return

	_fuse_decay_elapsed += maxf(delta,0.0)
	var decay_time:float = _fuse_decay_elapsed - maxf(fuse_decay_delay,0.0)
	if decay_time <= 0.0:
		return
	var decay_speed:float = minf(
		decay_time * maxf(fuse_decay_acceleration,0.01),
		maxf(fuse_decay_max_speed,0.01)
	)
	_fuse_elapsed = maxf(_fuse_elapsed - decay_speed * maxf(delta,0.0),0.0)


func _set_fuse_advancing(value:bool,target_id:int) -> void:
	if not is_multiplayer_authority() or not _fusing:
		return
	var safe_target_id:int = target_id if value else 0
	if _fuse_advancing == value and (_fuse_target_id == safe_target_id or not value):
		return
	if multiplayer.has_multiplayer_peer():
		_rpc_set_fuse_advancing.rpc(value,safe_target_id)
	else:
		_rpc_set_fuse_advancing(value,safe_target_id)


@rpc("authority","call_local","reliable")
func _rpc_set_fuse_advancing(value:bool,target_id:int) -> void:
	if not _fusing:
		return
	var was_advancing:bool = _fuse_advancing
	_fuse_advancing = value
	_fuse_target_id = target_id if value else 0
	if value:
		_fuse_decay_elapsed = 0.0
		if not was_advancing:
			_play_fuse_audio_from_progress()
	elif fuse_audio != null:
		fuse_audio.stop()


func _play_fuse_audio_from_progress() -> void:
	if fuse_audio == null or FUSE_SOUND == null:
		return
	fuse_audio.stop()
	fuse_audio.stream = FUSE_SOUND
	fuse_audio.volume_db = fuse_volume_db
	fuse_audio.pitch_scale = clampf(FUSE_SOUND.get_length() / maxf(_current_fuse_duration,0.1),0.82,1.22)
	var sound_length:float = maxf(FUSE_SOUND.get_length(),0.0)
	var progress:float = clampf(_fuse_elapsed / maxf(_current_fuse_duration,0.05),0.0,0.98)
	fuse_audio.play(progress * sound_length)


func _cancel_fuse() -> void:
	if not _fusing:
		return
	if multiplayer.has_multiplayer_peer():
		_rpc_cancel_fuse.rpc()
	else:
		_rpc_cancel_fuse()


@rpc("authority","call_local","reliable")
func _rpc_cancel_fuse() -> void:
	_fusing = false
	_fuse_advancing = false
	_targeting_slow_active = false
	_fuse_elapsed = 0.0
	_fuse_decay_elapsed = 0.0
	_fuse_visual_clock = 0.0
	_fuse_target_id = 0
	if fuse_audio != null:
		fuse_audio.stop()
	_reset_fuse_visual()


func _resolve_fuse_target() -> ball:
	if _fuse_target_id <= 0 or not is_instance_id_valid(_fuse_target_id):
		return null
	var candidate:Variant = instance_from_id(_fuse_target_id)
	if candidate is ball and is_instance_valid(candidate):
		return candidate as ball
	return null


func _update_fuse_visual(_delta:float) -> void:
	if not _fusing or graphics == null or image == null:
		return
	var progress:float = clampf(_fuse_elapsed / maxf(_current_fuse_duration,0.05),0.0,1.0)
	if fuse_progress != null:
		fuse_progress.value = progress

	# 只有检测范围内仍有目标、引信正在增加时才闪白。
	# 目标离开后的“停留 + 回退”阶段保留累计进度和体型，但不再闪白。
	if _fuse_advancing:
		var cycles_per_second:float = lerpf(2.0,9.5,progress)
		var pulse:float = (sin(_fuse_visual_clock * TAU * cycles_per_second) + 1.0) * 0.5
		var flash_floor:float = lerpf(0.06,0.28,progress)
		var flash_power:float = clampf(flash_floor + pulse * lerpf(0.44,0.72,progress),0.0,1.0)
		image.set_instance_shader_parameter("power",flash_power)
	else:
		image.set_instance_shader_parameter("power",0.0)

	# V90：引信阶段只做脚底锚定的轻微放大，不再朝移动方向前倾。
	# 这样快爆炸时仍有体型反馈，但 Graphics.rotation 始终保持角色原本角度。
	var scale_ratio:float = lerpf(1.0,maxf(fuse_final_scale,1.0),progress)
	# 模型已按原版 swelling 膨胀，不再重复叠加旧整图放大。
	if is_instance_valid(_native_mob_animation) and _native_mob_animation.ready_visual:
		_apply_feet_anchored_graphics_transform(1.0,0.0)
	else:
		_apply_feet_anchored_graphics_transform(scale_ratio,0.0)
	queue_redraw()


func _draw() -> void:
	if not _fusing or _exploded:
		return
	_draw_fuse_progress_bar()


func _draw_fuse_progress_bar() -> void:
	var ratio:float = clampf(_fuse_elapsed / maxf(_current_fuse_duration,0.05),0.0,1.0)
	SHARED_BAR.paint(self,FUSE_BAR_RECT,ratio,ratio)


func _capture_fuse_visual_base() -> void:
	if graphics == null:
		return
	_graphics_base_position = graphics.position
	_graphics_base_scale = graphics.scale
	_graphics_base_rotation = graphics.rotation
	var bottom_y:float = 130.0
	if image is Sprite2D:
		var sprite := image as Sprite2D
		if sprite.texture != null:
			bottom_y = sprite.position.y + (float(sprite.texture.get_height()) * 0.5 + sprite.offset.y) * sprite.scale.y
	_foot_anchor_child = Vector2(0.0,bottom_y)
	_foot_anchor_parent = _graphics_base_position + Vector2(
		_foot_anchor_child.x * _graphics_base_scale.x,
		_foot_anchor_child.y * _graphics_base_scale.y
	).rotated(_graphics_base_rotation)


func _apply_feet_anchored_graphics_transform(scale_ratio:float,lean:float) -> void:
	if graphics == null:
		return
	var target_scale:Vector2 = _graphics_base_scale * scale_ratio
	var target_rotation:float = _graphics_base_rotation + lean
	var transformed_anchor := Vector2(
		_foot_anchor_child.x * target_scale.x,
		_foot_anchor_child.y * target_scale.y
	).rotated(target_rotation)
	graphics.scale = target_scale
	graphics.rotation = target_rotation
	graphics.position = _foot_anchor_parent - transformed_anchor


func _reset_fuse_visual() -> void:
	if image != null and is_instance_valid(image):
		image.set_instance_shader_parameter("power",0.0)
	if graphics != null and is_instance_valid(graphics):
		graphics.position = _graphics_base_position
		graphics.scale = _graphics_base_scale
		graphics.rotation = _graphics_base_rotation
	if fuse_progress != null and is_instance_valid(fuse_progress):
		fuse_progress.value = 0.0
		fuse_progress.hide()
	queue_redraw()


func _current_facing_sign() -> float:
	if absf(direction.x) > 0.05:
		return 1.0 if direction.x > 0.0 else -1.0
	return -1.0 if not is_character_visual_flipped_h() else 1.0


func _update_lightning_timer(delta:float) -> void:
	_lightning_left -= delta
	if _lightning_left > 0.0:
		return
	_summon_self_lightning()
	_schedule_next_lightning()


func _schedule_next_lightning() -> void:
	var lo:float = minf(lightning_interval_min,lightning_interval_max)
	var hi:float = maxf(lightning_interval_min,lightning_interval_max)
	_lightning_left = _rng.randf_range(maxf(lo,0.2),maxf(hi,0.2))


func _summon_self_lightning() -> void:
	if _exploded or health <= 0:
		return
	# 雷声先出现。视觉节点在预警期间会持续跟随苦力怕脚底，
	# 因此角色移动后，真正落雷不会停在 0.68 秒前的旧坐标。
	var point:Vector2 = _self_foot_world_position()
	var seed_value:int = Game.battle_rng_seed_or("scripts/characters/我的世界/苦力怕.gd:seed_value",maxi(abs(int(Time.get_ticks_usec()) ^ int(get_instance_id()) ^ _rng.randi()),1))
	var delay:float = maxf(lightning_warning_delay,0.05)
	_broadcast_lightning_visual(point,seed_value,delay)


func _finish_self_lightning(point:Vector2) -> void:
	if _exploded or health <= 0 or not is_multiplayer_authority():
		return
	# Only the authoritative visible strike drives gameplay; use its true impact point.
	if not _charged:
		_set_charged_everywhere(true)
	_apply_lightning_area(point)


func _self_foot_world_position() -> Vector2:
	# 优先使用本体碰撞框底边：不会受到 Graphics 的引信缩放/倾斜影响，
	# 也不会把身体中心误当作脚底。to_global() 会自动包含角色根节点缩放。
	var body_collision:CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body_collision != null and is_instance_valid(body_collision) and body_collision.shape != null:
		if body_collision.shape is RectangleShape2D:
			var rect:RectangleShape2D = body_collision.shape as RectangleShape2D
			return body_collision.to_global(Vector2(0.0,rect.size.y * 0.5))
		if body_collision.shape is CapsuleShape2D:
			var capsule:CapsuleShape2D = body_collision.shape as CapsuleShape2D
			return body_collision.to_global(Vector2(0.0,capsule.height * 0.5))
		if body_collision.shape is CircleShape2D:
			var circle:CircleShape2D = body_collision.shape as CircleShape2D
			return body_collision.to_global(Vector2(0.0,circle.radius))

	if graphics != null and is_instance_valid(graphics):
		return graphics.to_global(_foot_anchor_child)
	return global_position


func _set_charged_everywhere(value:bool) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_set_charged.rpc(value)
	else:
		_rpc_set_charged(value)


@rpc("authority","call_local","reliable")
func _rpc_set_charged(value:bool) -> void:
	var became_charged:bool = value and not _charged
	_charged = value
	if became_charged and _fusing:
		_current_fuse_duration = maxf(
			_fuse_elapsed + 0.08,
			_current_fuse_duration * clampf(charged_fuse_duration_ratio,0.2,1.0)
		)
	if image is Sprite2D and (not is_instance_valid(_native_mob_animation) or not _native_mob_animation.ready_visual):
		(image as Sprite2D).texture = CHARGED_TEXTURE if _charged else NORMAL_TEXTURE


func _broadcast_lightning_visual(point:Vector2,seed_value:int,warning_delay:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_lightning.rpc(point,seed_value,lightning_radius,warning_delay)
	else:
		_rpc_play_lightning(point,seed_value,lightning_radius,warning_delay)


@rpc("authority","call_local","reliable")
func _rpc_play_lightning(point:Vector2,seed_value:int,impact_radius:float,warning_delay:float) -> void:
	# 这是 RPC 在每个 peer 本地创建的纯视觉节点，不挂到 World 根节点的
	# MultiplayerSpawner.spawn_path 下；同时强制可读名称，避免 @Node2D@ 保留名。
	MC_ABILITIES.lightning(self,point,seed_value,impact_radius,warning_delay,{
		"scene":LIGHTNING_SCENE,"name":"CreeperLightningVisual",
		"on_impact":_finish_self_lightning if is_multiplayer_authority() else Callable()
	})


func _apply_lightning_area(point:Vector2) -> void:
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var target:ball = raw as ball
		if ball.body_point(target,point).distance_to(point) > lightning_radius:
			continue
		if target.has_method("on_mc_lightning_struck"):
			target.call("on_mc_lightning_struck")
		if not _is_enemy(target):
			continue
		var accepted:bool = target.receive_spatial_damage(
			effective_outgoing_damage(lightning_damage),
			{"shape":"circle","center":point,"radius":lightning_radius,"source":self},
			false,
			false
		)
		if accepted and lightning_stun_duration > 0.0 and target.health > 0:
			target.apply_stun(lightning_stun_duration)


func _explode() -> void:
	if _exploded or not is_multiplayer_authority():
		return
	_exploded = true
	var point:Vector2 = global_position
	var head_spawn_position:Vector2 = _head_world_position()
	set_meta(&"ignore_combat_targeting",true)
	set_collision_layer(0)
	set_collision_mask(0)
	if self_hurtbox != null:
		self_hurtbox.set_deferred(&"monitorable",false)
		self_hurtbox.set_deferred(&"monitoring",false)
	var radius:float = explosion_radius * (charged_radius_multiplier if _charged else 1.0)
	var damage_value:float = effective_outgoing_damage(explosion_damage * (charged_damage_multiplier if _charged else 1.0))

	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var target:ball = raw as ball
		if not _is_enemy(target):
			continue
		if ball.body_point(target,point).distance_to(point) > radius:
			continue
		var accepted:bool = target.receive_spatial_damage(
			damage_value,
			{"shape":"circle","center":point,"radius":radius,"source":self},
			false,
			false
		)
		if not accepted:
			continue
		var push:Vector2 = ball.body_point(target,point) - point
		if push.length_squared() <= 0.000001:
			push = Vector2.RIGHT.rotated(_rng.randf_range(0.0,TAU))
		target.apply_knockback(
			push.normalized(),
			explosion_knockback_distance,
			explosion_knockback_speed,
			0.25,
			0.0,
			{"source":self,"max_wall_bounces":1,"stop_on_character":true}
		)

	var variant:int = _rng.randi_range(1,3)
	var visual_diameter:float = radius * 2.0
	if multiplayer.has_multiplayer_peer():
		_rpc_explosion_visual.rpc(point,variant,visual_diameter)
	else:
		_rpc_explosion_visual(point,variant,visual_diameter)

	# V38：爆炸视觉/伤害先在当前帧完成；苦力怕头放到下一 process frame 再实例化。
	# ball 派生角色的 _ready() 较重，避免与爆炸动画首次呈现挤在同一帧造成明显卡顿。
	_spawn_creeper_head_next_frame(head_spawn_position)
	await get_tree().create_timer(EXPLOSION_VISUAL_HOLD).timeout
	if is_instance_valid(self) and is_multiplayer_authority():
		Game.free_node(self)


@rpc("authority","call_local","reliable")
func _rpc_explosion_visual(point:Vector2,_variant:int,visual_diameter:float) -> void:
	_exploded = true
	_fusing = false
	_fuse_advancing = false
	_targeting_slow_active = false
	if fuse_audio != null:
		fuse_audio.stop()
	if image != null and is_instance_valid(image):
		image.set_instance_shader_parameter("power",0.0)
	if fuse_progress != null and is_instance_valid(fuse_progress):
		fuse_progress.value = 0.0
		fuse_progress.hide()
	queue_redraw()
	if health_bar != null:
		health_bar.hide()

	# 爆炸瞬间额外放大一次本体，并强制保持直立；不再带最终旋转。
	if graphics != null and is_instance_valid(graphics):
		graphics.show()
		_apply_feet_anchored_graphics_transform(maxf(fuse_final_scale,1.0),0.0)
		var pop_tween:Tween = graphics.create_tween()
		pop_tween.tween_method(
			Callable(self,"_set_explosion_body_scale"),
			maxf(fuse_final_scale,1.0),
			maxf(fuse_explosion_scale,fuse_final_scale),
			EXPLOSION_BODY_POP_DURATION
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		pop_tween.tween_callback(Callable(graphics,"hide"))

	var effect:Node2D = EXPLOSION_EFFECT_SCENE.instantiate() as Node2D
	if effect == null:
		return
	effect.set("radius",maxf(visual_diameter*0.5,8.0))
	# V38：恢复爆炸存在感；闪电苦力怕在普通爆炸音量上再额外提高。
	var explosion_db:float = explosion_volume_db
	if _charged:
		explosion_db += maxf(charged_explosion_volume_bonus_db,0.0)
	effect.set("volume_db",explosion_db)
	# Local RPC visuals live outside the dying actor and outside the spawner root.
	# Small ejected smoke must finish even after the creeper is removed.
	effect.name = "CreeperExplosionVisual"
	effect.position = point
	load("res://scripts/effects/我的世界/mc_explosion.gd").runtime_container(self).add_child(effect,true)
	effect.global_position = point


func _set_explosion_body_scale(scale_ratio:float) -> void:
	if graphics == null or not is_instance_valid(graphics):
		return
	_apply_feet_anchored_graphics_transform(scale_ratio,0.0)


func _spawn_creeper_head_next_frame(spawn_position:Vector2) -> void:
	if get_tree() == null:
		return
	# process_frame 信号只连接一次，不用零秒 Timer 在当前帧尾继续堆工作。
	get_tree().process_frame.connect(
		Callable(self,"_spawn_creeper_head").bind(spawn_position),
		CONNECT_ONE_SHOT
	)


func _spawn_creeper_head(spawn_position:Vector2) -> void:
	if not is_multiplayer_authority():
		return
	var head:ball = CREEPER_HEAD_SCENE.instantiate() as ball
	if head == null:
		return

	head.set("Team",Team)
	head.set("Master",self)
	head.set("Master_name",str(name))
	head.name = Game.return_random_name(head)

	var victory_key:String = _stable_victory_side_key()
	var presentation_key:String = _stable_presentation_side_key()
	head.set_meta(&"battle_continuation_victory_side_key",victory_key)
	head.set_meta(&"battle_continuation_presentation_side_key",presentation_key)
	head.set_meta(&"battle_continuation_display_name","苦力怕")
	head.set_meta(&"victory_side_key",victory_key)
	if has_meta(&"battle_setup_id"):
		head.set_meta(&"battle_setup_id",int(get_meta(&"battle_setup_id")))

	# V84：头不再只是继承本体朝向后立刻开始普通移动。
	# 爆炸时给一个随机 360° 飞出方向，并交给苦力怕头自己的“无重力弹球式”飞行态。
	var launch:Vector2 = Vector2.RIGHT.rotated(_rng.randf_range(0.0,TAU))
	head.direction = launch
	var world:Node = get_tree().current_scene
	if world != null:
		world.add_child(head,true)
		head.global_position = spawn_position
		if head.has_method("begin_explosion_launch"):
			# V86：闪电形态爆炸时把充能状态传给头，让初始炸飞力度和短暂加速度同步增强。
			head.call("begin_explosion_launch",launch,_charged)


func _head_world_position() -> Vector2:
	if graphics != null and is_instance_valid(graphics):
		return graphics.to_global(Vector2(0.0,-72.0))
	return global_position + Vector2(0.0,-18.0)


func _stable_victory_side_key() -> String:
	if has_meta(&"victory_side_key"):
		var cached:String = str(get_meta(&"victory_side_key","")).strip_edges()
		if not cached.is_empty():
			return cached
	var team_name:String = str(Team).strip_edges()
	if not team_name.is_empty() and team_name != "Ball":
		return "team:" + team_name
	if has_meta(&"battle_setup_id"):
		return "solo_setup:" + str(int(get_meta(&"battle_setup_id")))
	return "solo_instance:" + str(get_instance_id())


func _stable_presentation_side_key() -> String:
	var team_name:String = str(Team).strip_edges()
	if not team_name.is_empty() and team_name != "Ball":
		return "team:" + team_name
	return "solo:" + str(get_instance_id())


func _nearest_enemy() -> ball:
	var nearest:ball = null
	var nearest_distance_sq:float = INF
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var candidate:ball = raw as ball
		if not _is_enemy(candidate):
			continue
		var d:float = global_position.distance_squared_to(ball.body_point(candidate,global_position))
		if d < nearest_distance_sq:
			nearest_distance_sq = d
			nearest = candidate
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


func on_actual_health_damage_received(actual_health_damage:float,_health_before:float) -> void:
	if actual_health_damage <= 0.0 or health <= 0 or not is_multiplayer_authority():
		return
	if _hurt_audio_cooldown > 0.0 or _rng.randf() > clampf(hurt_sound_chance,0.0,1.0):
		return
	_hurt_audio_cooldown = 0.14
	var index:int = _rng.randi_range(0,HURT_SOUNDS.size() - 1)
	if multiplayer.has_multiplayer_peer():
		_rpc_play_hurt.rpc(index)
	else:
		_rpc_play_hurt(index)


@rpc("authority","call_local","unreliable")
func _rpc_play_hurt(index:int) -> void:
	if hurt_audio == null or HURT_SOUNDS.is_empty():
		return
	hurt_audio.stream = HURT_SOUNDS[clampi(index,0,HURT_SOUNDS.size() - 1)]
	hurt_audio.volume_db = hurt_volume_db
	hurt_audio.pitch_scale = randf_range(0.97,1.04)
	hurt_audio.play()


func _has_death_animation() -> bool:
	return true


func Die() -> void:
	if _death_sequence_started or _exploded:
		return
	_death_sequence_started = true
	_arm_death_bridge()
	super.Die()
	var death_position:Vector2 = global_position
	if multiplayer.has_multiplayer_peer():
		_rpc_start_death_visual.rpc(death_position)
	else:
		_rpc_start_death_visual(death_position)
	await get_tree().create_timer(DEATH_POSE_DURATION).timeout
	if is_instance_valid(self) and is_multiplayer_authority():
		Game.free_node(self)


func _arm_death_bridge() -> void:
	set_meta(DEATH_BRIDGE_ACTIVE_META,true)
	set_meta(DEATH_BRIDGE_VICTORY_META,_stable_victory_side_key())
	set_meta(DEATH_BRIDGE_PRESENTATION_META,_stable_presentation_side_key())
	set_meta(DEATH_BRIDGE_DISPLAY_META,"苦力怕")


@rpc("authority","call_local","reliable")
func _rpc_start_death_visual(death_position:Vector2) -> void:
	if _death_visual_started_local:
		return
	_death_visual_started_local = true
	_fusing = false
	_fuse_advancing = false
	_targeting_slow_active = false
	if fuse_audio != null:
		fuse_audio.stop()
	if hurt_audio != null:
		hurt_audio.stop()
	_reset_fuse_visual()
	if death_audio != null:
		death_audio.stream = DEATH_SOUND
		death_audio.volume_db = death_volume_db
		death_audio.pitch_scale = 1.0
		death_audio.play()
	if health_bar != null:
		health_bar.hide()
	if graphics != null:
		var rotate_sign:float = -1.0 if direction.x >= 0.0 else 1.0
		var tween:Tween = graphics.create_tween().set_parallel(true)
		tween.tween_property(graphics,"modulate",Color(1.0,0.20,0.20,1.0),0.10)
		tween.tween_property(graphics,"rotation",graphics.rotation + rotate_sign * PI * 0.5,DEATH_POSE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_create_delayed_death_smoke(death_position)


func _create_delayed_death_smoke(death_position:Vector2) -> void:
	var visual_parent:Node = get_tree().current_scene
	if visual_parent == null:
		return
	var smoke := AnimatedSprite2D.new()
	smoke.name = "苦力怕死亡烟雾"
	smoke.sprite_frames = DEATH_SMOKE_FRAMES
	smoke.animation = &"死亡烟雾"
	smoke.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	smoke.z_as_relative = false
	smoke.z_index = 8
	smoke.scale = Vector2.ONE * 0.52
	smoke.visible = false
	visual_parent.add_child(smoke)
	smoke.global_position = death_position
	smoke.animation_finished.connect(Callable(smoke,"queue_free"),CONNECT_ONE_SHOT)
	var delayed:Tween = smoke.create_tween()
	delayed.tween_interval(DEATH_POSE_DURATION)
	delayed.tween_callback(Callable(smoke,"show"))
	delayed.tween_callback(Callable(smoke,"play").bind(&"死亡烟雾"))
