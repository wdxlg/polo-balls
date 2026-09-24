extends RefCounted
const PROJECTILE_CONTACT = preload("res://scripts/projectile_contact.gd")
# 天堂弓专用：人物接触和地形反射分离，不改变其他角色共用的 U.trace。
const U = preload("res://scripts/characters/我的世界/new5/utils.gd")


static func terrain(source: Node2D, start: Vector2, finish: Vector2) -> Dictionary:
	return _trace(source, null, start, finish, false)


static func projectile(source: Node2D, owner: ball, start: Vector2, finish: Vector2, extra_exclusions: Array[RID] = []) -> Dictionary:
	return _trace(source, owner, start, finish, true, extra_exclusions)


static func _character(node: Node) -> ball:
	var cursor: Node = node
	while is_instance_valid(cursor):
		if cursor is ball:
			return cursor as ball
		cursor = cursor.get_parent()
	return null


static func _pure_terrain_actor(actor: ball) -> bool:
	# 兼容历史角色型障碍。当前石头是独立 StaticBody2D，直接走普通地形分支。
	# 不只看地形层或“障碍”标签，避免把友军、尸体或烈焰人误当成墙。
	return ((actor.collision_layer & 1) != 0
		and actor.Type_Tags.has("固定")
		and actor.Type_Tags.has("障碍")
		and bool(actor.get_meta(&"ignore_combat_targeting", false)))


static func _trace(source: Node2D, owner: ball, start: Vector2, finish: Vector2, hit_characters: bool, extra_exclusions: Array[RID] = []) -> Dictionary:
	if start.distance_squared_to(finish) < 0.000001:
		return {}
	# 正在穿越的障碍物只对这个箭排除；其他调用者保持默认空列表。
	var exclusions: Array[RID] = extra_exclusions.duplicate()
	if source is CollisionObject2D:
		exclusions.append(source.get_rid())
	if is_instance_valid(owner):
		exclusions.append(owner.get_rid())
	var query := PhysicsRayQueryParameters2D.create(start, finish, 3 if hit_characters else 1)
	query.collide_with_areas = hit_characters
	query.hit_from_inside = true
	var space: PhysicsDirectSpaceState2D = source.get_world_2d().direct_space_state
	for _attempt in range(2048):
		query.exclude = exclusions
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return {}
		var collider: Node = hit.get("collider") as Node
		var actor: ball = _character(collider)
		if actor != null:
			if PROJECTILE_CONTACT.ignores(actor):
				pass # Neither an enemy impact nor terrain; keep tracing beyond every child collider.
			elif _pure_terrain_actor(actor):
				# 只认实体碰撞，不把同一对象的 hurtbox 算成第二个障碍物。
				if collider is PhysicsBody2D and (collider.collision_layer & 1) != 0:
					return hit
			elif hit_characters and is_instance_valid(owner) and U.enemy(owner, actor):
				hit["victim"] = actor
				return hit
			# 普通人物子碰撞体/受击框、友军、尸体，以及误占地形层的人物仍被排除。
		elif not collider is Area2D and not collider is CharacterBody2D:
			if not collider is CollisionObject2D or (collider.collision_layer & 1) != 0:
				return hit
		var rid: RID = hit.get("rid", RID())
		if not rid.is_valid() or exclusions.has(rid):
			return {}
		exclusions.append(rid)
	# 超出防护上限时不能伪造墙面法线，否则仍会出现无故反弹。
	return {}
