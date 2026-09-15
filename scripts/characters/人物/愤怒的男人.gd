extends "res://scripts/characters/愤怒的人.gd"

const FRENZY_TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const TIRED_MAN_ANGRY_TEXTURE:Texture2D = preload("res://Images/characters/人物/疲倦的人/愤怒呐喊的蓝衣男子.png")
const SFX_ANGER:AudioStream = preload("res://audio/characters/疲倦的人/生气、(1).mp3")

@export_category("愤怒的男人 - 随机拳头")
@export_range(35.0,140.0,1.0) var frenzy_near_radius:float = 82.0
@export_range(0.05,0.8,0.01) var frenzy_punch_interval:float = 0.16
@export_range(0.0,120.0,1.0) var frenzy_slow_speed:float = 54.0
@export_range(40.0,260.0,1.0) var frenzy_fast_speed:float = 148.0
@export_range(18.0,90.0,1.0) var fist_trigger_radius:float = 46.0
@export_range(0.0,48.0,1.0) var fist_front_offset:float = 16.0
@export var fist_front_spawn_jitter:Vector2 = Vector2(9.0,13.0)
@export_range(0.2,0.9,0.01) var fist_base_scale:float = 0.50
@export_range(0.0,0.25,0.01) var fist_scale_variation:float = 0.08

@export_category("愤怒的男人 - 音效")
@export_range(-36.0,12.0,0.5) var anger_volume_db:float = 3.0
@export_range(120.0,2400.0,20.0) var anger_max_distance:float = 1000.0
@export_range(0.05,2.0,0.05) var anger_attenuation:float = 0.7

var _frenzy_left:float = 0.0
var _active_fist_attacks:int = 0
var _spawned_fists:Array[Area2D] = []
var _anger_sound_played:bool = false
var _anger_player:AudioStreamPlayer2D = null
var _frenzy_rng := RandomNumberGenerator.new()

func _ready() -> void:
	_frenzy_rng.seed = Game.battle_rng_seed_or("scripts/characters/人物/愤怒的男人.gd:_frenzy_rng",int(Time.get_ticks_usec()) ^ int(get_instance_id()))
	if not tree_exiting.is_connected(_cleanup_spawned_fists):
		tree_exiting.connect(_cleanup_spawned_fists)
	super._ready()
	Max_health = 250
	health = Max_health
	Damage = 50
	Speed = frenzy_fast_speed
	Attack_Cooling = 999.0
	Can_Attack = false
	Can_Skill = false
	Has_Collision_Damage = false
	if default_properties != null:
		default_properties["Max_health"] = Max_health
		default_properties["Damage"] = Damage
		default_properties["Speed"] = Speed
		default_properties["Attack_Cooling"] = Attack_Cooling
	_apply_tired_man_angry_visual()
	_ensure_anger_player()

# ================================
# V400 愤怒形态入场声音
# ================================
func _ensure_anger_player() -> void:
	if _anger_player != null and is_instance_valid(_anger_player):
		return
	_anger_player = AudioStreamPlayer2D.new()
	_anger_player.name = "AngryFormEntrySfx"
	_anger_player.stream = SFX_ANGER
	_anger_player.volume_db = anger_volume_db
	_anger_player.max_distance = maxf(anger_max_distance,50.0)
	_anger_player.attenuation = maxf(anger_attenuation,0.05)
	_anger_player.process_mode = Node.PROCESS_MODE_INHERIT
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		_anger_player.bus = &"GameplayRecord"
	add_child(_anger_player)


func _update_anger_audio_runtime() -> void:
	_ensure_anger_player()
	var runtime_active:bool = health > 0 and is_combat_runtime_active()
	if runtime_active and not _anger_sound_played:
		_anger_sound_played = true
		_anger_player.stream_paused = false
		_anger_player.play()
	elif _anger_player.playing:
		_anger_player.stream_paused = not runtime_active


func _apply_tired_man_angry_visual() -> void:
	if not (image is Sprite2D) or TIRED_MAN_ANGRY_TEXTURE == null:
		return
	var sprite:Sprite2D = image as Sprite2D
	sprite.texture = TIRED_MAN_ANGRY_TEXTURE
	sprite.visible = true
	sprite.self_modulate = Color.WHITE
	var source_height:float = maxf(float(TIRED_MAN_ANGRY_TEXTURE.get_height()),1.0)
	sprite.scale = Vector2.ONE * (angry_visual_height / source_height)

func _process(delta:float) -> void:
	_update_anger_audio_runtime()
	if not is_multiplayer_authority() or health <= 0 or not is_combat_runtime_active():
		return

	# V397：不再因为“附近有敌人”就提前减速。
	# 只有某只随机拳头已经找到自己近距内的合法敌人、真正进入伸拳动画后才减速；
	# 所有正在挥出的拳头都结束后立即恢复快移速。
	if _active_fist_attacks <= 0 and not is_equal_approx(Speed,frenzy_fast_speed):
		_set_frenzy_move_speed(frenzy_fast_speed)

	_frenzy_left = maxf(_frenzy_left - delta,0.0)
	if _frenzy_left > 0.0:
		return

	# 每次先在人物周围一个小圆盘内挑选“拳头根部”，再随机决定该拳头比例。
	# 若该拳头自己的最近攻击范围内没有敌人，本次就不挥拳；不会隔着一大段距离自动攻击。
	var fist_anchor:Vector2 = _random_fist_anchor()
	var scale_value:float = _frenzy_rng.randf_range(
		maxf(fist_base_scale - fist_scale_variation,0.05),
		maxf(fist_base_scale + fist_scale_variation,0.05)
	)
	var target:ball = _nearest_enemy_to_fist(fist_anchor,fist_trigger_radius * scale_value)
	if target == null or not is_instance_valid(target):
		return

	_frenzy_left = frenzy_punch_interval * _frenzy_rng.randf_range(0.80,1.18)
	_run_random_fist(fist_anchor,target,scale_value)

func _random_fist_anchor() -> Vector2:
	# V398：拳头根部只能从人物“自己身前”的小范围挥出，绝不能为了命中敌人
	# 把拳头根部直接随机到敌人脚下。先取人物当前真正前向，再在前方锚点附近
	# 做少量前后/侧向散布。这样拳头永远是从自己身前伸出去。
	var forward:Vector2 = _current_fist_forward()
	var side:Vector2 = Vector2(-forward.y,forward.x)
	var forward_jitter:float = _frenzy_rng.randf_range(-absf(fist_front_spawn_jitter.x),absf(fist_front_spawn_jitter.x))
	var side_jitter:float = _frenzy_rng.randf_range(-absf(fist_front_spawn_jitter.y),absf(fist_front_spawn_jitter.y))
	var front_distance:float = maxf(fist_front_offset,0.0) + forward_jitter
	return global_position + forward * front_distance + side * side_jitter

func _current_fist_forward() -> Vector2:
	# 优先使用人物当前真实移动/追敌方向；站立时回退到当前水平视觉朝向。
	var move_dir:Vector2 = player_control_direction if is_player_controlled() else direction
	if move_dir.length_squared() > 0.0001:
		return move_dir.normalized()
	var flipped:bool = is_character_visual_flipped_h()
	if dir_left:
		return Vector2.RIGHT if flipped else Vector2.LEFT
	return Vector2.LEFT if flipped else Vector2.RIGHT

func _nearest_enemy_to_fist(fist_anchor:Vector2,search_radius:float) -> ball:
	var candidates:Array[ball] = FRENZY_TOOLS.enemies_in_radius(self,fist_anchor,maxf(search_radius,1.0))
	var best:ball = null
	var best_sq:float = INF
	for candidate:ball in candidates:
		if candidate == null or not is_instance_valid(candidate) or not _is_legal_enemy(candidate):
			continue
		var distance_sq:float = fist_anchor.distance_squared_to(candidate.global_position)
		if distance_sq < best_sq:
			best_sq = distance_sq
			best = candidate
	return best

func _run_random_fist(fist_anchor:Vector2,target:ball,scale_value:float) -> void:
	if target == null or not is_instance_valid(target) or health <= 0:
		return

	var attack_dir:Vector2 = target.global_position - fist_anchor
	if attack_dir.length_squared() <= 0.000001:
		attack_dir = Vector2.RIGHT
	attack_dir = attack_dir.normalized()

	# 直接复用“愤怒的人”已经与面包车拳头小混混统一的拳头 PNG alpha 几何：
	# 基础拳长 30.4px、12 physics-frame、sin(t*PI)*12.8 伸出再收回。
	# 本形态的差异只在于：每拳根部在人物附近随机、整个拳头按 scale_value 等比缩放。
	var weapon:Area2D = _create_fist_weapon_area()
	if weapon == null:
		return
	var world:Node = get_tree().current_scene
	if world == null:
		weapon.queue_free()
		return

	world.add_child(weapon)
	_register_spawned_fist(weapon)
	weapon.scale = Vector2.ONE * scale_value
	weapon.global_rotation = attack_dir.angle()
	weapon.global_position = fist_anchor + attack_dir * (3.2 * scale_value)

	# 到这里才代表拳头实际可以开始攻击：此刻才减速。
	_active_fist_attacks += 1
	_set_frenzy_move_speed(frenzy_slow_speed)
	_play_fist_audio(false,fist_anchor)

	var hit_ids:Dictionary = {}
	var steps:int = 12
	for i:int in range(steps):
		if not _fist_attack_still_valid():
			break
		var t:float = float(i) / float(maxi(steps - 1,1))
		var extension:float = sin(t * PI) * 12.8 * scale_value
		weapon.global_position = fist_anchor + attack_dir * (3.2 * scale_value + extension)
		weapon.global_rotation = attack_dir.angle()
		# 前半程伸拳保持完全不透明；后半程收拳时同步渐隐。
		# Area2D 是 CanvasItem，modulate 会继续作用到其拳头 Sprite 子节点。
		var retract_progress:float = clampf((t - 0.5) * 2.0,0.0,1.0)
		weapon.modulate.a = 1.0 - retract_progress
		await get_tree().physics_frame
		_damage_fist_overlaps(weapon,hit_ids)

	if weapon != null and is_instance_valid(weapon):
		_unregister_spawned_fist(weapon)
		weapon.queue_free()
	_active_fist_attacks = maxi(_active_fist_attacks - 1,0)
	if _active_fist_attacks <= 0 and is_instance_valid(self) and health > 0:
		_set_frenzy_move_speed(frenzy_fast_speed)

# ================================
# V405 世界根拳头生命周期清理
# ================================
func _register_spawned_fist(weapon:Area2D) -> void:
	if weapon == null or not is_instance_valid(weapon):
		return
	if not _spawned_fists.has(weapon):
		_spawned_fists.append(weapon)


func _unregister_spawned_fist(weapon:Area2D) -> void:
	if weapon == null:
		return
	_spawned_fists.erase(weapon)


func _cleanup_spawned_fists() -> void:
	# 拳头为了保持固定世界锚点而挂在 current_scene，而不是角色子节点。
	# 角色被删除/替换/remove_child 时必须主动清理这些世界根临时节点，
	# 否则角色已经离树后拳头仍会留下。tree_exiting 触发时 self 仍有效，
	# 因此这里集中 queue_free 所有登记拳头，并清空攻击计数。
	for weapon:Area2D in _spawned_fists:
		if weapon != null and is_instance_valid(weapon) and not weapon.is_queued_for_deletion():
			weapon.queue_free()
	_spawned_fists.clear()
	_active_fist_attacks = 0


func _set_frenzy_move_speed(value:float) -> void:
	# ball.restore_default_runtime_properties_fast() 每个物理帧会从 default_properties
	# 恢复 Speed，所以临时攻击减速必须同时改运行值和默认运行值，否则下一帧就被还原。
	var speed_value:float = maxf(value,0.0)
	Speed = speed_value
	if default_properties != null:
		default_properties["Speed"] = speed_value
