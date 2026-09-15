extends "res://scripts/characters/我的世界/mc_mob_base.gd"
const LEVITATION = preload("res://scripts/effects/我的世界/潜影浮空.gd")
var target_ref:WeakRef
var _life:float = 7.0
var _course_wait:float = 0.0
var _course:Vector2 = Vector2.RIGHT
var _consumed:bool = false
var _trail_wait:float = 0.0
func _ready() -> void:
	Type = Ball_Type.Shooter_with_Health
	collision_layer = 0
	collision_mask = 1
	super._ready()
	self_hitbox.set_deferred("monitoring",false)
	add_to_group("MCShulkerBullet")
	# 保留内部三格耐久，但永不显示通用血条（通用命中逻辑仍持有该节点）。
	if health_bar != null:
		health_bar.suppress_floating_text = true
		health_bar.hide()
		health_bar.visibility_layer = 0
		health_bar.process_mode = Node.PROCESS_MODE_DISABLED
	_course = direction
func has_collision_damage() -> bool: return false
func tick_physics(state:State,delta:float) -> void:
	if health <= 0 or _consumed:
		retire()
		return
	if mc_live() and not _consumed:
		_life -= delta
		if _life <= 0.0:
			health = 0
			retire()
			return
		_course_wait -= delta
		var target:Variant = target_ref.get_ref() if target_ref != null else null
		if not is_instance_valid(target) or not mc_enemy(target): target = mc_nearest(delta)
		if is_instance_valid(target):
			var aim:Vector2 = global_position.direction_to(target.global_position)
			if _course_wait <= 0.0:
				_course_wait = _mc_rng.randf_range(0.28,0.55)
				_course = Vector2(signf(aim.x),0) if _mc_rng.randf() < 0.5 else Vector2(0,signf(aim.y))
				if _course == Vector2.ZERO: _course = aim.orthogonal()
				if _mc_rng.randf() < 0.2: _course = _course.orthogonal()
			var desired:Vector2 = _course.lerp(aim,0.13).normalized()
			direction = Vector2.RIGHT.rotated(rotate_toward(direction.angle(),desired.angle(),delta * 5.0))
	super.tick_physics(state,delta)
func move(speed:float,delta:float) -> void:
	if _consumed: return
	var from:Vector2 = global_position
	velocity = direction * speed
	var wall:KinematicCollision2D = move_and_collide(velocity * delta)
	_trail_wait -= delta
	if _trail_wait <= 0.0:
		_trail_wait = 0.04
		MC_FX.spark(self,global_position-direction*2.0)
	_scan_segment(from,global_position)
	if wall != null and not _consumed:
		mc_play("hit",-5.0)
		health = 0
		retire()
func _scan_segment(from:Vector2,to:Vector2) -> void:
	var shape := CapsuleShape2D.new()
	shape.radius = 3.0
	shape.height = from.distance_to(to) + 6.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D((to-from).angle() + PI * 0.5,from.lerp(to,0.5))
	query.collision_mask = 2
	query.collide_with_bodies = false
	query.collide_with_areas = true
	var candidates:Array[ball] = []
	for info:Dictionary in get_world_2d().direct_space_state.intersect_shape(query,24):
		var area:Variant = info.get("collider")
		if area is hurtbox and area.get_parent() is ball:
			var unit:ball = area.get_parent()
			if mc_enemy(unit) and not candidates.has(unit): candidates.append(unit)
	candidates.sort_custom(func(a:ball,b:ball) -> bool: return from.distance_squared_to(a.global_position) < from.distance_squared_to(b.global_position))
	for unit:ball in candidates:
		if unit.has_method("try_full_projectile_dodge") and unit.call("try_full_projectile_dodge",self): continue
		if unit.receive_positional_damage(attack_damage(),global_position,false,self):
			LEVITATION.apply(unit,Master if is_instance_valid(Master) else self)
		mc_play("hit",-5.0)
		health = 0
		retire()
		return
func take_damage(damage:float,_ignore_block:bool = false) -> void:
	if damage > 0.0 and health > 0 and is_multiplayer_authority():
		health -= 1 # 耐久按攻击次数计算，再高的单次伤害也只消耗一格。
		mc_play("hurt",-4.0)
		if health <= 0: retire()
func receive_spatial_damage(damage:float,space:Variant,ignore_block:bool = false,_raw_health:bool = false) -> bool:
	return super.receive_spatial_damage(damage,space,ignore_block,false)

func retire() -> void:
	if is_queued_for_deletion(): return
	_consumed = true
	for i:int in range(10): MC_FX.spark(self,global_position,true)
	hide()
	if self_hitbox != null: self_hitbox.set_deferred("monitoring",false)
	if is_in_group("MCShulkerBullet"): remove_from_group("MCShulkerBullet")
	if is_in_group("Ball"): remove_from_group("Ball")
	queue_free()
func Die() -> void: retire()
