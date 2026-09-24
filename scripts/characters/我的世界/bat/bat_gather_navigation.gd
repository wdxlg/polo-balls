extends RefCounted
## Bounded, on-demand terrain routing. Never teleport an unreachable bat into a merge.
static func route(actor:Node2D,start:Vector2,goal:Vector2) -> Array[Vector2]:
	if clear(actor,start,goal): return [goal]
	var arena:Rect2 = actor.mc_arena_rect().grow(-maxf(6.0,clearance_radius(actor)))
	var area:Rect2 = Rect2(start,Vector2.ZERO).expand(goal).grow(72.0).intersection(arena)
	var cell:float = 12.0
	if area.size.x*area.size.y/(cell*cell) > 4096.0: cell = 20.0
	var count := Vector2i(maxi(1,int(ceil(area.size.x/cell))),maxi(1,int(ceil(area.size.y/cell))))
	if count.x*count.y > 8192: return []
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO,count)
	grid.cell_size = Vector2(cell,cell)
	grid.offset = area.position+Vector2.ONE*cell*0.5
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for y:int in range(count.y):
		for x:int in range(count.x):
			var id := Vector2i(x,y)
			grid.set_point_solid(id,not actor.mc_position_clear(grid.get_point_position(id),clearance_radius(actor)))
	var from:Vector2i = Vector2i(((start-grid.offset)/cell).round()).clamp(Vector2i.ZERO,count-Vector2i.ONE)
	var to:Vector2i = Vector2i(((goal-grid.offset)/cell).round()).clamp(Vector2i.ZERO,count-Vector2i.ONE)
	# Endpoints are known safe actual actor/merge positions. Grid centers may be offset.
	grid.set_point_solid(from,false)
	grid.set_point_solid(to,false)
	var points:PackedVector2Array = grid.get_point_path(from,to)
	if points.is_empty(): return []
	var result:Array[Vector2] = []
	for i:int in range(1,points.size()): result.append(points[i])
	result.append(goal)
	return result

static func clear(actor:Node2D,start:Vector2,goal:Vector2) -> bool:
	# A center ray misses corners that the bat's body still hits. Sweep a clearance capsule.
	var shape := CapsuleShape2D.new()
	shape.radius = clearance_radius(actor)
	shape.height = start.distance_to(goal)+shape.radius*2.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D((goal-start).angle()-PI*0.5,(start+goal)*0.5)
	query.collision_mask = 1
	query.exclude = [actor.get_rid()]
	return actor.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty()

static func clearance_radius(actor:Node2D) -> float:
	var body:CollisionShape2D = actor.collision_shape_2d
	if body != null and body.shape is RectangleShape2D:
		return ((body.shape as RectangleShape2D).size*body.global_scale.abs()*0.5).length()+0.3
	return 4.5
