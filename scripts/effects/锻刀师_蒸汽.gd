extends Area2D

const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
# V40：蒸汽视觉直接复用炮兵现有烟雾 PNG；不复制、不另造同义素材路径。
const SMOKE_TEXTURE:Texture2D = preload("res://Images/characters/人物/炮兵/烟雾.png")

var source_owner:ball = null
var damage:float = 8.0
var tick_interval:float = 0.50
var lifetime:float = 1.70
var rise_speed:float = 78.0
var drift_speed:float = 12.0
var visual_radius:float = 46.0

var _elapsed:float = 0.0
var _tick_left:float = 0.0
var _drift_direction:float = 0.0
var _rotation_speed:float = 0.0
var _base_rotation:float = 0.0
var _rng := RandomNumberGenerator.new()
@onready var collision_shape:CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	top_level = true
	_rng.seed = Game.battle_rng_seed_or("scripts/effects/锻刀师_蒸汽.gd:_rng.seed",int(Time.get_ticks_usec()) ^ int(get_instance_id()))
	_drift_direction = _rng.randf_range(-1.0,1.0)
	_base_rotation = _rng.randf_range(-PI,PI)
	_rotation_speed = _rng.randf_range(-0.24,0.24)
	_tick_left = tick_interval
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	monitorable = false
	set_meta("threat_debug_damage",maxf(damage,0.0))
	queue_redraw()


func configure(owner_value:ball,damage_value:float) -> void:
	source_owner = owner_value
	damage = maxf(damage_value,0.0)
	if is_inside_tree():
		set_meta("threat_debug_damage",damage)


func _physics_process(delta:float) -> void:
	if source_owner == null or not is_instance_valid(source_owner):
		queue_free()
		return
	if not source_owner.is_combat_runtime_active():
		return

	_elapsed += delta
	if _elapsed >= lifetime:
		queue_free()
		return

	global_position += Vector2(
		_drift_direction * drift_speed,
		-rise_speed
	) * delta

	if source_owner.is_multiplayer_authority():
		_tick_left -= delta
		while _tick_left <= 0.0:
			_tick_left += tick_interval
			_damage_overlaps()

	queue_redraw()


func _damage_overlaps() -> void:
	var hit_ids:Dictionary = {}
	for area:Area2D in get_overlapping_areas():
		if not area is hurtbox:
			continue
		var target:ball = area.get_parent() as ball
		if target == null or not is_instance_valid(target):
			continue
		if not TOOLS.is_enemy(source_owner,target):
			continue
		var target_id:int = target.get_instance_id()
		if hit_ids.has(target_id):
			continue
		hit_ids[target_id] = true
		var outgoing:float = source_owner.effective_outgoing_damage(damage)
		if outgoing <= 0.0:
			continue
		var applied:bool = target.receive_positional_damage(
			outgoing,
			global_position,
			false,
			source_owner
		)
		if applied and source_owner.has_method("play_bladesmith_ball_damage_sfx"):
			source_owner.call("play_bladesmith_ball_damage_sfx",outgoing)


func _draw() -> void:
	# 炮兵烟雾 PNG 作为整团蒸汽的唯一主体视觉；碰撞仍是同节点真实 CircleShape2D。
	var ratio:float = clampf(_elapsed / maxf(lifetime,0.01),0.0,1.0)
	var rise_t:float = 1.0 - pow(1.0 - ratio,2.0)
	var diameter:float = visual_radius * 2.0 * lerpf(0.72,1.42,rise_t)
	var texture_size:Vector2 = SMOKE_TEXTURE.get_size()
	var extent:float = maxf(maxf(texture_size.x,texture_size.y),1.0)
	var scale_value:float = diameter / extent
	var fade_in:float = clampf(ratio / 0.10,0.0,1.0)
	var alpha:float = fade_in * pow(1.0 - ratio,1.35) * 0.56
	var angle:float = _base_rotation + _rotation_speed * _elapsed
	draw_set_transform(Vector2.ZERO,angle,Vector2(scale_value,scale_value))
	draw_texture(SMOKE_TEXTURE,-texture_size * 0.5,Color(0.93,0.97,1.0,alpha))
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
