extends Node2D

var owner_leader:Node = null
var authoritative_logic:bool = false
var projectile_team:String = ""
var travel_direction:Vector2 = Vector2.RIGHT
var projectile_speed:float = 340.0
var max_lifetime:float = 3.2
var damage_amount:float = 20.0
var hit_radius:float = 9.0
var elapsed:float = 0.0

@onready var visual:Sprite2D = $Visual


func configure(owner_node:Node,config:Dictionary,is_authority:bool) -> void:
	owner_leader = owner_node
	authoritative_logic = is_authority
	global_position = config.get("origin",global_position)
	travel_direction = config.get("direction",Vector2.RIGHT)
	if travel_direction.length_squared() <= 0.000001:
		travel_direction = Vector2.RIGHT
	travel_direction = travel_direction.normalized()
	projectile_speed = maxf(float(config.get("speed",340.0)),1.0)
	max_lifetime = maxf(float(config.get("lifetime",3.2)),0.1)
	damage_amount = maxf(float(config.get("damage",20.0)),0.0)
	projectile_team = str(config.get("team",""))
	rotation = travel_direction.angle() + PI * 0.5
	z_as_relative = false
	z_index = 80
	add_to_group("BattleTransient")
	if visual != null:
		visual.visible = true


func _physics_process(delta:float) -> void:
	elapsed += delta
	var from_pos:Vector2 = global_position
	var to_pos:Vector2 = from_pos + travel_direction * projectile_speed * delta
	var terrain_hit:Dictionary = _terrain_hit(from_pos,to_pos)
	if not terrain_hit.is_empty():
		global_position = terrain_hit.get("position",to_pos)
		_remove_self_synced()
		return
	global_position = to_pos
	if authoritative_logic:
		var target:ball = _first_enemy_hit(from_pos,to_pos)
		if target != null:
			var final_damage:float = damage_amount
			if (
				owner_leader is ball
				and is_instance_valid(owner_leader)
				and owner_leader.has_method("_roll_document_damage_for_target")
			):
				final_damage = float(owner_leader.call("_roll_document_damage_for_target",target))
			elif owner_leader is ball and is_instance_valid(owner_leader):
				final_damage = (owner_leader as ball).effective_outgoing_damage(damage_amount)

			var dealt:bool = false
			if final_damage > 0.0:
				dealt = target.receive_spatial_damage(
					final_damage,
					{"point":global_position,"source":owner_leader,"focus_position":global_position},
					false,
					false
				)
			if dealt and owner_leader != null and is_instance_valid(owner_leader):
				if owner_leader.has_method("_record_document_hit"):
					owner_leader.call("_record_document_hit",target)
				if owner_leader.has_method("_call_document_hit_audio"):
					owner_leader.call("_call_document_hit_audio",target.global_position)
			_remove_self_synced()
			return
	if elapsed >= max_lifetime:
		queue_free()


func _remove_self_synced() -> void:
	if authoritative_logic and owner_leader != null and is_instance_valid(owner_leader) and owner_leader.has_method("_call_remove_runtime_node"):
		owner_leader.call("_call_remove_runtime_node",str(name))
	else:
		queue_free()


func _terrain_hit(from_pos:Vector2,to_pos:Vector2) -> Dictionary:
	var world_2d:World2D = get_world_2d()
	if world_2d == null:
		return {}
	var query := PhysicsRayQueryParameters2D.create(from_pos,to_pos,1)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return world_2d.direct_space_state.intersect_ray(query)


func _first_enemy_hit(from_pos:Vector2,to_pos:Vector2) -> ball:
	var candidates:Array[Dictionary] = []
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not (raw is ball):
			continue
		var target:ball = raw as ball
		if target == owner_leader or not target.is_combat_targetable():
			continue
		if (
			projectile_team != ""
			and target.Team != ""
			and target.Team == projectile_team
		):
			continue
		var t:float = _segment_parameter(target.global_position,from_pos,to_pos)
		var closest:Vector2 = from_pos.lerp(to_pos,t)
		if target.global_position.distance_to(closest) <= hit_radius + _target_radius(target):
			candidates.append({"t":t,"target":target})

	candidates.sort_custom(func(a:Dictionary,b:Dictionary) -> bool: return float(a.get("t",0.0)) < float(b.get("t",0.0)))
	for candidate:Dictionary in candidates:
		var target:ball = candidate.get("target",null) as ball
		if target == null or not is_instance_valid(target):
			continue
		# V179：Sans 闪避不消耗文件投射物；继续寻找同一段路径后面的真实命中目标。
		if target.has_method("try_full_projectile_dodge") and bool(target.call("try_full_projectile_dodge",self)):
			continue
		return target
	return null


func _segment_parameter(point:Vector2,a:Vector2,b:Vector2) -> float:
	var ab:Vector2 = b - a
	var len_sq:float = ab.length_squared()
	if len_sq <= 0.000001:
		return 0.0
	return clampf((point - a).dot(ab) / len_sq,0.0,1.0)


func _target_radius(target:ball) -> float:
	if target.has_method("get_crowd_separation_radius_world"):
		return clampf(float(target.call("get_crowd_separation_radius_world")),5.0,28.0)
	return 12.0
