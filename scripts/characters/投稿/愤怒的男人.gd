extends "res://scripts/characters/愤怒的人.gd"

const FRENZY_TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const TIRED_MAN_ANGRY_TEXTURE:Texture2D = preload("res://Images/characters/人物/疲倦的人/愤怒呐喊的蓝衣男子.png")

@export_category("愤怒的男人 - 疯狂挥拳")
@export_range(60.0,280.0,5.0) var frenzy_near_radius:float = 155.0
@export_range(0.05,0.8,0.01) var frenzy_punch_interval:float = 0.16
@export_range(0.0,120.0,1.0) var frenzy_slow_speed:float = 54.0
@export_range(40.0,260.0,1.0) var frenzy_fast_speed:float = 148.0
@export_range(0.4,1.6,0.01) var fist_scale_min:float = 0.72
@export_range(0.4,1.8,0.01) var fist_scale_max:float = 1.18
@export_range(0.0,50.0,1.0) var fist_spawn_side_radius:float = 24.0
@export_range(0.0,60.0,1.0) var fist_spawn_forward_jitter:float = 18.0

var _frenzy_left:float = 0.0
var _frenzy_rng := RandomNumberGenerator.new()

func _ready() -> void:
	_frenzy_rng.seed = Game.battle_rng_seed_or("scripts/characters/投稿/愤怒的男人.gd:_frenzy_rng",int(Time.get_ticks_usec()) ^ int(get_instance_id()))
	super._ready()
	Max_health = 120
	health = Max_health
	Damage = 80
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
	# V393：疲倦的人复活为愤怒形态时使用用户提供的专属状态图，覆盖父类通用“愤怒的人”贴图。
	_apply_tired_man_angry_visual()


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
	if not is_multiplayer_authority() or health <= 0 or not is_combat_runtime_active():
		return
	var target:ball = FRENZY_TOOLS.nearest_enemy(self,frenzy_near_radius)
	var desired_speed:float = frenzy_fast_speed
	if target != null and is_instance_valid(target):
		desired_speed = frenzy_slow_speed
	if not is_equal_approx(Speed,desired_speed):
		Speed = desired_speed
		if default_properties != null:
			default_properties["Speed"] = desired_speed

	_frenzy_left = maxf(_frenzy_left - delta,0.0)
	if target == null or not is_instance_valid(target) or _frenzy_left > 0.0:
		return
	_frenzy_left = frenzy_punch_interval * _frenzy_rng.randf_range(0.80,1.18)
	_run_random_fist(target)

func _run_random_fist(target:ball) -> void:
	if target == null or not is_instance_valid(target) or health <= 0:
		return
	var attack_dir:Vector2 = target.global_position - global_position
	if attack_dir.length_squared() <= 0.000001:
		attack_dir = Vector2.RIGHT
	attack_dir = attack_dir.normalized()
	var tangent := Vector2(-attack_dir.y,attack_dir.x)
	var weapon:Area2D = _create_fist_weapon_area()
	if weapon == null:
		return
	var world:Node = get_tree().current_scene
	if world == null:
		weapon.queue_free()
		return
	world.add_child(weapon)

	# 拳头不是固定从同一点冒出：在人物前方的小范围随机散布，同时每拳都有轻微尺寸差。
	var side_offset:float = _frenzy_rng.randf_range(-fist_spawn_side_radius,fist_spawn_side_radius)
	var forward_offset:float = 34.0 + _frenzy_rng.randf_range(-fist_spawn_forward_jitter,fist_spawn_forward_jitter)
	var scale_value:float = _frenzy_rng.randf_range(minf(fist_scale_min,fist_scale_max),maxf(fist_scale_min,fist_scale_max))
	var angle_jitter:float = deg_to_rad(_frenzy_rng.randf_range(-22.0,22.0))
	weapon.global_position = global_position + attack_dir * forward_offset + tangent * side_offset
	weapon.global_rotation = attack_dir.angle() + angle_jitter
	weapon.scale = Vector2.ONE * scale_value
	_play_fist_audio(false,weapon.global_position)

	var hit_ids:Dictionary = {}
	await get_tree().physics_frame
	if weapon != null and is_instance_valid(weapon) and health > 0:
		_damage_fist_overlaps(weapon,hit_ids)
	await get_tree().create_timer(0.075,false).timeout
	if weapon != null and is_instance_valid(weapon) and health > 0:
		_damage_fist_overlaps(weapon,hit_ids)
	await get_tree().create_timer(0.045,false).timeout
	if weapon != null and is_instance_valid(weapon):
		weapon.queue_free()
