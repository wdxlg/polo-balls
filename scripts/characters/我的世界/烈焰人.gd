extends ball

const NATIVE_MODEL_ANIMATION = preload("res://scripts/effects/我的世界/mc_native_batch2.gd")
var _native_mob_animation:Node

const FIREBALL_SCENE:PackedScene = preload("res://scenes/shooter/我的世界/烈焰弹.tscn")
const BURN_TICK_SFX:AudioStream = preload("res://audio/status/debuff/烫伤.wav")
const BLAZE_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/烈焰人/动画/烈焰人_00000.png")
const CREEPER_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/苦力怕/苦力怕.webp")
const CREEPER_REFERENCE_SPRITE_SCALE:float = 0.52
const FIREBALL_LAUNCH_SFX:AudioStream = preload("res://audio/characters/我的世界/烈焰人/烈焰弹发射.ogg")
const BREATH_SFX:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/烈焰人/呼吸1.ogg"),
	preload("res://audio/characters/我的世界/烈焰人/呼吸2.ogg"),
	preload("res://audio/characters/我的世界/烈焰人/呼吸3.ogg"),
	preload("res://audio/characters/我的世界/烈焰人/呼吸4.ogg"),
]
const HURT_SFX:Array[AudioStream] = [
	preload("res://audio/characters/我的世界/烈焰人/受伤1.ogg"),
	preload("res://audio/characters/我的世界/烈焰人/受伤2.ogg"),
	preload("res://audio/characters/我的世界/烈焰人/受伤3.ogg"),
	preload("res://audio/characters/我的世界/烈焰人/受伤4.ogg"),
]
const DEATH_SFX:AudioStream = preload("res://audio/characters/我的世界/烈焰人/死亡.ogg")
const MC_SMOKE_SCENE:PackedScene = preload("res://scenes/effects/我的世界/MC烟雾粒子.tscn")
const BLAZE_HIT_FLASH_SHADER:Shader = preload("res://shaders/Set_RGB_Color.gdshader")

@export_category("烈焰人 / 视觉")
# 原版烈焰人 1.8 格、苦力怕 1.7 格；1.18 是旧 SVG 素材（含大量透明留白）时代的补偿值，
# 换成原生逐帧模型后同一比例会把烈焰人放大约 30%。
@export_range(0.75,1.40,0.01) var body_size_vs_creeper:float = 1.0

@export_category("烈焰人 / 连射")
@export_range(1,8,1) var burst_min_shots:int = 3
@export_range(1,8,1) var burst_max_shots:int = 5
@export_range(0.08,0.80,0.01) var burst_shot_gap:float = 0.20
@export_range(100.0,800.0,10.0) var fireball_speed:float = 330.0
@export_range(0.1,3.0,0.05) var fireball_damage_multiplier:float = 1.0
@export_range(0.2,8.0,0.1) var fireball_burn_duration:float = 3.2
@export_range(0.0,1.0,0.01) var fireball_burn_tick_damage_multiplier:float = 0.10
@export_range(0.0,1.0,0.01) var fire_patch_tick_damage_multiplier:float = 0.11
@export_range(0.0,1.0,0.01) var fire_patch_burn_tick_damage_multiplier:float = 0.05
@export_range(8.0,100.0,1.0) var fire_patch_radius:float = 34.0
@export_range(0.5,10.0,0.1) var fire_patch_duration:float = 4.5
@export_range(80.0,900.0,10.0) var attack_search_range:float = 520.0

@export_category("烈焰人 / 烈焰棒环绕")
@export_range(12.0,100.0,1.0) var rod_orbit_x:float = 27.0
@export_range(3.0,60.0,1.0) var rod_orbit_y:float = 10.0
@export_range(0.1,4.0,0.05) var rod_orbit_speed:float = 1.45
@export_range(30.0,140.0,1.0) var rod_attack_orbit_x:float = 72.0
@export_range(10.0,90.0,1.0) var rod_attack_orbit_y:float = 30.0
@export_range(2.0,16.0,0.1) var rod_attack_spin_speed:float = 8.0
@export_range(0.10,1.20,0.01) var rod_attack_expand_duration:float = 0.42
@export_range(0.10,1.50,0.01) var rod_attack_recover_duration:float = 0.72
@export_range(0.05,1.5,0.05) var rod_collision_damage_multiplier:float = 0.50
@export_range(0.5,1.0,0.01) var rod_back_scale:float = 0.82
@export_range(1.0,1.5,0.01) var rod_front_scale:float = 1.16

@export_category("烈焰人 / 烟雾")
@export_range(0.08,1.00,0.01) var smoke_interval_min:float = 0.20
@export_range(0.08,1.20,0.01) var smoke_interval_max:float = 0.38
@export_range(4.0,20.0,0.5) var smoke_visual_diameter:float = 9.0

@export_category("烈焰人 / 声音")
@export_range(0.0,1.0,0.01) var hurt_voice_chance:float = 0.35
@export_range(0.0,3.0,0.05) var hurt_voice_cooldown:float = 0.55
@export_range(0.0,8.0,0.1) var breath_first_delay_min:float = 1.4
@export_range(0.0,12.0,0.1) var breath_first_delay_max:float = 3.4
@export_range(0.0,12.0,0.1) var breath_silence_min:float = 1.6
@export_range(0.0,20.0,0.1) var breath_silence_max:float = 4.2

@onready var _body_anim:AnimatedSprite2D = $Graphics/AnimatedSprite2D
@onready var _rod_a:AnimatableBody2D = $BlazeRodA
@onready var _rod_b:AnimatableBody2D = $BlazeRodB
@onready var _rod_damage_a:Area2D = $BlazeRodA/DamageArea
@onready var _rod_damage_b:Area2D = $BlazeRodB/DamageArea
@onready var _breath_audio:AudioStreamPlayer2D = $BreathAudio
@onready var _hurt_audio:AudioStreamPlayer2D = $HurtAudio

var _burst_active:bool = false
var _projectile_serial:int = 0
var _rod_phase:float = 0.0
var _rod_attack_pose:bool = false
var _rod_attack_mix:float = 0.0
var _rod_hit_targets:Dictionary = {}
var _audio_rng:=RandomNumberGenerator.new()
var _visual_rng:=RandomNumberGenerator.new()
var _smoke_time_left:float = 0.0
var _breath_time_left:float = 0.0
var _hurt_voice_cooldown_left:float = 0.0
var _death_sfx_played:bool = false
var _blaze_facing_right:bool = false
var _blaze_facing_last_position:Vector2 = Vector2.ZERO
var _graphics_facing_abs_scale:Vector2 = Vector2.ONE

func _ready() -> void:
	# 明确绑定可见的动画节点，避免继承场景回退到隐藏的旧 Image。
	image = _body_anim
	_body_anim.show()
	$Graphics/Image.hide()
	# 55 帧素材原始朝向为左。V83 不再依赖公共 Shader 镜像是否对 AnimatedSprite2D 生效，
	# 而是用 Graphics 节点的 X 符号做最终镜像，保证整套逐帧动画真正改变朝向。
	dir_left = true
	Has_Collision_Damage = false
	Can_Attack = true
	Can_Skill = false
	Health_Restore = 0
	_fit_body_to_creeper_size()
	if graphics != null:
		_graphics_facing_abs_scale = Vector2(maxf(absf(graphics.scale.x),0.001),maxf(absf(graphics.scale.y),0.001))
	_blaze_facing_last_position = global_position
	super._ready()
	_native_mob_animation = NATIVE_MODEL_ANIMATION.attach(self,"blaze")
	_ensure_blaze_hit_flash_material()
	add_to_group("MinecraftBlaze")
	_apply_blaze_facing(false)
	# 烈焰人整套伪 3D 视觉需要允许跨出地图矩形显示。
	# World 的地图外遮罩是 z=90、黑色地图边框是 z=100：
	# 人物放 97，棒子后/侧/前分别放 96/97/98，血条放 99。
	# 这样两根棒无论绕到前后都不会被地图外遮罩切掉，同时仍保留
	# “后方被人物遮挡 / 前方遮挡人物”的伪 3D 层级。
	if graphics != null:
		graphics.z_as_relative = false
		graphics.z_index = 97
	if health_bar != null:
		health_bar.z_as_relative = false
		health_bar.z_index = 99

	_audio_rng.seed = Game.battle_rng_seed_or("scripts/characters/我的世界/烈焰人.gd:_audio_rng.seed",maxi(abs(int(Time.get_ticks_usec()) ^ int(get_instance_id())), 1))
	_visual_rng.seed = Game.battle_rng_seed_or("scripts/characters/我的世界/烈焰人.gd:_visual_rng.seed",maxi(abs(int(Time.get_ticks_usec()) ^ int(get_instance_id()) ^ 0x51A7E), 1))
	_smoke_time_left = _visual_rng.randf_range(minf(smoke_interval_min,smoke_interval_max),maxf(smoke_interval_min,smoke_interval_max))
	var first_low:float = minf(breath_first_delay_min,breath_first_delay_max)
	var first_high:float = maxf(breath_first_delay_min,breath_first_delay_max)
	_breath_time_left = _audio_rng.randf_range(first_low,first_high)
	_hurt_voice_cooldown_left = 0.0

	_setup_rod(_rod_a,"BlazeRodA")
	_setup_rod(_rod_b,"BlazeRodB")
	_setup_rod_damage_area(_rod_damage_a)
	_setup_rod_damage_area(_rod_damage_b)
	_update_rods(0.0)

func _setup_rod(rod:AnimatableBody2D,group_name:String) -> void:
	if rod == null:
		return
	rod.add_to_group("MinecraftBlazeRod")
	rod.set_meta("owner_blaze_id",get_instance_id())
	rod.set_meta("owner_team",Team)
	# 烈焰棒是烈焰人的子节点：让它使用本地坐标跟随父节点。
	# 关闭 AnimatableBody2D 的 physics transform 同步，避免物理同步把它
	# 锁在上一帧/出生时的全局位置，造成角色移动后棒子留在原地。
	rod.sync_to_physics = false
	rod.top_level = false
	# 只把 Z 层级改成绝对值；仍然继承烈焰人的父级 Transform，
	# 所以棒子继续跟随角色移动和本地轨道旋转。
	rod.z_as_relative = false
	add_collision_exception_with(rod)
	rod.add_collision_exception_with(self)

func _setup_rod_damage_area(area:Area2D) -> void:
	if area == null:
		return
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitoring = true
	area.monitorable = false

func tick_physics(state:State,delta:float) -> void:
	super.tick_physics(state,delta)
	var safe_delta:float = maxf(delta,0.0)
	_sync_blaze_animation_facing()
	_update_rods(safe_delta)
	_update_rod_collision_damage()
	_hurt_voice_cooldown_left = maxf(_hurt_voice_cooldown_left - safe_delta,0.0)
	if health > 0 and state != State.Die:
		_update_breath_audio(safe_delta)
		_update_blaze_smoke(safe_delta)

func _fit_body_to_creeper_size() -> void:
	if _body_anim == null or _body_anim.sprite_frames == null or CREEPER_TEXTURE == null:
		return
	var animation_name:StringName = _body_anim.animation
	if not _body_anim.sprite_frames.has_animation(animation_name):
		animation_name = &"idle"
	if not _body_anim.sprite_frames.has_animation(animation_name):
		return
	var frame_texture:Texture2D = _body_anim.sprite_frames.get_frame_texture(animation_name,0)
	if frame_texture == null:
		return
	var blaze_height:float = frame_texture.get_size().y
	var creeper_height:float = CREEPER_TEXTURE.get_size().y * CREEPER_REFERENCE_SPRITE_SCALE
	if blaze_height <= 0.0 or creeper_height <= 0.0:
		return
	var uniform_scale:float = creeper_height * maxf(body_size_vs_creeper,0.01) / blaze_height
	_body_anim.scale = Vector2.ONE * uniform_scale


func _sync_blaze_animation_facing() -> void:
	# 优先使用这一物理帧真实发生的水平位移。这样 AI 被碰撞挤开、移动逻辑临时改写 direction，
	# 或公共 ball 的 Shader 朝向链发生变化时，烈焰人本体仍然会按画面上的真实移动方向转身。
	var travelled_x:float = global_position.x - _blaze_facing_last_position.x
	_blaze_facing_last_position = global_position
	var facing_x:float = 0.0
	if absf(travelled_x) > 0.005:
		facing_x = travelled_x
	elif is_player_controlled() and absf(player_control_direction.x) > 0.001:
		facing_x = player_control_direction.x
	elif absf(velocity.x) > 0.05:
		facing_x = velocity.x
	elif absf(direction.x) > 0.001:
		facing_x = direction.x
	if absf(facing_x) <= 0.001:
		return
	_apply_blaze_facing(facing_x > 0.0)


func _apply_blaze_facing(face_right:bool) -> void:
	_blaze_facing_right = face_right
	# 公共 ball 会把朝向写入人物 Shader。烈焰人这里主动把那一层恢复为“不镜像”，
	# 只让 Graphics.scale.x 决定最终方向，避免 Shader 与 AnimatedSprite2D 的组合再次失效/双重镜像。
	set_character_visual_flip_h(false)
	if _body_anim != null:
		_body_anim.flip_h = false
		_body_anim.flip_v = false
		_body_anim.set_instance_shader_parameter("sprite_flip_h",0.0)
	if graphics != null:
		var sx:float = maxf(_graphics_facing_abs_scale.x,0.001)
		var sy:float = maxf(_graphics_facing_abs_scale.y,0.001)
		graphics.scale = Vector2(-sx if face_right else sx,sy)

func Attack() -> void:
	if _burst_active or state_machine == null or state_machine.current_state == State.Die or not is_multiplayer_authority():
		return
	super()
	if is_damage_output_disabled() or not is_combat_runtime_active():
		Attacking = false
		return
	var target:ball = _nearest_enemy(attack_search_range)
	if target == null:
		Attacking = false
		return
	_burst_active = true
	Attacking = true
	_set_rod_attack_pose(true)
	var low:int = mini(burst_min_shots,burst_max_shots)
	var high:int = maxi(burst_min_shots,burst_max_shots)
	var count:int = randi_range(maxi(low,1),maxi(high,1))
	for i:int in range(count):
		if not is_instance_valid(self) or health <= 0 or not is_combat_runtime_active():
			break
		var current:ball = _nearest_enemy(attack_search_range)
		if current == null:
			break
		var aim:Vector2 = combat_target_position(current) - global_position
		if aim.length_squared() <= 0.000001:
			aim = Vector2.RIGHT
		if absf(aim.x) > 0.001:
			_apply_blaze_facing(aim.x > 0.0)
		aim = aim.normalized().rotated(deg_to_rad(randf_range(-4.0,4.0)))
		_spawn_fireball(aim)
		if i + 1 < count:
			await get_tree().create_timer(maxf(burst_shot_gap,0.05),false).timeout
	_set_rod_attack_pose(false)
	_burst_active = false
	Attacking = false

func _spawn_fireball(aim:Vector2) -> void:
	var projectile:Node2D = FIREBALL_SCENE.instantiate() as Node2D
	if projectile == null or get_tree() == null or get_tree().current_scene == null:
		return
	_projectile_serial += 1
	projectile.name = "烈焰弹_%d_%d" % [get_instance_id(),_projectile_serial]
	get_tree().current_scene.add_child(projectile,true)
	projectile.global_position = global_position + aim * 26.0
	_play_world_sfx(FIREBALL_LAUNCH_SFX,projectile.global_position,-2.0)
	if projectile.has_method("configure"):
		projectile.call("configure",self,Team,aim,fireball_speed,fireball_damage_multiplier,fireball_burn_duration,fireball_burn_tick_damage_multiplier,fire_patch_radius,fire_patch_duration,fire_patch_tick_damage_multiplier,fire_patch_burn_tick_damage_multiplier)

func _update_rods(delta:float) -> void:
	var safe_delta:float = maxf(delta,0.0)
	if _rod_attack_pose:
		_rod_attack_mix = move_toward(_rod_attack_mix,1.0,safe_delta / maxf(rod_attack_expand_duration,0.01))
	else:
		_rod_attack_mix = move_toward(_rod_attack_mix,0.0,safe_delta / maxf(rod_attack_recover_duration,0.01))

	var attack_t:float = smoothstep(0.0,1.0,clampf(_rod_attack_mix,0.0,1.0))
	var current_speed:float = lerpf(rod_orbit_speed,rod_attack_spin_speed,attack_t)
	_rod_phase = fmod(_rod_phase + safe_delta * current_speed,TAU)
	var orbit_x:float = lerpf(rod_orbit_x,rod_attack_orbit_x,attack_t)
	var orbit_y:float = lerpf(rod_orbit_y,rod_attack_orbit_y,attack_t)
	_update_one_rod(_rod_a,_rod_phase,orbit_x,orbit_y)
	_update_one_rod(_rod_b,_rod_phase + PI,orbit_x,orbit_y)

func _update_one_rod(rod:AnimatableBody2D,phase:float,orbit_x:float,orbit_y:float) -> void:
	if rod == null or not is_instance_valid(rod):
		return
	var depth:float = sin(phase)
	var world_offset := Vector2(cos(phase) * orbit_x,depth * orbit_y)
	var local_origin:Vector2 = to_local(global_position)
	var local_target:Vector2 = to_local(global_position + world_offset)
	rod.position = local_target - local_origin
	var scale_factor:float = lerpf(rod_back_scale,rod_front_scale,(depth + 1.0) * 0.5)
	rod.scale = Vector2.ONE * scale_factor
	if depth > 0.12:
		rod.z_index = 98
	elif depth < -0.12:
		rod.z_index = 96
	else:
		rod.z_index = 97

func _update_rod_collision_damage() -> void:
	if not _rod_attack_pose or not is_multiplayer_authority() or health <= 0 or not is_combat_runtime_active():
		return
	_check_rod_damage_area(_rod_damage_a)
	_check_rod_damage_area(_rod_damage_b)

func _check_rod_damage_area(area:Area2D) -> void:
	if area == null or not is_instance_valid(area):
		return
	for body:Node2D in area.get_overlapping_bodies():
		if not body is ball:
			continue
		var target:ball = body as ball
		if not _is_enemy(target):
			continue
		var target_id:int = target.get_instance_id()
		if _rod_hit_targets.has(target_id):
			continue
		_rod_hit_targets[target_id] = true
		var outgoing:float = attack_damage(maxf(rod_collision_damage_multiplier,0.0))
		if outgoing > 0.0:
			target.receive_positional_damage(outgoing,area.global_position,false,self)

func _set_rod_attack_pose(enabled:bool) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_set_rod_attack_pose.rpc(enabled)
	else:
		_rpc_set_rod_attack_pose(enabled)

@rpc("authority","call_local","reliable")
func _rpc_set_rod_attack_pose(enabled:bool) -> void:
	_rod_attack_pose = enabled
	if enabled:
		# 每次攻击重新允许近身敌人被棒子碰撞命中；旋转/距离从当前值连续加速、拉开。
		_rod_hit_targets.clear()
	else:
		# 不瞬间复位。_update_rods() 会在 rod_attack_recover_duration 内缓慢收回并减速。
		_rod_phase = fmod(_rod_phase,TAU)

func _update_blaze_smoke(delta:float) -> void:
	if MC_SMOKE_SCENE == null or get_tree() == null or get_tree().current_scene == null:
		return
	_smoke_time_left -= maxf(delta,0.0)
	if _smoke_time_left > 0.0:
		return
	var low:float = minf(smoke_interval_min,smoke_interval_max)
	var high:float = maxf(smoke_interval_min,smoke_interval_max)
	_smoke_time_left = _visual_rng.randf_range(maxf(low,0.05),maxf(high,0.05))
	_spawn_blaze_smoke()


func _spawn_blaze_smoke() -> void:
	var smoke:Node2D = MC_SMOKE_SCENE.instantiate() as Node2D
	if smoke == null or get_tree() == null or get_tree().current_scene == null:
		return
	smoke.name = "MC烟雾_烈焰人_%d" % smoke.get_instance_id()
	_runtime_container().add_child(smoke,true)
	var spawn_position:Vector2 = global_position + Vector2(
		_visual_rng.randf_range(-8.0,8.0),
		_visual_rng.randf_range(-15.0,3.0)
	)
	var diameter:float = smoke_visual_diameter * _visual_rng.randf_range(0.82,1.18)
	if smoke.has_method("configure"):
		smoke.call(
			"configure",
			spawn_position,
			diameter,
			_visual_rng.randf_range(28.0,40.0),
			_visual_rng.randf_range(4.0,9.0),
			98,
			_visual_rng.randf_range(0.68,0.88)
		)


func _ensure_blaze_hit_flash_material() -> void:
	if _body_anim == null or BLAZE_HIT_FLASH_SHADER == null:
		return
	var current:ShaderMaterial = _body_anim.material as ShaderMaterial
	if current == null or current.shader != BLAZE_HIT_FLASH_SHADER:
		var material := ShaderMaterial.new()
		material.shader = BLAZE_HIT_FLASH_SHADER
		_body_anim.material = material
	_body_anim.set_instance_shader_parameter("hit_white_color",Color.WHITE)
	_body_anim.set_instance_shader_parameter("power",0.0)


func hit_white_method(power:float):
	super.hit_white_method(power)
	if _body_anim != null and is_instance_valid(_body_anim):
		_body_anim.set_instance_shader_parameter("hit_white_color",Color.WHITE)
		_body_anim.set_instance_shader_parameter("power",clampf(power,0.0,1.0))


func _runtime_container() -> Node:
	var world:Node = get_tree().current_scene if get_tree() != null else null
	if world == null:
		return self
	var container:Node = world.get_node_or_null("V311运行时对象")
	if container != null:
		return container
	container = Node2D.new()
	container.name = "V311运行时对象"
	world.add_child(container,true)
	return container


func _update_breath_audio(delta:float) -> void:
	if _breath_audio == null or BREATH_SFX.is_empty():
		return
	_breath_time_left -= delta
	if _breath_time_left > 0.0 or _breath_audio.playing:
		return

	var index:int = _audio_rng.randi_range(0,BREATH_SFX.size() - 1)
	var stream:AudioStream = BREATH_SFX[index]
	_breath_audio.stream = stream
	_breath_audio.pitch_scale = 1.0
	_breath_audio.play()

	# 用户要求下一次呼吸不能早于当前声音结束。
	# 因此 start-to-start 间隔 = 当前素材完整时长 + 一段随机静默。
	var silence_low:float = minf(breath_silence_min,breath_silence_max)
	var silence_high:float = maxf(breath_silence_min,breath_silence_max)
	_breath_time_left = maxf(stream.get_length(),0.05) + _audio_rng.randf_range(silence_low,silence_high)


func on_actual_health_damage_received(actual_health_damage:float,_health_before:float) -> void:
	if actual_health_damage <= 0.0 or health <= 0 or not is_inside_tree():
		return
	# 烈焰人的正式视觉是 AnimatedSprite2D。无论伤害来自 Hitbox、状态或直接扣血，
	# 只要真实生命下降就再保证触发一次白闪，避免公共伤害链遗漏视觉反馈。
	hit_white_visual_only()
	if _hurt_audio == null or HURT_SFX.is_empty() or _hurt_audio.playing:
		return
	if _hurt_voice_cooldown_left > 0.0:
		return
	if _audio_rng.randf() > clampf(hurt_voice_chance,0.0,1.0):
		return

	var index:int = _audio_rng.randi_range(0,HURT_SFX.size() - 1)
	var stream:AudioStream = HURT_SFX[index]
	_hurt_audio.stream = stream
	_hurt_audio.pitch_scale = 1.0
	_hurt_audio.play()
	_hurt_voice_cooldown_left = maxf(hurt_voice_cooldown,maxf(stream.get_length(),0.05))


func _play_world_sfx(stream:AudioStream,position_value:Vector2,volume_db_value:float = 0.0) -> void:
	if stream == null or get_tree() == null or get_tree().current_scene == null:
		return
	var player:=AudioStreamPlayer2D.new()
	player.name = "BlazeWorldSFX"
	player.stream = stream
	player.volume_db = volume_db_value
	player.pitch_scale = 1.0
	player.max_distance = 1050.0
	player.attenuation = 0.78
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	get_tree().current_scene.add_child(player)
	player.global_position = position_value
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func Die() -> void:
	if _breath_audio != null:
		_breath_audio.stop()
	if _hurt_audio != null:
		_hurt_audio.stop()
	if not _death_sfx_played:
		_death_sfx_played = true
		# 普通 ball 会在同一帧 queue_free；死亡声必须挂到 World 才能完整播放。
		_play_world_sfx(DEATH_SFX,global_position,1.0)
	super.Die()


func get_blaze_rod_rids() -> Array[RID]:
	var rids:Array[RID] = []
	if _rod_a != null and is_instance_valid(_rod_a):
		rids.append(_rod_a.get_rid())
	if _rod_b != null and is_instance_valid(_rod_b):
		rids.append(_rod_b.get_rid())
	return rids

func _nearest_enemy(max_range:float) -> ball:
	var best:ball = null
	var best_sq:float = maxf(max_range,1.0) * maxf(max_range,1.0)
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var candidate:ball = node as ball
		if not _is_enemy(candidate):
			continue
		var d:float = global_position.distance_squared_to(combat_target_position(candidate))
		if d <= best_sq:
			best_sq = d
			best = candidate
	return best

func _is_enemy(target:ball) -> bool:
	if target == null or not is_instance_valid(target) or target == self or target.health <= 0 or not target.is_combat_targetable():
		return false
	if not Game.Game_Settings.Have_Team_Damage and not Team.is_empty() and Team == target.Team:
		return false
	return true

func play_war_burn_tick_sfx(position_value:Vector2) -> void:
	if BURN_TICK_SFX == null or get_tree() == null or get_tree().current_scene == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = BURN_TICK_SFX
	player.volume_db = 0.5
	player.pitch_scale = randf_range(0.97,1.04)
	player.max_distance = 1050.0
	player.attenuation = 0.74
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	get_tree().current_scene.add_child(player)
	player.global_position = position_value
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()

func get_preview_texture() -> Texture2D:
	return BLAZE_TEXTURE
