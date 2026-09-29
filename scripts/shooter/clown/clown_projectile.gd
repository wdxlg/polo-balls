extends ball
const PROJECTILE_CONTACT = preload("res://scripts/projectile_contact.gd")

# 小丑专用投射物 V9.3：
# 0 玩具锤 / 1 狙击弹 / 2 火箭 / 3 回旋镖
# V9.3：回旋镖改成按目标冷却重复命中，并增加高速扫掠兜底。

enum ProjectileMode {
	HAMMER,
	SNIPER,
	ROCKET,
	BOOMERANG,
}

@export var projectile_mode:ProjectileMode = ProjectileMode.HAMMER
@export var projectile_skin_path:String = ""

@export_category("直接命中")
@export var impact_damage:float = 10.0
# V7：投射物直接命中的击退也使用通用 ball.apply_knockback()。
@export var impact_knockback_distance:float = 0.0
@export var impact_knockback_speed:float = 700.0
@export_range(0.0,2.0,0.05) var impact_wall_bounce_strength:float = 0.0
@export var impact_stun_duration:float = 0.0
@export var impact_lock_control:bool = true
@export var ignore_armor_on_hit:bool = false
@export var sniper_sweep_radius:float = 26.0

@export_category("火箭")
@export var explosion_damage:float = 35.0
@export var explosion_radius:float = 120.0

@export_category("回旋镖")
@export var boomerang_distance:float = 285.0
@export var return_finish_distance:float = 30.0
@export_range(1.0,30.0,0.5) var boomerang_return_smoothing:float = 9.0
@export var boomerang_spin_speed:float = 9.5
@export var boomerang_hit_separation:float = 14.0
@export_range(0.05,1.0,0.01) var boomerang_same_target_cooldown:float = 0.24
@export var boomerang_sweep_radius:float = 42.0

@export_category("视觉尺寸（像素长边）")
@export var hammer_visual_size:float = 92.0
@export var sniper_visual_size:float = 78.0
@export var rocket_visual_size:float = 120.0
@export var boomerang_visual_size:float = 90.0

@export_category("生命周期")
@export var max_lifetime:float = 5.0

var elapsed:float = 0.0
var exploded:bool = false
var spawn_position:Vector2 = Vector2.ZERO
var returning:bool = false
var boomerang_outbound_travelled:float = 0.0
var boomerang_last_hit_msec:Dictionary = {}


func _ready() -> void:
	super()

	Can_Attack = false
	Can_Skill = false
	Damage = 0
	spawn_position = global_position

	# 小丑投射物应该造成伤害，而不是像一个 1HP 角色一样被敌人的普通碰撞打死。
	# 仍保留自己的 hitbox 用来打人；自身 hurtbox 只作为继承结构存在。
	if self_hurtbox != null:
		self_hurtbox.monitoring = false
		self_hurtbox.monitorable = false
		self_hurtbox.collision_layer = 0
		self_hurtbox.collision_mask = 0

	# 物理体也忽略发射者，避免刚生成就在小丑身体内部碰撞并立刻销毁/反弹。
	if is_instance_valid(Master) and Master is PhysicsBody2D:
		add_collision_exception_with(Master as PhysicsBody2D)

	_apply_projectile_skin()


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
	if max_side <= 0.0:
		return

	var target_size:float = hammer_visual_size
	match projectile_mode:
		ProjectileMode.HAMMER:
			target_size = hammer_visual_size
		ProjectileMode.SNIPER:
			target_size = sniper_visual_size
		ProjectileMode.ROCKET:
			target_size = rocket_visual_size
		ProjectileMode.BOOMERANG:
			target_size = boomerang_visual_size

	sprite.scale = Vector2.ONE * (target_size / max_side)
	sprite.z_index = 12
	_apply_collision_size_for_mode()


func _apply_collision_size_for_mode() -> void:
	# ball.tscn 使用 200x41.875 的矩形 Shape；这里按武器视觉调整缩放，
	# 避免出现“图很大但碰撞仍只有几像素”的错觉。
	var shape_scale:Vector2 = Vector2(0.22,0.42)
	match projectile_mode:
		ProjectileMode.HAMMER:
			shape_scale = Vector2(0.40,0.90)
		ProjectileMode.SNIPER:
			shape_scale = Vector2(0.32,0.30)
		ProjectileMode.ROCKET:
			shape_scale = Vector2(0.50,1.00)
		ProjectileMode.BOOMERANG:
			shape_scale = Vector2(0.40,0.90)

	if collision_shape_2d != null:
		collision_shape_2d.scale = shape_scale
	if self_hitbox != null:
		var hit_shape:CollisionShape2D = self_hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if hit_shape != null:
			hit_shape.scale = shape_scale


func tick_physics(state:State,delta:float) -> void:
	if not is_multiplayer_authority():
		return
	if exploded:
		return

	elapsed += delta
	if elapsed >= max_lifetime:
		_finish_projectile()
		return

	if projectile_mode == ProjectileMode.BOOMERANG:
		_process_boomerang(delta)
		if image != null:
			image.rotation += boomerang_spin_speed * delta
		if exploded:
			return

	var before_move:Vector2 = global_position
	super(state,delta)
	if is_queued_for_deletion() or bool(get_meta("allay_captured",false)): return

	# 狙击弹速度很高，额外做一次“上一帧位置 -> 当前帧位置”的线段扫掠，
	# 避免只靠 Area2D 离散重叠时从小球中间穿过去。
	if projectile_mode == ProjectileMode.SNIPER and not exploded:
		_swept_sniper_hit(before_move,global_position)

	if projectile_mode == ProjectileMode.BOOMERANG and not exploded:
		if not returning:
			boomerang_outbound_travelled += before_move.distance_to(global_position)
			if boomerang_outbound_travelled >= boomerang_distance:
				returning = true
		# 回旋镖也做扫掠检测：大图、高速、反弹时都不再只依赖离散 Area2D 进入信号。
		_swept_boomerang_hit(before_move,global_position)


func _process_boomerang(delta:float) -> void:
	if returning:
		if not is_instance_valid(Master):
			_finish_projectile()
			return

		var to_master:Vector2 = Master.global_position - global_position
		if to_master.length() <= return_finish_distance:
			_finish_projectile()
			return

		if to_master.length_squared() > 0.001:
			var desired:Vector2 = to_master.normalized()
			if direction.length_squared() <= 0.001:
				direction = desired
			else:
				var weight:float = 1.0 - exp(-maxf(boomerang_return_smoothing,0.01) * maxf(delta,0.0))
				var angle:float = lerp_angle(direction.angle(),desired.angle(),clampf(weight,0.0,1.0))
				direction = Vector2.RIGHT.rotated(angle)
			global_rotation = Default_Rotation + direction.angle()


func _swept_sniper_hit(start:Vector2,finish:Vector2) -> void:
	if not is_instance_valid(Master):
		return
	if not Master.has_method("_can_damage_ball"):
		return

	var segment:Vector2 = finish - start
	var segment_len_sq:float = segment.length_squared()
	if segment_len_sq <= 0.0001:
		return

	var best_target:ball = null
	var best_t:float = INF

	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if PROJECTILE_CONTACT.ignores(target): continue
		if not bool(Master.call("_can_damage_ball",target)):
			continue

		var t:float = clampf((target.global_position - start).dot(segment) / segment_len_sq,0.0,1.0)
		var nearest:Vector2 = start + segment * t
		if target.global_position.distance_to(nearest) > sniper_sweep_radius:
			continue

		if t < best_t:
			best_t = t
			best_target = target

	if best_target != null:
		_damage_target(
			best_target,
			impact_damage,
			direction.normalized(),
			true,
			{"shape":"capsule","from":start,"to":finish,"half_width":maxf(sniper_sweep_radius,1.0),"source":self}
		)
		_finish_projectile()


func _on_hitbox_on_hit(hurt:hurtbox) -> void:
	if not is_multiplayer_authority():
		return
	if exploded:
		return
	var target:ball = _hurtbox_target_ball(hurt)
	if target == null or PROJECTILE_CONTACT.ignores(target):
		return
	if not is_instance_valid(Master):
		return

	match projectile_mode:
		ProjectileMode.HAMMER:
			_damage_target(target,impact_damage,direction.normalized(),false,_direct_hit_damage_space())
			_finish_projectile()

		ProjectileMode.SNIPER:
			_damage_target(target,impact_damage,direction.normalized(),true,_direct_hit_damage_space())
			_finish_projectile()

		ProjectileMode.ROCKET:
			_explode()

		ProjectileMode.BOOMERANG:
			_try_boomerang_hit(target)


func _try_boomerang_hit(target:ball,damage_space:Variant = null) -> bool:
	if PROJECTILE_CONTACT.ignores(target): return false
	if target == null or not is_instance_valid(target):
		return false
	if not is_instance_valid(Master):
		return false
	if not Master.has_method("_can_damage_ball"):
		return false
	if not bool(Master.call("_can_damage_ball",target)):
		return false

	var target_id:int = target.get_instance_id()
	var now_msec:int = Time.get_ticks_msec()
	var cooldown_msec:int = int(round(maxf(boomerang_same_target_cooldown,0.0) * 1000.0))
	if cooldown_msec > 0 and boomerang_last_hit_msec.has(target_id):
		if now_msec - int(boomerang_last_hit_msec[target_id]) < cooldown_msec:
			return false

	boomerang_last_hit_msec[target_id] = now_msec
	_damage_target(target,impact_damage,direction.normalized(),false,damage_space if damage_space != null else _direct_hit_damage_space())
	_bounce_boomerang_from_target(target)

	if boomerang_last_hit_msec.size() > 64:
		_cleanup_boomerang_hit_records(now_msec,maxi(cooldown_msec * 4,1000))
	return true


func _cleanup_boomerang_hit_records(now_msec:int,keep_msec:int) -> void:
	var to_remove:Array[int] = []
	for target_id in boomerang_last_hit_msec:
		if now_msec - int(boomerang_last_hit_msec[target_id]) > keep_msec:
			to_remove.append(int(target_id))
	for target_id in to_remove:
		boomerang_last_hit_msec.erase(target_id)


func _swept_boomerang_hit(start:Vector2,finish:Vector2) -> void:
	if projectile_mode != ProjectileMode.BOOMERANG or exploded:
		return
	if not is_instance_valid(Master) or not Master.has_method("_can_damage_ball"):
		return

	var segment:Vector2 = finish - start
	var segment_len_sq:float = segment.length_squared()
	if segment_len_sq <= 0.0001:
		return

	var now_msec:int = Time.get_ticks_msec()
	var cooldown_msec:int = int(round(maxf(boomerang_same_target_cooldown,0.0) * 1000.0))
	var best_target:ball = null
	var best_t:float = INF

	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var target:ball = node as ball
		if PROJECTILE_CONTACT.ignores(target): continue
		if not bool(Master.call("_can_damage_ball",target)):
			continue

		var target_id:int = target.get_instance_id()
		if cooldown_msec > 0 and boomerang_last_hit_msec.has(target_id):
			if now_msec - int(boomerang_last_hit_msec[target_id]) < cooldown_msec:
				continue

		var t:float = clampf((target.global_position - start).dot(segment) / segment_len_sq,0.0,1.0)
		var nearest:Vector2 = start + segment * t
		if target.global_position.distance_to(nearest) > maxf(boomerang_sweep_radius,1.0):
			continue

		if t < best_t:
			best_t = t
			best_target = target

	if best_target != null:
		_try_boomerang_hit(
			best_target,
			{"shape":"capsule","from":start,"to":finish,"half_width":maxf(boomerang_sweep_radius,1.0),"source":self}
		)


func _bounce_boomerang_from_target(target:ball) -> void:
	if target == null or direction.length_squared() <= 0.001:
		return

	var normal:Vector2 = global_position - target.global_position
	if normal.length_squared() <= 0.001:
		normal = -direction
	else:
		normal = normal.normalized()

	var bounced:Vector2 = direction.bounce(normal)
	if bounced.length_squared() <= 0.001:
		bounced = -direction
	direction = bounced.normalized()
	global_rotation = Default_Rotation + direction.angle()

	# 把回旋镖轻轻推出接触面，避免同一物理接触连续卡住。
	global_position += direction * maxf(boomerang_hit_separation,0.0)


func _direct_hit_damage_space() -> Dictionary:
	var radius:float = 26.0
	match projectile_mode:
		ProjectileMode.HAMMER:
			radius = 42.0
		ProjectileMode.SNIPER:
			radius = maxf(sniper_sweep_radius,1.0)
		ProjectileMode.ROCKET:
			radius = 50.0
		ProjectileMode.BOOMERANG:
			radius = maxf(boomerang_sweep_radius,1.0)
	return {"shape":"circle","center":global_position,"radius":radius,"source":self}


func _damage_target(
	target:ball,
	amount:float,
	knockback_direction:Vector2,
	ignore_armor:bool,
	damage_space:Variant = null
) -> void:
	if PROJECTILE_CONTACT.ignores(target): return
	if not is_instance_valid(Master):
		return
	if not Master.has_method("_clown_damage_target"):
		return
	if not Master.has_method("_can_damage_ball"):
		return
	if not bool(Master.call("_can_damage_ball",target)):
		return

	var before_health:float = float(target.health)
	var before_block:float = float(target.block)
	var resolved_space:Variant = damage_space if damage_space != null else _direct_hit_damage_space()

	# 伤害仍由小丑统一处理；击退改为所有 ball 都能使用的通用接口。
	# 狙击弹是“子弹”，因此关闭小丑旧的通用 Hit_Audio，改用专用子弹命中音。
	Master.call(
		"_clown_damage_target",
		target,
		amount,
		Vector2.ZERO,
		ignore_armor,
		projectile_mode != ProjectileMode.SNIPER,
		resolved_space
	)

	if projectile_mode == ProjectileMode.SNIPER:
		var health_loss:float = maxf(before_health - float(target.health),0.0)
		var block_loss:float = maxf(before_block - float(target.block),0.0)
		if block_loss > 0.0 or health_loss <= 0.0:
			_play_bullet_impact_sfx("子弹打墙",0.0)
		else:
			_play_bullet_impact_sfx("子弹打人",-1.0)

	if impact_knockback_distance <= 0.0:
		return
	if knockback_direction.length_squared() <= 0.001:
		return

	target.apply_knockback(
		knockback_direction.normalized(),
		impact_knockback_distance,
		impact_knockback_speed,
		impact_wall_bounce_strength,
		impact_stun_duration,
		{
			"source": Master,
			"lock_control": impact_lock_control,
			"max_wall_bounces": 1,
			"stop_on_character": true,
			"use_speed_falloff": false,
		}
	)


func when_collide(_speed:float,collision:KinematicCollision2D) -> void:
	if not is_multiplayer_authority():
		return
	if exploded:
		return

	match projectile_mode:
		ProjectileMode.ROCKET:
			_explode()

		ProjectileMode.BOOMERANG:
			if collision != null:
				var normal:Vector2 = collision.get_normal()
				if direction.dot(normal) < 0.0:
					direction = direction.bounce(normal).normalized()
					global_rotation = Default_Rotation + direction.angle()
					global_position += direction * 3.0

		ProjectileMode.HAMMER:
			_finish_projectile()

		ProjectileMode.SNIPER:
			# 狙击子弹撞到地形/硬物，使用“子弹打墙”；锤子等投射物不使用。
			_play_bullet_impact_sfx("子弹打墙",0.0)
			_finish_projectile()


func _play_bullet_impact_sfx(sfx_name:String,volume_offset:float = 0.0) -> void:
	var params:Dictionary = {
		"volume": volume_offset,
		"pitch": randf_range(0.96,1.04),
	}
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc(sfx_name,params,false,true)
	else:
		Audios.play_sfx(sfx_name,params,false,true)


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
		# 火箭可能正处于 Area2D 的命中/进入回调中，物理回调里不要直接改 monitoring。
		self_hitbox.set_deferred("monitoring",false)
		self_hitbox.set_deferred("monitorable",false)

	if is_instance_valid(Master) and Master.has_method("_clown_explosion"):
		Master.call(
			"_clown_explosion",
			global_position,
			explosion_radius,
			explosion_damage
		)

	if image:
		image.visible = false

	await get_tree().create_timer(0.06).timeout
	Game.free_node(self)


func _finish_projectile() -> void:
	if exploded:
		return
	exploded = true
	Speed = 0.0
	direction = Vector2.ZERO
	if image:
		image.visible = false
	Game.free_node(self)


# 投射物不是可被击杀的角色。敌方 Hitbox 即使通过 CharacterBody2D 的
# 物理接触兜底直接调用到这里，也不会把回旋镖/火箭等打成 0HP。
func hit_white(_ignore_block:bool = false):
	pass


func take_damage(_damage:float,_ignore_block:bool = false) -> void:
	pass


func Die() -> void:
	if projectile_mode == ProjectileMode.ROCKET:
		_explode()
	else:
		_finish_projectile()
