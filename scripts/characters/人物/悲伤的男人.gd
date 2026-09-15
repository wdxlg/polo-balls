extends ball

const TEAR_SCRIPT = preload("res://scripts/effects/投稿/悲伤眼泪.gd")
const SFX_CRY:AudioStream = preload("res://audio/characters/疲倦的人/哭.mp3")

@export_category("悲伤的男人 - 眼泪")
@export_range(0.02,1.0,0.005) var tear_interval:float = 0.060
@export_range(80.0,1800.0,10.0) var tear_speed:float = 1100.0
@export_range(0.1,2.0,0.05) var tear_damage_multiplier:float = 1.0
@export_range(0.0,60.0,1.0) var tear_forward_offset:float = 22.0
@export var tear_spawn_jitter:Vector2 = Vector2(26.0,16.0)
@export var tear_initial_length_range:Vector2 = Vector2(4.0,9.0)
@export var tear_initial_width_range:Vector2 = Vector2(0.32,0.68)
@export_range(0.0,220.0,5.0) var tear_lateral_speed:float = 95.0

@export_category("悲伤的男人 - 音效")
@export_range(-36.0,12.0,0.5) var cry_volume_db:float = -3.0
@export_range(120.0,2400.0,20.0) var cry_max_distance:float = 1000.0
@export_range(0.05,2.0,0.05) var cry_attenuation:float = 0.7

@onready var left_tear_point:Marker2D = get_node_or_null("LeftTearPoint") as Marker2D
@onready var right_tear_point:Marker2D = get_node_or_null("RightTearPoint") as Marker2D

var _tear_left:float = 0.0
var _cry_player:AudioStreamPlayer2D = null
var _tear_rng := RandomNumberGenerator.new()

func _ready() -> void:
	_tear_rng.seed = Game.battle_rng_seed_or("scripts/characters/人物/悲伤的男人.gd:_tear_rng",int(Time.get_ticks_usec()) ^ int(get_instance_id()))
	Type = Ball_Type.Ball
	Max_health = 400
	Damage = 8
	Speed = 60.0
	Has_Collision_Damage = false
	Can_Attack = false
	Can_Skill = false
	Health_Restore = 0
	super._ready()
	health = Max_health
	if default_properties != null:
		default_properties["Max_health"] = Max_health
		default_properties["Damage"] = Damage
		default_properties["Speed"] = Speed
	_ensure_cry_player()

func _process(delta:float) -> void:
	_update_cry_audio_runtime()
	if not is_multiplayer_authority() or health <= 0 or not is_combat_runtime_active():
		return
	_tear_left -= delta
	# V397：按固定时间步追赶发射次数。即使某一渲染帧较长，也不会直接漏掉整波泪滴，
	# 从而保持“源源不断”的左右双眼泪流。单帧最多补发 3 波，避免卡顿时无限追赶。
	var emitted:int = 0
	var cadence:float = maxf(tear_interval,0.02)
	while _tear_left <= 0.0 and emitted < 3:
		_tear_left += cadence
		_spawn_tear(0)
		_spawn_tear(1)
		emitted += 1

# ================================
# V400 悲伤形态持续哭声
# ================================
func _ensure_cry_player() -> void:
	if _cry_player != null and is_instance_valid(_cry_player):
		return
	_cry_player = AudioStreamPlayer2D.new()
	_cry_player.name = "SadFormCryLoop"
	var loop_stream:AudioStream = SFX_CRY.duplicate() as AudioStream
	if loop_stream is AudioStreamMP3:
		(loop_stream as AudioStreamMP3).loop = true
	_cry_player.stream = loop_stream
	_cry_player.volume_db = cry_volume_db
	_cry_player.max_distance = maxf(cry_max_distance,50.0)
	_cry_player.attenuation = maxf(cry_attenuation,0.05)
	_cry_player.process_mode = Node.PROCESS_MODE_INHERIT
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		_cry_player.bus = &"GameplayRecord"
	add_child(_cry_player)


func _update_cry_audio_runtime() -> void:
	_ensure_cry_player()
	var runtime_active:bool = health > 0 and is_combat_runtime_active()
	if runtime_active and not _cry_player.playing:
		_cry_player.stream_paused = false
		_cry_player.play()
	elif _cry_player.playing:
		_cry_player.stream_paused = not runtime_active
	if health <= 0 and _cry_player.playing:
		_cry_player.stop()


func _spawn_tear(eye_index:int) -> void:
	var world:Node = get_tree().current_scene
	if world == null or TEAR_SCRIPT == null:
		return
	var point:Marker2D = left_tear_point if eye_index == 0 else right_tear_point
	# V396：基础位置完全由场景里的两个 Marker2D 控制。
	# 以后只要在 2D 编辑器拖 LeftTearPoint / RightTearPoint 十字点即可改眼泪基础位置。
	var local_offset:Vector2 = point.position if point != null else (Vector2(15.0,-45.0) if eye_index == 0 else Vector2(30.0,-40.0))
	var facing_sign:float = _visual_forward_sign()
	# V404：Marker2D 是按用户提交场景中“原图朝右”的基础位置摆放的。公共人物镜像由
	# Shader 完成，Marker 本身不会自动跟着 UV 镜像，所以视觉翻转时必须围绕 Image 的
	# 实际绘制中心同步镜像 Marker X；否则朝另一侧移动时泪点仍停在原来那一侧。
	local_offset = _mirror_tear_marker_for_visual(local_offset)
	# Marker 基础位置之上继续沿人物当前朝向向前推。每一发再从一个椭圆小区域内
	# 独立随机选出生点，而不是只在同一个固定像素点生成。
	local_offset.x += facing_sign * tear_forward_offset
	local_offset += _random_tear_spawn_offset()
	var start:Vector2 = to_global(local_offset)
	var tear:Node2D = TEAR_SCRIPT.new()

	# 先把眼泪加入场景树，再写 global_position。这样本发的世界坐标不会受到
	# “未入树 Node2D 的 global transform”初始化时机影响。
	world.add_child(tear)
	var initial_length:float = _tear_rng.randf_range(
		minf(tear_initial_length_range.x,tear_initial_length_range.y),
		maxf(tear_initial_length_range.x,tear_initial_length_range.y)
	)
	var initial_width:float = _tear_rng.randf_range(
		minf(tear_initial_width_range.x,tear_initial_width_range.y),
		maxf(tear_initial_width_range.x,tear_initial_width_range.y)
	)
	tear.call(
		"setup",
		self,
		start,
		Vector2(_tear_rng.randf_range(-tear_lateral_speed,tear_lateral_speed),tear_speed * _tear_rng.randf_range(0.96,1.06)),
		attack_damage(tear_damage_multiplier),
		3.2,
		initial_length,
		initial_width
	)


func _mirror_tear_marker_for_visual(local_position:Vector2) -> Vector2:
	if not is_character_visual_flipped_h():
		return local_position
	var pivot_x:float = 0.0
	# 用户提交的 Marker 是以当前 Sprite2D 绘制中心为参照摆放；Image.offset.x 会把
	# 贴图绘制中心从角色根原点横向移开，因此镜像轴也必须使用同一个 offset.x。
	if image is Sprite2D:
		pivot_x = (image as Sprite2D).offset.x
	elif image is AnimatedSprite2D:
		pivot_x = (image as AnimatedSprite2D).offset.x
	local_position.x = pivot_x * 2.0 - local_position.x
	return local_position


func _random_tear_spawn_offset() -> Vector2:
	# 在 Marker 周围的椭圆区域内均匀散布。sqrt(r) 避免随机点过度堆在中心。
	var angle:float = _tear_rng.randf_range(-PI,PI)
	var radius:float = sqrt(_tear_rng.randf())
	return Vector2(
		cos(angle) * absf(tear_spawn_jitter.x) * radius,
		sin(angle) * absf(tear_spawn_jitter.y) * radius
	)


func _visual_forward_sign() -> float:
	# 公共人物可能由Shader接管水平翻转，不能直接读取Sprite2D.flip_h。
	var flipped:bool = is_character_visual_flipped_h()
	if dir_left:
		return 1.0 if flipped else -1.0
	return -1.0 if flipped else 1.0
