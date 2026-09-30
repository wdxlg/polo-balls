
extends ball

# ========================================================
# 决斗者
#
# 普通移动：
# - 非攻击阶段完全沿用 ball.gd 的通用移动/反弹逻辑。
# - 冷却完成后也不会为了找敌人而改写 direction。
#
# 突刺：
# - 每次攻击冷却完成，只在最近敌人位于 dash_max_distance 内时发动。
# - 发动瞬间锁定敌人的当前位置，不在突刺过程中追踪修正。
# - 落点与敌人保留一小段距离，并在前后/侧向做小幅随机。
# - 抵达落点后才进行一次攻击，然后只把普通移动方向改成突刺反方向。
# - 攻击结束后不再有“特殊后撤速度/距离”，后续移动完全使用角色自身 Speed。
# - 白色低透明度三角形从起点朝锁定的敌人位置拉长、前进并淡出。
# ========================================================

@export_category("突刺攻击")
@export_range(0.0,2000.0,5.0) var dash_max_distance:float = 520.0
@export_range(10.0,3000.0,10.0) var dash_speed:float = 900.0
@export_range(0.0,300.0,1.0) var thrust_target_gap:float = 38.0
@export_range(0.0,100.0,1.0) var thrust_target_gap_random:float = 5.0
@export_range(0.0,100.0,1.0) var thrust_lateral_random:float = 6.0
@export_range(1.0,80.0,1.0) var dash_arrival_distance:float = 8.0
@export_range(10.0,600.0,5.0) var stab_range:float = 62.0
@export var stab_audio:String = "战士attack1"

@export_category("突刺视觉")
@export_range(1.0,120.0,1.0) var thrust_visual_width:float = 10.0
@export_range(0.01,1.0,0.01) var thrust_visual_alpha:float = 0.16
@export_range(0.01,0.5,0.01) var thrust_visual_stretch_time:float = 0.09
@export_range(0.01,0.8,0.01) var thrust_visual_fade_time:float = 0.16
@export_range(0.0,160.0,1.0) var thrust_visual_forward_distance:float = 54.0

@export_category("角色贴图")
@export var normal_texture:Texture2D
@export var stab_texture:Texture2D
# 专用格挡贴图槽位。若未填写，则先用突刺贴图作为可见的临时格挡姿势，
# 这样旧项目不需要额外资源也能立刻看到“格挡时换图”。
@export var block_texture:Texture2D
@export_range(0.05,1.0,0.01) var stab_pose_duration:float = 0.18
@export_range(0.05,0.6,0.01) var block_pose_duration:float = 0.12

@export_category("背后破绽")
@export_range(5.0,80.0,1.0) var weakspot_half_angle_degrees:float = 38.0
@export_range(0.0,150.0,1.0) var weakspot_start_distance:float = 30.0
@export_range(30.0,500.0,5.0) var weakspot_length:float = 180.0
@export var show_weakspot_visual:bool = true
@export var weakspot_fill_color:Color = Color(1.0,0.12,0.12,0.10)
@export var weakspot_line_color:Color = Color(1.0,0.18,0.18,0.72)
@export_range(0.5,8.0,0.25) var weakspot_line_width:float = 2.0
@export var immune_audio:String = "BlockAtk1"
@export_range(0.0,1.0,0.01) var immune_audio_cooldown:float = 0.08

enum DuelistAttackPhase {
	None,
	Thrust,
}

var _attack_phase:DuelistAttackPhase = DuelistAttackPhase.None
var _dash_direction:Vector2 = Vector2.RIGHT
var _dash_target_point:Vector2 = Vector2.ZERO
var _dash_target:ball = null
var _dash_timeout:float = 0.0
var _stab_used:bool = false
var _attack_serial:int = 0
var _pose_serial:int = 0

# 破绽方向是“从角色指向破绽区域”的方向。
# 只在突刺开始时更新，不跟随普通移动/撞墙后的 direction。
var _weakspot_direction:Vector2 = Vector2.LEFT
var _weakspot_fill:Polygon2D = null
var _weakspot_outline:Line2D = null
var _weakspot_hurtbox:hurtbox = null
var _weakspot_collision:CollisionPolygon2D = null

var _last_immune_audio_msec:int = -100000

# 弱点不再依赖“同一 physics frame”的许可。
# Area2D/实体接触可能在物理步里的不同阶段触发，按 physics frame 锁许可会出现
# 看起来打中红色弱点但 take_damage() 时许可已经失效的问题。
# 现在许可只消费一次，并在当前调用链结束后的 deferred 阶段自动过期。
var _weakspot_damage_uses:int = 0
var _weakspot_damage_token:int = 0
var _weakspot_accepted_hitboxes:Dictionary = {}


func _ready() -> void:
	super._ready()
	_set_character_texture(normal_texture)
	_create_weakspot_visual()
	_create_weakspot_hurtbox()
	_set_weakspot_direction(Vector2.LEFT)


# 只有敌人在突刺范围内，冷却完成后才进入 Attack。
# 不在范围内时完全不接管普通移动方向。
func get_next_state(state:State) -> int:
	if not is_multiplayer_authority():
		return -1

	if health <= 0 and Type != Ball_Type.Creature:
		if state != State.Die:
			return State.Die
		return -1

	if dizziness:
		return -1

	# V129：直接控制时统一交回 ball 的“只响应玩家鼠标、不自动起手”状态逻辑。
	# 本角色仍可在玩家点击后执行自己的 Attack()/Skill()，这里只阻止自定义 AI 冷却分支抢先出招。
	if is_player_controlled():
		return super.get_next_state(state)

	# 自定义刺击状态机同样必须服从统一开战闸门。
	if not is_combat_runtime_active():
		return super.get_next_state(state)

	if Using_Skill and state != State.Skill:
		return State.Skill

	if Can_Skill:
		if not Using_Skill and state_machine.last_state_dis.Skill >= Skill_Cooling:
			return State.Skill
	else:
		state_machine.last_state_dis.Skill = 0

	if Attacking and state != State.Attack:
		return State.Attack

	if (
		Can_Attack
		and not Attacking
		and state_machine.last_state_dis.Attack >= Attack_Cooling
		and _can_start_thrust()
	):
		return State.Attack

	match state:
		State.Move:
			if Speed <= 0:
				return State.Stand
		State.Stand:
			if Speed > 0:
				return State.Move
		State.Attack:
			if not Attacking:
				return State.Stand
		State.Hurt:
			if hurting_timer.is_stopped():
				return State.Stand
		State.Skill:
			if not Using_Skill:
				return State.Stand

	return -1


func _can_start_thrust() -> bool:
	var target := _return_nearest_enemy()
	if target == null:
		return false
	return global_position.distance_to(target.global_position) <= dash_max_distance


func _return_nearest_enemy() -> ball:
	if not is_instance_valid(Nearest_Enemy):
		return null
	if not Nearest_Enemy is ball:
		return null

	var target:ball = Nearest_Enemy as ball
	if target.health <= 0:
		return null
	if target.state_machine and target.state_machine.current_state == State.Die:
		return null
	return target


func Attack() -> void:
	super()

	var target := _return_nearest_enemy()
	if target == null and not has_player_control_aim():
		Attacking = false
		return

	var start:Vector2 = global_position
	var locked_enemy_position:Vector2 = player_control_aim_world_position(start + direction * dash_max_distance) if has_player_control_aim() else combat_target_position(target)
	var to_target:Vector2 = locked_enemy_position - start
	var target_distance:float = to_target.length()
	if not has_player_control_aim() and target_distance > dash_max_distance:
		Attacking = false
		return
	if has_player_control_aim() and target_distance > dash_max_distance:
		locked_enemy_position = start + to_target.normalized() * dash_max_distance
		to_target = locked_enemy_position - start
		target_distance = to_target.length()

	Attacking = true
	_attack_phase = DuelistAttackPhase.Thrust
	_dash_target = target
	_stab_used = false
	_attack_serial += 1
	_reset_after_image_sampling()

	# 新的通用 Unique_Attack_Audio 会在进入 Attack 状态时自动播放。
	# 老场景若还没填写该槽位，则继续兼容原来的 Sfx 名称。
	if Unique_Attack_Audio == null and stab_audio != "":
		Audios.play_sfx.rpc(stab_audio,{},true)

	if to_target.length_squared() > 0.000001:
		_dash_direction = to_target.normalized()
	elif direction.length_squared() > 0.000001:
		_dash_direction = direction.normalized()
	else:
		_dash_direction = Vector2.RIGHT

	# 目标距离不是“冲到敌人中心”，而是在敌人前方留一点空隙。
	# 每次攻击只随机一次，因此途中不会抖动或重新选落点。
	var wanted_gap:float = maxf(
		0.0,
		thrust_target_gap + randf_range(-thrust_target_gap_random,thrust_target_gap_random)
	)
	var forward_distance:float = maxf(target_distance - wanted_gap,0.0)
	var side:Vector2 = Vector2(-_dash_direction.y,_dash_direction.x)
	var lateral_limit:float = minf(
		maxf(thrust_lateral_random,0.0),
		forward_distance * 0.18
	)
	var lateral_offset:float = randf_range(-lateral_limit,lateral_limit)

	_dash_target_point = start + _dash_direction * forward_distance + side * lateral_offset
	var travel_distance:float = start.distance_to(_dash_target_point)
	_dash_timeout = maxf(travel_distance / maxf(dash_speed,1.0) + 0.35,0.25)

	direction = _dash_direction
	_set_weakspot_direction(-_dash_direction)
	_broadcast_thrust_visual(start,locked_enemy_position)

	if travel_distance <= dash_arrival_distance:
		_complete_thrust()


func tick_physics(state:State,delta:float) -> void:
	if _attack_phase == DuelistAttackPhase.Thrust:
		if dizziness:
			_finish_attack()
			super.tick_physics(state,delta)
			return

		var to_point:Vector2 = _dash_target_point - global_position
		var remaining:float = to_point.length()
		if remaining <= dash_arrival_distance:
			_complete_thrust()
			Repel = Vector2.ZERO
			return

		direction = to_point / remaining
		var safe_delta:float = maxf(delta,0.000001)
		var current_speed:float = minf(dash_speed,remaining / safe_delta)
		move(current_speed,delta)
		# 突刺阶段没有走 super.tick_physics()，因此这里显式更新通用残影。
		# 决斗者场景把 AfterImage_Speed 设在普通 Speed 与 dash_speed 之间，
		# 所以只有突刺会产生残影，正常移动不会。
		_process_auto_after_image(delta)
		_dash_timeout -= delta

		if _attack_phase == DuelistAttackPhase.Thrust:
			if global_position.distance_to(_dash_target_point) <= dash_arrival_distance or _dash_timeout <= 0.0:
				_complete_thrust()

		Repel = Vector2.ZERO
		return

	# 非攻击阶段完全复用所有其他角色的移动逻辑。
	super.tick_physics(state,delta)



# 决斗者只允许在真正的突刺阶段生成通用残影。
# ball.gd 会在普通移动、击退、碰撞修正等阶段自动调用 _process_auto_after_image()；
# 单纯依靠 AfterImage_Speed 阈值会让瞬时高速位移偶尔冒出一张残影。
# 这里把“是否允许生成残影”绑定到攻击阶段，而不是绑定到速度。
func _process_auto_after_image(delta:float) -> void:
	if _attack_phase != DuelistAttackPhase.Thrust:
		_reset_after_image_sampling()
		_clear_after_image_path()
		_after_image_stretch_intensity = 0.0
		if _after_image_stretch_sprite != null and is_instance_valid(_after_image_stretch_sprite):
			_after_image_stretch_sprite.visible = false
		if _after_image_path_mesh != null and is_instance_valid(_after_image_path_mesh):
			_after_image_path_mesh.visible = false
		return
	super._process_auto_after_image(delta)

func _complete_thrust() -> void:
	if _attack_phase != DuelistAttackPhase.Thrust:
		return

	if is_instance_valid(_dash_target):
		if global_position.distance_to(_dash_target.global_position) <= stab_range:
			_perform_stab(_dash_target)

	# 攻击后的“后撤”不是第二段特殊移动。
	# 只把正常移动方向改成突刺反方向，然后立刻退出 Attack；
	# 下一物理帧开始完全由 ball.gd 按角色自身 Speed 正常移动。
	direction = -_dash_direction
	_finish_attack()


func _finish_attack() -> void:
	_attack_phase = DuelistAttackPhase.None
	Attacking = false
	_dash_target = null
	_dash_timeout = 0.0
	_stab_used = false
	_reset_after_image_sampling()


# 特殊移动仍然走 ball.gd 的 move()/move_and_slide()。
# 突刺撞到目标时立刻刺击并后撤；撞到其它实体或墙时也结束突刺，避免持续顶墙。
func when_collide(speed:float,collision:KinematicCollision2D) -> void:
	var phase_before:DuelistAttackPhase = _attack_phase
	var collider = collision.get_collider() if collision != null else null

	# 有些人物攻击仍以 CharacterBody2D 实体接触为主，Area2D 未必会在
	# 同一帧真正进入重叠。只要攻击者/碰撞伤害角色撞到决斗者身体，
	# 且来源不在背后破绽方向，就补一次格挡声；80ms 冷却会与
	# can_receive_hit_from() 的 Area2D 路径自动去重。
	if collider is ball and collider != self:
		var body_attacker:ball = collider as ball
		if (body_attacker.Attacking or body_attacker.Using_Skill or body_attacker.has_collision_damage()):
			if not _position_is_in_weakspot(body_attacker.global_position):
				_play_immune_sound()

	if phase_before == DuelistAttackPhase.Thrust and not _stab_used:
		if is_player_controlled() and collider is ball and collider != self:
			var manual_hit:ball = collider as ball
			if _is_control_attack_enemy(manual_hit):
				_perform_stab(manual_hit)
		elif is_instance_valid(_dash_target) and collider == _dash_target:
			_perform_stab(_dash_target)

	super.when_collide(speed,collision)

	if phase_before == DuelistAttackPhase.Thrust and _attack_phase == DuelistAttackPhase.Thrust:
		direction = -_dash_direction
		_finish_attack()


func _is_control_attack_enemy(target:ball) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(self,target): return false # 皓宸复制品及其产物不把己方选为目标
	if target == null or not is_instance_valid(target) or target == self or target.health <= 0:
		return false
	if not Team.is_empty() and target.Team == Team:
		return false
	if target.has_method("is_combat_targetable") and not bool(target.call("is_combat_targetable")):
		return false
	return true


func _perform_stab(target:ball) -> void:
	if _stab_used or target == null or not is_instance_valid(target):
		return
	if target.self_hurtbox == null or self_hitbox == null:
		return

	_stab_used = true
	_play_stab_pose()

	# 命中音效由 ball.gd 的 Unique_Hit_Audio / Hit_Audio 统一处理，
	# 这样“出招声”和“打中声”不会重叠成同一个声音。
	# 告诉通用受击爆射线系统：这是细窄的刺击，而不是人物整个身体宽度的范围攻击。
	# try_hit_hurtbox() 的信号是同步结算，因此命中结束后即可移除临时标记。
	self_hitbox.set_meta("hit_effect_coverage_width",10.0)
	# 走统一 Hitbox 入口，因此目标若也是决斗者，仍会检查其背后破绽。
	self_hitbox.try_hit_hurtbox(target.self_hurtbox)
	self_hitbox.remove_meta("hit_effect_coverage_width")


func _play_stab_pose() -> void:
	_pose_serial += 1
	var pose_token:int = _pose_serial
	_set_character_texture(stab_texture)
	await get_tree().create_timer(maxf(stab_pose_duration,0.05)).timeout
	if not is_instance_valid(self):
		return
	if pose_token == _pose_serial:
		_set_character_texture(normal_texture)


func _play_block_pose() -> void:
	_pose_serial += 1
	var pose_token:int = _pose_serial
	var guard_texture:Texture2D = block_texture if block_texture != null else stab_texture
	_set_character_texture(guard_texture)
	await get_tree().create_timer(maxf(block_pose_duration,0.05)).timeout
	if not is_instance_valid(self):
		return
	if pose_token == _pose_serial:
		_set_character_texture(normal_texture)


func _set_character_texture(texture:Texture2D) -> void:
	if image is Sprite2D and texture != null:
		(image as Sprite2D).texture = texture


func _broadcast_thrust_visual(start:Vector2,end:Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		_show_thrust_visual.rpc(start,end)
	else:
		_show_thrust_visual(start,end)


@rpc("authority","call_local","reliable")
func _show_thrust_visual(start:Vector2,end:Vector2) -> void:
	var vector:Vector2 = end - start
	var length:float = vector.length()
	if length <= 0.001:
		return

	var parent:Node = get_tree().current_scene
	if parent == null:
		return

	var triangle := Polygon2D.new()
	triangle.name = "DuelistThrustVisual"
	triangle.polygon = PackedVector2Array([
		Vector2(0.0,-thrust_visual_width * 0.5),
		Vector2(0.0, thrust_visual_width * 0.5),
		Vector2(length,0.0),
	])
	triangle.color = Color(1.0,1.0,1.0,clampf(thrust_visual_alpha,0.0,1.0))
	triangle.z_index = 35
	parent.add_child(triangle)
	triangle.global_position = start
	triangle.rotation = vector.angle()
	triangle.scale = Vector2(0.04,1.0)

	var tween := triangle.create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(
		triangle,
		"scale",
		Vector2.ONE,
		maxf(thrust_visual_stretch_time,0.01)
	)

	var forward:Vector2 = vector.normalized() * minf(
		maxf(thrust_visual_forward_distance,0.0),
		length * 0.25
	)
	tween.set_parallel(true)
	tween.tween_property(
		triangle,
		"global_position",
		start + forward,
		maxf(thrust_visual_fade_time,0.01)
	)
	tween.tween_property(
		triangle,
		"modulate",
		Color(1.0,1.0,1.0,0.0),
		maxf(thrust_visual_fade_time,0.01)
	)
	tween.set_parallel(false)
	tween.tween_callback(Callable(triangle,"queue_free"))


# ========================================================
# 背后破绽
# ========================================================

func _direction_is_in_weakspot(source_side_direction:Vector2) -> bool:
	if source_side_direction.length_squared() <= 0.000001:
		return false

	var weak_dir:Vector2 = _weakspot_direction
	if weak_dir.length_squared() <= 0.000001:
		weak_dir = Vector2.LEFT

	var threshold:float = cos(deg_to_rad(weakspot_half_angle_degrees))
	return source_side_direction.normalized().dot(weak_dir.normalized()) >= threshold


func _position_is_in_weakspot(source_position:Vector2) -> bool:
	return _direction_is_in_weakspot(source_position - global_position)


# Area2D 的进入事件只表示碰撞区域已经重叠。高速投射物可能在一个物理步里
# 从人物正面穿到背后，所以“触发时当前在哪边”不能单独作为弱点判定。
# 对真正移动中的攻击，优先用本帧实际运动的反方向判断它是从哪一侧飞来的；
# 对静止近战/贴身攻击，再使用 Hitbox/攻击者当前所在的位置。
func _incoming_hit_is_in_weakspot(incoming_hit:hitbox) -> bool:
	if incoming_hit == null or not is_instance_valid(incoming_hit):
		return false

	var source_node:Node2D = incoming_hit.get_parent() as Node2D
	if source_node == null and incoming_hit.owner is Node2D:
		source_node = incoming_hit.owner as Node2D

	var source_ball:ball = source_node as ball
	if source_ball == null and incoming_hit.owner is ball:
		source_ball = incoming_hit.owner as ball

	if source_ball != null and is_instance_valid(source_ball):
		var travel:Vector2 = source_ball.get_position_delta()
		if travel.length_squared() <= 0.000001 and source_ball.velocity.length_squared() > 0.000001:
			travel = source_ball.velocity

		if travel.length_squared() > 0.000001:
			# 物体往右飞，说明它来自左边；因此“来源侧”就是 -travel。
			# 直接用来向比反推上一帧中心点更稳定，也不会把已经穿过人物的高速弹误判成背刺。
			return _direction_is_in_weakspot(-travel)

	# 静止/近战攻击没有可靠的运动向量，使用真实 Hitbox 所在侧。
	if _position_is_in_weakspot(incoming_hit.global_position):
		return true
	if source_node != null and _position_is_in_weakspot(source_node.global_position):
		return true

	return false


# 真正的红色弱点现在同时拥有一个独立 Hurtbox。
# 对“真的撞到弱点区域”的攻击直接放行；对于 CharacterBody2D 实体碰撞兜底，
# 仍保留方向判断，这样从背后贴身冲撞也能正确命中。
func can_receive_hit_contact(incoming_hit:hitbox,contact_hurtbox:hurtbox) -> bool:
	# 核心规则：普通 Hitbox 必须“真实碰到”独立的 BackWeakspotHurtbox。
	# 不再根据攻击者方向/位置猜测弱点命中，否则会出现“在红区外但从背后来的攻击也能伤害”。
	if contact_hurtbox != null and contact_hurtbox == _weakspot_hurtbox:
		_grant_weakspot_damage_once(incoming_hit)
		return true

	_clear_weakspot_damage_permission()
	_play_immune_sound()
	return false


# 兼容旧版 hitbox.gd；新项目会优先调用上面的 hurtbox-aware 钩子。
func can_receive_hit_from(incoming_hit:hitbox) -> bool:
	# 旧接口没有“碰到的是哪个 Hurtbox”信息，因此不能证明命中了破绽。
	# 严格规则下统一拒绝，避免用方向猜测。
	_clear_weakspot_damage_permission()
	_play_immune_sound()
	return false


# 身体 Hurtbox 可能会比背后的独立弱点更早报告重叠。
# hitbox.gd 默认按“目标角色”做 80ms 去重，所以必须允许真正的弱点 Hurtbox
# 绕过这一次身体记录，否则就会出现红色区域明明被打到却仍然被前面的身体格挡吞掉。
func should_bypass_duplicate_hit_guard(incoming_hit:hitbox,contact_hurtbox:hurtbox) -> bool:
	if contact_hurtbox == null or contact_hurtbox != _weakspot_hurtbox:
		return false
	return not _weakspot_hitbox_was_already_accepted(incoming_hit)


func _weakspot_hitbox_was_already_accepted(incoming_hit:hitbox) -> bool:
	if incoming_hit == null or not is_instance_valid(incoming_hit):
		return false
	var hit_id:int = int(incoming_hit.get_instance_id())
	var until_msec:int = int(_weakspot_accepted_hitboxes.get(hit_id,0))
	if until_msec <= Time.get_ticks_msec():
		_weakspot_accepted_hitboxes.erase(hit_id)
		return false
	return true


func _grant_weakspot_damage_once(incoming_hit:hitbox) -> void:
	if incoming_hit != null and is_instance_valid(incoming_hit):
		var hit_id:int = int(incoming_hit.get_instance_id())
		_weakspot_accepted_hitboxes[hit_id] = Time.get_ticks_msec() + 180
		if _weakspot_accepted_hitboxes.size() > 64:
			_cleanup_accepted_weakspot_hitboxes()

	_weakspot_damage_token += 1
	var token:int = _weakspot_damage_token
	_weakspot_damage_uses = 1
	call_deferred("_expire_weakspot_damage_permission",token)


func _cleanup_accepted_weakspot_hitboxes() -> void:
	var now_msec:int = Time.get_ticks_msec()
	var expired:Array[int] = []
	for raw_id in _weakspot_accepted_hitboxes:
		var hit_id:int = int(raw_id)
		if int(_weakspot_accepted_hitboxes[raw_id]) <= now_msec:
			expired.append(hit_id)
	for hit_id in expired:
		_weakspot_accepted_hitboxes.erase(hit_id)


func _expire_weakspot_damage_permission(token:int) -> void:
	if token != _weakspot_damage_token:
		return
	_weakspot_damage_uses = 0


func _clear_weakspot_damage_permission() -> void:
	_weakspot_damage_token += 1
	_weakspot_damage_uses = 0


# 返回破绽真实碰撞多边形的世界坐标版本。
func _weakspot_world_polygon() -> PackedVector2Array:
	var result := PackedVector2Array()
	if _weakspot_collision == null or not is_instance_valid(_weakspot_collision):
		return result
	if _weakspot_collision.disabled:
		return result
	var polygon:PackedVector2Array = _weakspot_collision.polygon
	for local_point:Vector2 in polygon:
		result.append(_weakspot_collision.to_global(local_point))
	return result


# 判断一个“真实世界命中点”是否落在当前破绽碰撞多边形里。
func is_world_point_in_weakspot(world_point:Vector2) -> bool:
	var polygon:PackedVector2Array = _weakspot_world_polygon()
	if polygon.size() < 3:
		return false
	return Geometry2D.is_point_in_polygon(world_point,polygon)


# 非穿透式近战/实体接触不能拿“整个攻击体积是否曾覆盖破绽”来判定。
# 否则一根从正面刺进来的长胶囊会穿过整个人物，最后和背后的弱点相交，
# 造成“从正面打也永远能伤害决斗者”的假阳性。
# 这里改为求攻击来源这一侧与主体 Hurtbox 的第一接触表面点，再只判断这个点。
func _body_surface_contact_point_from_source(source_position:Vector2) -> Vector2:
	var shape_node:CollisionShape2D = null
	if self_hurtbox != null and is_instance_valid(self_hurtbox):
		shape_node = self_hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or shape_node.shape == null:
		var fallback_dir:Vector2 = source_position - global_position
		if fallback_dir.length_squared() <= 0.000001:
			fallback_dir = -_weakspot_direction
		return global_position + fallback_dir.normalized() * 1.0

	var local_source:Vector2 = shape_node.to_local(source_position)
	if local_source.length_squared() <= 0.000001:
		# 来源中心恰好与人物中心重合时没有唯一接触侧。
		# 这种情况不能凭空猜成破绽命中，使用弱点反方向作为保守的非破绽兜底。
		local_source = shape_node.to_local(global_position - _weakspot_direction * 8.0)

	var local_dir:Vector2 = local_source.normalized()
	var shape_value:Shape2D = shape_node.shape
	var local_surface:Vector2 = Vector2.ZERO

	if shape_value is RectangleShape2D:
		var half:Vector2 = (shape_value as RectangleShape2D).size * 0.5
		var tx:float = INF if absf(local_dir.x) <= 0.000001 else half.x / absf(local_dir.x)
		var ty:float = INF if absf(local_dir.y) <= 0.000001 else half.y / absf(local_dir.y)
		local_surface = local_dir * minf(tx,ty)
	elif shape_value is CircleShape2D:
		local_surface = local_dir * (shape_value as CircleShape2D).radius
	elif shape_value is CapsuleShape2D:
		# 决斗者当前场景使用 RectangleShape2D；这里仍给 Capsule 一个保守支持。
		# 用其外接矩形求来源侧表面，至少不会把正面攻击穿透到背面弱点。
		var capsule:CapsuleShape2D = shape_value as CapsuleShape2D
		var capsule_half:Vector2 = Vector2(capsule.radius,capsule.height * 0.5)
		var ctx:float = INF if absf(local_dir.x) <= 0.000001 else capsule_half.x / absf(local_dir.x)
		var cty:float = INF if absf(local_dir.y) <= 0.000001 else capsule_half.y / absf(local_dir.y)
		local_surface = local_dir * minf(ctx,cty)
	else:
		# 未知 Shape2D 不允许把整段攻击直接穿透到背面；退化到离中心很近的来源侧点。
		local_surface = local_dir

	return shape_node.to_global(local_surface)


func _surface_contact_hits_weakspot(source_position:Vector2) -> bool:
	var contact_point:Vector2 = _body_surface_contact_point_from_source(source_position)
	return is_world_point_in_weakspot(contact_point)


func _circle_hits_weakspot(center:Vector2,radius:float) -> bool:
	var polygon:PackedVector2Array = _weakspot_world_polygon()
	if polygon.size() < 3:
		return false
	var safe_radius:float = maxf(radius,0.0)
	if Geometry2D.is_point_in_polygon(center,polygon):
		return true
	for point:Vector2 in polygon:
		if point.distance_squared_to(center) <= safe_radius * safe_radius:
			return true
	for index:int in range(polygon.size()):
		var a:Vector2 = polygon[index]
		var b:Vector2 = polygon[(index + 1) % polygon.size()]
		var nearest:Vector2 = Geometry2D.get_closest_point_to_segment(center,a,b)
		if nearest.distance_squared_to(center) <= safe_radius * safe_radius:
			return true
	return false


func _segment_hits_weakspot(from_point:Vector2,to_point:Vector2,half_width:float = 0.0) -> bool:
	var polygon:PackedVector2Array = _weakspot_world_polygon()
	if polygon.size() < 3:
		return false
	var width:float = maxf(half_width,0.0)
	if from_point.distance_squared_to(to_point) <= 0.000001:
		return _circle_hits_weakspot(from_point,width)

	if width > 0.001:
		var thick_polygons:Array[PackedVector2Array] = Geometry2D.offset_polyline(
			PackedVector2Array([from_point,to_point]),
			width,
			Geometry2D.JOIN_ROUND,
			Geometry2D.END_ROUND
		)
		for thick_polygon:PackedVector2Array in thick_polygons:
			if not Geometry2D.intersect_polygons(polygon,thick_polygon).is_empty():
				return true
			# 只有边界相切时布尔多边形可能没有面积，再补点/边界检查。
			for point:Vector2 in thick_polygon:
				if Geometry2D.is_point_in_polygon(point,polygon):
					return true

	if Geometry2D.is_point_in_polygon(from_point,polygon) or Geometry2D.is_point_in_polygon(to_point,polygon):
		return true
	for index:int in range(polygon.size()):
		var a:Vector2 = polygon[index]
		var b:Vector2 = polygon[(index + 1) % polygon.size()]
		if Geometry2D.segment_intersects_segment(from_point,to_point,a,b) != null:
			return true
	return false


func _point_is_in_sector(
	point:Vector2,
	origin:Vector2,
	forward:Vector2,
	radius:float,
	half_angle_degrees:float
) -> bool:
	var offset:Vector2 = point - origin
	var distance:float = offset.length()
	if distance > maxf(radius,0.0) + 0.001:
		return false
	if distance <= 0.001:
		return true
	var dir:Vector2 = forward.normalized() if forward.length_squared() > 0.000001 else Vector2.RIGHT
	var threshold:float = cos(deg_to_rad(clampf(half_angle_degrees,0.0,180.0)))
	return offset.normalized().dot(dir) >= threshold


func _sector_hits_weakspot(
	origin:Vector2,
	forward:Vector2,
	radius:float,
	half_angle_degrees:float
) -> bool:
	var polygon:PackedVector2Array = _weakspot_world_polygon()
	if polygon.size() < 3:
		return false
	if Geometry2D.is_point_in_polygon(origin,polygon):
		return true
	for point:Vector2 in polygon:
		if _point_is_in_sector(point,origin,forward,radius,half_angle_degrees):
			return true

	# 检查破绽边缘上离扇形原点最近的点，覆盖“扇形穿过多边形但顶点都在外面”的情况。
	for index:int in range(polygon.size()):
		var a:Vector2 = polygon[index]
		var b:Vector2 = polygon[(index + 1) % polygon.size()]
		var nearest:Vector2 = Geometry2D.get_closest_point_to_segment(origin,a,b)
		if _point_is_in_sector(nearest,origin,forward,radius,half_angle_degrees):
			return true
	return false


# 特殊伤害统一提交“伤害覆盖几何”，而不是攻击者中心点。
# 支持 point / circle / segment(capsule) / sector / all。
# 这样拳头、钢叉、棋子、爆炸、范围波等只要它们真实覆盖破绽，就一定能造成伤害；
# 只覆盖身体其它位置则完全免疫。
func _damage_space_hits_weakspot(damage_space:Variant) -> bool:
	if damage_space is Vector2:
		return is_world_point_in_weakspot(damage_space as Vector2)
	if not damage_space is Dictionary:
		return false

	var context:Dictionary = damage_space as Dictionary

	# 物理接触/非穿透近战必须按“先碰到人物哪一侧”结算。
	# 这一步要早于 circle/capsule 的整形状相交测试，否则长武器会隔着身体碰到背面破绽。
	if bool(context.get("blocked_by_body",false)):
		var contact_source:Vector2 = context.get("source_position",context.get("origin",context.get("center",global_position))) as Vector2
		return _surface_contact_hits_weakspot(contact_source)

	var shape:String = str(context.get("shape","point")).to_lower()
	match shape:
		"contact", "surface_contact", "melee_contact", "non_penetrating":
			var source_position:Vector2 = context.get("source_position",context.get("origin",context.get("center",global_position))) as Vector2
			return _surface_contact_hits_weakspot(source_position)
		"all", "global", "target":
			return true
		"circle":
			var center:Vector2 = context.get("center",context.get("point",global_position)) as Vector2
			var radius:float = float(context.get("radius",0.0))
			return _circle_hits_weakspot(center,radius)
		"segment", "capsule", "corridor":
			var from_point:Vector2 = context.get("from",context.get("start",global_position)) as Vector2
			var to_point:Vector2 = context.get("to",context.get("end",from_point)) as Vector2
			var half_width:float = float(context.get("half_width",context.get("radius",0.0)))
			return _segment_hits_weakspot(from_point,to_point,half_width)
		"sector", "cone":
			var origin:Vector2 = context.get("origin",context.get("center",global_position)) as Vector2
			var forward:Vector2 = context.get("direction",Vector2.RIGHT) as Vector2
			var sector_radius:float = float(context.get("radius",0.0))
			var half_angle:float = float(context.get("half_angle_degrees",context.get("half_angle",0.0)))
			return _sector_hits_weakspot(origin,forward,sector_radius,half_angle)
		_:
			if context.has("point") and context["point"] is Vector2:
				return is_world_point_in_weakspot(context["point"] as Vector2)
	return false


func _apply_confirmed_weakspot_damage(
	damage:float,
	ignore_block:bool,
	raw_health:bool = false
) -> bool:
	if damage <= 0.0:
		return false
	var before_health:float = float(health)
	var before_block:float = float(block)
	if raw_health:
		hit_white_visual_only()
		# 与 ball 的原始伤害入口一致：绕过护甲/抗性，但不绕过药水伤害吸收。
		var raw_amount:int = maxi(int(round(damage)),0)
		health -= maxi(int(round(_consume_minecraft_absorption(float(raw_amount)))),0)
	else:
		hit_white(ignore_block)
		super.take_damage(damage,ignore_block)
	return float(health) < before_health or float(block) < before_block


func receive_spatial_damage(
	damage:float,
	damage_space:Variant,
	ignore_block:bool = false,
	raw_health:bool = false
) -> bool:
	if damage <= 0.0:
		return false
	# 自定义破绽判定仍需保留基类的溺水免疫；不豁免普通水伤害。
	if damage_space is Dictionary and str((damage_space as Dictionary).get("element","")) == "drowning":
		if has_minecraft_status("water_breathing") or has_minecraft_status("conduit_power"):
			return false
	if not _damage_space_hits_weakspot(damage_space):
		_clear_weakspot_damage_permission()
		_play_immune_sound()
		return false
	return _apply_confirmed_weakspot_damage(damage,ignore_block,raw_health)


# 兼容旧的“单点命中”调用；新特殊攻击尽量改用 receive_spatial_damage() 传真实形状。
func receive_positional_damage(
	damage:float,
	impact_position:Vector2,
	ignore_block:bool = false,
	source:Node = null
) -> bool:
	return receive_spatial_damage(
		damage,
		{"shape":"point","point":impact_position,"source":source},
		ignore_block,
		false
	)


# 决斗者的核心防御规则：没有经过弱点 Hurtbox/弱点方向放行的伤害全部免疫。
# 放行后的正常 hitbox.on_hit -> take_damage() 是同步调用，因此一次许可会在这里
# 立刻被消费；deferred 过期只是防止零伤害/取消命中时许可残留。
func take_damage(damage:float,ignore_block:bool = false) -> void:
	if damage <= 0.0:
		return

	if _weakspot_damage_uses <= 0:
		_play_immune_sound()
		return

	_weakspot_damage_uses -= 1
	if _weakspot_damage_uses <= 0:
		_weakspot_damage_token += 1

	super.take_damage(damage,ignore_block)


func _play_immune_sound() -> void:
	# 非破绽命中仍然给“确实打中了但被免疫”的闪白反馈，且不进入 Hurt。
	hit_white_visual_only()
	# 格挡视觉不受音效冷却限制；连续挡住多颗子弹时会持续保持格挡姿势。
	_play_block_pose()
	var has_unique_guard:bool = Unique_Block_Audio != null
	if not has_unique_guard and immune_audio == "":
		return

	var now_msec:int = Time.get_ticks_msec()
	var cooldown_msec:int = int(round(maxf(immune_audio_cooldown,0.0) * 1000.0))
	if now_msec - _last_immune_audio_msec < cooldown_msec:
		return

	_last_immune_audio_msec = now_msec
	# 攻击确实碰到决斗者，但没有从背后破绽方向进入时，也给明确的
	# “被格挡/擦开”反馈。人物若填写了独特格挡音频则优先使用。
	if has_unique_guard:
		play_unique_audio(Character_Audio_Slot.Block,true)
	else:
		Audios.play_sfx.rpc(immune_audio,{},true)


func _set_weakspot_direction(new_direction:Vector2) -> void:
	if new_direction.length_squared() <= 0.000001:
		return
	_weakspot_direction = new_direction.normalized()
	_update_weakspot_visual()


func _create_weakspot_visual() -> void:
	if _weakspot_fill != null:
		return

	var image_z:int = image.z_index if image != null and is_instance_valid(image) else 0

	_weakspot_fill = Polygon2D.new()
	_weakspot_fill.name = "BackWeakspotArea"
	_weakspot_fill.color = weakspot_fill_color
	# 破绽提示必须压在人物图片下面，而不是盖住人物。
	_weakspot_fill.z_index = image_z - 2
	_weakspot_fill.visible = show_weakspot_visual
	add_child(_weakspot_fill)

	_weakspot_outline = Line2D.new()
	_weakspot_outline.name = "BackWeakspotOutline"
	_weakspot_outline.default_color = weakspot_line_color
	_weakspot_outline.width = weakspot_line_width
	_weakspot_outline.z_index = image_z - 1
	_weakspot_outline.visible = show_weakspot_visual
	add_child(_weakspot_outline)


func _create_weakspot_hurtbox() -> void:
	if _weakspot_hurtbox != null and is_instance_valid(_weakspot_hurtbox):
		return

	var area := hurtbox.new()
	area.name = "BackWeakspotHurtbox"
	area.collision_layer = 0
	area.collision_mask = 0
	area.set_collision_layer_value(2,true)
	area.monitoring = false
	area.monitorable = true
	add_child(area)

	var collision := CollisionPolygon2D.new()
	collision.name = "CollisionPolygon2D"
	area.add_child(collision)

	_weakspot_hurtbox = area
	_weakspot_collision = collision


func _weakspot_visual_polygon_points() -> PackedVector2Array:
	var back:Vector2 = _weakspot_direction.normalized()
	if back.length_squared() <= 0.000001:
		back = Vector2.LEFT
	var side:Vector2 = Vector2(-back.y,back.x)
	var start:Vector2 = back * weakspot_start_distance
	var far_center:Vector2 = back * weakspot_length
	var far_half_width:float = tan(deg_to_rad(weakspot_half_angle_degrees)) * weakspot_length
	var far_a:Vector2 = far_center + side * far_half_width
	var far_b:Vector2 = far_center - side * far_half_width
	return PackedVector2Array([start,far_a,far_b])


func _weakspot_body_reach(back:Vector2) -> float:
	var shape_node:CollisionShape2D = null
	if self_hurtbox != null and is_instance_valid(self_hurtbox):
		shape_node = self_hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or shape_node.shape == null:
		return maxf(weakspot_start_distance + 36.0,72.0)

	var local_scale:Vector2 = shape_node.scale.abs()
	var shape_value:Shape2D = shape_node.shape
	if shape_value is RectangleShape2D:
		var half:Vector2 = (shape_value as RectangleShape2D).size * local_scale * 0.5
		return absf(back.x) * half.x + absf(back.y) * half.y
	if shape_value is CircleShape2D:
		return (shape_value as CircleShape2D).radius * maxf(local_scale.x,local_scale.y)
	if shape_value is CapsuleShape2D:
		var capsule:CapsuleShape2D = shape_value as CapsuleShape2D
		return maxf(capsule.height * local_scale.y * 0.5,capsule.radius * local_scale.x)
	return maxf(weakspot_start_distance + 36.0,72.0)


func _weakspot_collision_polygon_points() -> PackedVector2Array:
	var back:Vector2 = _weakspot_direction.normalized()
	if back.length_squared() <= 0.000001:
		back = Vector2.LEFT
	var side:Vector2 = Vector2(-back.y,back.x)

	# 真正可受伤的弱点只覆盖人物背侧身体附近，不把整条 180px 的红色指示锥
	# 都变成“远距离就能打中”的巨大 Hurtbox。
	var body_reach:float = _weakspot_body_reach(back)
	var contact_end:float = clampf(body_reach + 6.0,weakspot_start_distance + 12.0,weakspot_length)
	var start:Vector2 = back * weakspot_start_distance
	var far_center:Vector2 = back * contact_end
	var far_half_width:float = tan(deg_to_rad(weakspot_half_angle_degrees)) * contact_end
	var far_a:Vector2 = far_center + side * far_half_width
	var far_b:Vector2 = far_center - side * far_half_width
	return PackedVector2Array([start,far_a,far_b])


func _update_weakspot_visual() -> void:
	var polygon:PackedVector2Array = _weakspot_visual_polygon_points()
	if polygon.size() < 3:
		return

	var start:Vector2 = polygon[0]
	var far_a:Vector2 = polygon[1]
	var far_b:Vector2 = polygon[2]

	if _weakspot_fill != null and is_instance_valid(_weakspot_fill):
		_weakspot_fill.polygon = polygon
		_weakspot_fill.color = weakspot_fill_color
		_weakspot_fill.visible = show_weakspot_visual

	if _weakspot_collision != null and is_instance_valid(_weakspot_collision):
		_weakspot_collision.polygon = _weakspot_collision_polygon_points()
		_weakspot_collision.disabled = false

	if _weakspot_outline != null and is_instance_valid(_weakspot_outline):
		_weakspot_outline.points = PackedVector2Array([
			far_a,
			start,
			far_b,
		])
		_weakspot_outline.default_color = weakspot_line_color
		_weakspot_outline.width = weakspot_line_width
		_weakspot_outline.visible = show_weakspot_visual


func Die() -> void:
	super()
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(self):
		Game.free_node(self)


# 通用敌人有效性判断。
# 供威胁抽象接口复用，不依赖极速者。
func _is_valid_enemy(target:ball) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(self,target): return false # 皓宸复制品及其产物不把己方选为目标
	if target == null or not is_instance_valid(target) or target == self:
		return false
	if not target.is_combat_targetable():
		return false
	if Team != "" and target.Team == Team:
		return false
	return true


# AI 通用威胁接口：突刺阶段概括为当前点到锁定落点的胶囊走廊。
func get_ai_attack_threats(receiver:ball) -> Array:
	var result:Array = []
	if receiver == null or not is_instance_valid(receiver) or not _is_valid_enemy(receiver):
		return result
	if _attack_phase != DuelistAttackPhase.Thrust:
		return result
	var end_p:Vector2 = _dash_target_point
	var axis:Vector2 = end_p-global_position
	if axis.length_squared() <= 0.000001:
		axis = _dash_direction * maxf(stab_range,8.0)
	result.append({
		"shape":"segment",
		"start":global_position,
		"end":end_p,
		"radius":maxf(thrust_visual_width*0.5,8.0),
		"danger_in":0.0,
		"danger_duration":maxf(_dash_timeout,0.05),
		"damage":attack_damage(),
		"kind":"duelist_thrust",
		"source":self,
	})
	return result
