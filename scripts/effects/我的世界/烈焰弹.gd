extends Node2D

# V180：自定义射线投射物也必须尊重 Sans 的完全闪避；
# 闪避成功后继续沿原射线路径查询后方碰撞体，不生成火场、不销毁弹丸。

const FIRE_PATCH_SCRIPT:Script = preload("res://scripts/effects/我的世界/烈焰火场.gd")
const BURN_SCRIPT:Script = preload("res://scripts/status/战争女神_灼烧.gd")
const BURN_NODE_NAME:StringName = &"MinecraftBlazeBurn"
const MC_DAMAGE_SFX:Script = preload("res://scripts/effects/我的世界/女巫药水伤害音效.gd")
const MC_SMOKE_SCENE:PackedScene = preload("res://scenes/effects/我的世界/MC烟雾粒子.tscn")

var _source_ref:WeakRef = null
var _source_team:String = ""
var _direction:Vector2 = Vector2.RIGHT
var _speed:float = 330.0
var _damage_multiplier:float = 1.0
var _burn_duration:float = 3.2
var _burn_tick_damage_multiplier:float = 0.10
var _fire_radius:float = 34.0
var _fire_duration:float = 4.5
var _fire_tick_damage_multiplier:float = 0.11
var _fire_burn_tick_damage_multiplier:float = 0.05
var _configured:bool = false
var _life:float = 5.0
var _smoke_left:float = 0.0
var _smoke_rng := RandomNumberGenerator.new()

@export_category("烈焰弹 / 烟雾拖尾")
@export_range(0.03,0.30,0.01) var smoke_interval_min:float = 0.055
@export_range(0.03,0.40,0.01) var smoke_interval_max:float = 0.095
@export_range(2.0,28.0,0.5) var smoke_visual_diameter:float = 12.0


func _ready() -> void:
	_smoke_rng.seed = Game.battle_rng_seed_or("scripts/effects/我的世界/烈焰弹.gd:_smoke_rng.seed",maxi(abs(int(Time.get_ticks_usec()) ^ int(get_instance_id())),1))
	_smoke_left = _smoke_rng.randf_range(smoke_interval_min,smoke_interval_max)

func configure(source:ball,team:String,direction:Vector2,speed:float,damage_multiplier:float,burn_duration:float,burn_tick_damage_multiplier:float,fire_radius:float,fire_duration:float,fire_tick_damage_multiplier:float,fire_burn_tick_damage_multiplier:float) -> void:
	_source_ref = weakref(source) if source != null else null
	_source_team = team
	_direction = direction.normalized() if direction.length_squared() > 0.000001 else Vector2.RIGHT
	_speed = maxf(speed,1.0)
	_damage_multiplier = maxf(damage_multiplier,0.0)
	_burn_duration = maxf(burn_duration,0.1)
	_burn_tick_damage_multiplier = maxf(burn_tick_damage_multiplier,0.0)
	_fire_radius = maxf(fire_radius,8.0)
	_fire_duration = maxf(fire_duration,0.4)
	_fire_tick_damage_multiplier = maxf(fire_tick_damage_multiplier,0.0)
	_fire_burn_tick_damage_multiplier = maxf(fire_burn_tick_damage_multiplier,0.0)
	rotation = _direction.angle()
	_configured = true

func _physics_process(delta:float) -> void:
	if not _configured:
		return
	_life -= maxf(delta,0.0)
	if _life <= 0.0:
		queue_free()
		return
	var source:ball = _source_ball()
	# V38：旧逻辑在来源烈焰人被释放后只 return，导致弹丸剩余寿命内悬停在空中。
	# 来源已经死亡/无效时，弹丸不再有合法伤害归属，立即清理。
	if source == null or not is_instance_valid(source):
		queue_free()
		return
	if source.health <= 0 or (source.state_machine != null and source.state_machine.current_state == ball.State.Die):
		queue_free()
		return
	if not source.is_multiplayer_authority():
		return
	_update_smoke_trail(maxf(delta,0.0))
	var start:Vector2 = global_position
	var finish:Vector2 = start + _direction * _speed * maxf(delta,0.0)
	var hit:Dictionary = _raycast_motion(start,finish,source)
	if hit.is_empty():
		global_position = finish
		return
	global_position = hit.get("position",finish)
	var collider:Variant = hit.get("collider",null)
	var target:ball = _resolve_ball_from_collider(collider)
	if target != null and _can_damage(target):
		var applied:bool = target.receive_positional_damage(source.attack_damage(_damage_multiplier),global_position,false,source)
		if applied:
			MC_DAMAGE_SFX.play(target,global_position)
			_apply_burn(source,target,_burn_duration,source.attack_damage(_burn_tick_damage_multiplier))
		queue_free()
		return
	_spawn_fire_patch(source)
	queue_free()


func _update_smoke_trail(delta:float) -> void:
	if MC_SMOKE_SCENE == null or get_tree() == null or get_tree().current_scene == null:
		return
	_smoke_left -= maxf(delta,0.0)
	if _smoke_left > 0.0:
		return
	var low:float = minf(smoke_interval_min,smoke_interval_max)
	var high:float = maxf(smoke_interval_min,smoke_interval_max)
	_smoke_left = _smoke_rng.randf_range(maxf(low,0.03),maxf(high,0.03))
	var smoke:Node2D = MC_SMOKE_SCENE.instantiate() as Node2D
	if smoke == null:
		return
	smoke.name = "MC烟雾_烈焰弹_%d" % smoke.get_instance_id()
	_runtime_container().add_child(smoke,true)
	var perpendicular:=Vector2(-_direction.y,_direction.x)
	var spawn_position:Vector2 = global_position - _direction * _smoke_rng.randf_range(4.0,8.0) + perpendicular * _smoke_rng.randf_range(-2.2,2.2)
	var diameter:float = smoke_visual_diameter * _smoke_rng.randf_range(0.78,1.15)
	if smoke.has_method("configure"):
		smoke.call(
			"configure",
			spawn_position,
			diameter,
			_smoke_rng.randf_range(13.0,22.0),
			_smoke_rng.randf_range(2.0,5.0),
			35,
			_smoke_rng.randf_range(0.46,0.66)
		)

func _raycast_motion(start:Vector2,finish:Vector2,source:ball) -> Dictionary:
	if get_world_2d() == null:
		return {}
	var exclude:Array[RID] = [source.get_rid()]
	if source.has_method("get_blaze_rod_rids"):
		var rod_rids:Variant = source.call("get_blaze_rod_rids")
		if rod_rids is Array:
			for rid_value:Variant in rod_rids:
				exclude.append(rid_value)
	for _pass:int in range(12):
		var query:PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(start,finish,3,exclude)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.hit_from_inside = true
		var hit:Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return {}
		var collider:Variant = hit.get("collider",null)
		var target:ball = _resolve_ball_from_collider(collider)
		if target != null:
			if not _can_damage(target):
				_append_raycast_exclusion(exclude,collider,target)
				continue
			if _target_fully_dodged(target):
				_append_raycast_exclusion(exclude,collider,target)
				continue
		return hit
	return {}


func _resolve_ball_from_collider(collider:Variant) -> ball:
	if collider is ball and is_instance_valid(collider):
		return collider as ball
	if not collider is Node:
		return null
	var node:Node = collider as Node
	while node != null:
		if node is ball and is_instance_valid(node):
			return node as ball
		node = node.get_parent()
	return null


func _append_raycast_exclusion(exclude:Array[RID],collider:Variant,target:ball) -> void:
	var rid:RID = RID()
	if collider is CollisionObject2D and is_instance_valid(collider):
		rid = (collider as CollisionObject2D).get_rid()
	elif target != null and is_instance_valid(target):
		rid = target.get_rid()
	if rid.is_valid() and not exclude.has(rid):
		exclude.append(rid)


func _target_fully_dodged(target:ball) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.has_method("try_full_projectile_dodge"):
		return bool(target.call("try_full_projectile_dodge",self))
	return false

func _spawn_fire_patch(source:ball) -> void:
	if get_tree() == null or get_tree().current_scene == null:
		return
	var patch:Node2D = FIRE_PATCH_SCRIPT.new() as Node2D
	patch.name = "烈焰火场_%d" % patch.get_instance_id()
	_runtime_container().add_child(patch)
	patch.call("setup",source,_source_team,global_position,_fire_radius,_fire_duration,0.50,_fire_tick_damage_multiplier,2.2,_fire_burn_tick_damage_multiplier)

func _runtime_container() -> Node:
	var world:Node = get_tree().current_scene
	var container:Node = world.get_node_or_null("V311运行时对象")
	if container != null:
		return container
	container = Node2D.new()
	container.name = "V311运行时对象"
	world.add_child(container,true)
	return container

func _apply_burn(source:ball,target:ball,duration:float,tick_damage:float) -> void:
	var path := NodePath(String(BURN_NODE_NAME))
	var existing:Node = target.get_node_or_null(path)
	if existing != null and is_instance_valid(existing) and existing.has_method("refresh"):
		existing.call("refresh",source,duration,tick_damage)
		return
	var status:Node2D = BURN_SCRIPT.new() as Node2D
	status.name = BURN_NODE_NAME
	target.add_child(status,true)
	status.call("setup",target,source,duration,0.55,tick_damage)

func _can_damage(target:ball) -> bool:
	if target == null or not is_instance_valid(target) or target.health <= 0 or not target.is_combat_targetable():
		return false
	if not Game.Game_Settings.Have_Team_Damage and not _source_team.is_empty() and target.Team == _source_team:
		return false
	return true

func _source_ball() -> ball:
	if _source_ref == null:
		return null
	var raw:Variant = _source_ref.get_ref()
	return raw as ball if raw is ball and is_instance_valid(raw) else null
