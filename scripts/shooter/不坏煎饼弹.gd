extends ball

const ROT_SHADER:Shader = preload("res://shaders/不坏煎饼腐烂.gdshader")

@export_category("不坏煎饼弹 - 永久反弹")
@export_range(50.0,1200.0,10.0) var fresh_speed:float = 460.0
@export_range(20.0,800.0,10.0) var rotten_speed:float = 170.0
@export_range(0.05,2.0,0.01) var fresh_damage_multiplier:float = 1.0
@export_range(0.05,1.0,0.01) var rotten_damage_multiplier:float = 0.36
@export_range(2.0,120.0,0.5) var full_rot_time:float = 24.0
@export_range(0.0,1440.0,10.0) var spin_degrees_per_second:float = 440.0

@export_category("不坏煎饼弹 - 命中频率")
@export_range(0.05,2.0,0.01) var fresh_hit_cooldown:float = 0.24
@export_range(0.05,3.0,0.01) var rotten_hit_cooldown:float = 0.78
@export_range(0.01,0.25,0.01) var sustained_overlap_scan_interval:float = 0.04

@export_category("不坏煎饼弹 - 腐毒")
@export_range(0.0,1.0,0.01) var poison_rot_threshold:float = 0.70
@export_range(0.1,100.0,0.1) var poison_damage_per_stack:float = 2.0

var _rot_elapsed:float = 0.0
var _rot_ratio:float = 0.0
var _recent_hit_cooldowns:Dictionary = {}
var _rot_material:ShaderMaterial = null
var _overlap_scan_left:float = 0.0
var _full_rot_notified:bool = false


func _ready() -> void:
	Can_Attack = false
	Can_Skill = false
	Health_Restore = 0
	Has_Collision_Damage = true
	super._ready()
	# V274：恢复继承自 ball.tscn 的正常 CharacterBody2D 人物碰撞。
	# 永久煎饼弹会真实撞到敌人并按公共碰撞法线反弹；伤害仍由独立 Hitbox 结算。
	_overlap_scan_left = 0.0
	add_to_group("UnspoiledPancakeProjectile")
	add_to_group("BattleTransient")
	inherit_master_attack_power = true
	master_attack_damage_multiplier = 1.0
	_setup_rot_material()
	reset_pancake_state()


func get_next_state(state:State) -> int:
	# 这枚弹体的玩法定义就是“不消失”。即使有特殊攻击能打到 Shooter，
	# 也在进入 Die 前恢复弹体生命，避免状态机锁死在死亡态。
	if health <= 0:
		health = Max_health
	return super.get_next_state(state)


func tick_physics(state:State,delta:float) -> void:
	if not is_multiplayer_authority():
		super.tick_physics(state,delta)
		return

	_rot_elapsed += maxf(delta,0.0)
	_rot_ratio = clampf(_rot_elapsed / maxf(full_rot_time,0.1),0.0,1.0)
	_update_rot_state()
	if _rot_ratio >= 1.0 - 0.0001 and not _full_rot_notified:
		_full_rot_notified = true
		if Master != null and is_instance_valid(Master) and Master.has_method("on_pancake_rot_reached_full"):
			Master.call("on_pancake_rot_reached_full")
	_tick_recent_hit_cooldowns(delta)
	_overlap_scan_left -= maxf(delta,0.0)
	if _overlap_scan_left <= 0.0:
		_overlap_scan_left = maxf(sustained_overlap_scan_interval,0.01)
		_process_sustained_overlap_hits()

	if image != null and is_instance_valid(image):
		image.rotation += deg_to_rad(spin_degrees_per_second) * delta * lerpf(1.0,0.42,_rot_ratio)

	super.tick_physics(state,delta)


func current_hit_damage_multiplier() -> float:
	var curved:float = _rot_ratio * _rot_ratio * (3.0 - 2.0 * _rot_ratio)
	return lerpf(
		maxf(fresh_damage_multiplier,0.0),
		maxf(rotten_damage_multiplier,0.0),
		curved
	)


func _on_hitbox_on_hit(hurt:hurtbox) -> void:
	if not is_multiplayer_authority():
		return
	var target:ball = _hurtbox_target_ball(hurt)
	if target == null or target == self:
		return

	var target_id:int = target.get_instance_id()
	if float(_recent_hit_cooldowns.get(target_id,0.0)) > 0.0:
		return

	var before_health:float = float(target.health)
	super._on_hitbox_on_hit(hurt)
	var health_loss:float = maxf(before_health - float(target.health),0.0)

	var hit_lock:float = lerpf(
		maxf(fresh_hit_cooldown,0.05),
		maxf(rotten_hit_cooldown,0.05),
		_rot_ratio
	)
	_recent_hit_cooldowns[target_id] = hit_lock

	if health_loss > 0.0 and _rot_ratio >= poison_rot_threshold:
		_apply_infinite_poison(target)



func _process_sustained_overlap_hits() -> void:
	if self_hitbox == null or not is_instance_valid(self_hitbox) or not self_hitbox.has_method("try_hit_hurtbox"):
		return
	# Area2D.area_entered 只在“刚进入”时报告一次。永久弹如果与一个大体型敌人持续重叠，
	# 这里按煎饼自己的 fresh/rotten 命中冷却重新尝试命中，而不是依赖离开后再次 entered。
	for area:Area2D in self_hitbox.get_overlapping_areas():
		if not area is hurtbox:
			continue
		var target:ball = _hurtbox_target_ball(area as hurtbox)
		if target == null or target == self or target.health <= 0:
			continue
		var target_id:int = target.get_instance_id()
		if float(_recent_hit_cooldowns.get(target_id,0.0)) > 0.0:
			continue
		self_hitbox.call("try_hit_hurtbox",area)


func when_collide(speed:float,collision:KinematicCollision2D) -> void:
	# 公共 ball.when_collide() 本身就使用真实碰撞法线反弹；这里保留它，
	# 但绝不进入“撞墙/撞人后死亡”的普通投射物逻辑。
	super.when_collide(speed,collision)


func on_projectile_blocked_by(target:ball,_impact_position:Vector2) -> void:
	# 盾狗等正面格挡只把煎饼弹弹回去，不能销毁“不坏”弹体。
	if not is_multiplayer_authority():
		return
	var away:Vector2 = Vector2.ZERO
	if target != null and is_instance_valid(target):
		away = global_position - target.global_position
	if away.length_squared() <= 0.000001:
		away = -direction
	if away.length_squared() <= 0.000001:
		away = Vector2.RIGHT
	direction = away.normalized()
	velocity = direction * maxf(Speed,1.0)
	global_position += direction * 5.0


func reset_pancake_state() -> void:
	_rot_elapsed = 0.0
	_rot_ratio = 0.0
	_full_rot_notified = false
	_recent_hit_cooldowns.clear()
	_overlap_scan_left = 0.0
	Speed = maxf(fresh_speed,1.0)
	health = Max_health
	block = max_block
	energy = max_energy
	_update_rot_state()
	_notify_master_rot_status()


func get_rot_ratio() -> float:
	return _rot_ratio


func is_fully_rotten() -> bool:
	return _rot_ratio >= 1.0 - 0.0001


func _setup_rot_material() -> void:
	if image == null or not is_instance_valid(image) or not image is CanvasItem:
		return
	_rot_material = ShaderMaterial.new()
	_rot_material.shader = ROT_SHADER
	(image as CanvasItem).material = _rot_material


func _update_rot_state() -> void:
	var curved:float = _rot_ratio * _rot_ratio * (3.0 - 2.0 * _rot_ratio)
	Speed = lerpf(maxf(fresh_speed,1.0),maxf(rotten_speed,1.0),curved)
	if _rot_material != null:
		_rot_material.set_shader_parameter("rot_amount",_rot_ratio)
	_notify_master_rot_status()


func _notify_master_rot_status() -> void:
	# V280：删除不坏煎饼的额外腐烂/腐毒文字；机制与腐烂 Shader 保持。
	if Master == null or not is_instance_valid(Master) or Master.Type != Ball_Type.Ball:
		return
	Master.side_status_remove_permanent("right","unspoiled_pancake_rot")


func _tick_recent_hit_cooldowns(delta:float) -> void:
	if _recent_hit_cooldowns.is_empty():
		return
	var expired:Array[int] = []
	for raw_id:Variant in _recent_hit_cooldowns.keys():
		var id:int = int(raw_id)
		var left:float = maxf(float(_recent_hit_cooldowns.get(id,0.0)) - maxf(delta,0.0),0.0)
		if left <= 0.0:
			expired.append(id)
		else:
			_recent_hit_cooldowns[id] = left
	for id:int in expired:
		_recent_hit_cooldowns.erase(id)


func _apply_infinite_poison(target:ball) -> void:
	if target == null or not is_instance_valid(target) or target.health <= 0:
		return
	var world:Node = get_tree().current_scene
	if world == null or not world.has_method("new_buff"):
		return
	var source:Node = Master if Master != null and is_instance_valid(Master) else self
	world.call(
		"new_buff",
		target,
		source,
		"不坏煎饼_无限腐毒",
		Buff.new(0,INF,Buff.Buff_types.poison,maxf(poison_damage_per_stack,0.1),Buff.Algorithms.add),
		"add"
	)
	# V280：腐毒仍永久叠加，但不再生成角色旁的文字提示。
	target.side_status_remove_permanent("right","unspoiled_pancake_poison")
