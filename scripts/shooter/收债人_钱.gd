extends Node2D

const MONEY_TEXTURE_PATH:String = "res://Images/characters/人物/收债人/收债人_一沓钱.png"

# 收债人的“钱”不是普通伤害子弹：
# 它只负责命中判定，然后把事件交回收债人。
# 不走 hitbox/take_damage，因此 Block、Damage_reduction、反弹/格挡 Area 等
# 不会吞掉这次债务命中。

var travel_direction:Vector2 = Vector2.RIGHT
var projectile_speed:float = 270.0
var max_lifetime:float = 1.20
var hit_radius:float = 7.0
var collector:Node = null
var collector_team:String = ""
var authoritative_logic:bool = false
var _elapsed:float = 0.0
var _money_sprite:Sprite2D = null


func setup(owner_node:Node,start_position:Vector2,direction_value:Vector2,speed_value:float,lifetime_value:float,team_value:String,is_authority:bool) -> void:
	add_to_group("AllayExtendedProjectile")
	add_to_group("BattleTransient")
	collector = owner_node
	global_position = start_position
	travel_direction = direction_value.normalized() if direction_value.length_squared() > 0.000001 else Vector2.RIGHT
	projectile_speed = maxf(speed_value,1.0)
	max_lifetime = maxf(lifetime_value,0.1)
	collector_team = team_value
	authoritative_logic = is_authority
	rotation = travel_direction.angle()
	z_as_relative = false
	z_index = 80
	_create_money_visual()
	queue_redraw()


func _physics_process(delta:float) -> void:
	_elapsed += delta
	var from_pos:Vector2 = global_position
	var to_pos:Vector2 = from_pos + travel_direction * projectile_speed * delta
	if get_tree().has_group("MinecraftAllay") and load("res://scripts/characters/我的世界/allay/capture.gd").sweep(self,from_pos,to_pos): return
	var terrain_hit:Dictionary = _terrain_hit(from_pos,to_pos)
	if not terrain_hit.is_empty():
		to_pos = terrain_hit.get("position",to_pos)
	global_position = to_pos

	var target:ball = _find_first_enemy_hit(from_pos,to_pos)
	if target != null:
		if target.has_method("try_block_projectile_hit") and bool(target.call("try_block_projectile_hit",self,global_position,0.0)):
			queue_free()
			return
		if authoritative_logic and collector != null and is_instance_valid(collector) and collector.has_method("_on_money_projectile_hit"):
			collector.call("_on_money_projectile_hit",target)
		queue_free()
		return

	if not terrain_hit.is_empty():
		queue_free()
		return

	if _elapsed >= max_lifetime:
		queue_free()


func _terrain_hit(from_pos:Vector2,to_pos:Vector2) -> Dictionary:
	var world_2d := get_world_2d()
	if world_2d == null:
		return {}
	var query := PhysicsRayQueryParameters2D.create(from_pos,to_pos,1)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return world_2d.direct_space_state.intersect_ray(query)


func _find_first_enemy_hit(from_pos:Vector2,to_pos:Vector2) -> ball:
	var best:ball = null
	var best_t:float = INF
	for raw_candidate in get_tree().get_nodes_in_group("Ball"):
		if not (raw_candidate is ball):
			continue
		var candidate:ball = raw_candidate as ball
		if candidate == collector or candidate.Type != ball.Ball_Type.Ball or candidate.health <= 0:
			continue
		if collector_team != "" and candidate.Team != "" and collector_team == candidate.Team:
			continue

		var t:float = _segment_parameter(candidate.global_position,from_pos,to_pos)
		var closest:Vector2 = from_pos.lerp(to_pos,t)
		var target_radius:float = _estimate_target_radius(candidate)
		if candidate.global_position.distance_to(closest) <= hit_radius + target_radius and t < best_t:
			if candidate.has_method("try_full_projectile_dodge") and bool(candidate.call("try_full_projectile_dodge",self)): continue
			best_t = t
			best = candidate
	return best


func _segment_parameter(point:Vector2,a:Vector2,b:Vector2) -> float:
	var ab:Vector2 = b - a
	var len_sq:float = ab.length_squared()
	if len_sq <= 0.000001:
		return 0.0
	return clampf((point - a).dot(ab) / len_sq,0.0,1.0)


func _estimate_target_radius(target:ball) -> float:
	var visual_size:Vector2 = target.rect_size
	var scale_value:float = maxf(absf(target.scale.x),absf(target.scale.y))
	var estimate:float = maxf(visual_size.x,visual_size.y) * 0.5 * maxf(scale_value,0.01)
	return clampf(estimate,6.0,16.0)


func _create_money_visual() -> void:
	if _money_sprite != null and is_instance_valid(_money_sprite):
		return
	if not ResourceLoader.exists(MONEY_TEXTURE_PATH):
		return
	var resource:Resource = ResourceLoader.load(MONEY_TEXTURE_PATH)
	if not (resource is Texture2D):
		return

	var texture := resource as Texture2D
	var sprite := Sprite2D.new()
	sprite.name = "MoneyImage"
	sprite.texture = texture
	sprite.centered = true
	# 原图是完整透明 PNG 画布。把最长边缩到约 22px，作为小型投射物。
	var size:Vector2 = texture.get_size()
	var longest:float = maxf(size.x,size.y)
	if longest > 0.0:
		var visual_scale:float = 22.0 / longest
		sprite.scale = Vector2.ONE * visual_scale
	add_child(sprite)
	_money_sprite = sprite


func _draw() -> void:
	# 美术资源缺失时保留旧版简易钞票作为兜底。
	if _money_sprite != null and is_instance_valid(_money_sprite):
		return
	var body_rect := Rect2(Vector2(-7.5,-4.5),Vector2(15.0,9.0))
	draw_rect(body_rect,Color(0.20,0.88,0.42,0.96),true)
	draw_rect(body_rect,Color(0.05,0.28,0.12,1.0),false,1.0,true)
	draw_circle(Vector2.ZERO,2.3,Color(0.82,1.0,0.66,0.92))
	var ink := Color(0.04,0.30,0.11,1.0)
	draw_line(Vector2(-2.0,-2.3),Vector2(0.0,0.0),ink,0.9,true)
	draw_line(Vector2(2.0,-2.3),Vector2(0.0,0.0),ink,0.9,true)
	draw_line(Vector2(0.0,-0.1),Vector2(0.0,2.7),ink,0.9,true)
	draw_line(Vector2(-2.1,0.5),Vector2(2.1,0.5),ink,0.8,true)
	draw_line(Vector2(-2.1,1.6),Vector2(2.1,1.6),ink,0.8,true)
