extends RefCounted
## Shared geometry/target helpers, not a replacement for the project's damage system.
static func enemy(source:ball,target:Variant,neutral:bool = false) -> bool:
	if not is_instance_valid(target) or not target is ball or target == source: return false
	if not target.is_combat_targetable(): return false
	if target.has_method(&"is_guarded_from_friendly_copy") and target.call(&"is_guarded_from_friendly_copy",source): return false # Haochen copies never pick his side (task 10)
	if neutral: return true
	return Game.Game_Settings.Have_Team_Damage or source.Team.is_empty() or source.Team != target.Team
static func nearest(source:ball) -> ball:
	var result:ball
	var best:float = INF
	for target:Node in source.get_tree().get_nodes_in_group("Ball"):
		if not enemy(source,target) or not target.is_combat_lockable(): continue
		# Tall / multi-part bodies (grown cactus) measure to their part nearest to the source.
		var d:float = source.global_position.distance_squared_to(target.call(&"combat_distance_point_for",source) if target.has_method(&"combat_distance_point_for") else target.global_position)
		if d < best:
			best=d
			result=target
	return result
## Point of a target's body nearest to a world point: its position for ordinary units, the nearest
## point of the stack for tall multi-part bodies (grown cactus). Use with radius() for circle checks.
static func point(target:Node2D,from:Vector2) -> Vector2:
	if is_instance_valid(target) and target.has_method(&"combat_body_point"): return target.call(&"combat_body_point",from)
	return target.global_position if is_instance_valid(target) else from
static func radius(target:ball) -> float:
	return maxf(target.get_crowd_separation_radius_world(),3.0)
static func wall_node(node:Node) -> bool:
	while is_instance_valid(node):
		if node is TileMapLayer or bool(node.get_meta("map_safety_frame",false)) or bool(node.get_meta("mc_wall",false)): return true
		if node.has_method("is_builder_wall") and node.is_builder_wall(): return true
		if str(node.name).to_lower().contains("wall") or str(node.name).contains("墙"): return true
		node=node.get_parent()
	return false
static func boundary_hit(source:Node2D,hit:Dictionary) -> bool:
	var node:Node = hit.get("collider")
	while is_instance_valid(node):
		if bool(node.get_meta("mc_map_boundary",false)) or bool(node.get_meta("map_safety_frame",false)): return true
		node=node.get_parent()
	var world:Node=source.get_tree().current_scene
	if not wall_node(hit.get("collider")) or not world.has_method("map_island_rects"): return false
	var map:Node = world.call("_current_map_node")
	if map == null: return false
	for rect:Rect2 in world.map_island_rects(map):
		if rect.grow(-1.5).has_point(hit.position): return false
	return true
static func trace(source:Node2D,a:Vector2,b:Vector2,pass_boundary:bool = false,pass_walls:bool = false) -> Dictionary:
	if a.distance_squared_to(b)<0.000001: return {}
	var exclusions:Array[RID]=[]
	if source is CollisionObject2D: exclusions.append(source.get_rid())
	var direction:Vector2=(b-a).normalized()
	var cursor:Vector2=a
	# Never exclude a whole TileMap RID just to bypass its outer border: the
	# same body may contain an internal wall. Walk through only allowed shapes.
	for i:int in range(2048):
		if (b-cursor).dot(direction)<=0.0001: return {}
		var query:=PhysicsRayQueryParameters2D.create(cursor,b,1,exclusions)
		query.collide_with_areas=false
		query.hit_from_inside=true
		var hit:Dictionary=source.get_world_2d().direct_space_state.intersect_ray(query)
		if hit.is_empty(): return {}
		if pass_walls and wall_node(hit.collider):
			exclusions.append(hit.rid)
			continue
		if pass_boundary and boundary_hit(source,hit):
			cursor=hit.position+direction*0.5
			continue
		return hit
	return {"position":cursor}

static func line_clear(source:Node2D,a:Vector2,b:Vector2) -> bool: return trace(source,a,b).is_empty()
static func segment_distance(point:Vector2,a:Vector2,b:Vector2) -> float:
	return point.distance_to(Geometry2D.get_closest_point_to_segment(point,a,b))
static func slow(source:ball,target:ball,ratio:float,duration:float,key:String) -> void:
	if not is_instance_valid(target) or not target.can_receive_negative_effects() or not target.can_receive_control_from(source): return
	var buff:=Buff.new(2,duration,Buff.Buff_types.Speed,clampf(ratio,0.05,1.0),Buff.Algorithms.mul)
	var world:Node=source.get_tree().current_scene
	if world.has_method("new_buff"): world.new_buff(target,source,key,buff)
	else:
		var id:int=source.get_instance_id()
		if not target.Buff_Dic.has(id): target.Buff_Dic[id]={}
		target.Buff_Dic[id][key]=buff
static func damage(source:ball,target:ball,amount:float,point:Vector2,neutral:bool = false) -> bool:
	if not enemy(source,target,neutral) or amount<=0 or source.is_damage_output_disabled(): return false
	return target.receive_positional_damage(amount,point,false,source)
static func line(parent:Node,name:String,width:float,color:Color) -> Line2D:
	var result:=Line2D.new()
	result.name=name
	result.width=width
	result.default_color=color
	result.top_level=true
	result.z_index=85
	result.z_as_relative=false
	parent.add_child(result)
	return result
