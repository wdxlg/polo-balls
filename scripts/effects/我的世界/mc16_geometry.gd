extends RefCounted
# Shared world-space collision helpers. No center-point-only hit tests.
static func same_team(a:Node,b:Node) -> bool:
	return a == b or (not str(a.Team).is_empty() and str(a.Team)==str(b.Team))
static func enemy(caster:Node,target:Variant) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(caster,target): return false # 皓宸复制品及其产物不把己方选为目标
	return is_instance_valid(target) and target is ball and not same_team(caster,target) and caster.mc_enemy(target)
static func radius(unit:Node2D) -> float:
	return maxf(float(unit.get_crowd_separation_radius_world()),3.0)
static func segment_distance(a:Vector2,b:Vector2,p:Vector2) -> float:
	return Geometry2D.get_closest_point_to_segment(p,a,b).distance_to(p)
static func touching(a:Vector2,b:Vector2,p:Vector2,previous:Vector2,r:float) -> bool:
	if segment_distance(a,b,p)<=r or segment_distance(a,b,previous)<=r: return true
	if segment_distance(previous,p,a)<=r or segment_distance(previous,p,b)<=r: return true
	return Geometry2D.segment_intersects_segment(a,b,previous,p)!=null
static func crossing(a:Vector2,b:Vector2,c:Vector2,d:Vector2,margin:float = 4.0) -> Variant:
	var point:Variant = Geometry2D.segment_intersects_segment(a,b,c,d)
	if point == null: return null # Parallel/collinear overlap is not an X junction.
	for end:Vector2 in [a,b,c,d]:
		if end.distance_to(point)<=margin: return null # Shared wall endpoints excluded.
	return point
static func sweep_circle(a:Vector2,b:Vector2,center:Vector2,r:float) -> float:
	var v:Vector2 = b-a
	var offset:Vector2 = a-center
	if offset.length_squared()<=r*r: return 0.0
	var length_sq:float = v.length_squared()
	if length_sq<0.000001: return INF
	var linear:float = offset.dot(v)
	var discriminant:float = linear*linear-length_sq*(offset.length_squared()-r*r)
	if discriminant<0.0: return INF
	var t:float = (-linear-sqrt(discriminant))/length_sq
	return t if t>=0.0 and t<=1.0 else INF
static func wall_ray(unit:Node2D,a:Vector2,b:Vector2,exclude:Array[RID] = []) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(a,b,1,exclude)
	query.collide_with_areas = false
	return unit.get_world_2d().direct_space_state.intersect_ray(query)
