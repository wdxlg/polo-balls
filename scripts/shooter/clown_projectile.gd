extends ball

# 小丑专用“特殊投射物”。
# 目前只承担火箭和地雷，避免把小丑主脚本塞得更乱。

enum ProjectileMode {
	ROCKET,
	MINE,
}

@export var projectile_mode:ProjectileMode = ProjectileMode.ROCKET
@export var explosion_damage:float = 40.0
@export var explosion_radius:float = 110.0
@export var trigger_radius:float = 70.0
@export var homing_strength:float = 1.3
@export var max_lifetime:float = 5.0
@export var projectile_skin_path:String = ""

var elapsed:float = 0.0
var exploded:bool = false


func _ready() -> void:
	super()

	Can_Attack = false
	Can_Skill = false
	Damage = 0

	_apply_projectile_skin()

	if projectile_mode == ProjectileMode.MINE:
		Speed = 0.0
		direction = Vector2.ZERO
		collision_mask = 0
		if self_hitbox:
			self_hitbox.monitoring = false
			self_hitbox.monitorable = false


func _apply_projectile_skin() -> void:
	if projectile_skin_path == "" or not ResourceLoader.exists(projectile_skin_path):
		return

	var sprite:Sprite2D = get_node_or_null("Graphics/Image") as Sprite2D
	if sprite == null:
		return

	var texture:Texture2D = load(projectile_skin_path)
	if texture == null:
		return

	sprite.texture = texture
	var size:Vector2 = texture.get_size()
	var max_side:float = maxf(size.x,size.y)
	if max_side > 0.0:
		var target_size:float = 13.0 if projectile_mode == ProjectileMode.ROCKET else 17.0
		sprite.scale = Vector2.ONE * (target_size / max_side)


func tick_physics(state:State,delta:float) -> void:
	if not is_multiplayer_authority():
		return
	if exploded:
		return

	elapsed += delta

	match projectile_mode:
		ProjectileMode.ROCKET:
			_process_rocket_homing(delta)
		ProjectileMode.MINE:
			_process_mine_trigger()

	if elapsed >= max_lifetime:
		_explode()
		return

	super(state,delta)


func _process_rocket_homing(delta:float) -> void:
	if not is_instance_valid(Target_Enemy):
		return
	if not Target_Enemy is ball:
		return

	var to_target:Vector2 = combat_target_position(Target_Enemy) - global_position
	if to_target.length_squared() <= 0.001:
		return

	var wanted:Vector2 = to_target.normalized()
	var blend:float = clampf(homing_strength * delta,0.0,1.0)
	direction = direction.lerp(wanted,blend).normalized()
	global_rotation = Default_Rotation + direction.angle()


func _process_mine_trigger() -> void:
	if elapsed < 0.35:
		return

	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if target == Master:
			continue
		if not _master_can_damage(target):
			continue
		if global_position.distance_to(target.global_position) <= trigger_radius:
			_explode()
			return


func _on_hitbox_on_hit(_hurt:hurtbox) -> void:
	if not is_multiplayer_authority():
		return
	if projectile_mode == ProjectileMode.ROCKET:
		_explode()


func when_collide(_speed:float,_collision:KinematicCollision2D) -> void:
	if not is_multiplayer_authority():
		return
	if projectile_mode == ProjectileMode.ROCKET:
		_explode()


func _explode() -> void:
	if exploded:
		return
	exploded = true

	Speed = 0.0
	direction = Vector2.ZERO
	set_physics_process(false)
	set_collision_layer_value(1,false)
	set_collision_layer_value(2,false)
	set_collision_layer_value(3,false)
	set_collision_mask_value(1,false)
	set_collision_mask_value(2,false)
	set_collision_mask_value(3,false)
	if self_hitbox:
		self_hitbox.monitoring = false

	if is_instance_valid(Master) and Master.has_method("_rpc_show_explosion_everywhere"):
		Master.call(
			"_rpc_show_explosion_everywhere",
			global_position,
			explosion_radius,
			Color(1.0,0.48,0.12,0.95) if projectile_mode == ProjectileMode.ROCKET else Color(1.0,0.76,0.24,0.92)
		)

	if is_instance_valid(Master) and Master.has_method("_play_sfx_everywhere"):
		Master.call("_play_sfx_everywhere","explosion1",{},true,true)

	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue

		var target:ball = node as ball
		if not _master_can_damage(target):
			continue

		var distance:float = global_position.distance_to(target.global_position)
		if distance > explosion_radius:
			continue

		var falloff:float = lerpf(1.0,0.45,clampf(distance / explosion_radius,0.0,1.0))
		var repel_dir:Vector2 = (target.global_position - global_position).normalized()
		if repel_dir.length_squared() <= 0.001:
			repel_dir = Vector2.RIGHT.rotated(randf_range(0.0,TAU))

		if is_instance_valid(Master) and Master.has_method("_clown_damage_target"):
			Master.call(
				"_clown_damage_target",
				target,
				explosion_damage * falloff,
				repel_dir * 620.0 * falloff,
				false,
				true,
				{"shape":"circle","center":global_position,"radius":explosion_radius,"source":self}
			)

	if image:
		image.visible = false

	await get_tree().create_timer(0.08).timeout
	Game.free_node(self)


func _master_can_damage(target:ball) -> bool:
	if not is_instance_valid(Master):
		return false
	if Master.has_method("_can_damage_ball"):
		return bool(Master.call("_can_damage_ball",target))
	return false


func Die() -> void:
	if exploded:
		return
	_explode()
