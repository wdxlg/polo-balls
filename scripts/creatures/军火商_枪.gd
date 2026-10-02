extends Node2D

# 军火商放下的静止枪：根节点不是 PhysicsBody2D/Area2D，因此本体完全无碰撞。
# 枪型：0狙击枪 1小手枪 2沙鹰 3AK 4火箭筒 5加特林

const LOCAL_SFX = preload("res://scripts/audio/local_positional_sfx.gd")
const PROJECTILE_SCENE:PackedScene = preload("res://scenes/shooter/军火商_子弹.tscn")
const WEAPON_IMAGE_DIR:String = "res://Images/characters/人物/军火商/武器"
const GATLING_FIRE_STREAM:AudioStream = preload("res://audio/sfx/战斗/加特林发射.mp3")
const GATLING_CHARGE_STREAM:AudioStream = preload("res://audio/sfx/战斗/加特林蓄力.mp3")

const GUN_SNIPER:int = 0
const GUN_PISTOL:int = 1
const GUN_DEAGLE:int = 2
const GUN_AK:int = 3
const GUN_ROCKET:int = 4
const GUN_GATLING:int = 5
const NON_SNIPER_DAMAGE_SCALE:float = 0.5

@export var gun_type:int = GUN_PISTOL
@export var Master_name:String = ""
@export var Team:String = ""

@export_category("运行时枪械参数")
@export var gun_range:float = 260.0
@export var damage_multiplier:float = 3.75
@export var fire_interval:float = 0.20
@export var magazine_size:int = 6
@export var reload_duration:float = 1.10
@export var projectile_speed:float = 580.0
@export var projectile_acceleration:float = 0.0
@export var projectile_max_speed:float = 580.0
@export var spread_degrees:float = 2.0
@export var knockback_distance:float = 0.0
@export var knockback_speed:float = 0.0
@export var explosion_radius:float = 0.0
@export var projectile_visual_size:float = 5.0
@export var gatling_charge_duration:float = 0.0

@export_category("加特林前摇颤抖")
@export_range(1.0,20.0,0.5) var gatling_shake_start_hz:float = 5.0
@export_range(10.0,60.0,0.5) var gatling_shake_end_hz:float = 34.0
@export_range(0.0,3.0,0.05) var gatling_shake_start_amplitude:float = 0.20
@export_range(0.0,5.0,0.05) var gatling_shake_end_amplitude:float = 1.25

@export_category("加特林音效")
@export_range(-30.0,6.0,0.5) var gatling_charge_volume_db:float = -7.0
@export_range(-30.0,6.0,0.5) var gatling_fire_volume_db:float = -5.0
@export_range(100.0,2000.0,25.0) var gatling_audio_max_distance:float = 900.0

@export_category("加特林扇区")
@export_range(4.0,40.0,1.0) var gatling_cone_half_angle_degrees:float = 12.0
@export_range(10.0,240.0,5.0) var gatling_turn_speed_degrees:float = 55.0
@export_range(0.02,0.35,0.01) var gatling_cone_alpha:float = 0.10

@export_category("视觉与生命周期")
@export_range(0.05,2.0,0.05) var owner_missing_grace:float = 0.35
@export var sniper_aim_active:bool = false
@export var sniper_aim_length:float = 0.0
@export var gatling_aim_angle_world:float = 0.0

var _ammo:int = 0
var _shot_cooldown:float = 0.0
var _reload_left:float = 0.0
var _target_id:int = 0
var _gatling_charge_left:float = 0.0
var _muzzle_flash_left:float = 0.0
var _base_sprite_scale:Vector2 = Vector2.ONE
var _base_sprite_position:Vector2 = Vector2.ZERO
var _gatling_shake_phase:float = 0.0
var _muzzle_offset_distance:float = 16.0
var _owner_missing_left:float = 0.35
var _shot_sfx_cooldown:float = 0.0
var _gatling_cone_fill:Polygon2D = null
var _gatling_cone_outline:Line2D = null
var _gatling_charge_player:AudioStreamPlayer2D = null
var _gatling_fire_player:AudioStreamPlayer2D = null
var _gatling_charge_audio_requested:bool = false
var _gatling_fire_audio_requested:bool = false

# 瞄准视觉使用带阻尼的角度弹簧。根节点只在“正立”的半平面内旋转；
# 目标位于左侧时改用水平镜像，因此不会把整张枪图上下倒转。
var _aim_angular_velocity:float = 0.0
var _aim_facing_left:bool = false
var _aim_world_direction:Vector2 = Vector2.RIGHT

@onready var _sprite:Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var _muzzle:Polygon2D = get_node_or_null("MuzzleFlash") as Polygon2D
@onready var _sniper_aim_line:Line2D = get_node_or_null("SniperAimLine") as Line2D


func _ready() -> void:
	add_to_group("ArmsDealerGun")
	add_to_group("BattleTransient")
	_configure_gun_stats()
	_setup_visual()
	_setup_gatling_audio_players()
	gatling_aim_angle_world = global_rotation
	_setup_gatling_cone_visual()
	_ammo = maxi(magazine_size,1)
	_gatling_charge_left = maxf(gatling_charge_duration,0.0)
	_owner_missing_left = maxf(owner_missing_grace,0.05)
	if _muzzle != null:
		_muzzle.visible = false
	_update_sniper_aim_visual()
func _configure_gun_stats() -> void:
	match gun_type:
		GUN_SNIPER:
			gun_range = 440.0
			damage_multiplier = 17.5
			fire_interval = 0.75
			magazine_size = 1
			reload_duration = 2.35
			projectile_speed = 1150.0
			projectile_max_speed = 1150.0
			spread_degrees = 0.15
			knockback_distance = 92.0
			knockback_speed = 860.0
			projectile_visual_size = 5.5
		GUN_PISTOL:
			gun_range = 255.0
			damage_multiplier = 2.0
			fire_interval = 0.18
			magazine_size = 6
			reload_duration = 1.05
			projectile_speed = 590.0
			projectile_max_speed = 590.0
			spread_degrees = 2.0
			projectile_visual_size = 4.2
		GUN_DEAGLE:
			gun_range = 292.0
			damage_multiplier = 8.0
			fire_interval = 0.62
			magazine_size = 4
			reload_duration = 1.55
			projectile_speed = 720.0
			projectile_max_speed = 720.0
			spread_degrees = 1.2
			projectile_visual_size = 5.2
		GUN_AK:
			gun_range = 305.0
			damage_multiplier = 2.5
			fire_interval = 0.105
			magazine_size = 20
			reload_duration = 1.80
			projectile_speed = 660.0
			projectile_max_speed = 660.0
			spread_degrees = 11.0
			projectile_visual_size = 4.5
		GUN_ROCKET:
			gun_range = 350.0
			damage_multiplier = 18.75
			fire_interval = 0.90
			magazine_size = 1
			reload_duration = 3.15
			projectile_speed = 105.0
			projectile_acceleration = 390.0
			projectile_max_speed = 640.0
			spread_degrees = 0.8
			explosion_radius = 82.0
			knockback_distance = 58.0
			knockback_speed = 670.0
			projectile_visual_size = 9.0
		GUN_GATLING:
			# V107：军火商基础 Damage=4；旧加特林单发3.5，因此用0.875倍保留原数值。
			# 加特林只负责近距离压制，缩小自动索敌区域，避免隔很远就提前锁定。
			gun_range = 148.0
			damage_multiplier = 0.875
			fire_interval = 0.055
			magazine_size = 72
			reload_duration = 4.20
			projectile_speed = 760.0
			projectile_max_speed = 760.0
			spread_degrees = 5.5
			projectile_visual_size = 3.8
			gatling_charge_duration = 1.25


func _setup_visual() -> void:
	if _sprite == null:
		return
	var texture:Texture2D = _load_gun_texture()
	var visual_dimension:float = _gun_visual_dimension()
	if texture != null:
		_sprite.texture = texture
		# 任何枪都不再使用 flip_v。素材朝向 + 左右朝向都统一由 flip_h 处理，
		# 这样瞄准跨过角色背后时不会整张上下颠倒。
		_sprite.flip_v = false
		var size:Vector2 = texture.get_size()
		var max_dim:float = maxf(size.x,size.y)
		if max_dim > 0.0:
			_sprite.scale = Vector2.ONE * (visual_dimension / max_dim)
	_base_sprite_scale = _sprite.scale
	_base_sprite_position = _sprite.position
	_update_sprite_facing()
	_muzzle_offset_distance = maxf(visual_dimension * 0.48,7.0)
	_configure_muzzle_visual(visual_dimension)


func _setup_gatling_audio_players() -> void:
	if gun_type != GUN_GATLING:
		return

	_gatling_charge_player = AudioStreamPlayer2D.new()
	_gatling_charge_player.name = "GatlingChargeAudio"
	_gatling_charge_player.stream = GATLING_CHARGE_STREAM
	_gatling_charge_player.volume_db = gatling_charge_volume_db
	_gatling_charge_player.max_distance = gatling_audio_max_distance
	_gatling_charge_player.max_polyphony = 1
	add_child(_gatling_charge_player)

	_gatling_fire_player = AudioStreamPlayer2D.new()
	_gatling_fire_player.name = "GatlingFireAudio"
	var fire_stream:AudioStream = GATLING_FIRE_STREAM.duplicate() as AudioStream
	# 这段是短促的加特林发射声。持续扫射时循环播放，停止射击就立即 stop。
	if fire_stream is AudioStreamMP3:
		(fire_stream as AudioStreamMP3).loop = true
	_gatling_fire_player.stream = fire_stream
	_gatling_fire_player.volume_db = gatling_fire_volume_db
	_gatling_fire_player.max_distance = gatling_audio_max_distance
	_gatling_fire_player.max_polyphony = 1
	add_child(_gatling_fire_player)


func _gatling_charge_audio_pitch_scale(duration:float) -> float:
	if _gatling_charge_player == null or _gatling_charge_player.stream == null:
		return 1.0
	var source_length:float = _gatling_charge_player.stream.get_length()
	if source_length <= 0.001:
		return 1.0
	# AudioStreamPlayer2D.pitch_scale 同时改变速度和音高。
	# 播放时长约为 source_length / pitch_scale，因此这里用 source/duration
	# 让蓄力声音自动拉伸/压缩到当前 gatling_charge_duration。
	return clampf(source_length / maxf(duration,0.01),0.05,4.0)


func _set_gatling_charge_audio(active:bool) -> void:
	if gun_type != GUN_GATLING or _gatling_charge_audio_requested == active:
		return
	_gatling_charge_audio_requested = active
	if multiplayer.has_multiplayer_peer():
		_rpc_set_gatling_charge_audio.rpc(active,maxf(gatling_charge_duration,0.01))
	else:
		_rpc_set_gatling_charge_audio(active,maxf(gatling_charge_duration,0.01))


func _set_gatling_fire_audio(active:bool) -> void:
	if gun_type != GUN_GATLING or _gatling_fire_audio_requested == active:
		return
	_gatling_fire_audio_requested = active
	if multiplayer.has_multiplayer_peer():
		_rpc_set_gatling_fire_audio.rpc(active)
	else:
		_rpc_set_gatling_fire_audio(active)


@rpc("authority","call_local","reliable")
func _rpc_set_gatling_charge_audio(active:bool,duration:float) -> void:
	if _gatling_charge_player == null:
		return
	_gatling_charge_player.stop()
	if not active:
		return
	_gatling_charge_player.volume_db = gatling_charge_volume_db
	_gatling_charge_player.max_distance = gatling_audio_max_distance
	_gatling_charge_player.pitch_scale = _gatling_charge_audio_pitch_scale(duration)
	_gatling_charge_player.play()


@rpc("authority","call_local","reliable")
func _rpc_set_gatling_fire_audio(active:bool) -> void:
	if _gatling_fire_player == null:
		return
	if not active:
		_gatling_fire_player.stop()
		return
	_gatling_fire_player.volume_db = gatling_fire_volume_db
	_gatling_fire_player.max_distance = gatling_audio_max_distance
	_gatling_fire_player.pitch_scale = 1.0
	if not _gatling_fire_player.playing:
		_gatling_fire_player.play()


func _setup_gatling_cone_visual() -> void:
	if gun_type != GUN_GATLING:
		return

	_gatling_cone_fill = Polygon2D.new()
	_gatling_cone_fill.name = "GatlingFireCone"
	_gatling_cone_fill.z_index = -2
	_gatling_cone_fill.color = Color(1.0,0.18,0.08,clampf(gatling_cone_alpha,0.02,0.35))
	add_child(_gatling_cone_fill)

	_gatling_cone_outline = Line2D.new()
	_gatling_cone_outline.name = "GatlingFireConeOutline"
	_gatling_cone_outline.z_index = -1
	_gatling_cone_outline.width = 0.9
	_gatling_cone_outline.default_color = Color(1.0,0.34,0.18,clampf(gatling_cone_alpha * 1.55,0.04,0.45))
	_gatling_cone_outline.antialiased = true
	add_child(_gatling_cone_outline)

	_rebuild_gatling_cone_geometry()
	_update_gatling_cone_visual()


func _rebuild_gatling_cone_geometry() -> void:
	if _gatling_cone_fill == null or _gatling_cone_outline == null:
		return
	var range_value:float = maxf(gun_range,1.0)
	var half_angle:float = deg_to_rad(clampf(gatling_cone_half_angle_degrees,1.0,80.0))
	var half_width:float = tan(half_angle) * range_value
	var points:= PackedVector2Array([
		Vector2.ZERO,
		Vector2(range_value,-half_width),
		Vector2(range_value,half_width),
	])
	_gatling_cone_fill.polygon = points
	_gatling_cone_outline.points = PackedVector2Array([
		Vector2.ZERO,
		Vector2(range_value,-half_width),
		Vector2(range_value,half_width),
		Vector2.ZERO,
	])


func _update_gatling_cone_visual() -> void:
	if _gatling_cone_fill == null or _gatling_cone_outline == null:
		return
	var show:bool = gun_type == GUN_GATLING
	_gatling_cone_fill.visible = show
	_gatling_cone_outline.visible = show
	if not show:
		return

	# 三角形与真正判定使用同一个世界朝向。z_index 为负，所以加特林图片始终盖在它上面。
	_gatling_cone_fill.global_position = global_position
	_gatling_cone_outline.global_position = global_position
	_gatling_cone_fill.global_rotation = gatling_aim_angle_world
	_gatling_cone_outline.global_rotation = gatling_aim_angle_world


func _gun_visual_dimension() -> float:
	# 旧版所有枪统一拉到 48 像素，手枪会和角色本体差不多大。
	# 改成按枪型分别控制最大显示尺寸：手枪最小，长枪只保留必要辨识度。
	match gun_type:
		GUN_SNIPER:
			return 34.0
		GUN_PISTOL:
			return 13.0
		GUN_DEAGLE:
			return 16.0
		GUN_AK:
			return 31.0
		GUN_ROCKET:
			return 34.0
		GUN_GATLING:
			return 36.0
	return 28.0


func _configure_muzzle_visual(visual_dimension:float) -> void:
	if _muzzle == null:
		return
	var start_x:float = maxf(visual_dimension * 0.40,5.0)
	var flare:float = clampf(visual_dimension * 0.22,3.0,8.0)
	_muzzle.polygon = PackedVector2Array([
		Vector2(start_x,0.0),
		Vector2(start_x + flare,-flare * 0.42),
		Vector2(start_x + flare * 1.65,0.0),
		Vector2(start_x + flare,flare * 0.42)
	])


func _load_gun_texture() -> Texture2D:
	var names:Array[String] = ["狙击枪","小手枪","沙鹰","AK","火箭筒","加特林"]
	var index:int = clampi(gun_type,0,names.size() - 1)
	var base:String = names[index]
	for ext:String in ["png","webp","svg"]:
		var path:String = WEAPON_IMAGE_DIR.path_join(base + "." + ext)
		if ResourceLoader.exists(path):
			var res:Resource = ResourceLoader.load(path)
			if res is Texture2D:
				return res as Texture2D
	return null


func _physics_process(delta:float) -> void:
	_update_muzzle_visual(delta)
	_update_sniper_aim_visual()
	_update_gatling_cone_visual()
	if not is_multiplayer_authority():
		return

	if not _keep_alive_with_owner(delta):
		return

	_shot_cooldown = maxf(_shot_cooldown - delta,0.0)
	_shot_sfx_cooldown = maxf(_shot_sfx_cooldown - delta,0.0)
	if _reload_left > 0.0:
		_reload_left = maxf(_reload_left - delta,0.0)
		if _reload_left <= 0.0:
			_ammo = maxi(magazine_size,1)
			if gun_type == GUN_GATLING:
				_gatling_charge_left = maxf(gatling_charge_duration,0.0)

	if gun_type == GUN_GATLING:
		_process_gatling(delta)
	else:
		_process_standard_gun(delta)


func _process_standard_gun(delta:float) -> void:
	var target:ball = _get_target()
	if target != null and global_position.distance_to(target.global_position) > gun_range:
		_target_id = 0
		target = null
	if target == null:
		target = _acquire_nearest_target(gun_range)
	if target == null:
		_set_sniper_aim_state(false,0.0)
		return

	if gun_type == GUN_SNIPER:
		var predicted_point:Vector2 = _predict_intercept_point(target,projectile_speed)
		_aim_at(predicted_point,0.42,delta)
		_set_sniper_aim_state(true,minf(global_position.distance_to(predicted_point),gun_range))
	else:
		_set_sniper_aim_state(false,0.0)
		_aim_at(target.global_position,0.28,delta)

	if _reload_left > 0.0 or _shot_cooldown > 0.0:
		return
	if _ammo <= 0:
		_start_reload()
		return
	_fire_at_target(target)


func _process_gatling(delta:float) -> void:
	_set_sniper_aim_state(false,0.0)

	var old_id:int = _target_id
	var target:ball = _get_target()
	if target != null and global_position.distance_to(target.global_position) > gun_range:
		_target_id = 0
		target = null
	if target == null:
		target = _acquire_nearest_target(gun_range)

	# 更换目标、目标消失，都会让下一次有效开火重新完整蓄力。
	if _target_id != old_id:
		_reset_gatling_charge()

	if target == null:
		_reset_gatling_charge()
		return

	# 加特林不会瞬间对准敌人，而是按固定角速度缓慢转向。
	_aim_gatling_toward(target.global_position,delta)

	# 真正的开火限制是屏幕上显示的三角形。敌人一旦离开三角形，
	# 无论之前蓄力到多少，下次重新进入时都必须从头蓄力。
	if not _is_target_inside_gatling_triangle(target):
		_reset_gatling_charge()
		return

	if _reload_left > 0.0:
		_stop_gatling_shake()
		_set_gatling_charge_audio(false)
		_set_gatling_fire_audio(false)
		return
	if _ammo <= 0:
		_start_reload()
		return

	if _gatling_charge_left > 0.0:
		# 进入有效三角区后才开始蓄力声音；任何打断都会在 _reset_gatling_charge()
		# 里立刻 stop，重新进入时从声音开头重新蓄力。
		_set_gatling_fire_audio(false)
		_set_gatling_charge_audio(true)
		_gatling_charge_left = maxf(_gatling_charge_left - delta*preload("res://scripts/effects/我的世界/mc_enchantments.gd").charge_speed(self),0.0)
		_show_charge_visual(delta)
		return

	# 前摇完成后的第一发开始前立即归位；持续开火阶段不再颤抖。
	_stop_gatling_shake()
	_set_gatling_charge_audio(false)
	_set_gatling_fire_audio(true)
	if _shot_cooldown <= 0.0:
		_fire_at_target(target)


func _reset_gatling_charge() -> void:
	_gatling_charge_left = maxf(gatling_charge_duration,0.0)
	_gatling_shake_phase = 0.0
	_stop_gatling_shake()
	_set_gatling_charge_audio(false)
	_set_gatling_fire_audio(false)


func _aim_gatling_toward(point:Vector2,delta:float) -> void:
	var to_point:Vector2 = point - global_position
	if to_point.length_squared() <= 0.000001:
		return

	var wanted_angle:float = to_point.angle()
	var max_step:float = deg_to_rad(maxf(gatling_turn_speed_degrees,1.0)) * maxf(delta,0.0)
	var difference:float = wrapf(wanted_angle - gatling_aim_angle_world,-PI,PI)
	gatling_aim_angle_world = wrapf(
		gatling_aim_angle_world + clampf(difference,-max_step,max_step),
		-PI,
		PI
	)
	_aim_world_direction = Vector2.RIGHT.rotated(gatling_aim_angle_world)
	_aim_facing_left = _aim_world_direction.x < 0.0

	# 继续沿用项目现有的“左侧只水平镜像、不把枪图倒过来”视觉规则。
	var visual_angle:float = gatling_aim_angle_world
	if _aim_facing_left:
		visual_angle = wrapf(visual_angle + PI,-PI,PI)
	rotation = visual_angle
	_aim_angular_velocity = 0.0
	_update_sprite_facing()


func _is_target_inside_gatling_triangle(target:ball) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var offset:Vector2 = target.global_position - global_position
	if offset.length_squared() <= 0.000001:
		return true

	var forward:Vector2 = _aim_world_direction.normalized()
	var forward_distance:float = offset.dot(forward)
	if forward_distance < 0.0 or forward_distance > gun_range:
		return false

	# 用三角形而不是扇形：越靠近枪口越窄，到最远端达到最大宽度。
	var half_angle:float = deg_to_rad(clampf(gatling_cone_half_angle_degrees,1.0,80.0))
	var max_lateral:float = tan(half_angle) * forward_distance
	var lateral_distance:float = absf(offset.cross(forward))
	return lateral_distance <= max_lateral


func _show_charge_visual(delta:float) -> void:
	if _sprite == null:
		return

	# 不再通过缩放做“呼吸”前摇。改为位置颤抖，并让频率随着蓄力完成度持续提高。
	# 使用累积 phase 而不是每帧 randf()，这样颤抖连续、不会出现随机跳点。
	var duration:float = maxf(gatling_charge_duration,0.001)
	var progress:float = 1.0 - clampf(_gatling_charge_left / duration,0.0,1.0)
	var eased:float = progress * progress
	var frequency:float = lerpf(gatling_shake_start_hz,gatling_shake_end_hz,eased)
	var amplitude:float = lerpf(gatling_shake_start_amplitude,gatling_shake_end_amplitude,progress)
	_gatling_shake_phase = fmod(_gatling_shake_phase + TAU * frequency * maxf(delta,0.0),TAU)

	var shake:= Vector2(
		sin(_gatling_shake_phase),
		sin(_gatling_shake_phase * 1.73 + 0.65) * 0.58
	) * amplitude
	_sprite.position = _base_sprite_position + shake
	_sprite.scale = _base_sprite_scale


func _stop_gatling_shake() -> void:
	if _sprite == null:
		return
	_sprite.position = _base_sprite_position
	_sprite.scale = _base_sprite_scale


func _aim_at(point:Vector2,response:float,delta:float) -> void:
	var to_point:Vector2 = point - global_position
	if to_point.length_squared() <= 0.000001:
		return

	_aim_world_direction = to_point.normalized()
	var new_facing_left:bool = _aim_world_direction.x < 0.0
	if new_facing_left != _aim_facing_left:
		_aim_facing_left = new_facing_left
		# 换边时保留一点反向惯性，视觉上会轻微弹一下，而不是机械瞬切。
		_aim_angular_velocity *= -0.38

	# 左侧目标把实际角度折回 180°，让根节点始终维持正立：
	# 例如 170° -> -10°，再通过 flip_h 显示为朝左。
	var target_angle:float = _aim_world_direction.angle()
	if _aim_facing_left:
		target_angle = wrapf(target_angle + PI,-PI,PI)

	# 欠阻尼角度弹簧：有轻微过冲和回弹，同时随 delta 保持稳定。
	var response01:float = clampf(response,0.0,1.0)
	var stiffness:float = lerpf(62.0,118.0,response01)
	var damping:float = sqrt(stiffness) * 1.30
	var angle_error:float = wrapf(target_angle - rotation,-PI,PI)
	_aim_angular_velocity += angle_error * stiffness * maxf(delta,0.0)
	_aim_angular_velocity *= exp(-damping * maxf(delta,0.0))
	_aim_angular_velocity = clampf(_aim_angular_velocity,-12.0,12.0)
	rotation = wrapf(rotation + _aim_angular_velocity * maxf(delta,0.0),-PI,PI)

	_update_sprite_facing()


func _update_sprite_facing() -> void:
	if _sprite == null:
		return

	# 禁止上下镜像。需要翻面时只做左右镜像。
	_sprite.flip_v = false

	# 两把手枪和火箭筒的源图枪口都朝左，长枪源图枪口朝右。
	# 先校正素材基准，再叠加“面向左侧”的水平镜像。
	if gun_type in [GUN_PISTOL,GUN_DEAGLE,GUN_ROCKET]:
		_sprite.flip_h = not _aim_facing_left
	else:
		_sprite.flip_h = _aim_facing_left

	# 根节点始终正立，因此枪口闪光也要在左朝向时镜像到 -X 一侧。
	if _muzzle != null:
		_muzzle.scale.x = -1.0 if _aim_facing_left else 1.0


func _fire_at_target(target:ball) -> void:
	if target == null or not is_instance_valid(target):
		return
	var aim_dir:Vector2
	if gun_type == GUN_SNIPER:
		aim_dir = _predict_intercept_direction(target,projectile_speed)
	elif gun_type == GUN_GATLING:
		# 加特林真正沿当前枪口方向射击；慢转向因此不仅是视觉效果。
		aim_dir = _aim_world_direction.normalized()
	else:
		aim_dir = (target.global_position - global_position).normalized()
	if aim_dir.length_squared() <= 0.000001:
		aim_dir = _aim_world_direction
	if spread_degrees > 0.0:
		aim_dir = aim_dir.rotated(deg_to_rad(randf_range(-spread_degrees,spread_degrees)))

	_spawn_projectile(aim_dir.normalized())
	_ammo -= 1
	_shot_cooldown = maxf(fire_interval,0.01)
	_show_muzzle_flash_everywhere()
	_play_fire_sfx()
	if _ammo <= 0:
		_start_reload()


func _spawn_projectile(aim_dir:Vector2) -> void:
	var projectile:Area2D = PROJECTILE_SCENE.instantiate() as Area2D
	if projectile == null:
		return

	var master:ball = _resolve_master()
	var shot_damage:float = 4.0 * maxf(damage_multiplier,0.0)
	if master != null and is_instance_valid(master):
		shot_damage = master.attack_damage(damage_multiplier)
	# 军火商平衡调整：狙击枪保持原伤害，其余枪械在最终攻击力结算后统一减半。
	if gun_type != GUN_SNIPER:
		shot_damage *= NON_SNIPER_DAMAGE_SCALE

	projectile.set("Master_name",Master_name)
	projectile.set_meta("allay_launch_sound",load("res://scripts/characters/我的世界/allay/return_audio.gd").gun_sound(gun_type))
	projectile.set("Team",Team)
	projectile.set("projectile_kind",1 if gun_type == GUN_ROCKET else 0)
	projectile.set("damage_amount",shot_damage)
	projectile.set("speed",projectile_speed)
	projectile.set("acceleration",projectile_acceleration)
	projectile.set("max_speed",projectile_max_speed)
	projectile.set("direction",aim_dir)
	projectile.set("knockback_distance",knockback_distance)
	projectile.set("knockback_speed",knockback_speed)
	projectile.set("explosion_radius",explosion_radius)
	projectile.set("visual_size",projectile_visual_size)
	projectile.set("lifetime",5.0 if gun_type != GUN_ROCKET else 6.5)
	projectile.global_position = global_position + aim_dir * _muzzle_offset_distance
	projectile.global_rotation = aim_dir.angle()
	projectile.name = Game.return_random_name(projectile)
	get_tree().current_scene.add_child(projectile,true)


func _start_reload() -> void:
	if _reload_left > 0.0:
		return
	_reload_left = maxf(reload_duration,0.05)
	_play_reload_sfx()
	if gun_type == GUN_GATLING:
		_gatling_charge_left = maxf(gatling_charge_duration,0.0)
		_gatling_shake_phase = 0.0
		_stop_gatling_shake()
		_set_gatling_charge_audio(false)
		_set_gatling_fire_audio(false)


func _play_fire_sfx() -> void:
	# 两把“狙击枪”统一使用用户提供的狙击枪发射音效。
	if gun_type == GUN_SNIPER:
		_play_registered_sfx_everywhere(
			"狙击枪发射",
			{"volume":-2.0,"pitch":1.0},
			false,
			true
		)
		return

	# 火箭筒使用用户提供的专用发射音效。
	if gun_type == GUN_ROCKET:
		_play_registered_sfx_everywhere(
			"火箭筒发射",
			{"volume":-5.0,"pitch":1.0},
			false,
			true
		)
		return

	# 加特林使用用户提供的专用循环发射音效，由 _process_gatling() 控制启停。
	if gun_type == GUN_GATLING:
		return
	var key:String = "gun_a"
	var volume_db:float = -7.0
	var pitch:float = 1.0
	match gun_type:
		GUN_SNIPER:
			key = "gun_b"
			volume_db = -2.0
			pitch = 0.74
		GUN_PISTOL:
			key = "gun_a"
			volume_db = -8.0
			pitch = 1.10
		GUN_DEAGLE:
			key = "gun_b"
			volume_db = -4.0
			pitch = 0.90
		GUN_AK:
			key = "gun_b"
			volume_db = -9.0
			pitch = 1.08
	_play_local_sfx_everywhere(key,global_position,volume_db,pitch,900.0)


func _play_reload_sfx() -> void:
	_play_local_sfx_everywhere("reload",global_position,-8.0,randf_range(0.96,1.04),620.0)


func _play_registered_sfx_everywhere(
	sfx_name:String,
	params:Dictionary = {},
	randomize_sound:bool = false,
	create_new:bool = true
) -> void:
	if Audios == null or Audios.Sfx == null or not Audios.Sfx.has_node(sfx_name):
		return
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc(sfx_name,params,randomize_sound,create_new)
	else:
		Audios.play_sfx(sfx_name,params,randomize_sound,create_new)


func _play_local_sfx_everywhere(key:String,position_value:Vector2,volume_db:float,pitch:float,max_distance:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_local_sfx.rpc(key,position_value,volume_db,pitch,max_distance)
	else:
		_rpc_play_local_sfx(key,position_value,volume_db,pitch,max_distance)


@rpc("authority","call_local","unreliable")
func _rpc_play_local_sfx(key:String,position_value:Vector2,volume_db:float,pitch:float,max_distance:float) -> void:
	LOCAL_SFX.play(self,key,position_value,volume_db,pitch,max_distance)


func _get_target() -> ball:
	if _target_id <= 0 or not is_instance_id_valid(_target_id):
		_target_id = 0
		return null
	var obj:Object = instance_from_id(_target_id)
	if not obj is ball:
		_target_id = 0
		return null
	var target:ball = obj as ball
	if not _is_valid_enemy(target):
		_target_id = 0
		return null
	return target


func _acquire_nearest_target(max_range:float) -> ball:
	var nearest:ball = null
	var nearest_dist_sq:float = maxf(max_range,1.0) * maxf(max_range,1.0)
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if not _is_valid_enemy(target):
			continue
		var distance_sq:float = global_position.distance_squared_to(target.global_position)
		if distance_sq <= nearest_dist_sq:
			nearest_dist_sq = distance_sq
			nearest = target
	if nearest != null:
		_target_id = nearest.get_instance_id()
	return nearest


func _is_valid_enemy(target:ball) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(self,target): return false # 皓宸复制品及其产物不把己方选为目标
	if target == null or not is_instance_valid(target) or target.health <= 0:
		return false
	if not target.is_combat_targetable():
		return false
	var master:ball = _resolve_master()
	if master != null and target == master:
		return false
	if Team != "" and target.Team != "" and target.Team == Team:
		return false
	return true


func _resolve_master() -> ball:
	if Master_name.is_empty():
		return null
	var world:Node = get_tree().current_scene
	if world == null:
		return null
	var resolved:Node = world.get_node_or_null(NodePath(Master_name))
	if resolved is ball:
		return resolved as ball
	# 兼容军火商不直接挂在 current_scene 根节点下的场景结构。
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if node is ball and str(node.name) == Master_name:
			return node as ball
	return null


func _keep_alive_with_owner(delta:float) -> bool:
	var master:ball = _resolve_master()
	if master != null and is_instance_valid(master) and master.health > 0:
		_owner_missing_left = maxf(owner_missing_grace,0.05)
		return true

	_target_id = 0
	_set_sniper_aim_state(false,0.0)
	if gun_type == GUN_GATLING:
		_set_gatling_charge_audio(false)
		_set_gatling_fire_audio(false)
	_owner_missing_left = maxf(_owner_missing_left - delta,0.0)
	if _owner_missing_left <= 0.0:
		Game.free_node(self)
	return false


func _set_sniper_aim_state(active:bool,length_value:float) -> void:
	if gun_type != GUN_SNIPER:
		active = false
		length_value = 0.0
	sniper_aim_active = active
	sniper_aim_length = clampf(length_value,0.0,gun_range)


func _update_sniper_aim_visual() -> void:
	if _sniper_aim_line == null:
		return
	var should_show:bool = gun_type == GUN_SNIPER and sniper_aim_active and sniper_aim_length > _muzzle_offset_distance
	_sniper_aim_line.visible = should_show
	if not should_show:
		return
	var side:float = -1.0 if _aim_facing_left else 1.0
	var start_x:float = _muzzle_offset_distance * 0.72 * side
	_sniper_aim_line.points = PackedVector2Array([
		Vector2(start_x,0.0),
		Vector2(sniper_aim_length * side,0.0)
	])
	var pulse:float = 0.68 + sin(float(Time.get_ticks_msec()) * 0.010) * 0.16
	_sniper_aim_line.modulate = Color(1.0,1.0,1.0,clampf(pulse,0.45,0.90))


func _predict_intercept_point(target:ball,shot_speed:float) -> Vector2:
	var relative:Vector2 = target.global_position - global_position
	if relative.length_squared() <= 0.000001:
		return target.global_position
	var target_velocity:Vector2 = target.velocity
	var s:float = maxf(shot_speed,1.0)
	var a:float = target_velocity.dot(target_velocity) - s * s
	var b:float = 2.0 * relative.dot(target_velocity)
	var c:float = relative.dot(relative)
	var t:float = -1.0

	if absf(a) < 0.00001:
		if absf(b) > 0.00001:
			t = -c / b
	else:
		var disc:float = b * b - 4.0 * a * c
		if disc >= 0.0:
			var root:float = sqrt(disc)
			var t1:float = (-b - root) / (2.0 * a)
			var t2:float = (-b + root) / (2.0 * a)
			if t1 > 0.0 and t2 > 0.0:
				t = minf(t1,t2)
			elif t1 > 0.0:
				t = t1
			elif t2 > 0.0:
				t = t2

	if t <= 0.0:
		t = relative.length() / s
	t = clampf(t,0.0,1.15)
	return target.global_position + target_velocity * t


func _predict_intercept_direction(target:ball,shot_speed:float) -> Vector2:
	var point:Vector2 = _predict_intercept_point(target,shot_speed)
	var direction_to_point:Vector2 = point - global_position
	if direction_to_point.length_squared() <= 0.000001:
		return _aim_world_direction
	return direction_to_point.normalized()


func _show_muzzle_flash_everywhere() -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_muzzle_flash.rpc()
	else:
		_rpc_muzzle_flash()


@rpc("authority","call_local","unreliable")
func _rpc_muzzle_flash() -> void:
	_muzzle_flash_left = 0.055
	if _muzzle != null:
		_muzzle.visible = true
	if _sprite != null:
		_sprite.scale = _base_sprite_scale * Vector2(0.94,1.06)


func _update_muzzle_visual(delta:float) -> void:
	if _muzzle_flash_left > 0.0:
		_muzzle_flash_left = maxf(_muzzle_flash_left - delta,0.0)
		if _muzzle_flash_left <= 0.0:
			if _muzzle != null:
				_muzzle.visible = false
			if _sprite != null:
				_sprite.scale = _base_sprite_scale
	elif _sprite != null and gun_type != GUN_GATLING:
		_sprite.scale = _base_sprite_scale
