extends Area2D

const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")

var source_owner:ball = null
var damage:float = 24.0
var duration:float = 0.38
var start_radius:float = 7.0
var end_radius:float = 76.0
var knockback_distance:float = 16.0
var knockback_speed:float = 300.0

var _elapsed:float = 0.0
var _hit_ids:Dictionary = {}
@onready var collision_shape:CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	top_level = true
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	monitorable = false
	set_meta("threat_debug_damage",maxf(damage,0.0))
	_update_radius(start_radius)
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
	var ratio:float = clampf(_elapsed / maxf(duration,0.01),0.0,1.0)
	_update_radius(lerpf(start_radius,end_radius,ratio))
	if source_owner.is_multiplayer_authority():
		_damage_new_overlaps()
	queue_redraw()
	if ratio >= 1.0:
		queue_free()


func _update_radius(radius:float) -> void:
	var circle:= collision_shape.shape as CircleShape2D
	if circle != null:
		circle.radius = maxf(radius,1.0)


func _damage_new_overlaps() -> void:
	for area:Area2D in get_overlapping_areas():
		if not area is hurtbox:
			continue
		var target:ball = area.get_parent() as ball
		if target == null or not is_instance_valid(target):
			continue
		if not TOOLS.is_enemy(source_owner,target):
			continue
		var target_id:int = target.get_instance_id()
		if _hit_ids.has(target_id):
			continue
		_hit_ids[target_id] = true
		var outgoing:float = source_owner.effective_outgoing_damage(damage)
		if outgoing > 0.0:
			var applied:bool = target.receive_positional_damage(
				outgoing,
				global_position,
				false,
				source_owner
			)
			# V40：锻造震荡波是真实伤害，命中后也播放项目原有 balls_hit1 碰撞伤害声。
			if applied and source_owner.has_method("play_bladesmith_ball_damage_sfx"):
				source_owner.call("play_bladesmith_ball_damage_sfx",outgoing)
		if knockback_distance > 0.0:
			var push_dir:Vector2 = target.global_position - global_position
			if push_dir.length_squared() <= 0.0001:
				push_dir = Vector2.RIGHT
			target.apply_knockback(
				push_dir.normalized(),
				knockback_distance,
				knockback_speed,
				0.0,
				0.0,
				{
					"source":source_owner,
					"lock_control":false,
					"stop_on_character":true,
				}
			)


func _draw() -> void:
	var ratio:float = clampf(_elapsed / maxf(duration,0.01),0.0,1.0)
	var radius:float = lerpf(start_radius,end_radius,ratio)
	var alpha:float = (1.0 - ratio) * 0.72
	draw_arc(Vector2.ZERO,radius,0.0,TAU,72,Color(1.0,0.78,0.36,alpha),3.0,true)
	draw_arc(Vector2.ZERO,maxf(radius - 5.0,1.0),0.0,TAU,72,Color(1.0,0.95,0.72,alpha * 0.55),1.5,true)
