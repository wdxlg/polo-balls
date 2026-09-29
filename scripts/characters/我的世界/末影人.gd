extends "res://scripts/characters/我的世界/mc_mob_base.gd"
const PROJECTILE_API = preload("res://classes/projectile_interactions.gd")
const VISUAL = preload("res://Images/characters/我的世界/末影人/末影人.png")
const PARTICLE = preload("res://scripts/effects/我的世界/末影粒子.gd")
@export_range(0,1,0.01) var chance_dodge:float = 0.25
@export_range(0,1,0.01) var chance_clone_on_random_dodge:float = 0.40
@export_range(0,1,0.01) var chance_clone_on_projectile_dodge:float = 0.12
@export var gaze_charge_seconds:float = 1.25
@export var gaze_decay_seconds:float = 2.5
@export_range(0.0,1.0,0.05) var gaze_facing_threshold:float = 0.5
@export var gaze_range:float = 340.0
@export var rage_duration:float = 3.0
@export var max_rage_remaining:float = 4.0
@export var max_rage_total:float = 5.0
var _rage_elapsed:float = 0.0
@export_range(0.0,0.3,0.01) var dodge_anger_gain:float = 0.08
var _dodge_anger_hold:float = 0.0
@export var watched_rage_gain:float = 3.0
@export var rage_speed_ratio:float = 1.16
@export var max_clones:int = 6
var rage_remaining:float = 0.0
var gaze_charge:float = 0.0
var last_dodge_kind:String = ""
var _red_amount:float = 0.0
var _gaze_wait:float = 0.0
var _mutual_gaze:bool = false
var _enemy_watching:bool = false
var _dodge_grace:float = 0.0
var _damage_guard:int = 0
var _contact_approved:bool = false
@export var rage_teleport_interval:float = 1.1
var _rage_teleport_wait:float = 0.0
var _rush_left:float = 0.0
var _rush_direction:Vector2 = Vector2.ZERO
var _clones:Array[WeakRef] = []
var _stare_player:AudioStreamPlayer2D
var _anger_ui_wait:float = 0.0
var _anger_text:String = ""
func get_preview_texture() -> Texture2D: return VISUAL
func tick_physics(state:State,delta:float) -> void:
	if mc_live():
		_dodge_grace = maxf(_dodge_grace-delta,0.0)
		_rush_left = maxf(_rush_left-delta,0.0)
		_gaze_wait -= delta
		if _gaze_wait <= 0.0:
			_gaze_wait = 0.10
			_scan_gazes()
		update_rage(delta,_mutual_gaze,_enemy_watching)
		_tick_rage_teleport(delta)
		_anger_ui_wait -= delta
		if _anger_ui_wait <= 0.0:
			_anger_ui_wait = 0.15
			_update_anger_status()
	super.tick_physics(state,delta)
	if image != null:
		_red_amount = move_toward(_red_amount,1.0 if rage_remaining > 0.0 else gaze_charge,delta * 2.5)
		# 叠色而非简单乘红色，黑色的身体也能清楚变红。
		image_color = Color(1.0,0.035,0.055)
		image_color_mix = _red_amount * 0.80
		set_image_color()
func _facing(unit:ball) -> Vector2:
	# 当前人物画面只有左右朝向；斜向移动向量不等于眼睛看向的方向。
	var right:bool = unit._visual_facing_flipped_h == unit.dir_left
	return Vector2.RIGHT.rotated(unit.global_rotation) * (1.0 if right else -1.0)
func _scan_gazes() -> void:
	_mutual_gaze = false
	_enemy_watching = false
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball or not mc_enemy(node): continue
		if node.Type != Ball_Type.Ball: continue
		var relative:Vector2 = global_position - ball.body_point(node,global_position)
		if relative.length_squared() > gaze_range*gaze_range or relative.length_squared() < 1.0: continue
		var to_me:Vector2 = relative.normalized()
		if _facing(node).dot(to_me) < gaze_facing_threshold: continue
		if not mc_line_clear(node.global_position,global_position): continue
		_enemy_watching = true
		if _facing(self).dot(-to_me) >= gaze_facing_threshold: _mutual_gaze = true
func update_rage(delta:float,mutual:bool,watched:bool) -> void:
	_dodge_anger_hold = maxf(_dodge_anger_hold-delta,0.0)
	var was_raging:bool = rage_remaining > 0.0
	if was_raging:
		_rage_elapsed += delta
		rage_remaining = clampf(rage_remaining-delta + (watched_rage_gain*delta if watched else 0.0),0.0,max_rage_remaining)
		rage_remaining = minf(rage_remaining,maxf(max_rage_total-_rage_elapsed,0.0))
		if rage_remaining <= 0.0: gaze_charge = 0.0
	else:
		gaze_charge = clampf(gaze_charge + (delta / maxf(gaze_charge_seconds,0.1) if mutual else (0.0 if _dodge_anger_hold > 0.0 else -delta / maxf(gaze_decay_seconds,0.1))),0.0,1.0)
		if gaze_charge >= 1.0: rage_remaining = rage_duration
	var raging:bool = rage_remaining > 0.0
	# 碰撞伤害由正式场景常开；愤怒只改变颜色、速度与主动绕后能力。
	if raging and not was_raging:
		_rage_elapsed = 0.0
		_rage_teleport_wait = 0.20
		_stop_stare()
		_stare_player = mc_play("stare",-5.0)
	elif not raging:
		_stop_stare()
func move(speed:float,delta:float) -> void:
	if _rush_left > 0.0: direction = _rush_direction
	var manual_input:Vector2 = player_control_direction
	if _rush_left > 0.0 and is_player_controlled():
		# 愤怒背刺的短暂冲撞锁方向，不被 WASD 覆盖；结束后还给玩家移动。
		player_control_direction = _rush_direction
	super.move(speed * (rage_speed_ratio if rage_remaining > 0.0 else 1.0) * (2.4 if _rush_left > 0.0 else 1.0),delta)
	if is_player_controlled():
		player_control_direction = manual_input

func controlled_attack_action() -> void:
	# 左键：只在已有的愤怒期、传送间隔与闪避缓冲结束后主动绕后。
	if not is_player_controlled() or not is_multiplayer_authority() or not mc_live() or not has_player_control_aim():
		return
	if rage_remaining <= 0.0 or _rage_teleport_wait > 0.0 or _dodge_grace > 0.0 or _rush_left > 0.0:
		return
	var target:ball = null
	var best_distance:float = INF
	var aim:Vector2 = player_control_aim_world_position()
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball or not mc_enemy(raw):
			continue
		var candidate:ball = raw as ball
		var distance:float = aim.distance_squared_to(ball.body_point(candidate,aim))
		if distance < best_distance:
			best_distance = distance
			target = candidate
	_rage_teleport_wait = maxf(rage_teleport_interval,0.3) if _try_rage_backstab(target) else 0.25
func when_collide(speed:float,collision:KinematicCollision2D) -> void:
	if _rush_left > 0.0: _rush_left = 0.0
	super.when_collide(speed,collision)
func _ranged_source(source:Node) -> bool:
	return PROJECTILE_API.is_projectile(source)

func _attempt_dodge(source:Node = null,force_projectile:bool = false) -> bool:
	if not mc_live(): return false
	if _dodge_grace > 0.0: return true
	# 顺序是玩法规则：先掷概率闪避，再判断远程必闪。每次攻击只抽一次。
	var random_dodge:bool = _mc_rng.randf() < chance_dodge
	if not random_dodge and not force_projectile and not _ranged_source(source): return false
	last_dodge_kind = "random" if random_dodge else "projectile"
	_dodge_grace = 0.075
	_perform_dodge(source,random_dodge)
	if rage_remaining <= 0.0:
		gaze_charge = minf(gaze_charge+dodge_anger_gain,1.0)
		_dodge_anger_hold = 0.45
		update_rage(0.0,false,false)
		_update_anger_status()
	return true
func try_full_projectile_dodge(projectile:Node = null) -> bool:
	return _attempt_dodge(projectile,true)
func can_receive_hit_from(incoming:hitbox) -> bool:
	var source:ball = _incoming_hit_attacker(incoming)
	if _attempt_dodge(source): return false
	_contact_approved = true
	return true
func _on_hurtbox_on_hurt(_incoming:hitbox) -> void:
	_contact_approved = false
func on_incoming_hit_rejected(_incoming:hitbox) -> void:
	pass # 闪避不是格挡，不销毁子弹、不播放格挡反馈。
func should_destroy_projectile_on_rejected_hit(_incoming:hitbox) -> bool: return false
func receive_positional_damage(damage:float,point:Vector2,ignore_block:bool = false,source:Node = null) -> bool:
	if damage <= 0.0: return false
	if _damage_guard == 0 and _attempt_dodge(source): return false
	_damage_guard += 1
	var accepted:bool = super.receive_positional_damage(damage,point,ignore_block,source)
	_damage_guard -= 1
	return accepted
func receive_spatial_damage(damage:float,space:Variant,ignore_block:bool = false,raw_health:bool = false) -> bool:
	var source:Node = space.get("source",null) if space is Dictionary else null
	if damage <= 0.0 or (_damage_guard == 0 and _attempt_dodge(source)): return false
	_damage_guard += 1
	var accepted:bool = super.receive_spatial_damage(damage,space,ignore_block,raw_health)
	_damage_guard -= 1
	return accepted
func take_damage(damage:float,ignore_block:bool = false) -> void:
	if _contact_approved:
		_contact_approved = false
	elif _damage_guard == 0 and damage > 0.0 and _attempt_dodge(): return
	super.take_damage(damage,ignore_block)
func _perform_dodge(source:Node,random_dodge:bool) -> void:
	var target:ball = source as ball
	if is_instance_valid(target) and is_instance_valid(target.Master): target = target.Master
	if not mc_enemy(target): target = mc_nearest()
	_rush_left = 0.0 # 普通远程闪避不能延续上一次背刺冲撞。
	# 每次独立闪避都重新抽取普通移动方向；只有真正背刺时才改为朝敌人冲。
	direction = Vector2.RIGHT.rotated(_mc_rng.randf_range(-PI,PI))
	# 保底闪避只留短缓冲，不反复重置完整技能冷却，避免连续来箭永久压住主动进攻。
	_rage_teleport_wait = maxf(_rage_teleport_wait,0.30)
	if rage_remaining > 0.0 and random_dodge and _try_rage_backstab(target):
		_rage_teleport_wait = maxf(rage_teleport_interval,0.3)
	else:
		_teleport_to(mc_safe_random_position())
	var clone_chance:float = chance_clone_on_random_dodge if random_dodge else chance_clone_on_projectile_dodge
	if _mc_rng.randf() < clone_chance: call_deferred("_spawn_clones",_mc_rng.randi_range(2,3))
func _tick_rage_teleport(delta:float) -> void:
	if rage_remaining <= 0.0:
		_rage_teleport_wait = 0.0
		_rush_left = 0.0
		return
	if not mc_live(): return
	_rage_teleport_wait = maxf(_rage_teleport_wait-delta,0.0)
	if is_player_controlled(): return
	var target:ball = mc_nearest(delta)
	if _rage_teleport_wait > 0.0 or _dodge_grace > 0.0 or _rush_left > 0.0: return
	# 不依赖受击触发，也不经过闪避涨怒/分身入口；没有安全背位时短暂等候再检查。
	_rage_teleport_wait = maxf(rage_teleport_interval,0.3) if _try_rage_backstab(target) else 0.25
func _try_rage_backstab(target:Variant) -> bool:
	if rage_remaining <= 0.0 or not mc_enemy(target): return false
	var behind:Vector2 = target.global_position - _facing(target) * (get_crowd_separation_radius_world() + target.get_crowd_separation_radius_world() + 10.0)
	if not mc_arena_rect().grow(-18.0).has_point(behind) or not mc_body_position_clear(behind): return false
	_rush_direction = behind.direction_to(ball.body_point(target,behind))
	_rush_left = 0.32
	direction = _rush_direction
	_teleport_to(behind)
	return true
func _teleport_to(point:Vector2) -> void:
	mc_play("teleport",-3.0)
	_emit_teleport_particles(global_position)
	global_position = point
	reset_physics_interpolation()
	_emit_teleport_particles(point)
func _emit_teleport_particles(point:Vector2,count:int = 10) -> void:
	MC_FX.portal(self,point,count)
func _stop_stare() -> void:
	if is_instance_valid(_stare_player):
		_stare_player.stop()
		_stare_player.queue_free()
	_stare_player = null
func _update_anger_status() -> void:
	# Rage remains visible through body tint, not extra overhead status text.
	_anger_text = ""
	side_status_remove_permanent("right","mc_anger")
func Die() -> void:
	_stop_stare()
	super.Die()
func _spawn_clones(count:int) -> void:
	if not mc_live(): return
	for i:int in range(_clones.size()-1,-1,-1):
		var unit:Variant = _clones[i].get_ref()
		if not is_instance_valid(unit) or unit.health <= 0: _clones.remove_at(i)
	for i:int in range(mini(count,maxi(max_clones-_clones.size(),0))):
		if get_tree().get_nodes_in_group("MCEndermanClone").size() >= 36: break
		var unit:ball = mc_spawn_creature("res://scenes/creatures/末影分身.tscn",mc_safe_random_position(),0.65)
		if unit != null: _clones.append(weakref(unit))

func mc_ambient_event() -> String: return "scream" if rage_remaining > 0.0 else "ambient"
func mc_ambient_gap() -> Vector2:
	return Vector2(0.5,1.5) if rage_remaining > 0.0 else super.mc_ambient_gap()
