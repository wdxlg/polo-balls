extends "res://scripts/characters/我的世界/mc_mob_base.gd"
const U=preload("res://scripts/characters/我的世界/new5/utils.gd")
const CLOSED = preload("res://Images/characters/我的世界/潜影贝/关壳.png")
const OPEN = preload("res://Images/characters/我的世界/潜影贝/开壳.png")
@export_range(0.0,1.0,0.05) var hurt_teleport_chance:float = 0.10
var _teleport_pending:bool = false
var _restoring_closed_health:bool = false
@export var closed_speed_ratio:float = 0.40
@export var closed_duration:float = 2.2
@export var open_duration:float = 1.7
@export var gravity_acceleration:float = 640.0
var gravity_direction:Vector2 = Vector2.DOWN
var shell_open:bool = false
var _shell_left:float = 1.1
var _shots_left:int = 0
var _shot_wait:float = 0.0
var _turn_wait:float = 0.0
var _shell_anchor_y:float = 0.0
@export var volley_min:int = 2
@export var volley_max:int = 4
@export var volley_growth_interval:float = 10.0
var _combat_elapsed:float = 0.0
var _last_closed_feedback_msec:int = -10000
func _ready() -> void:
	super._ready()
	configure_external_directional_gravity_locomotion(true)
	configure_external_directional_gravity_hop(false)
	direction = Vector2.RIGHT
	_shell_anchor_y = image.position.y + float(CLOSED.get_height())*100.0/float(CLOSED.get_width())*0.5
	_update_shell_visual()
func get_preview_texture() -> Texture2D: return CLOSED
func get_external_directional_gravity() -> Vector2:
	return gravity_direction * gravity_acceleration + super.get_external_directional_gravity()
func get_volley_count_range() -> Vector2i:
	var gain:int = int(floor((_combat_elapsed+0.000001)/maxf(volley_growth_interval,0.1)))
	return Vector2i(maxi(volley_min,1)+gain,maxi(volley_max,maxi(volley_min,1))+gain)
func tick_physics(state:State,delta:float) -> void:
	if is_multiplayer_authority() and health > 0 and is_combat_runtime_active():
		_combat_elapsed += maxf(delta,0.0)
	if mc_live():
		var target:ball = null if is_player_controlled() else mc_nearest(delta)
		_turn_wait = maxf(0.0,_turn_wait - delta)
		_shell_left -= delta
		_shot_wait -= delta
		if _shell_left <= 0.0 and (not shell_open or _shots_left <= 0 or target == null):
			shell_open = not shell_open
			_shell_left = open_duration if shell_open else closed_duration
			var counts:Vector2i = get_volley_count_range()
			_shots_left = _mc_rng.randi_range(counts.x,counts.y) if shell_open else 0
			_shot_wait = 0.15
			_update_shell_visual()
			mc_play("open" if shell_open else "close",-4.0)
		if not is_player_controlled() and shell_open and _shots_left > 0 and _shot_wait <= 0.0 and target != null and not dizziness:
			if fire_bullet(target):
				_shots_left -= 1
				_shot_wait = _mc_rng.randf_range(0.22,0.38)
			else:
				_shot_wait = 0.10 # 全局弹体预算满时等空位，不把尚未发出的子弹算作已发。
	super.tick_physics(state,delta)
	if graphics != null: graphics.rotation = gravity_direction.angle() - Vector2.DOWN.angle()
func controlled_attack_action() -> void:
	if not is_player_controlled() or not mc_live() or dizziness or not shell_open or _shots_left<=0 or _shot_wait>0.0 or not has_player_control_aim(): return
	var point:Vector2=player_control_aim_world_position()
	var chosen:ball=null
	var nearest:float=INF
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not mc_enemy(raw) or not raw.is_combat_lockable(): continue
		var distance:float=ball.body_point(raw,point).distance_to(point)
		if distance<=U.radius(raw)+6.0 and distance<nearest:
			chosen=raw as ball
			nearest=distance
	if chosen!=null and fire_bullet(chosen):
		_shots_left-=1
		_shot_wait=_mc_rng.randf_range(0.22,0.38)
func move(speed:float,delta:float) -> void:
	# 公共 Sans 定向重力负责下落；自主移动永远只有贴墙切线分量。
	var tangent:Vector2 = gravity_direction.orthogonal()
	direction = tangent * _external_directional_gravity_lateral_sign
	super.move(speed * (1.0 if shell_open else closed_speed_ratio),delta)
func _process_external_directional_gravity_locomotion_collisions() -> void:
	super._process_external_directional_gravity_locomotion_collisions()
	# 公共定向重力刻意忽略人物掉头；潜影贝必须单独把反弹写回切线符号，
	# 否则通用碰撞只改 direction，下一帧 move() 又会覆盖回原方向。
	for i:int in range(get_slide_collision_count()):
		var contact:KinematicCollision2D = get_slide_collision(i)
		if contact.get_collider() is ball: _bounce_from_character(contact.get_normal())
	# 贴墙转向保护只限制换墙，不能屏蔽这段时间里撞到人物的反弹。
	if _turn_wait > 0.0: return
	for i:int in range(get_slide_collision_count()):
		var contact:KinematicCollision2D = get_slide_collision(i)
		if contact.get_collider() is ball: continue
		var normal:Vector2 = contact.get_normal()
		if _last_requested_velocity.dot(normal) >= -0.01: continue
		accept_wall_normal(normal)
		if _turn_wait > 0.0: break
func _bounce_from_character(normal:Vector2) -> void:
	if normal.length_squared() < 0.000001: return
	normal = normal.normalized()
	if _last_requested_velocity.dot(normal) >= -0.01: return
	var reflected:Vector2 = _last_requested_velocity.bounce(normal)
	var tangent:Vector2 = gravity_direction.orthogonal()
	var lateral:float = reflected.dot(tangent)
	if absf(lateral) > 0.01: _external_directional_gravity_lateral_sign = signf(lateral)
	if absf(normal.dot(gravity_direction)) > 0.01:
		_external_directional_gravity_velocity = gravity_direction*reflected.dot(gravity_direction)
		_external_directional_gravity_grounded = false
	direction = tangent*_external_directional_gravity_lateral_sign
	# 人物不是墙：不更改贴附方向、开壳阶段或连射进度。
func accept_wall_normal(normal:Vector2) -> void:
	# 上墙只反弹，不把重力改为向上。
	if normal.y > 0.65:
		var tangent:Vector2 = gravity_direction.orthogonal()
		if tangent.y != 0.0: _external_directional_gravity_lateral_sign = signf(tangent.y)
		return
	var next:Vector2 = Vector2.DOWN
	if absf(normal.x) > 0.65: next = Vector2.LEFT if normal.x > 0.0 else Vector2.RIGHT
	elif normal.y > -0.65: return
	if next == gravity_direction: return
	var away:Vector2 = -gravity_direction
	gravity_direction = next
	up_direction = -next
	clear_external_directional_gravity_velocity()
	_external_directional_gravity_grounded = false
	_external_directional_gravity_lateral_sign = 1.0 if next.orthogonal().dot(away) >= 0.0 else -1.0
	direction = next.orthogonal() * _external_directional_gravity_lateral_sign
	_turn_wait = 0.18
func can_receive_hit_from(_incoming:hitbox) -> bool:
	return shell_open
func on_incoming_hit_rejected(incoming:hitbox) -> void:
	if not is_instance_valid(incoming) or health <= 0: return
	var attacker:ball = _incoming_hit_attacker(incoming)
	var point:Vector2 = _estimate_block_impact_position(incoming)
	_closed_block_feedback(point,float(attacker.Damage) if is_instance_valid(attacker) else 8.0)
	if is_instance_valid(attacker) and _is_ranged_hit_source(attacker) and should_destroy_projectile_on_rejected_hit(incoming):
		attacker.on_projectile_blocked_by(self,point)
func receive_positional_damage(damage:float,point:Vector2,ignore_block:bool = false,source:Node = null) -> bool:
	if damage > 0.0 and not shell_open and not incoming_damage_bypasses_guard():
		var toward:Vector2 = point-global_position
		var impact:Vector2 = global_position+toward.limit_length(_hit_burst_character_radius())
		_closed_block_feedback(impact,damage)
		return false
	var suppressed:bool = health_bar.suppress_floating_text if health_bar != null else false
	if health_bar != null and incoming_damage_bypasses_guard(): health_bar.suppress_floating_text = false
	var accepted:bool = super.receive_positional_damage(damage,point,ignore_block,source)
	if health_bar != null: health_bar.suppress_floating_text = suppressed
	return accepted
func hit_white(ignore_block:bool = false):
	if shell_open or incoming_damage_bypasses_guard(): super.hit_white(ignore_block)
func hit_white_visual_only() -> void:
	if shell_open or incoming_damage_bypasses_guard(): super.hit_white_visual_only()
func hit_white_method(power:float):
	super.hit_white_method(power if shell_open or incoming_damage_bypasses_guard() else 0.0)
func _closed_block_feedback(point:Vector2,damage:float) -> void:
	if not is_inside_tree() or health <= 0 or damage <= 0.0: return
	var now:int = Time.get_ticks_msec()
	if now-_last_closed_feedback_msec < 100: return
	_last_closed_feedback_msec = now
	notify_block_burst_feedback(point,damage,_positional_damage_feedback_coverage(),now ^ int(get_instance_id()))
func _play_block_burst_feedback_local(point:Vector2,raw_damage:float,coverage_width:float,seed:int) -> void:
	super._play_block_burst_feedback_local(point,raw_damage,coverage_width,seed)
	# 格挡反馈使用原版闭壳受伤声，不抽45%的普通 hurt，也不被呼吸/射击声挤掉。
	MC_AUDIO.play(self,"entity.shulker.hurt_closed",point,0.0,false,true)
	# 与木矛相同的短促白圈参数；白色爆线已由公共入口生成，不给壳体加闪白。
	var ring := Line2D.new()
	ring.name = "潜影贝_闭壳格挡白圈"
	ring.top_level = true
	ring.z_index = 520
	ring.width = 0.95
	ring.default_color = Color(1.0,1.0,1.0,0.96)
	ring.antialiased = true
	for i:int in range(21): ring.add_point(Vector2.RIGHT.rotated(TAU*float(i)/20.0)*3.2)
	get_tree().current_scene.add_child(ring)
	ring.add_to_group("MCShulkerBlockRing")
	ring.global_position = point
	ring.scale = Vector2(0.65,0.65)
	var tween := ring.create_tween().set_parallel(true)
	tween.tween_property(ring,"scale",Vector2(2.15,2.15),0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring,"modulate",Color(1.0,1.0,1.0,0.0),0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(ring.queue_free)
func take_damage(damage:float,ignore_block:bool = false) -> void:
	if damage > 0.0 and not shell_open and not incoming_damage_bypasses_guard():
		_closed_block_feedback(global_position,damage)
		return
	super.take_damage(damage,ignore_block)
func receive_spatial_damage(damage:float,space:Variant,ignore_block:bool = false,_raw_health:bool = false) -> bool:
	# 所有空间命中仍走公共几何检测，但不允许 raw_health 绕过完全格挡。
	return super.receive_spatial_damage(damage,space,ignore_block,false)
func on_actual_health_damage_received(actual_health_damage:float,health_before:float) -> void:
	if not is_multiplayer_authority(): return
	if _restoring_closed_health: return
	if not shell_open and not current_health_damage_bypasses_guard():
		# 覆盖毒/流血和旧技能直接写 health 的路径；在 setter 进入死亡调度前恢复。
		_restoring_closed_health = true
		health = int(health_before)
		_restoring_closed_health = false
		_closed_block_feedback(global_position,actual_health_damage)
		return
	super.on_actual_health_damage_received(actual_health_damage,health_before)
	if health > 0 and is_multiplayer_authority() and not _teleport_pending and _mc_rng.randf() < hurt_teleport_chance:
		_teleport_pending = true
		call_deferred("mc_try_wall_teleport")
func mc_ambient_allowed() -> bool: return shell_open
func mc_try_wall_teleport() -> bool:
	_teleport_pending = false
	if not is_multiplayer_authority() or health <= 0 or not is_inside_tree(): return false
	var arena:Rect2 = mc_arena_rect().grow(-3.0)
	for attempt:int in range(64):
		var ray_direction:Vector2 = [Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT][_mc_rng.randi_range(0,2)]
		if ray_direction == gravity_direction: continue
		var origin:Vector2 = Vector2(_mc_rng.randf_range(arena.position.x,arena.end.x),_mc_rng.randf_range(arena.position.y,arena.end.y))
		var query := PhysicsRayQueryParameters2D.create(origin,origin+ray_direction*(arena.size.x+arena.size.y),1,[get_rid()])
		var hit:Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
		if hit.is_empty(): continue
		var normal:Vector2 = hit["normal"]
		if normal.y > 0.5 or normal.dot(-ray_direction) < 0.9: continue
		var half:Vector2 = collision_shape_2d.shape.get_rect().size*0.5
		var trans:Transform2D = collision_shape_2d.global_transform
		var support:float = absf(normal.dot(trans.x))*half.x+absf(normal.dot(trans.y))*half.y
		var point:Vector2 = hit["position"]+normal*(support+1.5)
		if not arena.has_point(point) or not mc_body_position_clear(point): continue
		global_position = point
		gravity_direction = -normal
		up_direction = normal
		clear_external_directional_gravity_velocity()
		_external_directional_gravity_grounded = false
		# 纯换位：不重置开壳时间、剩余发射数、发射冷却或攻击状态，也不重抽移动方向。
		direction = gravity_direction.orthogonal()*_external_directional_gravity_lateral_sign
		graphics.rotation = gravity_direction.angle()-Vector2.DOWN.angle()
		_turn_wait = 0.18
		mc_play("teleport",-3.0)
		return true
	return false
func _update_shell_visual() -> void:
	if not shell_open:
		if hit_white_tween: hit_white_tween.kill()
		super.hit_white_method(0.0)
	if not image is Sprite2D: return
	if health_bar != null: health_bar.suppress_floating_text = not shell_open
	# 原版盖子升降/旋转由 MinecraftAnimation 连续采样；此处仅更新战斗 UI。
func fire_bullet(target:ball) -> bool:
	if not mc_enemy(target) or get_tree().get_nodes_in_group("MCShulkerBullet").size() >= 64: return false
	mc_play("shoot",-3.0)
	var bullet:ball = load("res://scenes/shooter/潜影弹.tscn").instantiate()
	bullet.Master = self
	bullet.Master_name = str(get_path())
	bullet.Team = Team
	bullet.Damage = attack_damage()
	bullet.set("target_ref",weakref(target))
	bullet.direction = Vector2.RIGHT.rotated(float(_mc_rng.randi_range(0,3)) * PI * 0.5)
	bullet.name = Game.return_random_name(bullet)
	get_tree().current_scene.add_child(bullet,true)
	bullet.global_position = global_position - gravity_direction * 16.0
	bullet.add_to_group("BattleTransient")
	return true

func mc_hurt_event() -> String: return "hurt" if shell_open else "hurt_closed"
