extends ball

# 愤怒的普通人：满血保持中速小刀突刺；生命越少，人物越红、伤害越高，并获得越来越夸张的攻速加成。
# 视觉接入：01/02 为微笑持刀/突刺，03/04 为愤怒持刀/突刺。
# 音效：挥刺固定播放“刺.mp3”；真正命中角色时从 6 个“小刀刺”中随机播放一个；首次进入半血愤怒阶段播放“怪物叫.wav”。
const TEX_NORMAL_IDLE:Texture2D = preload("res://Images/characters/meme/愤怒的普通人/01_普通人_微笑持刀.png")
const TEX_NORMAL_STAB:Texture2D = preload("res://Images/characters/meme/愤怒的普通人/02_普通人_微笑刺出小刀.png")
const TEX_ANGRY_IDLE:Texture2D = preload("res://Images/characters/meme/愤怒的普通人/03_普通人_愤怒持刀.png")
const TEX_ANGRY_STAB:Texture2D = preload("res://Images/characters/meme/愤怒的普通人/04_普通人_愤怒刺出小刀.png")
const SFX_KNIFE_SWING:AudioStream = preload("res://audio/characters/meme/愤怒的普通人/刺.mp3")
const SFX_ANGER_ENTER_PATH:String = "res://audio/characters/meme/愤怒的普通人/怪物叫.wav"
const SFX_KNIFE_HITS:Array[AudioStream] = [
	preload("res://audio/characters/meme/愤怒的普通人/小刀刺_[cut_1sec].mp3"),
	preload("res://audio/characters/meme/愤怒的普通人/小刀刺_[cut_1sec] (1).mp3"),
	preload("res://audio/characters/meme/愤怒的普通人/小刀刺_[cut_1sec] (2).mp3"),
	preload("res://audio/characters/meme/愤怒的普通人/小刀刺_[cut_1sec] (3).mp3"),
	preload("res://audio/characters/meme/愤怒的普通人/小刀刺_[cut_1sec] (4).mp3"),
	preload("res://audio/characters/meme/愤怒的普通人/小刀刺_[cut_1sec] (5).mp3"),
]

@export_category("愤怒的普通人 - 突刺")
# Damage（攻击力）就是满血时的基础突刺伤害；残血只提高倍率。
@export_range(1.0,4.0,0.05) var max_rage_damage_multiplier:float = 2.50
@export_range(1.0,8.0,0.10) var max_rage_attack_speed_multiplier:float = 5.00
@export_range(0.10,1.00,0.01) var stab_duration:float = 0.34
@export_range(0.0,0.5,0.01) var stab_active_from:float = 0.10
@export_range(0.0,0.8,0.01) var stab_active_until:float = 0.23
@export_range(20.0,160.0,1.0) var knife_rest_distance:float = 48.0
@export_range(30.0,220.0,1.0) var knife_max_distance:float = 118.0
@export_range(0.0,1.0,0.01) var angry_expression_threshold:float = 0.50

@export_category("愤怒的普通人 - 音效")
@export_range(-36.0,12.0,0.5) var knife_swing_volume_db:float = -6.0
@export_range(-36.0,12.0,0.5) var knife_hit_volume_db:float = -4.0
@export_range(-36.0,12.0,0.5) var anger_enter_volume_db:float = -1.0
@export_range(100.0,3000.0,50.0) var knife_sfx_max_distance:float = 1100.0

@onready var knife_hitbox:hitbox = $KnifeHitbox
@onready var knife_shape:CollisionShape2D = $KnifeHitbox/CollisionShape2D

var _stab_elapsed:float = 0.0
var _stab_direction:Vector2 = Vector2.RIGHT
var _last_visual_texture:Texture2D = null
var _audio_serial:int = 0
var _sfx_anger_enter:AudioStream = null
var _angry_phase_entered:bool = false
var _rage_cooling_physics_frame:int = -1
var _rage_cooling_source:float = 0.90


func _ready() -> void:
	Has_Collision_Damage = false
	Can_Attack = true
	Can_Skill = false
	Health_Restore = 0
	super._ready()

	knife_hitbox.collision_layer = 0
	knife_hitbox.collision_mask = 2
	knife_hitbox.monitoring = false
	knife_hitbox.monitorable = false
	knife_shape.disabled = true
	_update_rage_visual_and_damage()
	_place_knife(knife_rest_distance)


func _process(_delta:float) -> void:
	_update_rage_visual_and_damage()


func get_next_state(state:State) -> int:
	# world.gd 每个 physics tick 会先恢复默认属性并结算 Buff。
	# 这里在状态机真正检查攻击冷却前，再把“当前已含 Buff 的攻速”乘上残血攻速倍率。
	# 同一 physics frame 内状态机可能连续询问多次，缓存原始冷却避免倍率重复叠乘。
	if is_multiplayer_authority():
		var physics_frame:int = Engine.get_physics_frames()
		if _rage_cooling_physics_frame != physics_frame:
			_rage_cooling_physics_frame = physics_frame
			_rage_cooling_source = maxf(Attack_Cooling,0.01)
		Attack_Cooling = maxf(
			_rage_cooling_source / _current_attack_speed_multiplier(),
			0.05
		)
	return super.get_next_state(state)


func Attack() -> void:
	if state_machine.current_state == State.Die or not is_multiplayer_authority():
		return
	if is_damage_output_disabled() or not is_combat_runtime_active():
		Attacking = false
		return

	var target:Node = return_reusable_combat_target()
	if has_player_control_aim():
		# V130：有敌人也不吸敌、没敌人也能朝鼠标自由突刺。
		_stab_direction = player_control_aim_direction(direction)
	elif target is Node2D and is_instance_valid(target):
		var to_target:Vector2 = combat_target_position(target) - global_position
		if to_target.length_squared() > 0.000001:
			_stab_direction = to_target.normalized()
	elif direction.length_squared() > 0.000001:
		_stab_direction = direction.normalized()
	else:
		_stab_direction = Vector2.RIGHT

	direction = _stab_direction
	Attacking = true
	_stab_elapsed = 0.0
	_set_knife_active(false)
	_place_knife(knife_rest_distance)
	_refresh_character_texture()
	_play_knife_swing_everywhere(global_position,randf_range(0.98,1.02))


func tick_physics(state:State,delta:float) -> void:
	super.tick_physics(state,delta)
	if not is_multiplayer_authority():
		return
	if not Attacking:
		_set_knife_active(false)
		return

	_stab_elapsed += delta
	# 满血保持原来的突刺动作速度；残血时动作本身同步提速，
	# 避免 Attack_Cooling 已经很短，却仍被固定 0.34 秒攻击动作卡住。
	var attack_speed_multiplier:float = _current_attack_speed_multiplier()
	var safe_duration:float = maxf(stab_duration / attack_speed_multiplier,0.05)
	var active_from:float = stab_active_from / attack_speed_multiplier
	var active_until:float = stab_active_until / attack_speed_multiplier
	var t:float = clampf(_stab_elapsed / safe_duration,0.0,1.0)
	# 快速推出，随后收回；命中窗口只覆盖真正伸出的刀尖。
	var thrust:float = sin(t * PI)
	_place_knife(lerpf(knife_rest_distance,knife_max_distance,thrust))

	var active:bool = _stab_elapsed >= active_from and _stab_elapsed <= active_until
	_set_knife_active(active)

	if _stab_elapsed >= safe_duration:
		_set_knife_active(false)
		_place_knife(knife_rest_distance)
		Attacking = false
		_refresh_character_texture()


func _on_hitbox_on_hit(hurt:hurtbox) -> void:
	# 继续走 ball 的统一伤害 / 格挡 / 统计链路。
	super._on_hitbox_on_hit(hurt)
	if not is_multiplayer_authority():
		return
	if hurt == null or not is_instance_valid(hurt) or SFX_KNIFE_HITS.is_empty():
		return
	var target:ball = _hurtbox_target_ball(hurt)
	if target == null or target == self:
		return
	var hit_index:int = randi_range(0,SFX_KNIFE_HITS.size() - 1)
	_play_knife_hit_everywhere(hit_index,hurt.global_position,randf_range(0.97,1.03))


func _set_knife_active(active:bool) -> void:
	knife_shape.set_deferred("disabled",not active)
	knife_hitbox.set_deferred("monitoring",active)
	if active:
		knife_hitbox.set_meta("threat_debug_damage",attack_damage(current_hit_damage_multiplier()))
	elif knife_hitbox.has_meta("threat_debug_damage"):
		knife_hitbox.remove_meta("threat_debug_damage")


func _place_knife(distance:float) -> void:
	var dir:Vector2 = _stab_direction
	if dir.length_squared() <= 0.000001:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	# V191：刺击方向是世界方向；根节点受定向重力旋转时，攻击区仍对准真实目标。
	knife_hitbox.global_position = global_position + dir * distance
	knife_hitbox.global_rotation = dir.angle()


func _rage_ratio() -> float:
	if Max_health <= 0:
		return 0.0
	return clampf(1.0 - float(health) / float(Max_health),0.0,1.0)


func _curved_rage_ratio() -> float:
	var rage:float = _rage_ratio()
	return rage * rage * (3.0 - 2.0 * rage)


func _current_attack_speed_multiplier() -> float:
	# 满血 = 1.0x；半血约 3.0x；25% 血约 4.375x；濒死最高 5.0x。
	# 基础 Attack_Cooling 仍由场景保持为 0.90 秒。
	return lerpf(
		1.0,
		maxf(max_rage_attack_speed_multiplier,1.0),
		_curved_rage_ratio()
	)


func current_hit_damage_multiplier() -> float:
	return lerpf(1.0,maxf(max_rage_damage_multiplier,1.0),_curved_rage_ratio())


func _update_rage_visual_and_damage() -> void:
	var rage:float = _rage_ratio()
	var threshold:float = clampf(angry_expression_threshold,0.0,1.0)
	# 愤怒阶段是一次性进入：默认 rage >= 0.5，也就是当前生命 <= 50%。
	# 进入后保持愤怒状态，避免回血时图片来回跳、怪叫反复触发。
	if not _angry_phase_entered and rage >= threshold:
		_angry_phase_entered = true
		if is_multiplayer_authority():
			_play_anger_enter_everywhere(global_position,randf_range(0.98,1.02))

	# 低血量时增长更明显，但 Damage 本身保持“整体基础攻击力”，只改变命中倍率。
	var curved_rage:float = _curved_rage_ratio()

	if image is CanvasItem and is_instance_valid(image):
		# 健康越少越红；保留亮度，避免低血量时整个人直接变黑。
		var gb:float = lerpf(1.0,0.22,curved_rage)
		(image as CanvasItem).self_modulate = Color(1.0,gb,gb,1.0)

	_refresh_character_texture()
	if knife_hitbox != null and knife_hitbox.monitoring:
		knife_hitbox.set_meta("threat_debug_damage",attack_damage(current_hit_damage_multiplier()))


func _refresh_character_texture() -> void:
	if not image is Sprite2D:
		return
	var use_angry_face:bool = _angry_phase_entered
	var next_texture:Texture2D
	if Attacking:
		next_texture = TEX_ANGRY_STAB if use_angry_face else TEX_NORMAL_STAB
	else:
		next_texture = TEX_ANGRY_IDLE if use_angry_face else TEX_NORMAL_IDLE
	if next_texture == null or next_texture == _last_visual_texture:
		return
	(image as Sprite2D).texture = next_texture
	_last_visual_texture = next_texture


func _play_knife_swing_everywhere(position_value:Vector2,pitch_value:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_knife_swing.rpc(position_value,pitch_value)
	else:
		_rpc_play_knife_swing(position_value,pitch_value)


@rpc("authority","call_local","unreliable")
func _rpc_play_knife_swing(position_value:Vector2,pitch_value:float) -> void:
	_play_one_shot_local(SFX_KNIFE_SWING,position_value,knife_swing_volume_db,pitch_value)


func _play_knife_hit_everywhere(hit_index:int,position_value:Vector2,pitch_value:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_knife_hit.rpc(hit_index,position_value,pitch_value)
	else:
		_rpc_play_knife_hit(hit_index,position_value,pitch_value)


@rpc("authority","call_local","unreliable")
func _rpc_play_knife_hit(hit_index:int,position_value:Vector2,pitch_value:float) -> void:
	if hit_index < 0 or hit_index >= SFX_KNIFE_HITS.size():
		return
	_play_one_shot_local(SFX_KNIFE_HITS[hit_index],position_value,knife_hit_volume_db,pitch_value)


func _play_anger_enter_everywhere(position_value:Vector2,pitch_value:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_anger_enter.rpc(position_value,pitch_value)
	else:
		_rpc_play_anger_enter(position_value,pitch_value)


@rpc("authority","call_local","unreliable")
func _rpc_play_anger_enter(position_value:Vector2,pitch_value:float) -> void:
	_play_one_shot_local(_get_anger_enter_sfx(),position_value,anger_enter_volume_db,pitch_value)


func _get_anger_enter_sfx() -> AudioStream:
	# 怪叫属于角色阶段提示音：改为运行时安全加载。
	# 即使用户某次只覆盖了脚本而漏掉音频，也不会再因为 preload 在编译阶段直接让整份角色脚本解析失败。
	if _sfx_anger_enter != null:
		return _sfx_anger_enter
	if not ResourceLoader.exists(SFX_ANGER_ENTER_PATH):
		return null
	_sfx_anger_enter = ResourceLoader.load(SFX_ANGER_ENTER_PATH) as AudioStream
	return _sfx_anger_enter


func _play_one_shot_local(
	stream_value:AudioStream,
	position_value:Vector2,
	volume_db_value:float,
	pitch_value:float
) -> void:
	if stream_value == null or not is_inside_tree():
		return
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var player := AudioStreamPlayer2D.new()
	_audio_serial += 1
	player.name = "AngryOrdinarySfx_%d" % _audio_serial
	player.stream = stream_value
	player.volume_db = volume_db_value
	player.pitch_scale = maxf(pitch_value,0.05)
	player.max_distance = maxf(knife_sfx_max_distance,100.0)
	player.attenuation = 1.0
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	world.add_child(player)
	player.global_position = position_value
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()
