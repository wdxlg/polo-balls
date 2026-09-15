extends ball

const TEAR_SCRIPT = preload("res://scripts/effects/投稿/悲伤眼泪.gd")

@export_category("悲伤的男人 - 眼泪")
@export_range(0.05,1.0,0.01) var tear_interval:float = 0.36
@export_range(80.0,1200.0,10.0) var tear_speed:float = 650.0
@export_range(0.1,2.0,0.05) var tear_damage_multiplier:float = 1.0
@export var left_eye_offset:Vector2 = Vector2(-17.0,-49.0)
@export var right_eye_offset:Vector2 = Vector2(17.0,-49.0)
@export_range(0.0,60.0,1.0) var tear_forward_offset:float = 22.0
@export var tear_spawn_jitter:Vector2 = Vector2(6.0,4.0)

var _tear_left:float = 0.0
var _tear_rng := RandomNumberGenerator.new()

func _ready() -> void:
	_tear_rng.seed = Game.battle_rng_seed_or("scripts/characters/投稿/悲伤的男人.gd:_tear_rng",int(Time.get_ticks_usec()) ^ int(get_instance_id()))
	Type = Ball_Type.Ball
	Max_health = 340
	Damage = 20
	Speed = 50.0
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

func _process(delta:float) -> void:
	if not is_multiplayer_authority() or health <= 0 or not is_combat_runtime_active():
		return
	_tear_left -= delta
	if _tear_left > 0.0:
		return
	_tear_left += maxf(tear_interval,0.05)
	# 两个眼位在同一波同时落泪，保证视觉上一直是左右两道眼泪。
	_spawn_tear(0)
	_spawn_tear(1)

func _spawn_tear(eye_index:int) -> void:
	var world:Node = get_tree().current_scene
	if world == null or TEAR_SCRIPT == null:
		return
	var local_offset:Vector2 = left_eye_offset if eye_index == 0 else right_eye_offset
	var facing_sign:float = _visual_forward_sign()
	# V394：眼位整体下移，并沿人物当前视觉朝向向脸前推出。
	# 每滴还在眼位周围一个很小范围随机出生，不再锁死在同一像素点。
	local_offset.x += facing_sign * tear_forward_offset
	local_offset += Vector2(
		_tear_rng.randf_range(-absf(tear_spawn_jitter.x),absf(tear_spawn_jitter.x)),
		_tear_rng.randf_range(-absf(tear_spawn_jitter.y),absf(tear_spawn_jitter.y))
	)
	var start:Vector2 = to_global(local_offset)
	var tear:Node2D = TEAR_SCRIPT.new()
	tear.call(
		"setup",
		self,
		start,
		Vector2(_tear_rng.randf_range(-12.0,12.0),tear_speed * _tear_rng.randf_range(0.97,1.05)),
		attack_damage(tear_damage_multiplier),
		3.2
	)
	world.add_child(tear)


func _visual_forward_sign() -> float:
	# 公共人物可能由Shader接管水平翻转，不能直接读取Sprite2D.flip_h。
	var flipped:bool = is_character_visual_flipped_h()
	if dir_left:
		return 1.0 if flipped else -1.0
	return -1.0 if flipped else 1.0
