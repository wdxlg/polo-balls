extends ball

const VISUAL_SCRIPT:Script = preload("res://scripts/characters/月计/堇紫泪滴视觉.gd")
const BLEED_STATUS_SCRIPT:Script = preload("res://scripts/status/剑客_流血.gd")
const BLEED_NODE_NAME:StringName = &"PurpleTearBleedStatus"
const PREVIEW_TEXTURE:Texture2D = preload("res://Images/characters/月计/堇紫泪滴/站立.png")

# V85：堇紫泪滴动作音效。带数字后缀的同名音效由权威端随机一次，
# 再把最终选中的具体音效名同步给各端，避免多人环境各客户端抽到不同版本。
const SFX_BLUNT:String = "堇紫泪滴打击"
const SFX_DEFENSE:String = "堇紫泪滴防御"
const SFX_SLASH_BASE:String = "堇紫泪滴斩击"
const SFX_PIERCE_BASE:String = "堇紫泪滴刺"

enum Stance {
	DEFENSE,
	BLUNT,
	SLASH,
	PIERCE,
}

@export_category("堇紫泪滴 - 姿态")
@export_range(2.0,12.0,0.1) var stance_switch_interval:float = 5.0
@export_range(0.35,3.0,0.05) var attack_interval:float = 1.0
@export_range(20.0,160.0,1.0) var attack_detection_radius:float = 62.0

@export_category("堇紫泪滴 - 防御姿态")
@export_range(0.0,1.0,0.01) var defense_reflect_ratio:float = 0.30
@export_range(1,2,1) var defense_bleed_stacks:int = 1

@export_category("堇紫泪滴 - 斩击姿态")
@export var slash_hitbox_size:Vector2 = Vector2(235.0,150.0)
@export_range(0.0,10.0,0.05) var slash_damage_multiplier:float = 1.0
@export_range(0.0,1.0,0.01) var slash_repeat_chance:float = 0.45
@export_range(0.05,0.6,0.01) var slash_repeat_delay:float = 0.13

@export_category("堇紫泪滴 - 突刺姿态")
@export var pierce_hitbox_size:Vector2 = Vector2(260.0,72.0)
@export_range(0.0,10.0,0.05) var pierce_damage_multiplier:float = 1.0689655
@export_range(8.0,80.0,1.0) var pierce_face_distance:float = 26.0
@export_range(0.06,0.6,0.01) var pierce_dash_duration:float = 0.16
@export_range(1,2,1) var pierce_bleed_stacks:int = 1

@export_category("堇紫泪滴 - 打击姿态")
@export var blunt_hitbox_size:Vector2 = Vector2(190.0,132.0)
@export_range(0.0,10.0,0.05) var blunt_damage_multiplier:float = 1.1034483
@export_range(0.0,120.0,1.0) var blunt_knockback_distance:float = 24.0
@export_range(10.0,500.0,5.0) var blunt_knockback_speed:float = 185.0
@export_range(0.0,3.0,0.05) var blunt_stun_duration:float = 0.55

@export_category("堇紫泪滴 - 时间回溯")
@export_range(1,2000,1) var rewind_trigger_health:int = 350
@export_range(0.4,5.0,0.05) var rewind_absent_duration:float = 1.35
@export_range(0.05,1.0,0.05) var history_sample_interval:float = 0.20
@export_range(2.0,12.0,0.25) var rewind_min_history_seconds:float = 3.5
@export_range(3.0,16.0,0.25) var rewind_max_history_seconds:float = 8.0

@export_category("堇紫泪滴 - 流血（剑客同款，独立最多 2 层）")
@export_range(1.0,15.0,0.5) var bleed_duration:float = 6.0
@export_range(0.0,2.0,0.005) var bleed_action_damage_per_stack_multiplier:float = 0.0344828
@export_range(0.2,2.0,0.05) var bleed_move_tick_interval:float = 0.60
@export_range(0.0,2.0,0.0025) var bleed_move_damage_per_stack_multiplier:float = 0.0103448

var _stance:int = Stance.SLASH
var _stance_elapsed:float = 0.0
var _attack_elapsed:float = 0.0
var _action_busy:bool = false
var _action_serial:int = 0
var _visual_flip_cache:bool = false

var _history_clock:float = 0.0
var _history_sample_left:float = 0.0
var _history:Array[Dictionary] = []
var _rewind_used:bool = false
var _rewinding:bool = false
var _rewind_snapshot:Dictionary = {}
var _base_speed:float = 0.0
var _saved_collision_state:Dictionary = {}
var _active_attack_areas:Array[Area2D] = []

func _ready() -> void:
	Can_Attack = false
	Can_Skill = false
	Has_Collision_Damage = false
	Health_Restore = 0
	Type_Tags = PackedStringArray(["近战","月计","姿态","反伤","流血","控制","时间"])
	side_status_ui_enabled = false
	super._ready()
	image_color = Color.WHITE
	image_color_mix = 0.0
	set_image_color()
	_base_speed = Speed
	_saved_collision_state = _capture_collision_state()
	_stance = randi_range(Stance.DEFENSE,Stance.PIERCE)
	_set_stance_visual()
	_record_snapshot()

func get_preview_texture() -> Texture2D:
	return PREVIEW_TEXTURE

func _physics_process(delta:float) -> void:
	if not is_multiplayer_authority() or health <= 0:
		return
	_sync_visual_flip()
	if _rewinding:
		velocity = Vector2.ZERO
		Repel = Vector2.ZERO
		return

	_history_clock += delta
	_history_sample_left -= delta
	if _history_sample_left <= 0.0:
		_history_sample_left += maxf(history_sample_interval,0.05)
		_record_snapshot()

	_stance_elapsed += delta
	_attack_elapsed += delta
	if not is_player_controlled() and not _action_busy and _stance_elapsed >= maxf(stance_switch_interval,0.2):
		_switch_random_stance()

	if is_player_controlled():
		return
	if _action_busy or _stance == Stance.DEFENSE:
		return
	if _attack_elapsed < maxf(attack_interval,0.1):
		return
	var target:ball = _nearest_enemy_within(attack_detection_radius)
	if target == null:
		return
	_attack_elapsed = 0.0
	_action_serial += 1
	_action_busy = true
	call_deferred("_run_stance_attack",target,_action_serial)

func controlled_attack_action() -> void:
	# 左键按当前姿态发动已有攻击；防御姿态没有主动攻击。
	if not is_player_controlled() or not is_multiplayer_authority() or health <= 0 or _rewinding or not is_combat_runtime_active():
		return
	if _action_busy or _stance == Stance.DEFENSE or _attack_elapsed < maxf(attack_interval,0.1):
		return
	var target:ball = _manual_aimed_enemy()
	if target == null:
		return
	_attack_elapsed = 0.0
	_action_serial += 1
	_action_busy = true
	call_deferred("_run_stance_attack",target,_action_serial)

func controlled_skill_action() -> void:
	# 右键依次切换防御、打击、斩击、突刺；不能跳过原切换间隔。
	if not is_player_controlled() or not is_multiplayer_authority() or health <= 0 or _rewinding or not is_combat_runtime_active():
		return
	if _action_busy or _stance_elapsed < maxf(stance_switch_interval,0.2):
		return
	_stance = (_stance + 1) % 4
	_stance_elapsed = 0.0
	_set_stance_visual()
	_sync_stance_remote()

func _manual_aimed_enemy() -> ball:
	if not has_player_control_aim():
		return null
	var aim:Vector2 = player_control_aim_world_position()
	var nearest:ball = null
	var best_distance:float = pow(maxf(attack_detection_radius,1.0) * 0.6,2.0)
	var radius_sq:float = pow(maxf(attack_detection_radius,0.0),2.0)
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var candidate:ball = raw as ball
		if not _is_enemy(candidate) or global_position.distance_squared_to(candidate.global_position) > radius_sq:
			continue
		var distance:float = aim.distance_squared_to(candidate.global_position)
		if distance < best_distance:
			best_distance = distance
			nearest = candidate
	return nearest

func get_debug_detection_regions() -> Array[Dictionary]:
	if _rewinding or _stance == Stance.DEFENSE:
		return []
	return [{
		"shape":"circle",
		"position":global_position,
		"radius":maxf(attack_detection_radius,1.0),
		"kind":"purple_tear_attack_detection"
	}]

func _switch_random_stance() -> void:
	var choices:Array[int] = [Stance.DEFENSE,Stance.BLUNT,Stance.SLASH,Stance.PIERCE]
	choices.erase(_stance)
	if choices.is_empty():
		return
	_stance = choices[randi() % choices.size()]
	_stance_elapsed = 0.0
	_set_stance_visual()
	_sync_stance_remote()

func _run_stance_attack(target_value:Variant,serial:int) -> void:
	match _stance:
		Stance.BLUNT:
			await _run_blunt_attack(target_value,serial)
		Stance.PIERCE:
			await _run_pierce_attack(target_value,serial)
		Stance.SLASH:
			await _run_slash_attack(target_value,serial)
		_:
			pass
	if serial == _action_serial and not _rewinding:
		_action_busy = false
		_set_stance_visual()

func _run_blunt_attack(target_value:Variant,serial:int) -> void:
	var target:ball = _valid_enemy_from_variant(target_value)
	if target == null:
		return
	var attack_dir:Vector2 = _safe_direction_to(target)
	_face_direction(attack_dir)
	_set_visual_pose(&"blunt_attack")
	_play_character_sfx_everywhere(SFX_BLUNT)
	await get_tree().create_timer(0.09,true,false,true).timeout
	if serial != _action_serial or _rewinding:
		return
	var area:Area2D = _create_attack_area(
		attack_dir,blunt_hitbox_size,attack_damage(blunt_damage_multiplier),
		0,blunt_knockback_distance,blunt_knockback_speed,blunt_stun_duration
	)
	await _finish_attack_area(area,0.15)

func _run_slash_attack(target_value:Variant,serial:int) -> void:
	var target:ball = _valid_enemy_from_variant(target_value)
	if target == null:
		return
	var attack_dir:Vector2 = _safe_direction_to(target)
	_face_direction(attack_dir)
	_set_visual_pose(&"slash1")
	_play_random_numbered_sfx_everywhere(SFX_SLASH_BASE,2)
	await get_tree().create_timer(0.07,true,false,true).timeout
	if serial != _action_serial or _rewinding:
		return
	var area:Area2D = _create_attack_area(attack_dir,slash_hitbox_size,attack_damage(slash_damage_multiplier),0,0.0,0.0,0.0)
	await _finish_attack_area(area,0.13)
	if serial != _action_serial or _rewinding or randf() >= slash_repeat_chance:
		return
	await get_tree().create_timer(maxf(slash_repeat_delay,0.05),true,false,true).timeout
	if serial != _action_serial or _rewinding:
		return
	var current_target:ball = _valid_enemy_from_variant(target_value)
	if current_target != null:
		attack_dir = _safe_direction_to(current_target)
	_face_direction(attack_dir)
	_set_visual_pose(&"slash2")
	_play_random_numbered_sfx_everywhere(SFX_SLASH_BASE,2)
	var area2:Area2D = _create_attack_area(attack_dir,slash_hitbox_size,attack_damage(slash_damage_multiplier),0,0.0,0.0,0.0)
	await _finish_attack_area(area2,0.14)

func _run_pierce_attack(target_value:Variant,serial:int) -> void:
	var target:ball = _valid_enemy_from_variant(target_value)
	if target == null:
		return
	var attack_dir:Vector2 = _safe_direction_to(target)
	_face_direction(attack_dir)
	_set_visual_pose(&"pierce1")
	_play_random_numbered_sfx_everywhere(SFX_PIERCE_BASE,2)
	await get_tree().create_timer(0.07,true,false,true).timeout
	if serial != _action_serial or _rewinding:
		return
	target = _valid_enemy_from_variant(target_value)
	if target == null:
		return
	attack_dir = _safe_direction_to(target)
	var destination:Vector2 = target.global_position - attack_dir * maxf(pierce_face_distance,4.0)
	await _dash_to(destination,maxf(pierce_dash_duration,0.06),serial)
	if serial != _action_serial or _rewinding:
		return
	_set_visual_pose(&"pierce2")
	var area:Area2D = _create_attack_area(
		attack_dir,pierce_hitbox_size,attack_damage(pierce_damage_multiplier),
		pierce_bleed_stacks,0.0,0.0,0.0
	)
	await _finish_attack_area(area,0.16)

func _dash_to(destination:Vector2,duration:float,serial:int) -> void:
	var steps:int = maxi(int(ceil(duration / 0.035)),3)
	for i:int in range(steps):
		if serial != _action_serial or _rewinding or health <= 0:
			return
		var remain:int = maxi(steps - i,1)
		var motion:Vector2 = (destination - global_position) / float(remain)
		if motion.length_squared() <= 0.000001:
			return
		AfterImage()
		var collision:KinematicCollision2D = move_and_collide(motion)
		if collision != null:
			return
		await get_tree().physics_frame

func _create_attack_area(
	attack_dir:Vector2,
	size:Vector2,
	damage_amount:float,
	bleed_stacks:int,
	knockback_distance:float,
	knockback_speed:float,
	stun_duration:float
) -> Area2D:
	if damage_amount <= 0.0:
		return null
	var safe_dir:Vector2 = attack_dir.normalized() if attack_dir.length_squared() > 0.000001 else Vector2.RIGHT
	var rect:= RectangleShape2D.new()
	rect.size = Vector2(maxf(size.x,1.0),maxf(size.y,1.0))
	var area:= Area2D.new()
	area.name = "PurpleTearAttackVolume"
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitoring = true
	area.monitorable = false
	area.set_meta("threat_debug_damage",damage_amount)
	area.set_meta("purple_tear_damage",damage_amount)
	area.set_meta("purple_tear_bleed",maxi(bleed_stacks,0))
	area.set_meta("purple_tear_knockback_distance",maxf(knockback_distance,0.0))
	area.set_meta("purple_tear_knockback_speed",maxf(knockback_speed,0.0))
	area.set_meta("purple_tear_stun",maxf(stun_duration,0.0))
	area.set_meta("purple_tear_hit_ids",{})
	var shape_node:= CollisionShape2D.new()
	shape_node.name = "CollisionShape2D"
	shape_node.shape = rect
	area.add_child(shape_node)
	add_child(area)
	# V191：攻击方向来自世界坐标，不能被角色根节点的 Sans 重力旋转再转一次。
	area.global_position = global_position + safe_dir * maxf(size.x * 0.42,4.0)
	area.global_rotation = safe_dir.angle()
	area.body_entered.connect(_on_attack_area_body_entered.bind(area))
	_active_attack_areas.append(area)
	return area

func _on_attack_area_body_entered(body:Node2D,area:Area2D) -> void:
	if not is_multiplayer_authority() or area == null or not is_instance_valid(area):
		return
	if body == null or not is_instance_valid(body) or not body is ball:
		return
	var target:ball = body as ball
	if not _is_enemy(target):
		return
	var raw_ids:Variant = area.get_meta("purple_tear_hit_ids",{})
	var hit_ids:Dictionary = raw_ids if raw_ids is Dictionary else {}
	var id:int = target.get_instance_id()
	if hit_ids.has(id):
		return
	hit_ids[id] = true
	area.set_meta("purple_tear_hit_ids",hit_ids)
	var damage_amount:float = maxf(float(area.get_meta("purple_tear_damage",0.0)),0.0)
	var accepted:bool = target.receive_positional_damage(damage_amount,target.global_position,false,self)
	if not accepted:
		return
	var bleed_stacks:int = int(area.get_meta("purple_tear_bleed",0))
	if bleed_stacks > 0:
		_apply_bleed(target,bleed_stacks)
	var knockback_distance:float = float(area.get_meta("purple_tear_knockback_distance",0.0))
	var stun_duration:float = float(area.get_meta("purple_tear_stun",0.0))
	if knockback_distance > 0.0 or stun_duration > 0.0:
		var hit_dir:Vector2 = target.global_position - global_position
		if hit_dir.length_squared() <= 0.000001:
			hit_dir = Vector2.RIGHT
		target.apply_knockback(
			hit_dir.normalized(),
			knockback_distance,
			maxf(float(area.get_meta("purple_tear_knockback_speed",0.0)),10.0),
			0.0,
			stun_duration,
			{"source":self}
		)

func _finish_attack_area(area:Area2D,hold_time:float) -> void:
	if area == null or not is_instance_valid(area):
		if hold_time > 0.0:
			await get_tree().create_timer(hold_time,true,false,true).timeout
		return
	await get_tree().physics_frame
	if area != null and is_instance_valid(area):
		for body:Node2D in area.get_overlapping_bodies():
			_on_attack_area_body_entered(body,area)
	if hold_time > 0.0:
		await get_tree().create_timer(hold_time,true,false,true).timeout
	if area != null and is_instance_valid(area):
		for body:Node2D in area.get_overlapping_bodies():
			_on_attack_area_body_entered(body,area)
		_active_attack_areas.erase(area)
		area.queue_free()

# ------------------------------
# 防御姿态：全伤害免疫 + 30% 反伤 + 2 层上限的剑客同款流血。
# ------------------------------
func take_damage(damage:float,ignore_block:bool = false) -> void:
	if damage <= 0.0:
		return
	if _rewinding or _stance == Stance.DEFENSE:
		hit_white_visual_only()
		return
	super.take_damage(damage,ignore_block)

func receive_positional_damage(damage:float,impact_position:Vector2,ignore_block:bool = false,source:Node = null) -> bool:
	if damage <= 0.0:
		return false
	if _rewinding:
		return true
	if _stance == Stance.DEFENSE:
		hit_white_visual_only()
		_reflect_guard_damage(damage,source,impact_position)
		return true
	return super.receive_positional_damage(damage,impact_position,ignore_block,source)

func receive_spatial_damage(damage:float,damage_space:Variant,ignore_block:bool = false,raw_health:bool = false) -> bool:
	if damage <= 0.0:
		return false
	var is_reflection:bool = false
	var source:Node = null
	var point:Vector2 = global_position
	if damage_space is Dictionary:
		var context:Dictionary = damage_space as Dictionary
		is_reflection = bool(context.get("purple_tear_reflection",false))
		var raw_source:Variant = context.get("source",null)
		if is_instance_valid(raw_source) and raw_source is Node:
			source = raw_source as Node
		if context.get("point",null) is Vector2:
			point = context.get("point",global_position) as Vector2
	if is_reflection:
		return super.receive_spatial_damage(damage,damage_space,ignore_block,raw_health)
	if _rewinding:
		return true
	if _stance == Stance.DEFENSE:
		hit_white_visual_only()
		_reflect_guard_damage(damage,source,point)
		return true
	return super.receive_spatial_damage(damage,damage_space,ignore_block,raw_health)

func _on_hurtbox_on_hurt(hit:hitbox) -> void:
	if _rewinding or _stance != Stance.DEFENSE or hit == null or not is_instance_valid(hit):
		return
	var direct_source:Variant = hit.get_parent()
	var incoming_damage:float = 0.0
	if is_instance_valid(direct_source) and direct_source is ball:
		var direct_ball:ball = direct_source as ball
		incoming_damage = direct_ball.attack_damage()
	_reflect_guard_damage(incoming_damage,direct_source,global_position)

func _reflect_guard_damage(incoming_damage:float,source:Variant,impact_position:Vector2) -> void:
	if incoming_damage <= 0.0:
		return
	var resolved:Node = Game.resolve_combat_source(source) if Game.has_method("resolve_combat_source") else null
	if resolved == null or not is_instance_valid(resolved) or not resolved is ball:
		return
	var attacker:ball = resolved as ball
	if attacker == self or not _is_enemy(attacker) or attacker.health <= 0:
		return
	_play_character_sfx_everywhere(SFX_DEFENSE)
	var reflected:float = maxf(incoming_damage * clampf(defense_reflect_ratio,0.0,1.0),0.0)
	if reflected > 0.0:
		attacker.receive_spatial_damage(
			reflected,
			{
				"point":impact_position,
				"source":self,
				"purple_tear_reflection":true,
			},
			true,
			true
		)
	_apply_bleed(attacker,defense_bleed_stacks)

func _apply_bleed(target:ball,added_stacks:int) -> void:
	if target == null or not is_instance_valid(target) or target.health <= 0 or added_stacks <= 0:
		return
	var existing:Node = target.get_node_or_null(NodePath(str(BLEED_NODE_NAME)))
	if existing != null and is_instance_valid(existing) and existing.has_method("add_stacks"):
		existing.call("add_stacks",added_stacks,self)
		return
	var status:Node = BLEED_STATUS_SCRIPT.new()
	status.name = BLEED_NODE_NAME
	target.add_child(status)
	status.call(
		"setup",target,self,added_stacks,2,bleed_duration,
		attack_damage(bleed_action_damage_per_stack_multiplier),bleed_move_tick_interval,attack_damage(bleed_move_damage_per_stack_multiplier)
	)

# raw health / 流血等绕过 take_damage 的路径也必须被防御姿态免疫。
func on_actual_health_damage_received(actual_health_damage:float,health_before:float) -> void:
	if actual_health_damage <= 0.0:
		return
	if _rewinding or _stance == Stance.DEFENSE:
		health = clampi(int(round(health_before)),1,Max_health)
		return
	if not _rewind_used and health <= clampi(rewind_trigger_health,1,Max_health - 1):
		_begin_temporal_rewind()

# ------------------------------
# 时间回溯
# ------------------------------
func _record_snapshot() -> void:
	if _rewinding or health <= 0:
		return
	_history.append({
		"time":_history_clock,
		"health":int(health),
		"position":global_position,
		"stance":_stance,
		"block":int(block),
		"direction":direction,
		"stance_elapsed":_stance_elapsed,
		"attack_elapsed":_attack_elapsed,
	})
	var keep_seconds:float = maxf(rewind_max_history_seconds + 2.0,rewind_min_history_seconds + 1.0)
	while not _history.is_empty() and _history_clock - float(_history[0].get("time",0.0)) > keep_seconds:
		_history.pop_front()

func _select_rewind_snapshot() -> Dictionary:
	var candidates:Array[Dictionary] = []
	for snap:Dictionary in _history:
		var age:float = _history_clock - float(snap.get("time",_history_clock))
		if age >= rewind_min_history_seconds and age <= rewind_max_history_seconds:
			candidates.append(snap)
	if not candidates.is_empty():
		return candidates[randi() % candidates.size()].duplicate(true)
	# 极端情况下开局几秒内就被打到阈值，退回当前历史中最老的一帧，至少不会死锁。
	if not _history.is_empty():
		return _history[0].duplicate(true)
	return {
		"health":Max_health,
		"position":global_position,
		"stance":_stance,
		"block":0,
		"direction":direction,
	}

func _begin_temporal_rewind() -> void:
	if _rewind_used or _rewinding:
		return
	_rewind_used = true
	_rewinding = true
	_rewind_snapshot = _select_rewind_snapshot()
	_action_serial += 1
	_action_busy = false
	_clear_active_attack_areas()
	# 避免已经被打到 0 后下一物理帧进入普通死亡流程。
	if health <= 0:
		health = 1
	Speed = 0.0
	velocity = Vector2.ZERO
	Repel = Vector2.ZERO
	_set_temporal_presence(false)
	_sync_rewind_presence_remote(false)
	call_deferred("_finish_temporal_rewind")

func _finish_temporal_rewind() -> void:
	await get_tree().create_timer(maxf(rewind_absent_duration,0.1),true,false,true).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return
	var snap:Dictionary = _rewind_snapshot
	global_position = snap.get("position",global_position)
	# V86：时间回溯是“恢复到历史状态”，不是普通治疗。
	# 生命条仍正常同步，但不要生成一个巨大的绿色治疗跳字。
	var rewind_previous_suppress_floating_text:bool = false
	if health_bar != null:
		rewind_previous_suppress_floating_text = health_bar.suppress_floating_text
		health_bar.suppress_floating_text = true
	health = clampi(int(snap.get("health",Max_health)),1,Max_health)
	if health_bar != null:
		health_bar.suppress_floating_text = rewind_previous_suppress_floating_text
	block = clampi(int(snap.get("block",0)),0,max_block)
	direction = snap.get("direction",Vector2.ZERO)
	_stance = clampi(int(snap.get("stance",Stance.SLASH)),Stance.DEFENSE,Stance.PIERCE)
	Speed = _base_speed
	_stance_elapsed = float(snap.get("stance_elapsed",0.0))
	_attack_elapsed = float(snap.get("attack_elapsed",0.0))
	_rewinding = false
	_set_temporal_presence(true)
	_set_stance_visual()
	_sync_stance_remote()
	_sync_rewind_presence_remote(true)

func _capture_collision_state() -> Dictionary:
	return {
		"root_layer":collision_layer,
		"root_mask":collision_mask,
		"hurt_layer":self_hurtbox.collision_layer if self_hurtbox != null else 0,
		"hurt_mask":self_hurtbox.collision_mask if self_hurtbox != null else 0,
		"hurt_monitoring":self_hurtbox.monitoring if self_hurtbox != null else false,
		"hurt_monitorable":self_hurtbox.monitorable if self_hurtbox != null else false,
		"hit_layer":self_hitbox.collision_layer if self_hitbox != null else 0,
		"hit_mask":self_hitbox.collision_mask if self_hitbox != null else 0,
		"hit_monitoring":self_hitbox.monitoring if self_hitbox != null else false,
		"hit_monitorable":self_hitbox.monitorable if self_hitbox != null else false,
	}

# V87：回溯可能由 hurtbox / hitbox 的 Area2D 信号链直接触发。
# Godot 在 physics in/out signal 正在 flush 时禁止立即切换 monitoring / monitorable；
# 因此整组碰撞状态统一在帧末提交，避免 monitorable 修完后又被 monitoring / layer 写入卡住。
func _set_temporal_area_state_deferred(area:Area2D,layer:int,mask:int,monitoring_value:bool,monitorable_value:bool) -> void:
	if area == null or not is_instance_valid(area):
		return
	area.set_deferred("collision_layer",layer)
	area.set_deferred("collision_mask",mask)
	area.set_deferred("monitoring",monitoring_value)
	area.set_deferred("monitorable",monitorable_value)

func _set_temporal_presence(present:bool) -> void:
	visible = present
	if present:
		set_deferred("collision_layer",int(_saved_collision_state.get("root_layer",2)))
		set_deferred("collision_mask",int(_saved_collision_state.get("root_mask",3)))
		_set_temporal_area_state_deferred(
			self_hurtbox,
			int(_saved_collision_state.get("hurt_layer",0)),
			int(_saved_collision_state.get("hurt_mask",0)),
			bool(_saved_collision_state.get("hurt_monitoring",false)),
			bool(_saved_collision_state.get("hurt_monitorable",true))
		)
		_set_temporal_area_state_deferred(
			self_hitbox,
			int(_saved_collision_state.get("hit_layer",0)),
			int(_saved_collision_state.get("hit_mask",0)),
			bool(_saved_collision_state.get("hit_monitoring",false)),
			bool(_saved_collision_state.get("hit_monitorable",true))
		)
	else:
		set_deferred("collision_layer",0)
		set_deferred("collision_mask",0)
		_set_temporal_area_state_deferred(self_hurtbox,0,0,false,false)
		_set_temporal_area_state_deferred(self_hitbox,0,0,false,false)

func _clear_active_attack_areas() -> void:
	for area:Area2D in _active_attack_areas:
		if area != null and is_instance_valid(area):
			area.queue_free()
	_active_attack_areas.clear()

# ------------------------------
# 目标 / 视觉 / 联机
# ------------------------------
func _nearest_enemy_within(radius:float) -> ball:
	var best:ball = null
	var best_d2:float = maxf(radius,0.0) * maxf(radius,0.0)
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var candidate:ball = node as ball
		if not _is_enemy(candidate):
			continue
		var d2:float = global_position.distance_squared_to(candidate.global_position)
		if d2 <= best_d2:
			best_d2 = d2
			best = candidate
	return best

func _valid_enemy_from_variant(value:Variant) -> ball:
	if not is_instance_valid(value) or not value is ball:
		return null
	var candidate:ball = value as ball
	return candidate if _is_enemy(candidate) else null

func _is_enemy(candidate:ball) -> bool:
	if candidate == null or not is_instance_valid(candidate) or candidate == self or candidate.health <= 0:
		return false
	if not candidate.is_combat_targetable():
		return false
	if candidate.state_machine != null and candidate.state_machine.current_state == State.Die:
		return false
	var my_team:String = str(Team).strip_edges()
	var other_team:String = str(candidate.Team).strip_edges()
	if my_team.is_empty() or other_team.is_empty():
		return true
	return my_team != other_team

func _safe_direction_to(target:ball) -> Vector2:
	var v:Vector2 = target.global_position - global_position if target != null and is_instance_valid(target) else direction
	if v.length_squared() <= 0.000001:
		v = Vector2.RIGHT
	return v.normalized()

func _face_direction(world_dir:Vector2) -> void:
	if absf(world_dir.x) <= 0.001:
		return
	var flipped:bool = world_dir.x > 0.0 if dir_left else world_dir.x <= 0.0
	set_character_visual_flip_h(flipped)
	_visual_flip_cache = flipped
	if image != null and is_instance_valid(image) and image.has_method("apply_runtime_flip"):
		image.call("apply_runtime_flip",flipped)

func _sync_visual_flip() -> void:
	var flipped:bool = is_character_visual_flipped_h()
	if flipped == _visual_flip_cache:
		return
	_visual_flip_cache = flipped
	if image != null and is_instance_valid(image) and image.has_method("apply_runtime_flip"):
		image.call("apply_runtime_flip",flipped)

# ============================================================
# V85 堇紫泪滴动作音效
# ============================================================
func _play_random_numbered_sfx_everywhere(base_name:String,count:int) -> void:
	if base_name.is_empty() or count <= 0:
		return
	var chosen:String = "%s%d" % [base_name,randi_range(1,count)]
	_play_character_sfx_everywhere(chosen)

func _play_character_sfx_everywhere(sfx_name:String) -> void:
	if sfx_name.is_empty():
		return
	if Audios == null or Audios.Sfx == null or not Audios.Sfx.has_node(sfx_name):
		push_warning("堇紫泪滴：找不到动作音效 Sfx/%s。" % sfx_name)
		return

	# 战斗行为只在角色权威端决定。联网时把已经选定的具体编号音效同步给所有端，
	# 离线则直接本地播放。create_new_audio=true 避免连续动作彼此截断。
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc(sfx_name,{},false,true)
	else:
		Audios.play_sfx(sfx_name,{},false,true)


func _stance_idle_pose() -> StringName:
	match _stance:
		Stance.DEFENSE: return &"guard"
		Stance.BLUNT: return &"blunt_stance"
		Stance.PIERCE: return &"pierce_stance"
		_: return &"slash_stance"

func _set_stance_visual() -> void:
	_set_visual_pose(_stance_idle_pose())

func _set_visual_pose(pose:StringName) -> void:
	if image != null and is_instance_valid(image) and image.has_method("apply_runtime_pose"):
		image.call("apply_runtime_pose",pose)
		if image.has_method("apply_runtime_flip"):
			image.call("apply_runtime_flip",is_character_visual_flipped_h())
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		_remote_visual_pose.rpc(pose,is_character_visual_flipped_h())

@rpc("authority","call_remote","unreliable")
func _remote_visual_pose(pose:StringName,flipped:bool) -> void:
	set_character_visual_flip_h(flipped)
	if image != null and is_instance_valid(image) and image.has_method("apply_runtime_pose"):
		image.call("apply_runtime_pose",pose)
		if image.has_method("apply_runtime_flip"):
			image.call("apply_runtime_flip",flipped)

func _sync_stance_remote() -> void:
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		_remote_stance.rpc(_stance)

@rpc("authority","call_remote","unreliable")
func _remote_stance(value:int) -> void:
	_stance = clampi(value,Stance.DEFENSE,Stance.PIERCE)
	_set_stance_visual()

func _sync_rewind_presence_remote(present:bool) -> void:
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		_remote_rewind_presence.rpc(present)

@rpc("authority","call_remote","reliable")
func _remote_rewind_presence(present:bool) -> void:
	visible = present
