extends "res://classes/ai_original_base.gd"
var _shot_count:int = 0
func Attack() -> void:
	super.Attack()
	if not is_multiplayer_authority() or not is_combat_runtime_active():
		return
	var target:ball = nearest_opponent()
	if target == null:
		return
	var origin:Vector2 = global_position
	var aim:Vector2 = player_control_aim_direction(direction) if has_player_control_aim() else (target.global_position - origin).normalized()
	var endpoint:Vector2 = origin + aim * engagement_range
	var piercing:bool = (_shot_count + 1) % 3 == 0
	var delay:float = 0.40 if piercing else 0.18
	var generation:int = begin_action()
	effect(0,origin,endpoint,0.0,delay)
	if await windup(delay,generation):
		_shot_count += 1
		var query:PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(origin,endpoint,1,[get_rid()])
		var wall:Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
		if not wall.is_empty():
			endpoint = wall.position
		var candidates:Array[ball] = enemies_near(origin,engagement_range)
		candidates.sort_custom(func(a:ball,b:ball): return origin.distance_squared_to(a.global_position) < origin.distance_squared_to(b.global_position))
		effect(2,origin,endpoint,5.0 if piercing else 2.0,0.24)
		for opponent:ball in candidates:
			var offset:Vector2 = opponent.global_position - origin
			var projection:float = offset.dot(aim)
			var half_width:float = 5.0 + opponent.get_crowd_separation_radius_world()
			if projection < 0.0 or projection > origin.distance_to(endpoint) or absf(offset.cross(aim)) > half_width:
				continue
			if deal(opponent,1.5 if piercing else 1.0) and not piercing:
				break
	finish_action(generation)
func Skill() -> void:
	if not is_multiplayer_authority() or not is_combat_runtime_active() or is_damage_output_disabled():
		return
	var generation:int = begin_action(true)
	effect(0,global_position,global_position,75.0,0.24)
	if await windup(0.24,generation):
		effect(1,global_position,global_position,75.0,0.3)
		for target:ball in enemies_near(global_position,75.0):
			if clear_line(target.global_position) and deal(target,0.6):
				target.apply_knockback((target.global_position-global_position).normalized(),55.0,350.0,0.0,0.0,{"source":self,"stop_on_character":true})
	finish_action(generation,true)

func skill_available() -> bool:
	return not enemies_near(global_position,75.0).is_empty()
