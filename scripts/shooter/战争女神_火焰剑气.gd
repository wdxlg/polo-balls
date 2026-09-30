extends Node2D

const WAR_GODDESS_BURN_SCRIPT:Script = preload("res://scripts/status/战争女神_灼烧.gd")
const WAR_GODDESS_BURN_NODE_NAME:StringName = &"WarGoddessBurnStatus"

var owner_ball:ball = null
var team:String = ""
var direction:Vector2 = Vector2.RIGHT
var damage_amount:float = 26.0
var speed:float = 560.0
var max_distance:float = 520.0
var burn_duration:float = 3.0
var burn_tick_interval:float = 0.5
var burn_tick_damage:float = 3.0

var _travelled:float = 0.0
var _finished:bool = false
var _hit_target_ids:Dictionary = {}

@onready var hit_area:Area2D = $HitArea
@onready var collision_shape:CollisionShape2D = $HitArea/CollisionShape2D


func setup(
	new_owner:ball,
	new_team:String,
	new_direction:Vector2,
	new_damage:float,
	new_speed:float,
	new_max_distance:float,
	new_burn_duration:float,
	new_burn_tick_interval:float,
	new_burn_tick_damage:float
) -> void:
	owner_ball = new_owner
	team = new_team
	direction = new_direction.normalized() if new_direction.length_squared() > 0.000001 else Vector2.RIGHT
	damage_amount = maxf(new_damage,0.0)
	speed = maxf(new_speed,1.0)
	max_distance = maxf(new_max_distance,10.0)
	burn_duration = maxf(new_burn_duration,0.1)
	burn_tick_interval = maxf(new_burn_tick_interval,0.05)
	burn_tick_damage = maxf(new_burn_tick_damage,0.0)
	rotation = direction.angle()
	if hit_area != null:
		hit_area.set_meta("threat_debug_damage",damage_amount)


func _ready() -> void:
	add_to_group("AllayExtendedProjectile")
	add_to_group("BattleTransient")
	hit_area.collision_layer = 0
	hit_area.collision_mask = 3
	hit_area.monitoring = true
	hit_area.monitorable = false
	hit_area.set_meta("threat_debug_damage",damage_amount)
	queue_redraw()


func _physics_process(delta:float) -> void:
	if _finished:
		return
	if owner_ball == null or not is_instance_valid(owner_ball) or owner_ball.health <= 0:
		_finish()
		return
	if not owner_ball.is_combat_runtime_active():
		return

	var move_distance:float = minf(speed * delta,maxf(max_distance - _travelled,0.0))
	if move_distance <= 0.0:
		_finish()
		return

	# 非 authority 客户端只重放同样的直线运动；真正伤害/障碍判定只在 authority 执行。
	if not owner_ball.is_multiplayer_authority():
		global_position += direction * move_distance
		_travelled += move_distance
		if _travelled >= max_distance - 0.001:
			_finish()
		return

	var radius:float = _projectile_radius()
	var substeps:int = maxi(1,ceili(move_distance / maxf(radius * 0.80,2.0)))
	var sub_distance:float = move_distance / float(substeps)
	for _index:int in range(substeps):
		var next_position:Vector2 = global_position + direction * sub_distance
		if get_tree().has_group("MinecraftAllay") and load("res://scripts/characters/我的世界/allay/capture.gd").sweep(self,global_position,next_position): return
		var obstacle_hit:bool = _query_damage_shape(next_position)
		global_position = next_position
		_travelled += sub_distance
		if obstacle_hit:
			_finish()
			return
		if _travelled >= max_distance - 0.001:
			_finish()
			return


func _projectile_radius() -> float:
	var shape := collision_shape.shape as CircleShape2D
	return shape.radius if shape != null else 9.0


func _query_damage_shape(at_position:Vector2) -> bool:
	if collision_shape == null or collision_shape.shape == null:
		return false
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = collision_shape.shape
	params.transform = Transform2D(0.0,at_position)
	params.collision_mask = 3
	params.collide_with_bodies = true
	params.collide_with_areas = false
	if owner_ball != null and is_instance_valid(owner_ball):
		params.exclude = [owner_ball.get_rid()]
	var hits:Array[Dictionary] = get_world_2d().direct_space_state.intersect_shape(params,32)
	var obstacle_hit:bool = false
	for hit:Dictionary in hits:
		var collider:Variant = hit.get("collider",null)
		if collider is ball:
			var target:ball = collider as ball
			if _can_damage_target(target):
				_apply_projectile_hit(target,at_position)
			# 所有角色/召唤实体都允许剑气继续穿过；只有非 ball 障碍会截断。
			continue
		if collider != null:
			obstacle_hit = true
	return obstacle_hit


func _can_damage_target(target:ball) -> bool:
	if target == null or not is_instance_valid(target) or target == owner_ball or target.health <= 0:
		return false
	if not target.is_combat_targetable():
		return false
	if not team.is_empty() and target.Team == team:
		return false
	return true


func _apply_projectile_hit(target:ball,impact_position:Vector2) -> void:
	var target_id:int = target.get_instance_id()
	if _hit_target_ids.has(target_id):
		return
	if target.has_method("try_full_projectile_dodge") and bool(target.call("try_full_projectile_dodge",self)): return
	_hit_target_ids[target_id] = true
	var outgoing:float = owner_ball.effective_outgoing_damage(damage_amount)
	if outgoing <= 0.0:
		return
	if target.has_method("try_block_projectile_hit") and bool(target.call("try_block_projectile_hit",self,impact_position,outgoing)):
		_finish()
		return
	var before_health:float = float(target.health)
	var before_block:float = float(target.block)
	var applied:bool = target.receive_fire_positional_damage(outgoing,impact_position,false,owner_ball)
	var health_loss:float = maxf(before_health - float(target.health),0.0)
	var block_loss:float = maxf(before_block - float(target.block),0.0)
	if health_loss > 0.0:
		var seed:int = Game.battle_rng_seed_or("scripts/shooter/战争女神_火焰剑气.gd:seed",int(Time.get_ticks_usec()) ^ target_id ^ get_instance_id())
		target.notify_hit_burst_feedback(impact_position,outgoing,health_loss,block_loss,_projectile_radius() * 2.0,seed,direction)
		_play_hit_sfx(outgoing)
	if applied:
		_apply_burn(target)


func _apply_burn(target:ball) -> void:
	if target == null or not is_instance_valid(target) or not target.can_receive_fire_status():
		return
	var existing:Node = target.get_node_or_null(NodePath(String(WAR_GODDESS_BURN_NODE_NAME)))
	if existing != null and existing.has_method("refresh"):
		existing.call("refresh",owner_ball,burn_duration,burn_tick_damage)
		return
	var status:Node2D = WAR_GODDESS_BURN_SCRIPT.new() as Node2D
	if status == null:
		return
	status.name = WAR_GODDESS_BURN_NODE_NAME
	status.top_level = true
	target.add_child(status,true)
	status.global_position = target.global_position
	status.call("setup",target,owner_ball,burn_duration,burn_tick_interval,burn_tick_damage)


func _play_hit_sfx(raw_damage:float) -> void:
	if owner_ball == null or owner_ball.Hit_Audio.is_empty():
		return
	var params:Dictionary = {"volume":clampf(raw_damage - 36.0,-18.0,0.0),"pitch":randf_range(0.96,1.06)}
	if multiplayer.has_multiplayer_peer():
		Audios.play_sfx.rpc(owner_ball.Hit_Audio,params,true)
	else:
		Audios.play_sfx(owner_ball.Hit_Audio,params,true)


func _draw() -> void:
	# V48：远程火焰视觉由 FireArcVisual + CanvasItem Shader 负责。
	# 真实伤害仍由 HitArea/CollisionShape2D 承担，避免视觉与物理判定耦合。
	pass


func _finish() -> void:
	if _finished:
		return
	_finished = true
	queue_free()
