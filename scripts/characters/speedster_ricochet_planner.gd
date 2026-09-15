class_name SpeedsterRicochetPlanner
extends RefCounted

var owner_body:ball
var collision_mask:int = 1
var sample_count:int = 96
var ray_length:float = 1050.0
var min_wall_distance:float = 52.0
var min_incidence:float = 0.08
var target_extra_radius:float = 22.0
var setup_max_line_miss:float = 330.0
var setup_min_alignment:float = 0.16
var corner_probe:float = 105.0
var corner_min_open:float = 44.0
var controller_turn_penalty:float = 6.0

func configure(body:ball,config:Dictionary = {}) -> void:
	owner_body = body
	collision_mask = int(config.get("collision_mask",collision_mask))
	sample_count = maxi(int(config.get("sample_count",sample_count)),32)
	ray_length = maxf(float(config.get("ray_length",ray_length)),200.0)
	min_wall_distance = maxf(float(config.get("min_wall_distance",min_wall_distance)),8.0)
	min_incidence = clampf(float(config.get("min_incidence",min_incidence)),0.01,0.95)
	target_extra_radius = maxf(float(config.get("target_extra_radius",target_extra_radius)),0.0)
	setup_max_line_miss = maxf(float(config.get("setup_max_line_miss",setup_max_line_miss)),40.0)
	setup_min_alignment = clampf(float(config.get("setup_min_alignment",setup_min_alignment)),-0.5,0.98)
	corner_probe = maxf(float(config.get("corner_probe",corner_probe)),30.0)
	corner_min_open = maxf(float(config.get("corner_min_open",corner_min_open)),10.0)
	controller_turn_penalty = maxf(float(config.get("controller_turn_penalty",controller_turn_penalty)),0.0)


func find_wall_plan(target:ball,controller_direction:Vector2,attack_speed:float) -> Dictionary:
	if owner_body == null or not is_instance_valid(owner_body):
		return {"valid":false}
	if target == null or not is_instance_valid(target):
		return {"valid":false}
	if owner_body.get_world_2d() == null:
		return {"valid":false}

	var best_exact:Dictionary = {"valid":false,"score":-INF}
	var best_setup:Dictionary = {"valid":false,"score":-INF}
	var count:int = maxi(sample_count,32)
	var controller_dir:Vector2 = controller_direction.normalized() if controller_direction.length_squared() > 0.0001 else Vector2.ZERO

	for i:int in range(count):
		var initial_dir:Vector2 = Vector2.RIGHT.rotated(TAU * float(i) / float(count))
		var result:Dictionary = _evaluate_first_wall(target,initial_dir,attack_speed)
		if not bool(result.get("valid",false)):
			continue

		var score:float = float(result.get("score",-INF))
		if controller_dir.length_squared() > 0.0001:
			score -= absf(controller_dir.angle_to(initial_dir)) * controller_turn_penalty
		result["score"] = score
		result["direction"] = initial_dir

		if bool(result.get("exact",false)):
			if not bool(best_exact.get("valid",false)) or score > float(best_exact.get("score",-INF)):
				best_exact = result
		else:
			if not bool(best_setup.get("valid",false)) or score > float(best_setup.get("score",-INF)):
				best_setup = result

	if bool(best_exact.get("valid",false)):
		best_exact["kind"] = "exact_wall"
		return best_exact
	if bool(best_setup.get("valid",false)):
		best_setup["kind"] = "setup_wall"
		return best_setup
	return {"valid":false}


func current_heading_hits_target(target:ball,heading:Vector2,attack_speed:float,max_distance:float = 760.0) -> Dictionary:
	if owner_body == null or target == null or not is_instance_valid(target):
		return {"valid":false}
	if heading.length_squared() <= 0.0001:
		return {"valid":false}

	var dir:Vector2 = heading.normalized()
	var terrain_hit:Dictionary = _raycast_terrain(owner_body.global_position,dir,max_distance)
	var endpoint:Vector2 = owner_body.global_position + dir * max_distance
	if not terrain_hit.is_empty():
		endpoint = terrain_hit.get("position",endpoint)
		if _is_hazard_collider(terrain_hit.get("collider",null)):
			return {"valid":false}

	var segment_distance:float = owner_body.global_position.distance_to(endpoint)
	var travel_time:float = segment_distance / maxf(attack_speed,1.0)
	var target_velocity:Vector2 = _target_velocity(target)
	var predicted_target:Vector2 = target.global_position + target_velocity * minf(travel_time,0.45)
	var radius:float = _combined_radius(target) + target_extra_radius
	var miss:float = _point_segment_distance(predicted_target,owner_body.global_position,endpoint)
	var projection:float = _segment_projection(predicted_target,owner_body.global_position,endpoint)

	return {
		"valid": projection >= -0.03 and projection <= 1.05 and miss <= radius,
		"miss":miss,
		"projection":projection,
		"end":endpoint,
		"predicted_target":predicted_target,
	}


func _evaluate_first_wall(target:ball,initial_dir:Vector2,attack_speed:float) -> Dictionary:
	var origin:Vector2 = owner_body.global_position
	var hit:Dictionary = _raycast_terrain(origin,initial_dir,ray_length)
	if hit.is_empty():
		return {"valid":false}

	var collider:Variant = hit.get("collider",null)
	if _is_hazard_collider(collider):
		return {"valid":false}

	var wall_point:Vector2 = hit.get("position",origin + initial_dir * ray_length)
	var wall_distance:float = origin.distance_to(wall_point)
	if wall_distance < min_wall_distance:
		return {"valid":false}

	# 第一段绝对不允许先撞目标；攻击必须先拿到一次真实墙面反弹。
	var target_velocity:Vector2 = _target_velocity(target)
	var first_time:float = wall_distance / maxf(attack_speed,1.0)
	var predicted_before_wall:Vector2 = target.global_position + target_velocity * minf(first_time,0.45)
	var target_radius:float = _combined_radius(target) + target_extra_radius
	if _point_segment_distance(predicted_before_wall,origin,wall_point) <= target_radius:
		var proj_first:float = _segment_projection(predicted_before_wall,origin,wall_point)
		if proj_first >= 0.0 and proj_first <= 1.0:
			return {"valid":false}

	var normal:Vector2 = hit.get("normal",Vector2.ZERO)
	if normal.length_squared() <= 0.0001:
		return {"valid":false}
	normal = normal.normalized()
	var incidence:float = absf(initial_dir.normalized().dot(normal))
	if incidence < min_incidence:
		return {"valid":false}

	var reflected:Vector2 = initial_dir.normalized().bounce(normal).normalized()
	if reflected.length_squared() <= 0.0001:
		return {"valid":false}

	var bounce_origin:Vector2 = wall_point + normal * 4.0 + reflected * 4.0
	var openness:float = _bounce_openness(bounce_origin,reflected)
	if openness < corner_min_open:
		return {"valid":false}

	var predicted_target:Vector2 = target.global_position + target_velocity * minf(first_time + 0.18,0.55)
	var to_target:Vector2 = predicted_target - bounce_origin
	if to_target.length_squared() <= 0.0001:
		return {"valid":false}

	var forward:float = to_target.dot(reflected)
	if forward <= 0.0:
		return {"valid":false}
	var closest:Vector2 = bounce_origin + reflected * forward
	var line_miss:float = closest.distance_to(predicted_target)
	var alignment:float = reflected.dot(to_target.normalized())

	var second_hit:Dictionary = _raycast_terrain(bounce_origin,reflected,minf(maxf(forward + target_radius,160.0),ray_length))
	if not second_hit.is_empty():
		var second_collider:Variant = second_hit.get("collider",null)
		if _is_hazard_collider(second_collider):
			return {"valid":false}
		var second_distance:float = bounce_origin.distance_to(second_hit.get("position",bounce_origin))
		if second_distance + target_radius * 0.35 < forward:
			# 下一面墙先于目标出现，这条一墙命中路线不算 exact；仍可作为 setup。
			pass

	var exact:bool = alignment >= 0.58 and line_miss <= target_radius * 1.15
	var setup:bool = alignment >= setup_min_alignment and line_miss <= setup_max_line_miss
	if not exact and not setup:
		return {"valid":false}

	var score:float = alignment * 250.0 - line_miss * 0.72 - wall_distance * 0.035 + openness * 0.22
	if exact:
		score += 360.0

	return {
		"valid":true,
		"exact":exact,
		"score":score,
		"wall_point":wall_point,
		"wall_normal":normal,
		"reflected":reflected,
		"line_miss":line_miss,
		"alignment":alignment,
		"openness":openness,
		"wall_distance":wall_distance,
		"timeout":wall_distance / maxf(attack_speed,1.0) + 0.22,
		"predicted_target":predicted_target,
	}


func _raycast_terrain(origin:Vector2,direction:Vector2,distance:float) -> Dictionary:
	if owner_body == null or owner_body.get_world_2d() == null:
		return {}
	var dir:Vector2 = direction.normalized()
	var query := PhysicsRayQueryParameters2D.new()
	query.from = origin
	query.to = origin + dir * maxf(distance,1.0)
	query.collision_mask = collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [owner_body.get_rid()]
	return owner_body.get_world_2d().direct_space_state.intersect_ray(query)


func _bounce_openness(point:Vector2,heading:Vector2) -> float:
	var directions:Array[Vector2] = [
		heading,
		heading.rotated(deg_to_rad(38.0)),
		heading.rotated(deg_to_rad(-38.0)),
		heading.rotated(deg_to_rad(78.0)),
		heading.rotated(deg_to_rad(-78.0)),
	]
	var total:float = 0.0
	var best:float = 0.0
	for dir:Vector2 in directions:
		var hit:Dictionary = _raycast_terrain(point,dir,corner_probe)
		var clear:float = corner_probe
		if not hit.is_empty():
			clear = point.distance_to(hit.get("position",point))
		total += clear
		best = maxf(best,clear)
	# 既看总体空间也要求至少一个明显出口，避免选择封闭口袋。
	if best < corner_min_open:
		return 0.0
	return total / float(directions.size())


func _is_hazard_collider(collider:Variant) -> bool:
	if collider == null:
		return false
	if collider is ball:
		return false
	if not collider is Node:
		return false
	var node:Node = collider as Node
	var text:String = node.name.to_lower()
	var script:Script = node.get_script() as Script
	if script != null:
		text += " " + script.resource_path.to_lower()
	for token:String in ["矿工小石头","棋子","棋石","stone","rock","chess","piece"]:
		if text.contains(token.to_lower()):
			return true
	return false


func _combined_radius(target:ball) -> float:
	return _body_radius(owner_body) + _body_radius(target)


func _body_radius(entity:ball) -> float:
	if entity == null or not is_instance_valid(entity):
		return 18.0
	var collision:CollisionShape2D = entity.collision_shape_2d
	if collision == null or collision.shape == null:
		return 18.0
	var scale_abs:Vector2 = Vector2(absf(collision.global_scale.x),absf(collision.global_scale.y))
	var shape:Shape2D = collision.shape
	if shape is CircleShape2D:
		return (shape as CircleShape2D).radius * maxf(scale_abs.x,scale_abs.y)
	if shape is RectangleShape2D:
		var size:Vector2 = (shape as RectangleShape2D).size * scale_abs
		return size.length() * 0.5
	if shape is CapsuleShape2D:
		var capsule:CapsuleShape2D = shape as CapsuleShape2D
		return maxf(capsule.radius * scale_abs.x,capsule.height * scale_abs.y * 0.5)
	return 18.0 * maxf(scale_abs.x,scale_abs.y)


func _target_velocity(target:ball) -> Vector2:
	if target.velocity.length_squared() > 1.0:
		return target.velocity
	if target.direction.length_squared() > 0.0001:
		return target.direction.normalized() * maxf(target.Speed,0.0)
	return Vector2.ZERO


func _point_segment_distance(point:Vector2,a:Vector2,b:Vector2) -> float:
	var ab:Vector2 = b - a
	var denom:float = ab.length_squared()
	if denom <= 0.000001:
		return point.distance_to(a)
	var t:float = clampf((point - a).dot(ab) / denom,0.0,1.0)
	return point.distance_to(a + ab * t)


func _segment_projection(point:Vector2,a:Vector2,b:Vector2) -> float:
	var ab:Vector2 = b - a
	var denom:float = ab.length_squared()
	if denom <= 0.000001:
		return 0.0
	return (point - a).dot(ab) / denom
